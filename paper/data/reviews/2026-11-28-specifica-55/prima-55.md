> Classe di rischio: piena (oracle, golden). Divisa da #9 per la decisione "prima il pilota" (registro delle approvazioni, voce 86).

## Obiettivo

Eseguire nell'oracle il programma pilota `CBACT01C` (job `READACCT`) su ingressi noti e fissare ciò che produce come output di riferimento (*golden*). È il valore atteso del test di parità che verrà scritto prima della traduzione in Java.

## Dipendenze e perimetro

- Dipende da: #53 (file dei conti nell'oracle, passo `dati`), #24 (routine `COBDATFT`, mergiata), #23 e #43 (regole di codifica e adattatore, mergiate).
- Sorgenti di riferimento: `app/cbl/CBACT01C.cbl`, `app/jcl/READACCT.jcl`, `app/cpy/CVACT01Y.cpy`, `app/cpy/CODATECN.cpy`, `app/asm/COBDATFT.asm`.
- Cartelle ammesse: `oracle/golden/**` (nuovo passo `golden`, con una sottocartella `readacct/`), `oracle/README.md`, `docs/legacy-map/golden-readacct.md`, l'aggiunta di `golden` all'elenco fisso `PASSI` di `oracle/build/check.sh`. Per gli ingressi costruiti: una riga in più nella tabella di `analysis/oracle-dati/` e i suoi file, senza cambiare ciò che #53 ha consegnato per i dati di esempio.
- Fuori ambito: gli altri job; la traduzione; modifiche a `legacy/`, a `oracle/esegui.sh`, a `oracle/stubs/`, agli attesi esistenti.

## Specifica

### Scenari

1. **`esempio`** — il file dei conti caricato da #53 (50 record, contenuto di `AWS.M2.CARDDEMO.ACCTDATA.PS`).
2. **`mirato`** — i dati di esempio non contengono importi negativi (rilievo 6 della contestazione di #53), quindi lo scenario 1 non esercita il segno. Lo scenario 2 parte dagli stessi 50 record e ne modifica alcuni con una tabella di sostituzioni scritta a mano (chiave, campo, byte nuovi in esadecimale, motivo, valore decodificato atteso): almeno un saldo negativo, un limite di credito negativo, un importo con tutte le cifre a 9, uno zero negativo (`0000000000 0}` nella forma del profilo), uno stato diverso da `Y`, una data di riemissione diversa per anno, mese e giorno. Ogni sostituzione è verificata decodificando il campo con le regole di #23. In questo scenario `ACCT-CURR-CYC-DEBIT` resta zero in tutti i record (vedi "Campo non determinato").
3. **`osservazione-debito`** — come il 2, più due record con `ACCT-CURR-CYC-DEBIT` diverso da zero, uno dei quali è il primo del file. Non è un riferimento di parità: vedi sotto.

### Esecuzione

- `CBACT01C` compilato dalla build dell'oracle, eseguito con `oracle/esegui.sh` e i nomi DD di `READACCT.jcl`: `DD_ACCTFILE` (file indicizzato del passo `dati`), `DD_OUTFILE`, `DD_ARRYFILE`, `DD_VBRCFILE` in una cartella vuota. Il passo `PREDEL` del JCL cancella i tre file prima dell'esecuzione: l'oracle parte da una cartella vuota e lo dichiara.
- Si raccolgono: i tre file di uscita, stdout, stderr, codice di uscita, rapporto di `esegui.sh`.

### Che cosa è riferimento di parità, e che cosa no

- **`OUTFILE`** (record fissi di 107 byte, `LRECL=107,RECFM=FB`) e **`ARRYFILE`** (record fissi di 110 byte): riferimento di parità byte per byte, negli scenari 1 e 2. Verificare che GnuCOBOL scriva record senza terminatori né intestazioni e che la dimensione sia 107 × N e 110 × N; se non è così, dichiarare la trasformazione.
- **`VBRCFILE`** (`RECFM=VB`, `LRECL=84`): il riferimento di parità è la **sequenza dei record logici** (lunghezza e contenuto: due per conto, 12 e 39 byte), non il formato fisico. GnuCOBOL e z/OS scrivono intestazioni diverse per i record variabili: documentare il formato fisico prodotto da GnuCOBOL (con la fonte), estrarne i record logici con uno strumento nostro controllato, e versionare sia il file fisico (come osservazione) sia la sequenza logica (come riferimento).
- **Console (stdout)**: il programma stampa ogni record e ogni campo con `DISPLAY`. Stabilire con la documentazione IBM (citata) come z/OS stampa con `DISPLAY` un numerico `DISPLAY` con segno e confrontarlo con ciò che fa GnuCOBOL con le opzioni dell'oracle. Le righe che coincidono per costruzione sono riferimento di parità; quelle in cui GnuCOBOL formatta diversamente sono versionate come osservazione, elencate una per una con il motivo. Se non si riesce a stabilirlo, l'intera console è osservazione e lo si dichiara: non si presenta come riferimento ciò che non lo è.
- **Codice di uscita**: 0, riferimento di parità.

### Campo non determinato dal sorgente

Alle righe 236-238 `OUT-ACCT-CURR-CYC-DEBIT` riceve 2525,00 solo se `ACCT-CURR-CYC-DEBIT` è zero; altrimenti nessuna istruzione lo valorizza, e nel record scritto resta ciò che l'area del record conteneva. Su GnuCOBOL è il valore del record precedente (o il contenuto iniziale dell'area per il primo); su z/OS il contenuto dell'area dopo una `WRITE` su un file sequenziale a blocchi non è definito dal programma. Nei 50 record di esempio il campo è sempre zero (verificarlo), quindi negli scenari 1 e 2 l'uscita è determinata. Lo scenario 3 registra ciò che fa GnuCOBOL come **osservazione dichiarata**, con la fonte IBM sul contenuto dell'area dopo `WRITE`; i suoi file non sono golden e il controllo impedisce di usarli come tali (stessa linea delle voci 42 e 63 del registro). Se la documentazione IBM mostrasse che il contenuto è invece determinato, fermarsi con `needs-spec-update`.

