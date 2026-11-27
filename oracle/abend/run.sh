#!/usr/bin/env bash
# Prova dello stub CEE3ABD: i programmi di prova ABDUSING (CALL 'CEE3ABD' USING ABCODE, TIMING) e
# ABDNOARG (CALL 'CEE3ABD' senza argomenti) aprono il file ABDFILE, vi scrivono un record, lo lasciano
# aperto e chiamano CEE3ABD. Il file e' assegnato con la variabile DD_ABDFILE a un percorso fuori dalla
# cartella di lavoro (esempio reale dell'assegnazione DD -> file per un file sequenziale).
# Per ognuno si registrano il rapporto di oracle/esegui.sh (codice di uscita visto dalla shell che ha
# lanciato il programma, cioe' il processo padre; stdout; stderr) e i byte del file dopo l'arresto.
# Output in oracle/abend/out/: <NOME>.txt e <NOME>.dat.hex ("assente" se il file non esiste).
# ABEND_OUT_DIR e ABEND_BIN_DIR spostano output e artefatti (usate dalle prove negative).
. "$ORACLE_ROOT/lib.sh"

PROVE="ABDUSING ABDNOARG"
out="${ABEND_OUT_DIR:-$ORACLE_ROOT/abend/out}"
bin="${ABEND_BIN_DIR:-$BUILD_OUT/bin}"
require_legacy
ensure_image
[ -n "${ABEND_BIN_DIR:-}" ] || require_build
clean_dir "$out"

for n in $PROVE; do
  [ -x "$bin/$n" ] || fail "$n assente in $(rel "$bin")"
  mkdir -p "$out/dd-$n"
  orun -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- \
    sh /oracle/esegui.sh /out "$n" --dd "DD_ABDFILE=/out/dd-$n/ABDFILE.dat" || fail "esecuzione di $n fallita"
  [ -f "$out/$n.txt" ] || fail "rapporto di $n assente"
  if [ -f "$out/dd-$n/ABDFILE.dat" ]; then
    orun -v "$out:/out" -- timeout 60 od -An -tx1 -v "/out/dd-$n/ABDFILE.dat" \
      | tr -s ' \n' '  ' | sed -e 's/^ //' -e 's/ $//' > "$out/$n.dat.hex" || fail "lettura di ABDFILE di $n fallita"
    echo >> "$out/$n.dat.hex"
  else
    echo "assente" > "$out/$n.dat.hex"
  fi
  log "$n: codice di uscita $(sed -n '2p' "$out/$n.txt"); ABDFILE: $(cat "$out/$n.dat.hex")"
done
