#!/usr/bin/env bash
# Controllo della build dell'oracle.
# 1. Rifa' la build (oracle/build/run.sh): l'output viene cancellato e rigenerato, quindi nessun
#    artefatto di una corsa precedente puo' passare per attuale.
# 2. Verifica (oracle/build/verifica.sh, nel container) contro gli ELENCHI FISSI qui sotto, con confronti
#    esatti: i 12 programmi nell'elenco della build con tipo e sorgente; per ognuno dei 26 programmi
#    compilati (12 + stub e segnaposto + prove) una sola riga in compilazione.tsv, esito 0, nessun errore,
#    ARGOMENTI DI OGNI INVOCAZIONE DI cobc IDENTICI a quelli attesi (opzioni fissate piu' i soli argomenti
#    strutturali del tipo; per CBSTM03A, adattato, anche -I/out/adattati in testa e la copia adattata come
#    sorgente), artefatto del tipo giusto; in bin/ nient'altro; opzioni.txt identico;
#    compilatore, gestore dei file indicizzati e pacchetti come fissati nel Dockerfile; impronta valida.
# 3. Le opzioni di cobc.opts sono esattamente quelle fissate qui sotto (cambiarle richiede di cambiare
#    anche il controllo).
# 4. I passi dei criteri di accettazione esistono, con i loro script e dipendenze.
# 5. Prove negative per ognuna delle verifiche, tra cui ricompilazioni reali: un programma tolto
#    dall'elenco, un'opzione in piu' che annulla un'opzione obbligatoria, una build interrotta.
. "$ORACLE_ROOT/lib.sh"

# Elenco fisso: i programmi del legacy che `cobc -fsyntax-only -std=ibm` accetta (analysis/tools/out/gnucobol),
# con il tipo letto nel sorgente (motivi in oracle/programs.tsv) e il sorgente nel volume del legacy.
FISSO="legacy:CBACT01C:eseguibile:/legacy/app/cbl/CBACT01C.cbl legacy:CBACT02C:eseguibile:/legacy/app/cbl/CBACT02C.cbl
legacy:CBACT03C:eseguibile:/legacy/app/cbl/CBACT03C.cbl legacy:CBACT04C:eseguibile:/legacy/app/cbl/CBACT04C.cbl
legacy:CBCUS01C:eseguibile:/legacy/app/cbl/CBCUS01C.cbl legacy:CBSTM03B:modulo:/legacy/app/cbl/CBSTM03B.CBL
legacy:CBTRN01C:eseguibile:/legacy/app/cbl/CBTRN01C.cbl legacy:CBTRN02C:eseguibile:/legacy/app/cbl/CBTRN02C.cbl
legacy:CBTRN03C:eseguibile:/legacy/app/cbl/CBTRN03C.cbl legacy:COBSWAIT:eseguibile:/legacy/app/cbl/COBSWAIT.cbl
legacy:CSUTLDTC:modulo:/legacy/app/cbl/CSUTLDTC.cbl
adattato:CBSTM03A:eseguibile:/legacy/app/cbl/CBSTM03A.CBL"
# CBSTM03A (issue #25) non compila cosi' com'e': si compila la copia adattata (oracle/adattamenti/registro.md),
# con -I/out/adattati come primo argomento di cobc. Gli altri 11 non devono avere quell'argomento.
[ "$(echo $FISSO | wc -w | tr -d ' ')" -eq 12 ] || fail "l'elenco fisso del controllo non ha 12 voci"
# Stub, segnaposto e programmi di prova: compilati con le stesse opzioni, verificati allo stesso modo.
ACCESSORI="stub:CEE3ABD:modulo:/oracle/stubs/CEE3ABD.cbl stub:CEEDAYS:modulo:/oracle/stubs/CEEDAYS.cbl
stub:COBDATFT:modulo:/oracle/stubs/COBDATFT.cbl stub:MVSWAIT:modulo:/oracle/stubs/MVSWAIT.cbl
prova:PARMECHO:eseguibile:/oracle/tests/PARMECHO.cbl prova:ABDUSING:eseguibile:/oracle/tests/ABDUSING.cbl
prova:ABDNOARG:eseguibile:/oracle/tests/ABDNOARG.cbl prova:M03BCALL:eseguibile:/oracle/tests/M03BCALL.cbl
prova:DTCCALL:eseguibile:/oracle/tests/DTCCALL.cbl prova:SEGNOPRB:eseguibile:/oracle/tests/SEGNOPRB.cbl
prova:PERFPRB:eseguibile:/oracle/tests/PERFPRB.cbl prova:DATFTPRB:eseguibile:/oracle/tests/DATFTPRB.cbl
prova:IDXLOAD:eseguibile:/oracle/tests/IDXLOAD.cbl prova:IDXDUMP:eseguibile:/oracle/tests/IDXDUMP.cbl"
# Ambiente fissato (deve coincidere con oracle/ambiente.sh): variabili ricevute da cobc e dai programmi.
AMB_COBC_FISSO="PATH=/usr/bin:/bin HOME=/tmp LC_ALL=C"
AMB_RUN_FISSO="PATH=/usr/bin:/bin HOME=/tmp LC_ALL=C COB_LIBRARY_PATH=/oracle-bin"
# Opzioni fissate, nell'ordine (motivi in oracle/cobc.opts e oracle/README.md).
OPZIONI_FISSE="-std=ibm -fbinary-truncate -fsingle-quote -fsign=EBCDIC -Wall -I/legacy/app/cpy"
# Passi dei criteri di accettazione: nome e dipendenza (- = nessuna). selftest ha solo check.sh.
PASSI="build:- avvio:build avviatore:build abend:build segno:build dialetto:build routines:build adattamenti:build selftest:-"

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

