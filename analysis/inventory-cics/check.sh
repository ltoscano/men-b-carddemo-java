#!/usr/bin/env bash
# Controlli di inventory-cics (issue #22). Rigenera tutto dal legacy in una cartella temporanea, mai dagli output salvati:
#  1. run.sh, check.sh, deps, crosscheck.sh esistono e sono eseguibili; i limiti di tempo funzionano
#  2. gli output rigenerati coincidono con quelli versionati (out/blocchi.tsv, graph-cics.json, inventario-cics.md)
#  3. graph-cics.json e' valido rispetto a graph-cics.schema.json (libreria jsonschema, in container)
#  4. conteggio indipendente (awk) e verify.py: risposte grezze, estrazione, occorrenze, bersagli, risoluzione, archi, nodi e
#     riepilogo ricalcolati dal sorgente con un'implementazione separata; attesi scritti a mano dei quattro programmi
#  5. la stessa catena sui file di prova (forme assenti dai quattro programmi), contro i loro attesi scritti a mano
#  6-14. prove negative: ogni alterazione deve far fallire il controllo per il motivo dichiarato, riportato nel log
# La risposta di OGNI invocazione di verify.py e del validatore di schema e' validata (vstate, sstate): completa, nel formato
# atteso e con una conclusione coerente con il codice di uscita. Una risposta vuota, malformata o troncata e' un errore.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/inventory-cics/lib.sh"
require_legacy
[ -f "$MANIFEST" ] || fail "manifesto assente: eseguire prima './analysis/run.sh manifest'"
[ -f "$DOCS_DIR/graph.json" ] || fail "docs/legacy-map/graph.json assente: eseguire prima './analysis/run.sh inventory'"
ensure_legacy_volume
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT
gen="$tmp/gen"
fx="$tmp/fx"
FXD=/analysis/inventory-cics/fixtures

# ---------------------------------------------------------------------- risposte degli strumenti nostri, validate
VPASS='^verifica superata: [0-9]+ occorrenze, [0-9]+ archi, [0-9]+ nodi nuovi; [0-9]+ blocchi nel conteggio indipendente$'
VFAIL='^VERIFICA FALLITA: ([0-9]+) difetti$'
vstate() { # vstate CODICE RISPOSTA -> "pass" | "fail" | "invalida (...)"
  local rc="$1" out="$2" last n
  last="$(printf '%s\n' "$out" | tail -n 1)"
  n="$(printf '%s\n' "$out" | grep -c '^VERIFICA: ' || true)"
  if [ "$rc" -eq 0 ] && [[ "$last" =~ $VPASS ]] && [ "$n" -eq 0 ]; then echo pass
  elif [ "$rc" -eq 1 ] && [[ "$last" =~ $VFAIL ]] && [ "${BASH_REMATCH[1]}" -eq "$n" ] && [ "$n" -ge 1 ]; then echo fail
  else echo "invalida (uscita $rc, ultima riga '${last:0:90}', $n righe VERIFICA)"; fi
}
sstate() { # sstate CODICE RISPOSTA -> "pass" | "fail" | "invalida (...)"   (validatore jsonschema dell'immagine di #2)
  local rc="$1" out="$2" last n
  last="$(printf '%s\n' "$out" | tail -n 1)"
  n="$(printf '%s\n' "$out" | grep -c '^SCHEMA: ' || true)"
  if [ "$rc" -eq 0 ] && [ "$last" = "schema valido" ] && [ "$n" -eq 0 ]; then echo pass
  elif [ "$rc" -eq 1 ] && [[ "$last" =~ ^[0-9]+\ errori\ di\ schema$ ]] && [ "$n" -ge 1 ]; then echo fail
  else echo "invalida (uscita $rc, ultima riga '${last:0:90}', $n righe SCHEMA)"; fi
}
# verify_legacy / verify_fixture GRAPH [AWK] [ATTESI] [SCHEMA] [INVENTARIO.md] [BLOCCHI] [CARTELLA-STRUMENTO]
# (percorsi visti dal container; /work e' $gen, $fx o $VDIR). VFAKE: codice Python che sostituisce verify.py (prove sulla risposta).
verify_legacy() {
  local d="${VDIR:-$gen}"
  if [ -n "${VFAKE:-}" ]; then py "$d" -- -c "$VFAKE"; return; fi
  py "$d" -- "$(G verify.py)" "$1" /docs/graph.json "${2:-/work/tmp/awk.tsv}" "${3:-/analysis/inventory-cics/expected}" \
    "${4:-/docs/graph-cics.schema.json}" legacy "${5:-/work/docs/inventario-cics.md}" "${6:-/work/out/blocchi.tsv}" "${7:-/work/tmp}"
}
verify_fixture() {
  local d="${VDIR:-$fx}"
  if [ -n "${VFAKE:-}" ]; then py "$d" "${FIXENV[@]}" -- -c "$VFAKE"; return; fi
  py "$d" "${FIXENV[@]}" -- "$(G verify.py)" "$1" "$FXD/graph.json" "${2:-/work/tmp/awk.tsv}" "${3:-$FXD}" \
    "${4:-/docs/graph-cics.schema.json}" fixture "${5:-/work/docs/inventario-cics.md}" "${6:-/work/out/blocchi.tsv}" "${7:-/work/tmp}"
}
vrun() { # vrun legacy|fixture ARGOMENTI...: imposta VRC, VOUT, VSTATE
  local where="$1"; shift
  VRC=0; VOUT="$("verify_$where" "$@" 2>&1)" || VRC=$?
  VSTATE="$(vstate "$VRC" "$VOUT")"
}
schema() { # schema GRAPH-HOST. SFAKE: codice Python che sostituisce il validatore (prove sulla risposta)
  if [ -n "${SFAKE:-}" ]; then crun "$T_RUN" "$GLUE_IMAGE" python -I -c "$SFAKE"; return; fi
  crun "$T_RUN" -v "$DOCS_DIR/graph-cics.schema.json:/s.json:ro" -v "$1:/g.json:ro" "$IMG_JSONSCHEMA" /s.json /g.json
}
srun() { SRC=0; SOUT="$(schema "$1" 2>&1)" || SRC=$?; SSTATE="$(sstate "$SRC" "$SOUT")"; }
reason() { grep -F -- "$1" <<<"$2" | head -1 | cut -c1-190; }
expect_fail() { # expect_fail NOME MOTIVO-ATTESO: dopo vrun, la verifica deve essere conclusa con fallimento, per quel motivo
  local name="$1" needle="$2"
  case "$VSTATE" in
    pass) tail -3 <<<"$VOUT" >&2; fail "PROVA NEGATIVA FALLITA ($name): il controllo e' rimasto verde" ;;
    fail) ;;
    *) tail -5 <<<"$VOUT" >&2; fail "prova negativa ($name): risposta della verifica non valida: $VSTATE" ;;
  esac
  grep -qF -- "$needle" <<<"$VOUT" || { head -5 <<<"$VOUT" >&2; fail "prova negativa ($name): fallita ma non per il motivo atteso ('$needle')"; }
  log "   ok: $name (exit $VRC): $(reason "$needle" "$VOUT")"
}

