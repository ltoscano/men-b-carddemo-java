#!/usr/bin/env bash
# Controlli del contratto dati (issue #3).
#  0. run.sh, check.sh e deps esistono e sono eseguibili
#  1. tutto l'output si rigenera dal legacy (cb2xml rieseguito su tutti i sorgenti censiti) in una cartella temporanea
#     e coincide byte per byte con quello versionato (output grezzo, intermedio e documenti generati)
#  2. i derivati versionati coincidono con quelli rigenerati dall'output grezzo versionato (XML di cb2xml, fonti estratte)
#  3. verifica dell'output rigenerato: completezza del censimento, contratti senza buchi ne' sovrapposizioni, somme,
#     RECORDSIZE, lunghezze e cifre dalla PIC, nomi e ordine contro il sorgente, attesi scritti a mano, chiavi, discordanze
#  4. prove negative: ogni alterazione deve far fallire il controllo indicato, per il motivo atteso
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/data-contract/lib.sh"
require_legacy

GENERATI="contratti contratti.tsv contratti.md chiavi.tsv chiavi.md composizioni.tsv censimento.md"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

log "0. file dell'analisi"
for f in run.sh check.sh deps; do
  [ -f "$DC_DIR/$f" ] && [ -x "$DC_DIR/$f" ] || fail "analysis/data-contract/$f assente o non eseguibile"
done
[ -d "$DC_DIR/out" ] || fail "analysis/data-contract/out assente: eseguire prima './analysis/run.sh data-contract'"
log "   ok: run.sh, check.sh, deps presenti ed eseguibili"

# confronta OUT_A DOC_A con OUT_B DOC_B (alberi completi, nessuna esclusione); stampa le differenze, ritorna 1 se ce ne sono
confronta() {
  local oa="$1" da="$2" ob="$3" db="$4" rc=0 g
  diff -r "$oa" "$ob" > "$tmp/diff.txt" 2>&1 || rc=1
  for g in $GENERATI; do
    if [ -d "$db/$g" ] || [ -d "$da/$g" ]; then
      diff -r "$da/$g" "$db/$g" >> "$tmp/diff.txt" 2>&1 || rc=1
    else
      cmp "$da/$g" "$db/$g" >> "$tmp/diff.txt" 2>&1 || rc=1
    fi
  done
  return $rc
}

log "1. rigenerazione completa dal legacy (cb2xml su tutti i sorgenti censiti) e confronto con l'output versionato"
mkdir -p "$tmp/gen/out" "$tmp/gen/doc"
genera "$tmp/gen/out" "$tmp/gen/doc"
confronta "$tmp/gen/out" "$tmp/gen/doc" "$DC_DIR/out" "$DC_DOCS" || { head -40 "$tmp/diff.txt" >&2; fail "output versionato diverso da quello rigenerato dal legacy: rieseguire './analysis/run.sh data-contract'"; }
log "   ok: $(ls "$tmp/gen/out/cb2xml"/*.xml | wc -l | tr -d ' ') XML di cb2xml, fonti, tracciati, $(ls "$tmp/gen/doc/contratti" | wc -l | tr -d ' ') contratti e viste identici ai versionati"

log "2. i derivati versionati si rigenerano dall'output grezzo versionato"
rinormalizza() {   # rinormalizza OUT_GREZZO DEST: rigenera derivati e documenti dai soli cb2xml/ e fonti/ di OUT_GREZZO
  local src="$1" d="$2"
  rm -rf "$d"; mkdir -p "$d/out" "$d/doc"
  cp -R "$src/cb2xml" "$src/fonti" "$d/out/"
  glue_run --mount "$d/out:/out" --rw "$d/doc" --mount "$DC_DOCS:/docs:ro" -- /analysis/data-contract/glue/contratti.py /out /docs /work
}
rinormalizza "$DC_DIR/out" "$tmp/rn"
confronta "$tmp/rn/out" "$tmp/rn/doc" "$DC_DIR/out" "$DC_DOCS" || { head -20 "$tmp/diff.txt" >&2; fail "RINORMALIZZAZIONE: derivati versionati diversi da quelli rigenerati dall'output grezzo versionato"; }
log "   ok: tracciati, radici, discordanze rilevate, contratti e viste coincidono con quelli rigenerati dal grezzo"

