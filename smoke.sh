#!/usr/bin/env bash
# Smoke test dello stack Compose: avvio reale, salute, job batch, pulizia.
# Prerequisiti sull'host: bash e Docker con Compose v2. Nessun altro strumento locale:
# la richiesta HTTP parte da un container curl sulla rete dell'host, il JSON si legge
# con PostgreSQL (jsonb) nel container del database.
#
# Passi (ognuno con un limite di tempo):
#   1. controllo-iniziale  nessuna risorsa preesistente del progetto Compose di smoke
#   2. build               costruzione delle immagini loader, online e batch
#   3. avvio               db, poi il caricatore dei conti (loader, termina), poi online con porta
#                          host scelta da Docker; attesa dello stato sano (up --wait)
#   4. salute              GET /actuator/health dall'host: HTTP 200, radice "UP", "db" "UP"
#   4a. caricamento        (#60) container del caricatore terminato con 0, nel suo output la
#                          migrazione applicata e il caricamento riuscito; in account 50 righe,
#                          prima chiave 1, ultima 50
#   4b. migrazione         (#59) account e flyway_schema_history tabelle secondo il catalogo,
#                          account con 12 colonne, storico con la sola V1__account.sql riuscita: su
#                          un database nuovo li ha creati il caricatore, primo a partire (#60);
#                          online ha eseguito Flyway all'avvio (nel suo output: migrazione validata)
#   5. batch-1, batch-2    docker compose run --rm batch --spring.batch.job.name=installationCheckJob,
#                          due volte (con due job ogni avvio indica il job, #67); dopo ciascun lancio,
#                          Flyway eseguito anche da batch (nel suo output: migrazione validata,
#                          nessuna da applicare) e verifica in PostgreSQL delle esecuzioni di
#                          installationCheckJob
#   5b. readacct           (#67) job READACCT nell'immagine di batch sui 50 conti caricati: codice 0,
#                          tre file di uscita copiati dal container con docker cp, dimensioni e
#                          confronto con i riferimenti dello scenario esempio (byte ** esclusi), righe
#                          di console di classe a uguali; fallisce se il job non scrive
#   6. batch-primo         (#59) batch su un secondo database vuoto dello stesso server: deve
#                          creare da se' gli stessi oggetti del passo 4b ed eseguire il job
#   6b. online-primo       (#60) online su un terzo database vuoto: deve creare da se' gli stessi
#                          oggetti del passo 4b (prima di #60 lo provava il passo 4b)
#   7. secondo-avvio       (#60) down senza volumi e nuovo up sullo stesso volume: il caricatore
#                          (container nuovo) trova account gia' caricata con lo stesso file,
#                          termina con 0 senza scrivere (impronta righe+xmin invariata), online sano
#   8. batch-3             (#60) docker compose run batch, che rilancia il caricatore terminato:
#                          riesce, terza esecuzione del job, tabella invariata
#   9. riga-alterata       (#60) una riga alterata, poi down senza volumi e nuovo up: il caricatore
#                          termina con 1 (prima differenza alla chiave 1), up fallisce, online non
#                          parte, la tabella resta com'era
#  10. pulizia             down con volumi, anche se un passo e' fallito; poi verifica via
#                          etichette che non restino container (anche arrestati), reti, volumi
# Esce con 0 solo se tutti i passi, pulizia compresa, riescono; altrimenti con 1 (o il
# codice del segnale ricevuto) e dice quale passo e' fallito.
#
# Variabili opzionali (secondi, interi positivi):
#   MENB_SMOKE_BUILD_TIMEOUT (900), MENB_SMOKE_UP_TIMEOUT (240),
#   MENB_SMOKE_BATCH_TIMEOUT (180), MENB_SMOKE_DOWN_TIMEOUT (120)
# MENB_SMOKE_PROJECT: nome del progetto Compose di smoke (predefinito menb-smoke).
set -euo pipefail

