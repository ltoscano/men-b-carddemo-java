# Contestazione avversariale della specifica #36

| | |
| --- | --- |
| Data | 27 novembre 2026, 21:29:09 → 21:33:56 UTC |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #49 |
| Token | 185.917 |
| Esito | 6 rilievi: 2 bloccanti, 4 importanti. Tutti accolti |

`prima-36.md` è la bozza di poche righe che era su GitHub; `bozza-36.md` quella contestata; `dopo/36.md` la specifica pubblicata.

## Che cosa è cambiato
1. La bozza diceva che la macro `ASMWAIT` non è nel repository: c'è (`app/maclib/ASMWAIT.mac`), e si espande in `STIMER WAIT,BINTVL=…`. Errore mio: avevo cercato sotto `app/asm` e non nella cartella delle macro.
2. Conseguenza: non ogni valore è un caso determinato con ritorno 0. Oltre `X'7FFFFFFF'` il servizio termina il programma; l'equivalente si ferma con 97 invece di ritornare con successo.
3. Perimetro: per compilare un programma di prova nuovo serve toccare un elenco in `compile.sh` e uno in `check.sh`.
4. La riga di diagnostica su stderr è un secondo adattamento: dichiarato, con la distinzione tra ciò che è riferimento di parità (il valore richiesto) e ciò che non lo è (la riga).
5. Il limite di tempo vale anche per i casi positivi: altrimenti una routine che attende un secondo passerebbe.
6. La controprova di retrocompatibilità non dipende più da `origin/main`.
