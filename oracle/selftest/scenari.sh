#!/usr/bin/env bash
# Scenari del test automatico del comando unico. Non usa Docker.
# Uso: scenari.sh RUN TMP   (RUN = il run.sh da provare, TMP = cartella vuota in cui creare i passi finti)
# Esce con 0 se tutti gli scenari danno l'esito atteso, con 1 al primo scenario sbagliato.
set -uo pipefail
RUN="$1"; tmp="$2"
say() { echo "[scenari] $*"; }
die() { echo "[scenari] ERRORE: $*" >&2; exit 1; }
r() { local root="$1"; shift; ORACLE_ROOT="$root" bash "$RUN" "$@"; }

# 1. Ordine per dipendenze: il consumatore precede alfabeticamente il produttore.
r1="$tmp/s1"; mkdir -p "$r1/aaa-consumatore" "$r1/zzz-produttore"
printf 'zzz-produttore\n' > "$r1/aaa-consumatore/deps"
printf 'mkdir -p out && echo valore > out/v.txt\n' > "$r1/zzz-produttore/run.sh"
printf '[ "$(cat out/v.txt)" = valore ]\n' > "$r1/zzz-produttore/check.sh"
printf '[ -f ../zzz-produttore/out/v.txt ] || { echo "output del produttore assente" >&2; exit 1; }\nmkdir -p out && cp ../zzz-produttore/out/v.txt out/visto.txt\n' > "$r1/aaa-consumatore/run.sh"
printf '[ "$(cat out/visto.txt)" = valore ]\n' > "$r1/aaa-consumatore/check.sh"
say "1. ordine per dipendenze"
r "$r1" --all > "$tmp/s1.log" 2>&1 || { cat "$tmp/s1.log" >&2; die "--all fallito con dipendenze dichiarate"; }
[ "$(grep '^== ' "$tmp/s1.log" | head -1)" = "== zzz-produttore: run.sh" ] || die "il produttore non e' stato eseguito per primo"
r "$r1" --all --check > "$tmp/s1c.log" 2>&1 || { cat "$tmp/s1c.log" >&2; die "--all --check fallito"; }
[ "$(grep '^== ' "$tmp/s1c.log" | head -1)" = "== zzz-produttore: check.sh" ] || die "con --check il produttore non e' stato controllato per primo"

say "2. senza la dichiarazione delle dipendenze il consumatore fallisce (il test e' sensibile all'ordine)"
rm -rf "$r1/zzz-produttore/out" "$r1/aaa-consumatore/out" "$r1/aaa-consumatore/deps"
if r "$r1" --all > "$tmp/s2.log" 2>&1; then die "senza deps il consumatore avrebbe dovuto fallire"; fi
grep -q 'output del produttore assente' "$tmp/s2.log" || die "motivo del fallimento inatteso"

say "3. passo singolo, passo inesistente, nome non valido"
r "$r1" zzz-produttore > /dev/null 2>&1 || die "esecuzione singola fallita"
r "$r1" zzz-produttore --check > /dev/null 2>&1 || die "controllo singolo fallito"
if r "$r1" inesistente > /dev/null 2>&1; then die "passo inesistente accettato"; fi
if r "$r1" ../x > /dev/null 2>&1; then die "nome con / accettato"; fi

say "4. dipendenza mancante"
r4="$tmp/s4"; mkdir -p "$r4/uno"; echo 'non-esiste' > "$r4/uno/deps"; echo 'true' > "$r4/uno/run.sh"; echo 'true' > "$r4/uno/check.sh"
if r "$r4" --all > "$tmp/s4.log" 2>&1; then die "dipendenza mancante non rilevata (--all)"; fi
grep -q "dipende da 'non-esiste', che non esiste" "$tmp/s4.log" || die "messaggio di dipendenza mancante assente"
if r "$r4" --all --check > "$tmp/s4c.log" 2>&1; then die "dipendenza mancante non rilevata (--all --check)"; fi

say "5. ciclo di dipendenze, anche di un passo su se stesso"
r5="$tmp/s5"; mkdir -p "$r5/a" "$r5/b" "$r5/c"
echo b > "$r5/a/deps"; echo c > "$r5/b/deps"; echo a > "$r5/c/deps"
for n in a b c; do echo 'touch ../eseguito' > "$r5/$n/run.sh"; echo 'true' > "$r5/$n/check.sh"; done
if r "$r5" --all > "$tmp/s5.log" 2>&1; then die "ciclo non rilevato"; fi
grep -q 'dipendenze cicliche' "$tmp/s5.log" || die "messaggio di ciclo assente"
[ ! -e "$r5/eseguito" ] || die "con un ciclo e' stato eseguito un passo"
r5b="$tmp/s5b"; mkdir -p "$r5b/a"; echo a > "$r5b/a/deps"; echo true > "$r5b/a/run.sh"
if r "$r5b" --all > "$tmp/s5b.log" 2>&1; then die "dipendenza da se stesso non rilevata"; fi
grep -q 'dipende da se stesso' "$tmp/s5b.log" || die "messaggio di dipendenza da se stesso assente"

say "6. ci si ferma al primo errore"
r6="$tmp/s6"; mkdir -p "$r6/a" "$r6/b" "$r6/c"
echo 'true' > "$r6/a/run.sh"; echo 'exit 7' > "$r6/b/run.sh"; echo 'touch ../c-eseguito' > "$r6/c/run.sh"
for n in a b c; do echo 'true' > "$r6/$n/check.sh"; done
if r "$r6" --all > "$tmp/s6.log" 2>&1; then die "errore non propagato"; fi
[ ! -e "$r6/c-eseguito" ] || die "il passo successivo e' stato eseguito dopo un errore"

say "7. controllo mancante: con --check un passo con run.sh e senza check.sh e' un errore"
r7="$tmp/s7"; mkdir -p "$r7/con" "$r7/senza"
echo 'true' > "$r7/con/run.sh"; echo 'true' > "$r7/con/check.sh"; echo 'true' > "$r7/senza/run.sh"
r "$r7" --all > /dev/null 2>&1 || die "--all (senza --check) dovrebbe riuscire"
if r "$r7" --all --check > "$tmp/s7.log" 2>&1; then die "--all --check ha accettato un passo senza check.sh"; fi
grep -q "il passo 'senza' non ha check.sh" "$tmp/s7.log" || die "messaggio di controllo mancante assente (--all --check)"
if r "$r7" senza --check > "$tmp/s7b.log" 2>&1; then die "'senza --check' ha accettato un passo senza check.sh"; fi
grep -q "il passo 'senza' non ha check.sh" "$tmp/s7b.log" || die "messaggio di controllo mancante assente (passo singolo)"
r "$r7" con --check > /dev/null 2>&1 || die "il controllo di un passo che ce l'ha dovrebbe riuscire"

say "8. ordine alfabetico a parita' di dipendenze"
r8="$tmp/s8"; for n in m b t a; do mkdir -p "$r8/$n"; echo "echo $n >> ../ordine.txt" > "$r8/$n/run.sh"; done
echo b > "$r8/m/deps"
r "$r8" --all > /dev/null 2>&1 || die "scenario 8 fallito"
[ "$(tr '\n' ' ' < "$r8/ordine.txt")" = "a b m t " ] || die "ordine inatteso: $(tr '\n' ' ' < "$r8/ordine.txt")"

say "tutti gli scenari hanno dato l'esito atteso"
