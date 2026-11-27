#!/usr/bin/env bash
# Controlli delle sentinelle dei tracciati (issue #43).
#  0. run.sh, check.sh e deps esistono e sono eseguibili; le sentinelle, viste.tsv e il documento versionato esistono
#  1. verifica completa (glue/verifica.py, gruppi [sentinella] [sorgente] [coerenza] [valori] [unicita] [copertura]
#     [struttura] [decodifica] [ricodifica]) e rigenerazione del documento in una cartella temporanea: deve coincidere
#     con docs/legacy-map/data-contract/sentinelle.md
#  2. conteggi: contratti dei copybook in contratti.tsv, coppie contratto/vista, campi attesi per coppia e campi
#     elementari della vista nel contratto (la verifica li confronta per identita'; qui si stampano)
#  3. prove negative sulle copie private di contratti e sentinelle (glue/negativi.py): ognuna riportata con nome e
#     diagnosi; le mutazioni non applicabili sono elencate con il motivo e non contate come superate
#  4. prove negative su questo script e sulla generazione: documento alterato rilevato dal confronto; generazione
#     fallita con un documento buono rimasto da una corsa precedente: errore, e il residuo e' rimosso
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/data-sentinelle/lib.sh"
require_legacy

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

log "0. file dell'analisi"
for f in run.sh check.sh deps; do
  [ -f "$DSEN_DIR/$f" ] && [ -x "$DSEN_DIR/$f" ] || fail "analysis/data-sentinelle/$f assente o non eseguibile"
done
[ -f "$DSEN_DIR/viste.tsv" ] || fail "analysis/data-sentinelle/viste.tsv assente"
[ -d "$DSEN_DIR/sentinelle" ] || fail "analysis/data-sentinelle/sentinelle/ assente"
[ -f "$DSEN_DOC" ] || fail "docs/legacy-map/data-contract/sentinelle.md assente: eseguire './analysis/run.sh data-sentinelle'"
log "   ok: run.sh, check.sh, deps presenti ed eseguibili; sentinelle, viste.tsv e documento presenti"

log "1. verifica completa e rigenerazione del documento"
dsen_genera "$tmp/gen"
if ! diff "$tmp/gen/sentinelle.md" "$DSEN_DOC" > "$tmp/diff.txt" 2>&1; then
  head -30 "$tmp/diff.txt" >&2
  fail "sentinelle.md versionato diverso da quello rigenerato: rieseguire './analysis/run.sh data-sentinelle'"
fi
esito="$(tail -n 1 "$tmp/gen/verifica.txt")" || fail "esito della verifica illeggibile"
log "   ok: $esito; documento identico al versionato"

log "2. conteggi (contratti dei copybook in contratti.tsv; per coppia: campi attesi e campi della vista nel contratto)"
n_cb="$(awk -F'\t' 'NR > 1 && $3 == "copybook"' "$DSEN_DC/contratti.tsv" | wc -l | tr -d ' ')" || fail "conteggio dei contratti dei copybook fallito"
log "   contratti con righe=copybook in contratti.tsv: $n_cb"
# conteggi VERIFICA OUT: tabella dei conteggi dall'uscita della verifica; ritorna 1 se una coppia ha numeri diversi
conteggi() {
  awk -F'\t' '$1 == "contratto" { t = 1; next } t && NF == 5 { printf "   %-30s %-24s %-24s attesi %3s  contratto %3s%s\n", $1, $2, $3, $4, $5, ($4 == $5 ? "" : "  DIVERSI") }' \
    "$1" > "$2" || return 2
  [ -s "$2" ] || return 2
  if grep -q "DIVERSI" "$2"; then return 1; fi
  return 0
}
rc=0; conteggi "$tmp/gen/verifica.txt" "$tmp/conteggi.txt" || rc=$?
cat "$tmp/conteggi.txt" >&2 || fail "tabella dei conteggi illeggibile"
[ "$rc" -eq 0 ] || fail "conteggi: campi attesi e campi della vista nel contratto non coincidono, o tabella assente (uscita $rc)"
# prova negativa del confronto: un conteggio alterato deve essere rilevato
awk -F'\t' 'BEGIN { OFS = "\t" } NF == 5 && $1 == "COCOM01Y.CARDDEMO-COMMAREA" { $5 = $5 + 1 } { print }' \
  "$tmp/gen/verifica.txt" > "$tmp/verifica-alterata.txt" || fail "uscita alterata non scritta"
