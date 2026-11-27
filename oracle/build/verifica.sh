#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/build/check.sh. Verifica l'output di una build.
# Uso: verifica.sh ELENCO.tsv OUT "OPZIONI" "AMBIENTE-COBC" "AMBIENTE-RUN" VOCE ...
#   ELENCO.tsv  elenco della build da verificare (di norma /oracle/programs.tsv)
#   OUT         cartella di output della build (bin/, log/, compilazione.tsv, opzioni.txt, ambiente.txt,
#               ambiente-cobc.txt, ambiente-run.txt, cobc-info.txt, configurazione.sha256, runtime-config.txt)
#   OPZIONI     le opzioni di cobc fissate nel controllo, separate da spazi, nell'ordine
#   AMBIENTE-*  le variabili fissate nel controllo per cobc e per i programmi (VAR=valore separate da spazi)
# Attesi fissati in /oracle/build/expected/: configurazione.sha256 (cartella e SHA-256 dei file di
# configurazione del compilatore) e runtime-config.txt (configurazione di runtime riportata da libcob).
#   VOCE        origine:NOME:tipo:sorgente, con origine = legacy | adattato | stub | prova, tipo = eseguibile |
#               modulo, sorgente = percorso nel container. Le voci legacy e adattato sono l'elenco fisso dei
#               12 programmi del legacy. Per una voce adattato il sorgente e' l'originale (quello dell'elenco
#               della build); si compila la copia OUT/adattati/<nome del file>, con -I/out/adattati come
#               primo argomento di cobc (oracle/build/compile.sh, oracle/adattamenti/registro.md).
# Tutti i confronti sono esatti (righe intere, insiemi interi): niente prefissi, sottostringhe o jolly.
# Stampa una riga per ogni difetto trovato; esce con 1 se ce n'e' almeno uno, con 0 altrimenti.
# Esiti (issue #35): dove il fallimento di un comando potrebbe far passare un difetto, l'esito e' controllato
# e un fallimento e' un DIFETTO. Esiti ammessi di grep: 0 e 1 (nessuna riga trovata) per -c, -E e -v.
set -u
set -o pipefail
[ $# -ge 6 ] || { echo "uso: verifica.sh ELENCO.tsv OUT OPZIONI AMBIENTE-COBC AMBIENTE-RUN VOCE ..." >&2; exit 2; }
elenco="$1"; out="$2"; opzioni="$3"; amb_cobc="$4"; amb_run="$5"; shift 5
ATTESI=/oracle/build/expected
errs=0
err() { echo "DIFETTO: $*"; errs=$((errs + 1)); }
# conta MODELLO FILE: righe del FILE che contengono MODELLO; ritorna 1 se grep -c esce con un codice diverso
# da 0 e 1 o se il conteggio non e' un numero.
conta() {
  c="$(grep -c -- "$1" "$2")"
  r=$?
  [ "$r" -le 1 ] || return 1
  case "$c" in ''|*[!0-9]*) return 1 ;; esac
  echo "$c"
}
# Tabulazione come costante (issue #35: prima era "$(printf '\t')", una sostituzione senza esito controllato).
TAB='	'
# op CODICE DESCRIZIONE: esito di un passo di preparazione della verifica; diverso da 0 e' un DIFETTO (giro 1
# della PR #49: una pipeline o un'assegnazione fallita seguita da un confronto riuscito faceva passare la verifica).
op() { [ "$1" -eq 0 ] || err "verifica incompleta: $2 fallito (codice $1)"; }
# campi VOCE: orig, n, tipo, src dalla voce origine:NOME:tipo:sorgente, senza comandi esterni (prima cut).
campi() { orig="${1%%:*}"; resto="${1#*:}"; n="${resto%%:*}"; resto="${resto#*:}"; tipo="${resto%%:*}"; src="${resto#*:}"; }
w=/tmp/verifica
rm -rf "$w" && mkdir -p "$w" || { echo "verifica.sh: cartella di lavoro $w non creabile" >&2; exit 2; }