log "1. file dell'analisi presenti ed eseguibili; limite di tempo"
for f in run.sh check.sh deps crosscheck.sh; do
  [ -f "$CICS_DIR/$f" ] && [ -x "$CICS_DIR/$f" ] && [ -s "$CICS_DIR/$f" ] || fail "analysis/inventory-cics/$f manca, non e' eseguibile o e' vuoto"
done
[ -f "$DOCS_DIR/graph-cics.schema.json" ] || fail "docs/legacy-map/graph-cics.schema.json manca"
start=$SECONDS; rc=0
crun 3 "$GLUE_IMAGE" sleep 60 > "$tmp/to.out" 2>&1 || rc=$?
[ "$rc" -eq 124 ] && [ $((SECONDS - start)) -lt 30 ] && grep -q "limite di 3s superato" "$tmp/to.out" \
  || fail "il limite di tempo non interrompe un container che resta in attesa (uscita $rc, $((SECONDS - start))s)"
log "   ok: un container che non termina viene fermato dal limite di tempo (uscita 124 in $((SECONDS - start))s)"

log "2. rigenerazione dal legacy in una cartella temporanea"
cics_generate "$gen"
cmp_versioned() { # cmp_versioned BLOCCHI GRAPH MD: 0 se coincidono con i file rigenerati
  cmp -s "$gen/out/blocchi.tsv" "$1" || { echo "out/blocchi.tsv versionato diverso dal rigenerato" >&2; return 1; }
  cmp -s "$gen/docs/graph-cics.json" "$2" || { echo "graph-cics.json versionato diverso dal rigenerato" >&2; return 1; }
  cmp -s "$gen/docs/inventario-cics.md" "$3" || { echo "inventario-cics.md versionato diverso dal rigenerato" >&2; return 1; }
}
[ -f "$CICS_DIR/out/blocchi.tsv" ] || fail "analysis/inventory-cics/out/blocchi.tsv assente: eseguire prima './analysis/run.sh inventory-cics'"
[ "$(ls "$CICS_DIR/out")" = "blocchi.tsv" ] || fail "analysis/inventory-cics/out contiene file non prodotti dalla rigenerazione: $(ls "$CICS_DIR/out" | tr '\n' ' ')"
cmp_versioned "$CICS_DIR/out/blocchi.tsv" "$DOCS_DIR/graph-cics.json" "$DOCS_DIR/inventario-cics.md" \
  || fail "gli output versionati non coincidono con quelli rigenerati dal legacy"
log "   out/blocchi.tsv, graph-cics.json e inventario-cics.md identici al rigenerato"

log "3. validazione di graph-cics.json rispetto allo schema"
with_timeout "$T_BUILD" docker build -q -t "$IMG_JSONSCHEMA" "$ANALYSIS_ROOT/inventory/docker/jsonschema" > /dev/null || fail "build dell'immagine $IMG_JSONSCHEMA fallita"
srun "$gen/docs/graph-cics.json"
[ "$SSTATE" = pass ] || { echo "$SOUT" | tail -5 >&2; fail "graph-cics.json: validazione di schema non superata o risposta non valida: $SSTATE"; }
log "   $(tail -1 <<<"$SOUT")"

log "4. conteggio indipendente (awk) e verifica dal sorgente (verify.py)"
psh "$gen" -- "sh /analysis/inventory-cics/crosscheck.sh /work/tmp/files.txt" > "$gen/tmp/awk.tsv" || fail "conteggio awk fallito"
[ "$(grep -c '^blocco' "$gen/tmp/awk.tsv" || true)" -gt 0 ] || fail "il conteggio awk non ha trovato blocchi"
vrun legacy /work/docs/graph-cics.json
[ "$VSTATE" = pass ] || { echo "$VOUT" | tail -20 >&2; fail "verifica di graph-cics.json non superata o risposta non valida: $VSTATE"; }
log "   $(tail -1 <<<"$VOUT")"

log "5. la stessa catena sui file di prova (forme assenti dal legacy, catene di REDEFINES, opzioni CICS di uscita)"
cics_generate "$fx" fixture
psh "$fx" LEGACY_ROOT="$FXD/legacy" -- "sh /analysis/inventory-cics/crosscheck.sh /work/tmp/files.txt" > "$fx/tmp/awk.tsv" || fail "conteggio awk sui file di prova fallito"
srun "$fx/docs/graph-cics.json"
[ "$SSTATE" = pass ] || { echo "$SOUT" | tail -5 >&2; fail "graph-cics.json dei file di prova: schema non superato o risposta non valida: $SSTATE"; }
log "   $(tail -1 <<<"$SOUT")"
vrun fixture /work/docs/graph-cics.json
[ "$VSTATE" = pass ] || { echo "$VOUT" | tail -20 >&2; fail "verifica sui file di prova non superata o risposta non valida: $VSTATE"; }
log "   $(tail -1 <<<"$VOUT")"

