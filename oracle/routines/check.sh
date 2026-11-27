#!/usr/bin/env bash
# Controllo di COBDATFT (oracle/stubs/COBDATFT.cbl) contro gli attesi scritti a mano leggendo
# app/asm/COBDATFT.asm (oracle/routines/expected/, tabella in cobdatft-casi.md e cobdatft-casi.tsv).
# 1. Coerenza tra tabella dei casi, elenco dei casi di prova e attesi (coerenza.sh): la tabella copre
#    ogni combinazione di selettori una e una sola volta; ogni atteso e' quello che la tabella prescrive.
# 2. Riesegue tutti i casi in una cartella nuova (nessun risultato di una corsa precedente).
# 3. Confronto esatto, caso per caso, del rapporto (codice di uscita, stdout con l'area in esadecimale
#    prima e dopo la CALL e il codice di ritorno, stderr, file creati) e dell'ambiente ricevuto.
# 4. Prove negative: attesi alterati; esecuzioni reali con la routine alterata (modifica un byte da
#    conservare, restituisce un codice diverso da 0, tratta casi non determinati come determinati) e con
#    il segnaposto di #4 rimesso al posto della routine; tabella e casi alterati; evidenze alterate.
# 5. MVSWAIT e l'opzione --sysin di esegui.sh (issue #36): mvswait-check.sh, con le sue prove negative.
. "$ORACLE_ROOT/lib.sh"

DIR="$ORACLE_ROOT/routines"
EXP="$DIR/expected"
TAB="$DIR/cobdatft-casi.tsv"
CASI="$DIR/casi.tsv"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

nomi_casi() { grep -v '^#' "$CASI" | tail -n +2 | cut -f1 | grep -v '^$'; }

# verifica OSSERVATI [ATTESI]: 0 solo se per ogni caso rapporto e ambiente coincidono con gli attesi e
# non ci sono rapporti di casi sconosciuti.
verifica() {
  local obs="$1" att="${2:-$EXP}" c errs=0 extra
  for c in $(nomi_casi); do
    if [ ! -f "$obs/$c.txt" ]; then echo "$c: rapporto assente"; errs=$((errs + 1))
    elif ! diff -u "$att/$c.txt" "$obs/$c.txt" > "$tmp/d"; then
      echo "$c: rapporto diverso dall'atteso:"; indent "$tmp/d"; errs=$((errs + 1)); fi
    if [ ! -f "$obs/$c.ambiente" ]; then echo "$c: ambiente non registrato"; errs=$((errs + 1))
    elif ! diff -u "$att/DATFTPRB.ambiente" "$obs/$c.ambiente" > "$tmp/d"; then
      echo "$c: ambiente diverso da quello fissato:"; indent "$tmp/d"; errs=$((errs + 1)); fi
  done
  extra="$(cd "$obs" && ls -A | sed -n 's/\.txt$//p' | LC_ALL=C sort | comm -23 - <(nomi_casi | LC_ALL=C sort) | tr '\n' ' ')"
  [ -z "$extra" ] || { echo "rapporti di casi non previsti: $extra"; errs=$((errs + 1)); }
  [ "$errs" -eq 0 ] || { echo "verifica fallita: $errs differenze"; return 1; }
  echo "verifica riuscita: $(nomi_casi | wc -l | tr -d ' ') casi, area byte per byte e codice come attesi"
}