# 1. L'elenco della build coincide con le voci legacy (nome, tipo e sorgente; niente in piu' o in meno).
#    Ogni passo scrive un file e ha l'esito controllato; grep -v ammette 0 e 1 (nessuna riga non commento).
[ -f "$elenco" ] || err "elenco della build assente: $elenco"
for v in "$@"; do
  campi "$v"
  case "$orig" in legacy|adattato) printf '%s:%s:%s\n' "$n" "$tipo" "${src#/legacy/}" ;; esac
done > "$w/fisso.voci"; op $? "scrittura dell'elenco fisso"
sort "$w/fisso.voci" > "$w/fisso.txt"; op $? "ordinamento dell'elenco fisso (sort)"
grep -v '^#' "$elenco" > "$w/elenco.senza-commenti" 2>/dev/null
r=$?; [ "$r" -le 1 ] || op "$r" "lettura dell'elenco della build (grep -v)"
tail -n +2 "$w/elenco.senza-commenti" > "$w/elenco.righe"; op $? "lettura dell'elenco della build (tail)"
awk -F"$TAB" 'NF>0 {print $1 ":" $3 ":" $2}' "$w/elenco.righe" > "$w/build.voci"; op $? "lettura dell'elenco della build (awk)"
sort "$w/build.voci" > "$w/build.txt"; op $? "ordinamento dell'elenco della build (sort)"
comm -23 "$w/fisso.txt" "$w/build.txt" > "$w/mancanti.txt"; op $? "confronto con l'elenco fisso (comm -23)"
comm -13 "$w/fisso.txt" "$w/build.txt" > "$w/in-piu.txt"; op $? "confronto con l'elenco fisso (comm -13)"
while IFS= read -r v; do err "elenco: $v manca nell'elenco della build (o ha altro tipo o sorgente)"; done < "$w/mancanti.txt"
while IFS= read -r v; do err "elenco: $v nell'elenco della build ma non nell'elenco fisso del controllo"; done < "$w/in-piu.txt"

# 2. compilazione.tsv e bin/ contengono esattamente le voci attese, ne' piu' ne' meno.
tsv="$out/compilazione.tsv"
[ -f "$tsv" ] || err "compilazione.tsv assente"
for v in "$@"; do campi "$v"; echo "$n"; done > "$w/nomi.voci"; op $? "scrittura dei nomi attesi"
sort "$w/nomi.voci" > "$w/nomi.txt"; op $? "ordinamento dei nomi attesi (sort)"
: > "$w/tsv-nomi.voci"
[ ! -f "$tsv" ] || { awk -F"$TAB" 'NR>1 {print $1}' "$tsv" > "$w/tsv-nomi.voci"; op $? "lettura dei nomi di compilazione.tsv (awk)"; }
sort "$w/tsv-nomi.voci" > "$w/tsv-nomi.txt"; op $? "ordinamento dei nomi di compilazione.tsv (sort)"
cmp -s "$w/nomi.txt" "$w/tsv-nomi.txt" || err "compilazione.tsv: programmi diversi da quelli attesi: $(comm -3 "$w/nomi.txt" "$w/tsv-nomi.txt" | tr -d '\t' | tr '\n' ' ')"
for v in "$@"; do
  campi "$v"
  case "$tipo" in modulo) echo "$n.so" ;; *) echo "$n" ;; esac
done > "$w/artefatti.voci"; op $? "scrittura degli artefatti attesi"
sort "$w/artefatti.voci" > "$w/artefatti.txt"; op $? "ordinamento degli artefatti attesi (sort)"
: > "$w/bin.voci"
[ ! -d "$out/bin" ] || { ls -A "$out/bin" > "$w/bin.voci"; op $? "elenco di bin/ (ls)"; }
sort "$w/bin.voci" > "$w/bin.txt"; op $? "ordinamento di bin/ (sort)"
cmp -s "$w/artefatti.txt" "$w/bin.txt" || err "bin/: artefatti diversi da quelli attesi: $(comm -3 "$w/artefatti.txt" "$w/bin.txt" | tr -d '\t' | tr '\n' ' ')"

