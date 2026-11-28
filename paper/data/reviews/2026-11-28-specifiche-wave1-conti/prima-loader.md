> Classe di rischio: piena (dati). Wave 1, ristretta al file dei conti (registro delle approvazioni, voce 86).

## Obiettivo

Caricare nella tabella `account` gli stessi conti che l'oracle legge, a partire dallo stesso file di record, e dimostrare che ciò che sta in PostgreSQL corrisponde record per record a quel file.

## Dipendenze e perimetro

- Dipende da: l'issue della tabella `account`; #53 (file `analysis/oracle-dati/out/ACCTFILE.rec`: 50 record di 300 byte nel profilo dell'oracle); #54 (codifica dei campi in Java, mergiata).
- Cartelle ammesse: `carddemo-loader/**`, `carddemo-parity/**` (test), `compose.yaml` e `docker/**` solo per il servizio di caricamento, `smoke.sh` solo per verificare il caricamento, `docs/contratti.md`, `docs/sviluppo.md`, i `pom.xml` strettamente necessari.
- Fuori ambito: gli altri file; la lettura dei conti da parte di programmi tradotti; qualsiasi modifica ad `analysis/`, `oracle/`, `legacy/`.

## Specifica

- **Ingresso**: un file di record a lunghezza fissa di 300 byte nel profilo dell'oracle, indicato come parametro. Il caricatore non è legato al file di esempio: lo stesso comando caricherà i file degli scenari costruiti per la parità (#55).
- **Decodifica**: ogni campo con `GnuCobolFieldCodec` (#54) e il tracciato del contratto `CVACT01Y.ACCOUNT-RECORD`, letto dal repository in fase di build o riportato in una tabella il cui controllo lo confronta con il contratto. Nessuna regola di codifica riscritta.
- **Che cosa ferma il caricamento** (nessuna riga scritta, transazione annullata, codice di uscita diverso da 0, diagnosi con numero di record e campo): dimensione non multipla di 300; campo numerico non valido; chiave duplicata; carattere non rappresentabile in una colonna di testo (per esempio il byte nullo).
- **Che cosa si carica segnalandolo** in un rapporto (file, record, campo, byte originali, valore caricato): (a) rappresentazione non canonica di un valore numerico, per esempio lo zero con segno negativo: si carica il valore; (b) `FILLER` diverso da 178 spazi: non ha colonna. Il rapporto è l'elenco esatto di ciò che la tabella non conserva.
- **Decisione delegata, da registrare**: per i record nel rapporto la parità byte per byte delle uscite non è garantita nelle posizioni che derivano da quei campi; l'elenco entra nella tabella delle posizioni escluse del riferimento (#55) con questo motivo. Alternativa scartata: conservare nella tabella i byte originali del record (renderebbe PostgreSQL un deposito di byte per tutti i programmi successivi).
- **Riesecuzione**: il caricamento su una tabella non vuota si ferma con errore; non cancella e non aggiorna. (Sul mainframe `ACCTFILE.jcl` cancella e ricrea il file: l'equivalente è ricreare il database, e va documentato.)
- **Ordine**: tutto in una sola transazione, nell'ordine del file.
- **Servizio**: `docker compose` ha un servizio di caricamento che parte dopo la migrazione, carica `ACCTFILE.rec` (reso disponibile all'immagine in fase di build) e termina; `smoke.sh` verifica 50 righe e la prima e l'ultima chiave.

### Controlli, ciascuno con prova negativa (test contro PostgreSQL reale)

1. Numero di righe uguale al numero di record; insieme delle chiavi uguale.
2. **Ritorno al formato fisso**: da ogni riga, riletta con `ORDER BY acct_id`, un codificatore indipendente dal caricatore (nel test) ricompone il record di 300 byte con `encode` e 178 spazi di `FILLER`; il risultato è uguale byte per byte al record d'ingresso, per tutti i record che non compaiono nel rapporto; per quelli nel rapporto la differenza è esattamente quella dichiarata.
3. Totali di controllo: somma di ciascuna colonna numerica uguale alla somma calcolata dai byte del file con una lettura indipendente (nel test, senza passare dal caricatore).
4. Ordine: la sequenza delle chiavi lette con `ORDER BY acct_id` è la sequenza del file (che #53 garantisce crescente).
5. Casi costruiti nel test (file temporanei): zero negativo; importo massimo e minimo della `PICTURE`; `FILLER` non vuoto; campo numerico con spazi; chiave duplicata; file troncato; byte nullo in un campo di testo; file vuoto (0 record: caricamento riuscito con 0 righe, dichiarato).

Prove negative: due campi di uguale tracciato scambiati nel caricatore (`ACCT-CREDIT-LIMIT` e `ACCT-CASH-CREDIT-LIMIT`); scala sbagliata; segno ignorato; un record saltato; l'ultimo record caricato due volte con chiave alterata; transazione confermata prima dell'errore (deve restare zero righe); rapporto che omette una segnalazione; caricamento su tabella non vuota che riesce.

## Invarianti di parità

- Stessi conti, stessi valori, stesso ordine di chiave del file che legge l'oracle.
- Nessun valore riparato in silenzio: ciò che non si conserva è nel rapporto.
- Importi solo `BigDecimal`.

## Criteri di accettazione

1. `./verify.sh` esce con 0; i test nuovi risultano eseguiti nel rapporto.
2. `./smoke.sh` esce con 0, con il controllo sul caricamento; un caricamento fallito lo rende rosso.
3. Le suite di regressione esistenti toccate dal diff escono con 0.
4. Ogni prova negativa è riportata con nome e diagnosi.
5. `git status --short` vuoto; diff nel solo perimetro.
6. CI verde sullo SHA finale.

## Strategia di rollback

Revert della PR: la tabella resta vuota.

## Limiti per l'agente

- Unico prerequisito dell'host: Docker e Git. Mai un database in memoria.
- Una sola issue: solo il file dei conti.
- Se il contratto, i dati o il codec smentiscono la specifica: fermarsi, commento tecnico, `needs-spec-update`.
- Autocontrollo delle quattro famiglie prima della PR. File di appoggio sull'host con prefisso `issue-w1b-`.
