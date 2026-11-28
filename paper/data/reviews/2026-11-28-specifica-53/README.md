# Contestazione della specifica dell'issue #53 (file dei conti nell'oracle)

28 novembre 2026. Codex in sola lettura su un clone di `main`: 3 min 11 s, 140.398 token. Sei rilievi (1 bloccante, 3 importanti, 2 minori), tutti accolti.

- `prompt.txt`: il prompt. `prima-53.md`: la specifica contestata. `codex-rilievi.md`: l'output integrale. `dopo-53.md`: la specifica pubblicata.
- Il bloccante: la specifica chiedeva insieme di rigenerare sempre il file e di fallire se ne restava uno vecchio. Ora distingue i due casi di residuo.
- Un fatto sui dati emerso dalla contestazione: nessun conto di esempio ha importi negativi. Il pilota, da solo, non esercita il segno negativo (conseguenza per #55).