# 3. Per ogni voce: una sola riga in compilazione.tsv, compilazione riuscita, argomenti di cobc esatti,
#    artefatto del tipo giusto.
for v in "$@"; do
  campi "$v"
  righe=""
  [ ! -f "$tsv" ] || righe="$(awk -F"$TAB" -v n="$n" 'NR>1 && $1==n' "$tsv")" \
    || { err "$n: lettura della riga di compilazione.tsv fallita (awk)"; righe=""; }
  # Numero di righe con l'esito di grep -c controllato (ammessi 0 e 1; issue #35).
  nr="$(printf '%s' "$righe" | grep -c '')"; r=$?
  [ "$r" -le 1 ] || nr="(conteggio fallito, grep codice $r)"
  if [ "$nr" != 1 ]; then err "$n: attesa una riga in compilazione.tsv, trovate $nr"; else
    echo "$righe" | awk -F"$TAB" -v o="$orig" -v t="$tipo" '$2==o && $3==t && $4==0 && $6==0 {ok=1} END {exit !ok}' \
      || err "$n: in compilazione.tsv origine, tipo, esito o errori non validi: $(echo "$righe" | tr "$TAB" ' ')"
  fi
  logf="$out/log/$n.log"
  if [ ! -f "$logf" ]; then err "$n: log di compilazione assente"; else
    if wn="$(conta ': warning: ' "$logf")" && en="$(conta ': error: ' "$logf")"; then
      echo "$righe" | awk -F"$TAB" -v w="$wn" -v e="$en" '$5==w && $6==e {ok=1} END {exit !ok}' \
        || err "$n: avvertimenti/errori in compilazione.tsv diversi da quelli nel log ($wn/$en)"
    else err "$n: conteggio di avvertimenti/errori nel log fallito (grep -c)"; fi
    ultima="$(tail -n 1 "$logf")" || ultima="(lettura del log fallita: tail)"
    [ "$ultima" = "codice di uscita: 0" ] || err "$n: l'ultima riga del log non e' 'codice di uscita: 0' ($ultima)"
    # Argomenti effettivi di ogni invocazione di cobc (registrati da compile.sh, uno per riga) contro
    # quelli attesi: le opzioni fissate e i soli argomenti strutturali del tipo, elencati qui.
    grep -E '^(== cobc$|arg )' "$logf" > "$w/argomenti.txt"
    r=$?; [ "$r" -le 1 ] || err "$n: lettura degli argomenti dal log fallita (grep, codice $r)"
    # Programma adattato: si compila la copia adattata, con la sua cartella come primo -I.
    csrc="$src"
    [ "$orig" != adattato ] || csrc="/out/adattati/${src##*/}"
    {
      echo "== cobc"
      [ "$orig" != adattato ] || echo "arg -I/out/adattati"
      for o in $opzioni; do echo "arg $o"; done
      case "$tipo" in
        modulo)     printf 'arg %s\n' -m -o "/out/bin/$n.so" "$csrc" ;;
        eseguibile) printf 'arg %s\n' -c -o "/out/obj/$n.o" "$csrc"
                    echo "== cobc"
                    printf 'arg %s\n' -x -A "-DMENB_ENTRY=$n" -o "/out/bin/$n" /oracle/launcher/avvia.c "/out/obj/$n.o" ;;
      esac
    } > "$w/attesi.txt" || err "$n: scrittura degli argomenti attesi fallita"
    if ! cmp -s "$w/attesi.txt" "$w/argomenti.txt"; then
      err "$n: argomenti di cobc diversi da quelli attesi:"
      diff "$w/attesi.txt" "$w/argomenti.txt" | sed 's/^/      /'
    fi
    # Codici delle invocazioni (issue #35: prima l'esito del primo grep si perdeva nella pipeline). Ci deve
    # essere una riga "== codice" per ogni invocazione attesa (1 per un modulo, 2 per un eseguibile): l'assenza
    # delle righe non e' "nessun codice diverso da 0" (rilievo 4, giro 1 della PR #49).
    case "$tipo" in modulo) ninv=1 ;; *) ninv=2 ;; esac
    grep -E '^== codice ' "$logf" > "$w/codici.txt"
    r=$?
    if [ "$r" -gt 1 ]; then err "$n: lettura dei codici di cobc dal log fallita (grep, codice $r)"
    else
      nc=0; while IFS= read -r _riga; do nc=$((nc + 1)); done < "$w/codici.txt"
      [ "$nc" = "$ninv" ] || err "$n: righe '== codice' nel log: $nc, attese $ninv (una per invocazione di cobc)"
      grep -vx '== codice 0' "$w/codici.txt" > /dev/null
      r=$?
      case "$r" in
        0) err "$n: un'invocazione di cobc non e' terminata con 0" ;;
        1) ;;
        *) err "$n: lettura dei codici di cobc fallita (grep -v, codice $r)" ;;
      esac
    fi
  fi
  if [ "$orig" = adattato ] && [ ! -f "$out/adattati/${src##*/}" ]; then
    err "$n: copia adattata assente (adattati/${src##*/})"
  fi
  case "$tipo" in
    eseguibile)
      a="$out/bin/$n"
      # Simboli letti una volta, con l'esito di nm controllato (issue #35: nella pipeline nm | awk un nm
      # fallito faceva passare il controllo "il modulo non contiene un main").
      if [ ! -f "$a" ] || [ ! -x "$a" ]; then err "$n: eseguibile assente o non eseguibile (bin/$n)"
      elif ! nm "$a" > "$w/nm.txt" 2>/dev/null; then err "$n: lettura dei simboli fallita (nm bin/$n)"
      else
        awk -v n="$n" '$2=="T" && $3==n {f=1} END {exit !f}' "$w/nm.txt" || err "$n: l'eseguibile non contiene il programma $n"
        awk '$2=="T" && $3=="main" {f=1} END {exit !f}' "$w/nm.txt" || err "$n: l'eseguibile non ha main (avviatore)"
      fi
      ;;
    modulo)
      a="$out/bin/$n.so"
      if [ ! -f "$a" ]; then err "$n: modulo assente (bin/$n.so)"
      elif ! nm -D --defined-only "$a" > "$w/nm-d.txt" 2>/dev/null; then err "$n: lettura dei simboli esportati fallita (nm -D bin/$n.so)"
      elif ! nm "$a" > "$w/nm.txt" 2>/dev/null; then err "$n: lettura dei simboli fallita (nm bin/$n.so)"
      else
        awk -v n="$n" '$2=="T" && $3==n {f=1} END {exit !f}' "$w/nm-d.txt" || err "$n: il modulo non esporta il programma $n"
        awk '$2=="T" && $3=="main" {f=1} END {exit f}' "$w/nm.txt" || err "$n: il modulo contiene un main"
      fi
      ;;
    *) err "$n: tipo sconosciuto nell'elenco fisso: $tipo" ;;
  esac
