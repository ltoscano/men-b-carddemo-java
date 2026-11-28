#!/bin/sh
# VERIFICATORE INDIPENDENTE (issue #55, controllo 4). Non esegue COBOL, non usa alcuno script che produce i golden
# (prepara, scenario, estrai-vb, maschera, attesi, conteggi, coerenza): ha il proprio lettore dei file, il proprio
# lettore del file a record variabili e le proprie regole di codifica. Si lancia da solo su una cartella data, nel
# container dell'oracle (servono solo sh, od e awk), per esempio:
#   docker run --rm -v "$PWD/oracle:/oracle:ro" <immagine dell'oracle> sh /oracle/golden/verificatore.sh \
#     mirato /oracle/golden/readacct/generati/golden/mirato/ingresso.rec /oracle/golden/readacct/generati/golden/mirato \
#     /oracle/golden/readacct/campi.tsv /oracle/golden/readacct/esclusioni.tsv
# Per OGNI record dello scenario controlla OGNI campo di uscita contro il record d'ingresso, sui byte, con la tabella
# scritta a mano CAMPI (campo d'uscita <- campo d'ingresso, costante o trasformazione, riga del sorgente):
#   - OUTFILE e ARRYFILE: il riferimento di parita' (OUTFILE.riferimento.txt, ARRYFILE.riferimento.txt: byte in
#     esadecimale, ** nelle posizioni escluse, correzioni dell'oracle gia' applicate). Questo verificatore NON legge la
#     tabella delle correzioni: il byte atteso viene dalla regola del linguaggio scritta qui;
#   - VBRCFILE: il file fisico, letto qui (formato GnuCOBOL COB_VARSEQ_FORMAT 0: 2 byte di lunghezza big-endian senza
#     l'intestazione, 2 byte 00), tracciati logici VBRC-REC1 (12 byte) e VBRC-REC2 (39 byte), CBACT01C.cbl:123-130;
#   - regole proprie: copia (byte d'ingresso); copia-segno (byte d'ingresso solo se la rappresentazione d'ingresso e'
#     canonica: corpo di cifre 30-39, ultimo byte { A-I, oppure } J-R con valore non zero; altrimenti il risultato
#     dipende da NUMPROC e la posizione deve essere esclusa); data (byte 1-4 <- 1-4, 5-6 <- 6-7, 7-8 <- 9-10 della
#     data d'ingresso, COBDATFT.asm:51-53; 9-10 non determinati); debito (debito d'ingresso zero -> COMP-3 di +2525.00,
#     altrimenti non determinato); zoned (12 cifre, ultima con segno sovrapposto: { A-I positivo o zero, } J-R
#     negativo); packed (semiottetto di riempimento 0, 12 cifre, segno C positivo o zero, D negativo); spazi (20);
#   - le posizioni non determinate sono ESATTAMENTE quelle della tabella ESCLUSIONI per lo scenario e il record, e nei
#     riferimenti sono ESATTAMENTE quelle mascherate con **; nessuna esclusione senza motivo o senza riga del sorgente;
#   - numero di record: N d'ingresso, N in OUTFILE e ARRYFILE, 2N record logici alternati 12 e 39 byte;
#   - rapporto.txt (esegui.sh): codice di uscita 0; stdout = 2 + 15 x N righe, ognuna ricavata qui dal record
#     d'ingresso (letterali delle righe 141, 201-212, 283-284, 151, 158; numerici con segno nella forma di GnuCOBOL,
#     12 cifre e il segno in coda, con il valore del campo d'ingresso: e' la regola che riconduce la riga alla forma
#     IBM, dove la stessa cifra porta il segno sovrapposto); stderr = l'avviso di libxml2 e le tre chiusure implicite;
#     file creati: OUTFILE 107 x N, ARRYFILE 110 x N, VBRCFILE della dimensione letta.
# Uscite: 0 tutto conforme; 1 errore dello strumento; 4 difformita' (elencate).
# Uso: verificatore.sh SCENARIO INGRESSO DIR CAMPI ESCLUSIONI
set -u
die() { echo "verificatore.sh: $*" >&2; [ -z "${tmpv:-}" ] || rm -rf "$tmpv"; exit 1; }
[ $# -eq 5 ] || die "uso: verificatore.sh SCENARIO INGRESSO DIR CAMPI ESCLUSIONI"
S="$1"; ING="$2"; D="$3"; CAMPI="$4"; ESCL="$5"; tmpv=""
for f in "$ING" "$D/OUTFILE.riferimento.txt" "$D/ARRYFILE.riferimento.txt" "$D/VBRCFILE" "$D/rapporto.txt" "$CAMPI" "$ESCL"; do
  [ -f "$f" ] || die "file assente: $f"
done
tmpv="$(mktemp -d /tmp/issue55-verificatore.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
od -An -v -tx1 "$ING" > "$tmpv/ingresso.hex" || die "od dell'ingresso fallito"
od -An -v -tx1 "$D/VBRCFILE" > "$tmpv/vb.hex" || die "od di VBRCFILE fallito"
esito=0
awk -F '\t' -v SC="$S" -v F1="$CAMPI" -v F2="$ESCL" -v F3="$tmpv/ingresso.hex" -v F4="$D/OUTFILE.riferimento.txt" \
    -v F5="$D/ARRYFILE.riferimento.txt" -v F6="$tmpv/vb.hex" -v F7="$D/rapporto.txt" '
  BEGIN {
    LUNG["OUTFILE"] = 107; LUNG["ARRYFILE"] = 110; LUNG["VBRC1"] = 12; LUNG["VBRC2"] = 39
    for (i = 0; i < 256; i++) { HX[i] = sprintf("%02x", i); VAL[HX[i]] = i; CH[i] = sprintf("%c", i) }
    TR["copia"] = 1; TR["copia-segno"] = 1; TR["data"] = 1; TR["debito"] = 1; TR["zoned"] = 1; TR["packed"] = 1; TR["spazi"] = 1
  }
  function difetto(m) { nd++; if (nd <= 40) print "DIFFORME: " m }
  # --- regole di codifica, scritte qui -----------------------------------------------------------------------------
  # cifre12(v): "+1025.00" -> "000000102500"; SEGNO globale "+" o "-"
  function cifre12(v,   s, ip, dp) {
    s = substr(v, 1, 1); if (s != "+" && s != "-") return ""
    SEGNO = s; v = substr(v, 2); ip = v; dp = ""
    if (index(v, ".") > 0) { ip = substr(v, 1, index(v, ".") - 1); dp = substr(v, index(v, ".") + 1) }
    if (ip !~ /^[0-9]+$/ || dp !~ /^[0-9][0-9]$/ || length(ip) > 10) return ""
    while (length(ip) < 10) ip = "0" ip
    return ip dp
  }
  function zonato(v,   d, u, i, s) {          # costante -> 12 byte esadecimali
    d = cifre12(v); if (d == "") return ""
    s = ""; for (i = 1; i <= 11; i++) s = s HX[47 + index("0123456789", substr(d, i, 1))]
    u = substr(d, 12, 1) + 0
    if (SEGNO == "+" || d ~ /^0+$/) s = s (u == 0 ? "7b" : HX[64 + u]); else s = s (u == 0 ? "7d" : HX[73 + u])
    return s
  }
  function impaccato(v,   d) {                 # costante -> 7 byte esadecimali
    d = cifre12(v); if (d == "") return ""
    return "0" d ((SEGNO == "-" && d !~ /^0+$/) ? "d" : "c")
  }
  # lettura di un DISPLAY con segno dai byte d ingresso: ZC canonico, ZZ zero, ZG cifre (12), ZS segno
  function leggi_zonato(k, a, n,   i, c, u) {
    ZC = 1; ZG = ""
    for (i = 0; i < n - 1; i++) { c = IN[(k - 1) * 300 + a + i]; if (c < 48 || c > 57) ZC = 0; ZG = ZG CH[c] }
    u = IN[(k - 1) * 300 + a + n - 1]
    if (u == 123) { ZG = ZG "0"; ZS = "+" } else if (u >= 65 && u <= 73) { ZG = ZG (u - 64); ZS = "+" }
    else if (u == 125) { ZG = ZG "0"; ZS = "-" } else if (u >= 74 && u <= 82) { ZG = ZG (u - 73); ZS = "-" }
    else if (u >= 48 && u <= 57) { ZG = ZG (u - 48); ZS = "+"; ZC = 0 } else { ZC = 0; ZG = ZG "?"; ZS = "?" }
    ZZ = (ZG ~ /^0+$/); if (ZS == "-" && ZZ) ZC = 0
  }
  function byte_in(k, a, i) { return HX[IN[(k - 1) * 300 + a + i]] }
  function testo_in(k, a, n,   i, s) { s = ""; for (i = 0; i < n; i++) s = s CH[IN[(k - 1) * 300 + a + i]]; return s }
  # atteso(F, k): riempie ATT[1..LUNG[F]] (esadecimale, oppure "ND") dalle righe di CAMPI del file F
  function atteso(F, k,   r, p, n, a, i, x) {
    for (r = 1; r <= nc; r++) { if (CF[r] != F) continue
      p = CP[r]; n = CN[r]; a = CA[r]
      if (CT[r] == "copia") for (i = 0; i < n; i++) ATT[p + i] = byte_in(k, a, i)
      else if (CT[r] == "copia-segno") { leggi_zonato(k, a, n); for (i = 0; i < n; i++) ATT[p + i] = ZC ? byte_in(k, a, i) : "ND" }
      else if (CT[r] == "data") { for (i = 0; i < 4; i++) ATT[p + i] = byte_in(k, a, i)
        ATT[p + 4] = byte_in(k, a, 5); ATT[p + 5] = byte_in(k, a, 6); ATT[p + 6] = byte_in(k, a, 8); ATT[p + 7] = byte_in(k, a, 9)
        for (i = 8; i < n; i++) ATT[p + i] = "ND" }
      else if (CT[r] == "debito") { leggi_zonato(k, a, 12); x = impaccato("+2525.00")
        for (i = 0; i < n; i++) ATT[p + i] = (ZG ~ /^[0-9]+$/ && ZZ) ? substr(x, 2 * i + 1, 2) : "ND" }
      else if (CT[r] == "zoned") { x = zonato(a); for (i = 0; i < n; i++) ATT[p + i] = substr(x, 2 * i + 1, 2) }
      else if (CT[r] == "packed") { x = impaccato(a); for (i = 0; i < n; i++) ATT[p + i] = substr(x, 2 * i + 1, 2) }
      else if (CT[r] == "spazi") for (i = 0; i < n; i++) ATT[p + i] = "20" }
  }
  function escluso(F, k, p,   e) { for (e = 1; e <= ne; e++) if (EF[e] == F && (EK[e] == "*" || EK[e] == k) && p >= EP[e] && p < EP[e] + EN[e]) return 1; return 0 }
  # confronta(F, k, j, s, maschere): s = record in esadecimale (** dove mascherato se maschere = 1)
  function confronta(F, k, j, s, maschere,   p, b, chiave, nd0) {
    atteso(F, k); chiave = testo_in(k, 1, 11)
    if (length(s) != 2 * LUNG[F]) { difetto(F " record " j ": " length(s) / 2 " byte invece di " LUNG[F]); return }
    for (p = 1; p <= LUNG[F]; p++) { b = substr(s, 2 * p - 1, 2); nd0 = (ATT[p] == "ND")
      if (nd0 != escluso(F, chiave, p)) { difetto(F " " chiave " byte " p ": " (nd0 ? "posizione non determinata dal sorgente ma non esclusa" : "posizione esclusa ma determinata dal sorgente (atteso " ATT[p] ")")); continue }
      if (maschere && ((b == "**") != nd0)) { difetto(F " " chiave " byte " p ": " (nd0 ? "posizione non determinata ma non mascherata" : "posizione determinata mascherata")); continue }
      if (nd0) { nnd++; continue }
      if (b != ATT[p]) difetto(F " " chiave " byte " p " (" CAMPO[F, p] "): atteso " ATT[p] ", trovato " b); else nok++ }
  }
  function gnu(k, a,   s) { leggi_zonato(k, a, 12); return ZG (ZS == "-" ? "-" : "+") }
  # --- letture -----------------------------------------------------------------------------------------------------
  FILENAME == F1 { if ($0 ~ /^#/ || $0 ~ /^file\t/ || $0 == "") next
    if (NF != 7 || !($1 in LUNG) || !($5 in TR) || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ || $7 == "") { difetto("campi, riga " FNR ": riga non valida"); next }
    nc++; CF[nc] = $1; CP[nc] = $3 + 0; CN[nc] = $4 + 0; CT[nc] = $5; CA[nc] = $6
    if ($5 ~ /^(copia|copia-segno|data|debito)$/) { if ($6 !~ /^[0-9]+$/ || $6 + $4 - 1 > 300) difetto("campi, riga " FNR ": posizione d ingresso non valida"); CA[nc] = $6 + 0 }
    if ($5 == "zoned" && zonato($6) == "") difetto("campi, riga " FNR ": costante non valida " $6)
    if ($5 == "packed" && impaccato($6) == "") difetto("campi, riga " FNR ": costante non valida " $6)
    if ($5 == "data" && $4 != 10) difetto("campi, riga " FNR ": la data e di 10 byte")
    if ($5 == "debito" && $4 != 7) difetto("campi, riga " FNR ": il debito e un COMP-3 di 7 byte")
    if (($5 == "zoned" || $5 == "copia-segno") && $4 != 12) difetto("campi, riga " FNR ": DISPLAY S9(10)V99 di 12 byte")
    if ($5 == "packed" && $4 != 7) difetto("campi, riga " FNR ": COMP-3 S9(10)V99 di 7 byte")
    if (!($1 in SEGUE)) SEGUE[$1] = 1
    if ($3 != SEGUE[$1]) difetto("campi, " $1 " " $2 ": inizia al byte " $3 ", atteso " SEGUE[$1] " (buco o sovrapposizione)")
    for (i = 0; i < $4; i++) CAMPO[$1, $3 + i] = $2
    SEGUE[$1] = $3 + $4; next }
  FILENAME == F2 { if ($0 ~ /^#/ || $0 ~ /^scenario\t/ || $0 == "") next
    if (NF != 7 || $6 == "" || $6 == "-" || $7 == "" || $7 == "-") { difetto("esclusioni, riga " FNR ": esclusione senza motivo o senza riga del sorgente"); next }
    if (!($2 in LUNG) || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ || $4 + $5 - 1 > LUNG[$2]) { difetto("esclusioni, riga " FNR ": posizione non valida"); next }
    if ($1 != "*" && $1 != SC) next
    ne++; EF[ne] = $2; EK[ne] = $3; EP[ne] = $4 + 0; EN[ne] = $5 + 0; next }
  FILENAME == F3 { m = split($0, t, " "); for (i = 1; i <= m; i++) { if (!(t[i] in VAL)) { difetto("ingresso: byte illeggibile"); next }; IN[++nin] = VAL[t[i]] }; next }
  FILENAME == F4 { RO[++nro] = $0; next }
  FILENAME == F5 { RA[++nra] = $0; next }
  FILENAME == F6 { m = split($0, t, " "); for (i = 1; i <= m; i++) VB[++nvb] = t[i]; next }
  FILENAME == F7 { if ($0 ~ /^== /) { SEZ = $0; next }
    if (SEZ == "== codice di uscita") COD = COD $0 "|"; else if (SEZ == "== stdout") OUTL[++nout] = $0
    else if (SEZ == "== stderr") ERRL[++nerr] = $0; else if (SEZ == "== file nella cartella di lavoro") FIL[++nfil] = $0; next }
  END {
    for (f in LUNG) if (SEGUE[f] != LUNG[f] + 1) difetto("campi: " f " coperto fino al byte " SEGUE[f] - 1 ", record di " LUNG[f])
    if (nin == 0 || nin % 300) { difetto("ingresso di " nin " byte: non un multiplo positivo di 300"); exit 4 }
    N = nin / 300
    if (nro != N) difetto("OUTFILE: " nro " record, ingresso " N)
    if (nra != N) difetto("ARRYFILE: " nra " record, ingresso " N)
    # VBRCFILE fisico, letto qui
    p = 1; nlog = 0
    while (p <= nvb) { if (p + 3 > nvb) { difetto("VBRCFILE: intestazione troncata"); break }
      l = VAL[VB[p]] * 256 + VAL[VB[p + 1]]
      if (VB[p + 2] != "00" || VB[p + 3] != "00" || l < 1 || p + 3 + l > nvb) { difetto("VBRCFILE: intestazione non valida allo scostamento " p - 1); break }
      nlog++; s = ""; for (i = 0; i < l; i++) s = s VB[p + 4 + i]; LOG[nlog] = s; p += 4 + l }
    if (nlog != 2 * N) difetto("VBRCFILE: " nlog " record logici, attesi " 2 * N)
    for (k = 1; k <= N; k++) {
      if (k <= nro) confronta("OUTFILE", k, k, RO[k], 1)
      if (k <= nra) confronta("ARRYFILE", k, k, RA[k], 1)
      if (2 * k - 1 <= nlog) confronta("VBRC1", k, 2 * k - 1, LOG[2 * k - 1], 0)
      if (2 * k <= nlog) confronta("VBRC2", k, 2 * k, LOG[2 * k], 0)
    }
    # rapporto di esegui.sh
    if (COD != "0|") difetto("codice di uscita del programma: " COD " (atteso 0)")
    if (nerr != 4 || ERRL[1] != "Warning: program compiled against libxml 212 using older 209" \
        || ERRL[2] != "libcob: warning: implicit CLOSE of VBRC-FILE (\047VBRCFILE\047)" \
        || ERRL[3] != "libcob: warning: implicit CLOSE of ARRY-FILE (\047ARRYFILE\047)" \
        || ERRL[4] != "libcob: warning: implicit CLOSE of OUT-FILE (\047OUTFILE\047)") difetto("stderr diverso dall atteso (" nerr " righe)")
    if (nfil != 3 || FIL[1] != "ARRYFILE " 110 * N || FIL[2] != "OUTFILE " 107 * N || FIL[3] != "VBRCFILE " nvb) difetto("file creati diversi dagli attesi")
    # console, ricavata dal record d ingresso
    if (nout != 2 + 15 * N) difetto("stdout di " nout " righe, attese " 2 + 15 * N)
    E[1] = "START OF EXECUTION OF PROGRAM CBACT01C"; ne2 = 1
    for (k = 1; k <= N; k++) {
      E[++ne2] = "ACCT-ID                 :" testo_in(k, 1, 11)
      E[++ne2] = "ACCT-ACTIVE-STATUS      :" testo_in(k, 12, 1)
      E[++ne2] = "ACCT-CURR-BAL           :" gnu(k, 13)
      E[++ne2] = "ACCT-CREDIT-LIMIT       :" gnu(k, 25)
      E[++ne2] = "ACCT-CASH-CREDIT-LIMIT  :" gnu(k, 37)
      E[++ne2] = "ACCT-OPEN-DATE          :" testo_in(k, 49, 10)
      E[++ne2] = "ACCT-EXPIRAION-DATE     :" testo_in(k, 59, 10)
      E[++ne2] = "ACCT-REISSUE-DATE       :" testo_in(k, 69, 10)
      E[++ne2] = "ACCT-CURR-CYC-CREDIT    :" gnu(k, 79)
      E[++ne2] = "ACCT-CURR-CYC-DEBIT     :" gnu(k, 91)
      E[++ne2] = "ACCT-GROUP-ID           :" testo_in(k, 113, 10)
      E[++ne2] = "-------------------------------------------------"
      E[++ne2] = "VBRC-REC1:" testo_in(k, 1, 12)
      E[++ne2] = "VBRC-REC2:" testo_in(k, 1, 11) testo_in(k, 13, 24) testo_in(k, 69, 4)
      E[++ne2] = testo_in(k, 1, 300)
    }
    E[++ne2] = "END OF EXECUTION OF PROGRAM CBACT01C"
    for (i = 1; i <= ne2 && i <= nout; i++) if (OUTL[i] != E[i]) difetto("stdout, riga " i ": \"" OUTL[i] "\", attesa \"" E[i] "\""); else nrighe++
    if (nd) { print nd " difformita"; exit 4 }
    printf "verificatore indipendente (%s): %d record; %d byte determinati conformi alle regole, %d non determinati tutti esclusi e mascherati; %d record logici; %d righe di console conformi; codice 0\n", SC, N, nok, nnd, nlog, nrighe
  }' "$CAMPI" "$ESCL" "$tmpv/ingresso.hex" "$D/OUTFILE.riferimento.txt" "$D/ARRYFILE.riferimento.txt" "$tmpv/vb.hex" "$D/rapporto.txt" \
  > "$tmpv/esito" 2>&1 || esito=$?
case "$esito" in
  0) cat "$tmpv/esito" || die "esito non stampato (cat)" ;;
  4) cat "$tmpv/esito" >&2; rm -rf "$tmpv"; echo "verificatore.sh: CONTROLLO 4 FALLITO (scenario $S)" >&2; exit 4 ;;
  *) cat "$tmpv/esito" >&2; die "verifica non eseguita (awk, codice $esito)" ;;
esac
rm -rf "$tmpv" || { echo "verificatore.sh: temporanei non rimossi: $tmpv" >&2; exit 1; }
