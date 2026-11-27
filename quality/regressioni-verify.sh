#!/usr/bin/env bash
# Regressioni di ./verify.sh: per ogni caso applica una mutazione, esegue ./verify.sh con un
# limite di tempo, controlla codice di uscita e messaggio atteso, ripristina lo stato (anche
# se lo script fallisce o viene interrotto). Si esegue a richiesta; non fa parte di
# ./verify.sh ne' della CI obbligatoria.
#
# Casi:
#   0. base                   nessuna mutazione: ./verify.sh deve riuscire (altrimenti i casi
#                             negativi fallirebbero per la ragione sbagliata); ne conserva il
#                             rapporto del test di integrazione e il jar eseguibile di online
#   1. repackage-rimosso      blocco <build> tolto dal POM di online, con il jar eseguibile della
#                             corsa precedente (la base) presente
#   2. rapporto-incompleto    dentro il container di build, dopo il vero Maven, il rapporto del
#                             test di integrazione viene troncato a meta'
#   3. rapporto-altra-corsa   dentro il container di build, dopo il vero Maven, il rapporto viene
#                             sostituito da quello completo della corsa di base
#   4. test-rotto             un test che fallisce in carddemo-domain
#   5. id-fallisce            `id` sul PATH che esce con 42
#   6. id-bloccato            `id` sul PATH che non ritorna: ./verify.sh deve fallire entro il
#                             suo limite per i comandi brevi (MENB_VERIFY_SHORT_TIMEOUT=5)
#   7. docker-fallisce        `docker` sul PATH che esce con 42
#   8. docker-irraggiungibile `docker` sul PATH che inoltra tutto al vero docker ma toglie il
#                             montaggio del socket dal container di build: Docker funziona
#                             sull'host, non dentro Maven
#   9. git-bloccato           questo stesso script, con `git` sul PATH che non ritorna: deve
#                             fallire entro il suo limite per i comandi brevi
# Nei casi 2, 3, 8 lo shim registra di aver applicato la mutazione: se non lo ha fatto, il caso
# fallisce. Non si provano strumenti che restituiscono dati falsi ma ben formati (CLAUDE.md,
# "Fin dove arriva la sfiducia negli script").
#
# Prerequisiti: bash, git, Docker. Albero di lavoro pulito (git status vuoto) all'avvio.
# Variabili opzionali: MENB_REGRESSIONI_TIMEOUT (secondi per ogni ./verify.sh, predefinito 1800);
# MENB_REGRESSIONI_SHORT_TIMEOUT (secondi per ogni altro comando esterno, predefinito 60);
# MENB_REGRESSIONI_LOGS (cartella esistente in cui conservare il log di ogni caso, <caso>.log;
# senza, i log stanno nella cartella di lavoro temporanea, cancellata alla fine).
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
SHORT_TIMEOUT="${MENB_REGRESSIONI_SHORT_TIMEOUT:-60}"
check_seconds MENB_REGRESSIONI_TIMEOUT "${CASE_TIMEOUT}" || exit 1
check_seconds MENB_REGRESSIONI_SHORT_TIMEOUT "${SHORT_TIMEOUT}" || exit 1
# Limite dei casi che devono fallire presto (comandi bloccati): ben sopra i 5 s dei limiti
# brevi passati agli script, ben sotto il limite di una build.
QUICK_CASE_TIMEOUT=90

