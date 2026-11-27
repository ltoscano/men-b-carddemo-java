#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/adattamenti/check.sh. Verifica STMTFILE e HTMLFILE di
# CBSTM03A contro i valori ricavati a mano dagli ingressi e dal sorgente, indipendentemente dall'output
# registrato in expected/:
#   - record.tsv: ogni file ha esattamente il numero di record atteso, della lunghezza attesa (nessun
#     record in piu' o in meno, nessun byte in piu');
#   - verifica-a-mano.tsv: per ogni riga, i byte del file in quel record, da quella posizione, per quella
#     lunghezza, sono esattamente il valore della riga seguito da spazi fino alla lunghezza (uguaglianza
#     esatta del campo). Le righe "estratto" fissano numero e ordine degli estratti; le righe dei campi
#     dei movimenti fissano numero e ordine dei movimenti.
# Stampa una riga "DIFETTO: ..." per ogni differenza e alla fine l'esito; esce con 1 se ce n'e' almeno una.
# Uso: verifica-uscite.sh CARTELLA-CON-STMTFILE-E-HTMLFILE VERIFICA-A-MANO.tsv RECORD.tsv
set -u
[ $# -eq 3 ] || { echo "uso: verifica-uscite.sh CARTELLA VERIFICA-A-MANO.tsv RECORD.tsv" >&2; exit 2; }
obs="$1"; vam="$2"; rec="$3"
for f in "$vam" "$rec"; do [ -f "$f" ] || { echo "DIFETTO: tabella assente: $f"; exit 1; }; done
for f in STMTFILE HTMLFILE; do [ -f "$obs/$f" ] || { echo "DIFETTO: $f assente"; exit 1; }; done
awk -F'\t' -v stmt="$obs/STMTFILE" -v html="$obs/HTMLFILE" '
  BEGIN {
    # Ogni file e una sola stringa: record fissi senza separatori (nessun byte \001 nei file).
    RS = "\001"; s = ""; h = ""
    if ((getline s < stmt) < 0) { print "DIFETTO: STMTFILE illeggibile"; err++ }
    if ((getline h < html) < 0) { print "DIFETTO: HTMLFILE illeggibile"; err++ }
    close(stmt); close(html)
    dato["STMTFILE"] = s; dato["HTMLFILE"] = h
    RS = "\n"
  }
  FNR == 1 { tab++; next }
  /^#/ { next }
  tab == 1 {
    # record.tsv: file, lunghezza del record, numero di record
    L[$1] = $2 + 0; N[$1] = $3 + 0; nrec++
    b = length(dato[$1])
    if (b != L[$1] * N[$1]) { printf "DIFETTO: %s: %d byte, attesi %d record da %d byte (%d)\n", $1, b, N[$1], L[$1], L[$1] * N[$1]; err++ }
    next
  }
  tab == 2 {
    f = $1; r = $2 + 0; p = $3 + 0; n = $4 + 0; v = $5; righe++; tipo[$7]++
    if (!(f in L)) { printf "DIFETTO: verifica-a-mano riga %d: file sconosciuto %s\n", FNR, f; err++; next }
    if (length(v) > n || r < 1 || r > N[f] || p < 1 || p + n - 1 > L[f]) {
      printf "DIFETTO: verifica-a-mano riga %d: valore o posizione fuori dal record (%s record %d posizione %d lunghezza %d)\n", FNR, f, r, p, n; err++; next
    }
    atteso = sprintf("%-" n "s", v)
    trovato = substr(dato[f], (r - 1) * L[f] + p, n)
    if (trovato != atteso) {
      printf "DIFETTO: %s record %d posizione %d lunghezza %d (%s, riga %s del sorgente): atteso [%s] trovato [%s]\n", f, r, p, n, $8, $6, atteso, trovato
      err++
    }
  }
  END {
    if (nrec != 2) { printf "DIFETTO: record.tsv: %d file invece di 2\n", nrec; err++ }
    if (righe == 0) { print "DIFETTO: verifica-a-mano.tsv senza righe"; err++ }
    if (err) { printf "verifica a mano fallita: %d differenze\n", err; exit 1 }
    printf "verifica a mano riuscita: %d valori uguali (%d campi, %d chiusure, %d marcatori di estratto); STMTFILE %d record da %d byte, HTMLFILE %d record da %d byte\n", righe, tipo["campo"], tipo["chiusura"], tipo["estratto"], N["STMTFILE"], L["STMTFILE"], N["HTMLFILE"], L["HTMLFILE"]
  }' "$rec" "$vam"
