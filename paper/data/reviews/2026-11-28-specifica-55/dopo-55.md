> Classe di rischio: piena (oracle, golden). Divisa da #9 per la decisione "prima il pilota" (registro delle approvazioni, voce 86).

## Obiettivo

Eseguire nell'oracle il programma pilota `CBACT01C` (job `READACCT`) su ingressi noti e fissare ciò che produce come output di riferimento (*golden*). È il valore atteso del test di parità che verrà scritto prima della traduzione in Java.

## Dipendenze e perimetro

- Dipende da: #53 (file dei conti nell'oracle, passo `dati`), #24 (routine `COBDATFT`, mergiata), #23 e #43 (regole di codifica e adattatore, mergiate).
- Sorgenti di riferimento: `app/cbl/CBACT01C.cbl`, `app/jcl/READACCT.jcl`, `app/cpy/CVACT01Y.cpy`, `app/cpy/CODATECN.cpy`, `app/asm/COBDATFT.asm`.
- Cartelle ammesse: `oracle/golden/**` (nuovo passo `golden`, con una sottocartella `readacct/`), `oracle/README.md`, `docs/legacy-map/golden-readacct.md`, l'aggiunta di `golden` all'elenco fisso `PASSI` di `oracle/build/check.sh`. Gli ingressi costruiti si producono dentro `oracle/golden/**`, applicando le sostituzioni **dopo** la conversione di #53 e caricandoli con il caricatore a lunghezza fissa di #53, riusato senza modificarlo; nulla cambia sotto `analysis/oracle-dati/`.
- Fuori ambito: gli altri job; la traduzione; modifiche a `legacy/`, a `oracle/esegui.sh`, a `oracle/stubs/`, agli attesi esistenti.

## Specifica

### Scenari