# variante NOME SORGENTE: compila SORGENTE (sotto $tmp) come modulo COBDATFT con le opzioni fissate, lo
# mette accanto a una copia di DATFTPRB e riesegue tutti i casi con quegli artefatti.
variante() {
  local name="$1" src="$2" b="$tmp/$1/bin"
  mkdir -p "$tmp/$name/build" "$b"
  orun -v "$tmp/$name/build:/out" -- timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" \
    sh /oracle/build/compile.sh uno modulo "$(in_container "$src")" COBDATFT /out \
    > "$tmp/$name.log" 2>&1 || { cat "$tmp/$name.log" >&2; fail "compilazione della variante '$name' fallita"; }
  cp "$tmp/$name/build/bin/COBDATFT.so" "$BUILD_OUT/bin/DATFTPRB" "$b/" \
    || fail "preparazione degli artefatti della variante '$name' fallita"
  ROUTINES_BIN_DIR="$b" ROUTINES_OUT_DIR="$tmp/$name/obs" bash "$DIR/run.sh" >> "$tmp/$name.log" 2>&1 \
    || { cat "$tmp/$name.log" >&2; fail "esecuzione della variante '$name' fallita"; }
}
# sorgente NOME ESPRESSIONE-SED [ESPRESSIONE-SED]: copia alterata della routine in $tmp/src-NOME/COBDATFT.cbl
# (ogni espressione deve cambiare il file, altrimenti il controllo fallisce).
sorgente() {
  local name="$1"; shift
  mkdir -p "$tmp/src-$name"
  cp "$ORACLE_ROOT/stubs/COBDATFT.cbl" "$tmp/src-$name/COBDATFT.cbl"
  while [ $# -gt 0 ]; do mutate "$tmp/src-$name/COBDATFT.cbl" "$1"; shift; done
}

log "1. coerenza tra tabella, casi e attesi"
bash "$DIR/coerenza.sh" "$TAB" "$CASI" "$EXP" > "$tmp/c.out" 2>&1 || { indent "$tmp/c.out" >&2; fail "tabella, casi e attesi non coerenti"; }
indent "$tmp/c.out" >&2

log "2. casi rieseguiti in una cartella nuova"
ROUTINES_OUT_DIR="$tmp/obs" bash "$DIR/run.sh" || fail "prova di COBDATFT fallita"

log "3. confronto con gli attesi"
verifica "$tmp/obs" > "$tmp/v.out" 2>&1 || { cat "$tmp/v.out" >&2; fail "COBDATFT non si comporta come atteso"; }
indent "$tmp/v.out" >&2

log "4. prove negative"
# a) Un byte dell'atteso alterato: nella data d'uscita di D2A ('7' -> '8') e in un byte da conservare di
#    D1A (l'ultimo del messaggio di errore, X'A5' -> X'20').
mkdir -p "$tmp/att1"; cp "$EXP"/* "$tmp/att1/"
mutate "$tmp/att1/D2A.txt" 's/^\(DOPO  32 323032352d30332d3137a5a5a5a5a5a5a5a5a5a5 32 32303235303331\)37/\138/'
expect_fail "atteso di D2A con un byte della data d'uscita alterato" "D2A: rapporto diverso dall'atteso" verifica "$tmp/obs" "$tmp/att1"
expect_fail "atteso di D2A alterato: diverge dalla tabella" "D2A: l atteso scritto a mano diverge dalla tabella (C4) alla riga 6" \
  bash "$DIR/coerenza.sh" "$TAB" "$CASI" "$tmp/att1"
mkdir -p "$tmp/att2"; cp "$EXP"/* "$tmp/att2/"
mutate "$tmp/att2/D1A.txt" '/^DOPO /s/a5$/20/'
expect_fail "atteso di D1A con l'ultimo byte del messaggio alterato" "D1A: rapporto diverso dall'atteso" verifica "$tmp/obs" "$tmp/att2"

# b) La routine modifica un byte che doveva conservare.
#    - tipo 2: la terza copia scrive 3 byte invece di 2 (il nono byte della data d'uscita diventa spazio);
sorgente conserva 's/^           MOVE LK-COINPDT(9:2) TO LK-COOUTDT(7:2)\.$/           MOVE LK-COINPDT(9:2) TO LK-COOUTDT(7:3)./'
variante conserva "$tmp/src-conserva/COBDATFT.cbl"
expect_fail "routine che scrive il byte 31 (da conservare) nei casi di tipo 2" "D2A: rapporto diverso dall'atteso" verifica "$tmp/conserva/obs"
grep -qx 'DOPO  32 323032352d30332d3137a5a5a5a5a5a5a5a5a5a5 32 323032353033313720a5a5a5a5a5a5a5a5a5a5a5 a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5' "$tmp/conserva/obs/D2A.txt" \
  || fail "la variante 'conserva' non ha scritto il byte atteso: prova negativa non significativa"
#    - tutti i casi determinati: il messaggio di errore viene azzerato a spazi.
sorgente messaggio 's/^           MOVE 0 TO RETURN-CODE$/           MOVE SPACES TO LK-COERMSG MOVE 0 TO RETURN-CODE/'
variante messaggio "$tmp/src-messaggio/COBDATFT.cbl"
expect_fail "routine che riempie di spazi il messaggio di errore (da conservare)" "D1C: rapporto diverso dall'atteso" verifica "$tmp/messaggio/obs"

# c) La routine restituisce un codice diverso da 0.
sorgente codice 's/^           MOVE 0 TO RETURN-CODE$/           MOVE 4 TO RETURN-CODE/'
variante codice "$tmp/src-codice/COBDATFT.cbl"
expect_fail "routine che restituisce 4" "+RC  000000004" verifica "$tmp/codice/obs"

# d) Un caso non determinato trattato come determinato.
#    - al posto dell'arresto la routine ritorna al chiamante con codice 0 (tutti i non determinati);
sorgente ritorna 's/^           MOVE 97 TO RETURN-CODE$/           MOVE 0 TO RETURN-CODE/' 's/^           STOP RUN\.$/           GOBACK./'
variante ritorna "$tmp/src-ritorna/COBDATFT.cbl"
expect_fail "routine che non si ferma nei casi non determinati" "N4: rapporto diverso dall'atteso" verifica "$tmp/ritorna/obs"
#    - con ingresso 2 la routine ignora il tipo d'uscita 1 e formatta (caso N3);
sorgente uscita1 "s/^           IF LK-COOUTYPE = '1'\$/           IF LK-COOUTYPE = 'Z'/"
variante uscita1 "$tmp/src-uscita1/COBDATFT.cbl"
expect_fail "routine che formatta ingresso 2 con uscita 1" "N3: rapporto diverso dall'atteso" verifica "$tmp/uscita1/obs"
#    - riga 36: la routine non distingue piu' i 14 byte noti del pool dei letterali (CLC di 20 byte).
#      Si ferma per ogni '-' nel quinto byte della data (la classificazione troppo ampia del giro 1 della
#      PR #39): D1E e D1F, determinati, finirebbero in 97;
sorgente byte6 "s/^           IF LK-COINPDT(5:14) = '-INVALID INPUT'\$/           IF LK-COINPDT(5:1) = '-'/"
variante byte6 "$tmp/src-byte6/COBDATFT.cbl"
expect_fail "routine che si ferma per ogni '-' nel quinto byte (caso D1E)" "D1E: rapporto diverso dall'atteso" verifica "$tmp/byte6/obs"
expect_fail "routine che si ferma per ogni '-' nel quinto byte (caso D1F)" "D1F: rapporto diverso dall'atteso" verifica "$tmp/byte6/obs"
#      confronta solo 13 dei 14 byte noti: D1F, diverso solo nel quattordicesimo, finirebbe in 97;
sorgente prefisso13 "s/^           IF LK-COINPDT(5:14) = '-INVALID INPUT'\$/           IF LK-COINPDT(5:13) = '-INVALID INPU'/"
variante prefisso13 "$tmp/src-prefisso13/COBDATFT.cbl"
expect_fail "routine che confronta solo 13 byte del pool (caso D1F)" "D1F: rapporto diverso dall'atteso" verifica "$tmp/prefisso13/obs"
#      non si ferma mai alla riga 36: N5 (prefisso noto uguale, esito dipendente dai 6 byte ignoti)
#      verrebbe formattato con codice 0.
sorgente prefisso0 "s/^           IF LK-COINPDT(5:14) = '-INVALID INPUT'\$/           IF LK-COINPDT(5:14) = SPACES/"
variante prefisso0 "$tmp/src-prefisso0/COBDATFT.cbl"
expect_fail "routine che non si ferma con il prefisso -INVALID INPUT (caso N5)" "N5: rapporto diverso dall'atteso" verifica "$tmp/prefisso0/obs"
#    - attesi dei casi nuovi o cambiati alterati: D1E (un byte della data d'uscita), N5 (codice 97 -> 0).
mkdir -p "$tmp/att3"; cp "$EXP"/* "$tmp/att3/"
mutate "$tmp/att3/D1E.txt" 's/^\(DOPO  31 323032352d30332d3137a5a5a5a5a5a5a5a5a5a5 31 323032352d\)2d/\130/'
expect_fail "atteso di D1E con il byte 28 alterato" "D1E: rapporto diverso dall'atteso" verifica "$tmp/obs" "$tmp/att3"
mkdir -p "$tmp/att4"; cp "$EXP"/* "$tmp/att4/"
mutate "$tmp/att4/N5.txt" '2s/^97$/0/'
expect_fail "atteso di N5 con codice 0" "N5: rapporto diverso dall'atteso" verifica "$tmp/obs" "$tmp/att4"
expect_fail "atteso di N5 con codice 0: diverge dalla tabella" "N5: l atteso scritto a mano diverge dalla tabella (C2) alla riga 2" \
  bash "$DIR/coerenza.sh" "$TAB" "$CASI" "$tmp/att4"
cp "$CASI" "$tmp/casi-n5.tsv"
mutate "$tmp/casi-n5.tsv" 's/^N5	11ABCD-INVALID INPUT	C2$/N5	11ABCD-INVALID INPUT	C1/'
expect_fail "casi: N5 dichiarato della combinazione C1" "N5: dichiarato C1, ma per la tabella il PARM 11ABCD-INVALID INPUT e della combinazione C2" \
  bash "$DIR/coerenza.sh" "$TAB" "$tmp/casi-n5.tsv" "$EXP"
cp "$CASI" "$tmp/casi-d1f.tsv"
mutate "$tmp/casi-d1f.tsv" 's/^D1F	11ABCD-INVALID INPUX	C1$/D1F	11ABCD-INVALID INPUX	C2/'
expect_fail "casi: D1F dichiarato della combinazione C2" "D1F: dichiarato C2, ma per la tabella il PARM 11ABCD-INVALID INPUX e della combinazione C1" \
  bash "$DIR/coerenza.sh" "$TAB" "$tmp/casi-d1f.tsv" "$EXP"
#    - nella tabella: C5 dichiarata determinata (con le scritture di C4), o N3 dichiarato del caso C4.
cp "$TAB" "$tmp/tab-c5.tsv"
mutate "$tmp/tab-c5.tsv" 's/^C5	2	1	-	non-determinato	-	-	/C5	2	1	-	determinato	23-26<2-5;27-28<7-8;29-30<10-11	1-22;31-80	/'
expect_fail "tabella: C5 dichiarata determinata" "N3: l atteso scritto a mano diverge dalla tabella (C5) alla riga 2" \
  bash "$DIR/coerenza.sh" "$tmp/tab-c5.tsv" "$CASI" "$EXP"
cp "$CASI" "$tmp/casi-n3.tsv"
mutate "$tmp/casi-n3.tsv" 's/^N3	212025-03-17	C5$/N3	212025-03-17	C4/'
expect_fail "casi: N3 dichiarato della combinazione C4" "N3: dichiarato C4, ma per la tabella il PARM 212025-03-17 e della combinazione C5" \
  bash "$DIR/coerenza.sh" "$TAB" "$tmp/casi-n3.tsv" "$EXP"

# e) Il segnaposto di #4 rimesso al posto della routine: i programmi lo caricano (stesso nome, stessa
#    cartella dei moduli) e si fermano con 98.
mkdir -p "$tmp/src-segnaposto"
cat > "$tmp/src-segnaposto/COBDATFT.cbl" <<'EOF'
      *****************************************************************
      * COBDATFT - segnaposto dell'oracle MEN-B (non e' codice del
      * legacy). Nel legacy COBDATFT e' una routine assembler
      * (app/asm/COBDATFT.asm) di conversione di date, chiamata da
      * CBACT01C. La sua semantica non e' implementata qui (issue #24):
      * se viene chiamata, scrive una riga riconoscibile su stderr e
      * termina l'esecuzione con codice di uscita 98, fisso.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. COBDATFT.
       PROCEDURE DIVISION.
           DISPLAY 'MENB-ORACLE SEGNAPOSTO: COBDATFT NON IMPLEMENTATO'
                   ' (ISSUE #24)'
                   UPON SYSERR
           MOVE 98 TO RETURN-CODE
           STOP RUN.
EOF
variante segnaposto "$tmp/src-segnaposto/COBDATFT.cbl"
expect_fail "segnaposto di #4 al posto di COBDATFT" "+MENB-ORACLE SEGNAPOSTO: COBDATFT NON IMPLEMENTATO (ISSUE #24)" verifica "$tmp/segnaposto/obs"
for c in $(nomi_casi); do
  [ "$(sed -n 2p "$tmp/segnaposto/obs/$c.txt")" = 98 ] || fail "con il segnaposto il caso $c non termina con 98: il modulo caricato non e' quello della variante"
done
log "   e con il segnaposto ogni caso termina con 98: il modulo caricato e' quello in /oracle-bin"

# f) Tabella che non copre le combinazioni una e una sola volta.
cp "$TAB" "$tmp/tab-doppia.tsv"
mutate "$tmp/tab-doppia.tsv" 's/^C1	1	non-2	byte6-19!=-INVALID INPUT	/C1	1	non-2	-	/'
expect_fail "tabella: C1 senza condizione sui byte 6-19 (si sovrappone a C2)" "tabella: piu righe per ingresso 1, uscita 1, byte 6-19 -INVALID INPUT" \
  bash "$DIR/coerenza.sh" "$tmp/tab-doppia.tsv" "$CASI" "$EXP"
cp "$TAB" "$tmp/tab-byte.tsv"
mutate "$tmp/tab-byte.tsv" '/^C4	/s/	1-22;31-80	/	1-22;30-80	/'
expect_fail "tabella: byte 30 di C4 sia scritto sia conservato" "tabella C4: il byte 30 e scritto o conservato 2 volte" \
  bash "$DIR/coerenza.sh" "$tmp/tab-byte.tsv" "$CASI" "$EXP"

# g) Evidenze alterate o mancanti.
mkdir -p "$tmp/manca"; cp "$tmp/obs"/* "$tmp/manca/"; rm "$tmp/manca/N2.txt"
expect_fail "rapporto di N2 assente" "N2: rapporto assente" verifica "$tmp/manca"
mkdir -p "$tmp/amb"; cp "$tmp/obs"/* "$tmp/amb/"
mutate "$tmp/amb/D1B.ambiente" 's#^COB_LIBRARY_PATH=/oracle-bin$#COB_LIBRARY_PATH=/altrove#'
expect_fail "ambiente di D1B con un'altra cartella dei moduli" "D1B: ambiente diverso" verifica "$tmp/amb"
mkdir -p "$tmp/piu"; cp "$tmp/obs"/* "$tmp/piu/"; cp "$tmp/piu/D1A.txt" "$tmp/piu/D9Z.txt"
expect_fail "rapporto di un caso non previsto" "rapporti di casi non previsti: D9Z" verifica "$tmp/piu"

log "5. MVSWAIT e --sysin di esegui.sh (issue #36)"
bash "$DIR/mvswait-check.sh" || fail "controllo di MVSWAIT fallito"
log "controllo superato"
