#!/bin/sh
# Eseguito DENTRO il container dell'oracle (issue #55). Controllo dedicato degli scenari derivati, indipendente da
# prepara.sh (che scrive le sostituzioni): la differenza COMPLETA tra il file derivato e il file base coincide
# esattamente con la tabella delle sostituzioni.
#   - stessa dimensione, multipla di 300, stesse chiavi negli stessi record;
#   - il file atteso (la base con i byte della tabella sovrapposti) e' identico byte per byte al derivato: nessun altro
#     byte cambia, e ogni byte della tabella c'e';
#   - ogni riga della tabella cambia almeno un byte della base, e le righe non si sovrappongono;
#   - ogni sostituzione, decodificata con le regole di #23 (docs/legacy-map/data-contract/codifica.md), ha il valore
#     della colonna "valore" e la canonicita' della colonna "canonica" (zoned: corpo di cifre 30-39, ultimo byte
#     { A-I positivo, } J-R negativo, 30-39 cifra semplice = forma alternativa positiva, non canonica; lo zero con }
#     e' lo zero negativo, non canonico; alfa: i byte sono il testo).
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0 riuscito; 1 errore dello strumento; 4 differenza.
# Uso: differenze.sh BASE TABELLA DERIVATO
set -u
L=300
die() { echo "differenze.sh: $*" >&2; [ -z "${lav:-}" ] || rm -rf "$lav"; exit 1; }
[ $# -eq 3 ] || die "uso: differenze.sh BASE TABELLA DERIVATO"
base="$1"; tab="$2"; der="$3"; lav=""
for f in "$base" "$tab" "$der"; do [ -f "$f" ] || die "file assente: $f"; done
lav="$(mktemp -d /tmp/issue55-differenze.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
od -An -v -tx1 "$base" > "$lav/b.hex" || die "lettura della base fallita (od)"
od -An -v -tx1 "$der" > "$lav/d.hex" || die "lettura del derivato fallita (od)"
r=0
awk -F '\t' -v L="$L" -v FT="$tab" -v FB="$lav/b.hex" -v FD="$lav/d.hex" '
  function bv(x) { return index("0123456789abcdef", substr(x, 1, 1)) * 16 + index("0123456789abcdef", substr(x, 2, 1)) - 17 }
  # zoned: decodifica dei byte v[1..n]; imposta ZOK, ZVAL (testo +intero.decimali), ZCAN
  function zoned(n,   i, d, s, c, alt, zero, ip) {
    ZOK = 1; d = ""; alt = 0
    for (i = 1; i < n; i++) { if (v[i] < 48 || v[i] > 57) ZOK = 0; d = d sprintf("%c", v[i]) }
    c = v[n]
    if (c >= 48 && c <= 57) { d = d (c - 48); s = "+"; alt = 1 }
    else if (c == 123) { d = d "0"; s = "+" }
    else if (c >= 65 && c <= 73) { d = d (c - 64); s = "+" }
    else if (c == 125) { d = d "0"; s = "-" }
    else if (c >= 74 && c <= 82) { d = d (c - 73); s = "-" }
    else ZOK = 0
    if (!ZOK) { ZVAL = "?"; ZCAN = "no"; return }
    zero = (d ~ /^0+$/)
    ip = substr(d, 1, n - 2); sub(/^0+/, "", ip); if (ip == "") ip = "0"
    ZVAL = s ip "." substr(d, n - 1, 2)
    ZCAN = (alt || (s == "-" && zero)) ? "no" : "si"
  }
  FILENAME == FT { if ($0 ~ /^#/ || $0 ~ /^chiave\t/ || $0 == "") next
    if (NF != 9) { print "tabella, riga " FNR ": " NF " colonne, attese 9"; bad = 1; next }
    nr++; K[nr] = $1; C[nr] = $2; P[nr] = $3 + 0; N[nr] = $4 + 0; X[nr] = $5; T[nr] = $6; V[nr] = $7; Q[nr] = $8; next }
  FILENAME == FB { m = split($0, a, " "); for (i = 1; i <= m; i++) { if (a[i] !~ /^[0-9a-f][0-9a-f]$/) { print "token non esadecimale \"" a[i] "\" (od)"; rotto = 1 }; B[++nb] = a[i] }; next }
  FILENAME == FD { m = split($0, a, " "); for (i = 1; i <= m; i++) { if (a[i] !~ /^[0-9a-f][0-9a-f]$/) { print "token non esadecimale \"" a[i] "\" (od)"; rotto = 1 }; D[++nd] = a[i] }; next }
  END {
    if (rotto) exit 4
    if (bad) exit 4
    if (nr < 1) { print "tabella senza righe"; exit 4 }
    if (nb != nd) { print "dimensioni diverse: base " nb " byte, derivato " nd; exit 4 }
    if (nb == 0 || nb % L != 0) { print "dimensione " nb " non multipla positiva di " L; exit 4 }
    nrec = nb / L
    for (k = 1; k <= nrec; k++) { kb = ""; kd = ""
      for (i = 1; i <= 11; i++) { kb = kb sprintf("%c", bv(B[(k - 1) * L + i])); kd = kd sprintf("%c", bv(D[(k - 1) * L + i])) }
      if (kb in REC) { print "chiave doppia nella base: " kb; exit 4 }
      REC[kb] = k; if (kb != kd) { print "record " k ": chiave del derivato " kd " diversa da quella della base " kb; err++ } }
    for (j = 1; j <= nb; j++) E[j] = B[j]
    for (r = 1; r <= nr; r++) {
      if (!(K[r] in REC)) { print "riga " r ": chiave " K[r] " assente dalla base"; err++; continue }
      if (length(X[r]) != 2 * N[r] || P[r] < 1 || P[r] + N[r] - 1 > L) { print "riga " r ": posizione, lunghezza o byte incoerenti"; err++; continue }
      cambia = 0
      for (i = 0; i < N[r]; i++) { o = (REC[K[r]] - 1) * L + P[r] + i; x = substr(X[r], 2 * i + 1, 2)
        if (o in USO) { print "riga " r ": il byte " o " e anche nella riga " USO[o]; err++ }
        USO[o] = r; if (x != B[o]) cambia = 1; E[o] = x; v[i + 1] = bv(x) }
      if (!cambia) { print "riga " r " (" K[r] " " C[r] "): non cambia alcun byte della base"; err++ }
      if (T[r] == "zoned") { zoned(N[r])
        if (!ZOK) { print "riga " r " (" K[r] " " C[r] "): byte non validi per un DISPLAY con segno"; err++ }
        else { if (ZVAL != V[r]) { print "riga " r " (" K[r] " " C[r] "): valore decodificato " ZVAL ", atteso " V[r]; err++ }
               if (ZCAN != Q[r]) { print "riga " r " (" K[r] " " C[r] "): canonica " ZCAN ", dichiarata " Q[r]; err++ } } }
      else if (T[r] == "alfa") { s = ""; for (i = 1; i <= N[r]; i++) s = s sprintf("%c", v[i])
        if (s != V[r]) { print "riga " r " (" K[r] " " C[r] "): testo \"" s "\", atteso \"" V[r] "\""; err++ }
        if (Q[r] != "si") { print "riga " r ": un alfanumerico e sempre canonico"; err++ } }
      else { print "riga " r ": tipo sconosciuto " T[r]; err++ }
      nbt += N[r]; ok++
    }
    for (j = 1; j <= nb; j++) if (E[j] != D[j]) { nd2++; if (nd2 <= 10) printf "byte %d (record %d, posizione %d): atteso %s, nel derivato %s\n", j, int((j - 1) / L) + 1, (j - 1) % L + 1, E[j], D[j] }
    if (nd2) { print nd2 " byte del derivato diversi dalla base con le sole sostituzioni della tabella"; err++ }
    if (err) exit 4
    printf "differenze: %d record; il derivato e la base differiscono esattamente nelle %d sostituzioni della tabella (%d byte), valori e canonicita come dichiarati\n", nrec, ok, nbt
  }' "$tab" "$lav/b.hex" "$lav/d.hex" > "$lav/esito" 2>&1 || r=$?
case "$r" in
  0) cat "$lav/esito" || die "esito non stampato (cat)" ;;
  4) cat "$lav/esito" >&2; rm -rf "$lav"; echo "differenze.sh: DIFFERENZA tra derivato e tabella: $der" >&2; exit 4 ;;
  *) cat "$lav/esito" >&2; die "confronto non eseguito (awk, codice $r)" ;;
esac
rm -rf "$lav" || { echo "differenze.sh: temporanei non rimossi: $lav" >&2; exit 1; }
