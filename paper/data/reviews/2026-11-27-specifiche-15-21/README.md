# Contestazione avversariale delle specifiche #15 e #21

| | |
| --- | --- |
| Data | 27 novembre 2026, 13:01:09Z → 13:05:15Z |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #20 |
| Durata e costo | 4 min 6 s, 120.056 token |
| Esito | 13 rilievi: 1 bloccante, 12 importanti. Tutti accolti |

`prima/` e `dopo/` contengono le due specifiche prima e dopo. Output integrale in `codex-rilievi.md`.

## Cosa è cambiato
- **#15** conteneva quattro consegne indipendenti (rilievo 13). Ora è solo "test di integrazione con PostgreSQL reale"; il resto è in #26 (confini tra moduli e tipi vietati), #27 (copertura e SpotBugs), #28 (SonarQube), in sequenza.
- **#21**: può modificare anche `run.sh` e `lib.sh` di `analysis/tools/` per introdurre una sola dichiarazione dei verdetti dovuti; può rieseguire le build delle immagini dalla cache.

## Esito per rilievo

| # | Spec. | Gravità | Rilievo in breve | Esito |
| ---: | --- | --- | --- | --- |
| 1 | #21 | bloccante | Il comando obbligatorio ricostruisce le immagini che la specifica vietava di ricostruire | accolto: build dalla cache ammesse |
| 2 | #21 | importante | Le fonti indicate non definiscono l'insieme dei verdetti | accolto: dichiarazione unica usata da produttore e controllore |
| 3 | #15 | importante | Le variabili locali potevano restare scoperte | accolto: controllo sul sorgente obbligatorio, in #26 |
| 4 | #15 | importante | Confuse dipendenze Maven e dipendenze tra classi | accolto: Enforcer per il grafo Maven, in #26 |
| 5 | #15 | importante | Manca una prova che distingua l'accesso a Docker dentro Maven | accolto: prove su macOS e in CI; prova negativa dentro Maven |
| 6 | #15 | importante | L'eccezione per arm64 permetteva di consegnare Sonar inutilizzabile | accolto: immagine arm64 obbligatoria, in #28 |
| 7 | #15 | importante | Un rapporto di copertura vuoto sarebbe passato | accolto: contenuto verificato, in #27 |
| 8 | #15 | importante | Il confronto dell'immagine PostgreSQL poteva confrontare due costanti | accolto: il test avvia l'immagine letta da `compose.yaml` |
| 9 | #15 | importante | "Analisi completata" non definita | accolto: attesa dell'elaborazione lato server, in #28 |
| 10 | #21 | importante | La prova sul file aggiuntivo non discriminava | accolto: verdetto valido copiato sotto un altro strumento |
| 11 | #15 | importante | Le regressioni della PR #20 non erano un comando ripetibile | accolto: `quality/regressioni-verify.sh`, esclusi gli attacchi respinti |
| 12 | entrambe | importante | Due issue sulla stessa cartella dei workflow | accolto: eccezione registrata per due file distinti (voce 27) |
| 13 | #15 | importante | Quattro consegne in una | accolto: divisa in quattro issue |
