#!/usr/bin/env bash
# File dei conti nell'oracle (issue #53): carica analysis/oracle-dati/out/ACCTFILE.rec (i 50 record del file che
# app/jcl/ACCTFILE.jcl carica nel KSDS, nel profilo dell'oracle) in un file indicizzato GnuCOBOL con organizzazione,
# chiave e lunghezza del SELECT/FD di CBACT01C, lo rilegge in ordine di chiave e lo verifica.
#   1. Come il JCL (DELETE prima di DEFINE): la cartella d'uscita si cancella e si ricrea; nessun file indicizzato di
#      una corsa precedente sopravvive. L'ingresso si copia prima in un file privato (nessun alias con le uscite).
#   2. carica.sh, nel container: IDXLOADF carica, IDXDUMP rilegge, la rilettura deve coincidere byte per byte con
#      l'ingresso; rapporto con record, byte, prima e ultima chiave, SHA-256 della rilettura.
#   3. Sull'host: rapporto, rapporti di esegui.sh dei due programmi e ambienti ricevuti identici agli attesi
#      versionati in oracle/dati/expected/.
#   4. Solo se tutto riesce il file indicizzato va al suo percorso stabile:
#        oracle/dati/out/ACCTFILE.dat         sull'host
#        /oracle/dati/out/ACCTFILE.dat        nel container dell'oracle (orun monta oracle/ su /oracle)
#      da usare con esegui.sh --dd DD_ACCTFILE=/oracle/dati/out/ACCTFILE.dat (#55). Se qualcosa fallisce non resta
#      alcun file indicizzato, ne' al percorso stabile ne' nella cartella di lavoro.
#   5. Verifica del percorso stabile: IDXDUMP rilegge oracle/dati/out/ACCTFILE.dat attraverso il montaggio in sola
#      lettura di /oracle, come lo vedra' #55, e la rilettura deve coincidere con l'ingresso.
# Solo per le prove negative del controllo (cartelle sotto oracle/):
#   DATI_INGRESSO   un altro file d'ingresso;   DATI_OUT_DIR   sposta l'uscita;
#   DATI_BIN_DIR    altri artefatti al posto di quelli della build (niente controllo dell'impronta);
#   DATI_ATTESI     un'altra cartella di attesi; DATI_TIMEOUT  limite di carica.sh nel container (default 300 s);
#   DATI_DOCKER_EXTRA  opzioni docker in piu' per il container di carica.sh (involucri nel PATH, registro).
. "$ORACLE_ROOT/lib.sh"

DIR="$ORACLE_ROOT/dati"
ingresso="${DATI_INGRESSO:-$REPO_ROOT/analysis/oracle-dati/out/ACCTFILE.rec}"
out="${DATI_OUT_DIR:-$DIR/out}"
bin="${DATI_BIN_DIR:-$BUILD_OUT/bin}"
exp="${DATI_ATTESI:-$DIR/expected}"
limite="${DATI_TIMEOUT:-300}"
case "$limite" in ''|*[!0-9]*) fail "DATI_TIMEOUT non valido: '$limite'" ;; esac
require_legacy
ensure_image
[ -n "${DATI_BIN_DIR:-}" ] || require_build
for p in IDXLOADF IDXDUMP; do [ -x "$bin/$p" ] || fail "$p assente in $(rel "$bin")"; done
[ -f "$ingresso" ] || fail "ingresso assente: $(rel "$ingresso"): eseguire './analysis/run.sh oracle-dati'"
[ -d "$exp" ] || fail "attesi assenti: $(rel "$exp")"

tmp="$(mktmp)" || exit 1
# Uscita con errore: nessun file indicizzato resta come risultato (ne' quello stabile ne' quello di lavoro).
fine() {
  local rc=$?
  rm -rf "$tmp" || log "temporanei non rimossi: $(rel "$tmp")"
  if [ "$rc" -ne 0 ]; then
    rm -rf "$out/lavoro" "$out/ACCTFILE.dat" "$out/ACCTFILE.rapporto" \
      || log "ATTENZIONE: uscite parziali non rimosse in $(rel "$out")"
    if [ -e "$out/ACCTFILE.dat" ] || [ -e "$out/lavoro" ]; then log "ATTENZIONE: uscite parziali ancora presenti in $(rel "$out")"; fi
  fi
  exit "$rc"
}
trap fine EXIT
mkdir -p "$tmp/in" || fail "cartella dell'ingresso privato non creata"
cp "$ingresso" "$tmp/in/ACCTFILE.rec" || fail "copia privata dell'ingresso fallita"
clean_dir "$out"

# 2. Caricamento e rilettura (un solo container; ogni programma ha il limite di tempo di esegui.sh). L'ingresso
# privato si monta su /in e l'uscita su /out: percorsi fissi, quindi ambienti ricevuti confrontabili con gli attesi.
# DATI_DOCKER_EXTRA: solo per le prove sugli esiti di carica.sh (involucri nel PATH del container).
rc=0
# shellcheck disable=SC2086
orun -v "$tmp/in:/in:ro" -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" \
  ${DATI_DOCKER_EXTRA:-} -- timeout -k 10 "$limite" sh /oracle/dati/carica.sh /in/ACCTFILE.rec /out \
  > "$tmp/carica.log" 2>&1 || rc=$?
