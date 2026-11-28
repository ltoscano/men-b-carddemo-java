#!/usr/bin/env bash
# File dei conti nell'oracle (issue #53): carica analysis/oracle-dati/out/ACCTFILE.rec (i 50 record del file che
# app/jcl/ACCTFILE.jcl carica nel KSDS, nel profilo dell'oracle) in un file indicizzato GnuCOBOL con organizzazione,
# chiave e lunghezza del SELECT/FD di CBACT01C, lo legge per due vie indipendenti e lo verifica.
#   0. PRIMO ATTO, prima di ogni altro controllo: il risultato corrente (il file al percorso stabile) si invalida. Ogni
#      uscita con errore, anche nella preparazione, lascia quindi il percorso stabile vuoto (trap installata subito).
#   1. Come il JCL (DELETE prima di DEFINE): la cartella d'uscita si cancella e si ricrea. L'ingresso si copia prima in
#      un file privato (nessun alias con le uscite).
#   2. carica.sh, nel container: IDXLOADF carica in dati/out/ACCTFILE.dat.verifica (non pubblicato); IDXLEGGI, il
#      lettore indipendente, lo legge in ordine di chiave e per chiave; IDXDUMP lo rilegge come seconda via; le letture
#      devono coincidere fra loro e con l'ingresso. Rapporto con record, byte, prima e ultima chiave, SHA-256.
#   3. Sull'host: rapporto, rapporti di esegui.sh dei tre programmi e ambienti ricevuti identici agli attesi
#      versionati in oracle/dati/expected/.
#   4. Ultima verifica, prima della pubblicazione: IDXLEGGI legge lo stesso file attraverso il montaggio in sola
#      lettura di /oracle, come lo vedra' #55, e la lettura deve coincidere con l'ingresso.
#   5. PUBBLICAZIONE, ultimo atto: lo stesso file gia' verificato (stesso inode) si rinomina al percorso stabile:
#        oracle/dati/out/ACCTFILE.dat         sull'host
#        /oracle/dati/out/ACCTFILE.dat        nel container dell'oracle (orun monta oracle/ su /oracle)
#      da usare con esegui.sh --dd DD_ACCTFILE=/oracle/dati/out/ACCTFILE.dat (#55). Prima della pubblicazione il file
#      non e' mai al percorso stabile; se qualcosa fallisce non resta alcun file indicizzato.
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
tmp=""
# Uscita: temporanei rimossi (un fallimento di rm e' un errore e cambia l'esito); con errore, nessun file indicizzato
# resta come risultato (ne' quello stabile ne' quello in verifica ne' la cartella di lavoro).
fine() {
  local rc=$?
  if [ -n "$tmp" ]; then
    rm -rf "$tmp" || { log "ERRORE: temporanei non rimossi: $(rel "$tmp")"; [ "$rc" -ne 0 ] || rc=1; }
  fi
  if [ "$rc" -ne 0 ]; then
    rm -rf "$out/lavoro" "$out/ACCTFILE.dat" "$out/ACCTFILE.dat.verifica" "$out/ACCTFILE.rapporto" \
      || log "ATTENZIONE: uscite parziali non rimosse in $(rel "$out")"
    if [ -e "$out/ACCTFILE.dat" ] || [ -e "$out/ACCTFILE.dat.verifica" ] || [ -e "$out/lavoro" ]; then
      log "ATTENZIONE: uscite parziali ancora presenti in $(rel "$out")"
    fi
  fi
  exit "$rc"
}
trap fine EXIT
# 0. Primo atto: il risultato corrente non vale piu' finche' questa corsa non lo ripubblica.
rm -f "$out/ACCTFILE.dat" "$out/ACCTFILE.dat.verifica" "$out/ACCTFILE.rapporto" || fail "risultato precedente non invalidato"
[ ! -e "$out/ACCTFILE.dat" ] || fail "risultato precedente ancora presente: $(rel "$out")/ACCTFILE.dat"

case "$limite" in ''|*[!0-9]*) fail "DATI_TIMEOUT non valido: '$limite'" ;; esac
require_legacy
ensure_image
[ -n "${DATI_BIN_DIR:-}" ] || require_build
for p in IDXLOADF IDXLEGGI IDXDUMP; do [ -x "$bin/$p" ] || fail "$p assente in $(rel "$bin")"; done
[ -f "$ingresso" ] || fail "ingresso assente: $(rel "$ingresso"): eseguire './analysis/run.sh oracle-dati'"
[ -d "$exp" ] || fail "attesi assenti: $(rel "$exp")"

tmp="$(mktmp)" || exit 1
mkdir -p "$tmp/in" || fail "cartella dell'ingresso privato non creata"
cp "$ingresso" "$tmp/in/ACCTFILE.rec" || fail "copia privata dell'ingresso fallita"
clean_dir "$out"

