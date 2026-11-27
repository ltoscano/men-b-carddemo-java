## Obiettivo

Trasformare i file dati forniti con CardDemo in **fixture verificate**: per ogni file, i record decodificati campo per campo, con le anomalie elencate e nessun valore riparato. È la base dei dati d'ingresso per l'oracle (caricamento: issue successiva, divisa da questa) e per il loader Java (Wave 1).

Classe di rischio: **piena** (dati). Validazione con Codex.

## Dipendenze e perimetro

- Dipende da: #3 (contratti e file: `docs/legacy-map/data-contract/`), #23 (regole di codifica: `analysis/data-codec/glue/codec.py`, profili `oracle-gnucobol` e `zos-ebcdic`), #43 (i contratti dei copybook sono verificati dalle sentinelle).
- Sorgenti di riferimento (sola lettura): `app/data/ASCII/` (9 file), `app/data/EBCDIC/` (13 file, compresi `…DALYTRAN.PS.INIT`, `…USRSEC.PS`, `…EXPORT.DATA.PS`, e i due file conti `…ACCDATA.PS` e `…ACCTDATA.PS`), i JCL che definiscono e caricano i file (`ACCTFILE`, `CARDFILE`, `CUSTFILE`, `XREFFILE`, `TRANFILE`, `TCATBALF`, `DISCGRP`, `TRANTYPE`, `TRANCATG`, `DUSRSECJ`).
- File ammessi: `analysis/data-fixtures/**` (nuova analisi: `run.sh`, `check.sh`, `deps` con `data-codec`, colla, attesi, fixture prodotte e versionate), `docs/legacy-map/fixture.md` (nuovo, generato).
- Sola lettura: `analysis/data-codec/**`, `analysis/data-contract/**`, `analysis/data-sentinelle/**`, `docs/legacy-map/data-contract/**`, `analysis/tools/`, `analysis/lib/`, `analysis/manifest/`, `analysis/run.sh`, `oracle/`, `legacy/`. Il codec si usa, non si copia né si modifica; l'adattatore contratto → campi di `analysis/data-sentinelle/` si può **riusare importandolo**, non copiandolo; se serve modificarlo, `needs-spec-update`.
- Fuori ambito: il caricamento nei file indicizzati dell'oracle (issue successiva); fixture costruite apposta (#6); esecuzione dei programmi (#9); loader Java.

## Specifica

Comando: `./analysis/run.sh data-fixtures` e `--check`, con le convenzioni delle altre analisi.

### Inventario dei file

Una tabella versionata, scritta a mano e verificata dal controllo: per ogni file di `app/data/ASCII/` e `app/data/EBCDIC/`, il contratto del record (da `docs/legacy-map/data-contract/file.tsv` e dai JCL di caricamento), la lunghezza del record attesa, il file corrispondente nell'altra codifica se esiste, e il JCL che lo carica con la riga. Ogni file presente nelle due cartelle deve comparire, e ogni voce deve corrispondere a un file: il controllo confronta gli insiemi nelle due direzioni, enumerando dal manifesto. I file senza corrispondente (per esempio `USRSEC`, solo EBCDIC; `EXPORT.DATA.PS`; i due file conti, di cui va detto con evidenza se sono identici o in che cosa differiscono) sono dichiarati.

### Struttura fisica, prima dei campi

Per ogni file si stabilisce e si verifica, senza usare il contratto:
- **EBCDIC**: dimensione del file divisibile per la lunghezza del record; numero di record = dimensione / lunghezza;
- **ASCII**: i terminatori di riga effettivi, riga per riga (alla scrittura: `tcatbal.txt` e `trantype.txt` hanno sia CRLF sia LF, `trancatg.txt` CRLF: da riverificare e riportare con i conteggi); la lunghezza di ogni riga senza terminatore; le righe più corte o più lunghe della lunghezza del record sono **elencate una per una**, non riempite in silenzio.
Come si passa da una riga ASCII più corta al record a lunghezza fissa è una regola dichiarata (riempimento a destra con spazi, che è ciò che fa il caricamento sul mainframe da un file a lunghezza variabile? oppure altro): la regola va **giustificata con il JCL di caricamento** e, se il JCL non la determina, dichiarata come scelta e applicata in un passo separato e visibile, così che la fixture distingua "byte del file" da "byte aggiunti".

### Decodifica

Ogni record è decodificato campo per campo con il codec di #23, guidato dal contratto: i file ASCII con il profilo `oracle-gnucobol`, i file EBCDIC con il profilo `zos-ebcdic`. Per ogni campo: stato (valido, non valido, oltre la `PICTURE`), valore se c'è, byte originali.
- **Nessun valore riparato.** Un campo numerico non valido resta non valido, con i suoi byte (voce 20 del registro). Il record iniziale `…DALYTRAN.PS.INIT` (350 byte: da verificare se tutti a zero binario) si conserva com'è e i suoi campi numerici risultano non validi.
- **Round-trip**: la ricodifica conservativa di ogni record riproduce i byte originali del file (per l'ASCII: i byte della riga, distinti dall'eventuale riempimento).
- **Confronto tra le due codifiche**, dove esistono entrambe: i record si abbinano per chiave primaria (dal contratto), e per ogni coppia si confrontano stato e valore di ogni campo. Le differenze si elencano tutte: record presenti in una sola codifica, campi con valore diverso, campi validi in una e non validi nell'altra, differenze nei soli byte di riempimento. Nessuna differenza è "attesa" a priori: se l'elenco non è vuoto è un risultato, e va spiegato o dichiarato non spiegato.

