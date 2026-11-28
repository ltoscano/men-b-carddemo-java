#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/dati/run.sh (issue #53). Carica ACCTFILE e lo legge per due vie.
#   1. IDXLOADF (oracle/tests/) carica INGRESSO (record di 300 byte senza terminatori) nel file indicizzato
#      OUT/ACCTFILE.dat.verifica (non ancora pubblicato: lo pubblica run.sh, per ultimo); rapporto in OUT/carico/.
#   2. IDXLEGGI (oracle/tests/, il lettore indipendente: nessun codice in comune con IDXDUMP ne' con IDXLOADF) legge
#      il file indicizzato in ordine di chiave in OUT/lavoro/lettura.bin (pretende chiavi crescenti e lo stato 10
#      alla fine) e poi per chiave (START + READ) le chiavi di CHIAVI qui sotto, in OUT/lavoro/chiavi.bin; rapporto in
#      OUT/lettura/.
#   3. IDXDUMP (oracle/tests/, #25), seconda via: rilegge in ordine di chiave in OUT/lavoro/rilettura.bin (termina
#      con 0 solo se arriva alla fine con stato 10); rapporto in OUT/rilettura/.
#   Ogni programma deve terminare con 0 (altrimenti uscita 3).
#   4. La lettura di IDXLEGGI deve essere identica byte per byte all'ingresso, la rilettura di IDXDUMP anche, e le due
#      letture identiche fra loro; ogni lettura per chiave identica al record dell'ingresso con quella chiave
#      (altrimenti uscita 4). Poi OUT/lavoro/ACCTFILE.rapporto: record, byte, prima e ultima chiave, SHA-256, letture
#      per chiave. Il confronto con il rapporto atteso lo fa run.sh, sull'host.
# esegui.sh riceve sempre PATH=/usr/bin:/bin: gli involucri delle prove sugli esiti (davanti nel PATH di questo
# script) valgono solo per i comandi di questo script. Ogni comando ha l'esito controllato e ogni risposta usata e'
# validata; nessuna pipeline. Uscite: 0 riuscito; 1 errore dello strumento; 3 programma uscito con un codice diverso
# da 0; 4 lettura diversa dall'ingresso.
# Uso: carica.sh INGRESSO OUT
set -u
[ $# -eq 2 ] || { echo "uso: carica.sh INGRESSO OUT" >&2; exit 1; }
in="$1"; out="$2"
L=300; K=11
# Letture per chiave: chiave:numero del record dell'ingresso con quella chiave (primo, uno in mezzo, quello della
# differenza ASCII/EBCDIC).
CHIAVI="00000000001:1 00000000025:25 00000000049:49"
# CARICA_ESEGUI: solo per le prove sugli esiti (una copia di esegui.sh che esce con 42 dopo il suo lavoro).
ESEGUI="${CARICA_ESEGUI:-/oracle/esegui.sh}"
IDX="$out/ACCTFILE.dat.verifica"
die() { echo "carica.sh: $*" >&2; exit 1; }
diverso() { echo "carica.sh: $*" >&2; exit 4; }
numero() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
# codice RAPPORTO: la seconda riga del rapporto di esegui.sh (codice di uscita del programma), validata.
codice() {
  c="$(sed -n '2p' "$1")" || die "rapporto illeggibile: $1 (sed)"
  numero "$c" || die "codice di uscita non numerico nel rapporto $1: '$c'"
  echo "$c"
}
dimensione() {
  d="$(wc -c < "$1")" || die "dimensione di $1 non leggibile (wc)"
  set -- $d
  [ $# -eq 1 ] && numero "$1" || die "risposta di wc non numerica: '$d'"
  echo "$1"
}
# uguali A B DESCRIZIONE: cmp distinto in 0 (uguali), 1 (diversi: uscita 4), altro (errore dello strumento).
uguali() {
  r=0; cmp "$1" "$2" > "$out/lavoro/cmp.txt" 2>&1 || r=$?
  case "$r" in
    0) ;;
    1) diverso "$3: $(sed -n '1p' "$out/lavoro/cmp.txt")" ;;
    *) die "confronto non eseguito: $3 (cmp, codice $r)" ;;
  esac
}
[ -f "$in" ] || die "ingresso assente: $in"
mkdir -p "$out/carico" "$out/lettura" "$out/rilettura" "$out/lavoro" || die "cartelle non creabili in $out (mkdir)"
for f in "$IDX" "$out/lavoro/lettura.bin" "$out/lavoro/chiavi.bin" "$out/lavoro/rilettura.bin" "$out/lavoro/ACCTFILE.rapporto"; do
  [ ! -e "$f" ] || die "residuo di una corsa precedente: $f"
done

PATH=/usr/bin:/bin sh "$ESEGUI" "$out/carico" IDXLOADF --parm ACCTFILE \
  --dd "DD_ENTRATA=$in" --dd "DD_ACCTFILE=$IDX" || die "esecuzione di IDXLOADF fallita (esegui.sh)"
c="$(codice "$out/carico/IDXLOADF.txt")" || exit 1
[ "$c" -eq 0 ] || { echo "carica.sh: IDXLOADF: codice di uscita $c, atteso 0" >&2; exit 3; }

