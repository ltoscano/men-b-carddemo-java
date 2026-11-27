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
# e, SOLO quando e' data l'opzione --sysin (issue #36), in coda:
#
#   == sysin
#   fornito: <byte> byte, sha256 <impronta SHA-256 del file>
#
# e, in OUT/NOME.ambiente, le variabili d'ambiente che riceve il programma (una per riga).
#
# Uso: esegui.sh OUT NOME [--parm TESTO] [--sysin FILE] [--dd DD_<nome>=<percorso>]...
#   gli artefatti sono in /oracle-bin (montata dal chiamante; e' anche COB_LIBRARY_PATH)
#   OUT      cartella dei risultati: OUT/NOME.txt, OUT/NOME.ambiente, OUT/lavoro-NOME/ (cartella di lavoro)
#   --parm   testo del PARM passato all'avviatore (il PARM= del JCL)
#   --sysin  file collegato all'ingresso standard del programma: le schede di una //SYSIN DD *, lette da
#            ACCEPT ... FROM SYSIN. Percorso assoluto (nel container) di un file regolare leggibile; una
#            sola volta. E' un ingresso diverso da --parm (issue #36)
#   --dd     una variabile DD_<nome> per un file (ripetibile)
# Il programma parte da `env -i` con le sole variabili di AMBIENTE_RUN (oracle/ambiente.sh) e quelle
# date con --dd: nulla dell'ambiente di questo script gli arriva. Ha stdin vuoto (o il file di --sysin)
# e un limite di tempo (ORACLE_TIMEOUT_RUN secondi, poi TERM e, 5 secondi dopo, KILL).
# Senza --sysin comandi eseguiti, rapporto e ambiente sono quelli di prima della issue #36.
set -u
set -o pipefail
. /oracle/ambiente.sh
BIN=/oracle-bin
[ $# -ge 2 ] || { echo "uso: esegui.sh OUT NOME [--parm TESTO] [--sysin FILE] [--dd DD_<nome>=<percorso>]..." >&2; exit 2; }
out="$1"; nome="$2"; shift 2
haparm=0; parm=""; dds=""; hasysin=0; sysin=""
while [ $# -gt 0 ]; do
  case "$1" in
    --parm) [ $# -ge 2 ] || { echo "esegui.sh: --parm senza testo" >&2; exit 2; }; haparm=1; parm="$2"; shift 2 ;;
    --sysin)
      [ $# -ge 2 ] || { echo "esegui.sh: --sysin senza file" >&2; exit 2; }
      [ "$hasysin" -eq 0 ] || { echo "esegui.sh: --sysin ripetuto" >&2; exit 2; }
      case "$2" in /*) ;; *) echo "esegui.sh: --sysin ammette solo un percorso assoluto: '$2'" >&2; exit 2 ;; esac
      hasysin=1; sysin="$2"; shift 2 ;;
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
so="$out/$nome.stdout"; se="$out/$nome.stderr"; rap="$out/$nome.txt"
# Ingresso standard del programma: vuoto, oppure il file di --sysin (issue #36). Con --sysin, PRIMA di ogni
# scrittura o cancellazione dello script, il file si copia in un file privato appena creato (mktemp): da li'
# in poi impronta e ingresso del programma sono la copia, anche se --sysin coincide (o e' un collegamento)
# con un file che lo script scrive o cancella (.ambiente, .stdout, .stderr, rapporto, cartella di lavoro).
# Ogni passo ha l'esito controllato e il valore validato (giro 1 della PR #52).
ingresso=/dev/null; copia=""
if [ "$hasysin" -eq 1 ]; then
  { [ -f "$sysin" ] && [ -r "$sysin" ]; } || { echo "esegui.sh: --sysin: file assente o illeggibile: '$sysin'" >&2; exit 2; }
  copia="$(mktemp /tmp/esegui-sysin.XXXXXX)" || { echo "esegui.sh: --sysin: copia privata non creabile (mktemp)" >&2; exit 2; }
  cp "$sysin" "$copia" || { echo "esegui.sh: --sysin: copia privata non riuscita (cp): '$sysin'" >&2; exit 2; }
  sysin_byte="$(wc -c < "$copia")" || { echo "esegui.sh: --sysin: dimensione non leggibile (wc): '$sysin'" >&2; exit 2; }
  sysin_byte="${sysin_byte#"${sysin_byte%%[! ]*}"}"; sysin_byte="${sysin_byte%"${sysin_byte##*[! ]}"}"
  case "$sysin_byte" in ''|*[!0-9]*) echo "esegui.sh: --sysin: dimensione non valida: '$sysin_byte'" >&2; exit 2 ;; esac
  sysin_sha="$(sha256sum < "$copia")" || { echo "esegui.sh: --sysin: impronta non calcolabile (sha256sum): '$sysin'" >&2; exit 2; }
  sysin_sha="${sysin_sha%% *}"
  case "$sysin_sha" in ''|*[!0-9a-f]*) echo "esegui.sh: --sysin: impronta non valida: '$sysin_sha'" >&2; exit 2 ;; esac
  [ "${#sysin_sha}" -eq 64 ] || { echo "esegui.sh: --sysin: impronta non valida: '$sysin_sha'" >&2; exit 2; }
  ingresso="$copia"
fi
# Nessun residuo di una corsa precedente (giro 1 della PR #52): stdout, stderr e rapporto si vuotano prima di
# tutto, con i soli comandi della shell. Se lo script si ferma dopo, il rapporto resta vuoto, non vecchio.
{ : > "$so" && : > "$se" && : > "$rap"; } || { echo "esegui.sh: file d'uscita non scrivibili in $out" >&2; exit 2; }
lav="$out/lavoro-$nome"
rm -rf "$lav" && mkdir -p "$lav" || { echo "esegui.sh: cartella di lavoro non creabile: $lav" >&2; exit 2; }
# Esito di ls controllato (issue #35): prima si perdeva dentro [ -z "$(ls -A ...)" ].
vuota="$(ls -A "$lav")" || { echo "esegui.sh: cartella di lavoro non elencabile: $lav" >&2; exit 2; }
[ -z "$vuota" ] || { echo "esegui.sh: cartella di lavoro non vuota: $lav" >&2; exit 2; }
cd "$lav" || exit 2
# shellcheck disable=SC2086
env -i $AMBIENTE_RUN $dds env > "$out/$nome.ambiente" || { echo "esegui.sh: ambiente non registrabile" >&2; exit 2; }
# Apertura dell'ingresso controllata a parte (giro 1 della PR #52): un'apertura fallita e' un errore dello
# strumento, non un codice del programma. L'ingresso resta aperto sul descrittore 3 e il programma lo riceve
# come stdin (<&3) senza una seconda apertura; se exec 3< fallisse comunque, la shell si ferma con 2.
# Lo stesso per stdout e stderr (descrittori 4 e 5): una redirezione fallita non diventa il codice del programma.
( exec < "$ingresso" ) 2>/dev/null || { echo "esegui.sh: ingresso non apribile: '$ingresso'" >&2; exit 2; }
exec 3< "$ingresso" 4> "$so" 5> "$se"
if [ "$haparm" -eq 1 ]; then
  # shellcheck disable=SC2086
  env -i $AMBIENTE_RUN $dds /usr/bin/timeout -k 5 "$t" "$BIN/$nome" "$parm" <&3 >&4 2>&5 3<&- 4>&- 5>&-
else
  # shellcheck disable=SC2086
  env -i $AMBIENTE_RUN $dds /usr/bin/timeout -k 5 "$t" "$BIN/$nome" <&3 >&4 2>&5 3<&- 4>&- 5>&-
fi
rc=$?
exec 3<&- 4>&- 5>&-
cd / || exit 2
# Il rapporto, con l'esito di ogni comando controllato (issue #35): prima gli esiti di cat, ls, sort e wc si
# perdevano dentro il gruppo, la pipeline e le sostituzioni di comando, e un rapporto incompleto passava.
# file_lavoro: una riga "<nome> <byte>" per file della cartella di lavoro, in ordine (formato invariato).
# Nessuna pipeline (giro 1 della PR #49: senza pipefail l'esito del primo comando di "printf | sort" e
# "printf | tr" si perdeva): sort legge l'elenco da un here-document, gli spazi si tolgono senza comandi.
file_lavoro() (
  cd "$lav" || exit 1
  nomi="$(ls -A)" || exit 1
  nomi="$(sort <<FINE
$nomi
FINE
)" || exit 1
  for f in $nomi; do
    b="$(wc -c < "$f")" || exit 1
    b="${b#"${b%%[! ]*}"}"; b="${b%"${b##*[! ]}"}"
    echo "$f $b" || exit 1
  done
)
# sezione_sysin: solo con --sysin (issue #36); senza l'opzione non scrive nulla e il rapporto resta identico.
sezione_sysin() {
  [ "$hasysin" -eq 1 ] || return 0
  echo "== sysin" && echo "fornito: $sysin_byte byte, sha256 $sysin_sha"
}
rapporto() {
  echo "== codice di uscita" && echo "$rc" \
    && echo "== stdout" && cat "$so" \
    && echo "== stderr" && cat "$se" \
    && echo "== file nella cartella di lavoro" && file_lavoro \
    && sezione_sysin
}
rapporto > "$rap" || { echo "esegui.sh: rapporto non scrivibile o incompleto" >&2; exit 2; }
rm -f "$so" "$se" ${copia:+"$copia"} || { echo "esegui.sh: file temporanei non rimovibili: $so $se $copia" >&2; exit 2; }
# 124/137: limite di tempo scaduto. E' un fallimento dello strumento, non un comportamento da registrare.
case "$rc" in 124|137) echo "esegui.sh: $nome non e' terminato entro ${t}s" >&2; exit 3 ;; esac
exit 0
