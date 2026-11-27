#!/usr/bin/env bash
# Controllo di MVSWAIT (oracle/stubs/MVSWAIT.cbl) e dell'opzione --sysin di oracle/esegui.sh (issue #36),
# chiamato da routines/check.sh. Attesi scritti a mano dal sorgente: mvswait-attesi/ (tabella in
# mvswait-casi.md e .tsv); osservazioni, non attesi: mvswait-osservati/ (mvswait-osservazioni.md).
# 1. Riesegue tutti i casi in una cartella nuova (mvswait-run.sh, limite operativo di 3 s per esecuzione).
# 2. Coerenza tra tabella, casi, attesi, schede e osservazioni (mvswait-coerenza.sh).
# 3. Confronto esatto, caso per caso, del rapporto e dell'ambiente ricevuto, per i casi ricavati e per le
#    osservazioni; nessun rapporto in piu'.
# 4. Retrocompatibilita' di esegui.sh senza --sysin: a parita' di programma e moduli (COBSWAIT con il
#    segnaposto di #4), il rapporto coincide con quello di riferimento, prodotto dalla versione precedente
#    dello script (mvswait-riferimento/).
# 5. Prove negative: varianti reali della routine, esegui.sh alterato o con un comando che fallisce,
#    --sysin sbagliato, attesi, tabella, casi e schede alterati, evidenze mancanti o in piu', residui.
. "$ORACLE_ROOT/lib.sh"

DIR="$ORACLE_ROOT/routines"
TAB="$DIR/mvswait-casi.tsv"
PROVE="$DIR/mvswait-prove.tsv"
ATT="$DIR/mvswait-attesi"
OSS="$DIR/mvswait-osservazioni.tsv"
OSSD="$DIR/mvswait-osservati"
RIF="$DIR/mvswait-riferimento"
JCL="$LEGACY/app/jcl/WAITSTEP.jcl"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT
require_legacy
require_build

# casi_di FILE: i nomi dei casi, uno per riga (righe non commento, intestazione esclusa).
casi_di() {
  local righe n=0 caso resto
  righe="$(grep -v '^#' "$1")" || return 1
  while IFS="	" read -r caso resto; do
    n=$((n + 1))
    if [ "$n" -gt 1 ] && [ -n "$caso" ]; then echo "$caso"; fi
  done <<< "$righe"
}
PROVE_CASI="$(casi_di "$PROVE")" || fail "lettura dei casi di $(rel "$PROVE") fallita"
OSS_CASI="$(casi_di "$OSS")" || fail "lettura delle osservazioni di $(rel "$OSS") fallita"
[ -n "$PROVE_CASI" ] && [ -n "$OSS_CASI" ] || fail "nessun caso o nessuna osservazione"
# shellcheck disable=SC2086
TUTTI=" $(echo $PROVE_CASI $OSS_CASI) "

# confronto CASO ATTESO OSSERVATO: 0 se i due file coincidono; altrimenti stampa la differenza.
confronto() {
  local r=0
  [ -f "$2" ] || { echo "$1: atteso assente ($(rel "$2"))"; return 1; }
  [ -f "$3" ] || { echo "$1: rapporto assente ($(rel "$3"))"; return 1; }
  diff -u "$2" "$3" > "$tmp/d" || r=$?
  case "$r" in
    0) return 0 ;;
    1) echo "$1: rapporto diverso dall'atteso ($(rel "$2")):"; indent "$tmp/d"; return 1 ;;
    *) echo "$1: confronto fallito (diff, codice $r)"; return 1 ;;
  esac
}
# fuori_elenco CARTELLA: i file .txt della cartella che non sono di un caso o di un'osservazione.
fuori_elenco() {
  local n f s=""
  n="$(ls -A "$1")" || { echo "cartella non elencabile: $(rel "$1")"; return 1; }
  for f in $n; do
    case "$f" in *.txt) case "$TUTTI" in *" ${f%.txt} "*) ;; *) s="$s ${f%.txt}" ;; esac ;; esac
  done
  [ -z "$s" ] || { echo "rapporti o attesi non previsti in $(rel "$1"):$s"; return 1; }
}
# verifica OSSERVATI [ATTESI] [OSSERVATI-REGISTRATI]: 0 solo se ogni caso e ogni osservazione hanno il
# rapporto atteso, l'ambiente fissato, e non ci sono rapporti o attesi in piu'.
verifica() {
  local obs="$1" att="${2:-$ATT}" od="${3:-$OSSD}" c errs=0
  for c in $PROVE_CASI; do confronto "$c" "$att/$c.txt" "$obs/$c.txt" || errs=$((errs + 1)); done
  for c in $OSS_CASI; do confronto "$c" "$od/$c.txt" "$obs/$c.txt" || errs=$((errs + 1)); done
  for c in $PROVE_CASI $OSS_CASI; do
    if [ ! -f "$obs/$c.ambiente" ]; then echo "$c: ambiente non registrato"; errs=$((errs + 1))
    elif ! diff -u "$att/ambiente" "$obs/$c.ambiente" > "$tmp/d"; then
      echo "$c: ambiente diverso da quello fissato:"; indent "$tmp/d"; errs=$((errs + 1)); fi
  done
  fuori_elenco "$obs" || errs=$((errs + 1))
  fuori_elenco "$att" || errs=$((errs + 1))
  fuori_elenco "$od" || errs=$((errs + 1))
  [ "$errs" -eq 0 ] || { echo "verifica fallita: $errs differenze"; return 1; }
  echo "verifica riuscita: $(echo $PROVE_CASI | wc -w | tr -d ' ') casi ricavati e $(echo $OSS_CASI | wc -w | tr -d ' ') osservazioni come registrati"
}
# impronte SCHEDE FILE: "<caso> <byte> <sha256>" per ogni scheda, calcolati nel container (non da esegui.sh).
impronte() {
  orun -v "$1:/s:ro" -- timeout -k 10 60 sh -c '
    set -u
    cd /s || exit 1
    for f in *.sysin; do
      [ -f "$f" ] || exit 1
      b="$(wc -c < "$f")" || exit 1
      s="$(sha256sum < "$f")" || exit 1
      b="${b#"${b%%[! ]*}"}"
      echo "${f%.sysin} $b ${s%% *}" || exit 1
    done' > "$2"
}
coerenza() { # coerenza [TABELLA] [PROVE] [ATTESI] [OSSERVAZIONI] [OSSERVATI] [SCHEDE] [IMPRONTE]
  bash "$DIR/mvswait-coerenza.sh" "${1:-$TAB}" "${2:-$PROVE}" "${3:-$ATT}" "${4:-$OSS}" "${5:-$OSSD}" \
    "${6:-$tmp/obs/schede}" "${7:-$tmp/impronte}" "$JCL"
}

