# shellcheck shell=bash
# Limite di tempo per un comando esterno, senza `timeout` (assente su macOS).
# Da includere con `.` in verify.sh e quality/regressioni-verify.sh; stessa logica di
# `limited` in smoke.sh, che resta autonomo.
#
# limited <secondi> <comando esterno> [argomenti...]
# Allo scadere invia SIGTERM al comando, dopo altri 10 s SIGKILL. Restituisce il codice del
# comando, o 124 se il limite e' scaduto. Lo standard input del comando e' quello della
# funzione. LIMITED_PID e LIMITED_WD contengono i pid del comando e del suo guardiano mentre
# il comando e' in corso, perche' un trap possa fermarli.
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
    printf 'ERRORE: superato il limite di %ss: %s\n' "${limit}" "$*" >&2
    return 124
  fi
  return "${rc}"
}

# stop_limited: ferma il comando in corso di `limited` (TERM, poi KILL dopo 10 s) e il suo
# guardiano. Per i trap di uscita; non decide nulla, l'esito lo decide chi chiama.
stop_limited() {
  if [ -n "${LIMITED_PID}" ] && kill -0 "${LIMITED_PID}" 2>/dev/null; then
    printf 'ERRORE: arresto del comando in corso (pid %s)\n' "${LIMITED_PID}" >&2
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
  return 0
}

# check_seconds <nome> <valore>: valore intero positivo di secondi, altrimenti 1.
check_seconds() {
  case "$2" in
    '' | *[!0-9]* | 0)
      printf "ERRORE: %s deve essere un intero positivo di secondi, non '%s'\n" "$1" "$2" >&2
      return 1
      ;;
  esac
  return 0
}
