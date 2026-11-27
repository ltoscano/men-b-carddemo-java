#!/usr/bin/env bash
# Sonda semantica sul dialetto: il programma di prova PERFPRB (oracle/tests/PERFPRB.cbl) dipende da
# perform-osvs, un'impostazione che non e' tra le opzioni di cobc ma viene dalla configurazione del
# dialetto IBM letta dal compilatore. Si registrano il rapporto di oracle/esegui.sh e l'ambiente ricevuto.
# Output in oracle/dialetto/out/: PERFPRB.txt e PERFPRB.ambiente.
# DIALETTO_OUT_DIR e DIALETTO_BIN_DIR spostano output e artefatti (usate dalle prove negative).
. "$ORACLE_ROOT/lib.sh"

out="${DIALETTO_OUT_DIR:-$ORACLE_ROOT/dialetto/out}"
bin="${DIALETTO_BIN_DIR:-$BUILD_OUT/bin}"
require_legacy
ensure_image
[ -n "${DIALETTO_BIN_DIR:-}" ] || require_build
[ -x "$bin/PERFPRB" ] || fail "PERFPRB assente in $(rel "$bin")"
clean_dir "$out"

orun -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- \
  sh /oracle/esegui.sh /out PERFPRB || fail "esecuzione di PERFPRB fallita"
[ -f "$out/PERFPRB.txt" ] || fail "rapporto di PERFPRB assente"
log "PERFPRB: codice di uscita $(sed -n '2p' "$out/PERFPRB.txt"); righe: $(sed -n '/^== stdout$/,/^== stderr$/p' "$out/PERFPRB.txt" | sed '1d;$d' | tr '\n' ' ')"
