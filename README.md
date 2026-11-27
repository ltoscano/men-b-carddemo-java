# MEN-B — Make Everything Now, Brownfield

Migrazione reale e documentata di **AWS CardDemo** da COBOL/CICS/VSAM/JCL a **Java 21 + Spring Boot + Spring Batch + PostgreSQL**, consegnata come applicazione containerizzata, eseguita con agenti AI governati da una coda di GitHub Issues.

Questo repository è insieme il prodotto della migrazione e il materiale di un paper che vuole insegnare come rifarla su un altro sistema legacy: in modo replicabile, chiaro e reale.

> **Stato:** Wave 0A (mappa del legacy e golden oracle). Non c'è ancora codice Java.

## Cosa trovi qui

| Percorso | Contenuto |
| --- | --- |
| `paper/mec-b-paper.md` | Il paper, scritto man mano che il lavoro procede |
| `paper/articolo-metodo-greenfield-brownfield.md` | Il metodo: issue come coda di specifiche, ruoli, Fase 0 |
| `paper/piano-migrazione-carddemo-java.md` | Inventario di CardDemo e piano a ondate |
| `paper/data/` | Misure grezze (tempi, esiti) da cui derivano tabelle e grafici |
| `legacy/aws-mainframe-modernization-carddemo/` | Sorgente COBOL originale, submodule in sola lettura fissato al commit `59cc6c2` |
| `CLAUDE.md` | Contesto e regole per gli agenti |
| [Issues](../../issues) | La coda di specifiche: ogni cambiamento nasce da una issue e arriva con una PR |

## Come funziona il lavoro

`Issue ready → Selettore → Esecutore → Validatore adversarial → Gate umano (merge)`

- **Selettore / pianificatore:** Claude Fable — scrive le issue e avvia il lavoro, non implementa.
- **Esecutore:** Claude Opus o Sonnet — una issue, un worktree, una PR.
- **Validatore adversarial:** Codex CLI, a contesto pulito — cerca di falsificare la PR.
- **Gate umano:** l'unico che decide il merge.

## Clonare

```sh
git clone --recurse-submodules https://github.com/ltoscano/men-b-carddemo-java.git
```

Unico prerequisito previsto per costruire, testare ed eseguire: Docker.

## Attribuzione

CardDemo è un progetto di Amazon Web Services distribuito con licenza Apache-2.0: <https://github.com/aws-samples/aws-mainframe-modernization-carddemo>. Questo repository non è affiliato ad AWS e non apre issue o PR sul progetto originale.
