#!/usr/bin/env bash
# Controllo del passo golden (issue #55): golden del job READACCT (CBACT01C).
# 0. File indicizzato dello scenario esempio rigenerato da zero con il passo dati, in una cartella nuova (nessun
#    risultato pubblicato in precedenza viene usato).
# 1. Controllo 1: due corse consecutive di run.sh da zero, in cartelle nuove; ognuna coincide byte per byte con i golden
#    versionati (oracle/golden/readacct/generati) e con il documento versionato.
# 2. Controlli 2, 3, 4, coerenza fisico/riferimento, 5, eseguiti DA SOLI sul risultato della prima corsa.
# 3. Prove negative della specifica: ognuna prepara un risultato sbagliato con i programmi veri (o con una variante
#    realmente caricata) e vi esegue da solo il controllo bersaglio, che deve fallire con una diagnosi che lo nomina.
# 4. Residui e ramo d'errore: risultato precedente con programma che fallisce (errore di scrittura reale, file system
#    pieno); file indicizzato corrotto; residuo con corsa regolare.
# 5. Presenza del passo nel controllo dei passi di build/check.sh.
# 6. Esiti dei comandi: ogni comando dei programmi nel container (involucro build/avvolgi.sh davanti nel PATH) e i
#    comandi di run.sh sull'host, con esito 42 dopo il loro lavoro; limite di tempo.
. "$ORACLE_ROOT/lib.sh"

DIR="$ORACLE_ROOT/golden"
RA="$DIR/readacct"
GV="$RA/generati"
DOCV="$REPO_ROOT/docs/legacy-map/golden-readacct.md"
REC="$REPO_ROOT/analysis/oracle-dati/out/ACCTFILE.rec"
tmp="$(mktmp)" || exit 1
trap 'rm -rf "$tmp" || { log "ERRORE: temporanei non rimossi: $(rel "$tmp")"; exit 1; }' EXIT
require_legacy
ensure_image
require_build
[ -f "$REC" ] || fail "ingresso assente: $(rel "$REC"): eseguire './analysis/run.sh oracle-dati'"
[ -d "$GV" ] && [ -f "$DOCV" ] || fail "golden versionati assenti: eseguire './oracle/run.sh golden'"

