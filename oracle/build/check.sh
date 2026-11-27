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
# Numero di voci senza comandi esterni (issue #35: prima wc girava dentro una sostituzione di comando).
# shellcheck disable=SC2086
set -- $FISSO
[ $# -eq 12 ] || fail "l'elenco fisso del controllo non ha 12 voci"
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
  local elenco="$1" out="$2" rc=0 p ce co
  # Percorsi nel container calcolati prima, con l'esito controllato (issue #35).
  ce="$(in_container "$elenco")" && co="$(in_container "$out")" \
    || { echo "DIFETTO: percorsi della verifica non calcolabili (in_container)"; return 1; }
  # shellcheck disable=SC2086
  orun -- timeout 300 sh /oracle/build/verifica.sh "$ce" "$co" \
    "$OPZIONI_FISSE" "$AMB_COBC_FISSO" "$AMB_RUN_FISSO" $FISSO $ACCESSORI || rc=1
  if p="$(stamp_problem "$out")"; then echo "impronta valida: input e artefatti attuali"
  else echo "DIFETTO: impronta: $p"; rc=1; fi
  return "$rc"
}

# opzioni_fisse FILE: le righe non commento del file, una parola ciascuna, sono esattamente OPZIONI_FISSE.
opzioni_fisse() {
  local got bad
  # Esiti delle pipeline controllati (pipefail, da lib.sh; issue #35).
  bad="$(sed -e 's/#.*$//' "$1" | awk 'NF > 1')" || { echo "opzioni in $(rel "$1"): lettura fallita"; return 1; }
  [ -z "$bad" ] || { echo "opzioni in $(rel "$1"): riga con piu' di una parola: '$bad'"; return 1; }
  got="$(sed -e 's/#.*$//' "$1" | awk 'NF {print $1}' | tr '\n' ' ' | sed 's/ $//')" \
    || { echo "opzioni in $(rel "$1"): lettura fallita"; return 1; }
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
adafail_build() {
  local c
  c="$(in_container "$tmp/adafail.compile.sh")" || fail "percorso di adafail.compile.sh non calcolabile"
  orun -v "$tmp/adafail:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" sh "$c" tutto /oracle/programs.tsv /out
}
expect_fail "generazione delle copie adattate fallita: la build fallisce" "generazione delle copie adattate fallita" adafail_build

# Ambiente e configurazione del compilatore e del runtime.
# verifica_container ELENCO OUT: la sola verifica nel container (senza impronta).
verifica_container() {
  local ce co
  ce="$(in_container "$1")" && co="$(in_container "$2")" \
    || { echo "DIFETTO: percorsi della verifica non calcolabili (in_container)"; return 1; }
  # shellcheck disable=SC2086
  orun -- timeout 300 sh /oracle/build/verifica.sh "$ce" "$co" \
    "$OPZIONI_FISSE" "$AMB_COBC_FISSO" "$AMB_RUN_FISSO" $FISSO $ACCESSORI
}
# build_alterata NOME ESPRESSIONE-SED: build completa reale con una copia alterata di compile.sh.
build_alterata() {
  local c
  cp "$ORACLE_ROOT/build/compile.sh" "$tmp/$1.compile.sh"
  mutate "$tmp/$1.compile.sh" "$2"
  mkdir -p "$tmp/$1"
  c="$(in_container "$tmp/$1.compile.sh")" || fail "build alterata '$1': percorso di compile.sh non calcolabile"
  orun -v "$tmp/$1:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh "$c" tutto /oracle/programs.tsv /out > "$tmp/$1.log" 2>&1 \
    || { indent "$tmp/$1.log" >&2; fail "build alterata '$1' fallita"; }
}
config_alternativa "$tmp/alt"
alt="$(in_container "$tmp/alt")" || fail "percorso della configurazione alternativa non calcolabile"
# a) configurazione alternativa (perform-osvs: no) che arriva davvero a cobc.
build_alterata cfg "s#^\. /oracle/ambiente\.sh\$#. /oracle/ambiente.sh; AMBIENTE_COBC=\"\$AMBIENTE_COBC COB_CONFIG_DIR=$alt\"#"
expect_fail "build con COB_CONFIG_DIR alternativo nell'ambiente di cobc: ambiente" "ambiente di cobc diverso" verifica_container "$ORACLE_ROOT/programs.tsv" "$tmp/cfg"
expect_fail "build con COB_CONFIG_DIR alternativo: cobc --info lo riporta" "cobc --info riporta variabili d'ambiente" verifica_container "$ORACLE_ROOT/programs.tsv" "$tmp/cfg"
expect_fail "build con COB_CONFIG_DIR alternativo: file di configurazione diversi" "configurazione del compilatore diversa" verifica_container "$ORACLE_ROOT/programs.tsv" "$tmp/cfg"
# a') manifesto della configurazione alternativa (issue #35, rilievo 2 del giro 3 della PR #29): la build deve
#     registrare la cartella realmente usata e lo SHA-256 di ognuno dei suoi file. Atteso acquisito qui in modo
#     indipendente da compile.sh: il percorso e' quello che il controllo stesso ha passato a cobc, i nomi si
#     elencano con find e gli hash si calcolano con un solo sha256sum, nella cartella montata altrove (/ind).
manifesto_indipendente() { # manifesto_indipendente CARTELLA-SULL'HOST PERCORSO-PASSATO-A-COBC
  printf 'cartella %s\n' "$2" || return 1
  orun -v "$1:/ind:ro" -- timeout 60 sh -c 'set -eu; set -o pipefail; cd /ind
    find . -mindepth 1 -maxdepth 1 -printf "%f\n" | LC_ALL=C sort > /tmp/nomi
    [ -s /tmp/nomi ]
    tr "\n" "\0" < /tmp/nomi | xargs -0 sha256sum'
}
# confronta_manifesto MANIFESTO: confronto integrale con l'atteso indipendente ($tmp/cfg.atteso).
confronta_manifesto() {
  if cmp -s "$tmp/cfg.atteso" "$1"; then echo "manifesto identico a quello acquisito in modo indipendente"; return 0; fi
  echo "manifesto della configurazione alternativa diverso da quello acquisito in modo indipendente:"
  diff "$tmp/cfg.atteso" "$1" | sed 's/^/    /'
  return 1
}
# log_senza_errori_cd LOG: nessun "can't cd" nel log della build (esiti ammessi di grep: 1 = nessuna riga).
log_senza_errori_cd() {
  local r=0
  grep -F "can't cd" "$1" || r=$?
  case "$r" in
    1) echo "nessun errore 'can't cd' nel log $(rel "$1")" ;;
    0) echo "errore spurio 'can't cd' nel log $(rel "$1")"; return 1 ;;
    *) echo "lettura del log $(rel "$1") fallita (grep, codice $r)"; return 1 ;;
  esac
}
manifesto_indipendente "$tmp/alt" "$alt" > "$tmp/cfg.atteso" || fail "manifesto indipendente della configurazione alternativa non calcolabile"
# L'atteso indipendente ha gli stessi nomi di file della configurazione dell'immagine (la cartella e' una sua
# copia) e differisce da quella solo nella riga della cartella e nell'hash di ibm.conf.
r=0; diff "$ORACLE_ROOT/build/expected/configurazione.sha256" "$tmp/cfg.atteso" > "$tmp/cfg.diff" || r=$?
[ "$r" -eq 1 ] || fail "confronto dell'atteso indipendente con quello dell'immagine non riuscito (diff, codice $r)"
cdiff="$(grep -c '^[<>]' "$tmp/cfg.diff")" || fail "conteggio delle differenze dell'atteso indipendente fallito"
[ "$cdiff" -eq 4 ] && grep -qxF "> cartella $alt" "$tmp/cfg.diff" && grep -q '^> [0-9a-f]\{64\}  ibm\.conf$' "$tmp/cfg.diff" \
  || { indent "$tmp/cfg.diff" >&2; fail "l'atteso indipendente non differisce da quello dell'immagine solo per cartella e ibm.conf"; }
