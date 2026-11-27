BOCCIATA

I comandi ordinari passano, ma ho riprodotto falsi verdi nei controlli di provenienza, freschezza, configurazione SpotBugs ed esclusioni.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Verifica ordinaria | `./verify.sh` | **0**; aggregato JaCoCo con 3 classi eseguibili, prove dell’agente su 5 moduli, rapporti SpotBugs su 4 moduli |
| Regressioni nuove | `./quality/regressioni-copertura.sh` | **0**; 29 casi; **50m14s**, una sola esecuzione con limite complessivo di 60 minuti; working tree pulito |
| Regressioni della verifica | `./quality/regressioni-verify.sh` | **0**; `repackage-rimosso` fallisce al controllo del jar per il motivo atteso |
| Regressioni delle regole | `./quality/regressioni-regole.sh` | **0**; working tree pulito |
| Smoke | `./smoke.sh` | **0**; `SMOKE RIUSCITO` |
| Perimetro | `git diff --name-only origin/main...HEAD` | 17 file; unica violazione del vincolo d’uso: `quality/regressioni-verify.sh`, rilievo 6 |
| CI sullo SHA `982f873` | `gh api repos/ltoscano/men-b-carddemo-java/commits/982f87393743a52b9562dc6bbff67b6cb13f2eaa/check-runs` | `verify`, `smoke`, `analysis-check`: **success** |

Nelle regressioni nuove non ho trovato fallimenti attribuibili a compilazione, download o timeout. Le due chiamate al validatore rimosse lasciano effettivamente `verify.sh` a **0** e vengono rilevate dalla completezza.

Ho eseguito altre **31 prove**, tutte attraverso `./verify.sh`. [Codici, tempi e messaggi osservati](file locale del Validatore, non conservato).

| Mutazione aggiuntiva | Esito osservato |
|---|---|
| Agente spento in `online`, `jacoco.exec` copiato da `domain` della stessa corsa | **0: falso verde** |
| Agente spento, file di esecuzione di una corsa precedente | **1**, sessione vecchia rilevata |
| Classe nuova esclusa dall’aggregato mediante `excludes` | **1**, classe mancante rilevata |
| Record, record vuoto, enum, enum vuoto, interfaccia default, codice solo sintetico e classe sintetica da switch | **0**; nessun falso rosso osservato |
| Aggregato vecchio con soli identificativi di sessione aggiornati | **0: falso verde** |
| Soglia locale `High` con difetti `Medium` | **0: falso verde**; stesso codice con `Medium`: **1**, `EI_EXPOSE_REP` e `EI_EXPOSE_REP2` |
| Difetto in classe annidata / lambda | **1** ciascuno, rispettivamente `NP_ALWAYS_NULL` e `RV_RETURN_VALUE_IGNORED` |
| `onlyAnalyze` limitato a `package-info` / rilevatore `FindNullDeref` disattivato | **0: falsi verdi**; configurazione ordinaria: **1** |
| Esclusione globale con motivo | **0**, ammessa dalla specifica |
| Esclusione globale senza motivo tramite `<Class>` | **0: falso verde** |
| Filtro reale alternativo, percorso autorizzato presente soltanto in un commento POM | **0: falso verde** |
| Semplice commento POM contenente `excludeFilterFile` | **1: falso rosso** |
| Rapporto SpotBugs vecchio con solo `analysisTimestamp` aggiornato | **0: falso verde** |
| `spotbugs.skip` in profilo attivo / `.mvn/maven.config` | **1** ciascuno, rapporti mancanti |
| DTD ed entità esterne | Nessuna richiesta al server predisposto; nessuna espansione osservata |
| DOCTYPE estraneo a JaCoCo | Accettato: il parser ignora i DTD, senza una lista di identificativi ammessi |
| Atteso della controprova cambiato da 5 a 6 | **1**, fallimento dell’asserzione |

Anche il controllo di completezza considera completi i log dei falsi verdi sopra indicati.

1. **Bloccante — La prova JaCoCo non identifica il modulo. Falso verde: sì.**  
   In [RapportiQualita.java:109](quality/RapportiQualita.java:109) basta una sessione della corsa corrente; tutti i moduli ricevono lo stesso `sessionId` dal [POM:170](pom.xml:170). Ho spento l’agente in `online` e copiato il file corrente di `domain`: viene dichiarato attivo anche l’agente di `online`.  
   **Schema:** identificazione della corsa scambiata per identificazione del produttore.  
   **Correzione richiesta:** legare la prova anche al modulo e aggiungere regressioni con scambio di file fra moduli della stessa corsa, inclusi quelli senza produzione eseguibile.

