> Classe di rischio: piena (logica di business, parità). Wave 2, pilota batch. È l'ultimo anello della catena specifica → test → issue → implementazione: il test esiste già (#65) e non si modifica.

## Obiettivo

Tradurre in Java il programma `CBACT01C` (job `READACCT`) così che il test di parità di #65 passi, senza toccarlo: stessi file di uscita dell'originale nelle posizioni determinate, stessa console dove è riferimento, stesso comportamento alla riesecuzione.

## Dipendenze e perimetro

- Dipende da: #65 (test di parità e contratto del job), #55 (output di riferimento, tabelle delle posizioni escluse e delle correzioni dell'oracle), #60 (conti in PostgreSQL), #59 (tabella `account`), #54 (codifica dei campi).
- Sorgenti di riferimento: `app/cbl/CBACT01C.cbl`, `app/cpy/CVACT01Y.cpy`, `app/cpy/CODATECN.cpy`, `app/asm/COBDATFT.asm`, `app/jcl/READACCT.jcl`; `docs/legacy-map/golden-readacct.md`; `oracle/routines/cobdatft-casi.md`.
- Cartelle ammesse: `carddemo-batch/src/main/**` e `carddemo-batch/src/test/**`; `carddemo-domain/src/main/**` solo per tipi che altri programmi riuseranno (dichiarando quali e perché); del test di parità **soltanto** la rimozione della marcatura di fallimento atteso dai casi di `READACCT`, della loro riga in `quality/fallimenti-attesi.tsv` e della pretesa della ricevuta in `verify.sh`; `smoke.sh` e gli avvii esistenti di `batch` nei test, per indicare il nome del job ora che ce n'è più di uno, e per il nuovo passo dello smoke; `compose.yaml` e `docker/**` solo se servono a lanciare il job; `docs/contratti.md`, `docs/sviluppo.md`; un nuovo `docs/programmi/CBACT01C.md`.
- Fuori ambito: qualunque altra modifica ai test di `carddemo-parity`, ai riferimenti di `oracle/golden/`, a `analysis/`, `oracle/`, `legacy/`; gli altri programmi; ottimizzazioni.

## Specifica

### Corrispondenza con il sorgente

