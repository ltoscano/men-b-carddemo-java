#!/usr/bin/env bash
# Golden del job READACCT (issue #55): CBACT01C eseguito nell'oracle su tre scenari, output di riferimento verificato.
#   0. PRIMO ATTO, prima di ogni altro controllo: il risultato corrente (oracle/golden/readacct/generati e
#      docs/legacy-map/golden-readacct.md) si invalida. Qualunque errore, anche nella preparazione, lascia il risultato
#      assente (git lo mostra come cancellato; i versionati si ripristinano con git): nessun golden vecchio resta al suo
#      posto come se fosse attuale.
#   1. Precondizioni: legacy, immagine, build (impronta), programmi, file indicizzato del passo dati, ingresso, tabelle.
#   2. genera.sh, in un solo container: ingressi derivati, CBACT01C sui tre scenari, proprieta', raccolta, riferimenti,
#      controlli 2, 3, 4, coerenza, 5 e 6, documento. Tutto in una cartella temporanea nuova (oracle/.work/).
#   3. PUBBLICAZIONE, ultimo atto: la cartella generata (verificata) si rinomina in readacct/generati, il documento in
#      docs/legacy-map/golden-readacct.md.
# Il file indicizzato dello scenario esempio e' quello pubblicato dal passo dati (oracle/dati/out/ACCTFILE.dat); nel
# container e' montato in sola lettura su /acct/ACCTFILE.dat (percorso fisso: l'ambiente registrato non dipende dalla
# cartella), e scenario.sh lo rilegge con IDXLEGGI e pretende che coincida con l'ingresso prima di usarlo.
# Solo per le prove negative del controllo:
#   GOLDEN_OUT_DIR    sposta la cartella generata;   GOLDEN_DOC     sposta il documento;
#   GOLDEN_ACCTFILE   un altro file indicizzato;     GOLDEN_INGRESSO  un altro ingresso dello scenario esempio;
#   GOLDEN_BIN_DIR    altri artefatti (niente impronta); GOLDEN_TABELLE  un'altra cartella di tabelle (sotto oracle/);
#   GOLDEN_TIMEOUT    limite di genera.sh (default 900 s); GOLDEN_DOCKER_EXTRA  opzioni docker in piu'.
. "$ORACLE_ROOT/lib.sh"

DIR="$ORACLE_ROOT/golden"
out="${GOLDEN_OUT_DIR:-$DIR/readacct/generati}"
doc="${GOLDEN_DOC:-$REPO_ROOT/docs/legacy-map/golden-readacct.md}"
acct="${GOLDEN_ACCTFILE:-$ORACLE_ROOT/dati/out/ACCTFILE.dat}"
rec="${GOLDEN_INGRESSO:-$REPO_ROOT/analysis/oracle-dati/out/ACCTFILE.rec}"
bin="${GOLDEN_BIN_DIR:-$BUILD_OUT/bin}"
tab="${GOLDEN_TABELLE:-$DIR/readacct}"
limite="${GOLDEN_TIMEOUT:-900}"
tmp=""
fine() {
  local rc=$?
  if [ -n "$tmp" ]; then rm -rf "$tmp" || { log "ERRORE: temporanei non rimossi: $(rel "$tmp")"; [ "$rc" -ne 0 ] || rc=1; }; fi
  if [ "$rc" -ne 0 ]; then
    rm -rf "$out" "$doc" || log "ATTENZIONE: risultato parziale non rimosso"
    if [ -e "$out" ] || [ -e "$doc" ]; then log "ATTENZIONE: risultato ancora presente dopo un errore"; fi
  fi
  exit "$rc"
}
trap fine EXIT
# 0. Primo atto.
rm -rf "$out" "$doc" || fail "risultato precedente non invalidato"
[ ! -e "$out" ] && [ ! -e "$doc" ] || fail "risultato precedente ancora presente"

# 1. Precondizioni.
case "$limite" in ''|*[!0-9]*) fail "GOLDEN_TIMEOUT non valido: '$limite'" ;; esac
require_legacy
ensure_image
[ -n "${GOLDEN_BIN_DIR:-}" ] || require_build
for p in CBACT01C IDXLOADF IDXLEGGI IDXDUMP COBDATFT.so CEE3ABD.so; do [ -e "$bin/$p" ] || fail "$p assente in $(rel "$bin")"; done
[ -f "$acct" ] || fail "file indicizzato assente: $(rel "$acct"): eseguire './oracle/run.sh dati'"
[ -f "$rec" ] || fail "ingresso assente: $(rel "$rec"): eseguire './analysis/run.sh oracle-dati'"
[ -d "$tab" ] || fail "tabelle assenti: $(rel "$tab")"
tab_c="$(in_container "$tab")" || fail "tabelle fuori da oracle/"
mkdir -p "${out%/*}" "${doc%/*}" || fail "cartelle di destinazione non create"

tmp="$(mktmp)" || exit 1
mkdir -p "$tmp/in" || fail "cartella dell'ingresso privato non creata"
cp "$rec" "$tmp/in/esempio.rec" || fail "copia privata dell'ingresso fallita"

# 2. Generazione e verifica, nel container.
rc=0
# shellcheck disable=SC2086
orun -v "$tmp:/w" -v "$acct:/acct/ACCTFILE.dat:ro" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" \
  ${GOLDEN_DOCKER_EXTRA:-} -- timeout -k 10 "$limite" sh /oracle/golden/genera.sh "$tab_c" /w > "$tmp/genera.log" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  indent "$tmp/genera.log" >&2
  case "$rc" in
    124|137) fail "genera.sh non e' terminato entro ${limite}s" ;;
    *) fail "generazione o verifica dei golden fallita (genera.sh, uscita $rc)" ;;
  esac
fi
indent "$tmp/genera.log" >&2
[ -d "$tmp/generati" ] && [ -f "$tmp/golden-readacct.md" ] || fail "genera.sh e' uscito con 0 senza produrre i golden"

# 3. Pubblicazione, ultimo atto.
mv "$tmp/generati" "$out" || fail "golden non pubblicati in $(rel "$out")"
mv "$tmp/golden-readacct.md" "$doc" || fail "documento non pubblicato in $(rel "$doc")"
log "golden pubblicati in $(rel "$out"); documento in $(rel "$doc")"
