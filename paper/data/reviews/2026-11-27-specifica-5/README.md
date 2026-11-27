# Contestazione avversariale della specifica #5

| | |
| --- | --- |
| Data | 27 novembre 2026, 22:27:16 → 22:31:41 UTC |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #51 |
| Token | 110.592 |
| Esito | 6 rilievi: 1 bloccante, 5 importanti. Tutti accolti |

`prima-5.md`: la specifica del mattino; `bozza-5.md`: quella riscritta e contestata; `dopo/`: le specifiche pubblicate (#5 e la nuova issue del caricamento).

## Che cosa è cambiato
1. I due file conti EBCDIC sono identici tra loro e corrispondono al file ASCII dei conti; Codex ha trovato una differenza reale tra le due codifiche (un CAP diverso nello stesso conto).
2. Per il file di export, con viste sovrapposte, mancava la regola per scegliere la vista: è il tipo di record, come nel sorgente.
3. Gli attesi a mano per file lasciavano scoperti due tipi di record dell'export: ora un atteso per ogni tipo presente.
4. Il file giornaliero è sequenziale e non ha chiave primaria: la chiave di abbinamento è una scelta dichiarata.
5. Non per ogni file esiste un JCL che lo carica: l'inventario distingue caricamento diretto, consumatore, nessun caricatore.
6. Il conteggio dei record dalla dimensione vale solo per gli EBCDIC; per gli ASCII si contano le righe e si riconcilia al byte.