ONLINE_POM="carddemo-online/pom.xml"
BROKEN_TEST="carddemo-domain/src/test/java/io/github/ltoscano/carddemo/domain/RegressioneTestRottoTest.java"
IT_REPORT="carddemo-parity/target/surefire-reports/TEST-io.github.ltoscano.carddemo.parity.PostgresIntegrazioneTest.xml"
REAL_DOCKER="$(command -v docker)" || { echo "ERRORE: docker non trovato sul PATH" >&2; exit 1; }
case "${REAL_DOCKER}" in
  /*) ;;
  *) echo "ERRORE: percorso di docker non assoluto: '${REAL_DOCKER}'" >&2; exit 1 ;;
esac

# Cartella di lavoro: nome unico, creata con mkdir (che fallisce se esiste gia') sotto limite.
TMP_BASE="${TMPDIR:-/tmp}"
WORK="${TMP_BASE%/}/menb-regressioni-$$-${RANDOM}${RANDOM}"
limited "${SHORT_TIMEOUT}" mkdir -m 700 "${WORK}" </dev/null || { echo "ERRORE: creazione di ${WORK} fallita" >&2; exit 1; }
LOG_DIR="${MENB_REGRESSIONI_LOGS:-${WORK}}"
HANG_PIDS="${WORK}/pid-appesi"

# Ripristino: POM di online dalla copia (se gia' fatta), test rotto cancellato. Idempotente.
restore() {
  local rc=0
  if [ -f "${WORK}/online-pom.orig" ] && ! limited "${SHORT_TIMEOUT}" cp "${WORK}/online-pom.orig" "${ROOT}/${ONLINE_POM}" </dev/null; then
    echo "ERRORE: ripristino di ${ONLINE_POM} fallito" >&2
    rc=1
  fi
  if [ -e "${ROOT}/${BROKEN_TEST}" ] && ! limited "${SHORT_TIMEOUT}" rm -f "${ROOT}/${BROKEN_TEST}" </dev/null; then
    echo "ERRORE: cancellazione di ${BROKEN_TEST} fallita" >&2
    rc=1
  fi
  return "${rc}"
}

# Ferma i processi lasciati in vita dagli shim che non ritornano (pid registrati dagli shim).
kill_hung() {
  local pid
  [ -f "${HANG_PIDS}" ] || return 0
  while IFS= read -r pid; do
    case "${pid}" in '' | *[!0-9]*) continue ;; esac
    kill -TERM "${pid}" 2>/dev/null || true
  done <"${HANG_PIDS}"
  return 0
}

# Stato dell'albero: deve essere pulito prima e dopo. 0 pulito, 1 sporco, 2 git fallito.
git_clean() {
  if ! limited_out "${WORK}/git-status.out" "${SHORT_TIMEOUT}" git -C "${ROOT}" status --porcelain --untracked-files=all </dev/null; then
    echo "ERRORE: git status fallito" >&2
    return 2
  fi
  if [ -n "${LIMITED_OUT}" ]; then
    printf '%s\n' "${LIMITED_OUT}" >&2
    return 1
  fi
  return 0
}

on_exit() {
  local rc=$?
  trap - EXIT HUP INT TERM
  stop_limited
  kill_hung
  if ! restore; then
    [ "${rc}" -ne 0 ] || rc=1
  fi
  if ! git_clean; then
    echo "ERRORE: dopo il ripristino git status non e' pulito o non verificabile (vedi sopra)" >&2
    [ "${rc}" -ne 0 ] || rc=1
  else
    echo "== git status pulito"
  fi
  if ! limited "${SHORT_TIMEOUT}" rm -rf "${WORK}" </dev/null; then
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

[ -d "${LOG_DIR}" ] || { echo "ERRORE: MENB_REGRESSIONI_LOGS non e' una cartella esistente: '${LOG_DIR}'" >&2; exit 1; }
if ! git_clean; then
  echo "ERRORE: l'albero di lavoro non e' pulito o git non risponde (vedi sopra): impossibile garantire il ripristino" >&2
  exit 1
fi
limited "${SHORT_TIMEOUT}" cp "${ROOT}/${ONLINE_POM}" "${WORK}/online-pom.orig" </dev/null \
  || { echo "ERRORE: copia di ${ONLINE_POM} fallita" >&2; exit 1; }

# run_case <caso> <limite> <comando> [argomenti...]: esegue il comando con limite di tempo,
# output in ${LOG_DIR}/<caso>.log (riscritto a ogni corsa). Imposta RUN_RC, RUN_SECONDS,
# RUN_LIMIT e RUN_LOG (contenuto del log).
RUN_RC=0
RUN_SECONDS=0
RUN_LIMIT=0
RUN_LOG=""
run_case() {
  local name="$1" limit="$2" started
  shift 2
  local log="${LOG_DIR}/${name}.log"
  started="${SECONDS}"
  RUN_RC=0
  RUN_LIMIT="${limit}"
  limited "${limit}" "$@" </dev/null >"${log}" 2>&1 || RUN_RC=$?
  RUN_SECONDS=$((SECONDS - started))
  kill_hung
  if ! RUN_LOG="$(<"${log}")"; then
    echo "ERRORE [${name}]: lettura del log ${log} fallita" >&2
    return 1
  fi
  return 0
}

# run_verify <caso> [PATH alternativo]: ./verify.sh con il limite di una build.
run_verify() {
  run_case "$1" "${CASE_TIMEOUT}" env PATH="${2:-${PATH}}" "${ROOT}/verify.sh"
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
    verdict="NON RILEVATO: superato il limite di ${RUN_LIMIT}s"
  elif [ "${want}" = "ok" ] && [ "${RUN_RC}" -ne 0 ]; then
    verdict="NON RIUSCITO: codice ${RUN_RC}, atteso 0"
  elif [ "${want}" = "ko" ] && [ "${RUN_RC}" -eq 0 ]; then
    verdict="NON RILEVATO: codice 0"
  elif [ -n "${missing}" ]; then
    verdict="NON RILEVATO: messaggio atteso assente:${missing}"
  elif [ "${want}" = "ok" ]; then
    verdict="riuscito"
  fi
  printf '== [%s] codice %s, %ss (limite %ss): %s\n' "${name}" "${RUN_RC}" "${RUN_SECONDS}" "${RUN_LIMIT}" "${verdict}"
  case "${verdict}" in
    rilevato | riuscito) ;;
    *)
      show_tail
      FAILED="${FAILED} ${name}"
      ;;
  esac
  return 0
}

# expect_marker <caso> <file>: lo shim deve aver registrato la mutazione, altrimenti il caso
# non dimostra nulla e fallisce. Restituisce 1 se il file manca.
expect_marker() {
  if [ ! -e "$2" ]; then
    echo "ERRORE [$1]: lo shim non ha applicato la mutazione (manca ${2##*/})" >&2
    FAILED="${FAILED} $1"
    return 1
  fi
  return 0
}

