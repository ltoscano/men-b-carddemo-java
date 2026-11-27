#!/usr/bin/env bash
# Verifica completa del progetto: unico prerequisito sull'host e' Docker.
#  1. mvn -B verify in un'immagine Maven ufficiale (JDK 21, versione fissata);
#  2. avvio dei jar eseguibili prodotti: online deve rispondere sano, batch deve uscire con 0.
# Variabili opzionali: MENB_BUILD_CACHE_VOLUME (volume Docker con la cache Maven),
# MENB_HEALTH_TIMEOUT (secondi di attesa per la salute di online, default 90).
set -euo pipefail

IMAGE="maven:3.9.16-eclipse-temurin-21"
CACHE_VOLUME="${MENB_BUILD_CACHE_VOLUME:-menb-build-m2}"
HEALTH_TIMEOUT="${MENB_HEALTH_TIMEOUT:-90}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Il contenitore gira come root: a fine corsa restituisce i file creati all'utente dell'host.
docker run --rm -i \
  --name "menb-build-verify-$$" \
  -v "${CACHE_VOLUME}:/root/.m2" \
  -v "${ROOT}:/workspace" \
  -w /workspace \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -e HEALTH_TIMEOUT="${HEALTH_TIMEOUT}" \
  "${IMAGE}" bash -s <<'CONTAINER'
set -uo pipefail
ONLINE_PID=""
cleanup() {
  [ -n "${ONLINE_PID}" ] && kill "${ONLINE_PID}" 2>/dev/null
  chown -R "${HOST_UID}:${HOST_GID}" /workspace 2>/dev/null
  true
}
trap cleanup EXIT

echo "== [1/3] mvn -B verify"
mvn -B verify </dev/null || { echo "ERRORE: mvn verify fallito" >&2; exit 1; }

echo "== [2/3] avvio del jar eseguibile di carddemo-online"
ONLINE_JAR="$(ls carddemo-online/target/*-exec.jar 2>/dev/null | head -n 1)"
[ -n "${ONLINE_JAR}" ] || { echo "ERRORE: jar eseguibile di online non trovato" >&2; exit 1; }
java -jar "${ONLINE_JAR}" --server.port=8080 > /tmp/online.log 2>&1 &
ONLINE_PID=$!
healthy=0
for _ in $(seq 1 "${HEALTH_TIMEOUT}"); do
  if ! kill -0 "${ONLINE_PID}" 2>/dev/null; then
    echo "ERRORE: online terminato prima di diventare sano" >&2
    tail -n 40 /tmp/online.log >&2
    exit 1
  fi
  if curl -fsS http://localhost:8080/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
    healthy=1
    break
  fi
  sleep 1
done
if [ "${healthy}" -ne 1 ]; then
  echo "ERRORE: online non sano entro ${HEALTH_TIMEOUT}s" >&2
  tail -n 40 /tmp/online.log >&2
  exit 1
fi
echo "online sano: $(curl -fsS http://localhost:8080/actuator/health)"
kill "${ONLINE_PID}" 2>/dev/null
wait "${ONLINE_PID}" 2>/dev/null
ONLINE_PID=""

echo "== [3/3] avvio del jar eseguibile di carddemo-batch"
BATCH_JAR="$(ls carddemo-batch/target/*-exec.jar 2>/dev/null | head -n 1)"
[ -n "${BATCH_JAR}" ] || { echo "ERRORE: jar eseguibile di batch non trovato" >&2; exit 1; }
timeout 120 java -jar "${BATCH_JAR}" </dev/null > /tmp/batch.log 2>&1
rc=$?
if [ "${rc}" -ne 0 ]; then
  echo "ERRORE: batch terminato con codice ${rc}" >&2
  tail -n 40 /tmp/batch.log >&2
  exit 1
fi
echo "batch terminato con codice 0"
echo "== verifica completata"
CONTAINER
