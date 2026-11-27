#!/usr/bin/env bash
# Controllo dell'avviatore.
# Atteso, scritto a mano (oracle/avviatore/expected/):
#   - PARMDUMP.hex: i 12 byte dell'area del PARM come li vede un programma con la LINKAGE di CBACT04C:
#     lunghezza 10 su due byte big-endian (00 0a) seguita dal testo ASCII 2022071800 (32 30 32 32 30 37 31 38 30 30);
#   - PARMECHO.txt: codice 0, PARM-LENGTH letto dal programma uguale a 10, PARM-DATE uguale al testo.
# 1. Riesegue la prova in una cartella nuova. 2. Confronta byte e rapporto con gli attesi.
# 3. Prove negative, tra cui due esecuzioni reali: avviatore che scrive la lunghezza con l'ordine dei byte
#    invertito, e PARMECHO compilato con binari in ordine nativo (little-endian) invece che big-endian.
. "$ORACLE_ROOT/lib.sh"

EXP="$ORACLE_ROOT/avviatore/expected"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

# verifica OSSERVATI: 0 solo se byte dell'area e rapporto coincidono con gli attesi.
verifica() {
  local obs="$1" errs=0
  if [ ! -f "$obs/PARMDUMP.hex" ]; then echo "byte dell'area assenti (PARMDUMP.hex)"; errs=$((errs + 1))
  elif ! diff -u "$EXP/PARMDUMP.hex" "$obs/PARMDUMP.hex" > "$tmp/d1"; then
    echo "byte dell'area diversi dagli attesi:"; indent "$tmp/d1"; errs=$((errs + 1)); fi
  if [ ! -f "$obs/PARMECHO.txt" ]; then echo "rapporto di PARMECHO assente"; errs=$((errs + 1))
  elif ! diff -u "$EXP/PARMECHO.txt" "$obs/PARMECHO.txt" > "$tmp/d2"; then
    echo "rapporto di PARMECHO diverso dall'atteso:"; indent "$tmp/d2"; errs=$((errs + 1)); fi
  [ "$errs" -eq 0 ] || { echo "verifica fallita: $errs differenze"; return 1; }
  echo "verifica riuscita: area $(cat "$obs/PARMDUMP.hex"), lunghezza e testo letti dal programma come attesi"
}

# variante NOME [opzione cobc] [opzione C]: compila PARMECHO alterato in $tmp/NOME/bin e lo esegue.
variante() {
  local name="$1" xcob="${2:-}" xc="${3:-}"
  mkdir -p "$tmp/$name/build"
  orun -v "$tmp/$name/build:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh /oracle/build/compile.sh uno eseguibile /oracle/tests/PARMECHO.cbl PARMECHO /out "$xcob" "$xc" \
    > "$tmp/$name.log" 2>&1 || { cat "$tmp/$name.log" >&2; fail "compilazione della variante '$name' fallita"; }
  AVVIATORE_BIN_DIR="$tmp/$name/build/bin" AVVIATORE_OUT_DIR="$tmp/$name/obs" \
    bash "$ORACLE_ROOT/avviatore/run.sh" >> "$tmp/$name.log" 2>&1 \
    || { cat "$tmp/$name.log" >&2; fail "esecuzione della variante '$name' fallita"; }
}

log "1. prova dell'avviatore rieseguita in una cartella nuova"
AVVIATORE_OUT_DIR="$tmp/obs" bash "$ORACLE_ROOT/avviatore/run.sh" || fail "prova dell'avviatore fallita"

log "2. confronto con gli attesi"
verifica "$tmp/obs" > "$tmp/v.out" 2>&1 || { cat "$tmp/v.out" >&2; fail "l'avviatore non passa l'area attesa"; }
sed 's/^/   /' "$tmp/v.out" >&2

log "3. prove negative"
variante invertito "" "-DMENB_ORDINE_INVERTITO"
grep -q "0a 00 32" "$tmp/invertito/obs/PARMDUMP.hex" || fail "la variante con ordine invertito non ha prodotto l'area attesa (0a 00 ...)"
expect_fail "avviatore con la lunghezza in ordine little-endian (0a 00)" "byte dell'area diversi" verifica "$tmp/invertito/obs"
variante nativo "-fbinary-byteorder=native" ""
expect_fail "PARMECHO compilato con -fbinary-byteorder=native (legge 2560)" "PARM-LENGTH= 02560" verifica "$tmp/nativo/obs"
mkdir -p "$tmp/manca"; cp "$tmp/obs/PARMECHO.txt" "$tmp/manca/"
expect_fail "byte dell'area assenti" "byte dell'area assenti" verifica "$tmp/manca"
mkdir -p "$tmp/testo"; cp "$tmp/obs/PARMECHO.txt" "$tmp/obs/PARMDUMP.hex" "$tmp/testo/"
mutate "$tmp/testo/PARMECHO.txt" 's/^PARMECHO PARM-DATE=2022071800$/PARMECHO PARM-DATE=2022071900/'
expect_fail "testo del PARM letto dal programma alterato" "rapporto di PARMECHO diverso" verifica "$tmp/testo"
log "controllo superato"
