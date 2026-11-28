#!/usr/bin/env bash
# Controlli dei record per l'oracle (issue #53).
#  0. run.sh, check.sh, deps, controprova.sh esistono e sono eseguibili; tabella, attesi, out/ e documento esistono
#  1. rigenerazione completa in una cartella nuova (controllo 1, generazione, controlli 2, 4, 5 sui file scritti,
#     controllo 3 con controprova.sh); out/ e documento rigenerati identici ai versionati (diff: 0 / 1 / altro)
#  2. prove negative della colla (glue/negativi.py): ognuna con nome e diagnosi; censimento: ogni guardia (ogni
#     chiamata es.errore con codice letterale in oracle_dati.py) e' scattata in almeno una prova superata
#  3. prove negative della controprova (controllo 3): prodotto, controprova scritta a mano e file ASCII alterati, uno
#     per prova, ciascuna con il difetto atteso
#  4. esiti dei comandi di controprova.sh: ogni invocazione di ogni comando esterno, una alla volta, esce con 42 dopo
#     aver fatto il suo lavoro (e wc e od rispondono vuoto o malformato con esito 0): controprova.sh esce con 2;
#     limite di tempo: un comando che attende oltre il limite ferma la controprova
#  5. residui e generazione: uscite buone di una corsa precedente nella destinazione di odt_genera e una verifica (o
#     una controprova) che fallisce: errore e residuo rimosso; limite di tempo della colla
#  6. esiti degli script sull'host: glue_run, docker, tail, grep, diff, cp, rm, sed che falliscono
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/oracle-dati/lib.sh"
require_legacy

tmp="$(mktmp)" || fail "cartella temporanea non creata"
trap 'rm -rf "$tmp"' EXIT
NEG=0
ok_neg() { NEG=$((NEG + 1)); log "   prova negativa ok: $*"; }

# presenza MODELLO FILE: 0 se una riga corrisponde, 1 se nessuna, 2 se grep non ha potuto leggere (mai preso per assenza)
presenza() { local rc=0; grep -q -- "$1" "$2" || rc=$?; case "$rc" in 0|1) return "$rc" ;; *) return 2 ;; esac; }
# contiene TESTO FILE: come presenza, ma TESTO e' una stringa fissa (grep -F), non un'espressione regolare
contiene() { local rc=0; grep -qF -- "$1" "$2" || rc=$?; case "$rc" in 0|1) return "$rc" ;; *) return 2 ;; esac; }
# confronta A B DIFF: diff -r, 0 uguali, 1 diversi, altro errore operativo
confronta() { local rc=0; diff -r "$1" "$2" > "$3" 2>&1 || rc=$?; return "$rc"; }
# pretendi NOME CODICE-ATTESO SOTTOSTRINGA FILE-LOG: l'ultimo comando e' uscito con $rc; deve essere CODICE-ATTESO e il
# log deve contenere SOTTOSTRINGA ('-': funzione che non scrive nulla, conta solo il codice).
pretendi() {
  local nome="$1" atteso="$2" ago="$3" logf="$4" r
  [ "$rc" -eq "$atteso" ] || { sed 's/^/      | /' "$logf" >&2; fail "PROVA NEGATIVA FALLITA ($nome): uscita $rc invece di $atteso"; }
  if [ "$ago" = - ]; then ok_neg "$nome (uscita $rc)"; return 0; fi
  r=0; contiene "$ago" "$logf" || r=$?
  case "$r" in
    0) ;;
    1) sed 's/^/      | /' "$logf" >&2; fail "prova negativa ($nome): uscita $rc ma non per il motivo atteso ('$ago')" ;;
    *) fail "prova negativa ($nome): log illeggibile (grep $r)" ;;
  esac
  ok_neg "$nome (uscita $rc, motivo: '$ago')"
}

