#!/usr/bin/env bash
# Banco di prova degli strumenti di analisi: esegue ogni prova in container e salva in analysis/tools/out/
# l'output, il comando, la versione e il verdetto del confronto con gli attesi scritti a mano.
#
# Regola sulle riserve (issue #1): una riserva si prova solo se il candidato che la precede per la stessa capacita'
# risulta scartato o insufficiente; si procede una alla volta, nell'ordine indicato, fino a trovarne una adottabile
# o a esaurirle. Un verdetto "fail" e' un dato, non un errore di questo script.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
require_legacy

trial() { bash "$TOOLS_DIR/trials/$1.sh"; }

# verdict CHECK [TOOL] [DIRECTORY-DEL-VERDETTO]: esegue il confronto e salva l'esito; ritorna 0 se pass, 1 se fail.
verdict() {
  local check="$1" tool="${2:-}" dir="${3:-${2:-}}" file rc=0
  [ -n "$dir" ] || dir="$check"
  mkdir -p "$OUT/$dir"
  file="$OUT/$dir/verdetto-$check.txt"
  verdict_require_declared "$dir/verdetto-$check.txt"
  verdict_text "$check" "$tool" > "$file" || fail "scrittura del verdetto $dir/verdetto-$check.txt fallita"
  verdict_record "$dir/verdetto-$check.txt" "$check" "$tool"
  [ "$(tail -1 "$file")" = "VERDETTO: pass" ] || rc=1
  log "verdetto $check ${tool}: $(tail -1 "$file")"
  return $rc
}

mkdir -p "$OUT"

# --- conteggi
trial 10-scc
verdict scc "" scc || true
# Capacita' ripartizione-codice-commenti: i campioni a mano smentiscono scc. Il fallimento e' la prova richiesta
# per una capacita' unavailable e si salva come tale (campioni, valori di scc e differenze).
verdict_require_declared "scc/prova-fallita-ripartizione.txt"
verdict_text scc-split > "$OUT/scc/prova-fallita-ripartizione.txt" || fail "scrittura di scc/prova-fallita-ripartizione.txt fallita"
verdict_record "scc/prova-fallita-ripartizione.txt" scc-split ""
log "prova del fallimento (ripartizione codice/commenti): $(tail -1 "$OUT/scc/prova-fallita-ripartizione.txt")"

# --- compilazione e diagnostica
trial 20-gnucobol
verdict compile "" gnucobol || true

# --- grafi COPY e CALL: primo candidato cobol-migration-toolkit; riserve cobmix, ProLeap, Koopa
trial 30-cmt
verdict call cmt || true
copy_ok=1
verdict copy cmt || copy_ok=0
if [ "$copy_ok" -eq 0 ]; then
  log "cmt insufficiente per le occorrenze COPY: si prova la prima riserva (cobmix)"
  trial 31-cobmix
  copy_ok=1; verdict copy cobmix || copy_ok=0
else
  rm -rf "$OUT/cobmix" "$OUT/proleap"
fi
if [ "$copy_ok" -eq 0 ]; then
  log "cobmix insufficiente: si prova la seconda riserva (ProLeap)"
  trial 32-proleap
  copy_ok=1; verdict copy proleap || copy_ok=0
else
  rm -rf "$OUT/proleap"
fi
[ "$copy_ok" -eq 1 ] || log "ATTENZIONE: nessuna riserva provata ha superato le occorrenze COPY (Koopa non provato: aggiungere una prova e rieseguire)"

# --- tracciati dei copybook
trial 40-cb2xml
verdict layout "" cb2xml || true

# --- JCL
trial 50-mapa
verdict jcl "" mapa || true

# I verdetti scritti in QUESTA corsa devono essere esattamente quelli dichiarati in verdetti.tsv (un file preesistente
# non vale), e sul disco non deve esserci nient'altro.
verdict_written_check || fail "i verdetti scritti in questa corsa non coincidono con analysis/tools/verdetti.tsv"
verdict_set_check "$OUT" || fail "i verdetti presenti non coincidono con analysis/tools/verdetti.tsv"

log "prove completate; i verdetti sono in analysis/tools/out/*/verdetto-*.txt"
