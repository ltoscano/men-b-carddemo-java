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

Attenzione alle maiuscole: 5 programmi hanno estensione `.CBL` (tra cui `CBSTM03A` e `CBSTM03B`); su Linux un glob `*.cbl` li perde. Enumerare sempre senza distinzione di maiuscole e contro un manifesto esplicito.

Baseline misurata (27 nov 2026): `app/cbl` 31 programmi / 20.650 righe; 44 `.cbl` / 30.175 righe contando i tre moduli opzionali; `app/cpy` 30 copybook / 2.786 righe; 17 mappe BMS / 4.472 righe; 38 JCL / 2.429 righe.

## Il metodo in breve

Migrazione **ibrida**: il comportamento da preservare è brownfield, lo stack target è greenfield. Quindi due Fasi 0 prima di qualsiasi logica di business.

**Fonte unica per wave, numerazione e dipendenze: `docs/piano-wave.md`.** In caso di discordanza con altri documenti (compreso `paper/piano-migrazione-carddemo-java.md`, che è la proposta iniziale) vale il piano. In sintesi:

- **Wave 0A** (brownfield, sola lettura): strumenti, inventario, contratto dati, oracle GnuCOBOL, golden, matrice di comportamento online.
- **Wave 0B** (greenfield, in parallelo a 0A): scheletro Java in container, Compose, cancelli di qualità, contratti condivisi.
- **Wave 1** dati → **Wave 2** pilota (una fetta batch, una online) → **Wave 3** online ∥ **Wave 4** batch → **Wave 5** parità end-to-end e rilascio 1.0 → **Wave 6** moduli opzionali.

### Ruoli e modelli

| Ruolo | Chi | Compito |
| --- | --- | --- |
| Pianificatore / Selettore | **Fable** (sessione principale) | Scrive le issue, verifica dipendenze e non-sovrapposizione di cartelle/tabelle, apre il worktree, lancia l'Esecutore. Non implementa. |
| Esecutore | subagent **Opus** (issue complesse: aritmetica, COMMAREA, batch) o **Sonnet** (issue meccaniche: DTO, schema, loader, boilerplate) | Una sola issue, in worktree isolato. Implementa, testa, apre PR con `Closes #N`. |
| Validatore adversarial | **Codex CLI** (`codex exec` / `codex review`), contesto pulito | Legge solo specifica, diff e test. Mandato: falsificare. Max due giri, poi scala. |
| Approvatore | **Fable**, per delega dell'autore (27 nov 2026) | Giudica i rilievi del Validatore, decide il merge secondo le regole qui sotto, scrive ogni approvazione nel registro. |
| Autore | l'utente | Ha delegato l'approvazione. Riceve le escalation, legge il registro quando vuole, può annullare qualsiasi decisione. |

Il Validatore è deliberatamente un modello di un altro fornitore: non condivide contesto né bias dell'Esecutore. Sulle PR lavora in un clone usa e getta con `-s workspace-write -c 'sandbox_workspace_write.network_access=true'`, così esegue da sé Docker e i criteri di accettazione (autonomia concordata con l'autore il 27 nov 2026); mai `danger-full-access`. Sulle specifiche basta `-s read-only`. Prompt in `paper/data/prompts/`. Il suo output va riportato per intero nella PR, comprese le obiezioni respinte e il motivo.

### Coda di issue

Etichette: `bootstrap`, `ready`, `in-progress`, `in-review`, `blocked`, `needs-spec-update`, più `wave-0`…`wave-6`.

Una issue diventa `ready` solo dopo che Codex ha contestato **la specifica** (non solo, più tardi, la PR) e i rilievi sono stati accolti o respinti con motivo. Prompt, output integrale ed esito vanno in `paper/data/reviews/`.

Ogni issue ha: Obiettivo · Dipendenze e perimetro (sorgenti COBOL di riferimento, cartelle target, fuori ambito) · Specifica · Invarianti di parità · Criteri di accettazione **eseguibili da un comando** · Strategia di rollback · Limiti per l'agente.

Flusso: `ready → Selettore → Esecutore → Validatore → Approvatore → sblocco dipendenze`. Dove i documenti di metodo e il piano dicono "gate umano", oggi si intende l'Approvatore delegato, con escalation all'autore.

Nei worktree il submodule va inizializzato (`git submodule update --init`). Il repository è pubblico: niente segreti, dati personali o percorsi locali in commit, issue e PR.

## Regole non negoziabili

