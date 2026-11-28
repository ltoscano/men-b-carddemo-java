BOCCIATA

Validato lo SHA `eed2cd47d4645c6375dc8492b46af49e766e68ea`. Nessun file fuori perimetro: il diff comprende 13 file ammessi. `legacy/` è invariato.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Build e suite obbligatorie | `./verify.sh` | **0**; 426 test, nessun fallimento o salto; 20 nuovi casi eseguiti |
| Smoke applicativo | `./smoke.sh` | **0** sul ramo originale; riprodotti due falsi verdi descritti sotto |
| Regressioni verify | `./quality/regressioni-verify.sh` | **0**, tutti i casi rilevati |
| Regressioni regole | `./quality/regressioni-regole.sh` | **0**, ripristino pulito |
| Copertura richiesta | `./quality/regressioni-copertura.sh controprova-lecita` | **0**, base e controprova riuscite; nessun altro atteso dello script cambia nel diff |
| Prove negative | Mutazioni elencate sotto, una alla volta | Eseguite, con diagnosi specifiche |
| Perimetro, versioni, profili | `git diff --name-only origin/main...HEAD`, ispezione POM e jar | Perimetro rispettato; nessun profilo Maven; Flyway effettivo **12.11.0**, fissato attraverso il parent Spring Boot **4.2.0** |
| Stato Git | `git status --short`, `git diff --exit-code` | Nessuna modifica versionata; dopo la restituzione dei materiali resta soltanto `.validazione/` non tracciata |
| CI sullo SHA finale | `gh pr view …`, `gh run view … --log` | Tutti i check verdi. Conteggi coincidenti: domain 399, loader/online/batch 1 ciascuno, parity 24 |

Ho usato una cache Maven dedicata e progetti Compose `menb-val61-*`. Le risorse Docker dell’audit sono state rimosse; nessun commit o push.

1. **Bloccante — La condizione di arresto su `CHAR(n)` è stata ristretta unilateralmente.**

   **Evidenza:** `docs/contratti.md:124–126` introduce il divieto di conversione esplicita a `text` per giustificare il mancato `needs-spec-update`. Ho confermato che il confronto cambia risultato:
   
   - valore memorizzato: `G1` riempito a dieci caratteri;
   - `colonna = ?`, parametro riempito: **1 riga**;
   - `colonna = ?::text`, stesso parametro: **0 righe**.

   Inoltre, senza alcun cast esplicito, `lower(colonna) = lower(?)` restituisce **0 righe** con il parametro riempito. Il legacy usa proprio `FUNCTION LOWER-CASE` su questi campi in `legacy/aws-mainframe-modernization-carddemo/app/cbl/COACTUPC.cbl:4139–4140`; `ACUP-OLD-GROUP-ID` è `PIC X(10)` alla riga 708. La controprova eseguita con GnuCOBOL restituisce **TRUE** tra i due campi riempiti.

   **Schema generale:** dichiarare equivalenza sulla base di un sottoinsieme delle operazioni, aggiungendo restrizioni d’uso non approvate dalla specifica. La perdita non riguarda soltanto conversioni esplicite.

   **Correzione richiesta:** aprire `needs-spec-update` e sottoporre alla decisione prevista un contratto completo di lettura e confronto, comprese le conversioni implicite; poi allineare documentazione e test.

   **Falso verde / oracle infedele:** sì, sul contratto di confronto. **File versionati:** specifica, documentazione e test. **Falsificazione di artefatti generati:** non necessaria.

2. **Importante — Lo smoke non dimostra che `batch` sappia eseguire la migrazione.**

   **Evidenza:** aggiungendo soltanto
   
   ```properties
   spring.flyway.skip-executing-migrations=true
   ```
   
   alle proprietà di `batch`, `./smoke.sh` termina ancora con **0**. I tre messaggi cercati in `smoke.sh:508–517` compaiono realmente: `online` ha già migrato il database.

   Avviando il jar batch con la stessa impostazione su un database vuoto, il processo termina con **0**, crea lo storico Flyway e le tabelle Batch, ma **non crea `account`**.

   **Schema generale:** osservare un’applicazione soltanto su uno stato già preparato da un’altra applicazione; i messaggi di validazione non provano l’esecuzione del contenuto SQL.

   **Correzione richiesta:** provare anche `batch` come primo migratore su database vuoto, controllando gli oggetti risultanti. La mutazione sopra deve rendere rosso lo smoke.

   **Falso verde:** sì, dello smoke; altri test attuali possono intercettarlo. **Oracle infedele:** la diagnosi dello smoke attribuisce una capacità non dimostrata. **File versionati:** basta modificare `application.properties`; nessun artefatto falsificato.

