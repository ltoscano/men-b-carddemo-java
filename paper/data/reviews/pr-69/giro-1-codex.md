BOCCIATA

Validato lo SHA `553930f`. Il diff contiene 18 file, tutti nel perimetro ammesso. **File fuori perimetro: nessuno.** `legacy/` e le classi di produzione risultano immutati.

Comandi e criteri di accettazione eseguiti:

| Criterio o prova | Comando eseguito | Esito osservato |
|---|---|---|
| Verifica ordinaria | `./verify.sh` | **0**. Comparatore 14, estensione 5, avvio 3, parità 4; quattro ricevute correnti. |
| Marcatura di `esempio` tolta | `./verify.sh` | **1**, `MotivoDichiarato job-readacct-assente` non intercettato. |
| Riga di `esempio` tolta | `./verify.sh` | **1**, `FALLIMENTO-ATTESO-NON-IN-ELENCO`. |
| Riga inesistente aggiunta | `./verify.sh` | **1**, `ricevuta assente ... #inesistente`. |
| Metodo, marcatura e riga tolti insieme | `./verify.sh` | **1**, `testcase ... ReadacctParitaTest.esempio assente dal rapporto`. |
| `mirato` caricato dall’ingresso di `esempio` | `./verify.sh` | **1**, record 3, offset 18, campo `ACCT-CURR-BAL` diverso prima dell’avvio. |
| Database del solo avvio irraggiungibile | `./verify.sh` | **1**, `FALLIMENTO-ATTESO-MOTIVO-DIVERSO`, codice del processo 1. |
| Smoke | `./smoke.sh` | **0**, `SMOKE RIUSCITO`. |
| Regressioni della verifica | `./quality/regressioni-verify.sh` | **0**. |
| Regressioni delle regole | `./quality/regressioni-regole.sh` | **0**. |
| Controprova copertura | `./quality/regressioni-copertura.sh controprova-lecita` | **0**, base e controprova eseguite. |
| Controprova codec richiesta | `./quality/regressioni-codec.sh controprova-lecita` | **1**, `caso richiesto sconosciuto`. Il caso manca già nello script preesistente; la base eseguita prima esce con 0. |
| Transizione con job fedele ed elenco vuoto | `./verify.sh` | **0**, quattro casi ordinariamente riusciti, zero ricevute richieste, cinque test del meccanismo riusciti. |
| Elenco vuoto, marcature tolte, jar senza traduzione | `mvn -B -pl carddemo-parity test -Dtest=ReadacctParitaTest` nel container | **1**, quattro errori ordinari `MotivoDichiarato`. |
| Ripristino | `git diff --exit-code`, controllo del submodule, `git status --short` | Nessuna modifica versionata. Rimane soltanto `?? .validazione/`, già presente inizialmente. |
| CI sullo SHA esaminato | Lettura dei risultati della PR | `verify`, `smoke`, `analysis-check`, `oracle-check`: **SUCCESS**. Conteggi locali e CI identici: 25 classi, 472 test. [CI](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46126515287) |

I sei controesempi dentro `verify.sh` sono falliti per le diagnosi indicate: nessun errore di compilazione, guasto Docker o timeout estraneo.

Ho aggiunto nella copia un vero job Spring Batch `READACCT`, che legge `account` con `ORDER BY acct_id` e riproduce i due scenari. I quattro casi sono diventati verdi togliendo soltanto marcature e righe dell’elenco. Nessuna modifica ai confronti o a `verify.sh`.

Le mutazioni successive sono state eseguite contro il jar reale con i test del modulo `carddemo-parity` nel container Maven. Per riesecuzione e ordine ho usato rispettivamente `miratoRiesecuzione` e `miratoOrdineDiLettura`; per le altre, `mirato`.

| Job di prova | Esito | Diagnosi osservata |
|---|---|---|
| Fedele, tutti e quattro i casi | Accettato | Quattro successi ordinari. |
| `ARRYFILE`, byte 80 a `30` | Respinto | `BYTE-DIVERSO: ARRYFILE record 1 posizione 80: atteso 7b, trovato 30`. |
| `ARRYFILE`, byte 99 a `30` | Respinto | Stessa diagnosi, posizione 99. |
| `VBRCFILE` nel formato GnuCOBOL | Respinto | `LUNGHEZZA-RECORD: VBRCFILE record 1 di 8 byte, atteso 12`. |
| `VBRCFILE` con BDW | Respinto | `DESCRITTORE: VBRCFILE record 1 (byte 1): lunghezza 2954 fuori da 5-84`. |
| Lettura senza `ORDER BY` | Respinto | `BYTE-DIVERSO: OUTFILE record 1 posizione 10`. |
| Segno errato nel conto 3 di `mirato` | Respinto | `BYTE-DIVERSO: OUTFILE record 3 posizione 24`. |
| Importo del conto 3 moltiplicato per 10 | Respinto | `BYTE-DIVERSO: OUTFILE record 3 posizione 18`. |
| Ultimo record di `OUTFILE` omesso | Respinto | `NUMERO-DI-RECORD: OUTFILE ha 49 record, attesi 50`. |
| Log/banner aggiunto a stdout | Respinto | `CONSOLE: riga 1`. |
| Uno spazio finale tolto | Respinto | `CONSOLE: riga 12`. |
| Scrittura soltanto se il file non esiste | Respinto al secondo avvio | `LUNGHEZZA: OUTFILE di 6350 byte, non multiplo di 107`. |
| Scrittura in append | Respinto al secondo avvio | `LUNGHEZZA: OUTFILE di 11700 byte, non multiplo di 107`. |
| Uscite corrette, exit code 1 | Respinto | `CODICE-DI-USCITA: atteso 0, trovato 1`. |
| Secondo avvio già completato | Respinto | Codice 1; Spring Batch richiede parametri diversi per rieseguire. |
| File scritti in percorsi diversi | Respinto | `FILE-ASSENTE: OUTFILE` nel percorso passato dal test. |
| Byte 77–78 di `OUTFILE` arbitrari | **Accettato** | Valori `ff fe` accettati nelle sole posizioni mascherate. |
| Byte 76 alterato | Respinto | `BYTE-DIVERSO: OUTFILE record 1 posizione 76`. |
| Byte 79 alterato | Respinto | `BYTE-DIVERSO: OUTFILE record 1 posizione 79`. |

