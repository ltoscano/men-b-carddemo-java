#!/usr/bin/env bash
# Controlli di inventory-cics (issue #22). Rigenera tutto dal legacy in una cartella temporanea, mai dagli output salvati:
#  1. run.sh, check.sh, deps, crosscheck.sh esistono e sono eseguibili; i limiti di tempo funzionano
#  2. gli output rigenerati coincidono con quelli versionati (out/blocchi.tsv, graph-cics.json, inventario-cics.md)
#  3. graph-cics.json e' valido rispetto a graph-cics.schema.json (libreria jsonschema, in container)
#  4. conteggio indipendente (awk) e verify.py: blocchi, comandi, opzioni, bersagli, risoluzione, archi e nodi ricalcolati
#     dal sorgente con un'implementazione separata; attesi scritti a mano dei quattro programmi
#  5. la stessa catena sui file di prova (forme assenti dai quattro programmi), contro i loro attesi scritti a mano
#  6-12. prove negative: ogni alterazione deve far fallire il controllo per il motivo dichiarato
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
schema() { crun "$T_RUN" -v "$DOCS_DIR/graph-cics.schema.json:/s.json:ro" -v "$1:/g.json:ro" "$IMG_JSONSCHEMA" /s.json /g.json; }
schema "$gen/docs/graph-cics.json" > "$tmp/s.out" 2>&1 || { cat "$tmp/s.out" >&2; fail "graph-cics.json non e' valido rispetto allo schema"; }
grep -qx "schema valido" "$tmp/s.out" || fail "risposta del validatore di schema inattesa"

log "4. conteggio indipendente (awk) e verifica dal sorgente (verify.py)"
psh "$gen" -- "sh /analysis/inventory-cics/crosscheck.sh /work/tmp/files.txt" > "$gen/tmp/awk.tsv" || fail "conteggio awk fallito"
verify_legacy() { # verify_legacy GRAPH [AWK] [ATTESI] [SCHEMA] [INVENTARIO.md]   (percorsi visti dal container)
  py "$gen" -- "$(G verify.py)" "$1" /docs/graph.json "${2:-/work/tmp/awk.tsv}" "${3:-/analysis/inventory-cics/expected}" \
    "${4:-/docs/graph-cics.schema.json}" legacy "${5:-/work/docs/inventario-cics.md}"
}
verify_fixture() {
  py "$fx" "${FIXENV[@]}" -- "$(G verify.py)" "$1" "$FXD/graph.json" "${2:-/work/tmp/awk.tsv}" "${3:-$FXD}" \
    "${4:-/docs/graph-cics.schema.json}" fixture "${5:-/work/docs/inventario-cics.md}"
}
out="$(verify_legacy /work/docs/graph-cics.json 2>&1)" || { echo "$out" | tail -20 >&2; fail "verifica di graph-cics.json fallita"; }
log "   $(tail -1 <<<"$out")"
[ "$(grep -c '^blocco' "$gen/tmp/awk.tsv")" -gt 0 ] || fail "il conteggio awk non ha trovato blocchi"

log "5. la stessa catena sui file di prova (WRITE, DELETE, code, START, SEND TEXT, copybook, commenti, costanti modificate)"
cics_generate "$fx" fixture
psh "$fx" LEGACY_ROOT="$FXD/legacy" -- "sh /analysis/inventory-cics/crosscheck.sh /work/tmp/files.txt" > "$fx/tmp/awk.tsv" || fail "conteggio awk sui file di prova fallito"
schema "$fx/docs/graph-cics.json" > "$tmp/s.out" 2>&1 || { cat "$tmp/s.out" >&2; fail "graph-cics.json dei file di prova non e' valido rispetto allo schema"; }
out="$(verify_fixture /work/docs/graph-cics.json 2>&1)" || { echo "$out" | tail -20 >&2; fail "verifica sui file di prova fallita"; }
log "   $(tail -1 <<<"$out")"

