#!/usr/bin/env bash
# Controllo della prova di avvio reale.
# 1. Riesegue la prova (oracle/avvio/run.sh) in una cartella nuova: nessun rapporto di una corsa
#    precedente viene usato.
# 2. Confronta, per ognuno dei lanci dell'elenco fisso qui sotto, il rapporto osservato (codice di
#    uscita, stdout, stderr, file creati) con quello atteso in oracle/avvio/expected/, scritto a mano
#    leggendo il sorgente (paragrafi di OPEN, 9910-DISPLAY-IO-STATUS, 9999-ABEND-PROGRAM).
# 3. Prove negative: alterazioni dei rapporti e degli attesi, e un'esecuzione reale senza moduli
#    (CEE3ABD e segnaposto non risolvibili); ognuna deve far fallire il confronto.
. "$ORACLE_ROOT/lib.sh"

# Elenco fisso: i 10 eseguibili del legacy (CBSTM03A compreso, issue #25) e i chiamanti di prova dei 2
# moduli (CBSTM03B, CSUTLDTC).
LANCI="CBACT01C CBACT02C CBACT03C CBACT04C CBCUS01C CBSTM03A CBTRN01C CBTRN02C CBTRN03C COBSWAIT M03BCALL DTCCALL"
EXP="$ORACLE_ROOT/avvio/expected"

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