# Cartella dello script senza comandi esterni (niente dirname), con esito controllato.
case "${BASH_SOURCE[0]}" in
  */*) ROOT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) ROOT_DIR="." ;;
esac
ROOT="$(cd "${ROOT_DIR}" && pwd)" || { echo "ERRORE: cartella dello script non raggiungibile" >&2; exit 1; }
[ -f "${ROOT}/compose.yaml" ] || { echo "ERRORE: ${ROOT}/compose.yaml non trovato" >&2; exit 1; }
PROJECT="${MENB_SMOKE_PROJECT:-menb-smoke}"
BUILD_TIMEOUT="${MENB_SMOKE_BUILD_TIMEOUT:-900}"
UP_TIMEOUT="${MENB_SMOKE_UP_TIMEOUT:-240}"
BATCH_TIMEOUT="${MENB_SMOKE_BATCH_TIMEOUT:-180}"
DOWN_TIMEOUT="${MENB_SMOKE_DOWN_TIMEOUT:-120}"
SHORT_TIMEOUT=60
# Immagine per la richiesta HTTP dall'host (verificata su Docker Hub il 27 nov 2026).
CURL_IMAGE="curlimages/curl:8.23.0@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93"
LABEL="com.docker.compose.project=${PROJECT}"
# Con due job (installationCheckJob e READACCT, issue #67) ogni avvio di batch indica il job.
JOB_NAME="installationCheckJob"
STEP_NAME="installationCheckStep"

STEP="avvio-script"
CLEANUP_ARMED=0
# Cartella privata della corsa per l'output del runner batch (#59): nome unico, creata con mkdir
# (che fallisce se esiste gia': nessun output di altre corse viene riletto), rimossa alla fine.
TMP_BASE="${TMPDIR:-/tmp}"
WORK="${TMP_BASE%/}/menb-smoke-$$-${RANDOM}${RANDOM}"
WORK_CREATED=0

log() { printf '== [%s] %s\n' "${STEP}" "$*"; }
err() { printf 'ERRORE [%s]: %s\n' "${STEP}" "$*" >&2; }
fail() { err "$*"; exit 1; }

# limited <secondi> <comando esterno> [argomenti...]
# Esegue il comando con un limite di tempo senza dipendere da `timeout` (assente su macOS):
# allo scadere SIGTERM, dopo altri 10 s SIGKILL. Restituisce il codice del comando, o 124
# se il limite e' scaduto. Lo standard input del comando e' quello della funzione.
LIMITED_PID=""
LIMITED_WD=""
limited() {
  local limit="$1"
  shift
  "$@" <&0 &
  local cmd_pid=$!
  LIMITED_PID="${cmd_pid}"
  (
    sleep_pid=""
    trap 'if [ -n "${sleep_pid}" ]; then kill "${sleep_pid}" 2>/dev/null; fi; exit 0' TERM
    sleep "${limit}" &
    sleep_pid=$!
    wait "${sleep_pid}"
    trap '' TERM
    kill -TERM "${cmd_pid}" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "${cmd_pid}" 2>/dev/null || exit 124
      sleep 1
    done
    kill -KILL "${cmd_pid}" 2>/dev/null
    exit 124
  ) </dev/null >/dev/null 2>&1 &
  local wd_pid=$!
  LIMITED_WD="${wd_pid}"
  local rc=0
  local wd_rc=0
  wait "${cmd_pid}" || rc=$?
  kill -TERM "${wd_pid}" 2>/dev/null || true
  wait "${wd_pid}" || wd_rc=$?
  LIMITED_PID=""
  LIMITED_WD=""
  if [ "${wd_rc}" -eq 124 ]; then
    printf 'ERRORE [%s]: superato il limite di %ss: %s\n' "${STEP}" "${limit}" "$*" >&2
    return 124
  fi
  return "${rc}"
}

check_seconds() {
  case "$2" in
    '' | *[!0-9]* | 0) fail "$1 deve essere un intero positivo di secondi, non '$2'" ;;
  esac
}

# Controlla che ogni riga di $2 sia un identificativo del tipo $1 (formato di Docker).
valid_ids() {
  local kind="$1" line
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    case "${kind}" in
      container | network) [[ "${line}" =~ ^[0-9a-f]{64}$ ]] || return 1 ;;
      volume) [[ "${line}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 1 ;;
    esac
  done <<EOF
$2
EOF
  return 0
}

# Acquisisce da Docker gli identificativi grezzi delle risorse con l'etichetta del progetto
# in RES_CONTAINERS, RES_NETWORKS, RES_VOLUMES. Va chiamata nella shell corrente (non in
# $(...)). Restituisce 1, lasciando le variabili al valore "<ignoto>", se un elenco non si
# ottiene o non ha il formato atteso: in quel caso l'assenza di risorse non e' provata.
# La decisione si prende solo su questi dati grezzi; la stampa e' separata (print_resources).
RES_CONTAINERS="<ignoto>"
RES_NETWORKS="<ignoto>"
RES_VOLUMES="<ignoto>"
collect_project_resources() {
  local containers networks volumes
  RES_CONTAINERS="<ignoto>"
  RES_NETWORKS="<ignoto>"
  RES_VOLUMES="<ignoto>"
  if ! containers="$(limited "${SHORT_TIMEOUT}" docker ps -a -q --no-trunc --filter "label=${LABEL}" </dev/null)"; then
    err "elenco dei container con l'etichetta ${LABEL} fallito"
    return 1
  fi
  if ! networks="$(limited "${SHORT_TIMEOUT}" docker network ls -q --no-trunc --filter "label=${LABEL}" </dev/null)"; then
    err "elenco delle reti con l'etichetta ${LABEL} fallito"
    return 1
  fi
  if ! volumes="$(limited "${SHORT_TIMEOUT}" docker volume ls -q --filter "label=${LABEL}" </dev/null)"; then
    err "elenco dei volumi con l'etichetta ${LABEL} fallito"
    return 1
  fi
  if ! valid_ids container "${containers}" || ! valid_ids network "${networks}" || ! valid_ids volume "${volumes}"; then
    err "risposta inattesa di Docker nell'elenco delle risorse: '${containers}' '${networks}' '${volumes}'"
    return 1
  fi
  RES_CONTAINERS="${containers}"
  RES_NETWORKS="${networks}"
  RES_VOLUMES="${volumes}"
  return 0
}

# Vero solo se l'ultima acquisizione e' riuscita e non ha trovato nulla.
no_project_resources() {
  [ -z "${RES_CONTAINERS}" ] && [ -z "${RES_NETWORKS}" ] && [ -z "${RES_VOLUMES}" ]
}

# Stampa su stderr le risorse dell'ultima acquisizione (solo presentazione, con builtin).
print_resources() {
  local kind ids id
  for kind in container network volume; do
    case "${kind}" in
      container) ids="${RES_CONTAINERS}" ;;
      network) ids="${RES_NETWORKS}" ;;
      volume) ids="${RES_VOLUMES}" ;;
    esac
    while IFS= read -r id; do
      [ -n "${id}" ] && printf '  %s %s\n' "${kind}" "${id}" >&2
    done <<EOF
${ids}
EOF
  done
  return 0
}

# Rimozione di riserva, per etichetta, di cio' che "down" non ha rimosso. Gli esiti dei
# singoli comandi vengono riportati; la decisione la prende la nuova acquisizione che segue.
remove_by_label() {
  local id
  while IFS= read -r id; do
    [ -n "${id}" ] || continue
    limited "${SHORT_TIMEOUT}" docker rm -f -v "${id}" </dev/null >/dev/null || err "rimozione del container ${id} fallita"
  done <<EOF
${RES_CONTAINERS}
EOF
  while IFS= read -r id; do
    [ -n "${id}" ] || continue
    limited "${SHORT_TIMEOUT}" docker network rm "${id}" </dev/null >/dev/null || err "rimozione della rete ${id} fallita"
  done <<EOF
${RES_NETWORKS}
EOF
  while IFS= read -r id; do
    [ -n "${id}" ] || continue
    limited "${SHORT_TIMEOUT}" docker volume rm -f "${id}" </dev/null >/dev/null || err "rimozione del volume ${id} fallita"
  done <<EOF
${RES_VOLUMES}
EOF
  return 0
}

# Spegne e rimuove container, reti e volumi del progetto, poi verifica per etichetta.
# Restituisce 0 solo se "down" riesce, l'elenco di Docker si ottiene e non resta nulla.
# La verifica per etichetta serve anche perche' "down" termina con 0 quando un volume non
# si puo' rimuovere perche' in uso.
cleanup_project() {
  local rc=0
  log "docker compose down --volumes del progetto ${PROJECT}"
  if ! limited "${DOWN_TIMEOUT}" "${COMPOSE[@]}" --profile batch down --volumes --remove-orphans --timeout 10 </dev/null; then
    err "docker compose down fallito"
    rc=1
  fi
  if ! collect_project_resources; then
    err "impossibile verificare l'assenza di risorse con l'etichetta ${LABEL}"
    return 1
  fi
  if no_project_resources; then
    log "nessun container, rete o volume con l'etichetta ${LABEL}"
    return "${rc}"
  fi
  err "risorse con l'etichetta ${LABEL} rimaste dopo down:"
  print_resources
  log "rimozione di riserva per etichetta"
  remove_by_label
  if ! collect_project_resources; then
    err "impossibile verificare l'assenza di risorse con l'etichetta ${LABEL}"
    return 1
  fi
  if no_project_resources; then
    log "rimozione di riserva riuscita: nessuna risorsa rimasta"
  else
    err "risorse ancora presenti, da rimuovere a mano:"
    print_resources
  fi
  return 1
}

on_exit() {
  local rc=$?
  local failed_step="${STEP}"
  trap - EXIT HUP INT TERM
  # Interrotto da un segnale durante un comando lungo: lo si ferma prima della pulizia,
  # perche' non ricrei risorse mentre "down" le rimuove.
  if [ -n "${LIMITED_PID}" ] && kill -0 "${LIMITED_PID}" 2>/dev/null; then
    err "arresto del comando in corso (pid ${LIMITED_PID})"
    kill -TERM "${LIMITED_PID}" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "${LIMITED_PID}" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "${LIMITED_PID}" 2>/dev/null || true
  fi
  if [ -n "${LIMITED_WD}" ]; then
    kill -TERM "${LIMITED_WD}" 2>/dev/null || true
  fi
  if [ "${CLEANUP_ARMED}" -eq 1 ]; then
    STEP="pulizia"
    if ! cleanup_project; then
      if [ "${rc}" -eq 0 ]; then
        rc=1
        failed_step="pulizia"
      else
        failed_step="${failed_step}, poi pulizia"
      fi
    fi
  fi
  if [ "${WORK_CREATED}" -eq 1 ] && ! limited "${SHORT_TIMEOUT}" rm -rf "${WORK}" </dev/null; then
    err "cancellazione di ${WORK} fallita"
    if [ "${rc}" -eq 0 ]; then
      rc=1
      failed_step="pulizia"
    fi
  fi
  if [ "${rc}" -eq 0 ]; then
    echo "== SMOKE RIUSCITO"
  else
    echo "== SMOKE FALLITO (passo: ${failed_step}; codice ${rc})" >&2
  fi
  exit "${rc}"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Esegue psql nel container db, con lo script SQL sullo standard input. psql_in <database> usa il
# database indicato (vuoto: quello del servizio, POSTGRES_DB); psql_db usa quello del servizio.
psql_in() {
  local database="$1"
  shift
  limited "${SHORT_TIMEOUT}" "${COMPOSE[@]}" exec -T db \
    sh -c 'd="$1"; shift; exec psql -X -q -A -t -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${d:-${POSTGRES_DB}}" "$@"' \
    psql "${database}" "$@"
}
psql_db() {
  psql_in "" "$@"
}

# Oggetti creati dalla migrazione (#59) nel database $1 (vuoto: quello del servizio), dopo l'avvio
# dell'applicazione $2: account e flyway_schema_history devono essere tabelle secondo il catalogo
# (relkind 'r' in pg_class, non una vista o un'altra relazione con lo stesso nome), account con 12
# colonne, e lo storico deve contenere la sola V1__account.sql riuscita.
query_migration_objects() {
  psql_in "$1" -f - <<'SQL'
select coalesce((select c.relkind::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = 'account'), '<assente>')
       || '|' ||
       coalesce((select c.relkind::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = 'flyway_schema_history'), '<assente>')
       || '|' ||
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'account');
SQL
}
verify_migration() {
  local database="$1" who="$2" kinds history
  if ! kinds="$(query_migration_objects "${database}")"; then
    fail "interrogazione del catalogo fallita (database '${database:-del servizio}')"
  fi
  [ "${kinds}" = "r|r|12" ] \
    || fail "dopo l'avvio di ${who}: attese account e flyway_schema_history come tabelle (relkind r) e 12 colonne in account, trovati '${kinds}' (relkind account|relkind storico|colonne)"
  if ! history="$(psql_in "${database}" -c "select installed_rank || '|' || coalesce(version, '<null>') || '|' || script || '|' || success from flyway_schema_history order by installed_rank" </dev/null)"; then
    fail "lettura dello storico di Flyway fallita (database '${database:-del servizio}')"
  fi
  printf '   %s\n' "${history}"
  [ "${history}" = "1|1|V1__account.sql|true" ] \
    || fail "storico di Flyway inatteso: '${history}' (attesa la sola migrazione 1|1|V1__account.sql|true)"
  return 0
}

# Lettura del JSON con jsonb: "stato radice|stato del componente db", <assente> se manca
# o non e' una stringa. Un JSON non valido fa fallire psql.
health_verdict() {
  psql_db -v "body=$1" -f - <<'SQL'
select case when jsonb_typeof(b) <> 'object' then '<non-oggetto>|<non-oggetto>'
       else coalesce(case when jsonb_typeof(b -> 'status') = 'string' then b ->> 'status' end, '<assente>')
            || '|' ||
            coalesce(case when jsonb_typeof(b #> '{components,db,status}') = 'string'
                          then b #>> '{components,db,status}' end, '<assente>')
       end
from (select (:'body')::jsonb as b) as r;
SQL
}

# Righe "esecuzione|istanza|stato|exit_code|passi|passi_ok" delle esecuzioni del job.
query_executions() {
  psql_db -f - <<SQL
select e.job_execution_id || '|' || e.job_instance_id || '|' || coalesce(e.status, '<null>') || '|'
       || coalesce(e.exit_code, '') || '|'
       || (select count(*) from batch_step_execution s
           where s.job_execution_id = e.job_execution_id) || '|'
       || (select count(*) from batch_step_execution s
           where s.job_execution_id = e.job_execution_id
             and s.step_name = '${STEP_NAME}'
             and s.status = 'COMPLETED' and s.exit_code = 'COMPLETED')
from batch_job_execution e
join batch_job_instance i on i.job_instance_id = e.job_instance_id
where i.job_name = '${JOB_NAME}'
order by e.job_execution_id;
SQL
}

# Dopo il lancio n: esattamente n esecuzioni del job, tutte COMPLETED con il solo passo
# COMPLETED, su istanze distinte, e le esecuzioni dei lanci precedenti invariate.
EXEC_IDS=""
verify_executions() {
  local n="$1" rows line count=0 exec_id inst_id status exit_code steps steps_ok
  local ids="" insts=""
  if ! rows="$(query_executions </dev/null)"; then
    fail "interrogazione delle esecuzioni di ${JOB_NAME} fallita"
  fi
  if [ -n "${rows}" ]; then
    # Solo presentazione, con builtin: la decisione si prende sotto, sui dati grezzi.
    while IFS= read -r line; do printf '   %s\n' "${line}"; done <<EOF
${rows}
EOF
  else
    echo "   (nessuna esecuzione di ${JOB_NAME})"
  fi
  while IFS='|' read -r exec_id inst_id status exit_code steps steps_ok; do
    [ -n "${exec_id}" ] || continue
    count=$((count + 1))
    case "${exec_id}" in '' | *[!0-9]*) fail "riga inattesa: ${exec_id}|${inst_id}|${status}" ;; esac
    case "${inst_id}" in '' | *[!0-9]*) fail "riga inattesa: ${exec_id}|${inst_id}|${status}" ;; esac
    if [ "${status}" != "COMPLETED" ] || [ "${exit_code}" != "COMPLETED" ]; then
      fail "esecuzione ${exec_id}: stato ${status}, exit_code ${exit_code} (atteso COMPLETED)"
    fi
    if [ "${steps}" != "1" ] || [ "${steps_ok}" != "1" ]; then
      fail "esecuzione ${exec_id}: ${steps} passi, ${steps_ok} ${STEP_NAME} COMPLETED (atteso 1 e 1)"
    fi
    case " ${insts} " in *" ${inst_id} "*) fail "istanza ${inst_id} riusata: il lancio non ha creato una nuova istanza" ;; esac
    insts="${insts} ${inst_id}"
    ids="${ids} ${exec_id}"
  done <<EOF
${rows}
EOF
  if [ "${count}" -ne "${n}" ]; then
    fail "trovate ${count} esecuzioni di ${JOB_NAME}, attese ${n}"
  fi
  case "${ids} " in
    "${EXEC_IDS} "*) ;;
    *) fail "le esecuzioni dei lanci precedenti (${EXEC_IDS# }) sono cambiate:${ids}" ;;
  esac
  EXEC_IDS="${ids}"
  [ "${n}" -gt 0 ] || return 0
  log "${n} esecuzioni di ${JOB_NAME} create da questo smoke test, tutte COMPLETED con ${STEP_NAME} COMPLETED"
}

# Identificativo dell'unico container (anche terminato) del servizio $1, in SERVICE_ID. Fallisce se
# l'elenco non si ottiene o non contiene esattamente un identificativo nel formato di Docker.
SERVICE_ID=""
service_container() {
  local ids
  SERVICE_ID=""
  ids="$(limited "${SHORT_TIMEOUT}" "${COMPOSE[@]}" ps -a -q "$1" </dev/null)" || fail "elenco dei container di $1 fallito"
  case "${ids}" in
    '' | *$'\n'*) fail "atteso un solo container di $1, trovati: '${ids}'" ;;
  esac
  valid_ids container "${ids}" || fail "identificativo inatteso del container di $1: '${ids}'"
  SERVICE_ID="${ids}"
}

# Output del servizio $1 (docker compose logs, senza prefisso) nel file $2 della cartella privata,
# poi stampato; il testo resta in SERVICE_LOG.
SERVICE_LOG=""
service_log() {
  local line
  SERVICE_LOG=""
  limited "${SHORT_TIMEOUT}" "${COMPOSE[@]}" logs --no-color --no-log-prefix "$1" </dev/null >"$2" 2>&1 \
    || fail "lettura dell'output di $1 fallita"
  SERVICE_LOG="$(<"$2")" || fail "lettura del file $2 fallita"
  while IFS= read -r line; do printf '   | %s\n' "${line}"; done <<EOF
${SERVICE_LOG}
EOF
}

# Conti caricati (#60): "righe|prima chiave|ultima chiave" in ordine di acct_id. Con la tabella
# vuota le chiavi sono nulle e la concatenazione e' vuota.
query_accounts() {
  psql_db -c "select count(*) || '|' || (select acct_id from account order by acct_id limit 1) || '|' || (select acct_id from account order by acct_id desc limit 1) from account" </dev/null
}
ACCOUNTS_EXPECTED="50|1|50"

# --- 1. controllo iniziale ------------------------------------------------------------
STEP="controllo-iniziale"
check_seconds MENB_SMOKE_BUILD_TIMEOUT "${BUILD_TIMEOUT}"
check_seconds MENB_SMOKE_UP_TIMEOUT "${UP_TIMEOUT}"
check_seconds MENB_SMOKE_BATCH_TIMEOUT "${BATCH_TIMEOUT}"
check_seconds MENB_SMOKE_DOWN_TIMEOUT "${DOWN_TIMEOUT}"
case "${PROJECT}" in
  '' | *[!a-z0-9_-]* | [_-]*) fail "MENB_SMOKE_PROJECT non valido: '${PROJECT}'" ;;
esac
# Porta host scelta da Docker; il file .env dello sviluppatore non viene letto e i profili
# attivi nell'ambiente non valgono, cosi' lo smoke non dipende dalla configurazione locale.
export MENB_ONLINE_PORT=0
unset COMPOSE_PROFILES
COMPOSE=(docker compose --project-name "${PROJECT}" --project-directory "${ROOT}"
  --file "${ROOT}/compose.yaml" --env-file /dev/null)

limited "${SHORT_TIMEOUT}" docker compose version </dev/null || fail "docker compose non disponibile"
limited "${SHORT_TIMEOUT}" mkdir -m 700 "${WORK}" </dev/null || fail "creazione della cartella di lavoro ${WORK} fallita"
WORK_CREATED=1
if ! collect_project_resources; then
  fail "impossibile verificare l'assenza di risorse con l'etichetta ${LABEL}"
fi
CLEANUP_ARMED=1
if ! no_project_resources; then
  print_resources
  fail "esistono gia' risorse del progetto ${PROJECT} (residui di una corsa precedente o uno smoke in corso): vengono rimosse, rilanciare lo smoke"
fi
log "progetto ${PROJECT}: nessuna risorsa preesistente"

# --- 2. build -------------------------------------------------------------------------
STEP="build"
log "costruzione delle immagini loader, online e batch"
limited "${BUILD_TIMEOUT}" "${COMPOSE[@]}" --profile batch build </dev/null || fail "costruzione delle immagini fallita"

# --- 3. avvio -------------------------------------------------------------------------
STEP="avvio"
log "docker compose up (db, loader, online), attesa dello stato sano entro ${UP_TIMEOUT}s"
limited "$((UP_TIMEOUT + 30))" "${COMPOSE[@]}" up -d --no-build --wait --wait-timeout "${UP_TIMEOUT}" </dev/null \
  || fail "docker compose up --wait fallito: caricamento non riuscito o db e online non sani (limite ${UP_TIMEOUT}s)"
for svc in db online; do
  ids="$(limited "${SHORT_TIMEOUT}" "${COMPOSE[@]}" ps -q "${svc}" </dev/null)" || fail "elenco dei container di ${svc} fallito"
  # Esattamente un identificativo, senza pipeline: nessun a capo e formato di Docker.
  case "${ids}" in
    '' | *$'\n'*) fail "atteso un solo container di ${svc}, trovati: '${ids}'" ;;
  esac
  valid_ids container "${ids}" || fail "identificativo inatteso del container di ${svc}: '${ids}'"
  health="$(limited "${SHORT_TIMEOUT}" docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${ids}" </dev/null)" \
    || fail "ispezione del container di ${svc} fallita"
  [ "${health}" = "healthy" ] || fail "${svc} non sano: '${health}'"
done
log "db e online sani"

STEP="porta"
mapping="$(limited "${SHORT_TIMEOUT}" "${COMPOSE[@]}" port online 8080 </dev/null)" || fail "lettura della porta pubblicata fallita"
mapping="${mapping%%$'\n'*}"
PORT="${mapping##*:}"
case "${PORT}" in
  '' | *[!0-9]*) fail "porta pubblicata non riconosciuta: '${mapping}'" ;;
esac
if [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then
  fail "porta pubblicata fuori intervallo: '${mapping}'"
fi
log "online pubblicato sulla porta host ${PORT} (scelta da Docker)"

# --- 4. salute dall'host --------------------------------------------------------------
STEP="salute"
URL="http://127.0.0.1:${PORT}/actuator/health"
log "GET ${URL} (container curl sulla rete dell'host, timeout 5s per richiesta)"
response=""
for attempt in 1 2 3 4 5; do
  if response="$(limited 30 docker run --rm --network host --label "${LABEL}" "${CURL_IMAGE}" \
    -sS --connect-timeout 3 --max-time 5 -w '\n%{http_code}' "${URL}" </dev/null)"; then
    break
  fi
  response=""
  err "tentativo ${attempt}: richiesta HTTP non riuscita"
  sleep 2
done
[ -n "${response}" ] || fail "nessuna risposta HTTP da ${URL}"
http_code="${response##*$'\n'}"
body="${response%$'\n'*}"
printf '   HTTP %s %s\n' "${http_code}" "${body}"
[ "${http_code}" = "200" ] || fail "HTTP ${http_code} da ${URL} (atteso 200)"
if ! verdict="$(health_verdict "${body}")"; then
  fail "la risposta di ${URL} non e' un JSON valido"
fi
root_status="${verdict%%|*}"
db_status="${verdict#*|}"
[ "${root_status}" = "UP" ] || fail "stato alla radice '${root_status}' (atteso UP)"
[ "${db_status}" = "UP" ] || fail "componente db '${db_status}' (atteso presente e UP)"
log "stato alla radice UP, componente db UP"

# --- 4a. caricamento dei conti (#60) ----------------------------------------------------
# Il caricatore parte prima di online (online dipende dal suo completamento riuscito): sul database
# nuovo applica la migrazione, carica ACCTFILE.rec (nell'immagine) e termina con 0.
STEP="caricamento"
service_container loader
LOADER_ID="${SERVICE_ID}"
loader_state="$(limited "${SHORT_TIMEOUT}" docker inspect --format '{{.State.Status}}|{{.State.ExitCode}}' "${LOADER_ID}" </dev/null)" \
  || fail "ispezione del container del caricatore fallita"
[ "${loader_state}" = "exited|0" ] || fail "caricatore in stato '${loader_state}' (atteso exited|0: terminato con codice 0)"
service_log loader "${WORK}/loader-1.log"
for atteso in 'Successfully applied 1 migration to schema "public"' \
  'CARICAMENTO RIUSCITO: 50 record caricati da /app/dati/ACCTFILE.rec nella tabella account'; do
  case "${SERVICE_LOG}" in
    *"${atteso}"*) ;;
    *) fail "nell'output del caricatore manca '${atteso}'" ;;
  esac
done
if ! accounts="$(query_accounts)"; then
  fail "lettura dei conti caricati fallita"
fi
[ "${accounts}" = "${ACCOUNTS_EXPECTED}" ] \
  || fail "conti caricati: '${accounts}' (attesi ${ACCOUNTS_EXPECTED}: righe|prima chiave|ultima chiave)"
log "caricatore terminato con 0 dopo aver applicato la migrazione; account con 50 righe, chiavi da 1 a 50"

# --- 4b. migrazione dello schema (#59) ----------------------------------------------------
# Il database e' nuovo (volume creato da questo smoke); il primo a partire e' il caricatore, che ha
# applicato la migrazione (passo 4a). Online, partito dopo, l'ha validata all'avvio: la prova e' nel
# suo output. Che online sappia anche applicarla su un database vuoto lo prova il passo online-primo.
STEP="migrazione"
verify_migration "" "loader e online"
service_log online "${WORK}/online-1.log"
for atteso in 'Successfully validated 1 migration' 'Schema "public" is up to date. No migration necessary.'; do
  case "${SERVICE_LOG}" in
    *"${atteso}"*) ;;
    *) fail "nell'output di online manca '${atteso}': Flyway non e' stato eseguito all'avvio di online" ;;
  esac
done
log "account e' una tabella con 12 colonne, storico di Flyway con V1__account.sql riuscita; online ha validato la migrazione"

# --- 5. job batch, due lanci ----------------------------------------------------------
STEP="batch-0"
if ! tables="$(psql_db -c "select count(*) from pg_tables where schemaname = 'public' and tablename = 'batch_job_execution'" </dev/null)"; then
  fail "interrogazione iniziale del database fallita"
fi
if [ "${tables}" = "1" ]; then
  verify_executions 0
elif [ "${tables}" != "0" ]; then
  fail "risposta inattesa dal database: '${tables}'"
fi
log "nessuna esecuzione di ${JOB_NAME} prima dei lanci"
for n in 1 2; do
  STEP="batch-${n}"
  log "docker compose run --rm batch (lancio ${n}, limite ${BATCH_TIMEOUT}s)"
  rc=0
  # Output in un file della cartella privata (non in $(...): un processo figlio sopravvissuto
  # all'arresto terrebbe aperta la pipe), poi mostrato e letto.
  batch_log="${WORK}/batch-${n}.log"
  limited "${BATCH_TIMEOUT}" "${COMPOSE[@]}" run --rm -T batch "--spring.batch.job.name=${JOB_NAME}" </dev/null \
    >"${batch_log}" 2>&1 || rc=$?
  batch_out="$(<"${batch_log}")" || fail "lettura dell'output del runner batch fallita"
  while IFS= read -r line; do printf '   | %s\n' "${line}"; done <<EOF
${batch_out}
EOF
  [ "${rc}" -eq 0 ] || fail "il runner batch e' terminato con codice ${rc}"
  # Anche batch esegue Flyway all'avvio (#59): sul database gia' migrato da online valida la
  # migrazione e non ne applica altre. Il database non cambia, quindi la prova e' nel suo output.
  for atteso in 'Successfully validated 1 migration' 'Current version of schema "public": 1' \
    'Schema "public" is up to date. No migration necessary.'; do
    case "${batch_out}" in
      *"${atteso}"*) ;;
      *) fail "nell'output del runner batch manca '${atteso}': Flyway non e' stato eseguito all'avvio di batch" ;;
    esac
  done
  log "batch ha eseguito Flyway all'avvio: 1 migrazione validata, schema alla versione 1, nessuna da applicare"
  verify_executions "${n}"
done

# --- 5b. job READACCT sui conti caricati (#67) -------------------------------------------
# Il job READACCT (CBACT01C tradotto) gira nell'immagine distribuita di batch, con il comando del
# contratto (docs/contratti.md), sui 50 conti che il caricatore ha messo in account (lo stesso file
# dello scenario esempio di #55). Le uscite si scrivono in /tmp del container di "run", che non si
# rimuove alla fine del job: i tre file si copiano con "docker cp" in una cartella nuova della corsa.
# Poi: codice 0, dimensioni (107 x 50, 110 x 50, 50 x (4 + 12 + 4 + 39)) e confronto con i riferimenti
# dello scenario esempio (oracle/golden/readacct/generati/golden/esempio/), byte per byte tranne i byte
# mascherati (**) dei riferimenti; console: le righe di classe a uguali, nella stessa posizione. Il
# comparatore del test di parita' e' codice di test di carddemo-parity, non utilizzabile qui: il
# confronto e' riscritto con builtin di bash, sui byte letti con od nel container del database.
STEP="readacct"
READACCT_REF="${ROOT}/oracle/golden/readacct/generati/golden/esempio"
READACCT_RUN="${PROJECT}-readacct"
READACCT_DIR="${WORK}/readacct"
READACCT_N=50

# Byte del file $1 in esadecimale minuscolo continuo, in HEX_OUT; $2 distingue i file di appoggio. La
# conversione gira nel container db (Debian), senza pipeline: od scrive in un file temporaneo del
# container e tr ne toglie spazi e a capo; set -e fa fallire il comando se uno dei due fallisce. Nessuno
# strumento sull'host, e nessuna sostituzione di bash su testi lunghi (in bash 3.2 e' quadratica: la prima
# versione del passo restava minuti su 16 KB). Fallisce se la conversione fallisce o se l'uscita non e'
# esadecimale.
HEX_OUT=""
hex_of() {
  local raw
  HEX_OUT=""
  if ! limited "${SHORT_TIMEOUT}" "${COMPOSE[@]}" exec -T db \
    sh -c 'set -eu; t="$(mktemp)"; od -An -v -tx1 >"${t}"; tr -d " \n" <"${t}"; rm -f "${t}"' \
    <"$1" >"${WORK}/od-$2.out" 2>"${WORK}/od-$2.err"; then
    err "lettura dei byte di $1 fallita (od nel container db): $(<"${WORK}/od-$2.err")"
    return 1
  fi
  raw="$(<"${WORK}/od-$2.out")" || return 1
  if ! [[ "${raw}" =~ ^[0-9a-f]*$ ]]; then
    err "uscita di od non esadecimale per $1"
    return 1
  fi
  HEX_OUT="${raw}"
}

# compare_fixed NOME LUNGHEZZA ESADECIMALE RIFERIMENTO: record fissi, uno per riga del riferimento
# (esadecimale, ** per un byte mascherato), confrontati byte per byte; poi nessun byte in piu'.
compare_fixed() {
  local name="$1" len="$2" hex="$3" ref="$4" line rec want got r=0 i
  local width=$((len * 2))
  [ -f "${ref}" ] || fail "riferimento assente: ${ref}"
  while IFS= read -r line; do
    [ "${#line}" -eq "${width}" ] || fail "riferimento ${ref##*/}, riga $((r + 1)): ${#line} caratteri, attesi ${width}"
    rec="${hex:$((r * width)):${width}}"
    [ "${#rec}" -eq "${width}" ] \
      || fail "${name}: record $((r + 1)) mancante o troncato ($(( ${#hex} / 2 )) byte nel file, attesi $((READACCT_N * len)))"
    for ((i = 0; i < len; i++)); do
      want="${line:$((2 * i)):2}"
      if [ "${want}" != "**" ]; then
        got="${rec:$((2 * i)):2}"
        [ "${want}" = "${got}" ] || fail "${name} record $((r + 1)) posizione $((i + 1)): atteso ${want}, trovato ${got}"
      fi
    done
    r=$((r + 1))
  done <"${ref}"
  [ "${r}" -eq "${READACCT_N}" ] || fail "riferimento ${ref##*/}: ${r} record, attesi ${READACCT_N}"
  [ "${#hex}" -eq $((r * width)) ] \
    || fail "${name}: $(( ${#hex} / 2 )) byte, attesi $((r * len)) (${r} record di ${len} byte)"
  log "${name}: $(( ${#hex} / 2 )) byte, ${r} record di ${len} byte uguali al riferimento (byte ** esclusi)"
}

