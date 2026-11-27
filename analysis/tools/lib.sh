# Funzioni comuni agli script di analysis/tools (da includere dopo lib/common.sh).

TOOLS_DIR="$ANALYSIS_ROOT/tools"
OUT="${TOOLS_OUT:-$TOOLS_DIR/out}"   # TOOLS_OUT: cartella alternativa, usata da check.sh per rigenerare gli output
DOCKER_DIR="$TOOLS_DIR/docker"
MANIFEST="$ANALYSIS_ROOT/manifest/sources.tsv"

# Immagini (versione dello strumento nel tag; digest delle basi nei Dockerfile).
IMG_SCC="menb-analysis-scc:4.1.0"
IMG_COBC="menb-analysis-gnucobol:3.2"
IMG_CMT="menb-analysis-cmt:0.8.0"
IMG_COBMIX="menb-analysis-cobmix:0.1.2"
IMG_PROLEAP="menb-analysis-proleap:d1bfe75"
IMG_CB2XML="menb-analysis-cb2xml:1.01.08"
IMG_MAPA="menb-analysis-mapa:d05705a"

# Programmi COBOL di app/cbl/ presi dal manifesto (tipo cobol, percorso sotto app/cbl/), uno per riga.
app_cbl_programs() {
  [ -f "$MANIFEST" ] || fail "manifesto assente: eseguire prima './analysis/run.sh manifest'"
  awk -F'\t' 'NR>1 && $2=="cobol" && index($1,"app/cbl/")==1 {print $1}' "$MANIFEST"
}

# Il legacy viene copiato una volta in un volume Docker (file system del container, sensibile alle maiuscole)
# e gli strumenti lo vedono in sola lettura su /legacy. Motivo: su macOS i bind mount di Docker Desktop
# possono risolvere i nomi senza distinguere maiuscole (es. COPY CUSTREC trova CUSTREC.cpy come CUSTREC.CPY),
# e i risultati non sarebbero uguali a quelli di un host Linux. Il volume e' nominato con il commit del submodule.
LEGACY_VOL=""
ensure_legacy_volume() {
  [ -z "$LEGACY_VOL" ] || return 0
  local sha; sha="$(git -C "$LEGACY" rev-parse --short=12 HEAD)"
  LEGACY_VOL="menb-analysis-legacy-$sha"
  if ! docker run --rm -v "$LEGACY_VOL:/dst:ro" "$GLUE_IMAGE" test -f /dst/.menb-complete 2>/dev/null; then
    log "copia del legacy ($sha) nel volume $LEGACY_VOL"
    docker volume create "$LEGACY_VOL" > /dev/null
    docker run --rm -v "$LEGACY:/src:ro" -v "$LEGACY_VOL:/dst" "$GLUE_IMAGE" \
      sh -c 'cp -a /src/. /dst/ && touch /dst/.menb-complete' || fail "copia del legacy nel volume fallita"
  fi
}

# Esegue un container di strumento con il legacy in sola lettura e, se indicata, una cartella di output scrivibile.
# Uso: tool_run IMAGE OUTDIR_HOST [opzioni docker...] -- argomenti dello strumento
tool_run() {
  local image="$1" outdir="$2"; shift 2
  local extra=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do extra+=("$1"); shift; done
  [ $# -eq 0 ] || shift
  ensure_legacy_volume
  docker run --rm --name "menb-analysis-run-$$-$RANDOM" --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$LEGACY_VOL:/legacy:ro" -v "$outdir:/out" ${extra[@]+"${extra[@]}"} "$image" "$@"
}

# Testo di un verdetto: intestazione + output del confronto (stesso formato dei file verdetto-*.txt / prova-fallita-*.txt).
# Uso: verdict_text CHECK [TOOL] [argomenti di compare.py, es. --out DIR]   (il codice di uscita del confronto e' ignorato)
verdict_text() {
  local check="$1" tool="${2:-}"
  shift; [ $# -eq 0 ] || shift
  echo "controllo: $check ${tool}"
  glue_run -- /analysis/tools/glue/compare.py $check $tool "$@" 2>&1 || true
}

# Registra versione e comando eseguito (testo semplice, versionato) per uno strumento.
record() { # record TOOL FILE TEXT
  mkdir -p "$OUT/$1"
  printf '%s\n' "$3" > "$OUT/$1/$2"
}