log "0. file dell'analisi"
for f in run.sh check.sh deps controprova.sh; do
  [ -f "$ODT_DIR/$f" ] && [ -x "$ODT_DIR/$f" ] || fail "analysis/oracle-dati/$f assente o non eseguibile"
done
[ -f "$ODT_DIR/tabella.tsv" ] && [ -d "$ODT_DIR/attesi" ] && [ -d "$ODT_DIR/out" ] || fail "tabella, attesi/ o out/ assenti"
[ -f "$ODT_DOC" ] || fail "docs/legacy-map/oracle-dati.md assente: eseguire './analysis/run.sh oracle-dati'"
log "   ok: script eseguibili; tabella, attesi, out/ e documento presenti"

log "1. rigenerazione completa e confronto con le uscite versionate"
odt_genera "$tmp/gen"
for coppia in "$tmp/gen/out:$ODT_DIR/out" "$tmp/gen/oracle-dati.md:$ODT_DOC"; do
  rc=0; confronta "${coppia%%:*}" "${coppia#*:}" "$tmp/diff.txt" || rc=$?
  case "$rc" in
    0) ;;
    1) head -30 "$tmp/diff.txt" >&2; fail "${coppia#*:} diverso dal rigenerato: rieseguire './analysis/run.sh oracle-dati'" ;;
    *) cat "$tmp/diff.txt" >&2; fail "confronto non eseguito (diff uscito con $rc)" ;;
  esac
done
sed 's/^/   /' "$tmp/gen/verifica.txt" "$tmp/gen/controprova.txt" >&2 || fail "uscite della generazione illeggibili"
log "   ok: controlli 1-5 superati; out/ e documento identici ai versionati"

log "2. prove negative della colla (copie private)"
rc=0; odt_negativi "$tmp/neg.txt" || rc=$?
if [ "$rc" -ne 0 ]; then
  rg=0; grep -A6 "^PROVA NEGATIVA FALLITA\|^ERRORE operativo\|^INVENTARIO" "$tmp/neg.txt" >&2 || rg=$?
  case "$rg" in 0) ;; 1) tail -40 "$tmp/neg.txt" >&2 || true ;; *) log "   uscita delle prove negative illeggibile (grep $rg)" ;; esac
  fail "prove negative della colla non superate (uscita $rc)"
fi
ultima="$(odt_ultima "$tmp/neg.txt" "prove negative: ")" || fail "esito delle prove negative illeggibile o assente"
case "$ultima" in "prove negative: "*" superate, ogni guardia coperta") ;; *) cat "$tmp/neg.txt" >&2; fail "prove negative senza esito riconoscibile" ;; esac
rc=0; presenza "^PROVA NEGATIVA FALLITA" "$tmp/neg.txt" || rc=$?
case "$rc" in
  1) ;;
  0) fail "una prova negativa della colla e' fallita ma l'uscita e' 0" ;;
  *) fail "uscita delle prove negative illeggibile (grep $rc)" ;;
esac
while IFS= read -r l; do
  case "$l" in "ok: "*) ok_neg "colla: ${l#ok: }" ;; *) log "   $l" ;; esac
done < "$tmp/neg.txt"

log "3. prove negative della controprova (controllo 3)"
PROD="$tmp/gen/out"
# copia_prod NOME: copia privata dei file prodotti in $tmp/NOME/prod
copia_prod() { rm -rf "$tmp/$1"; mkdir -p "$tmp/$1" && cp -R "$PROD" "$tmp/$1/prod" || fail "copia del prodotto per '$1' fallita"; }
# copia_cart NOME: copia privata della cartella dell'analisi (tabella, attesi) in $tmp/NOME/cart
copia_cart() { rm -rf "$tmp/$1"; mkdir -p "$tmp/$1/cart" && cp -R "$ODT_DIR/tabella.tsv" "$ODT_DIR/attesi" "$tmp/$1/cart/" \
  || fail "copia della cartella per '$1' fallita"; }
