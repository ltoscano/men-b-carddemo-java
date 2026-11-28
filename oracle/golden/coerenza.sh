#!/bin/sh
# Eseguito DENTRO il container dell'oracle (issue #55). Controllo separato tra file fisico e riferimento (specifica,
# "Posizioni in cui l'oracle sbaglia"): il file fisico dell'oracle differisce dal riferimento di parita' SOLO nelle
# posizioni della tabella delle correzioni (con esattamente i byte dichiarati: oracle nel fisico, riferimento nel
# riferimento) e in quelle della tabella delle esclusioni (** nel riferimento); in ogni altra posizione i byte sono
# identici. Vale per OUTFILE, ARRYFILE e per i record logici di VBRCFILE, letti qui dal file fisico (non da
# VBRCFILE.logici.txt, che produce l estrattore: rilievo 1 del giro 1 della PR #64), stesso numero di
# record e stesse lunghezze. Ogni correzione della tabella che riguarda lo scenario deve essere applicata almeno una
# volta. Ogni token esadecimale letto e validato. Non condivide codice con maschera.sh ne con estrai-vb.sh.
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0; 1 errore dello strumento; 4 differenza.
# Uso: coerenza.sh SCENARIO DIR ESCLUSIONI CORREZIONI
set -u
die() { echo "coerenza.sh: $*" >&2; [ -z "${lav:-}" ] || rm -rf "$lav"; exit 1; }
[ $# -eq 4 ] || die "uso: coerenza.sh SCENARIO DIR ESCLUSIONI CORREZIONI"
scen="$1"; dir="$2"; esc="$3"; cor="$4"; lav=""
for f in "$esc" "$cor" "$dir/OUTFILE" "$dir/ARRYFILE" "$dir/VBRCFILE" "$dir/OUTFILE.riferimento.txt" \
         "$dir/ARRYFILE.riferimento.txt" "$dir/VBRCFILE.riferimento.txt"; do [ -f "$f" ] || die "file assente: $f"; done
lav="$(mktemp -d /tmp/issue55-coerenza.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
od -An -v -tx1 "$dir/OUTFILE" > "$lav/o.hex" || die "lettura di OUTFILE fallita (od)"
od -An -v -tx1 "$dir/ARRYFILE" > "$lav/a.hex" || die "lettura di ARRYFILE fallita (od)"
od -An -v -tx1 "$dir/VBRCFILE" > "$lav/v.hex" || die "lettura di VBRCFILE fallita (od)"
r=0
awk -F '\t' -v S="$scen" -v FE="$esc" -v FC="$cor" -v FO="$lav/o.hex" -v FA="$lav/a.hex" -v FL="$lav/v.hex" \
    -v RO="$dir/OUTFILE.riferimento.txt" -v RA="$dir/ARRYFILE.riferimento.txt" -v RV="$dir/VBRCFILE.riferimento.txt" '
  function ch(x) { return sprintf("%c", index("0123456789abcdef", substr(x, 1, 1)) * 16 + index("0123456789abcdef", substr(x, 2, 1)) - 17) }
  function chiave(h,   i, s) { s = ""; for (i = 1; i <= 21; i += 2) s = s ch(substr(h, i, 2)); return s }
  function paragona(F, j, fis, rif,   k, p, f, g, e, c, x) {
    if (length(fis) != length(rif)) { print F " record " j ": lunghezze diverse (fisico " length(fis) / 2 ", riferimento " length(rif) / 2 ")"; err++; return }
    k = chiave(fis)
    for (p = 1; p <= length(fis) / 2; p++) { f = substr(fis, 2 * p - 1, 2); g = substr(rif, 2 * p - 1, 2); c = 0; x = 0
      for (e = 1; e <= nc; e++) if (CF[e] == F && (CK[e] == "*" || CK[e] == k) && CP[e] == p) c = e
      for (e = 1; e <= ne; e++) if (EF[e] == F && (EK[e] == "*" || EK[e] == k) && p >= EP[e] && p < EP[e] + EN[e]) x = 1
      if (f !~ /^[0-9a-f][0-9a-f]$/ || (g != "**" && g !~ /^[0-9a-f][0-9a-f]$/)) { print F " record " j " byte " p ": token non valido (fisico " f ", riferimento " g ")"; err++; continue }
      if (g == "**") { if (!x) { print F " " k " byte " p ": mascherato nel riferimento ma non escluso"; err++ } else masc++; continue }
      if (x) { print F " " k " byte " p ": escluso ma non mascherato nel riferimento"; err++; continue }
      if (c) { if (f != CO[c] || g != CR[c]) { print F " " k " byte " p ": correzione attesa " CO[c] " -> " CR[c] ", trovato fisico " f " e riferimento " g; err++ } else { cor++; uso[c]++ }; continue }
      if (f != g) { print F " " k " byte " p ": fisico " f ", riferimento " g ", posizione in nessuna tabella"; err++ } else ug++ }
  }
  FILENAME == FE { if ($0 ~ /^#/ || $0 ~ /^scenario\t/ || $0 == "") next; if ($1 != "*" && $1 != S) next
    ne++; EF[ne] = $2; EK[ne] = $3; EP[ne] = $4 + 0; EN[ne] = $5 + 0; next }
  FILENAME == FC { if ($0 ~ /^#/ || $0 ~ /^scenario\t/ || $0 == "") next; if ($1 != "*" && $1 != S) next
    nc++; CF[nc] = $2; CK[nc] = $3; CP[nc] = $4 + 0; CO[nc] = $5; CR[nc] = $6; next }
  function tok(x, d) { if (x !~ /^[0-9a-f][0-9a-f]$/) { print d ": token non esadecimale \"" x "\""; err++; rotto = 1 } }
  FILENAME == FO { m = split($0, t, " "); for (i = 1; i <= m; i++) { tok(t[i], "OUTFILE"); O[++no] = t[i] }; next }
  FILENAME == FA { m = split($0, t, " "); for (i = 1; i <= m; i++) { tok(t[i], "ARRYFILE"); A[++na] = t[i] }; next }
  FILENAME == FL { m = split($0, t, " "); for (i = 1; i <= m; i++) { tok(t[i], "VBRCFILE"); V[++nv] = t[i] }; next }
  FILENAME == RO { XO[++nxo] = $0; next }
  FILENAME == RA { XA[++nxa] = $0; next }
  FILENAME == RV { split($0, t, " "); XV[++nxv] = t[3]; XL[nxv] = t[1] " " t[2]; next }
  END {
    if (rotto) exit 4
    p = 1; nl = 0
    while (p <= nv) { if (p + 3 > nv) { print "VBRCFILE: intestazione troncata"; exit 4 }
      l = (index("0123456789abcdef", substr(V[p], 1, 1)) - 1) * 4096 + (index("0123456789abcdef", substr(V[p], 2, 1)) - 1) * 256 + (index("0123456789abcdef", substr(V[p + 1], 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(V[p + 1], 2, 1)) - 1
      if (V[p + 2] != "00" || V[p + 3] != "00" || l < 1 || p + 3 + l > nv) { print "VBRCFILE: intestazione non valida allo scostamento " p - 1; exit 4 }
      nl++; s = ""; for (i = 0; i < l; i++) s = s V[p + 4 + i]; L[nl] = s; LL[nl] = sprintf("%06d %03d", nl, l); p += 4 + l }
    if (no % 107 || na % 110) { print "file fisici non multipli del record"; exit 4 }
    if (nxo != no / 107 || nxa != na / 110 || nxv != nl) { print "numero di record diverso tra fisico e riferimento"; exit 4 }
    for (j = 1; j <= nxo; j++) { s = ""; for (i = 1; i <= 107; i++) s = s O[(j - 1) * 107 + i]; paragona("OUTFILE", j, s, XO[j]) }
    for (j = 1; j <= nxa; j++) { s = ""; for (i = 1; i <= 110; i++) s = s A[(j - 1) * 110 + i]; paragona("ARRYFILE", j, s, XA[j]) }
    for (j = 1; j <= nl; j++) { if (LL[j] != XL[j]) { print "record logico " j ": numero o lunghezza diversi"; err++; continue }; paragona((j % 2 ? "VBRC1" : "VBRC2"), j, L[j], XV[j]) }
    for (e = 1; e <= nc; e++) if (!uso[e]) { print "correzione " CF[e] " byte " CP[e] " mai applicata nel riferimento"; err++ }
    if (err) exit 4
    printf "fisico e riferimento (%s): %d byte identici, %d corretti come da tabella, %d mascherati come da tabella, nessun altra differenza\n", S, ug, cor, masc
  }' "$esc" "$cor" "$lav/o.hex" "$lav/a.hex" "$lav/v.hex" "$dir/OUTFILE.riferimento.txt" \
  "$dir/ARRYFILE.riferimento.txt" "$dir/VBRCFILE.riferimento.txt" > "$lav/esito" 2>&1 || r=$?
case "$r" in
  0) cat "$lav/esito" || die "esito non stampato (cat)" ;;
  4) cat "$lav/esito" >&2; rm -rf "$lav"; echo "coerenza.sh: FISICO E RIFERIMENTO DIFFERISCONO fuori dalle tabelle (scenario $scen)" >&2; exit 4 ;;
  *) cat "$lav/esito" >&2; die "confronto non eseguito (awk, codice $r)" ;;
esac
rm -rf "$lav" || { echo "coerenza.sh: temporanei non rimossi: $lav" >&2; exit 1; }