log "6. prove sulla risposta di verify.py e del validatore di schema (vuota, malformata, troncata, incoerente con l'uscita)"
FAKES_V=(
  "vuota con uscita 0|import sys; sys.exit(0)"
  "vuota con uscita 1|import sys; sys.exit(1)"
  "malformata con uscita 0|print('ok')"
  "troncata (difetti senza conclusione) con uscita 1|import sys; print('VERIFICA: a'); print('VERIFICA: b'); sys.exit(1)"
  "troncata (conclusione con 3 difetti, 1 riga) con uscita 1|import sys; print('VERIFICA: a'); print('VERIFICA FALLITA: 3 difetti'); sys.exit(1)"
  "superata con un difetto e uscita 0|print('VERIFICA: a'); print('verifica superata: 1 occorrenze, 1 archi, 1 nodi nuovi; 1 blocchi nel conteggio indipendente')"
  "superata con uscita 1|import sys; print('verifica superata: 1 occorrenze, 1 archi, 1 nodi nuovi; 1 blocchi nel conteggio indipendente'); sys.exit(1)"
)
for where in legacy fixture; do
  for fk in "${FAKES_V[@]}"; do
    VFAKE="${fk#*|}" vrun "$where" /work/docs/graph-cics.json
    case "$VSTATE" in invalida*) ;; *) fail "PROVA NEGATIVA FALLITA (risposta di verify.py ${fk%%|*}, $where): accettata come '$VSTATE'" ;; esac
    log "   ok: verify.py ($where), risposta ${fk%%|*}: rifiutata, $VSTATE"
  done
done
FAKES_S=(
  "vuota con uscita 0|import sys; sys.exit(0)"
  "malformata con uscita 0|print('ok')"
  "'schema valido' con uscita 1|import sys; print('schema valido'); sys.exit(1)"
  "errori dichiarati senza righe SCHEMA|import sys; print('2 errori di schema'); sys.exit(1)"
  "troncata (righe SCHEMA senza conclusione)|import sys; print('SCHEMA: a x'); sys.exit(1)"
)
for g in "$gen/docs/graph-cics.json" "$fx/docs/graph-cics.json"; do
  for fk in "${FAKES_S[@]}"; do
    SFAKE="${fk#*|}" srun "$g"
    case "$SSTATE" in invalida*) ;; *) fail "PROVA NEGATIVA FALLITA (risposta del validatore di schema ${fk%%|*}): accettata come '$SSTATE'" ;; esac
    log "   ok: validatore di schema (${g#"$tmp/"}), risposta ${fk%%|*}: rifiutata, $SSTATE"
  done
done