2. **Bloccante — La freschezza dipende da un solo metadato ritoccabile. Falso verde: sì.**  
   Il controllo JaCoCo confronta soltanto gli ID delle sessioni ([riga 143](quality/RapportiQualita.java:143)); quello SpotBugs soltanto `analysisTimestamp` rispetto all’inizio corsa ([riga 347](quality/RapportiQualita.java:347)). Entrambi accettano rapporti realmente prodotti prima, aggiornando soltanto quel campo.  
   **Schema:** metadato autodichiarato senza riscontro con gli artefatti correnti.  
   **Correzione richiesta:** verificare la coerenza delle sessioni complete dell’aggregato con gli `exec` correnti e stabilire un legame effettivo del rapporto SpotBugs con la corsa. Aggiungere entrambe le regressioni con metadati ritoccati.

3. **Bloccante — `ClassStats` non dimostra l’analisi richiesta né la soglia effettiva. Falso verde: sì.**  
   Il controllo verifica l’inventario delle classi ([riga 369](quality/RapportiQualita.java:369)), ma passa con `onlyAnalyze` limitato a `package-info`, con `FindNullDeref` disattivato e con soglia locale `High` che nasconde due difetti `Medium`. I quattro difetti automatici sono tutti classificati `High`: non proteggono il confine `Medium` dichiarato.  
   **Schema:** assenza di segnalazioni e presenza nell’inventario scambiate per analisi conforme alla politica.  
   **Correzione richiesta:** verificare configurazione effettiva, ambito e rilevatori; aggiungere regressioni per restrizione dell’analisi e difetti al confine `Medium`.

4. **Importante — Il filtro configurato viene identificato cercando testo nel POM. Falso verde: sì; produce anche falsi rossi.**  
   Le verifiche con `contains` ([riga 280](quality/RapportiQualita.java:280)) accettano il percorso autorizzato dentro un commento mentre Maven usa `alternate.xml`, senza motivi. Il validatore controlla quindi un altro file. Viceversa, un commento innocuo contenente `excludeFilterFile` fa fallire una build sana.  
   **Schema:** ricerca di sottostringhe al posto della lettura della configurazione effettiva.  
   **Correzione richiesta:** risolvere il filtro realmente utilizzato da Maven mediante dati strutturati, ignorando i commenti; verificare quello stesso file. Conservare entrambe le controprove.

5. **Importante — Il controllo dei motivi ignora esclusioni valide diverse da `<Match>`. Falso verde: sì.**  
   Alla [riga 303](quality/RapportiQualita.java:303) vengono controllati soltanto figli diretti chiamati `Match`. SpotBugs accetta invece `<FindBugsFilter><Class name="~.*"/></FindBugsFilter>`: il difetto viene soppresso senza motivo e il validatore stampa «0 esclusioni, ciascuna con il motivo».  
   **Schema:** grammatica riconosciuta dal validatore più ristretta di quella accettata dallo strumento, con accettazione silenziosa del resto.  
   **Correzione richiesta:** verificare ogni forma di esclusione ammessa oppure respingere esplicitamente le strutture non supportate; aggiungere il caso senza `Match`.

6. **Minore — Modifica di un caso esistente oltre il perimetro letterale. Falso verde: no.**  
   `quality/regressioni-verify.sh` modifica `repackage-rimosso` ([riga 294](quality/regressioni-verify.sh:294)), mentre la specifica consente soltanto aggiunte di casi o adeguamenti dei conteggi. La modifica conserva la prova originaria: jar precedente presente, Maven riuscito, fallimento per assenza del nuovo jar eseguibile.  
   **Schema:** adeguamento funzionale dichiarato nella PR, ma non autorizzato dal vincolo della specifica.  
   **Correzione richiesta:** allineare esplicitamente il perimetro a questo adeguamento.

Le build `online` e `batch`, eseguite anche con `docker build --no-cache --progress=plain`, terminano con **0**. Confermano `docs/sviluppo.md`: agente JaCoCo e controllo sulle classi dei database girano su padre, `domain` e applicazione selezionata; SpotBugs e aggregato non girano con `package`.

Le versioni fissate coincidono con le ultime release dei metadati Maven Central: [JaCoCo 0.8.16](https://repo.maven.apache.org/maven2/org/jacoco/jacoco-maven-plugin/maven-metadata.xml), [plugin SpotBugs 4.10.5.0](https://repo.maven.apache.org/maven2/com/github/spotbugs/spotbugs-maven-plugin/maven-metadata.xml), [motore 4.10.5](https://repo.maven.apache.org/maven2/com/github/spotbugs/spotbugs/maven-metadata.xml). L’esecuzione su Java 21 è verificata nelle corse Docker.

Il diff non introduce affermazioni sul comportamento COBOL né attesi di parità. `legacy/` e il relativo gitlink sono invariati. Non ho rilevato segreti o percorsi host aggiunti; JDK, Maven e parser girano nei container.

Nessun commit o modifica residua ai file tracciati; resta soltanto `.validazione/`, già presente. Rimosse le quattro immagini e il volume `menb-val48-*`; nessun container o rete della validazione rimasto. [Riepilogo delle esecuzioni e della pulizia](file locale del Validatore, non conservato).