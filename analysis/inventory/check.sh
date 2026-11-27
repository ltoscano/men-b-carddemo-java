#!/usr/bin/env bash
# Controlli dell'inventario (issue #2). Rigenera tutto dal legacy in una cartella temporanea e non parte mai dagli output salvati:
#  1. run.sh, check.sh, deps esistono e sono eseguibili
#  2. gli output rigenerati coincidono con quelli versionati (out/, graph.json, inventario.md)
#  3. graph.json e' valido rispetto a graph.schema.json (libreria jsonschema, in container)
#  4. conteggi indipendenti (Python, e awk senza Python), riga di ogni occorrenza, livelli JCL, attesi scritti a mano
#  5. prove negative: ogni alterazione dell'output o dell'atteso deve far fallire il controllo, per il motivo atteso
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/inventory/lib.sh"
require_legacy
[ -f "$MANIFEST" ] || fail "manifesto assente: eseguire prima './analysis/run.sh manifest'"
ensure_legacy_volume
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT
gen="$tmp/gen"

log "1. file dell'analisi presenti ed eseguibili"
for f in run.sh check.sh deps; do
  [ -f "$INV_DIR/$f" ] && [ -x "$INV_DIR/$f" ] && [ -s "$INV_DIR/$f" ] || fail "analysis/inventory/$f manca, non e' eseguibile o e' vuoto"
done
[ -f "$DOCS_DIR/graph.schema.json" ] || fail "docs/legacy-map/graph.schema.json manca"

log "2. rigenerazione dal legacy in una cartella temporanea"
inv_generate "$gen"

# cmp_versioned OUTDIR GRAPH MD: ritorna 0 se coincidono con i file generati
cmp_versioned() {
  diff -r "$gen/out" "$1" > "$tmp/diff.txt" 2>&1 || { head -5 "$tmp/diff.txt" >&2; return 1; }
  cmp -s "$gen/docs/graph.json" "$2" || { echo "graph.json versionato diverso dal rigenerato" >&2; return 1; }
  cmp -s "$gen/docs/inventario.md" "$3" || { echo "inventario.md versionato diverso dal rigenerato" >&2; return 1; }
}
[ -d "$INV_DIR/out" ] || fail "analysis/inventory/out assente: eseguire prima './analysis/run.sh inventory'"
cmp_versioned "$INV_DIR/out" "$DOCS_DIR/graph.json" "$DOCS_DIR/inventario.md" || fail "gli output versionati non coincidono con quelli rigenerati dal legacy"
log "   out/ ($(ls "$INV_DIR/out" | wc -l | tr -d ' ') file), graph.json e inventario.md identici al rigenerato"

log "3. validazione di graph.json rispetto allo schema"
build_image "$IMG_JSONSCHEMA" "$INV_DIR/docker/jsonschema"
schema() { docker run --rm -v "$DOCS_DIR/graph.schema.json:/s.json:ro" -v "$1:/g.json:ro" "$IMG_JSONSCHEMA" /s.json /g.json; }
schema "$gen/docs/graph.json" || fail "graph.json non e' valido rispetto allo schema"

