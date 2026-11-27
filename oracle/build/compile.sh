#!/bin/sh
# Eseguito DENTRO il container dell'oracle (vedi oracle/lib.sh, orun). Compila con cobc:
#   - gli stub e i segnaposto di oracle/stubs/          -> moduli (bin/<NOME>.so)
#   - i programmi del legacy elencati in un file .tsv   -> eseguibili (bin/<NOME>) o moduli (bin/<NOME>.so)
#   - i programmi di prova di oracle/tests/             -> eseguibili
# Opzioni: tutte e sole quelle di /oracle/cobc.opts, uguali per tutti. In piu', per tipo di artefatto,
# solo questi argomenti strutturali (verificati uno per uno da oracle/build/verifica.sh):
#   modulo:     cobc <opzioni> -m -o OUT/bin/<NOME>.so <sorgente>
#   eseguibile: cobc <opzioni> -c -o OUT/obj/<NOME>.o <sorgente>
#               cobc -x -A -DMENB_ENTRY=<NOME> -o OUT/bin/<NOME> /oracle/launcher/avvia.c OUT/obj/<NOME>.o
#               (il secondo comando compila solo il C dell'avviatore e collega).
# Ogni invocazione di cobc passa da cobc_reg, che scrive nel log gli argomenti effettivi, uno per riga
# ("== cobc", poi "arg <argomento>"), e poi esegue esattamente quegli argomenti.
#
# Uso:
#   compile.sh tutto ELENCO.tsv OUT
#       compila tutto; scrive OUT/bin, OUT/log/<NOME>.log, OUT/compilazione.tsv, OUT/opzioni.txt, OUT/ambiente.txt
#       e l'ambiente effettivo: ambiente-cobc.txt, ambiente-run.txt (variabili ricevute), cobc-info.txt,
#       configurazione.sha256 (cartella di configurazione riportata da cobc e SHA-256 dei suoi file),
#       runtime-config.txt (configurazione di runtime riportata da libcob).
#       Esce con 1 se una compilazione fallisce.
#   compile.sh uno TIPO SORGENTE NOME OUT [opzione cobc in piu'] [opzione C in piu' per l'avviatore]
#       compila un solo programma (usato dalle prove negative dei controlli, mai dalla build). Solo in
#       questo modo UNO_OPZIONI puo' indicare un file di opzioni alterato al posto di /oracle/cobc.opts.
set -u

OPTFILE=/oracle/cobc.opts
if [ "${1:-}" = uno ] && [ -n "${UNO_OPZIONI:-}" ]; then OPTFILE="$UNO_OPZIONI"; fi
LAUNCHER=/oracle/launcher/avvia.c
# Programmi di prova (oracle/tests/), tutti eseguibili.
PROVE="PARMECHO ABDUSING ABDNOARG M03BCALL DTCCALL SEGNOPRB PERFPRB DATFTPRB"

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

# Ambiente fissato (AMBIENTE_COBC, AMBIENTE_RUN): cobc parte sempre da `env -i` con quelle sole variabili.
. /oracle/ambiente.sh

# cobc_reg ARGOMENTI...: registra gli argomenti nel log ($logf) e li esegue tali e quali, nell'ambiente fissato.
cobc_reg() {
  { echo "== cobc"; for a in "$@"; do printf 'arg %s\n' "$a"; done; } >> "$logf"
  # shellcheck disable=SC2086
  env -i $AMBIENTE_COBC cobc "$@" >> "$logf" 2>&1
  r=$?
  echo "== codice $r" >> "$logf"
  return "$r"
}

