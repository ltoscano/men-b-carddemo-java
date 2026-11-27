# Funzioni comuni agli script dei passi dell'oracle (da includere con `. "$ORACLE_ROOT/lib.sh"`).
# Prerequisiti sull'host: bash, git, Docker e utility POSIX. Tutto il resto gira nel container dell'oracle.

set -euo pipefail
export LC_ALL=C

: "${ORACLE_ROOT:?ORACLE_ROOT non impostata: lanciare gli script tramite oracle/run.sh}"
: "${ORACLE_NAME:=?}"

REPO_ROOT="$(cd "$ORACLE_ROOT/.." && pwd)"
LEGACY="$REPO_ROOT/legacy/aws-mainframe-modernization-carddemo"
# Output della build (artefatti). ORACLE_BUILD_OUT lo sposta: serve solo alle prove negative dei controlli.
BUILD_OUT="${ORACLE_BUILD_OUT:-$ORACLE_ROOT/build/out}"

# Tempo massimo, in secondi, di ogni comando eseguito nel container (applicato con `timeout` dentro il
# container: TERM allo scadere, KILL 10 secondi dopo). Un programma che non termina fa fallire il passo.
ORACLE_TIMEOUT_COMPILE="${ORACLE_TIMEOUT_COMPILE:-900}"
ORACLE_TIMEOUT_RUN="${ORACLE_TIMEOUT_RUN:-60}"

log() { echo "[$ORACLE_NAME] $*" >&2; }
fail() { echo "[$ORACLE_NAME] ERRORE: $*" >&2; exit 1; }

