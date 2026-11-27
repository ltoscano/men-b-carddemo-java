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
# e, in OUT/NOME.ambiente, le variabili d'ambiente che riceve il programma (una per riga).
#
# Uso: esegui.sh OUT NOME [--parm TESTO] [--dd DD_<nome>=<percorso>]...
#   gli artefatti sono in /oracle-bin (montata dal chiamante; e' anche COB_LIBRARY_PATH)
#   OUT      cartella dei risultati: OUT/NOME.txt, OUT/NOME.ambiente, OUT/lavoro-NOME/ (cartella di lavoro)
#   --parm   testo del PARM passato all'avviatore
#   --dd     una variabile DD_<nome> per un file (ripetibile)
# Il programma parte da `env -i` con le sole variabili di AMBIENTE_RUN (oracle/ambiente.sh) e quelle
# date con --dd: nulla dell'ambiente di questo script gli arriva. Ha stdin vuoto e un limite di tempo
# (ORACLE_TIMEOUT_RUN secondi, poi TERM e, 5 secondi dopo, KILL).
set -u
. /oracle/ambiente.sh
BIN=/oracle-bin
[ $# -ge 2 ] || { echo "uso: esegui.sh OUT NOME [--parm TESTO] [--dd DD_<nome>=<percorso>]..." >&2; exit 2; }
out="$1"; nome="$2"; shift 2
haparm=0; parm=""; dds=""
while [ $# -gt 0 ]; do
  case "$1" in
    --parm) [ $# -ge 2 ] || { echo "esegui.sh: --parm senza testo" >&2; exit 2; }; haparm=1; parm="$2"; shift 2 ;;
    --dd)
      [ $# -ge 2 ] || { echo "esegui.sh: --dd senza valore" >&2; exit 2; }
      case "$2" in
        DD_*=*) ;;
        *) echo "esegui.sh: --dd ammette solo DD_<nome>=<percorso>: '$2'" >&2; exit 2 ;;
      esac
      case "$2" in *[[:space:]]*) echo "esegui.sh: spazi non ammessi in --dd: '$2'" >&2; exit 2 ;; esac
      dds="$dds${dds:+ }$2"; shift 2 ;;
    *) echo "esegui.sh: argomento sconosciuto: '$1'" >&2; exit 2 ;;
  esac
done
t="${ORACLE_TIMEOUT_RUN:-60}"
[ -x "$BIN/$nome" ] || { echo "esegui.sh: eseguibile assente: $BIN/$nome" >&2; exit 2; }
lav="$out/lavoro-$nome"
rm -rf "$lav" && mkdir -p "$lav" || { echo "esegui.sh: cartella di lavoro non creabile: $lav" >&2; exit 2; }
[ -z "$(ls -A "$lav")" ] || { echo "esegui.sh: cartella di lavoro non vuota: $lav" >&2; exit 2; }
so="$out/$nome.stdout"; se="$out/$nome.stderr"
cd "$lav" || exit 2
# shellcheck disable=SC2086
env -i $AMBIENTE_RUN $dds env > "$out/$nome.ambiente" || { echo "esegui.sh: ambiente non registrabile" >&2; exit 2; }
if [ "$haparm" -eq 1 ]; then
  # shellcheck disable=SC2086
  env -i $AMBIENTE_RUN $dds /usr/bin/timeout -k 5 "$t" "$BIN/$nome" "$parm" < /dev/null > "$so" 2> "$se"
else
  # shellcheck disable=SC2086
  env -i $AMBIENTE_RUN $dds /usr/bin/timeout -k 5 "$t" "$BIN/$nome" < /dev/null > "$so" 2> "$se"
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