# compila TIPO SORGENTE NOME OUT [cobc-extra] [c-extra]; scrive OUT/log/NOME.log; ritorna il codice di cobc
compila() {
  tipo="$1"; src="$2"; nome="$3"; out="$4"; xcob="${5:-}"; xc="${6:-}"
  mkdir -p "$out/bin" "$out/obj" "$out/log"
  logf="$out/log/$nome.log"
  : > "$logf"
  case "$tipo" in
    modulo)
      # shellcheck disable=SC2086
      set -- $OPTS $xcob -m -o "$out/bin/$nome.so" "$src"
      cobc_reg "$@"; rc=$?
      ;;
    eseguibile)
      # shellcheck disable=SC2086
      set -- $OPTS $xcob -c -o "$out/obj/$nome.o" "$src"
      cobc_reg "$@"; rc=$?
      if [ "$rc" -eq 0 ]; then
        if [ -n "$xc" ]; then
          set -- -x -A "-DMENB_ENTRY=$nome" -A "$xc" -o "$out/bin/$nome" "$LAUNCHER" "$out/obj/$nome.o"
        else
          set -- -x -A "-DMENB_ENTRY=$nome" -o "$out/bin/$nome" "$LAUNCHER" "$out/obj/$nome.o"
        fi
        cobc_reg "$@"; rc=$?
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
    # shellcheck disable=SC2086
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
    for n in $PROVE; do
      compila eseguibile "/oracle/tests/$n.cbl" "$n" "$out"; rc=$?
      riga "$n" prova eseguibile "$out" "$rc"
    done
    rm -rf "$out/obj"
    # Ambiente effettivo, sempre letto nello stesso ambiente fissato usato per compilare ed eseguire:
    # versioni, gestore dei file indicizzati, configurazione di runtime.
    # shellcheck disable=SC2086
    {
      echo "== cobc --version"; env -i $AMBIENTE_COBC cobc --version | head -1
      echo "== cobc --info"; env -i $AMBIENTE_COBC cobc --info | sed -n '/GnuCOBOL information/,$p'
      echo "== pacchetti"
      dpkg-query -W -f '${Package} ${Version}\n' gnucobol3 libcob4t64 libcob4-dev libdb5.3t64 gcc-14 libc6 libgmp10 libxml2
      echo "== cobcrun --runtime-config"; env -i $AMBIENTE_RUN cobcrun --runtime-config 2>&1
    } > "$out/ambiente.txt" 2>&1
    # Le variabili che ricevono cobc e i programmi (una per riga, nell'ordine dell'elenco).
    # shellcheck disable=SC2086
    env -i $AMBIENTE_COBC env > "$out/ambiente-cobc.txt"
    # shellcheck disable=SC2086
    env -i $AMBIENTE_RUN env > "$out/ambiente-run.txt"
    # Configurazione del compilatore come la riporta cobc stesso (cobc --info: COB_CONFIG_DIR, piu' una
    # riga "env:" per ogni variabile che la sostituisce) e contenuto della cartella effettivamente usata.
    # shellcheck disable=SC2086
    env -i $AMBIENTE_COBC cobc --info > "$out/cobc-info.txt" 2>&1
    cfg="$(awk -F': ' '/^  env: COB_CONFIG_DIR/ {e=$2} /^COB_CONFIG_DIR/ {d=$2} END {print (e != "" ? e : d)}' "$out/cobc-info.txt" | sed 's/[[:space:]]*$//')"
    { echo "cartella $cfg"; (cd "$cfg" && LC_ALL=C ls -A | while read -r f; do sha256sum "$f"; done); } > "$out/configurazione.sha256"
    # Configurazione di runtime come la riporta libcob (cobcrun --runtime-config) nell'ambiente dei programmi.
    # shellcheck disable=SC2086
    env -i $AMBIENTE_RUN cobcrun --runtime-config > "$out/runtime-config.txt" 2>&1
    # Un programma che non compila fa fallire la build (le righe con codice diverso da 0).
    fl="$(awk -F'\t' 'NR>1 && $4!=0' "$out/compilazione.tsv" | wc -l)"
    [ "$fl" -eq 0 ] || { awk -F'\t' 'NR>1 && $4!=0 {print "compile.sh: compilazione fallita: " $1}' "$out/compilazione.tsv" >&2; exit 1; }
    ;;
  uno)
    [ $# -ge 5 ] || die "uso: compile.sh uno TIPO SORGENTE NOME OUT [opzione cobc] [opzione C]"
    compila "$2" "$3" "$4" "$5" "${6:-}" "${7:-}" || { cat "$5/log/$4.log" >&2; exit 1; }
    ;;
  *) die "uso: compile.sh tutto ELENCO.tsv OUT | compile.sh uno TIPO SORGENTE NOME OUT [opzione cobc] [opzione C]" ;;
esac
