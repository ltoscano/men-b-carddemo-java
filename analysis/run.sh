#!/usr/bin/env bash
# Punto d'ingresso unico delle analisi del legacy. Richiede solo bash, git e Docker sull'host.
#
#   ./analysis/run.sh <nome>              esegue analysis/<nome>/run.sh
#   ./analysis/run.sh <nome> --check      esegue analysis/<nome>/check.sh
#   ./analysis/run.sh --all               esegue tutte le analisi rispettando le dipendenze
#   ./analysis/run.sh --all --check       idem per i controlli
#
# Un'analisi e' una cartella di analysis/ che contiene run.sh e/o check.sh.
# Le dipendenze si dichiarano in analysis/<nome>/deps (un nome per riga; righe vuote e '#' ignorate).
# Aggiungere un'analisi significa aggiungere una cartella: questo file non va modificato.
#
# Variabili d'ambiente:
#   ANALYSIS_ROOT  cartella che contiene le analisi (default: la cartella di questo script);
#                  serve ai test automatici, che la puntano a una cartella temporanea.
# Agli script delle analisi vengono esportate ANALYSIS_ROOT e ANALYSIS_NAME; il loro
# directory di lavoro e' la cartella dell'analisi.
#
# Compatibile con bash 3.2 (macOS): niente array associativi.

set -u

ROOT="${ANALYSIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export ANALYSIS_ROOT="$ROOT"

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

die() { echo "run.sh: errore: $*" >&2; exit 1; }

# Elenco (ordinato alfabeticamente, locale C) delle analisi presenti.
list_analyses() {
  local d name
  for d in "$ROOT"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ -f "$d/run.sh" ] || [ -f "$d/check.sh" ]; then
      printf '%s\n' "$name"
    fi
  done | LC_ALL=C sort
}

# Dipendenze dichiarate da un'analisi, una per riga.
deps_of() {
  local f="$ROOT/$1/deps"
  [ -f "$f" ] || return 0
  sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f" | grep -v '^$' || true
}

# Ordine topologico (Kahn) con parita' risolta in ordine alfabetico.
# Stampa i nomi uno per riga; in caso di dipendenza mancante o ciclo stampa l'errore su stderr e ritorna 1.
topo_order() {
  local all name dep missing=0
  all="$(list_analyses)"
  [ -n "$all" ] || die "nessuna analisi trovata in $ROOT"

  for name in $all; do
    for dep in $(deps_of "$name"); do
      if ! printf '%s\n' "$all" | grep -qx -- "$dep"; then
        echo "run.sh: errore: l'analisi '$name' dipende da '$dep', che non esiste" >&2
        missing=1
      fi
      if [ "$dep" = "$name" ]; then
        echo "run.sh: errore: l'analisi '$name' dipende da se stessa (ciclo)" >&2
        missing=1
      fi
    done
  done
  [ "$missing" -eq 0 ] || return 1

  local done_list="" remaining="$all" progressed ready n d ok
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

# Esegue lo script di una analisi. Ritorna il codice di uscita dello script.
run_one() {
  local name="$1" mode="$2" script
  if [ "$mode" = check ]; then script=check.sh; else script=run.sh; fi
  local dir="$ROOT/$name"
  [ -d "$dir" ] || die "analisi '$name' inesistente in $ROOT"
  if [ ! -f "$dir/$script" ]; then
    echo "== $name: nessun $script, saltata"
    return 0
  fi
  echo "== $name: $script"
  ( cd "$dir" && ANALYSIS_NAME="$name" bash "./$script" )
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
      *) [ -z "$name" ] || die "un solo nome di analisi alla volta"; name="$1" ;;
    esac
    shift
  done

  if [ "$all" -eq 1 ]; then
    [ -z "$name" ] || die "--all e un nome di analisi si escludono"
    local order n
    order="$(topo_order)" || exit 1
    for n in $order; do
      run_one "$n" "$mode" || { echo "run.sh: FALLITA l'analisi '$n' ($mode): mi fermo" >&2; exit 1; }
    done
    echo "run.sh: tutte le analisi hanno terminato con successo ($mode)"
  else
    [ -n "$name" ] || usage
    case "$name" in */*|.*) die "nome di analisi non valido: $name" ;; esac
    run_one "$name" "$mode"
  fi
}

main "$@"
