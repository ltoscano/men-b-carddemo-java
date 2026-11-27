#!/usr/bin/env bash
# Controlli a campione sugli strumenti adottati (contro il sorgente, tramite gli attesi scritti a mano in
# analysis/tools/expected/), prova negativa per ogni controllo, prova dei fallimenti per i candidati scartati,
# coerenza tra capabilities.tsv e docs/legacy-map/strumenti.md, versioni fissate nelle immagini.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
require_legacy

CAPS="$TOOLS_DIR/capabilities.tsv"
DOC="$REPO_ROOT/docs/legacy-map/strumenti.md"
[ -d "$OUT" ] || fail "analysis/tools/out assente: eseguire prima './analysis/run.sh tools'"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

# compare CHECK [TOOL] [--expected DIR]: esegue il confronto, stampa l'esito, ritorna 0 se pass
compare() { glue_run --rw "$tmp" -- /analysis/tools/glue/compare.py "$@"; }

# negative NOME KIND SOTTOSTRINGA CHECK [TOOL]: altera un valore atteso e pretende che il controllo fallisca
negative() {
  local name="$1" kind="$2" needle="$3"; shift 3
  glue_run --rw "$tmp" -- /analysis/tools/glue/mutate.py "$kind" /analysis/tools/expected /work/exp-"$kind"
  if compare "$@" --expected "/work/exp-$kind" > "$tmp/neg.out" 2>&1; then
    cat "$tmp/neg.out" >&2
    fail "PROVA NEGATIVA FALLITA ($name): il controllo non ha rilevato l'atteso alterato"
  fi
  grep -q -- "$needle" "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "prova negativa ($name): il controllo e' fallito ma non per il motivo atteso ('$needle')"; }
  log "   prova negativa ok: $name (atteso alterato -> il controllo fallisce)"
}

# --- 1. capacita' dichiarate e controlli degli strumenti adottati
log "1. controlli a campione per ogni capacita' dichiarata in capabilities.tsv"
[ -f "$CAPS" ] || fail "capabilities.tsv assente"
header_seen=0
while IFS=$'\t' read -r cap issues stato tools checks scartati; do
  case "$cap" in ''|'#'*) continue ;; esac
  if [ "$header_seen" -eq 0 ]; then header_seen=1; continue; fi   # prima riga non commento = intestazione
  case "$stato" in
    available)
      log "   capacita' '$cap' (available, strumenti: $tools)"
      for c in $(echo "$checks" | tr ',' ' '); do
        chk="${c%%:*}"; tool=""; [ "$chk" = "$c" ] || tool="${c#*:}"
        compare $chk $tool > "$tmp/c.out" 2>&1 || { cat "$tmp/c.out" >&2; fail "controllo '$c' fallito per la capacita' '$cap' dichiarata available"; }
        sed 's/^/      /' "$tmp/c.out" >&2
      done
      ;;
    unavailable)
      log "   capacita' '$cap' (unavailable): prova del fallimento per ogni candidato"
      for t in $(echo "$scartati" | tr ',' ' '); do
        ls "$OUT/$t"/prova-fallita*.txt > /dev/null 2>&1 || fail "capacita' '$cap' unavailable ma manca la prova del fallimento di '$t' in out/$t/prova-fallita*.txt"
      done
      ;;
    *) fail "stato non valido '$stato' per la capacita' '$cap' (ammessi: available, unavailable)" ;;
  esac
done < "$CAPS"
[ "$header_seen" -eq 1 ] || fail "capabilities.tsv vuoto"

# --- 2. i candidati insufficienti restano insufficienti (la prova e' riproducibile) e hanno il verdetto registrato
log "2. candidati non adottati per le occorrenze COPY: la prova dell'insufficienza e' registrata e riproducibile"
for t in cmt cobmix; do
  [ -f "$OUT/$t/verdetto-copy.txt" ] || fail "manca out/$t/verdetto-copy.txt"
  [ "$(tail -1 "$OUT/$t/verdetto-copy.txt")" = "VERDETTO: fail" ] || fail "verdetto registrato di $t non e' fail"
  if compare copy "$t" > "$tmp/c.out" 2>&1; then fail "$t supera ora il controllo COPY: aggiornare capabilities.tsv e strumenti.md"; fi
  grep -q 'non riporta il numero di riga' "$tmp/c.out" || fail "motivo del fallimento di $t inatteso"
  log "   $t: insufficiente come registrato ($(grep -c PROBLEMA "$tmp/c.out") problemi: righe e sostituzioni non riportate)"
