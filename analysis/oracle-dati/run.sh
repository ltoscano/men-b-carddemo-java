#!/usr/bin/env bash
# Record dei file indicizzati nel profilo dell'oracle GnuCOBOL (issue #53). Per ogni riga di tabella.tsv (oggi solo
# ACCTFILE) porta il file che il JCL carica nel KSDS dal profilo zos-ebcdic al profilo oracle-gnucobol campo per campo,
# con il codec di #23 guidato dal contratto di #3 attraverso l'adattatore di #43, esegue i cinque controlli della
# specifica (1, 2, 4, 5 nella colla; 3, la controprova con il file ASCII, in controprova.sh con le sole utility POSIX)
# e solo se tutti riescono rigenera analysis/oracle-dati/out/ e docs/legacy-map/oracle-dati.md.
# Solo per le prove negative di check.sh: ODT_OUT_DIR e ODT_DOC_FILE spostano le due destinazioni (sotto analysis/.work).
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/oracle-dati/lib.sh"
require_legacy

dest="${ODT_OUT_DIR:-$ODT_DIR/out}"
doc="${ODT_DOC_FILE:-$ODT_DOC}"
tmp="$(mktmp)" || fail "cartella temporanea non creata"
trap 'rm -rf "$tmp"' EXIT
odt_genera "$tmp/gen"
rm -rf "$dest" || fail "out/ precedente non rimossa"
[ ! -e "$dest" ] || fail "out/ precedente ancora presente"
cp -R "$tmp/gen/out" "$dest" || fail "impossibile scrivere analysis/oracle-dati/out/"
cp "$tmp/gen/oracle-dati.md" "$doc" || fail "impossibile scrivere docs/legacy-map/oracle-dati.md"
sed 's/^/   /' "$tmp/gen/verifica.txt" >&2 || fail "uscita della verifica illeggibile"
sed 's/^/   /' "$tmp/gen/controprova.txt" >&2 || fail "uscita della controprova illeggibile"
log "record in analysis/oracle-dati/out/, documento docs/legacy-map/oracle-dati.md"
