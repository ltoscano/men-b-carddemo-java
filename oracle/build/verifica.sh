#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/build/check.sh. Verifica l'output di una build.
# Uso: verifica.sh ELENCO.tsv OUT NOME:tipo ...
#   ELENCO.tsv   elenco della build da verificare (di norma /oracle/programs.tsv)
#   OUT          cartella di output della build (bin/, log/, compilazione.tsv, opzioni.txt, ambiente.txt)
#   NOME:tipo    l'elenco fisso del controllo (11 voci), tipo = eseguibile | modulo
# Stampa una riga per ogni difetto trovato; esce con 1 se ce n'e' almeno uno, con 0 altrimenti.
set -u
[ $# -ge 3 ] || { echo "uso: verifica.sh ELENCO.tsv OUT NOME:tipo ..." >&2; exit 2; }
elenco="$1"; out="$2"; shift 2
errs=0
err() { echo "DIFETTO: $*"; errs=$((errs + 1)); }
TAB="$(printf '\t')"

# 1. L'elenco della build coincide con l'elenco fisso (nomi e tipi, senza voci in piu' o in meno).
[ -f "$elenco" ] || err "elenco della build assente: $elenco"
for voce in "$@"; do printf '%s\n' "$voce"; done | sort > /tmp/fisso.txt
grep -v '^#' "$elenco" 2>/dev/null | tail -n +2 | awk -F"$TAB" 'NF>0 {print $1 ":" $3}' | sort > /tmp/build.txt
comm -23 /tmp/fisso.txt /tmp/build.txt | while read -r v; do echo "DIFETTO: elenco: $v manca nell'elenco della build (o ha un altro tipo)"; done
comm -13 /tmp/fisso.txt /tmp/build.txt | while read -r v; do echo "DIFETTO: elenco: $v nell'elenco della build ma non nell'elenco fisso del controllo"; done
d="$(comm -3 /tmp/fisso.txt /tmp/build.txt | wc -l)"; [ "$d" -eq 0 ] || errs=$((errs + d))

# 2. e 3. Per ogni programma dell'elenco fisso: compilazione riuscita e artefatto del tipo giusto.
tsv="$out/compilazione.tsv"
[ -f "$tsv" ] || err "compilazione.tsv assente"
for voce in "$@"; do
  n="${voce%%:*}"; tipo="${voce#*:}"
  riga="$(awk -F"$TAB" -v n="$n" '$1==n && $2=="legacy"' "$tsv" 2>/dev/null)"
  if [ -z "$riga" ]; then err "$n: nessuna riga in compilazione.tsv"; else
    echo "$riga" | awk -F"$TAB" -v t="$tipo" '$3==t && $4==0 && $6==0 {ok=1} END {exit !ok}' \
      || err "$n: in compilazione.tsv tipo, esito o errori non validi: $(echo "$riga" | tr "$TAB" ' ')"
    logf="$out/log/$n.log"
    if [ ! -f "$logf" ]; then err "$n: log di compilazione assente"; else
      w="$(grep -c ': warning: ' "$logf")"; e="$(grep -c ': error: ' "$logf")"
      echo "$riga" | awk -F"$TAB" -v w="$w" -v e="$e" '$5==w && $6==e {ok=1} END {exit !ok}' \
        || err "$n: avvertimenti/errori in compilazione.tsv diversi da quelli nel log ($w/$e)"
      grep -q '^codice di uscita: 0$' "$logf" || err "$n: il log non registra codice di uscita 0"
    fi
  fi
  case "$tipo" in
    eseguibile)
      a="$out/bin/$n"
      if [ ! -f "$a" ] || [ ! -x "$a" ]; then err "$n: eseguibile assente o non eseguibile (bin/$n)"; else
        nm "$a" 2>/dev/null | grep -q " T $n\$" || err "$n: l'eseguibile non contiene il programma $n"
        nm "$a" 2>/dev/null | grep -q ' T main$' || err "$n: l'eseguibile non ha main (avviatore)"
      fi
      [ ! -e "$out/bin/$n.so" ] || err "$n: c'e' anche un modulo bin/$n.so"
      ;;
    modulo)
      a="$out/bin/$n.so"
      if [ ! -f "$a" ]; then err "$n: modulo assente (bin/$n.so)"; else
        nm -D --defined-only "$a" 2>/dev/null | grep -q " T $n\$" || err "$n: il modulo non esporta il programma $n"
        nm "$a" 2>/dev/null | grep -q ' T main$' && err "$n: il modulo contiene un main"
      fi
      [ ! -e "$out/bin/$n" ] || err "$n: c'e' anche un eseguibile bin/$n"
      ;;
    *) err "$n: tipo sconosciuto nell'elenco fisso: $tipo" ;;
  esac
done

# 4. Opzioni: quelle usate sono quelle di cobc.opts, identiche in ogni compilazione COBOL.
attese="$(sed -e 's/#.*$//' /oracle/cobc.opts | awk 'NF {print $1}' | tr '\n' ' ' | sed 's/ $//')"
usate="$(tr '\n' ' ' < "$out/opzioni.txt" 2>/dev/null | sed 's/ $//')"
[ "$usate" = "$attese" ] || err "opzioni: usate '$usate', in cobc.opts '$attese'"
for voce in "$@"; do
  n="${voce%%:*}"
  first="$(grep -m1 '^comando: cobc ' "$out/log/$n.log" 2>/dev/null)"
  case "$first" in "comando: cobc $attese "*) ;; *) err "$n: compilato con opzioni diverse: $first" ;; esac
done

# 5. Ambiente: compilatore, gestore dei file indicizzati e pacchetti fissati nel Dockerfile.
amb="$out/ambiente.txt"
for atteso in 'cobc (GnuCOBOL) 3.2.0' 'indexed file handler     : BDB' 'sequential file handler  : built-in' \
              'gnucobol3 3.2-3' 'libcob4t64 3.2-3' 'libcob4-dev 3.2-3' 'libdb5.3t64 5.3.28+dfsg2-9'; do
  grep -qxF -- "$atteso" "$amb" 2>/dev/null || err "ambiente: manca la riga '$atteso'"
done

if [ "$errs" -eq 0 ]; then
  echo "verifica riuscita: $# programmi dell'elenco fisso compilati come attesi, opzioni e ambiente conformi"
  exit 0
fi
echo "verifica fallita: $errs difetti"
exit 1
