#!/usr/bin/env bash
# Controllo della build dell'oracle.
# 1. Rifa' la build (oracle/build/run.sh): l'output viene cancellato e rigenerato, quindi nessun
#    artefatto di una corsa precedente puo' passare per attuale.
# 2. Verifica (oracle/build/verifica.sh, nel container) contro l'ELENCO FISSO qui sotto: gli 11 programmi
#    nell'elenco della build con il loro tipo, compilati senza errori, ciascuno con il suo artefatto
#    (eseguibile con main e programma, o modulo che esporta il programma); opzioni usate = cobc.opts;
#    compilatore, gestore dei file indicizzati e pacchetti come fissati nel Dockerfile; impronta valida
#    (input e artefatti attuali).
# 3. Le opzioni di cobc.opts sono quelle fissate qui sotto (cambiarle richiede di cambiare anche il controllo).
# 4. I passi dei criteri di accettazione esistono, con i loro script e dipendenze.
# 5. Prove negative per ognuna delle verifiche precedenti, tra cui un programma tolto dall'elenco della
#    build ricompilando davvero e una build interrotta dal limite di tempo.
. "$ORACLE_ROOT/lib.sh"

# Elenco fisso: i programmi del legacy che `cobc -fsyntax-only -std=ibm` accetta (analysis/tools/out/gnucobol)
# e il tipo letto nel sorgente (motivi in oracle/programs.tsv).
FISSO="CBACT01C:eseguibile CBACT02C:eseguibile CBACT03C:eseguibile CBACT04C:eseguibile CBCUS01C:eseguibile
CBSTM03B:modulo CBTRN01C:eseguibile CBTRN02C:eseguibile CBTRN03C:eseguibile COBSWAIT:eseguibile CSUTLDTC:modulo"
[ "$(echo $FISSO | wc -w | tr -d ' ')" -eq 11 ] || fail "l'elenco fisso del controllo non ha 11 voci"
# Opzioni fissate (motivi in oracle/cobc.opts e oracle/README.md).
OPZIONI_FISSE="-std=ibm -fbinary-truncate -fsingle-quote -Wall -I/legacy/app/cpy"
# Passi dei criteri di accettazione: nome e dipendenza (- = nessuna). selftest ha solo check.sh.
PASSI="build:- avvio:build avviatore:build abend:build selftest:-"

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

# verifica ELENCO OUT: verifica nel container + impronta (sull'host, con git).
verifica() {
  local elenco="$1" out="$2" rc=0 p
  # shellcheck disable=SC2086
  orun -- timeout 300 sh /oracle/build/verifica.sh "$(in_container "$elenco")" "$(in_container "$out")" $FISSO || rc=1
  if p="$(stamp_problem "$out")"; then echo "impronta valida: input e artefatti attuali"
  else echo "DIFETTO: impronta: $p"; rc=1; fi
  return "$rc"
}

# opzioni_fisse FILE: le opzioni del file (righe non commento, prima parola) sono esattamente OPZIONI_FISSE.
opzioni_fisse() {
  local got
  got="$(sed -e 's/#.*$//' "$1" | awk 'NF {print $1}' | tr '\n' ' ' | sed 's/ $//')"
  [ "$got" = "$OPZIONI_FISSE" ] || { echo "opzioni in $(rel "$1"): '$got', fissate nel controllo: '$OPZIONI_FISSE'"; return 1; }
  echo "opzioni conformi: $got"
}

# passi_presenti RADICE: ogni passo dell'elenco ha check.sh, quelli con dipendenza hanno run.sh e deps giusto.
passi_presenti() {
  local root="$1" v n d errs=0
  for v in $PASSI; do
    n="${v%%:*}"; d="${v#*:}"
    [ -f "$root/$n/check.sh" ] || { echo "passo $n: manca check.sh"; errs=$((errs + 1)); }
    if [ "$d" != - ]; then
      [ -f "$root/$n/run.sh" ] || { echo "passo $n: manca run.sh"; errs=$((errs + 1)); }
      grep -qx "$d" "$root/$n/deps" 2>/dev/null || { echo "passo $n: deps non contiene $d"; errs=$((errs + 1)); }
    fi
  done
  [ "$errs" -eq 0 ] || return 1
  echo "passi presenti: $PASSI"
}