confronta_manifesto "$tmp/cfg/configurazione.sha256" > "$tmp/cfgman.out" 2>&1 \
  || { indent "$tmp/cfgman.out" >&2; fail "build con COB_CONFIG_DIR alternativo: il manifesto non e' quello della cartella usata"; }
log_senza_errori_cd "$tmp/cfg.log" > "$tmp/cfgcd.out" 2>&1 || { indent "$tmp/cfgcd.out" >&2; fail "build con COB_CONFIG_DIR alternativo: errore spurio nel log"; }
log "   manifesto della configurazione alternativa: cartella $(rel "$tmp/alt") e SHA-256 dei suoi file, identico all'atteso indipendente; nessun 'can't cd' nel log"
copia_manifesto() { cp "$tmp/cfg/configurazione.sha256" "$tmp/$1.sha256" || fail "copia del manifesto fallita"; }
copia_manifesto man1; mutate "$tmp/man1.sha256" "1s#^cartella .*#cartella COB_CONFIG_DIR#"
expect_fail "manifesto con il nome della variabile al posto del percorso (difetto del giro 3 della PR #29)" "diverso da quello acquisito" confronta_manifesto "$tmp/man1.sha256"
copia_manifesto man2; ibm_img="$(grep '  ibm\.conf$' "$ORACLE_ROOT/build/expected/configurazione.sha256")" || fail "hash di ibm.conf dell'immagine non trovato"
mutate "$tmp/man2.sha256" "s#^[0-9a-f]\{64\}  ibm\.conf\$#$ibm_img#"
expect_fail "manifesto con l'hash di ibm.conf della cartella dell'immagine (cartella sbagliata)" "diverso da quello acquisito" confronta_manifesto "$tmp/man2.sha256"
cp "$tmp/cfg.log" "$tmp/cfgcd.log" && printf "compile.sh: 1: cd: can't cd to COB_CONFIG_DIR\n" >> "$tmp/cfgcd.log" || fail "preparazione del log alterato fallita"
expect_fail "log della build con l'errore spurio del giro 3 della PR #29" "errore spurio 'can't cd'" log_senza_errori_cd "$tmp/cfgcd.log"
# L'estrazione del giro 3 della PR #29 (secondo campo della riga "env:", cioe' il nome della variabile) oggi
# ferma la build: l'elenco della cartella "COB_CONFIG_DIR" fallisce ed e' un'acquisizione controllata.
cp "$ORACLE_ROOT/build/compile.sh" "$tmp/vecchia.compile.sh"
mutate "$tmp/vecchia.compile.sh" 's#{ e = \$0; sub(/^  env: COB_CONFIG_DIR\[\[:space:\]\]\*: /, "", e) }#{ split($0, campi, ": "); e = campi[2] }#'
mutate "$tmp/vecchia.compile.sh" "s#^\. /oracle/ambiente\.sh\$#. /oracle/ambiente.sh; AMBIENTE_COBC=\"\$AMBIENTE_COBC COB_CONFIG_DIR=$alt\"#"
mkdir -p "$tmp/vecchia"
vecchia_build() {
  local c
  c="$(in_container "$tmp/vecchia.compile.sh")" || fail "percorso di vecchia.compile.sh non calcolabile"
  orun -v "$tmp/vecchia:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" sh "$c" tutto /oracle/programs.tsv /out
}
expect_fail "estrazione del giro 3 della PR #29 con COB_CONFIG_DIR alternativo: la build si ferma" \
  "acquisizione fallita: elenco dei file di configurazione di COB_CONFIG_DIR (ls)" vecchia_build
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

