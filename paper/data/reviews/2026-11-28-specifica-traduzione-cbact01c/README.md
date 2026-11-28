# Contestazione della specifica della traduzione di CBACT01C

28 novembre 2026. Codex in sola lettura: 3 min 46 s, 138.816 token. Nove rilievi (1 bloccante, 8 importanti), tutti accolti. Issue pubblicata: https://github.com/ltoscano/men-b-carddemo-java/issues/67.

- `prompt.txt`, `prima.md`, `codex-rilievi.md`, `dopo.md`.
- Il bloccante rovescia una decisione del pianificatore: fermare il job sui conti con addebito di ciclo diverso da zero. Nel sorgente è indeterminato un campo di sette byte, non la prosecuzione: il programma scrive il record e va avanti. Il Java prosegue e scrive in quei byte una convenzione dichiarata.
- Altri rilievi di sostanza: gli errori non avevano un contratto (il nuovo sistema non ha gli stati di file del COBOL); l'ordine degli effetti tra console e scritture non era verificato; una riesecuzione fallita poteva lasciare i file della corsa precedente, mentre il JCL li cancella prima di cominciare.