log "7. prove negative sul grafo (alterazioni coerenti, come le farebbe una colla sbagliata)"
neg() { # neg NOME ALTERAZIONE MOTIVO-ATTESO [fixture]
  local name="$1" kind="$2" needle="$3" where="${4:-legacy}" d
  if [ "$where" = fixture ]; then d="$fx"; else d="$gen"; fi
  rm -f "$d/m.json"
  py "$d" -- "$(G mutate.py)" "$kind" /work/docs/graph-cics.json /work/m.json || fail "alterazione $kind non applicata"
  ! cmp -s "$d/docs/graph-cics.json" "$d/m.json" || fail "prova negativa ($name): l'alterazione non ha cambiato nulla"
  vrun "$where" /work/m.json
  expect_fail "$name" "$needle"
}
neg "comando classificato in un'altra categoria (SYNCPOINT -> altro)" categoria-syncpoint "categoria 'altro', per il comando SYNCPOINT e' 'transazione'"
neg "READ classificato 'altro', bersagli e archi tolti in modo coerente" categoria-read-coerente "categoria 'altro', per il comando READ e' 'file'"
neg "bersaglio letterale cambiato, arco coerente" letterale-cambiato "nome 'COMEN01C', nel sorgente 'COADM01C'"
neg "arco eliminato con l'occorrenza conservata (nodo di graph.json)" arco-tolto-base "-> program:COADM01C: richiesto dal sorgente 1, presente nel grafo 0"
neg "arco eliminato con l'occorrenza conservata (nodo nuovo)" arco-tolto-nuovo "-> cics-file:ACCTDAT: richiesto dal sorgente 1, presente nel grafo 0"
neg "bersagli dei due READ UPDATE di COACTUPC scambiati" scambio-read-update "app/cbl/COACTUPC.cbl:3894: bersagli"
neg "solo i bersagli degli archi dei due READ UPDATE scambiati" scambio-solo-archi "-> cics-file:CUSTDAT: richiesto dal sorgente 0, presente nel grafo 1"
neg "dato valorizzato con MOVE fatto passare per costante (COCRDLIC:538)" move-come-costante "risoluzione 'costante', per la regola dichiarata 'non_risolto' (senza-value-letterale)"
neg "dato con VALUE modificato da una MOVE fatto passare per costante" modificato-come-costante "risoluzione 'costante', per la regola dichiarata 'non_risolto' (modificato)" fixture
neg "dato modificato attraverso una catena di due REDEFINES fatto passare per costante" redefines-catena-costante "FIXRDEF.cbl:49: PROGRAM WS-PGM: risoluzione 'costante', per la regola dichiarata 'non_risolto' (modificato)" fixture
neg "dato scritto da ASSIGN PROGRAM fatto passare per costante" assign-costante "FIXRDEF.cbl:54: PROGRAM WS-PGM-A: risoluzione 'costante', per la regola dichiarata 'non_risolto' (modificato)" fixture
neg "costante lasciata non risolta (l'unico LINK)" costante-non-risolta "risoluzione 'non_risolto', per la regola dichiarata 'costante'"
neg "READ e READ UPDATE scambiati" read-update-scambiati "update True, nel sorgente UPDATE assente"
neg "MAP e MAPSET scambiati" map-mapset-scambiati "app/cbl/COSGN00C.cbl:110: bersagli"
neg "arco verso un nodo inesistente" arco-nodo-inesistente "il nodo cics-file:NONESISTE non esiste"
neg "occorrenza duplicata sulla stessa riga (altra colonna)" occorrenza-doppia-riga "nel grafo 1, nel conteggio indipendente 0"
neg "occorrenza duplicata identica" occorrenza-doppia-identica "presente 2 volte"
neg "blocco in una riga di commento contato come vero" commento-come-blocco "la riga di EXEC e' un commento" fixture
neg "bersaglio con il nome giusto e il tipo sbagliato (program -> external)" tipo-bersaglio-external "-> external:COADM01C: richiesto dal sorgente 0, presente nel grafo 1"
neg "TRANSID verso external invece che transaction" tipo-bersaglio-transazione "-> external:CC00: richiesto dal sorgente 0, presente nel grafo 1"
neg "bersaglio di tipo sbagliato fra i nodi nuovi (mapset -> file)" categoria-mappa-file "-> cics-file:COSGN00: richiesto dal sorgente 0, presente nel grafo 1"
neg "riga della VALUE spostata" riga-valore "riga_valore 38, nel sorgente 37"
neg "letterale della VALUE alterato" valore "valore \"'USRSEC'\", nel sorgente \"'USRSEC  '\""
neg "un'opzione tolta" opzione-tolta "diverse dal sorgente"
neg "argomento di un'opzione alterato" argomento "diverse dal sorgente"
neg "riga di END-EXEC alterata" riga-fine "app/cbl/COSGN00C.cbl:211 col 12 (fine 220, READ): nel grafo 1, nel conteggio indipendente 0"
neg "comando cambiato (XCTL -> LINK)" comando "comando 'LINK', nel sorgente 'XCTL'"
neg "motivo di un non risolto alterato" motivo "motivo 'modificato', per la regola dichiarata 'senza-value-letterale'"
neg "modifica citata che non e' una modifica" modifica-falsa "non e' una modifica secondo la regola" fixture
neg "mapset di un nodo mappa alterato" nodo-mapset "diversi da quelli ricavati dall'identificativo"
neg "origine di un nodo external alterata" nodo-origine "diversi da quelli ricavati dall'identificativo" fixture
neg "nodo nuovo senza archi" nodo-orfano "nodo cics-file:ORFANO: nessun arco entrante"
neg "nodo nuovo presente due volte" nodo-doppio "presente 2 volte"
neg "nodo dichiarato qui ma gia' in graph.json" nodo-gia-in-base "esiste gia' in graph.json"
neg "arco presente due volte" arco-doppio "presente 2 volte"
neg "occorrenza attribuita a un altro programma" da-sbagliato "da program:COMEN01C, atteso program:COSGN00C"

log "8. prove negative sull'estrazione: confronto diretto fra estrazione, occorrenze, risposte dello strumento e sorgente"
negblk() { # negblk NOME ALTERAZIONE MOTIVO-ATTESO [fixture]: estrazione alterata e grafo ricostruito dalla colla
  local name="$1" kind="$2" needle="$3" where="${4:-legacy}" d envs=()
  if [ "$where" = fixture ]; then d="$fx"; envs=("${FIXENV[@]}"); else d="$gen"; fi
  rm -rf "$d/mb" "$d/b.tsv" && mkdir -p "$d/mb"
  py "$d" -- "$(G mutate.py)" "$kind" /work/out/blocchi.tsv /work/b.tsv || fail "alterazione $kind non applicata"
  py "$d" ${envs[@]+"${envs[@]}"} -- "$(G build.py)" /work/b.tsv /work/tmp/regole.txt /work/tmp/proof/app_cbl_FIXCICS.cbl.tsv /work/tmp/diagnostica.tsv /work/mb \
    || fail "prova negativa ($name): la colla non ha ricostruito il grafo"
  vrun "$where" /work/mb/graph-cics.json "" "" "" /work/mb/inventario-cics.md /work/b.tsv
  expect_fail "$name" "$needle"
}
negblk "un blocco tolto dall'estrazione, grafo ricostruito" blocchi-meno-uno "estrazione e conteggio indipendente divergono su app/cbl/COACTUPC.cbl:3921"
negblk "un blocco in piu' nell'estrazione, grafo ricostruito" blocchi-piu-uno "app/cbl/COSGN00C.cbl:220 col 12 (fine 220, READ): nel grafo 1, nel conteggio indipendente 0"
negblk "un blocco commentato contato come vero nell'estrazione" blocchi-commento "app/cbl/FIXCICS.cbl:53 col 17 (fine 53, XCTL): nel grafo 1, nel conteggio indipendente 0" fixture
negblk "un'opzione alterata nell'estrazione, grafo ricostruito" blocchi-opzione "risposta dello strumento ed estrazione divergono su app/cbl/COSGN00C.cbl:211"
negext() { # negext NOME ALTERAZIONE MOTIVO-ATTESO: estrazione alterata, grafo quello vero (difetto assorbito dal costruttore)
  local name="$1" kind="$2" needle="$3"
  rm -f "$gen/b.tsv"
  py "$gen" -- "$(G mutate.py)" "$kind" /work/out/blocchi.tsv /work/b.tsv || fail "alterazione $kind non applicata"
  vrun legacy /work/docs/graph-cics.json "" "" "" "" /work/b.tsv
  expect_fail "$name" "$needle"
}
negext "blocco duplicato dall'estrattore e tolto dal costruttore (COTRN02C:156)" blocchi-doppio "estrazione e occorrenze divergono su app/cbl/COTRN02C.cbl:156 col 12 (RETURN): record in blocchi.tsv 2, occorrenze nel grafo 1"
negext "blocco perso dall'estrattore e reintegrato dal costruttore (COACTUPC:3921)" blocchi-meno-uno "estrazione e occorrenze divergono su app/cbl/COACTUPC.cbl:3921 col 12 (READ): record in blocchi.tsv 0, occorrenze nel grafo 1"
negext "opzione alterata nell'estrazione e corretta dal costruttore" blocchi-opzione "estrazione e occorrenze divergono su app/cbl/COSGN00C.cbl:211"
negtool() { # negtool NOME COMANDO-SULLA-COPIA MOTIVO-ATTESO: risposte grezze, diagnostica o regole alterate, il resto vero
  local name="$1" cmd="$2" needle="$3"
  rm -rf "$tmp/rq" && mkdir -p "$tmp/rq" && cp -R "$gen/tmp" "$gen/out" "$gen/docs" "$tmp/rq/"
  ( cd "$tmp/rq/tmp" && eval "$cmd" ) || fail "prova negativa ($name): alterazione non applicata"
  VDIR="$tmp/rq" vrun legacy /work/docs/graph-cics.json
  expect_fail "$name" "$needle"
}
negtool "risposta dello strumento con un blocco in meno e chiusura coerente" \
  "awk 'BEGIN{FS=OFS=\"\\t\"} NR==3{next} /^#fine/{\$2=\$2-1} {print}' resp/app_cbl_COSGN00C.cbl.tsv > x && mv x resp/app_cbl_COSGN00C.cbl.tsv" \
  "risposta dello strumento ed estrazione divergono su app/cbl/COSGN00C.cbl:110"