# verifica ELENCO OUT: verifica nel container + impronta (sull'host, con git).
verifica() {
  local elenco="$1" out="$2" rc=0 p
  # shellcheck disable=SC2086
  orun -- timeout 300 sh /oracle/build/verifica.sh "$(in_container "$elenco")" "$(in_container "$out")" \
    "$OPZIONI_FISSE" "$AMB_COBC_FISSO" "$AMB_RUN_FISSO" $FISSO $ACCESSORI || rc=1
  if p="$(stamp_problem "$out")"; then echo "impronta valida: input e artefatti attuali"
  else echo "DIFETTO: impronta: $p"; rc=1; fi
  return "$rc"
}

# opzioni_fisse FILE: le righe non commento del file, una parola ciascuna, sono esattamente OPZIONI_FISSE.
opzioni_fisse() {
  local got bad
  bad="$(sed -e 's/#.*$//' "$1" | awk 'NF > 1')"
  [ -z "$bad" ] || { echo "opzioni in $(rel "$1"): riga con piu' di una parola: '$bad'"; return 1; }
  got="$(sed -e 's/#.*$//' "$1" | awk 'NF {print $1}' | tr '\n' ' ' | sed 's/ $//')"
  [ "$got" = "$OPZIONI_FISSE" ] || { echo "opzioni in $(rel "$1"): '$got', fissate nel controllo: '$OPZIONI_FISSE'"; return 1; }
  echo "opzioni conformi: $got"
}

# passi_presenti RADICE: ogni passo dell'elenco ha check.sh, quelli con dipendenza hanno run.sh e deps giusto.
passi_presenti() {
  local root="$1" v n d errs=0
  for v in $PASSI; do
    n="${v%%:*}"; d="${v#*:}"
    [ -f "$root/$n/check.sh" ] || { echo "passo $n: manca check.sh"; errs=$((errs + 1)); }
    if [ "$d" != - ]; then
      [ -f "$root/$n/run.sh" ] || { echo "passo $n: manca run.sh"; errs=$((errs + 1)); }
      grep -qx "$d" "$root/$n/deps" 2>/dev/null || { echo "passo $n: deps non contiene $d"; errs=$((errs + 1)); }
    fi
  done
  [ "$errs" -eq 0 ] || return 1
  echo "passi presenti: $PASSI"
}

log "1. build rifatta da zero"
bash "$ORACLE_ROOT/build/run.sh" || fail "build fallita"

log "2. verifica contro gli elenchi fissi"
verifica "$ORACLE_ROOT/programs.tsv" "$BUILD_OUT" > "$tmp/v.out" 2>&1 || { indent "$tmp/v.out" >&2; fail "la build non supera la verifica"; }
indent "$tmp/v.out" >&2

log "3. opzioni fissate"
opzioni_fisse "$ORACLE_ROOT/cobc.opts" > "$tmp/o.out" 2>&1 || { indent "$tmp/o.out" >&2; fail "cobc.opts diverso dalle opzioni fissate"; }
indent "$tmp/o.out" >&2