done

# --- 3. prove negative: ogni controllo fallisce se si altera il valore atteso
log "3. prove negative (un valore atteso alterato alla volta)"
negative "conteggi: file di app/cbl" scc "app/cbl file: atteso 30" scc
negative "compilazione: esito atteso di COSGN00C" compile "COSGN00C: atteso ok" compile
negative "COPY: numero di riga di COBIL00C" copy-line "COBIL00C: occorrenze diverse dall'atteso" copy proleap
negative "COPY: sostituzioni di una occorrenza di CSSETATY in COACTUPC" copy-replacing "COACTUPC: occorrenze diverse dall'atteso" copy proleap
negative "COPY: numero di istruzioni COPY contate nel sorgente per CBACT04C" copy-count "CBACT04C: occorrenze COPY riportate 5, contate nel sorgente 6" copy proleap
negative "CALL: chiamato atteso di COBSWAIT" call "CALL attesa non trovata: COBSWAIT -> MVSWAIX" call cmt
negative "tracciati: offset di ACCT-CURR-BAL" layout-offset "CVACT01Y.ACCT-CURR-BAL" layout
negative "tracciati: lunghezza totale di CVTRA05Y" layout-length "CVTRA05Y: lunghezza totale attesa 351" layout
negative "JCL: programma del passo STEP15 di POSTTRAN" jcl-program "POSTTRAN/STEP15: tipo e programma attesi ('PGM', 'CBTRN03C')" jcl
negative "JCL: tipo del passo atteso PROC invece di PGM" jcl-type "POSTTRAN/STEP15: tipo e programma attesi ('PROC', 'CBTRN02C')" jcl
negative "conteggi: campione a mano di CVACT03Y (codice, commenti)" scc-sample "CVACT03Y.cpy: Code atteso 11, scc 5" scc
negative "JCL: dataset della DD DALYREJS (GDG)" jcl-dd "POSTTRAN/STEP15: DD attese" jcl

# --- 3b. prove negative sull'OUTPUT dello strumento (l'atteso resta quello vero, si altera l'output)
log "3b. prove negative: un valore dell'output alterato alla volta"
negative_out() {
  local name="$1" kind="$2" needle="$3"; shift 3
  glue_run --rw "$tmp" -- /analysis/tools/glue/mutate_out.py "$kind" /analysis/tools/out "/work/out-$kind"
  if compare "$@" --out "/work/out-$kind" > "$tmp/neg.out" 2>&1; then
    cat "$tmp/neg.out" >&2
    fail "PROVA NEGATIVA FALLITA ($name): il controllo non ha rilevato l'output alterato"
  fi
  grep -q -- "$needle" "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "prova negativa ($name): fallito ma non per il motivo atteso ('$needle')"; }
  log "   prova negativa ok: $name (output alterato -> il controllo fallisce)"
}
negative_out "scc: codice, commenti e vuote dell'aggregato app/cbl azzerati" scc-aggregate-zero "app/cbl: righe 20650 != codice + commenti + vuote" scc
negative_out "scc: commenti di CVACT03Y azzerati nel CSV per file" scc-file-comments "CVACT03Y.cpy: Code atteso 5, scc 11" scc
negative_out "compilazione: errori di CBSTM03A portati da 39 a 9999 nel TSV (log originale invariato)" compile-count "CBSTM03A: errori nel TSV 9999, nelle diagnostiche salvate 39" compile
negative_out "JCL: tipo del passo POSTTRAN/STEP15 alterato nell'output (PGM -> PROC)" jcl-type "POSTTRAN/STEP15: tipo e programma attesi ('PGM', 'CBTRN02C'), mapa ('PROC', 'CBTRN02C')" jcl

