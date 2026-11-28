> Classe di rischio: piena (oracle, dati). Ristretta al solo file dei conti per la decisione "prima il pilota" (registro delle approvazioni, voce 86).

## Obiettivo

Mettere nell'oracle GnuCOBOL il file indicizzato dei conti (`ACCTFILE`), con lo stesso contenuto che sul mainframe vi carica `app/jcl/ACCTFILE.jcl`, e dimostrare rileggendolo che contiene esattamente quei record, in ordine di chiave. È l'ingresso del programma pilota `CBACT01C` (#55).

## Dipendenze e perimetro

- Dipende da: #5 (fixture verificate, mergiata), #23 (regole di codifica, mergiata), #36 (routine `MVSWAIT`: la sua PR modifica gli elenchi `PROVE` e `ACCESSORI` della build dell'oracle, che questa issue può dover toccare; si parte dopo il suo merge).
- Sorgenti di riferimento: `app/jcl/ACCTFILE.jcl` (`DEFINE CLUSTER` con `KEYS(11 0)` e `RECORDSIZE(300 300)`, `REPRO` da `AWS.M2.CARDDEMO.ACCTDATA.PS`), `app/cpy/CVACT01Y.cpy`, `app/cbl/CBACT01C.cbl` (righe 29-33 e 52-56: `SELECT` e `FD` del file), `app/data/EBCDIC/AWS.M2.CARDDEMO.ACCTDATA.PS`, `app/data/ASCII/acctdata.txt`.
- Cartelle ammesse: `analysis/oracle-dati/**` (nuova analisi), `oracle/dati/**` (nuovo passo dell'oracle), `oracle/README.md`, `docs/legacy-map/oracle-dati.md` (documento generato). Se serve un programma di prova nuovo: `oracle/tests/<nome>.cbl` e le sole righe degli elenchi `PROVE` (`oracle/build/compile.sh`) e `ACCESSORI` (`oracle/build/check.sh`). In ogni caso: l'aggiunta di `dati` all'elenco fisso `PASSI` di `oracle/build/check.sh`, così che la cancellazione della cartella del nuovo passo sia rilevata.
- Fuori ambito: gli altri file indicizzati; l'esecuzione di `CBACT01C` sui conti caricati (#55; la prova di avvio preesistente, senza dati, resta com'è); qualsiasi modifica a `legacy/`, a `oracle/esegui.sh`, alle analisi esistenti, agli attesi esistenti; indici alternativi (il file dei conti non ne ha in `ACCTFILE.jcl`).

## Specifica

### Decisione sul contenuto (delegata, da registrare)

I due file di esempio dei conti non concordano: nel record con chiave 49 il campo `ACCT-ADDR-ZIP` vale `A000000000` in `acctdata.txt` e `ZEROAPR   ` in `AWS.M2.CARDDEMO.ACCTDATA.PS` (`docs/legacy-map/fixture.md`). Il repository non spiega la differenza. Si carica **il contenuto del file EBCDIC**, perché è quello che `ACCTFILE.jcl` carica nel KSDS (`REPRO INFILE(ACCTDATA)`, DD alla riga 57). Il file ASCII serve da controprova.

### Parte 1 — record nel profilo dell'oracle (`analysis/oracle-dati/`)

- L'oracle lavora su dati ASCII (profilo `oracle-gnucobol`). I 50 record EBCDIC si portano in quel profilo **campo per campo** con la libreria di #23 (`analysis/data-codec/glue/codec.py`, importata e non modificata) guidata dal contratto `CVACT01Y.ACCOUNT-RECORD` attraverso l'adattatore di #43: decodifica con `zos-ebcdic`, ricodifica con `oracle-gnucobol`. Nessuna conversione di caratteri sull'intero record, nessuna regola di codifica riscritta. Un campo non valido o non ricodificabile ferma la generazione.
- Uscita versionata: `analysis/oracle-dati/out/ACCTFILE.rec`, 50 record di 300 byte senza terminatori (15.000 byte), nell'ordine del file d'origine, più un elenco leggibile (record, chiave, impronta).
- La generazione è guidata da una tabella scritta a mano con una riga per file (oggi una sola): DD, file d'origine, contratto, posizione e lunghezza della chiave con il riferimento al JCL, lunghezza del record con il riferimento al JCL. Aggiungere un file in futuro significa aggiungere una riga e i suoi attesi.
- Controlli della parte 1, ciascuno con prova negativa:
  1. lunghezza del record e chiave della tabella coincidono con `ACCTFILE.jcl` (rilette dal JCL) e con il contratto;
  2. ogni campo del record prodotto, ridecodificato con `oracle-gnucobol`, ha stato e valore uguali a quelli della fixture EBCDIC di #5 (`analysis/data-fixtures/out/AWS.M2.CARDDEMO.ACCTDATA.PS.tsv`, letta e non rigenerata);
  3. controprova con il file ASCII: i 50 record prodotti coincidono byte per byte con i record di `acctdata.txt` (letti dal file legacy, senza terminatori) **tranne** i 10 byte di `ACCT-ADDR-ZIP` del record con chiave 49; il controllo pretende esattamente quella differenza, con quei byte, e nessun'altra;
  4. le chiavi sono 50, uniche, strettamente crescenti nell'ordine del file. Se non lo sono, fermarsi con `needs-spec-update`: `REPRO` su un KSDS vuoto richiede chiavi crescenti e il comportamento del legacy andrebbe deciso;
  5. cinque record con chiavi distinte, scelti e scritti a mano prima della generazione (primo, ultimo, il 49 e due a scelta; nei dati non esistono importi negativi, e va dichiarato nel documento: questo file non esercita il segno negativo), come byte attesi nel profilo dell'oracle ricavati dai byte EBCDIC con la tabella della pagina 037 e la regola del segno di #23; committati prima della colla.

### Parte 2 — caricamento e rilettura (`oracle/dati/`)

- Nuovo passo `./oracle/run.sh dati [--check]`. Carica `ACCTFILE.rec` in un file indicizzato GnuCOBOL con organizzazione, chiave e lunghezza del `SELECT`/`FD` di `CBACT01C` (chiave `9(11)` nei byte 1-11, record di 300 byte), e lo rilegge in ordine di chiave.
- `IDXLOAD` di #25 non basta così com'è: riempie con spazi le righe più corte del record e non controlla lo stato di chiusura dell'ingresso (`oracle/tests/IDXLOAD.cbl`, righe 126-154), e #25 non va modificato. Si aggiunge un programma di prova che legge record a lunghezza fissa di 300 byte, non riempie e non tronca, e controlla ogni stato di file. `IDXDUMP` si riusa solo se rilegge senza alterare e controlla gli stati; altrimenti un secondo programma di prova, dichiarandolo. Un ingresso la cui dimensione non è un multiplo esatto di 300 è un errore.
- Rilettura: il file riletto, record per record in ordine di chiave, è identico byte per byte a `ACCTFILE.rec`; i record sono 50; dopo l'ultimo la lettura dà fine file (stato 10). Stati di file di apertura, scrittura, lettura e chiusura controllati uno per uno.
- Il file indicizzato prodotto resta disponibile ai passi successivi con un percorso stabile e documentato (lo userà #55 con `--dd DD_ACCTFILE=<percorso visto dal container>`); è un artefatto generato, non versionato, cancellato e ricreato a ogni corsa, come fa il JCL (`DELETE` prima di `DEFINE`).
- Atteso versionato del passo: rapporto con numero di record, prima e ultima chiave, impronta della rilettura.
- Ordinamento: la chiave è numerica `DISPLAY` senza segno; cifre ASCII ed EBCDIC hanno lo stesso ordine. Dichiararlo in documentazione come motivo per cui l'ordine di chiave dell'oracle coincide con quello del mainframe per questo file; non vale in generale per chiavi alfanumeriche.

### Prove negative richieste (oltre a quelle dei controlli della parte 1)

Ogni prova fa fallire il comando per il motivo dichiarato, poi ripristina: un record tolto da `ACCTFILE.rec`; due record scambiati (chiave non crescente: il caricamento deve fermarsi); una chiave duplicata; un byte alterato in un campo numerico e uno nel `FILLER`; file troncato a metà record; la differenza del record 49 annullata (ZIP ASCII al posto di quello EBCDIC); una seconda differenza introdotta rispetto al file ASCII; il programma di caricamento che esce con errore; il programma di rilettura che si ferma un record prima; un record di 299 byte ottenuto togliendo uno spazio finale del `FILLER` (non deve essere riempito); residui: (a) un file indicizzato rimasto da una corsa precedente con contenuto diverso, seguito da una corsa regolare, deve dare successo e contenuto corretto; (b) un file indicizzato sano rimasto, seguito da un caricamento che fallisce, deve dare errore e non lasciare alcun file utilizzabile come risultato corrente; la cartella `oracle/dati/` cancellata (deve accorgersene il controllo di presenza dei passi); la tabella con chiave o lunghezza diverse dal JCL.

## Invarianti di parità

- Il contenuto caricato è quello del file che il JCL carica, non una sua correzione: nessun valore riparato, nessun campo normalizzato, `FILLER` compreso.
- Stesso numero di record, stesse chiavi, stesso ordine di chiave.

## Criteri di accettazione

1. `./analysis/run.sh oracle-dati` e `./analysis/run.sh oracle-dati --check` (due volte) escono con 0; la rigenerazione non cambia i file versionati.
2. `./oracle/run.sh dati` e `./oracle/run.sh dati --check` (due volte) escono con 0.
3. `./oracle/run.sh --all --check` e `./analysis/run.sh --all --check` escono con 0; nessun atteso preesistente cambiato, nessuna prova preesistente con esito diverso.
4. Ogni prova negativa è riportata con nome e diagnosi; il numero di prove locale coincide con quello della CI.
5. `git status --short` vuoto dopo i comandi; `legacy/` invariato; diff nel solo perimetro ammesso.
6. CI verde sullo SHA finale (`analysis-check`, `oracle-check`, `verify`, `smoke`).
7. Storia Git: gli attesi a mano del controllo 5 e la tabella sono committati prima della colla.

## Strategia di rollback

Revert della PR: si tolgono un'analisi e un passo dell'oracle; nessun altro passo ne dipende finché #55 non è avviata.

## Limiti per l'agente

- Unico prerequisito dell'host: Docker e Git. Niente Perl, Python o altro sull'host.
- Una sola issue: non eseguire `CBACT01C`, non caricare altri file.
- Se il sorgente o i dati smentiscono la specifica: fermarsi, commento tecnico, `needs-spec-update`.
- Autocontrollo delle quattro famiglie prima della PR (`paper/data/prompts/esecutore.md`). File di appoggio sull'host con prefisso `issue53-`.
