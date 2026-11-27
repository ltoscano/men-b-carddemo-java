#!/usr/bin/env bash
# Smoke test dello stack Compose: avvio reale, salute, job batch, pulizia.
# Prerequisiti sull'host: bash e Docker con Compose v2. Nessun altro strumento locale:
# la richiesta HTTP parte da un container curl sulla rete dell'host, il JSON si legge
# con PostgreSQL (jsonb) nel container del database.
#
# Passi (ognuno con un limite di tempo):
#   1. controllo-iniziale  nessuna risorsa preesistente del progetto Compose di smoke
#   2. build               costruzione delle immagini online e batch
#   3. avvio               db e online con porta host scelta da Docker; attesa dello stato sano
#   4. salute              GET /actuator/health dall'host: HTTP 200, radice "UP", "db" "UP"
#   5. batch-1, batch-2    docker compose run --rm batch, due volte; dopo ciascun lancio,
#                          verifica in PostgreSQL delle esecuzioni di installationCheckJob
#   6. pulizia             down con volumi, anche se un passo e' fallito; poi verifica via
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
JOB_NAME="installationCheckJob"
STEP_NAME="installationCheckStep"

STEP="avvio-script"
CLEANUP_ARMED=0

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

# Esegue psql nel container db, con lo script SQL sullo standard input.
psql_db() {
  limited "${SHORT_TIMEOUT}" "${COMPOSE[@]}" exec -T db \
    sh -c 'exec psql -X -q -A -t -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" "$@"' psql "$@"
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
log "costruzione delle immagini online e batch"
limited "${BUILD_TIMEOUT}" "${COMPOSE[@]}" --profile batch build </dev/null || fail "costruzione delle immagini fallita"

# --- 3. avvio -------------------------------------------------------------------------
STEP="avvio"
log "docker compose up (db, online), attesa dello stato sano entro ${UP_TIMEOUT}s"
limited "$((UP_TIMEOUT + 30))" "${COMPOSE[@]}" up -d --no-build --wait --wait-timeout "${UP_TIMEOUT}" </dev/null \
  || fail "docker compose up --wait fallito: db e online non sono diventati sani (limite ${UP_TIMEOUT}s)"
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
  limited "${BATCH_TIMEOUT}" "${COMPOSE[@]}" run --rm -T batch </dev/null || rc=$?
  [ "${rc}" -eq 0 ] || fail "il runner batch e' terminato con codice ${rc}"
  verify_executions "${n}"
done

STEP="fine"
log "tutti i passi riusciti; segue la pulizia"
