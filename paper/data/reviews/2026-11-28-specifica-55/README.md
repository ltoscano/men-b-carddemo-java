# Contestazione della specifica dell'issue #55 (golden del job READACCT)

28 novembre 2026. Codex in sola lettura su un clone di `main`: 5 min 51 s, 195.807 token. Otto rilievi (1 bloccante, 7 importanti), tutti accolti.

- `prompt.txt`: il prompt. `prima-55.md`: la specifica contestata. `codex-rilievi.md`: l'output integrale. `dopo-55.md`: la specifica pubblicata.
- Il bloccante: due byte di ogni record del file di uscita principale non sono determinati dal sorgente (area di lavoro senza valore iniziale, scritta per 8 byte e copiata per 10). La parità "byte per byte" su 107 byte non è sostenibile: diventa 105 byte, con una tabella versionata delle posizioni escluse.
- Altri rilievi di sostanza: il confronto sui valori decodificati non distingue rappresentazioni diverse dello stesso valore (segno del packed, zero negativo); la console di GnuCOBOL stampa i numeri con segno in una forma diversa da z/OS; le prove negative devono raggiungere il controllo che dichiarano di provare.
- Aggiunta successiva dell'Approvatore, non contestata da Codex: la riserva su `NUMPROC` per lo zero negativo (nata scrivendo la specifica della tabella dei conti).