log "4. passi dei criteri di accettazione"
passi_presenti "$ORACLE_ROOT" > "$tmp/p.out" 2>&1 || { indent "$tmp/p.out" >&2; fail "mancano passi dell'oracle"; }
indent "$tmp/p.out" >&2

log "5. prove negative"
copia() { rm -rf "$tmp/$1"; cp -R "$BUILD_OUT" "$tmp/$1" && cp "$ORACLE_ROOT/programs.tsv" "$tmp/$1.tsv"; }
# ricompila COPIA TIPO SORGENTE NOME OPZIONE-IN-PIU': ricompilazione reale di un programma dentro una copia
# della build, con un argomento di cobc in piu' (compile.sh lo passa davvero a cobc e lo registra).
ricompila() {
  orun -v "$tmp/$1:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh /oracle/build/compile.sh uno "$2" "$3" "$4" /out "$5" > "$tmp/$1.log" 2>&1 \
    || { indent "$tmp/$1.log" >&2; fail "ricompilazione '$1' fallita"; }
}

# Un'opzione in piu' che annulla un'opzione obbligatoria, in coda agli argomenti reali di cobc.
copia trunc; ricompila trunc eseguibile /legacy/app/cbl/CBACT04C.cbl CBACT04C -fno-binary-truncate
expect_fail "CBACT04C ricompilato con -fno-binary-truncate in coda (annulla -fbinary-truncate)" \
  "CBACT04C: argomenti di cobc diversi" verifica "$tmp/trunc.tsv" "$tmp/trunc"
grep -qx 'arg -fno-binary-truncate' "$tmp/trunc/log/CBACT04C.log" || fail "la ricompilazione 'trunc' non ha usato l'opzione in piu'"
copia sign; ricompila sign modulo /legacy/app/cbl/CSUTLDTC.cbl CSUTLDTC -fsign=ASCII
expect_fail "CSUTLDTC ricompilato con -fsign=ASCII in coda (annulla -fsign=EBCDIC)" \
  "CSUTLDTC: argomenti di cobc diversi" verifica "$tmp/sign.tsv" "$tmp/sign"

# Un programma tolto dall'elenco della build: si ricompila davvero con l'elenco alterato.
cp "$ORACLE_ROOT/programs.tsv" "$tmp/senza.tsv"
mutate "$tmp/senza.tsv" '/^CBTRN03C	/d'
ORACLE_BUILD_OUT="$tmp/senza" BUILD_ELENCO="$tmp/senza.tsv" bash "$ORACLE_ROOT/build/run.sh" > "$tmp/senza.log" 2>&1 \
  || { indent "$tmp/senza.log" >&2; fail "ricompilazione con l'elenco alterato fallita"; }
expect_fail "CBTRN03C tolto dall'elenco della build (ricompilato)" "CBTRN03C:eseguibile:app/cbl/CBTRN03C.cbl manca nell'elenco della build" verifica "$tmp/senza.tsv" "$tmp/senza"
expect_fail "CBTRN03C tolto dall'elenco della build: artefatto assente" "CBTRN03C: eseguibile assente" verifica "$tmp/senza.tsv" "$tmp/senza"
expect_fail "build con elenco sostituito: senza impronta" "DIFETTO: impronta: build assente o incompleta" verifica "$tmp/senza.tsv" "$tmp/senza"

# Una compilazione che fallisce fa fallire la build.
cp "$ORACLE_ROOT/programs.tsv" "$tmp/rotto.tsv"
mutate "$tmp/rotto.tsv" 's#^\(CBACT02C	\)app/cbl/CBACT02C\.cbl	#\1app/cbl/NONESISTE.cbl	#'
expect_fail "sorgente di CBACT02C inesistente: la build fallisce" "compilazione fallita" \
  env ORACLE_BUILD_OUT="$tmp/rotto" BUILD_ELENCO="$tmp/rotto.tsv" bash "$ORACLE_ROOT/build/run.sh"
# Una build interrotta (qui dal limite di tempo, 1 secondo) fallisce e non lascia l'impronta, quindi i
# passi successivi rifiutano i suoi artefatti parziali.
expect_fail "build interrotta dal limite di tempo di 1 s" "compilazione fallita" \
  env ORACLE_BUILD_OUT="$tmp/lenta" ORACLE_TIMEOUT_COMPILE=1 bash "$ORACLE_ROOT/build/run.sh"