log "6. esiti dei comandi: acquisizioni della build, esegui.sh, verifica.sh, lib.sh (issue #35)"
# Schema comune: un solo comando alla volta e' avvolto da build/avvolgi.sh, che lo esegue davvero (output
# autentico), scrive una riga nel registro e restituisce 42. Ogni prova verifica che lo script fallisca per il
# motivo atteso e, dal registro, che il comando bersaglio sia stato raggiunto con l'esito reale atteso.
# Controprove: con gli stessi involucri in modo "passa" tutto riesce e i risultati non cambiano.

# bersaglio REGISTRO ID ESITO-REALE: il comando con ID e' stato raggiunto e almeno una sua invocazione, con
# l'esito reale atteso (0, oppure 1 per grep senza righe trovate), e' stata trasformata in 42.
bersaglio() {
  local n
  n="$(awk -v id="$2" -v r="$3" '$1==id && $4==42 && $3==r {n++} END {if (n==0) exit 1; print n}' "$1")" \
    || { [ ! -f "$1" ] || indent "$1" >&2; fail "comando bersaglio $2 non raggiunto o non avvolto come atteso (registro $(rel "$1"))"; }
  log "     bersaglio raggiunto: $2 ($n invocazioni con esito reale $3 restituite come 42)"
}

# 6a. Build di produzione. build/run.sh (con lib.sh, la verifica del volume e la scrittura dell'impronta) gira su
#     una copia dell'oracle con il legacy collegato, in cui compile.sh ha un solo comando avvolto. Un'acquisizione
#     fallita deve fermare la build con un messaggio che la nomina, prima che l'impronta venga scritta.
radice="$tmp/radice"
mkdir -p "$radice/oracle/build" "$radice/legacy" || fail "copia dell'oracle: cartelle non creabili"
for x in Dockerfile cobc.opts programs.tsv ambiente.sh lib.sh esegui.sh launcher stubs tests adattamenti; do
  cp -R "$ORACLE_ROOT/$x" "$radice/oracle/$x" || fail "copia dell'oracle: $x non copiato"
