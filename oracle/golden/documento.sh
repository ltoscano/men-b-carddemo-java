#!/bin/sh
# Eseguito DENTRO il container dell'oracle da genera.sh (issue #55). Scrive docs/legacy-map/golden-readacct.md (in USCITA;
# run.sh lo pubblica): scenari, file, dimensioni, impronte, che cosa e' riferimento e che cosa osservazione, campi non
# determinati, correzioni dell'oracle, console, differenze GnuCOBOL / z/OS con le fonti, osservazioni e limiti.
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0; 1 errore.
# Uso: documento.sh GENERATI TABELLE USCITA
set -u
die() { echo "documento.sh: $*" >&2; rm -f "$usc.parziale" "$usc.file" "$usc.o.hex" "$usc.a.hex"; exit 1; }
[ $# -eq 3 ] || { echo "documento.sh: uso: documento.sh GENERATI TABELLE USCITA" >&2; exit 1; }
g="$1"; t="$2"; usc="$3"
[ -d "$g" ] || die "cartella assente: $g"
# file: "<percorso relativo> <byte> <sha256>" per ogni file dei generati, in ordine
elenco="$(cd "$g" && find . -type f)" || die "elenco dei file fallito (find)"
elenco="$(LC_ALL=C sort <<FINE
$elenco
FINE
)" || die "ordinamento fallito (sort)"
: > "$usc.file" || die "file temporaneo non scrivibile"
for f in $elenco; do
  b="$(wc -c < "$g/$f")" || die "dimensione di $f non letta (wc)"
  b="${b#"${b%%[! ]*}"}"; b="${b%"${b##*[! ]}"}"
  h="$(sha256sum < "$g/$f")" || die "impronta di $f non calcolata (sha256sum)"
  h="${h%% *}"
  case "$h" in *[!0-9a-f]*|'') die "impronta non valida: $h" ;; esac
  echo "${f#./} $b $h" >> "$usc.file" || die "elenco non scritto"