# Shim: script messi in testa al PATH solo per un caso.
make_shim() {
  local dir="$1" name="$2" body="$3"
  limited "${SHORT_TIMEOUT}" mkdir -p "${dir}" </dev/null || { echo "ERRORE: mkdir ${dir} fallito" >&2; return 1; }
  printf '#!/usr/bin/env bash\n%s\n' "${body}" >"${dir}/${name}" || { echo "ERRORE: scrittura dello shim ${name} fallita" >&2; return 1; }
  limited "${SHORT_TIMEOUT}" chmod +x "${dir}/${name}" </dev/null || { echo "ERRORE: chmod dello shim ${name} fallito" >&2; return 1; }
  return 0
}

# Corpo di uno shim che non ritorna: un processo figlio che dura un'ora (registrato, per
# fermarlo dopo il caso) e l'attesa della sua fine. Il figlio eredita lo standard output.
hang_body() {
  printf 'sleep 3600 &\necho "$!" >>%q\nwait\n' "${HANG_PIDS}"
}

# Shim di docker che, nel solo "docker run", monta <cartella> in /menb-shim e mette
# /menb-shim/bin in testa al PATH del container: li' c'e' un mvn che esegue il vero Maven e poi
# altera il rapporto del test di integrazione. Il PATH e' quello dell'immagine Maven.
docker_mvn_shim_body() {
  printf "real=%q\nshim=%q\n" "${REAL_DOCKER}" "$1"
  printf '%s\n' \
    'if [ "${1:-}" = run ]; then' \
    '  shift' \
    '  exec "${real}" run -v "${shim}:/menb-shim" \' \
    '    -e PATH=/menb-shim/bin:/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"' \
    'fi' \
    'exec "${real}" "$@"'
}

