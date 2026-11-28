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
coerenza() { # coerenza [TABELLA] [PROVE] [ATTESI] [OSSERVAZIONI] [OSSERVATI] [SCHEDE] [IMPRONTE] [JCL]
  bash "$DIR/mvswait-coerenza.sh" "${1:-$TAB}" "${2:-$PROVE}" "${3:-$ATT}" "${4:-$OSS}" "${5:-$OSSD}" \
    "${6:-$tmp/obs/schede}" "${7:-$tmp/impronte}" "${8:-$JCL}"
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

# 2. Routine alterate. Le espressioni di sed agiscono su righe intere della routine. Una mutazione, una sola
#    violazione (giro 1 della PR #52): solo_diversi verifica che, rispetto alla corsa sana di M1, cambino
#    esattamente i rapporti dei casi in cui la violazione e' visibile e nessun altro.
# solo_diversi VARIANTE CASI...: i rapporti diversi da quelli di M1 sono esattamente CASI.
solo_diversi() {
  local v="$1" c r atteso; shift
  for c in $PROVE_CASI $OSS_CASI; do
    atteso=0; case " $* " in *" $c "*) atteso=1 ;; esac
    r=0; cmp -s "$tmp/obs/$c.txt" "$tmp/$v/obs/$c.txt" || r=$?
    case "$r" in 0|1) ;; *) fail "variante '$v': confronto di $c fallito (cmp, codice $r)" ;; esac
    [ "$r" = "$atteso" ] || fail "variante '$v': il rapporto di $c $( [ "$r" = 1 ] && echo cambia || echo non cambia ) (attesi diversi: $*): la mutazione non isola la violazione"
    cmp -s "$tmp/obs/$c.ambiente" "$tmp/$v/obs/$c.ambiente" || fail "variante '$v': ambiente di $c cambiato"
  done
  log "     variante '$v': cambiano solo i rapporti di ${*:-nessun caso}"
}
# arresto_97 RAPPORTO VARIANTE: il codice d'uscita del rapporto (riga 2) e' ancora 97. La lettura ha l'esito
# controllato a parte (giro 2 della PR #52: dentro [ "$(sed ...)" = 97 ] l'esito di sed si perdeva).
arresto_97() {
  local rc
  rc="$(sed -n 2p "$1")" || fail "variante '$2': lettura del codice di $(rel "$1") fallita (sed)"
  [ "$rc" = 97 ] || fail "la variante '$2' ha cambiato l'arresto ($rc invece di 97)"
}
V_TUTTI="D00000000 D00000001 D00000E10 D05F5E0FF D05F5E100 D7FFFFFFF S1 S2 O1 O2 O3 O4"
R0='^           MOVE 0 TO RETURN-CODE$'
sorgente argomento "s/$R0/           MOVE X'00' TO LK-INTERVALLO(4:1)\n           MOVE 0 TO RETURN-CODE/"
variante argomento
grep -qx 'DOPO  a5a5a5a5 00000000 a5a5a5a5' "$tmp/argomento/obs/D00000001.txt" \
  || fail "la variante 'argomento' non ha modificato l'argomento: prova negativa non significativa"