# scrivi_byte FILE POSIZIONE TESTO: sostituisce i byte da POSIZIONE (da 0) con TESTO, con le sole utility POSIX
scrivi_byte() {
  local f="$1" p="$2" s="$3" n
  n="$(wc -c < "$f")" || fail "dimensione di $f illeggibile"
  { head -c "$p" "$f" && printf '%s' "$s" && tail -c "+$((p + ${#s} + 1))" "$f"; } > "$f.nuovo" || fail "alterazione di $f fallita"
  cmp -s "$f" "$f.nuovo" && fail "alterazione di $f senza effetto"
  mv "$f.nuovo" "$f" || fail "sostituzione di $f fallita"
  [ "$(wc -c < "$f")" -eq "$n" ] || fail "alterazione di $f: dimensione cambiata"
}
# sostituisci_testo FILE VECCHIO NUOVO: una sola occorrenza di una riga intera o di un pezzo, con awk (verificata)
sostituisci_testo() {
  local f="$1"
  V="$2" N="$3" awk 'BEGIN { v = ENVIRON["V"]; n = ENVIRON["N"] } !fatto && (i = index($0, v)) { $0 = substr($0, 1, i - 1) n substr($0, i + length(v)); fatto = 1 } { print }' \
    "$f" > "$f.nuovo" || fail "sostituzione in $f fallita"
  cmp -s "$f" "$f.nuovo" && fail "sostituzione in $f senza effetto: '$2'"
  mv "$f.nuovo" "$f" || fail "sostituzione di $f fallita"
}
cpr() { # cpr NOME SOTTOSTRINGA PRODOTTO CARTELLA [opzioni docker]: la controprova deve fallire con 1 e quel difetto
  local nome="$1" ago="$2" prod="$3" cart="$4"
  shift 4
  rc=0; odt_controprova "$prod" "$cart" "$@" > "$tmp/$nome.log" 2>&1 || rc=$?
  pretendi "controprova: $nome" 1 "$ago" "$tmp/$nome.log"
}
R49=$((48 * 300 + 102))
copia_prod zip; scrivi_byte "$tmp/zip/prod/ACCTFILE.rec" "$R49" "A000000000"
cpr zip-49-annullata "differenza attesa assente al byte 14503 (record 49, posizione 103)" "$tmp/zip/prod" "$ODT_DIR"
copia_prod filler; scrivi_byte "$tmp/filler/prod/ACCTFILE.rec" $((9 * 300 + 199)) "."
cpr seconda-differenza-filler "differenza non attesa al byte 2900 (record 10, posizione 200)" "$tmp/filler/prod" "$ODT_DIR"
copia_prod num; scrivi_byte "$tmp/num/prod/ACCTFILE.rec" $((19 * 300 + 20)) "9"
cpr seconda-differenza-numerica "differenza non attesa al byte 5721 (record 20, posizione 21)" "$tmp/num/prod" "$ODT_DIR"
copia_prod tronco; head -c 14999 "$PROD/ACCTFILE.rec" > "$tmp/tronco/prod/ACCTFILE.rec" || fail "troncamento fallito"
cpr prodotto-troncato "ACCTFILE.rec ha 14999 byte, attesi 50 record di 300" "$tmp/tronco/prod" "$ODT_DIR"
copia_prod scambio
{ head -c 2700 "$PROD/ACCTFILE.rec" && tail -c +3001 "$PROD/ACCTFILE.rec" | head -c 300 \
  && tail -c +2701 "$PROD/ACCTFILE.rec" | head -c 300 && tail -c +3301 "$PROD/ACCTFILE.rec"; } > "$tmp/scambio/prod/ACCTFILE.rec" \
  || fail "scambio dei record fallito"
