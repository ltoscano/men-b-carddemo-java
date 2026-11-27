#!/usr/bin/env bash
# Contratto dati (issue #3): censimento dei tracciati, contratti fisici campo per campo, chiavi da quattro fonti.
# Rigenera dal legacy (cb2xml in container + estrazione testuale dichiarata) l'output in analysis/data-contract/out/
# e i documenti generati in docs/legacy-map/data-contract/ (contratti/, contratti.tsv, contratti.md, chiavi.*,
# parte generata di censimento.md). I file scritti a mano non vengono toccati.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/data-contract/lib.sh"
require_legacy
[ -f "$MANIFEST" ] || fail "manifesto assente: eseguire prima './analysis/run.sh manifest'"

genera "$DC_DIR/out" "$DC_DOCS"
log "contratti: $(($(wc -l < "$DC_DOCS/contratti.tsv") - 1)); discordanze e osservazioni rilevate: $(($(wc -l < "$DC_DIR/out/discordanze-rilevate.tsv") - 1))"
