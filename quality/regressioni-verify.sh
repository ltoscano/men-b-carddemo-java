#!/usr/bin/env bash
# Regressioni di ./verify.sh: per ogni caso applica una mutazione, esegue ./verify.sh con un
# limite di tempo, controlla codice di uscita e messaggio atteso, ripristina lo stato (anche
# se lo script fallisce o viene interrotto). Si esegue a richiesta; non fa parte di
# ./verify.sh ne' della CI obbligatoria.
#
# Casi:
#   0. base                  nessuna mutazione: ./verify.sh deve riuscire (altrimenti i casi
#                            negativi fallirebbero per la ragione sbagliata) e lasciare il jar
#                            eseguibile di online, che serve al caso 1
#   1. repackage-rimosso     blocco <build> tolto dal POM di online, con il jar eseguibile della
#                            corsa precedente (la base) presente
#   2. test-rotto            un test che fallisce in carddemo-domain
#   3. id-fallisce           `id` sul PATH che esce con 42
#   4. docker-fallisce       `docker` sul PATH che esce con 42
#   5. docker-irraggiungibile `docker` sul PATH che inoltra tutto al vero docker ma toglie il
#                            montaggio del socket dal container di build: Docker funziona
#                            sull'host, non dentro Maven
# Non si provano strumenti che restituiscono dati falsi ma ben formati (CLAUDE.md, "Fin dove
# arriva la sfiducia negli script").
#
# Prerequisiti: bash, git, Docker. Albero di lavoro pulito (git status vuoto) all'avvio.
# Variabili opzionali: MENB_REGRESSIONI_TIMEOUT (secondi per ogni ./verify.sh, predefinito 1800);
# MENB_REGRESSIONI_LOGS (cartella esistente in cui conservare il log di ogni caso, <caso>.log;
# senza, i log stanno in una cartella temporanea cancellata alla fine).
# Esce con 0 solo se tutti i casi danno l'esito atteso e alla fine git status e' pulito.
set -euo pipefail

case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) SCRIPT_DIR="." ;;
esac
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)" || { echo "ERRORE: radice del repository non raggiungibile" >&2; exit 1; }
[ -f "${ROOT}/verify.sh" ] || { echo "ERRORE: ${ROOT}/verify.sh non trovato" >&2; exit 1; }
# shellcheck source=quality/limite.sh
. "${ROOT}/quality/limite.sh" || { echo "ERRORE: caricamento di quality/limite.sh fallito" >&2; exit 1; }
CASE_TIMEOUT="${MENB_REGRESSIONI_TIMEOUT:-1800}"
check_seconds MENB_REGRESSIONI_TIMEOUT "${CASE_TIMEOUT}" || exit 1

ONLINE_POM="carddemo-online/pom.xml"
BROKEN_TEST="carddemo-domain/src/test/java/io/github/ltoscano/carddemo/domain/RegressioneTestRottoTest.java"

# Stato dell'albero: deve essere pulito prima e dopo.
git_clean() {
  local out
  if ! out="$(git -C "${ROOT}" status --porcelain --untracked-files=all </dev/null)"; then
    echo "ERRORE: git status fallito" >&2
    return 2
  fi
  if [ -n "${out}" ]; then
    printf '%s\n' "${out}" >&2
    return 1
  fi
  return 0
}
if ! git_clean; then
  echo "ERRORE: l'albero di lavoro non e' pulito (vedi sopra): impossibile garantire il ripristino" >&2
  exit 1
