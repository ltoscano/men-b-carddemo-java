# MEN-B — Make Everything Now, Brownfield

Contesto di riferimento per ogni sessione agentica in questo progetto. Lingua di lavoro: italiano.

## Obiettivo

Scrivere un paper per **Zenodo** che **insegni a persone** come modernizzare, realisticamente e concretamente, un sistema legacy con gli agenti: in modo **replicabile, chiaro e reale**. Il caso è una migrazione brownfield **COBOL → Java**, con **tempi misurati** e approccio. Il paper non descrive un metodo in astratto: riporta ciò che è stato effettivamente eseguito, su un repository GitHub reale, con issue, PR e log verificabili.

Il lettore è un professionista (sviluppatore, architetto, responsabile tecnico) che lunedì deve poter rifare lo stesso percorso sul proprio sistema. Ogni scelta di lavoro si giudica con questa domanda: *un lettore saprebbe rifarlo, e saprebbe perché?*

- Oggetto migrato: **AWS CardDemo** (`legacy/aws-mainframe-modernization-carddemo/`, commit `59cc6c2`, Apache-2.0).
- Target: **Java 21 + Spring Boot + Spring Batch + PostgreSQL + Docker Compose**, consegnato come **applicazione containerizzata funzionante** (`docker compose up` da clone pulito).
- Si procede **per passi**: ogni passo si chiude con un risultato verificabile e una decisione umana prima del successivo.

## Fonti (leggere prima di pianificare)

| File | Cosa contiene |
| --- | --- |
| `paper/articolo-metodo-greenfield-brownfield.md` | Il metodo: issue come coda di specifiche, ruoli, Fase 0, template di issue, cinque regole |
| `paper/piano-migrazione-carddemo-java.md` | Inventario verificato di CardDemo, architettura target, piano a ondate (Wave 0–4), due issue di esempio, quattro rischi COBOL→Java |
| `paper/mec-b-paper.md` | **Il paper in scrittura** (deliverable, vedi sotto) |

## Layout

```
legacy/aws-mainframe-modernization-carddemo/   sorgente COBOL — submodule fissato a 59cc6c2, SOLA LETTURA, mai modificare, mai aprire issue/PR upstream
paper/                                         metodo, piano, paper, dati e figure
paper/data/                                    misure grezze (CSV/JSON) da cui derivano tabelle e grafici
paper/figures/                                 grafici generati da paper/data/
repo GitHub: ltoscano/men-b-carddemo-java (pubblico) — codice migrato, issue, PR e paper nello stesso repository
```

Baseline misurata (27 nov 2026): `app/cbl` 31 programmi / 20.650 righe; 44 `.cbl` / 30.175 righe contando i tre moduli opzionali; `app/cpy` 30 copybook / 2.786 righe; 17 mappe BMS / 4.472 righe; 38 JCL / 2.429 righe.

## Il metodo in breve

Migrazione **ibrida**: il comportamento da preservare è brownfield, lo stack target è greenfield. Quindi due Fasi 0, in sequenza, prima di qualsiasi logica di business:

1. **Wave 0A (brownfield, sola lettura):** inventario, grafo `COPY`/`CALL`/`EXEC PGM=`, contratto dati campo per campo, golden fixture e oracle.
2. **Wave 0B (greenfield):** scheletro Java, Compose, moduli vuoti (`carddemo-domain`, `-loader`, `-online`, `-batch`, `-parity`), CI verde.
3. **Wave 1** schema e loader → **Wave 2** online `CO*` ∥ **Wave 3** batch `CB*` → **Wave 4** moduli opzionali e parità end-to-end.

### Ruoli e modelli

| Ruolo | Chi | Compito |
| --- | --- | --- |
| Pianificatore / Selettore | **Fable** (sessione principale) | Scrive le issue, verifica dipendenze e non-sovrapposizione di cartelle/tabelle, apre il worktree, lancia l'Esecutore. Non implementa. |
| Esecutore | subagent **Opus** (issue complesse: aritmetica, COMMAREA, batch) o **Sonnet** (issue meccaniche: DTO, schema, loader, boilerplate) | Una sola issue, in worktree isolato. Implementa, testa, apre PR con `Closes #N`. |
| Validatore adversarial | **Codex CLI** (`codex exec` / `codex review`), contesto pulito | Legge solo specifica, diff e test. Mandato: falsificare. Max due giri, poi scala. |
| Gate umano | l'utente | Unico a decidere il merge. |

