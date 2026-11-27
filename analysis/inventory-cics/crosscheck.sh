#!/bin/sh
# Conteggio INDIPENDENTE dei blocchi EXEC CICS (issue #22): awk, senza Python e senza ProLeap. Gira in container su /legacy
# (o su LEGACY_ROOT). Criterio dichiarato:
#  - righe di commento escluse (indicatore '*' o '/' in colonna 7); si legge solo l'area colonne 8-72;
#  - letterali tra apici mascherati (anche se non chiusi sulla riga); da '*>' a fine riga e' commento;
#  - le parole ([A-Z0-9-]+, maiuscole) formano un flusso unico attraverso le righe: un blocco comincia alla parola EXEC
#    seguita (anche sulla riga dopo) dalla parola CICS e finisce alla prima parola END-EXEC; piu' blocchi sulla stessa riga
#    sono contati uno per uno;
#  - comando: prima parola dopo CICS, piu' la seconda se qualifica la prima (stessa tabella dichiarata in glue/extract.py).
# Uso: crosscheck.sh FILE_ELENCO   (un percorso per riga). Stampa, per ogni blocco,
#   "blocco<TAB>file<TAB>riga<TAB>colonna<TAB>riga_fine<TAB>comando", e "errore<TAB>file<TAB>riga<TAB>motivo" per un blocco
#   senza comando, non chiuso, o con un EXEC dentro; poi "fine<TAB><numero di file letti>".
ROOT="${LEGACY_ROOT:-/legacy}"
n=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  f="$ROOT/$path"
  [ -f "$f" ] || { printf 'errore\t%s\t0\tfile mancante\n' "$path"; continue; }
  awk -v P="$path" '
    BEGIN {
      split("MAP TEXT CONTROL PAGE", a); for (i in a) Q["SEND " a[i]] = 1
      Q["RECEIVE MAP"] = 1
      split("WRITEQ READQ DELETEQ", b); for (i in b) { Q[b[i] " TD"] = 1; Q[b[i] " TS"] = 1 }
      split("ABEND AID CONDITION", c); for (i in c) Q["HANDLE " c[i]] = 1
      Q["IGNORE CONDITION"] = 1; Q["SYNCPOINT ROLLBACK"] = 1
      split("PROGRAM TRANSACTION FILE TERMINAL TASK", d); for (i in d) Q["INQUIRE " d[i]] = 1
      st = 0
    }
    function word(w, ln, col) {
      if (st == 0) { if (w == "EXEC") { st = 1; el = ln; ec = col } return }
      if (st == 1) { if (w == "CICS") { st = 2; return } st = 0; word(w, ln, col); return }
      if (st == 2) { if (w == "END-EXEC") { printf "errore\t%s\t%d\tblocco senza comando\n", P, el; st = 0; return }
                     c1 = w; st = 3; return }
      if (w == "EXEC") { printf "errore\t%s\t%d\tEXEC dentro un blocco\n", P, el; st = 1; el = ln; ec = col; return }
      if (st == 3) { st = 4; if ((c1 " " w) in Q) { c1 = c1 " " w; return } }
      if (w == "END-EXEC") { printf "blocco\t%s\t%d\t%d\t%d\t%s\n", P, el, ec, ln, c1; st = 0 }
    }
    { l = $0; sub(/\r$/, "", l)
      if (length(l) > 6 && substr(l, 7, 1) ~ /[*\/]/) next
      s = substr(l, 8, 65); m = ""; q = ""
      for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (q != "") { m = m "#"; if (ch == q) q = ""; continue }
        if (ch == "\047" || ch == "\"") { q = ch; m = m "#"; continue }
        if (ch == "*" && substr(s, i + 1, 1) == ">") break
        m = m ch
      }
      u = toupper(m); off = 0
      while (match(substr(u, off + 1), /[A-Z0-9-]+/)) {
        word(substr(u, off + RSTART, RLENGTH), NR, 7 + off + RSTART)
        off = off + RSTART + RLENGTH - 1
      }
    }
    END { if (st >= 2) printf "errore\t%s\t%d\tblocco non chiuso\n", P, el }' "$f" || { printf 'errore\t%s\t0\tawk fallito\n' "$path"; continue; }
  n=$((n + 1))
done < "$1"
printf 'fine\t%d\n' "$n"
