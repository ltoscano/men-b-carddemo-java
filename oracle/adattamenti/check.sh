#!/usr/bin/env bash
# Controllo del passo adattamenti (issue #25): CBSTM03A compilato dalla copia adattata e il suo scenario.
# 1. Copie adattate della build (verifica-copie.sh copie): CUSTREC uguale alla riapplicazione indipendente
#    dell'espansione dei TAB, senza TAB, nulla oltre la colonna 72; CBSTM03A diverso dall'originale solo
#    nelle 23 righe attese e solo nella colonna 7.
# 2. Tracciato di CUSTREC e copybook letti (verifica-copie.sh tracciato), con gli argomenti di cobc della
#    build: 500 byte, ogni campo come l'atteso scritto a mano; CUSTREC dalla copia, il resto dal legacy.
# 3. Dati dei blocchi di controllo z/OS (verifica-copie.sh zos): fuori dalle righe 266-291 compaiono solo
#    nelle dichiarazioni.
# 4. Provenienza dei file di testo dello scenario dai dati di esempio (origine.sh).
# 5. Scenario rieseguito in una cartella nuova (run.sh, con la verifica del caricamento).
# 6. Confronto con gli attesi: rapporto e ambiente esatti, STMTFILE e HTMLFILE byte per byte con l'output
#    registrato, e indipendentemente valori ricavati a mano (verifica-a-mano.tsv, record.tsv).
# 7. Prove negative 1-9 della specifica, piu' quelle dei controlli propri; ognuna deve fallire per il
#    motivo dichiarato (expect_fail in lib.sh).
. "$ORACLE_ROOT/lib.sh"

DIR="$ORACLE_ROOT/adattamenti"
EXP="$DIR/expected"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT
require_legacy
ensure_image
require_build

# Solo per le prove negative: CP_LEGACY e CP_ATTESI (cartelle sotto oracle/) sostituiscono, per
# verifica-copie.sh, la radice del legacy e la cartella degli attesi.
cp_env() {
  local c
  CPE=()
  if [ -n "${CP_LEGACY:-}" ]; then c="$(in_container "$CP_LEGACY")" || fail "CP_LEGACY fuori da oracle/"; CPE+=(-e "VERIFICA_LEGACY=$c"); fi
  if [ -n "${CP_ATTESI:-}" ]; then c="$(in_container "$CP_ATTESI")" || fail "CP_ATTESI fuori da oracle/"; CPE+=(-e "VERIFICA_ATTESI=$c"); fi
}
# copie_c AZIONE OUT: verifica-copie.sh nel container, con OUT (la build o una sua copia) su /out.
copie_c() {
  cp_env
  orun -v "$2:/out:ro" ${CPE[@]+"${CPE[@]}"} -- timeout -k 10 600 sh /oracle/adattamenti/verifica-copie.sh "$1" /out
}
# zos_c SORGENTE: verifica delle occorrenze dei dati dei blocchi di controllo z/OS nel sorgente dato.
zos_c() {
  cp_env
  orun ${CPE[@]+"${CPE[@]}"} -- timeout -k 10 120 sh /oracle/adattamenti/verifica-copie.sh zos "$1"
}
origine_c() {
  local s; s="$(in_container "$1")" || return 1
  orun -- timeout -k 10 120 sh /oracle/adattamenti/origine.sh "$s"
}
# uscite_c OSSERVATI [VERIFICA-A-MANO] [RECORD]: valori ricavati a mano contro STMTFILE e HTMLFILE.
uscite_c() {
  local o v r
  o="$(in_container "$1")" && v="$(in_container "${2:-$EXP/verifica-a-mano.tsv}")" \
    && r="$(in_container "${3:-$EXP/record.tsv}")" || return 1
  orun -- timeout -k 10 120 sh /oracle/adattamenti/verifica-uscite.sh "$o" "$v" "$r"
}