1. Nessun codice di business prima che la Fase 0 sia mergiata.
2. Una issue, un perimetro, un comando che dice se è finita. Diff minimo, zero refactoring non richiesto.
3. Se il COBOL smentisce la specifica: fermarsi, commento tecnico, `needs-spec-update`. Mai adattare la realtà in silenzio.
4. Mai due issue `in-progress` sulla stessa tabella o cartella. Ciclo batch giornaliero in sequenza stretta.
5. Il merge lo decide solo l'Approvatore (Fable), alle condizioni della sezione "Approvazione delegata". Esecutori e Validatore non mergiano mai.
6. Importi solo `BigDecimal` con scala e arrotondamento COBOL espliciti. Mai `double`/`float` su `PIC S9…V99`.
7. Parità significa stesso effetto, stesso ordine di chiave, stesso comportamento su riesecuzione — nessuna idempotenza o "miglioria" inventata.
8. Ogni `COPY` del programma sorgente ha un corrispondente tradotto o un'esclusione esplicita.

I rischi su cui tarare il Validatore: aritmetica decimale, troncamento e overpunch · stato pseudo-conversazionale `COMMAREA` (due tempi ENTER/REENTER) · confini di transazione CICS (`READ UPDATE`, `SYNCPOINT`, rollback) · chiavi, duplicati e ordinamenti VSAM/AIX · ordine di collazione EBCDIC contro ASCII · logica nascosta nei `COPY` · differenze GnuCOBOL / z/OS che rendono falso l'oracle · effetti parziali prima di un abend.

## Approvazione delegata

Dal 27 nov 2026 l'autore ha delegato a Fable l'approvazione e il merge delle PR, per rendere il processo il più automatico possibile. In cambio, ogni approvazione è scritta in `docs/registro-approvazioni.md`.

