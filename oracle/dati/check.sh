#!/usr/bin/env bash
# Controllo del passo dati (issue #53): il file dei conti nell'oracle.
# 1. Passo rieseguito da zero in una cartella nuova (run.sh): caricamento con IDXLOADF, rilettura con IDXDUMP,
#    rilettura identica all'ingresso, rapporto, rapporti di esegui.sh e ambienti identici agli attesi, file
#    indicizzato al suo percorso stabile e riletto da li' in sola lettura; poi una rilettura indipendente da run.sh.
# 2. Organizzazione, chiave e lunghezza del file nei programmi di prova (IDXLOADF, IDXDUMP) uguali al SELECT e all'FD
#    di CBACT01C (app/cbl/CBACT01C.cbl, righe 29-33 e 52-56), letti dal sorgente.
# 3. Prove negative della specifica e dei controlli propri, ciascuna con il motivo atteso (expect_fail di lib.sh) e,
#    dopo ogni fallimento, nessun file indicizzato rimasto: ingresso alterato (record tolto, record scambiati, chiave
#    duplicata, byte numerico e del FILLER, troncato a meta' record, ZIP ASCII, record di 299 byte), programmi
#    alterati e ricompilati (caricatore che esce con errore, rilettura che si ferma un record prima), attesi alterati,
#    build assente, ingresso assente.
# 4. Residui: un file indicizzato diverso rimasto e una corsa regolare (successo, contenuto corretto); un file sano
#    rimasto e un caricamento che fallisce (errore, nessun file utilizzabile).
# 5. Presenza del passo: la cartella oracle/dati/ cancellata e' vista dal controllo dei passi di build/check.sh.
# 6. Esiti dei comandi: carica.sh (build/avvolgi.sh davanti nel PATH del container: ogni invocazione di ogni comando
#    con esito 42 dopo il suo lavoro; risposte malformate con esito 0; esegui.sh che esce con 42; limite di tempo) e
#    run.sh (cp, mv, diff, cmp, rm e i due docker sull'host).
. "$ORACLE_ROOT/lib.sh"

DIR="$ORACLE_ROOT/dati"
EXP="$DIR/expected"
REC="$REPO_ROOT/analysis/oracle-dati/out/ACCTFILE.rec"
tmp="$(mktmp)" || exit 1
trap 'rm -rf "$tmp"' EXIT
require_legacy
ensure_image
require_build
[ -f "$REC" ] || fail "ingresso assente: $(rel "$REC"): eseguire './analysis/run.sh oracle-dati'"

# passo ID [VAR=VALORE ...]: run.sh con l'uscita in $tmp/ID/out e le variabili date; log in $tmp/ID.log.
passo() {
  local n="$1"; shift
  mkdir -p "$tmp/$n" || fail "cartella di '$n' non creata"
  env DATI_OUT_DIR="$tmp/$n/out" "$@" bash "$DIR/run.sh" > "$tmp/$n.log" 2>&1
}
# pulita CARTELLA-D'USCITA: nessun file indicizzato (ne' al percorso stabile ne' nella cartella di lavoro)
pulita() {
  [ ! -e "$1/ACCTFILE.dat" ] || { echo "resta un file indicizzato al percorso stabile: $(rel "$1")/ACCTFILE.dat"; return 1; }
  [ ! -e "$1/lavoro" ] || { echo "resta la cartella di lavoro: $(rel "$1")/lavoro"; return 1; }
}
# neg ID DESCRIZIONE SOTTOSTRINGA [VAR=VALORE ...]: run.sh deve fallire per quel motivo; dopo, nessun file indicizzato.
neg() {
  local n="$1" d="$2" ago="$3"; shift 3
  mkdir -p "$tmp/$n" || fail "cartella di '$n' non creata"
  expect_fail "$d" "$ago" env DATI_OUT_DIR="$tmp/$n/out" "$@" bash "$DIR/run.sh"
  pulita "$tmp/$n/out" > "$tmp/$n.pulita" 2>&1 || { cat "$tmp/$n.pulita" >&2; fail "PROVA NEGATIVA FALLITA ($d): dopo il fallimento"; }
}
# rileggi FILE-INDICIZZATO DEST: IDXDUMP della build rilegge il file in DEST/rilettura.bin, indipendentemente da
# run.sh; ritorna 0 solo se IDXDUMP termina con 0.
rileggi() {
  local f d c
  f="$(in_container "$1")" && d="$(in_container "$2")" || return 1
  mkdir -p "$2" || return 1
  orun -v "$BUILD_OUT/bin:/oracle-bin:ro" -v "$2:/ril" -- timeout -k 10 120 sh /oracle/esegui.sh /ril IDXDUMP \
    --parm ACCTFILE --dd "DD_ACCTFILE=$f" --dd "DD_USCITA=/ril/rilettura.bin" > "$2.log" 2>&1 || return 1
  c="$(sed -n 2p "$2/IDXDUMP.txt")" || return 1
  [ "$c" = 0 ]
}
# scrivi_byte FILE POSIZIONE TESTO: sostituisce i byte da POSIZIONE (da 0), dimensione invariata, alterazione verificata
scrivi_byte() {
  local f="$1" p="$2" s="$3" n m
  n="$(wc -c < "$f")" || fail "dimensione di $f illeggibile"
  { head -c "$p" "$f" && printf '%s' "$s" && tail -c "+$((p + ${#s} + 1))" "$f"; } > "$f.nuovo" || fail "alterazione di $f fallita"
  ! cmp -s "$f" "$f.nuovo" || fail "alterazione di $(rel "$f") senza effetto"
  mv "$f.nuovo" "$f" || fail "sostituzione di $f fallita"
  m="$(wc -c < "$f")" || fail "dimensione di $f illeggibile"
  [ "$m" -eq "$n" ] || fail "alterazione di $(rel "$f"): dimensione cambiata"
}
# record FILE N: i 300 byte del record N (da 1) in un file, poi su stdout (niente pipeline: nessun esito perso)
record() {
  tail -c "+$(( ($2 - 1) * 300 + 1 ))" "$1" > "$tmp/record.tmp" || fail "lettura del record $2 fallita"
  head -c 300 "$tmp/record.tmp" || fail "lettura del record $2 fallita"
}

