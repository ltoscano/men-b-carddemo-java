#!/usr/bin/env bash
# Prova di scc: conteggi di file e righe (codice / commenti / vuote) su $LEGACY/app/.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
require_legacy
ensure_legacy_volume

build_image "$IMG_SCC" "$DOCKER_DIR/scc"
mkdir -p "$OUT/scc"
opts="--no-config --no-gitignore --no-ignore --no-scc-ignore --no-cocomo --no-complexity"

docker run --rm "$IMG_SCC" --version > "$OUT/scc/version.txt"
record scc command.txt "docker run --rm -v \$LEGACY:/legacy:ro $IMG_SCC $opts --by-file -f csv /legacy/app    (CSV per file, righe ordinate)
docker run --rm -v \$LEGACY:/legacy:ro $IMG_SCC $opts /legacy/app/<cbl|cpy|jcl>    (riepilogo per cartella, formato csv)"

# CSV per file: l'ordine di uscita dipende dal parallelismo, quindi si ordina (intestazione per prima).
tool_run "$IMG_SCC" "$OUT/scc" -- $opts --by-file -f csv /legacy/app > "$OUT/scc/.raw.csv"
{ head -1 "$OUT/scc/.raw.csv"; tail -n +2 "$OUT/scc/.raw.csv" | LC_ALL=C sort; } > "$OUT/scc/app-by-file.csv"
rm -f "$OUT/scc/.raw.csv"

# Riepilogo per le cartelle usate come baseline.
: > "$OUT/scc/dirs.csv"
for d in cbl cpy jcl; do
  tool_run "$IMG_SCC" "$OUT/scc" -- $opts -f csv "/legacy/app/$d" | sed "s#^#app/$d,#" >> "$OUT/scc/dirs.csv"
done
# Tabella leggibile (stessa esecuzione, formato tabulare) per il documento.
tool_run "$IMG_SCC" "$OUT/scc" -- $opts /legacy/app > "$OUT/scc/app-summary.txt"
log "scc: $(( $(wc -l < "$OUT/scc/app-by-file.csv") - 1 )) file contati in app/"
