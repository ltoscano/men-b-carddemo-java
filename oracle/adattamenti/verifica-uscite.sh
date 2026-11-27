#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/adattamenti/check.sh. Verifica STMTFILE e HTMLFILE di
# CBSTM03A contro i valori ricavati a mano dagli ingressi e dal sorgente, indipendentemente dall'output
# registrato in expected/.
#
# 1. I due file si leggono per intero: la lunghezza letta deve essere la dimensione reale del file
#    (wc -c), e un byte 0x01 (usato come separatore di lettura) rende il file non valido.
# 2. La struttura attesa degli output e' definita QUI, in un punto solo (funzione struttura qui sotto),
#    dal sorgente di CBSTM03A e dal numero di movimenti per estratto dello scenario (MOVIMENTI): per ogni
#    estratto e per ciascuno dei due file, il record e la posizione di ogni campo dinamico, di ogni
#    chiusura (cio' che segue un campo dell'HTML fino alla fine del record) e dei marcatori di inizio e
#    fine estratto; da qui anche il numero di record di ogni file.
# 3. record.tsv deve dichiarare esattamente quei numeri di record e quelle lunghezze, e i file devono
#    averli (nessun record o byte in piu' o in meno).
# 4. verifica-a-mano.tsv deve coprire ESATTAMENTE l'insieme definito al punto 2, in entrambe le
#    direzioni: nessuna riga attesa mancante, nessuna riga non prevista, nessuna riga duplicata, metadati
#    con sintassi rigorosa (interi positivi, file e tipo ammessi, 8 colonne). Per i campi di lunghezza
#    variabile dell'HTML (nome e indirizzo, STRING ... DELIMITED BY '  ') la chiusura deve cominciare
#    subito dopo il campo e finire alla fine del record.
# 5. Per ogni riga, i byte del file in quel record, da quella posizione, per quella lunghezza, sono
#    esattamente il valore della riga seguito da spazi fino alla lunghezza (uguaglianza esatta).
# Stampa una riga "DIFETTO: ..." per ogni differenza e alla fine l'esito; esce con 1 se ce n'e' almeno una.
# Uso: verifica-uscite.sh CARTELLA-CON-STMTFILE-E-HTMLFILE VERIFICA-A-MANO.tsv RECORD.tsv
set -u
# Numero di movimenti di ciascuno dei tre estratti dello scenario, nell'ordine delle carte
# (scenario/trnxfile.txt: 2 movimenti della carta 0500024453765740, nessuno della 0683586198171516,
# 2 della 0923877193247330).
MOVIMENTI="2 0 2"
[ $# -eq 3 ] || { echo "uso: verifica-uscite.sh CARTELLA VERIFICA-A-MANO.tsv RECORD.tsv" >&2; exit 2; }
obs="$1"; vam="$2"; rec="$3"
for f in "$vam" "$rec" "$obs/STMTFILE" "$obs/HTMLFILE"; do
  [ -f "$f" ] && [ -r "$f" ] || { echo "DIFETTO: file assente o illeggibile: $f"; echo "verifica a mano fallita"; exit 1; }
done
ss="$(wc -c < "$obs/STMTFILE")" || { echo "DIFETTO: dimensione di STMTFILE non leggibile"; exit 1; }
sh_="$(wc -c < "$obs/HTMLFILE")" || { echo "DIFETTO: dimensione di HTMLFILE non leggibile"; exit 1; }
ss="$(echo "$ss" | tr -d ' ')"; sh_="$(echo "$sh_" | tr -d ' ')"
case "$ss$sh_" in ''|*[!0-9]*) echo "DIFETTO: dimensioni non numeriche: '$ss' '$sh_'"; exit 1 ;; esac

