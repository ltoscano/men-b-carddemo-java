# Contestazione avversariale delle specifiche #14 e #19

| | |
| --- | --- |
| Data | 27 novembre 2026, 11:44:15Z → 11:47:00Z |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #17 |
| Durata e costo | 2 min 45 s, 45.899 token |
| Esito | 11 rilievi: 2 bloccanti, 9 importanti |

Stesso comando e stessa struttura di prompt della contestazione precedente (`../2026-11-27-specifiche-1-13/README.md`), con in più la richiesta di cercare conflitti tra le due issue se eseguite in parallelo.

## La decisione che ne è uscita

Il rilievo 1 mostra che le due issue erano in conflitto di fondo: #13 aveva messo l'avvio dei jar dentro `verify.sh`; #14 porta il database, senza il quale i jar non partono; #19 doveva correggere proprio la parte di `verify.sh` che #14 rende impossibile. Decisione del pianificatore (voce 13 del registro delle approvazioni): l'avvio esce da `verify.sh` e passa a `smoke.sh`, sullo stack reale; **#19 viene chiusa come superata**.

## Esito per rilievo

| # | Specifica | Gravità | Rilievo in breve | Esito |
| ---: | ---: | --- | --- | --- |
| 1 | #14 | bloccante | Con PostgreSQL i jar non partono da soli, ma `verify.sh` li avvia e non si poteva toccare | accolto: nuova divisione tra `verify.sh` (build e test) e `smoke.sh` (avvio reale) |
| 2 | #14 | bloccante | Chiesto un job, vietati i file per definirlo | accolto: `installationCheckJob` nel perimetro |
| 3 | #19 | importante | #14 e #19 toccano gli stessi file e #14 cambia il presupposto di #19 | accolto: #19 chiusa come superata |
| 4 | #19 | importante | La prova non esercita la corsa che si vuole correggere | superato dalla chiusura di #19 |
| 5 | #19 | importante | Manca la prova del SIGKILL fallito | superato dalla chiusura di #19 |
| 6 | #14 | importante | Codice 0 e tabelle presenti non provano che il job sia stato eseguito | accolto: lo smoke legge in PostgreSQL le esecuzioni `COMPLETED`; prova negativa con lancio disabilitato |
| 7 | #14 | importante | Il nome di progetto non isola le porte | accolto: porta dinamica; prova con lo stack ordinario attivo |
| 8 | #14 | importante | L'Esecutore poteva svuotare i test esistenti | accolto: i test di contesto restano, con regole esplicite |
| 9 | #14 | importante | Riesecuzione del batch non definita | accolto: nuova istanza a ogni lancio; due lanci nello smoke |
| 10 | #19 | importante | "Jar residuo" descritto in modo incompleto | recepito nei criteri di `verify.sh` dentro #14 |
| 11 | #14 | importante | I controlli di pulizia non guardano reti e container arrestati | accolto: verifica per etichette del progetto; prova di pulizia fallita |