done
rm -rf "$radice/oracle/adattamenti/out" || fail "copia dell'oracle: adattamenti/out non cancellabile"
cp "$ORACLE_ROOT"/build/*.sh "$radice/oracle/build/" || fail "copia dell'oracle: script di build/ non copiati"
ln -s "$LEGACY" "$radice/legacy/${LEGACY##*/}" || fail "copia dell'oracle: collegamento al legacy non creabile"
rout="$radice/oracle/build/out"
build_copia() { env -u ORACLE_BUILD_OUT -u BUILD_ELENCO ORACLE_ROOT="$radice/oracle" bash "$radice/oracle/build/run.sh" < /dev/null; }
# avvolgi_in FILE PREFISSO ID MODO: mette l'involucro davanti all'unica occorrenza di PREFISSO in FILE.
avvolgi_in() {
  local f="$1" pre="$2" n r=0
  n="$(grep -cF -- "$pre" "$f")" || fail "avvolgi_in: '$pre' non trovato in $(rel "$f")"
  [ "$n" -eq 1 ] || fail "avvolgi_in: '$pre' compare in $n righe di $(rel "$f"), attesa una"
  # Sostituzione letterale con awk (testi passati per ambiente: awk -v interpreterebbe le sequenze \t).
  AVV_PRE="$pre" AVV_INS="sh /oracle/build/avvolgi.sh /out/registro $3 $4 " \
    awk '{ i = index($0, ENVIRON["AVV_PRE"]); if (i) $0 = substr($0, 1, i - 1) ENVIRON["AVV_INS"] substr($0, i); print }' \
    "$f" > "$f.mut" || fail "avvolgi_in: scrittura fallita"
  cmp -s "$f" "$f.mut" || r=$?
  [ "$r" -eq 1 ] || fail "avvolgi_in: '$pre' non sostituito in $(rel "$f")"
  mv "$f.mut" "$f" || fail "avvolgi_in: sostituzione di $(rel "$f") fallita"
}
# Punti di acquisizione (issue #35, specifica punto 1) e altri comandi di compile.sh con l'esito controllato:
# ID|PREFISSO DEL COMANDO|MODO|ESITO REALE ATTESO|MOTIVO ATTESO
PUNTI_BUILD="A01|env -i \$AMBIENTE_COBC cobc --version|42|0|acquisizione fallita: cobc --version (codice 42)
A02|env -i \$AMBIENTE_COBC cobc --info > \"\$w/|42|0|acquisizione fallita: cobc --info (per ambiente.txt) (codice 42)
A03|dpkg-query -W|42|0|acquisizione fallita: dpkg-query (pacchetti) (codice 42)
A04|env -i \$AMBIENTE_RUN cobcrun --runtime-config > \"\$w/|42|0|acquisizione fallita: cobcrun --runtime-config (per ambiente.txt) (codice 42)
A05|head -n 1|42|0|acquisizione fallita: composizione di ambiente.txt (codice 42)
A06|sed -n '/GnuCOBOL|42|0|acquisizione fallita: composizione di ambiente.txt (codice 42)
A07|env -i \$AMBIENTE_COBC env|42|0|acquisizione fallita: env (ambiente di cobc) (codice 42)
A08|env -i \$AMBIENTE_RUN env|42|0|acquisizione fallita: env (ambiente dei programmi) (codice 42)
A09|env -i \$AMBIENTE_COBC cobc --info > \"\$out/|42|0|acquisizione fallita: cobc --info (per cobc-info.txt) (codice 42)
A10|awk '|42|0|acquisizione fallita: estrazione della cartella di configurazione da cobc --info (awk) (codice 42)
A11|ls -A)|42|0|acquisizione fallita: elenco dei file di configurazione di /usr/share/gnucobol/config (ls) (codice 42)
A12|sha256sum \"\$f\"|42:acu.conf|0|acquisizione fallita: sha256sum di acu.conf (codice 42)
A13|env -i \$AMBIENTE_RUN cobcrun --runtime-config > \"\$out/|42|0|acquisizione fallita: cobcrun --runtime-config (per runtime-config.txt) (codice 42)
C01|grep -c -- \"\$1\"|42@1|1|conteggio di ': warning: ' in /out/log/CEE3ABD.log fallito (grep, codice 42)
C02|grep -v '^#'|42|0|lettura dell'elenco /oracle/programs.tsv fallita (grep, codice 42)
C03|tail -n +2|42|0|lettura dell'elenco /oracle/programs.tsv fallita (tail)
C04|awk -F'\\t' 'NR>1|42|0|lettura di /out/compilazione.tsv fallita (awk)
C05|sed -e 's/#|42@1|0|lettura delle opzioni di /oracle/cobc.opts fallita (sed)"
# Il file del ciclo degli hash che si fa fallire (acu.conf) non e' l'ultimo della cartella.
ultimo_cfg="$(tail -n 1 "$ORACLE_ROOT/build/expected/configurazione.sha256")" || fail "lettura dell'atteso della configurazione fallita"
[ "${ultimo_cfg##* }" != acu.conf ] && grep -q '  acu\.conf$' "$ORACLE_ROOT/build/expected/configurazione.sha256" \
  || fail "acu.conf assente o ultimo nella configurazione: la prova del ciclo degli hash non sarebbe su un file non ultimo"
while IFS='|' read -r id pre modo reale motivo; do
  cp "$ORACLE_ROOT/build/compile.sh" "$radice/oracle/build/compile.sh" || fail "copia di compile.sh fallita"
  avvolgi_in "$radice/oracle/build/compile.sh" "$pre" "$id" "$modo"
  clean_dir "$rout"
  expect_fail "build di produzione con '$pre' che restituisce 42 ($id)" "$motivo" build_copia
  [ ! -e "$rout/IMPRONTA" ] || fail "prova $id: la build fallita ha scritto l'impronta"
  bersaglio "$rout/registro" "$id" "$reale"
done <<< "$PUNTI_BUILD"
# Il ciclo degli hash si e' fermato al secondo file: il primo (acu-strict.conf) e' passato, nessuno dopo acu.conf.
cp "$ORACLE_ROOT/build/compile.sh" "$radice/oracle/build/compile.sh" || fail "copia di compile.sh fallita"
avvolgi_in "$radice/oracle/build/compile.sh" 'sha256sum "$f"' A12 42:acu.conf
clean_dir "$rout"
expect_fail "build di produzione: sha256sum di acu.conf (secondo file di 40) restituisce 42" "acquisizione fallita: sha256sum di acu.conf" build_copia
awk '$1=="A12" {n++; f[n]=$4 " " $NF} END {exit !(n==2 && f[1]=="0 acu-strict.conf" && f[2]=="42 acu.conf")}' "$rout/registro" \
  || { indent "$rout/registro" >&2; fail "ciclo degli hash: attese due invocazioni (acu-strict.conf passato, acu.conf fallito)"; }
log "     ciclo degli hash fermato al secondo file: acu-strict.conf passato, acu.conf con 42, nessun file successivo"
# Estrazione vuota: cobc --info senza la cartella di configurazione ferma la build.
cp "$ORACLE_ROOT/build/compile.sh" "$radice/oracle/build/compile.sh" || fail "copia di compile.sh fallita"
mutate "$radice/oracle/build/compile.sh" 's/END { v = (e != "" ? e : d);/END { v = "";/'
clean_dir "$rout"
expect_fail "build di produzione con estrazione vuota della cartella di configurazione" \
  "acquisizione fallita: cobc --info non riporta la cartella di configurazione" build_copia
