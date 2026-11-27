#!/usr/bin/env bash
# Verifica di build e test: unico prerequisito sull'host e' Docker.
#  1. elimina gli output precedenti (fallisce se la cancellazione fallisce);
#  2. lancia mvn -B verify in un'immagine Maven ufficiale (JDK 21, versione fissata), con
#     accesso al Docker dell'host per i test di integrazione (Testcontainers);
#  3. controlla che il test di integrazione PostgreSQL sia stato eseguito e non saltato;
#  4. controlla che online e batch abbiano esattamente un jar eseguibile (*-exec.jar);
#  5. alla fine, riuscita o no, anche se interrotta, rimuove il container di build e i
#     container avviati dai test di questa corsa (etichetta menb.verify.run) e verifica che
#     non ne resti nessuno.
# Non avvia alcun processo applicativo: l'avvio reale dello stack e' compito di ./smoke.sh.
# Variabili opzionali: MENB_BUILD_CACHE_VOLUME (volume Docker con la cache Maven),
# MENB_VERIFY_TIMEOUT (secondi, limite dell'intero container di build; predefinito 1800).
set -euo pipefail

IMAGE="maven:3.9.16-eclipse-temurin-21"
CACHE_VOLUME="${MENB_BUILD_CACHE_VOLUME:-menb-build-m2}"
VERIFY_TIMEOUT="${MENB_VERIFY_TIMEOUT:-1800}"
SHORT_TIMEOUT=60
# Socket del daemon Docker: la sorgente di un montaggio e' risolta dal daemon, quindi e' il
# suo socket (su Docker Desktop il percorso e' gestito in modo speciale e porta alla VM).
DOCKER_SOCKET="/var/run/docker.sock"
RUN_LABEL_KEY="menb.verify.run"
# Cartella dello script senza comandi esterni (niente dirname), con esito controllato.
case "${BASH_SOURCE[0]}" in
  */*) ROOT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) ROOT_DIR="." ;;
esac
ROOT="$(cd "${ROOT_DIR}" && pwd)" || { echo "ERRORE: cartella dello script non raggiungibile" >&2; exit 1; }
[ -f "${ROOT}/pom.xml" ] || { echo "ERRORE: ${ROOT}/pom.xml non trovato" >&2; exit 1; }
[ -f "${ROOT}/quality/limite.sh" ] || { echo "ERRORE: ${ROOT}/quality/limite.sh non trovato" >&2; exit 1; }
# shellcheck source=quality/limite.sh
. "${ROOT}/quality/limite.sh" || { echo "ERRORE: caricamento di quality/limite.sh fallito" >&2; exit 1; }
check_seconds MENB_VERIFY_TIMEOUT "${VERIFY_TIMEOUT}" || exit 1
# Utente dell'host a cui restituire le cartelle target/: esito di id controllato e valore
# numerico, altrimenti chown riceverebbe un utente vuoto e non cambierebbe nulla.
HOST_UID="$(id -u)" || { echo "ERRORE: id -u fallito" >&2; exit 1; }
HOST_GID="$(id -g)" || { echo "ERRORE: id -g fallito" >&2; exit 1; }
for value in "${HOST_UID}" "${HOST_GID}"; do
  case "${value}" in
    '' | *[!0-9]*) echo "ERRORE: utente dell'host non numerico: '${HOST_UID}:${HOST_GID}'" >&2; exit 1 ;;
  esac
done

# Identificativo di questa corsa: nome del container di build ed etichetta dei container
# avviati dai test. Unico per corsa, quindi i residui di altre corse (o di altri) non contano.
RUN_ID="verify-$$-${RANDOM}${RANDOM}"
BUILD_CONTAINER="menb-build-${RUN_ID}"
RUN_LABEL="${RUN_LABEL_KEY}=${RUN_ID}"

# Controlla che ogni riga di $1 sia un identificativo completo di container (formato di Docker).
valid_ids() {
  local line
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    [[ "${line}" =~ ^[0-9a-f]{64}$ ]] || return 1
  done <<EOF
$1
EOF
  return 0
}

# Acquisisce in LISTED gli id grezzi dei container (anche arrestati) che soddisfano il filtro
# $1. Va chiamata nella shell corrente. Restituisce 1, lasciando LISTED a "<ignoto>", se
# l'elenco non si ottiene o non ha il formato atteso: l'assenza non e' provata.
LISTED="<ignoto>"
list_containers() {
  local out
  LISTED="<ignoto>"
  if ! out="$(limited "${SHORT_TIMEOUT}" docker ps -a -q --no-trunc --filter "$1" </dev/null)"; then
    echo "ERRORE: elenco dei container con il filtro $1 fallito" >&2
    return 1
  fi
  if ! valid_ids "${out}"; then
    echo "ERRORE: risposta inattesa di Docker nell'elenco dei container ($1): '${out}'" >&2
    return 1
  fi
  LISTED="${out}"
  return 0
}

# Rimuove i container dell'ultima acquisizione. Riporta gli esiti; decide la nuova acquisizione.
remove_listed() {
  local id
  while IFS= read -r id; do
    [ -n "${id}" ] || continue
    printf '  container %s\n' "${id}" >&2
    limited "${SHORT_TIMEOUT}" docker rm -f -v "${id}" </dev/null >/dev/null || echo "ERRORE: rimozione del container ${id} fallita" >&2
  done <<EOF
${LISTED}
EOF
  return 0
}

# Prima il container di build (se e' ancora vivo potrebbe avviare altri container di test),
# poi i container con l'etichetta della corsa. Restituisce 0 solo se gli elenchi si ottengono
# e sono vuoti; se trova qualcosa lo rimuove e restituisce comunque 1.
cleanup_run() {
  local rc=0 filter what
  for filter in "name=^${BUILD_CONTAINER}\$" "label=${RUN_LABEL}"; do
    case "${filter}" in
      name=*) what="container di build ${BUILD_CONTAINER}" ;;
      *) what="container di test con l'etichetta ${RUN_LABEL}" ;;
    esac
    if ! list_containers "${filter}"; then
      echo "ERRORE: impossibile verificare l'assenza di ${what}" >&2
      rc=1
      continue
    fi
    [ -n "${LISTED}" ] || continue
    rc=1
    echo "ERRORE: ${what} ancora presenti, rimozione:" >&2
    remove_listed
    if ! list_containers "${filter}"; then
      echo "ERRORE: impossibile verificare la rimozione di ${what}" >&2
    elif [ -n "${LISTED}" ]; then
      echo "ERRORE: ${what} ancora presenti dopo la rimozione, da rimuovere a mano" >&2
    else
      echo "   rimozione riuscita" >&2
    fi
  done
  if [ "${rc}" -eq 0 ]; then
    echo "== nessun container di test (${RUN_LABEL}) ne' di build rimasto"
  fi
  return "${rc}"
}

CLEANUP_ARMED=0
on_exit() {
  local rc=$?
  trap - EXIT HUP INT TERM
  # Interrotta durante il container di build: lo si ferma prima della pulizia.
  stop_limited
  if [ "${CLEANUP_ARMED}" -eq 1 ]; then
    echo "== pulizia dei container della corsa ${RUN_ID}"
    if ! cleanup_run; then
      [ "${rc}" -ne 0 ] || rc=1
    fi
  fi
  if [ "${rc}" -eq 0 ]; then
    echo "== verifica completata"
  else
    echo "== VERIFICA FALLITA (codice ${rc})" >&2
  fi
  exit "${rc}"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Il contenitore gira come root: a fine corsa restituisce all'utente dell'host solo le
# cartelle target/ generate (non .git, ne' i sorgenti, ne' legacy/).
# Accesso a Docker dai test: socket del daemon montato; le porte dei container avviati dai
# test (fratelli, non figli) si raggiungono da host.docker.internal, che punta all'host sia su
# Docker Desktop sia su Linux (host-gateway). Ryuk e' disattivato: la pulizia la fa questo
# script, per etichetta, in on_exit.
CLEANUP_ARMED=1
rc=0
limited "${VERIFY_TIMEOUT}" docker run --rm -i \
  --name "${BUILD_CONTAINER}" \
  -v "${CACHE_VOLUME}:/root/.m2" \
  -v "${ROOT}:/workspace" \
  -v "${DOCKER_SOCKET}:${DOCKER_SOCKET}" \
  --add-host "host.docker.internal:host-gateway" \
  -w /workspace \
  -e HOST_UID="${HOST_UID}" -e HOST_GID="${HOST_GID}" \
  -e TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal \
  -e TESTCONTAINERS_RYUK_DISABLED=true \
  -e MENB_VERIFY_RUN_ID="${RUN_ID}" \
  "${IMAGE}" bash -s <<'CONTAINER' || rc=$?
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

echo "== [1/3] pulizia degli output precedenti e mvn -B verify"
rm -rf carddemo-*/target || { echo "ERRORE: cancellazione dei target/ precedenti fallita" >&2; exit 1; }
residui=(carddemo-*/target)
if [ "${#residui[@]}" -ne 0 ]; then
  echo "ERRORE: output precedenti ancora presenti dopo la cancellazione: ${residui[*]}" >&2
  exit 1
