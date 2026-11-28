#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/golden/run.sh (issue #55). Costruisce l'ingresso di uno scenario
# derivato: copia BASE (record di 300 byte senza terminatori) e vi scrive, byte per byte, le sostituzioni di TABELLA
# (sostituzioni-<scenario>.tsv: chiave, campo, posizione, lunghezza, byte esadecimali, ...). Nessun altro byte cambia;
# la verifica indipendente e' differenze.sh, che non usa questo script.
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0 riuscito; 1 errore (nessuna USCITA lasciata).
# Uso: prepara.sh BASE TABELLA USCITA
set -u
L=300
die() { echo "prepara.sh: $*" >&2; [ -z "${usc:-}" ] || rm -f "$usc.parziale"; [ -z "${lav:-}" ] || rm -rf "$lav"; exit 1; }
[ $# -eq 3 ] || die "uso: prepara.sh BASE TABELLA USCITA"
base="$1"; tab="$2"; usc="$3"; lav=""
[ -f "$base" ] || die "base assente: $base"
[ -f "$tab" ] || die "tabella assente: $tab"
[ ! -e "$usc" ] || die "uscita gia' presente (residuo di una corsa precedente): $usc"
[ ! -e "$usc.parziale" ] || die "uscita parziale gia' presente (residuo): $usc.parziale"
lav="$(mktemp -d /tmp/issue55-prepara.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
od -An -v -tx1 "$base" > "$lav/base.hex" || die "lettura della base fallita (od)"
# Chiavi della base: una riga "<numero del record> <chiave>" (la chiave sono i primi 11 byte, come testo).
awk -v L="$L" '
  BEGIN { for (i = 0; i < 256; i++) h[sprintf("%02x", i)] = i }
  { for (i = 1; i <= NF; i++) { n++; p = (n - 1) % L; if (p < 11) k = k sprintf("%c", h[$i]); if (p == L - 1) { print int(n / L), k; k = "" } } }
  END { if (n % L != 0) { print "dimensione della base non multipla di " L > "/dev/stderr"; exit 3 } }' "$lav/base.hex" > "$lav/chiavi" \
  || die "chiavi della base non lette (awk)"
# Righe della tabella -> "<scostamento da 0> <lunghezza> <byte in ottale per printf>".
awk -F '\t' -v L="$L" '
  FNR == NR { split($0, a, " "); rec[a[2]] = a[1]; nrec++; next }
  /^#/ || /^chiave\t/ || /^$/ { next }
  {
    if (NF != 9) { print "riga " FNR ": " NF " colonne, attese 9" > "/dev/stderr"; bad = 1; next }
    k = $1; pos = $3; len = $4; x = $5
    if (k !~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) { print "riga " FNR ": chiave non valida: " k > "/dev/stderr"; bad = 1; next }
    if (!(k in rec)) { print "riga " FNR ": chiave " k " assente dalla base" > "/dev/stderr"; bad = 1; next }
    if (pos !~ /^[0-9]+$/ || len !~ /^[0-9]+$/ || pos < 1 || len < 1 || pos + len - 1 > L) { print "riga " FNR ": posizione o lunghezza non valide" > "/dev/stderr"; bad = 1; next }
    if (x !~ /^([0-9a-f][0-9a-f])+$/ || length(x) != 2 * len) { print "riga " FNR ": byte non validi o di lunghezza diversa dal campo" > "/dev/stderr"; bad = 1; next }
    e = ""
    for (i = 1; i <= length(x); i += 2) { v = index("0123456789abcdef", substr(x, i, 1)) * 16 + index("0123456789abcdef", substr(x, i + 1, 1)) - 17; e = e sprintf("\\%03o", v) }
    print (rec[k] - 1) * L + pos - 1, len, e; righe++
  }
  END { if (bad) exit 3; if (righe < 1) { print "nessuna sostituzione nella tabella" > "/dev/stderr"; exit 3 } }' \
  "$lav/chiavi" "$tab" > "$lav/righe" || die "tabella non valida: $tab"
cp "$base" "$usc.parziale" || die "copia della base fallita (cp)"
n=0
while read -r off len esc; do
  # shellcheck disable=SC2059
  printf "$esc" > "$lav/byte" || die "byte della sostituzione non scritti (printf)"
  b="$(wc -c < "$lav/byte")" || die "dimensione dei byte non letta (wc)"
  [ "$b" -eq "$len" ] || die "sostituzione allo scostamento $off: $b byte invece di $len"
  dd if="$lav/byte" of="$usc.parziale" bs=1 seek="$off" conv=notrunc > "$lav/dd.log" 2>&1 || { cat "$lav/dd.log" >&2; die "scrittura allo scostamento $off fallita (dd)"; }
  n=$((n + 1))
done < "$lav/righe"
[ "$n" -gt 0 ] || die "nessuna sostituzione applicata"
s1="$(wc -c < "$base")" || die "dimensione della base non letta (wc)"
s2="$(wc -c < "$usc.parziale")" || die "dimensione dell'uscita non letta (wc)"
[ "$s1" -eq "$s2" ] || die "dimensione cambiata: base $s1, uscita $s2"
mv "$usc.parziale" "$usc" || die "uscita non pubblicata (mv)"
rm -rf "$lav" || { echo "prepara.sh: temporanei non rimossi: $lav" >&2; rm -f "$usc"; exit 1; }
echo "prepara.sh: $n sostituzioni scritte in $usc ($s2 byte)"
