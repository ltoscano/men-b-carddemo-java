#!/bin/sh
# Solo per le prove negative di oracle/build/check.sh (issue #35), eseguito DENTRO il container.
# Avvolge un comando: lo esegue con gli stessi argomenti, lascia passare il suo output autentico (stdout,
# stderr) e cambia soltanto l'esito restituito. Ogni invocazione aggiunge una riga al REGISTRO:
#   <ID> <numero dell'invocazione> <esito reale> <esito restituito> <argomenti>
# cosi' la prova dimostra che il comando bersaglio e' stato raggiunto, quante volte e con che esito.
#
# Uso: avvolgi.sh REGISTRO ID MODO COMANDO [ARGOMENTI...]
#   MODO  passa          restituisce l'esito reale
#         42             restituisce 42, qualunque sia l'esito reale
#         42@N           restituisce 42 alla N-esima invocazione con questo ID, altrimenti l'esito reale
#         42:ARGOMENTO   restituisce 42 se uno degli argomenti e' ARGOMENTO, altrimenti l'esito reale
#         T42, T42@N, T42:ARGOMENTO
#                        come 42, 42@N e 42:ARGOMENTO, ma con output PARZIALE: lo stdout autentico senza l'ultima riga
# Un errore dell'involucro stesso (uso, registro non scrivibile) esce con 120. I comandi dell'involucro hanno
# il percorso assoluto: l'involucro puo' stare davanti nel PATH.
set -u
[ $# -ge 4 ] || { echo "avvolgi.sh: uso: avvolgi.sh REGISTRO ID MODO COMANDO [ARGOMENTI...]" >&2; exit 120; }
reg="$1"; id="$2"; modo="$3"; shift 3

# Numero di questa invocazione: righe gia' registrate con lo stesso ID, piu' una. Esiti ammessi di grep -c:
# 0 e 1 (nessuna riga).
prec=0
if [ -e "$reg" ]; then
  prec="$(/usr/bin/grep -c -- "^$id " "$reg")"
  r=$?
  [ "$r" -le 1 ] || { echo "avvolgi.sh: registro $reg illeggibile (grep, codice $r)" >&2; exit 120; }
fi
num=$((prec + 1))

colpisci=0; tronca=0
case "$modo" in
  passa) ;;
  42) colpisci=1 ;;
  42@*) [ "$num" -ne "${modo#42@}" ] || colpisci=1 ;;
  42:*) for a in "$@"; do [ "$a" != "${modo#42:}" ] || colpisci=1; done ;;
  T42) colpisci=1; tronca=1 ;;
  T42@*) [ "$num" -ne "${modo#T42@}" ] || { colpisci=1; tronca=1; } ;;
  T42:*) for a in "$@"; do [ "$a" != "${modo#T42:}" ] || { colpisci=1; tronca=1; }; done ;;
  *) echo "avvolgi.sh: modo sconosciuto: $modo" >&2; exit 120 ;;
esac

if [ "$tronca" -eq 1 ]; then
  t="$(/usr/bin/mktemp /tmp/avvolgi.XXXXXX)" || { echo "avvolgi.sh: file temporaneo non creabile" >&2; exit 120; }
  "$@" > "$t"
  reale=$?
  /usr/bin/sed '$d' "$t" || { echo "avvolgi.sh: troncamento fallito" >&2; exit 120; }
  /usr/bin/rm -f "$t"
else
  "$@"
  reale=$?
fi
restituito=$reale
[ "$colpisci" -eq 0 ] || restituito=42
printf '%s %s %s %s %s\n' "$id" "$num" "$reale" "$restituito" "$*" >> "$reg" \
  || { echo "avvolgi.sh: registro $reg non scrivibile" >&2; exit 120; }
exit "$restituito"