# confronta OSSERVATI ATTESI: ritorna 0 solo se per ogni lancio dell'elenco i due rapporti esistono e
# coincidono riga per riga, e se tra gli attesi e gli osservati non c'e' nulla fuori elenco.
confronta() {
  local obs="$1" exp="$2" n f errs=0
  for n in $LANCI; do
    if [ ! -f "$exp/$n.txt" ]; then echo "$n: rapporto atteso assente ($n.txt)"; errs=$((errs + 1)); continue; fi
    if [ ! -f "$obs/$n.txt" ]; then echo "$n: rapporto osservato assente ($n.txt)"; errs=$((errs + 1)); continue; fi
    if ! diff -u "$exp/$n.txt" "$obs/$n.txt" > "$tmp/diff.txt"; then
      echo "$n: osservato diverso dall'atteso:"; indent "$tmp/diff.txt"; errs=$((errs + 1))
    fi
    # Ambiente ricevuto dal programma: esattamente quello fissato (oracle/ambiente.sh), uguale per tutti.
    if [ ! -f "$obs/$n.ambiente" ]; then echo "$n: ambiente non registrato ($n.ambiente)"; errs=$((errs + 1))
    elif ! diff -u "$exp/tutti.ambiente" "$obs/$n.ambiente" > "$tmp/diff.txt"; then
      echo "$n: ambiente diverso da quello fissato:"; indent "$tmp/diff.txt"; errs=$((errs + 1))
    fi
  done
  for f in "$exp"/*.txt "$obs"/*.txt; do
    [ -f "$f" ] || continue
    n="$(basename "$f" .txt)"
    case " $LANCI " in *" $n "*) ;; *) echo "$n: rapporto fuori elenco in $(rel "$(dirname "$f")")"; errs=$((errs + 1)) ;; esac
  done
  [ "$errs" -eq 0 ] || { echo "confronto fallito: $errs differenze"; return 1; }
  echo "confronto riuscito: $(echo $LANCI | wc -w | tr -d ' ') lanci coincidono con gli attesi"
}

log "1. prova di avvio rieseguita in una cartella nuova"
AVVIO_OUT_DIR="$tmp/obs" bash "$ORACLE_ROOT/avvio/run.sh" || fail "prova di avvio fallita"

log "2. confronto con gli attesi"
confronta "$tmp/obs" "$EXP" > "$tmp/c.out" 2>&1 || { cat "$tmp/c.out" >&2; fail "la prova di avvio non coincide con gli attesi"; }
sed 's/^/   /' "$tmp/c.out" >&2

log "3. prove negative"
neg() { # neg NOME: copia pulita degli osservati e degli attesi in $tmp/NOME/{obs,exp}
  rm -rf "$tmp/$1"; mkdir -p "$tmp/$1/obs" "$tmp/$1/exp"
  cp "$tmp/obs"/*.txt "$tmp/obs"/*.ambiente "$tmp/$1/obs/"; cp "$EXP"/*.txt "$EXP"/*.ambiente "$tmp/$1/exp/"
}
neg codice;    mutate "$tmp/codice/obs/CBACT04C.txt" '2s/^99$/0/'
expect_fail "codice di uscita di CBACT04C 99 -> 0" "CBACT04C: osservato diverso" confronta "$tmp/codice/obs" "$tmp/codice/exp"
neg messaggio; mutate "$tmp/messaggio/obs/CBTRN02C.txt" '/^ABENDING PROGRAM$/d'
expect_fail "riga 'ABENDING PROGRAM' tolta da CBTRN02C" "CBTRN02C: osservato diverso" confronta "$tmp/messaggio/obs" "$tmp/messaggio/exp"
neg stato;     mutate "$tmp/stato/obs/M03BCALL.txt" 's/^M03BCALL CUSTFILE O RC=35$/M03BCALL CUSTFILE O RC=00/'
expect_fail "ritorno di CBSTM03B per CUSTFILE 35 -> 00" "M03BCALL: osservato diverso" confronta "$tmp/stato/obs" "$tmp/stato/exp"
neg stm03a;    mutate "$tmp/stm03a/obs/CBSTM03A.txt" 's/^RETURN CODE: 35$/RETURN CODE: 00/'
expect_fail "CBSTM03A: stato dell'apertura di TRNXFILE 35 -> 00" "CBSTM03A: osservato diverso" confronta "$tmp/stm03a/obs" "$tmp/stm03a/exp"
neg file;      mutate "$tmp/file/obs/CBACT01C.txt" '$a\
ACCTFILE 0'
expect_fail "file creato nella cartella di lavoro di CBACT01C" "CBACT01C: osservato diverso" confronta "$tmp/file/obs" "$tmp/file/exp"
neg manca-oss; rm "$tmp/manca-oss/obs/DTCCALL.txt"
expect_fail "rapporto osservato di DTCCALL cancellato" "DTCCALL: rapporto osservato assente" confronta "$tmp/manca-oss/obs" "$tmp/manca-oss/exp"
neg manca-att; rm "$tmp/manca-att/exp/COBSWAIT.txt"
expect_fail "rapporto atteso di COBSWAIT cancellato" "COBSWAIT: rapporto atteso assente" confronta "$tmp/manca-att/obs" "$tmp/manca-att/exp"
neg fuori;     cp "$tmp/fuori/obs/CBACT01C.txt" "$tmp/fuori/obs/CBACT05C.txt"
expect_fail "rapporto di un programma fuori elenco" "CBACT05C: rapporto fuori elenco" confronta "$tmp/fuori/obs" "$tmp/fuori/exp"
# Esecuzione reale alterata: eseguibili senza moduli accanto (CEE3ABD, segnaposto, CBSTM03B, CSUTLDTC).
AVVIO_SENZA_STUB=1 AVVIO_OUT_DIR="$tmp/senza-stub" bash "$ORACLE_ROOT/avvio/run.sh" > "$tmp/senza-stub.log" 2>&1 \
  || { cat "$tmp/senza-stub.log" >&2; fail "esecuzione senza moduli non completata"; }
expect_fail "esecuzione reale senza i moduli (CEE3ABD non risolvibile)" "CBACT01C: osservato diverso" confronta "$tmp/senza-stub" "$EXP"
neg manca-amb; rm "$tmp/manca-amb/obs/CBTRN01C.ambiente"
expect_fail "ambiente di CBTRN01C non registrato" "CBTRN01C: ambiente non registrato" confronta "$tmp/manca-amb/obs" "$tmp/manca-amb/exp"
# Esecuzione reale con una variabile di runtime alterata: copia di esegui.sh che aggiunge
# COB_VARSEQ_FORMAT=1 all'ambiente fissato dei programmi.
cp "$ORACLE_ROOT/esegui.sh" "$tmp/esegui-alterato.sh"
mutate "$tmp/esegui-alterato.sh" 's#^\. /oracle/ambiente\.sh$#. /oracle/ambiente.sh; AMBIENTE_RUN="$AMBIENTE_RUN COB_VARSEQ_FORMAT=1"#'
AVVIO_ESEGUI="$tmp/esegui-alterato.sh" AVVIO_OUT_DIR="$tmp/runtime-alterato" bash "$ORACLE_ROOT/avvio/run.sh" > "$tmp/runtime-alterato.log" 2>&1 \
  || { cat "$tmp/runtime-alterato.log" >&2; fail "esecuzione con il runtime alterato non completata"; }
grep -qx 'COB_VARSEQ_FORMAT=1' "$tmp/runtime-alterato/CBACT01C.ambiente" || fail "la variabile alterata non e' arrivata al programma"
expect_fail "esecuzione reale con COB_VARSEQ_FORMAT=1 nell'ambiente dei programmi" "CBACT01C: ambiente diverso da quello fissato" confronta "$tmp/runtime-alterato" "$EXP"
# Controprova: la stessa variabile soltanto esportata dallo script (ambiente ereditato) non arriva ai
# programmi, perche' partono da env -i: il confronto deve riuscire.
cp "$ORACLE_ROOT/esegui.sh" "$tmp/esegui-export.sh"
mutate "$tmp/esegui-export.sh" 's#^\. /oracle/ambiente\.sh$#. /oracle/ambiente.sh; export COB_VARSEQ_FORMAT=1 COB_RUNTIME_CONFIG=/nonesiste#'
AVVIO_ESEGUI="$tmp/esegui-export.sh" AVVIO_OUT_DIR="$tmp/runtime-export" bash "$ORACLE_ROOT/avvio/run.sh" > "$tmp/runtime-export.log" 2>&1 \
  || { cat "$tmp/runtime-export.log" >&2; fail "esecuzione con le variabili esportate non completata"; }
confronta "$tmp/runtime-export" "$EXP" > "$tmp/runtime-export.out" 2>&1 \
  || { indent "$tmp/runtime-export.out" >&2; fail "variabili esportate dallo script sono arrivate ai programmi"; }
log "   controprova ok: COB_VARSEQ_FORMAT e COB_RUNTIME_CONFIG esportati dallo script non arrivano ai programmi"
# Artefatti di una build assente, incompleta o non aggiornata: la prova si rifiuta di usarli.
cp -R "$BUILD_OUT" "$tmp/build-senza-impronta"; rm "$tmp/build-senza-impronta/IMPRONTA"
expect_fail "build senza impronta (interrotta o fallita)" "build assente o incompleta" \
  env ORACLE_BUILD_OUT="$tmp/build-senza-impronta" AVVIO_OUT_DIR="$tmp/x1" bash "$ORACLE_ROOT/avvio/run.sh"
cp -R "$BUILD_OUT" "$tmp/build-vecchia"; mutate "$tmp/build-vecchia/IMPRONTA" 's/^./x/'
expect_fail "build con impronta di input diversi (vecchia)" "build non aggiornata" \
  env ORACLE_BUILD_OUT="$tmp/build-vecchia" AVVIO_OUT_DIR="$tmp/x2" bash "$ORACLE_ROOT/avvio/run.sh"
cp -R "$BUILD_OUT" "$tmp/build-alterata"; cp "$tmp/build-alterata/bin/CBACT02C" "$tmp/build-alterata/bin/CBACT01C"
expect_fail "eseguibile CBACT01C sostituito dopo la build" "artefatti della build cambiati" \
  env ORACLE_BUILD_OUT="$tmp/build-alterata" AVVIO_OUT_DIR="$tmp/x3" bash "$ORACLE_ROOT/avvio/run.sh"
log "controllo superato"
