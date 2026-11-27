#!/usr/bin/env bash
# Controlli delle regole di codifica (issue #23).
#  0. run.sh, check.sh e deps esistono e sono eseguibili; l'output versionato esiste
#  1. tutto l'output si rigenera da zero in una cartella temporanea (censimento dai contratti, pagina di codici dai
#     file EBCDIC, sonda CODECPRB ricompilata ed eseguita nell'ambiente dell'oracle) e coincide con quello versionato
#  2. verifica dell'output rigenerato (glue/verifica.py): struttura e copertura dei vettori, colla contro i vettori
#     nei due profili, osservazioni della sonda contro gli attesi del profilo oracle-gnucobol, documento, pagina
#  3. prove negative sulla colla (glue/negativi.py): ogni regola alterata deve far fallire il confronto
#  4. prove negative su vettori, censimento, documento e osservazioni alterati (glue/altera.py)
#  5. prove negative reali sulla sonda: compilata senza -fsign=EBCDIC, l'osservazione differisce dagli attesi;
#     compilazione fallita con un'osservazione buona rimasta da una corsa precedente: nessun residuo e' usato
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/data-codec/lib.sh"
require_legacy

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT
cont() { echo "/analysis/${1#"$ANALYSIS_ROOT"/}"; }   # percorso, nei container della colla, di un file sotto analysis/

log "0. file dell'analisi"
for f in run.sh check.sh deps; do
  [ -f "$DCOD_DIR/$f" ] && [ -x "$DCOD_DIR/$f" ] || fail "analysis/data-codec/$f assente o non eseguibile"
done
[ -d "$DCOD_DIR/out" ] || fail "analysis/data-codec/out assente: eseguire prima './analysis/run.sh data-codec'"
[ -f "$DCOD_DOC" ] || fail "docs/legacy-map/data-contract/codifica.md assente"
log "   ok: run.sh, check.sh, deps presenti ed eseguibili"

log "1. rigenerazione completa e confronto con l'output versionato"
dcod_genera "$tmp/gen"
diff -r "$tmp/gen" "$DCOD_DIR/out" > "$tmp/diff.txt" 2>&1 || { sed "s#$tmp#<tmp>#g" "$tmp/diff.txt" | head -30 >&2; fail "output versionato diverso da quello rigenerato: rieseguire './analysis/run.sh data-codec'"; }
log "   ok: censimento, pagina di codici e osservazioni della sonda ($(($(wc -l < "$tmp/gen/sonde/osservazioni.tsv") - 1))) identici ai versionati"