[ ! -e "$tmp/lenta/IMPRONTA" ] || fail "una build interrotta ha lasciato l'impronta"
log "   e la build interrotta non ha lasciato l'impronta"

copia src; mutate "$tmp/src.tsv" 's#^\(CBACT01C	\)app/cbl/CBACT01C\.cbl	#\1app/cbl/CBACT02C.cbl	#'
expect_fail "sorgente di CBACT01C sostituito nell'elenco della build" "CBACT01C:eseguibile:app/cbl/CBACT01C.cbl manca" verifica "$tmp/src.tsv" "$tmp/src"
copia art; rm "$tmp/art/bin/CBACT04C"
expect_fail "eseguibile CBACT04C cancellato" "CBACT04C: eseguibile assente" verifica "$tmp/art.tsv" "$tmp/art"
copia mod; rm "$tmp/mod/bin/CBSTM03B.so"
expect_fail "modulo CBSTM03B cancellato" "CBSTM03B: modulo assente" verifica "$tmp/mod.tsv" "$tmp/mod"
copia extra; cp "$tmp/extra/bin/CBACT01C" "$tmp/extra/bin/CBACT05C"
expect_fail "artefatto in piu' in bin/" "bin/: artefatti diversi da quelli attesi: CBACT05C" verifica "$tmp/extra.tsv" "$tmp/extra"
copia tipo; mutate "$tmp/tipo.tsv" 's/^\(CSUTLDTC	[^	]*	\)modulo	/\1eseguibile	/'
expect_fail "CSUTLDTC dichiarato eseguibile nell'elenco della build" "CSUTLDTC:modulo:app/cbl/CSUTLDTC.cbl manca" verifica "$tmp/tipo.tsv" "$tmp/tipo"
copia scambio; mv "$tmp/scambio/bin/CSUTLDTC.so" "$tmp/scambio/bin/CSUTLDTC"
expect_fail "modulo CSUTLDTC sostituito da un file con nome di eseguibile" "CSUTLDTC: modulo assente" verifica "$tmp/scambio.tsv" "$tmp/scambio"
copia sost; cp "$tmp/sost/bin/CBACT02C" "$tmp/sost/bin/CBACT03C"
expect_fail "eseguibile CBACT03C sostituito da CBACT02C" "CBACT03C: l'eseguibile non contiene il programma CBACT03C" verifica "$tmp/sost.tsv" "$tmp/sost"
expect_fail "eseguibile sostituito dopo la build: impronta" "artefatti della build cambiati" verifica "$tmp/sost.tsv" "$tmp/sost"
copia errori; mutate "$tmp/errori/compilazione.tsv" 's/^\(CBTRN02C	legacy	eseguibile	0	1	\)0$/\13/'
expect_fail "errori di CBTRN02C in compilazione.tsv 0 -> 3" "CBTRN02C: in compilazione.tsv origine, tipo, esito o errori non validi" verifica "$tmp/errori.tsv" "$tmp/errori"
copia avv; mutate "$tmp/avv/compilazione.tsv" 's/^\(CBTRN03C	legacy	eseguibile	0	\)1	/\10	/'
expect_fail "avvertimenti di CBTRN03C in compilazione.tsv 1 -> 0 (il log ne ha 1)" "CBTRN03C: avvertimenti/errori in compilazione.tsv diversi" verifica "$tmp/avv.tsv" "$tmp/avv"
copia doppia; mutate "$tmp/doppia/compilazione.tsv" '/^CBCUS01C	/p'
expect_fail "riga di CBCUS01C duplicata in compilazione.tsv" "CBCUS01C: attesa una riga in compilazione.tsv, trovate 2" verifica "$tmp/doppia.tsv" "$tmp/doppia"
copia opz; mutate "$tmp/opz/opzioni.txt" '/^-fbinary-truncate$/d'
expect_fail "opzione -fbinary-truncate tolta da quelle registrate" "opzioni: usate" verifica "$tmp/opz.tsv" "$tmp/opz"
copia cmd; mutate "$tmp/cmd/log/CBACT02C.log" '/^arg -fsign=EBCDIC$/d'
expect_fail "log di CBACT02C senza -fsign=EBCDIC" "CBACT02C: argomenti di cobc diversi" verifica "$tmp/cmd.tsv" "$tmp/cmd"
copia isam; mutate "$tmp/isam/ambiente.txt" 's/^indexed file handler     : BDB$/indexed file handler     : VBISAM/'
expect_fail "gestore dei file indicizzati diverso da BDB" "ambiente: manca la riga 'indexed file handler     : BDB'" verifica "$tmp/isam.tsv" "$tmp/isam"
copia impr; mutate "$tmp/impr/IMPRONTA" '1s/^input ./input x/'
expect_fail "impronta degli input alterata" "build non aggiornata" verifica "$tmp/impr.tsv" "$tmp/impr"

