#!/usr/bin/env bash
# Prova di COBDATFT (oracle/stubs/COBDATFT.cbl): il chiamante di prova DATFTPRB (oracle/tests/) riempie
# l'area di 80 byte con X'A5', vi scrive i byte del caso (dal PARM), stampa l'area in esadecimale, chiama
# COBDATFT e stampa codice di ritorno e area dopo la chiamata. Un'esecuzione per ogni caso di
# oracle/routines/casi.tsv, ognuna con il rapporto di oracle/esegui.sh (codice di uscita visto dalla
# shell che ha lanciato il programma, stdout, stderr, file creati) e l'ambiente ricevuto.
# Output in oracle/routines/out/: <CASO>.txt e <CASO>.ambiente.
# ROUTINES_OUT_DIR e ROUTINES_BIN_DIR spostano output e artefatti (usate dalle prove negative).
. "$ORACLE_ROOT/lib.sh"

CASI="$ORACLE_ROOT/routines/casi.tsv"
out="${ROUTINES_OUT_DIR:-$ORACLE_ROOT/routines/out}"
bin="${ROUTINES_BIN_DIR:-$BUILD_OUT/bin}"
require_legacy
ensure_image
[ -n "${ROUTINES_BIN_DIR:-}" ] || require_build
[ -x "$bin/DATFTPRB" ] || fail "DATFTPRB assente in $(rel "$bin")"
[ -f "$bin/COBDATFT.so" ] || fail "COBDATFT.so assente in $(rel "$bin")"
clean_dir "$out"

# Coppie caso/PARM, nell'ordine del file (righe non commento, intestazione esclusa).
coppie=()
while IFS="$(printf '\t')" read -r caso parm comb; do
  [ -n "$caso" ] || continue
  case "$caso" in *[!A-Z0-9]*) fail "nome di caso non valido in casi.tsv: '$caso'" ;; esac
  coppie+=("$caso" "$parm")
done < <(grep -v '^#' "$CASI" | tail -n +2)
[ "${#coppie[@]}" -gt 0 ] || fail "nessun caso in $(rel "$CASI")"

# Un solo container per tutti i casi; ogni esecuzione passa da esegui.sh (ambiente fissato, limite di
# tempo). Il primo esito diverso da 0 di esegui.sh (fallimento dello strumento) ferma la prova.
orun -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- sh -c '
  set -u
  while [ $# -ge 2 ]; do
    caso="$1"; parm="$2"; shift 2
    mkdir -p "/out/$caso" || exit 1
    sh /oracle/esegui.sh "/out/$caso" DATFTPRB --parm "$parm" || { echo "esegui.sh fallito per $caso" >&2; exit 1; }
    mv "/out/$caso/DATFTPRB.txt" "/out/$caso.txt" && mv "/out/$caso/DATFTPRB.ambiente" "/out/$caso.ambiente" \
      && rm -rf "/out/$caso" || exit 1
  done' sh "${coppie[@]}" || fail "esecuzione dei casi di COBDATFT fallita"

i=0
while [ "$i" -lt "${#coppie[@]}" ]; do
  caso="${coppie[$i]}"
  [ -f "$out/$caso.txt" ] || fail "rapporto di $caso assente"
  log "$caso (PARM ${coppie[$((i + 1))]}): codice di uscita $(sed -n '2p' "$out/$caso.txt")"
  i=$((i + 2))
done
