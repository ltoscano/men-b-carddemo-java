# Contestazione avversariale della specifica "codifica dei campi in Java" (issue #54, divisa da #16)

| | |
| --- | --- |
| Data | 27 novembre 2026, 22:40:07 → 22:43:45 UTC |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #48 |
| Token | 132.206 |
| Esito | 8 rilievi: 2 bloccanti, 6 importanti. Tutti accolti |

## Che cosa è cambiato
1. Il test obbligatorio sui vettori avrebbe reso rossa la build delle immagini, che non copia quel file: ora il test è obbligatorio quando gira `./verify.sh` e saltato in modo visibile altrove, e `verify.sh` controlla che sia stato eseguito davvero.
2. Formato reale dei vettori (375: 336 decodifiche, 39 codifiche) e due percorsi di verifica distinti.
3. Il secondo file ha un altro formato e non aggiunge casi: se ne usa solo una parte.
4. I soli vettori passano anche con un parser che accetta un segno dove non deve: aggiunti i controlli esaustivi della prova di riferimento.
5. Le regole di #26 non garantiscono l'assenza di `double`: serve una verifica esplicita sulle classi compilate.
6. Scala: si rifiutano le cifre non rappresentabili, non le scale diverse; si verifica la scala restituita.
7. Offset: ogni vettore provato anche a un offset positivo tra byte di guardia.
8. Perimetro e meccanica delle prove negative resi coerenti (script nuovo, vista temporanea dei vettori).
