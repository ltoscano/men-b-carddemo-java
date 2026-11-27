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

# Percorso, visto dal container, di una cartella dentro $tmp (che sta in analysis/.work, montata in sola lettura su /analysis)
cont() { echo "/analysis/.work/$(basename "$tmp")/$1"; }

# check_unavailable CAPACITA CANDIDATI CONTROLLI HOSTOUT CONTOUT: per una capacita' unavailable la prova del fallimento
# deve esistere per ogni candidato, essere un fallimento, coincidere con il ricalcolo e il ricalcolo deve fallire ancora.
check_unavailable() {
  local cap="$1" cands="$2" checks="$3" hout="$4" cout="$5" t c f
  for t in $(echo "$cands" | tr ',' ' '); do
    f="$(ls "$hout/$t"/prova-fallita-*.txt 2>/dev/null | head -1)"
    [ -n "$f" ] || { echo "capacita' '$cap' unavailable ma manca la prova del fallimento di '$t' (out/$t/prova-fallita-*.txt)" >&2; return 1; }
    [ "$(tail -1 "$f")" = "VERDETTO: fail" ] || { echo "la prova salvata per '$t' non e' un fallimento" >&2; return 1; }
    for c in $(echo "$checks" | tr ',' ' '); do
      verdict_text "$c" "" --out "$cout" > "$tmp/live.txt"
      [ "$(tail -1 "$tmp/live.txt")" = "VERDETTO: fail" ] || { echo "capacita' '$cap': i campioni a mano coincidono ora con '$t': non e' piu' unavailable, aggiornare capabilities.tsv e strumenti.md" >&2; return 1; }
      cmp -s "$f" "$tmp/live.txt" || { echo "la prova salvata in $f differisce dal ricalcolo" >&2; return 1; }
    done
  done
}

# reconcile HOSTOUT CONTOUT: ogni verdetto / prova dichiarato in verdetti.tsv deve esistere ed essere uguale al ricalcolato,
# con il controllo e lo strumento dichiarati (non ricavati dal nome del file o dalla cartella in cui si trova).
reconcile() {
  local hout="$1" cout="$2" tbl path check tool n=0
  tbl="$(verdict_table)" || return 1
  while IFS=$'\t' read -r path check tool; do
    [ "$tool" != "-" ] || tool=""
    [ -f "$hout/$path" ] || { echo "verdetto dovuto mancante: $path" >&2; return 1; }
    verdict_text "$check" "$tool" --out "$cout" > "$tmp/re.txt" || return 1
    [ -s "$tmp/re.txt" ] || { echo "ricalcolo del verdetto $path senza output" >&2; return 1; }
    cmp -s "$hout/$path" "$tmp/re.txt" || { echo "verdetto salvato $path (ultima riga '$(tail -1 "$hout/$path")') diverso dal ricalcolato ('$(tail -1 "$tmp/re.txt")')" >&2; return 1; }
    n=$((n + 1))
  done <<< "$tbl"
  echo "   $n verdetti/prove salvati coincidono con il ricalcolo"
}

