#!/usr/bin/env bash
# Prova del segno dei numeri DISPLAY: il programma di prova SEGNOPRB (oracle/tests/SEGNOPRB.cbl) legge il
# file di dati originale app/data/ASCII/dailytran.txt (assegnato con DD_DALYTRAN, dal volume del legacy in
# sola lettura) con il copybook originale CVTRA06Y, stampa importi letti, ramo credito/debito e i byte che
# GnuCOBOL scrive per gli stessi importi e per alcune costanti; questi byte vanno anche nel file SEGNOOUT
# (assegnato con DD_SEGNOOUT fuori dalla cartella di lavoro).
# Output in oracle/segno/out/: SEGNOPRB.txt (rapporto di oracle/esegui.sh) e SEGNOOUT.txt (contenuto del
# file scritto, seguito da un a capo; "assente" se il file non esiste).
# SEGNO_OUT_DIR e SEGNO_BIN_DIR spostano output e artefatti (usate dalle prove negative).
. "$ORACLE_ROOT/lib.sh"

out="${SEGNO_OUT_DIR:-$ORACLE_ROOT/segno/out}"
bin="${SEGNO_BIN_DIR:-$BUILD_OUT/bin}"
require_legacy
ensure_image
[ -n "${SEGNO_BIN_DIR:-}" ] || require_build
[ -x "$bin/SEGNOPRB" ] || fail "SEGNOPRB assente in $(rel "$bin")"
clean_dir "$out"
mkdir -p "$out/dd"

orun -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- \
  sh /oracle/esegui.sh /out SEGNOPRB --dd DD_DALYTRAN=/legacy/app/data/ASCII/dailytran.txt \
  --dd DD_SEGNOOUT=/out/dd/SEGNOOUT.dat || fail "esecuzione di SEGNOPRB fallita"
[ -f "$out/SEGNOPRB.txt" ] || fail "rapporto di SEGNOPRB assente"
if [ -f "$out/dd/SEGNOOUT.dat" ]; then
  { cat "$out/dd/SEGNOOUT.dat"; echo; } > "$out/SEGNOOUT.txt" || fail "lettura di SEGNOOUT fallita"
else
  echo "assente" > "$out/SEGNOOUT.txt"
fi
log "SEGNOPRB: codice di uscita $(sed -n '2p' "$out/SEGNOPRB.txt"); SEGNOOUT: $(cat "$out/SEGNOOUT.txt")"
