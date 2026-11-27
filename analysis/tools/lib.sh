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

# --- Dichiarazione unica dei verdetti dovuti (verdetti.tsv): usata da run.sh (produzione) e da check.sh (controllo).
# Ogni riga: cartella, nome file, controllo (argomento di compare.py), strumento ('-' se il controllo non ne ha).
# Nota di robustezza: queste funzioni sono chiamate anche dentro 'if' e con '||', dove 'set -e' non agisce; per questo
# l'esito di ogni comando (sostituzioni di comando, pipeline, awk, find, sort) e' controllato esplicitamente e
# propagato con 'return 1'. Non si usano sostituzioni di processo.
VERDETTI="$TOOLS_DIR/verdetti.tsv"   # sempre il file del repository: non si eredita dall'ambiente (check.sh lo sostituisce solo per le prove negative)

# Cartella di out/ in cui un controllo scrive il proprio verdetto: dipende solo dal controllo e dallo strumento
# (e' la stessa regola con cui run.sh organizza i verdetti); stampa la cartella, errore se la coppia non esiste.
verdict_check_dir() { # verdict_check_dir CONTROLLO STRUMENTO('-' o vuoto = nessuno)
  local tool="${2:--}"
  case "$1:$tool" in
    scc:-|scc-split:-) echo scc ;;
    compile:-) echo gnucobol ;;
    layout:-) echo cb2xml ;;
    jcl:-) echo mapa ;;
    call:cmt|call:cobmix|call:proleap|copy:cmt|copy:cobmix|copy:proleap) echo "$tool" ;;
    *) return 1 ;;
  esac
}

# Tabella dichiarata e validata: "cartella/nome<TAB>controllo<TAB>strumento", ordinata, una riga per verdetto.
# Errore se una riga e' malformata, se cartella o nome non sono quelli che il controllo produce, se c'e' un duplicato.
verdict_table() {
  [ -f "$VERDETTI" ] || { echo "dichiarazione dei verdetti assente: $VERDETTI" >&2; return 1; }
  local rows d f c t extra want_dir want_file out="" sorted dups
  rows="$(awk '/^[ \t]*#/ || /^[ \t]*$/ { next } { print }' "$VERDETTI")" || return 1
  [ -n "$rows" ] || { echo "dichiarazione dei verdetti vuota: $VERDETTI" >&2; return 1; }
  while IFS=$'\t' read -r d f c t extra; do
    if [ -z "$d" ] || [ -z "$f" ] || [ -z "$c" ] || [ -z "$t" ] || [ -n "$extra" ]; then
      echo "riga malformata in verdetti.tsv (servono 4 colonne: cartella, nome, controllo, strumento): $d $f $c $t $extra" >&2; return 1
    fi
    want_dir="$(verdict_check_dir "$c" "$t")" || { echo "verdetti.tsv: controllo/strumento sconosciuti: $c $t" >&2; return 1; }
    [ "$d" = "$want_dir" ] || { echo "verdetti.tsv: il verdetto del controllo '$c' ($t) va nella cartella '$want_dir', non in '$d'" >&2; return 1; }
    case "$c" in scc-split) want_file="prova-fallita-ripartizione.txt" ;; *) want_file="verdetto-$c.txt" ;; esac
    [ "$f" = "$want_file" ] || { echo "verdetti.tsv: il controllo '$c' scrive '$want_file', non '$f'" >&2; return 1; }
    out="$out$d/$f"$'\t'"$c"$'\t'"$t"$'\n'
  done <<< "$rows"
  sorted="$(printf '%s' "$out" | LC_ALL=C sort)" || return 1
  dups="$(printf '%s\n' "$sorted" | cut -f1 | LC_ALL=C sort | uniq -d)" || return 1
  [ -z "$dups" ] || { echo "voce duplicata in verdetti.tsv: $dups" >&2; return 1; }
  printf '%s\n' "$sorted"
}

# Percorsi dichiarati (cartella/nome), uno per riga.
verdict_declared() {
  local tbl
  tbl="$(verdict_table)" || return 1
  printf '%s\n' "$tbl" | cut -f1
}