solo_diversi argomento D00000001 D00000E10 D05F5E0FF D7FFFFFFF
expect_fail "routine che modifica l'argomento (quarto byte azzerato)" "D00000001: rapporto diverso dall'atteso" verifica "$tmp/argomento/obs"
sorgente codice "s/$R0/           MOVE 4 TO RETURN-CODE/"
variante codice
solo_diversi codice $V_TUTTI
expect_fail "routine che restituisce 4" "+RC  000000004" verifica "$tmp/codice/obs"
expect_fail "routine che restituisce 4 (COBSWAIT termina con 4)" "S1: rapporto diverso dall'atteso" verifica "$tmp/codice/obs"
sorgente stdout "s/$R0/           DISPLAY 'MVSWAIT SU STDOUT'\n           MOVE 0 TO RETURN-CODE/"
variante stdout
solo_diversi stdout $V_TUTTI
expect_fail "routine che scrive su stdout" "+MVSWAIT SU STDOUT" verifica "$tmp/stdout/obs"
# Attese di un secondo (giri 1 e 2 della PR #52): rapporti identici a quelli sani, ma la durata del caso
# supera quella dei controlli di circa 1000 ms, oltre la soglia di 500 ms di mvswait-run.sh e sotto l'arresto
# di 3 s: la prova deve fallire per la differenza misurata, non per il contenuto, e indicare i casi giusti.
# esito_variante NOME: esegue la variante, conserva output ed esito; mostra NOME li restituisce.
esito_variante() {
  local rc=0
  esegui_variante "$1" > "$tmp/$1.esito" 2>&1 || rc=$?
  echo "$rc" > "$tmp/$1.rc" || fail "esito della variante '$1' non registrabile"
}
mostra() { local rc; cat "$tmp/$1.esito" || return 99; rc="$(cat "$tmp/$1.rc")" || return 99; return "$rc"; }
# misure CARTELLA: le durate di ogni caso (caso, controlli, differenza), per il log (solo diagnostica).
misure() {
  local d="$1" c r s=""
  for c in $PROVE_CASI $OSS_CASI; do
    r="$(cat "$d/$c.durata")" || return 1
    set -- $r
    s="$s $c=$1/$2/$3/$(( $1 - ($2 > $3 ? $2 : $3) ))"
  done
  echo "caso=durata/controllo prima/controllo dopo/differenza (ms):$s"
}
# differenze VARIANTE CASI...: per ogni caso, durata - max(controlli) >= 900 ms (la variante ha atteso davvero).
differenze() {
  local v="$1" c r; shift
  for c in "$@"; do
    r="$(cat "$tmp/$v/obs/$c.durata")" || fail "durata di $c della variante '$v' illeggibile"
    set -- $r
    [ $# -eq 3 ] && [ $(( $1 - ($2 > $3 ? $2 : $3) )) -ge 900 ] \
      || fail "la variante '$v' non ha atteso per $c ($r): prova negativa non significativa"
  done
}
# - fissa: ogni esecuzione con valore ammesso attende un secondo;
sorgente unsecondo "s/^      \* Riga 23 (ASMWAIT): l'attesa non e' eseguita\.\$/           MOVE 1 TO WS-HI\n           CALL 'C\$SLEEP' USING WS-HI/"
prepara unsecondo "$tmp/src-unsecondo/MVSWAIT.cbl"
esito_variante unsecondo
expect_fail "routine che attende un secondo fisso" "(MVSWAIT non deve attendere): D00000000=" mostra unsecondo
solo_diversi unsecondo
differenze unsecondo $V_TUTTI
log "     e in ogni caso con valore ammesso (WAITPRB e tutti i lanci di COBSWAIT) il caso supera i controlli di almeno 900 ms"
# - solo alla prima esecuzione della routine nel container (marcatore in /tmp): il caso D00000000;
sorgente primo "s#^      \* Riga 23 (ASMWAIT): l'attesa non e' eseguita\.\$#           CALL 'SYSTEM' USING '[ -e /tmp/m ]||{ :>/tmp/m;sleep 1;}'#"
prepara primo "$tmp/src-primo/MVSWAIT.cbl"
esito_variante primo
expect_fail "routine che attende un secondo solo alla prima esecuzione" "(MVSWAIT non deve attendere): D00000000=" mostra primo
grep -Eq 'attendere\): D00000000=[0-9]+ms\.$' "$tmp/primo.esito" || fail "la variante 'primo' non e' respinta solo per D00000000"
solo_diversi primo
differenze primo D00000000
# - solo all'ultimo caso (dodicesima chiamata che arriva all'attesa, contata in /tmp): il caso O4.
sorgente ultimo \
  "s#^\(       01  WS-LO .*\)\$#\1\n       01  WS-CMD                  PIC X(60).#" \
  "s#^      \* Riga 23 (ASMWAIT): l'attesa non e' eseguita\.\$#           MOVE 'echo>>/tmp/c;[ \$(wc -l </tmp/c) -lt 12 ]' TO WS-CMD\n           MOVE '||sleep 1' TO WS-CMD(41:)\n           CALL 'SYSTEM' USING WS-CMD#"
prepara ultimo "$tmp/src-ultimo/MVSWAIT.cbl"
esito_variante ultimo
expect_fail "routine che attende un secondo solo all'ultimo caso" "(MVSWAIT non deve attendere): O4=" mostra ultimo
grep -Eq 'attendere\): O4=[0-9]+ms\.$' "$tmp/ultimo.esito" || fail "la variante 'ultimo' non e' respinta solo per O4"
solo_diversi ultimo
differenze ultimo O4
# Controprova: routine sana con la CPU del container strozzata (docker --cpus 0.015). Esiti ammessi: 0 (nessun
# falso rosso) oppure 3 con "INFRASTRUTTURA LENTA" (giudizio impossibile, distinto); mai la violazione.
lento_sano() {
  local rc=0 g=0 c
  MVSWAIT_CPUS=0.015 MVSWAIT_OUT_DIR="$tmp/lento" bash "$DIR/mvswait-run.sh" > "$tmp/lento.log" 2>&1 || rc=$?
  grep -q "MVSWAIT non deve attendere" "$tmp/lento.log" || g=$?
  case "$g" in 1) ;; 0) indent "$tmp/lento.log" >&2; fail "routine sana con CPU strozzata: falso rosso (violazione)" ;;
    *) fail "lettura del log con CPU strozzata fallita (grep, codice $g)" ;; esac
  case "$rc" in
    0) esito_lento="nessun falso rosso" ;;
    3) g=0; grep -q "INFRASTRUTTURA LENTA" "$tmp/lento.log" || g=$?
       [ "$g" = 0 ] || { indent "$tmp/lento.log" >&2; fail "codice 3 senza il messaggio INFRASTRUTTURA LENTA"; }
       esito_lento="infrastruttura lenta dichiarata (codice 3), nessuna violazione" ;;
    *) indent "$tmp/lento.log" >&2; fail "routine sana con CPU strozzata: esito $rc" ;;
  esac
  for c in $PROVE_CASI $OSS_CASI; do
    cmp -s "$tmp/obs/$c.txt" "$tmp/lento/$c.txt" || fail "CPU strozzata: rapporto di $c diverso da quello di M1"
  done
}
lento_sano
log "   controprova ok: routine sana con --cpus 0.015: $esito_lento; rapporti identici a quelli di M1"
for v in obs unsecondo/obs primo/obs ultimo/obs lento; do
  m="$(misure "$tmp/$v")" || fail "durate di $v illeggibili"
  log "     durate $v: $m"
