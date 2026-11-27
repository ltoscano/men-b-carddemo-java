## Obiettivo
Trasformare i file dati forniti con CardDemo in fixture verificate e caricarle nei file indicizzati dell'oracle.

## Dipendenze e perimetro
- Dipende da: #3 (contratto dati), #4 (immagine oracle).
- Sorgenti legacy di riferimento: `app/data/ASCII/`, `app/data/EBCDIC/` (compreso `AWS.M2.CARDDEMO.DALYTRAN.PS.INIT`), JCL di definizione e caricamento (`ACCTFILE`, `CARDFILE`, `CUSTFILE`, `XREFFILE`, `TRANFILE`, `TCATBALF`, `DISCGRP`, `TRANTYPE`, `TRANCATG`, `DUSRSECJ`).
- Cartelle coinvolte: `oracle/fixtures/`, `docs/legacy-map/fixture.md`.
- Fuori ambito: esecuzione dei programmi (#9), fixture costruite apposta (#6), loader Java (Wave 1).

## Specifica
- Decodifica guidata dal contratto di #3 con lo strumento adottato in #1, per ogni file ASCII e per il corrispondente EBCDIC.
- Casi da trattare e documentare: terminatori di riga misti (`tcatbal.txt` e `trantype.txt` hanno CRLF e LF, `trancatg.txt` CRLF); record più corti del `RECORDSIZE`; segno overpunch nei campi zoned (per esempio `{` in `ACCT-CURR-BAL`); `USRSEC` disponibile solo in EBCDIC e in-stream nel JCL; il record iniziale di `TRANFILE`, 350 byte a zero binario, che **si conserva com'è** e si marca come non valido numericamente.
- Dove esistono entrambe, le versioni ASCII ed EBCDIC decodificate si confrontano campo per campo; le differenze si elencano.
- Caricamento nei file indicizzati dell'oracle, equivalente di `DEFINE` + `REPRO`, con chiavi e indici alternativi del contratto.

## Invarianti da preservare
- I file sotto `legacy/` non si toccano. Nessun valore riparato: un record anomalo resta anomalo ed è elencato.

## Criteri di accettazione (verificabili)
- [ ] `./oracle/run.sh fixtures --check` passa e verifica:
  - **round-trip**: ogni record decodificato e ricodificato riproduce i byte originali, filler e segno compresi;
  - **valori di riferimento indipendenti**: per ogni file, numero di record uguale a quello ottenuto dividendo la dimensione del file EBCDIC per la lunghezza del record; per almeno tre record per file (primo, ultimo, uno con importo negativo dove esiste) i valori attesi sono scritti a mano in `oracle/fixtures/expected/` leggendo i byte, non copiando l'output del decodificatore;
  - unicità delle chiavi primarie; totali di controllo dei campi numerici registrati nel repository.
- [ ] Rilettura dai file indicizzati caricati: stessi record, in ordine di chiave.
- [ ] `docs/legacy-map/fixture.md` elenca per file: record, anomalie, decisioni di decodifica.
- [ ] Il diff tocca solo le cartelle dichiarate.

## Strategia di rollback
Revert della PR.

## Limiti per l'agente
- I valori attesi scritti a mano si ricavano dai byte del file, con il procedimento descritto accanto.
- Un'anomalia che impedisce il caricamento: `needs-spec-update`, non una correzione del dato.

