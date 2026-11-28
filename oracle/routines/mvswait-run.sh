#!/usr/bin/env bash
# Prova di MVSWAIT (oracle/stubs/MVSWAIT.cbl, issue #36), chiamato dal passo routines (run.sh).
# Esegue, ognuno con oracle/esegui.sh (ambiente fissato, cartella di lavoro vuota, rapporto e ambiente):
#   - i casi ricavati dal sorgente, mvswait-prove.tsv: WAITPRB (oracle/tests/) con l'argomento nel PARM,
#     COBSWAIT (il programma del legacy) con una scheda SYSIN ricavata da app/jcl/WAITSTEP.jcl;
#   - le osservazioni, mvswait-osservazioni.tsv: COBSWAIT con SYSIN che il sorgente non determina.
# Le schede si ricavano a ogni esecuzione, nel container, dal JCL nel volume del legacy (mvswait-casi.md):
#   jcl            sed -n '26{s/\r$//;p}' /legacy/app/jcl/WAITSTEP.jcl
#   jcl:<cifre>    sed -n '26{s/\r$//;s/^00003600/<cifre>/;p}' /legacy/app/jcl/WAITSTEP.jcl
#   vuoto          file di 0 byte
#   testo:<testo>  printf '%s\n' '<testo>'
# Limiti operativi, su ogni esecuzione che chiama MVSWAIT (casi e osservazioni, quindi anche ogni lancio di
# COBSWAIT), applicati all'artefatto vero:
#   - durata, per DIFFERENZA con una corsa di controllo (giro 2 della PR #52): ogni esecuzione del caso e'
#     preceduta e seguita, nello stesso container, da un'esecuzione di controllo, WAITPRB senza PARM, che si
#     ferma prima della CALL e quindi non carica MVSWAIT (stesso esegui.sh, stesso avvio di libcob). Si
#     misurano le tre durate (date +%s%N) e si giudica differenza = caso - max(controllo prima, controllo
#     dopo): il carico della macchina pesa sul caso e sui controlli, un'attesa della routine solo sul caso.
#     Ogni caso si esegue una sola volta e la prova fallisce se in un caso qualunque la differenza supera
#     MVSWAIT_DIFFERENZA_MS (500 ms): nessuna esecuzione lenta viene scartata o ripetuta. Se i controlli
#     stessi sono lenti (oltre MVSWAIT_CONTROLLO_LENTO_MS, 300 ms) la riga del caso dice "infrastruttura
#     lenta"; se in quel caso la differenza supera la soglia, la prova termina con il codice 3 e il
#     messaggio "INFRASTRUTTURA LENTA" (giudizio impossibile: ne' verde ne' violazione, che ha codice 1).
#     Valori in <CASO>.durata: "caso controllo-prima controllo-dopo" in millisecondi;
#   - arresto: MVSWAIT_LIMITE secondi (3), applicato da esegui.sh (ORACLE_TIMEOUT_RUN): allo scadere esegui.sh
#     termina il programma e fallisce, e con lui questa prova (un'attesa lunga non resta appesa).
# Output in oracle/routines/out/mvswait/: <CASO>.txt, <CASO>.ambiente, <CASO>.durata, schede/<CASO>.sysin,
# controllo/<CASO>-{prima,dopo}.txt (rapporti dei controlli: codice 2, nessuna riga di MVSWAIT).
# Solo per le prove negative di mvswait-check.sh: MVSWAIT_OUT_DIR sposta l'output, MVSWAIT_BIN_DIR gli
# artefatti (con WAITPRB, COBSWAIT e MVSWAIT.so), MVSWAIT_ESEGUI indica una copia alterata di esegui.sh
# (sotto oracle/), MVSWAIT_CPUS limita la CPU del container (docker --cpus: la macchina lenta simulata).
. "$ORACLE_ROOT/lib.sh"

MVSWAIT_LIMITE=3
MVSWAIT_DIFFERENZA_MS=500
MVSWAIT_CONTROLLO_LENTO_MS=300
DIR="$ORACLE_ROOT/routines"
# Elenchi dei casi: un elemento per percorso (giro 1 della PR #52: la lista separata da spazi non reggeva
# una radice del repository con spazi nel nome).
casi=("$DIR/mvswait-prove.tsv" "$DIR/mvswait-osservazioni.tsv")
out="${MVSWAIT_OUT_DIR:-$ORACLE_ROOT/routines/out/mvswait}"
bin="${MVSWAIT_BIN_DIR:-$BUILD_OUT/bin}"
esegui="/oracle/esegui.sh"
if [ -n "${MVSWAIT_ESEGUI:-}" ]; then esegui="$(in_container "$MVSWAIT_ESEGUI")" || fail "copia di esegui.sh fuori da oracle/"; fi
require_legacy
ensure_image
[ -n "${MVSWAIT_BIN_DIR:-}" ] || require_build
for a in WAITPRB COBSWAIT MVSWAIT.so; do [ -f "$bin/$a" ] || fail "$a assente in $(rel "$bin")"; done
clean_dir "$out"
mkdir -p "$out/schede" || fail "cartella delle schede non creabile"

