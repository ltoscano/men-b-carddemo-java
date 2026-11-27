BOCCIATA

Valutazione in sola lettura, senza eseguire Docker. I controesempi sotto derivano dall’analisi del codice; il log fornito documenta soltanto il percorso positivo.

| Criterio di accettazione | Stato | Evidenza |
|---|---|---|
| Clone pulito, solo Docker: `./verify.sh` termina con 0 | **dimostrato** | Il log terzo mostra cinque moduli `SUCCESS`, salute `UP`, batch terminato con 0 e completamento: `.validazione/verify-clone-pulito.log:1242–1259`. Lo script non invoca Java o Maven sull’host. |
| Un test rotto provoca esito diverso da 0 | **solo dichiarato** | Prova su `LoaderModuleTest` descritta in `.validazione/descrizione-pr.md:11`, senza relativo log. Il codice propaga correttamente il fallimento Maven: `verify.sh:33`. |
| `dependency:tree` mostra il grafo ammesso | **solo dichiarato** | Esecuzione riportata in `.validazione/descrizione-pr.md:12–15`, senza output allegato. Il grafo dichiarato nei cinque POM rispetta comunque la tabella. |
| Verifica fallita se online non è sano oppure batch esce con codice nonzero | **non soddisfatto** | Le due prove dell’Esecutore sono dichiarate a `.validazione/descrizione-pr.md:16–19`. Restano selezione di artefatti residui, controllo della salute incompleto e attese non realmente limitate: rilievi 1–3. |
| Workflow presente e CI della PR verde | **solo dichiarato** | Presenza, eventi, submodule e comando sono dimostrati da `.github/workflows/ci.yml:3–15`. Il verde è riportato soltanto nella descrizione, righe 40–41; il log locale non dimostra l’esito CI. |
| Diff limitato al perimetro | **dimostrato** | `git diff --stat origin/main...HEAD`: 21 file, 478 inserzioni, tutti ammessi. Nessuna modifica a `README.md`, `CLAUDE.md` o alle cartelle escluse. |

Le coordinate, Java 21, Boot fissato a `4.2.0`, assenza di sovrascritture Spring e separazione fra jar ordinari ed eseguibili risultano dai POM. Il log conferma il `repackage` con classificatore `exec` per entrambe le applicazioni. Non emergono classi di dominio, logica applicativa, database incorporati, dipendenze dirette non ammesse, segreti o percorsi locali nel diff. La cache predefinita è un volume Docker. Che Boot `4.2.0` fosse **l’ultima GA** alla data indicata resta un’affermazione documentata dall’Esecutore in `docs/sviluppo.md:23`, non verificabile indipendentemente con il materiale fornito.

1. **Importante — Può verificare un jar residuo invece di quello appena prodotto.**  
   **Evidenza:** [verify.sh:33](verify.sh:33), righe 36 e 64. La build non pulisce `target/`; entrambi gli artefatti sono scelti mediante `ls …/*-exec.jar | head -n 1`. Dopo un cambio di versione può essere selezionato il vecchio jar. Anche eliminando erroneamente il `repackage`, un eseguibile precedente rimane disponibile e può far passare la verifica. Il log da clone pulito non esercita questi casi.  
   **Correzione richiesta:** eliminare gli output precedenti prima della build, mantenendo `mvn -B verify`, e selezionare univocamente l’artefatto atteso. Verificare che un vecchio jar sano non possa coprire una build corrente guasta. Il problema riguarda anche gli artefatti che #14 containerizzerà.

2. **Importante — Il controllo della salute cerca una sottostringa, non lo stato complessivo.**  
   **Evidenza:** [verify.sh:47](verify.sh:47). Una risposta HTTP 200 come `{"status":"DOWN","components":{"diskSpace":{"status":"UP"}}}` soddisfa il `grep`. Non basta quindi dimostrare che la rimozione dell’endpoint produca un errore. Questo controesempio presuppone HTTP 200; un normale HTTP 503 viene invece respinto da `curl -f`.  
   **Correzione richiesta:** validare il JSON e richiedere esattamente `status == "UP"` alla radice, usando strumenti nel container. Aggiungere una prova negativa con stato complessivo non sano e componente `UP`, rilevante soprattutto quando #14 aggiungerà altri indicatori.

3. **Bloccante — Il limite temporale della verifica non è garantito.**  
   **Evidenza:** [verify.sh:41](verify.sh:41), righe 47, 58–60 e 66. Il ciclo limita le iterazioni, ma `curl` non ha timeout: una connessione accettata senza risposta può bloccare la prima richiesta indefinitamente. Anche il secondo `curl` e `wait` non hanno limite. `timeout 120` sul batch non impone una successiva uccisione forzata se il processo non termina dopo `SIGTERM`.  
   **Correzione richiesta:** applicare una scadenza complessiva al controllo online, timeout alle singole richieste e arresto forzato dopo un intervallo limitato per entrambi i processi. Provare endpoint bloccato e arresto bloccato: la verifica deve terminare con errore.

4. **Importante — La pulizia cambia proprietario all’intero repository e nasconde gli errori.**  
   **Evidenza:** [verify.sh:25](verify.sh:25), righe 25–30. `chown -R … /workspace` comprende `.git`, sorgenti e submodule `legacy`, benché il commento parli soltanto dei file creati. Gli errori sono soppressi e il `true` permette un esito positivo anche quando gli artefatti restano di root, contrariamente a `docs/sviluppo.md:12`.  
   **Correzione richiesta:** limitare la restituzione della proprietà agli output generati e rendere visibili gli errori; preservare l’eventuale fallimento precedente. Il `true` del trap **non annulla** gli `exit 1` espliciti di Maven o batch: non attribuisco allo script quel difetto.

5. **Importante — Mancano evidenze verificabili per completare l’accettazione.**  
   **Evidenza:** `.validazione/descrizione-pr.md:11–20,40–41`; il log terzo contiene soltanto l’esecuzione positiva. Non dimostra le mutazioni negative, l’output di `dependency:tree` o il verde CI sul commit esaminato. Ciò non dimostra che quelle esecuzioni siano fallite.  
   **Correzione richiesta:** rendere disponibili nella PR gli output delle prove negative con codici di uscita, l’albero delle dipendenze e un risultato CI associato allo SHA revisionato. Dopo le correzioni, ripetere anche i controesempi dei rilievi 1–3.

6. **Importante — Rischio per #15: il container attuale non dispone di accesso a Docker per Testcontainers.**  
   **Evidenza:** [verify.sh:15](verify.sh:15), righe 15–22: nessun socket o endpoint Docker configurato. Inoltre i test attuali controllano contesti e visibilità delle classi, senza imporre i confini architetturali.  
   **Correzione richiesta nella #15:** predisporre esplicitamente l’accesso al daemon necessario ai test e introdurre i controlli dei confini mantenendo `./verify.sh` come ingresso unico. Non è richiesta l’introduzione anticipata di Testcontainers o ArchUnit in questa PR.