verifica() {  # verifica OUT DOCS GEN EXP (il legacy dal volume sensibile alle maiuscole, in sola lettura)
  ensure_legacy_volume
  glue_run --mount "$1:/v/out:ro" --mount "$2:/v/docs:ro" --mount "$3:/v/gen:ro" --mount "$4:/v/exp:ro" \
    --mount "$LEGACY_VOL:$DC_LEGACY:ro" -- \
    /analysis/data-contract/glue/verifica.py /v/out /v/docs /v/gen /v/exp "$DC_LEGACY" /analysis/manifest/sources.tsv
}

log "3. verifica dell'output rigenerato dal legacy"
verifica "$tmp/gen/out" "$DC_DOCS" "$tmp/gen/doc" "$DC_DIR/expected" > "$tmp/v.txt" 2>&1 || { cat "$tmp/v.txt" >&2; fail "verifica fallita"; }
sed 's/^/   /' "$tmp/v.txt" >&2

log "4. prove negative"
# mondo NOME: copia di out/, docs/ ed expected/ versionati in $tmp/m-NOME/{out,docs,exp}, poi l'alterazione
mondo() {
  local m="$tmp/m-$1"
  rm -rf "$m"; mkdir -p "$m"
  cp -R "$DC_DIR/out" "$m/out"; cp -R "$DC_DOCS" "$m/docs"; cp -R "$DC_DIR/expected" "$m/exp"
  glue_run --rw "$m" -- /analysis/data-contract/glue/altera.py "$1" /work >&2 || return 1
  echo "$m"
}
# negativa TIPO "TESTO ATTESO": la verifica dell'alterazione deve fallire e contenere il testo atteso
negativa() {
  local m rc=0; m="$(mondo "$1")" || fail "alterazione $1 non applicata"
  verifica "$m/out" "$m/docs" "$m/docs" "$m/exp" > "$tmp/neg.txt" 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || { cat "$tmp/neg.txt" >&2; fail "PROVA NEGATIVA FALLITA ($1): la verifica e' uscita con $rc invece di 1"; }
  grep -qF -- "$2" "$tmp/neg.txt" || { cat "$tmp/neg.txt" >&2; fail "prova negativa ($1): la verifica e' fallita ma non per il motivo atteso ('$2')"; }
  log "   ok: $1 -> verifica uscita con $rc, $(grep -c '^ERRORE' "$tmp/neg.txt") errori, tra cui: $2"
}
# negativa_rig TIPO "TESTO ATTESO": l'output versionato alterato deve risultare diverso da quello rigenerato dal legacy
negativa_rig() {
  local m rc=0; m="$(mondo "$1")" || fail "alterazione $1 non applicata"
  confronta "$tmp/gen/out" "$tmp/gen/doc" "$m/out" "$m/docs" || rc=$?
  [ "$rc" -eq 1 ] || fail "PROVA NEGATIVA FALLITA ($1): il confronto con la rigenerazione e' uscito con $rc invece di 1"
  grep -qF -- "$2" "$tmp/diff.txt" || { head -20 "$tmp/diff.txt" >&2; fail "prova negativa ($1): differenza inattesa (cercato '$2')"; }
  log "   ok: $1 -> confronto con la rigenerazione dal legacy uscito con $rc (${2//"$tmp"/<tmp>})"
}
# negativa_rn TIPO: l'output grezzo alterato (derivati invariati) deve dare derivati diversi da quelli versionati
negativa_rn() {
  local m rc=0; m="$(mondo "$1")" || fail "alterazione $1 non applicata"
  rinormalizza "$m/out" "$tmp/rn-neg" > /dev/null 2>&1 || true
  confronta "$tmp/rn-neg/out" "$tmp/rn-neg/doc" "$DC_DIR/out" "$DC_DOCS" || rc=$?
  [ "$rc" -eq 1 ] || fail "PROVA NEGATIVA FALLITA ($1): derivati rigenerati dal grezzo alterato uguali ai versionati (uscita $rc)"
  log "   ok: $1 -> RINORMALIZZAZIONE dal grezzo alterato diversa dai derivati versionati (uscita $rc)"
}
# negativa_gen TIPO "TESTO ATTESO": si altera un file scritto a mano, si RIGENERANO dal legacy (cb2xml compreso) tutti i
# derivati coerenti con l'alterazione, e la verifica deve comunque fallire (uscita 1) per il motivo atteso
negativa_gen() {
  local m rc=0; m="$(mondo "$1")" || fail "alterazione $1 non applicata"
  ( DC_DOCS_IN="$m/docs"; genera "$m/out" "$m/docs" ) > "$tmp/gen-neg.txt" 2>&1 || { cat "$tmp/gen-neg.txt" >&2; fail "rigenerazione dopo l'alterazione $1 fallita"; }
  verifica "$m/out" "$m/docs" "$m/docs" "$m/exp" > "$tmp/neg.txt" 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || { cat "$tmp/neg.txt" >&2; fail "PROVA NEGATIVA FALLITA ($1): con i derivati rigenerati la verifica e' uscita con $rc invece di 1"; }
  grep -qF -- "$2" "$tmp/neg.txt" || { cat "$tmp/neg.txt" >&2; fail "prova negativa ($1): la verifica e' fallita ma non per il motivo atteso ('$2')"; }
  log "   ok: $1 -> derivati rigenerati dal legacy con l'alterazione; verifica uscita con $rc, $(grep -c '^ERRORE' "$tmp/neg.txt") errori, tra cui: $2"
}

