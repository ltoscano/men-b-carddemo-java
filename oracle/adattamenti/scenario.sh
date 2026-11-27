#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/adattamenti/run.sh. Ogni programma passa da
# oracle/esegui.sh (ambiente fissato, cartella di lavoro vuota, stdin vuoto, limite di tempo) e lascia il
# suo rapporto; il chiamante ne controlla il codice di uscita. Un fallimento dello strumento (esegui.sh
# che non riesce a lanciare o a registrare, o un limite di tempo scaduto) ferma lo script con codice 1.
#
#   scenario.sh carica SCENARIO OUT
#       per ognuno dei quattro file indicizzati: IDXLOAD lo carica dal file di testo di SCENARIO in
#       OUT/dati/<DD>.dat (rapporto in OUT/carico/<DD>/), poi IDXDUMP lo rilegge in ordine di chiave in
#       OUT/rilettura/<DD>.bin (rapporto in OUT/rilettura/<DD>/).
#   scenario.sh esegui OUT [DD-ASSENTE]
#       esegue CBSTM03A con le quattro DD d'ingresso su OUT/dati (rapporto in OUT/CBSTM03A.txt, ambiente
#       in OUT/CBSTM03A.ambiente). STMTFILE e HTMLFILE non hanno DD: il programma li crea nella propria
#       cartella di lavoro (OUT/lavoro-CBSTM03A/), da cui si copiano in OUT/. Con DD-ASSENTE quella DD
#       indica un file che non esiste (prova negativa 9).
set -u
die() { echo "scenario.sh: $*" >&2; exit 1; }
[ $# -ge 2 ] || die "uso: scenario.sh carica SCENARIO OUT | scenario.sh esegui OUT [DD-ASSENTE]"
case "$1" in
  carica)
    [ $# -eq 3 ] || die "uso: scenario.sh carica SCENARIO OUT"
    scen="$2"; out="$3"
    mkdir -p "$out/dati" "$out/carico" "$out/rilettura" || die "cartelle di lavoro non creabili in $out"
    for v in TRNXFILE:trnxfile.txt XREFFILE:xreffile.txt CUSTFILE:custfile.txt ACCTFILE:acctfile.txt; do
      dd="${v%%:*}"; f="${v#*:}"
      [ -f "$scen/$f" ] || die "file di testo assente: $scen/$f"
      mkdir -p "$out/carico/$dd" "$out/rilettura/$dd" || die "cartelle per $dd non creabili"
      sh /oracle/esegui.sh "$out/carico/$dd" IDXLOAD --parm "$dd" \
        --dd "DD_ENTRATA=$scen/$f" --dd "DD_$dd=$out/dati/$dd.dat" || die "esecuzione di IDXLOAD $dd fallita"
      sh /oracle/esegui.sh "$out/rilettura/$dd" IDXDUMP --parm "$dd" \
        --dd "DD_$dd=$out/dati/$dd.dat" --dd "DD_USCITA=$out/rilettura/$dd.bin" || die "esecuzione di IDXDUMP $dd fallita"
    done
    ;;
  esegui)
    out="$2"; assente="${3:-}"
    set --
    for dd in TRNXFILE XREFFILE CUSTFILE ACCTFILE; do
      p="$out/dati/$dd.dat"
      if [ "$dd" = "$assente" ]; then p="$out/dati/ASSENTE-$dd.dat"; [ ! -e "$p" ] || die "$p esiste"; fi
      set -- "$@" --dd "DD_$dd=$p"
    done
    sh /oracle/esegui.sh "$out" CBSTM03A "$@" || die "esecuzione di CBSTM03A fallita"
    for f in STMTFILE HTMLFILE; do
      if [ -f "$out/lavoro-CBSTM03A/$f" ]; then cp "$out/lavoro-CBSTM03A/$f" "$out/$f" || die "copia di $f fallita"; fi
    done
    ;;
  *) die "uso: scenario.sh carica SCENARIO OUT | scenario.sh esegui OUT [DD-ASSENTE]" ;;
esac
