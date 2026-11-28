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
# Programmi adattati (elenco fisso ADATTATI, oggi solo CBSTM03A; issue #25, oracle/adattamenti/registro.md):
# il sorgente compilato e' la copia di compilazione generata a ogni build da /oracle/adattamenti/adatta.sh
# in OUT/adattati/, e davanti alle opzioni c'e' un solo argomento strutturale in piu', -IOUT/adattati,
# perche' COPY CUSTREC trovi la copia adattata prima di /legacy/app/cpy (cobc cerca nelle cartelle -I
# nell'ordine in cui sono date):
#   adattato:   cobc -IOUT/adattati <opzioni> -c -o OUT/obj/<NOME>.o OUT/adattati/<sorgente>
#               cobc -x -A -DMENB_ENTRY=<NOME> -o OUT/bin/<NOME> /oracle/launcher/avvia.c OUT/obj/<NOME>.o
# Ogni invocazione di cobc passa da cobc_reg, che scrive nel log gli argomenti effettivi, uno per riga
# ("== cobc", poi "arg <argomento>"), e poi esegue esattamente quegli argomenti.
#
# Uso:
#   compile.sh tutto ELENCO.tsv OUT
#       compila tutto; scrive OUT/bin, OUT/log/<NOME>.log, OUT/compilazione.tsv, OUT/opzioni.txt, OUT/ambiente.txt
#       e l'ambiente effettivo: ambiente-cobc.txt, ambiente-run.txt (variabili ricevute), cobc-info.txt,
#       configurazione.sha256 (cartella di configurazione riportata da cobc e SHA-256 dei suoi file),
#       runtime-config.txt (configurazione di runtime riportata da libcob).
#       Esce con 1 se una compilazione fallisce o se fallisce un'acquisizione dell'ambiente.
#   compile.sh uno TIPO SORGENTE NOME OUT [opzione cobc in piu'] [opzione C in piu' per l'avviatore]
#                  [cartella dei copybook adattati, anteposta alle opzioni come -I<cartella>]
#       compila un solo programma (usato dalle prove negative dei controlli, mai dalla build). Solo in
#       questo modo UNO_OPZIONI puo' indicare un file di opzioni alterato al posto di /oracle/cobc.opts.
#
# Esiti (issue #35). Ogni comando il cui fallimento cambierebbe il risultato ha l'esito controllato; un
# errore operativo ferma lo script con un messaggio che nomina il comando. Esiti diversi da 0 ammessi:
# quello di cobc (registrato nel log e in compilazione.tsv, decide se la build fallisce) e l'esito 1 di
# `grep -c` e di `grep -v` (nessuna riga trovata: conteggio 0, elenco senza righe di commento).
# In modo `tutto` l'ambiente effettivo si acquisisce PRIMA di compilare: un'acquisizione fallita ferma la
# build, e build/run.sh, che scrive l'impronta solo dopo una build riuscita, non la scrive.
set -u
set -o pipefail

OPTFILE=/oracle/cobc.opts
if [ "${1:-}" = uno ] && [ -n "${UNO_OPZIONI:-}" ]; then OPTFILE="$UNO_OPZIONI"; fi
LAUNCHER=/oracle/launcher/avvia.c
# Tabulazione (separatore di programs.tsv): una costante, senza comandi.
TAB='	'
# Programmi di prova (oracle/tests/), tutti eseguibili.
PROVE="PARMECHO ABDUSING ABDNOARG M03BCALL DTCCALL SEGNOPRB PERFPRB DATFTPRB IDXLOAD IDXDUMP WAITPRB IDXLOADF"
# Programmi del legacy compilati da una copia adattata (oracle/adattamenti/registro.md).
ADATTATI="CBSTM03A"

die() { echo "compile.sh: $*" >&2; exit 1; }

# Opzioni dal file: righe senza commenti e senza spazi iniziali/finali; una sola parola per riga.
OPTS=""
while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" \
    || die "lettura delle opzioni di $OPTFILE fallita (sed)"
  [ -n "$line" ] || continue
  case "$line" in *[[:space:]]*) die "opzione con spazi in $OPTFILE: '$line'" ;; esac
  OPTS="$OPTS${OPTS:+ }$line"