Il Validatore è deliberatamente un modello di un altro fornitore: non condivide contesto né bias dell'Esecutore. Il suo output va riportato per intero nella PR, comprese le obiezioni respinte e il motivo.

### Coda di issue

Etichette: `bootstrap`, `ready`, `in-progress`, `in-review`, `blocked`, `needs-spec-update`, più `wave-0`…`wave-4`.

Ogni issue ha: Obiettivo · Dipendenze e perimetro (sorgenti COBOL di riferimento, cartelle target, fuori ambito) · Specifica · Invarianti di parità · Criteri di accettazione **eseguibili da un comando** · Strategia di rollback · Limiti per l'agente.

Flusso: `ready → Selettore → Esecutore → Validatore → Gate umano → sblocco dipendenze`.

Nei worktree il submodule va inizializzato (`git submodule update --init`). Il repository è pubblico: niente segreti, dati personali o percorsi locali in commit, issue e PR.

## Regole non negoziabili

1. Nessun codice di business prima che la Fase 0 sia mergiata.
2. Una issue, un perimetro, un comando che dice se è finita. Diff minimo, zero refactoring non richiesto.
3. Se il COBOL smentisce la specifica: fermarsi, commento tecnico, `needs-spec-update`. Mai adattare la realtà in silenzio.
4. Mai due issue `in-progress` sulla stessa tabella o cartella. Ciclo batch giornaliero in sequenza stretta.
5. Il merge è umano. Gli agenti non mergiano.
6. Importi solo `BigDecimal` con scala e arrotondamento COBOL espliciti. Mai `double`/`float` su `PIC S9…V99`.
7. Parità significa stesso effetto, stesso ordine di chiave, stesso comportamento su riesecuzione — nessuna idempotenza o "miglioria" inventata.
8. Ogni `COPY` del programma sorgente ha un corrispondente tradotto o un'esclusione esplicita.

I quattro rischi su cui tarare il Validatore: aritmetica decimale e overpunch · stato pseudo-conversazionale `COMMAREA` (due tempi ENTER/REENTER) · chiavi e ordinamenti VSAM/AIX · logica nascosta nei `COPY`.

## Non reinventare l'acqua calda

Prima di scrivere un tool di analisi, verificare se ne esiste uno. Si scrive codice proprio solo per incollare strumenti esistenti. Ogni strumento adottato o scartato va registrato nel paper con il motivo.

**SonarQube non analizza il COBOL senza licenza**: l'analizzatore COBOL parte dalla Enterprise Edition (verificato sulla documentazione Sonar il 27 nov 2026). L'utente non ha licenza: Sonar si usa solo sul Java (Community Build, in container). Non esiste un equivalente open source maturo per il COBOL: l'analisi preliminare si compone da strumenti più piccoli.

| Esigenza | Candidati open source | Stato |
| --- | --- | --- |
| Sintassi, warning, cross-reference, esecuzione batch come oracle | **GnuCOBOL 3.2** (`cobc`) | adottato; immagine propria con versione fissata |
| Inventario e grafi `CALL` / `COPY` | `cobol-migration-toolkit` (Python, basato su regex) | da provare su CardDemo in Wave 0A |
| AST, CFG, gerarchia copybook, overlay di memoria | `cobmix` (Python), ProLeap COBOL parser (Java, AGPL-3), Koopa | da provare in Wave 0A |
| Copybook → schema, lettura record in Java | cb2xml, JRecord | da provare in Wave 0A |
| Analisi JCL | `mapa` | da provare in Wave 0A |
| Conteggi e complessità di base | scc | da usare via container |
| Qualità lato Java | SonarQube Community Build, JaCoCo, SpotBugs, ArchUnit, PIT | Wave 0B |
| Integrazione | Testcontainers | Wave 0B |

Criterio di adozione: lo strumento gira su CardDemo senza modifiche al sorgente e il suo output è controllato a campione contro il codice. Maturità e licenza dei candidati **non sono ancora verificate**: una prova fallita si registra nel paper come strumento scartato.