3. **Importante — Il passo `migrazione` accetta una vista al posto della tabella.**

   **Evidenza:** sostituendo temporaneamente V1 con
   
   ```sql
   CREATE VIEW account AS SELECT 1 AS acct_id;
   ```
   
   `./smoke.sh` termina con **0** e dichiara «tabella account presente». `to_regclass`, usato in `smoke.sh:471`, risolve anche una vista.

   **Schema generale:** usare la risoluzione del nome di una relazione come prova del suo tipo.

   **Correzione richiesta:** verificare nel catalogo che `account` sia effettivamente una tabella, aggiungendo la controprova con una vista omonima.

   **Falso verde:** sì, dello smoke; i test di schema respingono la mutazione. **Oracle infedele:** sì, nella diagnosi “tabella presente”. **File versionato:** migrazione SQL; nessun artefatto falsificato.

4. **Importante — Il classpath condiviso rende infedeli i test di avvio delle applicazioni.**

   **Evidenza:** ho rimosso, a turno, `spring-boot-starter-flyway` dal POM di `online` e da quello di `batch`. In entrambi i casi **`./verify.sh` termina con 0**, compresi i quattro casi di `AccountMigrazioneTest`.

   I jar prodotti, avviati separatamente su database vuoti, partono senza creare né `account` né `flyway_schema_history`. Il test avvia le classi nello stesso processo (`AccountMigrazioneTest.java:156`), dove l’autoconfigurazione viene fornita dall’altro modulo.

   **Schema generale:** verificare la configurazione di un’applicazione dentro un classpath più ricco di quello distribuito, nascondendo dipendenze mancanti.

   **Correzione richiesta:** verificare entrambe le applicazioni con il rispettivo classpath effettivamente distribuito. Togliere lo starter dal singolo modulo deve far fallire il relativo controllo di avvio.

   **Falso verde:** sì, di `verify.sh`; lo smoke ordinario conserva una difesa separata. **Oracle infedele:** sì, rispetto al runtime distribuito. **File versionato:** basta il POM applicativo; nessun artefatto falsificato.

5. **Importante — L’attesa documentata per testo lungo con eccedenza di spazi è falsa.**

   **Evidenza:** `docs/contratti.md:116` afferma che anche `::text` restituisce “i primi 10 caratteri”. Con inserimento JDBC parametrizzato di `"G1" + 11 spazi` ho ottenuto:
   
   - JDBC diretto: `"G1" + 8 spazi`;
   - `::text`: `"G1"`.

   Il test `AccountSchemaTest.java:292–295` usa soltanto dieci `B` prima dell’eccedenza: quel campione nasconde il caso in cui i primi dieci caratteri contengono già spazi finali.

   **Schema generale:** generalizzare un risultato da un campione che evita l’interazione tra due proprietà del dato.

   **Correzione richiesta:** correggere la tabella documentale e aggiungere casi lunghi con spazi anche nella porzione conservata, compreso un valore interamente composto da spazi.

   **Falso verde:** sì, rispetto all’affermazione documentale. **Oracle infedele:** sì. **File versionati:** documentazione e test; nessun artefatto falsificato.

Ho interrogato direttamente PostgreSQL **18.7**, della stessa immagine e digest, dopo l’applicazione della migrazione. Le dodici colonne coincidono per nome, ordine, tipo, precisione, scala, annullabilità e predefiniti. Coincidono anche i dodici `NOT NULL`, `PRIMARY KEY (acct_id)`, `CHECK ((acct_id >= (0)::numeric))` e l’unico indice della chiave primaria. Il [catalogo rilevato](/tmp/menb-val61-audit/catalogo.txt) contiene il confronto completo.

I campi e il refuso sono confermati da `legacy/aws-mainframe-modernization-carddemo/app/cpy/CVACT01Y.cpy:5–17`; la chiave da `app/jcl/ACCTFILE.jcl:40`; il caricamento tramite `REPRO` senza validazione delle date dalla riga 61. Ho controllato i 50 record del campione EBCDIC: chiavi distinte e canoniche, importi canonici, filler di 178 spazi.

