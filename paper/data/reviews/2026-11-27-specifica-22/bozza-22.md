## Obiettivo

Aggiungere alla mappa del legacy i comandi `EXEC CICS`, che nessuno strumento provato in #1 vede: quali programmi online passano il controllo a quali altri, quali mappe mostrano, quali file leggono e scrivono e in che modo, quali code usano, dove chiudono o annullano una transazione. È la base per il grafo dei flussi (#7) e per la matrice di comportamento online (#11).

Questa issue copre l'**estrazione** dei comandi e i collegamenti con bersaglio scritto nel sorgente. La risoluzione dei bersagli in variabile (tabelle di menu, campi della COMMAREA), l'arco online → batch di `CORPT00C` e le voci di menu verso i moduli opzionali sono nella issue successiva (divisa da questa).

Classe di rischio: **piena** (mappa del legacy e script di verifica). Validazione con Codex.

## Dipendenze e perimetro

- Dipende da: #2 (mergiata: `analysis/inventory/`, `docs/legacy-map/graph.json`, `graph.schema.json`, `inventario.md`).
- File ammessi: `analysis/inventory-cics/**` (nuova analisi: `run.sh`, `check.sh`, `deps`, colla, attesi, file di prova), `docs/legacy-map/graph-cics.json`, `docs/legacy-map/graph-cics.schema.json`, `docs/legacy-map/inventario-cics.md` (tutti nuovi).
- Sola lettura: `analysis/inventory/**`, `docs/legacy-map/graph.json`, `graph.schema.json`, `inventario.md`, `analysis/tools/`, `analysis/lib/`, `analysis/manifest/`, `analysis/run.sh`, `legacy/`. Il grafo di #2 **non si modifica**: i nuovi archi stanno in un file a parte e fanno riferimento ai suoi nodi per identificativo.
- Fuori ambito: bersagli in variabile risolti; `CORPT00C` → batch; semantica dei comandi (condizioni `RESP`, `HANDLE`): si registra che ci sono, non che cosa comportano.

## Specifica

Tutto gira in container, con `./analysis/run.sh inventory-cics` e `--check`, secondo le convenzioni di `analysis/inventory/` (rigenerazione in cartella temporanea dal legacy, confronto con i file versionati, prove negative automatiche che alterano la colla o il grafo).

### Perimetro dei sorgenti

Tutti i sorgenti COBOL del manifesto (`analysis/manifest/sources.tsv`), compresi i moduli opzionali e i copybook: un comando `EXEC CICS` che sta in un copybook appartiene, come occorrenza, al copybook (file e riga), e ogni programma che lo include lo eredita tramite gli archi `COPY` già presenti nel grafo di #2 (stesso trattamento della `CALL` in `CSUTLDPY`, voce 31 del registro). Le righe di commento (indicatore in colonna 7) non contano.

### Estrazione

Prima si verifica, e si scrive in `inventario-cics.md` con la prova, se ProLeap espone i blocchi `EXEC CICS … END-EXEC` con riga e testo: se sì lo si usa. Altrimenti un estrattore proprio, minimo e dichiarato, che legge il formato fisso (colonne 8-72, continuazioni, blocchi su più righe, più comandi sulla stessa riga se esistono) e produce per ogni blocco: file, riga di `EXEC`, riga di `END-EXEC`, comando (prima parola o coppia di parole, per esempio `SEND MAP`, `READ`, `SYNCPOINT ROLLBACK`), elenco ordinato delle opzioni con il loro argomento testuale.

### Occorrenze e archi

`graph-cics.json` contiene una occorrenza per **ogni** blocco estratto, nessuno escluso, con il suo comando. Per le categorie seguenti l'occorrenza porta in più gli attributi indicati e, dove il bersaglio è un letterale, un arco verso il nodo corrispondente:
- **trasferimento di controllo**: `XCTL`, `LINK`, `START`, `RETURN` (con e senza `TRANSID`): opzione `PROGRAM` o `TRANSID`; arco verso `program:<nome>` o `transaction:<nome>` del grafo di #2 se esiste, altrimenti verso un nodo `external:` dichiarato in questo file;
- **mappe**: `SEND MAP`, `RECEIVE MAP`, `SEND TEXT`: `MAP` e `MAPSET` sono due simboli distinti, entrambi registrati;
- **file**: `READ` (con il flag `UPDATE` distinto), `WRITE`, `REWRITE`, `DELETE`, `STARTBR`, `READNEXT`, `READPREV`, `ENDBR`, `RESETBR`, `UNLOCK`: opzione `FILE`/`DATASET`, modalità;
- **code**: `WRITEQ TD`/`TS`, `READQ TD`/`TS`, `DELETEQ`: nome della coda;
- **transazione**: `SYNCPOINT`, `SYNCPOINT ROLLBACK`, `ABEND`.
Ogni altro comando presente (per esempio `ASSIGN`, `HANDLE`, `ASKTIME`, `FORMATTIME`) è un'occorrenza con categoria `altro`: l'elenco dei comandi trovati, con il conteggio, è prodotto dall'estrazione e non scritto a mano.