log "1. build rifatta da zero"
bash "$ORACLE_ROOT/build/run.sh" || fail "build fallita"

log "2. verifica contro l'elenco fisso"
verifica "$ORACLE_ROOT/programs.tsv" "$BUILD_OUT" > "$tmp/v.out" 2>&1 || { indent "$tmp/v.out" >&2; fail "la build non supera la verifica"; }
indent "$tmp/v.out" >&2

log "3. opzioni fissate"
opzioni_fisse "$ORACLE_ROOT/cobc.opts" > "$tmp/o.out" 2>&1 || { indent "$tmp/o.out" >&2; fail "cobc.opts diverso dalle opzioni fissate"; }
indent "$tmp/o.out" >&2

log "4. passi dei criteri di accettazione"
passi_presenti "$ORACLE_ROOT" > "$tmp/p.out" 2>&1 || { indent "$tmp/p.out" >&2; fail "mancano passi dell'oracle"; }
indent "$tmp/p.out" >&2

log "5. prove negative"
copia() { rm -rf "$tmp/$1"; cp -R "$BUILD_OUT" "$tmp/$1" && cp "$ORACLE_ROOT/programs.tsv" "$tmp/$1.tsv"; }

# Un programma tolto dall'elenco della build: si ricompila davvero con l'elenco alterato.
cp "$ORACLE_ROOT/programs.tsv" "$tmp/senza.tsv"
mutate "$tmp/senza.tsv" '/^CBTRN03C	/d'
ORACLE_BUILD_OUT="$tmp/senza" BUILD_ELENCO="$tmp/senza.tsv" bash "$ORACLE_ROOT/build/run.sh" > "$tmp/senza.log" 2>&1 \
  || { indent "$tmp/senza.log" >&2; fail "ricompilazione con l'elenco alterato fallita"; }
expect_fail "CBTRN03C tolto dall'elenco della build (ricompilato)" "CBTRN03C:eseguibile manca nell'elenco della build" verifica "$tmp/senza.tsv" "$tmp/senza"
expect_fail "CBTRN03C tolto dall'elenco della build: artefatto assente" "CBTRN03C: eseguibile assente" verifica "$tmp/senza.tsv" "$tmp/senza"
expect_fail "build con elenco sostituito: senza impronta" "DIFETTO: impronta: build assente o incompleta" verifica "$tmp/senza.tsv" "$tmp/senza"

# Una compilazione che fallisce fa fallire la build.
cp "$ORACLE_ROOT/programs.tsv" "$tmp/rotto.tsv"
mutate "$tmp/rotto.tsv" 's#^\(CBACT02C	\)app/cbl/CBACT02C\.cbl	#\1app/cbl/NONESISTE.cbl	#'
expect_fail "sorgente di CBACT02C inesistente: la build fallisce" "compilazione fallita" \
  env ORACLE_BUILD_OUT="$tmp/rotto" BUILD_ELENCO="$tmp/rotto.tsv" bash "$ORACLE_ROOT/build/run.sh"
# Una build interrotta (qui dal limite di tempo, 1 secondo) fallisce e non lascia l'impronta, quindi i
# passi successivi rifiutano i suoi artefatti parziali.
expect_fail "build interrotta dal limite di tempo di 1 s" "compilazione fallita" \
  env ORACLE_BUILD_OUT="$tmp/lenta" ORACLE_TIMEOUT_COMPILE=1 bash "$ORACLE_ROOT/build/run.sh"
[ ! -e "$tmp/lenta/IMPRONTA" ] || fail "una build interrotta ha lasciato l'impronta"
log "   e la build interrotta non ha lasciato l'impronta"

