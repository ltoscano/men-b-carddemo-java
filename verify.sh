#!/usr/bin/env bash
# Verifica completa del progetto: unico prerequisito sull'host e' Docker.
#  1. elimina gli output precedenti e lancia mvn -B verify in un'immagine Maven ufficiale
#     (JDK 21, versione fissata);
#  2. avvia i jar eseguibili prodotti da quella build: online deve rispondere con stato
#     radice "UP", batch deve uscire con 0. Ogni attesa ha un limite e i processi vengono
#     arrestati con la forza se non terminano.
# Variabili opzionali: MENB_BUILD_CACHE_VOLUME (volume Docker con la cache Maven),
# MENB_HEALTH_TIMEOUT (secondi complessivi per la salute di online, default 90),
# MENB_BATCH_TIMEOUT (secondi massimi per batch, default 120).
set -euo pipefail

IMAGE="maven:3.9.16-eclipse-temurin-21"
CACHE_VOLUME="${MENB_BUILD_CACHE_VOLUME:-menb-build-m2}"
HEALTH_TIMEOUT="${MENB_HEALTH_TIMEOUT:-90}"
BATCH_TIMEOUT="${MENB_BATCH_TIMEOUT:-120}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Il contenitore gira come root: a fine corsa restituisce all'utente dell'host solo le
# cartelle target/ generate (non .git, ne' i sorgenti, ne' legacy/).
docker run --rm -i \
  --name "menb-build-verify-$$" \
  -v "${CACHE_VOLUME}:/root/.m2" \
  -v "${ROOT}:/workspace" \
  -w /workspace \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -e HEALTH_TIMEOUT="${HEALTH_TIMEOUT}" \
  -e BATCH_TIMEOUT="${BATCH_TIMEOUT}" \
  "${IMAGE}" bash -s <<'CONTAINER'
set -uo pipefail
shopt -s nullglob
ONLINE_PID=""

# Arresto con SIGTERM, poi SIGKILL dopo 10 s. Restituisce 1 se serve la forza.
stop_proc() {
  local pid="$1"
  kill -TERM "${pid}" 2>/dev/null
  for _ in $(seq 1 10); do
    if ! kill -0 "${pid}" 2>/dev/null; then
      wait "${pid}" 2>/dev/null
      return 0
    fi
    sleep 1
  done
  echo "AVVISO: processo ${pid} non terminato con SIGTERM, arresto forzato" >&2
  kill -KILL "${pid}" 2>/dev/null
  wait "${pid}" 2>/dev/null
  return 1
}

cleanup() {
  local rc=$?
  [ -n "${ONLINE_PID}" ] && stop_proc "${ONLINE_PID}"
  for d in carddemo-*/target; do
    if ! chown -R "${HOST_UID}:${HOST_GID}" "${d}"; then
      echo "ERRORE: chown di ${d} fallito" >&2
      [ "${rc}" -eq 0 ] && rc=1
    fi
  done
  exit "${rc}"
}
trap cleanup EXIT

# Stato radice esattamente "UP" (JSON validato con perl, presente nell'immagine).
health_up() {
  local body
  body="$(curl -fsS --connect-timeout 2 --max-time 3 http://localhost:8080/actuator/health 2>/dev/null)" || return 1
  printf '%s' "${body}" | perl -MJSON::PP -e '
    local $/; my $d = eval { decode_json(<STDIN>) };
    exit(($d && ref($d) eq "HASH" && defined $d->{status} && $d->{status} eq "UP") ? 0 : 1)'
}

echo "== [1/3] pulizia degli output precedenti e mvn -B verify"
rm -rf carddemo-*/target
mvn -B verify </dev/null || { echo "ERRORE: mvn verify fallito" >&2; exit 1; }

# Dopo la pulizia puo' esistere solo l'eseguibile prodotto da questa build: ne serve uno.
select_jar() {
  local jars=("$1"/target/*-exec.jar)
  if [ "${#jars[@]}" -ne 1 ]; then
    echo "ERRORE: attesi esattamente 1 jar eseguibile in $1/target, trovati ${#jars[@]}" >&2
    return 1
  fi
  printf '%s\n' "${jars[0]}"
}
ONLINE_JAR="$(select_jar carddemo-online)" || exit 1
BATCH_JAR="$(select_jar carddemo-batch)" || exit 1

echo "== [2/3] avvio del jar eseguibile di carddemo-online (${ONLINE_JAR})"
java -jar "${ONLINE_JAR}" --server.port=8080 > /tmp/online.log 2>&1 < /dev/null &
ONLINE_PID=$!
healthy=0
deadline=$((SECONDS + HEALTH_TIMEOUT))
while [ "${SECONDS}" -lt "${deadline}" ]; do
  if ! kill -0 "${ONLINE_PID}" 2>/dev/null; then
    echo "ERRORE: online terminato prima di diventare sano" >&2
    tail -n 40 /tmp/online.log >&2
    ONLINE_PID=""
    exit 1
  fi
  if health_up; then
    healthy=1
    break
  fi
  sleep 1
done
if [ "${healthy}" -ne 1 ]; then
  echo "ERRORE: online non sano (stato radice UP) entro ${HEALTH_TIMEOUT}s" >&2
  tail -n 40 /tmp/online.log >&2
  exit 1
fi
echo "online sano (stato radice UP)"
stop_proc "${ONLINE_PID}"
ONLINE_PID=""

echo "== [3/3] avvio del jar eseguibile di carddemo-batch (${BATCH_JAR})"
timeout -k 10 "${BATCH_TIMEOUT}" java -jar "${BATCH_JAR}" </dev/null > /tmp/batch.log 2>&1
rc=$?
if [ "${rc}" -ne 0 ]; then
  echo "ERRORE: batch terminato con codice ${rc} (124/137 = scaduto il limite di ${BATCH_TIMEOUT}s)" >&2
  tail -n 40 /tmp/batch.log >&2
  exit 1
fi
echo "batch terminato con codice 0"
echo "== verifica completata"
CONTAINER
