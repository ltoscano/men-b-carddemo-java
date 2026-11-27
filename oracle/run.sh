#!/usr/bin/env bash
# Punto d'ingresso unico dell'oracle GnuCOBOL. Richiede solo bash, git, Docker e utility POSIX sull'host.
#
#   ./oracle/run.sh <nome>              esegue oracle/<nome>/run.sh
#   ./oracle/run.sh <nome> --check      esegue oracle/<nome>/check.sh (fallisce se manca)
#   ./oracle/run.sh --all               esegue tutte le cartelle rispettando le dipendenze
#   ./oracle/run.sh --all --check       idem per i controlli; fallisce se una cartella con run.sh non ha check.sh
#
# Una cartella di oracle/ che contiene run.sh e/o check.sh e' un passo dell'oracle.
# Le dipendenze si dichiarano in oracle/<nome>/deps (un nome per riga; righe vuote e '#' ignorate).
# Aggiungere un passo significa aggiungere una cartella: questo file non va modificato.
#
# Differenza rispetto ad analysis/run.sh: con --check un passo senza check.sh e' un errore, non viene saltato.
#
# Variabili d'ambiente:
#   ORACLE_ROOT  cartella che contiene i passi (default: la cartella di questo script);
#                serve al test automatico (oracle/selftest), che la punta a una cartella temporanea.
# Agli script dei passi vengono esportate ORACLE_ROOT e ORACLE_NAME; la loro cartella di lavoro
# e' quella del passo.
#
# Compatibile con bash 3.2 (macOS): niente array associativi.

set -u

ROOT="${ORACLE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export ORACLE_ROOT="$ROOT"

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

die() { echo "run.sh: errore: $*" >&2; exit 1; }

# Elenco (ordinato alfabeticamente, locale C) dei passi presenti.
list_steps() {
  local d name
  for d in "$ROOT"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ -f "$d/run.sh" ] || [ -f "$d/check.sh" ]; then
      printf '%s\n' "$name"
    fi
  done | LC_ALL=C sort
}

# Dipendenze dichiarate da un passo, una per riga.
deps_of() {
  local f="$ROOT/$1/deps"
  [ -f "$f" ] || return 0
  sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f" | grep -v '^$' || true
}

# Ordine topologico (Kahn) con parita' risolta in ordine alfabetico.
# Stampa i nomi uno per riga; in caso di dipendenza mancante o ciclo stampa l'errore su stderr e ritorna 1.
topo_order() {
  local all name dep missing=0
  all="$(list_steps)"
  [ -n "$all" ] || { echo "run.sh: errore: nessun passo trovato in $ROOT" >&2; return 1; }

  for name in $all; do
    for dep in $(deps_of "$name"); do
      if ! printf '%s\n' "$all" | grep -qx -- "$dep"; then
        echo "run.sh: errore: il passo '$name' dipende da '$dep', che non esiste" >&2
        missing=1
      fi
      if [ "$dep" = "$name" ]; then
        echo "run.sh: errore: il passo '$name' dipende da se stesso (ciclo)" >&2
        missing=1
      fi
    done
  done
  [ "$missing" -eq 0 ] || return 1

  local done_list="" remaining="$all" ready n d ok
  while [ -n "$remaining" ]; do
    ready=""
    for n in $remaining; do
      ok=1
      for d in $(deps_of "$n"); do
        if ! printf '%s\n' "$done_list" | grep -qx -- "$d"; then ok=0; break; fi
      done
      if [ "$ok" -eq 1 ]; then ready="$n"; break; fi   # $remaining e' ordinato: primo pronto = alfabeticamente minore
    done
    if [ -z "$ready" ]; then
      echo "run.sh: errore: dipendenze cicliche tra: $(printf '%s' "$remaining" | tr '\n' ' ')" >&2
      return 1
    fi
    done_list="${done_list}${done_list:+
}${ready}"
    remaining="$(printf '%s\n' "$remaining" | grep -vx -- "$ready" || true)"
  done
  printf '%s\n' "$done_list"
}

# Esegue lo script di un passo. Ritorna il codice di uscita dello script.
run_one() {
  local name="$1" mode="$2" script
  if [ "$mode" = check ]; then script=check.sh; else script=run.sh; fi
  local dir="$ROOT/$name"
  [ -d "$dir" ] || die "passo '$name' inesistente in $ROOT"
  if [ ! -f "$dir/$script" ]; then
    if [ "$mode" = check ]; then
      echo "run.sh: errore: il passo '$name' non ha check.sh: ogni passo deve avere il suo controllo" >&2
      return 1
    fi
    echo "== $name: nessun $script, saltato"
    return 0
  fi
  echo "== $name: $script"
  ( cd "$dir" && ORACLE_NAME="$name" bash "./$script" )
}

main() {
  local all=0 mode=run name=""
  [ $# -ge 1 ] || usage
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1 ;;
      --check) mode=check ;;
      -h|--help) usage ;;
      --*) die "opzione sconosciuta: $1" ;;
      *) [ -z "$name" ] || die "un solo nome di passo alla volta"; name="$1" ;;
    esac
    shift
  done

  if [ "$all" -eq 1 ]; then
    [ -z "$name" ] || die "--all e un nome di passo si escludono"
    local order n
    order="$(topo_order)" || exit 1
    for n in $order; do
      run_one "$n" "$mode" || { echo "run.sh: FALLITO il passo '$n' ($mode): mi fermo" >&2; exit 1; }
    done
    echo "run.sh: tutti i passi hanno terminato con successo ($mode)"
  else
    [ -n "$name" ] || usage
    case "$name" in */*|.*) die "nome di passo non valido: $name" ;; esac
    run_one "$name" "$mode"
  fi
}

main "$@"