done < "$OPTFILE" || die "lettura di $OPTFILE fallita"
[ -n "$OPTS" ] || die "nessuna opzione in $OPTFILE"

# Ambiente fissato (AMBIENTE_COBC, AMBIENTE_RUN): cobc parte sempre da `env -i` con quelle sole variabili.
. /oracle/ambiente.sh

# registra ARGOMENTI...: le righe "== cobc" e "arg <argomento>" (una per argomento) su stdout.
registra() {
  echo "== cobc" || return 1
  for a in "$@"; do printf 'arg %s\n' "$a" || return 1; done
}

# cobc_reg ARGOMENTI...: registra gli argomenti nel log ($logf) e li esegue tali e quali, nell'ambiente fissato.
# Ritorna il codice di cobc; una scrittura del log fallita ferma lo script.
cobc_reg() {
  registra "$@" >> "$logf" || die "scrittura del log $logf fallita"
  # shellcheck disable=SC2086
  env -i $AMBIENTE_COBC cobc "$@" >> "$logf" 2>&1
  r=$?
  echo "== codice $r" >> "$logf" || die "scrittura del log $logf fallita"
  return "$r"
}

# compila TIPO SORGENTE NOME OUT [cobc-extra] [c-extra] [cartella-adattati]; scrive OUT/log/NOME.log;
# ritorna il codice di cobc. Con cartella-adattati il primo argomento di cobc e' -I<cartella-adattati>.
compila() {
  tipo="$1"; src="$2"; nome="$3"; out="$4"; xcob="${5:-}"; xc="${6:-}"; xpre=""
  [ -z "${7:-}" ] || xpre="-I$7"
  mkdir -p "$out/bin" "$out/obj" "$out/log" || die "impossibile creare le cartelle di $out"
  logf="$out/log/$nome.log"
  : > "$logf" || die "impossibile creare $logf"
  case "$tipo" in
    modulo)
      # shellcheck disable=SC2086
      set -- $xpre $OPTS $xcob -m -o "$out/bin/$nome.so" "$src"
      cobc_reg "$@"; rc=$?
      ;;
    eseguibile)
      # shellcheck disable=SC2086
      set -- $xpre $OPTS $xcob -c -o "$out/obj/$nome.o" "$src"
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
  echo "codice di uscita: $rc" >> "$logf" || die "scrittura del log $logf fallita"
  return "$rc"
}

# conta MODELLO FILE: stampa quante righe del FILE contengono MODELLO. Esiti ammessi di `grep -c`: 0 (almeno
# una riga) e 1 (nessuna riga: conteggio 0, il caso normale); ogni altro esito ferma lo script.
# Si chiama come c="$(conta ...)" || exit 1: die dentro la sostituzione di comando esce solo da quella.
conta() {
  c="$(grep -c -- "$1" "$2")"
  r=$?
  [ "$r" -le 1 ] || die "conteggio di '$1' in $2 fallito (grep, codice $r)"
  case "$c" in ''|*[!0-9]*) die "conteggio di '$1' in $2 non numerico: '$c'" ;; esac
  echo "$c"
}

# riga TSV: nome origine tipo codice avvertimenti errori
riga() {
  w_n="$(conta ': warning: ' "$4/log/$1.log")" || exit 1
  e_n="$(conta ': error: ' "$4/log/$1.log")" || exit 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$5" "$w_n" "$e_n" >> "$4/compilazione.tsv" \
    || die "scrittura di $4/compilazione.tsv fallita"
}

# esito CODICE NOME: un'acquisizione dell'ambiente (o la scrittura di un suo risultato) e' riuscita solo con
# codice 0; altrimenti la build si ferma con un messaggio che nomina l'acquisizione.
esito() { [ "$1" -eq 0 ] || die "acquisizione fallita: $2 (codice $1)"; }

