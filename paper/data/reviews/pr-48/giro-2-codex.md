BOCCIATA

Sul commit `44540ad` restano due falsi verdi riprodotti attraverso `./verify.sh`, entrambi ottenibili modificando POM versionati, senza falsificare rapporti.

Nella tabella, `C` indica `./quality/regressioni-copertura.sh`, eseguito selezionando i casi per nome.

| Rilievo precedente | Stato | Comando / controesempio | Esito |
|---|---|---|---|
| 1 — Provenienza JaCoCo | **Chiuso** | `C agente-scambio-online-domain agente-scambio-domain-loader` | Entrambi **1**: sessione del modulo sbagliato respinta. |
| 2 — Metadati ritoccati | **Limite documentato** | Lettura `docs/sviluppo.md:208` | Distingue correttamente rapporto precedente invariato e metadati falsificati intenzionalmente. Non riproposto né ritestato. |
| 3 — Configurazione SpotBugs | **Non chiuso** | `C spotbugs-soglia-high spotbugs-ambito-ristretto spotbugs-rilevatore-disattivato`; `./verify.sh` con `onlyAnalyze=package-info` | I controesempi originari ora terminano con **1**. Restano falsi verdi tramite proprietà del POM e profili variabili, descritti sotto. |
| 4 — Filtro alternativo / commento innocuo | **Chiuso** | `C esclusione-filtro-alternativo esclusione-commento-innocuo` | Filtro alternativo: **1**, percorso respinto. Commento innocuo: **0**. |
| 5 — `<Class>` senza motivo | **Chiuso** | `C esclusione-senza-match` | **1**, struttura `<Class>` esplicitamente respinta dopo `BUILD SUCCESS`. |
| 6 — Perimetro | **Chiuso per modifica di specifica** | Nessuna verifica dedicata | Come richiesto. |

I nuovi rilievi sono:

1. **Bloccante — Il confronto ignora proprietà del POM che configurano realmente SpotBugs.**  
   `controllaConfigurazioneSpotbugs()` confronta le sezioni `<configuration>`, ma non considera le proprietà di progetto usate per parametri assenti da quelle sezioni.

   Ho riprodotto questi risultati con `./verify.sh`:

   | Proprietà nel POM del modulo | Difetto presente | Esito |
   |---|---|---|
   | `spotbugs.onlyAnalyze=io.github.ltoscano.carddemo.online.package-info` | `EI_EXPOSE_REP` in `online` | **0, falso verde** |
   | `spotbugs.omitVisitors=FindNullDeref` | `NP_ALWAYS_NULL` in `domain` | **0, falso verde** |
   | `spotbugs.maxRank=1` | `EI_EXPOSE_REP` in `online` | **0, falso verde** |

   Il validatore stampa configurazione conforme e zero difetti. [Esecuzioni e risultati](file locale del Validatore, non conservato), [log `onlyAnalyze`](file locale del Validatore, non conservato).

   **Correzione richiesta:** verificare anche i parametri applicati attraverso proprietà del progetto, oppure vietare esplicitamente le proprietà che possono indebolire parametri non fissati; aggiungere queste regressioni.  
   **Falso verde: sì. Richiede modifiche versionate:** POM e classe difettosa. **Falsificazione di artefatti generati: no.**

2. **Bloccante — Il POM effettivo successivo alla build può descrivere un’altra configurazione.**  
   In `online` ho aggiunto un profilo con attivazione:

   ```xml
   <activation>
     <file><missing>${basedir}/target/spotbugsXml.xml</missing></file>
   </activation>
   ```

   Il profilo imposta `threshold=High`; la classe di prova contiene il difetto Medium. Dopo la pulizia, `mvn verify` attiva il profilo e produce il rapporto senza segnalare il difetto. Alla successiva invocazione di `effective-pom`, il rapporto esiste: il profilo è disattivato, il controllo legge `Medium` e `./verify.sh` termina con **0**.

   [POM della prova](file locale del Validatore, non conservato), [log completo](file locale del Validatore, non conservato).

   **Correzione richiesta:** acquisire e verificare il modello effettivamente usato dall’invocazione che esegue la build, senza ricostruirlo soltanto dopo che il filesystem è cambiato; aggiungere questa regressione.  
   **Falso verde: sì. Richiede modifiche versionate:** POM e classe difettosa. **Falsificazione di artefatti generati: no.**

Le altre prove sul diff di correzione hanno dato questi esiti:

| Prova attraverso `./verify.sh` | Esito |
|---|---|
| POM effettivo mancante, vuoto, troncato, precedente invariato, del solo altro modulo | **1** ciascuno, per il motivo previsto |
| Generazione del POM effettivo fallita | **1**, errore controllato |
| Profilo attivo per default con soglia High; `pluginManagement` del modulo; seconda esecuzione; `skip` nell’esecuzione | **1** ciascuno |
| Proprietà POM `spotbugs.threshold=High` | **1**, difetto Medium segnalato: prevale la configurazione esplicita |
| Sessione `<corsa>:carddemo-online-extra` | **1**: uguaglianza esatta, sia nell’`exec` sia nell’aggregato |
| `.mvn/maven.config`; `.mvn/jvm.config` | **1** ciascuno, presenza esplicitamente vietata |

`./verify.sh`, `./smoke.sh`, `./quality/regressioni-verify.sh` e `./quality/regressioni-regole.sh` sono tutti terminati con **0**.

Ho eseguito **gli 11 casi nuovi e tre vecchi**, senza eseguire l’intera suite di copertura: **0 complessivo**, 15 esiti includendo la base, **2081 secondi**. I vecchi scelti sono `rapporto-troncato`, `esclusione-con-motivo` e `cancello-controllo-spotbugs-rimosso`. Ogni esito corrisponde al motivo dichiarato; nessun errore estraneo di compilazione, download o timeout. Il cancello rimosso lascia `verify.sh` a 0 ed è rilevato dalla completezza. `--lista` riesce; un nome sconosciuto termina con **1** dopo una base verde. [Riepilogo completo](file locale del Validatore, non conservato).

Il confronto `git diff --name-only origin/main...HEAD` contiene **18 file, tutti ammessi** dal perimetro aggiornato. Con `gh` ho verificato sullo SHA attuale sei check completati con **success**: due ciascuno per `verify`, `smoke` e `analysis-check`. [Stato acquisito](file locale del Validatore, non conservato).

Nessuna correzione o commit. File tracciati invariati; resta soltanto `.validazione/`, già presente. Risorse Docker proprie rimosse; nessun residuo nelle 43 corse controllate. Immagini e volumi condivisi preservati.