done

# 4. opzioni.txt: esattamente le opzioni fissate, una per riga, nell'ordine.
for o in $opzioni; do echo "$o"; done > "$w/opzioni-attese.txt"; op $? "scrittura delle opzioni attese"
cmp -s "$w/opzioni-attese.txt" "$out/opzioni.txt" 2>/dev/null \
  || err "opzioni: usate '$(tr '\n' ' ' < "$out/opzioni.txt" 2>/dev/null)', fissate '$opzioni'"

# 5. Ambiente: compilatore, gestore dei file indicizzati e pacchetti fissati nel Dockerfile (righe intere).
amb="$out/ambiente.txt"
for atteso in 'cobc (GnuCOBOL) 3.2.0' 'indexed file handler     : BDB' 'sequential file handler  : built-in' \
              'gnucobol3 3.2-3' 'libcob4t64 3.2-3' 'libcob4-dev 3.2-3' 'libdb5.3t64 5.3.28+dfsg2-9'; do
  grep -qxF -- "$atteso" "$amb" 2>/dev/null || err "ambiente: manca la riga '$atteso'"
done

# 6. Ambiente e configurazione effettivamente usati.
#    a) le variabili ricevute da cobc e dai programmi sono esattamente quelle fissate, nell'ordine;
for o in $amb_cobc; do echo "$o"; done > "$w/amb-cobc.txt"; op $? "scrittura dell'ambiente di cobc atteso"
cmp -s "$w/amb-cobc.txt" "$out/ambiente-cobc.txt" 2>/dev/null \
  || err "ambiente di cobc diverso da quello fissato: $(tr '\n' ' ' < "$out/ambiente-cobc.txt" 2>/dev/null)"