# rilievi del giro 1 di validazione: dichiarazioni scritte a mano alterate e derivati rigenerati in modo coerente
negativa_gen frammento-accorciato "ERRORE [censimento] app/cbl/CBIMPORT.cbl WS-ERROR-RECORD: intervallo dichiarato 152-159, nel sorgente la struttura va da 152 a 160"
negativa_gen composizione-eliminata "ERRORE [relazioni] app/cbl/CBTRN02C.cbl:448: MOVE WS-VALIDATION-TRAILER TO VALIDATION-TRAILER (struttura intera verso il record REJECT-RECORD) non coperta da una relazione"
negativa_gen timestamp-eliminato "ERRORE [relazioni] app/cbl/CBTRN02C.cbl:438: MOVE DB2-FORMAT-TS TO TRAN-PROC-TS (struttura intera verso il record TRAN-RECORD) non coperta da una relazione"
negativa_gen timestamp-cbact04c-eliminato "ERRORE [relazioni] app/cbl/CBACT04C.cbl:497: MOVE DB2-FORMAT-TS TO TRAN-ORIG-TS (struttura intera verso il record TRAN-RECORD) non coperta da una relazione"
# rilievo del giro 2: trasferimenti persi dal rilevatore e punti non coperti attribuiti all'istruzione sbagliata
negativa trasferimento-tolto "ERRORE [controprova] app/cbl/CBACT04C.cbl:497: MOVE DB2-FORMAT-TS TO TRAN-ORIG-TS e' un trasferimento di struttura intera che non e' tra i trasferimenti"
negativa non-coperto-spostato "ERRORE [non-coperti] app/cbl/CBACT04C.cbl:464: l'istruzione COMPUTE che inizia a questa riga non ha la destinazione TRAN-AMT"
negativa_gen sezione-errata "ERRORE [censimento] app/cbl/CBACT01C.cbl VBRC-REC1: tipo LINKAGE, ma la riga 123 e' nella sezione WORKING-STORAGE"
negativa_gen file-contratto-scambiato "ERRORE [assegnazioni] file.tsv: AWS.M2.CARDDEMO.TCATBALF.VSAM.KSDS ha contratto CVTRA02Y.DIS-GROUP-RECORD, ma i programmi lo leggono o scrivono con ['CVTRA01Y.TRAN-CAT-BAL-RECORD']"
negativa voce-tracciato-tolta "ERRORE [tracciati] app/cpy/CVACT01Y.cpy ACCOUNT-RECORD: cb2xml ha 13 voci, il sorgente ne ha 14 fino al confine"
negativa composizione-spostata "ERRORE [composizioni] CBTRN02C.WS-VALIDATION-TRAILER -> CBTRN02C.REJECT-RECORD: WS-VALIDATION-FAIL-REASON atteso a offset 350 per 4 byte, generato a 351 per 4"

