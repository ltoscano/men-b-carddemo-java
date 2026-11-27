BOCCIATA

Il diff comprende **39 file, tutti nel perimetro ammesso**. Nessun file fuori perimetro; `legacy/` è invariato. I nuovi documenti e attesi non aggiungono affermazioni sul comportamento COBOL da verificare sul sorgente.

Ho eseguito le prove in copie temporanee pulite, adattando soltanto i nomi delle risorse Docker al prefisso richiesto. Tutte le modifiche temporanee sono state ripristinate; nessun commit. Container, reti, volumi e immagini della validazione sono stati rimossi.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Perimetro | `rg '^diff --git' .validazione/diff.patch` e controllo dei percorsi | 39 file ammessi; nessuna modifica al legacy |
| Verifica ordinaria | `MENB_BUILD_CACHE_VOLUME=menb-val40-m2 ./verify.sh` | **0**. Presenti 16 controlli Enforcer riusciti, 4 esecuzioni Checkstyle senza violazioni e 2 test ArchUnit riusciti |
| Regressioni delle regole | `MENB_BUILD_CACHE_VOLUME=menb-val40-m2 ./quality/regressioni-regole.sh` | **0**. Base più 31 casi; ripristino e albero pulito |
| Smoke ordinario | `MENB_SMOKE_PROJECT=menb-val40-smoke ./smoke.sh` | **0**, `SMOKE RIUSCITO` |
| Regressioni di verify | `MENB_BUILD_CACHE_VOLUME=menb-val40-m2 MENB_REGRESSIONI_LOGS=<cartella temporanea> ./quality/regressioni-verify.sh` | **0**, tutti i casi rilevati |
| Smoke con campo `double` in produzione online | `MENB_SMOKE_PROJECT=menb-val40-negative ./smoke.sh` | **1**, fallimento Checkstyle al passo **build**, come richiesto |
| CI sul commit della PR | `gh pr list --head issue-26-regole-moduli --json number,headRefName,headRefOid,url,statusCheckRollup` | Commit `b6b501e`; controlli `verify` e `smoke` verdi nella [PR #40](https://github.com/ltoscano/men-b-carddemo-java/pull/40) |
| Versioni fissate | Lettura del POM padre, dei cinque POM e dei riferimenti Docker | Versioni nuove fissate direttamente o tramite parent fissato |

Ho riesaminato i log dei **24 casi negativi**: ciascuno contiene i marcatori del controllo atteso, senza errori di compilazione, download o timeout. I sei casi di cancello disattivato sono stati riconosciuti.

Le mutazioni aggiuntive hanno respinto correttamente generici annidati, ritorni wrapper, lambda tipizzate, array wrapper, record, annotazioni, import statici e letterali esadecimali. Gli archi con `provided`, `runtime` più `optional`, classifier, profilo attivo e dipendenza gestita effettivamente usata sono stati rilevati. Profilo inattivo, `dependencyManagement` non utilizzato e tipi sotto `src/test` passano coerentemente con il perimetro.

1. **Bloccante — Gli escape Unicode aggirano sia i tipi vietati sia `var`.**

   **Evidenza:** con Checkstyle attivo, queste dichiarazioni passano:
   ```java
   java.lang.\u0044ouble wrapper;
   \u0064ouble primitive;
   \u0066loat array[];
   void f() { \u0076ar hidden = Math.sqrt(2); }
   ```
   `mvn -B -pl carddemo-domain test` termina con **0**. `javap` conferma nel bytecode `java.lang.Double`, `double` e `float[]`: non è soltanto un controllo interrotto prima della compilazione. Vedi [bytecode osservato](file locale del Validatore, non conservato).

   **Schema generale:** i controlli in [checkstyle.xml:13](quality/regole/checkstyle.xml:13) non coprono la traduzione degli escape Unicode prevista da Java. Questa lacuna non è dichiarata fra i limiti.

   **Correzione richiesta:** adottare un controllo che riconosca tali forme, oppure respinga gli escape capaci di nascondere token e identificatori vietati. Aggiungere regressioni per primitivi, wrapper, array e `var`, verificando anche la compilabilità delle prove.

2. **Bloccante — Il divieto dei database non copre coordinate note di distribuzioni ripubblicate.**

   **Evidenza:** aggiunte separatamente a `online`, queste dipendenze lasciano `mvn -B validate` verde:
   ```text
   org.apache.servicemix.bundles:org.apache.servicemix.bundles.hsqldb:1.8.0.10_2
   org.apache.servicemix.bundles:org.apache.servicemix.bundles.derby:10.14.2.0_2
   ```
   Ho scaricato e ispezionato i JAR: contengono rispettivamente `org/hsqldb/jdbcDriver.class` e `org/apache/derby/jdbc/EmbeddedDriver.class`. Vedi [contenuto degli artefatti](file locale del Validatore, non conservato).

   **Schema generale:** entrambe le liste in [pom.xml:125](pom.xml:125) riconoscono soltanto cinque groupId. Un database già incorporato in un bundle ripubblicato non compare necessariamente come dipendenza transitiva originale.

   **Correzione richiesta:** completare l’elenco delle coordinate note, applicarlo alle verifiche dirette e transitive e aggiungere regressioni sui bundle realmente contenenti i database.

3. **Bloccante — Le immagini Docker vengono costruite senza eseguire ArchUnit.**

   **Evidenza:** ho introdotto in `online` una classe che usa un tipo del pacchetto `batch`, compilando il tipo ausiliario nello stesso modulo, senza aggiungere un arco Maven vietato. La verifica completa fallisce con:
   ```text
   Architecture Violation
   Field <...online.Val40Probe.forbidden> has type <...batch.Val40Foreign>
   ```
   Sullo stesso sorgente:
   ```sh
   docker build -f docker/app.Dockerfile --build-arg MODULE=online \
     -t menb-val40-architecture:probe .
   ```
   termina con **0**. Vedi [fallimento ArchUnit](file locale del Validatore, non conservato) e [build riuscita](file locale del Validatore, non conservato).

   **Schema generale:** [app.Dockerfile:21](docker/app.Dockerfile:21) seleziona il modulo applicativo e le sue dipendenze; `carddemo-parity`, che contiene ArchUnit, resta fuori. Copiare la configurazione rende operativo Checkstyle, ma non tutti i controlli.

   **Correzione richiesta:** eseguire anche la verifica architetturale prima di completare l’immagine e aggiungere questa controprova. Poiché il perimetro Docker attuale autorizza soltanto la copia della configurazione, occorre adeguare esplicitamente la specifica prima della modifica.

4. **Importante — Un errore durante la creazione della mutazione lascia sorgenti residui.**

   **Evidenza:** nella prova mirata della funzione `mut_java`, un `sed` che scrive un output parziale e termina con **42** fa fallire lo script, ma lascia:
   ```text
   ?? carddemo-domain/src/main/java/io/github/ltoscano/carddemo/domain/ProvaRegole.java
   ```
   Vedi [prova di ripristino fallita](file locale del Validatore, non conservato).

   **Schema generale:** in [regressioni-regole.sh:201](quality/regressioni-regole.sh:201) la redirezione crea il file prima che venga registrato in `CREATED`. Errori o interruzioni in quella finestra sfuggono al ripristino. L’albero sporco viene segnalato, ma non ripristinato.

   **Correzione richiesta:** registrare la destinazione prima della prima scrittura e controllare analoghe finestre nelle altre mutazioni. Aggiungere prove di scrittura parziale e interruzione.

5. **Importante — Diversi comandi esterni dello script non hanno limite di tempo.**

   **Evidenza:** con `MENB_REGOLE_SHORT_TIMEOUT=1`, un `sed` rallentato di quattro secondi viene accettato; la prova termina con **0** dopo **4,34 secondi**. Vedi [misura del timeout assente](file locale del Validatore, non conservato).

   **Schema generale:** `cp`, `awk`, `sed`, `grep` e le operazioni di ripristino sono invocati direttamente in più punti, non tramite `limited`. Il limite copre Maven e alcuni comandi amministrativi, contrariamente alla prescrizione «ogni comando».

   **Correzione richiesta:** applicare limiti ed esiti controllati a tutte le operazioni esterne, compreso il ripristino, e aggiungere regressioni sui comandi bloccati.

Le controprove mirate dello script riconoscono sia un caso reso lecito sostituendo `double` con `long` (`NON-RILEVATO`, uscita 1), sia un marcatore atteso alterato (`MOTIVO`, uscita 1). Restano limiti dichiarati, senza rilievo aggiuntivo: inferenza nelle espressioni, esclusione dei test e di `parity`, elenco finito di nomi aggiuntivi e opzioni di salto da riga di comando. `verify.sh`, CI e Dockerfile non usano tali opzioni.