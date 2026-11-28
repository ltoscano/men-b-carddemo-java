#!/bin/sh
# Eseguito DENTRO il container dell'oracle (issue #55). Estrattore dei record logici di VBRCFILE (RECORDING MODE IS V,
# RECORD VARYING FROM 10 TO 80, app/cbl/CBACT01C.cbl:80-85) dal file fisico scritto da GnuCOBOL.
# Formato fisico di GnuCOBOL 3.2 con COB_VARSEQ_FORMAT 0, il valore predefinito, non impostato dall'oracle
# (oracle/ambiente.sh): davanti a ogni record 2 byte di lunghezza in big-endian, che non comprendono l'intestazione, e
# 2 byte X'00' (/usr/share/gnucobol/config/runtime.cfg dell'immagine, voce COB_VARSEQ_FORMAT: "0 means 2 byte record
# length (big-endian) + 2 NULs", "'length' is the data length, does not include the prefix"). Su z/OS il descrittore
# (RDW) e' di 4 byte e la sua lunghezza comprende il descrittore: il formato fisico non e' un riferimento di parita'.
# Scrive in USCITA una riga per record logico, nell'ordine: "<numero, 6 cifre> <lunghezza, 3 cifre> <byte esadecimali>".
# Rifiuta: intestazione troncata, byte 3-4 dell'intestazione diversi da 00, lunghezza fuori da 10-80, record oltre la
# fine del file, file vuoto. Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0; 1 errore dello
# strumento; 4 file fisico malformato (nessuna USCITA lasciata).
# Uso: estrai-vb.sh VBRCFILE USCITA
set -u
die() { echo "estrai-vb.sh: $*" >&2; [ -z "${lav:-}" ] || rm -rf "$lav"; exit 1; }
[ $# -eq 2 ] || die "uso: estrai-vb.sh VBRCFILE USCITA"
vb="$1"; usc="$2"; lav=""
[ -f "$vb" ] || die "file assente: $vb"
rm -f "$usc" || die "uscita precedente non rimossa: $usc"
lav="$(mktemp -d /tmp/issue55-estrai.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
od -An -v -tx1 "$vb" > "$lav/vb.hex" || die "lettura di $vb fallita (od)"
r=0
awk '
  BEGIN { for (i = 0; i < 256; i++) H[sprintf("%02x", i)] = i }
  { for (i = 1; i <= NF; i++) { if (!($i in H)) { print "byte non esadecimale: " $i; rotto = 1; exit 4 }; b[++n] = $i } }
  END {
    if (rotto) exit 4
    if (n == 0) { print "file vuoto"; exit 4 }
    p = 1; r = 0
    while (p <= n) {
      if (p + 3 > n) { print "intestazione troncata allo scostamento " p - 1; exit 4 }
      len = H[b[p]] * 256 + H[b[p + 1]]
      if (b[p + 2] != "00" || b[p + 3] != "00") { print "intestazione allo scostamento " p - 1 ": byte 3-4 " b[p + 2] b[p + 3] ", attesi 0000"; exit 4 }
      if (len < 10 || len > 80) { print "record allo scostamento " p - 1 ": lunghezza " len " fuori da 10-80"; exit 4 }
      if (p + 3 + len > n) { print "record allo scostamento " p - 1 ": " len " byte oltre la fine del file"; exit 4 }
      r++; s = ""
      for (j = 0; j < len; j++) s = s b[p + 4 + j]
      printf "%06d %03d %s\n", r, len, s
      p += 4 + len
    }
  }' "$lav/vb.hex" > "$lav/logici" 2> "$lav/err" || r=$?
case "$r" in
  0) ;;
  4) cat "$lav/logici" "$lav/err" >&2; rm -rf "$lav"; echo "estrai-vb.sh: file fisico malformato: $vb" >&2; exit 4 ;;
  *) cat "$lav/err" >&2; die "estrazione non eseguita (awk, codice $r)" ;;
esac
mv "$lav/logici" "$usc" || die "uscita non scritta (mv): $usc"
rm -rf "$lav" || { echo "estrai-vb.sh: temporanei non rimossi: $lav" >&2; rm -f "$usc"; exit 1; }