# Terne caso/programma/ingresso, nell'ordine dei file (righe non commento, intestazione esclusa).
terne=()
for f in "${casi[@]}"; do
  [ -f "$f" ] || fail "elenco dei casi assente: $(rel "$f")"
  righe="$(grep -v '^#' "$f")" || fail "lettura di $(rel "$f") fallita"
  n=0
  while IFS="	" read -r caso prog ingr resto; do
    n=$((n + 1))
    [ "$n" -gt 1 ] || continue
    [ -n "$caso" ] || continue
    case "$caso" in *[!A-Z0-9]*) fail "nome di caso non valido in $(rel "$f"): '$caso'" ;; esac
    case "$prog" in WAITPRB|COBSWAIT) ;; *) fail "programma non valido per $caso: '$prog'" ;; esac
    [ -n "$ingr" ] || fail "ingresso vuoto per $caso"
    terne+=("$caso" "$prog" "$ingr")
  done <<< "$righe"
done
[ "${#terne[@]}" -gt 0 ] || fail "nessun caso di MVSWAIT"


# CPU limitata solo per le prove (MVSWAIT_CPUS, macchina lenta simulata).
opz_docker=()
if [ -n "${MVSWAIT_CPUS:-}" ]; then opz_docker=(--cpus "$MVSWAIT_CPUS"); fi
mkdir -p "$out/controllo" || fail "cartella dei controlli non creabile"

# Un solo container per tutti i casi, con un limite complessivo di 300 s. Ogni comando ha l'esito
# controllato: il primo fallimento (scheda non ricavabile, esegui.sh fallito o fuori tempo, orologio) ferma
# la prova. Per ogni caso: controllo prima, caso, controllo dopo, ciascuno misurato una sola volta.
orun -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$MVSWAIT_LIMITE" ${opz_docker[@]+"${opz_docker[@]}"} \
  -- timeout -k 10 300 sh -c '
  set -u
  esegui="$1"; shift
  jcl=/legacy/app/jcl/WAITSTEP.jcl
  # orologio: nanosecondi dall epoca in $ns, con esito e forma controllati.
  orologio() {
    ns="$(date +%s%N)" || { echo "orologio non leggibile (date) per $caso" >&2; return 1; }
    case "$ns" in ""|*[!0-9]*) echo "orologio non valido per $caso: $ns" >&2; return 1 ;; esac
  }
  # cronometra CARTELLA PROGRAMMA [OPZIONE VALORE]: esegui.sh, durata in millisecondi in $ms.
  cronometra() {
    orologio || return 1; inizio="$ns"
    sh "$esegui" "$@" || { echo "esegui.sh fallito per $caso ($2)" >&2; return 1; }
    orologio || return 1; ms=$(( (ns - inizio) / 1000000 ))
  }
  # controllo FASE: WAITPRB senza PARM (si ferma prima della CALL), rapporto in /out/controllo/CASO-FASE.txt.
  controllo() {
    c="/out/controllo/$caso-$1"
    mkdir -p "$c" || return 1
    cronometra "$c" WAITPRB || return 1
    mv "$c/WAITPRB.txt" "$c.txt" && rm -rf "$c" || return 1
  }
  while [ $# -ge 3 ]; do
    caso="$1"; prog="$2"; ingr="$3"; shift 3
    mkdir -p "/out/$caso" || exit 1
    if [ "$prog" = WAITPRB ]; then
      opz=--parm; val="$ingr"
    else
      s="/out/schede/$caso.sysin"
      case "$ingr" in
        jcl) sed -n "26{s/\r\$//;p}" "$jcl" > "$s" || { echo "scheda di $caso non ricavabile dal JCL" >&2; exit 1; } ;;
        jcl:*)
          d="${ingr#jcl:}"
          case "$d" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) echo "cifre non valide per $caso: $d" >&2; exit 1 ;; esac
          sed -n "26{s/\r\$//;s/^00003600/$d/;p}" "$jcl" > "$s" || { echo "scheda di $caso non ricavabile dal JCL" >&2; exit 1; } ;;
        vuoto) : > "$s" || exit 1 ;;
        testo:*) printf "%s\n" "${ingr#testo:}" > "$s" || exit 1 ;;
        *) echo "ingresso non valido per $caso: $ingr" >&2; exit 1 ;;
      esac
      opz=--sysin; val="$s"
    fi
    controllo prima || exit 1; prima="$ms"
    cronometra "/out/$caso" "$prog" "$opz" "$val" || exit 1; reale="$ms"
    controllo dopo || exit 1; dopo="$ms"
    echo "$reale $prima $dopo" > "/out/$caso.durata" || exit 1
    mv "/out/$caso/$prog.txt" "/out/$caso.txt" && mv "/out/$caso/$prog.ambiente" "/out/$caso.ambiente" \
      && rm -rf "/out/$caso" || exit 1
  done' sh "$esegui" "${terne[@]}" || fail "esecuzione dei casi di MVSWAIT fallita"