**Letterale o variabile.** Un argomento tra apici è un letterale. Un argomento che è un nome di dato si risolve **solo** se quel dato ha una clausola `VALUE` con un letterale e nessuna istruzione del programma (o dei suoi copybook) lo modifica; la regola con cui si stabilisce "nessuna istruzione lo modifica" è dichiarata, e i casi dubbi sono non risolti. Ogni altro caso è `non_risolto: true` con il testo dell'operando: registrato, mai omesso, mai indovinato. La risoluzione è nella issue successiva.

### Controlli

- **Conteggio indipendente**: il numero di blocchi `EXEC CICS` per file è ricontato con un mezzo indipendente dall'estrattore (altro strumento o altro linguaggio, criterio dichiarato) e confrontato file per file; idem il numero di occorrenze per comando sul totale.
- **Due direzioni, senza sovrascritture** (lo schema di difetto che ha tenuto aperta la PR #30 per tre giri): ogni blocco estratto ha esattamente una occorrenza e ogni occorrenza ha esattamente un blocco; ogni arco ha il bersaglio confrontato per intero (tipo e nome) con il blocco e con il manifesto o il grafo di #2; identificativi unici; nessun nodo nuovo senza arco.
- **Attesi a mano** leggendo il sorgente, con file e riga, per l'elenco completo dei blocchi di quattro programmi: `COSGN00C`, `COMEN01C`, `COCRDSLC`, `CORPT00C`, più un copybook che contiene comandi CICS se ne esiste uno. Si scrivono prima di guardare l'output dell'estrattore; ciò che l'output smentisce si riferisce, non si adatta.
- **Riferimenti**: ogni identificativo di nodo citato esiste in `graph.json` o è dichiarato in `graph-cics.json`; `graph-cics.json` è valido rispetto al suo schema.
- **Prove negative** automatiche, ciascuna deve fallire per il motivo dichiarato: un blocco tolto dall'estrazione; un blocco in più; un comando classificato in un'altra categoria; un bersaglio letterale cambiato; un bersaglio variabile fatto passare per risolto; `READ` e `READ UPDATE` scambiati; `MAP` e `MAPSET` scambiati; un arco verso un nodo inesistente; un'occorrenza duplicata sulla stessa riga; una risposta vuota o malformata dello strumento di estrazione; un blocco in una riga di commento contato come vero.

`inventario-cics.md` (generato, non scritto a mano) riporta: comandi trovati con conteggio; per programma, trasferimenti, mappe, file con modalità, code, punti di `SYNCPOINT`; elenco dei bersagli non risolti con operando; limiti.

## Invarianti di parità

- Nessun collegamento indovinato: ciò che non è determinato dal testo del sorgente con la regola dichiarata resta non risolto.
- Il grafo di #2 e i suoi controlli restano invariati e verdi.

## Criteri di accettazione

- [ ] `./analysis/run.sh inventory-cics` termina con 0 e rigenera senza differenze i file versionati; `run.sh`, `check.sh`, `deps` esistono e sono eseguibili.
- [ ] `./analysis/run.sh inventory-cics --check` termina con 0 due volte di seguito, con ogni prova negativa riportata con nome e motivo.
- [ ] `./analysis/run.sh --all --check` termina con 0.
- [ ] `git status --short` vuoto dopo i controlli; `legacy/` invariato; `git diff --name-only origin/main...HEAD` elenca solo file ammessi.
- [ ] CI verde, compreso `analysis-check`.

## Strategia di rollback

Revert del commit di merge: i tre file nuovi e la cartella dell'analisi spariscono; il grafo di #2 non è stato toccato.

## Limiti per l'agente

- Regole comuni alle analisi: sorgenti dal manifesto, mai da un glob; legacy letto dal volume Docker sensibile alle maiuscole; immagini e volumi condivisi non si rimuovono né si ricostruiscono con modifiche; nessun comando Docker globale.
- Negli script ogni comando ha l'esito controllato (attenzione a `$(...)` dentro altri comandi e a `echo … | grep -q` sotto `pipefail`, difetti già trovati in questo repository); limite di tempo sui comandi che possono restare in attesa; nessun residuo di una corsa precedente può soddisfare un controllo; la risposta di ogni strumento è validata a ogni invocazione.
- Autocontrollo prima della PR come da `paper/data/prompts/esecutore.md`. File di appoggio dell'agente sull'host con prefisso `issue22-`. Non mergiare.
