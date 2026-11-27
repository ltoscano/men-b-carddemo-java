## Obiettivo

Aggiungere a `./verify.sh` due cancelli sul codice Java: il rapporto di copertura dei test (JaCoCo) e l'analisi statica dei difetti (SpotBugs). Oggi il codice è quasi vuoto: si fissano gli strumenti e i loro controlli prima che arrivi la logica di business.

Classe di rischio: **piena** (script di verifica e POM). Validazione con Codex.

## Dipendenze e perimetro

- Dipende da: #26 (mergiata).
- File ammessi: `pom.xml`, `carddemo-*/pom.xml`, `verify.sh`, `quality/**` (nuovi file per questi controlli; `quality/regressioni-verify.sh` e `quality/regressioni-regole.sh` solo per aggiungere casi o adeguare conteggi), `docs/sviluppo.md`, `docker/app.Dockerfile` e `.dockerignore` (solo se i nuovi plugin, girando nella build delle immagini, richiedono file nel contesto).
- Fuori ambito: soglie di copertura (nessuna finché non c'è codice di business); SonarQube (#28); arresto dei processi figli allo scadere dei limiti di tempo (#34); codice di produzione, salvo che SpotBugs segnali un difetto reale nell'esistente (in quel caso: correzione minima, dichiarata).

## Specifica

Versioni dei plugin fissate nel POM padre; se Spring Boot 4.2.0 le gestisce si usa la sua, altrimenti l'ultima stabile su Maven Central, dichiarata in `docs/sviluppo.md`. Tutto gira nel ciclo ordinario (`mvn -B verify`, cioè `./verify.sh`), in container.

### JaCoCo

- Agente attivo sui test di tutti i moduli; **rapporto aggregato** XML prodotto dal modulo `carddemo-parity` (che dipende da tutti), in una fase e in un percorso fissati e documentati.
- `./verify.sh` controlla il rapporto con un programma che usa un parser XML (sul modello di `quality/RapportoSurefire.java`, non con `grep`): è ben formato e completo; è **di questa corsa** (legato all'identificativo di corsa già usato per il rapporto dei test, o con un mezzo equivalente dichiarato); contiene una voce per ogni modulo con classi eseguibili; contiene dati di esecuzione (almeno una classe con righe coperte).
- Un modulo senza codice eseguibile (oggi `domain` e `loader` contengono solo `package-info.java`) è un'assenza **legittima** e va distinta da un rapporto vuoto per errore: l'elenco dei moduli attesi con e senza classi si ricava dal contenuto dei moduli in quella corsa, non da un elenco scritto a mano che invecchia.
- Nessuna soglia di copertura.

### SpotBugs

- Eseguito su `domain`, `loader`, `online`, `batch` (codice di produzione); soglia di gravità e livello di sforzo fissati e motivati in `docs/sviluppo.md`; un file di esclusioni è ammesso solo con una riga di motivo per ogni esclusione (oggi dovrebbe essere vuoto o assente).
- Un difetto alla soglia scelta fa fallire `./verify.sh`.

### Rapporto con la build delle immagini

Dichiarare in `docs/sviluppo.md` quali dei due controlli girano anche nella build delle immagini e quali no, e perché (precedente: voci 46 e 52 del registro). `./smoke.sh` deve restare verde.

### Regressioni (in `quality/`, sul modello di `quality/regressioni-regole.sh`)

Corsa di base verde, poi mutazioni isolate con ripristino anche su interruzione, ciascuna deve fallire **per il motivo dichiarato** (non per compilazione, download o limite di tempo):
1. rapporto JaCoCo assente; troncato; ben formato ma rimasto da una corsa precedente; senza dati di esecuzione; privo della voce di un modulo che ha classi;
2. agente JaCoCo disattivato in un modulo (il rapporto perde i dati di quel modulo);
3. una classe con un difetto che SpotBugs segnala alla soglia scelta, in ciascuno dei quattro moduli (almeno due categorie diverse di difetto);
4. SpotBugs disattivato in un modulo o rimosso dal POM padre; controllo del rapporto rimosso da `verify.sh`;
5. controprova lecita: una classe nuova senza difetti e con un test non fa fallire nulla.

## Criteri di accettazione

- [ ] `./verify.sh` termina con 0 e il suo output mostra l'esecuzione di JaCoCo (rapporto aggregato) e di SpotBugs su quattro moduli.
- [ ] Il comando delle regressioni termina con 0, con ogni caso riportato con nome, codice di uscita e motivo; working tree pulito alla fine.
- [ ] `./quality/regressioni-verify.sh` e `./quality/regressioni-regole.sh` restano verdi (se i loro conteggi vanno adeguati, la modifica è dichiarata).
- [ ] `./smoke.sh` termina con 0.
- [ ] `git diff --name-only origin/main...HEAD` elenca solo file ammessi.
- [ ] CI verde.

## Strategia di rollback

Revert del commit di merge.

## Limiti per l'agente

- Negli script ogni comando ha l'esito controllato; limite di tempo sui comandi che possono restare in attesa (Docker, Maven, rete); nessun residuo di una corsa precedente può soddisfare un controllo.
- Docker condiviso: risorse con prefisso proprio, nessun comando globale.
- Autocontrollo prima della PR come da `paper/data/prompts/esecutore.md`. File temporanei con prefisso `issue27-`. Non mergiare.
