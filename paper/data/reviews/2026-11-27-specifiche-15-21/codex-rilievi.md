1. **Specifica 21 — bloccante: il comando obbligatorio viola il divieto di ricostruire immagini.**  
   **Evidenza:** [21.md:31](prima/21.md:31) vieta di ricostruire `menb-analysis-*`. Ma `--check` riesegue tutti i trial ([check.sh:153](analysis/tools/check.sh:153)), che chiamano `build_image`; questa esegue sempre `docker build -t` ([common.sh:35](analysis/lib/common.sh:35)). Anche con cache, il comando costruisce e può riassegnare il tag condiviso.  
   **Correzione proposta:** autorizzare esplicitamente queste build oppure consentire un’esecuzione su daemon e immagini isolati, ampliando il perimetro necessario. Definire anche il comportamento su runner CI privo di immagini.

2. **Specifica 21 — importante: le fonti indicate non definiscono l’insieme esatto dei verdetti.**  
   **Evidenza:** [21.md:12](prima/21.md:12) indica `trials/` e `capabilities.tsv`; i trial producono misure, mentre nomi, directory e condizioni dei verdetti sono in [tools/run.sh:14](analysis/tools/run.sh:14). `capabilities.tsv` non elenca i verdetti COPY falliti di cmt e cobmix; il nome `prova-fallita-ripartizione.txt` è deciso in `run.sh:33`.  
   **Correzione proposta:** introdurre una dichiarazione unica consumata da produttore e controllore, autorizzando le modifiche a `run.sh`/`lib.sh`; oppure specificare esattamente come derivare l’insieme dal produttore esistente, comprese le riserve condizionali.