done
natura() {
  case "$1" in
    golden/*/OUTFILE.riferimento.txt|golden/*/ARRYFILE.riferimento.txt) echo "**riferimento di parita'** (correzioni applicate, esclusioni mascherate con \`**\`)" ;;
    golden/*/VBRCFILE.riferimento.txt) echo "**riferimento di parita'**: sequenza dei record logici" ;;
    golden/*/console.riferimento.txt) echo "**riferimento di parita'** per le righe di classe a; le altre sono marcate \`#OSSERVAZIONE\`" ;;
    golden/*/OUTFILE|golden/*/ARRYFILE) echo "file fisico dell'oracle (osservazione: il riferimento e' il .riferimento.txt)" ;;
    golden/*/VBRCFILE) echo "file fisico GnuCOBOL a record variabili (osservazione)" ;;
    golden/*/VBRCFILE.logici.txt) echo "record logici estratti dal fisico (estrai-vb.sh)" ;;
    golden/*/rapporto.txt) echo "rapporto di esegui.sh: codice di uscita (riferimento: 0), stdout, stderr (osservazione), file" ;;
    golden/*/ambiente.txt) echo "variabili ricevute dal programma" ;;
    golden/*/ingresso.rec) echo "ingresso dello scenario (record di 300 byte)" ;;
    */MARCATURA) echo "marcatura" ;;
    osservazioni/*) echo "osservazione" ;;
    *) echo "-" ;;
  esac
}
# osservati SCENARIO DIR: per ogni esclusione che riguarda lo scenario, i byte che l'oracle ha scritto in quelle
# posizioni nel file fisico (valori distinti, con il numero di record); righe di tabella Markdown.
osservati() {
  od -An -v -tx1 "$2/OUTFILE" > "$usc.o.hex" || die "od di $2/OUTFILE fallito"
  od -An -v -tx1 "$2/ARRYFILE" > "$usc.a.hex" || die "od di $2/ARRYFILE fallito"
  awk -F '\t' -v S="$1" -v FE="$t/esclusioni.tsv" -v FO="$usc.o.hex" -v FA="$usc.a.hex" -v FV="$2/VBRCFILE.logici.txt" '
    function ch(x) { return sprintf("%c", index("0123456789abcdef", substr(x, 1, 1)) * 16 + index("0123456789abcdef", substr(x, 2, 1)) - 17) }
    function chiave(h,   i, s) { s = ""; for (i = 1; i <= 21; i += 2) s = s ch(substr(h, i, 2)); return s }
    FILENAME == FE { if ($0 ~ /^#/ || $0 ~ /^scenario\t/ || $0 == "") next; if ($1 != "*" && $1 != S) next
      ne++; EF[ne] = $2; EK[ne] = $3; EP[ne] = $4 + 0; EN[ne] = $5 + 0; next }
    FILENAME == FO { m = split($0, z, " "); for (i = 1; i <= m; i++) O[++no] = z[i]; next }
    FILENAME == FA { m = split($0, z, " "); for (i = 1; i <= m; i++) A[++na] = z[i]; next }
    FILENAME == FV { split($0, z, " "); nv++; REC["VBRC" (nv % 2 ? 1 : 2), ++NR2["VBRC" (nv % 2 ? 1 : 2)]] = z[3]; next }
    END {
      for (j = 1; j <= no / 107; j++) { s = ""; for (i = 1; i <= 107; i++) s = s O[(j - 1) * 107 + i]; REC["OUTFILE", j] = s }; NR2["OUTFILE"] = no / 107
      for (j = 1; j <= na / 110; j++) { s = ""; for (i = 1; i <= 110; i++) s = s A[(j - 1) * 110 + i]; REC["ARRYFILE", j] = s }; NR2["ARRYFILE"] = na / 110
      for (e = 1; e <= ne; e++) { delete V; nd = 0; lista = ""
        for (j = 1; j <= NR2[EF[e]]; j++) { s = REC[EF[e], j]; if (EK[e] != "*" && chiave(s) != EK[e]) continue
          b = substr(s, 2 * EP[e] - 1, 2 * EN[e]); if (!(b in V)) { V[b] = 0; ORD[++nd] = b }; V[b]++ }
        for (i = 1; i <= nd; i++) lista = lista (i > 1 ? "; " : "") "`" ORD[i] "` (" V[ORD[i]] " record)"
        printf "| %s | %s | %s | %d-%d | %s |\n", S, EF[e], EK[e], EP[e], EP[e] + EN[e] - 1, (nd ? lista : "nessun record") }
    }' "$t/esclusioni.tsv" "$usc.o.hex" "$usc.a.hex" "$2/VBRCFILE.logici.txt" || die "byte osservati non resi (awk)"
  rm -f "$usc.o.hex" "$usc.a.hex" || die "temporanei non rimossi"
}
tabella() { # tabella FILE COLONNE...: righe dati di una tabella TSV (salta commenti e intestazione) in Markdown
  awk -F '\t' -v C="$2" 'BEGIN { n = split(C, c, ",") }
    /^#/ || FNR == 0 || $0 == "" { next }
    !h { h = 1; next }
    { s = "|"; for (i = 1; i <= n; i++) { v = $(c[i]); gsub(/\|/, "\\|", v); s = s " " v " |" }; print s }' "$1"
}
{
cat <<'FINE' || die "testo non scritto (cat)"
# Golden del job READACCT (`CBACT01C`): l'output di riferimento del pilota batch (issue #55)

Documento generato da `./oracle/run.sh golden` (`oracle/golden/`): non modificarlo a mano. I file elencati sono in `oracle/golden/readacct/generati/`; le tabelle scritte a mano in `oracle/golden/readacct/`.

## Cosa si fa

Il programma pilota `CBACT01C` (job `app/jcl/READACCT.jcl`, passo `STEP05`) gira nell'oracle GnuCOBOL (`oracle/esegui.sh`, nomi DD del JCL: `DD_ACCTFILE`, `DD_OUTFILE`, `DD_ARRYFILE`, `DD_VBRCFILE`) su tre ingressi noti. Il passo `PREDEL` del JCL cancella le tre uscite prima del programma: l'oracle parte da una cartella di lavoro vuota (creata da `esegui.sh`). Cio' che il programma scrive, con le correzioni e le esclusioni dichiarate, e' il valore atteso del test di parita' Java.

| Scenario | Classe | Ingresso | Record |
| --- | --- | --- | --- |
| `esempio` | riferimento di parita' | `analysis/oracle-dati/out/ACCTFILE.rec` (i 50 record di `AWS.M2.CARDDEMO.ACCTDATA.PS`, #53), letto dal file indicizzato del passo `dati` | 50 |
| `mirato` | riferimento di parita' | esempio con le 10 sostituzioni canoniche di `sostituzioni-mirato.tsv`, caricato con `oracle/dati/carica.sh` (#53) | 50 |
| `osservazione` | **osservazione, non golden** | mirato con le 4 sostituzioni di `sostituzioni-osservazione.tsv` (debito di ciclo diverso da zero, zero negativo, segno alternativo) | 50 |

Ogni ingresso derivato e' verificato da `differenze.sh` (la differenza completa dalla base coincide con la tabella; valori e canonicita' decodificati con le regole di #23) e ogni proprieta' richiesta (`proprieta.tsv`) e' verificata sul file indicizzato effettivamente letto con `IDXLEGGI` dopo il caricamento (`proprieta.sh`).

## Sostituzioni dello scenario mirato

| Chiave | Campo | Byte | Valore | Motivo |
| --- | --- | --- | --- | --- |
FINE
tabella "$t/sostituzioni-mirato.tsv" "1,2,5,7,9" || die "tabella non resa"
cat <<'FINE' || die "testo non scritto (cat)"

Sostituzioni aggiunte dallo scenario osservazione:

| Chiave | Campo | Byte | Valore | Canonica | Motivo |
| --- | --- | --- | --- | --- | --- |
FINE
tabella "$t/sostituzioni-osservazione.tsv" "1,2,5,7,8,9" || die "tabella non resa"
cat <<'FINE' || die "testo non scritto (cat)"

## File, dimensioni e impronte

FINE
printf '| File | Byte | SHA-256 | Natura |\n| --- | --- | --- | --- |\n' || die "intestazione non scritta"
while read -r f b h; do printf '| `%s` | %s | `%s` | %s |\n' "$f" "$b" "$h" "$(natura "$f")" || die "elenco non reso"; done < "$usc.file"
cat <<'FINE' || die "testo non scritto (cat)"

Formato dei file prodotti da GnuCOBOL: OUTFILE e ARRYFILE sono record fissi di 107 e 110 byte senza terminatori ne' intestazioni (dimensione esatta 107 x 50 e 110 x 50, controllo 2). VBRCFILE (`RECORDING MODE IS V`, `RECORD VARYING FROM 10 TO 80`) ha davanti a ogni record 2 byte di lunghezza in big-endian, senza l'intestazione, e 2 byte `00`: formato `COB_VARSEQ_FORMAT` 0, il predefinito (`/usr/share/gnucobol/config/runtime.cfg` dell'immagine: "0 means 2 byte record length (big-endian) + 2 NULs"; "'length' is the data length, does not include the prefix"). Su z/OS (`RECFM=VB,LRECL=84`) il descrittore di record e' di 4 byte e comprende se stesso: il formato fisico non e' un riferimento; il riferimento e' la sequenza dei record logici (due per conto, 12 e 39 byte), estratta con `estrai-vb.sh` e riletta per una via indipendente dal verificatore.

## Che cosa e' riferimento di parita' e che cosa e' osservazione

| Uscita | Riferimento di parita' (scenari esempio e mirato) | Osservazione |
| --- | --- | --- |
| OUTFILE | `OUTFILE.riferimento.txt`: 105 byte su 107 per record (77-78 esclusi) | il file fisico, compresi i byte 77-78 (`00 00` nell'oracle) |
| ARRYFILE | `ARRYFILE.riferimento.txt`: 110 byte su 110, con i byte 80 e 99 corretti (vedi sotto) | il file fisico, con i byte 80 e 99 come li scrive GnuCOBOL (`30`) |
| VBRCFILE | `VBRCFILE.riferimento.txt`: lunghezza e contenuto di ogni record logico | il file fisico |
| Console | `console.riferimento.txt`: righe di classe a | righe di classe b e c (tabella sotto) |
| Codice di uscita | 0 | - |
| stderr | - | avviso di libxml2 e tre righe `libcob: warning: implicit CLOSE` (il programma chiude solo ACCTFILE, riga 390) |
| Scenario osservazione | - | tutto (cartella `osservazioni/osservazione`, marcata `OSSERVAZIONE`) |
| Riesecuzione | - | `osservazioni/riesecuzione` (controllo 6) |

Il file fisico differisce dal riferimento solo nelle posizioni delle tabelle delle correzioni e delle esclusioni (`coerenza.sh`).

## Campi non determinati dal sorgente

Ricerca dei campi delle aree di uscita non valorizzati a ogni record (righe di `app/cbl/CBACT01C.cbl`):

| Campo o area | Determinato? | Perche' |
| --- | --- | --- |
| `OUT-ACCT-REISSUE-DATE` byte 9-10 (OUTFILE 77-78) | **no** | `CODATECN-0UT-DATE` e' `X(20)` senza `VALUE` (`app/cpy/CODATECN.cpy:39-51`); `COBDATFT` (caso C4) ne scrive i primi 8 byte (`app/asm/COBDATFT.asm:51-53`); il programma ne copia 10 (righe 223-233). Su z/OS il valore iniziale senza `VALUE` e' imprevedibile (IBM, *Enterprise COBOL for z/OS 6.4 Language Reference*, VALUE clause: "If the initial value is not explicitly specified, the value is unpredictable", https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=entry-value-clause); nell'oracle `defaultbyte 0` da' `00 00`. Esclusi |
| `OUT-ACCT-CURR-CYC-DEBIT` con debito d'ingresso diverso da zero | **no** | righe 236-238: nessuna istruzione lo valorizza; resta il contenuto dell'area del record. IBM non lo definisce: "the information in the area referenced by record-name-1 is unavailable, except as specified by the SAME RECORD AREA clause" (*Enterprise COBOL 6.1 Language Reference*, Common processing facilities, frasi INTO e FROM, https://www.ibm.com/docs/en/SS6SG3_6.1.0/lr/ref/rlpdscpf.html). Nei dati degli scenari esempio e mirato il debito e' sempre zero (verificato da `proprieta.sh`): l'uscita e' 2525,00, determinata. Solo nello scenario osservazione |
| `ARR-ACCT-CURR-BAL(4)`, `(5)`, `ARR-ACCT-CURR-CYC-DEBIT(4)`, `(5)`, `ARR-FILLER` | si' | `INITIALIZE ARR-ARRAY-REC` a ogni record (riga 169): ZERO ai numerici, SPACE agli alfanumerici; `ARR-FILLER` e' un nome, non la parola `FILLER`, quindi e' inizializzato (IBM, INITIALIZE statement rules, regole 1 e 2). Per due byte l'oracle sbaglia: sezione seguente |
| byte di `VBR-REC` oltre la lunghezza scritta | non scritti | `WRITE VBR-REC` scrive `WS-RECD-LEN` byte (12 o 39, righe 288-290, 303-305): i byte oltre non entrano nel record logico |
| `VBRC-REC1` | si' | `INITIALIZE` (riga 175) e poi i due campi (righe 277-279) |
| `VBRC-REC2` | si' | non inizializzato, ma i suoi quattro campi (39 byte) sono valorizzati a ogni record (righe 277-282) |
| `WS-REISSUE-DATE` / `WS-ACCT-REISSUE-YYYY` | si' | riceve `ACCT-REISSUE-DATE` a ogni record (righe 223-224) |
| aree di `CODATECN` tra una chiamata e l'altra | si', tranne i byte 9-20 della data d'uscita | tipo, data d'ingresso (10 byte piu' 10 spazi di riempimento del `MOVE`) e tipo d'uscita a ogni record (righe 223-226); `COBDATFT` scrive i primi 8 byte della data d'uscita; il messaggio d'errore non e' mai scritto nel caso C4 e non e' copiato in uscita |

Tabella delle posizioni escluse (`esclusioni.tsv`, unica fonte delle maschere):

| Scenario | File | Chiave | Posizione | Lunghezza | Motivo | Riga |
| --- | --- | --- | --- | --- | --- | --- |
FINE
tabella "$t/esclusioni.tsv" "1,2,3,4,5,6,7" || die "tabella non resa"
cat <<'FINE' || die "testo non scritto (cat)"

Che cosa ha scritto l'oracle nelle posizioni escluse (osservazione, letta dai file fisici; nello scenario osservazione: debito del primo record dall'area iniziale, del record 20 dal record precedente; zero negativo conservato dal `MOVE` di GnuCOBOL; segno alternativo riscritto in forma canonica):

| Scenario | File | Chiave | Byte | Valori osservati |
| --- | --- | --- | --- | --- |
FINE
osservati esempio "$g/golden/esempio"
osservati mirato "$g/golden/mirato"
osservati osservazione "$g/osservazioni/osservazione"
cat <<'FINE' || die "testo non scritto (cat)"

## Posizioni in cui l'oracle sbaglia: correzioni

Alla prima esecuzione l'oracle ha smentito un atteso scritto a mano: nei byte 80 e 99 di ogni record di ARRYFILE (ultimo byte di `ARR-ACCT-CURR-BAL(4)` e `(5)`, valorizzati solo da `INITIALIZE`, riga 169) GnuCOBOL scrive `30` (cifra semplice), mentre le regole IBM danno lo zero con segno C, `7B` nel profilo dell'oracle. Nello stesso oracle `MOVE` e `COMPUTE` di zero scrivono `7B` (`oracle/README.md`, "Segno dei numeri DISPLAY"): e' l'`INITIALIZE` di GnuCOBOL a non applicare la convenzione di `-fsign=EBCDIC` (causa e opzioni: issue #62). Un errore noto dell'oracle non diventa riferimento: il riferimento porta il byte della regola, attraverso questa tabella (`correzioni.tsv`), condizionata al byte che l'oracle scrive oggi (un byte diverso fa fallire il passo). Il verificatore indipendente non legge la tabella: ricava il byte dalla regola.

| File | Chiave | Posizione | Byte dell'oracle | Byte di riferimento | Regola e fonte | Riga |
| --- | --- | --- | --- | --- | --- | --- |
FINE
tabella "$t/correzioni.tsv" "2,3,4,5,6,7,8" || die "tabella non resa"
cat <<'FINE' || die "testo non scritto (cat)"

Fonti: IBM, *Enterprise COBOL for z/OS 6.4 Language Reference*, INITIALIZE statement rules, regola 2: "ZERO is the implied sending item for receiving items of category numeric or numeric-edited" (https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=statement-initialize-rules); IBM, *Enterprise COBOL 6.3 Programming Guide*, Sign representation of zoned and packed-decimal data: con `NUMPROC(NOPFD)` "The preferred sign is always generated in the receiver", con `NUMPROC(PFD)` "The preferred sign is generated only where necessary (for example, when unsigned data is moved to signed data)" (https://www.ibm.com/docs/en/SS6SG3_6.3.0/pg/ref/rpari25.html); segno preferito X'C' per positivo o zero (pagina NUMPROC).

Ricerca di ogni campo numerico con segno valorizzato da `INITIALIZE` e scritto in uscita (`CBACT01C` ha due `INITIALIZE`, righe 169 e 175):

| Campo | Byte | GnuCOBOL scrive | Regola IBM | Esito |
| --- | --- | --- | --- | --- |
| `ARR-ACCT-CURR-BAL(1)`-`(3)` | 12-23, 31-42, 50-61 | (sovrascritti dalle righe 255, 257, 259) | - | nessuna correzione |
| `ARR-ACCT-CURR-CYC-DEBIT(1)`-`(3)` | 24-30, 43-49, 62-68 | (sovrascritti dalle righe 256, 258, 260) | - | nessuna correzione |
| `ARR-ACCT-CURR-BAL(4)` | 69-80 | `30` x 12 | `30` x 11, `7B` | **corretto il byte 80** |
| `ARR-ACCT-CURR-CYC-DEBIT(4)` | 81-87 | `00 00 00 00 00 00 0C` | `00 00 00 00 00 00 0C` | coincidono |
| `ARR-ACCT-CURR-BAL(5)` | 88-99 | `30` x 12 | `30` x 11, `7B` | **corretto il byte 99** |
| `ARR-ACCT-CURR-CYC-DEBIT(5)` | 100-106 | `00 00 00 00 00 00 0C` | `00 00 00 00 00 00 0C` | coincidono |
| `VBRC-REC1` (riga 175) | - | - | nessun campo con segno | - |

## Console

Assunzione dichiarata sul legacy: compilazione IBM con `DISPSIGN(COMPAT)`, il valore predefinito (IBM, *Enterprise COBOL 6.4 Programming Guide*, DISPSIGN: "Default is: DISPSIGN(COMPAT)", https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=options-dispsign): un numerico zonato con segno esce con il segno sovrapposto all'ultima cifra. GnuCOBOL lo stampa con 12 cifre e il segno in coda (`000000019400+`). Il verificatore controlla ogni riga, comprese quelle di classe b, ricavandola dal record d'ingresso: il valore stampato da GnuCOBOL e' quello del campo, e la forma IBM e' la stessa sequenza di cifre con l'ultima che porta il segno (la regola dei byte del campo). Su z/OS un operando piu' lungo del record del dispositivo continua nel record successivo (IBM, DISPLAY statement: "Any operand being printed or displayed when the end of a record is reached is continued in the next record"; record logico predefinito 120 caratteri, massimo 255, https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=statements-display-statement); GnuCOBOL scrive una riga sola. Il riferimento e' il testo della riga, non la forma dei record SYSOUT.

| Posizione | Riga | Prefisso | Classe | Motivo |
| --- | --- | --- | --- | --- |
FINE
tabella "$t/console.tsv" "1,2,3,4,5" || die "tabella non resa"
cat <<'FINE' || die "testo non scritto (cat)"

## Differenze GnuCOBOL / z/OS che toccano questo job

| Tema | GnuCOBOL (oracle) | z/OS | Fonte | Trattamento |
| --- | --- | --- | --- | --- |
| Campo senza `VALUE` | `00` (`defaultbyte 0`) | imprevedibile | IBM, VALUE clause | OUTFILE 77-78 esclusi |
| `INITIALIZE` di un zonato con segno | ultimo byte `30` (cifra semplice) | zona C (`7B` nel profilo) | IBM, INITIALIZE statement rules; Sign representation | correzione condizionata (ARRYFILE 80, 99) |
| `MOVE` tra zonati con segno, rappresentazione non canonica | osservato nello scenario osservazione | segno preferito con `NUMPROC(NOPFD)`, segno dato con `NUMPROC(PFD)` | IBM, Sign representation | escluso (solo osservazione) |
| Area del record dopo `WRITE` | conserva i byte | non disponibile | IBM, Common processing facilities | debito non zero solo nello scenario osservazione |
| Record variabili | 2 byte di lunghezza + 2 byte `00` | RDW di 4 byte | `runtime.cfg`; JCL `RECFM=VB` | riferimento = record logici |
| `DISPLAY` di numerici con segno | segno separato in coda | segno sovrapposto (`DISPSIGN(COMPAT)`) | IBM, DISPSIGN | righe di classe b: osservazione |
| `DISPLAY` di 300 byte | una riga | piu' record | IBM, DISPLAY statement | riga di classe c: osservazione |
| File d'uscita non chiusi dal programma | `implicit CLOSE` su stderr | chiusura alla fine dell'unita' di esecuzione: **non verificato** nella documentazione IBM | - | stderr: osservazione |
| Arresto con file aperti | lo stub `CEE3ABD` chiude i file e lascia le uscite parziali | `DISP=(NEW,CATLG,DELETE)`: alla fine anomala i data set nuovi si cancellano | IBM, z/OS 3.1 MVS JCL Reference, DISP parameter (https://www.ibm.com/docs/en/zos/3.1.0?topic=d-parameter-field-2) | osservazione (prova negativa del ramo d'errore) |
| `OPEN OUTPUT` su file esistente | vedi riesecuzione | non accade: `PREDEL` cancella prima | `READACCT.jcl:22-48` | osservazione (controllo 6) |

## Osservazioni registrate

Riesecuzione (controllo 6): seconda esecuzione con i tre file d'uscita gia' presenti, ciascuno di 20000 byte `R`.

FINE
sed 's/^/- /' "$g/osservazioni/riesecuzione/esito.txt" || die "esito della riesecuzione non reso"
cat <<'FINE' || die "testo non scritto (cat)"

Ramo d'errore del programma (prove negative di `oracle/golden/check.sh`):

- **Errore di lettura** (stato diverso da 00 e 10): **raggiungibile** senza modificare il programma (rilievo 2 del giro 1 della PR #64: la prima versione di questo documento lo dichiarava, a torto, non provocabile). In una copia del file indicizzato si cambia da `80` a `00` il primo byte del quarto elemento del vettore degli scostamenti della pagina 2 (la prima foglia del B-tree di Berkeley DB; scostamento 2 x dimensione di pagina + 32, ricavato dal file, con il formato verificato prima di alterarlo). `CBACT01C` stampa `ERROR READING ACCOUNT FILE`, `FILE STATUS IS: NNNN0043` (stato osservato nell'oracle), `ABENDING PROGRAM`, chiama `CEE3ABD` con `ABCODE=+0000000999 TIMING=+0000000000` (righe 192-195 e 406-410) e termina con codice 99. Attraverso il passo (la rilettura con `IDXLEGGI` usa il file sano, `CBACT01C` quello alterato) `run.sh` fallisce, nessun golden e' pubblicato e il risultato precedente e' rimosso. Altre prove: altre alterazioni delle pagine danno la fine file silenziosa (sotto); record di 299 byte letti con stato 00; record di 301 byte: errore all'apertura (stato 39).
- **Limite dell'oracle**: un file indicizzato corrotto (pagina Berkeley DB alterata) non produce un errore ma una **fine file silenziosa**: il programma esce con 0 e le uscite sono troncate, con solo righe `BDB0058`/`PANIC` su stderr. Il passo lo attenua rileggendo il file con `IDXLEGGI` prima dell'esecuzione (la lettura deve coincidere con l'ingresso) e pretendendo il numero di record atteso (controllo 2).
- **Errore di scrittura**: raggiungibile, con le uscite su un file system pieno (tmpfs di 8 KiB). Diagnostica `ACCOUNT FILE WRITE STATUS IS:` e `FILE STATUS IS: NNNN00..` (34 osservato con 8 KiB, 30 con 12 KiB), `ABENDING PROGRAM`, `CEE3ABD` con `ABCODE=+0000000999 TIMING=+0000000000` (righe 406-410), codice dell'oracle 99, nessun golden pubblicato. Lo stub lascia i file parziali, mentre il JCL li cancellerebbe (`DISP=(NEW,CATLG,DELETE)`, `READACCT.jcl:37-47`): osservazione distinta.

## Controlli

`./oracle/run.sh golden` genera e verifica; `./oracle/run.sh golden --check` rigenera da zero due volte e confronta, poi esegue le prove negative.

| Controllo | Che cosa | Script |
| --- | --- | --- |
| 1 | golden rigenerati da zero coincidenti byte per byte con i versionati (due corse) | `check.sh` |
| 2 | N record in OUTFILE e ARRYFILE, 2N record logici, ordine e chiavi dell'ingresso, dimensione del fisico | `conteggi.sh` |
| 3 | attesi scritti a mano (`attesi-a-mano.tsv`, 15 conti) uguali ai golden; posizioni ND = escluse | `attesi.sh` |
| 4 | verificatore indipendente su tutti i record degli scenari esempio e mirato: legge e controlla ogni file pubblicato come riferimento (OUTFILE, ARRYFILE, VBRCFILE e console), il fisico, i record logici, il rapporto e l ambiente; valida ogni token | `verificatore.sh` |
| 4b | fisico (VBRCFILE letto da se) e riferimento differiscono solo nelle posizioni delle due tabelle | `coerenza.sh` |
| - | ogni file dei golden elencato nel documento con dimensione e SHA-256 reali | `impronte.sh` |
| 5 | scenario osservazione fuori dai golden, marcato | `separazione.sh` |
| 6 | riesecuzione con file preesistenti (osservazione) | `riesecuzione.sh` |
| - | sostituzioni e proprieta' degli scenari derivati | `differenze.sh`, `proprieta.sh` |
FINE
} > "$usc.parziale" || die "documento non scritto"
rm -f "$usc.file" || die "temporaneo non rimosso"
mv "$usc.parziale" "$usc" || die "documento non pubblicato (mv)"
echo "documento.sh: $usc"