[ ! -e "$rout/IMPRONTA" ] || fail "estrazione vuota: la build fallita ha scritto l'impronta"
# Controprova: tutti gli involucri insieme in modo "passa". La build riesce, scrive l'impronta, ogni comando
# avvolto e' stato raggiunto con l'esito reale restituito tale e quale, e i risultati sono identici a quelli della
# build di produzione del punto 1 (gli involucri lasciano passare l'output autentico).
cp "$ORACLE_ROOT/build/compile.sh" "$radice/oracle/build/compile.sh" || fail "copia di compile.sh fallita"
while IFS='|' read -r id pre modo reale motivo; do
  avvolgi_in "$radice/oracle/build/compile.sh" "$pre" "$id" passa
done <<< "$PUNTI_BUILD"
clean_dir "$rout"
build_copia > "$tmp/passa.log" 2>&1 || { indent "$tmp/passa.log" >&2; fail "controprova: la build con gli involucri in modo passa e' fallita"; }
[ -f "$rout/IMPRONTA" ] || fail "controprova: la build riuscita non ha scritto l'impronta"
# passato_intatto REGISTRO ID: ID raggiunto almeno una volta, sempre con l'esito reale restituito tale e quale.
passato_intatto() {
  awk -v id="$2" '$1==id {n++; if ($3!=$4) bad++} END {exit !(n>0 && !bad)}' "$1" \
    || { echo "$2 non raggiunto o con l'esito alterato (registro $(rel "$1"))"; return 1; }
}
# risultati_identici CARTELLA: i risultati dell'ambiente e delle compilazioni coincidono con la build del punto 1.
risultati_identici() {
  local f
  for f in ambiente.txt ambiente-cobc.txt ambiente-run.txt cobc-info.txt configurazione.sha256 runtime-config.txt compilazione.tsv opzioni.txt; do
    cmp -s "$BUILD_OUT/$f" "$1/$f" || { echo "$f diverso da quello della build di produzione"; return 1; }
  done
}
while IFS='|' read -r id pre modo reale motivo; do
  passato_intatto "$rout/registro" "$id" > "$tmp/pi.out" 2>&1 || { indent "$tmp/pi.out" >&2; fail "controprova: $id"; }
done <<< "$PUNTI_BUILD"
risultati_identici "$rout" > "$tmp/ri.out" 2>&1 || { indent "$tmp/ri.out" >&2; fail "controprova: risultati con gli involucri diversi"; }
log "   controprova ok: involucri in modo passa su tutti i punti, build riuscita con impronta, risultati identici"
# Prove negative dei controlli della controprova e di bersaglio.
cp -R "$rout" "$tmp/rout-alt" || fail "copia dei risultati della controprova fallita"
mutate "$tmp/rout-alt/runtime-config.txt" '$a\
riga in piu'
expect_fail "controprova: runtime-config.txt con una riga in piu'" "runtime-config.txt diverso" risultati_identici "$tmp/rout-alt"
mutate "$tmp/rout-alt/registro" 's/^A01 1 0 0 /A01 1 0 42 /'
expect_fail "controprova: involucro che ha alterato l'esito (registro)" "A01 non raggiunto o con l'esito alterato" passato_intatto "$tmp/rout-alt/registro" A01
expect_fail "controprova: comando mai raggiunto (registro)" "Z99 non raggiunto" passato_intatto "$tmp/rout-alt/registro" Z99
expect_fail "bersaglio: nessuna invocazione restituita come 42 (registro della controprova)" "comando bersaglio A02 non raggiunto" \
  bash -c '. "$ORACLE_ROOT/lib.sh"; eval "$1"; bersaglio "$2" A02 0' _ "$(declare -f bersaglio)" "$rout/registro"
expect_fail "bersaglio: esito reale diverso dall'atteso" "comando bersaglio A01 non raggiunto" \
  bash -c '. "$ORACLE_ROOT/lib.sh"; eval "$1"; bersaglio "$2" A01 1' _ "$(declare -f bersaglio)" "$tmp/rout-alt/registro"
# Residuo sano: l'impronta e il registro della controprova restano nella cartella; una build con A01 a 42 deve
# fallire senza impronta e con un registro che contiene solo la sua invocazione (build/run.sh cancella l'output).
cp "$ORACLE_ROOT/build/compile.sh" "$radice/oracle/build/compile.sh" || fail "copia di compile.sh fallita"
avvolgi_in "$radice/oracle/build/compile.sh" 'env -i $AMBIENTE_COBC cobc --version' A01 42
[ -f "$rout/IMPRONTA" ] && [ -s "$rout/registro" ] || fail "residuo: impronta o registro della controprova assenti"
expect_fail "residuo sano della controprova, poi cobc --version a 42" "acquisizione fallita: cobc --version (codice 42)" build_copia
[ ! -e "$rout/IMPRONTA" ] || fail "residuo: l'impronta della corsa precedente e' sopravvissuta a una build fallita"
solo_a01() { awk '$1!="A01" {bad=1} END {exit !(NR==1 && !bad)}' "$1" || { echo "il registro $(rel "$1") contiene righe di un'altra corsa"; return 1; }; }
solo_a01 "$rout/registro" > "$tmp/sa.out" 2>&1 || { indent "$rout/registro" >&2; fail "residuo: il registro contiene righe di una corsa precedente"; }
expect_fail "residuo: registro con le righe della controprova" "contiene righe di un'altra corsa" solo_a01 "$tmp/rout-alt/registro"
log "     residuo sano rimosso: nessuna impronta, registro con la sola invocazione della corsa"