# mvn per il container: vero Maven, poi l'alterazione $1 del rapporto, poi il marcatore.
mvn_shim_body() {
  printf 'r=%q\n' "${IT_REPORT}"
  printf '/usr/share/maven/bin/mvn "$@" || exit $?\n'
  printf '[ -f "$r" ] || { echo "SHIM: rapporto assente" >&2; exit 97; }\n'
  printf '%s || { echo "SHIM: alterazione del rapporto fallita" >&2; exit 96; }\n' "$1"
  printf ': >/menb-shim/mvn-eseguito || exit 98\n'
}

# --- 0. base ------------------------------------------------------------------------------
echo "== [base] ./verify.sh senza mutazioni (limite ${CASE_TIMEOUT}s)"
run_verify base || exit 1
expect base ok "Tests run: 1, Failures: 0, Errors: 0, Skipped: 0" \
  "PostgresIntegrazioneTest.avviaLImmagineDiComposeScriveRileggeEdElimina: eseguito e riuscito" "== verifica completata"
if [ -n "${FAILED}" ]; then
  echo "ERRORE: la corsa di base non riesce: i casi negativi non sarebbero significativi" >&2
  exit 1
fi
limited "${SHORT_TIMEOUT}" cp "${ROOT}/${IT_REPORT}" "${WORK}/rapporto-base.xml" </dev/null \
  || { echo "ERRORE: copia del rapporto della corsa di base fallita" >&2; exit 1; }

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