# compare_vbrc ESADECIMALE RIFERIMENTO: ogni record logico del riferimento (<numero> <lunghezza> <dati>)
# preceduto dal descrittore del contratto (lunghezza compreso il descrittore su 2 byte, poi 00 00).
compare_vbrc() {
  local hex="$1" ref="$2" num len data want_num want_rdw rdw got l p=0 r=0
  [ -f "${ref}" ] || fail "riferimento assente: ${ref}"
  while IFS=' ' read -r num len data; do
    r=$((r + 1))
    printf -v want_num '%06d' "${r}"
    [ "${num}" = "${want_num}" ] || fail "riferimento ${ref##*/}, riga ${r}: numero '${num}'"
    case "${len}" in
      [0-9][0-9][0-9]) ;;
      *) fail "riferimento ${ref##*/}, riga ${r}: lunghezza '${len}'" ;;
    esac
    l=$((10#${len}))
    [ "${#data}" -eq $((2 * l)) ] || fail "riferimento ${ref##*/}, riga ${r}: dati di ${#data} caratteri, attesi $((2 * l))"
    printf -v want_rdw '%04x0000' $((l + 4))
    rdw="${hex:${p}:8}"
    [ "${rdw}" = "${want_rdw}" ] \
      || fail "VBRCFILE record ${r} (byte $((p / 2 + 1))): descrittore '${rdw}', atteso ${want_rdw}"
    got="${hex:$((p + 8)):$((2 * l))}"
    [ "${got}" = "${data}" ] || fail "VBRCFILE record ${r}: atteso ${data}, trovato ${got}"
    p=$((p + 8 + 2 * l))
  done <"${ref}"
  [ "${r}" -eq $((2 * READACCT_N)) ] || fail "riferimento ${ref##*/}: ${r} record, attesi $((2 * READACCT_N))"
  [ "${p}" -eq "${#hex}" ] || fail "VBRCFILE: $(( ${#hex} / 2 )) byte, attesi $((p / 2)) (${r} record con il descrittore)"
  log "VBRCFILE: $((p / 2)) byte, ${r} record logici con il descrittore uguali al riferimento"
}

# compare_console STDOUT RIFERIMENTO: stesso numero di righe (2 + 15 x N); le righe di classe a uguali,
# nella stessa posizione; le righe #OSSERVAZIONE del riferimento presenti ma non confrontate.
compare_console() {
  local out="$1" ref="$2" a b i=0
  [ -f "${ref}" ] || fail "riferimento assente: ${ref}"
  exec 3<"${ref}" 4<"${out}" || fail "apertura della console o del riferimento fallita"
  while IFS= read -r a <&3; do
    i=$((i + 1))
    IFS= read -r b <&4 || fail "console: ${i} righe attese o piu', lo standard output finisce prima (riga ${i}: «${a}»)"
    case "${a}" in
      '#OSSERVAZIONE'*) continue ;;
    esac
    [ "${a}" = "${b}" ] || fail "console riga ${i}: attesa «${a}», trovata «${b}»"
  done
  if IFS= read -r b <&4; then
    fail "console: riga in eccesso $((i + 1)): «${b}»"
  fi
  exec 3<&- 4<&-
  [ "${i}" -eq $((2 + 15 * READACCT_N)) ] || fail "riferimento della console di ${i} righe, attese $((2 + 15 * READACCT_N))"
  log "console: ${i} righe, quelle di classe a uguali al riferimento"
}