done
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
solo_diversi bitalto D80000000 DFFFFFFFF
expect_fail "routine che ritorna 0 anche con il bit alto acceso (X'80000000')" "D80000000: rapporto diverso dall'atteso" verifica "$tmp/bitalto/obs"
expect_fail "routine che ritorna 0 anche con il bit alto acceso (X'FFFFFFFF')" "DFFFFFFFF: rapporto diverso dall'atteso" verifica "$tmp/bitalto/obs"

# 3. Valore RIPORTATO con l'ordine dei byte invertito, o con il segno: cambia solo il decimale stampato;
#    classificazione (WS-VALORE), esadecimale, arresto e codice restano quelli della routine (giro 1 della
#    PR #52: prima la mutazione sul segno cambiava anche l'arresto 97 in un ritorno 0).
sorgente ordine 's/^           MOVE WS-VALORE TO WS-DEC$/           COMPUTE WS-DEC = WS-BYTE(4) * 16777216 + WS-BYTE(3) * 65536\n                          + WS-BYTE(2) * 256 + WS-BYTE(1)/'
variante ordine
solo_diversi ordine D00000001 D00000E10 D05F5E0FF D05F5E100 D7FFFFFFF D80000000 S1 S2 O2
arresto_97 "$tmp/ordine/obs/D80000000.txt" ordine
expect_fail "routine che riporta il valore con i 4 byte in ordine inverso" "D00000E10: rapporto diverso dall'atteso" verifica "$tmp/ordine/obs"
sorgente segno "s/^               DISPLAY 'MENB-ORACLE MVSWAIT: ATTESA RICHIESTA '\$/               COMPUTE WS-DEC = 4294967296 - WS-VALORE\n               DISPLAY 'MENB-ORACLE MVSWAIT: ATTESA RICHIESTA -'/"
variante segno
grep -q "ATTESA RICHIESTA -2147483648 (X'80000000') OLTRE" "$tmp/segno/obs/D80000000.txt" \
  || fail "la variante 'segno' non riporta il valore con il segno: prova negativa non significativa"
