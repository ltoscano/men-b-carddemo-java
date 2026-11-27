#!/usr/bin/env bash
# Prova di cobmix (riserva per "grafi COPY e CALL"): provato perché il primo candidato (cobol-migration-toolkit)
# non conserva le occorrenze di COPY con riga e sostituzioni. Vista "copybook" su ogni programma di app/cbl/.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
require_legacy
ensure_legacy_volume

build_image "$IMG_COBMIX" "$DOCKER_DIR/cobmix"
rm -rf "$OUT/cobmix"
mkdir -p "$OUT/cobmix"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

docker run --rm --entrypoint pip "$IMG_COBMIX" show cobmix | grep -E '^(Name|Version|License)' > "$OUT/cobmix/version.txt"
record cobmix command.txt "per ogni programma P di app/cbl/ (elenco dal manifesto):
cobmix --code-file /legacy/<P> --copy-path /legacy/app/cpy --copy-path /legacy/app/cpy-bms --graphs copybook --format json --output /out/<P>
(il JSON grezzo, di centinaia di nodi per programma, non e' versionato: si conserva la forma normalizzata in copy.tsv)"

while IFS= read -r rel; do
  prog="$(basename "$rel")"; prog="${prog%.*}"
  tool_run "$IMG_COBMIX" "$work" -- --code-file "/legacy/$rel" --copy-path /legacy/app/cpy --copy-path /legacy/app/cpy-bms \
    --graphs copybook --format json --output "/out/$prog" > /dev/null
done < <(app_cbl_programs)

glue_run --rw "$work" -- /analysis/tools/glue/normalize.py cobmix /work
cp "$work/copy.tsv" "$OUT/cobmix/copy.tsv"