log "M1. MVSWAIT: casi rieseguiti in una cartella nuova (limite operativo 3 s per esecuzione)"
MVSWAIT_OUT_DIR="$tmp/obs" bash "$DIR/mvswait-run.sh" || fail "prova di MVSWAIT fallita"

log "M2. coerenza tra tabella, casi, attesi, schede e osservazioni"
impronte "$tmp/obs/schede" "$tmp/impronte" || fail "impronte delle schede non calcolabili"
coerenza > "$tmp/c.out" 2>&1 || { indent "$tmp/c.out" >&2; fail "tabella, casi, attesi e osservazioni di MVSWAIT non coerenti"; }
indent "$tmp/c.out" >&2

log "M3. confronto con gli attesi e con le osservazioni registrate"
verifica "$tmp/obs" > "$tmp/v.out" 2>&1 || { cat "$tmp/v.out" >&2; fail "MVSWAIT non si comporta come atteso"; }
indent "$tmp/v.out" >&2

# --- varianti reali della routine ----------------------------------------------------------------------
# sorgente NOME ESPRESSIONE-SED...: copia di MVSWAIT.cbl in $tmp/src-NOME/, alterata con sed di GNU nel
# container (stessa sed in locale e in CI); ogni espressione deve cambiare il file.
sorgente() {
  local name="$1" d="$tmp/src-$1" r; shift
  mkdir -p "$d" && cp "$ORACLE_ROOT/stubs/MVSWAIT.cbl" "$d/MVSWAIT.cbl" || fail "copia della routine per '$name' fallita"
  while [ $# -gt 0 ]; do
    cp "$d/MVSWAIT.cbl" "$d/prima" || fail "copia di lavoro per '$name' fallita"
    orun -v "$d:/v" -- timeout -k 10 60 sed -i -e "$1" /v/MVSWAIT.cbl || fail "sed fallita sulla variante '$name'"
    r=0; cmp -s "$d/prima" "$d/MVSWAIT.cbl" || r=$?
    case "$r" in
      0) fail "variante '$name': l'espressione '$1' non altera la routine" ;;
      1) ;;
      *) fail "variante '$name': confronto fallito (cmp, codice $r)" ;;
    esac
    shift
  done
}
# prepara NOME SORGENTE: compila SORGENTE come modulo MVSWAIT con le opzioni fissate e lo mette in
# $tmp/NOME/bin accanto a copie di WAITPRB e COBSWAIT della build.
prepara() {
  local name="$1" src="$2" b="$tmp/$1/bin"
  mkdir -p "$tmp/$name/build" "$b" || fail "cartelle della variante '$name' non creabili"
  orun -v "$tmp/$name/build:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh /oracle/build/compile.sh uno modulo "$(in_container "$src")" MVSWAIT /out \
    > "$tmp/$name.log" 2>&1 || { cat "$tmp/$name.log" >&2; fail "compilazione della variante '$name' fallita"; }
  cp "$tmp/$name/build/bin/MVSWAIT.so" "$BUILD_OUT/bin/WAITPRB" "$BUILD_OUT/bin/COBSWAIT" "$b/" \
    || fail "preparazione degli artefatti della variante '$name' fallita"
}
# esegui_variante NOME [CARTELLA-OUT]: tutti i casi con gli artefatti della variante (ritorna l'esito).
esegui_variante() {
  MVSWAIT_BIN_DIR="$tmp/$1/bin" MVSWAIT_OUT_DIR="${2:-$tmp/$1/obs}" bash "$DIR/mvswait-run.sh"
}
variante() { # variante NOME: prepara ed esegue; l'esecuzione deve completarsi
  prepara "$1" "$tmp/src-$1/MVSWAIT.cbl"
  esegui_variante "$1" >> "$tmp/$1.log" 2>&1 || { cat "$tmp/$1.log" >&2; fail "esecuzione della variante '$1' fallita"; }
}