limited "${SHORT_TIMEOUT}" mkdir "${READACCT_DIR}" </dev/null || fail "creazione della cartella ${READACCT_DIR} fallita"
log "docker compose run batch --spring.batch.job.name=READACCT sui conti caricati (limite ${BATCH_TIMEOUT}s)"
rc=0
limited "${BATCH_TIMEOUT}" "${COMPOSE[@]}" run -T --name "${READACCT_RUN}" batch --spring.batch.job.name=READACCT \
  OUTFILE=/tmp/OUTFILE ARRYFILE=/tmp/ARRYFILE VBRCFILE=/tmp/VBRCFILE \
  </dev/null >"${READACCT_DIR}/stdout" 2>"${READACCT_DIR}/stderr" || rc=$?
if [ "${rc}" -ne 0 ]; then
  while IFS= read -r line; do printf '   | %s\n' "${line}"; done <"${READACCT_DIR}/stderr"
  fail "il job READACCT e' terminato con codice ${rc} (atteso 0)"
fi
log "job READACCT terminato con 0; copia delle uscite dal container ${READACCT_RUN}"
for f in OUTFILE ARRYFILE VBRCFILE; do
  limited "${SHORT_TIMEOUT}" docker cp "${READACCT_RUN}:/tmp/${f}" "${READACCT_DIR}/${f}" </dev/null >/dev/null \
    || fail "${f} non copiato dal container: il job non l'ha scritto"