# completezza (criterio 2)
negativa contratto-cancellato "ERRORE [contratti] contratto mancante: CVTRA05Y.TRAN-RECORD"
negativa radice-cancellata "ERRORE [censimento] app/cpy/CVTRA05Y.cpy: radice di livello 01 trovata da cb2xml e assente dal censimento: TRAN-RECORD"
negativa fd-cancellata "ERRORE [censimento] FD VBRC-FILE di app/cbl/CBACT01C.cbl (riga 80) assente dal censimento"
negativa cbact01c-solo-fd "ERRORE [campi] CBACT01C.VBRC-REC2: 5 righe attese, 1 nel contratto"
negativa cbact01c-solo-fd-censimento "ERRORE [relazioni-attese] CBACT01C.VBRC-REC2: contratto assente"
negativa non-tracciato-falso "ERRORE [censimento] app/cpy/CVACT02Y.cpy: classificato non-tracciato ma cb2xml"
negativa riga-citata-errata "ERRORE [censimento] app/cpy/CVACT01Y.cpy:5: la riga non dichiara l'01 ACCOUNT-RECORD"
# posizioni, somme, REDEFINES (criterio 3)
negativa posizione-alterata "ERRORE [contratti] CVTRA05Y.TRAN-RECORD: buco prima di TRAN-DESC (area -): offset 33, atteso 32"
negativa lunghezza-alterata "ERRORE [contratti] CVTRA03Y.TRAN-TYPE-RECORD: somma delle lunghezze 61 diversa dalla lunghezza del record 60"
negativa ridefinizione-accorciata "ERRORE [contratti] CVEXPORT.EXPORT-RECORD: EXPORT-ACCOUNT-DATA (459 byte) ridefinisce EXPORT-RECORD-DATA (460 byte) e non e' segnalata"
# lunghezze attese (criterio 4)
negativa lunghezza-attesa-alterata "ERRORE [lunghezze] CVTRA05Y.TRAN-RECORD: lunghezza attesa 351, contratto 350"
# tabelle attese: campi scambiati, scala, segno, tipo, chiave spostata (criterio 5)
negativa campi-scambiati "ERRORE [campi] CVACT01Y.ACCOUNT-RECORD riga 5 (ACCT-CREDIT-LIMIT): campo atteso ACCT-CREDIT-LIMIT, contratto ACCT-CASH-CREDIT-LIMIT"
negativa campi-scambiati-ovunque "ERRORE [tracciati] CVACT01Y (riga 8): sorgente ('05', 'ACCT-CREDIT-LIMIT'"
negativa campi-scambiati-senza-attesi "ERRORE [tracciati] contratto CVTRA05Y.TRAN-RECORD: voce 9 diversa dal tracciato di cb2xml"
negativa scala-alterata "ERRORE [campi] CVACT01Y.ACCOUNT-RECORD riga 4 (ACCT-CURR-BAL): scala atteso 2, contratto 3"
negativa scala-alterata-con-pic "ERRORE [campi] CVACT01Y.ACCOUNT-RECORD riga 4 (ACCT-CURR-BAL): scala atteso 2, contratto 3"
negativa segno-alterato "ERRORE [campi] CVTRA01Y.TRAN-CAT-BAL-RECORD riga 6 (TRAN-CAT-BAL): segno atteso S, contratto -"
negativa usage-alterato "ERRORE [contratti] CVEXPORT.EXPORT-RECORD: EXP-ACCT-CURR-BAL PIC S9(10)V99 DISPLAY: 7 byte nel contratto, 12 calcolati dalla PIC"
negativa chiave-spostata "ERRORE [chiavi] AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS chiave primaria -: attesa ('0', '11', 'ACCT-ID', 'esatta'), generata [('1', '11', 'ACCT-ID', 'esatta')]"
negativa chiave-alternativa-spostata "ERRORE [chiavi] CBACT04C chiave alternativa FD-XREF-ACCT-ID: attesa ('25', '11', 'senza WITH DUPLICATES', 'si'), generata ('26', '11', 'senza WITH DUPLICATES', 'si')"
negativa chiave-attesa-spostata "ERRORE [chiavi] AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS chiave primaria -: attesa ('1', '11', 'ACCT-ID', 'esatta'), generata [('0', '11', 'ACCT-ID', 'esatta')]"
# attesi svuotati o accorciati: il contenuto chiesto dai criteri di accettazione deve esserci
negativa attesi-svuotati "ERRORE [attesi] campi.tsv: mancano i campi attesi di CVACT01Y.ACCOUNT-RECORD"
negativa lunghezza-attesa-cancellata "ERRORE [attesi] lunghezze.tsv: CVEXPORT deve valere 500 (criterio di accettazione), trovato None"
negativa discordanza-attesa-cancellata "ERRORE [attesi] discordanze-attese.tsv: manca la discordanza chiesta dalla specifica chiave-unicita:AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX:..."
# relazioni struttura -> FD
negativa relazione-move-mancante "ERRORE [relazioni] app/cbl/CBTRN03C.cbl:295: MOVE FD-REPTFILE-REC non coperta da alcuna relazione"
negativa record-declassato "ERRORE [relazioni] app/cbl/CBSTM03A.CBL righe 388: CUSTREC.CUSTOMER-RECORD e' letto o scritto in un file ma e' classificato ['area-di-lavoro']"
negativa relazione-lunghezza "ERRORE [relazioni] app/cbl/CBACT01C.cbl righe 304: lunghezza_da 40 scritta a mano, cb2xml 39 per CBACT01C.VBRC-REC2"
negativa relazione-mancante "ERRORE [relazioni] app/cbl/CBACT04C.cbl:500: WRITE FD-TRANFILE-REC non coperta da alcuna relazione"
negativa relazione-trasferita "ERRORE [relazioni] app/cbl/CBACT01C.cbl:288: la riga non contiene MOVE 13 TO WS-RECD-LEN"
negativa assegnazione-errata "ERRORE [assegnazioni] app/jcl/INTCALC.jcl:32: la riga non contiene DSN=AWS.M2.CARDDEMO.CARDXREF.VSAM.KSDS"
# discordanze (criterio 6)
negativa discordanza-cancellata "ERRORE [discordanze] discordanza attesa assente da discordanze.md: chiave-unicita:AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX:CBACT04C"
negativa discordanza-non-rilevata "ERRORE [discordanze] discordanza attesa non rilevata dal confronto delle fonti: chiave-allineamento:AWS.M2.CARDDEMO.EXPORT.DATA:app/jcl/CBEXPORT.jcl:30"
negativa discordanza-inventata "ERRORE [discordanze] discordanze.md cita chiave-unicita:AWS.M2.CARDDEMO.TRANSACT.VSAM.AIX:CBTRN02C, che il confronto delle fonti non rileva"
# evidenze mancanti o alterate: il confronto con la rigenerazione dal legacy e la rinormalizzazione dal grezzo
negativa_rig xml-cancellato "Only in $tmp/gen/out/cb2xml: CVACT01Y.xml"
negativa_rig log-cancellato "Only in $tmp/gen/out/cb2xml: CSSETATY.log"
negativa_rig fonte-cancellata "Only in $tmp/gen/out/fonti: listcat.tsv"
negativa_rig contratto-cancellato "Only in $tmp/gen/doc/contratti: CVTRA05Y.TRAN-RECORD.tsv"
negativa_rig campi-scambiati-senza-attesi "CVTRA05Y.TRAN-RECORD.tsv"
negativa_rig scala-alterata "CVACT01Y.ACCOUNT-RECORD.tsv"
negativa_rig chiave-spostata "chiavi.tsv"
negativa_rn xml-alterato
log "data-contract: tutti i controlli superati"
