#!/bin/sh
# Eseguito DENTRO il container dell'oracle (issue #55). Verifica le proprieta' richieste dalla specifica
# (readacct/proprieta.tsv, righe dello SCENARIO) sul file indicizzato EFFETTIVAMENTE LETTO: LETTO e' la lettura in
# ordine di chiave fatta con IDXLEGGI dopo il caricamento (record di 300 byte), non il file preparato. ESEMPIO e'
# l'ingresso dello scenario esempio (serve alla condizione base-non-zero). Le condizioni sono descritte in testa a
# proprieta.tsv; i byte si decodificano con le regole di #23 (docs/legacy-map/data-contract/codifica.md).
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0 tutte presenti; 1 errore dello strumento;
# 4 una proprieta' manca.
# Uso: proprieta.sh LETTO SCENARIO TABELLA ESEMPIO
set -u
L=300
die() { echo "proprieta.sh: $*" >&2; [ -z "${lav:-}" ] || rm -rf "$lav"; exit 1; }
[ $# -eq 4 ] || die "uso: proprieta.sh LETTO SCENARIO TABELLA ESEMPIO"
letto="$1"; scen="$2"; tab="$3"; es="$4"; lav=""
for f in "$letto" "$tab" "$es"; do [ -f "$f" ] || die "file assente: $f"; done
lav="$(mktemp -d /tmp/issue55-proprieta.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
od -An -v -tx1 "$letto" > "$lav/l.hex" || die "lettura di $letto fallita (od)"
od -An -v -tx1 "$es" > "$lav/e.hex" || die "lettura di $es fallita (od)"
r=0
awk -F '\t' -v L="$L" -v S="$scen" -v FT="$tab" -v FL="$lav/l.hex" -v FE="$lav/e.hex" '
  function bv(x) { return index("0123456789abcdef", substr(x, 1, 1)) * 16 + index("0123456789abcdef", substr(x, 2, 1)) - 17 }
  function txt(A, k, p, n,   i, s) { s = ""; for (i = 0; i < n; i++) s = s sprintf("%c", bv(A[(k - 1) * L + p + i])); return s }
  function hx(A, k, p, n,   i, s) { s = ""; for (i = 0; i < n; i++) s = s A[(k - 1) * L + p + i]; return s }
  # zoned(A, k, p, n): ZOK, ZSGN (+/-), ZZERO, ZALT (ultimo byte cifra semplice), ZCAN, ZD (cifre)
  function zoned(A, k, p, n,   i, c) {
    ZOK = 1; ZD = ""; ZALT = 0
    for (i = 0; i < n - 1; i++) { c = bv(A[(k - 1) * L + p + i]); if (c < 48 || c > 57) ZOK = 0; ZD = ZD sprintf("%c", c) }
    c = bv(A[(k - 1) * L + p + n - 1])
    if (c >= 48 && c <= 57) { ZD = ZD (c - 48); ZSGN = "+"; ZALT = 1 }
    else if (c == 123) { ZD = ZD "0"; ZSGN = "+" } else if (c >= 65 && c <= 73) { ZD = ZD (c - 64); ZSGN = "+" }
    else if (c == 125) { ZD = ZD "0"; ZSGN = "-" } else if (c >= 74 && c <= 82) { ZD = ZD (c - 73); ZSGN = "-" }
    else ZOK = 0
    ZZERO = (ZD ~ /^0+$/); ZCAN = ZOK && !ZALT && !(ZSGN == "-" && ZZERO)
  }
  function dataok(k,   y, m, d, j, s) {
    s = txt(LB, k, 69, 10); if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return "data non nel formato AAAA-MM-GG: " s
    y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    if (y == m || y == d || m == d) return "anno, mese e giorno non tutti diversi: " s
    for (j = 1; j <= nrec; j++) { if (j == k) continue
      if (substr(txt(LB, j, 69, 10), 1, 4) + 0 == y) return "anno " y " anche nella data di riemissione del record " j
      if (substr(txt(LB, j, 69, 10), 6, 2) + 0 == m) return "mese " m " anche nella data di riemissione del record " j
      if (substr(txt(LB, j, 69, 10), 9, 2) + 0 == d) return "giorno " d " anche nella data di riemissione del record " j }
    for (j = 49; j <= 59; j += 10) { s = txt(LB, k, j, 10)
      if (substr(s, 1, 4) + 0 == y || substr(s, 6, 2) + 0 == m || substr(s, 9, 2) + 0 == d) return "componente uguale a quella di un altra data dello stesso conto: " s }
    return ""
  }
  FILENAME == FT { if ($0 ~ /^#/ || $0 ~ /^scenario\t/ || $0 == "") next
    if (NF != 8) { print "tabella, riga " FNR ": " NF " colonne, attese 8"; bad = 1; next }
    if ($1 != S) next
    nr++; K[nr] = $2; C[nr] = $3; P[nr] = $4 + 0; N[nr] = $5 + 0; Q[nr] = $6; A[nr] = $7; M[nr] = $8; next }
  FILENAME == FL { m = split($0, a, " "); for (i = 1; i <= m; i++) { if (a[i] !~ /^[0-9a-f][0-9a-f]$/) { print "token non esadecimale \"" a[i] "\" (od)"; rotto = 1 }; LB[++nl] = a[i] }; next }
  FILENAME == FE { m = split($0, a, " "); for (i = 1; i <= m; i++) { if (a[i] !~ /^[0-9a-f][0-9a-f]$/) { print "token non esadecimale \"" a[i] "\" (od)"; rotto = 1 }; EB[++ne] = a[i] }; next }
  END {
    if (rotto) exit 4
    if (bad) exit 4
    if (nr < 1) { print "nessuna proprieta per lo scenario " S; exit 4 }
    if (nl == 0 || nl % L != 0) { print "file letto di " nl " byte: non un multiplo positivo di " L; exit 4 }
    nrec = nl / L; nes = ne / L
    for (k = 1; k <= nrec; k++) { kk = txt(LB, k, 1, 11); REC[kk] = k }
    for (k = 1; k <= nes; k++) { kk = txt(EB, k, 1, 11); RES[kk] = k }
    for (r = 1; r <= nr; r++) {
      if (K[r] == "*") { da = 1; a2 = nrec } else { if (!(K[r] in REC)) { print "MANCA: " M[r] " (" K[r] "): chiave assente dal file letto"; err++; continue }; da = REC[K[r]]; a2 = da }
      for (k = da; k <= a2; k++) {
        q = Q[r]; f = ""
        if (q == "record-50") { if (nrec != 50) f = nrec " record" }
        else if (q == "zero") { zoned(LB, k, P[r], N[r]); if (!ZCAN || !ZZERO) f = "valore non zero canonico: " txt(LB, k, P[r], N[r]) }
        else if (q == "canonico") { zoned(LB, k, P[r], N[r]); if (!ZCAN) f = "rappresentazione non canonica: " txt(LB, k, P[r], N[r]) }
        else if (q == "negativo") { zoned(LB, k, P[r], N[r]); if (!ZCAN || ZSGN != "-" || ZZERO) f = "non negativo: " txt(LB, k, P[r], N[r]) }
        else if (q == "positivo") { zoned(LB, k, P[r], N[r]); if (!ZCAN || ZSGN != "+" || ZZERO) f = "non positivo: " txt(LB, k, P[r], N[r]) }
        else if (q == "cifre-9") { zoned(LB, k, P[r], N[r]); if (!ZOK || ZD !~ /^9+$/) f = "non tutte le cifre a 9: " txt(LB, k, P[r], N[r]) }
        else if (q == "zero-positivo") { if (hx(LB, k, P[r], N[r]) != "30303030303030303030307b") f = "byte " hx(LB, k, P[r], N[r]) }
        else if (q == "base-non-zero") { kk = txt(LB, k, 1, 11); if (!(kk in RES)) f = "conto assente dallo scenario esempio"; else { zoned(EB, RES[kk], P[r], N[r]); if (!ZOK || ZZERO) f = "nello scenario esempio il campo vale zero" } }
        else if (q == "diverso-campo") { if (hx(LB, k, P[r], N[r]) == hx(LB, k, A[r] + 0, N[r])) f = "uguale al campo alla posizione " A[r] }
        else if (q == "non-spazi") { if (txt(LB, k, P[r], N[r]) ~ /^ *$/) f = "solo spazi" }
        else if (q == "diverso-da") { if (txt(LB, k, P[r], N[r]) == A[r]) f = "uguale a " A[r] }
        else if (q == "data-unica") { f = dataok(k) }
        else if (q == "diverso-zero") { zoned(LB, k, P[r], N[r]); if (!ZOK || ZZERO) f = "vale zero: " txt(LB, k, P[r], N[r]) }
        else if (q == "zero-negativo") { if (hx(LB, k, P[r], N[r]) != "30303030303030303030307d") f = "byte " hx(LB, k, P[r], N[r]) }
        else if (q == "segno-alternativo") { zoned(LB, k, P[r], N[r]); if (!ZOK || !ZALT) f = "ultimo byte non cifra semplice: " txt(LB, k, P[r], N[r]) }
        else if (q == "primo") { if (k != 1) f = "record " k ", non il primo" }
        else f = "condizione sconosciuta: " q
        if (f != "") { print "MANCA: " M[r] " (" K[r] ", record " k ", " C[r] "): " f; err++ }
      }
      if (K[r] == "*") ok[r] = "tutti i " nrec " record"; else ok[r] = K[r]
    }
    if (err) exit 4
    for (r = 1; r <= nr; r++) printf "proprieta presente nel file letto: %s (%s, %s)\n", M[r], ok[r], Q[r]
  }' "$tab" "$lav/l.hex" "$lav/e.hex" > "$lav/esito" 2>&1 || r=$?
case "$r" in
  0) cat "$lav/esito" || die "esito non stampato (cat)" ;;
  4) cat "$lav/esito" >&2; rm -rf "$lav"; echo "proprieta.sh: PROPRIETA' MANCANTE nello scenario $scen" >&2; exit 4 ;;
  *) cat "$lav/esito" >&2; die "verifica non eseguita (awk, codice $r)" ;;
esac
rm -rf "$lav" || { echo "proprieta.sh: temporanei non rimossi: $lav" >&2; exit 1; }