done
limited "${SHORT_TIMEOUT}" docker rm -v "${READACCT_RUN}" </dev/null >/dev/null || fail "rimozione del container ${READACCT_RUN} fallita"
hex_of "${READACCT_DIR}/OUTFILE" outfile || fail "lettura di OUTFILE fallita"
compare_fixed OUTFILE 107 "${HEX_OUT}" "${READACCT_REF}/OUTFILE.riferimento.txt"
hex_of "${READACCT_DIR}/ARRYFILE" arryfile || fail "lettura di ARRYFILE fallita"
compare_fixed ARRYFILE 110 "${HEX_OUT}" "${READACCT_REF}/ARRYFILE.riferimento.txt"
hex_of "${READACCT_DIR}/VBRCFILE" vbrcfile || fail "lettura di VBRCFILE fallita"
compare_vbrc "${HEX_OUT}" "${READACCT_REF}/VBRCFILE.riferimento.txt"
compare_console "${READACCT_DIR}/stdout" "${READACCT_REF}/console.riferimento.txt"
log "READACCT: uscite e console uguali ai riferimenti dello scenario esempio"

# --- 6. batch come primo migratore su un database vuoto (#59) ---------------------------
# Nel database del servizio la migrazione l'ha gia' applicata online: qui batch parte da solo,
# con il suo classpath distribuito (la sua immagine), su un secondo database vuoto dello stesso
# server, e deve creare da se' account e lo storico di Flyway, accanto alle tabelle di Spring Batch.
STEP="batch-primo"
FIRST_DB="menb_batch_primo"
log "database vuoto ${FIRST_DB}: batch come primo migratore (limite ${BATCH_TIMEOUT}s)"
psql_db -c "create database ${FIRST_DB}" </dev/null || fail "creazione del database ${FIRST_DB} fallita"
if ! objects="$(psql_in "${FIRST_DB}" -c "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'" </dev/null)"; then
  fail "interrogazione del database ${FIRST_DB} fallita"