fi
REAL_DOCKER="$(command -v docker)" || { echo "ERRORE: docker non trovato sul PATH" >&2; exit 1; }
case "${REAL_DOCKER}" in
  /*) ;;
  *) echo "ERRORE: percorso di docker non assoluto: '${REAL_DOCKER}'" >&2; exit 1 ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/menb-regressioni.XXXXXX")" || { echo "ERRORE: mktemp fallito" >&2; exit 1; }
[ -n "${WORK}" ] && [ -d "${WORK}" ] || { echo "ERRORE: cartella temporanea non valida: '${WORK}'" >&2; exit 1; }
cp "${ROOT}/${ONLINE_POM}" "${WORK}/online-pom.orig" || { echo "ERRORE: copia di ${ONLINE_POM} fallita" >&2; exit 1; }
LOG_DIR="${MENB_REGRESSIONI_LOGS:-${WORK}}"
[ -d "${LOG_DIR}" ] || { echo "ERRORE: MENB_REGRESSIONI_LOGS non e' una cartella esistente: '${LOG_DIR}'" >&2; rm -rf "${WORK}"; exit 1; }

# Ripristino: POM di online dalla copia, test rotto cancellato. Idempotente.
restore() {
  local rc=0
  if ! cp "${WORK}/online-pom.orig" "${ROOT}/${ONLINE_POM}"; then
    echo "ERRORE: ripristino di ${ONLINE_POM} fallito" >&2
    rc=1
  fi
  if [ -e "${ROOT}/${BROKEN_TEST}" ] && ! rm -f "${ROOT}/${BROKEN_TEST}"; then
    echo "ERRORE: cancellazione di ${BROKEN_TEST} fallita" >&2
    rc=1
  fi
  return "${rc}"
}

on_exit() {
  local rc=$?
  trap - EXIT HUP INT TERM
  stop_limited
  if ! restore; then
    [ "${rc}" -ne 0 ] || rc=1
  fi
  if ! git_clean; then
    echo "ERRORE: dopo il ripristino git status non e' pulito (vedi sopra)" >&2
    [ "${rc}" -ne 0 ] || rc=1
  else
    echo "== git status pulito"
  fi
  if ! rm -rf "${WORK}"; then
    echo "ERRORE: cancellazione di ${WORK} fallita" >&2
    [ "${rc}" -ne 0 ] || rc=1
  fi
  if [ "${rc}" -eq 0 ]; then
    echo "== REGRESSIONI RIUSCITE: tutti i casi rilevati"
  else
    echo "== REGRESSIONI FALLITE (codice ${rc})" >&2
  fi
  exit "${rc}"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# run_verify <caso> [PATH alternativo]: esegue ./verify.sh con limite di tempo, output in
# ${LOG_DIR}/<caso>.log (riscritto a ogni corsa). Imposta RUN_RC, RUN_SECONDS e RUN_LOG (contenuto del log).
RUN_RC=0
RUN_SECONDS=0
RUN_LOG=""
run_verify() {
  local name="$1" path="${2:-${PATH}}" started
  local log="${LOG_DIR}/${name}.log"
  started="${SECONDS}"
  RUN_RC=0
  limited "${CASE_TIMEOUT}" env PATH="${path}" "${ROOT}/verify.sh" </dev/null >"${log}" 2>&1 || RUN_RC=$?
  RUN_SECONDS=$((SECONDS - started))
  if ! RUN_LOG="$(<"${log}")"; then
    echo "ERRORE [${name}]: lettura del log ${log} fallita" >&2
    return 1
  fi
  return 0
}

# Ultime righe del log, per chi legge (solo presentazione, con builtin).
show_tail() {
  local lines=() line i start
  while IFS= read -r line; do lines+=("${line}"); done <<EOF
${RUN_LOG}
EOF
  start=$(( ${#lines[@]} > 15 ? ${#lines[@]} - 15 : 0 ))
  for ((i = start; i < ${#lines[@]}; i++)); do printf '     | %s\n' "${lines[i]}"; done
  return 0
}

FAILED=""
# expect <caso> <esito: ok|ko> <messaggio atteso>...: decide su RUN_RC e RUN_LOG.
expect() {
  local name="$1" want="$2" msg missing=""
  shift 2
  for msg in "$@"; do
    case "${RUN_LOG}" in
      *"${msg}"*) ;;
      *) missing="${missing} [${msg}]" ;;
    esac
  done
  local verdict="rilevato"
  if [ "${RUN_RC}" -eq 124 ]; then
    verdict="NON RILEVATO: superato il limite di ${CASE_TIMEOUT}s"
  elif [ "${want}" = "ok" ] && [ "${RUN_RC}" -ne 0 ]; then
    verdict="NON RIUSCITO: codice ${RUN_RC}, atteso 0"
  elif [ "${want}" = "ko" ] && [ "${RUN_RC}" -eq 0 ]; then
    verdict="NON RILEVATO: codice 0"
  elif [ -n "${missing}" ]; then
    verdict="NON RILEVATO: messaggio atteso assente:${missing}"
  elif [ "${want}" = "ok" ]; then
    verdict="riuscito"
  fi
  printf '== [%s] codice %s, %ss: %s\n' "${name}" "${RUN_RC}" "${RUN_SECONDS}" "${verdict}"
  case "${verdict}" in
    rilevato | riuscito) ;;
    *)
      show_tail
      FAILED="${FAILED} ${name}"
      ;;
  esac
  return 0
}

# Shim: script messi in testa al PATH solo per un caso.
make_shim() {
  local dir="$1" name="$2" body="$3"
  mkdir -p "${dir}" || { echo "ERRORE: mkdir ${dir} fallito" >&2; return 1; }
  printf '#!/usr/bin/env bash\n%s\n' "${body}" >"${dir}/${name}" || { echo "ERRORE: scrittura dello shim ${name} fallita" >&2; return 1; }
  chmod +x "${dir}/${name}" || { echo "ERRORE: chmod dello shim ${name} fallito" >&2; return 1; }
  return 0
}

# --- 0. base ------------------------------------------------------------------------------
echo "== [base] ./verify.sh senza mutazioni (limite ${CASE_TIMEOUT}s)"
run_verify base || exit 1
expect base ok "Tests run: 1, Failures: 0, Errors: 0, Skipped: 0" \
  "PostgresIntegrazioneTest: tests=1 skipped=0 failures=0 errors=0" "== verifica completata"
if [ -n "${FAILED}" ]; then
  echo "ERRORE: la corsa di base non riesce: i casi negativi non sarebbero significativi" >&2
  exit 1
fi

# --- 1. repackage rimosso, jar della corsa base presente ----------------------------------
echo "== [repackage-rimosso] mutazione: blocco <build> tolto da ${ONLINE_POM}"
shopt -s nullglob
old_jars=("${ROOT}"/carddemo-online/target/*-exec.jar)
shopt -u nullglob
if [ "${#old_jars[@]}" -ne 1 ]; then
  echo "ERRORE: precondizione non valida: attesi 1 jar eseguibile di online della corsa di base, trovati ${#old_jars[@]}" >&2
  exit 1
fi
echo "   jar della corsa precedente presente: ${old_jars[0]#"${ROOT}"/}"
pom="$(<"${ROOT}/${ONLINE_POM}")" || { echo "ERRORE: lettura di ${ONLINE_POM} fallita" >&2; exit 1; }
case "${pom}" in
  *"<build>"*"</build>"*) ;;
  *) echo "ERRORE: blocco <build> non trovato in ${ONLINE_POM}: mutazione non applicabile" >&2; exit 1 ;;
esac
printf '%s%s\n' "${pom%%<build>*}" "${pom#*</build>}" >"${ROOT}/${ONLINE_POM}" \
  || { echo "ERRORE: scrittura di ${ONLINE_POM} fallita" >&2; exit 1; }
run_verify repackage-rimosso || exit 1
expect repackage-rimosso ko "ERRORE: attesi esattamente 1 jar eseguibile in carddemo-online/target, trovati 0"
restore || exit 1

# --- 2. test rotto ------------------------------------------------------------------------
echo "== [test-rotto] mutazione: ${BROKEN_TEST}"
[ ! -e "${ROOT}/${BROKEN_TEST}" ] || { echo "ERRORE: ${BROKEN_TEST} esiste gia'" >&2; exit 1; }
cat >"${ROOT}/${BROKEN_TEST}" <<'JAVA' || { echo "ERRORE: scrittura del test rotto fallita" >&2; exit 1; }
package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.fail;

import org.junit.jupiter.api.Test;

class RegressioneTestRottoTest {

    @Test
    void fallisce() {
        fail("test rotto di proposito da quality/regressioni-verify.sh");
    }
}
JAVA
run_verify test-rotto || exit 1
expect test-rotto ko "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.RegressioneTestRottoTest" "test rotto di proposito" "ERRORE: mvn verify fallito"
restore || exit 1

# --- 3. id che fallisce -------------------------------------------------------------------
echo "== [id-fallisce] shim: id esce con 42"
make_shim "${WORK}/shim-id" id 'echo "SHIM: id fallisce (42)" >&2; exit 42' || exit 1
run_verify id-fallisce "${WORK}/shim-id:${PATH}" || exit 1
expect id-fallisce ko "SHIM: id fallisce (42)" "ERRORE: id -u fallito"

# --- 4. docker che fallisce ---------------------------------------------------------------
echo "== [docker-fallisce] shim: docker esce con 42"
make_shim "${WORK}/shim-docker" docker 'echo "SHIM: docker fallisce (42)" >&2; exit 42' || exit 1
run_verify docker-fallisce "${WORK}/shim-docker:${PATH}" || exit 1
expect docker-fallisce ko "SHIM: docker fallisce (42)" "ERRORE: container di build terminato con codice 42" \
  "== VERIFICA FALLITA (codice 42)"

# --- 5. Docker non raggiungibile dentro Maven ---------------------------------------------
# Lo shim inoltra al vero docker; nel solo "docker run" toglie "-v <socket>:<socket>" e lo
# registra in un file: se il montaggio non viene trovato la mutazione non e' applicata e il
# caso fallisce (un verify.sh cambiato non puo' far passare il caso per la ragione sbagliata).
echo "== [docker-irraggiungibile] shim: docker run senza il socket di Docker"
marker="${WORK}/socket-tolto"
make_shim "${WORK}/shim-nosocket" docker "real='${REAL_DOCKER}'
marker='${marker}'
if [ \"\${1:-}\" = run ]; then
  args=()
  prev=''
  for a in \"\$@\"; do
    if [ \"\${prev}\" = -v ] && [ \"\${a}\" = /var/run/docker.sock:/var/run/docker.sock ]; then
      unset 'args[\${#args[@]}-1]'
      : >\"\${marker}\" || exit 99
      prev=''
      continue
    fi
    args+=(\"\${a}\")
    prev=\"\${a}\"
  done
  exec \"\${real}\" \"\${args[@]}\"
fi
exec \"\${real}\" \"\$@\"" || exit 1
run_verify docker-irraggiungibile "${WORK}/shim-nosocket:${PATH}" || exit 1
if [ ! -e "${marker}" ]; then
  echo "ERRORE [docker-irraggiungibile]: il montaggio del socket non e' stato trovato nel docker run: mutazione non applicata" >&2
  FAILED="${FAILED} docker-irraggiungibile"
else
  expect docker-irraggiungibile ko "Could not find a valid Docker environment" \
    "<<< FAILURE! -- in io.github.ltoscano.carddemo.parity.PostgresIntegrazioneTest" "ERRORE: mvn verify fallito"
fi

if [ -n "${FAILED}" ]; then
  echo "ERRORE: casi non rilevati:${FAILED}" >&2
  exit 1
fi