# verifica VETTORI OUT DOC [CODEC]: esegue glue/verifica.py; scrive l'uscita su stdout, ritorna il suo codice
verifica() {
  local extra=()
  [ $# -lt 4 ] || extra=("$(cont "$4")")
  glue_run --mount "$3:/v/codifica.md:ro" --mount "$ORACLE_DIR/cobc.opts:/v/cobc.opts:ro" -- \
    /analysis/data-codec/glue/verifica.py "$(cont "$1")" "$(cont "$2")" /v/codifica.md /v/cobc.opts ${extra[@]+"${extra[@]}"}
}

log "2. verifica dell'output rigenerato"
verifica "$DCOD_DIR/vettori" "$tmp/gen" "$DCOD_DOC" > "$tmp/v.txt" 2>&1 || { cat "$tmp/v.txt" >&2; fail "verifica fallita"; }
grep -q '^verifica riuscita: ' "$tmp/v.txt" || { cat "$tmp/v.txt" >&2; fail "verifica senza esito riconoscibile"; }
sed 's/^/   /' "$tmp/v.txt" >&2

log "3. prove negative sulla colla (regole alterate, vettori e attesi fermi)"
glue_run --mount "$DCOD_DOC:/v/codifica.md:ro" -- /analysis/data-codec/glue/negativi.py \
  /analysis/data-codec/vettori "$(cont "$tmp/gen/censimento.tsv")" /v/codifica.md > "$tmp/neg.txt" 2>&1 \
  || { grep -v '^ok: ' "$tmp/neg.txt" >&2; fail "prove negative sulla colla non superate"; }
grep -q '^prove negative sulla colla: .* superate' "$tmp/neg.txt" || { cat "$tmp/neg.txt" >&2; fail "prove negative sulla colla senza esito riconoscibile"; }
grep -v '^ok: \(ampiezza\|scala\)-' "$tmp/neg.txt" | sed 's/^/   /' >&2
log "   (piu' $(grep -c '^ok: \(ampiezza\|scala\)-' "$tmp/neg.txt") prove per variante: ampiezza aumentata di un byte, scala spostata di uno)"

log "4. prove negative su vettori, censimento, documento e osservazioni alterati"
# mondo NOME: copia di vettori, output rigenerato e documento in $tmp/m-NOME, poi l'alterazione
mondo() {
  local m="$tmp/m-$1"
  rm -rf "$m"; mkdir -p "$m"
  cp -R "$DCOD_DIR/vettori" "$m/vettori" && cp -R "$tmp/gen" "$m/out" && cp "$DCOD_DOC" "$m/codifica.md" || return 1
  glue_run --rw "$m" -- /analysis/data-codec/glue/altera.py "$1" /work > /dev/null || return 1
  echo "$m"
}
# negativa NOME "TESTO ATTESO": la verifica del mondo alterato deve uscire con 1 e contenere il testo atteso
negativa() {
  local m rc=0
  m="$(mondo "$1")" || fail "alterazione $1 non applicata"
  verifica "$m/vettori" "$m/out" "$m/codifica.md" > "$tmp/n.txt" 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || { cat "$tmp/n.txt" >&2; fail "PROVA NEGATIVA FALLITA ($1): la verifica e' uscita con $rc invece di 1"; }
  grep -qF -- "$2" "$tmp/n.txt" || { cat "$tmp/n.txt" >&2; fail "prova negativa ($1): la verifica e' fallita ma non per il motivo atteso ('$2')"; }
  log "   ok: $1 -> uscita $rc, $(grep -c '^ERRORE' "$tmp/n.txt") errori, tra cui: $2"
}
negativa vettore-senza-valore "ERRORE [vettori] oracle-gnucobol.tsv riga"
grep -qF "vettore senza atteso (valido senza valore o senza byte di scrittura)" "$tmp/n.txt" || fail "prova negativa (vettore-senza-valore): manca la diagnosi 'vettore senza atteso'"
negativa vettore-con-colonna-vuota "vettore senza atteso (colonna byte vuota)"
negativa variante-senza-vettori "ERRORE [copertura] profilo zos-ebcdic: variante del censimento senza vettori: display-senza-segno 9(16)"
negativa variante-del-censimento-in-piu "ERRORE [copertura] profilo oracle-gnucobol: variante del censimento senza vettori: comp 9(4)"
negativa riga-della-tabella-del-segno-tolta "ERRORE [copertura] profilo oracle-gnucobol categoria display-con-segno variante S9(4)V9(2): manca la riga 42 della tabella del segno"
negativa codice-comp3-tolto "ERRORE [copertura] profilo zos-ebcdic categoria comp-3 variante S9(9)V9(2): manca il codice di segno accettato F"
negativa estremo-binario-tolto "ERRORE [copertura] profilo oracle-gnucobol categoria comp variante 9(11): manca estremo della PICTURE (99999999999)"
negativa byte-distintivo-tolto "ERRORE [copertura] profilo zos-ebcdic categoria alfanumerico: manca il byte BA che distingue 037 da 1047"
negativa fonte-dell-altro-profilo "fonte GC-SRC-PACKED non appartiene al profilo zos-ebcdic"
negativa variante-tolta-dal-documento "ERRORE [documento] codifica.md: manca la variante comp 9(11)"
negativa fonte-tolta-dal-documento "fonte IBM-PG63-TRUNC non definita in codifica.md"
negativa pagina-byte-in-alfanumerico "ERRORE [pagina] AWS.M2.CARDDEMO.EXPORT.DATA.PS record 494 posizione 65: byte distintivo BB nel campo alfanumerico"
negativa osservazione-mancante "ERRORE [sonda] profilo oracle-gnucobol categoria display-con-segno variante S9(4)V9(2) byte 31 32 33 34 35 4A: nessuna osservazione della sonda"
negativa osservazione-in-piu "ERRORE [sonda] osservazione della riga 9 senza un vettore corrispondente"
negativa osservazione-alterata "ERRORE [sonda] profilo oracle-gnucobol categoria display-con-segno variante S9(10)V9(2) byte 30*7 31 32 33 34 4A: valore con MOVE atteso -123.41, osservato 123.41"
negativa oltre-picture-add-alterato "ERRORE [oltre-picture] profilo oracle-gnucobol categoria comp variante 9(9) byte FF*4: valore con ADD atteso 4294967295, osservato -1"
negativa oltre-picture-osservazione-tolta "ERRORE [oltre-picture] profilo oracle-gnucobol categoria comp variante 9(3) byte FF FF: caso oltre la PICTURE senza osservazione dichiarata"
negativa compilazione-senza-fsign "ERRORE [sonda] argomenti di compilazione della sonda"
negativa ambiente-in-piu "ERRORE [sonda] ambiente della sonda"
# l'output versionato alterato deve risultare diverso da quello rigenerato
m="$(mondo censimento-alterato)" || fail "alterazione censimento-alterato non applicata"
if diff -r "$tmp/gen" "$m/out" > "$tmp/d.txt" 2>&1; then fail "PROVA NEGATIVA FALLITA (censimento-alterato): nessuna differenza con l'output rigenerato"; fi
grep -q 'censimento.tsv' "$tmp/d.txt" || { cat "$tmp/d.txt" >&2; fail "prova negativa (censimento-alterato): differenza inattesa"; }
log "   ok: censimento-alterato -> il confronto con la rigenerazione trova la differenza in censimento.tsv"

log "5. prove negative reali sulla sonda"
# 5a. sonda compilata senza -fsign=EBCDIC (file delle opzioni senza quella riga, passato al modo uno dell'oracle)
mkdir -p "$tmp/senza"
grep -vx -- '-fsign=EBCDIC' "$ORACLE_DIR/cobc.opts" > "$tmp/senza/cobc.opts" || fail "file delle opzioni senza -fsign non scritto"
cmp -s "$ORACLE_DIR/cobc.opts" "$tmp/senza/cobc.opts" && fail "il file delle opzioni 'senza' coincide con oracle/cobc.opts"
mkdir -p "$tmp/senza/out"
cp "$tmp/gen/censimento.tsv" "$tmp/gen/censimento-categorie.tsv" "$tmp/gen/pagina.tsv" "$tmp/gen/pagina-esito.tsv" "$tmp/senza/out/" \
  || fail "copia dell'output per la sonda 'senza' fallita"
( dcod_sonde "$tmp/senza/out" "$tmp/senza/cobc.opts" ) > "$tmp/senza.log" 2>&1 || { cat "$tmp/senza.log" >&2; fail "sonda senza -fsign=EBCDIC non eseguita"; }
grep -qx 'arg -fsign=EBCDIC' "$tmp/senza/out/sonde/compilazione.log" && fail "la sonda 'senza' risulta compilata con -fsign=EBCDIC"
rc=0; verifica "$DCOD_DIR/vettori" "$tmp/senza/out" "$DCOD_DOC" > "$tmp/n.txt" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { cat "$tmp/n.txt" >&2; fail "PROVA NEGATIVA FALLITA (sonda senza -fsign=EBCDIC): la verifica e' uscita con $rc"; }
attesa="ERRORE [sonda] profilo oracle-gnucobol categoria display-con-segno variante S9(10)V9(2) byte 30*7 31 32 33 34 4A: IS NUMERIC atteso valido, osservato non-valido"
grep -qF -- "$attesa" "$tmp/n.txt" || { cat "$tmp/n.txt" >&2; fail "prova negativa (sonda senza -fsign=EBCDIC): manca '$attesa'"; }
log "   ok: sonda compilata senza -fsign=EBCDIC -> $(grep -c "^ERRORE \[sonda\] profilo" "$tmp/n.txt") errori sulle osservazioni, tra cui: $attesa"
# 5b. residuo: un'osservazione buona di una corsa precedente e una compilazione che fallisce
mkdir -p "$tmp/res/out"
cp -R "$tmp/gen/sonde" "$tmp/res/out/sonde" || fail "residuo non preparato"
{ cat "$ORACLE_DIR/cobc.opts"; echo "-fopzione-inesistente-menb"; } > "$tmp/res/cobc.opts"
rc=0; ( dcod_sonde "$tmp/res/out" "$tmp/res/cobc.opts" ) > "$tmp/res.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "PROVA NEGATIVA FALLITA (residuo): la sonda con una compilazione fallita e' risultata riuscita"
grep -qF "compilazione della sonda CODECPRB fallita" "$tmp/res.log" || { cat "$tmp/res.log" >&2; fail "prova negativa (residuo): fallita ma non per la compilazione"; }
[ ! -e "$tmp/res/out/sonde/osservazioni.tsv" ] || fail "PROVA NEGATIVA FALLITA (residuo): l'osservazione della corsa precedente e' rimasta"
log "   ok: compilazione fallita con un'osservazione precedente presente -> errore, e l'osservazione precedente e' stata rimossa"
log "data-codec: tutti i controlli superati"