cpr record-scambiati "differenza non attesa al byte 2711 (record 10, posizione 11)" "$tmp/scambio/prod" "$ODT_DIR"
copia_prod mancante; rm "$tmp/mancante/prod/ACCTFILE.rec" || fail "rimozione fallita"
cpr prodotto-assente "file prodotto assente: ACCTFILE.rec" "$tmp/mancante/prod" "$ODT_DIR"
H=attesi/ACCTFILE.controprova.tsv
copia_cart ha; sostituisci_testo "$tmp/ha/cart/$H" "	41 30 30 30" "	42 30 30 30"
cpr mano-ascii-sbagliato "record 49 ACCT-ADDR-ZIP: byte del file ASCII '41 30 30 30 30 30 30 30 30 30', scritti a mano '42 30" "$PROD" "$tmp/ha/cart"
copia_cart hp; sostituisci_testo "$tmp/hp/cart/$H" "	5A 45 52" "	5A 45 53"
cpr mano-prodotto-sbagliato "record 49 ACCT-ADDR-ZIP: byte del prodotto '5A 45 52 4F 41 50 52 20 20 20', scritti a mano '5A 45 53" "$PROD" "$tmp/hp/cart"
copia_cart hk; sostituisci_testo "$tmp/hk/cart/$H" "49	00000000049	" "49	00000000048	"
cpr mano-chiave-sbagliata "record 49: chiave del prodotto" "$PROD" "$tmp/hk/cart"
copia_cart hr; sostituisci_testo "$tmp/hr/cart/$H" "49	00000000049	ACCT-ADDR-ZIP	102	10	41 30 30 30 30 30 30 30 30 30	5A 45 52 4F 41 50 52 20 20 20" "# riga tolta"
cpr mano-riga-tolta "differenza non attesa al byte 14503 (record 49, posizione 103)" "$PROD" "$tmp/hr/cart"
copia_cart hs; sostituisci_testo "$tmp/hs/cart/$H" "	41 30 30 30 30 30 30 30 30 30	5A 45 52 4F 41 50 52 20 20 20" \
  "	41 30 30 30 30 30 30 30 30 30	5A 30 30 30 30 30 30 30 30 30"
cpr mano-differenza-ridotta "differenza non attesa al byte 14504 (record 49, posizione 104)" "$PROD" "$tmp/hs/cart"
copia_cart hl; sostituisci_testo "$tmp/hl/cart/$H" "ACCT-ADDR-ZIP	102	10	" "ACCT-ADDR-ZIP	102	9	"
cpr mano-lunghezza "record 49 ACCT-ADDR-ZIP: 10 e 10 byte scritti, lunghezza 9" "$PROD" "$tmp/hl/cart"
copia_cart hi; sostituisci_testo "$tmp/hi/cart/$H" "record	chiave	campo" "record	key	campo"
cpr mano-intestazione "ACCTFILE.controprova.tsv malformato (codice 3" "$PROD" "$tmp/hi/cart"
copia_cart hx; rm "$tmp/hx/cart/$H" || fail "rimozione fallita"
cpr mano-assente "controprova scritta a mano assente" "$PROD" "$tmp/hx/cart"
# File ASCII alterato (copia montata sopra il file del volume): stessa dimensione, una riga di 299 byte e una di 301.
A="$tmp/acctdata.txt"
docker run --rm --network none --user "$(id -u):$(id -g)" -v "$LEGACY_VOL:/legvol:ro" -v "$tmp:/t" "$GLUE_IMAGE" \
  timeout 60 cp /legvol/app/data/ASCII/acctdata.txt /t/acctdata.txt < /dev/null || fail "copia del file ASCII fallita"
cp "$A" "$A.righe" && scrivi_byte "$A.righe" $((4 * 301 + 299)) $'\n' && scrivi_byte "$A.righe" $((4 * 301 + 300)) " " \
  || fail "file ASCII con righe spostate non preparato"
cpr ascii-righe-di-299-e-301 "non e' fatto di 50 righe di 300 byte chiuse da LF" "$PROD" "$ODT_DIR" \
  -v "$A.righe:/legvol/app/data/ASCII/acctdata.txt:ro"
