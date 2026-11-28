> Classe di rischio: piena (riferimento di parità per l'online). Riallineata il 28 novembre 2026: è il primo passo del pilota online (`COSGN00C`), che segue il pilota batch (registro delle approvazioni, voce 86).

## Obiettivo
Definire il formato della matrice di comportamento, cioè il riferimento per i programmi online che non si possono eseguire fuori da CICS, e compilarla per il programma pilota `COSGN00C` (accesso, transazione `CC00`).

## Dipendenze e perimetro
- Dipende da: #2 (inventario), #3 (contratto dati), #22 (comandi `EXEC CICS` del programma: `docs/legacy-map/inventario-cics.md` e `graph-cics.json`, da usare come elenco di partenza e da non riscrivere), #23 (regole di codifica, per i campi della COMMAREA e del record utente).
- Sorgenti legacy di riferimento: `app/cbl/COSGN00C.cbl`, `app/bms/COSGN00.bms`, `app/cpy-bms/COSGN00.CPY`, `COCOM01Y`, `CSUSR01Y`, `CSMSG01Y`, `COTTL01Y`, `CSDAT01Y`.
- Cartelle coinvolte: `analysis/behavior/`, `docs/legacy-map/behavior/`.
- Fuori ambito: gli altri programmi online (una issue ciascuno in Wave 3); codice Java.

## Specifica
**Primo livello: decisioni.** Si elencano tutti i punti di decisione del programma (`IF`, `EVALUATE`, controlli sui codici di risposta), ciascuno con un identificatore stabile, riga del sorgente e le sue alternative.

**Secondo livello: casi.** Ogni caso ha:
- ingresso: COMMAREA (`EIBCALEN` e campi di `COCOM01Y`), tasto premuto, campi della mappa, record presenti nei file, **ambiente** (data e ora, identificativi restituiti da `EXEC CICS ASSIGN`), **risposta simulata** di ogni comando CICS con `RESP` (per esempio lettura riuscita, record non trovato, altro errore);
- esito: campi e messaggio sulla mappa, attributi rilevanti, operazioni sui file nell'ordine, **confini di transazione** (lettura per aggiornamento, `SYNCPOINT`, rollback, se presenti), COMMAREA in uscita, trasferimento di controllo;
- alternative coperte: gli identificatori delle decisioni che il caso attraversa;
- riferimento al sorgente.

Un esito non deducibile dal sorgente si scrive "non determinabile dal sorgente" e quella parte **non** conta come coperta: va elencata tra i limiti di parità.

Il formato è machine-readable: in Wave 2 e 3 ogni caso diventa un test.

## Invarianti da preservare
- La matrice descrive ciò che il COBOL fa, anche quando è discutibile.

## Criteri di accettazione (verificabili)
- [ ] `./analysis/run.sh behavior --check` passa: schema valido; ogni riga citata esiste; **ogni alternativa di ogni decisione è coperta da almeno un caso** oppure marcata irraggiungibile con motivo; ogni `EXEC CICS` del programma compare in almeno un esito.
- [ ] L'elenco delle decisioni è confrontato dal controllo con un conteggio indipendente di `IF` / `EVALUATE` / `WHEN` nella `PROCEDURE DIVISION`.
- [ ] Esistono almeno i casi: primo ingresso, utente inesistente, password errata, accesso riuscito come amministratore e come utente, tasto non valido, campi obbligatori vuoti.
- [ ] Il diff tocca solo le cartelle dichiarate.
- [ ] Formato e matrice pilota approvati dall'Approvatore, dopo la validazione, prima di aprire le matrici degli altri programmi.
- [ ] Ogni prova negativa è riportata con nome e diagnosi; `./analysis/run.sh --all --check` esce con 0; CI verde sullo SHA finale.

## Strategia di rollback
Revert della PR.

## Limiti per l'agente
- Non supporre il comportamento del runtime CICS. Non semplificare un ramo perché sembra un errore.


- Unico prerequisito dell'host: Docker e Git. Autocontrollo delle quattro famiglie prima della PR (`paper/data/prompts/esecutore.md`). File di appoggio sull'host con prefisso `issue11-`.
- Se il sorgente smentisce la specifica: fermarsi, commento tecnico, `needs-spec-update`.
