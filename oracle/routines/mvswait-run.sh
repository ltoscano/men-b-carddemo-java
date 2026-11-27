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
# Limite operativo: ogni esecuzione che chiama MVSWAIT ha MVSWAIT_LIMITE secondi (3), applicato da esegui.sh
# (ORACLE_TIMEOUT_RUN): allo scadere esegui.sh termina il programma e fallisce, e con lui questa prova.
# Output in oracle/routines/out/mvswait/: <CASO>.txt, <CASO>.ambiente, schede/<CASO>.sysin.
# Solo per le prove negative di mvswait-check.sh: MVSWAIT_OUT_DIR sposta l'output, MVSWAIT_BIN_DIR gli
# artefatti (con WAITPRB, COBSWAIT e MVSWAIT.so), MVSWAIT_ESEGUI indica una copia alterata di esegui.sh
# (sotto oracle/), MVSWAIT_CASI un elenco di casi diverso (uno o piu' file, separati da spazi).
. "$ORACLE_ROOT/lib.sh"

MVSWAIT_LIMITE=3
DIR="$ORACLE_ROOT/routines"
casi="${MVSWAIT_CASI:-$DIR/mvswait-prove.tsv $DIR/mvswait-osservazioni.tsv}"
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
for f in $casi; do
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

# Un solo container per tutti i casi, con un limite complessivo di 300 s. Ogni comando ha l'esito
# controllato: il primo fallimento (scheda non ricavabile, esegui.sh fallito o fuori tempo) ferma la prova.
orun -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$MVSWAIT_LIMITE" -- timeout -k 10 300 sh -c '
  set -u
  esegui="$1"; shift
  jcl=/legacy/app/jcl/WAITSTEP.jcl
  while [ $# -ge 3 ]; do
    caso="$1"; prog="$2"; ingr="$3"; shift 3
    mkdir -p "/out/$caso" || exit 1
    if [ "$prog" = WAITPRB ]; then
      sh "$esegui" "/out/$caso" WAITPRB --parm "$ingr" || { echo "esegui.sh fallito per $caso" >&2; exit 1; }
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
      sh "$esegui" "/out/$caso" COBSWAIT --sysin "$s" || { echo "esegui.sh fallito per $caso" >&2; exit 1; }
    fi
    mv "/out/$caso/$prog.txt" "/out/$caso.txt" && mv "/out/$caso/$prog.ambiente" "/out/$caso.ambiente" \
      && rm -rf "/out/$caso" || exit 1
  done' sh "$esegui" "${terne[@]}" || fail "esecuzione dei casi di MVSWAIT fallita"

i=0
while [ "$i" -lt "${#terne[@]}" ]; do
  caso="${terne[$i]}"
  [ -f "$out/$caso.txt" ] || fail "rapporto di $caso assente"
  rc="$(sed -n '2p' "$out/$caso.txt")" || fail "rapporto di $caso illeggibile"
  log "$caso (${terne[$((i + 1))]} ${terne[$((i + 2))]}): codice di uscita $rc"
  i=$((i + 3))
done