head -c 15049 "$A" > "$A.senza-lf" || fail "file ASCII senza ultimo LF non preparato"
cpr ascii-senza-ultimo-lf "acctdata.txt ha 15049 byte, non n righe di 300 byte piu' LF" "$PROD" "$ODT_DIR" \
  -v "$A.senza-lf:/legvol/app/data/ASCII/acctdata.txt:ro"
cp "$A" "$A.cr" && scrivi_byte "$A.cr" $((6 * 301 + 299)) $'\r' || fail "file ASCII con CR non preparato"
cpr ascii-cr-in-una-riga "differenza non attesa al byte 2100 (record 7, posizione 300)" "$PROD" "$ODT_DIR" \
  -v "$A.cr:/legvol/app/data/ASCII/acctdata.txt:ro"
# Tabella senza alcuna controprova: errore operativo (2), non un successo vuoto.
copia_cart tn; sostituisci_testo "$tmp/tn/cart/tabella.tsv" "	app/data/ASCII/acctdata.txt	" "	-	"
rc=0; odt_controprova "$PROD" "$tmp/tn/cart" > "$tmp/tn.log" 2>&1 || rc=$?
pretendi "controprova: tabella-senza-controprova" 2 "nessuna riga della tabella ha una controprova" "$tmp/tn.log"
# Controprova: con i file versionati e con quelli rigenerati riesce (controprova di riferimento per le prove sopra).
rc=0; odt_controprova "$ODT_DIR/out" "$ODT_DIR" > "$tmp/cpr-versionati.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { cat "$tmp/cpr-versionati.log" >&2; fail "controprova sui file versionati fallita (uscita $rc)"; }
log "   controprova ok: la controprova sui file versionati riesce ($(tail -n 1 "$tmp/cpr-versionati.log"))"

log "4. esiti dei comandi di controprova.sh (involucro davanti nel PATH, nel container)"
WRAP="$tmp/wrap"; REG="$tmp/reg"; mkdir -p "$WRAP" "$REG" || fail "cartelle dell'involucro non create"
cp "$ODT_DIR/prove/involucro.sh" "$tmp/involucro.sh" || fail "copia dell'involucro fallita"
c_tmp="$(odt_cartella_c "$tmp")" || fail "percorso dei temporanei fuori da analysis/"
COMANDI="awk tr cmp od wc mktemp rm"
for c in $COMANDI; do
  printf '#!/bin/sh\nexec sh \047%s/involucro.sh\047 /reg/registro %s "${ODT_MODO_%s:-passa}" /usr/bin/%s "$@"\n' "$c_tmp" "$c" "$c" "$c" \
    > "$WRAP/$c" || fail "involucro di $c non scritto"
  chmod +x "$WRAP/$c" || fail "involucro di $c non eseguibile"
