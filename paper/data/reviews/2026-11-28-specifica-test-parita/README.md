# Contestazione della specifica del test di parità del pilota batch

28 novembre 2026. Codex in sola lettura su `main` con il ramo della PR #64 unito in locale: 6 min 9 s, 148.181 token. Undici rilievi (4 bloccanti, 7 importanti), tutti accolti. Issue pubblicata: https://github.com/ltoscano/men-b-carddemo-java/issues/65.

- `prompt.txt`, `prima.md`, `codex-rilievi.md`, `dopo.md`.
- I bloccanti: il comando scritto non selezionava il job (in Spring Boot serve `spring.batch.job.name`); la riesecuzione non aveva un contratto; il riconoscimento "il job non esiste" poteva restare vero anche dopo una traduzione corretta; il comparatore da solo non può accorgersi di uscite rimaste da una corsa precedente.
- Conseguenza sul disegno: il job si avvia come processo separato dal jar distribuito, e le prove sull'avvio usano applicazioni di prova costruite nei test.
