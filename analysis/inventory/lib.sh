# Funzioni dell'analisi "inventory" (da includere dopo lib/common.sh e tools/lib.sh).
INV_DIR="$ANALYSIS_ROOT/inventory"
DOCS_DIR="$REPO_ROOT/docs/legacy-map"
IMG_JSONSCHEMA="menb-inventory-jsonschema:4.23.0"
INV_JOBS=6

# py RW_DIR script.py args...: esegue uno script di colla nel container Python di base, con analysis/ in sola lettura su
# /analysis, il legacy (volume sensibile alle maiuscole) in sola lettura su /legacy e RW_DIR scrivibile su /work.
py() {
  local rw="$1"; shift
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e PYTHONDONTWRITEBYTECODE=1 \
    -v "$ANALYSIS_ROOT:/analysis:ro" -v "$LEGACY_VOL:/legacy:ro" -v "$rw:/work" "$GLUE_IMAGE" python -I "$@"
}
# psh RW_DIR comando...: come py, ma esegue un comando di shell nel container (sh -c).
psh() {
  local rw="$1"; shift
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e PYTHONDONTWRITEBYTECODE=1 \
    -v "$ANALYSIS_ROOT:/analysis:ro" -v "$LEGACY_VOL:/legacy:ro" -v "$rw:/work" "$GLUE_IMAGE" sh -c "$*"
}
G() { echo "/analysis/inventory/glue/$1"; }

# Elenco dei file del manifesto di un tipo (percorso, uno per riga, ordine del manifesto).
manifest_of() { awk -F'\t' -v t="$1" 'NR>1 && $2==t {print $1}' "$MANIFEST"; }

# inv_stage_procs DIR: copia le procedure in DIR/procs con il nome che mapa si aspetta e verifica che siano identiche agli originali.
# INV_FAULT (solo per le prove negative di check.sh) altera un byte di una copia prima della verifica.
inv_stage_procs() {
  local d="$1"
  mkdir -p "$d/procs"
  py "$d" "$(G stage_procs.py)" stage /work/procs
  [ -z "${INV_FAULT:-}" ] || py "$d" "$(G fault.py)" "$INV_FAULT" /work/procs
  py "$d" "$(G stage_procs.py)" verify /work/procs || fail "le copie delle procedure non sono identiche agli originali"
}

# inv_generate G: rigenera dal legacy tutti gli output in G (G/out = versionati, G/docs = per docs/legacy-map, G/tmp = scratch).
inv_generate() {
  local g="$1" f n key
  mkdir -p "$g/out" "$g/docs" "$g/tmp/procs" "$g/tmp/mapa" "$g/tmp/cmt" "$g/tmp/proleap"
  ensure_legacy_volume
  build_image "$IMG_PROLEAP" "$DOCKER_DIR/proleap"
  build_image "$IMG_CMT" "$DOCKER_DIR/cmt"
  build_image "$IMG_MAPA" "$DOCKER_DIR/mapa"

  inv_stage_procs "$g/tmp"

  # COPY con riga e REPLACING: ProLeap (programmi e copybook), in parallelo, un file per volta
  log "COPY: ProLeap su programmi e copybook"
  export LEGACY_VOL IMG_PROLEAP IMG_MAPA g
  { manifest_of cobol; manifest_of copybook; } > "$g/tmp/copy-files.txt"
  xargs -P "$INV_JOBS" -I{} bash "$INV_DIR/one.sh" proleap {} < "$g/tmp/copy-files.txt" || fail "ProLeap fallito"
  printf 'file\triga\tcopybook\tsostituzioni\n' > "$g/out/copy.tsv"
  while IFS= read -r f; do
    cat "$g/tmp/proleap/$(echo "$f" | tr '/' '_').tsv" | awk -F'\t' -v p="$f" 'BEGIN{OFS="\t"} NR>1 {print p,$1,$2,$3}'
  done < "$g/tmp/copy-files.txt" >> "$g/out/copy.tsv"

  # CALL statiche: nomi da cobol-migration-toolkit (una scansione per cartella di programmi), righe dal localizzatore
  log "CALL: cobol-migration-toolkit per cartella, poi localizzatore"
  for d in $(manifest_of cobol | sed 's#/[^/]*$##' | LC_ALL=C sort -u); do
    key="$(echo "$d" | tr '/' '_')"
    mkdir -p "$g/tmp/cmt/$key"
    local cpath=(--copybook-path "/legacy/app/cpy" --copybook-path "/legacy/app/cpy-bms")
    local mod="${d%/cbl}"
    [ "$mod" = "app" ] || cpath+=(--copybook-path "/legacy/$mod/cpy" --copybook-path "/legacy/$mod/cpy-bms")
    tool_run "$IMG_CMT" "$g/tmp/cmt/$key" -- scan "/legacy/$d" "${cpath[@]}" --format json --output /out > "$g/tmp/cmt/$key/stdout.txt" \
      || fail "cobol-migration-toolkit fallito su $d"
  done
  py "$g" "$(G normalize.py)" cmt /work/tmp/cmt /work/out || fail "normalizzazione di cmt fallita"
  py "$g" "$(G locate_calls.py)" /work/out /work/out || fail "localizzatore delle CALL fallito"

  # JCL: mapa un file per volta (livello A), poi schede (livello B e forme sorgente)
  log "JCL: mapa su ogni file jcl"
  manifest_of jcl > "$g/tmp/jcl-files.txt"
  xargs -P "$INV_JOBS" -I{} bash "$INV_DIR/one.sh" mapa {} < "$g/tmp/jcl-files.txt" || fail "mapa fallito"
  py "$g" "$(G normalize.py)" mapa /work/tmp/mapa /work/out || fail "normalizzazione di mapa fallita"
  py "$g" "$(G cards.py)" /work/out || fail "estrattore di schede fallito"
  py "$g" "$(G csd.py)" /work/out || fail "estrazione delle transazioni del CSD fallita"

  # conteggi indipendenti (servono a decidere il livello di ogni JCL) e grafo
  py "$g" "$(G counts.py)" /work/tmp/counts.json || fail "conteggi indipendenti falliti"
  py "$g" "$(G build.py)" /work/tmp/counts.json /work/out /work/docs || fail "costruzione del grafo fallita"
}
