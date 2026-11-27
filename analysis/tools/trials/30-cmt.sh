#!/usr/bin/env bash
# Prova di cobol-migration-toolkit (primo candidato per "grafi COPY e CALL") sui 31 programmi di app/cbl/.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
require_legacy
ensure_legacy_volume

build_image "$IMG_CMT" "$DOCKER_DIR/cmt"
rm -rf "$OUT/cmt"
mkdir -p "$OUT/cmt"

docker run --rm --entrypoint pip "$IMG_CMT" show cobol-migration-toolkit | grep -E '^(Name|Version|License)' > "$OUT/cmt/version.txt"
record cmt command.txt "cobol-migrate scan /legacy/app/cbl --copybook-path /legacy/app/cpy --copybook-path /legacy/app/cpy-bms --format json --format dot --output /out
(l'intera cartella app/cbl contiene esattamente i programmi del manifesto: lo verifica check.sh)"

tool_run "$IMG_CMT" "$OUT/cmt" -- scan /legacy/app/cbl --copybook-path /legacy/app/cpy --copybook-path /legacy/app/cpy-bms \
  --format json --format dot --output /out | tee "$OUT/cmt/stdout.txt" >&2

# Forma normalizzata (colla): un'occorrenza per riga -> copy.tsv / calls.tsv
glue_run --rw "$OUT/cmt" -- /analysis/tools/glue/normalize.py cmt /work