done
# involucri MODI...: controprova.sh con gli involucri davanti nel PATH, registro nuovo; uscita in $tmp/inv.log
involucri() {
  local m e=()
  rm -f "$REG/registro" || fail "registro precedente non rimosso"
  [ ! -e "$REG/registro" ] || fail "registro precedente ancora presente"
  for m in "$@"; do e+=(-e "$m"); done
  rc=0; odt_controprova "$PROD" "$ODT_DIR" -v "$REG:/reg" -e "PATH=$c_tmp/wrap:/usr/local/bin:/usr/bin:/bin" \
    ${e[@]+"${e[@]}"} > "$tmp/inv.log" 2>&1 || rc=$?
}
involucri
[ "$rc" -eq 0 ] || { cat "$tmp/inv.log" >&2; fail "controprova con gli involucri in modo passa fallita (uscita $rc)"; }
cp "$REG/registro" "$tmp/registro-passa" || fail "registro di riferimento non copiato"
log "   controprova ok: involucri in modo passa, controprova riuscita; invocazioni registrate:$(awk '{ n[$1]++ } END { for (c in n) printf " %s=%d", c, n[c] }' "$tmp/registro-passa")"
for c in $COMANDI; do
  tot="$(awk -v c="$c" '$1 == c' "$tmp/registro-passa" | wc -l | tr -d ' ')" || fail "registro illeggibile"
  [ "$tot" -gt 0 ] || fail "il comando $c non e' mai invocato da controprova.sh: elenco COMANDI da rivedere"
  i=1
  while [ "$i" -le "$tot" ]; do
    involucri "ODT_MODO_$c=42@$i"
    # raggiunto con il suo esito reale normale (0; per cmp 1, perche' i file differiscono nei 10 byte attesi)
    r=0; presenza "^$c $i [01] 42\$" "$REG/registro" || r=$?
    [ "$r" -eq 0 ] || { cat "$tmp/inv.log" "$REG/registro" >&2; fail "prova $c@$i: il comando non e' stato raggiunto con esito reale 0 o 1 (grep $r)"; }
    pretendi "controprova.sh: $c, invocazione $i di $tot, esce con 42 dopo il suo lavoro" 2 "ERRORE operativo" "$tmp/inv.log"
    i=$((i + 1))
  done
done
for c in wc od; do
  tot="$(awk -v c="$c" '$1 == c' "$tmp/registro-passa" | wc -l | tr -d ' ')" || fail "registro illeggibile"
  i=1
  while [ "$i" -le "$tot" ]; do
    for m in vuoto rumore; do
      involucri "ODT_MODO_$c=$m@$i"
      pretendi "controprova.sh: $c, invocazione $i di $tot, risposta $m con esito 0" 2 "ERRORE operativo" "$tmp/inv.log"
    done
    i=$((i + 1))
  done
done
# Limite di tempo: cmp attende 30 s, il limite e' ridotto a 3 s; timeout ferma controprova.sh (124).
rm -f "$REG/registro"
rc=0; ODT_TIMEOUT_CONTROPROVA=3 odt_controprova "$PROD" "$ODT_DIR" -v "$REG:/reg" \
  -e "PATH=$c_tmp/wrap:/usr/local/bin:/usr/bin:/bin" -e "ODT_MODO_cmp=attesa@1" > "$tmp/attesa.log" 2>&1 || rc=$?
[ "$rc" -eq 124 ] || { cat "$tmp/attesa.log" >&2; fail "PROVA NEGATIVA FALLITA (limite di tempo della controprova): uscita $rc invece di 124"; }
ok_neg "controprova.sh: cmp che attende 30 s con il limite a 3 s -> fermata da timeout (uscita 124)"