# --- 0. completezza dei verdetti: l'insieme esatto dei file presenti coincide con quello dichiarato in verdetti.tsv
log "0. insieme dei file di verdetto e di prova fallita uguale a quello dichiarato (verdetti.tsv)"
verdict_set_check "$OUT" || fail "verdetti presenti diversi da quelli dichiarati in analysis/tools/verdetti.tsv"
decl_all="$(verdict_declared)" || fail "dichiarazione dei verdetti non valida"
n_decl="$(printf '%s\n' "$decl_all" | wc -l | tr -d ' ')"
log "   $n_decl file dichiarati, tutti presenti e nessun altro"
# Prove negative automatiche, su copie in cartella temporanea: mancante, nome sconosciuto, verdetto valido sotto un altro strumento.
set_negative() { # set_negative NOME ATTESO -- comando di alterazione (cwd = copia di out)
  local name="$1" needle="$2"; shift 3
  rm -rf "$tmp/setneg"; cp -R "$OUT" "$tmp/setneg"
  ( cd "$tmp/setneg" && "$@" )
  if verdict_set_check "$tmp/setneg" > "$tmp/neg.out" 2>&1; then
    fail "PROVA NEGATIVA FALLITA ($name): l'insieme alterato e' accettato"
  fi
  grep -qF -- "$needle" "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "prova negativa ($name): fallito ma non nominando '$needle'"; }
  log "   prova negativa ok: $name"
}
set_negative "verdetto cb2xml cancellato" "verdetto dovuto mancante: cb2xml/verdetto-layout.txt" -- rm cb2xml/verdetto-layout.txt
set_negative "prova fallita della ripartizione cancellata" "verdetto dovuto mancante: scc/prova-fallita-ripartizione.txt" -- rm scc/prova-fallita-ripartizione.txt
set_negative "nome di verdetto sconosciuto" "file di verdetto non dovuto: scc/verdetto-sconosciuto.txt" -- cp scc/verdetto-scc.txt scc/verdetto-sconosciuto.txt
set_negative "verdetto valido copiato sotto un altro strumento" "file di verdetto non dovuto: cmt/verdetto-layout.txt" -- cp cb2xml/verdetto-layout.txt cmt/verdetto-layout.txt
set_negative "verdetto spostato sotto un altro strumento" "verdetto dovuto mancante: cb2xml/verdetto-layout.txt" -- mv cb2xml/verdetto-layout.txt mapa/verdetto-layout.txt

# Prova negativa: voce aggiunta alla dichiarazione (valida per la regola) + file residuo preesistente, che il solo confronto
# dei file presenti accetterebbe. Deve fallire il confronto con i verdetti scritti nella corsa e il ricalcolo per strumento.
written_real="$(verdict_table)" || fail "dichiarazione dei verdetti non valida"
rm -rf "$tmp/setneg"; cp -R "$OUT" "$tmp/setneg"
cp "$tmp/setneg/cmt/verdetto-call.txt" "$tmp/setneg/cobmix/verdetto-call.txt"
{ cat "$VERDETTI"; printf 'cobmix\tverdetto-call.txt\tcall\tcobmix\n'; } > "$tmp/verdetti-extra.tsv"
VERDETTI="$tmp/verdetti-extra.tsv" verdict_set_check "$tmp/setneg" > /dev/null 2>&1 \
  || fail "prova negativa (voce aggiunta + residuo): il confronto dei soli file presenti avrebbe dovuto accettare il caso (premessa della prova)"
if VERDETTI="$tmp/verdetti-extra.tsv" verdict_written_check "$written_real" > "$tmp/neg.out" 2>&1; then
  fail "PROVA NEGATIVA FALLITA (voce aggiunta + residuo): i verdetti scritti nella corsa non coincidono con la dichiarazione ma il controllo e' verde"
fi
grep -qF -- "verdetto dichiarato ma non scritto in questa corsa: cobmix/verdetto-call.txt" "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "prova negativa (voce aggiunta + residuo): motivo inatteso"; }
if VERDETTI="$tmp/verdetti-extra.tsv" reconcile "$tmp/setneg" "$(cont setneg)" > "$tmp/neg.out" 2>&1; then
  fail "PROVA NEGATIVA FALLITA (voce aggiunta + residuo): il verdetto copiato da un altro strumento supera il ricalcolo"
fi
grep -qF -- "cobmix/verdetto-call.txt" "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "prova negativa (voce aggiunta + residuo, ricalcolo): motivo inatteso"; }
log "   prova negativa ok: voce aggiunta alla dichiarazione + file residuo (verdetti scritti in corsa e ricalcolo per strumento)"
# Voce con cartella sbagliata per il controllo (verdetto di cb2xml dichiarato sotto scc): rifiutata dalla dichiarazione stessa.
{ cat "$VERDETTI"; printf 'scc\tverdetto-layout.txt\tlayout\t-\n'; } > "$tmp/verdetti-bad.tsv"
if VERDETTI="$tmp/verdetti-bad.tsv" verdict_table > "$tmp/neg.out" 2>&1; then fail "PROVA NEGATIVA FALLITA: una voce con cartella sbagliata per il controllo e' accettata"; fi
grep -qF -- "va nella cartella 'cb2xml', non in 'scc'" "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "prova negativa (cartella sbagliata): motivo inatteso"; }
log "   prova negativa ok: voce con la cartella di un altro strumento rifiutata"

