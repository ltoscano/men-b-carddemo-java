#!/usr/bin/env bash
# Controllo del passo dati (issue #53): il file dei conti nell'oracle.
# 1. Passo rieseguito da zero in una cartella nuova (run.sh): caricamento con IDXLOADF, lettura indipendente con
#    IDXLEGGI (sequenziale e per chiave), rilettura con IDXDUMP, letture identiche fra loro e all'ingresso, rapporto,
#    rapporti di esegui.sh e ambienti identici agli attesi, ultima verifica in sola lettura, pubblicazione; poi una
#    lettura con IDXLEGGI indipendente da run.sh.
# 2. Organizzazione, chiave e lunghezza del file nei programmi di prova (IDXLOADF, IDXLEGGI, IDXDUMP) uguali al
#    SELECT e all'FD di CBACT01C (app/cbl/CBACT01C.cbl, righe 29-33 e 52-56), letti dal sorgente.
# 3. Prove negative della specifica e dei controlli propri, ciascuna con il motivo atteso (expect_fail di lib.sh) e,
#    dopo ogni fallimento, nessun file indicizzato rimasto: ingresso alterato (record tolto, record scambiati, chiave
#    duplicata, byte numerico e del FILLER, troncato a meta' record, ZIP ASCII, record di 299 byte), programmi
#    alterati e ricompilati (caricatore che esce con errore o che altera il FILLER, rilettura che si ferma un record
#    prima, lettori finti che copiano l'ingresso, da soli e combinati), attesi alterati, build assente, ingresso assente.
# 4. Residui: un file sano rimasto e ogni errore della preparazione (percorso stabile vuoto); un file indicizzato
#    diverso rimasto e una corsa regolare (successo, contenuto corretto); un file sano rimasto e un caricamento che
#    fallisce (errore, nessun file utilizzabile).
# 5. Presenza del passo: la cartella oracle/dati/ cancellata e' vista dal controllo dei passi di build/check.sh.
# 6. Esiti dei comandi: carica.sh (build/avvolgi.sh davanti nel PATH del container: ogni invocazione di ogni comando
#    con esito 42 dopo il suo lavoro; risposte malformate con esito 0; esegui.sh che esce con 42; limite di tempo) e
#    run.sh (cp, mv, diff, cmp, rm e i due docker sull'host); momento della pubblicazione (mai prima dell'ultima
#    verifica); cmp e wc degli aiuti delle prove con esito 42.
. "$ORACLE_ROOT/lib.sh"