Le mutazioni di schema sono passate dal container Maven del progetto con:

```sh
mvn -B -pl carddemo-parity -am test \
  -Dtest=AccountSchemaTest,AccountContrattoTest \
  -Dsurefire.failIfNoSpecifiedTests=false -Dmenb.verify.run=<corsa>
```

| Mutazione | Esito | Test che la rileva |
|---|---:|---|
| Scala `NUMERIC(12,3)` | 1 | `AccountContrattoTest`; limiti e scala riletta |
| `NUMERIC(13,2)` | 1 | `AccountContrattoTest`; `unaCifraInteraInPiuERifiutata` |
| Due colonne dello stesso tipo scambiate | 1 | `AccountContrattoTest`, confronto dell’ordine |
| `CHAR(10)` → `VARCHAR(10)` | 1 | `AccountContrattoTest`; lettura, spazi e confronti |
| `CHAR(10)` → `CHAR(11)` | 1 | `AccountContrattoTest`; lunghezza riletta |
| `NOT NULL` tolto | 1 | Confronto colonne e `vincoliChiavePrimariaECheckSullaChiave` |
| `CHECK` tolto | 1 | Confronto vincoli e `chiaveNegativaRifiutata` |
| `CHECK (acct_id > 0)` | 1 | Confronto vincoli e minimo numerico pari a zero |
| `DEFAULT 0` aggiunto | 1 | Confronto colonne/predefiniti |
| Indice aggiunto | 1 | `soloLIndiceDellaChiavePrimaria`, `oggettiDelloSchemaETrigger` |
| Chiave primaria composta | 1 | Confronto vincoli e indice |
| Chiave primaria tolta | 1 | Vincoli, indice e `chiaveDuplicataRifiutata` |
| Colonna annullabile aggiunta in coda | 1 | `AccountContrattoTest`, confronto colonne |
| Nome `acct_expiration_date` | 1 | `AccountContrattoTest`, colonna contrattuale mancante |
| Tabella in schema diverso | 1 | `AccountContrattoTest`; controlli su `public.account` |

Nella prova coordinata ho tolto `acct_group_id` anche dalle attese e dai conteggi. **Schema: 15/15 verdi; migrazione: 4/4 verdi; contratto: rosso**, con diagnosi `acct_group_id character(10)` mancante. Il TSV viene letto dal repository tramite `menb.contratto.account`, senza copia incorporata.

| Ulteriore prova | Comando/percorso | Esito osservato |
|---|---|---|
| Suite esclusa | `./verify.sh` | 1, rapporto assente |
| Suite disabilitata | `./verify.sh` | 1, caso saltato |
| Caso rinominato | `./verify.sh` | 1, nome obbligatorio assente |
| Caso spostato in altra classe | `./verify.sh` | 1, rapporto della classe obbligatoria assente |
| Classe `abstract` | `./verify.sh` | 1, rapporto assente |
| Rapporto autentico precedente | `RapportoSurefire.java` | 1 con identificativo diverso; 0 con quello originale |
| Tentativo con H2 | `./verify.sh` | 1, `DATABASE-INCORPORATO-VIETATO`, prima dell’esecuzione dei test |
| Atteso decimale alterato | Modulo parity | 1, `0.02` atteso contro `0.01` effettivo |
| Ordinamento invertito | Modulo parity | 1, ordine numerico errato |
| Trigger aggiunto | Modulo parity | 1, trigger attesi 0, rilevati 1 |

Le due prove con Flyway disattivato rendono rosso lo smoke, rispettivamente ai passi `migrazione` e `batch-1`. Nei jar reali, una migrazione modificata dopo l’applicazione impedisce entrambi gli avvii con `checksum mismatch`. Avvio batch per primo, riavvii e convivenza con l’inizializzatore Batch riescono; database con sole tabelle Batch vengono rifiutati da entrambe le applicazioni, come documentato.

La lettura JDBC degli spazi, i confronti ordinari e l’arrotondamento silenzioso dei decimali sono confermati. Nelle righe aggiunte agli script non ho trovato esiti di comando persi, attese prive di limite o residui di corsa riutilizzati. Restano aperti i cinque rilievi sopra.