fi
[ "${objects}" = "0" ] || fail "il database ${FIRST_DB} non e' vuoto prima del lancio: ${objects} oggetti nello schema public"
rc=0
batch_log="${WORK}/batch-primo.log"
limited "${BATCH_TIMEOUT}" "${COMPOSE[@]}" run --rm -T \
  -e "SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/${FIRST_DB}" batch "--spring.batch.job.name=${JOB_NAME}" \
  </dev/null >"${batch_log}" 2>&1 || rc=$?
batch_out="$(<"${batch_log}")" || fail "lettura dell'output del runner batch fallita"
while IFS= read -r line; do printf '   | %s\n' "${line}"; done <<EOF
${batch_out}
EOF
[ "${rc}" -eq 0 ] || fail "il runner batch e' terminato con codice ${rc}"
verify_migration "${FIRST_DB}" batch
if ! runs="$(psql_in "${FIRST_DB}" -c "select count(*) || '|' || count(*) filter (where status = 'COMPLETED' and exit_code = 'COMPLETED') from batch_job_execution" </dev/null)"; then
  fail "interrogazione delle esecuzioni nel database ${FIRST_DB} fallita"
fi
[ "${runs}" = "1|1" ] || fail "esecuzioni di ${JOB_NAME} nel database ${FIRST_DB}: '${runs}' (attese 1|1: una, COMPLETED)"
log "batch ha applicato la migrazione su un database vuoto: account e' una tabella con 12 colonne, storico con V1__account.sql riuscita, job COMPLETED"