log "M4. retrocompatibilita' di esegui.sh senza --sysin"
# Il segnaposto di #4 (oracle/stubs/MVSWAIT.cbl prima della issue #36), testo invariato.
mkdir -p "$tmp/src-segnaposto" || fail "cartella del segnaposto non creabile"
cat > "$tmp/src-segnaposto/MVSWAIT.cbl" <<'EOF' || fail "scrittura del segnaposto fallita"
      *****************************************************************
      * MVSWAIT - segnaposto dell'oracle MEN-B (non e' codice del
      * legacy). Nel legacy MVSWAIT e' una routine assembler
      * (app/asm/MVSWAIT.asm) che attende un tempo dato, chiamata da
      * COBSWAIT. La sua semantica non e' implementata qui (issue #24):
      * se viene chiamata, scrive una riga riconoscibile su stderr e
      * termina l'esecuzione con codice di uscita 98, fisso.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MVSWAIT.
       PROCEDURE DIVISION.
           DISPLAY 'MENB-ORACLE SEGNAPOSTO: MVSWAIT NON IMPLEMENTATO'
                   ' (ISSUE #24)'
                   UPON SYSERR
           MOVE 98 TO RETURN-CODE
           STOP RUN.
EOF
prepara segnaposto "$tmp/src-segnaposto/MVSWAIT.cbl"
# retro NOME [ESEGUI]: COBSWAIT con il segnaposto, senza --sysin, con esegui.sh (o con una sua copia).
retro() {
  local d="$tmp/retro-$1" e="/oracle/esegui.sh"
  [ -z "${2:-}" ] || e="$(in_container "$2")" || return 1
  clean_dir "$d"
  orun -v "$d:/out" -v "$tmp/segnaposto/bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN=3 \
    -- timeout -k 10 60 sh "$e" /out COBSWAIT || { echo "esegui.sh fallito per la prova di retrocompatibilita'"; return 1; }
  cmp -s "$RIF/COBSWAIT-segnaposto.txt" "$d/COBSWAIT.txt" \
    || { diff -u "$RIF/COBSWAIT-segnaposto.txt" "$d/COBSWAIT.txt" > "$tmp/d"; echo "rapporto di riferimento diverso:"; indent "$tmp/d"; return 1; }
  cmp -s "$ATT/ambiente" "$d/COBSWAIT.ambiente" || { echo "ambiente diverso da quello fissato"; return 1; }
}
retro attuale > "$tmp/r.out" 2>&1 || { indent "$tmp/r.out" >&2; fail "esegui.sh senza --sysin non riproduce il rapporto di riferimento"; }
log "   controprova ok: COBSWAIT con il segnaposto, senza --sysin: rapporto identico a quello di riferimento ($(rel "$RIF/COBSWAIT-segnaposto.txt"))"
cp "$ORACLE_ROOT/esegui.sh" "$tmp/esegui-sempre.sh" || fail "copia di esegui.sh fallita"
mutate "$tmp/esegui-sempre.sh" 's/^  \[ "\$hasysin" -eq 1 \] || return 0$/  [ "$hasysin" -eq 1 ] || { echo "== sysin"; return 0; }/'
expect_fail "esegui.sh che scrive la sezione == sysin anche senza l'opzione" "rapporto di riferimento diverso" retro sempre "$tmp/esegui-sempre.sh"

log "M5. prove negative"
# 1. Il segnaposto di #4 al posto della routine: COBSWAIT (e ogni caso) termina con 98.
esegui_variante segnaposto >> "$tmp/segnaposto.log" 2>&1 || { cat "$tmp/segnaposto.log" >&2; fail "esecuzione con il segnaposto fallita"; }
expect_fail "segnaposto di #4 al posto di MVSWAIT (COBSWAIT, caso S1)" "S1: rapporto diverso dall'atteso" verifica "$tmp/segnaposto/obs"
for c in $PROVE_CASI $OSS_CASI; do
  rc="$(sed -n 2p "$tmp/segnaposto/obs/$c.txt")" || fail "rapporto di $c illeggibile"
  [ "$rc" = 98 ] || fail "con il segnaposto il caso $c non termina con 98: il modulo caricato non e' quello della variante"
done
log "   e con il segnaposto ogni caso termina con 98: il modulo caricato e' quello in /oracle-bin"