Sono stati respinti anche i seguenti controesempi del comparatore:

| Alterazione | Diagnosi |
|---|---|
| `OUTFILE`, record 3 byte 20; data al byte 72 | `BYTE-DIVERSO`, con record e posizione corretti. |
| `ARRYFILE`, record 2 byte 5 | `BYTE-DIVERSO: ARRYFILE record 2 posizione 5`. |
| Record 1 e 2 scambiati | `BYTE-DIVERSO: OUTFILE record 1 posizione 11`. |
| Record logico VBRC 2 ridotto a 38 byte | `LUNGHEZZA-RECORD: VBRCFILE record 2 di 38 byte, atteso 39`. |
| Descrittore invertito | `DESCRITTORE: VBRCFILE record 1 (byte 1): byte 3-4 ... 10 00`. |
| Console determinata alterata | `CONSOLE: riga 2`. |
| Una riga di console omessa | `CONSOLE: 751 righe ... attese 752`. |
| `ARRYFILE` assente | `FILE-ASSENTE: ARRYFILE`. |
| Byte parziale aggiunto a ciascun file | Lunghezza non multipla per i fissi; `VBRCFILE record 101 (byte 2951): descrittore troncato`. |
| Record completo aggiunto a ciascun file | 51 record invece di 50; 101 invece di 100 per VBRC. |

Una riga di console di osservazione con contenuto arbitrario viene accettata, come previsto dalla specifica.

Sul comparatore e sulla preparazione:

- Il contenuto atteso proviene soltanto dai riferimenti di `oracle/golden/readacct/`. Lettore RDW e conversione del simulatore sono separati.
- Ho alterato separatamente tutti gli otto file `*.riferimento.txt`: il test positivo li respinge con codice 1; il verificatore indipendente di #55 li respinge con codice 4.
- Allargare la maschera nel riferimento oppure cambiare `esclusioni.tsv` fa fallire il controllo di uguaglianza delle maschere.
- `osservazione` viene rifiutato con `SCENARIO-NON-AMMESSO`.
- L’atteso della preparazione è ricavato indipendentemente dalla funzione che sceglie l’ingresso. L’ingresso permutato conserva gli stessi record; interrogando la tabella **senza `ORDER BY`**, le prime chiavi sono effettivamente `50, 49, 48, 47, 46`.

Sul meccanismo e sulla transizione:

| Prova | Esito osservato |
|---|---|
| Job `READACCT` avviato, propria eccezione con il testo cercato, exit 1 | **Falso verde: quattro casi e quattro ricevute accettati.** |
| Errore precedente alla selezione con lo stesso testo | **Falso verde.** |
| Job chiamato `readacct` oppure `READACCT ` | Assenza riconosciuta nella fase marcata; rosso dopo la transizione. |
| Job che non termina, limite ridotto a 10 secondi | Rosso: `FALLIMENTO-ATTESO-MOTIVO-DIVERSO` con `AVVIO-LIMITE-DI-TEMPO`; discendenti ancora vivi. |
| Jar assente | Rosso, `jar eseguibile ... assente`. |
| Jar precedente | Utilizzabile dal solo comando del modulo. `verify.sh` lo elimina e ricostruisce: provato inserendolo prima della verifica completa di transizione. |
| `@Disabled` oppure assunzione fallita | Maven 0, controllo XML 1: `skipped=1`. |
| Classe rinominata | Controllo XML 1: rapporto atteso assente. |
| Metodo rinominato o cancellato dopo la transizione | Controllo XML 1: `testcase ... esempio assente`. |
| Ricevuta della corsa precedente | Respinta: corsa diversa. |
| Ricevuta scritta a mano con identificativo corretto | Accettata dal lettore: richiede **falsificare un artefatto generato**. |
| Riga duplicata | Respinta dall’estensione; il lettore delle ricevute, isolato, la accetta. |
| Campi aggiuntivi | Respinti da entrambi i parser. |
| Riga vuota o commento | Accettati. |
| CRLF | Interpretazione coerente dei due parser. |
| Spazi finali | Conservati come parte del campo; producono discrepanza con marcatura/ricevuta. |