log "5. residui e generazione"
# residuo: uscite buone di una corsa precedente NELLA DESTINAZIONE di odt_genera, poi una generazione che fallisce
# (un atteso a mano alterato in una copia privata): errore e residuo rimosso.
res() { # res NOME CODICE-NEL-LOG CARTELLA [LIMITE]
  local nome="$1" ago="$2" cart="$3" lim="${4:-}"
  rm -rf "$tmp/$nome"; mkdir -p "$tmp/$nome" || fail "destinazione di '$nome' non creata"
  cp -R "$tmp/gen/out" "$tmp/gen/oracle-dati.md" "$tmp/gen/verifica.txt" "$tmp/gen/controprova.txt" "$tmp/$nome/" \
    || fail "residuo di '$nome' non preparato"
  [ -s "$tmp/$nome/out/ACCTFILE.rec" ] && [ -s "$tmp/$nome/oracle-dati.md" ] || fail "residuo di '$nome' non preparato"
  rc=0; ( odt_genera "$tmp/$nome" "$cart" "$lim" ) > "$tmp/$nome.log" 2>&1 || rc=$?
  pretendi "residuo: $nome" 1 "$ago" "$tmp/$nome.log"
  [ ! -e "$tmp/$nome/out" ] && [ ! -e "$tmp/$nome/oracle-dati.md" ] \
    || fail "PROVA NEGATIVA FALLITA (residuo: $nome): le uscite della corsa precedente sono rimaste"
  log "   e le uscite della corsa precedente non ci sono piu'"
}
copia_cart r1; sostituisci_testo "$tmp/r1/cart/attesi/ACCTFILE.record.tsv" "30*7 38 34 33 30 7B" "30*7 38 34 34 30 7B"
res verifica-che-fallisce "ERRORE [A09] attesi: record 39 ACCT-CURR-BAL" "$tmp/r1/cart"
copia_cart r2; sostituisci_testo "$tmp/r2/cart/$H" "49	00000000049	" "49	00000000048	"
res controprova-che-fallisce "record 49: chiave del prodotto" "$tmp/r2/cart"
res limite-di-tempo-della-colla "ERRORE operativo: limite di 1e-06 s superato" "$ODT_DIR" 0.000001
rc=0; odt_negativi "$tmp/neg-limite.txt" 0.000001 || rc=$?
pretendi "limite di tempo delle prove negative della colla" 2 "ERRORE operativo: limite di 1e-06 s superato" "$tmp/neg-limite.txt"

log "6. esiti degli script sull'host"
# glue_run che esegue davvero la colla e poi esce con 42: odt_genera fallisce.
eval "glue_run_vero() $(declare -f glue_run | tail -n +2)" || fail "copia di glue_run non riuscita"
rc=0; ( glue_run() { glue_run_vero "$@"; return 42; }; odt_genera "$tmp/e1" ) > "$tmp/e1.log" 2>&1 || rc=$?
pretendi "glue_run (esegui.py) che esce con 42 dopo il suo lavoro" 1 "generazione o verifica dei record fallita (uscita 42)" "$tmp/e1.log"
[ ! -e "$tmp/e1/out" ] || fail "glue_run-42: uscite rimaste"
rc=0; ( docker() { command docker "$@"; local r=$?; [ "$r" -ne 0 ] || r=42; return "$r"; }
        glue_run() { glue_run_vero "$@"; }; odt_controprova "$PROD" "$ODT_DIR" ) > "$tmp/e2.log" 2>&1 || rc=$?
pretendi "docker (controprova) che esce con 42 dopo il suo lavoro" 42 "controprova riuscita" "$tmp/e2.log"
rc=0; ( odt_controprova() { command docker version > /dev/null 2>&1; echo "controprova riuscita: falso"; return 42; }
        odt_genera "$tmp/e3" ) > "$tmp/e3.log" 2>&1 || rc=$?
pretendi "odt_controprova che esce con 42 dopo aver stampato l'esito giusto" 1 "controprova con il file ASCII fallita (uscita 42)" "$tmp/e3.log"
[ ! -e "$tmp/e3/out" ] || fail "odt_controprova-42: uscite rimaste"
rc=0; ( tail() { command tail "$@"; return 7; }; odt_ultima "$tmp/gen/verifica.txt" "verifica riuscita: " ) > "$tmp/e4.log" 2>&1 || rc=$?
pretendi "tail che stampa il testo giusto ed esce con 7 (odt_ultima)" 2 - "$tmp/e4.log"
rc=0; ( grep() { return 2; }; presenza "^PROVA NEGATIVA FALLITA" "$tmp/neg.txt" ) > "$tmp/e5.log" 2>&1 || rc=$?
pretendi "grep che esce con 2 (presenza)" 2 - "$tmp/e5.log"
rc=0; ( diff() { command diff "$@"; return 2; }; confronta "$tmp/gen/out" "$ODT_DIR/out" "$tmp/e6.diff" ) > "$tmp/e6.log" 2>&1 || rc=$?
pretendi "diff che esce con 2 (confronta)" 2 - "$tmp/e6.log"
# run.sh con destinazioni private e un comando avvolto sull'host (PATH): cp, rm, sed.
HW="$tmp/hostwrap"; mkdir -p "$HW" || fail "cartella degli involucri sull'host non creata"
for c in cp rm sed; do
  vero="$(command -v "$c")" || fail "$c non trovato sull'host"
  printf '#!/bin/sh\nexec sh \047%s\047 \047%s\047 %s "${ODT_MODO_%s:-passa}" \047%s\047 "$@"\n' "$tmp/involucro.sh" "$tmp/reg-host" "$c" "$c" "$vero" \
    > "$HW/$c" || fail "involucro di $c non scritto"
  chmod +x "$HW/$c" || fail "involucro di $c non eseguibile"
