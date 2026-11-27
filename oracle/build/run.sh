#!/usr/bin/env bash
# Build dell'oracle: immagine GnuCOBOL, volume del legacy, compilazione degli 11 programmi (elenco in
# oracle/programs.tsv), dello stub CEE3ABD, dei segnaposto e dei programmi di prova.
# Output (ignorato da git) in oracle/build/out/:
#   bin/              eseguibili e moduli
#   log/<NOME>.log    comandi di cobc e diagnostica di ogni compilazione
#   compilazione.tsv  esito, avvertimenti ed errori per programma
#   opzioni.txt       opzioni di cobc effettivamente usate
#   ambiente.txt      versioni, gestore dei file indicizzati, configurazione di runtime
#   IMPRONTA          impronta degli input e degli artefatti (lib.sh); scritta per ultima, solo se tutto e' riuscito
# Solo per le prove negative dei controlli: ORACLE_BUILD_OUT sposta l'output (vedi lib.sh) e
# BUILD_ELENCO sostituisce l'elenco dei programmi; entrambi devono stare sotto oracle/.
. "$ORACLE_ROOT/lib.sh"

out="$BUILD_OUT"
elenco="${BUILD_ELENCO:-$ORACLE_ROOT/programs.tsv}"
require_legacy
ensure_image
verify_legacy_volume
log "immagine $IMAGE, volume $LEGACY_VOL"

clean_dir "$out"
# Percorso dell'elenco nel container calcolato prima, con l'esito controllato (giro 1 della PR #49: dentro
# gli argomenti di orun un in_container fallito non fermava la build).
elenco_c="$(in_container "$elenco")" || fail "percorso dell'elenco nel container non calcolabile"
orun -v "$out:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
  sh /oracle/build/compile.sh tutto "$elenco_c" /out \
  || fail "compilazione fallita (dettagli in $(rel "$out")/log/)"
# Numero di programmi compilati, letto prima dell'impronta con l'esito controllato.
compilati="$(awk -F'\t' 'NR>1 {n++} END {print n+0}' "$out/compilazione.tsv")" \
  || fail "lettura di $(rel "$out")/compilazione.tsv fallita (awk)"

# Ultimo atto: l'impronta. Senza di essa i passi successivi rifiutano gli artefatti. Una build con un
# elenco sostituito (BUILD_ELENCO) non e' la build dell'oracle e non riceve l'impronta.
if [ -z "${BUILD_ELENCO:-}" ]; then
  stamp="$(build_stamp "$out")" || fail "calcolo dell'impronta fallito"
  printf '%s\n' "$stamp" > "$out/IMPRONTA" || fail "scrittura dell'impronta fallita"
fi
log "compilati: $compilati programmi (dettagli in $(rel "$out")/compilazione.tsv)"
