#!/bin/sh
# Solo per le prove negative di analysis/oracle-dati/check.sh (issue #53). Avvolge un comando: lo esegue davvero con
# gli stessi argomenti e cambia soltanto cio' che restituisce, a una sola invocazione scelta. Ogni invocazione scrive
# una riga nel REGISTRO: "<NOME> <numero dell'invocazione> <esito reale> <esito restituito>", cosi' la prova
# dimostra che il comando bersaglio e' stato raggiunto e con quale esito reale.
#
# Uso: involucro.sh REGISTRO NOME MODO REALE [ARGOMENTI...]
#   MODO  passa       esito reale, output autentico
#         42@N        all'N-esima invocazione: il comando gira davvero (output autentico), poi l'esito e' 42
#         vuoto@N     all'N-esima invocazione: nessun output, esito 0 (risposta incompleta)
#         rumore@N    all'N-esima invocazione: output "x?", esito 0 (risposta malformata)
#         attesa@N    all'N-esima invocazione: attende 30 s, poi esegue il comando (limite di tempo)
# Solo comandi della shell e il comando REALE (percorso assoluto): l'involucro puo' stare davanti nel PATH.
# Un errore dell'involucro stesso esce con 120.
[ $# -ge 4 ] || { echo "involucro.sh: uso: involucro.sh REGISTRO NOME MODO REALE [ARGOMENTI...]" >&2; exit 120; }
reg="$1"; nome="$2"; modo="$3"; reale="$4"; shift 4
prec=0
if [ -e "$reg" ]; then
  while IFS= read -r l; do case "$l" in "$nome "*) prec=$((prec + 1)) ;; esac; done < "$reg" \
    || { echo "involucro.sh: registro illeggibile: $reg" >&2; exit 120; }
fi
num=$((prec + 1))
bersaglio=""
case "$modo" in
  passa) ;;
  *@*) [ "${modo#*@}" != "$num" ] || bersaglio="${modo%@*}" ;;
  *) echo "involucro.sh: modo sconosciuto: $modo" >&2; exit 120 ;;
esac
case "$bersaglio" in
  vuoto) reale_rc=-; rc=0 ;;
  rumore) printf 'x?\n'; reale_rc=-; rc=0 ;;
  *)
    if [ "$bersaglio" = attesa ]; then /bin/sleep 30; fi
    "$reale" "$@"; reale_rc=$?; rc=$reale_rc
    [ "$bersaglio" != 42 ] || rc=42 ;;
esac
printf '%s %s %s %s\n' "$nome" "$num" "$reale_rc" "$rc" >> "$reg" || { echo "involucro.sh: registro non scrivibile" >&2; exit 120; }
exit "$rc"