# Programma adattato (CBSTM03A, issue #25): la copia adattata e la sua cartella -I sono solo sue.
copia noada; mutate "$tmp/noada/log/CBSTM03A.log" '/^arg -I\/out\/adattati$/d'
expect_fail "CBSTM03A registrato senza -I/out/adattati" "CBSTM03A: argomenti di cobc diversi" verifica "$tmp/noada.tsv" "$tmp/noada"
copia orig; mutate "$tmp/orig/log/CBSTM03A.log" 's#^arg /out/adattati/CBSTM03A\.CBL$#arg /legacy/app/cbl/CBSTM03A.CBL#'
expect_fail "CBSTM03A registrato come compilato dall'originale" "CBSTM03A: argomenti di cobc diversi" verifica "$tmp/orig.tsv" "$tmp/orig"
# Un altro programma ricompilato davvero con la cartella delle copie adattate (in coda agli argomenti).
copia altroada; ricompila altroada eseguibile /legacy/app/cbl/CBCUS01C.cbl CBCUS01C -I/out/adattati
grep -qx 'arg -I/out/adattati' "$tmp/altroada/log/CBCUS01C.log" || fail "la ricompilazione 'altroada' non ha usato la cartella delle copie adattate"
expect_fail "CBCUS01C ricompilato con -I/out/adattati" "CBCUS01C: argomenti di cobc diversi" verifica "$tmp/altroada.tsv" "$tmp/altroada"
copia senzacopia; rm "$tmp/senzacopia/adattati/CBSTM03A.CBL"
expect_fail "copia adattata di CBSTM03A cancellata dopo la build" "CBSTM03A: copia adattata assente" verifica "$tmp/senzacopia.tsv" "$tmp/senzacopia"
expect_fail "copia adattata di CBSTM03A cancellata: impronta" "artefatti della build cambiati" verifica "$tmp/senzacopia.tsv" "$tmp/senzacopia"
copia copiamod; mutate "$tmp/copiamod/adattati/CUSTREC.cpy" '6s/CUST-FIRST-NAME/CUST-FIRST-NAMX/'
expect_fail "copia adattata di CUSTREC alterata dopo la build: impronta" "artefatti della build cambiati" verifica "$tmp/copiamod.tsv" "$tmp/copiamod"
# Un file illeggibile fa fallire l'impronta (rilievo 3, giro 1 della PR #44): un artefatto di bin/, una copia
# adattata, un input della build. build_stamp e' la chiamata con cui build/run.sh scrive IMPRONTA (se fallisce
# la build fallisce); stamp_problem e' quella con cui i passi e questo controllo verificano l'impronta.
illeggibile() { # illeggibile FILE: toglie ogni permesso e verifica che il file non sia piu' leggibile
  chmod 000 "$1" || fail "chmod 000 su $(rel "$1") fallito"
  [ ! -r "$1" ] || fail "$(rel "$1") resta leggibile dopo chmod 000 (utente root?): prova dell'impronta non eseguibile"
}
copia ill1; illeggibile "$tmp/ill1/adattati/CUSTREC.cpy"
expect_fail "copia adattata illeggibile: build_stamp (scrittura di IMPRONTA) fallisce" "Permission denied" build_stamp "$tmp/ill1"
expect_fail "copia adattata illeggibile: verifica dell'impronta" "DIFETTO: impronta: calcolo dell'impronta fallito" verifica "$tmp/ill1.tsv" "$tmp/ill1"
copia ill2; illeggibile "$tmp/ill2/bin/CBACT01C"
expect_fail "artefatto di bin/ illeggibile: build_stamp fallisce" "Permission denied" build_stamp "$tmp/ill2"
expect_fail "artefatto di bin/ illeggibile: require_build dei passi lo rifiuta" "calcolo dell'impronta fallito" \
  env ORACLE_BUILD_OUT="$tmp/ill2" bash -c '. "$ORACLE_ROOT/lib.sh"; require_build'