# 2. Routine alterate. Le espressioni di sed agiscono su righe intere della routine.
R0='^           MOVE 0 TO RETURN-CODE$'
sorgente argomento "s/$R0/           MOVE X'00' TO LK-INTERVALLO(4:1)\n           MOVE 0 TO RETURN-CODE/"
variante argomento
grep -qx 'DOPO  a5a5a5a5 00000000 a5a5a5a5' "$tmp/argomento/obs/D00000001.txt" \
  || fail "la variante 'argomento' non ha modificato l'argomento: prova negativa non significativa"
expect_fail "routine che modifica l'argomento (quarto byte azzerato)" "D00000001: rapporto diverso dall'atteso" verifica "$tmp/argomento/obs"
sorgente codice "s/$R0/           MOVE 4 TO RETURN-CODE/"
variante codice
expect_fail "routine che restituisce 4" "+RC  000000004" verifica "$tmp/codice/obs"
expect_fail "routine che restituisce 4 (COBSWAIT termina con 4)" "S1: rapporto diverso dall'atteso" verifica "$tmp/codice/obs"
sorgente stdout "s/$R0/           DISPLAY 'MVSWAIT SU STDOUT'\n           MOVE 0 TO RETURN-CODE/"
variante stdout
expect_fail "routine che scrive su stdout" "+MVSWAIT SU STDOUT" verifica "$tmp/stdout/obs"
# Attesa vera dell'intervallo richiesto (C\$SLEEP, secondi = centesimi / 100): 36 s per D00000E10, oltre il
# limite operativo; la prova fallisce per durata e non resta appesa.
sorgente attende "s/^      \* Riga 23 (ASMWAIT): l'attesa non e' eseguita\.\$/           COMPUTE WS-HI = WS-VALORE \/ 100\n           CALL 'C\$SLEEP' USING WS-HI/"
prepara attende "$tmp/src-attende/MVSWAIT.cbl"
t0="$(date +%s)" || fail "date fallito"
expect_fail "routine che attende davvero l'intervallo richiesto" "esegui.sh: WAITPRB non e' terminato entro 3s" esegui_variante attende
t1="$(date +%s)" || fail "date fallito"
[ $((t1 - t0)) -lt 60 ] || fail "la variante 'attende' ha impiegato $((t1 - t0)) s: il limite operativo non e' stato applicato"
log "     (fallita per durata in $((t1 - t0)) s, sotto i 36 s richiesti da D00000E10)"
sorgente bitalto 's/^           IF WS-VALORE > 2147483647$/           IF WS-VALORE > 4294967295/'
variante bitalto
expect_fail "routine che ritorna 0 anche con il bit alto acceso (X'80000000')" "D80000000: rapporto diverso dall'atteso" verifica "$tmp/bitalto/obs"
expect_fail "routine che ritorna 0 anche con il bit alto acceso (X'FFFFFFFF')" "DFFFFFFFF: rapporto diverso dall'atteso" verifica "$tmp/bitalto/obs"

# 3. Valore riportato con l'ordine dei byte invertito, o con il segno.
sorgente ordine 's/^           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > 4$/           PERFORM VARYING WS-I FROM 4 BY -1 UNTIL WS-I < 1/'
variante ordine
expect_fail "routine che legge i 4 byte in ordine inverso (little-endian)" "D00000E10: rapporto diverso dall'atteso" verifica "$tmp/ordine/obs"
sorgente segno \
  's/^           MOVE WS-VALORE TO WS-DEC$/           IF WS-VALORE > 2147483647\n               SUBTRACT 4294967296 FROM WS-VALORE\n           END-IF\n           MOVE WS-VALORE TO WS-DEC/' \
  's/^       01  WS-DEC                  PIC 9(10)\.$/       01  WS-DEC                  PIC -9(10)./'
variante segno
grep -q "ATTESA RICHIESTA -2147483648" "$tmp/segno/obs/D80000000.txt" \
  || fail "la variante 'segno' non riporta il valore con il segno: prova negativa non significativa"
expect_fail "routine che legge l'argomento con segno (X'80000000' = -2147483648)" "D80000000: rapporto diverso dall'atteso" verifica "$tmp/segno/obs"

