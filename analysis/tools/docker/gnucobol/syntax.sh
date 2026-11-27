#!/bin/sh
# Eseguito DENTRO il container gnucobol: cobc -fsyntax-only su ogni programma elencato in /in/programs.txt
# (percorsi relativi al legacy, presi dal manifesto). Scrive un log per programma e syntax.tsv in /out.
# Uso: syntax.sh
set -u
mkdir -p /out/log
printf 'programma\tcodice_uscita\terrori\tavvertimenti\n' > /out/syntax.tsv
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  prog="$(basename "$rel")"; prog="${prog%.*}"
  cobc -fsyntax-only -std=ibm -I /legacy/app/cpy -I /legacy/app/cpy-bms "/legacy/$rel" > "/out/log/$prog.log" 2>&1
  rc=$?
  errors="$(grep -c ': error: ' "/out/log/$prog.log")"
  warnings="$(grep -c ': warning: ' "/out/log/$prog.log")"
  printf '%s\t%s\t%s\t%s\n' "$prog" "$rc" "$errors" "$warnings" >> /out/syntax.tsv
done < /in/programs.txt
