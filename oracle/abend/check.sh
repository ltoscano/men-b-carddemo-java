#!/usr/bin/env bash
# Controllo dello stub CEE3ABD, per le due forme di chiamata (ABDUSING con due argomenti, ABDNOARG senza).
# Atteso, scritto a mano (oracle/abend/expected/):
#   - codice di uscita 99 visto dal processo padre (la shell che ha lanciato il programma);
#   - stdout: solo le righe stampate prima della CALL (nessuna riga "DOPO CEE3ABD": la CALL non ritorna);
#   - stderr: la riga dello stub con ABCODE e TIMING (o "SENZA ARGOMENTI") e la chiusura implicita del
#     file fatta da libcob allo STOP RUN;
#   - ABDFILE.hex: dopo l'arresto il file contiene esattamente il record scritto prima, 20 byte
#     "RECORD-PRIMA-ABEND  ", e non il secondo.
# 1. Riesegue la prova in una cartella nuova. 2. Confronta con gli attesi.
# 3. Prove negative, tra cui due esecuzioni reali con uno stub alterato: uno che ritorna al chiamante
#    (GOBACK al posto di STOP RUN) e uno che termina il processo senza chiudere i file (_exit in C).
. "$ORACLE_ROOT/lib.sh"

PROVE="ABDUSING ABDNOARG"
EXP="$ORACLE_ROOT/abend/expected"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

# verifica OSSERVATI: 0 solo se per entrambe le prove rapporto e contenuto del file coincidono con gli attesi.
verifica() {
  local obs="$1" n errs=0
  for n in $PROVE; do
    if [ ! -f "$obs/$n.txt" ]; then echo "$n: rapporto assente"; errs=$((errs + 1))
    elif ! diff -u "$EXP/$n.txt" "$obs/$n.txt" > "$tmp/d"; then
      echo "$n: rapporto diverso dall'atteso:"; indent "$tmp/d"; errs=$((errs + 1)); fi
    if [ ! -f "$obs/$n.dat.hex" ]; then echo "$n: contenuto di ABDFILE non registrato"; errs=$((errs + 1))
    elif ! diff -u "$EXP/ABDFILE.hex" "$obs/$n.dat.hex" > "$tmp/d"; then
      echo "$n: ABDFILE dopo l'arresto diverso dall'atteso:"; indent "$tmp/d"; errs=$((errs + 1)); fi
  done
  [ "$errs" -eq 0 ] || { echo "verifica fallita: $errs differenze"; return 1; }
  echo "verifica riuscita: codice 99 per entrambe le forme, nessun ritorno dalla CALL, record su disco dopo l'arresto"
}

# variante NOME SORGENTE: compila lo stub CEE3ABD alterato SORGENTE (sotto $tmp) come modulo, lo mette
# accanto a una copia dei due programmi di prova e riesegue la prova con quegli artefatti.
variante() {
  local name="$1" src="$2" b="$tmp/$1/bin"
  mkdir -p "$tmp/$name/build" "$b"
  orun -v "$tmp/$name/build:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh /oracle/build/compile.sh uno modulo "$(in_container "$src")" CEE3ABD /out \
    > "$tmp/$name.log" 2>&1 || { cat "$tmp/$name.log" >&2; fail "compilazione della variante '$name' fallita"; }
  cp "$tmp/$name/build/bin/CEE3ABD.so" "$b/" && cp "$BUILD_OUT/bin/ABDUSING" "$BUILD_OUT/bin/ABDNOARG" "$b/" \
    || fail "preparazione degli artefatti della variante '$name' fallita"
  ABEND_BIN_DIR="$b" ABEND_OUT_DIR="$tmp/$name/obs" bash "$ORACLE_ROOT/abend/run.sh" >> "$tmp/$name.log" 2>&1 \
    || { cat "$tmp/$name.log" >&2; fail "esecuzione della variante '$name' fallita"; }
}

