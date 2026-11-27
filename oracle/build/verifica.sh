#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/build/check.sh. Verifica l'output di una build.
# Uso: verifica.sh ELENCO.tsv OUT "OPZIONI" VOCE ...
#   ELENCO.tsv  elenco della build da verificare (di norma /oracle/programs.tsv)
#   OUT         cartella di output della build (bin/, log/, compilazione.tsv, opzioni.txt, ambiente.txt)
#   OPZIONI     le opzioni di cobc fissate nel controllo, separate da spazi, nell'ordine
#   VOCE        origine:NOME:tipo:sorgente, con origine = legacy | stub | prova, tipo = eseguibile | modulo,
#               sorgente = percorso nel container. Le voci legacy sono l'elenco fisso degli 11.
# Tutti i confronti sono esatti (righe intere, insiemi interi): niente prefissi, sottostringhe o jolly.
# Stampa una riga per ogni difetto trovato; esce con 1 se ce n'e' almeno uno, con 0 altrimenti.
set -u
[ $# -ge 4 ] || { echo "uso: verifica.sh ELENCO.tsv OUT OPZIONI VOCE ..." >&2; exit 2; }
elenco="$1"; out="$2"; opzioni="$3"; shift 3
errs=0
err() { echo "DIFETTO: $*"; errs=$((errs + 1)); }
TAB="$(printf '\t')"
w=/tmp/verifica; rm -rf "$w"; mkdir -p "$w"

# 1. L'elenco della build coincide con le voci legacy (nome, tipo e sorgente; niente in piu' o in meno).
[ -f "$elenco" ] || err "elenco della build assente: $elenco"
for v in "$@"; do
  case "$v" in legacy:*) echo "$v" | awk -F: '{sub("^/legacy/", "", $4); print $2 ":" $3 ":" $4}' ;; esac
done | sort > "$w/fisso.txt"
grep -v '^#' "$elenco" 2>/dev/null | tail -n +2 | awk -F"$TAB" 'NF>0 {print $1 ":" $3 ":" $2}' | sort > "$w/build.txt"
comm -23 "$w/fisso.txt" "$w/build.txt" | while read -r v; do echo "DIFETTO: elenco: $v manca nell'elenco della build (o ha altro tipo o sorgente)"; done
comm -13 "$w/fisso.txt" "$w/build.txt" | while read -r v; do echo "DIFETTO: elenco: $v nell'elenco della build ma non nell'elenco fisso del controllo"; done
d="$(comm -3 "$w/fisso.txt" "$w/build.txt" | wc -l)"; [ "$d" -eq 0 ] || errs=$((errs + d))

# 2. compilazione.tsv e bin/ contengono esattamente le voci attese, ne' piu' ne' meno.
tsv="$out/compilazione.tsv"
[ -f "$tsv" ] || err "compilazione.tsv assente"
for v in "$@"; do echo "$v" | awk -F: '{print $2}'; done | sort > "$w/nomi.txt"
awk -F"$TAB" 'NR>1 {print $1}' "$tsv" 2>/dev/null | sort > "$w/tsv-nomi.txt"
cmp -s "$w/nomi.txt" "$w/tsv-nomi.txt" || err "compilazione.tsv: programmi diversi da quelli attesi: $(comm -3 "$w/nomi.txt" "$w/tsv-nomi.txt" | tr -d '\t' | tr '\n' ' ')"
for v in "$@"; do echo "$v" | awk -F: '{ if ($3 == "modulo") print $2 ".so"; else print $2 }'; done | sort > "$w/artefatti.txt"
ls -A "$out/bin" 2>/dev/null | sort > "$w/bin.txt"
cmp -s "$w/artefatti.txt" "$w/bin.txt" || err "bin/: artefatti diversi da quelli attesi: $(comm -3 "$w/artefatti.txt" "$w/bin.txt" | tr -d '\t' | tr '\n' ' ')"