Cercare nel programma altri casi dello stesso schema (campi delle aree di uscita non valorizzati a ogni record: per esempio le occorrenze 4 e 5 e `ARR-FILLER` di `ARR-ARRAY-REC` dopo `INITIALIZE`, i byte di `VBR-REC` oltre la lunghezza scritta, `WS-REISSUE-DATE`) e dichiarare per ciascuno se è determinato e perché.

### Attesi scritti a mano, prima di eseguire

Per cinque conti dello scenario 1 (primo, ultimo, il 49, due a scelta) e per ogni conto modificato dello scenario 2: i byte attesi del record di `OUTFILE` (107), del record di `ARRYFILE` (110) e dei due record logici di `VBRCFILE` (12 e 39), ricavati a mano dal record d'ingresso e dal sorgente, campo per campo, con la riga del sorgente che li determina. In particolare: la data di riemissione riformattata da `COBDATFT` (caso C4 di `oracle/routines/cobdatft-casi.md`: `AAAA-MM-GG` → `AAAAMMGG`, con i byte restanti del campo di 10 secondo quel documento); il `COMP-3` di 2525,00 in 7 byte; le costanti di `1400-POPUL-ARRAY-RECORD` (1005,00; 1525,00; −1025,00; −2500,00) nelle loro codifiche; il segno dei valori negativi nel profilo dell'oracle. Committati prima della prima esecuzione; se l'oracle li smentisce, fermarsi e riportare la differenza senza correggere l'atteso.

### Controlli, ciascuno con prova negativa

1. I golden versionati si rigenerano da zero e coincidono byte per byte (due corse consecutive).
2. Numero di record: N in `OUTFILE` e `ARRYFILE`, 2N record logici in `VBRCFILE`, nell'ordine di chiave dell'ingresso; chiavi d'uscita uguali alle chiavi d'ingresso, nello stesso ordine.
3. Ogni atteso a mano coincide con il record corrispondente del golden.
4. Per **tutti** i record degli scenari 1 e 2: ogni campo di uscita, decodificato con le regole di #23 secondo il tracciato dell'`FD`, è uguale al valore che il sorgente gli assegna a partire dal record d'ingresso (regola scritta in una tabella campo d'uscita ← campo d'ingresso o costante, con la riga del sorgente; il verificatore non esegue COBOL e non riusa il codice che ha prodotto i golden).
5. Lo scenario 3 non compare tra i golden e ha la marcatura di osservazione.
6. Riesecuzione: una seconda esecuzione in una cartella in cui i tre file esistono già. Documentare che cosa fa GnuCOBOL (`OPEN OUTPUT` su file esistente) rispetto al JCL (`DISP=(NEW,CATLG,DELETE)` dopo `PREDEL`): è un'osservazione, dichiarata.

Prove negative richieste: un byte di un golden alterato (uno per file e uno nella console); un record d'ingresso alterato (saldo, stato, data); la routine `COBDATFT` sostituita da una che restituisce la data invariata; un record tolto dall'ingresso; due record d'ingresso scambiati prima del caricamento (il caricamento deve rifiutarli); un atteso a mano alterato; la tabella campo ← campo con due campi di uguale tracciato scambiati (`ACCT-CREDIT-LIMIT` e `ACCT-CASH-CREDIT-LIMIT`); l'estrattore dei record variabili che perde l'ultimo record o legge una lunghezza sbagliata; lo scenario 3 copiato tra i golden; `CBACT01C` che termina con codice diverso da 0; file di uscita rimasti da una corsa precedente con il programma che fallisce.

## Invarianti di parità

- Stesso numero di record, stesso ordine di chiave, stessi byte nei file a record fissi, stessa sequenza di record logici nel file variabile.
- Nessun valore riparato: ciò che il programma scrive è il riferimento, anche dove sembra un difetto (per esempio le costanti scritte nella tabella al posto dei valori del conto).

## Criteri di accettazione

1. `./oracle/run.sh golden` e `./oracle/run.sh golden --check` (due volte) escono con 0; la rigenerazione non cambia i file versionati.
2. `./oracle/run.sh --all --check` e `./analysis/run.sh --all --check` escono con 0; nessun atteso preesistente cambiato, nessuna prova preesistente con esito diverso.
3. Ogni prova negativa è riportata con nome e diagnosi; conteggi locali uguali a quelli della CI.
4. `docs/legacy-map/golden-readacct.md` (generato) elenca: scenari, file, dimensioni, impronte, che cosa è riferimento e che cosa è osservazione, i campi non determinati, le differenze GnuCOBOL / z/OS con la fonte.
5. `git status --short` vuoto; `legacy/` invariato; diff nel solo perimetro.
6. CI verde sullo SHA finale.
7. Storia Git: attesi a mano e tabelle committati prima della prima esecuzione.

## Strategia di rollback

Revert della PR: si toglie un passo dell'oracle; nessun codice Java ne dipende finché il test di parità non è scritto.

## Limiti per l'agente

- Unico prerequisito dell'host: Docker e Git.
- Una sola issue: nessun altro job, nessuna traduzione.
- Se il sorgente o l'oracle smentiscono la specifica: fermarsi, commento tecnico, `needs-spec-update`.
- Autocontrollo delle quattro famiglie prima della PR. File di appoggio sull'host con prefisso `issue55-`.
