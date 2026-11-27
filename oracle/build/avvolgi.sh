#!/bin/sh
# Solo per le prove negative di oracle/build/check.sh (issue #35), eseguito DENTRO il container.
# Avvolge un comando: lo esegue con gli stessi argomenti, lascia passare il suo output autentico (stdout,
# stderr) e cambia soltanto l'esito restituito. Ogni invocazione aggiunge una riga al REGISTRO:
#   <ID> <numero dell'invocazione> <esito reale> <esito restituito> <argomenti>
# cosi' la prova dimostra che il comando bersaglio e' stato davvero raggiunto, quante volte e con che esito.
#
# Uso: avvolgi.sh REGISTRO ID MODO COMANDO [ARGOMENTI...]
#   MODO  passa          restituisce l'esito reale
#         42             restituisce 42, qualunque sia l'esito reale
#         42@N           restituisce 42 alla N-esima invocazione con questo ID, altrimenti l'esito reale
#         42:ARGOMENTO   restituisce 42 se uno degli argomenti e' ARGOMENTO, altrimenti l'esito reale
# Un errore dell'involucro stesso (uso, registro non scrivibile) esce con 120.
set -u
[ $# -ge 4 ] || { echo "avvolgi.sh: uso: avvolgi.sh REGISTRO ID MODO COMANDO [ARGOMENTI...]" >&2; exit 120; }
reg="$1"; id="$2"; modo="$3"; shift 3

# Numero di questa invocazione: righe gia' registrate con lo stesso ID, piu' una. Esiti ammessi di grep -c:
# 0 e 1 (nessuna riga). grep con il percorso assoluto: l'involucro puo' stare davanti nel PATH.
prec=0
if [ -e "$reg" ]; then
  prec="$(/usr/bin/grep -c -- "^$id " "$reg")"
  r=$?
  [ "$r" -le 1 ] || { echo "avvolgi.sh: registro $reg illeggibile (grep, codice $r)" >&2; exit 120; }
fi
num=$((prec + 1))

colpisci=0
case "$modo" in
  passa) ;;
  42) colpisci=1 ;;
  42@*) [ "$num" -ne "${modo#42@}" ] || colpisci=1 ;;
  42:*) for a in "$@"; do [ "$a" != "${modo#42:}" ] || colpisci=1; done ;;
  *) echo "avvolgi.sh: modo sconosciuto: $modo" >&2; exit 120 ;;
esac

"$@"
reale=$?
restituito=$reale
[ "$colpisci" -eq 0 ] || restituito=42
printf '%s %s %s %s %s\n' "$id" "$num" "$reale" "$restituito" "$*" >> "$reg" \
  || { echo "avvolgi.sh: registro $reg non scrivibile" >&2; exit 120; }
exit "$restituito"