# verifica OSSERVATI [ATTESI]: rapporto, ambiente, STMTFILE e HTMLFILE contro l'output registrato, piu'
# i valori ricavati a mano. Ritorna 0 solo se tutto coincide.
verifica() {
  local obs="$1" att="${2:-$EXP}" errs=0 f rc
  if [ ! -f "$obs/CBSTM03A.txt" ]; then echo "CBSTM03A: rapporto assente"; errs=$((errs + 1))
  else
    rc="$(sed -n 2p "$obs/CBSTM03A.txt")"
    [ "$rc" = "$(sed -n 2p "$att/CBSTM03A.txt")" ] || { echo "CBSTM03A: codice di uscita $rc, atteso $(sed -n 2p "$att/CBSTM03A.txt")"; errs=$((errs + 1)); }
    diff -u "$att/CBSTM03A.txt" "$obs/CBSTM03A.txt" > "$tmp/d" || { echo "CBSTM03A: rapporto diverso dall'atteso:"; indent "$tmp/d"; errs=$((errs + 1)); }
  fi
  if [ ! -f "$obs/CBSTM03A.ambiente" ]; then echo "CBSTM03A: ambiente non registrato"; errs=$((errs + 1))
  elif ! diff -u "$att/CBSTM03A.ambiente" "$obs/CBSTM03A.ambiente" > "$tmp/d"; then
    echo "CBSTM03A: ambiente diverso da quello fissato:"; indent "$tmp/d"; errs=$((errs + 1)); fi
  for f in STMTFILE HTMLFILE; do
    if [ ! -f "$obs/$f" ]; then echo "$f: assente"; errs=$((errs + 1))
    elif ! cmp "$att/$f" "$obs/$f" > "$tmp/d" 2>&1; then
      echo "$f: diverso dall'atteso registrato ($(head -n 1 "$tmp/d" | sed "s#$REPO_ROOT/##g"))"; errs=$((errs + 1)); fi
  done
  if [ -f "$obs/STMTFILE" ] && [ -f "$obs/HTMLFILE" ]; then
    uscite_c "$obs" > "$tmp/u" 2>&1 || { echo "valori ricavati a mano:"; indent "$tmp/u"; errs=$((errs + 1)); }
  fi
  [ "$errs" -eq 0 ] || { echo "verifica fallita: $errs differenze"; return 1; }
  echo "verifica riuscita: rapporto, ambiente, STMTFILE e HTMLFILE come gli attesi; $(tail -n 1 "$tmp/u")"
}
# scenario NOME [VAR=VALORE ...]: riesegue lo scenario in $tmp/NOME/obs con le variabili date.
scenario() {
  local name="$1"; shift
  mkdir -p "$tmp/$name"
  env "$@" ADATTAMENTI_OUT_DIR="$tmp/$name/obs" bash "$DIR/run.sh" > "$tmp/$name.log" 2>&1
}
# compila_variante NOME TIPO SORGENTE PROGRAMMA [CARTELLA-ADATTATI]: compila SORGENTE (sotto $tmp/NOME/out,
# montata su /out) con le opzioni fissate e mette il risultato in una copia degli artefatti della build,
# $tmp/NOME/bin.
compila_variante() {
  local name="$1" tipo="$2" src="$3" prog="$4" ada="${5:-}"
  orun -v "$tmp/$name/out:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh /oracle/build/compile.sh uno "$tipo" "$src" "$prog" /out "" "" "$ada" > "$tmp/$name.compila.log" 2>&1 \
    || { indent "$tmp/$name.compila.log" >&2; fail "compilazione della variante '$name' fallita"; }
  mkdir -p "$tmp/$name/bin"
  cp "$BUILD_OUT"/bin/* "$tmp/$name/bin/" && cp "$tmp/$name/out/bin/$prog" "$tmp/$name/bin/$prog" \
    || fail "preparazione degli artefatti della variante '$name' fallita"
}
# copia_build NOME: copia di adattati/ e log/ della build in $tmp/NOME (per alterare le copie adattate).
copia_build() {
  rm -rf "$tmp/$1"; mkdir -p "$tmp/$1"
  cp -R "$BUILD_OUT/adattati" "$BUILD_OUT/log" "$tmp/$1/" || fail "copia della build per '$1' fallita"
}

log "1. copie adattate della build"
copie_c copie "$BUILD_OUT" > "$tmp/c1.out" 2>&1 || { indent "$tmp/c1.out" >&2; fail "copie adattate non conformi"; }
indent "$tmp/c1.out" >&2
log "2. tracciato di CUSTREC e copybook letti, con gli argomenti di cobc della build"
copie_c tracciato "$BUILD_OUT" > "$tmp/c2.out" 2>&1 || { indent "$tmp/c2.out" >&2; fail "tracciato o copybook non conformi"; }
indent "$tmp/c2.out" >&2
log "3. dati dei blocchi di controllo z/OS nel sorgente originale"
zos_c /legacy/app/cbl/CBSTM03A.CBL > "$tmp/c3.out" 2>&1 || { indent "$tmp/c3.out" >&2; fail "dati dei blocchi di controllo usati fuori dalle righe 266-291"; }
indent "$tmp/c3.out" >&2
log "4. provenienza dello scenario"
origine_c "$DIR/scenario" > "$tmp/c4.out" 2>&1 || { indent "$tmp/c4.out" >&2; fail "provenienza dello scenario non verificata"; }
indent "$tmp/c4.out" >&2
log "5. scenario rieseguito in una cartella nuova"
ADATTAMENTI_OUT_DIR="$tmp/obs" bash "$DIR/run.sh" || fail "scenario di CBSTM03A fallito"
log "6. confronto con gli attesi"
verifica "$tmp/obs" > "$tmp/v.out" 2>&1 || { indent "$tmp/v.out" >&2; fail "CBSTM03A non produce gli estratti attesi"; }
indent "$tmp/v.out" >&2

log "7. prove negative"
# --- 1. TAB espansi a 8 colonne (adatta.sh con LARGHEZZA_TAB=8): compilazione e tracciato falliscono.
copia_build n1; rm -rf "$tmp/n1/adattati"
cp "$DIR/adatta.sh" "$tmp/n1.adatta.sh"; mutate "$tmp/n1.adatta.sh" 's/^LARGHEZZA_TAB=4$/LARGHEZZA_TAB=8/'
n1c="$(in_container "$tmp/n1.adatta.sh")" || fail "prova 1: percorso fuori da oracle/"
orun -v "$tmp/n1:/out" -- timeout -k 10 60 sh "$n1c" /legacy /out/adattati > "$tmp/n1.log" 2>&1 \
  || { indent "$tmp/n1.log" >&2; fail "generazione delle copie a 8 colonne fallita"; }
expect_fail "1. TAB a 8 colonne: la compilazione con gli argomenti della build fallisce" \
  "tracciato: compilazione di controllo di CBSTM03A fallita" copie_c tracciato "$tmp/n1"
expect_fail "1. TAB a 8 colonne: testo oltre la colonna 72" "CUSTREC.cpy: testo oltre la colonna 72" copie_c copie "$tmp/n1"
# --- 2. Un TAB lasciato nella copia (i primi 8 spazi della riga 7 tornano un TAB).
copia_build n2; mutate "$tmp/n2/adattati/CUSTREC.cpy" "7s/^        /$(printf '\t')/"
expect_fail "2. TAB lasciato nella riga 7 della copia di CUSTREC" "CUSTREC.cpy: TAB nella copia (righe: 7 )" copie_c copie "$tmp/n2"
# --- 3. Un campo spostato di una colonna (stesso testo, spazi diversi): il tracciato non cambia, fallisce
#        il confronto con la riapplicazione indipendente.
copia_build n3; mutate "$tmp/n3/adattati/CUSTREC.cpy" '7s/^             05  CUST-MIDDLE-NAME/              05 CUST-MIDDLE-NAME/'
expect_fail "3. CUST-MIDDLE-NAME spostato di una colonna nella copia" \
  "CUSTREC.cpy: la copia e' diversa dalla riapplicazione indipendente" copie_c copie "$tmp/n3"
copie_c tracciato "$tmp/n3" > "$tmp/n3.tr" 2>&1 || { indent "$tmp/n3.tr" >&2; fail "prova 3: il tracciato della copia spostata doveva restare valido"; }
log "   e il tracciato della copia spostata resta valido: fallisce solo il confronto con la riapplicazione"
# --- 4. Righe di CBSTM03A: una non vuota dell'intervallo non commentata; una commentata fuori
#        dall'intervallo (293); una modificata altrove (300); una vuota dell'intervallo alterata (271).
copia_build n4a; mutate "$tmp/n4a/adattati/CBSTM03A.CBL" '270s/^\(......\)\*/\1 /'
expect_fail "4a. riga 270 lasciata non commentata" "CBSTM03A.CBL riga 270: non commentata" copie_c copie "$tmp/n4a"
copia_build n4b; mutate "$tmp/n4b/adattati/CBSTM03A.CBL" '293s/^\(......\) /\1*/'
expect_fail "4b. riga 293 commentata (fuori dall'intervallo)" "CBSTM03A.CBL riga 293: modificata fuori dall intervallo 266-291" copie_c copie "$tmp/n4b"
copia_build n4c; mutate "$tmp/n4c/adattati/CBSTM03A.CBL" "300s/8100-TRNXFILE-OPEN/8200-XREFFILE-OPEN/"
expect_fail "4c. riga 300 modificata" "CBSTM03A.CBL riga 300: modificata fuori dall intervallo 266-291" copie_c copie "$tmp/n4c"
copia_build n4d; mutate "$tmp/n4d/adattati/CBSTM03A.CBL" '271s/^$/      */'
expect_fail "4d. riga vuota 271 alterata" "CBSTM03A.CBL riga 271: riga vuota dell intervallo alterata" copie_c copie "$tmp/n4d"
# --- 5. CBSTM03B.so assente all'esecuzione, con un residuo sano della corsa buona nella cartella d'uscita:
#        lo scenario fallisce alla prima CALL e il residuo non viene preso per attuale.
mkdir -p "$tmp/n5/bin"; cp "$BUILD_OUT"/bin/* "$tmp/n5/bin/" && rm "$tmp/n5/bin/CBSTM03B.so" || fail "preparazione della prova 5 fallita"
cp -R "$tmp/obs" "$tmp/n5/obs"
scenario n5 ADATTAMENTI_BIN_DIR="$tmp/n5/bin" || { indent "$tmp/n5.log" >&2; fail "prova 5: scenario non completato"; }
expect_fail "5. CBSTM03B.so assente (residuo sano nella cartella)" "+libcob: error: module 'CBSTM03B' not found" verifica "$tmp/n5/obs"
[ "$(sed -n 2p "$tmp/n5/obs/CBSTM03A.txt")" != 0 ] || fail "prova 5: CBSTM03A senza CBSTM03B ha terminato con 0"
# --- 6. Un ALTER reindirizzato a un altro paragrafo (copia di prova di CBSTM03A, riga 300: il primo
#        ALTER porta a 8200-XREFFILE-OPEN invece che a 8100-TRNXFILE-OPEN), compilato davvero.
mkdir -p "$tmp/n6/out/adattati"; cp "$BUILD_OUT/adattati/"* "$tmp/n6/out/adattati/" || fail "preparazione della prova 6 fallita"
mutate "$tmp/n6/out/adattati/CBSTM03A.CBL" '300s/ALTER 8100-FILE-OPEN TO PROCEED TO 8100-TRNXFILE-OPEN/ALTER 8100-FILE-OPEN TO PROCEED TO 8200-XREFFILE-OPEN/'
compila_variante n6 eseguibile /out/adattati/CBSTM03A.CBL CBSTM03A /out/adattati
scenario n6 ADATTAMENTI_BIN_DIR="$tmp/n6/bin" || { indent "$tmp/n6.log" >&2; fail "prova 6: scenario non completato"; }
expect_fail "6. ALTER della riga 300 reindirizzato a 8200-XREFFILE-OPEN" "STMTFILE: diverso dall'atteso registrato" verifica "$tmp/n6/obs"
# --- 7. Un importo cambiato in un movimento d'ingresso (183,88 -> 183,89).
mkdir -p "$tmp/n7"; cp -R "$DIR/scenario" "$tmp/n7/scenario"
mutate "$tmp/n7/scenario/trnxfile.txt" '1s/0000001838H/0000001839H/'
scenario n7 ADATTAMENTI_SCENARIO="$tmp/n7/scenario" || { indent "$tmp/n7.log" >&2; fail "prova 7: scenario non completato"; }
expect_fail "7. importo del primo movimento cambiato: output registrato" "STMTFILE: diverso dall'atteso registrato" verifica "$tmp/n7/obs"
expect_fail "7. importo del primo movimento cambiato: valori ricavati a mano" \
  "DIFETTO: STMTFILE record 17 posizione 68 lunghezza 13" uscite_c "$tmp/n7/obs"
expect_fail "7. importo cambiato: la provenienza dello scenario non e' piu' quella dichiarata" \
  "trnxfile.txt riga 1: diversa da dailytran.txt riga 21" origine_c "$tmp/n7/scenario"
# --- 8. Attesi alterati, un valore della tabella a mano alterato, un caricatore che altera un campo.
for f in STMTFILE HTMLFILE CBSTM03A.txt; do
  mkdir -p "$tmp/n8-$f"; cp "$EXP"/* "$tmp/n8-$f/"
done
mutate "$tmp/n8-STMTFILE/STMTFILE" 's/Aniya Alba Von/Aniya Alba Vom/'
expect_fail "8. un byte alterato nell'atteso STMTFILE" "STMTFILE: diverso dall'atteso registrato" verifica "$tmp/obs" "$tmp/n8-STMTFILE"
mutate "$tmp/n8-HTMLFILE/HTMLFILE" 's#<p>0000000058866561</p>#<p>0000000058866562</p>#'
expect_fail "8. un byte alterato nell'atteso HTMLFILE" "HTMLFILE: diverso dall'atteso registrato" verifica "$tmp/obs" "$tmp/n8-HTMLFILE"
mutate "$tmp/n8-CBSTM03A.txt/CBSTM03A.txt" 's/^HTMLFILE 23600$/HTMLFILE 23601/'
expect_fail "8. un byte alterato nel rapporto atteso" "CBSTM03A: rapporto diverso dall'atteso" verifica "$tmp/obs" "$tmp/n8-CBSTM03A.txt"
cp "$EXP/verifica-a-mano.tsv" "$tmp/n8-vam.tsv"
mutate "$tmp/n8-vam.tsv" '/^STMTFILE	11	21	20	623	/s/	623	/	624	/'
expect_fail "8. FICO alterato nella tabella a mano (623 -> 624)" "DIFETTO: STMTFILE record 11 posizione 21 lunghezza 20" uscite_c "$tmp/obs" "$tmp/n8-vam.tsv"
#     Caricatore che azzera il FICO dei clienti (byte 330-332 del record di CUSTFILE), compilato davvero.
mkdir -p "$tmp/n8c/out"; cp "$ORACLE_ROOT/tests/IDXLOAD.cbl" "$tmp/n8c/IDXLOAD.cbl"
mutate "$tmp/n8c/IDXLOAD.cbl" "s/^                 WRITE FD-CUSTFILE-REC\$/           MOVE '000' TO FD-CUST-DATA (321:3) WRITE FD-CUSTFILE-REC/"
n8cc="$(in_container "$tmp/n8c/IDXLOAD.cbl")" || fail "prova 8: percorso fuori da oracle/"
compila_variante n8c eseguibile "$n8cc" IDXLOAD
expect_fail "8. caricatore che azzera il FICO: la verifica del caricamento ferma lo scenario" \
  "CUSTFILE: contenuto riletto diverso dal file di testo: primo byte diverso nel record 1, posizione 330" \
  env ADATTAMENTI_BIN_DIR="$tmp/n8c/bin" ADATTAMENTI_OUT_DIR="$tmp/n8c/obs" bash "$DIR/run.sh"
[ -f "$tmp/n8c/obs/carico/verifica.txt" ] || fail "prova 8: la verifica del caricamento non e' stata eseguita"
[ ! -e "$tmp/n8c/obs/CBSTM03A.txt" ] || fail "prova 8: CBSTM03A e' stato eseguito su un caricamento infedele"
log "   e CBSTM03A non e' stato eseguito sul caricamento infedele"
# --- 9. Un file indicizzato d'ingresso mancante (ACCTFILE): ERROR OPENING, CEE3ABD, codice 99, distinto dal
#        successo e uguale all'atteso dell'arresto (stdout e codice dal sorgente, righe 807-813 e 921-923).
scenario n9 ADATTAMENTI_SENZA=ACCTFILE || { indent "$tmp/n9.log" >&2; fail "prova 9: scenario non completato"; }
expect_fail "9. ACCTFILE assente: distinto dal successo" "CBSTM03A: codice di uscita 99, atteso 0" verifica "$tmp/n9/obs"
diff -u "$EXP/senza-ACCTFILE.txt" "$tmp/n9/obs/CBSTM03A.txt" > "$tmp/n9.diff" \
  || { indent "$tmp/n9.diff" >&2; fail "prova 9: l'arresto per ACCTFILE assente non e' quello prescritto dal sorgente"; }
log "   e l'arresto coincide con l'atteso: ERROR OPENING ACCTFILE, RETURN CODE: 35, ABENDING PROGRAM, codice 99"

# --- Controlli propri.
#     Campo di lunghezza diversa nella copia; copybook in piu' nella cartella delle copie (letto al posto
#     di quello del legacy).
copia_build tra
mutate "$tmp/tra/adattati/CUSTREC.cpy" '22s/PIC 9(03)\./PIC 9(04)./'
expect_fail "tracciato: CUST-FICO-CREDIT-SCORE di 4 byte nella copia" "tracciato di CUSTOMER-RECORD visto dal compilatore diverso" copie_c tracciato "$tmp/tra"
copia_build dip; orun -v "$tmp/dip:/out" -- timeout 60 cp /legacy/app/cpy/COSTM01.CPY /out/adattati/COSTM01.CPY || fail "preparazione della prova 'dip' fallita"
expect_fail "copybook COSTM01 letto dalla cartella delle copie adattate" "copybook letti dalla compilazione di CBSTM03A diversi" copie_c tracciato "$tmp/dip"
expect_fail "copybook in piu' nella cartella delle copie adattate" "adattati/: contenuto 'CBSTM03A.CBL COSTM01.CPY CUSTREC.cpy '" copie_c copie "$tmp/dip"
#     Dati dei blocchi di controllo letti fuori dall'intervallo (copia di prova dell'originale, riga 293).
cp "$LEGACY/app/cbl/CBSTM03A.CBL" "$tmp/zos.cbl"
mutate "$tmp/zos.cbl" '293s/OPEN OUTPUT STMT-FILE HTML-FILE\./DISPLAY TIOTNJOB OPEN OUTPUT STMT-FILE HTML-FILE./'
zosc="$(in_container "$tmp/zos.cbl")" || fail "prova 'zos': percorso fuori da oracle/"
expect_fail "TIOTNJOB letto alla riga 293" "fuori dalle righe 266-291: TIOTNJOB:293" zos_c "$zosc"
#     Provenienza: un cliente dello scenario diverso dalla riga dichiarata.
mkdir -p "$tmp/ori"; cp -R "$DIR/scenario" "$tmp/ori/scenario"
mutate "$tmp/ori/scenario/custfile.txt" '3s/^000000050Aniya/000000050Anija/'
expect_fail "provenienza: riga 3 di custfile.txt alterata" "custfile.txt riga 3: diversa da custdata.txt riga 50" origine_c "$tmp/ori/scenario"
#     Un record in piu' in STMTFILE (copia dell'ultimo) e uno in meno in HTMLFILE.
mkdir -p "$tmp/rec"; cp "$tmp/obs/STMTFILE" "$tmp/obs/HTMLFILE" "$tmp/rec/"
tail -c 80 "$tmp/obs/STMTFILE" >> "$tmp/rec/STMTFILE" || fail "preparazione della prova 'rec' fallita"
expect_fail "STMTFILE con un record in piu'" "DIFETTO: STMTFILE: 4960 byte, attesi 61 record da 80 byte (4880)" uscite_c "$tmp/rec"
head -c 23500 "$tmp/obs/HTMLFILE" > "$tmp/rec/HTMLFILE" || fail "preparazione della prova 'rec' fallita"
expect_fail "HTMLFILE con un record in meno" "DIFETTO: HTMLFILE: 23500 byte, attesi 236 record da 100 byte (23600)" uscite_c "$tmp/rec"
#     Tabella a mano incompleta, duplicata o malformata (rilievo 1, giro 1 della PR #44): deve coprire
#     esattamente l'insieme dei campi definito in verifica-uscite.sh, per ogni estratto e ogni output.
cp "$EXP/verifica-a-mano.tsv" "$tmp/vam-omessa.tsv"; mutate "$tmp/vam-omessa.tsv" '/^HTMLFILE	188	25	20	268	/d'
expect_fail "tabella a mano senza il FICO HTML del terzo estratto" \
  "manca la riga attesa: HTMLFILE record 188, campo (estratto 3, ST-FICO-SCORE)" uscite_c "$tmp/obs" "$tmp/vam-omessa.tsv"
cp "$EXP/verifica-a-mano.tsv" "$tmp/vam-dup.tsv"; mutate "$tmp/vam-dup.tsv" '/^STMTFILE	11	21	20	623	/p'
expect_fail "tabella a mano con una riga duplicata" "riga duplicata (estratto 1, ST-FICO-SCORE, STMTFILE record 11)" uscite_c "$tmp/obs" "$tmp/vam-dup.tsv"
cp "$EXP/verifica-a-mano.tsv" "$tmp/vam-junk.tsv"; mutate "$tmp/vam-junk.tsv" '/^STMTFILE	2	1	75	/s/	75	/	75junk	/'
expect_fail "tabella a mano con lunghezza '75junk'" "verifica-a-mano riga 3: metadati non validi" uscite_c "$tmp/obs" "$tmp/vam-junk.tsv"
cp "$EXP/verifica-a-mano.tsv" "$tmp/vam-sposta.tsv"; mutate "$tmp/vam-sposta.tsv" '/^HTMLFILE	188	25	20	268	/s/^HTMLFILE	188	/HTMLFILE	124	/'
expect_fail "FICO HTML del terzo estratto assegnato al record del secondo" \
  "manca la riga attesa: HTMLFILE record 188, campo (estratto 3, ST-FICO-SCORE)" uscite_c "$tmp/obs" "$tmp/vam-sposta.tsv"
expect_fail "FICO HTML del terzo estratto assegnato al record del secondo: duplicato" \
  "riga duplicata (estratto 2, ST-FICO-SCORE, HTMLFILE record 124)" uscite_c "$tmp/obs" "$tmp/vam-sposta.tsv"
head -n 2 "$EXP/verifica-a-mano.tsv" > "$tmp/vam-una.tsv" || fail "preparazione della prova 'vam-una' fallita"
expect_fail "tabella a mano con una sola riga" "manca la riga attesa" uscite_c "$tmp/obs" "$tmp/vam-una.tsv"
#     STMTFILE e HTMLFILE letti per intero (rilievo 2): byte dopo un 0x01 in coda, 0x01 all'interno.
mkdir -p "$tmp/sep1" "$tmp/sep2"; cp "$tmp/obs/STMTFILE" "$tmp/obs/HTMLFILE" "$tmp/sep1/" && cp "$tmp/obs/STMTFILE" "$tmp/obs/HTMLFILE" "$tmp/sep2/" \
  || fail "preparazione delle prove 'sep' fallita"
printf '\001GARBAGE' >> "$tmp/sep1/HTMLFILE" || fail "preparazione della prova 'sep1' fallita"
expect_fail "HTMLFILE con 0x01GARBAGE in coda: separatore" "DIFETTO: HTMLFILE contiene il byte 0x01" uscite_c "$tmp/sep1"
expect_fail "HTMLFILE con 0x01GARBAGE in coda: dimensione reale" "DIFETTO: HTMLFILE: 23608 byte, attesi 236 record da 100 byte (23600)" uscite_c "$tmp/sep1"
{ head -c 100 "$tmp/obs/STMTFILE"; printf '\001'; tail -c +102 "$tmp/obs/STMTFILE"; } > "$tmp/sep2/STMTFILE" || fail "preparazione della prova 'sep2' fallita"
expect_fail "STMTFILE con un 0x01 al posto del byte 101" "DIFETTO: STMTFILE contiene il byte 0x01 (2 segmenti)" uscite_c "$tmp/sep2"
cp "$EXP/verifica-a-mano.tsv" "$tmp/fuori.tsv"
mutate "$tmp/fuori.tsv" '/^STMTFILE	2	1	75	/s/	75	/	81	/'
expect_fail "tabella a mano con un campo oltre il record" "verifica-a-mano riga 3: valore o posizione fuori dal record" uscite_c "$tmp/obs" "$tmp/fuori.tsv"
#     Ambiente atteso diverso.
mkdir -p "$tmp/amb"; cp "$EXP"/* "$tmp/amb/"; mutate "$tmp/amb/CBSTM03A.ambiente" 's#^DD_ACCTFILE=/out/dati/ACCTFILE\.dat$#DD_ACCTFILE=/altrove#'
expect_fail "ambiente atteso con un'altra DD per ACCTFILE" "CBSTM03A: ambiente diverso da quello fissato" verifica "$tmp/obs" "$tmp/amb"
#     Copie adattate: righe con TAB nell'originale diverse da 6-22 (legacy di prova in cui la riga 23
#     comincia con un TAB che expand -t 4 riporta agli stessi spazi: l'identita' resta, cambia l'elenco).
mkdir -p "$tmp/leg/app/cpy" "$tmp/leg/app/cbl"
cp "$LEGACY/app/cpy/CUSTREC.cpy" "$tmp/leg/app/cpy/" && cp "$LEGACY/app/cbl/CBSTM03A.CBL" "$tmp/leg/app/cbl/" || fail "preparazione della prova 'leg' fallita"
mutate "$tmp/leg/app/cpy/CUSTREC.cpy" "23s/^    /$(printf '\t')/"
CP_LEGACY="$tmp/leg" expect_fail "righe con TAB nell'originale: anche la 23" \
  "CUSTREC.cpy: righe con TAB nell'originale '6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23'" copie_c copie "$BUILD_OUT"
CP_LEGACY="$tmp/leg" copie_c copie "$BUILD_OUT" > "$tmp/leg.out" 2>&1 || true
! grep -q "diversa dalla riapplicazione" "$tmp/leg.out" || fail "prova 'leg': doveva cambiare solo l'elenco delle righe con TAB"
#     Copie adattate: una riga senza TAB cambiata (riga 5); una riga in piu' in CBSTM03A; byte e righe vuote.
copia_build r5; mutate "$tmp/r5/adattati/CUSTREC.cpy" '5s/CUST-ID /CUST-IX /'
expect_fail "riga 5 di CUSTREC (senza TAB) cambiata nella copia" "righe senza TAB nell'originale cambiate nella copia: 5" copie_c copie "$tmp/r5"
copia_build piu; mutate "$tmp/piu/adattati/CBSTM03A.CBL" '$a\
      * riga in piu'"'"
expect_fail "riga in piu' in coda alla copia di CBSTM03A" "CBSTM03A.CBL: numero di righe" copie_c copie "$tmp/piu"
expect_fail "riga in piu' in coda alla copia di CBSTM03A: cmp arriva alla fine di un solo file" \
  "CBSTM03A.CBL: confronto byte per byte non completo" copie_c copie "$tmp/piu"
copia_build ill; chmod 000 "$tmp/ill/adattati/CUSTREC.cpy" || fail "preparazione della prova 'ill' fallita"
[ ! -r "$tmp/ill/adattati/CUSTREC.cpy" ] || fail "prova 'ill': la copia resta leggibile dopo chmod 000 (utente root?)"
expect_fail "copia di CUSTREC illeggibile: la lettura fallita non passa per 'nessun TAB'" \
  "CUSTREC.cpy: copia o originale assente o illeggibile" copie_c copie "$tmp/ill"
chmod 644 "$tmp/ill/adattati/CUSTREC.cpy"
copia_build pri; mutate "$tmp/pri/log/CBSTM03A.log" '/^arg -I\/out\/adattati$/d'
expect_fail "log di CBSTM03A senza -I/out/adattati in testa" "tracciato: il primo argomento registrato non e' -I/out/adattati" copie_c tracciato "$tmp/pri"
expect_fail "riga 293 commentata: 24 byte diversi" "24 byte diversi dall'originale (cmp -l), attesi 23" copie_c copie "$tmp/n4b"
expect_fail "riga vuota 271 alterata: controllo delle righe vuote" "CBSTM03A.CBL riga 271: attesa vuota" copie_c copie "$tmp/n4d"
#     Tracciato: argomenti registrati inattesi; atteso con la riga sbagliata o troncato.
copia_build arg; mutate "$tmp/arg/log/CBSTM03A.log" 's#^arg /out/adattati/CBSTM03A\.CBL$#arg /out/adattati/ALTRO.CBL#'
expect_fail "log di CBSTM03A con un altro sorgente" "tracciato: argomenti registrati inattesi in coda" copie_c tracciato "$tmp/arg"
mkdir -p "$tmp/att-riga"; cp "$EXP"/* "$tmp/att-riga/"
mutate "$tmp/att-riga/custrec-tracciato.tsv" 's/^CUST-SSN	280	9	17$/CUST-SSN	280	9	18/'
CP_ATTESI="$tmp/att-riga" expect_fail "tracciato atteso: CUST-SSN dichiarato alla riga 18" "CUST-SSN non e' alla riga 18 di CUSTREC.cpy" copie_c tracciato "$BUILD_OUT"
mkdir -p "$tmp/att-tronco"; cp "$EXP"/* "$tmp/att-tronco/"; mutate "$tmp/att-tronco/custrec-tracciato.tsv" '/^FILLER	/d'
CP_ATTESI="$tmp/att-tronco" expect_fail "tracciato atteso senza FILLER" "tracciato: l'atteso non ha 20 righe" copie_c tracciato "$BUILD_OUT"
mutate "$tmp/att-tronco/blocchi-zos.tsv" '/^TIOTPSTP	/d'
CP_ATTESI="$tmp/att-tronco" expect_fail "occorrenze attese senza TIOTPSTP" "zos: l'atteso non elenca 19 nomi" zos_c /legacy/app/cbl/CBSTM03A.CBL
#     Provenienza: una riga dello scenario senza provenienza dichiarata.
mkdir -p "$tmp/cop"; cp -R "$DIR/scenario" "$tmp/cop/scenario"
mutate "$tmp/cop/scenario/origine.tsv" '/^custfile\.txt	2	/d'
expect_fail "origine.tsv senza la riga 2 di custfile.txt" "custfile.txt riga 2: provenienza dichiarata 0 volte" origine_c "$tmp/cop/scenario"
#     Caricamento: chiavi non crescenti (IDXLOAD si ferma); una riga di testo piu' lunga del dichiarato.
mkdir -p "$tmp/ord"; cp -R "$DIR/scenario" "$tmp/ord/scenario"
{ sed -n 2p "$DIR/scenario/custfile.txt"; sed -n 1p "$DIR/scenario/custfile.txt"; sed -n 3p "$DIR/scenario/custfile.txt"; } > "$tmp/ord/scenario/custfile.txt" \
  || fail "preparazione della prova 'ord' fallita"
expect_fail "custfile.txt con due chiavi scambiate" "caricamento di CUSTFILE: IDXLOAD non ha terminato con 0" \
  env ADATTAMENTI_SCENARIO="$tmp/ord/scenario" ADATTAMENTI_OUT_DIR="$tmp/ord/obs" bash "$DIR/run.sh"
mkdir -p "$tmp/lun"; cp -R "$DIR/scenario" "$tmp/lun/scenario"; mutate "$tmp/lun/scenario/xreffile.txt" '1s/$/ /'
expect_fail "xreffile.txt con la riga 1 lunga 37" "XREFFILE: righe di xreffile.txt con lunghezza diversa da 36: 1(37)" \
  env ADATTAMENTI_SCENARIO="$tmp/lun/scenario" ADATTAMENTI_OUT_DIR="$tmp/lun/obs" bash "$DIR/run.sh"
#     Rapporto di IDXLOAD con una riga di stdout in piu' (involucro che esegue il vero IDXLOAD e aggiunge
#     una riga): il controllo dei rapporti guarda lo stdout intero, non solo la sua prima riga.
mkdir -p "$tmp/piurighe/bin"; cp "$BUILD_OUT"/bin/* "$tmp/piurighe/bin/" && mv "$tmp/piurighe/bin/IDXLOAD" "$tmp/piurighe/bin/IDXLOAD.vero" \
  || fail "preparazione della prova 'piurighe' fallita"
printf '#!/bin/sh\n/oracle-bin/IDXLOAD.vero "$@"; rc=$?\necho RIGA IN PIU\nexit $rc\n' > "$tmp/piurighe/bin/IDXLOAD" && chmod +x "$tmp/piurighe/bin/IDXLOAD" \
  || fail "preparazione della prova 'piurighe' fallita"
expect_fail "rapporto di IDXLOAD con una riga di stdout in piu'" "caricamento di TRNXFILE: IDXLOAD non ha terminato con 0" \
  env ADATTAMENTI_BIN_DIR="$tmp/piurighe/bin" ADATTAMENTI_OUT_DIR="$tmp/piurighe/obs" bash "$DIR/run.sh"
#     Copia adattata cambiata nella build dopo la build: lo scenario rifiuta gli artefatti.
cp -R "$BUILD_OUT" "$tmp/bo"; mutate "$tmp/bo/adattati/CBSTM03A.CBL" '300s/8100-TRNXFILE-OPEN/8200-XREFFILE-OPEN/'
expect_fail "copia adattata di CBSTM03A cambiata dopo la build" "artefatti della build cambiati" \
  env ORACLE_BUILD_OUT="$tmp/bo" ADATTAMENTI_OUT_DIR="$tmp/bo-obs" bash "$DIR/run.sh"
log "controllo superato"