`docs/programmi/CBACT01C.md` contiene, scritta prima del codice, una tabella con una riga per ogni paragrafo e per ogni istruzione che produce un effetto osservabile (`MOVE` verso un'area di uscita, `WRITE`, `DISPLAY`, `CALL`, controllo di uno stato di file), con: riga del sorgente, che cosa fa, dove sta nel Java, e "tradotto / escluso con motivo". Ogni `COPY` del programma (`CVACT01Y`, `CODATECN`) ha un corrispondente o un'esclusione esplicita. Nessuna istruzione osservabile resta senza riga.

### Regole

- **Lettura**: i conti dalla tabella `account` in ordine crescente di `acct_id`. Il record COBOL di 300 byte, dove serve (console), si ricompone dai valori con la codifica di #54 e 178 spazi.
- **Importi**: solo `BigDecimal`, scala esplicita, codifica e decodifica con `GnuCobolFieldCodec`; nessuna aritmetica in questo programma oltre al confronto con zero. Le costanti (`2525.00`, `1005.00`, `1525.00`, `-1025.00`, `-2500.00`) si scrivono come nel sorgente, con la riga.
- **`OUTFILE`** (107 byte) e **`ARRYFILE`** (110 byte): un record per conto, composto campo per campo secondo i tracciati dell'`FD`. Le occorrenze 4 e 5 di `ARRYFILE` e il suo riempimento finale valgono ciò che dà `INITIALIZE` secondo le regole del linguaggio: zero **con segno** per i numerici (`7B` nell'ultimo byte dello zonato: è la posizione in cui l'oracle sbaglia, #55), spazi per l'alfanumerico.
- **Data di riemissione**: l'equivalente di `COBDATFT` per la sola combinazione che il programma usa (tipo d'ingresso `2`, tipo d'uscita `2`): i caratteri 1-4, 6-7 e 9-10 dell'ingresso diventano i primi 8 dell'uscita, senza alcuna validazione della data, come fa l'assembler (`COBDATFT.asm:51-53`).
- **Byte che il sorgente non determina: una sola convenzione.** Dove l'originale scrive byte che nessuna sua istruzione determina, il Java scrive il byte convenzionale `X'00'`, e `docs/programmi/CBACT01C.md` dichiara per ciascuna posizione che è una convenzione del progetto e **non** un comportamento dell'originale. Oggi i casi sono due: (a) i byte 77-78 di ogni record di `OUTFILE` (#55); (b) i sette byte di `OUT-ACCT-CURR-CYC-DEBIT` (posizioni 91-97) quando l'addebito di ciclo del conto è diverso da zero (`CBACT01C.cbl:236-238`: il `MOVE` è saltato e resta ciò che l'area conteneva). **Decisione delegata**, corretta in contestazione: nel caso (b) il programma **prosegue** come l'originale (scrive il record, la tabella, i due record variabili e passa al conto successivo): è indeterminato un campo, non la prosecuzione. Alternative scartate: fermarsi sul conto (la mia prima proposta: cambierebbe effetti che il sorgente determina); copiare il valore del record precedente (ciò che fa GnuCOBOL, non definito su z/OS); scrivere l'addebito del conto (plausibile intenzione, ma non è ciò che il programma fa). Sette byte a zero non sono un numero compresso valido: è voluto, perché chi legge quel campo deve accorgersi che l'originale non lo valorizzava. I dati di esempio non hanno conti in questa condizione.
- **`VBRCFILE`**: due record per conto, 12 e 39 byte, con il descrittore fissato da #65.
- **Console**: una riga per ogni `DISPLAY`, nell'ordine dell'originale. Righe di classe a: identiche al riferimento. Righe con numerici con segno: il campo si stampa come sequenza dei suoi byte nel profilo (segno sovrapposto all'ultima cifra), che è la forma documentata da IBM per `DISPSIGN(COMPAT)`; non è confrontata dal test e va dichiarato. `DISPLAY` di gruppo: i byte del gruppo su una riga sola; la suddivisione che z/OS farebbe per un operando di 300 byte non è riprodotta e va dichiarato.
- **Ordine degli effetti, per ogni conto**, come nel sorgente (`CBACT01C.cbl:149-151,171-178,283-305`): le undici righe dei campi e la riga di trattini; scrittura di `OUTFILE`; scrittura di `ARRYFILE`; le due righe `VBRC-REC1:` e `VBRC-REC2:`; scrittura dei due record variabili; e solo dopo, la riga del `DISPLAY ACCOUNT-RECORD`. Un guasto a metà lascia sulla console esattamente il prefisso corrispondente.
- **Apertura, chiusura, fine.** `PREDEL` del JCL (`READACCT.jcl:22-32`): come primo atto, prima di qualunque accesso al database, il job cancella i tre file di uscita se esistono. Poi `START OF EXECUTION…`, apertura dell'accesso ai conti, creazione dei tre file. A fine lettura: chiusura dell'accesso ai conti, riga `END OF EXECUTION…`, e solo dopo svuotamento e chiusura dei tre file (nell'originale sono chiusi implicitamente alla fine dell'esecuzione: il programma chiude esplicitamente solo `ACCTFILE`).
- **Errori: corrispondenza fissata.** Il nuovo sistema non ha gli stati di file del COBOL, quindi le righe `FILE STATUS IS: NNNN…` di `9910-DISPLAY-IO-STATUS` e i valori di stato **non si riproducono**: è un'esclusione esplicita, da scrivere nella tabella di corrispondenza con questo motivo. Si riproducono il messaggio letterale del ramo e l'arresto:

  | Fase Java | Ramo del sorgente | Righe sulla console, nell'ordine |
  | --- | --- | --- |
  | errore nell'aprire l'accesso ai conti (connessione, prima interrogazione) | `0000-ACCTFILE-OPEN` | `ERROR OPENING ACCTFILE`, `ABENDING PROGRAM` |
  | errore nell'avanzare la lettura | `1000-ACCTFILE-GET-NEXT` | `ERROR READING ACCOUNT FILE`, `ABENDING PROGRAM` |
  | errore nel creare un file di uscita | `2000`/`3000`/`4000-…-OPEN` | il messaggio letterale del paragrafo corrispondente, `ABENDING PROGRAM` |
  | errore nello scrivere un record | `1350`/`1450`/`1550`/`1575` | `ACCOUNT FILE WRITE STATUS IS:` (senza stato), `ABENDING PROGRAM` |
  | errore nel chiudere l'accesso ai conti | `9000-ACCTFILE-CLOSE` | `ERROR CLOSING ACCOUNT FILE`, `ABENDING PROGRAM` |
  | errore nello svuotare o chiudere un file di uscita dopo `END OF EXECUTION…` | chiusura implicita | nessuna riga in più sulla console |

  I testi esatti si copiano dal sorgente, con la riga. Il dettaglio tecnico dell'errore Java va sullo standard error. In tutti i casi: codice di uscita diverso da 0 (uno solo, dedicato alla fine anomala del programma, distinto dagli errori di avvio dell'applicazione) e **nessuno dei tre file di uscita resta**, né parziale né di una corsa precedente (`DISP=(NEW,CATLG,DELETE)`, `READACCT.jcl:37-47`, dopo `PREDEL`).
- **Riesecuzione** e **comando**: come fissati da #65. Gli avvii esistenti di `batch` che non indicano un job (`smoke.sh`, test di avvio) si adeguano indicando il job che già eseguivano.
- Nessuna idempotenza, validazione o "miglioria" che l'originale non ha: stati non `Y`, date non valide e importi qualsiasi si trattano come nell'originale.

### Controlli

1. Il test di parità di #65 passa per `esempio`, `mirato`, riesecuzione e ordine di lettura, **senza la marcatura**; nel diff del test compaiono solo le rimozioni ammesse.
2. Test del modulo `batch` sui casi che i riferimenti non coprono: conto con addebito diverso da zero, primo e non primo del file (il programma prosegue; posizioni 91-97 a `X'00'`; ogni altro byte del record e dei conti successivi come da regole); ciascuna riga della tabella degli errori (console esatta fino al guasto, codice di uscita, nessun file rimasto), compresi: guasto nella scrittura di `OUTFILE` (niente righe `VBRC`, niente `DISPLAY ACCOUNT-RECORD` per quel conto), nella scrittura del primo record variabile, a metà lettura; riesecuzione **fallita** con tre file sentinella preesistenti (non devono restare); forma esatta delle righe di console non coperte dal test di parità: numerici con segno positivi e negativi (segno sovrapposto, scala implicita), riga `VBRC-REC2:` (39 byte), riga del `DISPLAY ACCOUNT-RECORD` (tutti i 300 byte: CAP, gruppo e i 178 spazi compresi); tabella vuota (tre file vuoti, console di due righe, codice 0: verificarlo contro ciò che fa l'oracle con un file dei conti vuoto, e se l'oracle fa altro fermarsi); data di riemissione non valida (`ABCDEFGHIJ` → `ABCDFGIJ`).
3. **I test discriminano questa implementazione.** L'Esecutore applica al job, una alla volta, queste alterazioni e riporta quale test diventa rosso e con quale diagnosi (file, record, posizione). Devono essere rilevate dal test di parità: `ACCT-CREDIT-LIMIT` e `ACCT-CASH-CREDIT-LIMIT` scambiati in `OUTFILE`; `2525.00` → `2525.01`; segno del `COMP-3` di `2525.00` da `C` a `F`; `-1025.00` scritto positivo; `-2500.00` con scala sbagliata (`-250.00`); `ARR-ACCT-CURR-BAL(2)` preso dal limite di credito invece che dal saldo; `7B` → `30` in ciascuna delle due occorrenze inizializzate; riempimento finale di `ARRYFILE` a zeri invece che a spazi; mese e giorno della data scambiati; `VB2-ACCT-REISSUE-YYYY` preso dalla data di apertura; `VB2-ACCT-CREDIT-LIMIT` omesso; descrittore dei record variabili con la lunghezza dei soli dati; lettura in ordine **decrescente** di chiave; un conto saltato; una riga di console di classe a alterata; file non sostituiti alla riesecuzione. Devono essere rilevate dai test del modulo `batch`: ordine degli effetti alterato (tutta la console prima delle scritture); numerici con segno stampati con segno separato; `DISPLAY ACCOUNT-RECORD` senza il riempimento; file sentinella lasciati dopo una fine anomala. In più, per l'ordinamento: un controllo che la lettura dichiari esplicitamente l'ordine per `acct_id` (l'indice della chiave primaria può restituire le righe in ordine anche senza dichiararlo). **Una alterazione obbligatoria non rilevata impedisce l'accettazione**: se a non rilevarla è il test di parità, che non si può modificare, fermarsi con `needs-spec-update` e l'evidenza.
4. `./smoke.sh` ha un passo che lancia il job nell'applicazione avviata con Compose, sui conti caricati dal servizio di caricamento, e verifica codice 0, dimensione dei tre file (107 × 50, 110 × 50 e il flusso dei record variabili) e uguaglianza con i riferimenti dello scenario `esempio` attraverso il comparatore, se è utilizzabile fuori dai test, oppure con un confronto di impronte dei byte determinati; il passo fallisce se il job non scrive.
5. Regole sul codice: l'ispezione del codice compilato (virgola mobile, conversioni con perdita) copre le classi di produzione di `carddemo-batch`.

## Invarianti di parità

- Stesso effetto dell'originale in tutto ciò che il sorgente determina, compresa la prosecuzione dopo un campo non valorizzato; dove l'originale non determina un byte, il byte convenzionale dichiarato, mai un valore presentato come dell'originale.
- Stesso ordine di chiave; stesso comportamento alla riesecuzione.
- Importi solo `BigDecimal`.

## Criteri di accettazione

1. `./verify.sh` esce con 0, con il test di parità eseguito e riuscito in modo ordinario e `quality/fallimenti-attesi.tsv` senza righe per `READACCT`.
2. `./smoke.sh` esce con 0 con il passo nuovo.
3. `./quality/regressioni-verify.sh`, `./quality/regressioni-regole.sh` e i casi toccati delle altre suite escono con 0.
4. Tabella delle alterazioni del controllo 3 nella PR, con esito e diagnosi per ciascuna.
5. `git diff` sui casi di parità di `READACCT`: solo le rimozioni ammesse (marcatura, riga dell'elenco, pretesa della ricevuta); l'adeguamento degli avvii esistenti di `batch` che indicano il nome del job è distinto e ammesso. `git status --short` vuoto; diff nel perimetro.
6. CI verde sullo SHA finale.

## Strategia di rollback

Revert della PR: il test torna marcato "fallimento atteso".

## Limiti per l'agente

- Unico prerequisito dell'host: Docker e Git.
- Non modificare il test di parità, i riferimenti o le tabelle di #55 per far passare il test. Se il test o un riferimento sembrano sbagliati: fermarsi, commento tecnico con l'evidenza, `needs-spec-update`.
- Una sola issue: solo `CBACT01C`.
- Autocontrollo delle quattro famiglie prima della PR. File di appoggio sull'host con prefisso `issue-w2b-`.