1. **`esempio`** — il file dei conti caricato da #53 (50 record, contenuto di `AWS.M2.CARDDEMO.ACCTDATA.PS`).
2. **`mirato`** — i dati di esempio non contengono importi negativi (rilievo 6 della contestazione di #53), quindi lo scenario 1 non esercita il segno. Lo scenario 2 parte dagli stessi 50 record e ne modifica alcuni con una tabella di sostituzioni scritta a mano (chiave, campo, byte nuovi in esadecimale nel profilo dell'oracle, motivo, valore decodificato atteso). Obbligatori: un saldo negativo; un limite di credito negativo; un limite di anticipo diverso dal limite di credito dello stesso conto; un importo con tutte le cifre a 9; uno zero positivo nel saldo di un conto che nei dati di esempio ha saldo diverso da zero; un credito di ciclo diverso da zero, positivo in un conto e negativo in un altro; un gruppo non vuoto; uno stato diverso da `Y`; una data di riemissione con anno, mese e giorno tutti diversi tra loro e da quelli degli altri conti. Tutte le sostituzioni usano la rappresentazione canonica del profilo (quella che la codifica di #23 scrive): è la condizione a cui il sistema Java accetta i dati (issue della tabella dei conti), e lo scenario 2 è il riferimento del test di parità. Ogni sostituzione è verificata sui byte e decodificando il campo con le regole di #23. Controllo dedicato: la differenza completa tra il file derivato e il file base coincide esattamente con la tabella (nessun altro byte cambia), e ogni proprietà richiesta è presente nel file indicizzato effettivamente letto (riletto dopo il caricamento). In questo scenario `ACCT-CURR-CYC-DEBIT` resta zero in tutti i record (vedi "Campo non determinato").
3. **`osservazione`** — come il 2, più: due record con `ACCT-CURR-CYC-DEBIT` diverso da zero, uno dei quali è il primo del file; un record con **zero negativo nel saldo** (`ACCT-CURR-BAL`, copiato nelle uscite), scritto come undici byte `30` seguiti da `7D`; un record con un segno alternativo. Non è un riferimento di parità: per il debito vedi sotto; per le rappresentazioni non canoniche, il sistema Java non le accetta in ingresso, e ciò che ne fa l'originale si registra soltanto (con la riserva su `NUMPROC` del controllo 4).

### Esecuzione

- `CBACT01C` compilato dalla build dell'oracle, eseguito con `oracle/esegui.sh` e i nomi DD di `READACCT.jcl`: `DD_ACCTFILE` (file indicizzato del passo `dati`), `DD_OUTFILE`, `DD_ARRYFILE`, `DD_VBRCFILE` in una cartella vuota. Il passo `PREDEL` del JCL cancella i tre file prima dell'esecuzione: l'oracle parte da una cartella vuota e lo dichiara.
- Si raccolgono: i tre file di uscita, stdout, stderr, codice di uscita, rapporto di `esegui.sh`.

### Che cosa è riferimento di parità, e che cosa no

- **`OUTFILE`** (record fissi di 107 byte, `LRECL=107,RECFM=FB`): riferimento di parità per **105 byte su 107**, negli scenari 1 e 2. I byte 77-78 di ogni record (gli ultimi due di `OUT-ACCT-REISSUE-DATE`) non sono determinati dal sorgente: `COBDATFT` scrive solo i primi 8 byte dell'area d'uscita (`app/asm/COBDATFT.asm:51-53`), l'area è `X(20)` senza `VALUE` (`app/cpy/CODATECN.cpy:39-51`), il programma non la inizializza e ne copia i primi 10 (`CBACT01C.cbl:223-233`). Su z/OS il valore iniziale senza `VALUE` è imprevedibile (IBM, *VALUE clause*); nell'oracle l'opzione `defaultbyte 0` (`oracle/cobc.opts`) dà `00 00`. Il file fisico si versiona com'è; il riferimento di parità è il file con quei due byte per record mascherati, e una tabella versionata delle posizioni escluse (file, posizione, lunghezza, motivo, riga del sorgente) è l'unica fonte delle maschere. Non si aggiungono inizializzazioni né al programma né allo stub.
- **`ARRYFILE`** (record fissi di 110 byte): riferimento di parità byte per byte, negli scenari 1 e 2, salvo posizioni non determinate che la ricerca richiesta sotto dovesse trovare (stessa tabella). Verificare che GnuCOBOL scriva record senza terminatori né intestazioni e che la dimensione sia 107 × N e 110 × N; se non è così, dichiarare la trasformazione.
- **`VBRCFILE`** (`RECFM=VB`, `LRECL=84`): il riferimento di parità è la **sequenza dei record logici** (lunghezza e contenuto: due per conto, 12 e 39 byte), non il formato fisico. GnuCOBOL e z/OS scrivono intestazioni diverse per i record variabili: documentare il formato fisico prodotto da GnuCOBOL (con la fonte), estrarne i record logici con uno strumento nostro controllato, e versionare sia il file fisico (come osservazione) sia la sequenza logica (come riferimento).
- **Console (stdout)**: il programma stampa ogni record e ogni campo con `DISPLAY`. Assunzione dichiarata sul legacy: compilazione IBM con `DISPSIGN(COMPAT)`, il valore predefinito (IBM, *DISPSIGN*): un numerico zonato con segno è stampato con il segno sovrapposto all'ultima cifra. GnuCOBOL, con le opzioni dell'oracle, lo stampa con il segno separato in coda (lo mostra già `oracle/segno/expected/SEGNOPRB.txt`). Classificazione, riga per riga, in una tabella versionata: (a) righe di soli letterali e righe con campi alfanumerici o numerici senza segno: riferimento di parità; (b) righe con numerici con segno (`ACCT-CURR-BAL` e simili, e le righe `VBRC-REC2:`): osservazione, con il motivo; il valore si può ricondurre alla forma IBM con una regola scritta e verificata, ma la riga di GnuCOBOL non è riferimento; (c) `DISPLAY ACCOUNT-RECORD` e gli altri `DISPLAY` di gruppo (300 byte): osservazione, perché su z/OS un operando più lungo del record del dispositivo viene suddiviso (IBM, *DISPLAY statement*) e GnuCOBOL scrive una riga sola. Non è ammesso classificare come osservazione l'intera console.
- **Fine regolare**: dopo la fine del file (stato 10) il programma chiude ed esce senza altre emissioni: l'atteso della console lo fissa (ultima riga `END OF EXECUTION OF PROGRAM CBACT01C`).
- **Codice di uscita**: 0, riferimento di parità.

### Campo non determinato dal sorgente

Alle righe 236-238 `OUT-ACCT-CURR-CYC-DEBIT` riceve 2525,00 solo se `ACCT-CURR-CYC-DEBIT` è zero; altrimenti nessuna istruzione lo valorizza, e nel record scritto resta ciò che l'area del record conteneva. Su GnuCOBOL è il valore del record precedente (o il contenuto iniziale dell'area per il primo); su z/OS il contenuto dell'area dopo una `WRITE` su un file sequenziale a blocchi non è definito dal programma. Nei 50 record di esempio il campo è sempre zero (verificarlo), quindi negli scenari 1 e 2 l'uscita è determinata. Lo scenario 3 registra ciò che fa GnuCOBOL come **osservazione dichiarata**, con la fonte IBM sul contenuto dell'area dopo `WRITE`; i suoi file non sono golden e il controllo impedisce di usarli come tali (stessa linea delle voci 42 e 63 del registro). Se la documentazione IBM mostrasse che il contenuto è invece determinato, fermarsi con `needs-spec-update`.