# 3. Per ogni voce: una sola riga in compilazione.tsv, compilazione riuscita, argomenti di cobc esatti,
#    artefatto del tipo giusto.
for v in "$@"; do
  orig="$(echo "$v" | cut -d: -f1)"; n="$(echo "$v" | cut -d: -f2)"
  tipo="$(echo "$v" | cut -d: -f3)"; src="$(echo "$v" | cut -d: -f4-)"
  righe="$(awk -F"$TAB" -v n="$n" 'NR>1 && $1==n' "$tsv" 2>/dev/null)"
  if [ "$(printf '%s' "$righe" | grep -c '')" -ne 1 ]; then err "$n: attesa una riga in compilazione.tsv, trovate $(printf '%s' "$righe" | grep -c '')"; else
    echo "$righe" | awk -F"$TAB" -v o="$orig" -v t="$tipo" '$2==o && $3==t && $4==0 && $6==0 {ok=1} END {exit !ok}' \
      || err "$n: in compilazione.tsv origine, tipo, esito o errori non validi: $(echo "$righe" | tr "$TAB" ' ')"
  fi
  logf="$out/log/$n.log"
  if [ ! -f "$logf" ]; then err "$n: log di compilazione assente"; else
    wn="$(grep -c ': warning: ' "$logf")"; en="$(grep -c ': error: ' "$logf")"
    echo "$righe" | awk -F"$TAB" -v w="$wn" -v e="$en" '$5==w && $6==e {ok=1} END {exit !ok}' \
      || err "$n: avvertimenti/errori in compilazione.tsv diversi da quelli nel log ($wn/$en)"
    [ "$(tail -n 1 "$logf")" = "codice di uscita: 0" ] || err "$n: l'ultima riga del log non e' 'codice di uscita: 0'"
    # Argomenti effettivi di ogni invocazione di cobc (registrati da compile.sh, uno per riga) contro
    # quelli attesi: le opzioni fissate e i soli argomenti strutturali del tipo, elencati qui.
    grep -E '^(== cobc$|arg )' "$logf" > "$w/argomenti.txt"
    {
      echo "== cobc"
      for o in $opzioni; do echo "arg $o"; done
      case "$tipo" in
        modulo)     printf 'arg %s\n' -m -o "/out/bin/$n.so" "$src" ;;
        eseguibile) printf 'arg %s\n' -c -o "/out/obj/$n.o" "$src"
                    echo "== cobc"
                    printf 'arg %s\n' -x -A "-DMENB_ENTRY=$n" -o "/out/bin/$n" /oracle/launcher/avvia.c "/out/obj/$n.o" ;;
      esac
    } > "$w/attesi.txt"
    if ! cmp -s "$w/attesi.txt" "$w/argomenti.txt"; then
      err "$n: argomenti di cobc diversi da quelli attesi:"
      diff "$w/attesi.txt" "$w/argomenti.txt" | sed 's/^/      /'
    fi
    grep -E '^== codice ' "$logf" | grep -vx '== codice 0' > /dev/null && err "$n: un'invocazione di cobc non e' terminata con 0"
  fi
  case "$tipo" in
    eseguibile)
      a="$out/bin/$n"
      if [ ! -f "$a" ] || [ ! -x "$a" ]; then err "$n: eseguibile assente o non eseguibile (bin/$n)"; else
        nm "$a" 2>/dev/null | awk -v n="$n" '$2=="T" && $3==n {f=1} END {exit !f}' || err "$n: l'eseguibile non contiene il programma $n"
        nm "$a" 2>/dev/null | awk '$2=="T" && $3=="main" {f=1} END {exit !f}' || err "$n: l'eseguibile non ha main (avviatore)"
      fi
      ;;
    modulo)
      a="$out/bin/$n.so"
      if [ ! -f "$a" ]; then err "$n: modulo assente (bin/$n.so)"; else
        nm -D --defined-only "$a" 2>/dev/null | awk -v n="$n" '$2=="T" && $3==n {f=1} END {exit !f}' || err "$n: il modulo non esporta il programma $n"
        nm "$a" 2>/dev/null | awk '$2=="T" && $3=="main" {f=1} END {exit f}' || err "$n: il modulo contiene un main"
      fi
      ;;
    *) err "$n: tipo sconosciuto nell'elenco fisso: $tipo" ;;
  esac
done

# 4. opzioni.txt: esattamente le opzioni fissate, una per riga, nell'ordine.
for o in $opzioni; do echo "$o"; done > "$w/opzioni-attese.txt"
cmp -s "$w/opzioni-attese.txt" "$out/opzioni.txt" 2>/dev/null \
  || err "opzioni: usate '$(tr '\n' ' ' < "$out/opzioni.txt" 2>/dev/null)', fissate '$opzioni'"

# 5. Ambiente: compilatore, gestore dei file indicizzati e pacchetti fissati nel Dockerfile (righe intere).
amb="$out/ambiente.txt"
for atteso in 'cobc (GnuCOBOL) 3.2.0' 'indexed file handler     : BDB' 'sequential file handler  : built-in' \
              'gnucobol3 3.2-3' 'libcob4t64 3.2-3' 'libcob4-dev 3.2-3' 'libdb5.3t64 5.3.28+dfsg2-9'; do
  grep -qxF -- "$atteso" "$amb" 2>/dev/null || err "ambiente: manca la riga '$atteso'"
done

if [ "$errs" -eq 0 ]; then
  echo "verifica riuscita: $# programmi compilati con gli argomenti attesi (11 del legacy), opzioni e ambiente conformi"
  exit 0
fi
echo "verifica fallita: $errs difetti"
exit 1
