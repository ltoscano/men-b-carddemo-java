# Tracciato dei costi: che cosa c'è e che cosa manca

Creato il 27 novembre 2026, 21:35 UTC, su richiesta dell'autore. Fino a quel momento i consumi erano annotati solo dentro le note di `eventi.csv` e nei log di Codex. `costi.csv` li raccoglie in un file solo, **così come sono stati registrati**.

## Che cosa contiene `costi.csv`

Una riga per ogni fase di lavoro di un Esecutore e per ogni sessione di Codex: ora, oggetto (issue o PR), ruolo, modello, token, tipo di contatore, fonte.

- **Validatore (Codex)**: il numero della riga "tokens used" che Codex stampa a fine sessione. È il dato più affidabile: una sessione, un totale.
- **Esecutori (Claude Opus e Sonnet)**: il contatore che l'ambiente riporta quando un agente si ferma. Limiti: (1) quando un agente viene ripreso il contatore è cumulativo, e nelle note non sempre l'ho scritto: la colonna `tipo_contatore` lo dice dove lo so; (2) non so se il contatore misura i token fatturati o un'altra grandezza: **non va convertito in denaro senza verificarlo**; (3) mancano le fasi per cui non avevo annotato il contatore.

## Che cosa manca

- **La sessione principale (Fable: pianificatore e approvatore)**: non è registrata. Dall'interno della sessione non ho un contatore affidabile; il dato si legge da Claude Code (`/cost`) o dalla console di utilizzo dell'account.
- **Il costo in denaro**: nessuna conversione. Servono i prezzi per modello alla data e i token distinti in ingresso, uscita e cache, che questi contatori non distinguono.
- **La CI**: minuti di GitHub Actions non raccolti (si leggono dalle corse, fonte `github`).

## Come si userà nel paper

La sezione 6.1 riporta i tempi; i costi vanno in una tabella a parte con queste avvertenze. Un totale in token per ruolo si può dare per Codex; per gli Esecutori solo dopo aver chiarito il punto 1 fase per fase, e per la sessione principale solo con il dato dell'account.