log "6. prove negative sul grafo (alterazioni coerenti, come le farebbe una colla sbagliata)"
neg() { # neg NOME ALTERAZIONE MOTIVO-ATTESO [fixture]
  local name="$1" kind="$2" needle="$3" where="${4:-legacy}" d out rc=0
  if [ "$where" = fixture ]; then d="$fx"; else d="$gen"; fi
  rm -f "$d/m.json"
  py "$d" -- "$(G mutate.py)" "$kind" /work/docs/graph-cics.json /work/m.json || fail "alterazione $kind non applicata"
  ! cmp -s "$d/docs/graph-cics.json" "$d/m.json" || fail "prova negativa ($name): l'alterazione non ha cambiato nulla"
  out="$("verify_$where" /work/m.json 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { tail -3 <<<"$out" >&2; fail "PROVA NEGATIVA FALLITA ($name): il controllo e' rimasto verde"; }
  grep -qF -- "$needle" <<<"$out" || { head -5 <<<"$out" >&2; fail "prova negativa ($name): fallita ma non per il motivo atteso ('$needle')"; }
  log "   ok: $name (exit $rc): $(grep -F -- "$needle" <<<"$out" | head -1 | cut -c1-170)"
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

log "7. prove negative sull'estrazione: blocchi.tsv alterato, grafo ricostruito con la colla, poi verificato"
negblk() { # negblk NOME ALTERAZIONE MOTIVO-ATTESO [fixture]
  local name="$1" kind="$2" needle="$3" where="${4:-legacy}" d out rc=0 envs=()
  if [ "$where" = fixture ]; then d="$fx"; envs=("${FIXENV[@]}"); else d="$gen"; fi
  rm -rf "$d/mb" "$d/b.tsv" && mkdir -p "$d/mb"
  py "$d" -- "$(G mutate.py)" "$kind" /work/out/blocchi.tsv /work/b.tsv || fail "alterazione $kind non applicata"
  py "$d" ${envs[@]+"${envs[@]}"} -- "$(G build.py)" /work/b.tsv /work/tmp/regole.txt /work/tmp/proof/app_cbl_FIXCICS.cbl.tsv /work/tmp/diagnostica.tsv /work/mb \
    || fail "prova negativa ($name): la colla non ha ricostruito il grafo"
  out="$("verify_$where" /work/mb/graph-cics.json 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "PROVA NEGATIVA FALLITA ($name): il controllo e' rimasto verde"
  grep -qF -- "$needle" <<<"$out" || { head -5 <<<"$out" >&2; fail "prova negativa ($name): motivo inatteso ('$needle')"; }
  log "   ok: $name (exit $rc): $(grep -F -- "$needle" <<<"$out" | head -1 | cut -c1-170)"
}
negblk "un blocco tolto dall'estrazione" blocchi-meno-uno "app/cbl/COACTUPC.cbl:3921 col 12 (fine 3930, READ): nel grafo 0, nel conteggio indipendente 1"
negblk "un blocco in piu' nell'estrazione" blocchi-piu-uno "app/cbl/COSGN00C.cbl:220 col 12 (fine 220, READ): nel grafo 1, nel conteggio indipendente 0"
negblk "un blocco commentato contato come vero nell'estrazione" blocchi-commento "app/cbl/FIXCICS.cbl:53 col 17 (fine 53, XCTL): nel grafo 1, nel conteggio indipendente 0" fixture

log "8. prove negative sulla risposta dello strumento di estrazione (ProLeap/CicsLister) e del conteggio awk"
negresp() { # negresp NOME COMANDO-SULLA-COPIA MOTIVO-ATTESO
  local name="$1" cmd="$2" needle="$3" out rc=0
  rm -rf "$tmp/rp" && mkdir -p "$tmp/rp" && cp -R "$gen/tmp/resp" "$tmp/rp/resp" && cp "$gen/tmp/files.txt" "$gen/tmp/resp.stdout" "$tmp/rp/"
  ( cd "$tmp/rp/resp" && eval "$cmd" ) || fail "prova negativa ($name): alterazione non applicata"
  out="$(py "$tmp/rp" -- "$(G extract.py)" /work/files.txt /work/resp /work/resp.stdout /work/b.tsv /work/d.tsv 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "PROVA NEGATIVA FALLITA ($name): risposta non valida accettata"
  grep -qF -- "$needle" <<<"$out" || { head -3 <<<"$out" >&2; fail "prova negativa ($name): motivo inatteso ('$needle')"; }
  log "   ok: $name (exit $rc)"
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
log "   ok: risposta di --regole con un token assente rifiutata"
negawk() { # negawk NOME COMANDO-SULLA-COPIA MOTIVO-ATTESO
  local name="$1" cmd="$2" needle="$3" out rc=0
  cp "$gen/tmp/awk.tsv" "$gen/awk-bad.tsv"
  ( cd "$gen" && eval "$cmd" ) || fail "prova negativa ($name): alterazione non applicata"
  out="$(verify_legacy /work/docs/graph-cics.json /work/awk-bad.tsv 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "PROVA NEGATIVA FALLITA ($name): risposta awk non valida accettata"
  grep -qF -- "$needle" <<<"$out" || { head -3 <<<"$out" >&2; fail "prova negativa ($name): motivo inatteso ('$needle')"; }
  log "   ok: $name (exit $rc)"
}
negawk "elenco awk vuoto" ": > awk-bad.tsv" "elenco awk"
negawk "elenco awk senza chiusura" "sed -i.bak '\$d' awk-bad.tsv && rm awk-bad.tsv.bak" "elenco awk incompleto"
negawk "elenco awk con un file in meno dichiarato" "sed -i.bak 's/^fine\\t106\$/fine\\t105/' awk-bad.tsv && rm awk-bad.tsv.bak" "elenco awk incompleto"
negawk "elenco awk troncato" "printf %s \"\$(cat awk-bad.tsv)\" > x && mv x awk-bad.tsv" "troncato"
negawk "elenco awk con un errore" "printf 'errore\\tapp/cbl/COSGN00C.cbl\\t1\\tblocco non chiuso\\n' | cat - awk-bad.tsv > x && mv x awk-bad.tsv" "conteggio awk: errore"
negawk "elenco awk con una riga non riconoscibile" "printf 'garbage\\n' | cat - awk-bad.tsv > x && mv x awk-bad.tsv" "riga non riconoscibile"

log "9. prove negative sulla colla alterata: output rigenerati con la colla sbagliata, poi il controllo completo"
negglue() { # negglue NOME FILE-DELLA-COLLA TESTO-ORIGINALE TESTO-ALTERATO MOTIVO-ATTESO [fixture]
  local name="$1" file="$2" old="$3" new="$4" needle="$5" where="${6:-legacy}" d out rc=0 envs=()
  if [ "$where" = fixture ]; then d="$fx"; envs=("${FIXENV[@]}"); else d="$gen"; fi
  rm -rf "$tmp/ga" && mkdir -p "$tmp/ga/out" "$tmp/ga/docs" && cp -R "$CICS_DIR/glue" "$tmp/ga/glue" && cp -R "$d/tmp" "$tmp/ga/tmp"
  py "$tmp/ga" -- -c "import sys; p, a, b = sys.argv[1:4]; s = open(p).read(); assert s.count(a) == 1, 'testo da alterare non trovato una volta sola'; open(p, 'w').write(s.replace(a, b))" \
    "/work/glue/$file" "$old" "$new" || fail "prova negativa ($name): colla non alterata"
  py "$tmp/ga" ${envs[@]+"${envs[@]}"} -- /work/glue/extract.py /work/tmp/files.txt /work/tmp/resp /work/tmp/resp.stdout /work/out/blocchi.tsv /work/tmp/diagnostica.tsv \
    && py "$tmp/ga" ${envs[@]+"${envs[@]}"} -- /work/glue/build.py /work/out/blocchi.tsv /work/tmp/regole.txt /work/tmp/proof/app_cbl_FIXCICS.cbl.tsv /work/tmp/diagnostica.tsv /work/docs \
    || fail "prova negativa ($name): la colla alterata non ha prodotto gli output"
  cp "$tmp/ga/docs/graph-cics.json" "$d/ga.json" && cp "$tmp/ga/docs/inventario-cics.md" "$d/ga.md"
  out="$("verify_$where" /work/ga.json "" "" "" /work/ga.md 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "PROVA NEGATIVA FALLITA ($name): output della colla alterata accettati"
  grep -qF -- "$needle" <<<"$out" || { head -5 <<<"$out" >&2; fail "prova negativa ($name): motivo inatteso ('$needle')"; }
  log "   ok: $name (exit $rc): $(grep -F -- "$needle" <<<"$out" | head -1 | cut -c1-170)"
}
negglue "build.py: SYNCPOINT tolto dalla categoria transazione" build.py '"SYNCPOINT", "SYNCPOINT ROLLBACK", "ABEND"' '"SYNCPOINT ROLLBACK", "ABEND"' \
  "per il comando SYNCPOINT e' 'transazione'"
negglue "build.py: nessun arco MAPSET" build.py 'if t["risoluzione"] not in RESOLVED:' 'if t["risoluzione"] not in RESOLVED or t["ruolo"] == "MAPSET":' \
  "-> cics-mapset:COSGN00: richiesto dal sorgente 1, presente nel grafo 0"
negglue "build.py: programmi sempre external (tipo sbagliato, nome giusto)" build.py 'tid = "program:" + nm if "program:" + nm in bnodes else "external:" + nm' 'tid = "external:" + nm' \
  "-> program:COADM01C: richiesto dal sorgente 1, presente nel grafo 0"
negglue "build.py: UPDATE letto al contrario" build.py 'upd = "UPDATE" in names' 'upd = "UPDATE" not in names' "nel sorgente UPDATE"
negglue "resolve.py: modifiche ignorate (costanti false)" resolve.py 'mods = self.modifications(self.related(it))' 'mods = []' \
  "FIXCICS.cbl:45: FILE WS-FILE-MOSSO: risoluzione 'costante', per la regola dichiarata 'non_risolto' (modificato)" fixture
negglue "resolve.py: INITIALIZE trattata come lettura" resolve.py 'READ_VERBS = {"IF", "EVALUATE", "WHEN", "UNTIL", "DISPLAY"}' 'READ_VERBS = {"IF", "EVALUATE", "WHEN", "UNTIL", "DISPLAY", "INITIALIZE"}' \
  "FIXCICS.cbl:56: PROGRAM WS-PROG-GRUPPO: risoluzione 'costante'" fixture
negglue "resolve.py: riga della VALUE sbagliata" resolve.py '"file_valore": vf, "riga_valore": vl}' '"file_valore": vf, "riga_valore": vl + 1}' "riga_valore"
negglue "extract.py: l'ultimo blocco di ogni file perso" extract.py '    return blocks, (errs, first_err, resumes)' '    return blocks[:-1], (errs, first_err, resumes)' \
  "nel grafo 0, nel conteggio indipendente 1"
negglue "extract.py: MAP e MAPSET scambiati nei nomi delle opzioni" extract.py 'name = m.group().upper()' 'name = {"MAP": "MAPSET", "MAPSET": "MAP"}.get(m.group().upper(), m.group().upper())' \
  "nel sorgente 'RECEIVE MAP'"
negglue "extract.py: spazi finali tolti dentro i letterali degli operandi" extract.py 'arg = norm_arg(text[j + 1:k])' 'arg = norm_arg(text[j + 1:k]).replace(" '"'"'", "'"'"'")' \
  "app/cbl/FIXCICS.cbl:78: opzioni" fixture
negglue "build.py: conteggio di un comando alterato nel riepilogo" build.py 'w(f"| `{c}` | {k} | {n} |")' 'w(f"| `{c}` | {k} | {n + (c == '"'"'READ'"'"')} |")' \
  "tabella dei comandi diversa dal conteggio indipendente"
negglue "build.py: stato dei bersagli sbagliato nel riepilogo per programma" build.py 'return f"`{a}` ({t['"'"'risoluzione'"'"']})"' 'return f"`{a}` (costante)"' \
  "voci diverse dal ricalcolo"
negglue "build.py: motivo sbagliato nella tabella dei non risolti" build.py "| \`{t['operando']}\` | {t['motivo']} |" "| \`{t['operando']}\` | modificato |" \
  "tabella dei bersagli non risolti diversa dal ricalcolo"

log "10. prove negative sugli attesi scritti a mano (si altera l'atteso, il grafo resta quello vero)"
negexp() { # negexp NOME FILE ESPRESSIONE-SED(o rm) MOTIVO-ATTESO [fixture]
  local name="$1" file="$2" expr="$3" needle="$4" where="${5:-legacy}" d src out rc=0
  if [ "$where" = fixture ]; then d="$fx"; src="$CICS_DIR/fixtures"; else d="$gen"; src="$CICS_DIR/expected"; fi
  rm -rf "$d/exp" && cp -R "$src" "$d/exp"
  if [ "$expr" = rm ]; then rm -f "$d/exp/$file"; else
    sed -i.bak "$expr" "$d/exp/$file" && rm -f "$d/exp/$file.bak"
    ! cmp -s "$d/exp/$file" "$src/$file" || fail "prova negativa ($name): la modifica dell'atteso non ha cambiato nulla"
  fi
  out="$("verify_$where" /work/docs/graph-cics.json "" /work/exp 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "PROVA NEGATIVA FALLITA ($name): atteso alterato ma controllo verde"
  grep -qF -- "$needle" <<<"$out" || { head -5 <<<"$out" >&2; fail "prova negativa ($name): motivo inatteso ('$needle')"; }
  log "   ok: $name (exit $rc)"
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

log "11. prove negative sui file versionati (si altera il versionato, il rigenerato resta quello vero)"
negver() { # negver NOME COMANDO (eseguito su una copia in $tmp/ver)
  local name="$1"; shift
  rm -rf "$tmp/ver" && mkdir -p "$tmp/ver" && cp "$CICS_DIR/out/blocchi.tsv" "$DOCS_DIR/graph-cics.json" "$DOCS_DIR/inventario-cics.md" "$tmp/ver/"
  ( cd "$tmp/ver" && eval "$@" ) || fail "prova negativa ($name): alterazione non applicata"
  if cmp -s "$tmp/ver/blocchi.tsv" "$CICS_DIR/out/blocchi.tsv" && cmp -s "$tmp/ver/graph-cics.json" "$DOCS_DIR/graph-cics.json" \
     && cmp -s "$tmp/ver/inventario-cics.md" "$DOCS_DIR/inventario-cics.md"; then fail "prova negativa ($name): l'alterazione non ha cambiato nulla"; fi
  ! cmp_versioned "$tmp/ver/blocchi.tsv" "$tmp/ver/graph-cics.json" "$tmp/ver/inventario-cics.md" 2> /dev/null \
    || fail "PROVA NEGATIVA FALLITA ($name): versionato alterato ma il confronto con il rigenerato e' verde"
  log "   ok: $name"
}
negver "blocchi.tsv: una riga tolta" "sed -i.bak '5d' blocchi.tsv && rm blocchi.tsv.bak"
negver "graph-cics.json: una riga alterata" "sed -i.bak 's/\"riga\": 98,/\"riga\": 99,/' graph-cics.json && rm graph-cics.json.bak"
negver "inventario-cics.md: una cifra alterata" "sed -i.bak 's/\\*\\*240\\*\\*/**241**/' inventario-cics.md && rm inventario-cics.md.bak"

log "12. prove negative dello schema e della copertura degli attributi"
py "$gen" -- -c "import json; g = json.load(open('/work/docs/graph-cics.json')); del g['occorrenze'][0]['comando']; json.dump(g, open('/work/bad.json', 'w'))"
if schema "$gen/bad.json" > "$tmp/s.out" 2>&1; then fail "PROVA NEGATIVA FALLITA (schema): un'occorrenza senza comando e' stata accettata"; fi
grep -q "SCHEMA" "$tmp/s.out" || fail "prova negativa dello schema: motivo inatteso"
log "   ok: occorrenza senza comando rifiutata dallo schema"
py "$gen" -- -c "import json; s = json.load(open('/docs/graph-cics.schema.json')); s['\$defs']['bersaglio']['properties']['nuovo_attributo'] = {'type': 'string'}; json.dump(s, open('/work/schema-plus.json', 'w'))"
rc=0; out="$(verify_legacy /work/docs/graph-cics.json "" "" /work/schema-plus.json 2>&1)" || rc=$?
[ "$rc" -ne 0 ] && grep -qF "attributo dello schema non coperto: bersaglio.nuovo_attributo" <<<"$out" \
  || fail "PROVA NEGATIVA FALLITA: un attributo nuovo dello schema non fa fallire il controllo"
log "   ok: attributo nuovo dello schema non coperto rifiutato (exit $rc)"
log "inventory-cics: tutti i controlli superati"