3. **Specifica 15 — importante: il divieto delle variabili locali può restare scoperto pur ottenendo l’accettazione.**  
   **Evidenza:** [15.md:14](prima/15.md:14) impone il controllo anche sulle variabili locali; `15.md:27` permette invece di dichiararle scoperte. Il modello pubblico di [ArchUnit](https://www.archunit.org/userguide/html/000_Index.html#_domain) espone membri e accessi, senza un controllo generale delle dichiarazioni locali.  
   **Correzione proposta:** rendere obbligatorio un controllo sul sorgente per le dichiarazioni locali, con fixture positiva e negativa eseguite da `verify.sh`; oppure restringere esplicitamente il requisito e registrare la copertura rinviata.

4. **Specifica 15 — importante: dipendenze Maven e dipendenze tra classi sono confuse.**  
   **Evidenza:** [15.md:12](prima/15.md:12) assegna ad ArchUnit anche il divieto dei database incorporati nel grafo Maven; `15.md:28` richiede che basti aggiungere una dipendenza vietata al POM. [ArchUnit analizza bytecode](https://www.archunit.org/userguide/html/000_Index.html#_introduction): una dipendenza dichiarata ma inutilizzata non introduce necessariamente accessi tra classi. Inoltre una mutazione che crea un ciclo Maven fallirebbe anche senza il cancello richiesto.  
   **Correzione proposta:** separare ArchUnit dai controlli Maven, usando per questi ultimi Enforcer o equivalente. Provare un arco vietato **aciclico e inutilizzato**, per esempio `loader → online`, e H2 senza riferimenti Java; verificare la causa del fallimento.

5. **Specifica 15 — importante: manca un collaudo discriminante della topologia Docker interna.**  
   **Evidenza:** [verify.sh:31](verify.sh:31) monta repository e cache, senza socket Docker né configurazione dell’host raggiungibile. [15.md:10](prima/15.md:10) lascia scegliere la soluzione, ma l’accettazione richiede evidenza CI soltanto su Linux. Nel modello con container fratelli servono accesso al daemon e raggiungibilità delle porte; Docker Desktop richiede la configurazione documentata di [`TESTCONTAINERS_HOST_OVERRIDE`](https://java.testcontainers.org/supported_docker_environment/continuous_integration/dind_patterns/).  
   **Correzione proposta:** richiedere prove su macOS e GitHub Actions. La negativa deve lasciare funzionante Docker per avviare Maven e negarne l’accesso **dentro Maven**, verificando che fallisca il test previsto entro un limite: spegnere Docker sull’host non dimostra questo requisito.

6. **Specifica 15 — importante: l’eccezione arm64 permette di consegnare Sonar inutilizzabile.**  
   **Evidenza:** [15.md:30](prima/15.md:30) accetta la sola dichiarazione dell’errore se Sonar non gira sull’architettura locale. La documentazione ufficiale dichiara invece il supporto delle immagini Community Build per [amd64 e Apple Silicon arm64](https://docs.sonarsource.com/sonarqube-community-build/server-installation/from-docker-image/installation-overview).  
   **Correzione proposta:** richiedere un tag fissato con manifest compatibile e una prova nativa sull’host previsto. Un’immagine scelta senza arm64 deve far fallire l’accettazione; un eventuale impedimento documentato richiede una decisione di perimetro, non un’esenzione automatica.

7. **Specifica 15 — importante: un rapporto JaCoCo vuoto potrebbe soddisfare la verifica descritta.**  
   **Evidenza:** [15.md:11](prima/15.md:11) non stabilisce posizione, contenuto o controlli sul rapporto; i criteri non lo verificano. Il [pom.xml:21](pom.xml:21) aggrega moduli ma non dichiara dipendenze verso di essi: `report-aggregate` raccoglie i progetti dalle [dipendenze, non dalla sola lista dei moduli](https://www.jacoco.org/jacoco/trunk/doc/report-aggregate-mojo.html).  
   **Correzione proposta:** fissare modulo aggregatore, fase e percorso; verificare XML corrente, classi attese e dati di esecuzione. `parity` possiede già le dipendenze utili. Distinguere l’assenza legittima di codice eseguibile in `domain`/`loader` da un rapporto accidentalmente vuoto.

8. **Specifica 15 — importante: il confronto PostgreSQL è fattibile, ma non è vincolato all’immagine realmente avviata.**  
   **Evidenza:** [15.md:10](prima/15.md:10) richiede il confronto; [verify.sh:34](verify.sh:34) monta tutto il repository, quindi `compose.yaml` è accessibile da `parity`, purché il percorso sia risolto dalla radice e non dalla directory corrente del modulo. Nessun criterio richiede una divergenza intenzionale: confrontare due copie della stessa stringa lascerebbe passare un container configurato diversamente.  
   **Correzione proposta:** confrontare `services.db.image` con la configurazione effettivamente passata a Testcontainers, includendo tag e digest; imporre negative separate per divergenza del tag e del digest.

9. **Specifica 15 — importante: “analisi Sonar completata” non ha una definizione verificabile.**  
   **Evidenza:** [15.md:17](prima/15.md:17) chiede avvio, analisi e URL, senza distinguere invio del rapporto da elaborazione conclusa. Sonar documenta che [`EXECUTION SUCCESS` dello scanner può precedere un’elaborazione server fallita](https://docs.sonarsource.com/sonarqube-community-build/analyzing-source-code/background-tasks). Restano inoltre da decidere bootstrap delle credenziali e ripetibilità dopo `--down`.  
   **Correzione proposta:** richiedere bootstrap documentato da clone pulito e attesa limitata del task della corsa corrente fino a `SUCCESS`; errori, cancellazione e scadenza devono produrre esito non zero. Specificare separatamente se il Quality Gate debba essere vincolante.

10. **Specifica 21 — importante: la negativa sul file aggiuntivo può dimostrare soltanto un controllo già esistente.**  
    **Evidenza:** [21.md:21](prima/21.md:21) non precisa quale file aggiungere. Un nome di controllo sconosciuto è già respinto. Il caso discriminante è una coppia directory/controllo indebita con contenuto valido: per esempio copiare il verdetto layout sotto `out/cmt/verdetto-layout.txt`. [check.sh:54](analysis/tools/check.sh:54) accetta il nome; `compare.py:336` esegue layout indipendentemente dal parametro strumento; il confronto con la rigenerazione esclude i verdetti.  
    **Correzione proposta:** imporre questa negativa, oltre al nome sconosciuto, e verificare l’insieme esatto dei percorsi relativi dovuti.

11. **Specifica 15 — importante: le regressioni della PR #20 non sono consegnate come comando ripetibile.**  
    **Evidenza:** [15.md:29](prima/15.md:29) rimanda alle prove precedenti. Il [rapporto del giro 2:5](paper/data/reviews/pr-20/giro-2-codex.md:5) rimanda a shim locali in `.validazione/prove/`; il [giro 1:59](paper/data/reviews/pr-20/giro-1-codex.md:59) dichiara il relativo harness non conservato. L’esecutore deve ricostruire iniezioni e oracoli.  
    **Correzione proposta:** elencare precisamente le regressioni richieste e aggiungere un harness versionato in `quality/`, con timeout, verifica del motivo del fallimento e ripristino. Escludere esplicitamente gli attacchi respinti dalla regola sulla sfiducia negli strumenti.

12. **Specifiche 15 e 21 — importante: la separazione dei file non risolve la regola sulla proprietà delle cartelle.**  
    **Evidenza:** [15.md:6](prima/15.md:6) e [21.md:8](prima/21.md:8) autorizzano entrambi interventi in `.github/workflows/`. [CLAUDE.md:76](CLAUDE.md:76) vieta due issue contemporaneamente sulla stessa cartella.  
    **Correzione proposta:** registrare prima dell’assegnazione un’eccezione esplicita per i due file disgiunti, oppure assegnare i workflow a un solo esecutore e serializzare quella parte.

13. **Specifica 15 — importante: il perimetro comprende almeno quattro consegne indipendenti.**  
    **Evidenza:** [15.md:10](prima/15.md:10)–`17` unisce infrastruttura Docker multipiattaforma, regole Java/Maven, copertura e analisi statica, più un server Sonar con ciclo di vita proprio. Ogni parte introduce scelte e prove negative diverse; il rollback unico le accoppia inutilmente.  
    **Correzione proposta:** dividerla in quattro PR sequenziali: **Testcontainers e robustezza di `verify.sh`**; **ArchUnit, divieti Maven e controllo dei tipi locali**; **JaCoCo e SpotBugs**, con politica di severità fissata; **Sonar locale**, con bootstrap, compatibilità arm64 e pulizia. Ogni PR deve avere un proprio comando di accettazione e preservare `smoke`.