log "4. conteggi indipendenti, righe, livelli, attesi a mano (verify.py)"
verify() { # verify GRAPH(in /work) [EXPECTED(in container)]
  psh "$gen" "python -I $(G verify.py) $1 /work/tmp/counts.json /work/out ${2:-/analysis/inventory/expected}"
}
verify /work/docs/graph.json | tail -3 >&2 || fail "verifica del grafo fallita"
# secondo conteggio, senza Python (awk), contro quello di Python
{ for t in cobol copybook jcl proc csd; do manifest_of "$t" | awk -v t="$t" '{print t "\t" $0}'; done; } > "$gen/tmp/files.tsv"
psh "$gen" "sh /analysis/inventory/crosscheck.sh /work/tmp/files.tsv" > "$gen/tmp/awk.tsv" || fail "conteggio awk fallito"
py "$gen" "$(G counts_tsv.py)" /work/tmp/counts.json > "$gen/tmp/py.tsv"
cmp -s "$gen/tmp/awk.tsv" "$gen/tmp/py.tsv" || { diff "$gen/tmp/awk.tsv" "$gen/tmp/py.tsv" | head >&2; fail "i conteggi awk e Python divergono"; }
log "   conteggio awk = conteggio Python su $(wc -l < "$gen/tmp/awk.tsv" | tr -d ' ') valori"
# il conteggio non puo' essere vuoto o banale
[ "$(awk -F'\t' '$1=="exec" && $2 ~ /\/jcl\// {s+=$3} END{print s+0}' "$gen/tmp/awk.tsv")" = 119 ] || fail "somma EXEC dei file jcl (awk) diversa da 119"
[ "$(awk -F'\t' '$1=="dd" && $2 ~ /\/jcl\// {s+=$3} END{print s+0}' "$gen/tmp/awk.tsv")" = 480 ] || fail "somma DD dei file jcl (awk) diversa da 480"

log "5. prove negative sul grafo (ogni alterazione deve far fallire verify.py per il motivo atteso)"
neg() { # neg NOME KIND NEEDLE
  local name="$1" kind="$2" needle="$3" out rc=0
  out="$(psh "$gen" "python -I $(G mutate.py) $kind /work/docs/graph.json /work/m.json && python -I $(G verify.py) /work/m.json /work/tmp/counts.json /work/out /analysis/inventory/expected" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "$out" | tail -3 >&2; fail "PROVA NEGATIVA FALLITA ($name): il controllo e' rimasto verde"; }
  echo "$out" | grep -q -- "$needle" || { echo "$out" | head -5 >&2; fail "prova negativa ($name): fallito ma non per il motivo atteso ('$needle')"; }
  log "   ok: $name (exit $rc)"
}
neg "rimozione di tutte le COPY" drop-copy-category "COPY: app/cbl/CBACT01C.cbl: occorrenze nel grafo 0"
neg "rimozione di tutte le DD" drop-dd-category "JCL: app/jcl/POSTTRAN.jcl: passo POSTTRAN/STEP15 (riga 23): DD nel grafo 0, nel sorgente 9"
neg "rimozione di tutte le transazioni" drop-transaction-category "transazioni: app/csd/CARDDEMO.CSD: nel grafo 0"
neg "rimozione di una COPY di CBACT04C" drop-occurrence "COPY: app/cbl/CBACT04C.cbl: occorrenze nel grafo 4, conteggio indipendente sul sorgente 5"
neg "rimozione di una COPY di COBIL00C (atteso a mano)" drop-occurrence-handwritten "edges_COBIL00C.tsv: manca"
neg "riga di una CALL di CBSTM03A alterata" alter-line "non contiene l'istruzione"
neg "riga di una COPY di COBIL00C alterata (atteso a mano)" alter-line-handwritten "edges_COBIL00C.tsv"
neg "due COPY di CSSETATY con REPLACING diversi fuse in una" merge-replacing "COPY: app/cbl/COACTUPC.cbl: occorrenze nel grafo 55, conteggio indipendente sul sorgente 56"
neg "TRANEXTR spostato al livello A senza che mapa lo analizzi" level-b-to-a "dichiarato livello A ma mapa riporta 0 passi"
neg "una DD di livello job attribuita a un passo" jobdd-to-step "DD a livello di job nel grafo"
neg "DD marcata livello passo ma sul job" dd-job-level-marked-step "fonte/livello inattesi"
neg "una DD di POSTTRAN rimossa" drop-dd-occurrence "POSTTRAN.jcl: passo POSTTRAN/STEP15 (riga 23): DD nel grafo 8, nel sorgente 9"
neg "PARM di INTCALC alterato" alter-parm "contains_parm.tsv"