# 4. --sysin sbagliato o ignorato.
# sysin_diretto ARGOMENTI...: COBSWAIT con esegui.sh e gli argomenti dati (le schede di M1 su /s).
sysin_diretto() {
  local d="$tmp/diretto"
  clean_dir "$d"
  orun -v "$d:/out" -v "$BUILD_OUT/bin:/oracle-bin:ro" -v "$tmp/obs/schede:/s:ro" -e ORACLE_TIMEOUT_RUN=3 \
    -- timeout -k 10 60 sh /oracle/esegui.sh /out COBSWAIT "$@"
}
expect_fail "--sysin con un file inesistente" "esegui.sh: --sysin: file assente o illeggibile: '/s/nonesiste.sysin'" sysin_diretto --sysin /s/nonesiste.sysin
expect_fail "--sysin con una cartella" "esegui.sh: --sysin: file assente o illeggibile: '/s'" sysin_diretto --sysin /s
expect_fail "--sysin con un percorso relativo" "esegui.sh: --sysin ammette solo un percorso assoluto: 'S1.sysin'" sysin_diretto --sysin S1.sysin
expect_fail "--sysin senza file" "esegui.sh: --sysin senza file" sysin_diretto --sysin
expect_fail "--sysin ripetuto" "esegui.sh: --sysin ripetuto" sysin_diretto --sysin /s/S1.sysin --sysin /s/S2.sysin
cp "$ORACLE_ROOT/esegui.sh" "$tmp/esegui-ignora.sh" || fail "copia di esegui.sh fallita"
mutate "$tmp/esegui-ignora.sh" 's#< "\$ingresso" >#< /dev/null >#g'
MVSWAIT_ESEGUI="$tmp/esegui-ignora.sh" MVSWAIT_OUT_DIR="$tmp/ignora" bash "$DIR/mvswait-run.sh" > "$tmp/ignora.log" 2>&1 \
  || { cat "$tmp/ignora.log" >&2; fail "esecuzione con esegui.sh che ignora --sysin fallita"; }
grep -qx '== sysin' "$tmp/ignora/S1.txt" || fail "con esegui.sh alterato manca la sezione == sysin: prova negativa non significativa"
expect_fail "esegui.sh che ignora --sysin (ingresso vuoto al posto della scheda)" "S1: rapporto diverso dall'atteso" verifica "$tmp/ignora"

# 4b. Esiti dei comandi nuovi di esegui.sh (wc e sha256sum su --sysin): l'involucro build/avvolgi.sh, davanti
#     nel PATH del container, esegue davvero il comando e ne cambia solo l'esito (o tronca l'output).
avvolto() { # avvolto NOME COMANDO=MODO...: COBSWAIT con --sysin /s/S1.sysin e i comandi avvolti
  local d="$tmp/av-$1" s c m; shift
  clean_dir "$d"
  mkdir -p "$d/avv" "$d/res/out" || fail "cartelle degli involucri non creabili"
  cp "$ORACLE_ROOT/build/avvolgi.sh" "$d/avv/.avvolgi.sh" || fail "copia di avvolgi.sh fallita"
  for s in "$@"; do
    c="${s%%=*}"; m="${s#*=}"
    case "$m" in
      # finto:TESTO: al posto del comando, uno script che stampa TESTO ed esce con 0 (risposta malformata).
      finto:*) printf '#!/bin/sh\necho '\''%s'\''\n' "${m#finto:}" > "$d/avv/$c" ;;
      *) printf '#!/bin/sh\nexec sh /avv/.avvolgi.sh /res/registro %s '\''%s'\'' /usr/bin/%s "$@"\n' "$c" "$m" "$c" > "$d/avv/$c" ;;
    esac
    chmod +x "$d/avv/$c" || fail "involucro di $c non creabile"
  done
  orun -v "$d/avv:/avv:ro" -v "$d/res:/res" -v "$BUILD_OUT/bin:/oracle-bin:ro" -v "$tmp/obs/schede:/s:ro" \
    -e PATH=/avv:/usr/bin:/bin -e ORACLE_TIMEOUT_RUN=3 \
    -- timeout -k 10 60 sh /oracle/esegui.sh /res/out COBSWAIT --sysin /s/S1.sysin
}
# raggiunto REGISTRO COMANDO ESITO-RESTITUITO: il comando avvolto e' stato eseguito con esito reale 0.
raggiunto() {
  awk -v c="$2" -v r="$3" '$1==c && $3==0 && $4==r {n++} END {exit !(n>0)}' "$1" \
    || fail "comando $2 non raggiunto o non avvolto come atteso (registro $(rel "$1"))"
}
avvolto passa wc=passa sha256sum=passa > "$tmp/av-passa.log" 2>&1 || { indent "$tmp/av-passa.log" >&2; fail "controprova: esegui.sh con gli involucri in modo passa fallito"; }
cmp -s "$tmp/obs/S1.txt" "$tmp/av-passa/res/out/COBSWAIT.txt" || fail "controprova: rapporto con gli involucri in modo passa diverso da quello di S1"
raggiunto "$tmp/av-passa/res/registro" wc 0
raggiunto "$tmp/av-passa/res/registro" sha256sum 0
log "   controprova ok: esegui.sh --sysin con wc e sha256sum avvolti in modo passa, rapporto identico a quello di S1"
expect_fail "esegui.sh --sysin con wc che restituisce 42" "esegui.sh: --sysin: dimensione non leggibile (wc)" avvolto wc42 wc=42 sha256sum=passa
raggiunto "$tmp/av-wc42/res/registro" wc 42
expect_fail "esegui.sh --sysin con sha256sum che restituisce 42" "esegui.sh: --sysin: impronta non calcolabile (sha256sum)" avvolto sha42 wc=passa sha256sum=42
raggiunto "$tmp/av-sha42/res/registro" sha256sum 42
expect_fail "esegui.sh --sysin con sha256sum che scrive un output parziale ed esce con 42 (T42)" "esegui.sh: --sysin: impronta non calcolabile (sha256sum)" avvolto shaT42 wc=passa sha256sum=T42
raggiunto "$tmp/av-shaT42/res/registro" sha256sum 42
expect_fail "esegui.sh --sysin con wc che risponde con un testo non numerico (esito 0)" "esegui.sh: --sysin: dimensione non valida: 'ottantuno'" avvolto wcfinto wc=finto:ottantuno sha256sum=passa
expect_fail "esegui.sh --sysin con sha256sum che risponde con un'impronta troncata (esito 0)" "esegui.sh: --sysin: impronta non valida: '59f72f438a92'" avvolto shacorta wc=passa 'sha256sum=finto:59f72f438a92  -'
expect_fail "esegui.sh --sysin con sha256sum che risponde con caratteri non esadecimali (esito 0)" "esegui.sh: --sysin: impronta non valida: 'IMPRONTA'" avvolto shanonhex wc=passa 'sha256sum=finto:IMPRONTA  -'
for d in wc42 sha42 shaT42 wcfinto shacorta shanonhex; do
  [ ! -e "$tmp/av-$d/res/out/COBSWAIT.txt" ] || fail "con $d esegui.sh ha scritto comunque un rapporto"
