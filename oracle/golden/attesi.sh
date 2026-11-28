#!/bin/sh
# Eseguito DENTRO il container dell'oracle (issue #55). Controllo 3: ogni atteso scritto a mano (readacct/
# attesi-a-mano.tsv) coincide con il record corrispondente del golden.
#   - per ogni conto e file dello SCENARIO (OUTFILE, ARRYFILE, VBRC1, VBRC2) gli attesi coprono il record per intero,
#     campo dopo campo, senza buchi ne' sovrapposizioni (107, 110, 12, 39 byte);
#   - i conti coperti sono quelli dovuti: nello scenario esempio almeno cinque, tra cui il primo e l'ultimo del file e il
#     49; nello scenario mirato ogni conto della tabella delle sostituzioni (SOSTITUZIONI); per ogni conto i quattro
#     record;
#   - ogni byte atteso coincide con il byte del golden, cioe' del riferimento di parita' (OUTFILE.riferimento.txt,
#     ARRYFILE.riferimento.txt, VBRCFILE.riferimento.txt: correzioni dell'oracle applicate, esclusioni mascherate);
#   - le posizioni attese ND sono esattamente le posizioni escluse per quel conto (ESCLUSIONI) e quelle mascherate (**)
#     nel riferimento: ne' una in piu' ne' una in meno.
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0; 1 errore dello strumento; 4 differenza.
# Uso: attesi.sh ATTESI SOSTITUZIONI ESCLUSIONI SCENARIO DIR   (DIR: i tre *.riferimento.txt)
set -u
die() { echo "attesi.sh: $*" >&2; exit 1; }
[ $# -eq 5 ] || die "uso: attesi.sh ATTESI SOSTITUZIONI ESCLUSIONI SCENARIO DIR"
att="$1"; sos="$2"; esc="$3"; scen="$4"; dir="$5"
for f in "$att" "$sos" "$esc" "$dir/OUTFILE.riferimento.txt" "$dir/ARRYFILE.riferimento.txt" "$dir/VBRCFILE.riferimento.txt"; do
  [ -f "$f" ] || die "file assente: $f"
done
lav="$(mktemp -d /tmp/issue55-attesi.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
r=0
awk -F '\t' -v S="$scen" -v FA="$att" -v FS2="$sos" -v FE="$esc" -v FO="$dir/OUTFILE.riferimento.txt" -v FR="$dir/ARRYFILE.riferimento.txt" -v FV="$dir/VBRCFILE.riferimento.txt" '
  function bv(x) { return index("0123456789abcdef", substr(x, 1, 1)) * 16 + index("0123456789abcdef", substr(x, 2, 1)) - 17 }
  function key(h,   i, s) { s = ""; for (i = 1; i <= 21; i += 2) s = s sprintf("%c", bv(substr(h, i, 2))); return s }
  BEGIN { LEN["OUTFILE"] = 107; LEN["ARRYFILE"] = 110; LEN["VBRC1"] = 12; LEN["VBRC2"] = 39
          ASC = ""; for (i = 32; i < 127; i++) ASC = ASC sprintf("%c", i) }
  FILENAME == FA { if ($0 ~ /^#/ || $0 ~ /^scenario\t/ || $0 == "") next
    if (NF != 8) { print "attesi, riga " FNR ": " NF " colonne, attese 8"; bad = 1; next }
    if ($1 != S) next
    k = $2; f = $3; p = $5 + 0; n = $6 + 0; v = $7
    if (!(f in LEN)) { print "attesi, riga " FNR ": file sconosciuto " f; bad = 1; next }
    g = k SUBSEP f; if (!(g in NX)) { NX[g] = 1; G[++ng] = g; if (!(k in KS)) { KS[k] = 1; KL[++nk] = k } }
    if (p != NX[g]) { print "attesi, riga " FNR ": " k " " f " " $4 " inizia al byte " p ", atteso " NX[g] " (buco o sovrapposizione)"; bad = 1 }
    if (v == "ND") { for (i = 0; i < n; i++) X[g, p + i] = "ND" }
    else if (v ~ /^c:/) { t = substr(v, 3); if (length(t) != n) { print "attesi, riga " FNR ": " length(t) " caratteri per " n " byte"; bad = 1 }
      for (i = 0; i < n; i++) X[g, p + i] = sprintf("%02x", index(ASC, substr(t, i + 1, 1)) + 31) }
    else if (v ~ /^x:/) { t = substr(v, 3); if (t !~ /^([0-9a-f][0-9a-f])+$/ || length(t) != 2 * n) { print "attesi, riga " FNR ": esadecimale non valido per " n " byte"; bad = 1 }
      for (i = 0; i < n; i++) X[g, p + i] = substr(t, 2 * i + 1, 2) }
    else { print "attesi, riga " FNR ": valore non riconosciuto " v; bad = 1 }
    CAMPO[g, p] = $4; NX[g] = p + n; next }
  FILENAME == FS2 { if ($0 ~ /^#/ || $0 ~ /^chiave\t/ || $0 == "") next; DOV[$1] = 1; next }
  FILENAME == FE { if ($0 ~ /^#/ || $0 ~ /^scenario\t/ || $0 == "") next
    if (NF != 7) { print "esclusioni, riga " FNR ": " NF " colonne, attese 7"; bad = 1; next }
    if ($1 != "*" && $1 != S) next
    ne++; EF[ne] = $2; EK[ne] = $3; EP[ne] = $4 + 0; EN[ne] = $5 + 0; next }
  FILENAME == FO { no++; GR["OUTFILE", key($0)] = $0; if (no == 1) prima = key($0); ultima = key($0); next }
  FILENAME == FR { nr++; GR["ARRYFILE", key($0)] = $0; next }
  FILENAME == FV { nv++; split($0, a, " "); GR[(nv % 2 ? "VBRC1" : "VBRC2"), key(a[3])] = a[3]; next }
  END {
    if (bad) exit 4
    if (no == 0 || nr == 0 || nv == 0) { print "riferimento vuoto"; exit 4 }
    # conti dovuti
    if (S == "esempio") { if (nk < 5) { print "scenario esempio: " nk " conti con attesi, almeno 5"; err++ }
      split(prima " " ultima " 00000000049", d, " "); for (i = 1; i <= 3; i++) if (!(d[i] in KS)) { print "scenario esempio: manca il conto " d[i]; err++ } }
    else if (S == "mirato") { for (k in DOV) if (!(k in KS)) { print "scenario mirato: manca il conto modificato " k; err++ } }
    for (i = 1; i <= nk; i++) for (f in LEN) if (!((KL[i] SUBSEP f) in NX)) { print KL[i] ": manca il record " f; err++ }
    for (q = 1; q <= ng; q++) { g = G[q]; split(g, z, SUBSEP); k = z[1]; f = z[2]
      if (NX[g] != LEN[f] + 1) { print k " " f ": attesi fino al byte " NX[g] - 1 ", record di " LEN[f]; err++; continue }
      if (!((f SUBSEP k) in GR)) { print k " " f ": record assente dal golden"; err++; continue }
      s = GR[f, k]; if (length(s) != 2 * LEN[f]) { print k " " f ": record del golden di " length(s) / 2 " byte"; err++; continue }
      for (p = 1; p <= LEN[f]; p++) { ex = 0
        for (e = 1; e <= ne; e++) if (EF[e] == f && (EK[e] == "*" || EK[e] == k) && p >= EP[e] && p < EP[e] + EN[e]) ex = 1
        gb = substr(s, 2 * p - 1, 2)
        if (X[g, p] == "ND") { if (!ex) { print k " " f " byte " p ": atteso ND ma la posizione non e esclusa"; err++ }
          if (gb != "**") { print k " " f " byte " p ": atteso ND ma il riferimento non e mascherato (" gb ")"; err++ }; continue }
        if (ex) { print k " " f " byte " p ": posizione esclusa ma l atteso a mano ha un valore"; err++ }
        if (X[g, p] != gb) { print k " " f " byte " p ": atteso a mano " X[g, p] ", golden " gb; err++ } else ok++ }
      nrec++ }
    if (err) exit 4
    printf "attesi a mano: %d conti, %d record, %d byte coincidenti con il golden; posizioni ND = posizioni escluse\n", nk, nrec, ok
  }' "$att" "$sos" "$esc" "$dir/OUTFILE.riferimento.txt" "$dir/ARRYFILE.riferimento.txt" "$dir/VBRCFILE.riferimento.txt" > "$lav/esito" 2>&1 || r=$?
case "$r" in
  0) cat "$lav/esito" || die "esito non stampato (cat)" ;;
  4) cat "$lav/esito" >&2; rm -rf "$lav"; echo "attesi.sh: ATTESI A MANO DIVERSI dal golden (scenario $scen)" >&2; exit 4 ;;
  *) cat "$lav/esito" >&2; die "confronto non eseguito (awk, codice $r)" ;;
esac
rm -rf "$lav" || { echo "attesi.sh: temporanei non rimossi: $lav" >&2; exit 1; }