log "1. passo rieseguito in una cartella nuova"
passo obs || { cat "$tmp/obs.log" >&2; fail "passo dati fallito"; }
indent "$tmp/obs.log" >&2
[ -f "$tmp/obs/out/ACCTFILE.dat" ] || fail "file indicizzato assente al percorso stabile"
[ ! -e "$tmp/obs/out/lavoro" ] || fail "cartella di lavoro rimasta dopo una corsa riuscita"
diff -u "$EXP/ACCTFILE.rapporto" "$tmp/obs/out/ACCTFILE.rapporto" > "$tmp/d" || { indent "$tmp/d" >&2; fail "rapporto diverso dall'atteso"; }
rileggi "$tmp/obs/out/ACCTFILE.dat" "$tmp/obs-ril" || { cat "$tmp/obs-ril.log" >&2; fail "rilettura indipendente fallita"; }
r=0; cmp "$tmp/obs-ril/rilettura.bin" "$REC" > "$tmp/d" 2>&1 || r=$?
[ "$r" -eq 0 ] || { indent "$tmp/d" >&2; fail "rilettura indipendente diversa dall'ingresso (cmp $r)"; }
log "   ok: 50 record caricati e riletti in ordine di chiave, identici a $(rel "$REC"); rapporto, programmi e ambienti come gli attesi"

log "2. organizzazione, chiave e lunghezza come nel SELECT e nell'FD di CBACT01C"
# dichiarazioni FILE INIZIO-SELECT INIZIO-FD: le righe significative del SELECT (organizzazione, accesso, chiave) e i
# campi 05 dell'FD del file, normalizzate (colonne 8-72, spazi compressi), senza commenti.
dichiarazioni() {
  awk -v S="$2" -v F="$3" '
    { ind = substr($0, 7, 1); l = substr($0, 8, 65); sub(/[ \t]+$/, "", l); gsub(/[ \t]+/, " ", l); sub(/^ /, "", l) }
    ind == "*" { next }
    index(l, S) == 1 { s = 1; next }
    s && l ~ /^(ORGANIZATION|ACCESS|RECORD KEY)/ { print "select: " l; next }
    s && l ~ /^FILE STATUS/ { s = 0; next }
    index(l, F) == 1 { f = 1; next }
    f == 1 && l ~ /^01 / { f = 2; next }
    f == 2 && l ~ /^05 / { print "fd: " l; next }
    f == 2 { f = 0 }' "$1"
}
# dich_cbact01c SORGENTE USCITA: le righe significative di CBACT01C, che devono essere 5 (3 del SELECT, 2 dell'FD): con
# meno righe (o nessuna) il confronto sotto sarebbe vuoto e passerebbe.
dich_cbact01c() {
  local n
  dichiarazioni "$1" "SELECT ACCTFILE-FILE " "FD ACCTFILE-FILE" > "$2" || { echo "lettura di CBACT01C fallita"; return 2; }
  n="$(wc -l < "$2")" || { echo "conteggio fallito"; return 2; }
  [ "$n" -eq 5 ] || { cat "$2"; echo "CBACT01C: attese 5 righe significative (3 del SELECT, 2 dell'FD), lette $n"; return 1; }
}
attese="$tmp/dich-cbact01c.txt"
dich_cbact01c "$LEGACY/app/cbl/CBACT01C.cbl" "$attese" > "$tmp/dc.out" 2>&1 || { cat "$tmp/dc.out" >&2; fail "dichiarazioni di CBACT01C non lette"; }
cp "$LEGACY/app/cbl/CBACT01C.cbl" "$tmp/CBACT01C-x.cbl" || fail "copia di CBACT01C fallita"
mutate "$tmp/CBACT01C-x.cbl" 's/SELECT ACCTFILE-FILE ASSIGN TO ACCTFILE/SELECT ALTRO-FILE ASSIGN TO ACCTFILE/'
expect_fail "SELECT di CBACT01C non trovato (estrazione incompleta)" "CBACT01C: attese 5 righe significative" \
  dich_cbact01c "$tmp/CBACT01C-x.cbl" "$tmp/dich-x.txt"
