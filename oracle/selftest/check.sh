#!/usr/bin/env bash
# Test automatico del comando unico oracle/run.sh (non usa Docker): ordine per dipendenze, dipendenza
# mancante, ciclo, arresto al primo errore, controllo mancante (oracle/selftest/scenari.sh).
# Prove negative: gli stessi scenari eseguiti su copie alterate di run.sh devono fallire.
. "$ORACLE_ROOT/lib.sh"

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT
SCENARI="$ORACLE_ROOT/selftest/scenari.sh"

log "1. scenari sul comando unico"
mkdir -p "$tmp/vero"
bash "$SCENARI" "$ORACLE_ROOT/run.sh" "$tmp/vero" >&2 || fail "il comando unico non supera gli scenari"

log "2. prove negative: copie alterate del comando unico"
cp "$ORACLE_ROOT/run.sh" "$tmp/run-controllo.sh"
mutate "$tmp/run-controllo.sh" 's/^    if \[ "\$mode" = check \]; then$/    if false; then/'
mkdir -p "$tmp/m1"
expect_fail "run.sh che salta i passi senza check.sh" "ha accettato un passo senza check.sh" bash "$SCENARI" "$tmp/run-controllo.sh" "$tmp/m1"
cp "$ORACLE_ROOT/run.sh" "$tmp/run-ordine.sh"
mutate "$tmp/run-ordine.sh" 's/order="\$(topo_order)" || exit 1/order="$(list_steps)" || exit 1/'
mkdir -p "$tmp/m2"
expect_fail "run.sh che ignora le dipendenze" "output del produttore assente" bash "$SCENARI" "$tmp/run-ordine.sh" "$tmp/m2"
cp "$ORACLE_ROOT/run.sh" "$tmp/run-errore.sh"
mutate "$tmp/run-errore.sh" 's/run_one "\$n" "\$mode" || {/run_one "$n" "$mode" || true || {/'
mkdir -p "$tmp/m3"
expect_fail "run.sh che non si ferma al primo errore" "senza deps il consumatore avrebbe dovuto fallire" bash "$SCENARI" "$tmp/run-errore.sh" "$tmp/m3"
log "controllo superato"
