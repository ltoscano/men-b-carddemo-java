#!/usr/bin/env bash
# Prova dell'avviatore: il programma di prova PARMECHO (oracle/tests/PARMECHO.cbl, stessa LINKAGE di
# CBACT04C) e' avviato come `EXEC PGM=CBACT04C,PARM='2022071800'` di app/jcl/INTCALC.jcl, cioe' con il
# testo 2022071800 come PARM. Si registrano il rapporto di oracle/esegui.sh e i byte dell'area ricevuta,
# che PARMECHO scrive nel file PARMDUMP (assegnato senza variabile DD: il file si chiama PARMDUMP nella
# cartella di lavoro).
# Output in oracle/avviatore/out/: PARMECHO.txt (rapporto) e PARMDUMP.hex (byte in esadecimale).
# AVVIATORE_OUT_DIR e AVVIATORE_BIN_DIR spostano output e artefatti (usate dalle prove negative).
. "$ORACLE_ROOT/lib.sh"

PARM="2022071800"
out="${AVVIATORE_OUT_DIR:-$ORACLE_ROOT/avviatore/out}"
bin="${AVVIATORE_BIN_DIR:-$BUILD_OUT/bin}"
require_legacy
ensure_image
[ -n "${AVVIATORE_BIN_DIR:-}" ] || require_build
[ -x "$bin/PARMECHO" ] || fail "PARMECHO assente in $(rel "$bin")"
clean_dir "$out"

orun -v "$out:/out" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- \
  sh /oracle/esegui.sh "$(in_container "$bin")" /out PARMECHO "$PARM" || fail "esecuzione di PARMECHO fallita"
[ -f "$out/PARMECHO.txt" ] || fail "rapporto di PARMECHO assente"
if [ -f "$out/lavoro-PARMECHO/PARMDUMP" ]; then
  # od gira nel container: stesse utility su ogni host. Una riga: byte esadecimali separati da uno spazio.
  orun -v "$out:/out" -- timeout 60 od -An -tx1 -v /out/lavoro-PARMECHO/PARMDUMP \
    | tr -s ' \n' '  ' | sed -e 's/^ //' -e 's/ $//' > "$out/PARMDUMP.hex" || fail "lettura dei byte di PARMDUMP fallita"
  echo >> "$out/PARMDUMP.hex"
fi
log "PARMECHO: codice di uscita $(sed -n '2p' "$out/PARMECHO.txt"); area: $(cat "$out/PARMDUMP.hex" 2>/dev/null || echo 'PARMDUMP assente')"
