#!/usr/bin/env bash
# Prova di avvio reale: ogni eseguibile degli 11 e' lanciato nel container in una cartella di lavoro
# vuota, senza file d'ingresso, senza PARM e con stdin vuoto; i moduli CBSTM03B e CSUTLDTC sono
# richiamati dai programmi di prova M03BCALL e DTCCALL (oracle/tests/).
# Per ognuno si registra il rapporto di oracle/esegui.sh: codice di uscita, stdout, stderr, file creati.
# Output in oracle/avvio/out/<NOME>.txt (ignorato da git). AVVIO_OUT_DIR sposta l'output (controlli).
# AVVIO_SENZA_STUB=1 lancia i programmi con COB_LIBRARY_PATH vuoto (solo per una prova negativa).
. "$ORACLE_ROOT/lib.sh"

# Elenco dei lanci: gli 9 eseguibili del legacy e i due chiamanti dei moduli.
LANCI="CBACT01C CBACT02C CBACT03C CBACT04C CBCUS01C CBTRN01C CBTRN02C CBTRN03C COBSWAIT M03BCALL DTCCALL"

out="${AVVIO_OUT_DIR:-$ORACLE_ROOT/avvio/out}"
require_legacy
ensure_image
require_build
clean_dir "$out"

bin="$(in_container "$BUILD_OUT/bin")"
if [ "${AVVIO_SENZA_STUB:-0}" = 1 ]; then
  # Copia dei soli eseguibili, senza moduli: le CALL a CEE3ABD e ai segnaposto non si risolvono.
  vuota="$out/bin-senza-moduli"; mkdir -p "$vuota"
  for n in $LANCI; do cp "$BUILD_OUT/bin/$n" "$vuota/$n"; done
  bin="$(in_container "$vuota")"
fi
for n in $LANCI; do
  orun -v "$out:/out" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- sh /oracle/esegui.sh "$bin" /out "$n" \
    || fail "esecuzione di $n fallita"
  [ -f "$out/$n.txt" ] || fail "rapporto di $n assente"
  log "$n: codice di uscita $(sed -n '2p' "$out/$n.txt")"
done