confronta_dich() { # confronta_dich SORGENTE NOME
  local r=0
  dichiarazioni "$1" "SELECT ACCT-FILE " "FD ACCT-FILE" > "$tmp/dich.txt" || { echo "lettura di $2 fallita"; return 1; }
  diff -u "$attese" "$tmp/dich.txt" > "$tmp/dich.diff" || r=$?
  case "$r" in
    0) echo "$2: SELECT/FD di ACCT-FILE come CBACT01C" ;;
    1) echo "$2: SELECT/FD di ACCT-FILE diversi da CBACT01C:"; indent "$tmp/dich.diff"; return 1 ;;
    *) echo "$2: confronto non eseguito (diff, codice $r)"; return 2 ;;
  esac
}
for p in IDXLOADF IDXDUMP; do
  confronta_dich "$ORACLE_ROOT/tests/$p.cbl" "$p" > "$tmp/c.out" 2>&1 || { cat "$tmp/c.out" >&2; fail "dichiarazioni di $p non conformi"; }
  indent "$tmp/c.out" >&2
done
sed 's/^/    CBACT01C /' "$attese" >&2 || fail "stampa fallita"
cp "$ORACLE_ROOT/tests/IDXLOADF.cbl" "$tmp/IDXLOADF-x.cbl" || fail "copia fallita"
mutate "$tmp/IDXLOADF-x.cbl" 's/05 FD-ACCT-ID                        PIC 9(11)\./05 FD-ACCT-ID                        PIC X(11)./'
expect_fail "chiave del caricatore PIC X(11) invece di 9(11)" "IDXLOADF: SELECT/FD di ACCT-FILE diversi da CBACT01C" confronta_dich "$tmp/IDXLOADF-x.cbl" IDXLOADF
cp "$ORACLE_ROOT/tests/IDXDUMP.cbl" "$tmp/IDXDUMP-x.cbl" || fail "copia fallita"
mutate "$tmp/IDXDUMP-x.cbl" '/SELECT ACCT-FILE ASSIGN TO ACCTFILE/,/FILE STATUS/s/ORGANIZATION IS INDEXED/ORGANIZATION IS RELATIVE/'
expect_fail "organizzazione della rilettura RELATIVE invece di INDEXED" "IDXDUMP: SELECT/FD di ACCT-FILE diversi da CBACT01C" confronta_dich "$tmp/IDXDUMP-x.cbl" IDXDUMP
cp "$ORACLE_ROOT/tests/IDXLOADF.cbl" "$tmp/IDXLOADF-y.cbl" || fail "copia fallita"
mutate "$tmp/IDXLOADF-y.cbl" 's/PIC X(289)\./PIC X(288)./'
expect_fail "record del caricatore di 299 byte" "IDXLOADF: SELECT/FD di ACCT-FILE diversi da CBACT01C" confronta_dich "$tmp/IDXLOADF-y.cbl" IDXLOADF