**Una PR si mergia solo se valgono tutte:**
1. la CI sullo SHA finale è verde;
2. il Validatore (Codex) ha eseguito da sé i criteri di accettazione su un clone pulito e nel suo ultimo giro non resta aperto alcun rilievo bloccante (per le PR a basso rischio vedi "Validazione proporzionata al rischio");
3. ogni rilievo del Validatore ha un esito scritto: corretto, respinto con motivo verificato sul sorgente, o rinviato a una issue esistente o nuova;
4. il diff è nel perimetro della specifica;
5. sono state fatte **al massimo due validazioni avversariali** (regola dell'autore, 27 nov 2026, 15:35 UTC): prima validazione, un giro di correzione, seconda validazione, che è l'ultima. Niente terzo giro di Codex.

**Dopo la seconda validazione decide Fable, con pragmatismo, e registra** (regola dell'autore del 27 nov 2026, resa più stretta alle 15:35 UTC: le validazioni sono al massimo due). Se la seconda validazione boccia ancora:
- se i rilievi residui **non sono bloccanti** e nessuno può far passare per buono un lavoro sbagliato (niente falsi verdi, niente perdita o alterazione di dati, niente violazione di parità), Fable mergia e apre una issue per ogni rilievo residuo, con la prova del Validatore e criteri di accettazione;
- se resta un rilievo **bloccante**, o un rischio di falso verde o sui dati, Fable non mergia subito: l'Esecutore corregge quel solo rilievo e **Fable verifica da sé la correzione** rieseguendo su un clone pulito il controesempio del Validatore e i criteri di accettazione (senza un terzo giro di Codex); poi mergia. Se la correzione non regge, sceglie tra riscrivere la specifica o dividere l'issue, e registra perché;
- in ogni caso la voce di registro dice cosa chiedeva il Validatore, cosa si è deciso, perché, e dove è finito ciò che resta.

**Fin dove arriva la sfiducia negli script (regola nata dalla PR #20).** Uno script di verifica deve accorgersi di un comando che fallisce, di un'attesa che non finisce, di una risposta malformata o incompleta, di un risultato rimasto da una corsa precedente. Non gli si chiede di difendersi da uno strumento che restituisce dati falsi ma ben formati con esito positivo (per esempio un `docker` sostituito che dichiara assente una risorsa presente): la difesa userebbe lo stesso strumento e non avrebbe fine. Un rilievo di questo secondo tipo si registra come limite dichiarato, non blocca il merge, e nei prompt di validazione non si chiede di cercarlo.

**Validazione proporzionata al rischio** (decisione dell'autore, 27 nov 2026, 16:00 UTC).
- *Rischio pieno, Codex obbligatorio*: la PR tocca `oracle/`, golden, parità, schema o dati, logica di business Java, script di verifica (`verify.sh`, `smoke.sh`, `quality/`, `check.sh` e colla di `analysis/`), CI, Dockerfile o Compose. Nel dubbio è rischio pieno.
- *Basso rischio, senza Codex*: solo documentazione, testi e motivazioni, correzioni che non cambiano alcun valore atteso né alcun controllo. Bastano CI verde e la lettura integrale del diff da parte di Fable, che riesegue i criteri di accettazione su un clone pulito. La voce di registro dichiara "senza Codex" e la classe di rischio.
- La classe si scrive nell'issue quando passa a `ready`. Se il diff della PR esce dalla classe dichiarata, torna a rischio pieno.

**Per andare più veloci senza abbassare la guardia** (stessa data): l'Esecutore esegue prima della PR un autocontrollo sulle quattro famiglie di difetto ricorrenti (`paper/data/prompts/esecutore.md`); la seconda validazione è ristretta ai rilievi della prima e al diff di correzione (`paper/data/prompts/validatore-pr.md`); non più di tre validazioni Codex in parallelo; le issue grandi si dividono prima di affidarle.

Per far bastare due validazioni: la prima deve essere completa (il prompt elenca tutte le verifiche attese, comprese le mutazioni), e nel giro di correzione l'Esecutore cerca in tutto il lavoro lo stesso schema di difetto, non solo il caso segnalato.

**Fable scala all'autore solo quando:** serve cambiare l'obiettivo del progetto o il perimetro di una wave; un contrasto bloccante resta dopo il giro in più; la decisione è irreversibile o esce dal repository.

**Coerenza.** Fable ha scritto la specifica, quindi non è un giudice indipendente del proprio lavoro: l'indipendenza viene da Codex. Fable non respinge un rilievo senza un'evidenza verificata, e a parità di dubbio dà ragione al Validatore. Rilievi simili ricevono lo stesso trattamento: prima di decidere si rilegge il registro.

**Decisioni di prodotto** (per esempio portare o escludere `CBTRN01C`, scenari batch di riferimento): Fable sceglie l'opzione più coerente con l'obiettivo e con le decisioni già prese, la registra come *decisione delegata* con motivo e alternative, e procede. L'autore può annullarla.

**Registro** (`docs/registro-approvazioni.md`, in sola aggiunta): una voce per ogni specifica passata a `ready`, PR mergiata, decisione delegata, rilievo respinto, escalation. Ogni voce: data e ora UTC, oggetto, decisione, motivo, evidenze (SHA, CI, giro del Validatore), cosa è stato rinviato e dove.

## Non reinventare l'acqua calda

Prima di scrivere un tool di analisi, verificare se ne esiste uno. Si scrive codice proprio solo per incollare strumenti esistenti. Ogni strumento adottato o scartato va registrato nel paper con il motivo.

**SonarQube non analizza il COBOL senza licenza**: l'analizzatore COBOL parte dalla Enterprise Edition (verificato sulla documentazione Sonar il 27 nov 2026). L'utente non ha licenza: Sonar si usa solo sul Java (Community Build, in container). Non esiste un equivalente open source maturo per il COBOL: l'analisi preliminare si compone da strumenti più piccoli.

| Esigenza | Strumento | Stato (esito di #1, dettagli in `docs/legacy-map/strumenti.md`) |
| --- | --- | --- |
| File, righe totali, righe vuote | scc 4.1.0 | adottato |
| Ripartizione codice / commenti | — | **non disponibile**: scc sbaglia su COBOL con numeri di sequenza e assembler |
| Compilazione, diagnostica, oracle batch | GnuCOBOL 3.2 | adottato; `CBEXPORT`, `CBIMPORT`, `CBSTM03A` non compilano così come sono (vedi #4) |
| `COPY` con riga e `REPLACING` | ProLeap COBOL parser (MIT) + colla Java | adottato |
| `CALL` statiche | cobol-migration-toolkit 0.8.0 | adottato (scartato per le `COPY`) |
| Comandi `EXEC CICS` | — | nessuno strumento li vede: ripiego in #2 |
| Copybook → tracciato | cb2xml 1.01.08 | adottato (posizioni a base 1; `OCCURS` per elemento) |
| JCL | mapa | adottato (non riporta `PARM=` né `SYSIN *`) |
| Scartati / non provati | cobmix (scartato); Koopa, JRecord (non provati) | |
| Qualità lato Java | SonarQube Community Build, JaCoCo, SpotBugs, ArchUnit, PIT | #15 |
| Integrazione | Testcontainers | #15 |

Comandi: `./analysis/run.sh --all` e `--all --check` (analisi del legacy), `./verify.sh` (build e test Java). Una nuova analisi è una nuova cartella `analysis/<nome>/` con `run.sh`, `check.sh`, `deps`. Su macOS il legacy va letto da un volume Docker sensibile alle maiuscole, non da un bind mount (`analysis/lib/common.sh`).

Criterio di adozione: lo strumento gira su CardDemo senza modifiche al sorgente e il suo output è controllato a campione contro attesi scritti a mano. Un controllo vale solo se fallisce quando si altera l'output: ogni controllo ha la sua prova negativa. Un errore noto di uno strumento non diventa mai un valore atteso.

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
- **Niente cade dal cielo.** Ogni passaggio è documentato in modo chiaro e semplice, nell'ordine in cui è avvenuto. Ogni decisione, strumento, numero, file o termine che compare nel paper è introdotto prima di essere usato: da dove viene, perché si è scelto, quali alternative si sono scartate. Se un passo dipende da uno precedente, lo dice. Un lettore non deve mai chiedersi "e questo da dove salta fuori?".
- **Chiaro.** Scritto per chi non ha seguito il lavoro: ogni termine COBOL/mainframe o agentico è spiegato alla prima occorrenza, ogni passo dice *cosa si fa, perché, come si capisce che è riuscito*. Prosa piana, niente gergo da cronaca di sessione.
- **Reale.** Si racconta ciò che è accaduto, compresi errori, vicoli ciechi e interventi umani. Niente esempi ripuliti a posteriori. Costi e tempi così come misurati.
- **Trasferibile.** A ogni wave, una nota su cosa è specifico di CardDemo e cosa vale per un altro sistema legacy; dove serve, una lista di controllo riusabile.
- **Solo fatti misurati.** Ogni numero ha una fonte in `paper/data/` o un comando riproducibile. Niente stime presentate come misure; ciò che è stima è etichettato come tale.
- **Tempi: ogni singolo passaggio ha i suoi.** Alla fine il lettore deve sapere quanto tempo è servito in tutto e dove è andato. Vedi la sezione "Misura dei tempi" qui sotto.
- **Anche i fallimenti:** PR bocciate, `needs-spec-update`, rework, strumenti scartati. Sono il dato più utile.
- Tabelle e grafici dove chiariscono (Mermaid per i flussi, figure generate da `paper/data/` per le misure).
- Il metodo si chiama **MEN-B**; il file resta `mec-b-paper.md` finché l'utente non decide diversamente.

## Misura dei tempi

Vincolo dell'autore: nessun passaggio senza tempi. Il registro è `paper/data/eventi.csv`, in sola aggiunta.

- **Si registra nel momento in cui accade**, con `paper/data/tlog.sh <passo> <evento> <attore> [note]`, che scrive l'ora UTC corrente. Mai ricostruire a memoria.
- **Ogni turno di lavoro**: all'inizio `tlog.sh <passo> richiesta-autore autore`, alla fine `tlog.sh <passo> risposta-consegnata fable`. L'intervallo tra una risposta consegnata e la richiesta successiva è tempo di attesa umano.
- **Ogni passo** ha `inizio` e `fine`. Ogni lancio di Esecutore o Validatore ha inizio, fine, modello, token ed esito; il comando si avvolge tra due chiamate a `tlog.sh`.
- **Issue e PR**: apertura, etichette, PR aperta, merge si leggono dai timestamp di GitHub (fonte `github`) e si esportano nel registro alla chiusura di ogni issue.
- **Colonna `fonte`**: `orologio` (registrato dal vivo), `git`, `github`, `file` (data di un file), `log-strumento`. Un tempo ricostruito a posteriori dichiara la fonte e, se è solo un limite, lo dice nelle note.
- **Ciò che non è stato misurato si scrive "non misurato"**, non si stima. Vale anche per il lavoro dell'autore fatto fuori sessione.
- **Tempo perso** (blocchi, tentativi falliti, rework) si registra come gli altri: è parte del totale.
- Nel paper ogni passo riporta la propria durata, e la sezione 6.1 dà il totale distinto in: lavoro degli agenti, attesa e lavoro dell'autore, tempo perso, tempo di calendario.
- Comandi non interattivi lanciati da script (Codex compreso) vanno avviati con `< /dev/null`: senza, `codex exec` può restare in attesa di input all'infinito.

## Azioni che richiedono conferma esplicita

Cambiare visibilità o nome del repository, pubblicare su Zenodo, cancellare rami o dati non rigenerabili, forzare la storia di `main`. Il merge delle PR è delegato (vedi "Approvazione delegata"). Mai operare sul repository upstream `aws-samples`.
