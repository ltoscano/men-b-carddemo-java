#!/bin/sh
# VERIFICATORE INDIPENDENTE (issue #55, controllo 4). Non esegue COBOL, non usa alcuno script che produce i golden
# (prepara, scenario, estrai-vb, maschera, attesi, conteggi, coerenza): ha il proprio lettore dei file, il proprio
# lettore del file a record variabili e le proprie regole di codifica. Si lancia da solo su una cartella data, nel
# container dell'oracle (servono solo sh, od e awk), per esempio:
#   docker run --rm -v "$PWD/oracle:/oracle:ro" <immagine dell'oracle> sh /oracle/golden/verificatore.sh \
#     mirato /oracle/golden/readacct/generati/golden/mirato/ingresso.rec /oracle/golden/readacct/generati/golden/mirato \
#     /oracle/golden/readacct/campi.tsv /oracle/golden/readacct/esclusioni.tsv
# Si verifica cio' che si pubblica, dopo l'ultima trasformazione (rilievo 1 del giro 1 della PR #64): per OGNI record
# dello scenario legge e controlla TUTTI i file pubblicati come riferimento, sui byte, contro il record d'ingresso, con
# la tabella scritta a mano CAMPI (campo d'uscita <- campo d'ingresso, costante o trasformazione, riga del sorgente):
#   - OUTFILE.riferimento.txt, ARRYFILE.riferimento.txt: una riga per record, byte in esadecimale, ** nelle posizioni
#     escluse, correzioni dell'oracle gia' applicate. Questo verificatore NON legge la tabella delle correzioni: il byte
#     atteso viene dalla regola del linguaggio scritta qui;
#   - VBRCFILE.riferimento.txt: numerazione 1..2N, lunghezza dichiarata uguale ai byte e al tracciato logico (VBRC-REC1
#     12 byte, VBRC-REC2 39 byte, CBACT01C.cbl:123-130), ordine (un VBRC-REC1 e un VBRC-REC2 per conto, nell'ordine
#     dell'ingresso), contenuto;
#   - console.riferimento.txt: 2 + 15 x N righe; le righe di classe a ricavate qui dal sorgente (letterali delle righe
#     141, 201-202, 206-208, 211-212, 283, 158) e dal record d'ingresso; le righe di osservazione esattamente
#     "#OSSERVAZIONE b <riga>" per i DISPLAY delle righe 203-205, 209-210, 284 e "#OSSERVAZIONE c 151" per
#     DISPLAY ACCOUNT-RECORD, nelle loro posizioni;
#   - inoltre i file pubblicati accanto ai riferimenti: il VBRCFILE fisico, letto qui (formato GnuCOBOL
#     COB_VARSEQ_FORMAT 0: 2 byte di lunghezza big-endian senza l'intestazione, 2 byte 00) e controllato con le stesse
#     regole; VBRCFILE.logici.txt identico alla lettura fatta qui; rapporto.txt (codice 0; stdout di 2 + 15 x N righe,
#     tutte ricavate qui, compresi i numerici con segno nella forma di GnuCOBOL, 12 cifre e il segno in coda, e i
#     DISPLAY di gruppo; stderr = avviso di libxml2 e tre chiusure implicite; file creati 107 x N, 110 x N e la
#     dimensione del VBRCFILE); ambiente.txt (le variabili fissate dell'oracle e i quattro DD del JCL);
#   - regole proprie: copia (byte d'ingresso); copia-segno (byte d'ingresso solo se la rappresentazione d'ingresso e'
#     canonica: corpo di cifre 30-39, ultimo byte { A-I, oppure } J-R con valore non zero; altrimenti il risultato
#     dipende da NUMPROC e la posizione deve essere esclusa); data (byte 1-4 <- 1-4, 5-6 <- 6-7, 7-8 <- 9-10 della
#     data d'ingresso, COBDATFT.asm:51-53; 9-10 non determinati); debito (debito d'ingresso zero -> COMP-3 di +2525.00,
#     altrimenti non determinato); zoned (12 cifre, ultima con segno sovrapposto: { A-I positivo o zero, } J-R
#     negativo); packed (semiottetto di riempimento 0, 12 cifre, segno C positivo o zero, D negativo); spazi (20);
#   - le posizioni non determinate sono ESATTAMENTE quelle della tabella ESCLUSIONI per lo scenario e il record, e nei
#     riferimenti sono ESATTAMENTE quelle mascherate con **; nessuna esclusione senza motivo o senza riga del sorgente;
#   - ogni token esadecimale letto (da od o dai riferimenti) e' validato: un token malformato e' una difformita', mai
#     uno zero (rilievo 4 del giro 1 della PR #64).
# Uscite: 0 tutto conforme; 1 errore dello strumento; 4 difformita' (elencate).
# Uso: verificatore.sh SCENARIO INGRESSO DIR CAMPI ESCLUSIONI
set -u
die() { echo "verificatore.sh: $*" >&2; [ -z "${tmpv:-}" ] || rm -rf "$tmpv"; exit 1; }
[ $# -eq 5 ] || die "uso: verificatore.sh SCENARIO INGRESSO DIR CAMPI ESCLUSIONI"
S="$1"; ING="$2"; D="$3"; CAMPI="$4"; ESCL="$5"; tmpv=""
for f in "$ING" "$D/OUTFILE.riferimento.txt" "$D/ARRYFILE.riferimento.txt" "$D/VBRCFILE.riferimento.txt" \
         "$D/console.riferimento.txt" "$D/VBRCFILE" "$D/VBRCFILE.logici.txt" "$D/rapporto.txt" "$D/ambiente.txt" "$CAMPI" "$ESCL"; do
  [ -f "$f" ] || die "file assente: $f"
done
tmpv="$(mktemp -d /tmp/issue55-verificatore.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
od -An -v -tx1 "$ING" > "$tmpv/ingresso.hex" || die "od dell'ingresso fallito"
od -An -v -tx1 "$D/VBRCFILE" > "$tmpv/vb.hex" || die "od di VBRCFILE fallito"
esito=0
awk -F '\t' -v SC="$S" -v F1="$CAMPI" -v F2="$ESCL" -v F3="$tmpv/ingresso.hex" -v F4="$D/OUTFILE.riferimento.txt" \
    -v F5="$D/ARRYFILE.riferimento.txt" -v F6="$tmpv/vb.hex" -v F7="$D/rapporto.txt" -v F8="$D/VBRCFILE.riferimento.txt" \
    -v F9="$D/console.riferimento.txt" -v F10="$D/VBRCFILE.logici.txt" -v F11="$D/ambiente.txt" '
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
  # confronta(F, k, j, s, maschere, ORIGINE): s = record in esadecimale (** dove mascherato se maschere = 1)
  function confronta(F, k, j, s, maschere, orig,   p, b, chiave, nd0) {
    atteso(F, k); chiave = testo_in(k, 1, 11)
    if (length(s) != 2 * LUNG[F]) { difetto(orig " record " j ": " length(s) / 2 " byte invece di " LUNG[F]); return }
    for (p = 1; p <= LUNG[F]; p++) { b = substr(s, 2 * p - 1, 2); nd0 = (ATT[p] == "ND")
      if (b != "**" && !(b in VAL)) { difetto(orig " " chiave " byte " p ": token non esadecimale \"" b "\""); continue }
      if (b == "**" && !maschere) { difetto(orig " " chiave " byte " p ": maschera in un file fisico"); continue }
      if (nd0 != escluso(F, chiave, p)) { difetto(orig " " chiave " byte " p ": " (nd0 ? "posizione non determinata dal sorgente ma non esclusa" : "posizione esclusa ma determinata dal sorgente (atteso " ATT[p] ")")); continue }
      if (maschere && ((b == "**") != nd0)) { difetto(orig " " chiave " byte " p ": " (nd0 ? "posizione non determinata ma non mascherata" : "posizione determinata mascherata")); continue }
      if (nd0) { nnd++; continue }
      if (b != ATT[p]) difetto(orig " " chiave " byte " p " (" CAMPO[F, p] "): atteso " ATT[p] ", trovato " b); else nok++ }
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
  FILENAME == F3 { m = split($0, t, " "); for (i = 1; i <= m; i++) { if (!(t[i] in VAL)) { difetto("ingresso: token non esadecimale \"" t[i] "\""); continue }; IN[++nin] = VAL[t[i]] }; next }
  FILENAME == F4 { RO[++nro] = $0; next }
  FILENAME == F5 { RA[++nra] = $0; next }
  FILENAME == F6 { m = split($0, t, " "); for (i = 1; i <= m; i++) { if (!(t[i] in VAL)) { difetto("VBRCFILE fisico: token non esadecimale \"" t[i] "\""); vbrotto = 1; continue }; VB[++nvb] = t[i] }; next }
  FILENAME == F7 { if ($0 ~ /^== /) { SEZ = $0; next }
    if (SEZ == "== codice di uscita") COD = COD $0 "|"; else if (SEZ == "== stdout") OUTL[++nout] = $0
    else if (SEZ == "== stderr") ERRL[++nerr] = $0; else if (SEZ == "== file nella cartella di lavoro") FIL[++nfil] = $0; next }
  FILENAME == F8 { RV[++nrv] = $0; next }
  FILENAME == F9 { RC[++nrc] = $0; next }
  FILENAME == F10 { LT[++nlt] = $0; next }
  FILENAME == F11 { AMB[++namb] = $0; next }
  END {
    for (f in LUNG) if (SEGUE[f] != LUNG[f] + 1) difetto("campi: " f " coperto fino al byte " SEGUE[f] - 1 ", record di " LUNG[f])
    if (nin == 0 || nin % 300) { difetto("ingresso di " nin " byte: non un multiplo positivo di 300"); print nd " difformita"; exit 4 }
    N = nin / 300
    if (nro != N) difetto("OUTFILE.riferimento.txt: " nro " record, ingresso " N)
    if (nra != N) difetto("ARRYFILE.riferimento.txt: " nra " record, ingresso " N)
    # VBRCFILE fisico, letto qui (ogni token gia validato)
    p = 1; nlog = 0
    while (!vbrotto && p <= nvb) { if (p + 3 > nvb) { difetto("VBRCFILE: intestazione troncata"); break }
      l = VAL[VB[p]] * 256 + VAL[VB[p + 1]]
      if (VB[p + 2] != "00" || VB[p + 3] != "00" || l < 1 || p + 3 + l > nvb) { difetto("VBRCFILE: intestazione non valida allo scostamento " p - 1); break }
      nlog++; s = ""; for (i = 0; i < l; i++) s = s VB[p + 4 + i]; LOG[nlog] = s; LL[nlog] = l; p += 4 + l }
    if (nlog != 2 * N) difetto("VBRCFILE fisico: " nlog " record logici, attesi " 2 * N)
    # VBRCFILE.logici.txt (pubblicato): identico alla lettura fatta qui
    if (nlt != nlog) difetto("VBRCFILE.logici.txt: " nlt " righe, " nlog " record logici nel fisico")
    for (j = 1; j <= nlt && j <= nlog; j++) if (LT[j] != sprintf("%06d %03d %s", j, LL[j], LOG[j])) difetto("VBRCFILE.logici.txt, riga " j ": diversa dal record logico " j " del fisico")
    # VBRCFILE.riferimento.txt: numerazione, lunghezza, ordine e contenuto
    if (nrv != 2 * N) difetto("VBRCFILE.riferimento.txt: " nrv " record logici, attesi " 2 * N)
    for (j = 1; j <= nrv; j++) { m = split(RV[j], t, " ")
      F = (j % 2) ? "VBRC1" : "VBRC2"
      if (m != 3 || t[1] != sprintf("%06d", j) || t[2] != sprintf("%03d", LUNG[F]) || length(t[3]) != 2 * LUNG[F]) {
        difetto("VBRCFILE.riferimento.txt, riga " j ": numero, lunghezza o byte non validi per " F " (attesi " sprintf("%06d %03d", j, LUNG[F]) ")"); continue }
      if (int((j + 1) / 2) <= N) confronta(F, int((j + 1) / 2), j, t[3], 1, "VBRCFILE.riferimento.txt " F) }
    for (k = 1; k <= N; k++) {
      if (k <= nro) confronta("OUTFILE", k, k, RO[k], 1, "OUTFILE.riferimento.txt")
      if (k <= nra) confronta("ARRYFILE", k, k, RA[k], 1, "ARRYFILE.riferimento.txt")
      if (2 * k - 1 <= nlog) confronta("VBRC1", k, 2 * k - 1, LOG[2 * k - 1], 0, "VBRCFILE fisico VBRC1")
      if (2 * k <= nlog) confronta("VBRC2", k, 2 * k, LOG[2 * k], 0, "VBRCFILE fisico VBRC2")
    }
    # rapporto di esegui.sh
    if (COD != "0|") difetto("codice di uscita del programma: " COD " (atteso 0)")
    if (nerr != 4 || ERRL[1] != "Warning: program compiled against libxml 212 using older 209" \
        || ERRL[2] != "libcob: warning: implicit CLOSE of VBRC-FILE (\047VBRCFILE\047)" \
        || ERRL[3] != "libcob: warning: implicit CLOSE of ARRY-FILE (\047ARRYFILE\047)" \
        || ERRL[4] != "libcob: warning: implicit CLOSE of OUT-FILE (\047OUTFILE\047)") difetto("stderr diverso dall atteso (" nerr " righe)")
    if (nfil != 3 || FIL[1] != "ARRYFILE " 110 * N || FIL[2] != "OUTFILE " 107 * N || FIL[3] != "VBRCFILE " nvb) difetto("file creati diversi dagli attesi")
    # ambiente.txt
    if (namb != 8 || AMB[1] != "PATH=/usr/bin:/bin" || AMB[2] != "HOME=/tmp" || AMB[3] != "LC_ALL=C" || AMB[4] != "COB_LIBRARY_PATH=/oracle-bin" \
        || AMB[5] !~ /^DD_ACCTFILE=\/[^ ]+$/ || AMB[6] !~ /^DD_OUTFILE=\/[^ ]*\/OUTFILE$/ || AMB[7] !~ /^DD_ARRYFILE=\/[^ ]*\/ARRYFILE$/ \
        || AMB[8] !~ /^DD_VBRCFILE=\/[^ ]*\/VBRCFILE$/) difetto("ambiente.txt diverso dalle variabili fissate e dai quattro DD del JCL")
    # console: attesa ricavata dal record d ingresso; classe delle posizioni del ciclo, dal sorgente
    E[1] = "START OF EXECUTION OF PROGRAM CBACT01C"; K[1] = E[1]; ne2 = 1
    for (k = 1; k <= N; k++) {
      E[++ne2] = "ACCT-ID                 :" testo_in(k, 1, 11);       K[ne2] = E[ne2]
      E[++ne2] = "ACCT-ACTIVE-STATUS      :" testo_in(k, 12, 1);       K[ne2] = E[ne2]
      E[++ne2] = "ACCT-CURR-BAL           :" gnu(k, 13);               K[ne2] = "#OSSERVAZIONE b 203"
      E[++ne2] = "ACCT-CREDIT-LIMIT       :" gnu(k, 25);               K[ne2] = "#OSSERVAZIONE b 204"
      E[++ne2] = "ACCT-CASH-CREDIT-LIMIT  :" gnu(k, 37);               K[ne2] = "#OSSERVAZIONE b 205"
      E[++ne2] = "ACCT-OPEN-DATE          :" testo_in(k, 49, 10);      K[ne2] = E[ne2]
      E[++ne2] = "ACCT-EXPIRAION-DATE     :" testo_in(k, 59, 10);      K[ne2] = E[ne2]
      E[++ne2] = "ACCT-REISSUE-DATE       :" testo_in(k, 69, 10);      K[ne2] = E[ne2]
      E[++ne2] = "ACCT-CURR-CYC-CREDIT    :" gnu(k, 79);               K[ne2] = "#OSSERVAZIONE b 209"
      E[++ne2] = "ACCT-CURR-CYC-DEBIT     :" gnu(k, 91);               K[ne2] = "#OSSERVAZIONE b 210"
      E[++ne2] = "ACCT-GROUP-ID           :" testo_in(k, 113, 10);     K[ne2] = E[ne2]
      E[++ne2] = "-------------------------------------------------";  K[ne2] = E[ne2]
      E[++ne2] = "VBRC-REC1:" testo_in(k, 1, 12);                      K[ne2] = E[ne2]
      E[++ne2] = "VBRC-REC2:" testo_in(k, 1, 11) testo_in(k, 13, 24) testo_in(k, 69, 4); K[ne2] = "#OSSERVAZIONE b 284"
      E[++ne2] = testo_in(k, 1, 300);                                  K[ne2] = "#OSSERVAZIONE c 151"
    }
    E[++ne2] = "END OF EXECUTION OF PROGRAM CBACT01C"; K[ne2] = E[ne2]
    if (nout != ne2) difetto("stdout del rapporto di " nout " righe, attese " ne2)
    for (i = 1; i <= ne2 && i <= nout; i++) if (OUTL[i] != E[i]) difetto("stdout, riga " i ": \"" OUTL[i] "\", attesa \"" E[i] "\""); else nrighe++
    if (nrc != ne2) difetto("console.riferimento.txt di " nrc " righe, attese " ne2)
    for (i = 1; i <= ne2 && i <= nrc; i++) if (RC[i] != K[i]) difetto("console.riferimento.txt, riga " i ": \"" RC[i] "\", attesa \"" K[i] "\""); else { nrif++; if (K[i] ~ /^#OSSERVAZIONE /) noss++ }
    if (nd) { print nd " difformita"; exit 4 }
    printf "verificatore indipendente (%s): %d record; %d byte determinati conformi alle regole, %d non determinati tutti esclusi e mascherati, in OUTFILE.riferimento.txt, ARRYFILE.riferimento.txt, VBRCFILE.riferimento.txt e VBRCFILE fisico; %d record logici, VBRCFILE.logici.txt identico al fisico; console.riferimento.txt %d righe conformi (%d di osservazione nelle loro posizioni); stdout %d righe conformi; ambiente e codice 0\n", SC, N, nok, nnd, nlog, nrif, noss, nrighe
  }' "$CAMPI" "$ESCL" "$tmpv/ingresso.hex" "$D/OUTFILE.riferimento.txt" "$D/ARRYFILE.riferimento.txt" "$tmpv/vb.hex" "$D/rapporto.txt" \
  "$D/VBRCFILE.riferimento.txt" "$D/console.riferimento.txt" "$D/VBRCFILE.logici.txt" "$D/ambiente.txt" \
  > "$tmpv/esito" 2>&1 || esito=$?
case "$esito" in
  0) cat "$tmpv/esito" || die "esito non stampato (cat)" ;;
  4) cat "$tmpv/esito" >&2; rm -rf "$tmpv"; echo "verificatore.sh: CONTROLLO 4 FALLITO (scenario $S)" >&2; exit 4 ;;
  *) cat "$tmpv/esito" >&2; die "verifica non eseguita (awk, codice $esito)" ;;
esac
rm -rf "$tmpv" || { echo "verificatore.sh: temporanei non rimossi: $tmpv" >&2; exit 1; }
