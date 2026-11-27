#!/usr/bin/env bash
# Test automatico del comando unico: dimostra che aggiungere un'analisi significa aggiungere una
# cartella (analysis/run.sh non viene modificato) e che le dipendenze sono rispettate.
# Lavora in una cartella temporanea (ANALYSIS_ROOT) e non tocca le analisi reali. Non usa Docker.
set -euo pipefail

RUN="$ANALYSIS_ROOT/run.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say() { echo "[selftest] $*"; }
die() { echo "[selftest] ERRORE: $*" >&2; exit 1; }

mk() { # mk ROOT NOME  -> crea la cartella dell'analisi
  mkdir -p "$1/$2"
}

# --- Scenario 1: produttore e consumatore, il nome del consumatore precede alfabeticamente quello del produttore.
r1="$tmp/s1"
mk "$r1" aaa-consumatore
mk "$r1" zzz-produttore
printf 'zzz-produttore\n' > "$r1/aaa-consumatore/deps"
cat > "$r1/zzz-produttore/run.sh" <<'EOS'
mkdir -p out
echo "valore-del-produttore" > out/valore.txt
EOS
cat > "$r1/zzz-produttore/check.sh" <<'EOS'
[ "$(cat out/valore.txt)" = "valore-del-produttore" ]
EOS
cat > "$r1/aaa-consumatore/run.sh" <<'EOS'
[ -f ../zzz-produttore/out/valore.txt ] || { echo "output del produttore assente" >&2; exit 1; }
mkdir -p out
cp ../zzz-produttore/out/valore.txt out/visto.txt
EOS
cat > "$r1/aaa-consumatore/check.sh" <<'EOS'
[ "$(cat out/visto.txt)" = "valore-del-produttore" ]
EOS

say "1. produttore/consumatore, partendo da output assenti"
[ ! -e "$r1/zzz-produttore/out" ] && [ ! -e "$r1/aaa-consumatore/out" ] || die "output non assenti in partenza"
ANALYSIS_ROOT="$r1" bash "$RUN" --all > "$tmp/s1.log" 2>&1 || { cat "$tmp/s1.log" >&2; die "--all fallito con dipendenze dichiarate"; }
[ "$(cat "$r1/aaa-consumatore/out/visto.txt")" = "valore-del-produttore" ] || die "il consumatore non ha trovato l'output del produttore"
first="$(grep '^== ' "$tmp/s1.log" | head -1)"
[ "$first" = "== zzz-produttore: run.sh" ] || die "il produttore non e' stato eseguito per primo (primo: $first)"
ANALYSIS_ROOT="$r1" bash "$RUN" --all --check > "$tmp/s1c.log" 2>&1 || { cat "$tmp/s1c.log" >&2; die "--all --check fallito"; }
say "   ok: ordine rispettato e output del produttore trovato dal consumatore"

say "2. senza la dichiarazione delle dipendenze l'ordine alfabetico fa fallire il consumatore (prova che il test e' sensibile)"
rm -rf "$r1/zzz-produttore/out" "$r1/aaa-consumatore/out" "$r1/aaa-consumatore/deps"
if ANALYSIS_ROOT="$r1" bash "$RUN" --all > "$tmp/s2.log" 2>&1; then
  die "senza deps il consumatore avrebbe dovuto fallire"
fi
grep -q 'output del produttore assente' "$tmp/s2.log" || die "motivo del fallimento inatteso"
say "   ok: fallisce come previsto"

say "3. esecuzione di una singola analisi"
ANALYSIS_ROOT="$r1" bash "$RUN" zzz-produttore > /dev/null 2>&1 || die "esecuzione singola fallita"
ANALYSIS_ROOT="$r1" bash "$RUN" zzz-produttore --check > /dev/null 2>&1 || die "check singolo fallito"
if ANALYSIS_ROOT="$r1" bash "$RUN" inesistente > /dev/null 2>&1; then die "analisi inesistente accettata"; fi
say "   ok"

say "4. dipendenza mancante"
r4="$tmp/s4"; mk "$r4" uno; echo 'non-esiste' > "$r4/uno/deps"; echo 'true' > "$r4/uno/run.sh"
if ANALYSIS_ROOT="$r4" bash "$RUN" --all > "$tmp/s4.log" 2>&1; then die "dipendenza mancante non rilevata"; fi
grep -q "dipende da 'non-esiste', che non esiste" "$tmp/s4.log" || die "messaggio di dipendenza mancante assente"
say "   ok"

say "5. dipendenze cicliche"
r5="$tmp/s5"; mk "$r5" a; mk "$r5" b; mk "$r5" c
echo b > "$r5/a/deps"; echo c > "$r5/b/deps"; echo a > "$r5/c/deps"
for n in a b c; do echo 'true' > "$r5/$n/run.sh"; done
if ANALYSIS_ROOT="$r5" bash "$RUN" --all > "$tmp/s5.log" 2>&1; then die "ciclo non rilevato"; fi
grep -q 'dipendenze cicliche' "$tmp/s5.log" || die "messaggio di ciclo assente"
say "   ok"

say "6. si ferma al primo errore"
r6="$tmp/s6"; mk "$r6" a; mk "$r6" b; mk "$r6" c
echo 'true' > "$r6/a/run.sh"; echo 'exit 7' > "$r6/b/run.sh"; echo 'touch ../c-eseguita' > "$r6/c/run.sh"
if ANALYSIS_ROOT="$r6" bash "$RUN" --all > "$tmp/s6.log" 2>&1; then die "errore non propagato"; fi
[ ! -e "$r6/c-eseguita" ] || die "l'analisi successiva e' stata eseguita dopo un errore"
say "   ok"

say "7. ordine alfabetico a parita' di dipendenze"
r7="$tmp/s7"; mk "$r7" m; mk "$r7" b; mk "$r7" t; mk "$r7" a
echo b > "$r7/m/deps"
for n in m b t a; do echo "echo $n >> ../ordine.txt" > "$r7/$n/run.sh"; done
ANALYSIS_ROOT="$r7" bash "$RUN" --all > /dev/null 2>&1 || die "scenario 7 fallito"
[ "$(tr '\n' ' ' < "$r7/ordine.txt")" = "a b m t " ] || die "ordine inatteso: $(tr '\n' ' ' < "$r7/ordine.txt")"
say "   ok: a b m t"

say "comando unico: tutti i test superati"
