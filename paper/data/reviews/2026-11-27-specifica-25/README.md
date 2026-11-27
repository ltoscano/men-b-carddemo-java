# Contestazione avversariale della specifica #25 (riscritta)

| | |
| --- | --- |
| Data | 27 novembre 2026, 2026-11-27T16:18:09Z → 2026-11-27T16:21:42Z |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #39 |
| Token | 113.880 |
| Esito | 5 rilievi: 2 bloccanti, 3 importanti. Tutti accolti |

La bozza (`bozza-25.md`) nasce dalla contestazione precedente (`../2026-11-27-specifiche-24-25-26/`). Prompt in `prompt.txt`, output integrale in `codex-rilievi.md`, specifica pubblicata in `dopo/25.md`.

## Che cosa è cambiato
1. Le righe da commentare sono 23, non 26: tre righe dell'intervallo 266-291 sono vuote e restano identiche.
2. L'atteso registrato poteva certificare un caricamento infedele: aggiunta la verifica del contenuto dei quattro file indicizzati contro gli ingressi, e la verifica a mano copre ogni campo dinamico emesso, con uguaglianza esatta per posizione, numero e ordine di estratti e movimenti.
3. Lo scenario minimo ammetteva movimenti su una sola carta: ora tre carte, due con movimenti (2 + 1), importi e totali tutti distinti.
4. Le aperture riuscite non lasciano tracce osservabili: la dimostrazione è indiretta e dichiarata.
5. Il limite di tempo vale per i comandi nuovi del passo; la `docker build` dell'immagine resta un limite ereditato.
