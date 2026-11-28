#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/golden/run.sh (issue #55). Produce i riferimenti di parita' di uno
# scenario dai file prodotti dall'oracle:
#   OUTFILE.riferimento.txt, ARRYFILE.riferimento.txt   una riga per record: i byte in esadecimale (2 caratteri per
#                                                       byte), nell'ordine del file;
#   VBRCFILE.riferimento.txt                            una riga per record logico: "<numero> <lunghezza> <byte>";
#   console.riferimento.txt                             le righe di stdout di classe a (readacct/console.tsv) come sono;
#                                                       ogni riga di classe b o c diventa "#OSSERVAZIONE <classe> <riga>".
# Prima le CORREZIONI (readacct/correzioni.tsv), condizionate: il byte dell'oracle deve essere esattamente quello
# dichiarato, altrimenti il passo fallisce; poi le ESCLUSIONI (readacct/esclusioni.tsv): ogni byte escluso diventa **.
# Una posizione corretta ed esclusa insieme e' un errore delle tabelle. Ogni riga delle due tabelle deve avere motivo
# (regola) e riga del sorgente; una correzione con byte uguali e' un errore.
# Ingressi in DIR: OUTFILE, ARRYFILE (fisici), VBRCFILE.logici.txt (estrai-vb.sh), rapporto.txt (esegui.sh).
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0; 1 errore dello strumento; 4 tabelle o file non
# coerenti (nessun riferimento lasciato).
# Uso: maschera.sh SCENARIO DIR ESCLUSIONI CORREZIONI CONSOLE
set -u
die() { echo "maschera.sh: $*" >&2; pulisci; exit 1; }
pulisci() { [ -z "${dir:-}" ] || rm -f "$dir/OUTFILE.riferimento.txt" "$dir/ARRYFILE.riferimento.txt" "$dir/VBRCFILE.riferimento.txt" "$dir/console.riferimento.txt"; [ -z "${lav:-}" ] || rm -rf "$lav"; }
[ $# -eq 5 ] || { echo "maschera.sh: uso: maschera.sh SCENARIO DIR ESCLUSIONI CORREZIONI CONSOLE" >&2; exit 1; }
scen="$1"; dir="$2"; esc="$3"; cor="$4"; con="$5"; lav=""
for f in "$esc" "$cor" "$con" "$dir/OUTFILE" "$dir/ARRYFILE" "$dir/VBRCFILE.logici.txt" "$dir/rapporto.txt"; do
  [ -f "$f" ] || die "file assente: $f"
done
rm -f "$dir/OUTFILE.riferimento.txt" "$dir/ARRYFILE.riferimento.txt" "$dir/VBRCFILE.riferimento.txt" "$dir/console.riferimento.txt" \
  || { echo "maschera.sh: riferimenti precedenti non rimossi (rm)" >&2; exit 1; }
lav="$(mktemp -d /tmp/issue55-maschera.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
od -An -v -tx1 "$dir/OUTFILE" > "$lav/o.hex" || die "lettura di OUTFILE fallita (od)"
od -An -v -tx1 "$dir/ARRYFILE" > "$lav/a.hex" || die "lettura di ARRYFILE fallita (od)"
r=0
awk -F '\t' -v S="$scen" -v FE="$esc" -v FC="$cor" -v FK="$con" -v FO="$lav/o.hex" -v FA="$lav/a.hex" \
    -v FV="$dir/VBRCFILE.logici.txt" -v FR="$dir/rapporto.txt" -v U="$lav" '
  function bv(x) { return index("0123456789abcdef", substr(x, 1, 1)) * 16 + index("0123456789abcdef", substr(x, 2, 1)) - 17 }
  function key(h,   i, s) { s = ""; for (i = 1; i <= 21; i += 2) s = s sprintf("%c", bv(substr(h, i, 2))); return s }
  # rif(F, s): applica correzioni ed esclusioni al record s (esadecimale) del file F; restituisce il riferimento
  function rif(F, s,   k, n, p, b, e, out, ex, co) {
    k = key(s); n = length(s) / 2; out = ""
    for (p = 1; p <= n; p++) { b = substr(s, 2 * p - 1, 2); ex = 0; co = 0
      for (e = 1; e <= nc; e++) if (CF[e] == F && (CK[e] == "*" || CK[e] == k) && CP[e] == p) co = e
      for (e = 1; e <= ne; e++) if (EF[e] == F && (EK[e] == "*" || EK[e] == k) && p >= EP[e] && p < EP[e] + EN[e]) ex = 1
      if (co && ex) { print F " " k " byte " p ": posizione sia corretta sia esclusa"; err++ }
      if (co) { if (b != CO[co]) { print "CORREZIONE CONDIZIONATA NON APPLICABILE: " F " " k " byte " p ": l oracle ha scritto " b ", la tabella dichiara " CO[co]; err++ }
                else { b = CR[co]; usate[co]++ } }
      if (ex) { b = "**"; esclusi++ }
      out = out b }
    return out
  }
  BEGIN { LEN["OUTFILE"] = 107; LEN["ARRYFILE"] = 110; LEN["VBRC1"] = 12; LEN["VBRC2"] = 39 }
  FILENAME == FE { if ($0 ~ /^#/ || $0 ~ /^scenario\t/ || $0 == "") next
    if (NF != 7 || $6 == "" || $6 == "-" || $7 == "" || $7 == "-") { print "esclusioni, riga " FNR ": colonne mancanti o senza motivo o senza riga del sorgente"; bad = 1; next }
    if (!($2 in LEN) || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ || $4 < 1 || $5 < 1 || $4 + $5 - 1 > LEN[$2]) { print "esclusioni, riga " FNR ": file, posizione o lunghezza non validi"; bad = 1; next }
    if ($1 != "*" && $1 != S) next
    ne++; EF[ne] = $2; EK[ne] = $3; EP[ne] = $4 + 0; EN[ne] = $5 + 0; next }
  FILENAME == FC { if ($0 ~ /^#/ || $0 ~ /^scenario\t/ || $0 == "") next
    if (NF != 8 || $7 == "" || $7 == "-" || $8 == "" || $8 == "-") { print "correzioni, riga " FNR ": colonne mancanti o senza regola o senza riga del sorgente"; bad = 1; next }
    if (!($2 in LEN) || $4 !~ /^[0-9]+$/ || $4 < 1 || $4 > LEN[$2] || $5 !~ /^[0-9a-f][0-9a-f]$/ || $6 !~ /^[0-9a-f][0-9a-f]$/) { print "correzioni, riga " FNR ": file, posizione o byte non validi"; bad = 1; next }
    if ($5 == $6) { print "correzioni, riga " FNR ": byte dell oracle uguale al byte di riferimento"; bad = 1; next }
    if ($1 != "*" && $1 != S) next
    nc++; CF[nc] = $2; CK[nc] = $3; CP[nc] = $4 + 0; CO[nc] = $5; CR[nc] = $6; next }
  FILENAME == FK { if ($0 ~ /^#/ || $0 ~ /^posizione\t/ || $0 == "") next
    if (NF != 5 || ($4 != "a" && $4 != "b" && $4 != "c")) { print "console, riga " FNR ": formato non valido"; bad = 1; next }
    KP[$1] = $3; KC[$1] = $4; KR[$1] = $2; nk++; next }
  FILENAME == FO { m = split($0, a, " "); for (i = 1; i <= m; i++) { if (a[i] !~ /^[0-9a-f][0-9a-f]$/) { print "token non esadecimale \"" a[i] "\" (od)"; rotto = 1 }; O[++no] = a[i] }; next }
  FILENAME == FA { m = split($0, a, " "); for (i = 1; i <= m; i++) { if (a[i] !~ /^[0-9a-f][0-9a-f]$/) { print "token non esadecimale \"" a[i] "\" (od)"; rotto = 1 }; A[++na] = a[i] }; next }
  FILENAME == FV { nv++; if (split($0, a, " ") != 3 || a[1] + 0 != nv || length(a[3]) != 2 * a[2] || a[3] !~ /^([0-9a-f][0-9a-f])+$/) { print "record logici, riga " nv ": formato non valido"; bad = 1 }; VN[nv] = a[2]; VH[nv] = a[3]; next }
  FILENAME == FR { if ($0 == "== stdout") { inso = 1; next } if ($0 == "== stderr") { inso = 0; next } if (inso) SO[++ns] = $0; next }
  END {
    if (rotto) exit 4
    if (bad) exit 4
    if (nk != 17) { print "console.tsv: " nk " posizioni, attese 17 (inizio, 1-15, fine)"; exit 4 }
    if (no == 0 || no % 107 || na == 0 || na % 110) { print "OUTFILE (" no " byte) o ARRYFILE (" na " byte) non multipli positivi del record"; exit 4 }
    for (j = 1; j <= no / 107; j++) { s = ""; for (i = 1; i <= 107; i++) s = s O[(j - 1) * 107 + i]; print rif("OUTFILE", s) > (U "/o.rif") }
    for (j = 1; j <= na / 110; j++) { s = ""; for (i = 1; i <= 110; i++) s = s A[(j - 1) * 110 + i]; print rif("ARRYFILE", s) > (U "/a.rif") }
    for (j = 1; j <= nv; j++) printf "%06d %03d %s\n", j, VN[j], rif((j % 2 ? "VBRC1" : "VBRC2"), VH[j]) > (U "/v.rif")
    for (e = 1; e <= nc; e++) if (!usate[e]) { print "correzione " CF[e] " byte " CP[e] " mai applicata: nessun record corrispondente"; err++ }
    if ((ns - 2) % 15 || ns < 2) { print "console di " ns " righe: non 2 + 15 x N"; err++ }
    for (i = 1; i <= ns; i++) { if (i == 1) q = "inizio"; else if (i == ns) q = "fine"; else q = (i - 2) % 15 + 1
      if (KP[q] != "-" && index(SO[i], KP[q]) != 1) { print "console, riga " i " (posizione " q "): non comincia con il letterale atteso"; err++ }
      if ((q == "inizio" || q == "fine") && SO[i] != KP[q]) { print "console, riga " i ": attesa esattamente \"" KP[q] "\""; err++ }
      if (KC[q] == "a") print SO[i] > (U "/c.rif"); else print "#OSSERVAZIONE " KC[q] " " KR[q] > (U "/c.rif") }
    if (err) exit 4
    printf "maschera: %d+%d record fissi, %d record logici, %d righe di console; correzioni applicate:", no / 107, na / 110, nv, ns
    for (e = 1; e <= nc; e++) printf " %s/%d=%d", CF[e], CP[e], usate[e]; printf "; byte esclusi: %d\n", esclusi
  }' "$esc" "$cor" "$con" "$lav/o.hex" "$lav/a.hex" "$dir/VBRCFILE.logici.txt" "$dir/rapporto.txt" > "$lav/esito" 2>&1 || r=$?
case "$r" in
  0) ;;
  4) cat "$lav/esito" >&2; pulisci; echo "maschera.sh: riferimenti NON prodotti (scenario $scen)" >&2; exit 4 ;;
  *) cat "$lav/esito" >&2; die "riferimenti non prodotti (awk, codice $r)" ;;
esac
for c in o:OUTFILE a:ARRYFILE v:VBRCFILE c:console; do
  [ -f "$lav/${c%%:*}.rif" ] || die "riferimento ${c#*:} non prodotto"
done
mv "$lav/o.rif" "$dir/OUTFILE.riferimento.txt" && mv "$lav/a.rif" "$dir/ARRYFILE.riferimento.txt" \
  && mv "$lav/v.rif" "$dir/VBRCFILE.riferimento.txt" && mv "$lav/c.rif" "$dir/console.riferimento.txt" \
  || die "riferimenti non scritti (mv)"
cat "$lav/esito" || die "esito non stampato (cat)"
rm -rf "$lav" || { lav=""; die "temporanei non rimossi"; }