arresto_97 "$tmp/segno/obs/D80000000.txt" segno
solo_diversi segno D80000000 DFFFFFFFF
expect_fail "routine che riporta il valore con segno (X'80000000' = -2147483648), arresto 97 invariato" "D80000000: rapporto diverso dall'atteso" verifica "$tmp/segno/obs"

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
# 4a. --sysin che coincide con un file che esegui.sh scrive o cancella (giro 1 della PR #52). La scheda di S2
#     e' messa proprio in quel file (o un collegamento simbolico punta li'): esegui.sh ne fa una copia privata
#     prima di ogni scrittura, quindi il rapporto deve essere esattamente l'atteso di S2.
# sysin_alias NOME BERSAGLIO [link] [ESEGUI]: COBSWAIT con --sysin /out/BERSAGLIO (o /out/alias.sysin -> BERSAGLIO).
sysin_alias() {
  local d="$tmp/alias-$1" b="$2" modo="${3:-}" e="/oracle/esegui.sh" p
  [ -z "${4:-}" ] || e="$(in_container "$4")" || return 1
  clean_dir "$d"
  case "$b" in */*) mkdir -p "$d/${b%/*}" || fail "preparazione di $1 fallita" ;; esac
  cp "$tmp/obs/schede/S2.sysin" "$d/$b" || fail "preparazione di $1 fallita"
  p="/out/$b"
  if [ "$modo" = link ]; then ln -s "/out/$b" "$d/alias.sysin" || fail "collegamento di $1 non creabile"; p=/out/alias.sysin; fi
  orun -v "$d:/out" -v "$BUILD_OUT/bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN=3 \
    -- timeout -k 10 60 sh "$e" /out COBSWAIT --sysin "$p" || { echo "esegui.sh fallito con --sysin $p"; return 1; }
  cmp -s "$ATT/S2.txt" "$d/COBSWAIT.txt" \
    || { diff -u "$ATT/S2.txt" "$d/COBSWAIT.txt" > "$tmp/d"; echo "rapporto con --sysin $p diverso dall'atteso di S2:"; indent "$tmp/d"; return 1; }
}
for spec in ambiente:COBSWAIT.ambiente stdout:COBSWAIT.stdout stderr:COBSWAIT.stderr rapporto:COBSWAIT.txt \
            lavoro:lavoro-COBSWAIT/S2.sysin "link:COBSWAIT.ambiente:link"; do
  n="${spec%%:*}"; r="${spec#*:}"; b="${r%%:*}"; m=""; [ "$b" = "$r" ] || m="${r#*:}"
  sysin_alias "$n" "$b" "$m" > "$tmp/alias.out" 2>&1 || { indent "$tmp/alias.out" >&2; fail "controprova: --sysin su $b${m:+ (collegamento)} non da' il rapporto di S2"; }
  log "   controprova ok: --sysin su /out/$b${m:+ tramite collegamento simbolico}: rapporto identico all'atteso di S2"
done
cp "$ORACLE_ROOT/esegui.sh" "$tmp/esegui-senza-copia.sh" || fail "copia di esegui.sh fallita"
mutate "$tmp/esegui-senza-copia.sh" 's/^  ingresso="\$copia"$/  ingresso="$sysin"/'
expect_fail "esegui.sh senza la copia privata, --sysin su .ambiente" "diverso dall'atteso di S2" sysin_alias senza-copia COBSWAIT.ambiente "" "$tmp/esegui-senza-copia.sh"
expect_fail "esegui.sh senza la copia privata, --sysin collegato a .ambiente" "diverso dall'atteso di S2" sysin_alias senza-copia-link COBSWAIT.ambiente link "$tmp/esegui-senza-copia.sh"

# 4b. Ingresso che non si apre al momento dell'esecuzione, con i file di una corsa precedente nella cartella
#     d'uscita (giro 1 della PR #52): esegui.sh deve fallire come strumento e non lasciare un rapporto.
# ingresso_perso NOME ESPRESSIONE-SED: copia di esegui.sh in cui l'ingresso sparisce nel punto indicato.
ingresso_perso() {
  local d="$tmp/perso-$1" e="$tmp/esegui-perso-$1.sh" rc=0
  cp "$ORACLE_ROOT/esegui.sh" "$e" || fail "copia di esegui.sh fallita"
  mutate "$e" "$2"
  clean_dir "$d"
  cp "$tmp/obs/S1.txt" "$d/COBSWAIT.txt" && printf 'VECCHIO STDOUT\n' > "$d/COBSWAIT.stdout" \
    && printf 'VECCHIO STDERR\n' > "$d/COBSWAIT.stderr" || fail "residui di $1 non preparabili"
  orun -v "$d:/out" -v "$BUILD_OUT/bin:/oracle-bin:ro" -v "$tmp/obs/schede:/s:ro" -e ORACLE_TIMEOUT_RUN=3 \
    -- timeout -k 10 60 sh "$(in_container "$e")" /out COBSWAIT --sysin /s/S1.sysin || rc=$?
  [ "$rc" -ne 0 ] || { echo "esegui.sh terminato con 0 senza ingresso"; return 0; }
  [ ! -s "$d/COBSWAIT.txt" ] || { echo "dopo il fallimento resta un rapporto"; return 0; }
  # Esiti di grep (giro 2 della PR #52): 1 = nessun residuo; 0 = residuo; ogni altro esito = verifica fallita.
  local g=0
  grep -q VECCHIO "$d/COBSWAIT.stdout" "$d/COBSWAIT.stderr" || g=$?
  case "$g" in
    1) ;;
    0) echo "dopo il fallimento resta un residuo della corsa precedente"; return 0 ;;
    *) echo "ricerca dei residui fallita (grep, codice $g)"; return 0 ;;
  esac
  return "$rc"
}
expect_fail "ingresso cancellato prima del controllo di apertura" "esegui.sh: ingresso non apribile" \
  ingresso_perso prima 's#^( exec < "\$ingresso" ) 2>/dev/null || #rm -f "$ingresso"; ( exec < "$ingresso" ) 2>/dev/null || #'
expect_fail "ingresso cancellato tra il controllo e l'apertura sul descrittore 3" "cannot open" \
  ingresso_perso dopo 's#^exec 3< "\$ingresso" 4>#rm -f "$ingresso"; exec 3< "$ingresso" 4>#'
# Lo stesso schema sull'uscita: stdout del programma non apribile (descrittore 4).
expect_fail "stdout del programma non apribile (descrittore 4)" "cannot create" \
  ingresso_perso stdout 's#^exec 3< "\$ingresso" 4> "\$so"#exec 3< "$ingresso" 4> /nonesiste/stdout#'
cp "$ORACLE_ROOT/esegui.sh" "$tmp/esegui-ignora.sh" || fail "copia di esegui.sh fallita"
mutate "$tmp/esegui-ignora.sh" 's#<&3 >#</dev/null >#g'
MVSWAIT_ESEGUI="$tmp/esegui-ignora.sh" MVSWAIT_OUT_DIR="$tmp/ignora" bash "$DIR/mvswait-run.sh" > "$tmp/ignora.log" 2>&1 \
  || { cat "$tmp/ignora.log" >&2; fail "esecuzione con esegui.sh che ignora --sysin fallita"; }
grep -qx '== sysin' "$tmp/ignora/S1.txt" || fail "con esegui.sh alterato manca la sezione == sysin: prova negativa non significativa"
expect_fail "esegui.sh che ignora --sysin (ingresso vuoto al posto della scheda)" "S1: rapporto diverso dall'atteso" verifica "$tmp/ignora"

# 4b. Esiti dei comandi nuovi di esegui.sh (wc e sha256sum su --sysin): l'involucro build/avvolgi.sh, davanti
#     nel PATH del container, esegue davvero il comando e ne cambia solo l'esito (o tronca l'output).
# scrivi_involucro CARTELLA COMANDO MODO: CARTELLA/avv/COMANDO. MODO finto:TESTO = uno script che stampa
# TESTO ed esce con 0 (risposta malformata); ogni altro MODO = build/avvolgi.sh. La scrittura e il chmod
# hanno ciascuno il proprio esito controllato (giro 2 della PR #52: l'esito di printf era coperto dal chmod).
scrivi_involucro() {
  local f="$1/avv/$2"
  case "$3" in
    finto:*) printf '#!/bin/sh\necho '\''%s'\''\n' "${3#finto:}" > "$f" || fail "involucro di $2 non scrivibile (printf)" ;;
    *) printf '#!/bin/sh\nexec sh /avv/.avvolgi.sh /res/registro %s '\''%s'\'' /usr/bin/%s "$@"\n' "$2" "$3" "$2" > "$f" \
         || fail "involucro di $2 non scrivibile (printf)" ;;
  esac
  chmod +x "$f" || fail "involucro di $2 non eseguibile (chmod)"
}
avvolto() { # avvolto NOME COMANDO=MODO...: COBSWAIT con --sysin /s/S1.sysin e i comandi avvolti
  local d="$tmp/av-$1" s c m; shift
  clean_dir "$d"
  mkdir -p "$d/avv" "$d/res/out" || fail "cartelle degli involucri non creabili"
  cp "$ORACLE_ROOT/build/avvolgi.sh" "$d/avv/.avvolgi.sh" || fail "copia di avvolgi.sh fallita"
  for s in "$@"; do
    c="${s%%=*}"; m="${s#*=}"
    scrivi_involucro "$d" "$c" "$m"
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
avvolto passa wc=passa sha256sum=passa cp=passa mktemp=passa > "$tmp/av-passa.log" 2>&1 || { indent "$tmp/av-passa.log" >&2; fail "controprova: esegui.sh con gli involucri in modo passa fallito"; }
cmp -s "$tmp/obs/S1.txt" "$tmp/av-passa/res/out/COBSWAIT.txt" || fail "controprova: rapporto con gli involucri in modo passa diverso da quello di S1"
for c in wc sha256sum cp mktemp; do raggiunto "$tmp/av-passa/res/registro" "$c" 0; done
log "   controprova ok: esegui.sh --sysin con wc, sha256sum, cp e mktemp avvolti in modo passa, rapporto identico a quello di S1"
expect_fail "esegui.sh --sysin con mktemp (copia privata) che restituisce 42" "esegui.sh: --sysin: copia privata non creabile (mktemp)" avvolto mk42 mktemp=42
raggiunto "$tmp/av-mk42/res/registro" mktemp 42
expect_fail "esegui.sh --sysin con cp (copia privata) che restituisce 42" "esegui.sh: --sysin: copia privata non riuscita (cp)" avvolto cp42 cp=42
raggiunto "$tmp/av-cp42/res/registro" cp 42
expect_fail "esegui.sh --sysin con wc che restituisce 42" "esegui.sh: --sysin: dimensione non leggibile (wc)" avvolto wc42 wc=42 sha256sum=passa
raggiunto "$tmp/av-wc42/res/registro" wc 42
expect_fail "esegui.sh --sysin con sha256sum che restituisce 42" "esegui.sh: --sysin: impronta non calcolabile (sha256sum)" avvolto sha42 wc=passa sha256sum=42
raggiunto "$tmp/av-sha42/res/registro" sha256sum 42
expect_fail "esegui.sh --sysin con sha256sum che scrive un output parziale ed esce con 42 (T42)" "esegui.sh: --sysin: impronta non calcolabile (sha256sum)" avvolto shaT42 wc=passa sha256sum=T42
raggiunto "$tmp/av-shaT42/res/registro" sha256sum 42
expect_fail "esegui.sh --sysin con wc che risponde con un testo non numerico (esito 0)" "esegui.sh: --sysin: dimensione non valida: 'ottantuno'" avvolto wcfinto wc=finto:ottantuno sha256sum=passa
expect_fail "esegui.sh --sysin con sha256sum che risponde con un'impronta troncata (esito 0)" "esegui.sh: --sysin: impronta non valida: '59f72f438a92'" avvolto shacorta wc=passa 'sha256sum=finto:59f72f438a92  -'
expect_fail "esegui.sh --sysin con sha256sum che risponde con caratteri non esadecimali (esito 0)" "esegui.sh: --sysin: impronta non valida: 'IMPRONTA'" avvolto shanonhex wc=passa 'sha256sum=finto:IMPRONTA  -'
for d in mk42 cp42 wc42 sha42 shaT42 wcfinto shacorta shanonhex; do
  [ ! -s "$tmp/av-$d/res/out/COBSWAIT.txt" ] || fail "con $d esegui.sh ha scritto comunque un rapporto"
done
log "     e in nessuno di questi casi esegui.sh ha scritto un rapporto"

# 4b-bis. Esiti dei comandi delle verifiche di questo controllo (giro 2 della PR #52): sed in arresto_97,
#     printf e chmod in scrivi_involucro, grep in ingresso_perso. Ogni comando restituisce 42 dopo aver
#     fatto davvero il suo lavoro (output autentico): la verifica deve fallire e dirlo.
sed_42() ( sed() { command sed "$@"; return 42; }; arresto_97 "$tmp/segno/obs/D80000000.txt" segno )
expect_fail "arresto_97 con sed che restituisce 42 (codice letto 97)" "lettura del codice di" sed_42
involucro_42() ( # involucro_42 COMANDO: scrivi_involucro con COMANDO (printf o chmod) che restituisce 42
  case "$1" in
    printf) printf() { builtin printf "$@"; return 42; } ;;
    chmod) chmod() { command chmod "$@"; return 42; } ;;
  esac
  rm -rf "$tmp/inv42" && mkdir -p "$tmp/inv42/avv" || exit 1
  scrivi_involucro "$tmp/inv42" wc passa
)
expect_fail "scrivi_involucro con printf che restituisce 42" "involucro di wc non scrivibile (printf)" involucro_42 printf
expect_fail "scrivi_involucro con chmod che restituisce 42" "involucro di wc non eseguibile (chmod)" involucro_42 chmod
# ingresso_perso segnala un difetto della verifica ritornando 0 (cosi' la sua prova negativa fallisce): qui
# quel ritorno diventa 1, e un ritorno diverso da 0 (grep fallito senza che la verifica se ne accorga) diventa 0.
grep_42() ( grep() { command grep "$@"; return 42; }
  if ingresso_perso grep 's#^( exec < "\$ingresso" ) 2>/dev/null || #rm -f "$ingresso"; ( exec < "$ingresso" ) 2>/dev/null || #'; then
    exit 1
  fi
  exit 0 )
expect_fail "ingresso_perso con grep (ricerca dei residui) che restituisce 42" "ricerca dei residui fallita (grep, codice 42)" grep_42

# 4c. Esiti dei comandi di mvswait-run.sh nel container (sed che ricava le schede, mv dei rapporti) e del
#     calcolo delle impronte: ogni docker run della sottoshell ha gli involucri davanti nel PATH.
run_avvolto() { # run_avvolto NOME COMANDO=MODO: mvswait-run.sh con il comando avvolto
  local d="$tmp/ra-$1" s="$2" c m
  clean_dir "$d"
  mkdir -p "$d/avv" "$d/res" || fail "cartelle degli involucri non creabili"
  cp "$ORACLE_ROOT/build/avvolgi.sh" "$d/avv/.avvolgi.sh" || fail "copia di avvolgi.sh fallita"
  c="${s%%=*}"; m="${s#*=}"
  scrivi_involucro "$d" "$c" "$m"
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
expect_fail "mvswait-run.sh con date (misura della durata) che restituisce 42" "orologio non leggibile (date) per D00000000" run_avvolto date date=42
raggiunto "$tmp/ra-date/res/registro" date 42
expect_fail "mvswait-run.sh con date che risponde con un testo non numerico (esito 0)" "orologio non valido per D00000000: adesso" run_avvolto datefinto date=finto:adesso
expect_fail "mvswait-run.sh con sed (scheda dal JCL) che restituisce 42" "scheda di S1 non ricavabile dal JCL" run_avvolto sed sed=42
raggiunto "$tmp/ra-sed/res/registro" sed 42
expect_fail "mvswait-run.sh con mv (rapporto del caso) che restituisce 42" "esecuzione dei casi di MVSWAIT fallita" run_avvolto mv mv=42
raggiunto "$tmp/ra-mv/res/registro" mv 42
expect_fail "mvswait-run.sh con mkdir (cartella del caso) che restituisce 42" "esecuzione dei casi di MVSWAIT fallita" run_avvolto mkdir mkdir=42
raggiunto "$tmp/ra-mkdir/res/registro" mkdir 42
impronte_avvolte() { # impronte_avvolte NOME COMANDO=MODO: impronte delle schede di M1 con il comando avvolto
  local d="$tmp/ia-$1" s="$2" c m
  clean_dir "$d"
  mkdir -p "$d/avv" "$d/res" || fail "cartelle degli involucri non creabili"
  cp "$ORACLE_ROOT/build/avvolgi.sh" "$d/avv/.avvolgi.sh" || fail "copia di avvolgi.sh fallita"
  c="${s%%=*}"; m="${s#*=}"
  scrivi_involucro "$d" "$c" "$m"
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
# Controlli di forma della coerenza, uno per riga: QUALE (posizione dell'argomento di coerenza: 1 tabella,
# 2 casi, 4 osservazioni, 7 impronte) | espressione sed sulla copia | motivo atteso.
FORMA="1|s/^classe	da	a	/classe	inizio	a	/|tabella: intestazione diversa da quella attesa
1|s/	bit alto acceso: .*$//|tabella: riga con 5 colonne invece di 6
1|s/^L	/V	/|tabella: classe ripetuta: V
1|s/^L	/l	/|tabella: nome di classe non valido: l
1|s/^L	80000000	/L	8000000G	/|tabella L: estremi non validi
1|s/^L	80000000	FFFFFFFF	/L	FFFFFFFF	80000000	/|tabella L: da maggiore di a
1|s/	arresto-97	/	abend	/|tabella L: esito non valido: abend
1|s/	MVSWAIT.asm 20-23; ASMWAIT.mac 19	/		/|tabella L: righe del sorgente o motivo assenti
2|s/^caso	programma	ingresso	classe$/caso	programma	argomento	classe/|casi: intestazione diversa da quella attesa
2|s/^D00000001	/D00000000	/|casi: caso ripetuto: D00000000
2|s/^D00000001	WAITPRB	00000001	/D00000001	WAITPRB	0000001	/|D00000001: argomento non valido
2|s/^S1	COBSWAIT	/S1	COBSWAIX	/|S1: programma non valido: COBSWAIX
2|s/^S1	COBSWAIT	jcl	/S1	COBSWAIT	jcl:ABC	/|S1: ingresso non valido per COBSWAIT: jcl:ABC
2|s/^S2	COBSWAIT	jcl:12345678	V$/S2	COBSWAIT	jcl:12345678/|casi: riga con 3 colonne invece di 4
4|s/^caso	programma	ingresso	previsione$/caso	programma	ingresso/|osservazioni: intestazione diversa da quella attesa
4|s/^O2	/O1	/|osservazioni: caso ripetuto: O1
4|s/^O2	COBSWAIT	/O2	WAITPRB	/|osservazioni: O2: programma diverso da COBSWAIT
4|s/^O2	COBSWAIT	testo:3600	/O2	COBSWAIT	testo:3601	/|osservazioni: O2: scheda diversa dal testo dichiarato
4|s/^O2	COBSWAIT	testo:3600	/O2	COBSWAIT	vuoto	/|osservazioni: O2: la scheda non e vuota
4|s/^O2	COBSWAIT	testo:3600	/O2	COBSWAIT	riga:3600	/|osservazioni: O2: ingresso non valido: riga:3600
7|s/^\(S1 81 \)[0-9a-f]*$/\1xyz/|impronte: riga non valida: S1 81 xyz
7|/^S1 /d|S1: impronta della scheda assente"
i=0
while IFS='|' read -r quale expr motivo; do
  i=$((i + 1))
  case "$quale" in 1) src="$TAB" ;; 2) src="$PROVE" ;; 4) src="$OSS" ;; 7) src="$tmp/impronte" ;; *) fail "FORMA: posizione $quale" ;; esac
  cp "$src" "$tmp/forma$i" || fail "copia per la prova di forma $i fallita"
  mutate "$tmp/forma$i" "$expr"
  set -- "" "" "" "" "" "" ""
  case "$quale" in 1) set -- "$tmp/forma$i" ;; 2) set -- "" "$tmp/forma$i" ;; 4) set -- "" "" "" "$tmp/forma$i" ;; 7) set -- "" "" "" "" "" "" "$tmp/forma$i" ;; esac
  expect_fail "coerenza, forma: $motivo" "$motivo" coerenza "$@"
done <<< "$FORMA"
# JCL alterato: riga 26 tolta; prime 8 colonne non numeriche (con la scheda della corsa alterata allo stesso modo).
cp "$JCL" "$tmp/jcl-corto"; mutate "$tmp/jcl-corto" '26,$d'
expect_fail "coerenza: JCL senza la riga 26" "JCL: riga 26 assente o vuota" coerenza "" "" "" "" "" "" "" "$tmp/jcl-corto"
cp "$JCL" "$tmp/jcl-x"; mutate "$tmp/jcl-x" 's/^00003600/0000360X/'
mkdir -p "$tmp/sch-x"; cp "$tmp/obs/schede"/* "$tmp/sch-x/"; mutate "$tmp/sch-x/S1.sysin" 's/^00003600/0000360X/'
expect_fail "coerenza: prime 8 colonne della scheda non numeriche" "S1: le prime 8 colonne della scheda non sono cifre" coerenza "" "" "" "" "" "$tmp/sch-x" "" "$tmp/jcl-x"
expect_fail "coerenza: riga 26 del JCL che non inizia con 00003600 (caso S2)" "S2: la riga 26 del JCL non inizia con 00003600" coerenza "" "" "" "" "" "$tmp/sch-x" "" "$tmp/jcl-x"
# Elenco degli attesi che fallisce: ls che restituisce 42 dopo l'output autentico.
ls_42() ( ls() { command ls "$@"; return 42; }; export -f ls; coerenza )
expect_fail "coerenza con ls (elenco degli attesi) che restituisce 42" "DIFETTO: cartella degli attesi non elencabile" ls_42

# 5c. Radice del repository con spazi nel nome (giro 1 della PR #52): mvswait-run.sh su una copia minima
#     dell'oracle in ".../radice con spazi/oracle" (legacy collegato), artefatti della build: rapporti
#     identici a quelli di M1.
sp="$tmp/radice con spazi"
mkdir -p "$sp/oracle/routines" || fail "radice con spazi non creabile"
cp "$ORACLE_ROOT/lib.sh" "$ORACLE_ROOT/ambiente.sh" "$ORACLE_ROOT/esegui.sh" "$ORACLE_ROOT/Dockerfile" "$sp/oracle/" \
  && cp "$DIR/mvswait-run.sh" "$PROVE" "$OSS" "$sp/oracle/routines/" && ln -s "$REPO_ROOT/legacy" "$sp/legacy" \
  || fail "copia dell'oracle nella radice con spazi fallita"
ORACLE_ROOT="$sp/oracle" MVSWAIT_BIN_DIR="$BUILD_OUT/bin" MVSWAIT_OUT_DIR="$sp/obs" bash "$sp/oracle/routines/mvswait-run.sh" \
  > "$tmp/spazi.log" 2>&1 || { indent "$tmp/spazi.log" >&2; fail "mvswait-run.sh non funziona con una radice con spazi"; }
for c in $PROVE_CASI $OSS_CASI; do
  cmp -s "$tmp/obs/$c.txt" "$sp/obs/$c.txt" || fail "radice con spazi: rapporto di $c diverso da quello di M1"
done
log "   controprova ok: mvswait-run.sh con la radice '$(rel "$sp")': tutti i rapporti identici a quelli di M1"

# 6. Residui: i rapporti sani di M1 lasciati nella cartella d'uscita non soddisfano una corsa rotta.
mkdir -p "$tmp/residuo"; cp -R "$tmp/obs"/. "$tmp/residuo/"
esegui_variante codice "$tmp/residuo" >> "$tmp/residuo.log" 2>&1 || { cat "$tmp/residuo.log" >&2; fail "esecuzione nella cartella con i residui fallita"; }
expect_fail "rapporti sani di una corsa precedente, poi una corsa con la routine che restituisce 4" "+RC  000000004" verifica "$tmp/residuo"
log "controllo di MVSWAIT superato"
