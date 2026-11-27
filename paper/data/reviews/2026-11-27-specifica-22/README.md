# Contestazione avversariale della specifica #22

| | |
| --- | --- |
| Data | 27 novembre 2026, 17:36:05 → 17:41:40 UTC |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #30 |
| Token | 117.416 |
| Esito | 4 rilievi: 1 bloccante, 3 importanti. Tutti accolti |

Bozza in `bozza-22.md`, prompt in `prompt.txt`, output integrale in `codex-rilievi.md`, specifiche pubblicate in `dopo/`.

## Che cosa è cambiato
1. I controlli guardavano solo gli archi presenti: un arco mancante con l'occorrenza conservata passava. Ora si confronta il multinsieme degli archi richiesti con quello degli archi presenti.
2. Il confine tra "scritto nel sorgente" e "variabile" era contraddittorio. Codex ha contato che tutti i 58 comandi sui file e i 24 `RETURN TRANSID` usano nomi di dato con `VALUE`: senza risolverli l'issue avrebbe consegnato quasi nulla. Tre stati espliciti: letterale, costante (dato con `VALUE` mai modificato: risolto qui, con arco), non risolto.
3. Mancavano le identità dei nodi per mappe, mapset, file e code; fissate, con operando originale e nome normalizzato distinti.
4. I quattro programmi scelti per gli attesi a mano coprivano 38 blocchi su 240 e nessuna delle forme delicate (`READ UPDATE`, scorrimento, `SYNCPOINT`, `LINK`). Sostituiti con `COSGN00C`, `COACTUPC`, `COCRDLIC`, `COPAUS1C`, più file di prova per le forme restanti; gli attesi coprono operandi, modalità e archi, non solo la posizione.

Il conteggio di Codex (240 blocchi in 25 programmi, nessuno nei copybook) è riportato nella specifica come dato della contestazione: l'Esecutore lo deve ritrovare con il proprio conteggio indipendente.