# --- 6b. online come primo migratore su un database vuoto (#60) ---------------------------
# Dal #60 il caricatore parte prima di online e applica lui la migrazione nel database del servizio:
# online, con la sua immagine, si avvia da solo su un terzo database vuoto e deve creare da se' gli
# stessi oggetti. Il container (run senza dipendenze ne' porte pubblicate) si ferma e si rimuove
# alla fine del passo; se il passo fallisce lo rimuove la pulizia (down rimuove anche i container
# di "run").
STEP="online-primo"
ONLINE_DB="menb_online_primo"
ONLINE_RUN="${PROJECT}-online-primo"
log "database vuoto ${ONLINE_DB}: online come primo migratore (limite ${UP_TIMEOUT}s)"
psql_db -c "create database ${ONLINE_DB}" </dev/null || fail "creazione del database ${ONLINE_DB} fallita"
if ! objects="$(psql_in "${ONLINE_DB}" -c "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'" </dev/null)"; then
  fail "interrogazione del database ${ONLINE_DB} fallita"
fi
[ "${objects}" = "0" ] || fail "il database ${ONLINE_DB} non e' vuoto prima dell'avvio: ${objects} oggetti nello schema public"
limited "${SHORT_TIMEOUT}" "${COMPOSE[@]}" run -d --no-deps -T --name "${ONLINE_RUN}" \
  -e "SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/${ONLINE_DB}" online </dev/null >"${WORK}/online-primo-run.log" 2>&1 \
  || fail "avvio di online sul database ${ONLINE_DB} fallito: $(<"${WORK}/online-primo-run.log")"
deadline=$((SECONDS + UP_TIMEOUT))
while :; do
  online_state="$(limited "${SHORT_TIMEOUT}" docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${ONLINE_RUN}" </dev/null)" \
    || fail "ispezione del container ${ONLINE_RUN} fallita"
  case "${online_state}" in
    'running|healthy') break ;;
    'running|starting') ;;
    *) fail "container ${ONLINE_RUN} in stato '${online_state}' (atteso running|healthy)" ;;
  esac
  [ "${SECONDS}" -lt "${deadline}" ] || fail "online sul database ${ONLINE_DB} non sano entro ${UP_TIMEOUT}s (stato '${online_state}')"
  sleep 2
done
verify_migration "${ONLINE_DB}" online
limited "${SHORT_TIMEOUT}" docker stop --time 10 "${ONLINE_RUN}" </dev/null >/dev/null || fail "arresto del container ${ONLINE_RUN} fallito"
limited "${SHORT_TIMEOUT}" docker rm -v "${ONLINE_RUN}" </dev/null >/dev/null || fail "rimozione del container ${ONLINE_RUN} fallita"
log "online ha applicato la migrazione su un database vuoto: account e' una tabella con 12 colonne, storico con V1__account.sql riuscita"

# --- 7-9. riavvii sullo stesso volume (#60) -----------------------------------------------
# Impronta della tabella: ogni riga con il suo xmin (la transazione che l'ha scritta). Se il
# caricatore non scrive nulla, l'impronta non cambia.
fingerprint() {
  psql_db -c "select count(*) || ':' || coalesce(md5(string_agg(xmin::text || '/' || account::text, ',' order by acct_id)), '-') from account" </dev/null
}

# down senza --volumes (i container si rimuovono, il volume del database resta), poi un nuovo up.
# Codice di up in UP_RC; l'output va in $1 e si stampa. Un limite scaduto (124) fa fallire subito.
UP_RC=0
restart_same_volume() {
  local log_file="$1" line
  limited "${DOWN_TIMEOUT}" "${COMPOSE[@]}" --profile batch down --remove-orphans --timeout 10 </dev/null \
    || fail "docker compose down (senza volumi) fallito"
  UP_RC=0
  limited "$((UP_TIMEOUT + 30))" "${COMPOSE[@]}" up -d --no-build --wait --wait-timeout "${UP_TIMEOUT}" </dev/null \
    >"${log_file}" 2>&1 || UP_RC=$?
  while IFS= read -r line; do printf '   | %s\n' "${line}"; done <"${log_file}"
  [ "${UP_RC}" -ne 124 ] || fail "up oltre il limite di tempo (${UP_TIMEOUT}s)"
}