# p PERCORSO: percorso nel container di un file sotto $tmp (montato su /t)
p() { case "$1" in "$tmp"/*) echo "/t/${1#"$tmp"/}" ;; *) fail "p: $1 non e' sotto $tmp" ;; esac; }
# cnt [opzioni docker] -- comando: nel container dell'oracle, con $tmp su /t e gli artefatti della build, limite 600 s
cnt() {
  local extra=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do extra+=("$1"); shift; done
  shift
  orun -v "$tmp:/t" -v "$BUILD_OUT/bin:/oracle-bin:ro" ${extra[@]+"${extra[@]}"} -- timeout -k 10 600 "$@"
}
# c1 VERSIONATO NUOVO: controllo 1 su due alberi o due file, byte per byte (cmp distinto: 0, 1, errore)
c1() {
  local a="$1" b="$2" la lb f r
  if [ -d "$a" ]; then
    [ -d "$b" ] || { echo "CONTROLLO 1 FALLITO: $(rel "$b") assente"; return 1; }
    la="$(cd "$a" && find . -type f | LC_ALL=C sort)" || { echo "CONTROLLO 1: elenco non letto"; return 2; }
    lb="$(cd "$b" && find . -type f | LC_ALL=C sort)" || { echo "CONTROLLO 1: elenco non letto"; return 2; }
    [ "$la" = "$lb" ] || { echo "CONTROLLO 1 FALLITO: insiemi di file diversi"; return 1; }
    for f in $la; do
      r=0; cmp -s "$a/$f" "$b/$f" || r=$?
      case "$r" in 0) ;; 1) echo "CONTROLLO 1 FALLITO: ${f#./} diverso dal versionato"; return 1 ;;
        *) echo "CONTROLLO 1: confronto non eseguito su $f (cmp, codice $r)"; return 2 ;; esac
    done
    echo "controllo 1: $(echo $la | wc -w | tr -d ' ') file identici byte per byte"
  else
    r=0; cmp -s "$a" "$b" || r=$?
    case "$r" in 0) echo "controllo 1: identici" ;; 1) echo "CONTROLLO 1 FALLITO: $(rel "$b") diverso da $(rel "$a")"; return 1 ;;
      *) echo "CONTROLLO 1: confronto non eseguito (cmp, codice $r)"; return 2 ;; esac
  fi
}
T="/oracle/golden/readacct"
c2() { cnt -- sh /oracle/golden/conteggi.sh "$1" "$2" 50; }                                    # INGRESSO DIR
c3() { cnt -- sh /oracle/golden/attesi.sh "${3:-$T}/attesi-a-mano.tsv" "${3:-$T}/sostituzioni-mirato.tsv" "${3:-$T}/esclusioni.tsv" "$2" "$1"; }  # DIR SCEN [TAB]
c4() { cnt -- sh /oracle/golden/verificatore.sh "$2" "$1/ingresso.rec" "$1" "${3:-$T}/campi.tsv" "${3:-$T}/esclusioni.tsv"; }   # DIR SCEN [TAB]
c4b() { cnt -- sh /oracle/golden/coerenza.sh "$2" "$1" "${3:-$T}/esclusioni.tsv" "${3:-$T}/correzioni.tsv"; }   # DIR SCEN [TAB]
c5() { cnt -- sh /oracle/golden/separazione.sh "$1"; }
maschera() { cnt -- sh /oracle/golden/maschera.sh "$2" "$1" "${3:-$T}/esclusioni.tsv" "${3:-$T}/correzioni.tsv" "${3:-$T}/console.tsv"; }
# corsa ID [VAR=VALORE...]: run.sh con uscite in $tmp/ID e il file indicizzato rigenerato al punto 0
corsa() { local n="$1"; shift; mkdir -p "$tmp/$n" || fail "cartella $n non creata"
  env GOLDEN_OUT_DIR="$tmp/$n/generati" GOLDEN_DOC="$tmp/$n/doc.md" GOLDEN_ACCTFILE="$ACCT" "$@" bash "$DIR/run.sh"; }
# copia ID: copia della prima corsa in $tmp/ID (generati)
copia() { rm -rf "$tmp/$1" && mkdir -p "$tmp/$1" && cp -R "$tmp/r1/generati" "$tmp/$1/generati" || fail "copia $1 non riuscita"; }
# tabelle ID: copia delle tabelle in $tmp/ID-tab
tabelle() { rm -rf "$tmp/$1-tab" && cp -R "$RA" "$tmp/$1-tab" && rm -rf "$tmp/$1-tab/generati" || fail "copia delle tabelle $1 non riuscita"; }
# rif_byte FILE RIGA POSIZIONE BYTE: cambia un byte (2 caratteri) di una riga di un riferimento; alterazione verificata
rif_byte() {
  awk -v L="$2" -v P="$3" -v B="$4" 'NR == L { $0 = substr($0, 1, 2 * P - 2) B substr($0, 2 * P + 1) } { print }' "$1" > "$1.mut" \
    || fail "rif_byte: awk fallito"
  local r=0; cmp -s "$1" "$1.mut" || r=$?
  case "$r" in 1) ;; 0) fail "rif_byte: nessuna alterazione in $(rel "$1")" ;; *) fail "rif_byte: cmp $r" ;; esac
  mv "$1.mut" "$1" || fail "rif_byte: mv fallito"
}
# fis_byte FILE SCOSTAMENTO OTTALE: cambia un byte di un file binario (dimensione invariata, alterazione verificata)
fis_byte() {
  cp "$1" "$1.orig" || fail "fis_byte: copia fallita"
  # shellcheck disable=SC2059
  printf "\\$3" | dd of="$1" bs=1 seek="$2" conv=notrunc 2> /dev/null || fail "fis_byte: dd fallito"
  local r=0; cmp -s "$1" "$1.orig" || r=$?
  case "$r" in 1) ;; 0) fail "fis_byte: nessuna alterazione in $(rel "$1")" ;; *) fail "fis_byte: cmp $r" ;; esac
  rm -f "$1.orig" || fail "fis_byte: rm fallito"
}
# produci ID INGRESSO [ARTEFATTI]: CBACT01C su un ingresso dato (caricato con carica.sh), uscite raccolte in $tmp/ID/g
# con i riferimenti (maschera.sh); diagnostica in $tmp/ID.log. Ritorna il codice del container.
produci() {
  local n="$1" in="$2" b="${3:-$BUILD_OUT/bin}"
  rm -rf "$tmp/$n" && mkdir -p "$tmp/$n/in" && cp "$in" "$tmp/$n/in/i.rec" || fail "preparazione di $n fallita"
  orun -v "$tmp/$n:/w" -v "$b:/oracle-bin:ro" -- timeout -k 10 600 sh -c '
    sh /oracle/golden/scenario.sh carica /w/in/i.rec - /w/s || exit $?
    mkdir -p /w/g || exit 1
    for f in OUTFILE ARRYFILE VBRCFILE; do cp /w/s/lavoro-CBACT01C/$f /w/g/$f || exit 1; done
    cp /w/s/VBRCFILE.logici.txt /w/g/ && cp /w/s/CBACT01C.txt /w/g/rapporto.txt && cp /w/in/i.rec /w/g/ingresso.rec || exit 1
    sh /oracle/golden/maschera.sh esempio /w/g /oracle/golden/readacct/esclusioni.tsv /oracle/golden/readacct/correzioni.tsv /oracle/golden/readacct/console.tsv' \
    > "$tmp/$n.log" 2>&1
  local r=$?
  [ "$r" -eq 0 ] || cat "$tmp/$n.log"
  return "$r"
}
# record FILE N: i 300 byte del record N (da 1) dell'ingresso, su stdout
record() { tail -c "+$(( ($2 - 1) * 300 + 1 ))" "$1" > "$tmp/record.tmp" || fail "record $2 illeggibile"; head -c 300 "$tmp/record.tmp" || fail "record $2 illeggibile"; }
# scrivi INGRESSO-ALTERATO SCOSTAMENTO TESTO: copia di REC con TESTO allo scostamento (da 0)
scrivi() { cp "$REC" "$1" || fail "copia dell'ingresso fallita"; printf '%s' "$3" | dd of="$1" bs=1 seek="$2" conv=notrunc 2> /dev/null || fail "scrittura fallita"
  local r=0; cmp -s "$1" "$REC" || r=$?; [ "$r" -eq 1 ] || fail "alterazione dell'ingresso senza effetto (cmp $r)"; }

log "0. file indicizzato dello scenario esempio rigenerato da zero (passo dati, cartella nuova)"
mkdir -p "$tmp/dati" || fail "cartella dati non creata"
DATI_OUT_DIR="$tmp/dati/out" bash "$ORACLE_ROOT/dati/run.sh" > "$tmp/dati.log" 2>&1 || { indent "$tmp/dati.log" >&2; fail "passo dati fallito"; }
ACCT="$tmp/dati/out/ACCTFILE.dat"
[ -f "$ACCT" ] || fail "file indicizzato non prodotto dal passo dati"

log "1. controllo 1: due corse da zero, confrontate byte per byte con i golden versionati"
for i in 1 2; do
  corsa "r$i" > "$tmp/r$i.log" 2>&1 || { indent "$tmp/r$i.log" >&2; fail "corsa $i di run.sh fallita"; }
  c1 "$GV" "$tmp/r$i/generati" > "$tmp/c1.out" 2>&1 || { indent "$tmp/c1.out" >&2; fail "corsa $i: golden diversi dai versionati"; }
  indent "$tmp/c1.out" >&2
  c1 "$DOCV" "$tmp/r$i/doc.md" > "$tmp/c1.out" 2>&1 || { indent "$tmp/c1.out" >&2; fail "corsa $i: documento diverso dal versionato"; }
  log "   corsa $i: golden e documento identici ai versionati"
done
R1="$(p "$tmp/r1/generati")"

log "2. controlli eseguiti da soli sul risultato della corsa 1"
for s in esempio mirato; do
  for c in "c2 $R1/golden/$s/ingresso.rec $R1/golden/$s" "c3 $R1/golden/$s $s" "c4 $R1/golden/$s $s" "c4b $R1/golden/$s $s"; do
    # shellcheck disable=SC2086
    $c > "$tmp/ctl.out" 2>&1 || { indent "$tmp/ctl.out" >&2; fail "controllo fallito: $c"; }
    indent "$tmp/ctl.out" >&2
  done
done
c5 "$R1" > "$tmp/ctl.out" 2>&1 || { indent "$tmp/ctl.out" >&2; fail "controllo 5 fallito"; }
indent "$tmp/ctl.out" >&2
grep -c "identico alla prima esecuzione: si" "$tmp/r1/generati/osservazioni/riesecuzione/esito.txt" > "$tmp/n6" || fail "esito della riesecuzione illeggibile"
[ "$(cat "$tmp/n6")" = 3 ] || fail "controllo 6: la riesecuzione non registra tre uscite identiche alla prima"
log "   controllo 6 (osservazione): OPEN OUTPUT su file esistente li riscrive da capo; uscite identiche alla prima esecuzione"

log "3. prove negative"
E="$tmp/r1/generati/golden/esempio"; M="$tmp/r1/generati/golden/mirato"
# a) un byte di un golden alterato: uno per file e uno nella console -> controllo 1
for v in "OUTFILE:12:061" "ARRYFILE:$((110 + 11)):061" "VBRCFILE:$((59 + 10)):061"; do
  f="${v%%:*}"; rest="${v#*:}"; copia "a-$f"
  fis_byte "$tmp/a-$f/generati/golden/esempio/$f" "${rest%%:*}" "${rest#*:}"
  expect_fail "byte alterato nel golden $f (esempio)" "CONTROLLO 1 FALLITO: golden/esempio/$f diverso" c1 "$GV" "$tmp/a-$f/generati"
done
copia a-console; rif_byte "$tmp/a-console/generati/golden/esempio/console.riferimento.txt" 2 1 "a"
expect_fail "byte alterato nella console di riferimento (esempio)" "CONTROLLO 1 FALLITO: golden/esempio/console.riferimento.txt diverso" c1 "$GV" "$tmp/a-console/generati"
# b) un record d'ingresso alterato (saldo, stato, data): CBACT01C eseguito davvero sull'ingresso alterato; controllo 1
#    sui file prodotti e controllo 4 da solo con l'ingresso dello scenario
for v in "saldo:$((1 * 300 + 20)):9:OUT-ACCT-CURR-BAL" "stato:$((16 * 300 + 11)):N:OUT-ACCT-ACTIVE-STATUS" "data:$((39 * 300 + 77)):8:OUT-ACCT-REISSUE-DATE"; do
  n="${v%%:*}"; r1="${v#*:}"; off="${r1%%:*}"; r2="${r1#*:}"; txt="${r2%%:*}"; campo="${r2#*:}"
  scrivi "$tmp/b-$n.rec" "$off" "$txt"
  produci "b-$n" "$tmp/b-$n.rec" || { indent "$tmp/b-$n.log" >&2; fail "prova b-$n: produzione fallita"; }
  expect_fail "ingresso alterato ($n): OUTFILE prodotto contro il golden" "CONTROLLO 1 FALLITO" c1 "$E/OUTFILE" "$tmp/b-$n/g/OUTFILE"
  cp "$E/ingresso.rec" "$tmp/b-$n/g/ingresso.rec" || fail "ingresso dello scenario non copiato"
  expect_fail "ingresso alterato ($n): verificatore con l'ingresso dello scenario" "($campo): atteso" c4 "$(p "$tmp/b-$n/g")" esempio
done
# c) COBDATFT sostituita da una variante che restituisce la data invariata, compilata e caricata davvero
mkdir -p "$tmp/c-src" && cp "$ORACLE_ROOT/stubs/COBDATFT.cbl" "$tmp/c-src/COBDATFT.cbl" || fail "copia della routine fallita"
mutate "$tmp/c-src/COBDATFT.cbl" 's/^           MOVE LK-COINPDT(6:2) TO LK-COOUTDT(5:2)$/           MOVE LK-COINPDT(5:6) TO LK-COOUTDT(5:6)/'
mutate "$tmp/c-src/COBDATFT.cbl" 's/^           MOVE LK-COINPDT(9:2) TO LK-COOUTDT(7:2)\.$/           CONTINUE./'
mkdir -p "$tmp/c-build" "$tmp/c-bin" || fail "cartelle della variante non create"
cnt -- sh /oracle/build/compile.sh uno modulo "$(p "$tmp/c-src/COBDATFT.cbl")" COBDATFT "$(p "$tmp/c-build")" > "$tmp/c.log" 2>&1 \
  || { indent "$tmp/c.log" >&2; fail "compilazione della variante di COBDATFT fallita"; }
cp "$BUILD_OUT"/bin/* "$tmp/c-bin/" && cp "$tmp/c-build/bin/COBDATFT.so" "$tmp/c-bin/COBDATFT.so" || fail "artefatti della variante non preparati"
produci c-datft "$REC" "$tmp/c-bin" || { indent "$tmp/c-datft.log" >&2; fail "prova COBDATFT: produzione fallita"; }
d1="$(head -c 78 "$tmp/c-datft/g/OUTFILE")" || fail "OUTFILE della variante illeggibile"
[ "${d1:68:10}" = "2025-05-20" ] || fail "la variante di COBDATFT non e' stata caricata (OUT-ACCT-REISSUE-DATE = '${d1:68:10}')"
log "   la variante e' davvero caricata: OUT-ACCT-REISSUE-DATE del record 1 = ${d1:68:10}"
expect_fail "COBDATFT che restituisce la data invariata" "(OUT-ACCT-REISSUE-DATE): atteso" c4 "$(p "$tmp/c-datft/g")" esempio
# d) un record tolto dall'ingresso -> controllo 2 (con l'ingresso dello scenario: 50 record dichiarati)
head -c $((49 * 300)) "$REC" > "$tmp/d.rec" || fail "ingresso senza l ultimo record non preparato"
produci d-tolto "$tmp/d.rec" || { indent "$tmp/d-tolto.log" >&2; fail "prova d: produzione fallita"; }
cp "$E/ingresso.rec" "$tmp/d-tolto/g/ingresso.rec" || fail "ingresso dello scenario non copiato"
expect_fail "un record tolto dall'ingresso" "OUTFILE di 5243 byte: attesi 50 record" c2 "$(p "$tmp/d-tolto/g/ingresso.rec")" "$(p "$tmp/d-tolto/g")"
# e) due record scambiati prima del caricamento: il caricamento li rifiuta
{ record "$REC" 1 && record "$REC" 3 && record "$REC" 2 && tail -c +901 "$REC"; } > "$tmp/e.rec" || fail "ingresso con record scambiati non preparato"
expect_fail "due record d'ingresso scambiati prima del caricamento" "IDXLOADF ACCTFILE ERRORE WRITE 21 DOPO IL RECORD 000002" produci e-scambio "$tmp/e.rec"
grep -q "caricamento o lettura non riusciti" "$tmp/e-scambio.log" || fail "prova e: diagnosi del caricamento assente"
# f) un atteso a mano alterato -> controllo 3
tabelle f; mutate "$tmp/f-tab/attesi-a-mano.tsv" 's/^\(esempio	00000000001	OUTFILE	OUT-ACCT-CURR-BAL	13	12	c:\)00000001940{/\100000001941{/'
expect_fail "un atteso a mano alterato" "00000000001 OUTFILE byte 23: atteso a mano 31, golden 30" c3 "$R1/golden/esempio" esempio "$(p "$tmp/f-tab")"
# g) golden e atteso a mano alterati allo stesso modo -> il controllo 3 passa, il controllo 4 da solo li respinge
copia g1; tabelle g1
rif_byte "$tmp/g1/generati/golden/esempio/OUTFILE.riferimento.txt" 1 97 0f
fis_byte "$tmp/g1/generati/golden/esempio/OUTFILE" 96 017
mutate "$tmp/g1-tab/attesi-a-mano.tsv" 's/^\(esempio	00000000001	OUTFILE	OUT-ACCT-CURR-CYC-DEBIT	91	7	x:\)0000000252500c/\10000000252500f/'
c3 "$(p "$tmp/g1/generati")/golden/esempio" esempio "$(p "$tmp/g1-tab")" > "$tmp/g1.c3" 2>&1 || { indent "$tmp/g1.c3" >&2; fail "prova g1: il controllo 3 doveva passare (alterazione concorde)"; }
log "   controprova ok: segno C -> F nel COMP-3, alterato allo stesso modo in golden e atteso: il controllo 3 passa"
expect_fail "segno C -> F nel COMP-3 di OUT-ACCT-CURR-CYC-DEBIT, golden e atteso concordi" "(OUT-ACCT-CURR-CYC-DEBIT): atteso 0c, trovato 0f" \
  c4 "$(p "$tmp/g1/generati")/golden/esempio" esempio
copia g2; tabelle g2
rif_byte "$tmp/g2/generati/golden/mirato/OUTFILE.riferimento.txt" 3 24 47
fis_byte "$tmp/g2/generati/golden/mirato/OUTFILE" $((2 * 107 + 23)) 107
mutate "$tmp/g2-tab/attesi-a-mano.tsv" 's/^\(mirato	00000000003	OUTFILE	OUT-ACCT-CURR-BAL	13	12	c:\)00000012345P/\100000012345G/'
c3 "$(p "$tmp/g2/generati")/golden/mirato" mirato "$(p "$tmp/g2-tab")" > "$tmp/g2.c3" 2>&1 || { indent "$tmp/g2.c3" >&2; fail "prova g2: il controllo 3 doveva passare (alterazione concorde)"; }
log "   controprova ok: saldo negativo -> positivo, concorde in golden e atteso: il controllo 3 passa"
expect_fail "segno negativo del saldo -> positivo, golden e atteso concordi" "(OUT-ACCT-CURR-BAL): atteso 50, trovato 47" \
  c4 "$(p "$tmp/g2/generati")/golden/mirato" mirato
# h) un byte delle posizioni escluse alterato nel file fisico: il riferimento mascherato non cambia, l'osservazione si'
copia h; fis_byte "$tmp/h/generati/golden/esempio/OUTFILE" 76 101
maschera "$(p "$tmp/h/generati")/golden/esempio" esempio > "$tmp/h.m" 2>&1 || { indent "$tmp/h.m" >&2; fail "prova h: riferimenti non rigenerati"; }
c1 "$E/OUTFILE.riferimento.txt" "$tmp/h/generati/golden/esempio/OUTFILE.riferimento.txt" > "$tmp/h.c1" 2>&1 \
  || { indent "$tmp/h.c1" >&2; fail "PROVA NEGATIVA FALLITA (h): il riferimento mascherato e' cambiato"; }
log "   esito 1 (h): byte 77 del record 1 alterato nel fisico: il riferimento mascherato rigenerato e' identico"
expect_fail "esito 2 (h): byte escluso alterato nel file fisico (osservazione)" "CONTROLLO 1 FALLITO: golden/esempio/OUTFILE diverso" c1 "$GV" "$tmp/h/generati"
# i) tabella delle esclusioni: una posizione tolta, una aggiunta senza motivo, una aggiunta su un byte determinato
tabelle i1; mutate "$tmp/i1-tab/esclusioni.tsv" '/^\*	OUTFILE	\*	77	2	/d'
expect_fail "posizione 77-78 tolta dalle esclusioni" "posizione non determinata dal sorgente ma non esclusa" c4 "$R1/golden/esempio" esempio "$(p "$tmp/i1-tab")"
expect_fail "posizione 77-78 tolta dalle esclusioni (controllo 3)" "atteso ND ma la posizione non e esclusa" c3 "$R1/golden/esempio" esempio "$(p "$tmp/i1-tab")"
tabelle i2; printf 'esempio\tOUTFILE\t*\t50\t1\t-\t-\n' >> "$tmp/i2-tab/esclusioni.tsv" || fail "riga non aggiunta"
expect_fail "esclusione aggiunta senza motivo" "esclusione senza motivo o senza riga del sorgente" c4 "$R1/golden/esempio" esempio "$(p "$tmp/i2-tab")"
tabelle i3; printf 'esempio\tOUTFILE\t*\t50\t1\tmotivo inventato\tcbl/CBACT01C.cbl:221\n' >> "$tmp/i3-tab/esclusioni.tsv" || fail "riga non aggiunta"
expect_fail "esclusione aggiunta su un byte determinato" "posizione esclusa ma determinata dal sorgente" c4 "$R1/golden/esempio" esempio "$(p "$tmp/i3-tab")"
# j) tabella campo <- campo con ACCT-CREDIT-LIMIT e ACCT-CASH-CREDIT-LIMIT scambiati
tabelle j
mutate "$tmp/j-tab/campi.tsv" 's/^\(OUTFILE	OUT-ACCT-CREDIT-LIMIT	25	12	copia-segno	\)25	/\137	/'
mutate "$tmp/j-tab/campi.tsv" 's/^\(OUTFILE	OUT-ACCT-CASH-CREDIT-LIMIT	37	12	copia-segno	\)37	/\125	/'
expect_fail "campi di uguale tracciato scambiati (credito e anticipo)" "(OUT-ACCT-CREDIT-LIMIT): atteso" c4 "$R1/golden/esempio" esempio "$(p "$tmp/j-tab")"
# k) estrattore dei record variabili che perde l'ultimo record o legge una lunghezza sbagliata -> controllo 2
for v in "perde:s/while (p <= n) {/while (p <= n - 50) {/" "lunghezza:s/for (j = 0; j < len; j++) s = s b\[p + 4 + j\]/for (j = 0; j < len - 1; j++) s = s b[p + 4 + j]/;s/printf \"%06d %03d %s\\\\n\", r, len, s/printf \"%06d %03d %s\\\\n\", r, len - 1, s/"; do
  n="${v%%:*}"; copia "k-$n"; cp "$DIR/estrai-vb.sh" "$tmp/k-$n/estrai.sh" || fail "copia dell'estrattore fallita"
  mutate "$tmp/k-$n/estrai.sh" "${v#*:}"
  K="$(p "$tmp/k-$n")"
  cnt -- sh "$K/estrai.sh" "$K/generati/golden/esempio/VBRCFILE" "$K/generati/golden/esempio/VBRCFILE.logici.txt" > "$tmp/k-$n.log" 2>&1 \
    || { indent "$tmp/k-$n.log" >&2; fail "prova k-$n: l'estrattore alterato e' fallito invece di produrre un risultato sbagliato"; }
  if [ "$n" = perde ]; then ago="VBRCFILE: 99 record logici, attesi 100"; else ago="ma i record logici estratti sommano 2850 byte"; fi
  expect_fail "estrattore dei record variabili che $n" "$ago" c2 "$K/generati/golden/esempio/ingresso.rec" "$K/generati/golden/esempio"
done
# l) scenario osservazione copiato tra i golden -> controllo 5
copia l; cp -R "$tmp/l/generati/osservazioni/osservazione" "$tmp/l/generati/golden/osservazione" || fail "copia fallita"
expect_fail "scenario osservazione copiato tra i golden" "i golden sono 'esempio mirato osservazione'" c5 "$(p "$tmp/l/generati")"
copia l2; cp "$tmp/l2/generati/osservazioni/osservazione/OUTFILE" "$tmp/l2/generati/golden/mirato/OUTFILE" || fail "copia fallita"
expect_fail "OUTFILE dello scenario osservazione al posto di quello del mirato" "e' identico a osservazioni/osservazione/OUTFILE" c5 "$(p "$tmp/l2/generati")"
copia l3; printf 'RIFERIMENTO DI PARITA'"'"' finto\n' > "$tmp/l3/generati/osservazioni/osservazione/MARCATURA" || fail "marcatura non scritta"
expect_fail "scenario osservazione marcato come riferimento" "scenario osservazione: marcatura" c5 "$(p "$tmp/l3/generati")"
# m) correzioni dell'oracle (specifica aggiornata, voce 106)
tabelle m1; mutate "$tmp/m1-tab/correzioni.tsv" '/^\*	ARRYFILE	\*	80	30	7b	/d'
copia m1; maschera "$(p "$tmp/m1/generati")/golden/esempio" esempio "$(p "$tmp/m1-tab")" > "$tmp/m1.m" 2>&1 || { indent "$tmp/m1.m" >&2; fail "prova m1: riferimenti non rigenerati"; }
expect_fail "correzione del byte 80 tolta dalla tabella" "(ARR-ACCT-CURR-BAL(4)): atteso 7b, trovato 30" c4 "$(p "$tmp/m1/generati")/golden/esempio" esempio
tabelle m2; printf '*\tARRYFILE\t*\t79\t30\t31\tcorrezione inventata\tcbl/CBACT01C.cbl:169\n' >> "$tmp/m2-tab/correzioni.tsv" || fail "riga non aggiunta"
copia m2; maschera "$(p "$tmp/m2/generati")/golden/esempio" esempio "$(p "$tmp/m2-tab")" > "$tmp/m2.m" 2>&1 || { indent "$tmp/m2.m" >&2; fail "prova m2: riferimenti non rigenerati"; }
expect_fail "correzione aggiunta su una posizione giusta (byte 79)" "(ARR-ACCT-CURR-BAL(4)): atteso 30, trovato 31" c4 "$(p "$tmp/m2/generati")/golden/esempio" esempio
tabelle m3; mutate "$tmp/m3-tab/correzioni.tsv" 's/^\(\*	ARRYFILE	\*	80	\)30	7b	/\131	7b	/'
copia m3; expect_fail "byte dell'oracle diverso da quello dichiarato (31 invece di 30)" "CORREZIONE CONDIZIONATA NON APPLICABILE: ARRYFILE 00000000001 byte 80: l oracle ha scritto 30, la tabella dichiara 31" \
  maschera "$(p "$tmp/m3/generati")/golden/esempio" esempio "$(p "$tmp/m3-tab")"
tabelle m4; mutate "$tmp/m4-tab/correzioni.tsv" 's/^\(\*	ARRYFILE	\*	80	30	\)7b	/\17c	/'
copia m4; maschera "$(p "$tmp/m4/generati")/golden/esempio" esempio "$(p "$tmp/m4-tab")" > "$tmp/m4.m" 2>&1 || { indent "$tmp/m4.m" >&2; fail "prova m4: riferimenti non rigenerati"; }
expect_fail "byte di riferimento della tabella diverso dalla regola (7c)" "(ARR-ACCT-CURR-BAL(4)): atteso 7b, trovato 7c" c4 "$(p "$tmp/m4/generati")/golden/esempio" esempio
copia m5; rif_byte "$tmp/m5/generati/golden/esempio/ARRYFILE.riferimento.txt" 1 50 31
expect_fail "riferimento diverso dal fisico in una posizione di nessuna tabella (coerenza)" "posizione in nessuna tabella" c4b "$(p "$tmp/m5/generati")/golden/esempio" esempio
copia m6; rif_byte "$tmp/m6/generati/golden/esempio/ARRYFILE.riferimento.txt" 1 80 30
expect_fail "correzione non applicata nel riferimento (coerenza)" "correzione attesa 30 -> 7b" c4b "$(p "$tmp/m6/generati")/golden/esempio" esempio
# n) scenari derivati: tabella delle sostituzioni e proprieta'
tabelle n1; mutate "$tmp/n1-tab/sostituzioni-mirato.tsv" 's/^\(00000000003	ACCT-CURR-BAL	13	12	303030303030313233343550	zoned	\)-1234.57/\1-1234.58/'
expect_fail "sostituzione con un valore dichiarato diverso dai byte" "valore decodificato -1234.57, atteso -1234.58" \
  cnt -- sh /oracle/golden/differenze.sh "$R1/golden/esempio/ingresso.rec" "$(p "$tmp/n1-tab")/sostituzioni-mirato.tsv" "$R1/golden/mirato/ingresso.rec"
cp "$M/ingresso.rec" "$tmp/n2.rec" && fis_byte "$tmp/n2.rec" $((30 * 300 + 200)) 056
expect_fail "un byte del derivato cambiato fuori dalla tabella" "1 byte del derivato diversi dalla base con le sole sostituzioni" \
  cnt -- sh /oracle/golden/differenze.sh "$R1/golden/esempio/ingresso.rec" "$T/sostituzioni-mirato.tsv" "$(p "$tmp/n2.rec")"
expect_fail "proprieta' dello scenario mirato cercate nel file letto dell'esempio" "MANCA: saldo negativo" \
  cnt -- sh /oracle/golden/proprieta.sh "$R1/golden/esempio/ingresso.rec" mirato "$T/proprieta.tsv" "$R1/golden/esempio/ingresso.rec"

log "4. residui, ramo d'errore, file indicizzato corrotto"
# Ramo d'errore reale: le uscite su un file system pieno (tmpfs di 8 KiB): WRITE con stato 34, 9910, 9999, CEE3ABD
# 999/0, codice 99. Prima: un risultato precedente sano nella cartella d'uscita e nel documento.
mkdir -p "$tmp/err" && cp -R "$tmp/r1/generati" "$tmp/err/generati" && cp "$tmp/r1/doc.md" "$tmp/err/doc.md" || fail "residuo non preparato"
expect_fail "errore di scrittura reale (file system pieno) con un risultato precedente al suo posto" "ABCODE=+0000000999 TIMING=+0000000000" \
  corsa err GOLDEN_DOCKER_EXTRA="--tmpfs /pieno:size=8k,mode=1777 -e SCENARIO_USCITE=/pieno"
[ ! -e "$tmp/err/generati" ] && [ ! -e "$tmp/err/doc.md" ] || fail "PROVA NEGATIVA FALLITA (errore di scrittura): il risultato precedente e' rimasto"
corsa err2 GOLDEN_DOCKER_EXTRA="--tmpfs /pieno:size=8k,mode=1777 -e SCENARIO_USCITE=/pieno" > "$tmp/err2.log" 2>&1 && fail "la corsa con il file system pieno e' riuscita"
for a in "ACCOUNT FILE WRITE STATUS IS:" "FILE STATUS IS: NNNN00" "ABENDING PROGRAM" "== codice di uscita" "CBACT01C: codice di uscita 99, atteso 0"; do
  grep -qF -- "$a" "$tmp/err2.log" || { indent "$tmp/err2.log" >&2; fail "ramo d'errore: manca '$a' nella diagnostica"; }
done
log "   ramo d'errore: diagnostica, CEE3ABD 999/0, codice 99, nessun golden pubblicato, risultato precedente rimosso"
# Osservazione: lo stub lascia i file parziali (il JCL li cancellerebbe, DISP=(NEW,CATLG,DELETE))
cnt --tmpfs /pieno:size=8k,mode=1777 -- sh -c 'SCENARIO_USCITE=/pieno sh /oracle/golden/scenario.sh carica /oracle/golden/readacct/generati/golden/esempio/ingresso.rec - /tmp/s > /tmp/log 2>&1; echo "uscita $?"; ls /pieno' \
  > "$tmp/parziali" 2>&1 || fail "osservazione dei file parziali non eseguita"
grep -qx "uscita 5" "$tmp/parziali" && grep -qx OUTFILE "$tmp/parziali" && grep -qx ARRYFILE "$tmp/parziali" && grep -qx VBRCFILE "$tmp/parziali" \
  || { indent "$tmp/parziali" >&2; fail "osservazione: i file parziali non sono quelli attesi"; }
log "   osservazione: dopo l'arresto (uscita 5 di scenario.sh, CBACT01C 99) restano OUTFILE, ARRYFILE e VBRCFILE parziali"
# File indicizzato corrotto: GnuCOBOL legge una fine file silenziosa; la rilettura con IDXLEGGI lo scopre.
cp "$ACCT" "$tmp/corrotto.dat" && cp "$ACCT" "$tmp/corrotto.orig" || fail "copia del file indicizzato fallita"
printf '\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377' | dd of="$tmp/corrotto.dat" bs=1 seek=$((4 * 4096)) conv=notrunc 2> /dev/null || fail "alterazione della pagina 4 fallita"
r=0; cmp -s "$tmp/corrotto.dat" "$tmp/corrotto.orig" || r=$?; [ "$r" -eq 1 ] || fail "alterazione del file indicizzato senza effetto (cmp $r)"
expect_fail "file indicizzato corrotto (pagina 4 alterata: fine file silenziosa)" "il file indicizzato letto e' diverso dall'ingresso" \
  corsa corrotto GOLDEN_ACCTFILE="$tmp/corrotto.dat"
# Residuo diverso nella cartella d'uscita e una corsa regolare: successo, risultato uguale ai versionati.
mkdir -p "$tmp/res/generati/golden/vecchio" && printf 'residuo\n' > "$tmp/res/generati/golden/vecchio/OUTFILE" && printf 'vecchio\n' > "$tmp/res/doc.md" || fail "residuo non preparato"
corsa res > "$tmp/res.log" 2>&1 || { indent "$tmp/res.log" >&2; fail "corsa regolare con un residuo fallita"; }
c1 "$GV" "$tmp/res/generati" > "$tmp/res.c1" 2>&1 || { indent "$tmp/res.c1" >&2; fail "corsa con un residuo: risultato diverso dai versionati"; }
log "   controprova ok: un residuo diverso nella cartella d'uscita non sopravvive a una corsa regolare"
# Precondizioni: file indicizzato e ingresso assenti, residuo sano al suo posto: nessun risultato resta.
for v in "acct:GOLDEN_ACCTFILE=$tmp/assente.dat:file indicizzato assente" "rec:GOLDEN_INGRESSO=$tmp/assente.rec:ingresso assente"; do
  n="${v%%:*}"; r="${v#*:}"; mkdir -p "$tmp/pre-$n" && cp -R "$tmp/r1/generati" "$tmp/pre-$n/generati" && cp "$tmp/r1/doc.md" "$tmp/pre-$n/doc.md" || fail "residuo non preparato"
  expect_fail "precondizione mancante ($n) con un risultato precedente al suo posto" "${r#*:}" corsa "pre-$n" "${r%%:*}"
  [ ! -e "$tmp/pre-$n/generati" ] && [ ! -e "$tmp/pre-$n/doc.md" ] || fail "PROVA NEGATIVA FALLITA (pre-$n): risultato precedente rimasto"
done
# scenario.sh rifiuta una cartella di scenario gia' presente
mkdir -p "$tmp/sres/s" || fail "residuo non preparato"
expect_fail "scenario.sh con la cartella dello scenario gia' presente" "residuo di una corsa precedente" \
  cnt -- sh /oracle/golden/scenario.sh carica "$R1/golden/esempio/ingresso.rec" - "$(p "$tmp/sres/s")"

log "5. presenza del passo nel controllo dei passi di build/check.sh"
sed -n '/^passi_presenti() {$/,/^}$/p' "$ORACLE_ROOT/build/check.sh" > "$tmp/passi.sh" || fail "passi_presenti non estratta"
grep -q '^PASSI=.* golden:dati ' "$ORACLE_ROOT/build/check.sh" || fail "golden non e' nell'elenco PASSI di build/check.sh"
grep '^PASSI=' "$ORACLE_ROOT/build/check.sh" >> "$tmp/passi.sh" || fail "PASSI non estratto"
mkdir -p "$tmp/radice" || fail "radice di prova non creata"
for d in "$ORACLE_ROOT"/*/; do b="${d%/}"; b="${b##*/}"; mkdir -p "$tmp/radice/$b" || fail "cartella $b non creata"
  for f in run.sh check.sh deps; do [ ! -f "$d$f" ] || cp "$d$f" "$tmp/radice/$b/" || fail "copia di $b/$f fallita"; done; done
( . "$tmp/passi.sh" && passi_presenti "$tmp/radice" ) > "$tmp/pp.out" 2>&1 || { indent "$tmp/pp.out" >&2; fail "controllo dei passi fallito sulla copia integra"; }
rm -rf "$tmp/radice/golden" || fail "cancellazione di golden/ nella copia fallita"
expect_fail "cartella oracle/golden/ cancellata (controllo dei passi di build/check.sh)" "passo golden: manca check.sh" \
  bash -c '. "$1" && passi_presenti "$2"' sh "$tmp/passi.sh" "$tmp/radice"

log "6. esiti dei comandi"
# 6a. Programmi nel container: build/avvolgi.sh davanti nel PATH (registro in /w/registro della corsa). Per ogni
#     comando, la prima, una intermedia e l'ultima invocazione escono con 42 dopo il loro lavoro: run.sh deve fallire e
#     non pubblicare nulla.
W="$tmp/wrap"; mkdir -p "$W" || fail "cartella degli involucri non creata"
cp "$ORACLE_ROOT/build/avvolgi.sh" "$W/.avvolgi.sh" || fail "copia di avvolgi.sh fallita"
w_c="$(in_container "$W")" || fail "involucri fuori da oracle/"
COMANDI="od awk cmp cp mv rm mkdir sed wc dd tr find sort sha256sum mktemp cat ls head tail"
for c in $COMANDI; do
  printf '#!/bin/sh\nm="${GOLDEN_MODO_%s:-passa}"\ncase "$m" in attesa) /usr/bin/sleep 30; m=passa ;; esac\nexec /usr/bin/sh %s/.avvolgi.sh "${GOLDEN_REGISTRO:-/w/registro}" %s "$m" /usr/bin/%s "$@"\n' \
    "$c" "$w_c" "$c" "$c" > "$W/$c" || fail "involucro di $c non scritto"
  chmod +x "$W/$c" || fail "involucro di $c non eseguibile"
done
WP="-e PATH=$w_c:/usr/bin:/bin"
# La corsa con gli involucri in modo passa: run.sh pubblica, risultato identico ai versionati; registro conservato
# (run.sh rimuove la sua cartella temporanea: il registro si scrive anche in /t, montata dal controllo).
corsa invp GOLDEN_DOCKER_EXTRA="$WP" > "$tmp/invp.log" 2>&1 || { indent "$tmp/invp.log" >&2; fail "run.sh con gli involucri in modo passa fallito"; }
c1 "$GV" "$tmp/invp/generati" > "$tmp/invp.c1" 2>&1 || { indent "$tmp/invp.c1" >&2; fail "con gli involucri in modo passa il risultato cambia"; }
log "   controprova ok: con gli involucri in modo passa run.sh riesce e il risultato e' identico ai versionati"
# Il registro e' in /w, cartella temporanea di run.sh: per contare le invocazioni si esegue genera.sh direttamente.
mkdir -p "$tmp/conta/in" && cp "$REC" "$tmp/conta/in/esempio.rec" || fail "conteggio: preparazione fallita"
orun -v "$tmp/conta:/w" -v "$ACCT:/acct/ACCTFILE.dat:ro" -v "$BUILD_OUT/bin:/oracle-bin:ro" -e "PATH=$w_c:/usr/bin:/bin" -- \
  timeout -k 10 900 sh /oracle/golden/genera.sh /oracle/golden/readacct /w > "$tmp/conta.log" 2>&1 || { indent "$tmp/conta.log" >&2; fail "genera.sh con gli involucri fallito"; }
reg="$tmp/conta/registro"; [ -f "$reg" ] || fail "registro degli involucri assente"
# Le righe del registro: "<comando> <invocazione> <esito reale> <esito restituito> /usr/bin/<comando> <argomenti>"; gli
# argomenti possono andare a capo (programmi awk), quindi si contano solo le righe con questa forma.
log "   invocazioni nel container:$(awk '$2 ~ /^[0-9]+$/ && $5 == "/usr/bin/" $1 { if ($2 > n[$1]) n[$1] = $2 } END { for (c in n) printf " %s=%d", c, n[c] }' "$reg")"
for c in $COMANDI; do
  tot="$(awk -v c="$c" '$1 == c && $2 ~ /^[0-9]+$/ && $5 == "/usr/bin/" c { if ($2 > n) n = $2 } END { print n + 0 }' "$reg")" || fail "registro illeggibile"
  [ "$tot" -gt 0 ] || fail "il comando $c non e' mai invocato: elenco COMANDI da rivedere"
  sel="$(printf '%s\n' 1 $(( (tot + 1) / 2 )) "$tot" | LC_ALL=C sort -un)" || fail "selezione delle invocazioni fallita"
  for i in $sel; do
    n="inv-$c-$i"; mkdir -p "$tmp/$n" && cp -R "$tmp/r1/generati" "$tmp/$n/generati" || fail "residuo non preparato"
    expect_fail "$c, invocazione $i di $tot, esce con 42 dopo il suo lavoro (residuo sano al suo posto)" "generazione o verifica dei golden fallita" \
      corsa "$n" GOLDEN_DOCKER_EXTRA="$WP -v $tmp/$n:/r -e GOLDEN_REGISTRO=/r/registro -e GOLDEN_MODO_$c=42@$i"
    [ ! -e "$tmp/$n/generati" ] || fail "PROVA NEGATIVA FALLITA ($n): risultato rimasto"
    r=0; awk -v c="$c" -v i="$i" '$1 == c && $2 == i && $4 == 42 { t = 1 } END { exit !t }' "$tmp/$n/registro" || r=$?
    [ "$r" -eq 0 ] || fail "$c@$i: il comando non e' stato raggiunto (registro $(rel "$tmp/$n/registro"))"
  done
done
# 6b. Limite di tempo: cmp che attende 30 s, limite di genera.sh 20 s.
expect_fail "genera.sh oltre il limite di tempo (cmp che attende 30 s, limite 20 s)" "genera.sh non e' terminato entro 20s" \
  corsa attesa GOLDEN_TIMEOUT=20 GOLDEN_DOCKER_EXTRA="$WP -e GOLDEN_MODO_cmp=attesa"
# 6c. run.sh sull'host: cp, mv, rm, mkdir, docker con esito 42 dopo il loro lavoro.
H="$tmp/hostwrap"; mkdir -p "$H" || fail "cartella degli involucri sull'host non creata"
for c in cp mv rm mkdir docker; do
  vero="$(command -v "$c")" || fail "$c non trovato sull'host"
  printf '#!/bin/sh\nexec sh \047%s\047 \047%s\047 %s "${GOLDEN_MODO_%s:-passa}" \047%s\047 "$@"\n' \
    "$ORACLE_ROOT/build/avvolgi.sh" "$tmp/reg-host" "$c" "$c" "$vero" > "$H/$c" || fail "involucro di $c non scritto"
  chmod +x "$H/$c" || fail "involucro di $c non eseguibile"
done
rm -f "$tmp/reg-host" || fail "registro precedente non rimosso"
corsa hostp PATH="$H:$PATH" > "$tmp/hostp.log" 2>&1 || { indent "$tmp/hostp.log" >&2; fail "run.sh con gli involucri sull'host in modo passa fallito"; }
log "   controprova ok: run.sh con gli involucri sull'host in modo passa riesce; invocazioni:$(awk '{ n[$1]++ } END { for (c in n) printf " %s=%d", c, n[c] }' "$tmp/reg-host")"
for v in "rm@1|risultato precedente non invalidato" "mkdir@1|cartelle di destinazione non create" "cp@1|copia privata dell'ingresso fallita" \
         "mv@1|golden non pubblicati" "mv@2|documento non pubblicato" "docker:/oracle/golden/genera.sh|generazione o verifica dei golden fallita (genera.sh, uscita 42)"; do
  m="${v%%|*}"
  case "$m" in *@*) c="${m%@*}"; modo="42@${m#*@}" ;; *) c="${m%%:*}"; modo="42:${m#*:}" ;; esac
  n="host-$c-${modo//[^a-z0-9]/}"
  rm -f "$tmp/reg-host" || fail "registro precedente non rimosso"
  expect_fail "run.sh: $c ($modo) esce con 42 dopo il suo lavoro" "${v#*|}" corsa "$n" PATH="$H:$PATH" "GOLDEN_MODO_$c=$modo"
  awk -v c="$c" '$1 == c && $4 == 42 { t = 1 } END { exit !t }' "$tmp/reg-host" || fail "run.sh, $c ($modo): il comando non e' stato raggiunto"
  [ ! -e "$tmp/$n/generati" ] && [ ! -e "$tmp/$n/doc.md" ] || fail "run.sh, $c ($modo): risultato rimasto dopo l'errore"
done
log "controllo superato"
