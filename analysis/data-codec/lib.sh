# Funzioni delle regole di codifica (issue #23), da includere dopo lib/common.sh e tools/lib.sh.
#
#   dcod_genera OUT [OPZIONI]   rigenera in OUT tutto cio' che l'analisi produce:
#       OUT/censimento.tsv, OUT/censimento-categorie.tsv   censimento delle rappresentazioni (dai contratti di #3)
#       OUT/pagina.tsv, OUT/pagina-esito.tsv               byte che distinguono 037 da 1047 nei file EBCDIC
#       OUT/sonde/                                         sonda CODECPRB compilata ed eseguita nell'ambiente
#                                                          dell'oracle: compilazione.log, rapporto.txt,
#                                                          ambiente.txt, osservazioni.tsv
#   OPZIONI (facoltativo) e' un file di opzioni di cobc alternativo a oracle/cobc.opts: serve solo alla prova
#   negativa della sonda compilata con un'opzione diversa, e passa per il modo `uno` di oracle/build/compile.sh
#   (variabile UNO_OPZIONI, prevista dall'oracle proprio per questo).

DCOD_DIR="$ANALYSIS_ROOT/data-codec"
DCOD_DOC="$REPO_ROOT/docs/legacy-map/data-contract/codifica.md"
DCOD_CONTRATTI="$REPO_ROOT/docs/legacy-map/data-contract/contratti"
ORACLE_DIR="$REPO_ROOT/oracle"
DCOD_LEGACY=/legvol   # percorso, nei container della colla, del volume del legacy sensibile alle maiuscole

# Esegue un comando nel container dell'oracle con le funzioni dell'oracle stesso (oracle/lib.sh, in sola
# lettura, in una sottoshell): stessa immagine, stesso volume del legacy, rete disattivata, utente dell'host,
# oracle/ montata in sola lettura su /oracle, stdin vuoto. Uso: oracle_do [opzioni docker...] -- comando...
oracle_do() {
  (
    export ORACLE_ROOT="$ORACLE_DIR" ORACLE_NAME="data-codec"
    # shellcheck disable=SC1091
    . "$ORACLE_DIR/lib.sh"
    orun "$@"
  )
}

dcod_censimento() {
  local out="$1"
  glue_run --rw "$out" --mount "$DCOD_CONTRATTI:/contratti:ro" -- /analysis/data-codec/glue/censimento.py /contratti /work \
    || fail "censimento delle rappresentazioni fallito"
}

dcod_pagina() {
  local out="$1"
  ensure_legacy_volume
  glue_run --rw "$out" --mount "$DCOD_CONTRATTI:/contratti:ro" --mount "$LEGACY_VOL:$DCOD_LEGACY:ro" -- \
    /analysis/data-codec/glue/pagina.py "$DCOD_LEGACY" /contratti /work || fail "analisi della pagina di codici fallita"
}

# dcod_sonde OUT [OPZIONI]: compila CODECPRB con oracle/build/compile.sh (modo uno) ed esegue con oracle/esegui.sh.
dcod_sonde() {
  local out="$1" opz="${2:-}" w
  # cartella di lavoro accanto a OUT (sempre una cartella temporanea del chiamante, che la rimuove)
  w="$out/.lavoro-sonde"
  rm -rf "$w" "$out/sonde" || fail "impossibile ripulire $w"
  mkdir -p "$w/build" "$w/run" "$out/sonde" || fail "cartelle di lavoro della sonda non create"
  glue_run --rw "$w" -- /analysis/data-codec/glue/sonda.py ingresso /analysis/data-codec/vettori/oracle-gnucobol.tsv /work/ingresso.dat \
    || fail "ingresso della sonda non scritto"
  local extra=()
  if [ -n "$opz" ]; then
    cp "$opz" "$w/cobc.opts" || fail "copia del file di opzioni alternativo fallita"
    extra=(-e UNO_OPZIONI=/w/cobc.opts)
  fi
  oracle_do -v "$w:/w" -v "$DCOD_DIR/sonde:/sonde:ro" ${extra[@]+"${extra[@]}"} -- \
    timeout -k 10 900 sh /oracle/build/compile.sh uno eseguibile /sonde/CODECPRB.cbl CODECPRB /w/build \
    > "$w/compile.out" 2>&1 || { cat "$w/compile.out" >&2; fail "compilazione della sonda CODECPRB fallita"; }
  [ -x "$w/build/bin/CODECPRB" ] || fail "compilazione della sonda: eseguibile assente"
  oracle_do -v "$w:/w" -v "$w/build/bin:/oracle-bin:ro" -- \
    timeout -k 10 180 sh /oracle/esegui.sh /w/run CODECPRB --dd DD_CODECIN=/w/ingresso.dat \
    > "$w/run.out" 2>&1 || { cat "$w/run.out" >&2; fail "esecuzione della sonda CODECPRB fallita"; }
  [ -f "$w/run/CODECPRB.txt" ] || fail "rapporto della sonda assente"
  cp "$w/build/log/CODECPRB.log" "$out/sonde/compilazione.log" || fail "log di compilazione della sonda assente"
  cp "$w/run/CODECPRB.txt" "$out/sonde/rapporto.txt" || fail "copia del rapporto della sonda fallita"
  cp "$w/run/CODECPRB.ambiente" "$out/sonde/ambiente.txt" || fail "ambiente della sonda non registrato"
  glue_run --rw "$out/sonde" -- /analysis/data-codec/glue/sonda.py leggi /work/rapporto.txt /work/osservazioni.tsv \
    || fail "lettura delle osservazioni della sonda fallita"
  rm -rf "$w" || fail "cartella di lavoro della sonda non rimossa"
}

dcod_genera() {
  local out="$1" opz="${2:-}"
  mkdir -p "$out" || fail "cartella $out non creata"
  dcod_censimento "$out"
  dcod_pagina "$out"
  dcod_sonde "$out" "$opz"
}