### Valori di riferimento indipendenti

Per ogni file, attesi scritti a mano **leggendo i byte** (con `xxd` o simili), non copiando l'output del decodificatore, e committati prima di eseguire la decodifica su quel file:
- il primo record, l'ultimo, e un record con un importo negativo dove il tracciato ha campi con segno e il file ne contiene; per i file con anomalie, anche un record anomalo;
- per ciascuno: i byte, e campo per campo il valore atteso tipizzato, con il procedimento (quale tabella di `codifica.md` si è applicata);
- il numero di record, ricavato dalla dimensione del file.
Controlli d'insieme, registrati nel repository e ricalcolati a ogni controllo: unicità della chiave primaria; per ogni chiave alternativa del contratto, se è unica nei dati (dato utile alla discordanza già registrata su `XREFFILE`); somma di controllo di ogni campo numerico valido, e numero di valori non validi per campo.

### Fixture prodotte

Per ogni file, in `analysis/data-fixtures/out/` (versionate, rigenerate e confrontate dal controllo): i record decodificati in un formato testuale stabile (una riga per record, campi con nome, stato e valore) e l'elenco delle anomalie. `docs/legacy-map/fixture.md` (generato): per file, record, lunghezze, terminatori, anomalie, differenze tra ASCII ed EBCDIC, decisioni di decodifica, limiti.

### Prove negative (automatiche, ciascuna fallisce per il motivo dichiarato)

1. un byte alterato in un file dati (copia privata): falliscono round-trip o confronto con le fixture versionate, e il totale di controllo;
2. un record tolto o duplicato in una copia: numero di record e unicità;
3. un atteso scritto a mano alterato; un atteso mancante per un file; un file dati senza voce nell'inventario e una voce senza file;
4. il contratto sbagliato associato a un file (per esempio quello delle carte al file dei conti): la decodifica non coincide con gli attesi a mano;
5. il profilo sbagliato (EBCDIC letto come ASCII): fallisce;
6. un campo non valido convertito in zero da una colla alterata; una riga corta riempita in silenzio senza comparire nell'elenco;
7. terminatori normalizzati prima dell'analisi (CRLF → LF) in una copia: i conteggi dei terminatori non coincidono;
8. una differenza ASCII/EBCDIC tolta dall'elenco; un'anomalia tolta dall'elenco.
Ogni asserzione del verificatore ha almeno una prova negativa che fallisce solo grazie a essa (inventario delle asserzioni nella PR, come nella PR #51).

## Invarianti di parità

- I file sotto `legacy/` non si toccano. Nessun valore riparato: un record anomalo resta anomalo ed è elencato.
- Ciò che il sorgente e i JCL non determinano (per esempio il riempimento di una riga corta) è una scelta dichiarata, non un fatto.

## Criteri di accettazione

- [ ] `./analysis/run.sh data-fixtures` termina con 0 e rigenera senza differenze; `run.sh`, `check.sh`, `deps` esistono e sono eseguibili.
- [ ] `./analysis/run.sh data-fixtures --check` termina con 0 due volte di seguito, con ogni prova negativa riportata con nome e diagnosi.
- [ ] Un comando riportato nella PR mostra, per file: record contati dalla dimensione, record decodificati, record negli attesi a mano; i numeri sono coerenti.
- [ ] `./analysis/run.sh --all --check` termina con 0.
- [ ] `git status --short` vuoto dopo i controlli; `legacy/` invariato; `git diff --name-only origin/main...HEAD` elenca solo file ammessi.
- [ ] CI verde, compreso `analysis-check`.

## Strategia di rollback

Revert del commit di merge: nulla dipende ancora da `analysis/data-fixtures/`.

## Limiti per l'agente

- Regole comuni alle analisi: file enumerati dal manifesto, mai da un glob; legacy letto dal volume Docker sensibile alle maiuscole; immagini e volumi condivisi non si rimuovono né si ricostruiscono con modifiche; nessun comando Docker globale.
- Negli script ogni comando ha l'esito controllato, con gli esiti ammessi dichiarati; limite di tempo sui comandi che possono restare in attesa; nessun residuo di una corsa precedente può soddisfare un controllo; i controlli pretendono l'insieme atteso, non "almeno uno".
- Un'anomalia che impedisce la decodifica di un file intero: `needs-spec-update`, non una correzione del dato.
- Autocontrollo prima della PR come da `paper/data/prompts/esecutore.md`. File di appoggio sull'host con prefisso `issue5-`. Non mergiare. Mantieni nel corpo della PR la riga `Closes #5` anche se lo riscrivi.