# 6b. Esiti ammessi di grep -c: la build sana ha programmi con conteggi a zero (grep -c esce con 1) ed e' verde.
zeri="$(awk -F'\t' 'NR>1 && $5==0 && $6==0 {n++} END {print n+0}' "$BUILD_OUT/compilazione.tsv")" || fail "lettura di compilazione.tsv fallita"
[ "$zeri" -gt 0 ] || fail "nessuna compilazione con conteggi a zero: l'esito 1 di grep -c non e' coperto"
log "   compilazioni con 0 avvertimenti e 0 errori nella build verde (grep -c con esito 1, ammesso): $zeri"

# 6c. esegui.sh e verifica.sh: involucri davanti nel PATH del container (i programmi compilati non li vedono:
#     partono da env -i con PATH=/usr/bin:/bin).
# prepara_avvolti CARTELLA COMANDO=MODO...: un involucro per comando in CARTELLA/avv, registro in CARTELLA/res.
prepara_avvolti() {
  local d="$1" s c m; shift
  clean_dir "$d"
  mkdir -p "$d/avv" "$d/res" || fail "cartelle degli involucri non creabili"
  for s in "$@"; do
    c="${s%%=*}"; m="${s#*=}"
    printf '#!/bin/sh\nexec sh /oracle/build/avvolgi.sh /res/registro %s '\''%s'\'' /usr/bin/%s "$@"\n' "$c" "$m" "$c" > "$d/avv/$c" \
      && chmod +x "$d/avv/$c" || fail "involucro di $c non creabile"
  done
}
# esegui_avvolto NOME COMANDO=MODO...: PARMECHO con esegui.sh, rapporto in $tmp/es-NOME/res/out/PARMECHO.txt.
esegui_avvolto() {
  local d="$tmp/es-$1"; shift
  prepara_avvolti "$d" "$@"
  mkdir -p "$d/res/out" || fail "cartella dei risultati non creabile"
  orun -v "$d/avv:/avv:ro" -v "$d/res:/res" -v "$BUILD_OUT/bin:/oracle-bin:ro" -e PATH=/avv:/usr/bin:/bin \
    -- timeout -k 10 120 sh /oracle/esegui.sh /res/out PARMECHO --parm 2022071800
}
esegui_avvolto rif > "$tmp/es-rif.log" 2>&1 || { indent "$tmp/es-rif.log" >&2; fail "esegui.sh senza involucri fallito"; }
esegui_avvolto passa ls=passa cat=passa sort=passa wc=passa tr=passa rm=passa mkdir=passa env=passa > "$tmp/es-passa.log" 2>&1 \
  || { indent "$tmp/es-passa.log" >&2; fail "controprova: esegui.sh con gli involucri in modo passa fallito"; }
# rapporti_identici CARTELLA-A CARTELLA-B: rapporto e ambiente di PARMECHO uguali byte per byte.
rapporti_identici() {
  cmp -s "$1/PARMECHO.txt" "$2/PARMECHO.txt" && cmp -s "$1/PARMECHO.ambiente" "$2/PARMECHO.ambiente" \
    || { echo "rapporto o ambiente di PARMECHO diversi tra $(rel "$1") e $(rel "$2")"; return 1; }
}
rapporti_identici "$tmp/es-rif/res/out" "$tmp/es-passa/res/out" > "$tmp/rid.out" 2>&1 \
  || { indent "$tmp/rid.out" >&2; fail "controprova: rapporto di esegui.sh con gli involucri diverso da quello senza"; }
mkdir -p "$tmp/es-alt" && cp "$tmp/es-passa/res/out/PARMECHO.txt" "$tmp/es-passa/res/out/PARMECHO.ambiente" "$tmp/es-alt/" || fail "copia del rapporto fallita"
mutate "$tmp/es-alt/PARMECHO.txt" 's/^PARMDUMP /PARMDUMQ /'
expect_fail "controprova di esegui.sh: rapporto con un nome di file alterato" "rapporto o ambiente di PARMECHO diversi" rapporti_identici "$tmp/es-rif/res/out" "$tmp/es-alt"
for c in ls cat sort wc tr rm mkdir env; do
  passato_intatto "$tmp/es-passa/res/registro" "$c" > "$tmp/pi.out" 2>&1 || { indent "$tmp/pi.out" >&2; fail "controprova di esegui.sh: $c"; }
done
grep -qx 'PARMDUMP [0-9][0-9]*' "$tmp/es-rif/res/out/PARMECHO.txt" || fail "PARMECHO non ha creato PARMDUMP: wc e tr non sarebbero provati"
log "   controprova ok: esegui.sh con gli involucri in modo passa, rapporto e ambiente identici"
# ID|COMANDO=MODO|MOTIVO ATTESO
PUNTI_ESEGUI="ES01|ls=42@1|cartella di lavoro non elencabile
ES02|ls=42@2|rapporto non scrivibile o incompleto
ES03|cat=42@1|rapporto non scrivibile o incompleto
ES04|cat=42@2|rapporto non scrivibile o incompleto
ES05|sort=42|rapporto non scrivibile o incompleto
ES06|wc=42|rapporto non scrivibile o incompleto
ES07|tr=42|rapporto non scrivibile o incompleto
ES08|rm=42@1|cartella di lavoro non creabile
ES09|mkdir=42|cartella di lavoro non creabile
ES10|rm=42@2|file temporanei non rimovibili
ES11|env=42@1|ambiente non registrabile"
while IFS='|' read -r id spec motivo; do
  expect_fail "esegui.sh con ${spec%%=*} che restituisce 42 (${spec#*=}, $id)" "esegui.sh: $motivo" esegui_avvolto "$id" "$spec"
  bersaglio "$tmp/es-$id/res/registro" "${spec%%=*}" 0