awk -F'\t' -v stmt="$obs/STMTFILE" -v html="$obs/HTMLFILE" -v ss="$ss" -v sh="$sh_" -v movimenti="$MOVIMENTI" '
  function leggi(f, nome, dim,    r, seg, n, s) {
    # Legge tutto il file, segmento per segmento (RS = 0x01), e ricostruisce il contenuto.
    RS = "\001"; n = 0; s = ""
    while ((r = (getline seg < f)) > 0) { s = (n++ ? s "\001" : "") seg }
    if (r < 0) { printf "DIFETTO: %s illeggibile\n", nome; err++ }
    close(f); RS = "\n"
    if (n > 1) { printf "DIFETTO: %s contiene il byte 0x01 (%d segmenti)\n", nome, n; err++ }
    if (length(s) != dim + 0) { printf "DIFETTO: %s: letti %d byte, il file ne ha %d\n", nome, length(s), dim; err++ }
    return s
  }
  # slot FILE RECORD TIPO POSIZIONE LUNGHEZZA ETICHETTA: una riga attesa. POSIZIONE o LUNGHEZZA "V" =
  # variabile (campi STRING dell HTML e loro chiusure).
  function slot(f, r, t, p, l, et,    k) {
    k = f SUBSEP r SUBSEP t SUBSEP p
    if (k in E) { printf "DIFETTO: struttura: posizione definita due volte (%s record %d %s)\n", f, r, t; err++ }
    E[k] = l; ET[k] = et; ne++
  }
  # La struttura degli output, dal sorgente di CBSTM03A (righe del sorgente in verifica-a-mano.tsv).
  function struttura(    nm, e, m, k, b, t) {
    nm = split(movimenti, M, " ")
    # STMTFILE, record di 80 byte: 16 record di 5000-CREATE-STATEMENT, uno per movimento, 3 di chiusura.
    b = 0
    for (e = 1; e <= nm; e++) {
      m = M[e] + 0
      slot("STMTFILE", b + 1, "estratto", 32, 18, "estratto " e ", ST-LINE0")
      slot("STMTFILE", b + 2, "campo", 1, 75, "estratto " e ", ST-NAME")
      slot("STMTFILE", b + 3, "campo", 1, 50, "estratto " e ", ST-ADD1")
      slot("STMTFILE", b + 4, "campo", 1, 50, "estratto " e ", ST-ADD2")
      slot("STMTFILE", b + 5, "campo", 1, 80, "estratto " e ", ST-ADD3")
      slot("STMTFILE", b + 9, "campo", 21, 20, "estratto " e ", ST-ACCT-ID")
      slot("STMTFILE", b + 10, "campo", 21, 13, "estratto " e ", ST-CURR-BAL")
      slot("STMTFILE", b + 11, "campo", 21, 20, "estratto " e ", ST-FICO-SCORE")
      for (k = 1; k <= m; k++) {
        slot("STMTFILE", b + 16 + k, "campo", 1, 16, "estratto " e ", movimento " k ", ST-TRANID")
        slot("STMTFILE", b + 16 + k, "campo", 18, 49, "estratto " e ", movimento " k ", ST-TRANDT")
        slot("STMTFILE", b + 16 + k, "campo", 68, 13, "estratto " e ", movimento " k ", ST-TRANAMT")
      }
      slot("STMTFILE", b + 16 + m + 2, "campo", 68, 13, "estratto " e ", ST-TOTAL-TRAMT")
      slot("STMTFILE", b + 16 + m + 3, "estratto", 33, 16, "estratto " e ", ST-LINE15")
      b += 19 + m
    }
    NREC["STMTFILE"] = b; LREC["STMTFILE"] = 80
    # HTMLFILE, record di 100 byte: 22 record di 5100, 34 di 5200, 11 per movimento, 8 di chiusura.
    b = 0
    for (e = 1; e <= nm; e++) {
      m = M[e] + 0
      slot("HTMLFILE", b + 1, "estratto", 1, 100, "estratto " e ", HTML-L01")
      slot("HTMLFILE", b + 11, "campo", 35, 20, "estratto " e ", L11-ACCT")
      slot("HTMLFILE", b + 23, "campo", 27, "V", "estratto " e ", L23-NAME")
      slot("HTMLFILE", b + 23, "chiusura", "V", "V", "estratto " e ", chiusura del nome")
      slot("HTMLFILE", b + 24, "campo", 4, "V", "estratto " e ", ST-ADD1")
      slot("HTMLFILE", b + 24, "chiusura", "V", "V", "estratto " e ", chiusura di ST-ADD1")
      slot("HTMLFILE", b + 25, "campo", 4, "V", "estratto " e ", ST-ADD2")
      slot("HTMLFILE", b + 25, "chiusura", "V", "V", "estratto " e ", chiusura di ST-ADD2")
      slot("HTMLFILE", b + 26, "campo", 4, "V", "estratto " e ", ST-ADD3")
      slot("HTMLFILE", b + 26, "chiusura", "V", "V", "estratto " e ", chiusura di ST-ADD3")
      slot("HTMLFILE", b + 36, "campo", 25, 20, "estratto " e ", ST-ACCT-ID")
      slot("HTMLFILE", b + 36, "chiusura", 45, 56, "estratto " e ", chiusura di ST-ACCT-ID")
      slot("HTMLFILE", b + 37, "campo", 25, 13, "estratto " e ", ST-CURR-BAL")
      slot("HTMLFILE", b + 37, "chiusura", 38, 63, "estratto " e ", chiusura di ST-CURR-BAL")
      slot("HTMLFILE", b + 38, "campo", 25, 20, "estratto " e ", ST-FICO-SCORE")
      slot("HTMLFILE", b + 38, "chiusura", 45, 56, "estratto " e ", chiusura di ST-FICO-SCORE")
      for (k = 1; k <= m; k++) {
        t = b + 56 + 11 * (k - 1)
        slot("HTMLFILE", t + 3, "campo", 4, 16, "estratto " e ", movimento " k ", ST-TRANID")
        slot("HTMLFILE", t + 3, "chiusura", 20, 81, "estratto " e ", movimento " k ", chiusura di ST-TRANID")
        slot("HTMLFILE", t + 6, "campo", 4, 49, "estratto " e ", movimento " k ", ST-TRANDT")
        slot("HTMLFILE", t + 6, "chiusura", 53, 48, "estratto " e ", movimento " k ", chiusura di ST-TRANDT")
        slot("HTMLFILE", t + 9, "campo", 4, 13, "estratto " e ", movimento " k ", ST-TRANAMT")
        slot("HTMLFILE", t + 9, "chiusura", 17, 84, "estratto " e ", movimento " k ", chiusura di ST-TRANAMT")
      }
      slot("HTMLFILE", b + 64 + 11 * m, "estratto", 1, 100, "estratto " e ", HTML-L80")
      b += 64 + 11 * m
    }
    NREC["HTMLFILE"] = b; LREC["HTMLFILE"] = 100
  }
  function intero(x) { return x ~ /^[1-9][0-9]*$/ }
  BEGIN {
    dato["STMTFILE"] = leggi(stmt, "STMTFILE", ss)
    dato["HTMLFILE"] = leggi(html, "HTMLFILE", sh)
    struttura()
  }
  FNR == 1 {
    tab++
    if (tab == 1 && $0 != "file\tlunghezza_record\tnumero_record\tderivazione") { print "DIFETTO: record.tsv: intestazione non valida"; err++ }
    if (tab == 2 && $0 != "file\trecord\tposizione\tlunghezza\tvalore\triga_sorgente\ttipo\tcampo") { print "DIFETTO: verifica-a-mano.tsv: intestazione non valida"; err++ }
    next
  }
  tab == 1 {
    # record.tsv: file, lunghezza del record, numero di record, derivazione
    if (NF != 4 || !($1 in NREC) || !intero($2) || !intero($3) || ($1 in DICH)) {
      printf "DIFETTO: record.tsv riga %d: non valida o duplicata\n", FNR; err++; next
    }
    DICH[$1] = 1; nrec++
    if ($2 + 0 != LREC[$1] || $3 + 0 != NREC[$1]) {
      printf "DIFETTO: record.tsv: %s dichiarato con %s record da %s byte, la struttura ne prevede %d da %d\n", $1, $3, $2, NREC[$1], LREC[$1]; err++
    }
    next
  }
  tab == 2 {
    righe++
    f = $1; r = $2; p = $3; n = $4; v = $5; t = $7
    if (NF != 8 || !(f in NREC) || !intero(r) || !intero(p) || !intero(n) || $6 !~ /^[0-9]+(-[0-9]+)?$/ \
        || (t != "campo" && t != "chiusura" && t != "estratto") || v == "" || $8 == "") {
      printf "DIFETTO: verifica-a-mano riga %d: metadati non validi (8 colonne: file, record, posizione e lunghezza intere, valore, riga del sorgente, tipo, campo)\n", FNR; err++; next
    }
    r += 0; p += 0; n += 0
    if (length(v) > n || r > NREC[f] || p + n - 1 > LREC[f]) {
      printf "DIFETTO: verifica-a-mano riga %d: valore o posizione fuori dal record (%s record %d posizione %d lunghezza %d)\n", FNR, f, r, p, n; err++; next
    }
    k = f SUBSEP r SUBSEP t SUBSEP p
    kv = f SUBSEP r SUBSEP t SUBSEP "V"
    if (k in E) {
      if (E[k] != "V" && n != E[k] + 0) { printf "DIFETTO: verifica-a-mano riga %d: %s: lunghezza %d, attesa %d\n", FNR, ET[k], n, E[k]; err++ }
      if (E[k] == "V") FINE[f, r] = p + n
    } else if (t == "chiusura" && (kv in E)) {
      k = kv; CP[f, r] = p; CE[f, r] = p + n - 1
    } else {
      printf "DIFETTO: verifica-a-mano riga %d: riga non prevista dalla struttura (%s record %d posizione %d, %s)\n", FNR, f, r, p, t; err++; next
    }
    if (++usata[k] > 1) { printf "DIFETTO: verifica-a-mano riga %d: riga duplicata (%s, %s record %d)\n", FNR, ET[k], f, r; err++; next }
    atteso = sprintf("%-" n "s", v)
    trovato = substr(dato[f], (r - 1) * LREC[f] + p, n)
    if (trovato != atteso) {
      printf "DIFETTO: %s record %d posizione %d lunghezza %d (%s, riga %s del sorgente): atteso [%s] trovato [%s]\n", f, r, p, n, $8, $6, atteso, trovato
      err++
    }
  }
  END {
    for (f in NREC) {
      if (!(f in DICH)) { printf "DIFETTO: record.tsv: manca %s\n", f; err++ }
      if (length(dato[f]) != NREC[f] * LREC[f]) {
        printf "DIFETTO: %s: %d byte, attesi %d record da %d byte (%d)\n", f, length(dato[f]), NREC[f], LREC[f], NREC[f] * LREC[f]; err++
      }
    }
    for (k in E) {
      split(k, q, SUBSEP)
      if (!(k in usata)) { printf "DIFETTO: manca la riga attesa: %s record %d, %s (%s)\n", q[1], q[2], q[3], ET[k]; err++; continue }
      if (q[3] == "chiusura" && q[4] == "V") {
        if (!((q[1], q[2]) in FINE) || CP[q[1], q[2]] != FINE[q[1], q[2]] || CE[q[1], q[2]] != LREC[q[1]]) {
          printf "DIFETTO: %s record %d: la chiusura non comincia subito dopo il campo o non finisce alla fine del record (%s)\n", q[1], q[2], ET[k]; err++
        }
      }
    }
    if (err) { printf "verifica a mano fallita: %d differenze\n", err; exit 1 }
    printf "verifica a mano riuscita: %d righe = le %d posizioni attese della struttura (3 estratti, movimenti %s), tutte uguali; STMTFILE %d record da %d byte, HTMLFILE %d record da %d byte, letti per intero\n", righe, ne, movimenti, NREC["STMTFILE"], LREC["STMTFILE"], NREC["HTMLFILE"], LREC["HTMLFILE"]
  }' "$rec" "$vam"
