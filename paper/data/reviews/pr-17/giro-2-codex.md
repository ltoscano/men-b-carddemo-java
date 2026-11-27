BOCCIATA

Revisionato lo SHA `9cecf041d734feca2212632a72c56d0eaaa82a7e`. Ho eseguito le prove; la CI è invece **letta dal rapporto fornito**, non rieseguita da me.

Timeout esterni: 600 s per la prima verifica, 150 s per ciascuna mutazione, 180 s per `dependency:tree`. Nelle prove negative: `MENB_HEALTH_TIMEOUT=8`, `MENB_BATCH_TIMEOUT=5`. Le durate comprendono build e pulizia.

| Criterio di accettazione | Comando eseguito da me | Esito osservato |
|---|---|---|
| Clone pulito, verifica positiva | `./verify.sh` | **0 in 29,447 s**; cinque moduli compilati, online sano, batch terminato con 0. Log (log locale del Validatore, non conservato) |
| Un test rotto deve fallire | `./verify.sh`, dopo inserimento di `fail(...)` nel test del loader | **1 in 2,112 s**, `BUILD FAILURE`. Log (log locale del Validatore, non conservato) |
| Dipendenze tra moduli conformi | `mvn -B dependency:tree`, nel container Maven | **0**. Domain senza dipendenze interne; loader/online/batch dipendono soltanto da domain; parity da tutti, senza classificatore `exec`. Albero completo (log locale del Validatore, non conservato) |
| Rifiuto delle applicazioni guaste | `./verify.sh` con le mutazioni descritte sotto | DOWN respinto; connessione senza risposta limitata; batch con `System.exit(7)` respinto: **1 in 7,653 s**. Resta però il falso verde con jar residuo. |
| Workflow presente e CI verde | `cat .github/workflows/ci.yml .validazione/ci.txt` | Workflow presente: push, PR, submodule ricorsivi, `./verify.sh`. Il rapporto fornito contiene due `pass`, 36/38 s; **evidenza letta**. |
| Diff entro il perimetro | `git diff --stat origin/main...HEAD` e `git diff --name-only origin/main...HEAD` | **21 file, 529 inserzioni**, tutti ammessi. Il patch fornito coincide con il diff Git. Evidenza (log locale del Validatore, non conservato) |

Il comando completo eseguito per le dipendenze è:

```sh
docker run --rm --name menb-val17-dependency-tree \
  -v "$MENB_BUILD_CACHE_VOLUME":/root/.m2 \
  -v "$PWD":/workspace -w /workspace \
  maven:3.9.16-eclipse-temurin-21 mvn -B dependency:tree
```

Ho inoltre verificato:

- **Versioni:** Maven 3.9.16 e Java 21 effettivi nel container; Boot fissato a 4.2.0; Batch 6.1.0 gestito da Boot. La richiesta `curl` a [Maven Central](https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-starter-parent/maven-metadata.xml) restituisce `release=4.2.0`. Output (log locale del Validatore, non conservato)
- **Database e dominio:** dalla lettura dei sorgenti e dall’albero completo non risultano database incorporati, classi di dominio o logica di business. Le sole classi applicative sono i due avviatori.
- **Artefatti:** ispezionati i quattro jar dopo il ripristino. Gli eseguibili hanno `JarLauncher` e `BOOT-INF`; gli ordinari espongono le classi alla radice. Manifest ed elenco (log locale del Validatore, non conservato)

| Rilievo del primo giro | Stato | Prova eseguita |
|---|---|---|
| **1 — Jar residuo** | **Non chiuso** | Con jar precedente e `repackage` rimosso: correttamente **1 in 5,711 s**. Ma facendo fallire realmente la cancellazione del vecchio jar, la stessa build senza `repackage` termina con **0 in 7,238 s** e avvia il residuo. |
| **2 — Salute per sottostringa** | **Chiuso** | Server HTTP che restituisce **200**, radice `DOWN` e componente `UP`: **1 in 14,881 s**. Log della risposta (log locale del Validatore, non conservato) |
| **3 — Attese e arresti bloccati** | **Non chiuso** | Connessioni accettate senza risposta: **1 in 15,693 s**. Batch che ignora TERM: SIGKILL, codice interno 137, verifica **1 in 31,820 s**. Online che ignora TERM: SIGKILL ma verifica **0 in 17,316 s**. |
| **4 — Proprietà e errori di pulizia** | **Chiuso** | Su volume Linux, sorgenti e sentinelle `.git`/`legacy` restano `4242:4243`; gli output diventano `501:20`. Con `--cap-drop=CHOWN`, errori reali visibili e verifica **1 in 14,342 s**. Proprietà (log locale del Validatore, non conservato), fallimento (log locale del Validatore, non conservato) |

1. **Importante — La nuova pulizia ignora il proprio fallimento e riapre il rilievo 1.**  
   **Evidenza eseguita:** in un volume Linux ho conservato un eseguibile sano, rimosso il `repackage` e assegnato al solo `target` online modalità `1777`, proprietario `1000:1000`. Eseguendo il container senza `CAP_FOWNER`, `rm` non può cancellare il residuo. Non ho simulato il comando:
   
   ```text
   rm: cannot remove '…-exec.jar': Operation not permitted
   BUILD SUCCESS
   online sano (stato radice UP)
   == verifica completata
   ```
   
   Risultato: **0**. Il jar conserva esattamente lo stesso SHA-256 prima e dopo. Dentro il container `set -uo pipefail` non abilita `errexit`, e `verify.sh:74` non controlla l’esito di `rm`.  
   **Correzione richiesta:** interrompere esplicitamente la verifica se la cancellazione fallisce, prima di Maven. Ripetere questo controesempio. Preparazione (log locale del Validatore, non conservato), verifica (log locale del Validatore, non conservato), hash finale (log locale del Validatore, non conservato).

2. **Importante — L’errore di arresto online viene deliberatamente perso.**  
   **Evidenza eseguita:** online sano che ignora SIGTERM produce l’avviso di arresto forzato, poi la verifica termina con **0**. `stop_proc` restituisce 1, ma la chiamata a `verify.sh:113` non ne propaga l’esito. Log (log locale del Validatore, non conservato).  
   **Giudizio:** il SIGKILL risolve il blocco temporale. La specifica iniziale richiede esplicitamente la salute, non un arresto pulito; tuttavia il rilievo 3 **accolto** chiedeva un errore anche per l’arresto bloccato. Trattarlo unilateralmente come avviso non chiude quella richiesta.  
   **Correzione richiesta:** mantenere l’arresto forzato per liberare le risorse, ma propagare un codice finale nonzero quando è necessario.

Le mutazioni sono state ripristinate con `git checkout`, usando un indice temporaneo perché `.git` è protetto in scrittura. Verifica finale positiva: **0 in 13,171 s**; nessuna modifica tracciata residua. Rimossi container, volume delle prove e cache dedicata. Nessun commit o push. Il rilievo 6 non è stato valutato.