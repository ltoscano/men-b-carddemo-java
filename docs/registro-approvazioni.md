# Registro delle approvazioni

Dal 27 novembre 2026 l'autore ha delegato al pianificatore (Claude Fable) l'approvazione e il merge delle pull request e le decisioni di prodotto ordinarie. Questo registro è la contropartita: tutto ciò che viene approvato è scritto qui, con il motivo e le evidenze, perché l'autore possa controllarlo e annullarlo.

Regole di approvazione: sezione "Approvazione delegata" di `CLAUDE.md`. Il registro è in sola aggiunta: una voce sbagliata si corregge con una voce nuova.

Tipi di voce: **specifica** (passata a `ready`), **merge**, **decisione delegata**, **rilievo respinto**, **escalation**.

| # | Data e ora (UTC) | Tipo | Oggetto | Decisione | Motivo ed evidenze | Rinviato a |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | 2026-11-27 09:30 | specifica | Piano delle wave v2 | approvato **dall'autore** (prima della delega) | Contestazione di Codex: 23 rilievi, tutti accolti. `paper/data/reviews/2026-11-27-piano-wave/` | — |
| 2 | 2026-11-27 10:03 | specifica | Issue #1 e #13 passate a `ready` | approvato (prima della delega, secondo il piano approvato dall'autore) | Contestazione di Codex: 12 rilievi, tutti accolti e recepiti nelle specifiche. `paper/data/reviews/2026-11-27-specifiche-1-13/` | — |
| 3 | 2026-11-27 10:13 | decisione dell'autore | Autonomia del Validatore | Codex lavora con scrittura nel clone usa e getta e accesso a Docker | Proposta dall'autore; provato che senza accesso alla rete locale Docker è rifiutato. Mai accesso completo | — |
| 4 | 2026-11-27 10:16 | rilievo rinviato | PR #17, rilievo 6 di Codex (accesso a Docker per Testcontainers) | non richiesto in questa PR | Riguarda i test di integrazione, che la specifica di #13 esclude e quella di #15 prevede esplicitamente | #15 |
| 5 | 2026-11-27 10:16 | rinvio all'Esecutore | PR #17, giro 1 | non approvata | Verdetto di Codex: BOCCIATA, 1 rilievo bloccante (limiti di tempo non garantiti in `verify.sh`) e 3 importanti da correggere. `paper/data/reviews/pr-17/giro-1-codex.md` | giro di correzione 1 |
| 6 | 2026-11-27 10:17 | decisione dell'autore | Approvazione e merge delegati a Fable | in vigore da questa voce | Richiesta dell'autore: rendere il processo il più automatico possibile, con registro di tutto ciò che viene approvato | — |