done
log "     e in nessuno di questi casi esegui.sh ha scritto un rapporto"

# 4c. Esiti dei comandi di mvswait-run.sh nel container (sed che ricava le schede, mv dei rapporti) e del
#     calcolo delle impronte: ogni docker run della sottoshell ha gli involucri davanti nel PATH.
run_avvolto() { # run_avvolto NOME COMANDO=MODO: mvswait-run.sh con il comando avvolto
  local d="$tmp/ra-$1" s="$2" c m
  clean_dir "$d"
  mkdir -p "$d/avv" "$d/res" || fail "cartelle degli involucri non creabili"
  cp "$ORACLE_ROOT/build/avvolgi.sh" "$d/avv/.avvolgi.sh" || fail "copia di avvolgi.sh fallita"
  c="${s%%=*}"; m="${s#*=}"
  printf '#!/bin/sh\nexec sh /avv/.avvolgi.sh /res/registro %s '\''%s'\'' /usr/bin/%s "$@"\n' "$c" "$m" "$c" > "$d/avv/$c" \
    && chmod +x "$d/avv/$c" || fail "involucro di $c non creabile"
  (
    AVV_D="$d"
    docker() {
      if [ "${1:-}" = run ]; then shift; command docker run -e PATH=/avv:/usr/bin:/bin -v "$AVV_D/avv:/avv:ro" -v "$AVV_D/res:/res" "$@"
      else command docker "$@"; fi
    }
    export -f docker; export AVV_D
    MVSWAIT_OUT_DIR="$d/obs" bash "$DIR/mvswait-run.sh"
  )
}
expect_fail "mvswait-run.sh con sed (scheda dal JCL) che restituisce 42" "scheda di S1 non ricavabile dal JCL" run_avvolto sed sed=42
raggiunto "$tmp/ra-sed/res/registro" sed 42
expect_fail "mvswait-run.sh con mv (rapporto del caso) che restituisce 42" "esecuzione dei casi di MVSWAIT fallita" run_avvolto mv mv=42
raggiunto "$tmp/ra-mv/res/registro" mv 42
impronte_avvolte() { # impronte_avvolte NOME COMANDO=MODO: impronte delle schede di M1 con il comando avvolto
  local d="$tmp/ia-$1" s="$2" c m
  clean_dir "$d"
  mkdir -p "$d/avv" "$d/res" || fail "cartelle degli involucri non creabili"
  cp "$ORACLE_ROOT/build/avvolgi.sh" "$d/avv/.avvolgi.sh" || fail "copia di avvolgi.sh fallita"
  c="${s%%=*}"; m="${s#*=}"
  printf '#!/bin/sh\nexec sh /avv/.avvolgi.sh /res/registro %s '\''%s'\'' /usr/bin/%s "$@"\n' "$c" "$m" "$c" > "$d/avv/$c" \
    && chmod +x "$d/avv/$c" || fail "involucro di $c non creabile"
  (
    docker() {
      if [ "${1:-}" = run ]; then shift; command docker run -e PATH=/avv:/usr/bin:/bin -v "$d/avv:/avv:ro" -v "$d/res:/res" "$@"
      else command docker "$@"; fi
    }
    impronte "$tmp/obs/schede" "$d/impronte" || { echo "impronte delle schede non calcolabili"; exit 1; }
    coerenza "" "" "" "" "" "" "$d/impronte"
  )
}
expect_fail "impronte delle schede con sha256sum che restituisce 42" "impronte delle schede non calcolabili" impronte_avvolte sha sha256sum=42
raggiunto "$tmp/ia-sha/res/registro" sha256sum 42
expect_fail "impronte delle schede con wc che restituisce 42" "impronte delle schede non calcolabili" impronte_avvolte wc wc=42
raggiunto "$tmp/ia-wc/res/registro" wc 42