negtool "risposta dello strumento malformata" "printf 'TRUNCATED\\n' > resp/app_cbl_COSGN00C.cbl.tsv" "risposta di CicsLister per app/cbl/COSGN00C.cbl mancante, incompleta o malformata"
negtool "diagnostica alterata (blocchi dopo il primo errore)" "sed -i.bak 's/\\t10\$/\\t9/' diagnostica.tsv && rm diagnostica.tsv.bak" "diagnostica.tsv diversa dalla chiusura delle risposte"
negtool "regole di ProLeap alterate" "sed -i.bak 's/^token\\tCICS\\tpresente\$/token\\tCICS\\tassente/' regole.txt && rm regole.txt.bak" "tabella delle regole di ProLeap diversa da regole.txt"
negtool "elenco dei file dato allo strumento senza un file" "sed -i.bak '1d' files.txt && rm files.txt.bak" "elenco dei file dati allo strumento diverso dal manifesto"

log "9. prove negative sulla risposta dello strumento di estrazione (ProLeap/CicsLister), rifiutata da extract.py"
negresp() { # negresp NOME COMANDO-SULLA-COPIA MOTIVO-ATTESO
  local name="$1" cmd="$2" needle="$3" out rc=0
  rm -rf "$tmp/rp" && mkdir -p "$tmp/rp" && cp -R "$gen/tmp/resp" "$tmp/rp/resp" && cp "$gen/tmp/files.txt" "$gen/tmp/resp.stdout" "$tmp/rp/"
  ( cd "$tmp/rp/resp" && eval "$cmd" ) || fail "prova negativa ($name): alterazione non applicata"
  out="$(py "$tmp/rp" -- "$(G extract.py)" /work/files.txt /work/resp /work/resp.stdout /work/b.tsv /work/d.tsv 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "PROVA NEGATIVA FALLITA ($name): risposta non valida accettata"
  grep -qF -- "$needle" <<<"$out" || { head -3 <<<"$out" >&2; fail "prova negativa ($name): motivo inatteso ('$needle')"; }
  log "   ok: $name (exit $rc): $(reason "$needle" "$out")"
}
Z=app_cpy_CSUTLDPY.cpy.tsv      # copybook senza blocchi: la risposta valida e' intestazione + chiusura
S=app_cbl_COSGN00C.cbl.tsv
printf 'riga\triga_fine\tcolonna\ttesto\n#fine\t0\t0\t0\t0\t0\n' | cmp -s - "$gen/tmp/resp/$Z" || fail "la risposta su CSUTLDPY (senza blocchi) non e' intestazione + chiusura"
negresp "risposta vuota (file senza blocchi)" ": > $Z" "risposta vuota"
negresp "risposta sostituita da testo (file senza blocchi)" "printf 'TRUNCATED INVALID RESPONSE\\n' > $Z" "intestazione"
negresp "risposta senza chiusura (file senza blocchi)" "printf 'riga\\triga_fine\\tcolonna\\ttesto\\n' > $Z" "manca la chiusura"
negresp "risposta troncata (senza fine riga finale)" "printf %s \"\$(cat $S)\" > x && mv x $S" "troncata"
negresp "una riga tolta, chiusura invariata" "awk 'NR!=3' $S > x && mv x $S" "la chiusura dichiara 10 blocchi, le righe sono 9"
negresp "riga di dati non riconoscibile" "awk 'NR==3{print \"garbage\"; next} {print}' $S > x && mv x $S" "non riconoscibile: riga"
negresp "testo di un blocco non riconoscibile" "awk 'BEGIN{FS=OFS=\"\\t\"} NR==3{\$4=\" READ (((\"} {print}' $S > x && mv x $S" "testo del blocco non riconoscibile"
negresp "posizione incoerente (riga_fine < riga)" "awk 'BEGIN{FS=OFS=\"\\t\"} NR==3{\$2=1} {print}' $S > x && mv x $S" "posizione incoerente"
negresp "blocchi incompleti dichiarati dallo strumento" "awk 'BEGIN{FS=OFS=\"\\t\"} /^#fine/{\$6=1} {print}' $S > x && mv x $S" "riconosciuti solo in parte"
negresp "risposta mancante" "rm $Z" "risposte mancanti"
negresp "risposta in piu' (file non nell'elenco)" "cp $S app_cbl_INVENTATO.cbl.tsv" "risposte non attese"
negresp "lo strumento non dichiara tutti i file" "printf 'file analizzati\\t3\\n' > ../resp.stdout" "non dichiara di aver analizzato"
check_rules() { printf 'regola\texecCicsStatement\ntoken\tEXEC\tpresente\ntoken\tCICS\tpresente\ntoken\tEND_EXEC\tpresente\n' | cmp -s - "$1"; }
check_rules "$gen/tmp/regole.txt" || fail "risposta di 'CicsLister --regole' inattesa"
sed 's/presente$/assente/' "$gen/tmp/regole.txt" > "$tmp/regole-bad.txt"
! check_rules "$tmp/regole-bad.txt" || fail "PROVA NEGATIVA FALLITA: una risposta di --regole con un token assente e' accettata"
log "   ok: risposta di --regole con un token assente rifiutata: $(diff "$gen/tmp/regole.txt" "$tmp/regole-bad.txt" | grep '^>' | head -1)"