done <<< "$PUNTI_ESEGUI"

bo="$(in_container "$BUILD_OUT")" || fail "percorso della build nel container non calcolabile"
# verifica_avvolta NOME COMANDO=MODO...: verifica.sh (nel container) sulla build sana del punto 1.
verifica_avvolta() {
  local d="$tmp/vf-$1"; shift
  prepara_avvolti "$d" "$@"
  # shellcheck disable=SC2086
  orun -v "$d/avv:/avv:ro" -v "$d/res:/res" -e PATH=/avv:/usr/bin:/bin -- timeout 300 sh /oracle/build/verifica.sh \
    /oracle/programs.tsv "$bo" "$OPZIONI_FISSE" "$AMB_COBC_FISSO" "$AMB_RUN_FISSO" $FISSO $ACCESSORI
}
verifica_avvolta passa comm=passa grep=passa tail=passa nm=passa > "$tmp/vf-passa.log" 2>&1 \
  || { indent "$tmp/vf-passa.log" >&2; fail "controprova: verifica.sh con gli involucri in modo passa fallita"; }
for c in comm grep tail nm; do
  passato_intatto "$tmp/vf-passa/res/registro" "$c" > "$tmp/pi.out" 2>&1 || { indent "$tmp/pi.out" >&2; fail "controprova di verifica.sh: $c"; }
done
log "   controprova ok: verifica.sh con gli involucri in modo passa supera la verifica della build sana"
# ID;COMANDO=MODO;ESITO REALE;MOTIVO ATTESO (separatore ';': un modello di grep contiene '|')
PUNTI_VERIFICA="VF01;comm=42:-3;0;DIFETTO: elenco: confronto con l'elenco fisso fallito (comm)
VF02;grep=42:;0;DIFETTO: CBACT01C: attesa una riga in compilazione.tsv, trovate (conteggio fallito, grep codice 42)
VF03;grep=42:: warning: ;1;DIFETTO: CBACT01C: conteggio di avvertimenti/errori nel log fallito (grep -c)
VF04;tail=42@2;0;DIFETTO: CBACT01C: l'ultima riga del log non e' 'codice di uscita: 0' ((lettura del log fallita: tail))
VF05;grep=42:^(== cobc\$|arg );0;DIFETTO: CBACT01C: lettura degli argomenti dal log fallita (grep, codice 42)
VF06;grep=42:^== codice ;0;DIFETTO: CBACT01C: lettura dei codici di cobc dal log fallita (grep, codice 42)
VF07;grep=42:== codice 0;1;DIFETTO: CBACT01C: lettura dei codici di cobc fallita (grep -v, codice 42)
VF08;nm=42@1;0;DIFETTO: CBACT01C: lettura dei simboli fallita (nm bin/CBACT01C)
VF09;nm=42:-D;0;DIFETTO: CBSTM03B: lettura dei simboli esportati fallita (nm -D bin/CBSTM03B.so)
VF10;nm=42@7;0;DIFETTO: CBSTM03B: lettura dei simboli fallita (nm bin/CBSTM03B.so)
VF11;grep=42:^[[:space:]]*env:;1;DIFETTO: cobc --info: ricerca delle righe env: fallita (grep, codice 42)
VF12;grep=42:^COB_CONFIG_DIR ;0;DIFETTO: cobc --info: conteggio di COB_CONFIG_DIR fallito (grep -c)"
while IFS=';' read -r id spec reale motivo; do
  expect_fail "verifica.sh con ${spec%%=*} che restituisce 42 (${spec#*=}, $id)" "$motivo" verifica_avvolta "$id" "$spec"
  bersaglio "$tmp/vf-$id/res/registro" "${spec%%=*}" "$reale"
done <<< "$PUNTI_VERIFICA"