# --- 2. rapporto incompleto ---------------------------------------------------------------
echo "== [rapporto-incompleto] shim: dopo il vero Maven il rapporto del test di integrazione e' troncato a meta'"
shim="${WORK}/shim-incompleto"
make_shim "${shim}/bin" mvn "$(mvn_shim_body 'c="$(<"$r")" && printf "%s" "${c:0:$(( ${#c} / 2 ))}" >"$r"')" || exit 1
make_shim "${WORK}/shim-docker-incompleto" docker "$(docker_mvn_shim_body "${shim}")" || exit 1
run_verify rapporto-incompleto "${WORK}/shim-docker-incompleto:${PATH}" || exit 1
if expect_marker rapporto-incompleto "${shim}/mvn-eseguito"; then
  expect rapporto-incompleto ko "non e' XML ben formato e completo" \
    "ERRORE: rapporto del test di integrazione non valido"
fi

# --- 3. rapporto di un'altra corsa ---------------------------------------------------------
echo "== [rapporto-altra-corsa] shim: dopo il vero Maven il rapporto e' sostituito da quello completo della corsa di base"
shim="${WORK}/shim-altra-corsa"
make_shim "${shim}/bin" mvn "$(mvn_shim_body 'cp /menb-shim/rapporto-base.xml "$r"')" || exit 1
limited "${SHORT_TIMEOUT}" cp "${WORK}/rapporto-base.xml" "${shim}/rapporto-base.xml" </dev/null \
  || { echo "ERRORE: copia del rapporto di base fallita" >&2; exit 1; }
make_shim "${WORK}/shim-docker-altra-corsa" docker "$(docker_mvn_shim_body "${shim}")" || exit 1
run_verify rapporto-altra-corsa "${WORK}/shim-docker-altra-corsa:${PATH}" || exit 1
if expect_marker rapporto-altra-corsa "${shim}/mvn-eseguito"; then
  expect rapporto-altra-corsa ko "il rapporto non e' della corsa corrente" \
    "ERRORE: rapporto del test di integrazione non valido"
fi

# --- 4. test rotto ------------------------------------------------------------------------
echo "== [test-rotto] mutazione: ${BROKEN_TEST}"
[ ! -e "${ROOT}/${BROKEN_TEST}" ] || { echo "ERRORE: ${BROKEN_TEST} esiste gia'" >&2; exit 1; }
printf '%s\n' \
  'package io.github.ltoscano.carddemo.domain;' \
  '' \
  'import static org.junit.jupiter.api.Assertions.fail;' \
  '' \
  'import org.junit.jupiter.api.Test;' \
  '' \
  'class RegressioneTestRottoTest {' \
  '' \
  '    @Test' \
  '    void fallisce() {' \
  '        fail("test rotto di proposito da quality/regressioni-verify.sh");' \
  '    }' \
  '}' >"${ROOT}/${BROKEN_TEST}" || { echo "ERRORE: scrittura del test rotto fallita" >&2; exit 1; }
run_verify test-rotto || exit 1
expect test-rotto ko "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.RegressioneTestRottoTest" "test rotto di proposito" "ERRORE: mvn verify fallito"
restore || exit 1

# --- 5. id che fallisce -------------------------------------------------------------------
echo "== [id-fallisce] shim: id esce con 42"
make_shim "${WORK}/shim-id" id 'echo "SHIM: id fallisce (42)" >&2; exit 42' || exit 1
run_verify id-fallisce "${WORK}/shim-id:${PATH}" || exit 1
expect id-fallisce ko "SHIM: id fallisce (42)" "ERRORE: id -u fallito"

# --- 6. id che non ritorna ----------------------------------------------------------------
echo "== [id-bloccato] shim: id non ritorna; MENB_VERIFY_SHORT_TIMEOUT=5, limite del caso ${QUICK_CASE_TIMEOUT}s"
make_shim "${WORK}/shim-id-bloccato" id "$(hang_body)" || exit 1
run_case id-bloccato "${QUICK_CASE_TIMEOUT}" env PATH="${WORK}/shim-id-bloccato:${PATH}" MENB_VERIFY_SHORT_TIMEOUT=5 "${ROOT}/verify.sh" || exit 1
expect id-bloccato ko "ERRORE: superato il limite di 5s: id -u" "ERRORE: id -u fallito" "== VERIFICA FALLITA"

# --- 7. docker che fallisce ---------------------------------------------------------------
echo "== [docker-fallisce] shim: docker esce con 42"
make_shim "${WORK}/shim-docker" docker 'echo "SHIM: docker fallisce (42)" >&2; exit 42' || exit 1
run_verify docker-fallisce "${WORK}/shim-docker:${PATH}" || exit 1
expect docker-fallisce ko "SHIM: docker fallisce (42)" "ERRORE: container di build terminato con codice 42" \
  "== VERIFICA FALLITA (codice 42)"

# --- 8. Docker non raggiungibile dentro Maven ---------------------------------------------
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
if expect_marker docker-irraggiungibile "${marker}"; then
  expect docker-irraggiungibile ko "Could not find a valid Docker environment" \
    "<<< FAILURE! -- in io.github.ltoscano.carddemo.parity.PostgresIntegrazioneTest" "ERRORE: mvn verify fallito"
fi

# --- 9. git che non ritorna (questo script) -----------------------------------------------
echo "== [git-bloccato] shim: git non ritorna; questo script con MENB_REGRESSIONI_SHORT_TIMEOUT=5, limite del caso ${QUICK_CASE_TIMEOUT}s"
make_shim "${WORK}/shim-git-bloccato" git "$(hang_body)" || exit 1
run_case git-bloccato "${QUICK_CASE_TIMEOUT}" env -u MENB_REGRESSIONI_LOGS PATH="${WORK}/shim-git-bloccato:${PATH}" \
  MENB_REGRESSIONI_SHORT_TIMEOUT=5 "${ROOT}/quality/regressioni-verify.sh" || exit 1
expect git-bloccato ko "ERRORE: superato il limite di 5s: git -C" "ERRORE: git status fallito" "== REGRESSIONI FALLITE"

if [ -n "${FAILED}" ]; then
  echo "ERRORE: casi non rilevati:${FAILED}" >&2
  exit 1
fi
