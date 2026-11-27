# Funzioni delle sentinelle dei tracciati (issue #43), da includere dopo lib/common.sh e tools/lib.sh.
#
#   dsen_genera OUT [SENTINELLE] [VISTE]
#       esegue la verifica completa (glue/verifica.py) e scrive OUT/sentinelle.md (documento generato) e
#       OUT/verifica.txt (uscita della verifica). SENTINELLE e VISTE (facoltativi, cartelle sotto analysis/) servono
#       solo alle prove negative di check.sh. Ogni uscita di una corsa precedente in OUT e' rimossa prima di
#       cominciare: un documento rimasto non puo' far passare una corsa fallita.
#   dsen_negativi OUT_FILE
#       esegue le prove negative (glue/negativi.py) e ne scrive l'uscita in OUT_FILE.
# Il legacy si legge dal volume sensibile alle maiuscole (menb-analysis-legacy-<commit>), in sola lettura.

DSEN_DIR="$ANALYSIS_ROOT/data-sentinelle"
DSEN_DC="$REPO_ROOT/docs/legacy-map/data-contract"
DSEN_DOC="$DSEN_DC/sentinelle.md"
DSEN_LEGACY=/legvol

dsen_cont() { echo "/analysis/${1#"$ANALYSIS_ROOT"/}"; }   # percorso, nei container della colla, di un file sotto analysis/

dsen_genera() {
  local out="$1" sent="${2:-$DSEN_DIR/sentinelle}" viste="${3:-$DSEN_DIR/viste.tsv}" rc=0 c_sent c_viste
  case "$sent:$viste" in "$ANALYSIS_ROOT"/*:"$ANALYSIS_ROOT"/*) ;; *) fail "sentinelle e viste devono stare sotto analysis/" ;; esac
  c_sent="$(dsen_cont "$sent")" || fail "percorso delle sentinelle non calcolato"
  c_viste="$(dsen_cont "$viste")" || fail "percorso di viste.tsv non calcolato"
  mkdir -p "$out" || fail "cartella $out non creata"
  rm -f "$out/sentinelle.md" "$out/verifica.txt" || fail "uscite precedenti in $out non rimosse"
  [ ! -e "$out/sentinelle.md" ] && [ ! -e "$out/verifica.txt" ] || fail "uscite precedenti ancora presenti in $out"
  ensure_legacy_volume
  glue_run --rw "$out" --mount "$LEGACY_VOL:$DSEN_LEGACY:ro" --mount "$DSEN_DC:/dc:ro" -- \
    /analysis/data-sentinelle/glue/verifica.py "$DSEN_LEGACY" /dc/contratti /dc/contratti.tsv \
    "$c_sent" "$c_viste" --doc /work/sentinelle.md > "$out/verifica.txt" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$out/sentinelle.md"
    cat "$out/verifica.txt" >&2
    fail "verifica delle sentinelle fallita (uscita $rc)"
  fi
  [ "$(tail -n 1 "$out/verifica.txt" | cut -c1-19)" = "verifica riuscita: " ] \
    || { cat "$out/verifica.txt" >&2; fail "verifica delle sentinelle senza esito riconoscibile"; }
  [ -s "$out/sentinelle.md" ] || fail "documento sentinelle.md non scritto dalla verifica"
}

dsen_negativi() {
  local file="$1" rc=0
  ensure_legacy_volume
  glue_run --mount "$LEGACY_VOL:$DSEN_LEGACY:ro" --mount "$DSEN_DC:/dc:ro" -- \
    /analysis/data-sentinelle/glue/negativi.py "$DSEN_LEGACY" /dc/contratti /dc/contratti.tsv \
    /analysis/data-sentinelle/sentinelle /analysis/data-sentinelle/viste.tsv > "$file" 2>&1 || rc=$?
  return "$rc"
}
