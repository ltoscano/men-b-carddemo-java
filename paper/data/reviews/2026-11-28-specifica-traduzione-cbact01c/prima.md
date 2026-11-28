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
- **Posizioni non determinate dal sorgente** (byte 77-78 di ogni record di `OUTFILE`, #55): il Java scrive `00 00`. **Decisione delegata**: è il valore dell'oracle; qualunque valore passerebbe il confronto, e questo rende il file identico a quello dell'oracle anche lì. Va scritto in `docs/programmi/CBACT01C.md` che è una scelta e non un comportamento dell'originale.
- **Addebito di ciclo diverso da zero** (`CBACT01C.cbl:236-238`): l'originale in quel caso non valorizza `OUT-ACCT-CURR-CYC-DEBIT` e scrive ciò che resta nell'area (#55, scenario di osservazione). **Decisione delegata**: il Java non inventa un valore e non imita un compilatore: si ferma su quel conto con un errore dichiarato (codice di uscita dedicato, messaggio con la chiave del conto e il riferimento alla riga del sorgente), come gli equivalenti delle routine dell'oracle si fermano sui casi non determinati (registro, voci 42 e 63). Alternative scartate: copiare il valore del record precedente (comportamento di GnuCOBOL, non definito su z/OS); scrivere l'addebito del conto (plausibile intenzione del programmatore, ma non è ciò che il programma fa). I dati di esempio non hanno alcun conto in questa condizione.
- **`VBRCFILE`**: due record per conto, 12 e 39 byte, con il descrittore fissato da #65.
- **Console**: una riga per ogni `DISPLAY`, nell'ordine dell'originale. Righe di classe a: identiche al riferimento. Righe con numerici con segno: il campo si stampa come sequenza dei suoi byte nel profilo (segno sovrapposto all'ultima cifra), che è la forma documentata da IBM per `DISPSIGN(COMPAT)`; non è confrontata dal test e va dichiarato. `DISPLAY` di gruppo: i byte del gruppo su una riga sola; la suddivisione che z/OS farebbe per un operando di 300 byte non è riprodotta e va dichiarato.
- **Fine anomala**: se il job fallisce dopo aver creato file di uscita, li cancella, come il JCL (`DISP=(NEW,CATLG,DELETE)`, `READACCT.jcl:37-47`); codice di uscita diverso da 0; nessun file parziale resta. Un errore del database durante la lettura è l'analogo dell'errore di lettura del file (`CBACT01C.cbl:180-195`): messaggio, fine anomala, file cancellati.
- **Riesecuzione** e **comando**: come fissati da #65. Gli avvii esistenti di `batch` che non indicano un job (`smoke.sh`, test di avvio) si adeguano indicando il job che già eseguivano.
- Nessuna idempotenza, validazione o "miglioria" che l'originale non ha: stati non `Y`, date non valide e importi qualsiasi si trattano come nell'originale.

### Controlli

1. Il test di parità di #65 passa per `esempio`, `mirato`, riesecuzione e ordine di lettura, **senza la marcatura**; nel diff del test compaiono solo le rimozioni ammesse.
2. Test del modulo `batch` sui casi che i riferimenti non coprono: conto con addebito diverso da zero (arresto dichiarato, nessun file lasciato, conti precedenti non pubblicati); errore del database a metà lettura (file cancellati, codice diverso da 0); tabella vuota (tre file vuoti, console di due righe, codice 0: verificarlo contro ciò che fa l'oracle con un file dei conti vuoto, e se l'oracle fa altro fermarsi); data di riemissione non valida (`ABCDEFGHIJ` → `ABCDFGIJ`).
3. **Il test di parità discrimina questa implementazione**: l'Esecutore applica al job, una alla volta, almeno queste alterazioni e riporta che il test di parità diventa rosso con la diagnosi che nomina file, record e posizione: due limiti scambiati; una costante cambiata di un centesimo; segno di una costante negativa perso; mese e giorno della data scambiati; `7B` → `30` nelle occorrenze inizializzate; un campo di `VBRC-REC2` omesso; descrittore dei record variabili con la lunghezza dei soli dati; lettura senza ordinamento; un conto saltato; una riga di console di classe a alterata; file non sostituiti alla riesecuzione. Un'alterazione che il test non rileva va riportata come tale: è un difetto del test, e si apre una issue invece di modificarlo.
4. `./smoke.sh` ha un passo che lancia il job nell'applicazione avviata con Compose, sui conti caricati dal servizio di caricamento, e verifica codice 0, dimensione dei tre file (107 × 50, 110 × 50 e il flusso dei record variabili) e uguaglianza con i riferimenti dello scenario `esempio` attraverso il comparatore, se è utilizzabile fuori dai test, oppure con un confronto di impronte dei byte determinati; il passo fallisce se il job non scrive.
5. Regole sul codice: l'ispezione del codice compilato (virgola mobile, conversioni con perdita) copre le classi di produzione di `carddemo-batch`.

## Invarianti di parità

- Stesso effetto dell'originale nelle posizioni determinate; nessun valore inventato dove l'originale non determina.
- Stesso ordine di chiave; stesso comportamento alla riesecuzione.
- Importi solo `BigDecimal`.

## Criteri di accettazione

1. `./verify.sh` esce con 0, con il test di parità eseguito e riuscito in modo ordinario e `quality/fallimenti-attesi.tsv` senza righe per `READACCT`.
2. `./smoke.sh` esce con 0 con il passo nuovo.
3. `./quality/regressioni-verify.sh`, `./quality/regressioni-regole.sh` e i casi toccati delle altre suite escono con 0.
4. Tabella delle alterazioni del controllo 3 nella PR, con esito e diagnosi per ciascuna.
5. `git diff` sul test di parità: solo le rimozioni ammesse. `git status --short` vuoto; diff nel perimetro.
6. CI verde sullo SHA finale.

## Strategia di rollback

Revert della PR: il test torna marcato "fallimento atteso".

## Limiti per l'agente

- Unico prerequisito dell'host: Docker e Git.
- Non modificare il test di parità, i riferimenti o le tabelle di #55 per far passare il test. Se il test o un riferimento sembrano sbagliati: fermarsi, commento tecnico con l'evidenza, `needs-spec-update`.
- Una sola issue: solo `CBACT01C`.
- Autocontrollo delle quattro famiglie prima della PR. File di appoggio sull'host con prefisso `issue-w2b-`.