log "10. prove negative sulla risposta del conteggio awk, rifiutata da verify.py"
negawk() { # negawk NOME COMANDO-SULLA-COPIA MOTIVO-ATTESO
  local name="$1" cmd="$2" needle="$3"
  cp "$gen/tmp/awk.tsv" "$gen/awk-bad.tsv"
  ( cd "$gen" && eval "$cmd" ) || fail "prova negativa ($name): alterazione non applicata"
  vrun legacy /work/docs/graph-cics.json /work/awk-bad.tsv
  expect_fail "$name" "$needle"
}
negawk "elenco awk vuoto" ": > awk-bad.tsv" "elenco awk"
negawk "elenco awk senza chiusura" "sed -i.bak '\$d' awk-bad.tsv && rm awk-bad.tsv.bak" "elenco awk incompleto"
negawk "elenco awk con un file in meno dichiarato" "sed -i.bak 's/^fine\\t106\$/fine\\t105/' awk-bad.tsv && rm awk-bad.tsv.bak" "elenco awk incompleto"
negawk "elenco awk troncato" "printf %s \"\$(cat awk-bad.tsv)\" > x && mv x awk-bad.tsv" "troncato"
negawk "elenco awk con un errore" "printf 'errore\\tapp/cbl/COSGN00C.cbl\\t1\\tblocco non chiuso\\n' | cat - awk-bad.tsv > x && mv x awk-bad.tsv" "conteggio awk: errore"
negawk "elenco awk con una riga non riconoscibile" "printf 'garbage\\n' | cat - awk-bad.tsv > x && mv x awk-bad.tsv" "riga non riconoscibile"