log "3. prove negative"
compila_variante() { # compila_variante ID SORGENTE PROGRAMMA: compilato davvero (compile.sh uno, opzioni della build)
  local n="$1" src="$2" prog="$3" c
  c="$(in_container "$src")" || fail "variante $n: sorgente fuori da oracle/"
  mkdir -p "$tmp/$n/build" || fail "variante $n: cartella non creata"
  orun -v "$tmp/$n/build:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh /oracle/build/compile.sh uno eseguibile "$c" "$prog" /out > "$tmp/$n.compila.log" 2>&1 \
    || { indent "$tmp/$n.compila.log" >&2; fail "compilazione della variante '$n' fallita"; }
  mkdir -p "$tmp/$n/bin" && cp "$BUILD_OUT"/bin/* "$tmp/$n/bin/" && cp "$tmp/$n/build/bin/$prog" "$tmp/$n/bin/$prog" \
    || fail "artefatti della variante '$n' non preparati"
}
head -c 14700 "$REC" > "$tmp/tolto.rec" || fail "ingresso senza l'ultimo record non preparato"
neg tolto "un record tolto da ACCTFILE.rec" "ACCTFILE: rapporto diverso dall'atteso" DATI_INGRESSO="$tmp/tolto.rec"
{ record "$REC" 1 && record "$REC" 3 && record "$REC" 2 && tail -c +901 "$REC"; } > "$tmp/scambio.rec" || fail "ingresso con record scambiati non preparato"
neg scambio "due record scambiati (chiave non crescente)" "IDXLOADF ACCTFILE ERRORE WRITE 21 DOPO IL RECORD 000002" DATI_INGRESSO="$tmp/scambio.rec"
{ record "$REC" 1 && record "$REC" 2 && record "$REC" 2 && tail -c +901 "$REC"; } > "$tmp/doppio.rec" || fail "ingresso con chiave duplicata non preparato"
neg doppio "una chiave duplicata" "IDXLOADF ACCTFILE ERRORE WRITE 21 DOPO IL RECORD 000002" DATI_INGRESSO="$tmp/doppio.rec"
cp "$REC" "$tmp/numerico.rec" && scrivi_byte "$tmp/numerico.rec" $((11 * 300 + 20)) "9" || fail "ingresso non preparato"
neg numerico "un byte alterato in un campo numerico (record 12, ACCT-CURR-BAL)" "ACCTFILE: rapporto diverso dall'atteso" DATI_INGRESSO="$tmp/numerico.rec"
cp "$REC" "$tmp/filler.rec" && scrivi_byte "$tmp/filler.rec" $((12 * 300 + 200)) "." || fail "ingresso non preparato"
neg filler "un byte alterato nel FILLER (record 13)" "ACCTFILE: rapporto diverso dall'atteso" DATI_INGRESSO="$tmp/filler.rec"
head -c 14850 "$REC" > "$tmp/tronco.rec" || fail "ingresso troncato non preparato"
neg tronco "file troncato a meta' record (14850 byte)" "IDXLOADF ENTRATA DI 14850 BYTE, NON MULTIPLA DI 0300" DATI_INGRESSO="$tmp/tronco.rec"
cp "$REC" "$tmp/zip.rec" && scrivi_byte "$tmp/zip.rec" $((48 * 300 + 102)) "A000000000" || fail "ingresso non preparato"
neg zip "differenza del record 49 annullata (ZIP ASCII al posto di quello EBCDIC)" "ACCTFILE: rapporto diverso dall'atteso" DATI_INGRESSO="$tmp/zip.rec"
# Record 25 di 299 byte: tolto l'ultimo spazio del FILLER. Il caricatore non deve riempirlo: 14999 byte, errore.
ultimo="$(record "$REC" 25)" || fail "lettura del record 25 fallita"
[ "${ultimo: -1}" = " " ] || fail "l'ultimo byte del record 25 non e' uno spazio"
{ head -c $((24 * 300 + 299)) "$REC" && tail -c +$((25 * 300 + 1)) "$REC"; } > "$tmp/r299.rec" || fail "ingresso con un record di 299 byte non preparato"
neg r299 "record di 299 byte (uno spazio finale del FILLER tolto): non riempito" "IDXLOADF ENTRATA DI 14999 BYTE, NON MULTIPLA DI 0300" DATI_INGRESSO="$tmp/r299.rec"
# Caricatore che esce con errore dopo aver caricato tutto (stessa riga di riuscita, poi codice 8).
cp "$ORACLE_ROOT/tests/IDXLOADF.cbl" "$tmp/IDXLOADF-esce8.cbl" || fail "copia fallita"
mutate "$tmp/IDXLOADF-esce8.cbl" "/DISPLAY 'IDXLOADF ' PARM-DD ' RECORD SCRITTI ' WS-SCRITTI/{n;s/MOVE 0 TO RETURN-CODE/MOVE 8 TO RETURN-CODE/;}"
compila_variante esce8 "$tmp/IDXLOADF-esce8.cbl" IDXLOADF
neg esce8 "il programma di caricamento esce con errore (8) dopo aver caricato" "IDXLOADF: codice di uscita 8, atteso 0" DATI_BIN_DIR="$tmp/esce8/bin"
# Rilettura che si ferma un record prima: dopo 49 record simula la fine del file (stato 10) ed esce con 0.
cp "$ORACLE_ROOT/tests/IDXDUMP.cbl" "$tmp/IDXDUMP-49.cbl" || fail "copia fallita"
mutate "$tmp/IDXDUMP-49.cbl" "s/^           PERFORM UNTIL IDX-STATUS NOT = '00'\$/           PERFORM UNTIL IDX-STATUS NOT = '00' OR WS-LETTI = 49/"
mutate "$tmp/IDXDUMP-49.cbl" "s/^           IF IDX-STATUS NOT = '10'\$/           MOVE '10' TO IDX-STATUS\\
           IF IDX-STATUS NOT = '10'/"
compila_variante ril49 "$tmp/IDXDUMP-49.cbl" IDXDUMP
neg ril49 "il programma di rilettura si ferma un record prima (ed esce con 0)" "rilettura diversa dall'ingresso" DATI_BIN_DIR="$tmp/ril49/bin"
riga="$(sed -n '4p' "$tmp/ril49/out/rilettura/IDXDUMP.txt")" || fail "rapporto della variante illeggibile"
[ "$riga" = "IDXDUMP ACCTFILE RECORD LETTI 000049" ] || fail "prova ril49: la variante non si e' fermata a 49 record ('$riga')"
log "   e la variante ha davvero riletto 49 record uscendo con 0"
# Rilettura che si ferma un record prima SENZA simulare la fine del file: IDXDUMP stesso pretende lo stato 10 dopo
# l'ultimo record ed esce con 8 (il controllo della fine del file e' nel programma, run.sh lo vede dal codice).
cp "$ORACLE_ROOT/tests/IDXDUMP.cbl" "$tmp/IDXDUMP-49s.cbl" || fail "copia fallita"
mutate "$tmp/IDXDUMP-49s.cbl" "s/^           PERFORM UNTIL IDX-STATUS NOT = '00'\$/           PERFORM UNTIL IDX-STATUS NOT = '00' OR WS-LETTI = 49/"
compila_variante ril49s "$tmp/IDXDUMP-49s.cbl" IDXDUMP
neg ril49s "la rilettura si ferma un record prima senza stato 10: IDXDUMP esce con 8" "IDXDUMP: codice di uscita 8, atteso 0" \
  DATI_BIN_DIR="$tmp/ril49s/bin"
riga="$(sed -n '4p' "$tmp/ril49s/out/rilettura/IDXDUMP.txt")" || fail "rapporto della variante illeggibile"
[ "$riga" = "IDXDUMP ACCTFILE ERRORE READ 00 DOPO IL RECORD 000049" ] || fail "prova ril49s: motivo inatteso ('$riga')"
log "   e IDXDUMP ha rifiutato la fine senza stato 10 ('$riga')"
# Stati del caricatore provocati direttamente (IDXLOADF della build con esegui.sh): ogni ramo d'errore esce con 8 e
# il suo messaggio. Non provocati qui: lettura con stato diverso da 00/10 e chiusure fallite (dichiarato nella PR).
carica_diretto() { # carica_diretto ID PARM DD...: IDXLOADF in $tmp/ID; stampa codice e stdout del rapporto
  local n="$1" parm="$2"; shift 2
  mkdir -p "$tmp/$n" || return 2
  cp "$REC" "$tmp/$n/ACCTFILE.rec" || return 2
  orun -v "$tmp/$n:/d" -v "$BUILD_OUT/bin:/oracle-bin:ro" -- timeout -k 10 120 sh /oracle/esegui.sh /d IDXLOADF \
    --parm "$parm" "$@" > "$tmp/$n.log" 2>&1 || { cat "$tmp/$n.log"; return 2; }
  local c
  sed -n '2,4p' "$tmp/$n/IDXLOADF.txt" || return 2
  c="$(sed -n 2p "$tmp/$n/IDXLOADF.txt")" || return 2
  [ "$c" = 0 ]
}
expect_fail "IDXLOADF: PARM sconosciuto" "IDXLOADF PARM SCONOSCIUTO: XREFFILE" \
  carica_diretto st1 XREFFILE --dd DD_ENTRATA=/d/ACCTFILE.rec --dd DD_ACCTFILE=/d/A.dat
expect_fail "IDXLOADF: DD_ENTRATA non impostata" "IDXLOADF DD_ENTRATA NON IMPOSTATA" \
  carica_diretto st2 ACCTFILE --dd DD_ACCTFILE=/d/A.dat
expect_fail "IDXLOADF: ingresso inesistente" "IDXLOADF ENTRATA ASSENTE: CBL_CHECK_FILE_EXIST" \
  carica_diretto st3 ACCTFILE --dd DD_ENTRATA=/d/NESSUNO.rec --dd DD_ACCTFILE=/d/A.dat
expect_fail "IDXLOADF: apertura del file indicizzato fallita (cartella inesistente)" "IDXLOADF ACCTFILE ERRORE OPEN" \
  carica_diretto st4 ACCTFILE --dd DD_ENTRATA=/d/ACCTFILE.rec --dd DD_ACCTFILE=/d/nessuna/A.dat
carica_diretto st5 ACCTFILE --dd DD_ENTRATA=/d/ACCTFILE.rec --dd DD_ACCTFILE=/d/A.dat > "$tmp/st5.out" 2>&1 \
  || { cat "$tmp/st5.out" >&2; fail "IDXLOADF diretto con ingressi validi fallito"; }
log "   controprova ok: IDXLOADF diretto con ingressi validi riesce ($(sed -n 3p "$tmp/st5.out"))"
# Attesi alterati, uno per prova.
k=0
for v in "ACCTFILE.rapporto|s/^record 50\$/record 51/|ACCTFILE: rapporto diverso dall'atteso" \
         "IDXLOADF.txt|s/RECORD SCRITTI 000050/RECORD SCRITTI 000051/|IDXLOADF: rapporto di esegui.sh diverso dall'atteso" \
         "IDXDUMP.txt|s/RECORD LETTI 000050/RECORD LETTI 000051/|IDXDUMP: rapporto di esegui.sh diverso dall'atteso" \
         "IDXLOADF.ambiente|s#^DD_ENTRATA=.*#DD_ENTRATA=/altro#|IDXLOADF: ambiente ricevuto diverso dall'atteso" \
         "IDXDUMP.ambiente|/^LC_ALL=C\$/d|IDXDUMP: ambiente ricevuto diverso dall'atteso"; do
  k=$((k + 1)); f="${v%%|*}"; resto="${v#*|}"; espr="${resto%%|*}"; ago="${resto#*|}"
  rm -rf "$tmp/att$k" && mkdir -p "$tmp/att$k" && cp "$EXP"/* "$tmp/att$k/" || fail "copia degli attesi fallita"
  mutate "$tmp/att$k/$f" "$espr"
  neg "natt$k" "atteso $f alterato" "$ago" DATI_ATTESI="$tmp/att$k"
done
rm -rf "$tmp/att-manca" && mkdir -p "$tmp/att-manca" && cp "$EXP"/* "$tmp/att-manca/" && rm "$tmp/att-manca/IDXDUMP.txt" \
  || fail "attesi senza IDXDUMP.txt non preparati"
neg nattm "atteso IDXDUMP.txt assente" "IDXDUMP: rapporto di esegui.sh: atteso assente" DATI_ATTESI="$tmp/att-manca"
cp -R "$BUILD_OUT" "$tmp/build-senza-impronta" && rm "$tmp/build-senza-impronta/IMPRONTA" || fail "build senza impronta non preparata"
neg nbuild "build senza impronta (interrotta o fallita)" "build assente o incompleta" ORACLE_BUILD_OUT="$tmp/build-senza-impronta"
neg ning "ingresso assente" "ingresso assente" DATI_INGRESSO="$tmp/nessuno.rec"

log "4. residui"
# (a) un file indicizzato DIVERSO rimasto da una corsa precedente (caricamento riuscito di 49 record, con attesi per
#     49 record), poi una corsa regolare nella stessa cartella: successo, e il file contiene i 50 record giusti.
rm -rf "$tmp/att49" && mkdir -p "$tmp/att49" && cp "$EXP"/* "$tmp/att49/" || fail "attesi per 49 record non preparati"
s49="$(orun -v "$tmp:/t:ro" -- timeout 60 sha256sum /t/tolto.rec)" || fail "impronta dell'ingresso di 49 record non calcolata"
s49="${s49%% *}"
[ "${#s49}" -eq 64 ] || fail "impronta non valida: '$s49'"
printf 'file ACCTFILE\nrecord 49\nbyte 14700\nprima chiave 00000000001\nultima chiave 00000000049\nsha256 rilettura %s\n' "$s49" \
  > "$tmp/att49/ACCTFILE.rapporto" || fail "rapporto atteso per 49 record non scritto"
mutate "$tmp/att49/IDXLOADF.txt" 's/RECORD SCRITTI 000050/RECORD SCRITTI 000049/'
mutate "$tmp/att49/IDXDUMP.txt" 's/RECORD LETTI 000050/RECORD LETTI 000049/'
passo resa DATI_INGRESSO="$tmp/tolto.rec" DATI_ATTESI="$tmp/att49" || { cat "$tmp/resa.log" >&2; fail "residuo (a): corsa di 49 record non riuscita"; }
rileggi "$tmp/resa/out/ACCTFILE.dat" "$tmp/resa-prima" || fail "residuo (a): rilettura del residuo fallita"
n="$(wc -c < "$tmp/resa-prima/rilettura.bin")" || fail "dimensione illeggibile"
[ "$n" -eq 14700 ] || fail "residuo (a): il residuo non ha 49 record ($n byte)"
passo resa || { cat "$tmp/resa.log" >&2; fail "PROVA NEGATIVA FALLITA (residuo a): con un residuo diverso la corsa regolare fallisce"; }
rileggi "$tmp/resa/out/ACCTFILE.dat" "$tmp/resa-dopo" || fail "residuo (a): rilettura dopo la corsa regolare fallita"
r=0; cmp -s "$tmp/resa-dopo/rilettura.bin" "$REC" || r=$?
[ "$r" -eq 0 ] || fail "PROVA NEGATIVA FALLITA (residuo a): dopo la corsa regolare il file non contiene ACCTFILE.rec (cmp $r)"
log "   controprova ok: residuo (a): file di 49 record rimasto, corsa regolare riuscita, ora 50 record identici all'ingresso"
# (b) un file indicizzato SANO rimasto (corsa riuscita), poi un caricamento che fallisce nella stessa cartella: errore,
#     nessun file utilizzabile al percorso stabile ne' nella cartella di lavoro.
passo resb || { cat "$tmp/resb.log" >&2; fail "residuo (b): corsa sana non riuscita"; }
[ -f "$tmp/resb/out/ACCTFILE.dat" ] || fail "residuo (b): file sano assente"
neg resb "residuo (b): file sano rimasto e caricamento che fallisce" "IDXLOADF ACCTFILE ERRORE WRITE 21" DATI_INGRESSO="$tmp/scambio.rec"
log "   e non resta alcun file indicizzato (ne' al percorso stabile ne' nella cartella di lavoro)"
# Prova negativa del controllo "nessun file rimasto": una copia di run.sh senza la pulizia nella trap lascia la
# cartella di lavoro (con il file indicizzato parziale) dopo un caricamento fallito, e pulita se ne accorge.
cp "$DIR/run.sh" "$tmp/run-senza-pulizia.sh" || fail "copia di run.sh fallita"
mutate "$tmp/run-senza-pulizia.sh" 's#rm -rf "$out/lavoro" "$out/ACCTFILE.dat" "$out/ACCTFILE.rapporto"#true#'
mkdir -p "$tmp/npul" || fail "cartella non creata"
r=0; env DATI_OUT_DIR="$tmp/npul/out" DATI_INGRESSO="$tmp/scambio.rec" bash "$tmp/run-senza-pulizia.sh" > "$tmp/npul.log" 2>&1 || r=$?
[ "$r" -ne 0 ] || fail "la copia di run.sh senza pulizia non e' fallita con l'ingresso scambiato"
[ -f "$tmp/npul/out/lavoro/ACCTFILE.dat" ] || fail "la copia di run.sh senza pulizia non ha lasciato il file di lavoro"
expect_fail "run.sh senza la pulizia dopo un fallimento: file indicizzato parziale rimasto" "resta la cartella di lavoro" pulita "$tmp/npul/out"

log "5. presenza del passo nel controllo di build/check.sh"
# PASSI e passi_presenti presi dal testo di build/check.sh (non ricopiati): e' il controllo vero che si prova.
{ sed -n '/^PASSI=/p' "$ORACLE_ROOT/build/check.sh" && sed -n '/^passi_presenti() {$/,/^}$/p' "$ORACLE_ROOT/build/check.sh"; } \
  > "$tmp/passi.sh" || fail "estrazione del controllo dei passi fallita"
r=0; grep -q '^PASSI=".* dati:build .*"$' "$tmp/passi.sh" || r=$?
[ "$r" -eq 0 ] || fail "PASSI di build/check.sh non contiene dati:build (grep $r)"
r=0; grep -q '^passi_presenti() {$' "$tmp/passi.sh" || r=$?
[ "$r" -eq 0 ] || fail "passi_presenti non trovata in build/check.sh (grep $r)"
( . "$tmp/passi.sh" && passi_presenti "$ORACLE_ROOT" ) > "$tmp/p.out" 2>&1 || { cat "$tmp/p.out" >&2; fail "controllo dei passi fallito sull'oracle vero"; }
# Copia della struttura dei passi (ogni cartella di oracle/ con i suoi run.sh, check.sh, deps), poi dati/ cancellata.
mkdir -p "$tmp/radice" || fail "radice di prova non creata"
for d in "$ORACLE_ROOT"/*/; do
  b="${d%/}"; b="${b##*/}"
  mkdir -p "$tmp/radice/$b" || fail "cartella $b non creata"
  for f in run.sh check.sh deps; do [ ! -f "$d$f" ] || cp "$d$f" "$tmp/radice/$b/" || fail "copia di $b/$f fallita"; done
done
( . "$tmp/passi.sh" && passi_presenti "$tmp/radice" ) > /dev/null 2>&1 || fail "controllo dei passi fallito sulla copia integra"
rm -rf "$tmp/radice/dati" && [ ! -e "$tmp/radice/dati" ] || fail "cancellazione di dati/ nella copia fallita"
expect_fail "cartella oracle/dati/ cancellata (controllo dei passi di build/check.sh)" "passo dati: manca check.sh" \
  bash -c '. "$1" && passi_presenti "$2"' sh "$tmp/passi.sh" "$tmp/radice"

log "6. esiti dei comandi"
# 6a. carica.sh: build/avvolgi.sh davanti nel PATH del container; registro nella cartella d'uscita (/out/registro).
W="$tmp/wrap"; mkdir -p "$W" || fail "cartella degli involucri non creata"
cp "$ORACLE_ROOT/build/avvolgi.sh" "$W/.avvolgi.sh" || fail "copia di avvolgi.sh fallita"
w_c="$(in_container "$W")" || fail "involucri fuori da oracle/"
COMANDI="sed wc cmp mkdir head tail sha256sum rm"
for c in $COMANDI; do
  printf '#!/bin/sh\nm="${DATI_MODO_%s:-passa}"\ncase "$m" in rumore) echo "x?"; exit 0 ;; attesa) /usr/bin/sleep 30; m=passa ;; esac\nexec /usr/bin/sh %s/.avvolgi.sh /out/registro %s "$m" /usr/bin/%s "$@"\n' \
    "$c" "$w_c" "$c" "$c" > "$W/$c" || fail "involucro di $c non scritto"
  chmod +x "$W/$c" || fail "involucro di $c non eseguibile"
done
WPATH="PATH=$w_c:/usr/bin:/bin"
passo invp DATI_DOCKER_EXTRA="-e $WPATH" || { cat "$tmp/invp.log" >&2; fail "carica.sh con gli involucri in modo passa fallito"; }
reg="$tmp/invp/out/registro"
[ -f "$reg" ] || fail "registro degli involucri assente"
log "   controprova ok: carica.sh con gli involucri in modo passa riesce; invocazioni:$(awk '{ n[$1]++ } END { for (c in n) printf " %s=%d", c, n[c] }' "$reg")"
# motivo COMANDO INVOCAZIONE: il messaggio di carica.sh che deve comparire quando quell'invocazione fallisce
motivo() {
  case "$1@$2" in
    sed@*) echo "rapporto illeggibile" ;;
    wc@*) echo "(wc)" ;;
    cmp@1) echo "confronto non eseguito (cmp, codice 42)" ;;
    mkdir@1) echo "cartelle non creabili" ;;
    head@1) echo "prima chiave illeggibile (head)" ;;
    head@2) echo "ultima chiave illeggibile (head)" ;;
    tail@1) echo "ultimo record illeggibile (tail)" ;;
    sha256sum@1) echo "impronta della rilettura non calcolabile (sha256sum)" ;;
    rm@1) echo "temporanei non rimovibili (rm)" ;;
    *) return 1 ;;
  esac
}
for c in $COMANDI; do
  tot="$(awk -v c="$c" '$1 == c { n++ } END { print n + 0 }' "$reg")" || fail "registro illeggibile"
  [ "$tot" -gt 0 ] || fail "il comando $c non e' mai invocato da carica.sh: elenco COMANDI da rivedere"
  i=1
  while [ "$i" -le "$tot" ]; do
    ago="$(motivo "$c" "$i")" || fail "invocazione $c@$i senza motivo atteso: elenco da rivedere"
    neg "inv-$c-$i" "carica.sh: $c, invocazione $i di $tot, esce con 42 dopo il suo lavoro" "$ago" \
      DATI_DOCKER_EXTRA="-e $WPATH -e DATI_MODO_$c=42@$i"
    r=0; awk -v c="$c" -v i="$i" '$1 == c && $2 == i && ($3 == 0 || $3 == 1) && $4 == 42 { t = 1 } END { exit !t }' \
      "$tmp/inv-$c-$i/out/registro" || r=$?
    [ "$r" -eq 0 ] || fail "carica.sh, $c@$i: il comando non e' stato raggiunto con il suo esito reale"
    i=$((i + 1))
  done
