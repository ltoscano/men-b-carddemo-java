#!/usr/bin/env bash
# Prova di avvio reale: ogni eseguibile degli 11 e' lanciato nel container in una cartella di lavoro
# vuota, senza file d'ingresso, senza PARM, con stdin vuoto e nell'ambiente fissato di oracle/ambiente.sh;
# i moduli CBSTM03B e CSUTLDTC sono richiamati dai programmi di prova M03BCALL e DTCCALL (oracle/tests/).
# Per ognuno si registrano il rapporto di oracle/esegui.sh (codice di uscita, stdout, stderr, file creati)
# e l'ambiente ricevuto dal programma.
# Output in oracle/avvio/out/<NOME>.txt e <NOME>.ambiente (ignorati da git). AVVIO_OUT_DIR sposta l'output.
# Solo per le prove negative del controllo: AVVIO_SENZA_STUB=1 monta in /oracle-bin i soli eseguibili,
# senza moduli; AVVIO_ESEGUI indica una copia alterata di esegui.sh (sotto oracle/).
. "$ORACLE_ROOT/lib.sh"

# Elenco dei lanci: gli 9 eseguibili del legacy e i due chiamanti dei moduli.
LANCI="CBACT01C CBACT02C CBACT03C CBACT04C CBCUS01C CBTRN01C CBTRN02C CBTRN03C COBSWAIT M03BCALL DTCCALL"

out="${AVVIO_OUT_DIR:-$ORACLE_ROOT/avvio/out}"
esegui="/oracle/esegui.sh"
[ -z "${AVVIO_ESEGUI:-}" ] || esegui="$(in_container "$AVVIO_ESEGUI")"
require_legacy
ensure_image
require_build
clean_dir "$out"

bin="$BUILD_OUT/bin"
if [ "${AVVIO_SENZA_STUB:-0}" = 1 ]; then
  # Copia dei soli eseguibili, senza moduli: le CALL a CEE3ABD e ai segnaposto non si risolvono.
  vuota="$out/bin-senza-moduli"; mkdir -p "$vuota"
  for n in $LANCI; do cp "$BUILD_OUT/bin/$n" "$vuota/$n"; done
  bin="$vuota"
fi
for n in $LANCI; do
  orun -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- sh "$esegui" /out "$n" \
    || fail "esecuzione di $n fallita"
  [ -f "$out/$n.txt" ] || fail "rapporto di $n assente"
  log "$n: codice di uscita $(sed -n '2p' "$out/$n.txt")"
done
