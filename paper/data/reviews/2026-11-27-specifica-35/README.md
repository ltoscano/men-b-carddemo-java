# Contestazione avversariale della specifica #35

| | |
| --- | --- |
| Data | 27 novembre 2026, 17:58:14 → 18:02:49 UTC |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #44 |
| Token | 116.622 |
| Esito | 7 rilievi: 1 bloccante, 6 importanti. Tutti accolti |

`prima-35.md` è la specifica com'era su GitHub (scritta al merge della PR #29); la bozza contestata la riallineava a #24 e #25. Prompt in `prompt.txt`, output integrale in `codex-rilievi.md`, specifica pubblicata in `dopo/35.md`.

## Che cosa è cambiato
1. "Una prova per comando" lasciava scoperte le invocazioni ripetute: ora l'elenco dei punti di acquisizione è esplicito, uno per uno.
2. Il criterio passava anche se la build fallita riceveva comunque un'impronta: ora si chiede build con codice diverso da zero e impronta assente.
3. "Ritorno diverso da zero = errore" avrebbe rotto le compilazioni sane: `grep -c` restituisce 1 quando conta zero. Esiti ammessi dichiarati per comando.
4. Perimetro: entrano `oracle/lib.sh` e `oracle/esegui.sh`, dove Codex ha riprodotto due esiti persi; gli altri script vanno alla issue #45.
5. La prova esistente sulla configurazione alternativa restava verde con il manifesto sbagliato: va estesa.
6. Il confronto tra prove eseguite in CI e in locale ora ha una condizione: stessi numeri per passo, prove sui permessi eseguite.
7. Un workflow rosso non dimostra nulla se non è rosso per il controllo giusto: si conservano corsa, SHA, mutazione e diagnostica, e si torna al verde.