Limite noto: GnuCOBOL non esegue `EXEC CICS` e non è emerso un emulatore CICS open source pronto all'uso (OpenKicks dichiara compatibilità GnuCOBOL ma la licenza è da verificare). L'oracle eseguibile copre i batch; per l'online l'oracle è una matrice di comportamento derivata dal sorgente e recensita dal Validatore. Va dichiarato nel paper.

## Containerizzazione: massima, ovunque

Il risultato finale è **un'applicazione containerizzata funzionante**, non codice che compila. Vale per il prodotto e per tutto ciò che lo circonda.

- **Unico prerequisito sull'host: Docker e git.** Niente JDK, Maven, GnuCOBOL o Postgres richiesti in locale per costruire, testare o eseguire.
- **Prodotto:** `docker compose up` da clone pulito porta su PostgreSQL, servizio online (API + UI), job batch (profilo o servizio dedicato) e caricamento dei dati di esempio. Build multi-stage, immagini con versione fissata, healthcheck su ogni servizio, utente non-root.
- **Oracle legacy:** GnuCOBOL gira in un'immagine costruita da noi (`cobc` con versione fissata); gli output dei batch COBOL usati come golden si rigenerano con un comando.
- **Verifica:** test di integrazione e parità contro PostgreSQL reale (Testcontainers o Compose), mai un database in memoria al posto di quello vero. La CI esegue gli stessi container.
- **Analisi:** scc, SonarQube Community e gli strumenti di Wave 0A girano in container, con il comando esatto registrato in `paper/data/`.
- **Definizione di "finito" per ogni wave:** oltre ai test, uno smoke test che parte da `docker compose up` e attraversa il percorso appena migrato.
- Un criterio di accettazione che si verifica solo sull'host dello sviluppatore non è un criterio di accettazione.

Sull'host sono comunque presenti `java` 21, `docker` 29.9, `cobc` 3.2, `gh` (autenticato), `codex` 0.172: utili per prove rapide, mai come dipendenza del progetto.

## Il paper (`paper/mec-b-paper.md`)

Si aggiorna **man mano**, a ogni passo chiuso, non alla fine.

- **Replicabile.** Ogni passo riporta ciò che serve per rifarlo: il comando esatto, il testo integrale dell'issue, il prompt dato all'Esecutore e al Validatore, versioni di modelli e strumenti. I materiali lunghi vanno in appendice o nel repository, con link stabile (commit, numero di issue/PR).
- **Chiaro.** Scritto per chi non ha seguito il lavoro: ogni termine COBOL/mainframe o agentico è spiegato alla prima occorrenza, ogni passo dice *cosa si fa, perché, come si capisce che è riuscito*. Prosa piana, niente gergo da cronaca di sessione.
- **Reale.** Si racconta ciò che è accaduto, compresi errori, vicoli ciechi e interventi umani. Niente esempi ripuliti a posteriori. Costi e tempi così come misurati.
- **Trasferibile.** A ogni wave, una nota su cosa è specifico di CardDemo e cosa vale per un altro sistema legacy; dove serve, una lista di controllo riusabile.
- **Solo fatti misurati.** Ogni numero ha una fonte in `paper/data/` o un comando riproducibile. Niente stime presentate come misure; ciò che è stima è etichettato come tale.
- **Tempi:** per ogni issue registrare in `paper/data/timeline.csv` apertura, inizio lavoro, PR aperta, esito di ogni giro del Validatore, merge (timestamp da GitHub), modello Esecutore, numero di giri, intervento umano, e dove disponibile consumo di token/costo. Distinguere tempo-agente, tempo di attesa del gate umano e tempo di calendario.
- **Anche i fallimenti:** PR bocciate, `needs-spec-update`, rework, strumenti scartati. Sono il dato più utile.
- Tabelle e grafici dove chiariscono (Mermaid per i flussi, figure generate da `paper/data/` per le misure).
- Il metodo si chiama **MEN-B**; il file resta `mec-b-paper.md` finché l'utente non decide diversamente.

## Azioni che richiedono conferma esplicita

Cambiare visibilità o nome del repository, pubblicare su Zenodo, mergiare una PR. Mai operare sul repository upstream `aws-samples`.