# Container del caricatore dopo un riavvio: nuovo (non quello del primo avvio), nello stato $1
# (exited|<codice>), con il testo $2 nel suo output.
check_new_loader() {
  service_container loader
  [ "${SERVICE_ID}" != "${LOADER_ID}" ] || fail "il container del caricatore e' quello del primo avvio: down non l'ha rimosso"
  loader_state="$(limited "${SHORT_TIMEOUT}" docker inspect --format '{{.State.Status}}|{{.State.ExitCode}}' "${SERVICE_ID}" </dev/null)" \
    || fail "ispezione del container del caricatore fallita"
  [ "${loader_state}" = "$1" ] || fail "caricatore in stato '${loader_state}' (atteso $1)"
  service_log loader "${WORK}/loader-${STEP}.log"
  case "${SERVICE_LOG}" in
    *"$2"*) ;;
    *) fail "nell'output del caricatore manca '$2'" ;;
  esac
}

# --- 7. secondo avvio sullo stesso volume: riesce senza scrivere ---------------------------
# Il caricatore trova account con esattamente i record del file, termina con 0 senza scrivere
# ("gia' caricato"), online riparte. Per ricaricare da capo si ricrea il volume (docs/sviluppo.md).
STEP="secondo-avvio"
if ! before="$(fingerprint)"; then
  fail "impronta della tabella fallita"
fi
log "docker compose down senza --volumes, poi un nuovo up sullo stesso volume (atteso: riesce senza scrivere)"
restart_same_volume "${WORK}/secondo-up.log"
[ "${UP_RC}" -eq 0 ] || fail "il secondo up sullo stesso volume e' fallito (codice ${UP_RC}): atteso il caricatore che trova la tabella gia' caricata"
check_new_loader "exited|0" "CARICAMENTO RIUSCITO: già caricato: 50 record, nessuna modifica"
service_container online
online_state="$(limited "${SHORT_TIMEOUT}" docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${SERVICE_ID}" </dev/null)" \
  || fail "ispezione del container di online fallita"
[ "${online_state}" = "running|healthy" ] || fail "online in stato '${online_state}' dopo il secondo avvio (atteso running|healthy)"
if ! after="$(fingerprint)"; then
  fail "impronta della tabella fallita"
fi
[ "${after}" = "${before}" ] || fail "la tabella e' cambiata nel secondo avvio: impronta '${before}' poi '${after}'"
if ! accounts="$(query_accounts)"; then
  fail "lettura dei conti dopo il secondo avvio fallita"
fi
[ "${accounts}" = "${ACCOUNTS_EXPECTED}" ] || fail "conti dopo il secondo avvio: '${accounts}' (attesi ${ACCOUNTS_EXPECTED})"
log "secondo up riuscito: caricatore terminato con 0 (gia' caricato, nessuna modifica), online sano, tabella invariata (${after%%:*} righe, stessi xmin)"

# --- 8. batch con la dipendenza dal caricatore ----------------------------------------------
# docker compose run batch rilancia il caricatore (gia' terminato): trova la tabella gia' caricata,
# termina con 0, e batch parte. Terza esecuzione del job sul database del servizio.
STEP="batch-3"
log "docker compose run --rm batch dopo il secondo avvio (limite ${BATCH_TIMEOUT}s)"
service_container loader
loader_started="$(limited "${SHORT_TIMEOUT}" docker inspect --format '{{.State.StartedAt}}' "${SERVICE_ID}" </dev/null)" \
  || fail "ispezione del container del caricatore fallita"
rc=0
batch_log="${WORK}/batch-3.log"
limited "${BATCH_TIMEOUT}" "${COMPOSE[@]}" run --rm -T batch "--spring.batch.job.name=${JOB_NAME}" </dev/null \
  >"${batch_log}" 2>&1 || rc=$?
batch_out="$(<"${batch_log}")" || fail "lettura dell'output del runner batch fallita"
while IFS= read -r line; do printf '   | %s\n' "${line}"; done <<EOF
${batch_out}
EOF
[ "${rc}" -eq 0 ] || fail "docker compose run batch e' terminato con codice ${rc}"
service_container loader
loader_state="$(limited "${SHORT_TIMEOUT}" docker inspect --format '{{.State.Status}}|{{.State.ExitCode}}|{{.State.StartedAt}}' "${SERVICE_ID}" </dev/null)" \
  || fail "ispezione del container del caricatore fallita"
# batch dipende dal caricatore: run deve averlo rilanciato (nuovo avvio), ed e' terminato con 0.
[ "${loader_state}" != "exited|0|${loader_started}" ] || fail "run batch non ha rilanciato il caricatore (avvio ancora ${loader_started}): batch non dipende da loader"
[ "${loader_state%|*}" = "exited|0" ] || fail "caricatore rilanciato da run batch in stato '${loader_state}' (atteso exited|0)"
verify_executions 3
log "run batch ha rilanciato il caricatore (terminato con 0, gia' caricato) e il job"
if ! after="$(fingerprint)"; then
  fail "impronta della tabella fallita"
fi
[ "${after}" = "${before}" ] || fail "la tabella e' cambiata con run batch: impronta '${before}' poi '${after}'"

# --- 9. terzo avvio con una riga alterata: fallisce ------------------------------------------
# Una riga della tabella diversa dal file: il caricatore si ferma con la prima differenza e
# termina con 1 senza scrivere; up fallisce e online (che dipende dal caricamento riuscito) resta
# creato ma non avviato.
STEP="riga-alterata"
psql_db -c "update account set acct_curr_bal = acct_curr_bal + 1 where acct_id = 1" </dev/null >/dev/null \
  || fail "alterazione della riga di prova fallita"
if ! before="$(fingerprint)"; then
  fail "impronta della tabella fallita"
fi
[ "${before}" != "${after}" ] || fail "l'alterazione non ha cambiato l'impronta della tabella"
log "riga con acct_id 1 alterata (saldo + 1), poi down senza --volumes e un nuovo up (atteso il fallimento)"
restart_same_volume "${WORK}/terzo-up.log"
[ "${UP_RC}" -ne 0 ] || fail "il terzo up con una riga alterata e' riuscito: atteso il rifiuto del caricatore"
check_new_loader "exited|1" "Prima differenza: chiave 1, record 1 (offset 0-299 del file), campo ACCT-CURR-BAL"
service_container online
online_state="$(limited "${SHORT_TIMEOUT}" docker inspect --format '{{.State.Status}}|{{.State.StartedAt}}' "${SERVICE_ID}" </dev/null)" \
  || fail "ispezione del container di online fallita"
[ "${online_state}" = "created|0001-01-01T00:00:00Z" ] \
  || fail "online in stato '${online_state}' (atteso created e mai avviato, perche' il caricamento e' fallito)"
if ! after="$(fingerprint)"; then
  fail "impronta della tabella fallita"
fi
[ "${after}" = "${before}" ] || fail "la tabella e' cambiata nel terzo avvio: impronta '${before}' poi '${after}'"
log "terzo up fallito come atteso: caricatore terminato con 1 (prima differenza alla chiave 1), online non avviato, tabella invariata"

STEP="fine"
log "tutti i passi riusciti; segue la pulizia"
