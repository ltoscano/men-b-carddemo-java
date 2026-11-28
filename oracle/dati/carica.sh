#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/dati/run.sh (issue #53). Carica e rilegge ACCTFILE.
#   1. IDXLOADF (oracle/tests/) carica INGRESSO (record di 300 byte senza terminatori) nel file indicizzato
#      OUT/lavoro/ACCTFILE.dat; rapporto di esegui.sh in OUT/carico/. Se non termina con 0 ci si ferma (uscita 3).
#   2. IDXDUMP (oracle/tests/, #25) rilegge il file indicizzato in ordine di chiave in OUT/lavoro/rilettura.bin
#      (record di 300 byte senza separatori); rapporto in OUT/rilettura/. Se non termina con 0 ci si ferma (uscita 3).
#      IDXDUMP controlla gli stati di apertura, lettura e chiusura e termina con 0 solo se la lettura arriva alla fine
#      del file con stato 10 (oracle/tests/IDXDUMP.cbl): il controllo della fine del file e' nel programma.
#   3. La rilettura deve essere identica byte per byte all'ingresso (cmp; altrimenti uscita 4) e lunga un multiplo di
#      300 byte; poi si scrive OUT/lavoro/ACCTFILE.rapporto: record, byte, prima e ultima chiave, SHA-256 della
#      rilettura. Il confronto con il rapporto atteso lo fa run.sh, sull'host.
# esegui.sh riceve sempre PATH=/usr/bin:/bin: gli involucri delle prove sugli esiti (davanti nel PATH di questo
# script) valgono solo per i comandi di questo script. Ogni comando ha l'esito controllato e ogni risposta usata e'
# validata; nessuna pipeline. Uscite: 0 riuscito; 1 errore dello strumento; 3 programma uscito con un codice diverso
# da 0; 4 rilettura diversa dall'ingresso.
# Uso: carica.sh INGRESSO OUT
set -u
[ $# -eq 2 ] || { echo "uso: carica.sh INGRESSO OUT" >&2; exit 1; }
in="$1"; out="$2"
L=300; K=11
# CARICA_ESEGUI: solo per le prove sugli esiti (una copia di esegui.sh che esce con 42 dopo il suo lavoro).
ESEGUI="${CARICA_ESEGUI:-/oracle/esegui.sh}"
die() { echo "carica.sh: $*" >&2; exit 1; }
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
[ -f "$in" ] || die "ingresso assente: $in"
mkdir -p "$out/carico" "$out/rilettura" "$out/lavoro" || die "cartelle non creabili in $out (mkdir)"
for f in "$out/lavoro/ACCTFILE.dat" "$out/lavoro/rilettura.bin" "$out/lavoro/ACCTFILE.rapporto"; do
  [ ! -e "$f" ] || die "residuo di una corsa precedente: $f"
done

PATH=/usr/bin:/bin sh "$ESEGUI" "$out/carico" IDXLOADF --parm ACCTFILE \
  --dd "DD_ENTRATA=$in" --dd "DD_ACCTFILE=$out/lavoro/ACCTFILE.dat" || die "esecuzione di IDXLOADF fallita (esegui.sh)"
c="$(codice "$out/carico/IDXLOADF.txt")" || exit 1
[ "$c" -eq 0 ] || { echo "carica.sh: IDXLOADF: codice di uscita $c, atteso 0" >&2; exit 3; }

PATH=/usr/bin:/bin sh "$ESEGUI" "$out/rilettura" IDXDUMP --parm ACCTFILE \
  --dd "DD_ACCTFILE=$out/lavoro/ACCTFILE.dat" --dd "DD_USCITA=$out/lavoro/rilettura.bin" \
  || die "esecuzione di IDXDUMP fallita (esegui.sh)"
c="$(codice "$out/rilettura/IDXDUMP.txt")" || exit 1
[ "$c" -eq 0 ] || { echo "carica.sh: IDXDUMP: codice di uscita $c, atteso 0" >&2; exit 3; }

[ -f "$out/lavoro/rilettura.bin" ] || die "rilettura assente"
si="$(dimensione "$in")" || exit 1
sr="$(dimensione "$out/lavoro/rilettura.bin")" || exit 1
r=0; cmp "$out/lavoro/rilettura.bin" "$in" > "$out/lavoro/cmp.txt" 2>&1 || r=$?
case "$r" in
  0) ;;
  1) echo "carica.sh: rilettura ($sr byte) diversa dall'ingresso ($si byte): $(sed -n '1p' "$out/lavoro/cmp.txt")" >&2; exit 4 ;;
  *) die "confronto non eseguito (cmp, codice $r)" ;;
esac
[ "$sr" -eq "$si" ] || die "cmp riuscito con dimensioni diverse: $sr e $si"
[ "$sr" -gt 0 ] && [ $((sr % L)) -eq 0 ] || die "rilettura di $sr byte: non un multiplo positivo di $L"
prima="$(head -c "$K" "$out/lavoro/rilettura.bin")" || die "prima chiave illeggibile (head)"
tail -c "$L" "$out/lavoro/rilettura.bin" > "$out/lavoro/ultimo.bin" || die "ultimo record illeggibile (tail)"
ultima="$(head -c "$K" "$out/lavoro/ultimo.bin")" || die "ultima chiave illeggibile (head)"
for k in "$prima" "$ultima"; do
  [ "${#k}" -eq "$K" ] && numero "$k" || die "chiave non di $K cifre: '$k'"
done
sha="$(sha256sum < "$out/lavoro/rilettura.bin")" || die "impronta della rilettura non calcolabile (sha256sum)"
sha="${sha%% *}"
case "$sha" in *[!0-9a-f]*) die "impronta non valida: '$sha'" ;; esac
[ "${#sha}" -eq 64 ] || die "impronta non valida: '$sha'"
{ echo "file ACCTFILE" && echo "record $((sr / L))" && echo "byte $sr" && echo "prima chiave $prima" \
  && echo "ultima chiave $ultima" && echo "sha256 rilettura $sha"; } > "$out/lavoro/ACCTFILE.rapporto" \
  || die "rapporto non scrivibile"
rm -f "$out/lavoro/cmp.txt" "$out/lavoro/ultimo.bin" || die "temporanei non rimovibili (rm)"
exit 0