log "11. prove negative sulla colla alterata: output rigenerati con la colla sbagliata, poi il controllo completo"
negglue() { # negglue NOME MOTIVO-ATTESO legacy|fixture FILE TESTO-ORIGINALE TESTO-ALTERATO [FILE ORIGINALE ALTERATO ...]
  local name="$1" needle="$2" where="$3" d envs=()
  shift 3
  if [ "$where" = fixture ]; then d="$fx"; envs=("${FIXENV[@]}"); else d="$gen"; fi
  rm -rf "$tmp/ga" && mkdir -p "$tmp/ga/out" "$tmp/ga/docs" && cp -R "$CICS_DIR/glue" "$tmp/ga/glue" && cp -R "$d/tmp" "$tmp/ga/tmp"
  while [ $# -ge 3 ]; do
    py "$tmp/ga" -- -c "import sys; p, a, b = sys.argv[1:4]; s = open(p).read(); assert s.count(a) == 1, 'testo da alterare non trovato una volta sola'; open(p, 'w').write(s.replace(a, b))" \
      "/work/glue/$1" "$2" "$3" || fail "prova negativa ($name): colla non alterata ($1)"
    shift 3
  done
  py "$tmp/ga" ${envs[@]+"${envs[@]}"} -- /work/glue/extract.py /work/tmp/files.txt /work/tmp/resp /work/tmp/resp.stdout /work/out/blocchi.tsv /work/tmp/diagnostica.tsv \
    && py "$tmp/ga" ${envs[@]+"${envs[@]}"} -- /work/glue/build.py /work/out/blocchi.tsv /work/tmp/regole.txt /work/tmp/proof/app_cbl_FIXCICS.cbl.tsv /work/tmp/diagnostica.tsv /work/docs \
    || fail "prova negativa ($name): la colla alterata non ha prodotto gli output"
  VDIR="$tmp/ga" vrun "$where" /work/docs/graph-cics.json
  expect_fail "$name" "$needle"
}
negglue "build.py: SYNCPOINT tolto dalla categoria transazione" "per il comando SYNCPOINT e' 'transazione'" legacy \
  build.py '"SYNCPOINT", "SYNCPOINT ROLLBACK", "ABEND"' '"SYNCPOINT ROLLBACK", "ABEND"'
negglue "build.py: nessun arco MAPSET" "-> cics-mapset:COSGN00: richiesto dal sorgente 1, presente nel grafo 0" legacy \
  build.py 'if t["risoluzione"] not in RESOLVED:' 'if t["risoluzione"] not in RESOLVED or t["ruolo"] == "MAPSET":'
negglue "build.py: programmi sempre external (tipo sbagliato, nome giusto)" "-> program:COADM01C: richiesto dal sorgente 1, presente nel grafo 0" legacy \
  build.py 'tid = "program:" + nm if "program:" + nm in bnodes else "external:" + nm' 'tid = "external:" + nm'
negglue "build.py: UPDATE letto al contrario" "nel sorgente UPDATE" legacy build.py 'upd = "UPDATE" in names' 'upd = "UPDATE" not in names'
negglue "resolve.py: modifiche ignorate (costanti false)" "FIXCICS.cbl:45: FILE WS-FILE-MOSSO: risoluzione 'costante', per la regola dichiarata 'non_risolto' (modificato)" fixture \
  resolve.py 'mods = self.modifications(self.related(it))' 'mods = []'
negglue "resolve.py: INITIALIZE trattata come lettura" "FIXCICS.cbl:56: PROGRAM WS-PROG-GRUPPO: risoluzione 'costante'" fixture \
  resolve.py 'READ_VERBS = {"IF", "EVALUATE", "WHEN", "UNTIL", "DISPLAY"}' 'READ_VERBS = {"IF", "EVALUATE", "WHEN", "UNTIL", "DISPLAY", "INITIALIZE"}'
negglue "resolve.py: REDEFINES seguite per un solo passaggio" "FIXRDEF.cbl:49: PROGRAM WS-PGM: risoluzione 'costante', per la regola dichiarata 'non_risolto' (modificato)" fixture \
  resolve.py 'region = set(self.ancestors(it)) | set(self.subtree(it))' 'region = set(self.ancestors(it)) | set(self.subtree(it)); start = set(region)' \
  resolve.py 'if y in region or z in region:' 'if y in start or z in start:'
negglue "resolve.py: sola lettura dedotta dal solo nome dell'opzione (ASSIGN PROGRAM)" "FIXRDEF.cbl:54: PROGRAM WS-PGM-A: risoluzione 'costante', per la regola dichiarata 'non_risolto' (modificato)" fixture \
  resolve.py 'whole = len(arg) == 1 and (cmd, opt) in READ_ONLY' 'whole = len(arg) == 1 and opt in {o for c, o in READ_ONLY}'
negglue "resolve.py: riga della VALUE sbagliata" "riga_valore" legacy resolve.py '"file_valore": vf, "riga_valore": vl}' '"file_valore": vf, "riga_valore": vl + 1}'
negglue "extract.py: l'ultimo blocco di ogni file perso" "nel grafo 0, nel conteggio indipendente 1" legacy \
  extract.py '    return blocks, (errs, first_err, resumes)' '    return blocks[:-1], (errs, first_err, resumes)'
negglue "extract.py duplica COTRN02C:156 e build.py deduplica (controesempio del Validatore)" "estrazione e occorrenze divergono su app/cbl/COTRN02C.cbl:156 col 12 (RETURN): record in blocchi.tsv 2, occorrenze nel grafo 1" legacy \
  extract.py '        blocks.append((a, b, col, cmd, opts))' '        blocks.append((a, b, col, cmd, opts))
        if rel == "app/cbl/COTRN02C.cbl" and a == 156:
            blocks.append((a, b, col, cmd, opts))' \
  build.py '            rows.append((p, int(a), int(b), int(c), cmd, [tuple(x) for x in json.loads(opts)]))' '            if not any(r[:4] == (p, int(a), int(b), int(c)) for r in rows):
                rows.append((p, int(a), int(b), int(c), cmd, [tuple(x) for x in json.loads(opts)]))'
negglue "extract.py: MAP e MAPSET scambiati nei nomi delle opzioni" "nel sorgente 'RECEIVE MAP'" legacy \
  extract.py 'name = m.group().upper()' 'name = {"MAP": "MAPSET", "MAPSET": "MAP"}.get(m.group().upper(), m.group().upper())'
negglue "extract.py: spazi finali tolti dentro i letterali degli operandi" "app/cbl/FIXCICS.cbl:78: opzioni" fixture \
  extract.py 'arg = norm_arg(text[j + 1:k])' 'arg = norm_arg(text[j + 1:k]).replace(" '"'"'", "'"'"'")'
negglue "build.py: conteggio di un comando alterato nel riepilogo" "tabella dei comandi diversa dal conteggio indipendente" legacy \
  build.py 'w(f"| `{c}` | {k} | {n} |")' 'w(f"| `{c}` | {k} | {n + (c == '"'"'READ'"'"')} |")'
negglue "build.py: stato dei bersagli sbagliato nel riepilogo per programma" "voci diverse dal ricalcolo" legacy \
  build.py 'return f"`{a}` ({t['"'"'risoluzione'"'"']})"' 'return f"`{a}` (costante)"'
negglue "build.py: motivo sbagliato nella tabella dei non risolti" "tabella dei bersagli non risolti diversa dal ricalcolo" legacy \
  build.py "| \`{t['operando']}\` | {t['motivo']} |" "| \`{t['operando']}\` | modificato |"
negglue "build.py: tabella degli errori di sintassi di ProLeap alterata" "tabella degli errori di sintassi di ProLeap diversa dalle risposte" legacy \
  build.py 'w(f"| {d[0]} | {d[1]} | {d[2]} | {d[3]} | {d[4]} |")' 'w(f"| {d[0]} | {d[1]} | {d[2]} | {d[3]} | {int(d[4]) + 1} |")'

log "12. prove negative sugli attesi scritti a mano (si altera l'atteso, il grafo resta quello vero)"
negexp() { # negexp NOME FILE ESPRESSIONE-SED(o rm) MOTIVO-ATTESO [fixture]
  local name="$1" file="$2" expr="$3" needle="$4" where="${5:-legacy}" d src
  if [ "$where" = fixture ]; then d="$fx"; src="$CICS_DIR/fixtures"; else d="$gen"; src="$CICS_DIR/expected"; fi
  rm -rf "$d/exp" && cp -R "$src" "$d/exp"
  if [ "$expr" = rm ]; then rm -f "$d/exp/$file"; else
    sed -i.bak "$expr" "$d/exp/$file" && rm -f "$d/exp/$file.bak"
    ! cmp -s "$d/exp/$file" "$src/$file" || fail "prova negativa ($name): la modifica dell'atteso non ha cambiato nulla"
  fi
  vrun "$where" /work/docs/graph-cics.json "" /work/exp
  expect_fail "$name" "$needle"
}
negexp "arco atteso di COSGN00C" blocchi_COSGN00C.tsv 's#program:COADM01C#program:COADM01X#' "blocchi_COSGN00C.tsv: riga 9"
negexp "riga della VALUE attesa di COCRDLIC" blocchi_COCRDLIC.tsv 's#COCRDLIC.cbl:214#COCRDLIC.cbl:213#' "blocchi_COCRDLIC.tsv: riga 7"
negexp "blocco atteso tolto (COACTUPC)" blocchi_COACTUPC.tsv '/\t4099\t/d' "blocchi_COACTUPC.tsv: riga 14"
negexp "modalita attesa di COACTUPC" blocchi_COACTUPC.tsv 's#3894\t3903\tREAD\tfile\tmodalita=lettura-update#3894\t3903\tREAD\tfile\tmodalita=lettura#' "blocchi_COACTUPC.tsv: riga 10"
negexp "stato atteso del LINK di COPAUS1C" blocchi_COPAUS1C.tsv 's#costante COPAUS2C#letterale COPAUS2C#' "blocchi_COPAUS1C.tsv: riga 2"
negexp "file degli attesi mancante" blocchi_COPAUS1C.tsv rm "manca il file degli attesi a mano blocchi_COPAUS1C.tsv"
negexp "totale atteso dei blocchi" totali.tsv 's/^blocchi\t240$/blocchi\t241/' "totali: blocchi scritto a mano 241, conteggio indipendente 240"
negexp "motivo atteso sui file di prova" blocchi_FIXCICS.tsv 's#!definito-piu-volte#!occurs#' "blocchi_FIXCICS.tsv: riga 17" fixture
negexp "conteggio atteso sui file di prova" conteggi.tsv 's#FIXCICS.cbl\t34#FIXCICS.cbl\t35#' "conteggi.tsv: app/cbl/FIXCICS.cbl scritto a mano 35" fixture
negexp "stato atteso della catena di REDEFINES (FIXRDEF)" blocchi_FIXRDEF.tsv '2s#non_risolto !modificato#costante FIXTGT @app/cbl/FIXRDEF.cbl:6#' "blocchi_FIXRDEF.tsv: riga 1" fixture
negexp "file degli attesi di FIXRDEF mancante" blocchi_FIXRDEF.tsv rm "manca il file degli attesi a mano blocchi_FIXRDEF.tsv" fixture

log "13. prove negative sui file versionati (si altera il versionato, il rigenerato resta quello vero)"
negver() { # negver NOME COMANDO (eseguito su una copia in $tmp/ver)
  local name="$1"; shift
  local why
  rm -rf "$tmp/ver" && mkdir -p "$tmp/ver" && cp "$CICS_DIR/out/blocchi.tsv" "$DOCS_DIR/graph-cics.json" "$DOCS_DIR/inventario-cics.md" "$tmp/ver/"
  ( cd "$tmp/ver" && eval "$@" ) || fail "prova negativa ($name): alterazione non applicata"
  if cmp -s "$tmp/ver/blocchi.tsv" "$CICS_DIR/out/blocchi.tsv" && cmp -s "$tmp/ver/graph-cics.json" "$DOCS_DIR/graph-cics.json" \
     && cmp -s "$tmp/ver/inventario-cics.md" "$DOCS_DIR/inventario-cics.md"; then fail "prova negativa ($name): l'alterazione non ha cambiato nulla"; fi
  if why="$(cmp_versioned "$tmp/ver/blocchi.tsv" "$tmp/ver/graph-cics.json" "$tmp/ver/inventario-cics.md" 2>&1)"; then
    fail "PROVA NEGATIVA FALLITA ($name): versionato alterato ma il confronto con il rigenerato e' verde"
  fi
  [ -n "$why" ] || fail "prova negativa ($name): confronto fallito senza motivo"
  log "   ok: $name: $why"
}
negver "blocchi.tsv: una riga tolta" "sed -i.bak '5d' blocchi.tsv && rm blocchi.tsv.bak"
negver "graph-cics.json: una riga alterata" "sed -i.bak 's/\"riga\": 98,/\"riga\": 99,/' graph-cics.json && rm graph-cics.json.bak"
negver "inventario-cics.md: una cifra alterata" "sed -i.bak 's/\\*\\*240\\*\\*/**241**/' inventario-cics.md && rm inventario-cics.md.bak"

log "14. prove negative dello schema e della copertura degli attributi"
py "$gen" -- -c "import json; g = json.load(open('/work/docs/graph-cics.json')); del g['occorrenze'][0]['comando']; json.dump(g, open('/work/bad.json', 'w'))"
srun "$gen/bad.json"
[ "$SSTATE" = fail ] || fail "PROVA NEGATIVA FALLITA (schema): un'occorrenza senza comando non e' stata rifiutata ($SSTATE)"
grep -q "^SCHEMA: occorrenze/0 .*'comando'" <<<"$SOUT" || { echo "$SOUT" | head -3 >&2; fail "prova negativa dello schema: motivo inatteso"; }
log "   ok: occorrenza senza comando rifiutata dallo schema (exit $SRC): $(grep '^SCHEMA:' <<<"$SOUT" | head -1 | cut -c1-150)"
py "$gen" -- -c "import json; s = json.load(open('/docs/graph-cics.schema.json')); s['\$defs']['bersaglio']['properties']['nuovo_attributo'] = {'type': 'string'}; json.dump(s, open('/work/schema-plus.json', 'w'))"
vrun legacy /work/docs/graph-cics.json "" "" /work/schema-plus.json
expect_fail "attributo nuovo dello schema non coperto" "attributo dello schema non coperto: bersaglio.nuovo_attributo"
log "inventory-cics: tutti i controlli superati"