La lettura della “pretesa della ricevuta” come riga dell’elenco **non apre un varco nella cancellazione dei casi**: i quattro nomi restano richiesti indipendentemente dall’elenco. Le applicazioni di prova sono avviate in processi separati e risultano assenti sia dal jar di produzione sia dal jar estratto dall’immagine dello smoke.

Le affermazioni legacy introdotte dalla PR corrispondono ai sorgenti: DD, `PREDEL` e lunghezze sono in `legacy/aws-mainframe-modernization-carddemo/app/jcl/READACCT.jcl:22–47`; lettura indicizzata sequenziale in `app/cbl/CBACT01C.cbl:30–33`; conteggio dei `DISPLAY` nelle righe 141, 151, 158, 201–212 e 283–284; lunghezze variabili 12 e 39 nelle righe 288 e 303. Le occorrenze 4–5 dell’array restano inizializzate dopo le assegnazioni alle prime tre (`CBACT01C.cbl:169,254–260`). La maschera della data è coerente con gli otto byte scritti da `app/asm/COBDATFT.asm:51–53`, l’area `X(20)` di `app/cpy/CODATECN.cpy:39` e la copia in `CBACT01C.cbl:233`.

Versioni gestite dal BOM fissato; PostgreSQL reale; nessun profilo Maven aggiunto; Java eseguito nei container; nessun percorso personale o segreto introdotto.

I rilievi sono:

1. **Bloccante — riconoscimento dell’assenza basato su una sottostringa, senza verificarne l’origine.**  
   Evidenza: `carddemo-parity/src/test/java/io/github/ltoscano/carddemo/parity/AvvioJob.java:110–119` accetta exit 1 e `contains(DIAGNOSTICA_JOB_ASSENTE)`. Il mio vero job `READACCT` è entrato nel tasklet, ha stampato una propria `IllegalStateException` con quel messaggio ed è uscito con 1 senza scrivere le uscite: **4/4 casi verdi e controllo delle quattro ricevute verde**. Anche l’errore precedente alla selezione è accettato. [Evidenza] (file locale del Validatore, non pubblicato)  
   **Schema generale:** testo diagnostico scambiato per prova della causa e della fase del fallimento. **Impatto:** falso verde nella fase marcata; può nascondere una traduzione presente ma rotta finché restano le marcature. Dopo la loro rimozione il caso diventa rosso. Nessuna alterazione dei golden. **Riproduzione:** modifica del solo job di prova, corrispondente a codice versionato; nessuna ricevuta o rapporto falsificato. **Correzione richiesta:** riconoscere la diagnostica nativa nel suo contesto causale del selettore, respingere errori precedenti o successivi alla selezione e aggiungere controprove obbligatorie per entrambi.

2. **Importante — al timeout sopravvivono i discendenti.**  
   Evidenza: `AvvioJob.java:102–105` termina soltanto `p`, senza gestirne i discendenti; ignora inoltre l’esito della seconda attesa. Dopo il timeout del caso marcato il test è correttamente rosso, ma il processo shell e il suo `sleep 3600` erano entrambi vivi; la shell aveva già `PPID=1`. [Evidenza dei processi] (file locale del Validatore, non pubblicato)  
   **Schema generale:** pulizia limitata al processo principale, senza gestione dell’albero e dell’interruzione. **Impatto:** nessun falso verde o oracle infedele osservato; difetto di isolamento e pulizia. **Riproduzione:** job di prova che avvia discendenti e non termina; nessun artefatto falsificato. **Correzione richiesta:** terminare e verificare la cessazione dell’albero dei processi, con attese limitate e pulizia anche su interruzione; aggiungere una prova obbligatoria con figlio e nipote.

3. **Minore — alcune diagnosi non rispettano il contratto “file, record e posizione”.**  
   Evidenza: `ComparatoreReadacct.java:137–150` produce soltanto lunghezza totale o conteggio per file troncati, parziali o con record aggiuntivi. Per esempio: `NUMERO-DI-RECORD: OUTFILE ha 49 record, attesi 50` e `LUNGHEZZA: OUTFILE di 5351 byte, non multiplo di 107`. Anche le differenze di console indicano la riga senza la posizione del carattere. I test accettano queste diagnosi incomplete.  
   **Schema generale:** le verifiche strutturali perdono la localizzazione della prima differenza e i test controllano prefissi insufficienti. **Impatto:** nessuna traduzione sbagliata accettata, nessuna giusta respinta, nessun oracle infedele; manca la diagnosi richiesta. **Riproduzione:** output errato prodotto dal job di prova, senza falsificare rapporti o ricevute. **Correzione richiesta:** indicare record e posizione determinabili, compreso il punto di EOF, e verificare tali informazioni nei test.

Tutte le prove sono state ripristinate. Risorse Docker dell’audit rimosse, nessun commit o push. [Esiti completi] (file locale del Validatore, non pubblicato).