# Specifiche in coda, agenti al lavoro

Un metodo per governare lo sviluppo software con agenti AI, applicato a un servizio greenfield e a un repository reale.

Lo sviluppo assistito da agenti non fallisce, di solito, per mancanza di codice. Fallisce perché il lavoro non è tagliato in unità verificabili, perché più agenti prendono decisioni incompatibili, e perché nessuno ha il mandato esplicito di falsificare il risultato. Questo articolo descrive un metodo concreto per evitarlo: usare le GitHub Issues come coda di specifiche, assegnare ruoli distinti a Selettore, Esecutore e Validatore adversarial, e riservare il merge a un gate umano.

Il metodo è lo stesso in un progetto partito da zero e in un codice già in produzione. Cambia il rischio che devi controllare per primo, e quindi cambia la Fase 0. Lo mostro su due casi. Il primo è un microservizio enterprise inventato, *Approval Gate*, con tre moduli disaccoppiati. Il secondo è un repository open source reale, [louislam/uptime-kuma](https://github.com/louislam/uptime-kuma), ispezionato in sola lettura: nessun file, simbolo o comando di test è stato inventato, e sul repository non è stata aperta alcuna issue o pull request.

---

## 1. Perché una coda di specifiche rende governabile il lavoro degli agenti

Un agente basato su un modello linguistico è efficace quando l'obiettivo è chiuso, il perimetro è esplicito e il criterio di fine è eseguibile. Perde disciplina appena deve inventare l'architettura, coordinarsi con altri cambiamenti in corso o decidere da solo che una specifica è "abbastanza vera". Lasciarlo libero sul repository intero significa accettare tre effetti collaterali ricorrenti: contratti incompatibili tra moduli, refactoring non richiesti e pull request che compilano senza dimostrare l'intento.

Le GitHub Issues risolvono il problema se smettono di essere un elenco di desiderata e diventano la coda operativa del lavoro. Ogni issue è una specifica completa: obiettivo, dipendenze, perimetro, fuori ambito e criteri di accettazione verificabili da un comando. Da quella issue nasce un branch, da quel branch una pull request, da quella pull request un merge. La tracciabilità specifica → issue → PR → test non è un orpello di processo: è l'unico modo per ricostruire, settimane dopo, perché una decisione è entrata in produzione.

I ruoli vanno tenuti separati. Non è una questione di organigramma, è una questione di contesto.

- Il **Selettore** legge solo le issue `ready`. Verifica che le dipendenze dichiarate siano chiuse e che le cartelle coinvolte non si sovrappongano a un'altra issue `in-progress`. Marca il lavoro, apre un worktree isolato e avvia l'Esecutore. Non implementa.
- L'**Esecutore** lavora su una sola issue. Implementa, scrive i test previsti dai criteri di accettazione, lancia i comandi di verifica e apre una pull request che chiude l'issue (`Closes #N`). Se la specifica contraddice il codice o un assunto architetturale, non improvvisa: lascia un commento tecnico, applica l'etichetta `needs-spec-update` e rilascia la issue.
- Il **Validatore adversarial** parte con un contesto pulito. Legge soltanto la specifica, il diff della pull request e i test. Il suo incarico non è "aiutare a far passare il lavoro", è cercare buchi: test di facciata, modifiche fuori perimetro, regressioni, convenzioni violate, criteri di accettazione soddisfatti solo a parole. Se boccia, commenta e rimanda all'Esecutore. Dopo due giri falliti, scala al gate umano.
- Il **gate umano** legge la sintesi del Validatore e decide il merge. Resta l'unico punto in cui una modifica diventa parte della linea principale. Se il merge cambia un assunto, le issue a valle vanno riallineate prima di tornare `ready`.

Bastano sei etichette per governare la coda: `bootstrap`, `ready`, `in-progress`, `in-review`, `blocked`, `needs-spec-update`. Il flusso è lineare.

```text
Issue ready → Selettore → Esecutore → Validatore adversarial → Gate umano → sblocco dipendenze
                 ↘ ambiguità: needs-spec-update
                 ↘ PR bocciata (al massimo due giri) → Esecutore
```

Questo schema non rende l'agente "autonomo" in senso manageriale. Lo rende utilizzabile. L'autonomia utile è la scelta del passo successivo *dentro* una specifica già approvata, non la riscrittura silenziosa del prodotto.

---

## 2. Caso greenfield: Approval Gate

### Contesto

Immaginiamo un'azienda industriale di medie dimensioni che ha iniziato a far proporre azioni operative ad agenti interni: aprire una pratica d'acquisto, aggiornare un ticket di manutenzione, richiedere un accesso temporaneo a un sistema. Il modello può scegliere gli strumenti e preparare la proposta. Non deve, da solo, produrre l'effetto sul mondo reale.

*Approval Gate* è il microservizio che sta in mezzo. Riceve una richiesta di azione già strutturata, la valuta rispetto a una policy versione, e risponde in uno di tre modi: approvazione automatica, rifiuto motivato, oppure apertura di un caso di approvazione umana. La decisione di autorizzare una spesa, un accesso o un cambiamento resta di una persona. Il servizio ha il solo compito di rendere quella decisione esplicita, tracciabile e ripetibile.

Il progetto è piccolo e va tenuto piccolo. Tre moduli disaccoppiati, comunicanti solo attraverso contratti condivisi, sono sufficienti:

| Modulo | Responsabilità | Non fa |
| --- | --- | --- |
| `policy` | Conserva le policy versionate e valuta una richiesta. Restituisce un verdetto (`allow`, `deny`, `needs_review`) con le ragioni e, se serve, il ruolo dell'approvatore. | Non persiste i casi e non parla con sistemi esterni. |
| `cases` | Gestisce il ciclo di vita del caso (`open`, `waiting`, `approved`, `rejected`, `expired`) e l'API usata da agenti e responsabili. | Non interpreta le regole di business e non invia notifiche in proprio. |
| `connectors` | Adatta identità, ticketing e canali di notifica verso i sistemi aziendali. | Non decide il verdetto e non muta lo stato del caso se non dietro comando esplicito di `cases`. |

I tre moduli dipendono da un nucleo condiviso, definito in Fase 0: tipi di dominio, errori, schema della richiesta e della decisione, convenzioni del repository e pipeline di verifica. Finché quel nucleo non è mergiato, nessun agente lavora sulle fette verticali.

### Fase 0: contratti, schema e CI prima del codice di business

Nel greenfield il rischio principale è la divergenza architetturale. Senza un confine condiviso, ogni agente inventa i propri tipi, i propri stati e il proprio modo di fallire. La prima issue, e solo la prima, è quindi un `bootstrap` sequenziale. Nessun altro lavoro è `ready` finché questa issue non è chiusa.

Ecco la issue di bootstrap nel formato che useremo anche in seguito.

````markdown
## Obiettivo
Creare lo scheletro del servizio Approval Gate, i contratti condivisi tra i moduli
`policy`, `cases` e `connectors`, e una pipeline di verifica già verde.

## Dipendenze e perimetro
- Dipende da: nessuna
- Moduli / cartelle coinvolte: `src/shared/`, `src/policy/`, `src/cases/`,
  `src/connectors/`, `tests/`, `pyproject.toml`, `.github/workflows/ci.yml`,
  `README.md`
- Fuori ambito: regole di business reali, persistenza di produzione,
  integrazioni verso IdP, ticketing o canali di notifica, interfaccia utente.

## Specifica
- Il repository espone tre package vuoti ma importabili, più un package
  `shared` con i tipi comuni.
- I contratti minimi, espressi come modelli Pydantic, sono:
  - `ActionRequest`: `request_id`, `agent_id`, `actor_id`, `tool`, `payload`,
    `amount_cents` opzionale, `created_at`.
  - `Decision`: `verdict` ∈ {`allow`, `deny`, `needs_review`}, `policy_id`,
    `policy_version`, `reasons[]`, `approver_role` opzionale.
  - `Case`: `case_id`, `request`, `decision`, `state` ∈ {`open`, `waiting`,
    `approved`, `rejected`, `expired`}, `approver_id` opzionale, timestamp
    di transizione.
- Le transizioni ammesse sono solo: `open → waiting | rejected | expired`,
  `waiting → approved | rejected | expired`. Ogni altra transizione solleva
  un errore di dominio.
- La CI esegue lint, typecheck e test ad ogni push. Al termine del bootstrap
  la suite è verde anche se i moduli di business espongono soltanto un
  adattatore vuoto che rispetta le firme.

## Contratti / Interfacce
- `PolicyEngine.evaluate(request: ActionRequest, policy: Policy) -> Decision`
- `CaseService.open(request: ActionRequest, decision: Decision) -> Case`
- `CaseService.transition(case_id, new_state, actor_id) -> Case`
- `Notifier.notify(case: Case) -> None` (firma soltanto; implementazione
  nel modulo `connectors`, fuori da questa issue)

## Criteri di accettazione (verificabili)
- [ ] `pytest` è verde e include almeno un test per i tipi condivisi e uno
      per ogni transizione di stato illegale.
- [ ] `ruff check` e `mypy src` sono verdi, senza warning nuovi.
- [ ] La workflow CI in `.github/workflows/ci.yml` esegue i tre comandi
      sopra e fallisce se uno di essi fallisce.
- [ ] I tre moduli si importano senza dipendere l'uno dall'implementazione
      dell'altro: dipendono solo da `src/shared`.

## Limiti per l'agente
- Non implementare un motore di policy reale, un database o un connettore.
- Se emerge la necessità di un campo di dominio non previsto, fermarsi e
  applicare `needs-spec-update` invece di allargare lo schema in silenzio.
````

Solo dopo il merge di questa issue il Selettore può rendere `ready` le fette verticali. A quel punto il parallelismo diventa possibile, ma resta disciplinato: `policy` e `cases` possono procedere in worktree distinti perché i confini di cartella e i tipi sono già fissati; `connectors` resta `blocked` finché `cases` non espone un caso persistito su cui notificare.

### Due issue verticali, già pronte per un Esecutore

La seconda issue costruisce il motore di policy. Non tocca i casi e non parla con l'esterno.

````markdown
## Obiettivo
Valutare una `ActionRequest` rispetto a una policy versione e restituire
una `Decision` deterministica.

## Dipendenze e perimetro
- Dipende da: #1
- Moduli / cartelle coinvolte: `src/policy/`, `tests/policy/`
- Fuori ambito: persistenza dei casi, API HTTP, connettori, interfaccia
  utente, motori di regole generici.

## Specifica
- Una policy è un documento versionato con: `policy_id`, `version`,
  `allowed_tools`, soglia `auto_allow_max_cents`, ruolo `reviewer_role`
  e un elenco opzionale di `denied_actors`.
- Regole, in questo ordine:
  1. se `tool` non è in `allowed_tools` → `deny`;
  2. se `actor_id` è in `denied_actors` → `deny`;
  3. se `amount_cents` è assente o ≤ `auto_allow_max_cents` → `allow`;
  4. altrimenti → `needs_review`, con `approver_role = reviewer_role`.
- `reasons` elenca le regole che hanno determinato il verdetto, in forma
  stabile e confrontabile nei test.
- A parità di richiesta e di policy, due valutazioni producono la stessa
  `Decision` (escluso eventuali campi non deterministici, che in questa
  issue non esistono).

## Contratti / Interfacce
- Rispettare `PolicyEngine.evaluate(request, policy) -> Decision` definito
  in #1. Non modificare i tipi in `src/shared/` senza una issue di
  riallineamento.

## Criteri di accettazione (verificabili)
- [ ] `pytest tests/policy/` copre i quattro esiti sopra, più i casi limite:
      `amount_cents = auto_allow_max_cents`, tool sconosciuto, attore
      negato anche con importo sotto soglia, richiesta senza importo.
- [ ] `pytest`, `ruff check` e `mypy src` restano verdi.
- [ ] Nessun file fuori da `src/policy/` e `tests/policy/` è modificato,
      salvo un eventuale export dichiarato in un `__init__.py` già previsto
      dal bootstrap.

## Limiti per l'agente
- Non introdurre un linguaggio di regole, un interprete o una dipendenza
  nuova senza `needs-spec-update`.
- Non "migliorare" lo schema condiviso per rendere la policy più espressiva.
````

La terza issue apre e fa transire i casi. Dipende dal bootstrap, non dall'implementazione interna di `policy`: riceve una `Decision` già calcolata.

````markdown
## Obiettivo
Aprire un caso di approvazione a partire da una `ActionRequest` e da una
`Decision`, e transire lo stato secondo la macchina a stati definita in #1.

## Dipendenze e perimetro
- Dipende da: #1
- Moduli / cartelle coinvolte: `src/cases/`, `tests/cases/`
- Fuori ambito: motore di policy, connettori verso sistemi esterni,
  autenticazione, interfaccia utente.

## Specifica
- `CaseService.open`:
  - se la decisione è `allow`, il caso nasce già in `approved`;
  - se è `deny`, nasce in `rejected`;
  - se è `needs_review`, nasce in `waiting`.
- `CaseService.transition` applica solo le transizioni ammesse. Una
  transizione illegale non lascia lo stato invariato in silenzio: solleva
  l'errore di dominio definito in #1.
- Il servizio persiste i casi in un archivio sostituibile (in questa issue
  basta un adattatore in memoria). Ogni transizione appende un evento
  immutabile: stato precedente, stato nuovo, attore, timestamp.
- L'API HTTP, se introdotta in questa issue, si limita a `POST /cases` e
  `POST /cases/{id}/transitions`. Nessun altro endpoint.

## Contratti / Interfacce
- Rispettare `CaseService.open` e `CaseService.transition` definiti in #1.
- L'archivio è iniettato: il servizio non importa un database concreto.

## Criteri di accettazione (verificabili)
- [ ] `pytest tests/cases/` verifica apertura nei tre verdetti, ogni
      transizione legale, ogni transizione illegale, e la scrittura
      dell'evento di audit.
- [ ] `pytest`, `ruff check` e `mypy src` restano verdi.
- [ ] Nessuna dipendenza nuova di infrastruttura (Postgres, code, broker).

## Limiti per l'agente
- Non chiamare il modulo `connectors` e non implementare un notifier
  "temporaneo" dentro `cases`.
- Non modificare `src/policy/`.
````

### Parallelismo e validazione

Dopo il merge di `#1`, il Selettore può far partire in parallelo l'Esecutore di `#2` e quello di `#3`, ciascuno in un worktree e su cartelle disgiunte. L'issue sui connettori resta in attesa: ha bisogno di un caso reale da notificare e, soprattutto, di non dover indovinare il formato dell'evento.

Il Validatore, in un greenfield, guarda tre cose prima di ogni altra: aderenza alla specifica, semplicità del disegno e qualità vera dei test. Un test che ripete l'implementazione senza coprire i casi limite non basta. Una pull request che "approfitta" per introdurre un framework di regole o un ORM non richiesto va bocciata, anche se i comandi sono verdi. Il gate umano, alla prima milestone (tipicamente ogni tre-cinque PR), rilegge i contratti. Se `#3` ha reso evidente che una `Decision` deve portare un tempo di scadenza, si aggiorna prima la specifica di `#2` e delle issue sui connettori, e solo dopo le si rimette `ready`.

---

## 3. Caso brownfield: Uptime Kuma

### Contesto e modifica scelta

[Uptime Kuma](https://github.com/louislam/uptime-kuma) è uno strumento self-hosted di monitoraggio, scritto in JavaScript, con frontend Vue 3 in `src/` e backend Node.js in `server/`. Il repository pubblico, ispezionato in sola lettura sul branch predefinito `master` il 27 novembre 2026 (ora di Europe/Rome), si presenta come un prodotto maturo: decine di tipi di monitor, più di novanta canali di notifica, test automatici di backend e una suite end-to-end Playwright. La versione dichiarata in `package.json` è `3.0.0-beta.3`.

Questa sezione è un esercizio di metodo. Non è una proposta di contributo al progetto ufficiale e non è stata aperta alcuna issue o pull request sul repository. Il progetto, peraltro, chiede esplicitamente che ogni modifica sia compresa, recensita e provata da una persona prima di essere proposta: il gate umano, in un brownfield che non ci appartiene, non è un optional.

La modifica realistica che usiamo come filo conduttore è un **limite in uscita sulle notifiche**, per ridurre le raffiche quando molti monitor cambiano stato insieme, per esempio durante un'interruzione di rete. Oggi il cammino è diretto e già ben strutturato, ma non ha un tetto globale in uscita:

- In [server/server.js](https://github.com/louislam/uptime-kuma/blob/master/server/server.js) il backend inizializza i provider con `Notification.init()`.
- [server/notification.js](https://github.com/louislam/uptime-kuma/blob/master/server/notification.js) registra una lista esplicita di provider e, in `Notification.send()`, inoltra subito a `this.providerList[notification.type].send(...)`. Se il tipo non esiste, solleva `Error("Notification type is not supported")`.
- Ogni provider estende [server/notification-providers/notification-provider.js](https://github.com/louislam/uptime-kuma/blob/master/server/notification-providers/notification-provider.js).
- Il chiamante principale è [server/model/monitor.js](https://github.com/louislam/uptime-kuma/blob/master/server/model/monitor.js): `Monitor.sendNotification()` costruisce il messaggio e, per ogni notifica associata al monitor, chiama `Notification.send()`, isolando gli errori per provider. Una notifica parte solo se `Monitor.isImportantForNotification()` considera il battito importante, in pratica sui passaggi di stato rilevanti (`UP → DOWN`, `DOWN → UP`, `PENDING → DOWN`, e il primo battito). Se un monitor resta `DOWN`, il campo già esistente `resendInterval` può rinviare la notifica dopo un certo numero di battiti. Tutto questo va preservato.
- Un rate limiter c'è già, ma serve un altro scopo: [server/rate-limiter.js](https://github.com/louislam/uptime-kuma/blob/master/server/rate-limiter.js) espone `loginRateLimiter` (20 token al minuto) e `apiRateLimiter` (60 token al minuto) per le richieste in ingresso, non per le notifiche in uscita.

I comandi di verifica, dichiarati in `package.json`, in [CONTRIBUTING.md](https://github.com/louislam/uptime-kuma/blob/master/CONTRIBUTING.md) e in [test/backend-test/README.md](https://github.com/louislam/uptime-kuma/blob/master/test/backend-test/README.md), sono questi:

- `npm run test-backend` — suite backend con il test runner di Node.js, file in `test/backend-test/` (inclusa la cartella `test/backend-test/notification-providers/`);
- `npm test` — `test-backend` seguito dai test end-to-end Playwright (`npm run test-e2e`);
- `npm run lint` — ESLint e Stylelint;
- `npm run fmt` — formattazione con Prettier.

Per questa modifica la rete di sicurezza quotidiana è `npm run test-backend`. `npm test` resta il criterio di non regressione più ampio, da usare prima del merge, anche se l'interfaccia in `src/components/notifications/` e `src/components/NotificationDialog.vue` resta fuori perimetro.

### Fase 0: mappare il perimetro e fotografare il comportamento attuale

Nel brownfield il rischio principale non è la divergenza di stile. Sono le regressioni silenziose e le regole che stanno nel codice ma non nella documentazione. Prima di cambiare il comportamento delle notifiche, un agente di sola lettura produce una mappa, e la prima issue di scrittura non aggiunge la nuova regola: aggiunge test di caratterizzazione.

La mappa, nel nostro caso, è già abbastanza chiara e va scritta nell'issue, non tenuta a memoria:

- chiamanti di `Notification.send()`: `Monitor.sendNotification()` e `sendCertNotificationByTargetDays()` nello stesso file `server/model/monitor.js`, più i percorsi di scadenza dominio e di test manuale del canale;
- invarianti da preservare: firma di `Notification.send(notification, msg, monitorJSON = null, heartbeatJSON = null)`; errore su tipo sconosciuto; registrazione dei provider in `Notification.init()` senza omonimi e senza provider privi di `name`; criterio di `isImportantForNotification()`; comportamento di `resendInterval`; isolamento degli errori nel ciclo sui provider;
- punti fragili: `server/notification.js` è un registro monolitico; i test esistenti coprono singoli provider e metodi della classe base (per esempio [test/backend-test/notification-providers/test-smtp.js](https://github.com/louislam/uptime-kuma/blob/master/test/backend-test/notification-providers/test-smtp.js) e [test/backend-test/notification-providers/test-notification-provider.js](https://github.com/louislam/uptime-kuma/blob/master/test/backend-test/notification-providers/test-notification-provider.js), ma non il dispatcher `Notification.send()` in sé;
- debito da non "sistemare" di passaggio: non rifattorizzare la lista dei provider, non toccare il frontend, non unificare i rate limiter di login e API.

### Tre micro-issue reversibili

Le tre issue vanno eseguite in sequenza. Il parallelo, su questa area condivisa, costerebbe più di quanto farebbe risparmiare.

**Issue A — Test di caratterizzazione sul comportamento attuale**

````markdown
## Obiettivo
Fotografare il comportamento attuale di `Notification.init()` e
`Notification.send()` con test backend, senza cambiare la logica di
produzione.

## Dipendenze e perimetro
- Dipende da: nessuna (oltre alla mappa di Fase 0)
- Moduli / cartelle coinvolte: `test/backend-test/`
  (nuovo file, per esempio `test/backend-test/test-notification.js`)
- Fuori ambito: qualsiasi modifica in `server/`, `src/`, `db/`.
  Nessun provider nuovo, nessun ritocco a `resendInterval`, nessun
  cambiamento a `KumaRateLimiter`.

## Specifica
Aggiungere test con `describe()` / `test()` nel formato già descritto
da `test/backend-test/README.md`, che fissino almeno questi comportamenti
oggi veri:

- `Notification.init()` costruisce `providerList` indicizzato su `item.name`;
  ogni provider ha un nome; non ci sono omonimi (altrimenti l'init attuale
  solleva `"Duplicate notification provider name"` o
  `"Notification provider without name"`).
- `Notification.send()` su un oggetto con `type` presente in `providerList`
  delega a `providerList[type].send(...)` e ne restituisce il risultato.
- `Notification.send()` su un `type` sconosciuto solleva
  `Error("Notification type is not supported")`.
- La firma resta `send(notification, msg, monitorJSON = null, heartbeatJSON = null)`:
  si può omettere `monitorJSON` e `heartbeatJSON`.

I test del dispatcher possono usare un provider fittizio iniettato in
`providerList` dopo `init()`, senza chiamare reti reali. I test già presenti
in `test/backend-test/notification-providers/` devono restare invariati e
verdi.

## Contratti / Interfacce
- Nessuna modifica di contratto. Questa issue osserva, non cambia.

## Criteri di accettazione (verificabili)
- [ ] `npm run test-backend` è verde, inclusi i nuovi test e quelli già
      esistenti sui provider.
- [ ] Il diff non contiene file fuori da `test/backend-test/`.
- [ ] `npm run lint` è verde.

## Invarianti da preservare
- API pubbliche dei provider, formato dei messaggi, criterio di
  `isImportantForNotification()`, `resendInterval`.

## Divieto di refactoring opportunistico
L'agente non "ripulisce" `server/notification.js`, non riorganizza la
lista dei provider e non rinomina test esistenti.

## Strategia di rollback
Revert della pull request. Non essendoci cambi di produzione, il
rollback non ha effetto sul comportamento runtime.

## Limiti per l'agente
- Se un comportamento osservato contraddice questa specifica, fermarsi
  e applicare `needs-spec-update`. Non "correggere" il codice di
  produzione per far coincidere il test con l'aspettativa.
````

**Issue B — Seam di disaccoppiamento, senza cambiare il comportamento**

````markdown
## Obiettivo
Introdurre un punto di estensione davanti a `Notification.send()` in
`server/notification.js`, lasciando invariato il comportamento osservabile
fissato dall'issue A.

## Dipendenze e perimetro
- Dipende da: issue A
- Moduli / cartelle coinvolte: `server/notification.js` e, se serve un
  oggetto policy nullo, un file nuovo e minimo accanto ad esso.
  Test in `test/backend-test/`.
- Fuori ambito: frontend (`src/`), schema del database, `server/rate-limiter.js`,
  `server/model/monitor.js`, nuovi canali in
  `server/notification-providers/`.

## Specifica
- `Notification.send()` continua a: (1) rifiutare i tipi sconosciuti con
  lo stesso errore, (2) delegare al provider registrato, (3) restituire
  la stessa stringa o lo stesso errore del provider.
- Prima della delega al provider, `send()` consulta un adattatore di
  policy in uscita. Nella configurazione predefinita l'adattatore
  consente sempre l'invio: è un no-op.
- L'adattatore è sostituibile nei test (iniezione o hook equivalente,
  nello stile già usato dal codice, senza introdurre un framework nuovo).
- `Monitor.sendNotification()` e gli altri chiamanti non cambiano firma
  e non devono essere modificati, salvo un import che si rivelasse
  strettamente necessario. Se la necessità emerge, è un segnale per
  `needs-spec-update`, non per allargare il diff.

## Contratti / Interfacce
- La firma pubblica `Notification.send(notification, msg, monitorJSON = null,
  heartbeatJSON = null)` non cambia.
- `Notification.init()` resta il punto di registrazione dei provider.

## Criteri di accettazione (verificabili)
- [ ] Tutti i test di caratterizzazione dell'issue A restano verdi
      senza cambiamenti di asserzione.
- [ ] Un test nuovo mostra che, con la policy predefinita, la delega al
      provider avviene come prima.
- [ ] Un test nuovo mostra che una policy iniettata può intercettare
      l'invio; questo test esiste per dimostrare il seam, ma la policy
      predefinita in produzione non intercetta nulla.
- [ ] `npm run test-backend` e `npm run lint` sono verdi.
- [ ] Il diff è minimo: niente riformattazioni di lista provider, niente
      rinomine, niente "pulizie" adiacenti.

## Invarianti da preservare
- Stessi errori, stessa delega, stessi provider, stessi chiamanti.

## Divieto di refactoring opportunistico
Non consolidare i `require` dei provider, non fondere questo seam con
`KumaRateLimiter`, non spostare file "per chiarezza".

## Strategia di rollback
Revert della pull request. Se il revert sembra rischioso, è sufficiente
ripristinare in `send()` la delega diretta al provider: il seam non deve
avere effetti se rimosso.

## Limiti per l'agente
- Non attivare alcun limite reale in questa issue.
- Non modificare i provider esistenti.
````

**Issue C — Limite in uscita, disattivato per default, con invarianti e rollback**

````markdown
## Obiettivo
Usare il seam dell'issue B per introdurre un limite opzionale sugli invii
di notifica, così che una raffica di cambi di stato non saturi un canale.
Con la configurazione predefinita il comportamento resta identico a quello
attuale.

## Dipendenze e perimetro
- Dipende da: issue B
- Moduli / cartelle coinvolte: seam introdotto in issue B,
  `server/notification.js`, test in `test/backend-test/`.
  Riutilizzo concettuale di `KumaRateLimiter` solo se si può fare senza
  alterare `loginRateLimiter` e `apiRateLimiter`.
- Fuori ambito: UI in `src/components/NotificationDialog.vue` e
  `src/components/notifications/`; modifiche a `resendInterval` e a
  `isImportantForNotification()`; nuovi provider; migrazioni database.

## Specifica
- Se il limite non è configurato, oppure è configurato come disattivo,
  ogni `Notification.send()` ammesso dal tipo continua a raggiungere il
  provider.
- Se il limite è attivo, si applica per chiave `(notification.type,
  notification.name o id, monitor id se disponibile)` su una finestra
  temporale esplicita (esempio: N invii al minuto). Gli invii oltre soglia
  non raggiungono il provider: vengono scartati e registrati in log,
  senza far fallire `Monitor.sendNotification()`.
- Il limite non sostituisce `isImportantForNotification()` né
  `resendInterval`: interviene dopo, solo sull'invio effettivo.
- Un invio di test del canale (messaggio generale senza `monitorJSON` e
  senza `heartbeatJSON`, come già previsto in CONTRIBUTING.md) non viene
  silenziato dal limite, oppure ha una chiave distinta, così che il
  pulsante di test resti utilizzabile.

## Contratti / Interfacce
- Nessuna modifica alla firma di `Notification.send()`.
- Nessuna modifica a `loginRateLimiter` o `apiRateLimiter`.

## Criteri di accettazione (verificabili)
- [ ] Con limite disattivo, i test di caratterizzazione dell'issue A e i
      test del seam dell'issue B restano verdi senza cambi di asserzione.
- [ ] Con limite attivo, i test dimostrano: invio sotto soglia, scarto
      oltre soglia, isolamento tra chiavi diverse, e che un tipo
      sconosciuto continua a sollevare
      `"Notification type is not supported"`.
- [ ] I test in `test/backend-test/notification-providers/` restano verdi.
- [ ] `npm run test-backend` e `npm run lint` sono verdi. Prima del merge,
      anche `npm test`, per escludere regressioni end-to-end accidentali.

## Invarianti da preservare
- Firma pubblica di `Notification.send()`.
- Semantica di `isImportantForNotification()` e di `resendInterval`.
- Isolamento degli errori per provider in `Monitor.sendNotification()`.
- Comportamento di login e API rate limit.
- Formato dei messaggi e contratti dei provider esistenti.

## Divieto di refactoring opportunistico
Non "ripulire" `server/model/monitor.js`, non unificare i limiter, non
aggiungere opzioni in interfaccia "visto che ci siamo". Se serve una
schermata di configurazione, è una issue successiva.

## Strategia di rollback
1. Disattivare il limite dalla configurazione: si torna al no-op del seam.
2. Se non basta, revert della pull request C; il seam dell'issue B può
   restare, perché è privo di effetti con la policy predefinita.

## Limiti per l'agente
- Non migrare il database e non cambiare lo schema delle notifiche salvate.
- Non modificare i file dei singoli provider.
- Se il posto giusto per la configurazione risulta ambiguo, fermarsi e
  applicare `needs-spec-update`.
````

### Come valida il Validatore, in un brownfield

Il Validatore non discute l'eleganza del disegno se il disegno non era in specifica. Guarda il diff e si chiede, in quest'ordine: i test di caratterizzazione sono ancora veri? È stato toccato qualcosa fuori perimetro, per esempio un provider o un componente Vue? I test nuovi potrebbero essere verdi anche se il limite non funziona (asserzioni deboli, clock non controllato, provider fittizio che non viene mai chiamato)? Il rollback è davvero un interruttore, o il limite è diventato invisibile e permanente? `resendInterval` e `isImportantForNotification()` sono rimasti intatti?

Due giri di correzione sono sufficienti. Al terzo fallimento il lavoro torna a una persona, che rilegge anche la specifica: a volte è la specifica, non l'agente, a essere troppo larga.

---

## 4. Confronto e principi operativi

| Dimensione | Greenfield (Approval Gate) | Brownfield (Uptime Kuma) |
| --- | --- | --- |
| Rischio principale | Divergenza tra agenti su tipi, stati e confini | Regressioni e regole implicite già presenti nel codice |
| Fase 0 | Contratti condivisi, schema, CI verde, moduli vuoti ma importabili | Mappa dei chiamanti e test di caratterizzazione, senza cambiare il runtime |
| Taglio delle issue | Fette verticali per modulo, dopo il bootstrap | Micro-passi reversibili: fotografare, disaccoppiare, poi cambiare |
| Parallelismo | Ammesso dopo il bootstrap, su cartelle disgiunte | Conservativo: in sequenza su un'area condivisa come `Notification.send()` |
| Regola d'oro per l'Esecutore | Rispettare i contratti di Fase 0, non allargarli in silenzio | Diff minimo, zero refactoring non richiesto, invarianti dichiarati |
| Focus del Validatore | Aderenza alla specifica, semplicità, qualità reale dei test | Non regressione, perimetro rispettato, rollback effettivamente usabile |
| Rollback | Rimuovere o non mergiare la fetta: non c'è ancora carico in produzione | Interruttore o revert, con un comportamento predefinito identico all'esistente |

Cinque regole bastano per adottare il metodo in un team, senza aggiungere una cerimonia nuova ogni settimana.

1. **Nessun agente scrive codice di business prima che la Fase 0 sia mergiata.** In un progetto nuovo la Fase 0 sono i contratti e la CI. In un progetto esistente sono la mappa e i test che fotografano l'oggi. Se questa regola viene saltata, il resto del processo diventa teatro.

2. **Una issue, un perimetro, un comando che sa dire se è finita.** L'obiettivo in prosa non è un criterio di accettazione. Lo è `pytest tests/policy/`, lo è `npm run test-backend`. Se il criterio non è eseguibile, l'Esecutore chiuderà la pull request appena il codice compila, e il Validatore non avrà una base su cui bocciare.

3. **Il Validatore non è un secondo Esecutore.** Parte da zero, legge solo specifica, diff e test, e ha il mandato di falsificare. Se usa lo stesso contesto, gli stessi strumenti e lo stesso incentivo a "chiudere", confermerà gli stessi errori. Due giri, poi si scala a una persona.

4. **Quando il codice smentisce una specifica, si ferma il lavoro, non si adatta la realtà in silenzio.** L'etichetta `needs-spec-update` esiste per questo. Dopo un merge che cambia un assunto — un nuovo campo in `Decision`, un significato diverso di `Notification.send()` — il gate umano rilegge le issue ancora aperte e aggiorna quelle a valle prima che il Selettore le riassegni. Una coda di specifiche non aggiornata è peggio di una coda vuota: dà agli agenti una certezza falsa.

5. **Il merge resta umano, soprattutto quando l'effetto è reale.** Gli agenti possono selezionare, implementare e contestare. Non decidono quando una policy di approvazione entra in servizio, né quando un limite sulle notifiche inizia a scartare allarmi. Il gate umano è il punto in cui il team accetta la responsabilità del cambiamento. Tutto il metodo serve a rendere quella decisione informata, non a sostituirla.

Il valore del metodo non sta nella novità dei ruoli. Sta nella disciplina con cui si taglia il lavoro. Un agente è utile quando la specifica è stretta, il test è onesto e qualcuno, alla fine, ha ancora il diritto di non mergiare.