parm=ACCTFILE
for v in $CHIAVI; do parm="$parm${v%%:*}"; done
PATH=/usr/bin:/bin sh "$ESEGUI" "$out/lettura" IDXLEGGI --parm "$parm" --dd "DD_ACCTFILE=$IDX" \
  --dd "DD_LETTURA=$out/lavoro/lettura.bin" --dd "DD_CHIAVI=$out/lavoro/chiavi.bin" \
  || die "esecuzione di IDXLEGGI fallita (esegui.sh)"
c="$(codice "$out/lettura/IDXLEGGI.txt")" || exit 1
[ "$c" -eq 0 ] || { echo "carica.sh: IDXLEGGI: codice di uscita $c, atteso 0" >&2; exit 3; }

PATH=/usr/bin:/bin sh "$ESEGUI" "$out/rilettura" IDXDUMP --parm ACCTFILE \
  --dd "DD_ACCTFILE=$IDX" --dd "DD_USCITA=$out/lavoro/rilettura.bin" || die "esecuzione di IDXDUMP fallita (esegui.sh)"
c="$(codice "$out/rilettura/IDXDUMP.txt")" || exit 1
[ "$c" -eq 0 ] || { echo "carica.sh: IDXDUMP: codice di uscita $c, atteso 0" >&2; exit 3; }

for f in lettura.bin chiavi.bin rilettura.bin; do [ -f "$out/lavoro/$f" ] || die "lettura assente: $f"; done
si="$(dimensione "$in")" || exit 1
sl="$(dimensione "$out/lavoro/lettura.bin")" || exit 1
uguali "$out/lavoro/lettura.bin" "$in" "lettura indipendente (IDXLEGGI, $sl byte) diversa dall'ingresso ($si byte)"
uguali "$out/lavoro/rilettura.bin" "$in" "rilettura di IDXDUMP diversa dall'ingresso"
uguali "$out/lavoro/lettura.bin" "$out/lavoro/rilettura.bin" "le due letture (IDXLEGGI, IDXDUMP) differiscono"
[ "$sl" -eq "$si" ] || die "cmp riuscito con dimensioni diverse: $sl e $si"
[ "$sl" -gt 0 ] && [ $((sl % L)) -eq 0 ] || die "lettura di $sl byte: non un multiplo positivo di $L"
# Letture per chiave: il k-esimo record di chiavi.bin e il record dell'ingresso con quella chiave.
k=0; desc=""
for v in $CHIAVI; do
  k=$((k + 1)); ch="${v%%:*}"; n="${v#*:}"
  tail -c "+$(( (k - 1) * L + 1 ))" "$out/lavoro/chiavi.bin" > "$out/lavoro/coda.bin" || die "lettura per chiave $ch illeggibile (tail)"
  head -c "$L" "$out/lavoro/coda.bin" > "$out/lavoro/per-chiave.bin" || die "lettura per chiave $ch illeggibile (head)"
  tail -c "+$(( (n - 1) * L + 1 ))" "$in" > "$out/lavoro/coda.bin" || die "record $n dell'ingresso illeggibile (tail)"
  head -c "$L" "$out/lavoro/coda.bin" > "$out/lavoro/atteso.bin" || die "record $n dell'ingresso illeggibile (head)"
  uguali "$out/lavoro/per-chiave.bin" "$out/lavoro/atteso.bin" "lettura per chiave $ch diversa dal record $n dell'ingresso"
  desc="$desc $ch=record$n"
done
sc="$(dimensione "$out/lavoro/chiavi.bin")" || exit 1
[ "$sc" -eq $((k * L)) ] || diverso "letture per chiave: $sc byte, attesi $k record da $L"
prima="$(head -c "$K" "$out/lavoro/lettura.bin")" || die "prima chiave illeggibile (head)"
tail -c "$L" "$out/lavoro/lettura.bin" > "$out/lavoro/ultimo.bin" || die "ultimo record illeggibile (tail)"
ultima="$(head -c "$K" "$out/lavoro/ultimo.bin")" || die "ultima chiave illeggibile (head)"
for x in "$prima" "$ultima"; do
  [ "${#x}" -eq "$K" ] && numero "$x" || die "chiave non di $K cifre: '$x'"
done
sha="$(sha256sum < "$out/lavoro/lettura.bin")" || die "impronta della lettura non calcolabile (sha256sum)"
sha="${sha%% *}"
case "$sha" in *[!0-9a-f]*) die "impronta non valida: '$sha'" ;; esac
[ "${#sha}" -eq 64 ] || die "impronta non valida: '$sha'"
{ echo "file ACCTFILE" && echo "record $((sl / L))" && echo "byte $sl" && echo "prima chiave $prima" \
  && echo "ultima chiave $ultima" && echo "sha256 lettura $sha" \
  && echo "letture identiche: IDXLEGGI = IDXDUMP = ingresso" && echo "letture per chiave:$desc"; } \
  > "$out/lavoro/ACCTFILE.rapporto" || die "rapporto non scrivibile"
rm -f "$out/lavoro/cmp.txt" "$out/lavoro/ultimo.bin" "$out/lavoro/coda.bin" "$out/lavoro/per-chiave.bin" \
  "$out/lavoro/atteso.bin" || die "temporanei non rimovibili (rm)"
exit 0