# Prove negative: un comando necessario al confronto che fallisce (esito 42) non puo' dare un insieme "completo",
# ne' con l'insieme intatto ne' con un verdetto assente. Ogni comando e' sostituito da un finto che esce con 42.
for cmd in find sed sort awk cut uniq; do
  mkdir -p "$tmp/wrap-$cmd"
  printf '#!/bin/sh\nexit 42\n' > "$tmp/wrap-$cmd/$cmd"; chmod +x "$tmp/wrap-$cmd/$cmd"
done
rm -rf "$tmp/setneg"; cp -R "$OUT" "$tmp/setneg"; rm "$tmp/setneg/gnucobol/verdetto-compile.txt"
for cmd in find sed sort awk cut uniq; do
  if PATH="$tmp/wrap-$cmd:$PATH" verdict_set_check "$OUT" > /dev/null 2>&1; then
    fail "PROVA NEGATIVA FALLITA: con '$cmd' che fallisce l'insieme dei verdetti presenti e' dichiarato completo"
  fi
  if PATH="$tmp/wrap-$cmd:$PATH" verdict_set_check "$tmp/setneg" > /dev/null 2>&1; then
    fail "PROVA NEGATIVA FALLITA: con '$cmd' che fallisce e un verdetto assente l'insieme e' accettato"
  fi
done
for cmd in awk cut uniq sort; do
  if PATH="$tmp/wrap-$cmd:$PATH" verdict_written_check "$written_real" > /dev/null 2>&1; then
    fail "PROVA NEGATIVA FALLITA: con '$cmd' che fallisce i verdetti scritti nella corsa sono dichiarati completi"
  fi
done
log "   prova negativa ok: un comando del confronto che fallisce (find sed sort awk cut uniq) non produce mai un insieme accettato"

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
      log "   capacita' '$cap' (unavailable): prova del fallimento per ogni candidato, riproducibile"
      check_unavailable "$cap" "$scartati" "$checks" "$OUT" /analysis/tools/out || fail "prova del fallimento non valida per '$cap'"
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
negative "conteggi: campione a mano di CVACT03Y (righe vuote)" scc-sample "CVACT03Y.cpy: Blanks atteso 1, scc 0" scc
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
negative_out "scc: commenti di CVACT03Y azzerati nel CSV per file" scc-file-comments "app/cpy: Code dell'aggregato" scc
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
diff -r -x 'verdetto-*' -x 'prova-fallita-*' "$tmp/rerun" "$OUT" > "$tmp/rerun.diff" || { head -20 "$tmp/rerun.diff" >&2; fail "output versionati diversi da quelli rigenerati dagli strumenti"; }
log "   ok: output rigenerati identici a quelli versionati"
log "   prova negativa: un output versionato alterato e' diverso da quello rigenerato"
glue_run --rw "$tmp" -- /analysis/tools/glue/mutate_out.py cmt-call-rename /analysis/tools/out /work/out-diff
if diff -r -x 'verdetto-*' -x 'prova-fallita-*' "$tmp/rerun" "$tmp/out-diff" > /dev/null; then fail "il confronto con la rigenerazione non rileva un output alterato"; fi
log "   ok"

# --- 3d. capacita' unavailable e riconciliazione dei verdetti salvati
log "3d. capacita' unavailable: prove negative"
glue_run --rw "$tmp" -- /analysis/tools/glue/mutate_out.py drop-evidence /analysis/tools/out /work/out-drop
if check_unavailable ripartizione-codice-commenti scc scc-split "$tmp/out-drop" "$(cont out-drop)" > "$tmp/neg.out" 2>&1; then fail "PROVA NEGATIVA FALLITA: la prova del fallimento mancante non e' rilevata"; fi
grep -q "manca la prova del fallimento di 'scc'" "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "motivo inatteso"; }
log "   prova negativa ok: prova del fallimento assente -> il controllo fallisce"
glue_run --rw "$tmp" -- /analysis/tools/glue/mutate_out.py scc-split-fixed /analysis/tools/out /work/out-fixed
if check_unavailable ripartizione-codice-commenti scc scc-split "$tmp/out-fixed" "$(cont out-fixed)" > "$tmp/neg.out" 2>&1; then fail "PROVA NEGATIVA FALLITA: scc 'corretto' non e' rilevato"; fi
grep -q "i campioni a mano coincidono ora" "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "motivo inatteso"; }
log "   prova negativa ok: se scc coincidesse con i campioni a mano la capacita' non sarebbe piu' unavailable"