# 5. Attesi, osservazioni e ambiente alterati di un byte; casi e attesi che non si corrispondono.
#    Un byte: l'ultimo carattere della riga di MVSWAIT su stderr diventa '#'.
for c in $PROVE_CASI; do
  rm -rf "$tmp/a1"; mkdir -p "$tmp/a1"; cp "$ATT"/* "$tmp/a1/"
  mutate "$tmp/a1/$c.txt" '/^MENB-ORACLE MVSWAIT: /s/.$/#/'
  expect_fail "atteso di $c con un byte alterato" "$c: rapporto diverso dall'atteso" verifica "$tmp/obs" "$tmp/a1"
  expect_fail "atteso di $c con un byte alterato: diverge dalla tabella" "$c: l atteso scritto a mano diverge dalla tabella" coerenza "" "" "$tmp/a1"
done
for c in $OSS_CASI; do
  rm -rf "$tmp/o1"; mkdir -p "$tmp/o1"; cp "$OSSD"/* "$tmp/o1/"
  mutate "$tmp/o1/$c.txt" '/^MENB-ORACLE MVSWAIT: /s/.$/#/'
  expect_fail "osservazione registrata di $c con un byte alterato" "$c: rapporto diverso dall'atteso" verifica "$tmp/obs" "" "$tmp/o1"
done
rm -rf "$tmp/a2"; mkdir -p "$tmp/a2"; cp "$ATT"/* "$tmp/a2/"
mutate "$tmp/a2/ambiente" 's#^COB_LIBRARY_PATH=/oracle-bin$#COB_LIBRARY_PATH=/altrove#'
expect_fail "ambiente atteso con un'altra cartella dei moduli" "S1: ambiente diverso da quello fissato" verifica "$tmp/obs" "$tmp/a2"
rm -rf "$tmp/a3"; mkdir -p "$tmp/a3"; cp "$ATT"/* "$tmp/a3/"; rm "$tmp/a3/D05F5E100.txt"
expect_fail "caso senza atteso (D05F5E100)" "D05F5E100: atteso assente" verifica "$tmp/obs" "$tmp/a3"
expect_fail "caso senza atteso (D05F5E100): coerenza" "D05F5E100: atteso assente o vuoto" coerenza "" "" "$tmp/a3"
rm -rf "$tmp/a4"; mkdir -p "$tmp/a4"; cp "$ATT"/* "$tmp/a4/"; cp "$tmp/a4/D00000001.txt" "$tmp/a4/D00000002.txt"
expect_fail "atteso senza caso (D00000002)" "rapporti o attesi non previsti in" verifica "$tmp/obs" "$tmp/a4"
expect_fail "atteso senza caso (D00000002): coerenza" "attesi: D00000002.txt non corrisponde a nessun caso" coerenza "" "" "$tmp/a4"
rm -rf "$tmp/o2"; mkdir -p "$tmp/o2"; cp "$OSSD"/* "$tmp/o2/"; rm "$tmp/o2/O3.txt"
expect_fail "osservazione senza rapporto registrato (O3)" "O3: atteso assente" verifica "$tmp/obs" "" "$tmp/o2"
expect_fail "osservazione senza rapporto registrato (O3): coerenza" "osservazioni: O3: rapporto osservato assente o vuoto" coerenza "" "" "" "" "$tmp/o2"
rm -rf "$tmp/o3"; mkdir -p "$tmp/o3"; cp "$OSSD"/* "$tmp/o3/"; cp "$tmp/o3/O1.txt" "$tmp/o3/O9.txt"
expect_fail "rapporto osservato senza osservazione (O9): coerenza" "osservati: O9.txt non corrisponde a nessuna osservazione" coerenza "" "" "" "" "$tmp/o3"
rm -rf "$tmp/o4"; mkdir -p "$tmp/o4"; cp "$OSSD"/* "$tmp/o4/"
mutate "$tmp/o4/O2.txt" 's/^fornito: 5 byte/fornito: 6 byte/'
expect_fail "rapporto osservato con la sezione == sysin di un'altra scheda (O2)" "osservazioni: O2: sezione == sysin del rapporto osservato diversa dalla scheda" coerenza "" "" "" "" "$tmp/o4"
mkdir -p "$tmp/piu"; cp "$tmp/obs"/*.txt "$tmp/obs"/*.ambiente "$tmp/piu/"; cp "$tmp/piu/S1.txt" "$tmp/piu/S9.txt"
expect_fail "rapporto di un caso non previsto (S9)" "rapporti o attesi non previsti in" verifica "$tmp/piu"
mkdir -p "$tmp/manca"; cp "$tmp/obs"/*.txt "$tmp/obs"/*.ambiente "$tmp/manca/"; rm "$tmp/manca/DFFFFFFFF.txt"
expect_fail "rapporto di DFFFFFFFF assente" "DFFFFFFFF: rapporto assente" verifica "$tmp/manca"

# 5b. Tabella, casi, schede e osservazioni alterati.
cp "$TAB" "$tmp/t1.tsv"; mutate "$tmp/t1.tsv" 's/^L	80000000	FFFFFFFF	arresto-97	/L	80000000	FFFFFFFF	ritorno-0	/'
expect_fail "tabella: classe L dichiarata ritorno-0" "D80000000: l atteso scritto a mano diverge dalla tabella (L) alla riga 2" coerenza "$tmp/t1.tsv"
cp "$TAB" "$tmp/t2.tsv"; mutate "$tmp/t2.tsv" 's/^V	00000000	7FFFFFFF	/V	00000000	7FFFFFFE	/'
expect_fail "tabella: buco tra V e L (7FFFFFFF non coperto)" "tabella: buco tra le classi V e L" coerenza "$tmp/t2.tsv"
cp "$TAB" "$tmp/t3.tsv"; mutate "$tmp/t3.tsv" 's/^L	80000000	/L	7FFFFFFF	/'
expect_fail "tabella: V e L sovrapposte su 7FFFFFFF" "tabella: le classi V e L si sovrappongono" coerenza "$tmp/t3.tsv"
cp "$TAB" "$tmp/t4.tsv"; mutate "$tmp/t4.tsv" 's/^L	80000000	FFFFFFFF	/L	80000000	FFFFFFFE	/'
expect_fail "tabella: FFFFFFFF non coperto" "tabella: l ultima classe non arriva a FFFFFFFF" coerenza "$tmp/t4.tsv"
cp "$PROVE" "$tmp/p1.tsv"; mutate "$tmp/p1.tsv" 's/^D80000000	WAITPRB	80000000	L$/D80000000	WAITPRB	80000000	V/'
expect_fail "casi: D80000000 dichiarato della classe V" "D80000000: dichiarato della classe V, ma per la tabella il valore 80000000 e della classe L" coerenza "" "$tmp/p1.tsv"
cp "$PROVE" "$tmp/p2.tsv"; mutate "$tmp/p2.tsv" '/^D7FFFFFFF	/d'
rm -rf "$tmp/a5"; mkdir -p "$tmp/a5"; cp "$ATT"/* "$tmp/a5/"; rm "$tmp/a5/D7FFFFFFF.txt"
expect_fail "casi: manca il caso obbligatorio 7FFFFFFF" "casi: manca il caso WAITPRB con argomento 7FFFFFFF" coerenza "" "$tmp/p2.tsv" "$tmp/a5"
cp "$PROVE" "$tmp/p3.tsv"; mutate "$tmp/p3.tsv" '/^S2	/d'
rm -rf "$tmp/a6"; mkdir -p "$tmp/a6"; cp "$ATT"/* "$tmp/a6/"; rm "$tmp/a6/S2.txt"
expect_fail "casi: manca COBSWAIT con altre 8 cifre" "casi: manca il caso COBSWAIT con altre 8 cifre" coerenza "" "$tmp/p3.tsv" "$tmp/a6"
mkdir -p "$tmp/sch"; cp "$tmp/obs/schede"/* "$tmp/sch/"
mutate "$tmp/sch/S1.sysin" 's/^00003600/00003601/'
expect_fail "scheda di S1 diversa dalla riga 26 del JCL" "S1: scheda della corsa diversa da quella ricavata dalla riga 26 del JCL" coerenza "" "" "" "" "" "$tmp/sch"
cp "$tmp/impronte" "$tmp/i1"; mutate "$tmp/i1" 's/^S2 81 /S2 82 /'
expect_fail "impronta di S2 con un byte in piu'" "S2: la scheda ha 82 byte invece di 81" coerenza "" "" "" "" "" "" "$tmp/i1"
cp "$OSS" "$tmp/s1.tsv"; mutate "$tmp/s1.tsv" 's/^O1	COBSWAIT	vuoto	/S1	COBSWAIT	vuoto	/'
expect_fail "osservazione con il nome di un caso ricavato (S1)" "osservazioni: S1 e anche un caso ricavato dal sorgente" coerenza "" "" "" "$tmp/s1.tsv"

# 6. Residui: i rapporti sani di M1 lasciati nella cartella d'uscita non soddisfano una corsa rotta.
mkdir -p "$tmp/residuo"; cp -R "$tmp/obs"/. "$tmp/residuo/"
esegui_variante codice "$tmp/residuo" >> "$tmp/residuo.log" 2>&1 || { cat "$tmp/residuo.log" >&2; fail "esecuzione nella cartella con i residui fallita"; }
expect_fail "rapporti sani di una corsa precedente, poi una corsa con la routine che restituisce 4" "+RC  000000004" verifica "$tmp/residuo"
log "controllo di MVSWAIT superato"