log "6. prove negative sugli attesi scritti a mano (si altera l'atteso, il grafo resta quello vero)"
negexp() { # negexp NOME FILE SED-EXPR NEEDLE
  local name="$1" file="$2" expr="$3" needle="$4" out rc=0
  rm -rf "$gen/exp" && cp -R "$INV_DIR/expected" "$gen/exp"
  if [ "$expr" = "rm" ]; then rm -f "$gen/exp/$file"; else sed -i.bak "$expr" "$gen/exp/$file" && rm -f "$gen/exp/$file.bak"; cmp -s "$gen/exp/$file" "$INV_DIR/expected/$file" && fail "prova negativa ($name): la mutazione dell'atteso non ha cambiato nulla"; fi
  out="$(psh "$gen" "python -I $(G verify.py) /work/docs/graph.json /work/tmp/counts.json /work/out /work/exp" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "PROVA NEGATIVA FALLITA ($name): atteso alterato ma il controllo e' verde"
  echo "$out" | grep -q -- "$needle" || { echo "$out" | head -5 >&2; fail "prova negativa ($name): fallito ma non per il motivo atteso ('$needle')"; }
  log "   ok: $name (exit $rc)"
}
negexp "riga di una COPY attesa di CBTRN02C" edges_CBTRN02C.tsv 's/\t107\t/\t108\t/' "edges_CBTRN02C.tsv"
negexp "destinazione di una CALL attesa di CBACT01C" edges_CBACT01C.tsv 's/asm:COBDATFT/asm:COBDATFX/' "edges_CBACT01C.tsv"
negexp "sostituzioni attese di CSSETATY in COACTUPC" contains_COACTUPC.tsv 's/ACCT-STATUS/ACCT-STATUZ/' "contains_COACTUPC.tsv"
negexp "generazione GDG attesa di DALYREJS in POSTTRAN" jcl_POSTTRAN.tsv 's/\t+1\tpasso/\t-1\tpasso/' "jcl_POSTTRAN.tsv"
negexp "tipo del passo atteso di CREASTMT (PGM -> PROC)" jcl_CREASTMT.tsv 's/\tPGM\tCBSTM03A/\tPROC\tCBSTM03A/' "jcl_CREASTMT.tsv"
negexp "DD attesa di TRANEXTR" jcl_TRANEXTR.tsv '/\tDD02\t/d' "jcl_TRANEXTR.tsv"
negexp "dataset atteso di una DD di TRANREPT" jcl_TRANREPT.tsv 's/dataset:AWS.M2.CARDDEMO.DATEPARM/dataset:AWS.M2.CARDDEMO.DATEPARX/' "jcl_TRANREPT.tsv"
negexp "passo della procedura attesa REPROC" jcl_REPROC.tsv 's/\tIDCAMS\t/\tIDCAMX\t/' "jcl_REPROC.tsv"
negexp "programma atteso di una transazione del CSD" csd_CARDDEMO.tsv 's/program:COBIL00C/program:COBIL00X/' "csd_CARDDEMO.tsv"
negexp "elenco atteso dei file al livello B (un file in meno)" livello_b.tsv '/TXT2PDF1/d' "livello B"
negexp "elenco atteso dei file al livello B (un file in piu)" livello_b.tsv 's#^app/jcl/TXT2PDF1.JCL#app/jcl/ACCTFILE.jcl#' "livello B"
negexp "totale atteso delle DD" totali.tsv 's/^DD\t480/DD\t481/' "totali"
negexp "riga dell'anomalia manuale di CREASTMT" anomalie_manuali.tsv 's/\t90\t/\t89\t/' "anomalia manuale"
negexp "file degli attesi a mano mancante" edges_COBIL00C.tsv rm "manca il file degli attesi"