cp "$ORACLE_ROOT/adattamenti/adatta.sh" "$tmp/ill3.sh"; illeggibile "$tmp/ill3.sh"
expect_fail "input della build illeggibile: l'impronta degli input fallisce" "Permission denied" \
  env INGRESSO_ILLEGGIBILE="$tmp/ill3.sh" bash -c '. "$ORACLE_ROOT/lib.sh"; build_inputs() { printf "%s\n" "$INGRESSO_ILLEGGIBILE"; }; fingerprint'
chmod 644 "$tmp/ill1/adattati/CUSTREC.cpy" "$tmp/ill2/bin/CBACT01C" "$tmp/ill3.sh"
# Se la generazione delle copie adattate fallisce, la build fallisce (compile.sh alterato: legacy inesistente).
cp "$ORACLE_ROOT/build/compile.sh" "$tmp/adafail.compile.sh"
mutate "$tmp/adafail.compile.sh" 's#sh /oracle/adattamenti/adatta\.sh /legacy #sh /oracle/adattamenti/adatta.sh /nonesiste #'
mkdir -p "$tmp/adafail"
expect_fail "generazione delle copie adattate fallita: la build fallisce" "generazione delle copie adattate fallita" \
  orun -v "$tmp/adafail:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh "$(in_container "$tmp/adafail.compile.sh")" tutto /oracle/programs.tsv /out

# Ambiente e configurazione del compilatore e del runtime.
# verifica_container ELENCO OUT: la sola verifica nel container (senza impronta).
verifica_container() {
  # shellcheck disable=SC2086
  orun -- timeout 300 sh /oracle/build/verifica.sh "$(in_container "$1")" "$(in_container "$2")" \
    "$OPZIONI_FISSE" "$AMB_COBC_FISSO" "$AMB_RUN_FISSO" $FISSO $ACCESSORI
}
# build_alterata NOME ESPRESSIONE-SED: build completa reale con una copia alterata di compile.sh.
build_alterata() {
  cp "$ORACLE_ROOT/build/compile.sh" "$tmp/$1.compile.sh"
  mutate "$tmp/$1.compile.sh" "$2"
  mkdir -p "$tmp/$1"
  orun -v "$tmp/$1:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh "$(in_container "$tmp/$1.compile.sh")" tutto /oracle/programs.tsv /out > "$tmp/$1.log" 2>&1 \
    || { indent "$tmp/$1.log" >&2; fail "build alterata '$1' fallita"; }
}
config_alternativa "$tmp/alt"
alt="$(in_container "$tmp/alt")"
# a) configurazione alternativa (perform-osvs: no) che arriva davvero a cobc.
build_alterata cfg "s#^\. /oracle/ambiente\.sh\$#. /oracle/ambiente.sh; AMBIENTE_COBC=\"\$AMBIENTE_COBC COB_CONFIG_DIR=$alt\"#"
expect_fail "build con COB_CONFIG_DIR alternativo nell'ambiente di cobc: ambiente" "ambiente di cobc diverso" verifica_container "$ORACLE_ROOT/programs.tsv" "$tmp/cfg"
expect_fail "build con COB_CONFIG_DIR alternativo: cobc --info lo riporta" "cobc --info riporta variabili d'ambiente" verifica_container "$ORACLE_ROOT/programs.tsv" "$tmp/cfg"
expect_fail "build con COB_CONFIG_DIR alternativo: file di configurazione diversi" "configurazione del compilatore diversa" verifica_container "$ORACLE_ROOT/programs.tsv" "$tmp/cfg"
# b) controprova: la mutazione del Validatore (giro 2, PR #29), la stessa configurazione solo esportata
#    nello script di compilazione, non arriva a cobc: la verifica riesce.
build_alterata export "s#^\. /oracle/ambiente\.sh\$#. /oracle/ambiente.sh; export COB_CONFIG_DIR=$alt COBCPY=/tmp COB_CFLAGS=-O0#"
verifica_container "$ORACLE_ROOT/programs.tsv" "$tmp/export" > "$tmp/export.out" 2>&1 \
  || { indent "$tmp/export.out" >&2; fail "variabili esportate dallo script di compilazione sono arrivate a cobc"; }
