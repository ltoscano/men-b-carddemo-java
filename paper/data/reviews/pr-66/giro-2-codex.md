**BOCCIATA**

I cinque rilievi originari sono chiusi. Restano due difetti nelle modifiche di correzione, descritti sotto. Comandi, mutazioni e log sono raccolti nelle [evidenze complete](/tmp/menb-val66b-evidence/LEGGIMI.md).

| Rilievo del primo giro | Stato | Comando / prova eseguita | Esito |
|---|---|---|---|
| 1. Tracciato dipendente dal modello dei test | **Chiuso** | `python3 mutations.py`, `python3 mutations-length.py` nelle copie isolate | Offset 48/58 scambiati: **1**. Scambio anche nei valori manuali: **1**. Lunghezze compensate nel caricatore e nel modello: **1**. Entrambi i confronti leggono direttamente il TSV e falliscono. |
| 2. Caricamenti concorrenti | **Chiuso** | `CaricamentoConcorrenteTest` e `DataChecks.java` contro PostgreSQL reale | Due file distinti di **un conto**: uno riesce, l’altro rifiuta; resta una riga. Stesso file: uno scrive, l’altro restituisce “già caricato”. Anche il confronto su tabella piena è protetto dal blocco. Resta il nuovo problema di durata sotto indicato. |
| 3. Scala nascosta dall’arrotondamento PostgreSQL | **Chiuso** | `python3 mutations.py`, `python3 mutations-extra.py` | `+0.001` e `setScale(3)` sugli importi: **1**, sul parametro effettivamente consegnato al driver. Scala 3 prima del controllo: rifiuto del caricatore. Il controllo comprende anche la chiave. |
| 4. Bytecode del caricatore non ispezionato | **Chiuso** | Mutazioni `math-pow`, `longValue`, `int-dopo-exact` | Tutte **1**: rilevati rispettivamente virgola mobile, conversione con perdita e `L2I`. |
| 5. Dipendenza di `batch` dal caricatore | **Chiuso** | `./smoke.sh`; `python3 batch-solo.py`; smoke senza dipendenze | Secondo `up` e `run batch` riusciti. Anche `batch` da solo su progetto vuoto riesce e lascia **50 conti**. Dipendenza rimossa: smoke **1** in `batch-3`. |

La riesecuzione identica conserva righe e `xmin`. Righe aggiunte/tolte, differenze in ciascuna delle dodici colonne, spazio finale diverso, file vuoto su tabella piena e file diverso vengono rifiutati senza scritture; file vuoto su tabella vuota accettato.

La ricomposizione **runtime riusa `CampoConto`**: con gli offset 48/58 invertiti, primo caricamento e riesecuzione riescono pur avendo date invertite. Il nuovo confronto TSV rende però questa mutazione rossa: **non supera più la validazione completa**. [Prova osservata](/tmp/menb-val66b-evidence/common-check.log).

Per osservare una differenza esclusivamente di scala nella tabella ho dovuto alterare la colonna a `NUMERIC(13,3)`: in quel caso la riesecuzione restituisce successo. Con il DDL contrattuale `NUMERIC(12,2)` quello stato non è rappresentabile. Non lo conteggio come difetto sullo schema prescritto.

| Comando di accettazione, una invocazione ciascuno | Esito |
|---|---|
| `./verify.sh` | **0** |
| `./smoke.sh` | **0** |
| `./quality/regressioni-verify.sh` | **0**, 9 casi |
| `./quality/regressioni-regole.sh` | **0**, 44 casi |
| `./quality/regressioni-copertura.sh controprova-lecita` | **0**, base e controprova |

Conteggi locali identici alla [CI sullo SHA `8a52d3f`](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46119251674): **domain 399, loader/online/batch 1 ciascuno, parity 44**, nessun salto. Tutti gli otto controlli CI sono verdi.

Le nove mutazioni smoke sono rosse. Su `online`, Flyway spento e starter mancante falliscono in `migrazione`; `skip-executing-migrations=true` fallisce in **`online-primo`**. Nessun esito perso o attesa senza limite rilevato nelle righe smoke aggiunte.

Rilievi nuovi:

1. **Importante — il nuovo blocco può attendere indefinitamente.**  
   In `CaricatoreConti.java:99–100`, il `LOCK` non ha un limite. Una transazione esterna con `UPDATE` non confermato mantiene bloccata anche la riesecuzione identica. Ho osservato `lock_timeout=0`, `statement_timeout=0` e `idle_in_transaction_session_timeout=0`; il caricatore termina soltanto dopo il rilascio manuale. I limiti dei test e dello smoke non configurano il caricatore ordinario. [Evidenza](/tmp/menb-val66b-evidence/data-checks.log).  
   **Correzione richiesta:** limite finito sul blocco, rollback e diagnosi alla scadenza, con prova che mantenga aperta la transazione detentrice. **Modifica versionata: sì. Dati infedeli o successo ingannevole dimostrati: no; avvio potenzialmente bloccato senza termine: sì.**

2. **Minore — “prima differenza” non rispetta l’ordine dichiarato.**  
   Eliminando il conto **1** e alterando il conto **50**, viene segnalato il conto 50. Le chiavi mancanti sono controllate soltanto dopo la scansione della tabella (`CaricatoreConti.java:235–267`). [Evidenza](/tmp/menb-val66b-evidence/data-checks.log).  
   **Correzione richiesta:** confrontare insieme le sequenze ordinate, rilevando una chiave mancante prima di differenze successive. **Modifica versionata: sì. Dati infedeli: no. Falso verde: no; rifiuto corretto, diagnosi fuori ordine.**

Diff interamente letto e nel perimetro. I due POM sono necessari al riuso tramite `test-jar`: nessun profilo o proprietà aggiunta, dipendenza di test ammessa; nessun artefatto di test nelle immagini finali.

Nessuna modifica versionata, commit, push o workflow avviato. Stato iniziale conservato: soltanto `.validazione/` non tracciata. Tutte le risorse Docker proprie rimosse; risorse condivise conservate.