Cercare nel programma altri casi dello stesso schema (campi delle aree di uscita non valorizzati a ogni record: le occorrenze 4 e 5 e `ARR-FILLER` di `ARR-ARRAY-REC` dopo `INITIALIZE`, i byte di `VBR-REC` oltre la lunghezza scritta, `WS-REISSUE-DATE`, le aree di `CODATECN` tra una chiamata e l'altra, `VBRC-REC2` che non viene inizializzato) e dichiarare per ciascuno se è determinato e perché, con la riga del sorgente. Ogni posizione non determinata entra nella tabella delle posizioni escluse; se ne emergono in `ARRYFILE` o nei record logici di `VBRCFILE`, valgono le stesse regole dei byte 77-78.

### Attesi scritti a mano, prima di eseguire

Per cinque conti dello scenario 1 (primo, ultimo, il 49, due a scelta) e per ogni conto modificato dello scenario 2: i byte attesi del record di `OUTFILE` (107), del record di `ARRYFILE` (110) e dei due record logici di `VBRCFILE` (12 e 39), ricavati a mano dal record d'ingresso e dal sorgente, campo per campo, con la riga del sorgente che li determina; le posizioni non determinate si scrivono come tali, non con un valore. In particolare: la data di riemissione riformattata da `COBDATFT` (caso C4 di `oracle/routines/cobdatft-casi.md`: `AAAA-MM-GG` → `AAAAMMGG` nei primi 8 byte; i due restanti non determinati); il `COMP-3` di 2525,00 in 7 byte; le costanti di `1400-POPUL-ARRAY-RECORD` (1005,00; 1525,00; −1025,00; −2500,00) nelle loro codifiche; il segno dei valori negativi nel profilo dell'oracle. Committati prima della prima esecuzione; se l'oracle li smentisce, fermarsi e riportare la differenza senza correggere l'atteso.

### Controlli, ciascuno con prova negativa

1. I golden versionati si rigenerano da zero e coincidono byte per byte (due corse consecutive).
2. Numero di record: N in `OUTFILE` e `ARRYFILE`, 2N record logici in `VBRCFILE`, nell'ordine di chiave dell'ingresso; chiavi d'uscita uguali alle chiavi d'ingresso, nello stesso ordine.
3. Ogni atteso a mano coincide con il record corrispondente del golden.
4. Per **tutti** i record degli scenari 1 e 2, un verificatore indipendente (non esegue COBOL, non riusa il codice che ha prodotto i golden, e si può lanciare da solo su un file dato) controlla ogni campo di uscita contro il record d'ingresso, con una tabella scritta a mano: campo d'uscita ← campo d'ingresso, costante o trasformazione, con la riga del sorgente. Tracciati: per `OUTFILE` e `ARRYFILE` quelli dell'`FD`; per `VBRCFILE` i due tracciati logici `VBRC-REC1` (12 byte) e `VBRC-REC2` (39 byte) della `WORKING-STORAGE` (`CBACT01C.cbl:123-130`), non `VBR-REC PIC X(80)`. Il confronto è **sui byte**, non solo sui valori decodificati: per una copia tra campi di uguale tracciato i byte d'uscita attesi sono quelli d'ingresso, con una riserva da verificare prima di scrivere gli attesi: su z/OS un `MOVE` tra numerici zonati con segno può conservare o correggere il byte del segno secondo l'opzione di compilazione `NUMPROC` (documentazione IBM, da citare). Se per una rappresentazione non canonica (zero negativo) il risultato dipende da quell'opzione, i byte interessati di quel record vanno nella tabella delle posizioni escluse come osservazione, con ciò che fa GnuCOBOL; non si dichiara riferimento ciò che dipende da un'opzione che il repository non fissa; per una costante o una conversione di formato (`DISPLAY` → `COMP-3`) i byte attesi vengono da regole scritte nel verificatore su segno, riempimento del packed, zeri e spazi, indipendenti dalla libreria di #23. La data: composizione indipendente delle sottostringhe anno, mese e giorno (`COBDATFT.asm:51-53`), con i due byte finali esclusi.
5. Lo scenario 3 non compare tra i golden e ha la marcatura di osservazione.
6. Riesecuzione: una seconda esecuzione in una cartella in cui i tre file esistono già. Documentare che cosa fa GnuCOBOL (`OPEN OUTPUT` su file esistente) rispetto al JCL (`DISP=(NEW,CATLG,DELETE)` dopo `PREDEL`): è un'osservazione, dichiarata.

Ogni prova negativa è associata al controllo che deve farla fallire e ne dimostra il raggiungimento: la diagnosi nomina quel controllo, e il controllo si esegue da solo sul risultato sbagliato (non basta che un controllo precedente fermi la corsa). Per la routine alterata si prepara una variante temporanea realmente caricata dal programma, come in `oracle/routines/check.sh`, e non una sostituzione che fa scattare prima l'impronta degli artefatti.

Prove negative richieste: un byte di un golden alterato (uno per file e uno nella console); un record d'ingresso alterato (saldo, stato, data); la routine `COBDATFT` sostituita da una che restituisce la data invariata; un record tolto dall'ingresso; due record d'ingresso scambiati prima del caricamento (il caricamento deve rifiutarli); un atteso a mano alterato; golden e atteso a mano alterati **allo stesso modo** (segno `C` → `F` nel `COMP-3`; segno negativo di un saldo → positivo): deve respingerli il controllo 4 eseguito da solo; un byte nelle posizioni escluse alterato nel file fisico (il riferimento mascherato non cambia, l'osservazione sì: i due esiti vanno distinti); una posizione tolta dalla tabella delle esclusioni e una aggiunta senza motivo; la tabella campo ← campo con due campi di uguale tracciato scambiati (`ACCT-CREDIT-LIMIT` e `ACCT-CASH-CREDIT-LIMIT`); l'estrattore dei record variabili che perde l'ultimo record o legge una lunghezza sbagliata; lo scenario 3 copiato tra i golden; il ramo d'errore del programma: provocare un errore di lettura reale (stato diverso da 00 e 10) e verificare diagnostica, argomenti di `CEE3ABD` (`ABCODE=999`, `TIMING=0`, `CBACT01C.cbl:406-410`), codice 99 dell'oracle e nessun golden pubblicato; se nel container un errore di lettura non è provocabile senza modificare il programma, dichiararlo con le prove tentate e coprire il ramo raggiungibile; file di uscita rimasti da una corsa precedente con il programma che fallisce. Documentare come osservazione distinta che lo stub lascia i file parziali, mentre il JCL li cancellerebbe (`DISP=(NEW,CATLG,DELETE)`, `READACCT.jcl:37-47`).

## Invarianti di parità

- Stesso numero di record, stesso ordine di chiave, stessi byte nei file a record fissi **nelle posizioni determinate dal sorgente**, stessa sequenza di record logici nel file variabile.
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