# Differenza tra due insiemi di righe: stampa "<ETICHETTA-A> riga" per quelle solo in A e "<ETICHETTA-B> riga" per quelle solo in B.
verdict_set_diff() { # verdict_set_diff INSIEME-A INSIEME-B ETICHETTA-A ETICHETTA-B
  A="$1" B="$2" LA="$3" LB="$4" awk 'BEGIN {
      n = split(ENVIRON["A"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") inA[a[i]] = 1
      m = split(ENVIRON["B"], b, "\n"); for (i = 1; i <= m; i++) if (b[i] != "") inB[b[i]] = 1
      for (k in inA) if (!(k in inB)) print ENVIRON["LA"] ": " k
      for (k in inB) if (!(k in inA)) print ENVIRON["LB"] ": " k }' | LC_ALL=C sort
}

# Confronta l'insieme esatto dei file di verdetto/prova presenti sotto DIR (a qualsiasi profondita', qualunque tipo
# di file tranne le cartelle) con quello dichiarato. Stampa su stderr ogni file mancante o non dovuto; ritorna 1 se differiscono
# o se un comando necessario al confronto fallisce.
verdict_set_check() {
  local dir="$1" decl present diff
  decl="$(verdict_declared)" || return 1
  [ -d "$dir" ] || { echo "cartella dei verdetti assente: $dir" >&2; return 1; }
  present="$(cd "$dir" && find . \( -name 'verdetto-*' -o -name 'prova-fallita-*' \) ! -type d | sed 's|^\./||' | LC_ALL=C sort)" \
    || { echo "elenco dei file di verdetto presenti non riuscito in $dir" >&2; return 1; }
  diff="$(verdict_set_diff "$decl" "$present" "verdetto dovuto mancante" "file di verdetto non dovuto")" || return 1
  if [ -n "$diff" ]; then printf '%s\n' "$diff" >&2; return 1; fi
}

# Registra un verdetto scritto nella corsa corrente (variabile di shell WRITTEN, righe "percorso<TAB>controllo<TAB>strumento").
verdict_record() { # verdict_record CARTELLA/NOME CONTROLLO [STRUMENTO]
  WRITTEN="${WRITTEN:-}$1"$'\t'"$2"$'\t'"${3:--}"$'\n'
}

# Azzera il registro delle scritture: run.sh lo chiama prima delle prove, cosi' un valore ereditato dall'ambiente non conta.
verdict_register_reset() { WRITTEN=""; }

# Verdetto calcolato: stampa il testo (intestazione + output del confronto, stesso formato di verdict_text) SOLO se il
# confronto si e' concluso: codice 0 con ultima riga "VERDETTO: pass", oppure codice 1 con "VERDETTO: fail". Qualsiasi
# altra cosa (docker che fallisce, eccezione dello script, risposta troncata) e' un errore operativo: ritorna 2 senza testo.
verdict_compute() { # verdict_compute CHECK [TOOL] [argomenti di compare.py, es. --out DIR]
  local check="$1" tool="${2:-}" body rc=0 last
  shift; [ $# -eq 0 ] || shift
  body="$(glue_run -- /analysis/tools/glue/compare.py $check $tool "$@" 2>&1)" || rc=$?
  last="$(printf '%s\n' "$body" | tail -n 1)" || return 2
  case "$rc:$last" in
    "0:VERDETTO: pass"|"1:VERDETTO: fail") ;;
    *) echo "confronto '$check $tool' non concluso (codice $rc, ultima riga '$last')" >&2; return 2 ;;
  esac
  printf 'controllo: %s %s\n%s\n' "$check" "$tool" "$body"
}

# Un file di verdetto e' valido solo se la prima riga e' l'intestazione "controllo: ..." e l'ultima e' una riga di esito.
verdict_file_valid() { # verdict_file_valid FILE
  local f="$1" first last
  [ -f "$f" ] || return 1
  first="$(head -n 1 "$f")" || return 1
  last="$(tail -n 1 "$f")" || return 1
  case "$first" in "controllo: "*) ;; *) return 1 ;; esac
  case "$last" in "VERDETTO: pass"|"VERDETTO: fail") ;; *) return 1 ;; esac
}

# Errore se CARTELLA/NOME non e' dichiarato (usato da run.sh prima di scrivere un verdetto).
verdict_require_declared() {
  local decl
  decl="$(verdict_declared)" || fail "dichiarazione dei verdetti non valida (analysis/tools/verdetti.tsv)"
  case $'\n'"$decl"$'\n' in *$'\n'"$1"$'\n'*) ;; *) fail "verdetto non dichiarato in analysis/tools/verdetti.tsv: $1" ;; esac
}

# L'insieme dei verdetti realmente scritti nella corsa corrente (WRITTEN, o l'argomento) deve coincidere con la
# dichiarazione: stessi percorsi, stesso controllo, stesso strumento. Un file preesistente non conta.
verdict_written_check() { # verdict_written_check [SCRITTI]
  local written="${1-${WRITTEN:-}}" tbl diff
  tbl="$(verdict_table)" || return 1
  diff="$(verdict_set_diff "$tbl" "$written" "verdetto dichiarato ma non scritto in questa corsa" "verdetto scritto ma non dichiarato")" || return 1
  if [ -n "$diff" ]; then printf '%s\n' "$diff" >&2; return 1; fi
}