copia art; rm "$tmp/art/bin/CBACT04C"
expect_fail "eseguibile CBACT04C cancellato" "CBACT04C: eseguibile assente" verifica "$tmp/art.tsv" "$tmp/art"
copia mod; rm "$tmp/mod/bin/CBSTM03B.so"
expect_fail "modulo CBSTM03B cancellato" "CBSTM03B: modulo assente" verifica "$tmp/mod.tsv" "$tmp/mod"
copia tipo; mutate "$tmp/tipo.tsv" 's/^\(CSUTLDTC	[^	]*	\)modulo	/\1eseguibile	/'
expect_fail "CSUTLDTC dichiarato eseguibile nell'elenco della build" "CSUTLDTC:modulo manca nell'elenco della build" verifica "$tmp/tipo.tsv" "$tmp/tipo"
copia scambio; mv "$tmp/scambio/bin/CSUTLDTC.so" "$tmp/scambio/bin/CSUTLDTC"
expect_fail "modulo CSUTLDTC sostituito da un file con nome di eseguibile" "CSUTLDTC: modulo assente" verifica "$tmp/scambio.tsv" "$tmp/scambio"
copia sost; cp "$tmp/sost/bin/CBACT02C" "$tmp/sost/bin/CBACT03C"
expect_fail "eseguibile CBACT03C sostituito da CBACT02C" "CBACT03C: l'eseguibile non contiene il programma CBACT03C" verifica "$tmp/sost.tsv" "$tmp/sost"
expect_fail "eseguibile sostituito dopo la build: impronta" "artefatti della build cambiati" verifica "$tmp/sost.tsv" "$tmp/sost"
copia errori; mutate "$tmp/errori/compilazione.tsv" 's/^\(CBTRN02C	legacy	eseguibile	0	1	\)0$/\13/'
expect_fail "errori di CBTRN02C in compilazione.tsv 0 -> 3" "CBTRN02C: in compilazione.tsv tipo, esito o errori non validi" verifica "$tmp/errori.tsv" "$tmp/errori"
copia avv; mutate "$tmp/avv/compilazione.tsv" 's/^\(CBTRN03C	legacy	eseguibile	0	\)1	/\10	/'
expect_fail "avvertimenti di CBTRN03C in compilazione.tsv 1 -> 0 (il log ne ha 1)" "CBTRN03C: avvertimenti/errori in compilazione.tsv diversi" verifica "$tmp/avv.tsv" "$tmp/avv"
copia opz; mutate "$tmp/opz/opzioni.txt" '/^-fbinary-truncate$/d'
expect_fail "opzione -fbinary-truncate tolta da quelle usate" "opzioni: usate" verifica "$tmp/opz.tsv" "$tmp/opz"
copia cmd; mutate "$tmp/cmd/log/CBACT02C.log" '1s/ -fbinary-truncate / /'
expect_fail "CBACT02C compilato senza -fbinary-truncate" "CBACT02C: compilato con opzioni diverse" verifica "$tmp/cmd.tsv" "$tmp/cmd"
copia isam; mutate "$tmp/isam/ambiente.txt" 's/^indexed file handler     : BDB$/indexed file handler     : VBISAM/'
expect_fail "gestore dei file indicizzati diverso da BDB" "ambiente: manca la riga 'indexed file handler     : BDB'" verifica "$tmp/isam.tsv" "$tmp/isam"
copia impr; mutate "$tmp/impr/IMPRONTA" '1s/^input ./input x/'
expect_fail "impronta degli input alterata" "build non aggiornata" verifica "$tmp/impr.tsv" "$tmp/impr"

cp "$ORACLE_ROOT/cobc.opts" "$tmp/cobc.opts"; mutate "$tmp/cobc.opts" 's/^-fbinary-truncate$/# -fbinary-truncate/'
expect_fail "-fbinary-truncate tolto da cobc.opts" "fissate nel controllo" opzioni_fisse "$tmp/cobc.opts"
cp "$ORACLE_ROOT/cobc.opts" "$tmp/cobc2.opts"; mutate "$tmp/cobc2.opts" '$a\
-debug'
expect_fail "opzione -debug aggiunta a cobc.opts" "fissate nel controllo" opzioni_fisse "$tmp/cobc2.opts"

mkdir -p "$tmp/passi"
for v in $PASSI; do
  n="${v%%:*}"; d="${v#*:}"; mkdir -p "$tmp/passi/$n"; : > "$tmp/passi/$n/check.sh"
  [ "$d" = - ] || { : > "$tmp/passi/$n/run.sh"; echo "$d" > "$tmp/passi/$n/deps"; }
done
passi_presenti "$tmp/passi" > /dev/null || fail "la struttura di prova dei passi non e' valida"
rm "$tmp/passi/avvio/check.sh"
expect_fail "passo avvio senza check.sh" "passo avvio: manca check.sh" passi_presenti "$tmp/passi"
rm -r "$tmp/passi/abend"
expect_fail "passo abend cancellato" "passo abend: manca check.sh" passi_presenti "$tmp/passi"
log "controllo superato"
