# Funzioni comuni agli script delle analisi (da includere con `. "$ANALYSIS_ROOT/lib/common.sh"`).
# Prerequisiti sull'host: bash, git, Docker. Tutto il resto gira in container.

set -euo pipefail

: "${ANALYSIS_ROOT:?ANALYSIS_ROOT non impostata: lanciare gli script tramite analysis/run.sh}"
: "${ANALYSIS_NAME:=?}"

REPO_ROOT="$(cd "$ANALYSIS_ROOT/.." && pwd)"
LEGACY="${LEGACY:-$REPO_ROOT/legacy/aws-mainframe-modernization-carddemo}"
export LEGACY

# Immagine di base Python per gli script di colla (versione e digest fissati).
GLUE_IMAGE="python:3.12-slim-trixie@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b"

log() { echo "[$ANALYSIS_NAME] $*" >&2; }
fail() { echo "[$ANALYSIS_NAME] ERRORE: $*" >&2; exit 1; }

# Elenco dei file tracciati nel submodule, separati da NUL (fonte di verita' del manifesto).
legacy_ls_files() { git -C "$LEGACY" ls-files -z; }

require_legacy() {
  [ -n "$(git -C "$LEGACY" ls-files 2>/dev/null | head -1)" ] \
    || fail "sorgente legacy assente o non inizializzato: eseguire 'git submodule update --init'"
}

# Costruisce un'immagine (cache dei layer di Docker; il tag porta la versione dello strumento).
build_image() {
  local tag="$1" dir="$2"
  docker build -q -t "$tag" "$dir" >/dev/null || fail "build dell'immagine $tag fallita"
}

# Esegue uno script Python di colla nel container di base, con la cartella analysis/ in sola lettura
# su /analysis, il legacy in sola lettura su /legacy e un'eventuale cartella scrivibile su /work.
# Uso: glue_run [--rw DIR] [--stdin] -- script.py args...   (percorsi come visti nel container)
glue_run() {
  local rw="" stdin=() extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --mount) extra+=(-v "$2"); shift 2 ;;   # --mount SORGENTE:DESTINAZIONE:ro
      --rw) rw="$2"; shift 2 ;;
      --stdin) stdin=(-i); shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  local mounts=(-v "$ANALYSIS_ROOT:/analysis:ro" -v "$LEGACY:/legacy:ro")
  [ -z "$rw" ] || mounts+=(-v "$rw:/work")
  [ ${#extra[@]} -eq 0 ] || mounts+=("${extra[@]}")
  docker run --rm ${stdin[@]+"${stdin[@]}"} --user "$(id -u):$(id -g)" -e HOME=/tmp -e PYTHONDONTWRITEBYTECODE=1 \
    "${mounts[@]}" "$GLUE_IMAGE" python -I "$@"
}
