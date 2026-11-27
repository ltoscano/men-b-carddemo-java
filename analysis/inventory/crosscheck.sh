#!/bin/sh
# Secondo conteggio indipendente, con awk e senza Python (gira in container su /legacy, o su LEGACY_ROOT):
# COPY, CALL con letterale, CALL con operando in variabile, EXEC, DD, transazioni.
# Regole: commenti di riga e `*>` esclusi, letterali mascherati, operando anche sulla riga successiva; dati in linea
# (`DD *` termina a /* o //, `DD DATA` solo a /*, entrambi al delimitatore DLM=); righe commento `*` del CSD escluse.
# Uso: crosscheck.sh FILE_ELENCO   (righe "tipo<TAB>percorso"); stampa "tipo<TAB>file<TAB>valore" ordinato.
ROOT="${LEGACY_ROOT:-/legacy}"
while IFS="	" read -r tipo path; do
  f="$ROOT/$path"
  case "$tipo" in
    cobol|copybook)
      awk -v P="$path" '
        function rep(n,   r) { r=""; while (n-- > 0) r = r "#"; return r }
        function scan(u, s, kw,   off, i, pos, pre, post, rest, c) {
          off = 0
          while ((i = index(substr(u, off + 1), kw)) > 0) {
            pos = off + i; off = pos + length(kw) - 1
            pre = (pos > 1) ? substr(u, pos - 1, 1) : " "; post = substr(u, pos + length(kw), 1)
            if (pre ~ /[A-Z0-9-]/ || post ~ /[A-Z0-9-]/) continue
            rest = substr(s, pos + length(kw)); sub(/^[ \t]+/, "", rest)
            if (rest == "") { pend = kw; continue }
            c = substr(rest, 1, 1)
            if (c ~ /["\047]/) lit[kw]++; else if (c ~ /[A-Za-z0-9]/) var[kw]++
          }
        }
        { l = $0; sub(/\r$/, "", l); if (length(l) > 6 && substr(l, 7, 1) ~ /[*\/]/) next
          s = substr(l, 8, 65); m = s
          while (match(m, /\047[^\047]*\047|"[^"]*"/)) m = substr(m, 1, RSTART - 1) rep(RLENGTH) substr(m, RSTART + RLENGTH)
          k = index(m, "*>"); if (k > 0) { s = substr(s, 1, k - 1); m = substr(m, 1, k - 1) }
          u = toupper(m)
          if (pend != "" && u ~ /[^ \t]/) {
            r = s; sub(/^[ \t]+/, "", r); c = substr(r, 1, 1)
            if (c ~ /["\047]/) lit[pend]++; else if (c ~ /[A-Za-z0-9]/) var[pend]++
            pend = ""
          }
          scan(u, s, "COPY"); scan(u, s, "CALL") }
        END { printf "copy\t%s\t%d\ncall\t%s\t%d\ncall_var\t%s\t%d\n", P, lit["COPY"] + var["COPY"], P, lit["CALL"] + 0, P, var["CALL"] + 0 }' "$f" ;;
    jcl|proc)
      awk -v P="$path" '
        { l = substr($0, 1, 72); sub(/\r$/, "", l)
          if (mode != "") {
            if (dlm != "") { if (index(l, dlm) == 1) mode = ""; next }
            if (substr(l, 1, 2) == "/*") { mode = ""; next }
            if (mode == "*" && substr(l, 1, 2) == "//") mode = ""; else next
          }
          if (substr(l, 1, 3) == "//*") next
          if (l ~ /^\/\/[^ ]* +EXEC( |$)/) e++
          else if (l ~ /^\/\/[^ ]* +DD( |$)/) {
            d++; r = l; sub(/^\/\/[^ ]* +DD +/, "", r)
            if (r ~ /^(\*|DATA)( |,|$)/) {
              mode = (substr(r, 1, 1) == "*") ? "*" : "D"; dlm = ""
              if (match(r, /DLM=[^ ,]+/)) { x = substr(r, RSTART + 4, RLENGTH - 4); gsub(/\047/, "", x); dlm = substr(x, 1, 2) }
            } } }
        END { printf "exec\t%s\t%d\ndd\t%s\t%d\n", P, e + 0, P, d + 0 }' "$f" ;;
    csd)
      printf 'transazioni\t%s\t%s\n' "$path" "$(awk 'toupper($0) ~ /^ *DEFINE +TRANSACTION\(/ {n++} END {print n+0}' "$f")" ;;
  esac
done < "$1" | LC_ALL=C sort