mostra() { local f; for f in "$@"; do [ ! -f "$f" ] || { echo "--- $(rel "$f")"; indent "$f"; }; done >&2; }
case "$rc" in
  0) ;;
  3|4) indent "$tmp/carica.log" >&2; mostra "$out/carico/IDXLOADF.txt" "$out/rilettura/IDXDUMP.txt"
       if [ "$rc" -eq 3 ]; then fail "caricamento o rilettura non riusciti: $(sed -n '$p' "$tmp/carica.log")"; fi
       fail "rilettura diversa dall'ingresso: $(sed -n '$p' "$tmp/carica.log")" ;;
  124|137) indent "$tmp/carica.log" >&2; fail "carica.sh non e' terminato entro ${limite}s" ;;
  *) indent "$tmp/carica.log" >&2; fail "carica.sh fallito (uscita $rc)" ;;
esac

# 3. Confronto con gli attesi versionati: rapporto, rapporti di esegui.sh, ambienti ricevuti.
confronta() { # confronta ATTESO OSSERVATO NOME: 0 uguali; altrimenti fail con la differenza (diff: 0, 1, altro)
  local r=0
  [ -f "$1" ] || fail "$3: atteso assente ($(rel "$1"))"
  [ -f "$2" ] || fail "$3: osservato assente ($(rel "$2"))"
  diff -u "$1" "$2" > "$tmp/diff.txt" 2>&1 || r=$?
  case "$r" in
    0) ;;
    1) indent "$tmp/diff.txt" >&2; fail "$3 diverso dall'atteso" ;;
    *) indent "$tmp/diff.txt" >&2; fail "$3: confronto non eseguito (diff, codice $r)" ;;
  esac
}
confronta "$exp/ACCTFILE.rapporto" "$out/lavoro/ACCTFILE.rapporto" "ACCTFILE: rapporto"
confronta "$exp/IDXLOADF.txt" "$out/carico/IDXLOADF.txt" "IDXLOADF: rapporto di esegui.sh"
confronta "$exp/IDXDUMP.txt" "$out/rilettura/IDXDUMP.txt" "IDXDUMP: rapporto di esegui.sh"
confronta "$exp/IDXLOADF.ambiente" "$out/carico/IDXLOADF.ambiente" "IDXLOADF: ambiente ricevuto"
confronta "$exp/IDXDUMP.ambiente" "$out/rilettura/IDXDUMP.ambiente" "IDXDUMP: ambiente ricevuto"

# 4. Percorso stabile.
mv "$out/lavoro/ACCTFILE.dat" "$out/ACCTFILE.dat" || fail "file indicizzato non spostato al percorso stabile"
mv "$out/lavoro/ACCTFILE.rapporto" "$out/ACCTFILE.rapporto" || fail "rapporto non spostato"
mv "$out/lavoro/rilettura.bin" "$out/rilettura/ACCTFILE.bin" || fail "rilettura non spostata"
rm -rf "$out/lavoro" || fail "cartella di lavoro non rimossa"
[ ! -e "$out/lavoro" ] || fail "cartella di lavoro ancora presente"

# 5. Il file al percorso stabile si rilegge attraverso il montaggio in sola lettura di /oracle (come lo vedra' #55).
# Solo nell'esecuzione normale (l'uscita deve stare sotto oracle/ per essere vista da /oracle).
st_c="$(in_container "$out")" || fail "uscita fuori da oracle/"
mkdir -p "$tmp/stabile" || fail "cartella della rilettura dal percorso stabile non creata"
rc=0
orun -v "$tmp/stabile:/st" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- \
  timeout -k 10 "$limite" sh -c 'PATH=/usr/bin:/bin sh /oracle/esegui.sh /st IDXDUMP --parm ACCTFILE \
    --dd "DD_ACCTFILE=$1/ACCTFILE.dat" --dd DD_USCITA=/st/rilettura.bin' sh "$st_c" > "$tmp/stabile.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { indent "$tmp/stabile.log" >&2; fail "rilettura dal percorso stabile non eseguita (uscita $rc)"; }
c="$(sed -n '2p' "$tmp/stabile/IDXDUMP.txt")" || fail "rapporto della rilettura dal percorso stabile illeggibile"
[ "$c" = 0 ] || { indent "$tmp/stabile/IDXDUMP.txt" >&2; fail "rilettura dal percorso stabile: IDXDUMP uscito con $c"; }
r=0; cmp -s "$tmp/stabile/rilettura.bin" "$tmp/in/ACCTFILE.rec" || r=$?
case "$r" in
  0) ;;
  1) fail "rilettura dal percorso stabile diversa dall'ingresso" ;;
  *) fail "rilettura dal percorso stabile: confronto non eseguito (cmp, codice $r)" ;;
esac
log "ACCTFILE: $(sed -n '2p' "$out/ACCTFILE.rapporto"), $(sed -n '4p' "$out/ACCTFILE.rapporto"), $(sed -n '5p' "$out/ACCTFILE.rapporto"); file indicizzato in $(rel "$out")/ACCTFILE.dat (nel container $st_c/ACCTFILE.dat), riletto anche da li' in sola lettura"