# Percorso relativo al repository, per i messaggi (niente percorsi assoluti della macchina nei log).
rel() { case "$1" in "$REPO_ROOT"/*) echo "${1#"$REPO_ROOT"/}" ;; *) echo "$1" ;; esac; }
# Stampa un file (per esempio l'output di diff) rientrato e con i percorsi resi relativi al repository.
indent() { sed -e "s#$REPO_ROOT/##g" -e 's/^/    /' "$1"; }

# --- prove negative --------------------------------------------------------------------------------

# Altera un file con un'espressione sed e verifica che l'alterazione sia avvenuta davvero:
# una mutazione che non cambia nulla renderebbe la prova negativa vuota.
mutate() { # mutate FILE ESPRESSIONE-SED
  local f="$1" expr="$2"
  [ -f "$f" ] || fail "mutate: file assente: $(rel "$f")"
  sed -e "$expr" "$f" > "$f.mut" || fail "mutate: sed fallito su $(rel "$f")"
  if cmp -s "$f" "$f.mut"; then rm -f "$f.mut"; fail "mutate: l'espressione '$expr' non altera $(rel "$f")"; fi
  mv "$f.mut" "$f" || fail "mutate: impossibile sostituire $(rel "$f")"
}

# Esegue un comando che DEVE fallire, e per il motivo atteso (sottostringa nel suo output).
# Uso: expect_fail NOME SOTTOSTRINGA comando argomenti...
expect_fail() {
  local name="$1" needle="$2" outf rc
  shift 2
  outf="$(mktemp "$ORACLE_ROOT/.work/neg.XXXXXX")"
  set +e; "$@" > "$outf" 2>&1; rc=$?; set -e
  if [ "$rc" -eq 0 ]; then
    sed 's/^/      | /' "$outf" >&2; rm -f "$outf"
    fail "PROVA NEGATIVA FALLITA ($name): il controllo non si e' accorto dell'alterazione (codice 0)"
  fi
  if ! grep -qF -- "$needle" "$outf"; then
    sed 's/^/      | /' "$outf" >&2; rm -f "$outf"
    fail "prova negativa ($name): il controllo e' fallito (codice $rc) ma non per il motivo atteso ('$needle')"
  fi
  rm -f "$outf"
  log "   prova negativa ok: $name (codice $rc, motivo: '$needle')"
}

# Cartella temporanea dentro il repository (oracle/.work/, ignorata da git), rimossa dal chiamante.
mktmp() {
  mkdir -p "$ORACLE_ROOT/.work"
  [ -f "$ORACLE_ROOT/.work/.gitignore" ] || printf '*\n' > "$ORACLE_ROOT/.work/.gitignore"
  mktemp -d "$ORACLE_ROOT/.work/t.XXXXXX"
}

# Cancella una cartella e verifica che non esista piu': un residuo di una corsa precedente non deve
# poter essere scambiato per un risultato attuale.
clean_dir() {
  rm -rf "$1" || fail "impossibile cancellare $1"
  [ ! -e "$1" ] || fail "$1 esiste ancora dopo la cancellazione"
  mkdir -p "$1" || fail "impossibile creare $1"
}

# --- sorgente legacy -------------------------------------------------------------------------------

legacy_commit() { git -C "$LEGACY" rev-parse HEAD; }

# Il legacy deve esserci e non essere modificato (invariante della issue: nessuna modifica sotto legacy/).
require_legacy() {
  [ -n "$(git -C "$LEGACY" ls-files 2>/dev/null | head -1)" ] \
    || fail "sorgente legacy assente o non inizializzato: eseguire 'git submodule update --init'"
  local dirty
  dirty="$(git -C "$LEGACY" status --porcelain)" || fail "git status sul legacy fallito"
  [ -z "$dirty" ] || fail "il legacy ha modifiche locali (non ammesse): $dirty"
}

# --- immagine --------------------------------------------------------------------------------------

# Il tag contiene l'hash del Dockerfile: un Dockerfile diverso produce un'immagine con un altro nome.
image_tag() { echo "menb-oracle-gnucobol:3.2-$(git hash-object "$ORACLE_ROOT/Dockerfile" | cut -c1-12)"; }

IMAGE=""
ensure_image() {
  [ -z "$IMAGE" ] || return 0
  IMAGE="$(image_tag)"
  # Nessun contesto di build: il Dockerfile non copia file.
  docker build -q -t "$IMAGE" - < "$ORACLE_ROOT/Dockerfile" > /dev/null || fail "build dell'immagine $IMAGE fallita"
}

# Identita' del contenuto dell'immagine: i digest dei suoi strati. L'Id dell'immagine non serve, perche'
# con lo store di containerd di Docker cambia a ogni `docker build` anche quando gli strati sono in cache.
image_id() { docker image inspect -f '{{json .RootFS.Layers}}' "$IMAGE"; }

# --- volume del legacy -----------------------------------------------------------------------------
# Il legacy si legge da un volume Docker (file system sensibile alle maiuscole, come un host Linux):
# su macOS un bind mount puo' risolvere COPY CUSTREC su CUSTREC.CPY. Il volume e' proprio dell'oracle
# (menb-oracle-legacy-<commit>), copiato byte per byte dal submodule e verificato con SHA-256 di ogni file.

LEGACY_VOL=""
ensure_legacy_volume() {
  [ -z "$LEGACY_VOL" ] || return 0
  ensure_image
  LEGACY_VOL="menb-oracle-legacy-$(legacy_commit | cut -c1-12)"
  if ! docker run --rm --network none -v "$LEGACY_VOL:/dst:ro" "$IMAGE" \
        timeout 60 test -f /dst/.menb-complete 2>/dev/null; then
    log "copia del legacy nel volume $LEGACY_VOL"
    docker volume create "$LEGACY_VOL" > /dev/null || fail "creazione del volume $LEGACY_VOL fallita"
    docker run --rm --network none --user 0:0 -v "$LEGACY:/src:ro" -v "$LEGACY_VOL:/dst" "$IMAGE" \
      timeout -k 10 600 sh -c '
        set -eu
        find /dst -mindepth 1 -delete
        cp -a /src/. /dst/
        rm -rf /dst/.git
        (cd /src && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum) > /tmp/src.sha
        (cd /dst && find . -type f -print0 | sort -z | xargs -0 sha256sum) > /tmp/dst.sha
        cmp /tmp/src.sha /tmp/dst.sha
        cp /tmp/src.sha /dst/.menb-sha256
        touch /dst/.menb-complete' || fail "copia del legacy nel volume $LEGACY_VOL fallita"
  fi
}

# Verifica che il volume coincida ancora, file per file, con il submodule (SHA-256 di ogni file).
verify_legacy_volume() {
  ensure_legacy_volume
  docker run --rm --network none -v "$LEGACY:/src:ro" -v "$LEGACY_VOL:/dst:ro" "$IMAGE" \
    timeout -k 10 300 sh -c '
      set -eu
      (cd /src && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum) > /tmp/src.sha
      (cd /dst && find . -type f ! -name .menb-complete ! -name .menb-sha256 -print0 | sort -z | xargs -0 sha256sum) > /tmp/dst.sha
      cmp -s /tmp/src.sha /tmp/dst.sha' \
    || fail "il volume $LEGACY_VOL non coincide con il submodule legacy: rimuoverlo con 'docker volume rm $LEGACY_VOL' e rieseguire"
}

# --- esecuzione nel container ----------------------------------------------------------------------

# Esegue un comando nel container dell'oracle: rete disattivata, utente dell'host, legacy in sola lettura
# su /legacy, cartella oracle/ in sola lettura su /oracle, stdin vuoto.
# Uso: orun [opzioni docker...] -- comando argomenti...
orun() {
  local extra=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do extra+=("$1"); shift; done
  [ $# -gt 0 ] || fail "orun: manca il comando"
  shift
  ensure_legacy_volume
  docker run --rm --network none --name "menb-oracle-run-$$-$RANDOM" \
    --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$LEGACY_VOL:/legacy:ro" -v "$ORACLE_ROOT:/oracle:ro" \
    ${extra[@]+"${extra[@]}"} "$IMAGE" "$@" < /dev/null
}

# Percorso, visto dal container, di un file o cartella sotto oracle/ (montata su /oracle).
in_container() {
  case "$1" in
    "$ORACLE_ROOT"/*) echo "/oracle/${1#"$ORACLE_ROOT"/}" ;;
    *) fail "in_container: $1 non e' sotto $ORACLE_ROOT" ;;
  esac
}

# --- impronta della build --------------------------------------------------------------------------
# build/out/IMPRONTA ha due righe:
#   input <hash>      di tutto cio' che determina gli artefatti: sorgenti dell'oracle, opzioni, elenco,
#                     strati dell'immagine, commit del legacy;
#   artefatti <hash>  dell'elenco degli artefatti in bin/ con l'hash del contenuto di ciascuno.
# La build la scrive come ultimo atto, solo se tutto e' riuscito; i passi che usano gli artefatti la
# ricalcolano e rifiutano una build assente, interrotta, vecchia o con artefatti cambiati dopo la build.
build_inputs() {
  printf '%s\n' "$ORACLE_ROOT/Dockerfile" "$ORACLE_ROOT/cobc.opts" "$ORACLE_ROOT/programs.tsv" \
    "$ORACLE_ROOT/launcher/avvia.c" "$ORACLE_ROOT/build/compile.sh" "$ORACLE_ROOT/ambiente.sh"
  ls "$ORACLE_ROOT"/stubs/*.cbl "$ORACLE_ROOT"/tests/*.cbl
}

fingerprint() {
  ensure_image
  {
    build_inputs | while IFS= read -r f; do
      printf '%s %s\n' "$(git hash-object "$f")" "${f#"$ORACLE_ROOT"/}"
    done
    echo "immagine $(image_id)"
    echo "legacy $(legacy_commit)"
    # Contenuto della configurazione di compilatore e runtime dell'immagine (file .conf, .words, runtime.cfg).
    config_hash
  } | git hash-object --stdin
}

# SHA-256 di ogni file della cartella di configurazione di GnuCOBOL nell'immagine.
config_hash() {
  orun -- timeout 60 sh -c 'cd /usr/share/gnucobol/config && LC_ALL=C ls -A | while read -r f; do sha256sum "$f"; done' \
    || fail "lettura della configurazione dell'immagine fallita"
}

# config_alternativa CARTELLA: copia della configurazione dell'immagine con perform-osvs: no aggiunto a
# ibm.conf (la mutazione del Validatore, giro 2 della PR #29). Solo per le prove negative.
config_alternativa() {
  mkdir -p "$1"
  orun -v "$1:/alt" -- timeout 60 sh -c 'cp -R /usr/share/gnucobol/config/. /alt/ && echo "perform-osvs: no" >> /alt/ibm.conf' \
    || fail "creazione della configurazione alternativa fallita"
}

artifacts_hash() { # artifacts_hash CARTELLA-DELLA-BUILD
  [ -d "$1/bin" ] || { echo "nessun-artefatto"; return 0; }
  (cd "$1/bin" && for f in $(ls -A | sort); do printf '%s %s\n' "$(git hash-object "$f")" "$f"; done) \
    | git hash-object --stdin
}

build_stamp() { # build_stamp CARTELLA-DELLA-BUILD: il contenuto atteso di IMPRONTA
  local fp ah
  fp="$(fingerprint)" && ah="$(artifacts_hash "$1")" || return 1
  printf 'input %s\nartefatti %s\n' "$fp" "$ah"
}

# Stampa il difetto dell'impronta di una build (nulla se e' valida); ritorna 1 se c'e' un difetto.
stamp_problem() { # stamp_problem CARTELLA-DELLA-BUILD
  local want have
  [ -f "$1/IMPRONTA" ] || { echo "build assente o incompleta (nessuna IMPRONTA)"; return 1; }
  want="$(build_stamp "$1")" || { echo "calcolo dell'impronta fallito"; return 1; }
  have="$(cat "$1/IMPRONTA")"
  [ "$(echo "$have" | sed -n 1p)" = "$(echo "$want" | sed -n 1p)" ] \
    || { echo "build non aggiornata: gli input sono cambiati dopo la build"; return 1; }
  [ "$(echo "$have" | sed -n 2p)" = "$(echo "$want" | sed -n 2p)" ] \
    || { echo "artefatti della build cambiati, aggiunti o tolti dopo la build"; return 1; }
  [ "$have" = "$want" ] || { echo "impronta malformata"; return 1; }
}

require_build() {
  local p
  p="$(stamp_problem "$BUILD_OUT")" || fail "$p: eseguire './oracle/run.sh build'"
}