done
rm -rf "$tmp/rs" "$tmp/reg-host" && mkdir -p "$tmp/rs" || fail "destinazione di run.sh non preparata"
rc=0; env PATH="$HW:$PATH" ODT_OUT_DIR="$tmp/rs/out" ODT_DOC_FILE="$tmp/rs/doc.md" bash "$ODT_DIR/run.sh" > "$tmp/rs.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { cat "$tmp/rs.log" >&2; fail "run.sh con gli involucri in modo passa fallito (uscita $rc)"; }
rc=0; confronta "$tmp/rs/out" "$ODT_DIR/out" "$tmp/rs.diff" || rc=$?
[ "$rc" -eq 0 ] && cmp -s "$tmp/rs/doc.md" "$ODT_DOC" || fail "run.sh con gli involucri in modo passa: uscite diverse dalle versionate"
# Invocazioni attese, nell'ordine: rm 1 (odt_genera, uscite precedenti), rm 2 (run.sh, out/ precedente), rm 3 (trap);
# cp 1 (out/), cp 2 (documento); sed 1 e 2 (stampa delle uscite di verifica e controprova).
conta="$(awk '{ n[$1]++ } END { printf "cp=%d rm=%d sed=%d", n["cp"], n["rm"], n["sed"] }' "$tmp/reg-host")" || fail "registro illeggibile"
[ "$conta" = "cp=2 rm=3 sed=2" ] || fail "run.sh: invocazioni sull'host diverse da quelle attese: $conta"
log "   controprova ok: run.sh con gli involucri in modo passa scrive uscite identiche alle versionate ($conta)"
for v in "rm=42@1|uscite precedenti in" "rm=42@2|out/ precedente non rimossa" \
         "cp=42@1|impossibile scrivere analysis/oracle-dati/out/" "cp=42@2|impossibile scrivere docs/legacy-map/oracle-dati.md" \
         "sed=42@1|uscita della verifica illeggibile" "sed=42@2|uscita della controprova illeggibile"; do
  m="${v%%|*}"; c="${m%%=*}"
  rm -rf "$tmp/rs" "$tmp/reg-host" && mkdir -p "$tmp/rs" || fail "destinazione di run.sh non preparata"
  rc=0; env PATH="$HW:$PATH" "ODT_MODO_$c=${m#*=}" ODT_OUT_DIR="$tmp/rs/out" ODT_DOC_FILE="$tmp/rs/doc.md" \
    bash "$ODT_DIR/run.sh" > "$tmp/rs.log" 2>&1 || rc=$?
  r=0; awk -v c="$c" -v n="${m#*@}" '$1 == c && $2 == n && $3 == 0 && $4 == 42 { t = 1 } END { exit !t }' "$tmp/reg-host" || r=$?
  [ "$r" -eq 0 ] || { cat "$tmp/rs.log" >&2; fail "run.sh, $m: il comando non e' stato raggiunto con esito reale 0"; }
  pretendi "run.sh: $c, invocazione ${m#*@}, esce con 42 dopo il suo lavoro" 1 "${v#*|}" "$tmp/rs.log"
done
log "oracle-dati: tutti i controlli superati, $NEG prove negative"
