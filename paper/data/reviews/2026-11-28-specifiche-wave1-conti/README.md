# Contestazione delle due specifiche della Wave 1 per i conti (tabella e caricamento)

28 novembre 2026. Codex in sola lettura su un clone di `main`: 5 min 43 s, 172.759 token. Dodici rilievi (3 bloccanti, 9 importanti), tutti accolti. Issue pubblicate: https://github.com/ltoscano/men-b-carddemo-java/issues/59 (tabella), https://github.com/ltoscano/men-b-carddemo-java/issues/60 (caricamento).

- `prompt.txt`: il prompt. `prima-*.md`: le specifiche contestate. `codex-rilievi.md`: l'output integrale. `dopo-*.md`: le specifiche pubblicate.
- I due bloccanti di sostanza riguardano la stessa decisione del pianificatore: conservare valori e non byte, e mascherare nel riferimento ciò che la tabella perde. Codex ha mostrato che le due cose non stanno insieme: la tabella delle esclusioni serve per ciò che il sorgente non determina, e una maschera per posizione nasconderebbe errori veri. Decisione rivista: il sistema Java accetta solo ingressi in rappresentazione canonica; un record non canonico non viene caricato; il caso si sposta nello scenario di osservazione dell'oracle.
- Il terzo bloccante: uno smoke test verde non provava che le applicazioni applicassero la migrazione.