rc=0; conteggi "$tmp/verifica-alterata.txt" "$tmp/conteggi-alterati.txt" || rc=$?
[ "$rc" -eq 1 ] && grep -q "COCOM01Y.CARDDEMO-COMMAREA .*DIVERSI" "$tmp/conteggi-alterati.txt" \
  || fail "PROVA NEGATIVA FALLITA (conteggio-alterato): il confronto non rileva un conteggio diverso (uscita $rc)"
log "   ok: conteggio-alterato -> il confronto rileva COCOM01Y.CARDDEMO-COMMAREA con 16 attesi e 17 nel contratto"

log "3. prove negative su copie private di contratti, sentinelle ed elenchi"
rc=0; dsen_negativi "$tmp/neg.txt" || rc=$?
if [ "$rc" -ne 0 ]; then
  grep -A14 "^PROVA NEGATIVA FALLITA" "$tmp/neg.txt" >&2 || tail -40 "$tmp/neg.txt" >&2
  fail "prove negative non superate (uscita $rc)"
fi
ultima="$(tail -n 1 "$tmp/neg.txt")" || fail "esito delle prove negative illeggibile"
case "$ultima" in "prove negative: "*" superate, "*" non applicabili "*) ;; *) cat "$tmp/neg.txt" >&2; fail "prove negative senza esito riconoscibile" ;; esac
if grep -q "^PROVA NEGATIVA FALLITA" "$tmp/neg.txt"; then fail "una prova negativa e' fallita ma l'uscita e' 0"; fi
sed 's/^/   /' "$tmp/neg.txt" >&2 || fail "uscita delle prove negative illeggibile"

log "4. prove negative sulla generazione"
# 4a. documento versionato alterato: il confronto con il rigenerato deve trovarlo
cp "$DSEN_DOC" "$tmp/alterato.md" || fail "copia del documento fallita"
printf '\n- riga aggiunta da una prova negativa\n' >> "$tmp/alterato.md" || fail "alterazione del documento fallita"
if diff -q "$tmp/gen/sentinelle.md" "$tmp/alterato.md" > /dev/null 2>&1; then
  fail "PROVA NEGATIVA FALLITA (documento-alterato): nessuna differenza con il documento rigenerato"
fi
log "   ok: documento-alterato -> il confronto con la rigenerazione trova la differenza"
# 4b. residuo: un documento buono di una corsa precedente e una verifica che fallisce (un valore atteso alterato)
mkdir -p "$tmp/rotte" || fail "cartella delle sentinelle alterate non creata"
cp -R "$DSEN_DIR/sentinelle" "$tmp/rotte/sentinelle" || fail "copia delle sentinelle fallita"
f="$tmp/rotte/sentinelle/CVTRA03Y.TRAN-TYPE-RECORD/base.tsv"
grep -q '"PR"$' "$f" || fail "valore da alterare assente in $f"
sed 's/"PR"$/"PQ"/' "$f" > "$f.nuovo" && mv "$f.nuovo" "$f" || fail "alterazione della sentinella fallita"
grep -q '"PQ"$' "$f" || fail "alterazione della sentinella non applicata"
mkdir -p "$tmp/res" && cp "$tmp/gen/sentinelle.md" "$tmp/gen/verifica.txt" "$tmp/res/" || fail "residuo non preparato"
rc=0; ( dsen_genera "$tmp/res" "$tmp/rotte/sentinelle" ) > "$tmp/res.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "PROVA NEGATIVA FALLITA (residuo): la generazione con una sentinella alterata e' riuscita"
grep -qF 'ERRORE [decodifica] CVTRA03Y.TRAN-TYPE-RECORD@base/base #1 TRAN-TYPE: atteso testo "PQ", ottenuto testo "PR"' "$tmp/res.log" \
  || { cat "$tmp/res.log" >&2; fail "prova negativa (residuo): fallita ma non per il valore alterato"; }
[ ! -e "$tmp/res/sentinelle.md" ] || fail "PROVA NEGATIVA FALLITA (residuo): il documento della corsa precedente e' rimasto"
log "   ok: residuo -> generazione fallita (uscita $rc) sul valore alterato, documento della corsa precedente rimosso"
log "data-sentinelle: tutti i controlli superati"
