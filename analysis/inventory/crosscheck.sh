#!/bin/sh
# Secondo conteggio indipendente, con awk e senza Python (gira in container su /legacy): COPY, CALL con letterale, EXEC, DD, transazioni.
# Uso: crosscheck.sh FILE_ELENCO_TIPO_PERCORSO   (righe "tipo<TAB>percorso"); stampa "tipo<TAB>file<TAB>valore" ordinato.
while IFS="	" read -r tipo path; do
  f="/legacy/$path"
  case "$tipo" in
    cobol|copybook)
      awk -v T="$tipo" -v P="$path" '
        { l=$0; sub(/\r$/,"",l); if (length(l)>6 && substr(l,7,1) ~ /[*\/]/) next; s=toupper(substr(l,8,65)) }
        s ~ /(^|[^A-Z0-9-])COPY +[A-Z0-9"\047]/ { c++ }
        T=="cobol" && s ~ /(^|[^A-Z0-9-])CALL +["\047]/ { k++ }
        END { printf "copy\t%s\t%d\n", P, c+0; if (T=="cobol") printf "call\t%s\t%d\n", P, k+0 }' "$f" ;;
    jcl|proc)
      awk -v P="$path" '
        { l=substr($0,1,72); sub(/\r$/,"",l)
          if (ins) { if (l ~ /^\/\*/ || l ~ /^\/\//) ins=0; else next }
          if (l ~ /^\/\/\*/) next
          if (l ~ /^\/\/[^ ]* +EXEC( |$)/) e++
          else if (l ~ /^\/\/[^ ]* +DD( |$)/) { d++; r=l; sub(/^\/\/[^ ]* +DD +/,"",r); if (r ~ /^(\*|DATA)( |,|$)/) ins=1 } }
        END { printf "exec\t%s\t%d\ndd\t%s\t%d\n", P, e+0, P, d+0 }' "$f" ;;
    csd)
      printf 'transazioni\t%s\t%s\n' "$path" "$(grep -i -c '^ *DEFINE  *TRANSACTION(' "$f")" ;;
  esac
done < "$1" | LC_ALL=C sort
