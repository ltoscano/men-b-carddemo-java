#!/usr/bin/env bash
# Coerenza tra la tabella dei casi di MVSWAIT, i casi di prova, gli attesi scritti a mano e le osservazioni
# (issue #36).
# Uso: mvswait-coerenza.sh TABELLA PROVE ATTESI OSSERVAZIONI OSSERVATI SCHEDE IMPRONTE JCL
#   TABELLA       mvswait-casi.tsv            PROVE      mvswait-prove.tsv       ATTESI    mvswait-attesi/
#   OSSERVAZIONI  mvswait-osservazioni.tsv    OSSERVATI  mvswait-osservati/
#   SCHEDE        cartella delle schede SYSIN di una corsa (<caso>.sysin)
#   IMPRONTE      una riga "<caso> <byte> <sha256>" per ogni scheda, calcolata nel container da chi chiama
#   JCL           app/jcl/WAITSTEP.jcl del legacy (sola lettura)
# Gira sull'host (bash e awk). Verifica:
#  1. la tabella: intestazione e righe ben formate; le classi, in ordine, coprono da 00000000 a FFFFFFFF
#     senza buchi ne' sovrapposizioni;
#  2. ogni caso: nome, programma e ingresso validi; per COBSWAIT la scheda della corsa e' quella ricavata
#     qui, indipendentemente, dalla riga 26 del JCL (senza il CR finale; per jcl:<cifre> con le colonne 1-8
#     sostituite), e il valore sono le sue prime 8 cifre; la classe che contiene il valore e' quella
#     dichiarata;
#  3. ogni atteso coincide, riga per riga, con quello che la tabella prescrive per quel valore (codice,
#     stdout di WAITPRB con l'argomento e i byte adiacenti invariati, riga su stderr, sezione == sysin con
#     byte e SHA-256 della scheda);
#  4. ci sono i casi obbligatori della specifica (argomenti 00000000, 00000001, 00000E10, 05F5E0FF,
#     05F5E100, 7FFFFFFF, 80000000, FFFFFFFF; COBSWAIT con la scheda del JCL e con altre 8 cifre); ogni
#     classe ha almeno un caso; nessun atteso senza caso;
#  5. le osservazioni sono separate dagli attesi: nomi diversi da quelli dei casi, programma COBSWAIT, un
#     rapporto osservato per caso e nessuno in piu', scheda conforme all'ingresso e sezione == sysin del
#     rapporto conforme alla scheda.
# Stampa una riga per ogni difetto; esce con 1 se ce n'e' almeno uno, con 2 per un uso sbagliato.
set -u
[ $# -eq 8 ] || { echo "uso: mvswait-coerenza.sh TABELLA PROVE ATTESI OSSERVAZIONI OSSERVATI SCHEDE IMPRONTE JCL" >&2; exit 2; }
tab="$1"; prove="$2"; att="$3"; oss="$4"; ossd="$5"; schede="$6"; impr="$7"; jcl="$8"
for f in "$tab" "$prove" "$oss" "$impr" "$jcl"; do [ -f "$f" ] || { echo "DIFETTO: file assente: $f"; exit 1; }; done
for d in "$att" "$ossd" "$schede"; do [ -d "$d" ] || { echo "DIFETTO: cartella assente: $d"; exit 1; }; done
# Elenchi dei rapporti presenti (nomi senza .txt), con l'esito di ogni comando controllato.
elenca() { # elenca CARTELLA: i nomi dei file .txt senza estensione, separati da spazi
  local n f s=""
  n="$(ls -A "$1")" || return 1
  for f in $n; do case "$f" in *.txt) s="$s ${f%.txt}" ;; esac; done
  echo "$s"
}
pres_att="$(elenca "$att")" || { echo "DIFETTO: cartella degli attesi non elencabile: $att"; exit 1; }
pres_oss="$(elenca "$ossd")" || { echo "DIFETTO: cartella delle osservazioni non elencabile: $ossd"; exit 1; }

LC_ALL=C awk -F'\t' -v tab="$tab" -v prove="$prove" -v att="$att" -v oss="$oss" -v ossd="$ossd" \
  -v schede="$schede" -v impr="$impr" -v jcl="$jcl" -v pres_att="$pres_att" -v pres_oss="$pres_oss" '