log "3e. i verdetti e le prove salvati coincidono con il ricalcolo"
reconcile "$OUT" /analysis/tools/out || fail "verdetto salvato incoerente"
glue_run --rw "$tmp" -- /analysis/tools/glue/mutate_out.py verdict-flip /analysis/tools/out /work/out-flip
if reconcile "$tmp/out-flip" "$(cont out-flip)" > "$tmp/neg.out" 2>&1; then fail "PROVA NEGATIVA FALLITA: un verdetto salvato alterato non e' rilevato"; fi
grep -q "verdetto salvato scc/verdetto-scc.txt" "$tmp/neg.out" || { cat "$tmp/neg.out" >&2; fail "motivo inatteso"; }
log "   prova negativa ok: verdetto salvato 'fail' contro ricalcolo 'pass' -> il controllo fallisce"

# --- 4. versioni fissate
log "4. immagini con versione fissata"
glue_run -- /analysis/tools/glue/lint_pins.py /analysis

# --- 5. capabilities.tsv coerente con strumenti.md
log "5. strumenti.md coerente con capabilities.tsv e con le prove eseguite"
glue_run --mount "$REPO_ROOT/docs/legacy-map:/docs:ro" -- /analysis/tools/glue/check_docs.py /analysis/tools/capabilities.tsv /docs/strumenti.md /analysis/tools/out

log "   prova negativa: una capacita' con stato diverso da quello del documento deve far fallire il controllo"
glue_run --rw "$tmp" -- -c "
s = open('/analysis/tools/capabilities.tsv', encoding='utf-8').read()
t = s.replace('conteggi-file-righe-vuote\tpaper\tavailable', 'conteggi-file-righe-vuote\tpaper\tunavailable')
assert s != t, 'alterazione non applicata'
open('/work/capabilities-bad.tsv', 'w', encoding='utf-8').write(t)"
if glue_run --rw "$tmp" --mount "$REPO_ROOT/docs/legacy-map:/docs:ro" -- /analysis/tools/glue/check_docs.py /work/capabilities-bad.tsv /docs/strumenti.md /analysis/tools/out > "$tmp/neg-doc.out" 2>&1; then
  fail "il controllo di coerenza NON ha rilevato lo stato alterato"
fi
grep -q "conteggi-file-righe-vuote: stato nel documento 'available' diverso da capabilities.tsv 'unavailable'" "$tmp/neg-doc.out" || { cat "$tmp/neg-doc.out" >&2; fail "motivo del fallimento inatteso"; }
log "   ok"

log "   prova negativa: il verdetto di un candidato scartato cambiato in 'adottato' nel documento deve far fallire il controllo"
glue_run --rw "$tmp" --mount "$REPO_ROOT/docs/legacy-map:/docs:ro" -- -c "
s = open('/docs/strumenti.md', encoding='utf-8').read()
t = s.replace('| scartato: provato perche\u0301 cmt', '| adottato: provato perche\u0301 cmt').replace('| scartato: provato perché cmt', '| adottato: provato perché cmt')
assert s != t, 'alterazione non applicata'
open('/work/strumenti-bad.md', 'w', encoding='utf-8').write(t)"
if glue_run --rw "$tmp" -- /analysis/tools/glue/check_docs.py /analysis/tools/capabilities.tsv /work/strumenti-bad.md /analysis/tools/out > "$tmp/neg-doc2.out" 2>&1; then
  fail "il controllo NON ha rilevato un candidato scartato dichiarato adottato"
fi
grep -q "cobmix: non e' adottato da nessuna capacita' available" "$tmp/neg-doc2.out" || { cat "$tmp/neg-doc2.out" >&2; fail "motivo del fallimento inatteso"; }
log "   ok"
log "tools: tutti i controlli superati"