# controllo_valido RAPPORTO: il controllo ha davvero saltato la CALL (codice 2, nessuna riga di MVSWAIT).
controllo_valido() {
  local rc g=0
  [ -f "$1" ] || fail "rapporto di controllo assente: $(rel "$1")"
  rc="$(sed -n '2p' "$1")" || fail "rapporto di controllo illeggibile: $(rel "$1")"
  [ "$rc" = 2 ] || fail "il controllo $(rel "$1") termina con '$rc' invece di 2"
  grep -q '^MENB-ORACLE MVSWAIT' "$1" || g=$?
  case "$g" in
    1) ;;
    0) fail "il controllo $(rel "$1") ha chiamato MVSWAIT" ;;
    *) fail "lettura del controllo $(rel "$1") fallita (grep, codice $g)" ;;
  esac
}
i=0; violazioni=""; indecisi=""; lente=0
while [ "$i" -lt "${#terne[@]}" ]; do
  caso="${terne[$i]}"
  [ -f "$out/$caso.txt" ] || fail "rapporto di $caso assente"
  rc="$(sed -n '2p' "$out/$caso.txt")" || fail "rapporto di $caso illeggibile"
  riga="$(cat "$out/$caso.durata")" || fail "durata di $caso illeggibile"
  set -- $riga
  [ $# -eq 3 ] || fail "durata di $caso non valida: '$riga'"
  case "$1$2$3" in ''|*[!0-9]*) fail "durata di $caso non valida: '$riga'" ;; esac
  controllo_valido "$out/controllo/$caso-prima.txt"
  controllo_valido "$out/controllo/$caso-dopo.txt"
  rif="$2"; [ "$3" -le "$rif" ] || rif="$3"
  diff_ms=$(( $1 - rif ))
  nota=""
  if [ "$rif" -gt "$MVSWAIT_CONTROLLO_LENTO_MS" ]; then nota=", infrastruttura lenta"; lente=$((lente + 1)); fi
  log "$caso (${terne[$((i + 1))]} ${terne[$((i + 2))]}): codice di uscita $rc; durata $1 ms, controlli $2 e $3 ms, differenza $diff_ms ms$nota"
  if [ "$diff_ms" -gt "$MVSWAIT_DIFFERENZA_MS" ]; then
    if [ -n "$nota" ]; then indecisi="$indecisi $caso=${diff_ms}ms"; else violazioni="$violazioni $caso=${diff_ms}ms"; fi
  fi
  i=$((i + 3))
done
# Esiti: differenza oltre la soglia con controlli veloci = violazione (codice 1); oltre la soglia con controlli
# lenti = macchina troppo lenta per giudicare (codice 3, distinto: non e' un verde e non e' una violazione).
# Nessuna ripetizione: un'esecuzione lenta non si scarta mai.
[ -z "$violazioni" ] || fail "differenza con il controllo oltre ${MVSWAIT_DIFFERENZA_MS} ms (MVSWAIT non deve attendere):$violazioni."
if [ -n "$indecisi" ]; then
  echo "[$ORACLE_NAME] INFRASTRUTTURA LENTA: differenza oltre ${MVSWAIT_DIFFERENZA_MS} ms con controlli oltre ${MVSWAIT_CONTROLLO_LENTO_MS} ms, giudizio impossibile:$indecisi." >&2
  exit 3
fi
[ "$lente" -eq 0 ] || log "nota: infrastruttura lenta in $lente casi (controlli oltre ${MVSWAIT_CONTROLLO_LENTO_MS} ms), differenze entro la soglia"
