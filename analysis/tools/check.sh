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
tmp="$(mktemp -d)"
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
negative "JCL: programma del passo STEP15 di POSTTRAN" jcl-program "POSTTRAN/STEP15: programma atteso CBTRN03C" jcl
negative "JCL: dataset della DD DALYREJS (GDG)" jcl-dd "POSTTRAN/STEP15: DD attese" jcl

# --- 4. versioni fissate
log "4. immagini con versione fissata"
glue_run -- /analysis/tools/glue/lint_pins.py /analysis

# --- 5. capabilities.tsv coerente con strumenti.md
log "5. strumenti.md coerente con capabilities.tsv e con le prove eseguite"
glue_run --mount "$REPO_ROOT/docs/legacy-map:/docs:ro" -- /analysis/tools/glue/check_docs.py /analysis/tools/capabilities.tsv /docs/strumenti.md /analysis/tools/out
