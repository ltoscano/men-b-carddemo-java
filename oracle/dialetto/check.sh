#!/usr/bin/env bash
# Controllo della sonda semantica sul dialetto (PERFPRB, perform-osvs).
# Atteso scritto a mano dalla regola di perform-osvs (vedi il commento di oracle/tests/PERFPRB.cbl):
# B, C, D, DONE, codice 0; ambiente del programma uguale a quello fissato.
# 1. Riesegue la sonda in una cartella nuova. 2. Confronta.
# 3. Prove negative:
#    - PERFPRB compilato da una copia di compile.sh che aggiunge all'ambiente fissato di cobc
#      COB_CONFIG_DIR verso una configurazione con perform-osvs: no: l'output cambia e il controllo fallisce;
#    - controprova: la mutazione del Validatore (giro 2, PR #29), cioe' la stessa configurazione solo
#      esportata nello script di compilazione, non arriva a cobc (env -i): l'output resta quello atteso;
#    - alterazioni delle evidenze.
. "$ORACLE_ROOT/lib.sh"

EXP="$ORACLE_ROOT/dialetto/expected"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

verifica() {
  local obs="$1" errs=0 f
  for f in PERFPRB.txt PERFPRB.ambiente; do
    if [ ! -f "$obs/$f" ]; then echo "$f: assente"; errs=$((errs + 1))
    elif ! diff -u "$EXP/$f" "$obs/$f" > "$tmp/d"; then
      echo "$f: diverso dall'atteso:"; indent "$tmp/d"; errs=$((errs + 1)); fi
  done
  [ "$errs" -eq 0 ] || { echo "verifica fallita: $errs differenze"; return 1; }
  echo "verifica riuscita: PERFORM con perform-osvs (B C D DONE), ambiente fissato"
}

# variante NOME MUTAZIONE-SED: compila PERFPRB con una copia alterata di compile.sh e lo esegue.
variante() {
  local name="$1" expr="$2"
  mkdir -p "$tmp/$name/build"
  cp "$ORACLE_ROOT/build/compile.sh" "$tmp/$name/compile.sh"
  mutate "$tmp/$name/compile.sh" "$expr"
  orun -v "$tmp/$name/build:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh "$(in_container "$tmp/$name/compile.sh")" uno eseguibile /oracle/tests/PERFPRB.cbl PERFPRB /out \
    > "$tmp/$name.log" 2>&1 || { indent "$tmp/$name.log" >&2; fail "compilazione della variante '$name' fallita"; }
  DIALETTO_BIN_DIR="$tmp/$name/build/bin" DIALETTO_OUT_DIR="$tmp/$name/obs" bash "$ORACLE_ROOT/dialetto/run.sh" \
    >> "$tmp/$name.log" 2>&1 || { indent "$tmp/$name.log" >&2; fail "esecuzione della variante '$name' fallita"; }
}

log "1. sonda sul dialetto rieseguita in una cartella nuova"
DIALETTO_OUT_DIR="$tmp/obs" bash "$ORACLE_ROOT/dialetto/run.sh" || fail "sonda sul dialetto fallita"

log "2. confronto con gli attesi"
verifica "$tmp/obs" > "$tmp/v.out" 2>&1 || { cat "$tmp/v.out" >&2; fail "la sonda sul dialetto non da' l'esito atteso"; }
indent "$tmp/v.out" >&2

log "3. prove negative"
config_alternativa "$tmp/alt"
alt="$(in_container "$tmp/alt")"
grep -qx 'perform-osvs: no' "$tmp/alt/ibm.conf" || fail "la configurazione alternativa non contiene perform-osvs: no"
variante cfg-cobc "s#^\. /oracle/ambiente\.sh\$#. /oracle/ambiente.sh; AMBIENTE_COBC=\"\$AMBIENTE_COBC COB_CONFIG_DIR=$alt\"#"
expect_fail "configurazione alternativa (perform-osvs: no) passata a cobc" "+AFTER-INNER" verifica "$tmp/cfg-cobc/obs"
variante cfg-export "s#^\. /oracle/ambiente\.sh\$#. /oracle/ambiente.sh; export COB_CONFIG_DIR=$alt#"
verifica "$tmp/cfg-export/obs" > "$tmp/cfg-export.out" 2>&1 \
  || { indent "$tmp/cfg-export.out" >&2; fail "la configurazione esportata dallo script di compilazione e' arrivata a cobc"; }
log "   controprova ok: COB_CONFIG_DIR esportato nello script di compilazione non arriva a cobc (B C D DONE)"
mkdir -p "$tmp/alt-obs"; cp "$tmp/obs/PERFPRB.txt" "$tmp/obs/PERFPRB.ambiente" "$tmp/alt-obs/"
mutate "$tmp/alt-obs/PERFPRB.txt" 's/^DONE$/E/'
expect_fail "riga DONE alterata" "PERFPRB.txt: diverso" verifica "$tmp/alt-obs"
mkdir -p "$tmp/manca"; cp "$tmp/obs/PERFPRB.txt" "$tmp/manca/"
expect_fail "ambiente di PERFPRB non registrato" "PERFPRB.ambiente: assente" verifica "$tmp/manca"
log "controllo superato"
