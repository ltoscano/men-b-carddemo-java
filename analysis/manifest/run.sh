#!/usr/bin/env bash
# Genera analysis/manifest/sources.tsv: un file tracciato del submodule legacy per riga, con il tipo.
# Fonte di verita': git -C $LEGACY ls-files (git sull'host e' un prerequisito ammesso); la
# classificazione gira in container.
. "$ANALYSIS_ROOT/lib/common.sh"
require_legacy

here="$(pwd)"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

legacy_ls_files | glue_run --stdin -- /analysis/manifest/classify.py > "$tmp/sources.tsv"
mv "$tmp/sources.tsv" "$here/sources.tsv"

mkdir -p "$here/out"
# Riepilogo per tipo e elenco di cio' che non si riconosce.
awk -F'\t' 'NR>1 {n[$2]++} END {for (t in n) printf "%s\t%d\n", t, n[t]}' "$here/sources.tsv" | LC_ALL=C sort > "$here/out/summary.tsv"
awk -F'\t' 'NR>1 && $2=="other" {print $1}' "$here/sources.tsv" > "$here/out/other.txt"
log "manifesto scritto: $(($(wc -l < "$here/sources.tsv") - 1)) file; altri non riconosciuti: $(wc -l < "$here/out/other.txt" | tr -d ' ')"