log "1. prova di CEE3ABD rieseguita in una cartella nuova"
ABEND_OUT_DIR="$tmp/obs" bash "$ORACLE_ROOT/abend/run.sh" || fail "prova di CEE3ABD fallita"

log "2. confronto con gli attesi"
verifica "$tmp/obs" > "$tmp/v.out" 2>&1 || { cat "$tmp/v.out" >&2; fail "lo stub CEE3ABD non si comporta come atteso"; }
sed 's/^/   /' "$tmp/v.out" >&2

log "3. prove negative"
# a) stub che ritorna al chiamante: il programma prosegue, scrive il secondo record e termina con 0.
mkdir -p "$tmp/src"
cp "$ORACLE_ROOT/stubs/CEE3ABD.cbl" "$tmp/src/CEE3ABD.cbl"
mutate "$tmp/src/CEE3ABD.cbl" 's/^           STOP RUN\.$/           GOBACK./'
variante ritorna "$tmp/src/CEE3ABD.cbl"
expect_fail "stub CEE3ABD che ritorna: secondo record nel file" "ABDUSING: ABDFILE dopo l'arresto diverso" verifica "$tmp/ritorna/obs"
expect_fail "stub CEE3ABD che ritorna: codice 0 e riga DOPO CEE3ABD" "+ABDNOARG DOPO CEE3ABD" verifica "$tmp/ritorna/obs"
# b) stub che termina subito il processo con 99 senza la chiusura dei file di libcob (_exit in C).
cat > "$tmp/src/CEE3ABD.c" <<'EOF'
/* Variante per la prova negativa: termina il processo con 99 senza chiudere i file (niente STOP RUN). */
#include <unistd.h>
int CEE3ABD (void) { _exit (99); }
EOF
variante senza-chiusura "$tmp/src/CEE3ABD.c"
expect_fail "stub CEE3ABD che esce con _exit(99) senza messaggio ne' chiusura" "ABDUSING: rapporto diverso" verifica "$tmp/senza-chiusura/obs"
# Fatto osservato e verificato (vedi README): anche senza la chiusura dei file il record scritto prima
# e' gia' su disco, cioe' libcob 3.2 non trattiene in memoria i record di un file sequenziale.
for n in $PROVE; do
  cmp -s "$EXP/ABDFILE.hex" "$tmp/senza-chiusura/obs/$n.dat.hex" \
    || fail "fatto non piu' vero: con _exit senza chiusura il record di $n non e' su disco ($(cat "$tmp/senza-chiusura/obs/$n.dat.hex")); aggiornare README"
done
log "   fatto verificato: anche uscendo con _exit, senza chiudere i file, il record scritto prima e' su disco"
# c) alterazioni delle evidenze.
mkdir -p "$tmp/hex"; cp "$tmp/obs"/*.txt "$tmp/obs"/*.hex "$tmp/hex/"
mutate "$tmp/hex/ABDNOARG.dat.hex" 's/ 20 20$/ 20 21/'
expect_fail "byte di ABDFILE alterati (ABDNOARG)" "ABDNOARG: ABDFILE dopo l'arresto diverso" verifica "$tmp/hex"
mkdir -p "$tmp/manca"; cp "$tmp/obs"/*.txt "$tmp/obs"/ABDNOARG.dat.hex "$tmp/manca/"
expect_fail "contenuto di ABDFILE non registrato (ABDUSING)" "ABDUSING: contenuto di ABDFILE non registrato" verifica "$tmp/manca"
mkdir -p "$tmp/codice"; cp "$tmp/obs"/*.txt "$tmp/obs"/*.hex "$tmp/codice/"
mutate "$tmp/codice/ABDNOARG.txt" '2s/^99$/1/'
expect_fail "codice di uscita di ABDNOARG 99 -> 1" "ABDNOARG: rapporto diverso" verifica "$tmp/codice"
log "controllo superato"