log "7. prove negative sui file versionati (si altera il versionato, il rigenerato resta quello vero)"
negver() { # negver NOME COMANDO-DI-ALTERAZIONE (eseguito su una copia in $tmp/ver)
  local name="$1"; shift
  rm -rf "$tmp/ver" && mkdir -p "$tmp/ver/docs" && cp -R "$INV_DIR/out" "$tmp/ver/out" && cp "$DOCS_DIR/graph.json" "$DOCS_DIR/inventario.md" "$tmp/ver/docs/"
  ( cd "$tmp/ver" && eval "$@" )
  if diff -rq "$INV_DIR/out" "$tmp/ver/out" > /dev/null 2>&1 && cmp -s "$DOCS_DIR/graph.json" "$tmp/ver/docs/graph.json" && cmp -s "$DOCS_DIR/inventario.md" "$tmp/ver/docs/inventario.md"; then
    fail "prova negativa ($name): l'alterazione non ha cambiato nulla"
  fi
  if cmp_versioned "$tmp/ver/out" "$tmp/ver/docs/graph.json" "$tmp/ver/docs/inventario.md" > /dev/null 2>&1; then
    fail "PROVA NEGATIVA FALLITA ($name): versionato alterato ma il confronto con il rigenerato e' verde"
  fi
  log "   ok: $name"
}
negver "output di ProLeap: una riga COPY tolta da out/copy.tsv" "sed -i.bak '5d' out/copy.tsv && rm out/copy.tsv.bak"
negver "output di cobol-migration-toolkit: un nome cambiato in out/cmt_calls.tsv" "sed -i.bak 's/CEE3ABD/CEE3ABX/' out/cmt_calls.tsv && rm out/cmt_calls.tsv.bak"
negver "output di mapa: un DISP cambiato in out/mapa_dd.tsv" "sed -i.bak '3s/SHR/MOD/' out/mapa_dd.tsv && rm out/mapa_dd.tsv.bak"
negver "output delle schede: un valore cambiato in out/cards.tsv" "sed -i.bak '10s/DD/XX/' out/cards.tsv && rm out/cards.tsv.bak"
negver "un file di out/ cancellato (livelli JCL)" "rm out/jcl_livelli.tsv"
negver "un file in piu' in out/" "echo x > out/extra.tsv"
negver "graph.json: una riga alterata" "sed -i.bak 's/\"riga\": 89\$/\"riga\": 90/' docs/graph.json && rm docs/graph.json.bak"
negver "inventario.md: una cifra alterata" "sed -i.bak 's/| program | /| program | 9/' docs/inventario.md && rm docs/inventario.md.bak"

log "8. prove negative sulle procedure presentate a mapa"
( INV_FAULT=proc-byte; export INV_FAULT; inv_stage_procs "$tmp/procfault" > "$tmp/pf.out" 2>&1 ) && fail "PROVA NEGATIVA FALLITA (procedura con un byte diverso): la verifica e' passata"
grep -q "non e' identica all'originale" "$tmp/pf.out" || { cat "$tmp/pf.out" >&2; fail "prova negativa (procedura con un byte diverso): fallita ma non per il motivo atteso"; }
log "   ok: una procedura copiata con un byte diverso viene rifiutata"
mkdir -p "$tmp/procextra/procs" && cp "$gen/tmp/procs"/* "$tmp/procextra/procs/" && echo x > "$tmp/procextra/procs/INVENTATA"
py "$tmp/procextra" "$(G stage_procs.py)" verify /work/procs > "$tmp/pe.out" 2>&1 && fail "PROVA NEGATIVA FALLITA (procedura in piu'): la verifica e' passata"
log "   ok: una procedura in piu' viene rifiutata"
py "$gen" "$(G stage_procs.py)" verify /work/tmp/procs > /dev/null || fail "le procedure usate nella rigenerazione non sono identiche agli originali"

log "9. prova negativa dello schema (graph.json senza un campo obbligatorio)"
py "$gen" -c "import json;g=json.load(open('/work/docs/graph.json'));del g['nodi'][0]['file'];json.dump(g,open('/work/bad.json','w'))"
if schema "$gen/bad.json" > "$tmp/s.out" 2>&1; then fail "PROVA NEGATIVA FALLITA (schema): un nodo program senza file e' stato accettato"; fi
grep -q "SCHEMA" "$tmp/s.out" || fail "prova negativa dello schema: motivo inatteso"
log "   ok: nodo senza file rifiutato dallo schema"
log "inventory: tutti i controlli superati"