done
for v in "sed|codice di uscita non numerico" "wc|risposta di wc non numerica" "head|chiave non di 11 cifre" \
         "sha256sum|impronta non valida"; do
  c="${v%%|*}"
  neg "rum-$c" "carica.sh: $c risponde in modo malformato con esito 0" "${v#*|}" DATI_DOCKER_EXTRA="-e $WPATH -e DATI_MODO_$c=rumore"
done
printf '#!/bin/sh\nsh /oracle/esegui.sh "$@"\nexit 42\n' > "$W/esegui42.sh" || fail "esegui42.sh non scritto"
neg esegui42 "carica.sh: esegui.sh esce con 42 dopo il suo lavoro" "esecuzione di IDXLOADF fallita (esegui.sh)" \
  DATI_DOCKER_EXTRA="-e CARICA_ESEGUI=$w_c/esegui42.sh"
neg attesa "carica.sh oltre il limite di tempo (cmp che attende 30 s, limite 3 s)" "carica.sh non e' terminato entro 3s" \
  DATI_TIMEOUT=3 DATI_DOCKER_EXTRA="-e $WPATH -e DATI_MODO_cmp=attesa"
# 6b. run.sh sull'host: build/avvolgi.sh davanti nel PATH dell'host; registro $tmp/reg-host.
H="$tmp/hostwrap"; mkdir -p "$H" || fail "cartella degli involucri sull'host non creata"
for c in cp mv diff cmp rm docker; do
  vero="$(command -v "$c")" || fail "$c non trovato sull'host"
  printf '#!/bin/sh\nexec sh \047%s\047 \047%s\047 %s "${DATI_MODO_%s:-passa}" \047%s\047 "$@"\n' \
    "$ORACLE_ROOT/build/avvolgi.sh" "$tmp/reg-host" "$c" "$c" "$vero" > "$H/$c" || fail "involucro di $c non scritto"
  chmod +x "$H/$c" || fail "involucro di $c non eseguibile"