function err(m) { print "DIFETTO: " m; nerr++ }
# Valore di 8 cifre esadecimali maiuscole; -1 se non valide.
function hexval(h,   i, c, v) {
  if (h !~ /^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$/) return -1
  v = 0
  for (i = 1; i <= 8; i++) { c = index(HX, substr(h, i, 1)) - 1; v = v * 16 + c }
  return v
}
function tohex(v,   s, i, d) { s = ""; for (i = 0; i < 8; i++) { d = v % 16; s = substr(HX, d + 1, 1) s; v = (v - d) / 16 } return s }
function dec10(v) { return sprintf("%010.0f", v) }
function classe(v,   i) { for (i = 1; i <= nc; i++) if (v >= DA[i] && v <= A[i]) return i; return 0 }
# Prima riga di un file e numero di righe (in NR1 e NL).
function leggi(f,   l) { NL = 0; NR1 = ""; while ((getline l < f) > 0) { NL++; if (NL == 1) NR1 = l } close(f) }
# Confronto riga per riga di un file con E[1..m].
function confronta(caso, f, m, cl,   x, j, bad) {
  j = 0; bad = 0
  while ((getline x < f) > 0) {
    j++
    if (j > m || x != E[j]) { if (!bad) err(caso ": l atteso scritto a mano diverge dalla tabella (" cl ") alla riga " j ": \"" x "\" invece di \"" (j <= m ? E[j] : "fine del file") "\""); bad = 1 }
  }
  close(f)
  if (j == 0) err(caso ": atteso assente o vuoto: " f)
  else if (j < m && !bad) err(caso ": atteso troncato (" j " righe invece di " m ")")
}
BEGIN {
  HX = "0123456789ABCDEF"; hx = "0123456789abcdef"
  W = "Warning: program compiled against libxml 212 using older 209"
  Q = sprintf("%c", 39)
  # Riga 26 del JCL senza il CR finale: la scheda di riferimento, ricavata qui senza passare dal container.
  n = 0; RIF = ""
  while ((getline l < jcl) > 0) { n++; if (n == 26) { sub(/\r$/, "", l); RIF = l } }
  close(jcl)
  if (RIF == "") err("JCL: riga 26 assente o vuota: " jcl)
  # Impronte delle schede.
  while ((getline l < impr) > 0) {
    split(l, p, " ")
    if (p[1] !~ /^[A-Z0-9]+$/ || p[2] !~ /^[0-9]+$/ || p[3] !~ /^[0-9a-f]+$/ || length(p[3]) != 64) { err("impronte: riga non valida: " l); continue }
    IB[p[1]] = p[2]; IS[p[1]] = p[3]
  }
  close(impr)

  # 1. Tabella.
  nc = 0; hdr = 0
  while ((getline l < tab) > 0) {
    if (l ~ /^#/) continue
    if (!hdr) { hdr = 1; if (l != "classe\tda\ta\tesito\trighe\tmotivo") err("tabella: intestazione diversa da quella attesa"); continue }
    n = split(l, f, "\t")
    if (n != 6) { err("tabella: riga con " n " colonne invece di 6: " l); continue }
    if (f[1] !~ /^[A-Z][A-Z0-9]*$/) err("tabella: nome di classe non valido: " f[1])
    if (f[1] in CI) err("tabella: classe ripetuta: " f[1])
    nc++; C[nc] = f[1]; CI[f[1]] = nc; DA[nc] = hexval(f[2]); A[nc] = hexval(f[3]); ES[nc] = f[4]
    if (DA[nc] < 0 || A[nc] < 0) err("tabella " f[1] ": estremi non validi (8 cifre esadecimali maiuscole): " f[2] " " f[3])
    else if (DA[nc] > A[nc]) err("tabella " f[1] ": da maggiore di a")
    if (f[4] != "ritorno-0" && f[4] != "arresto-97") err("tabella " f[1] ": esito non valido: " f[4])
    if (f[5] == "" || f[6] == "") err("tabella " f[1] ": righe del sorgente o motivo assenti")
  }
  close(tab)
  if (nc == 0) err("tabella: nessuna classe")
  else {
    if (DA[1] != 0) err("tabella: la prima classe non parte da 00000000 (buco iniziale)")
    for (i = 2; i <= nc; i++) {
      if (DA[i] < A[i - 1] + 1) err("tabella: le classi " C[i - 1] " e " C[i] " si sovrappongono")
      else if (DA[i] > A[i - 1] + 1) err("tabella: buco tra le classi " C[i - 1] " e " C[i])
    }
    if (A[nc] != 4294967295) err("tabella: l ultima classe non arriva a FFFFFFFF (buco finale)")
  }

  # 2-3. Casi e attesi.
  hdr = 0
  split("00000000 00000001 00000E10 05F5E0FF 05F5E100 7FFFFFFF 80000000 FFFFFFFF", OB, " ")
  while ((getline l < prove) > 0) {
    if (l ~ /^#/) continue
    if (!hdr) { hdr = 1; if (l != "caso\tprogramma\tingresso\tclasse") err("casi: intestazione diversa da quella attesa"); continue }
    n = split(l, f, "\t")
    if (n != 4) { err("casi: riga con " n " colonne invece di 4: " l); continue }
    caso = f[1]; prog = f[2]; ingr = f[3]
    if (caso !~ /^[A-Z0-9]+$/) { err("casi: nome non valido: " caso); continue }
    if (caso in VISTO) err("casi: caso ripetuto: " caso); VISTO[caso] = 1
    if (prog == "WAITPRB") {
      v = hexval(ingr)
      if (v < 0) { err(caso ": argomento non valido (8 cifre esadecimali maiuscole): " ingr); continue }
      ARGV_[ingr] = 1
    } else if (prog == "COBSWAIT") {
      if (ingr == "jcl") { atteso_s = RIF; NJCL++ }
      else if (ingr ~ /^jcl:[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) {
        d = substr(ingr, 5); atteso_s = RIF
        if (substr(RIF, 1, 8) != "00003600") err(caso ": la riga 26 del JCL non inizia con 00003600")
        atteso_s = d substr(RIF, 9)
        if (d != "00003600") NALT++
      } else { err(caso ": ingresso non valido per COBSWAIT: " ingr); continue }
      leggi(schede "/" caso ".sysin")
      if (NL != 1 || NR1 != atteso_s) { err(caso ": scheda della corsa diversa da quella ricavata dalla riga 26 del JCL (" NL " righe): \"" NR1 "\""); continue }
      if (substr(NR1, 1, 8) !~ /^[0-9]+$/ || length(NR1) < 8) { err(caso ": le prime 8 colonne della scheda non sono cifre"); continue }
      if (!(caso in IB)) { err(caso ": impronta della scheda assente"); continue }
      if (IB[caso] != length(NR1) + 1) err(caso ": la scheda ha " IB[caso] " byte invece di " (length(NR1) + 1))
      v = substr(NR1, 1, 8) + 0
    } else { err(caso ": programma non valido: " prog); continue }
    r = classe(v)
    if (!r) { err(caso ": nessuna classe della tabella contiene il valore " tohex(v)); continue }
    if (C[r] != f[4]) { err(caso ": dichiarato della classe " f[4] ", ma per la tabella il valore " tohex(v) " e della classe " C[r]); continue }
    COPERTA[C[r]]++
    H = tohex(v); h = tolower(H); m = 0
    E[++m] = "== codice di uscita"
    E[++m] = (ES[r] == "ritorno-0") ? "0" : "97"
    E[++m] = "== stdout"
    if (prog == "WAITPRB") {
      E[++m] = "PRIMA a5a5a5a5 " h " a5a5a5a5"
      if (ES[r] == "ritorno-0") { E[++m] = "RC  000000000"; E[++m] = "DOPO  a5a5a5a5 " h " a5a5a5a5" }
    }
    E[++m] = "== stderr"; E[++m] = W
    if (ES[r] == "ritorno-0") E[++m] = "MENB-ORACLE MVSWAIT: ATTESA RICHIESTA " dec10(v) " (X" Q H Q ") CENTESIMI DI SECONDO, NON ESEGUITA"
    else E[++m] = "MENB-ORACLE MVSWAIT: ATTESA RICHIESTA " dec10(v) " (X" Q H Q ") OLTRE X" Q "7FFFFFFF" Q ": ABEND X" Q "12F" Q " DI STIMER NON RIPRODOTTO"
    E[++m] = "== file nella cartella di lavoro"
    if (prog == "COBSWAIT") { E[++m] = "== sysin"; E[++m] = "fornito: " IB[caso] " byte, sha256 " IS[caso] }
    confronta(caso, att "/" caso ".txt", m, C[r])
  }
  close(prove)

  # 4. Casi obbligatori, classi coperte, attesi senza caso.
  for (i = 1; i <= 8; i++) if (!(OB[i] in ARGV_)) err("casi: manca il caso WAITPRB con argomento " OB[i])
  if (NJCL < 1) err("casi: manca il caso COBSWAIT con la scheda del JCL (ingresso jcl)")
  if (NALT < 1) err("casi: manca il caso COBSWAIT con altre 8 cifre (ingresso jcl:<cifre>)")
  for (i = 1; i <= nc; i++) if (!(C[i] in COPERTA)) err("tabella: la classe " C[i] " non ha casi di prova")
  np = split(pres_att, P, " ")
  for (i = 1; i <= np; i++) if (!(P[i] in VISTO)) err("attesi: " P[i] ".txt non corrisponde a nessun caso")

  # 5. Osservazioni.
  hdr = 0
  while ((getline l < oss) > 0) {
    if (l ~ /^#/) continue
    if (!hdr) { hdr = 1; if (l != "caso\tprogramma\tingresso\tprevisione") err("osservazioni: intestazione diversa da quella attesa"); continue }
    n = split(l, f, "\t")
    if (n != 4) { err("osservazioni: riga con " n " colonne invece di 4: " l); continue }
    caso = f[1]
    if (caso !~ /^[A-Z0-9]+$/) { err("osservazioni: nome non valido: " caso); continue }
    if (caso in VISTO) err("osservazioni: " caso " e anche un caso ricavato dal sorgente: le osservazioni devono restare separate")
    if (caso in OVISTO) err("osservazioni: caso ripetuto: " caso); OVISTO[caso] = 1
    if (f[2] != "COBSWAIT") err("osservazioni: " caso ": programma diverso da COBSWAIT: " f[2])
    leggi(schede "/" caso ".sysin")
    if (f[3] == "vuoto") { if (NL != 0 || IB[caso] != 0) err("osservazioni: " caso ": la scheda non e vuota") }
    else if (f[3] ~ /^testo:/) { if (NL != 1 || NR1 != substr(f[3], 7) || IB[caso] != length(NR1) + 1) err("osservazioni: " caso ": scheda diversa dal testo dichiarato") }
    else err("osservazioni: " caso ": ingresso non valido: " f[3])
    if (!(caso in IB)) { err("osservazioni: " caso ": impronta della scheda assente"); continue }
    # Sezione == sysin del rapporto osservato: le ultime due righe.
    of = ossd "/" caso ".txt"; j = 0; u1 = ""; u2 = ""
    while ((getline x < of) > 0) { j++; u1 = u2; u2 = x }
    close(of)
    if (j == 0) { err("osservazioni: " caso ": rapporto osservato assente o vuoto"); continue }
    if (u1 != "== sysin" || u2 != "fornito: " IB[caso] " byte, sha256 " IS[caso]) err("osservazioni: " caso ": sezione == sysin del rapporto osservato diversa dalla scheda")
  }
  close(oss)
  np = split(pres_oss, P, " ")
  for (i = 1; i <= np; i++) if (!(P[i] in OVISTO)) err("osservati: " P[i] ".txt non corrisponde a nessuna osservazione")

  if (nerr) { print "coerenza fallita: " nerr " difetti"; exit 1 }
  print "coerenza riuscita: " nc " classi da 00000000 a FFFFFFFF; attesi conformi alla tabella; osservazioni separate"
}'
