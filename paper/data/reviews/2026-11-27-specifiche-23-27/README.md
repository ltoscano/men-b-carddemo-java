# Contestazione avversariale delle specifiche #23 e #27

| | #23 regole di codifica | #27 copertura e analisi statica |
| --- | --- | --- |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #40 | idem |
| Orari e durata (UTC, 27 novembre 2026) | 16:52:14 16:56:25 0:04:11 | 16:52:14 16:55:15 0:03:01 |
| Token | 118.635 | 130.851 |
| Esito | 10 rilievi: 1 bloccante, 9 importanti. Tutti accolti | 6 rilievi: 5 importanti, 1 minore. Tutti accolti |

Le due contestazioni sono state lanciate in parallelo. Bozze in `bozza-*.md`, prompt in `prompt-*.txt`, output integrali in `codex-rilievi-*.md`, specifiche pubblicate in `dopo/`.

## Che cosa è cambiato

**#23.** La bozza chiedeva una sentinella scritta a mano per ogni contratto e per due profili: Codex ha contato 59 contratti e 329 campi, cioè almeno 118 record e 658 valori attesi a mano. L'issue è stata divisa: #23 fissa le regole di codifica per tipo di rappresentazione con vettori di prova; le sentinelle per tracciato passano alla nuova issue #43, ristrette ai 15 contratti dei copybook e a un solo profilo (decisione delegata, voce 61 del registro). Altri cambiamenti: copertura delle singole regole (tutta la tabella del segno, ogni ampiezza binaria, ogni lunghezza `COMP-3`); osservazione nell'oracle anche con byte grezzi in lettura, non solo scrivendo e rileggendo; stesso ambiente fissato dell'oracle; pagina di codici del profilo z/OS dichiarata; ricodifica conservativa distinta dalla codifica di un valore nuovo (lo zero negativo); validità, valore e byte prodotti tenuti distinti; prove negative che mutano la colla e devono fallire nel confronto della decodifica.

**#27.** Un modulo resta nel rapporto aggregato di JaCoCo anche con l'agente spento: il controllo ora chiede la prova dell'agente per ogni modulo che esegue test e l'elenco completo delle classi. Produzione dei rapporti (ciclo Maven) e loro validazione (dopo Maven, in `verify.sh`) sono distinte, per non rompere le regressioni di #26. Le prove sui cancelli rimossi falliscono nel controllo di completezza dello script, non in Maven. Il parser dei rapporti va adattato al `DOCTYPE` di JaCoCo. Codex ha anche trovato un'affermazione falsa lasciata in `docs/sviluppo.md` dalla PR #40 (l'ordine delle fasi di Maven): la correzione entra in questa issue.
