#!/bin/sh
# Eseguito DENTRO il container dell'oracle (issue #55). Controllo 2: numero e ordine dei record.
#   - l'ingresso ha esattamente N record di 300 byte (N dichiarato: 50) con chiavi strettamente crescenti (l'ordine di
#     chiave del file indicizzato);
#   - OUTFILE ha N record di 107 byte e ARRYFILE N di 110 (dimensione esatta: nessun terminatore ne' intestazione);
#   - VBRCFILE.logici.txt ha 2N record logici, numerati 1..2N, alternati 12 e 39 byte;
#   - la dimensione del VBRCFILE fisico e' la somma di 4 + lunghezza dei record logici (un estrattore che perde un record
#     o legge una lunghezza sbagliata non passa);
#   - chiavi d'uscita (primi 11 byte di ogni record di OUTFILE, ARRYFILE e dei due record logici di ogni conto) uguali
#     alle chiavi d'ingresso, nello stesso ordine.
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0; 1 errore dello strumento; 4 differenza.
# Uso: conteggi.sh INGRESSO DIR N   (DIR: OUTFILE, ARRYFILE, VBRCFILE, VBRCFILE.logici.txt)
set -u
die() { echo "conteggi.sh: $*" >&2; [ -z "${lav:-}" ] || rm -rf "$lav"; exit 1; }
[ $# -eq 3 ] || die "uso: conteggi.sh INGRESSO DIR N"
ing="$1"; dir="$2"; n="$3"; lav=""
case "$n" in ''|*[!0-9]*) die "N non numerico: '$n'" ;; esac
for f in "$ing" "$dir/OUTFILE" "$dir/ARRYFILE" "$dir/VBRCFILE" "$dir/VBRCFILE.logici.txt"; do [ -f "$f" ] || die "file assente: $f"; done
lav="$(mktemp -d /tmp/issue55-conteggi.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
for f in ingresso:"$ing" OUTFILE:"$dir/OUTFILE" ARRYFILE:"$dir/ARRYFILE" VBRCFILE:"$dir/VBRCFILE"; do
  d="$(wc -c < "${f#*:}")" || die "dimensione di ${f%%:*} non letta (wc)"
  set -- $d
  [ $# -eq 1 ] || die "risposta di wc non valida: '$d'"
  case "$1" in ''|*[!0-9]*) die "risposta di wc non numerica: '$1'" ;; esac
  echo "${f%%:*} $1" >> "$lav/dimensioni" || die "dimensioni non scritte"
done
od -An -v -tx1 "$ing" > "$lav/i.hex" || die "od dell'ingresso fallito"
od -An -v -tx1 "$dir/OUTFILE" > "$lav/o.hex" || die "od di OUTFILE fallito"
od -An -v -tx1 "$dir/ARRYFILE" > "$lav/a.hex" || die "od di ARRYFILE fallito"
r=0
awk -v N="$n" -v FD="$lav/dimensioni" -v FI="$lav/i.hex" -v FO="$lav/o.hex" -v FA="$lav/a.hex" -v FL="$dir/VBRCFILE.logici.txt" '
  function chiave(arr, base,   i, s) { s = ""; for (i = 1; i <= 11; i++) s = s sprintf("%c", index("0123456789abcdef", substr(arr[base + i], 1, 1)) * 16 + index("0123456789abcdef", substr(arr[base + i], 2, 1)) - 17); return s }
  function chiaveh(h,   i, s) { s = ""; for (i = 1; i <= 21; i += 2) s = s sprintf("%c", index("0123456789abcdef", substr(h, i, 1)) * 16 + index("0123456789abcdef", substr(h, i + 1, 1)) - 17); return s }
  FILENAME == FD { DIM[$1] = $2 + 0; next }
  FILENAME == FI { for (i = 1; i <= NF; i++) I[++ni] = $i; next }
  FILENAME == FO { for (i = 1; i <= NF; i++) O[++no] = $i; next }
  FILENAME == FA { for (i = 1; i <= NF; i++) A[++na] = $i; next }
  FILENAME == FL { nl++; if (NF != 3 || $1 + 0 != nl || $2 !~ /^[0-9]+$/ || length($3) != 2 * $2) { print "record logico " nl ": riga malformata"; err++ }; LN[nl] = $2 + 0; LH[nl] = $3; somma += 4 + $2; next }
  END {
    if (DIM["ingresso"] != 300 * N) { print "ingresso di " DIM["ingresso"] " byte: attesi " N " record di 300 (" 300 * N " byte)"; err++ }
    if (DIM["OUTFILE"] != 107 * N) { print "OUTFILE di " DIM["OUTFILE"] " byte: attesi " N " record di 107 (" 107 * N ")"; err++ }
    if (DIM["ARRYFILE"] != 110 * N) { print "ARRYFILE di " DIM["ARRYFILE"] " byte: attesi " N " record di 110 (" 110 * N ")"; err++ }
    if (nl != 2 * N) { print "VBRCFILE: " nl " record logici, attesi " 2 * N; err++ }
    if (DIM["VBRCFILE"] != somma) { print "VBRCFILE fisico di " DIM["VBRCFILE"] " byte, ma i record logici estratti sommano " somma " byte (4 + lunghezza ciascuno)"; err++ }
    if (err) exit 4
    prec = ""
    for (k = 1; k <= N; k++) { ki = chiave(I, (k - 1) * 300)
      if (ki !~ /^[0-9]+$/ || (prec != "" && ki <= prec)) { print "ingresso, record " k ": chiave " ki " non numerica o non crescente"; err++ }
      prec = ki
      if (chiave(O, (k - 1) * 107) != ki) { print "OUTFILE, record " k ": chiave " chiave(O, (k - 1) * 107) ", ingresso " ki; err++ }
      if (chiave(A, (k - 1) * 110) != ki) { print "ARRYFILE, record " k ": chiave " chiave(A, (k - 1) * 110) ", ingresso " ki; err++ }
      if (LN[2 * k - 1] != 12 || LN[2 * k] != 39) { print "VBRCFILE, conto " k ": record logici di " LN[2 * k - 1] " e " LN[2 * k] " byte, attesi 12 e 39"; err++ }
      if (chiaveh(LH[2 * k - 1]) != ki || chiaveh(LH[2 * k]) != ki) { print "VBRCFILE, conto " k ": chiavi dei record logici diverse da " ki; err++ } }
    if (err) exit 4
    printf "conteggi: %d record d ingresso in ordine di chiave; OUTFILE %d x 107, ARRYFILE %d x 110, VBRCFILE %d record logici (12/39, %d byte fisici); chiavi d uscita uguali alle chiavi d ingresso, nello stesso ordine\n", N, N, N, nl, somma
  }' "$lav/dimensioni" "$lav/i.hex" "$lav/o.hex" "$lav/a.hex" "$dir/VBRCFILE.logici.txt" > "$lav/esito" 2>&1 || r=$?
case "$r" in
  0) cat "$lav/esito" || die "esito non stampato (cat)" ;;
  4) cat "$lav/esito" >&2; rm -rf "$lav"; echo "conteggi.sh: CONTROLLO 2 FALLITO" >&2; exit 4 ;;
  *) cat "$lav/esito" >&2; die "conteggio non eseguito (awk, codice $r)" ;;
esac
rm -rf "$lav" || { echo "conteggi.sh: temporanei non rimossi: $lav" >&2; exit 1; }