for o in $amb_run; do echo "$o"; done > "$w/amb-run.txt"; op $? "scrittura dell'ambiente dei programmi atteso"
cmp -s "$w/amb-run.txt" "$out/ambiente-run.txt" 2>/dev/null \
  || err "ambiente dei programmi diverso da quello fissato: $(tr '\n' ' ' < "$out/ambiente-run.txt" 2>/dev/null)"
#    b) cobc --info (letto nello stesso ambiente) riporta la cartella di configurazione e dei copybook
#       dell'immagine e nessuna variabile d'ambiente che li sostituisca (righe "env:");
ci="$out/cobc-info.txt"
ncd="$(conta '^COB_CONFIG_DIR ' "$ci" 2>/dev/null)" || { err "cobc --info: conteggio di COB_CONFIG_DIR fallito (grep -c)"; ncd=x; }
[ "$ncd" = 1 ] && grep -qx 'COB_CONFIG_DIR           : /usr/share/gnucobol/config' "$ci" \
  || err "cobc --info: COB_CONFIG_DIR diverso da /usr/share/gnucobol/config"
grep -qx 'COB_COPY_DIR             : /usr/share/gnucobol/copy' "$ci" 2>/dev/null || err "cobc --info: COB_COPY_DIR diverso da /usr/share/gnucobol/copy"
# Righe "env:" con l'esito di grep controllato (ammessi 0 e 1; issue #35: prima un grep fallito lasciava il
# file vuoto e il controllo passava).
grep -E '^[[:space:]]*env:' "$ci" > "$w/env-info.txt" 2>/dev/null
r=$?
if [ "$r" -gt 1 ]; then err "cobc --info: ricerca delle righe env: fallita (grep, codice $r)"
elif [ -s "$w/env-info.txt" ]; then err "cobc --info riporta variabili d'ambiente che ne cambiano la configurazione: $(tr -s ' ' < "$w/env-info.txt" | tr '\n' ';')"
fi
#    c) la cartella di configurazione usata e il contenuto di ogni suo file sono quelli fissati;
cmp -s "$ATTESI/configurazione.sha256" "$out/configurazione.sha256" 2>/dev/null || {
  err "configurazione del compilatore diversa da quella fissata:"
  diff "$ATTESI/configurazione.sha256" "$out/configurazione.sha256" 2>&1 | sed 's/^/      /'; }
#    d) la configurazione di runtime riportata da libcob (cobcrun --runtime-config) e' quella fissata.
cmp -s "$ATTESI/runtime-config.txt" "$out/runtime-config.txt" 2>/dev/null || {
  err "configurazione di runtime diversa da quella fissata:"
  diff "$ATTESI/runtime-config.txt" "$out/runtime-config.txt" 2>&1 | sed 's/^/      /'; }

if [ "$errs" -eq 0 ]; then
  nleg=0
  for v in "$@"; do case "$v" in legacy:*|adattato:*) nleg=$((nleg + 1)) ;; esac; done
  echo "verifica riuscita: $# programmi compilati con gli argomenti attesi ($nleg del legacy), opzioni e ambiente conformi"
  exit 0
fi
echo "verifica fallita: $errs difetti"
exit 1
