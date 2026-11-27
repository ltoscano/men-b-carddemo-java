#!/usr/bin/env bash
# Coerenza tra la tabella dei casi di COBDATFT, l'elenco dei casi di prova e gli attesi scritti a mano.
# Uso: coerenza.sh TABELLA.tsv CASI.tsv CARTELLA-ATTESI
# Gira sull'host (bash e awk, nessun programma compilato). Verifica:
#  1. la tabella: righe ben formate; per ogni combinazione di selettori (tipo d'ingresso 1, 2, altro;
#     tipo d'uscita 1, 2, altro; byte 6-19 dell'area uguali a '-INVALID INPUT', diversi solo nell'ultimo
#     byte, diversi nel primo) una e una sola riga; per le righe
#     determinate scritture e byte conservati coprono esattamente i byte 1-80, senza sovrapposizioni;
#     per le non determinate nessuna scrittura;
#  2. ogni caso di prova: PARM valido; la riga della tabella che gli corrisponde e' quella dichiarata;
#  3. ogni atteso scritto a mano coincide, riga per riga, con quello che la tabella prescrive per quel
#     PARM: area di partenza (X'A5' piu' i byte del PARM), per i determinati codice 0, RC 0 e area dopo
#     la CALL = area di partenza con le sole scritture della riga; per i non determinati codice 97, solo
#     la riga PRIMA e il messaggio di arresto;
#  4. ogni riga della tabella ha almeno un caso; almeno due casi non determinati; nessun atteso senza caso.
# Stampa una riga per ogni difetto; esce con 1 se ce n'e' almeno uno.
set -u
[ $# -eq 3 ] || { echo "uso: coerenza.sh TABELLA.tsv CASI.tsv CARTELLA-ATTESI" >&2; exit 2; }
tab="$1"; casi="$2"; exp="$3"
for f in "$tab" "$casi"; do [ -f "$f" ] || { echo "DIFETTO: file assente: $f"; exit 1; }; done
[ -d "$exp" ] || { echo "DIFETTO: cartella degli attesi assente: $exp"; exit 1; }
# Attesi presenti (nomi senza .txt), per il controllo "nessun atteso senza caso".
presenti="$(cd "$exp" && ls -A | sed -n 's/\.txt$//p' | LC_ALL=C sort | tr '\n' ' ')"

LC_ALL=C awk -F'\t' -v tab="$tab" -v casi="$casi" -v dirattesi="$exp" -v presenti="$presenti" '
function err(m) { print "DIFETTO: " m; nerr++ }
function hex(c) { return (c in H) ? H[c] : "" }
# Il valore v (un carattere) soddisfa lo schema s del selettore?
function sel(s, v) {
  if (s == "qualsiasi") return 1
  if (s == "altro") return (v != "1" && v != "2")
  if (s ~ /^non-[12]$/) return (v != substr(s, 5, 1))
  return (v == s)
}
# p = byte 6-19 dell area (14 caratteri; un byte di riempimento X-A5 vale "~", diverso da ogni carattere
# del prefisso), confrontati con i 14 byte noti del pool dei letterali.
function cond(c, p) { if (c == "-") return 1; if (c == "byte6-19=" PREF) return (p == PREF); return (p != PREF) }
# Riga della tabella che corrisponde ai selettori; "" se nessuna, "*" se piu di una.
function riga(ti, tu, b6,   i, r) {
  r = ""
  for (i = 1; i <= nr; i++)
    if (sel(TI[i], ti) && sel(TU[i], tu) && cond(CO[i], b6)) r = (r == "") ? i : "*"
  return r
}
# Formato di una riga di stampa: i cinque campi in esadecimale separati da spazi.
function fmt(a,   s, k) {
  s = a[1] " "; for (k = 2; k <= 21; k++) s = s a[k]
  s = s " " a[22] " "; for (k = 23; k <= 42; k++) s = s a[k]
  s = s " "; for (k = 43; k <= 80; k++) s = s a[k]
  return s
}
BEGIN {
  for (i = 32; i < 127; i++) H[sprintf("%c", i)] = sprintf("%02x", i)
  PREF = "-INVALID INPUT"
  W = "Warning: program compiled against libxml 212 using older 209"
  MSG = "MENB-ORACLE COBDATFT: caso non riproducibile dall" sprintf("%c", 39) "oracle"
  # 1. Tabella.
  nr = 0; hdr = 0
  while ((getline l < tab) > 0) {
    if (l ~ /^#/) continue
    if (!hdr) { hdr = 1; if (l != "combinazione\ttipo_ingresso\ttipo_uscita\tcondizione\tesito\tscritture\tconservati\trighe_asm\tmotivo") err("tabella: intestazione diversa da quella attesa"); continue }
    n = split(l, f, "\t")
    if (n != 9) { err("tabella: riga con " n " colonne invece di 9: " l); continue }
    nr++; C[nr] = f[1]; TI[nr] = f[2]; TU[nr] = f[3]; CO[nr] = f[4]; ES[nr] = f[5]; SC[nr] = f[6]; CS[nr] = f[7]
    if (f[1] in IDX) err("tabella: combinazione ripetuta: " f[1]); IDX[f[1]] = nr
    for (j = 2; j <= 3; j++) if (f[j] !~ /^([12]|non-[12]|altro|qualsiasi)$/) err("tabella " f[1] ": selettore non valido: " f[j])
    if (f[4] != "-" && f[4] != "byte6-19=" PREF && f[4] != "byte6-19!=" PREF) err("tabella " f[1] ": condizione non valida: " f[4])
    if (f[8] !~ /^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$/) err("tabella " f[1] ": righe dell assembler non valide: " f[8])
    if (f[5] == "non-determinato") {
      if (f[6] != "-" || f[7] != "-") err("tabella " f[1] ": un caso non determinato non ha scritture ne byte conservati")
    } else if (f[5] == "determinato") {
      delete U
      ns = split(f[6], s, ";")
      for (j = 1; j <= ns; j++) {
        if (match(s[j], /^[0-9]+-[0-9]+<[0-9]+-[0-9]+$/)) {
          split(s[j], p, "[-<]")
          if (p[2] - p[1] != p[4] - p[3] || p[1] > p[2] || p[1] < 1 || p[2] > 80 || p[3] < 1 || p[4] > 80) err("tabella " f[1] ": copia non valida: " s[j])
          for (k = p[1]; k <= p[2]; k++) U[k]++
        } else if (match(s[j], /^[0-9]+=[0-9a-f][0-9a-f]$/)) {
          split(s[j], p, "="); if (p[1] < 1 || p[1] > 80) err("tabella " f[1] ": scrittura fuori area: " s[j]); U[p[1]]++
        } else err("tabella " f[1] ": scrittura non valida: " s[j])
      }
      nc = split(f[7], s, ";")
      for (j = 1; j <= nc; j++) {
        if (!match(s[j], /^[0-9]+-[0-9]+$/)) { err("tabella " f[1] ": intervallo conservato non valido: " s[j]); continue }
        split(s[j], p, "-")
        if (p[1] < 1 || p[2] > 80 || p[1] > p[2]) err("tabella " f[1] ": intervallo conservato fuori area: " s[j])
        for (k = p[1]; k <= p[2]; k++) U[k]++
      }
      for (k = 1; k <= 80; k++) if (U[k] != 1) err("tabella " f[1] ": il byte " k " e scritto o conservato " (U[k] + 0) " volte invece di una")
    } else err("tabella " f[1] ": esito non valido: " f[5])
  }
  close(tab)
  if (nr == 0) err("tabella: nessuna riga")
  # Ogni combinazione di selettori ha una e una sola riga.
  split("1 2 x", V, " "); Q[1] = PREF; Q[2] = "-INVALID INPUX"; Q[3] = "xINVALID INPUT"
  for (a = 1; a <= 3; a++) for (b = 1; b <= 3; b++) for (c = 1; c <= 3; c++) {
    b6 = Q[c]; r = riga(V[a], V[b], b6)
    if (r == "") err("tabella: nessuna riga per ingresso " V[a] ", uscita " V[b] ", byte 6-19 " b6)
    else if (r == "*") err("tabella: piu righe per ingresso " V[a] ", uscita " V[b] ", byte 6-19 " b6)
  }
  # 2-3. Casi e attesi.
  hdr = 0; nnd = 0
  while ((getline l < casi) > 0) {
    if (l ~ /^#/) continue
    if (!hdr) { hdr = 1; if (l != "caso\tparm\tcombinazione") err("casi: intestazione diversa da quella attesa"); continue }
    n = split(l, f, "\t")
    if (n != 3) { err("casi: riga con " n " colonne invece di 3: " l); continue }
    caso = f[1]; parm = f[2]
    if (caso in VISTO) err("casi: caso ripetuto: " caso); VISTO[caso] = 1
    if (length(parm) < 2 || length(parm) > 22) { err(caso ": PARM di lunghezza " length(parm) " (ammessa 2-22)"); continue }
    ok = 1; for (k = 1; k <= length(parm); k++) if (hex(substr(parm, k, 1)) == "") ok = 0
    if (substr(parm, 1, 1) == " " || substr(parm, length(parm), 1) == " ") ok = 0
    if (!ok) { err(caso ": PARM con caratteri non stampabili o spazi iniziali o finali"); continue }
    b6 = substr(parm, 7, 14); while (length(b6) < 14) b6 = b6 "~"
    r = riga(substr(parm, 1, 1), substr(parm, 2, 1), b6)
    if (r == "" || r == "*") { err(caso ": nessuna riga (o piu righe) della tabella per il PARM " parm); continue }
    if (C[r] != f[3]) { err(caso ": dichiarato " f[3] ", ma per la tabella il PARM " parm " e della combinazione " C[r]); continue }
    COPERTA[C[r]]++
    # Area di partenza.
    delete A; for (k = 1; k <= 80; k++) A[k] = "a5"
    A[1] = hex(substr(parm, 1, 1)); A[22] = hex(substr(parm, 2, 1))
    for (k = 3; k <= length(parm); k++) A[k - 1] = hex(substr(parm, k, 1))
    m = 0
    E[++m] = "== codice di uscita"
    if (ES[r] == "determinato") {
      for (k = 1; k <= 80; k++) D[k] = A[k]
      ns = split(SC[r], s, ";")
      for (j = 1; j <= ns; j++) {
        if (index(s[j], "<")) { split(s[j], p, "[-<]"); for (k = 0; k <= p[2] - p[1]; k++) D[p[1] + k] = A[p[3] + k] }
        else { split(s[j], p, "="); D[p[1]] = p[2] }
      }
      E[++m] = "0"; E[++m] = "== stdout"; E[++m] = "PRIMA " fmt(A); E[++m] = "RC  000000000"; E[++m] = "DOPO  " fmt(D)
      E[++m] = "== stderr"; E[++m] = W
    } else {
      nnd++
      E[++m] = "97"; E[++m] = "== stdout"; E[++m] = "PRIMA " fmt(A); E[++m] = "== stderr"; E[++m] = W; E[++m] = MSG
    }
    E[++m] = "== file nella cartella di lavoro"
    ef = dirattesi "/" caso ".txt"; j = 0; bad = 0
    while ((getline x < ef) > 0) { j++; if (j > m || x != E[j]) { if (!bad) err(caso ": l atteso scritto a mano diverge dalla tabella (" C[r] ") alla riga " j ": \"" x "\" invece di \"" (j <= m ? E[j] : "fine del file") "\""); bad = 1 } }
    if (j == 0) err(caso ": atteso assente o vuoto: " ef)
    else if (j < m && !bad) err(caso ": atteso troncato (" j " righe invece di " m ")")
    close(ef)
  }
  close(casi)
  for (i = 1; i <= nr; i++) if (!(C[i] in COPERTA)) err("tabella: la combinazione " C[i] " non ha casi di prova")
  if (nnd < 2) err("casi: " nnd " casi non determinati, ne servono almeno 2")
  np = split(presenti, P, " ")
  for (i = 1; i <= np; i++) if (!(P[i] in VISTO)) err("attesi: " P[i] ".txt non corrisponde a nessun caso")
  if (nerr) { print "coerenza fallita: " nerr " difetti"; exit 1 }
  print "coerenza riuscita: " nr " combinazioni, una per ogni selezione; attesi conformi alla tabella"
}'