done
rm -f "$tmp/reg-host"
passo hostp PATH="$H:$PATH" || { cat "$tmp/hostp.log" >&2; fail "run.sh con gli involucri sull'host in modo passa fallito"; }
cp "$tmp/reg-host" "$tmp/reg-host-passa" || fail "registro di riferimento non copiato"
conta="$(awk '{ n[$1]++ } END { printf "cp=%d mv=%d diff=%d cmp=%d rm=%d", n["cp"], n["mv"], n["diff"], n["cmp"], n["rm"] }' "$tmp/reg-host-passa")" \
  || fail "registro illeggibile"
# Attese: cp 1 (ingresso privato); mv 3 (file indicizzato, rapporto, rilettura); diff 5 (attesi); cmp 1 (rilettura dal
# percorso stabile); rm 3 (clean_dir, cartella di lavoro, temporanei nella trap).
[ "$conta" = "cp=1 mv=3 diff=5 cmp=1 rm=3" ] || fail "run.sh: invocazioni sull'host diverse da quelle attese: $conta"
log "   controprova ok: run.sh con gli involucri sull'host in modo passa riesce ($conta)"
for v in "cp@1|copia privata dell'ingresso fallita" "mv@1|file indicizzato non spostato al percorso stabile" \
         "mv@2|rapporto non spostato" "mv@3|rilettura non spostata" "diff@1|ACCTFILE: rapporto: confronto non eseguito (diff, codice 42)" \
         "diff@2|IDXLOADF: rapporto di esegui.sh: confronto non eseguito" "diff@3|IDXDUMP: rapporto di esegui.sh: confronto non eseguito" \
         "diff@4|IDXLOADF: ambiente ricevuto: confronto non eseguito" "diff@5|IDXDUMP: ambiente ricevuto: confronto non eseguito" \
         "cmp@1|rilettura dal percorso stabile: confronto non eseguito (cmp, codice 42)" "rm@1|impossibile cancellare" \
         "rm@2|cartella di lavoro non rimossa"; do
  m="${v%%|*}"; c="${m%@*}"; i="${m#*@}"
  rm -f "$tmp/reg-host"
  neg "host-$c-$i" "run.sh: $c, invocazione $i, esce con 42 dopo il suo lavoro" "${v#*|}" PATH="$H:$PATH" "DATI_MODO_$c=42@$i"
  r=0; awk -v c="$c" -v i="$i" '$1 == c && $2 == i && $4 == 42 { t = 1 } END { exit !t }' "$tmp/reg-host" || r=$?
  [ "$r" -eq 0 ] || fail "run.sh, $c@$i: il comando non e' stato raggiunto"
done
neg host-docker1 "run.sh: docker del container di carica.sh esce con 42 dopo il suo lavoro" "carica.sh fallito (uscita 42)" \
  PATH="$H:$PATH" DATI_MODO_docker=42:/oracle/dati/carica.sh
st="$(in_container "$tmp/host-docker2/out")" || fail "percorso fuori da oracle/"
neg host-docker2 "run.sh: docker della rilettura dal percorso stabile esce con 42 dopo il suo lavoro" \
  "rilettura dal percorso stabile non eseguita (uscita 42)" PATH="$H:$PATH" "DATI_MODO_docker=42:$st"
log "controllo superato"
