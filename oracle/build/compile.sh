#!/bin/sh
# Eseguito DENTRO il container dell'oracle (vedi oracle/lib.sh, orun). Compila con cobc:
#   - gli stub e i segnaposto di oracle/stubs/          -> moduli (bin/<NOME>.so)
#   - i programmi del legacy elencati in un file .tsv   -> eseguibili (bin/<NOME>) o moduli (bin/<NOME>.so)
#   - i programmi di prova di oracle/tests/             -> eseguibili
# Opzioni: tutte e sole quelle di /oracle/cobc.opts, uguali per tutti. In piu', per tipo di artefatto:
#   eseguibile: cobc -c <opzioni> sorgente  e poi  cobc -x -A -DMENB_ENTRY=<NOME> avvia.c <NOME>.o
#               (il secondo comando compila solo il C dell'avviatore e collega);
#   modulo:     cobc -m <opzioni> sorgente.
#
# Uso:
#   compile.sh tutto ELENCO.tsv OUT
#       compila tutto; scrive OUT/bin, OUT/log/<NOME>.log, OUT/compilazione.tsv, OUT/opzioni.txt, OUT/ambiente.txt.
#       Esce con 1 se una compilazione fallisce.
#   compile.sh uno TIPO SORGENTE NOME OUT [opzione cobc in piu'] [opzione C in piu' per l'avviatore]
#       compila un solo programma (usato dalle prove negative dei controlli, mai dalla build).
set -u

OPTFILE=/oracle/cobc.opts
LAUNCHER=/oracle/launcher/avvia.c

die() { echo "compile.sh: $*" >&2; exit 1; }

# Opzioni dal file: righe senza commenti e senza spazi iniziali/finali; una sola parola per riga.
OPTS=""
while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$line" ] || continue
  case "$line" in *[[:space:]]*) die "opzione con spazi in $OPTFILE: '$line'" ;; esac
  OPTS="$OPTS${OPTS:+ }$line"
done < "$OPTFILE"
[ -n "$OPTS" ] || die "nessuna opzione in $OPTFILE"

# compila TIPO SORGENTE NOME OUT [cobc-extra] [c-extra]; scrive OUT/log/NOME.log; ritorna il codice di cobc
compila() {
  tipo="$1"; src="$2"; nome="$3"; out="$4"; xcob="${5:-}"; xc="${6:-}"
  mkdir -p "$out/bin" "$out/obj" "$out/log"
  logf="$out/log/$nome.log"
  : > "$logf"
  case "$tipo" in
    modulo)
      echo "comando: cobc $OPTS${xcob:+ $xcob} -m -o bin/$nome.so $src" >> "$logf"
      # shellcheck disable=SC2086
      cobc $OPTS $xcob -m -o "$out/bin/$nome.so" "$src" >> "$logf" 2>&1
      rc=$?
      ;;
    eseguibile)
      echo "comando: cobc $OPTS${xcob:+ $xcob} -c -o obj/$nome.o $src" >> "$logf"
      # shellcheck disable=SC2086
      cobc $OPTS $xcob -c -o "$out/obj/$nome.o" "$src" >> "$logf" 2>&1
      rc=$?
      if [ "$rc" -eq 0 ]; then
        echo "comando: cobc -x -A -DMENB_ENTRY=$nome${xc:+ -A $xc} -o bin/$nome $LAUNCHER obj/$nome.o" >> "$logf"
        if [ -n "$xc" ]; then
          cobc -x -A "-DMENB_ENTRY=$nome" -A "$xc" -o "$out/bin/$nome" "$LAUNCHER" "$out/obj/$nome.o" >> "$logf" 2>&1
        else
          cobc -x -A "-DMENB_ENTRY=$nome" -o "$out/bin/$nome" "$LAUNCHER" "$out/obj/$nome.o" >> "$logf" 2>&1
        fi
        rc=$?
      fi
      ;;
    *) die "tipo sconosciuto: $tipo" ;;
  esac
  echo "codice di uscita: $rc" >> "$logf"
  return "$rc"
}

# riga TSV: nome origine tipo codice avvertimenti errori
riga() {
  w="$(grep -c ': warning: ' "$4/log/$1.log")"
  e="$(grep -c ': error: ' "$4/log/$1.log")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$5" "$w" "$e" >> "$4/compilazione.tsv"
}

case "${1:-}" in
  tutto)
    [ $# -eq 3 ] || die "uso: compile.sh tutto ELENCO.tsv OUT"
    elenco="$2"; out="$3"
    [ -f "$elenco" ] || die "elenco assente: $elenco"
    mkdir -p "$out" || die "impossibile creare $out"
    printf 'programma\torigine\ttipo\tcodice_uscita\tavvertimenti\terrori\n' > "$out/compilazione.tsv"
    printf '%s\n' $OPTS > "$out/opzioni.txt"
    for f in /oracle/stubs/*.cbl; do
      n="$(basename "$f" .cbl)"
      compila modulo "$f" "$n" "$out"; rc=$?
      riga "$n" stub modulo "$out" "$rc"
    done
    # Programmi del legacy: righe non commento, intestazione esclusa.
    grep -v '^#' "$elenco" | tail -n +2 | while IFS="$(printf '\t')" read -r n src tipo motivo; do
      [ -n "$n" ] || continue
      compila "$tipo" "/legacy/$src" "$n" "$out"; rc=$?
      riga "$n" legacy "$tipo" "$out" "$rc"
    done
    for n in PARMECHO ABDUSING ABDNOARG M03BCALL DTCCALL; do
      compila eseguibile "/oracle/tests/$n.cbl" "$n" "$out"; rc=$?
      riga "$n" prova eseguibile "$out" "$rc"
    done
    rm -rf "$out/obj"
    # Ambiente effettivo: versioni, gestore dei file indicizzati, configurazione di runtime.
    {
      echo "== cobc --version"; cobc --version | head -1
      echo "== cobc --info"; cobc --info | sed -n '/GnuCOBOL information/,$p'
      echo "== pacchetti"
      dpkg-query -W -f '${Package} ${Version}\n' gnucobol3 libcob4t64 libcob4-dev libdb5.3t64 gcc-14 libc6 libgmp10 libxml2
      echo "== cobcrun --runtime-config"; cobcrun --runtime-config 2>&1
    } > "$out/ambiente.txt" 2>&1
    # Un programma del legacy che non compila fa fallire la build (le righe con codice diverso da 0).
    fl="$(awk -F'\t' 'NR>1 && $4!=0' "$out/compilazione.tsv" | wc -l)"
    [ "$fl" -eq 0 ] || { awk -F'\t' 'NR>1 && $4!=0 {print "compile.sh: compilazione fallita: " $1}' "$out/compilazione.tsv" >&2; exit 1; }
    ;;
  uno)
    [ $# -ge 5 ] || die "uso: compile.sh uno TIPO SORGENTE NOME OUT [opzione cobc] [opzione C]"
    compila "$2" "$3" "$4" "$5" "${6:-}" "${7:-}" || { cat "$5/log/$4.log" >&2; exit 1; }
    ;;
  *) die "uso: compile.sh tutto ELENCO.tsv OUT | compile.sh uno TIPO SORGENTE NOME OUT [opzione cobc] [opzione C]" ;;
esac