fi
mvn -B verify </dev/null || { echo "ERRORE: mvn verify fallito" >&2; exit 1; }

# Il rapporto di surefire esiste solo se il test e' stato eseguito da questa build (i target/
# sono stati cancellati): almeno un test, nessuno saltato, fallito o in errore.
echo "== [2/3] controllo del test di integrazione"
report="carddemo-parity/target/surefire-reports/TEST-io.github.ltoscano.carddemo.parity.PostgresIntegrazioneTest.xml"
if [ ! -f "${report}" ]; then
  echo "ERRORE: rapporto del test di integrazione assente: ${report}" >&2
  exit 1
fi
if ! content="$(<"${report}")"; then
  echo "ERRORE: lettura di ${report} fallita" >&2
  exit 1
fi
re_suite='<testsuite[[:space:]][^>]*>'
if ! [[ "${content}" =~ ${re_suite} ]]; then
  echo "ERRORE: elemento testsuite non trovato in ${report}" >&2
  exit 1
fi
suite="${BASH_REMATCH[0]}"
summary=""
for attr in tests skipped failures errors; do
  re="[[:space:]]${attr}=\"([0-9]+)\""
  if ! [[ "${suite}" =~ ${re} ]]; then
    echo "ERRORE: attributo ${attr} assente o non numerico in ${report}" >&2
    exit 1
  fi
  value="${BASH_REMATCH[1]}"
  summary="${summary} ${attr}=${value}"
  case "${attr}" in
    tests) [ "${value}" -ge 1 ] || { echo "ERRORE: test di integrazione non eseguito (tests=${value})" >&2; exit 1; } ;;
    *) [ "${value}" -eq 0 ] || { echo "ERRORE: test di integrazione con ${attr}=${value} (atteso 0)" >&2; exit 1; } ;;
  esac
done
echo "PostgresIntegrazioneTest:${summary}"

# Dopo la pulizia puo' esistere solo l'eseguibile prodotto da questa build: ne serve uno.
echo "== [3/3] controllo dei jar eseguibili"
for module in carddemo-online carddemo-batch; do
  jars=("${module}"/target/*-exec.jar)
  if [ "${#jars[@]}" -ne 1 ]; then
    echo "ERRORE: attesi esattamente 1 jar eseguibile in ${module}/target, trovati ${#jars[@]}" >&2
    exit 1
  fi
  echo "${module}: ${jars[0]}"
done
echo "== build e controlli nel container completati"
CONTAINER
if [ "${rc}" -ne 0 ]; then
  echo "ERRORE: container di build terminato con codice ${rc}" >&2
  exit "${rc}"
fi