# 2. Caricamento e letture (un solo container; ogni programma ha il limite di tempo di esegui.sh). L'ingresso
# privato si monta su /in e l'uscita su /out: percorsi fissi, quindi ambienti ricevuti confrontabili con gli attesi.
rc=0
# shellcheck disable=SC2086
orun -v "$tmp/in:/in:ro" -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" \
  ${DATI_DOCKER_EXTRA:-} -- timeout -k 10 "$limite" sh /oracle/dati/carica.sh /in/ACCTFILE.rec /out \
  > "$tmp/carica.log" 2>&1 || rc=$?
mostra() { local f; for f in "$@"; do [ ! -f "$f" ] || { echo "--- $(rel "$f")"; indent "$f"; }; done >&2; }
case "$rc" in
  0) ;;
  3|4) indent "$tmp/carica.log" >&2
       mostra "$out/carico/IDXLOADF.txt" "$out/lettura/IDXLEGGI.txt" "$out/rilettura/IDXDUMP.txt"
       if [ "$rc" -eq 3 ]; then fail "caricamento o lettura non riusciti"; fi
       fail "lettura diversa dall'ingresso" ;;
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
confronta "$exp/IDXLEGGI.txt" "$out/lettura/IDXLEGGI.txt" "IDXLEGGI: rapporto di esegui.sh"
confronta "$exp/IDXDUMP.txt" "$out/rilettura/IDXDUMP.txt" "IDXDUMP: rapporto di esegui.sh"
confronta "$exp/IDXLOADF.ambiente" "$out/carico/IDXLOADF.ambiente" "IDXLOADF: ambiente ricevuto"
confronta "$exp/IDXLEGGI.ambiente" "$out/lettura/IDXLEGGI.ambiente" "IDXLEGGI: ambiente ricevuto"
confronta "$exp/IDXDUMP.ambiente" "$out/rilettura/IDXDUMP.ambiente" "IDXDUMP: ambiente ricevuto"

# 4. Ultima verifica: IDXLEGGI legge il file in verifica attraverso il montaggio in sola lettura di /oracle.
st_c="$(in_container "$out")" || fail "uscita fuori da oracle/"
mkdir -p "$tmp/sola-lettura" || fail "cartella della lettura in sola lettura non creata"
rc=0
orun -v "$tmp/sola-lettura:/sl" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- \
  timeout -k 10 "$limite" sh -c 'PATH=/usr/bin:/bin sh /oracle/esegui.sh /sl IDXLEGGI --parm ACCTFILE \
    --dd "DD_ACCTFILE=$1/ACCTFILE.dat.verifica" --dd DD_LETTURA=/sl/lettura.bin --dd DD_CHIAVI=/sl/chiavi.bin' \
  sh "$st_c" > "$tmp/sola-lettura.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { indent "$tmp/sola-lettura.log" >&2; fail "lettura in sola lettura non eseguita (uscita $rc)"; }
c="$(sed -n '2p' "$tmp/sola-lettura/IDXLEGGI.txt")" || fail "rapporto della lettura in sola lettura illeggibile"
[ "$c" = 0 ] || { indent "$tmp/sola-lettura/IDXLEGGI.txt" >&2; fail "lettura in sola lettura: IDXLEGGI uscito con $c"; }
r=0; cmp -s "$tmp/sola-lettura/lettura.bin" "$tmp/in/ACCTFILE.rec" || r=$?
case "$r" in
  0) ;;
  1) fail "lettura in sola lettura diversa dall'ingresso" ;;
  *) fail "lettura in sola lettura: confronto non eseguito (cmp, codice $r)" ;;
esac

# 5. Diagnostica al suo posto, temporanei rimossi, poi la pubblicazione come ultimo atto.
mv "$out/lavoro/ACCTFILE.rapporto" "$out/ACCTFILE.rapporto" || fail "rapporto non spostato"
mv "$out/lavoro/lettura.bin" "$out/lettura/ACCTFILE.bin" || fail "lettura non spostata"
mv "$out/lavoro/rilettura.bin" "$out/rilettura/ACCTFILE.bin" || fail "rilettura non spostata"
rm -rf "$out/lavoro" || fail "cartella di lavoro non rimossa"
[ ! -e "$out/lavoro" ] || fail "cartella di lavoro ancora presente"
log "ACCTFILE: $(sed -n '2p' "$out/ACCTFILE.rapporto"), $(sed -n '4p' "$out/ACCTFILE.rapporto"), $(sed -n '5p' "$out/ACCTFILE.rapporto"); letture IDXLEGGI e IDXDUMP identiche all'ingresso, letto anche in sola lettura; pubblico in $(rel "$out")/ACCTFILE.dat (nel container $st_c/ACCTFILE.dat)"
rm -rf "$tmp" || fail "temporanei non rimossi: $(rel "$tmp")"
tmp=""
mv "$out/ACCTFILE.dat.verifica" "$out/ACCTFILE.dat" || fail "file indicizzato non pubblicato al percorso stabile"
