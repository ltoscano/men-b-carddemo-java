# Contestazione avversariale della specifica #43

| | |
| --- | --- |
| Data | 27 novembre 2026, 19:51:31 → 19:54:52 UTC |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #47 |
| Token | 110.217 |
| Esito | 7 rilievi: 1 bloccante, 5 importanti, 1 minore. Tutti accolti |

Bozza in `bozza-43.md`, prompt in `prompt.txt`, output integrale in `codex-rilievi.md`, specifica pubblicata in `dopo/43.md`.

## Che cosa è cambiato
1. La specifica ordinava di fermarsi se il codec non decodifica un record intero: non lo fa, quindi l'Esecutore si sarebbe fermato subito. L'adattatore contratto → campi è ora parte dell'issue.
2. Record variabile: il codec rifiuta i carichi di 12 e 39 byte; definito come si passa il carico al codec e che il confronto riguarda solo il prefisso.
3. Alcune prove negative erano impossibili (un campo solo; spostamenti che aprono buchi già rilevati da #3): ogni mutazione dichiara applicabilità e diagnosi attesa.
4. Valori distinti non bastano a provare tipo, segno e precisione (`00 00 00 7B` vale 123 con tre dichiarazioni diverse): valori discriminanti campo per campo, e dichiarazione di ciò che resta affidato ai controlli di #3.
5. Aggiunti gli scambi tra campi adiacenti di uguale lunghezza e tipo diverso; attesi tipizzati.
6. Il commit anticipato non esclude un errore di lettura ripetuto in sentinella e contratto: aggiunta una verifica sorgente → sentinella che rilegge nome, `PICTURE` e `USAGE` dal copybook alle righe dichiarate.
7. La lunghezza totale si confronta con una fonte esterna solo dove esiste.
