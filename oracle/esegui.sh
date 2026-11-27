#!/bin/sh
# Eseguito DENTRO il container dell'oracle. Avvia un eseguibile in una cartella di lavoro vuota e
# registra cio' che si osserva in un rapporto di testo, nel formato confrontato dai controlli:
#
#   == codice di uscita
#   <codice visto da questa shell, il processo padre del programma>
#   == stdout
#   <righe>
#   == stderr
#   <righe>
#   == file nella cartella di lavoro
#   <nome> <byte>         uno per riga, in ordine; nessuna riga se la cartella e' rimasta vuota
#
# Uso: esegui.sh BIN OUT NOME [PARM]
#   BIN   cartella degli artefatti (eseguibili e moduli; e' anche COB_LIBRARY_PATH)
#   OUT   cartella dei risultati: OUT/NOME.txt (rapporto) e OUT/lavoro-NOME/ (cartella di lavoro)
#   PARM  testo del PARM passato all'avviatore (facoltativo)
# Le variabili DD_<nome> per i file, se servono, arrivano dall'ambiente del container (docker run -e).
# Il programma ha stdin vuoto e un limite di tempo (ORACLE_TIMEOUT_RUN secondi, poi TERM e KILL).
set -u
[ $# -ge 3 ] && [ $# -le 4 ] || { echo "uso: esegui.sh BIN OUT NOME [PARM]" >&2; exit 2; }
bin="$1"; out="$2"; nome="$3"
t="${ORACLE_TIMEOUT_RUN:-60}"
[ -x "$bin/$nome" ] || { echo "esegui.sh: eseguibile assente: $bin/$nome" >&2; exit 2; }
lav="$out/lavoro-$nome"
rm -rf "$lav" && mkdir -p "$lav" || { echo "esegui.sh: cartella di lavoro non creabile: $lav" >&2; exit 2; }
[ -z "$(ls -A "$lav")" ] || { echo "esegui.sh: cartella di lavoro non vuota: $lav" >&2; exit 2; }
so="$out/$nome.stdout"; se="$out/$nome.stderr"
cd "$lav" || exit 2
if [ $# -eq 4 ]; then
  COB_LIBRARY_PATH="$bin" timeout -k 5 "$t" "$bin/$nome" "$4" < /dev/null > "$so" 2> "$se"
else
  COB_LIBRARY_PATH="$bin" timeout -k 5 "$t" "$bin/$nome" < /dev/null > "$so" 2> "$se"
fi
rc=$?
cd / || exit 2
{
  echo "== codice di uscita"
  echo "$rc"
  echo "== stdout"
  cat "$so"
  echo "== stderr"
  cat "$se"
  echo "== file nella cartella di lavoro"
  ( cd "$lav" && for f in $(ls -A | sort); do echo "$f $(wc -c < "$f" | tr -d ' ')"; done )
} > "$out/$nome.txt" || { echo "esegui.sh: rapporto non scrivibile" >&2; exit 2; }
rm -f "$so" "$se"
# 124/137: limite di tempo scaduto. E' un fallimento dello strumento, non un comportamento da registrare.
case "$rc" in 124|137) echo "esegui.sh: $nome non e' terminato entro ${t}s" >&2; exit 3 ;; esac
exit 0