case "${1:-}" in
  tutto)
    [ $# -eq 3 ] || die "uso: compile.sh tutto ELENCO.tsv OUT"
    elenco="$2"; out="$3"
    [ -f "$elenco" ] || die "elenco assente: $elenco"
    mkdir -p "$out" || die "impossibile creare $out"
    # Cartella di lavoro nel container (non in OUT): file intermedi delle acquisizioni e dell'elenco.
    w="$(mktemp -d /tmp/compile.XXXXXX)" || die "impossibile creare la cartella di lavoro"

    # 1. Ambiente effettivo, sempre letto nello stesso ambiente fissato usato per compilare ed eseguire:
    #    versioni, gestore dei file indicizzati, configurazione di runtime. Ogni acquisizione ha un nome
    #    e un solo esito ammesso, 0.
    # shellcheck disable=SC2086
    env -i $AMBIENTE_COBC cobc --version > "$w/cobc-version.txt" 2>&1; esito $? "cobc --version"
    # shellcheck disable=SC2086
    env -i $AMBIENTE_COBC cobc --info > "$w/cobc-info.txt" 2>&1; esito $? "cobc --info (per ambiente.txt)"
    dpkg-query -W -f '${Package} ${Version}\n' gnucobol3 libcob4t64 libcob4-dev libdb5.3t64 gcc-14 libc6 libgmp10 libxml2 \
      > "$w/pacchetti.txt" 2>&1; esito $? "dpkg-query (pacchetti)"
    # shellcheck disable=SC2086
    env -i $AMBIENTE_RUN cobcrun --runtime-config > "$w/runtime-config.txt" 2>&1; esito $? "cobcrun --runtime-config (per ambiente.txt)"
    {
      echo "== cobc --version" && head -n 1 "$w/cobc-version.txt" \
        && echo "== cobc --info" && sed -n '/GnuCOBOL information/,$p' "$w/cobc-info.txt" \
        && echo "== pacchetti" && cat "$w/pacchetti.txt" \
        && echo "== cobcrun --runtime-config" && cat "$w/runtime-config.txt"
    } > "$out/ambiente.txt"; esito $? "composizione di ambiente.txt"
    # Le variabili che ricevono cobc e i programmi (una per riga, nell'ordine dell'elenco).
    # shellcheck disable=SC2086
    env -i $AMBIENTE_COBC env > "$out/ambiente-cobc.txt"; esito $? "env (ambiente di cobc)"
    # shellcheck disable=SC2086
    env -i $AMBIENTE_RUN env > "$out/ambiente-run.txt"; esito $? "env (ambiente dei programmi)"
    # Configurazione del compilatore come la riporta cobc stesso (cobc --info: COB_CONFIG_DIR, piu' una
    # riga "env:" per ogni variabile che la sostituisce) e contenuto della cartella effettivamente usata.
    # shellcheck disable=SC2086
    env -i $AMBIENTE_COBC cobc --info > "$out/cobc-info.txt" 2>&1; esito $? "cobc --info (per cobc-info.txt)"
    # Cartella usata: il percorso della riga "  env: COB_CONFIG_DIR    : <percorso>" se c'e', altrimenti
    # quello della riga "COB_CONFIG_DIR           : <percorso>". Il percorso e' cio' che segue il primo
    # ": " dopo il nome della variabile, senza spazi finali (prima si prendeva il secondo campo, che nella
    # riga "env:" e' il nome della variabile: rilievo 2 del giro 3 della PR #29).
    cfg="$(awk '
      /^  env: COB_CONFIG_DIR[[:space:]]*: / { e = $0; sub(/^  env: COB_CONFIG_DIR[[:space:]]*: /, "", e) }
      /^COB_CONFIG_DIR[[:space:]]*: /        { d = $0; sub(/^COB_CONFIG_DIR[[:space:]]*: /, "", d) }
      END { v = (e != "" ? e : d); sub(/[[:space:]]+$/, "", v); print v }' "$out/cobc-info.txt")"
    esito $? "estrazione della cartella di configurazione da cobc --info (awk)"
    [ -n "$cfg" ] || die "acquisizione fallita: cobc --info non riporta la cartella di configurazione"
    nomi="$(cd "$cfg" && LC_ALL=C ls -A)"; esito $? "elenco dei file di configurazione di $cfg (ls)"
    printf '%s\n' "$nomi" > "$w/configurazione.elenco"; esito $? "scrittura dell'elenco dei file di configurazione"
    echo "cartella $cfg" > "$out/configurazione.sha256"; esito $? "scrittura di configurazione.sha256"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      (cd "$cfg" && sha256sum "$f") >> "$out/configurazione.sha256"; esito $? "sha256sum di $f"
    done < "$w/configurazione.elenco" || exit 1
    # Configurazione di runtime come la riporta libcob (cobcrun --runtime-config) nell'ambiente dei programmi.
    # shellcheck disable=SC2086
    env -i $AMBIENTE_RUN cobcrun --runtime-config > "$out/runtime-config.txt" 2>&1; esito $? "cobcrun --runtime-config (per runtime-config.txt)"

    # 2. Compilazioni.
    printf 'programma\torigine\ttipo\tcodice_uscita\tavvertimenti\terrori\n' > "$out/compilazione.tsv" \
      || die "scrittura di $out/compilazione.tsv fallita"
    # shellcheck disable=SC2086
    printf '%s\n' $OPTS > "$out/opzioni.txt" || die "scrittura di $out/opzioni.txt fallita"
    for f in /oracle/stubs/*.cbl; do
      n="${f##*/}"; n="${n%.cbl}"
      compila modulo "$f" "$n" "$out"; rc=$?
      riga "$n" stub modulo "$out" "$rc"
    done
    # Copie di compilazione dei programmi adattati, rigenerate a ogni build in una cartella nuova
    # (adatta.sh rifiuta una cartella che esiste gia'). Se la generazione fallisce, la build fallisce.
    adatta_log="$out/log/adattamenti.txt"
    mkdir -p "$out/log" || die "impossibile creare $out/log"
    sh /oracle/adattamenti/adatta.sh /legacy "$out/adattati" > "$adatta_log" 2>&1 \
      || { cat "$adatta_log" >&2; die "generazione delle copie adattate fallita"; }
    # Programmi del legacy: righe non commento, intestazione esclusa. Esiti ammessi di `grep -v`: 0 e 1
    # (nessuna riga selezionata). L'elenco si legge da un file, non da una pipeline: il ciclo gira in
    # questa shell e un errore al suo interno ferma lo script.
    grep -v '^#' "$elenco" > "$w/elenco.tsv"
    r=$?; [ "$r" -le 1 ] || die "lettura dell'elenco $elenco fallita (grep, codice $r)"
    tail -n +2 "$w/elenco.tsv" > "$w/elenco-righe.tsv" || die "lettura dell'elenco $elenco fallita (tail)"
    # Separatore: la costante TAB, non una sostituzione di comando (giro 1 della PR #49: "$(printf '\t')"
    # fallito lasciava IFS vuoto, nessun programma del legacy compilato e la build verde).
    while IFS="$TAB" read -r n src tipo motivo; do
      [ -n "$n" ] || continue
      case " $ADATTATI " in
        *" $n "*)
          b="${src##*/}"
          compila "$tipo" "$out/adattati/$b" "$n" "$out" "" "" "$out/adattati"; rc=$?
          riga "$n" adattato "$tipo" "$out" "$rc" ;;
        *)
          compila "$tipo" "/legacy/$src" "$n" "$out"; rc=$?
          riga "$n" legacy "$tipo" "$out" "$rc" ;;
      esac
    done < "$w/elenco-righe.tsv" || exit 1
    for n in $PROVE; do
      compila eseguibile "/oracle/tests/$n.cbl" "$n" "$out"; rc=$?
      riga "$n" prova eseguibile "$out" "$rc"
    done
    rm -rf "$out/obj" || die "impossibile cancellare $out/obj"
    # Un programma che non compila fa fallire la build (le righe con codice diverso da 0).
    awk -F'\t' 'NR>1 && $4!=0 {print $1}' "$out/compilazione.tsv" > "$w/falliti.txt" \
      || die "lettura di $out/compilazione.tsv fallita (awk)"
    if [ -s "$w/falliti.txt" ]; then
      while IFS= read -r n; do echo "compile.sh: compilazione fallita: $n" >&2; done < "$w/falliti.txt"
      exit 1
    fi
    ;;
  uno)
    [ $# -ge 5 ] || die "uso: compile.sh uno TIPO SORGENTE NOME OUT [opzione cobc] [opzione C] [cartella adattati]"
    compila "$2" "$3" "$4" "$5" "${6:-}" "${7:-}" "${8:-}" || { cat "$5/log/$4.log" >&2; exit 1; }
    ;;
  *) die "uso: compile.sh tutto ELENCO.tsv OUT | compile.sh uno TIPO SORGENTE NOME OUT [opzione cobc] [opzione C] [cartella adattati]" ;;
esac
