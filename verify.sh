#!/usr/bin/env bash
# Verifica di build e test, senza servizi esterni: unico prerequisito sull'host e' Docker.
#  1. elimina gli output precedenti (fallisce se la cancellazione fallisce);
#  2. lancia mvn -B verify in un'immagine Maven ufficiale (JDK 21, versione fissata);
#  3. controlla che online e batch abbiano esattamente un jar eseguibile (*-exec.jar).
# Non avvia alcun processo applicativo: l'avvio reale dello stack e' compito di ./smoke.sh.
# Variabile opzionale: MENB_BUILD_CACHE_VOLUME (volume Docker con la cache Maven).
set -euo pipefail

IMAGE="maven:3.9.16-eclipse-temurin-21"
CACHE_VOLUME="${MENB_BUILD_CACHE_VOLUME:-menb-build-m2}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Il contenitore gira come root: a fine corsa restituisce all'utente dell'host solo le
# cartelle target/ generate (non .git, ne' i sorgenti, ne' legacy/).
docker run --rm -i \
  --name "menb-build-verify-$$" \
  -v "${CACHE_VOLUME}:/root/.m2" \
  -v "${ROOT}:/workspace" \
  -w /workspace \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  "${IMAGE}" bash -s <<'CONTAINER'
set -uo pipefail
shopt -s nullglob

cleanup() {
  local rc=$?
  for d in carddemo-*/target; do
    if ! chown -R "${HOST_UID}:${HOST_GID}" "${d}"; then
      echo "ERRORE: chown di ${d} fallito" >&2
      [ "${rc}" -eq 0 ] && rc=1
    fi
  done
  exit "${rc}"
}
trap cleanup EXIT

echo "== [1/2] pulizia degli output precedenti e mvn -B verify"
rm -rf carddemo-*/target || { echo "ERRORE: cancellazione dei target/ precedenti fallita" >&2; exit 1; }
residui=(carddemo-*/target)
if [ "${#residui[@]}" -ne 0 ]; then
  echo "ERRORE: output precedenti ancora presenti dopo la cancellazione: ${residui[*]}" >&2
  exit 1
fi
mvn -B verify </dev/null || { echo "ERRORE: mvn verify fallito" >&2; exit 1; }

# Dopo la pulizia puo' esistere solo l'eseguibile prodotto da questa build: ne serve uno.
echo "== [2/2] controllo dei jar eseguibili"
for module in carddemo-online carddemo-batch; do
  jars=("${module}"/target/*-exec.jar)
  if [ "${#jars[@]}" -ne 1 ]; then
    echo "ERRORE: attesi esattamente 1 jar eseguibile in ${module}/target, trovati ${#jars[@]}" >&2
    exit 1
  fi
  echo "${module}: ${jars[0]}"
done
echo "== verifica completata"
CONTAINER
