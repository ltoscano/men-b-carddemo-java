# Funzioni dell'analisi "inventory-cics" (da includere dopo lib/common.sh e tools/lib.sh).
CICS_DIR="$ANALYSIS_ROOT/inventory-cics"
DOCS_DIR="$REPO_ROOT/docs/legacy-map"
IMG_CICS="menb-inventory-cics-proleap:d1bfe75"
IMG_JSONSCHEMA="menb-inventory-jsonschema:4.23.0"   # immagine dell'issue #2 (analysis/inventory/docker/jsonschema), solo usata
T_BUILD=1200   # limite in secondi per la costruzione di un'immagine
T_RUN=600      # limite in secondi per un container

# with_timeout SECONDI [--container NOME] comando...: esegue il comando con un limite di tempo; allo scadere lo termina
# (e ferma il container NOME, se indicato), scrive l'errore e ritorna 124. Altrimenti ritorna il codice del comando.
with_timeout() {
  local secs="$1"; shift
  local cname=""
  if [ "${1:-}" = "--container" ]; then cname="$2"; shift 2; fi
  local flag rc=0 pid wd
  flag="$(mktemp "$ANALYSIS_ROOT/.work/to.XXXXXX")" || return 1
  rm -f "$flag"
  "$@" &
  pid=$!
  ( trap 'kill "$sp" 2>/dev/null; exit 0' TERM
    sleep "$secs" & sp=$!
    wait "$sp"
    : > "$flag"
    [ -z "$cname" ] || docker kill "$cname" > /dev/null 2>&1
    kill "$pid" 2> /dev/null
    exit 0 ) &
  wd=$!
  wait "$pid" || rc=$?
  kill "$wd" 2> /dev/null || true
  wait "$wd" 2> /dev/null || true
  if [ -e "$flag" ]; then
    rm -f "$flag"
    echo "[$ANALYSIS_NAME] ERRORE: limite di ${secs}s superato: $*" >&2
    return 124
  fi
  return "$rc"
}

# crun SECONDI argomenti-di-docker-run...: docker run --rm con nome proprio e limite di tempo.
crun() {
  local secs="$1"; shift
  local name="menb-inventory-cics-$$-$RANDOM"
  with_timeout "$secs" --container "$name" docker run --rm --name "$name" "$@"
}

cics_build_images() {
  # l'immagine condivisa di ProLeap (#1) si costruisce dalla cache con il suo Dockerfile, senza modifiche; poi la nostra
  with_timeout "$T_BUILD" docker build -q -t "$IMG_PROLEAP" "$DOCKER_DIR/proleap" > /dev/null || fail "build dell'immagine $IMG_PROLEAP fallita"
  with_timeout "$T_BUILD" docker build -q -t "$IMG_CICS" "$CICS_DIR/docker/proleap-cics" > /dev/null || fail "build dell'immagine $IMG_CICS fallita"
}