# --- 3c. i TSV normalizzati devono derivare dall'output grezzo
log "3c. i TSV versionati coincidono con quelli rigenerati dall'output grezzo"
renorm() { glue_run --rw "$tmp" -- /analysis/tools/glue/renorm.py "$@"; }
renorm cmt /analysis/tools/out/cmt /analysis/tools/out/cmt
renorm cb2xml /analysis/tools/out/cb2xml /analysis/tools/out/cb2xml
negative_raw() {
  local name="$1" kind="$2" tool="$3"
  glue_run --rw "$tmp" -- /analysis/tools/glue/mutate_out.py "$kind" /analysis/tools/out "/work/raw-$kind"
  if renorm "$tool" "/work/raw-$kind/$tool" "/analysis/tools/out/$tool" > "$tmp/neg.out" 2>&1; then
    cat "$tmp/neg.out" >&2
    fail "PROVA NEGATIVA FALLITA ($name): TSV e grezzo incoerenti ma il controllo e' verde"
  fi
  grep -q 'RINORMALIZZAZIONE' "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "prova negativa ($name): motivo inatteso"; }
  log "   prova negativa ok: $name"
}
negative_raw "cb2xml: campo rinominato nell'XML grezzo, TSV invariati" cb2xml-rename cb2xml
negative_raw "cmt: CALL rinominata nel JSON grezzo, TSV invariati" cmt-call-rename cmt

# Per gli strumenti il cui grezzo non e' versionato (cobmix, mapa: JSON molto grandi / UUID e orari) e per quelli la cui
# normalizzazione e' nello script di prova (scc, gnucobol, proleap) si rieseguono le prove in una cartella temporanea
# e si confronta l'intero albero degli output con quello versionato (esclusi i verdetti, scritti da run.sh).
log "   riesecuzione di tutte le prove in cartella temporanea e confronto con gli output versionati"
mkdir -p "$tmp/rerun"
for t in 10-scc 20-gnucobol 30-cmt 31-cobmix 32-proleap 40-cb2xml 50-mapa; do
  TOOLS_OUT="$tmp/rerun" bash "$TOOLS_DIR/trials/$t.sh" > /dev/null 2>&1 || fail "riesecuzione della prova $t fallita"
done
diff -r -x 'verdetto-*' "$tmp/rerun" "$OUT" > "$tmp/rerun.diff" || { head -20 "$tmp/rerun.diff" >&2; fail "output versionati diversi da quelli rigenerati dagli strumenti"; }
log "   ok: output rigenerati identici a quelli versionati"
log "   prova negativa: un output versionato alterato e' diverso da quello rigenerato"
glue_run --rw "$tmp" -- /analysis/tools/glue/mutate_out.py cmt-call-rename /analysis/tools/out /work/out-diff
if diff -r -x 'verdetto-*' "$tmp/rerun" "$tmp/out-diff" > /dev/null; then fail "il confronto con la rigenerazione non rileva un output alterato"; fi
log "   ok"

# --- 4. versioni fissate
log "4. immagini con versione fissata"
glue_run -- /analysis/tools/glue/lint_pins.py /analysis

# --- 5. capabilities.tsv coerente con strumenti.md
log "5. strumenti.md coerente con capabilities.tsv e con le prove eseguite"
glue_run --mount "$REPO_ROOT/docs/legacy-map:/docs:ro" -- /analysis/tools/glue/check_docs.py /analysis/tools/capabilities.tsv /docs/strumenti.md /analysis/tools/out

log "   prova negativa: una capacita' con stato diverso da quello del documento deve far fallire il controllo"
glue_run --rw "$tmp" -- -c "
s = open('/analysis/tools/capabilities.tsv', encoding='utf-8').read()
t = s.replace('conteggi\tpaper\tavailable', 'conteggi\tpaper\tunavailable')
assert s != t, 'alterazione non applicata'
open('/work/capabilities-bad.tsv', 'w', encoding='utf-8').write(t)"
if glue_run --rw "$tmp" --mount "$REPO_ROOT/docs/legacy-map:/docs:ro" -- /analysis/tools/glue/check_docs.py /work/capabilities-bad.tsv /docs/strumenti.md /analysis/tools/out > "$tmp/neg-doc.out" 2>&1; then
  fail "il controllo di coerenza NON ha rilevato lo stato alterato"
fi
grep -q "conteggi: stato nel documento 'available' diverso da capabilities.tsv 'unavailable'" "$tmp/neg-doc.out" || { cat "$tmp/neg-doc.out" >&2; fail "motivo del fallimento inatteso"; }
log "   ok"
log "tools: tutti i controlli superati"
