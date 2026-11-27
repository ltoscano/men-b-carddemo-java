#!/usr/bin/env bash
# Prova di cb2xml: tracciato (offset, lunghezza, tipo) di CVACT01Y, CVACT03Y, CVTRA05Y, CVEXPORT.
# Opzioni di rappresentazione: dialetto Mainframe (default di cb2xml) => binari COMP a 2/4/8 byte
# in base alle cifre (1-4, 5-9, 10-18); formato XML 2017.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
require_legacy
ensure_legacy_volume

build_image "$IMG_CB2XML" "$DOCKER_DIR/cb2xml"
rm -rf "$OUT/cb2xml"
mkdir -p "$OUT/cb2xml"

printf 'cb2xml 1.01.08 (jar della release GitHub, SHA-256 verificato in fase di build)\n' > "$OUT/cb2xml/version.txt"
record cb2xml command.txt "per ogni copybook C in CVACT01Y CVACT03Y CVTRA05Y CVEXPORT:
java -cp cb2xml.jar net.sf.cb2xml.Cb2Xml -cobol /legacy/app/cpy/C.cpy -xml /out/C.xml -indentXml -Dialect Mainframe
(eseguito in $IMG_CB2XML; opzioni di rappresentazione: dialetto Mainframe, formato XML 2017)"

for c in CVACT01Y CVACT03Y CVTRA05Y CVEXPORT; do
  grep -q "^app/cpy/$c.cpy	copybook$" "$MANIFEST" || fail "$c.cpy non risulta copybook nel manifesto"
  tool_run "$IMG_CB2XML" "$OUT/cb2xml" -- -cobol "/legacy/app/cpy/$c.cpy" -xml "/out/$c.xml" -indentXml -Dialect Mainframe
done

glue_run --rw "$OUT/cb2xml" -- /analysis/tools/glue/normalize.py cb2xml /work
log "cb2xml: tracciati scritti in out/cb2xml/layout.tsv"