log "   controprova ok: COB_CONFIG_DIR, COBCPY, COB_CFLAGS esportati nello script di compilazione non arrivano a cobc"
# c) configurazione di runtime alternativa nell'ambiente dei programmi.
build_alterata run "s#^\. /oracle/ambiente\.sh\$#. /oracle/ambiente.sh; AMBIENTE_RUN=\"\$AMBIENTE_RUN COB_RUNTIME_CONFIG=$alt/runtime_empty.cfg\"#"
expect_fail "COB_RUNTIME_CONFIG alternativo nell'ambiente dei programmi: ambiente" "ambiente dei programmi diverso" verifica_container "$ORACLE_ROOT/programs.tsv" "$tmp/run"
expect_fail "COB_RUNTIME_CONFIG alternativo: configurazione di runtime riportata da libcob" "configurazione di runtime diversa" verifica_container "$ORACLE_ROOT/programs.tsv" "$tmp/run"
# d) evidenze alterate.
copia cfgsha; mutate "$tmp/cfgsha/configurazione.sha256" 's/^[0-9a-f]\{64\}  ibm\.conf$/0000000000000000000000000000000000000000000000000000000000000000  ibm.conf/'
expect_fail "SHA-256 di ibm.conf alterato" "configurazione del compilatore diversa" verifica "$tmp/cfgsha.tsv" "$tmp/cfgsha"
copia info; mutate "$tmp/info/cobc-info.txt" '/^COB_CONFIG_DIR /a\
  env: COB_CONFIG_DIR    : /tmp/alt'
expect_fail "riga env: in cobc --info" "cobc --info riporta variabili d'ambiente" verifica "$tmp/info.tsv" "$tmp/info"
copia rtc; mutate "$tmp/rtc/runtime-config.txt" 's/^    : COB_VARSEQ_FORMAT      : 0        (default)$/ env: COB_VARSEQ_FORMAT      : 1       /'
expect_fail "COB_VARSEQ_FORMAT diverso nella configurazione di runtime" "configurazione di runtime diversa" verifica "$tmp/rtc.tsv" "$tmp/rtc"
copia ambc; rm "$tmp/ambc/ambiente-cobc.txt"
expect_fail "ambiente di cobc non registrato" "ambiente di cobc diverso" verifica "$tmp/ambc.tsv" "$tmp/ambc"

cp "$ORACLE_ROOT/cobc.opts" "$tmp/cobc.opts"; mutate "$tmp/cobc.opts" 's/^-fsign=EBCDIC$/# -fsign=EBCDIC/'
expect_fail "-fsign=EBCDIC tolto da cobc.opts" "fissate nel controllo" opzioni_fisse "$tmp/cobc.opts"
cp "$ORACLE_ROOT/cobc.opts" "$tmp/cobc2.opts"; mutate "$tmp/cobc2.opts" '$a\
-fno-binary-truncate'
expect_fail "opzione -fno-binary-truncate aggiunta in coda a cobc.opts" "fissate nel controllo" opzioni_fisse "$tmp/cobc2.opts"
cp "$ORACLE_ROOT/cobc.opts" "$tmp/cobc3.opts"; mutate "$tmp/cobc3.opts" 's/^-fbinary-truncate$/-fbinary-truncate -fno-binary-truncate/'
expect_fail "due opzioni sulla stessa riga di cobc.opts" "riga con piu' di una parola" opzioni_fisse "$tmp/cobc3.opts"

mkdir -p "$tmp/passi"
for v in $PASSI; do
  n="${v%%:*}"; d="${v#*:}"; mkdir -p "$tmp/passi/$n"; : > "$tmp/passi/$n/check.sh"
  [ "$d" = - ] || { : > "$tmp/passi/$n/run.sh"; echo "$d" > "$tmp/passi/$n/deps"; }
done
passi_presenti "$tmp/passi" > /dev/null || fail "la struttura di prova dei passi non e' valida"
rm "$tmp/passi/avvio/check.sh"
expect_fail "passo avvio senza check.sh" "passo avvio: manca check.sh" passi_presenti "$tmp/passi"
rm -r "$tmp/passi/segno"
expect_fail "passo segno cancellato" "passo segno: manca check.sh" passi_presenti "$tmp/passi"
log "controllo superato"
