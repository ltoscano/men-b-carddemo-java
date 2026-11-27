BOCCIATA

Sul commit `9516c47`, il diff tocca 16 file, tutti ammessi. Ho però riprodotto **un falso verde bloccante** nel controllo della pulizia.

**R1 — `smoke.sh:105`: fallimento ignorato nell’elenco delle risorse. Falso verde: sì.**  
La pipeline `printf … | sed …` non propaga esplicitamente l’errore. La funzione viene chiamata dentro condizioni che disabilitano l’effetto di `set -e`; le iterazioni successive possono quindi restituire successo.

Prova: ho creato un container arrestato con l’etichetta del progetto e iniettato tramite `PATH` un `sed` che consuma l’input ed esce con **42** durante la formattazione dei container. Senza modificare `smoke.sh`, ho ottenuto:

```text
VALIDATORE: sed fallisce nella formattazione dei container (42)
== [pulizia] nessun container, rete o volume con l'etichetta …
== SMOKE RIUSCITO
```

Lo smoke restituisce **0**, ma `docker ps -a` trova ancora il container etichettato. Riprodotto due volte, in **10,42 s** e **9,97 s**. Fixture poi rimossa manualmente. Il difetto è in [smoke.sh](smoke.sh:105).

| Prova eseguita | Codice reale | Durata | Esito |
|---|---:|---:|---|
| `./verify.sh`, prima corsa | 0 | 35,45 s | Passa |
| `./smoke.sh`, prima corsa | 0 | 11,18 s | Passa, nessun residuo |
| Verify: test rotto | 1 | 3,96 s | Rilevato |
| Verify: `repackage` rimosso, jar residuo presente | 1 | 5,74 s | Rilevato dopo pulizia |
| Verify: cancellazione impedita con `chflags uchg` | 1 | 0,28 s | Rilevata prima di Maven |
| Smoke: DB mai sano | 1 | 26,80 s | Rilevato |
| Smoke: radice `DOWN`, HTTP 200 | 1 | 13,87 s | Rilevato |
| Smoke: DB irraggiungibile da online | 1 | 28,10 s | Rilevato |
| Smoke: job fallito, runner con codice 5 | 1 | 15,02 s | Rilevato |
| Smoke: job disabilitato, runner con codice 0 | 1 | 7,69 s | Rilevato |
| Smoke: `down` fallisce | 1 | 9,68 s | Rilevato; rimozione di riserva riuscita |
| Extra: esecuzione già presente prima di `batch-0` | 1 | 8,62 s | Rilevata |
| Extra: secondo runner esce 0, resta una sola esecuzione | 1 | 8,27 s | Rilevato |
| Extra: job `COMPLETED`, step `FAILED` | 1 | 8,29 s | Rilevato |
| Extra: due esecuzioni sulla stessa istanza | 1 | 10,09 s | Rilevato |
| Extra: job `COMPLETED`, exit code `NOT_COMPLETED` | 1 | 8,38 s | Rilevato |
| Extra: errore di `sed`, container residuo | **0** | **10,42 / 9,97 s** | **Falso verde** |
| `mvn -B dependency:tree` in container | 0 | 9,72 s | Nessun DB incorporato |
| Stack ordinario: `compose up -d --wait` | 0 | 4,50 s | Sano |
| Smoke con stack ordinario attivo | 0 | 9,65 s | Stack ordinario intatto |
| Stack ordinario: `down -v` | 0 | 0,43 s | Pulito |
| Verify finale, sorgenti ripristinati | 0 | 6,70 s | Passa |

Tutte le prove negative richieste terminano senza residui del progetto. L’eccezione è il controesempio R1, ripulito da me. Ho usato timeout esterni per le corse e i comandi Docker; nelle prove negative di smoke, il limite di avvio era ridotto a 25 secondi.

La lettura riga per riga conferma che `verify.sh` non avvia jar o servizi applicativi. I controlli dello smoke leggono il JSON e confrontano esattamente gli stati; verificano conteggio, istanze e step delle esecuzioni. R1 resta il fallimento ignorato dimostrato.

Gli altri vincoli risultano rispettati:

- Basi delle immagini applicative fissate per tag e digest; PostgreSQL e curl anch’essi fissati.
- Entrambe le immagini restituiscono UID/GID **10001**; osservato anche il processo Java batch con UID 10001.
- Due test di contesto eseguiti, verdi, **Skipped: 0**.
- Nessuna dipendenza H2, HSQLDB o Derby; nessun segreto reale rilevato.
- Solo `installationCheckJob`; nel database solo le sei tabelle Batch, con esecuzioni **1/1** e **2/2**, entrambe `COMPLETED`, step compresi.
- Stack ordinario invariato prima/dopo lo smoke: stessi container, porta, rete, volume, salute e metadati.
- `ci.txt` fornito riporta `verify` e `smoke` verdi.

**Ciò che manca rispetto alla specifica:** la garanzia che lo smoke fallisca quando un comando rilevante fallisce e che non dichiari assenti risorse ancora presenti. R1 viola entrambe e può far risultare verde un lavoro sbagliato. Nessun altro scostamento dimostrato.

Sorgenti ripristinati, nessun commit o push. Risorse delle prove rimosse. [Log, harness e durate] (log locali del Validatore, non conservati).