DIR="$ORACLE_ROOT/dati"
EXP="$DIR/expected"
REC="$REPO_ROOT/analysis/oracle-dati/out/ACCTFILE.rec"
tmp="$(mktmp)" || exit 1
# Il fallimento della pulizia dei temporanei e' un errore e cambia l'esito (giro 1 della PR #58).
trap 'rm -rf "$tmp" || { log "ERRORE: temporanei non rimossi: $(rel "$tmp")"; exit 1; }' EXIT
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
# pulita CARTELLA-D'USCITA: nessun file indicizzato (ne' al percorso stabile ne' in verifica ne' nella cartella di lavoro)
pulita() {
  [ ! -e "$1/ACCTFILE.dat" ] || { echo "resta un file indicizzato al percorso stabile: $(rel "$1")/ACCTFILE.dat"; return 1; }
  [ ! -e "$1/ACCTFILE.dat.verifica" ] || { echo "resta il file indicizzato in verifica: $(rel "$1")/ACCTFILE.dat.verifica"; return 1; }
  [ ! -e "$1/lavoro" ] || { echo "resta la cartella di lavoro: $(rel "$1")/lavoro"; return 1; }
}
# neg ID DESCRIZIONE SOTTOSTRINGA [VAR=VALORE ...]: run.sh deve fallire per quel motivo; dopo, nessun file indicizzato.
neg() {
  local n="$1" d="$2" ago="$3"; shift 3
  mkdir -p "$tmp/$n" || fail "cartella di '$n' non creata"
  expect_fail "$d" "$ago" env DATI_OUT_DIR="$tmp/$n/out" "$@" bash "$DIR/run.sh"
  pulita "$tmp/$n/out" > "$tmp/$n.pulita" 2>&1 || { cat "$tmp/$n.pulita" >&2; fail "PROVA NEGATIVA FALLITA ($d): dopo il fallimento"; }
}
# rileggi FILE-INDICIZZATO DEST: IDXLEGGI della build (il lettore indipendente) legge il file in DEST/rilettura.bin,
# indipendentemente da run.sh; ritorna 0 solo se IDXLEGGI termina con 0.
rileggi() {
  local f d c
  f="$(in_container "$1")" && d="$(in_container "$2")" || return 1
  mkdir -p "$2" || return 1
  orun -v "$BUILD_OUT/bin:/oracle-bin:ro" -v "$2:/ril" -- timeout -k 10 120 sh /oracle/esegui.sh /ril IDXLEGGI \
    --parm ACCTFILE --dd "DD_ACCTFILE=$f" --dd "DD_LETTURA=/ril/rilettura.bin" --dd "DD_CHIAVI=/ril/chiavi.bin" \
    > "$2.log" 2>&1 || return 1
  c="$(sed -n 2p "$2/IDXLEGGI.txt")" || return 1
  [ "$c" = 0 ]
}
# alterato ORIGINALE ALTERATO: l'alterazione ha cambiato il file. cmp distinto: 0 (nessuna alterazione: errore della
# prova), 1 (alterato), altro (errore operativo, mai preso per "alterato": giro 1 della PR #58).
alterato() {
  local r=0
  cmp -s "$1" "$2" || r=$?
  case "$r" in
    1) ;;
    0) fail "alterazione di $(rel "$1") senza effetto" ;;
    *) fail "alterazione di $(rel "$1"): confronto non eseguito (cmp, codice $r)" ;;
  esac
}
# scrivi_byte FILE POSIZIONE TESTO: sostituisce i byte da POSIZIONE (da 0), dimensione invariata, alterazione verificata
scrivi_byte() {
  local f="$1" p="$2" s="$3" n m
  n="$(wc -c < "$f")" || fail "dimensione di $f illeggibile"
  { head -c "$p" "$f" && printf '%s' "$s" && tail -c "+$((p + ${#s} + 1))" "$f"; } > "$f.nuovo" || fail "alterazione di $f fallita"
  alterato "$f" "$f.nuovo"
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
log "   ok: 50 record caricati, letti da IDXLEGGI e IDXDUMP in ordine di chiave, identici a $(rel "$REC"); rapporto, programmi e ambienti come gli attesi; riletti in modo indipendente da qui con IDXLEGGI"
# Esiti degli strumenti delle prove (giro 1 della PR #58): cmp e wc che fanno il loro lavoro e poi escono con 42.
cp "$REC" "$tmp/aiuto.rec" || fail "copia fallita"
expect_fail "alterato: cmp che confronta e poi esce con 42 (non e' un'alterazione)" "confronto non eseguito (cmp, codice 42)" \
  bash -c '. "$ORACLE_ROOT/lib.sh"; cmp() { command cmp "$@"; return 42; }; '"$(declare -f alterato)"'; alterato "$1" "$1"' sh "$tmp/aiuto.rec"
expect_fail "scrivi_byte: wc che conta e poi esce con 42" "dimensione di" \
  bash -c '. "$ORACLE_ROOT/lib.sh"; wc() { command wc "$@"; return 42; }; '"$(declare -f alterato scrivi_byte)"'; scrivi_byte "$1" 10 X' sh "$tmp/aiuto.rec"
expect_fail "scrivi_byte: cmp che confronta e poi esce con 42" "confronto non eseguito (cmp, codice 42)" \
  bash -c '. "$ORACLE_ROOT/lib.sh"; cmp() { command cmp "$@"; return 42; }; '"$(declare -f alterato scrivi_byte)"'; scrivi_byte "$1" 10 X' sh "$tmp/aiuto.rec"

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
for p in IDXLOADF IDXLEGGI IDXDUMP; do
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
cp "$ORACLE_ROOT/tests/IDXLEGGI.cbl" "$tmp/IDXLEGGI-x.cbl" || fail "copia fallita"
mutate "$tmp/IDXLEGGI-x.cbl" 's/RECORD KEY   IS FD-ACCT-ID/RECORD KEY   IS FD-ACCT-DATA/'
expect_fail "lettore indipendente con un'altra chiave" "IDXLEGGI: SELECT/FD di ACCT-FILE diversi da CBACT01C" confronta_dich "$tmp/IDXLEGGI-x.cbl" IDXLEGGI

log "3. prove negative"
compila_variante() { # compila_variante ID SORGENTE PROGRAMMA [ARTEFATTI-DI-BASE]: compilato davvero (compile.sh uno,
  # opzioni della build) e messo in una copia degli artefatti (della build, o di un'altra variante per combinarle)
  local n="$1" src="$2" prog="$3" base="${4:-$BUILD_OUT/bin}" c
  c="$(in_container "$src")" || fail "variante $n: sorgente fuori da oracle/"
  mkdir -p "$tmp/$n/build" || fail "variante $n: cartella non creata"
  orun -v "$tmp/$n/build:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh /oracle/build/compile.sh uno eseguibile "$c" "$prog" /out > "$tmp/$n.compila.log" 2>&1 \
    || { indent "$tmp/$n.compila.log" >&2; fail "compilazione della variante '$n' fallita"; }
  mkdir -p "$tmp/$n/bin" && cp "$base"/* "$tmp/$n/bin/" && cp "$tmp/$n/build/bin/$prog" "$tmp/$n/bin/$prog" \
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
neg ril49 "il programma di rilettura si ferma un record prima (ed esce con 0)" "rilettura di IDXDUMP diversa dall'ingresso" DATI_BIN_DIR="$tmp/ril49/bin"
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
# Controesempio del Validatore (giro 1 della PR #58), sostituzioni singole e combinate:
#   A  caricatore che altera un byte del FILLER prima di scrivere (MOVE '.' TO ENT-REC (181:1));
#   B  IDXDUMP finto che non legge l'indice ma copia l'ingresso (/in/ACCTFILE.rec) nella sua uscita, stessa riga, 0;
#   C  IDXLEGGI finto che fa lo stesso (copia l'ingresso e i suoi record 1, 25, 49), stesse righe, 0.
# Basta un lettore onesto: A da sola e' vista da entrambi, A+B da IDXLEGGI, A+C da IDXDUMP. B da sola con un
# caricatore corretto non altera il risultato: e' una controprova (passo riuscito, file pubblicato corretto). C da sola
# non e' provata a parte: il lettore finto non trova /in nella lettura finale in sola lettura e fallirebbe per quello.
cp "$ORACLE_ROOT/tests/IDXLOADF.cbl" "$tmp/IDXLOADF-A.cbl" || fail "copia fallita"
mutate "$tmp/IDXLOADF-A.cbl" "s/^           WRITE FD-ACCTFILE-REC FROM ENT-REC\$/           MOVE '.' TO ENT-REC (181:1)\\
           WRITE FD-ACCTFILE-REC FROM ENT-REC/"
compila_variante varA "$tmp/IDXLOADF-A.cbl" IDXLOADF
# Lettori finti (sorgenti COBOL scritti qui): copiano /in/ACCTFILE.rec invece di leggere il file indicizzato.
cat > "$tmp/IDXDUMP-B.cbl" <<'FINE' || fail "sorgente del lettore finto IDXDUMP non scritto"
       IDENTIFICATION DIVISION.
       PROGRAM-ID. IDXDUMP.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT FINGRESSO ASSIGN TO '/in/ACCTFILE.rec'
                  ORGANIZATION IS SEQUENTIAL.
           SELECT FUSCITA ASSIGN TO USCITA
                  ORGANIZATION IS SEQUENTIAL.
       DATA DIVISION.
       FILE SECTION.
       FD  FINGRESSO RECORDING MODE IS F.
       01  RINGRESSO              PIC X(300).
       FD  FUSCITA RECORDING MODE IS F.
       01  RUSCITA                PIC X(300).
       WORKING-STORAGE SECTION.
       01  NREC                   PIC 9(06) VALUE 0.
       01  FINITO                 PIC X VALUE 'N'.
       PROCEDURE DIVISION.
           OPEN INPUT FINGRESSO OUTPUT FUSCITA
           PERFORM UNTIL FINITO = 'S'
             READ FINGRESSO
               AT END MOVE 'S' TO FINITO
               NOT AT END
                 ADD 1 TO NREC
                 WRITE RUSCITA FROM RINGRESSO
             END-READ
           END-PERFORM
           DISPLAY 'IDXDUMP ACCTFILE RECORD LETTI ' NREC
           CLOSE FINGRESSO FUSCITA
           MOVE 0 TO RETURN-CODE
           GOBACK.
FINE
cat > "$tmp/IDXLEGGI-C.cbl" <<'FINE' || fail "sorgente del lettore finto IDXLEGGI non scritto"
       IDENTIFICATION DIVISION.
       PROGRAM-ID. IDXLEGGI.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT FINGRESSO ASSIGN TO '/in/ACCTFILE.rec'
                  ORGANIZATION IS SEQUENTIAL.
           SELECT FLETTURA ASSIGN TO LETTURA
                  ORGANIZATION IS SEQUENTIAL.
           SELECT FCHIAVI ASSIGN TO CHIAVI
                  ORGANIZATION IS SEQUENTIAL.
       DATA DIVISION.
       FILE SECTION.
       FD  FINGRESSO RECORDING MODE IS F.
       01  RINGRESSO              PIC X(300).
       FD  FLETTURA RECORDING MODE IS F.
       01  RLETTURA               PIC X(300).
       FD  FCHIAVI RECORDING MODE IS F.
       01  RCHIAVI                PIC X(300).
       WORKING-STORAGE SECTION.
       01  NREC                   PIC 9(06) VALUE 0.
       01  FINITO                 PIC X VALUE 'N'.
       PROCEDURE DIVISION.
           OPEN INPUT FINGRESSO OUTPUT FLETTURA FCHIAVI
           PERFORM UNTIL FINITO = 'S'
             READ FINGRESSO
               AT END MOVE 'S' TO FINITO
               NOT AT END
                 ADD 1 TO NREC
                 WRITE RLETTURA FROM RINGRESSO
                 IF NREC = 1 OR NREC = 25 OR NREC = 49
                   WRITE RCHIAVI FROM RINGRESSO
                 END-IF
             END-READ
           END-PERFORM
           DISPLAY 'IDXLEGGI ACCTFILE RECORD LETTI ' NREC
                   ', FINE CON STATO 10'
           DISPLAY 'IDXLEGGI ACCTFILE CHIAVE ' '00000000001'
                   ' START 00 READ 00'
           DISPLAY 'IDXLEGGI ACCTFILE CHIAVE ' '00000000025'
                   ' START 00 READ 00'
           DISPLAY 'IDXLEGGI ACCTFILE CHIAVE ' '00000000049'
                   ' START 00 READ 00'
           CLOSE FINGRESSO FLETTURA FCHIAVI
           MOVE 0 TO RETURN-CODE
           GOBACK.
FINE
compila_variante varB "$tmp/IDXDUMP-B.cbl" IDXDUMP
compila_variante varAB "$tmp/IDXDUMP-B.cbl" IDXDUMP "$tmp/varA/bin"
compila_variante varAC "$tmp/IDXLEGGI-C.cbl" IDXLEGGI "$tmp/varA/bin"
neg varA "A: caricatore che altera un byte del FILLER" "lettura indipendente (IDXLEGGI, 15000 byte) diversa dall'ingresso" \
  DATI_BIN_DIR="$tmp/varA/bin"
neg varAB "A+B: caricatore che altera il FILLER e IDXDUMP che copia l'ingresso" \
  "lettura indipendente (IDXLEGGI, 15000 byte) diversa dall'ingresso" DATI_BIN_DIR="$tmp/varAB/bin"
neg varAC "A+C: caricatore che altera il FILLER e IDXLEGGI che copia l'ingresso" \
  "rilettura di IDXDUMP diversa dall'ingresso" DATI_BIN_DIR="$tmp/varAC/bin"
# Letture per chiave: IDXLEGGI che posiziona sempre sulla chiave 2 (D), prima con il suo controllo della chiave letta
# (esce con 8), poi anche senza quel controllo (E: lo vede il confronto di carica.sh con i record dell'ingresso).
cp "$ORACLE_ROOT/tests/IDXLEGGI.cbl" "$tmp/IDXLEGGI-D.cbl" || fail "copia fallita"
mutate "$tmp/IDXLEGGI-D.cbl" "s/^               MOVE CHIAVE-CHIESTA TO FD-ACCTFILE-REC (1:11)\$/               MOVE '00000000002' TO FD-ACCTFILE-REC (1:11)/"
compila_variante varD "$tmp/IDXLEGGI-D.cbl" IDXLEGGI
neg varD "D: lettura per chiave posizionata su un'altra chiave: IDXLEGGI se ne accorge" "IDXLEGGI: codice di uscita 8, atteso 0" \
  DATI_BIN_DIR="$tmp/varD/bin"
cp "$tmp/IDXLEGGI-D.cbl" "$tmp/IDXLEGGI-E.cbl" || fail "copia fallita"
mutate "$tmp/IDXLEGGI-E.cbl" "s/^               IF FD-ACCTFILE-REC (1:11) NOT = CHIAVE-CHIESTA\$/               IF FD-ACCTFILE-REC (1:11) = SPACES/"
compila_variante varE "$tmp/IDXLEGGI-E.cbl" IDXLEGGI
neg varE "E: come D, senza il controllo della chiave letta: lo vede il confronto con l'ingresso" \
  "lettura per chiave 00000000001 diversa dal record 1 dell'ingresso" DATI_BIN_DIR="$tmp/varE/bin"
for v in varB; do
  passo "$v-ok" DATI_BIN_DIR="$tmp/$v/bin" || { cat "$tmp/$v-ok.log" >&2; fail "controprova $v: il passo con il solo lettore finto e un caricatore corretto non riesce"; }
  rileggi "$tmp/$v-ok/out/ACCTFILE.dat" "$tmp/$v-ok-ril" || fail "controprova $v: lettura indipendente fallita"
  r=0; cmp -s "$tmp/$v-ok-ril/rilettura.bin" "$REC" || r=$?
  [ "$r" -eq 0 ] || fail "controprova $v: il file pubblicato non contiene ACCTFILE.rec (cmp $r)"
  log "   controprova ok: $v da sola (lettore finto, caricatore corretto): il passo riesce e il file pubblicato e' corretto"
done
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
         "IDXDUMP.ambiente|/^LC_ALL=C\$/d|IDXDUMP: ambiente ricevuto diverso dall'atteso" \
         "IDXLEGGI.txt|s/CHIAVE 00000000025 START/CHIAVE 00000000026 START/|IDXLEGGI: rapporto di esegui.sh diverso dall'atteso" \
         "IDXLEGGI.ambiente|s#^DD_CHIAVI=.*#DD_CHIAVI=/altro#|IDXLEGGI: ambiente ricevuto diverso dall'atteso"; do
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
# (0) Risultato precedente invalidato come primo atto (giro 1 della PR #58): con un file SANO di una corsa riuscita al
#     percorso stabile, ogni errore della preparazione deve lasciare il percorso stabile vuoto.
passo sano || { cat "$tmp/sano.log" >&2; fail "corsa sana per i residui non riuscita"; }
[ -f "$tmp/sano/out/ACCTFILE.dat" ] || fail "corsa sana senza file indicizzato"
mkdir -p "$tmp/bin-senza-lettore" && cp "$BUILD_OUT"/bin/* "$tmp/bin-senza-lettore/" && rm "$tmp/bin-senza-lettore/IDXLEGGI" \
  || fail "artefatti senza IDXLEGGI non preparati"
for v in "pre-ingresso|ingresso assente|DATI_INGRESSO=$tmp/nessuno.rec" \
         "pre-attesi|attesi assenti|DATI_ATTESI=$tmp/nessuna-cartella" \
         "pre-build|build assente o incompleta|ORACLE_BUILD_OUT=$tmp/build-senza-impronta" \
         "pre-binario|IDXLEGGI assente in|DATI_BIN_DIR=$tmp/bin-senza-lettore" \
         "pre-limite|DATI_TIMEOUT non valido|DATI_TIMEOUT=tre"; do
  n="${v%%|*}"; resto="${v#*|}"; ago="${resto%%|*}"; var="${resto#*|}"
  rm -rf "$tmp/$n" && mkdir -p "$tmp/$n" && cp -R "$tmp/sano/out" "$tmp/$n/out" || fail "residuo sano per '$n' non preparato"
  [ -f "$tmp/$n/out/ACCTFILE.dat" ] || fail "residuo sano per '$n' non preparato"
  neg "$n" "residuo sano e preparazione che fallisce ($ago)" "$ago" "$var"
done
log "   e per ognuno il file sano della corsa precedente non e' piu' al percorso stabile"
# (a) un file indicizzato DIVERSO rimasto da una corsa precedente (caricamento riuscito di 49 record, con attesi per
#     49 record), poi una corsa regolare nella stessa cartella: successo, e il file contiene i 50 record giusti.
rm -rf "$tmp/att49" && mkdir -p "$tmp/att49" && cp "$EXP"/* "$tmp/att49/" || fail "attesi per 49 record non preparati"
s49="$(orun -v "$tmp:/t:ro" -- timeout 60 sha256sum /t/tolto.rec)" || fail "impronta dell'ingresso di 49 record non calcolata"
s49="${s49%% *}"
[ "${#s49}" -eq 64 ] || fail "impronta non valida: '$s49'"
{ printf 'file ACCTFILE\nrecord 49\nbyte 14700\nprima chiave 00000000001\nultima chiave 00000000049\nsha256 lettura %s\n' "$s49" \
  && sed -n '7,8p' "$EXP/ACCTFILE.rapporto"; } > "$tmp/att49/ACCTFILE.rapporto" || fail "rapporto atteso per 49 record non scritto"
mutate "$tmp/att49/IDXLOADF.txt" 's/RECORD SCRITTI 000050/RECORD SCRITTI 000049/'
mutate "$tmp/att49/IDXLEGGI.txt" 's/RECORD LETTI 000050,/RECORD LETTI 000049,/'
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
mutate "$tmp/run-senza-pulizia.sh" 's#rm -rf "$out/lavoro" "$out/ACCTFILE.dat" "$out/ACCTFILE.dat.verifica" "$out/ACCTFILE.rapporto"#true#'
mkdir -p "$tmp/npul" || fail "cartella non creata"
r=0; env DATI_OUT_DIR="$tmp/npul/out" DATI_INGRESSO="$tmp/scambio.rec" bash "$tmp/run-senza-pulizia.sh" > "$tmp/npul.log" 2>&1 || r=$?
[ "$r" -ne 0 ] || fail "la copia di run.sh senza pulizia non e' fallita con l'ingresso scambiato"
[ -f "$tmp/npul/out/ACCTFILE.dat.verifica" ] || fail "la copia di run.sh senza pulizia non ha lasciato il file in verifica"
expect_fail "run.sh senza la pulizia dopo un fallimento: file indicizzato parziale rimasto" "resta il file indicizzato in verifica" pulita "$tmp/npul/out"

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
    cmp@1) echo "confronto non eseguito: lettura indipendente (IDXLEGGI" ;;
    cmp@2) echo "confronto non eseguito: rilettura di IDXDUMP diversa" ;;
    cmp@3) echo "confronto non eseguito: le due letture" ;;
    cmp@4) echo "confronto non eseguito: lettura per chiave 00000000001" ;;
    cmp@5) echo "confronto non eseguito: lettura per chiave 00000000025" ;;
    cmp@6) echo "confronto non eseguito: lettura per chiave 00000000049" ;;
    mkdir@1) echo "cartelle non creabili" ;;
    head@1) echo "lettura per chiave 00000000001 illeggibile (head)" ;;
    head@2) echo "record 1 dell'ingresso illeggibile (head)" ;;
    head@3) echo "lettura per chiave 00000000025 illeggibile (head)" ;;
    head@4) echo "record 25 dell'ingresso illeggibile (head)" ;;
    head@5) echo "lettura per chiave 00000000049 illeggibile (head)" ;;
    head@6) echo "record 49 dell'ingresso illeggibile (head)" ;;
    head@7) echo "prima chiave illeggibile (head)" ;;
    head@8) echo "ultima chiave illeggibile (head)" ;;
    tail@1) echo "lettura per chiave 00000000001 illeggibile (tail)" ;;
    tail@2) echo "record 1 dell'ingresso illeggibile (tail)" ;;
    tail@3) echo "lettura per chiave 00000000025 illeggibile (tail)" ;;
    tail@4) echo "record 25 dell'ingresso illeggibile (tail)" ;;
    tail@5) echo "lettura per chiave 00000000049 illeggibile (tail)" ;;
    tail@6) echo "record 49 dell'ingresso illeggibile (tail)" ;;
    tail@7) echo "ultimo record illeggibile (tail)" ;;
    sha256sum@1) echo "impronta della lettura non calcolabile (sha256sum)" ;;
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
# Attese: cp 1 (ingresso privato); mv 4 (rapporto, lettura, rilettura, poi la pubblicazione); diff 7 (attesi); cmp 1
# (lettura in sola lettura); rm 4 (invalidazione del risultato precedente, clean_dir, cartella di lavoro, temporanei).
[ "$conta" = "cp=1 mv=4 diff=7 cmp=1 rm=4" ] || fail "run.sh: invocazioni sull'host diverse da quelle attese: $conta"
log "   controprova ok: run.sh con gli involucri sull'host in modo passa riesce ($conta)"
for v in "cp@1|copia privata dell'ingresso fallita" "mv@1|rapporto non spostato" "mv@2|lettura non spostata" \
         "mv@3|rilettura non spostata" "mv@4|file indicizzato non pubblicato al percorso stabile" \
         "diff@1|ACCTFILE: rapporto: confronto non eseguito (diff, codice 42)" \
         "diff@2|IDXLOADF: rapporto di esegui.sh: confronto non eseguito" "diff@3|IDXLEGGI: rapporto di esegui.sh: confronto non eseguito" \
         "diff@4|IDXDUMP: rapporto di esegui.sh: confronto non eseguito" "diff@5|IDXLOADF: ambiente ricevuto: confronto non eseguito" \
         "diff@6|IDXLEGGI: ambiente ricevuto: confronto non eseguito" "diff@7|IDXDUMP: ambiente ricevuto: confronto non eseguito" \
         "cmp@1|lettura in sola lettura: confronto non eseguito (cmp, codice 42)" "rm@1|risultato precedente non invalidato" \
         "rm@2|impossibile cancellare" "rm@3|cartella di lavoro non rimossa" "rm@4|temporanei non rimossi"; do
  m="${v%%|*}"; c="${m%@*}"; i="${m#*@}"
  rm -f "$tmp/reg-host"
  neg "host-$c-$i" "run.sh: $c, invocazione $i, esce con 42 dopo il suo lavoro" "${v#*|}" PATH="$H:$PATH" "DATI_MODO_$c=42@$i"
  r=0; awk -v c="$c" -v i="$i" '$1 == c && $2 == i && $4 == 42 { t = 1 } END { exit !t }' "$tmp/reg-host" || r=$?
  [ "$r" -eq 0 ] || fail "run.sh, $c@$i: il comando non e' stato raggiunto"
done
neg host-docker1 "run.sh: docker del container di carica.sh esce con 42 dopo il suo lavoro" "carica.sh fallito (uscita 42)" \
  PATH="$H:$PATH" DATI_MODO_docker=42:/oracle/dati/carica.sh
st="$(in_container "$tmp/host-docker2/out")" || fail "percorso fuori da oracle/"
neg host-docker2 "run.sh: docker della lettura finale in sola lettura esce con 42 dopo il suo lavoro" \
  "lettura in sola lettura non eseguita (uscita 42)" PATH="$H:$PATH" "DATI_MODO_docker=42:$st"
# 6c. Momento della pubblicazione (giro 1 della PR #58): un involucro di docker annota, quando parte l'ultima verifica
#     (il container della lettura in sola lettura, riconosciuto dal suo argomento), se il file e' gia' al percorso
#     stabile. Con l'ultima verifica che fallisce (42 dopo il lavoro) il file non deve mai esserci stato; con l'ultima
#     verifica riuscita non deve esserci al suo inizio e deve esserci alla fine.
P="$tmp/pubwrap"; mkdir -p "$P" || fail "cartella dell'involucro di pubblicazione non creata"
vero="$(command -v docker)" || fail "docker non trovato"
printf '#!/bin/sh\nm=0\nfor a in "$@"; do [ "$a" != "$PUB_MARCA" ] || m=1; done\nif [ "$m" -eq 1 ]; then if [ -e "$PUB_OUT/ACCTFILE.dat" ]; then echo presente; else echo assente; fi >> "$PUB_REG" || exit 120; fi\n\047%s\047 "$@"\nr=$?\nif [ "$m" -eq 1 ] && [ "$PUB_MODO" = 42 ]; then exit 42; fi\nexit "$r"\n' \
  "$vero" > "$P/docker" || fail "involucro di pubblicazione non scritto"
chmod +x "$P/docker" || fail "involucro di pubblicazione non eseguibile"
for modo in 42 passa; do
  n="pub-$modo"; o="$tmp/$n/out"; mkdir -p "$tmp/$n" || fail "cartella non creata"
  rm -f "$tmp/$n.reg" || fail "annotazione precedente non rimossa"
  marca="$(in_container "$o")" || fail "percorso fuori da oracle/"
  if [ "$modo" = 42 ]; then
    neg "$n" "pubblicazione: l'ultima verifica fallisce (42 dopo il lavoro): il file non compare mai al percorso stabile" \
      "lettura in sola lettura non eseguita (uscita 42)" PATH="$P:$PATH" PUB_MARCA="$marca" PUB_OUT="$o" PUB_REG="$tmp/$n.reg" PUB_MODO=42
  else
    passo "$n" PATH="$P:$PATH" PUB_MARCA="$marca" PUB_OUT="$o" PUB_REG="$tmp/$n.reg" PUB_MODO=passa \
      || { cat "$tmp/$n.log" >&2; fail "pubblicazione: corsa con l'involucro in modo passa fallita"; }
    [ -f "$o/ACCTFILE.dat" ] || fail "pubblicazione: dopo la corsa riuscita il file non e' al percorso stabile"
  fi
  annot="$(cat "$tmp/$n.reg")" || fail "pubblicazione ($modo): annotazione assente: l'ultima verifica non e' stata intercettata"
  [ "$annot" = assente ] || fail "PROVA NEGATIVA FALLITA (pubblicazione, $modo): all'inizio dell'ultima verifica il file era: '$annot'"
done
log "   controprova ok: all'inizio dell'ultima verifica il file non e' mai al percorso stabile; pubblicato solo dopo (corsa riuscita), mai (verifica fallita)"
log "controllo superato"