# py RW_DIR [VAR=VALORE ...] [--mount SORGENTE:DESTINAZIONE:ro ...] -- script.py args...: colla Python nel container di base;
# /analysis e /docs in sola lettura, il legacy (volume sensibile alle maiuscole) in sola lettura su /legacy, RW_DIR
# scrivibile su /work. psh: stessi argomenti, ma esegue un comando di shell (sh -c "...").
_cont() {
  local how="$1" rw="$2"; shift 2
  local opts=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    if [ "$1" = "--mount" ]; then opts+=(-v "$2"); shift 2; else opts+=(-e "$1"); shift; fi
  done
  [ $# -eq 0 ] || shift
  local cmd=(python -I "$@")
  [ "$how" = py ] || cmd=(sh -c "$*")
  crun "$T_RUN" --user "$(id -u):$(id -g)" -e HOME=/tmp -e PYTHONDONTWRITEBYTECODE=1 ${opts[@]+"${opts[@]}"} \
    -v "$ANALYSIS_ROOT:/analysis:ro" -v "$DOCS_DIR:/docs:ro" -v "$LEGACY_VOL:/legacy:ro" -v "$rw:/work" "$GLUE_IMAGE" "${cmd[@]}"
}
py() { _cont py "$@"; }
psh() { _cont sh "$@"; }
G() { echo "/analysis/inventory-cics/glue/$1"; }
FIXENV=(CICS_LEGACY=/analysis/inventory-cics/fixtures/legacy CICS_MANIFEST=/analysis/inventory-cics/fixtures/sources.tsv CICS_BASE=/analysis/inventory-cics/fixtures/graph.json)

manifest_of() { awk -F'\t' -v t="$1" 'NR>1 && $2==t {print $1}' "$MANIFEST"; }

# lister SORGENTE(volume o cartella) RW_DIR ELENCO(in RW_DIR) RISPOSTE(in RW_DIR): esegue CicsLister su tutti i file dell'elenco.
lister() {
  local src="$1" rw="$2" list="$3" resp="$4"
  rm -rf "${rw:?}/$resp" && mkdir -p "$rw/$resp"
  crun "$T_RUN" --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$src:/legacy:ro" -v "$rw:/out" "$IMG_CICS" \
    /legacy "/out/$list" "/out/$resp" > "$rw/$resp.stdout"
}

# cics_generate G [fixture]: rigenera in G/out (versionati in analysis/inventory-cics/out) e G/docs (graph-cics.json,
# inventario-cics.md), dal legacy (default) o dai file di prova. G/tmp contiene le risposte grezze dello strumento.
cics_generate() {
  local g="$1" mode="${2:-legacy}" src envs=()
  mkdir -p "$g/out" "$g/docs" "$g/tmp"
  ensure_legacy_volume
  cics_build_images
  if [ "$mode" = fixture ]; then
    src="$CICS_DIR/fixtures/legacy"
    awk -F'\t' 'NR>1 && ($2=="cobol" || $2=="copybook") {print $1}' "$CICS_DIR/fixtures/sources.tsv" > "$g/tmp/files.txt"
    envs=("${FIXENV[@]}")
  else
    src="$LEGACY_VOL"
    { manifest_of cobol; manifest_of copybook; } > "$g/tmp/files.txt"
  fi
  [ -s "$g/tmp/files.txt" ] || fail "elenco dei sorgenti vuoto"
  log "EXEC CICS: ProLeap (CicsLister) su $(wc -l < "$g/tmp/files.txt" | tr -d ' ') file ($mode)"
  lister "$src" "$g/tmp" files.txt resp || fail "CicsLister fallito"
  # prova sul formato fisso, citata in inventario-cics.md: il file di prova FIXCICS.cbl
  echo "app/cbl/FIXCICS.cbl" > "$g/tmp/proof.txt"
  lister "$CICS_DIR/fixtures/legacy" "$g/tmp" proof.txt proof || fail "CicsLister fallito sul file di prova"
  crun "$T_RUN" --user "$(id -u):$(id -g)" -e HOME=/tmp "$IMG_CICS" --regole > "$g/tmp/regole.txt" || fail "CicsLister --regole fallito"
  printf 'regola\texecCicsStatement\ntoken\tEXEC\tpresente\ntoken\tCICS\tpresente\ntoken\tEND_EXEC\tpresente\n' \
    | cmp -s - "$g/tmp/regole.txt" || fail "risposta di 'CicsLister --regole' inattesa: ProLeap non espone piu' la regola execCicsStatement"
  py "$g" "${FIXENV[@]}" -- "$(G extract.py)" /work/tmp/proof.txt /work/tmp/proof /work/tmp/proof.stdout /work/tmp/proof-blocchi.tsv /work/tmp/proof-diag.tsv \
    || fail "risposta di CicsLister sul file di prova non valida"
  py "$g" ${envs[@]+"${envs[@]}"} -- "$(G extract.py)" /work/tmp/files.txt /work/tmp/resp /work/tmp/resp.stdout /work/out/blocchi.tsv /work/tmp/diagnostica.tsv \
    || fail "normalizzazione delle risposte di ProLeap fallita (risposta mancante, vuota o non riconoscibile)"
  py "$g" ${envs[@]+"${envs[@]}"} -- "$(G build.py)" /work/out/blocchi.tsv /work/tmp/regole.txt /work/tmp/proof/app_cbl_FIXCICS.cbl.tsv /work/tmp/diagnostica.tsv /work/docs \
    || fail "costruzione di graph-cics.json fallita"
}
