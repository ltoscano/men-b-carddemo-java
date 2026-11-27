#!/bin/sh
# Registra un evento con l'ora corrente (UTC) nel registro dei tempi.
# Uso: paper/data/tlog.sh <passo> <evento> <attore> [note]
#   passo   identificatore del passo (es. P7, issue-1, pr-17)
#   evento  inizio | fine | richiesta-autore | risposta-consegnata | altro nome breve
#   attore  autore | fable | opus | sonnet | codex | github
# Il registro e' in sola aggiunta: una riga sbagliata si corregge con una nuova riga, non modificando la vecchia.
set -eu
[ $# -ge 3 ] || { echo "uso: $0 <passo> <evento> <attore> [note]" >&2; exit 2; }
f="$(dirname "$0")/eventi.csv"
note=$(printf '%s' "${4:-}" | tr ',\n' '; ')
printf '%s,%s,%s,%s,orologio,%s\n' "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$note" >> "$f"