# 6d. lib.sh e questo controllo (sull'host). avvolto_42 COMANDO PRIMO-ARGOMENTO CHIAMATA...: esegue CHIAMATA in
#     una sottoshell in cui COMANDO, quando il suo primo argomento e' PRIMO-ARGOMENTO, gira davvero (output
#     autentico), scrive su stderr "AVVOLTO <COMANDO> <argomenti> (esito reale <n>)" e restituisce 42.
avvolto_42() (
  AVV_CMD="$1"; AVV_A1="$2"; shift 2
  eval "$AVV_CMD() {
    if [ \"\${1:-}\" = \"\$AVV_A1\" ]; then
      local r=0; command $AVV_CMD \"\$@\" || r=\$?
      echo \"AVVOLTO $AVV_CMD \$* (esito reale \$r)\" >&2
      return 42
    fi
    command $AVV_CMD \"\$@\"
  }"
  "$@"
)
# con_in_container_42 CHIAMATA...: CHIAMATA in una sottoshell in cui in_container stampa il percorso autentico,
# lo dichiara su stderr e restituisce 42.
con_in_container_42() (
  in_container() { printf '/oracle/%s\n' "${1#"$ORACLE_ROOT"/}"; echo "AVVOLTO in_container $1" >&2; return 42; }
  "$@"
)
# expect_fail_raggiunto NOME MOTIVO SEGNO COMANDO...: come expect_fail, e l'output deve contenere SEGNO, la riga
# con cui l'involucro dichiara di essere stato raggiunto.
expect_fail_raggiunto() {
  local name="$1" needle="$2" segno="$3" outf="$tmp/raggiunto.out" rc=0; shift 3
  "$@" > "$outf" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || { indent "$outf" >&2; fail "PROVA NEGATIVA FALLITA ($name): il controllo non si e' accorto dell'alterazione (codice 0)"; }
  grep -qF -- "$segno" "$outf" || { indent "$outf" >&2; fail "prova negativa ($name): comando bersaglio non raggiunto ('$segno' assente)"; }
  grep -qF -- "$needle" "$outf" || { indent "$outf" >&2; fail "prova negativa ($name): fallita (codice $rc) ma non per il motivo atteso ('$needle')"; }
  log "   prova negativa ok: $name (codice $rc, motivo: '$needle', raggiunto: '$segno')"
}
immagine_da_capo() { IMAGE=""; ensure_image; }
volume_da_capo() { LEGACY_VOL=""; ensure_legacy_volume; }
mktmp_altrove() { ORACLE_ROOT="$tmp/altrove"; mktmp; }
expect_fail_altrove() { ORACLE_ROOT="$tmp/altrove"; expect_fail "$@"; }
mkdir -p "$tmp/altrove/.work" || fail "cartella di prova non creabile"
expect_fail_raggiunto "lib.sh image_tag: git hash-object restituisce 42" "hash del Dockerfile fallito" "AVVOLTO git hash-object" \
  avvolto_42 git hash-object immagine_da_capo
expect_fail_raggiunto "lib.sh ensure_legacy_volume: git rev-parse del legacy restituisce 42" "commit del legacy non leggibile" "AVVOLTO git -C" \
  avvolto_42 git -C volume_da_capo
expect_fail_raggiunto "lib.sh require_legacy: git ls-files restituisce 42" "sorgente legacy assente o non inizializzato" "AVVOLTO git -C" \
  avvolto_42 git -C require_legacy
expect_fail_raggiunto "lib.sh orun: id -u restituisce 42" "orun: id -u fallito" "AVVOLTO id -u" avvolto_42 id -u orun -- true
expect_fail_raggiunto "lib.sh orun: id -g restituisce 42" "orun: id -g fallito" "AVVOLTO id -g" avvolto_42 id -g orun -- true
expect_fail_raggiunto "lib.sh stamp_problem: cat di IMPRONTA restituisce 42" "impronta illeggibile" "AVVOLTO cat" \
  avvolto_42 cat "$BUILD_OUT/IMPRONTA" stamp_problem "$BUILD_OUT"
expect_fail_raggiunto "lib.sh mktmp: mkdir restituisce 42" "non creabile" "AVVOLTO mkdir -p" avvolto_42 mkdir -p mktmp_altrove
expect_fail_raggiunto "lib.sh mktmp: scrittura di .gitignore restituisce 42" "scrittura di" "AVVOLTO printf" avvolto_42 printf '*\n' mktmp_altrove
expect_fail_raggiunto "lib.sh mktmp: mktemp restituisce 42" "cartella temporanea non creabile" "AVVOLTO mktemp -d" avvolto_42 mktemp -d mktmp_altrove
expect_fail_raggiunto "lib.sh expect_fail: mktemp restituisce 42" "file temporaneo non creabile" "AVVOLTO mktemp" \
  avvolto_42 mktemp "$tmp/altrove/.work/neg.XXXXXX" expect_fail_altrove interna "x" false
expect_fail_raggiunto "lib.sh config_alternativa: mkdir restituisce 42" "creazione della cartella" "AVVOLTO mkdir -p" \
  avvolto_42 mkdir -p config_alternativa "$tmp/alt-prova"
expect_fail_raggiunto "check.sh opzioni_fisse: sed restituisce 42" "lettura fallita" "AVVOLTO sed -e" avvolto_42 sed -e opzioni_fisse "$ORACLE_ROOT/cobc.opts"
expect_fail_raggiunto "check.sh verifica: in_container restituisce 42" "percorsi della verifica non calcolabili" "AVVOLTO in_container" \
  con_in_container_42 verifica "$ORACLE_ROOT/programs.tsv" "$BUILD_OUT"
expect_fail_raggiunto "check.sh verifica_container: in_container restituisce 42" "percorsi della verifica non calcolabili" "AVVOLTO in_container" \
  con_in_container_42 verifica_container "$ORACLE_ROOT/programs.tsv" "$BUILD_OUT"
expect_fail_raggiunto "check.sh build_alterata: in_container restituisce 42" "percorso di compile.sh non calcolabile" "AVVOLTO in_container" \
  con_in_container_42 build_alterata incont 's/^set -u$/set -u # prova/'
expect_fail_raggiunto "check.sh adafail: in_container restituisce 42" "percorso di adafail.compile.sh non calcolabile" "AVVOLTO in_container" \
  con_in_container_42 adafail_build
log "controllo superato"
