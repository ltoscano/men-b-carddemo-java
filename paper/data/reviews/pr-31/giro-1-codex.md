BOCCIATA

Validato `d79caab`. Ho riprodotto **due falsi verdi**.

Il diff effettivo `bb56edc..HEAD` coincide con `.validazione/diff.patch`: cinque file, 95 aggiunte, tutti nel perimetro. Nessun output versionato cambia.

Tutte le prove seguenti sono state **eseguite da me**, con timeout di 600 s per comando di analisi e cache Docker condivise. Ogni mutazione è stata ripristinata. Dopo ciascuna esecuzione di base e dopo ogni ripristino, `git status --short` mostra esclusivamente `?? .validazione/`, presente già all’inizio; nessuna modifica tracciata.

Abbreviazioni: `R` = `./analysis/run.sh --all`; `C` = `./analysis/run.sh --all --check`; `T` = `./analysis/run.sh tools --check`. I percorsi degli output sono relativi ad `analysis/tools/out/`.

| Prova | Comando | Esito osservato | Durata |
|---|---|---|---:|
| Rigenerazione 1 | `R` | 0 | 121,05 s |
| Controllo 1 | `C` | 0 | 155,61 s |
| Rigenerazione 2 | `R` | 0 | 162,87 s |
| Controllo 2 | `C` | 0 | 252,17 s |
| Cancellato `cb2xml/verdetto-layout.txt` | `T` | 1; nomina il file mancante | 0,07 s |
| Cancellato `cmt/verdetto-call.txt` | `T` | 1; nomina il file mancante | 0,07 s |
| Cancellato `cmt/verdetto-copy.txt` | `T` | 1; nomina il file mancante | 0,07 s |
| Cancellato `cobmix/verdetto-copy.txt` | `T` | 1; nomina il file mancante | 0,07 s |
| Cancellato `gnucobol/verdetto-compile.txt` | `T` | 1; nomina il file mancante | 0,09 s |
| Cancellato `mapa/verdetto-jcl.txt` | `T` | 1; nomina il file mancante | 0,08 s |
| Cancellato `proleap/verdetto-copy.txt` | `T` | 1; nomina il file mancante | 0,06 s |
| Cancellato `scc/prova-fallita-ripartizione.txt` | `T` | 1; nomina il file mancante | 0,09 s |
| Cancellato `scc/verdetto-scc.txt` | `T` | 1; nomina il file mancante | 0,08 s |
| Aggiunto `scc/verdetto-sconosciuto.txt` | `C` | 1; file non dovuto | 6,97 s |
| Copiato il verdetto cb2xml sotto `cmt` | `C` | 1; percorso non dovuto | 6,60 s |
| Tolta la voce scc da `verdetti.tsv` | `C` | 1; verdetto presente non dovuto | 6,97 s |
| Stessa dichiarazione ridotta | `R` | 1; verdetto non dichiarato | 11,25 s |
| Aggiunta voce `scc/verdetto-layout.txt`, file assente | `C` | 1; verdetto mancante | 9,50 s |
| Stessa voce aggiunta | `R` | 1; verdetto mancante | 151,90 s |
| Voce aggiunta e copia residua del verdetto cb2xml sotto `scc` | `R` | **0; falso verde** | 143,21 s |
| Stessa mutazione | `C` | **0; falso verde, riconcilia 10 file** | 262,89 s |
| Regressione PR 18: aggregato scc azzerato | `C` | 1; somme incoerenti | 5,31 s |
| Regressione: campo XML cb2xml rinominato, TSV invariato | `C` | 1; rinormalizzazione diversa | 31,67 s |
| Regressione: `POSTTRAN/STEP15`, `PGM → PROC` | `C` | 1; tipo errato | 6,82 s |
| Regressione: errori `CBSTM03A`, `39 → 9999` | `C` | 1; discordanza con il log | 7,46 s |
| Verdetto GnuCOBOL cancellato; prime due chiamate a `comm` falliscono con 42 | `env PATH=<wrapper>:$PATH C` | **0; falso verde, riconcilia solo 8 file** | 111,50 s |
| Verifica finale di diff, indice, output e legacy | `python3 <file locale>/final.py` | 0; stato iniziale ripristinato | 0,22 s |

Comandi, esiti e durate sono conservati nel registro delle prove (file locale del Validatore, non conservato).

Ho **letto** il workflow: `.github/workflows/analysis.yml:4–18` configura push e pull request, checkout con submodule ricorsivi, timeout di 45 minuti e il comando esatto richiesto. Non contiene condizioni di salto né `continue-on-error`. Non emerge un bypass del comando; può però risultare verde sui casi errati riprodotti sotto. Ho letto `.validazione/ci.txt`; non ho eseguito nuove run GitHub Actions, verificato online quella rossa dichiarata, né ricreato un ambiente Docker freddo.

Quanto alle altre analisi, dalla lettura risultano invariati `analysis/lib/common.sh`, il dispatcher e le funzioni preesistenti di `tools/lib.sh`. Quest’ultima è inclusa soltanto da `tools` e dalle sue prove. Manifesto e selftest sono passati nelle esecuzioni complete; non ho osservato regressioni.

1. **Importante — un verdetto residuo soddisfa una dichiarazione che nessuna prova produce. Falso verde: sì.**

   Ho aggiunto a `verdetti.tsv` la riga `scc<TAB>verdetto-layout.txt` e copiato in quel percorso il verdetto cb2xml. Sia produttore sia controllore terminano con 0; il controllore dichiara dieci verdetti riconciliati.

   Evidenza: [run.sh:72](analysis/tools/run.sh:72) confronta i file presenti, senza verificare quelli effettivamente scritti nella corsa corrente. [check.sh:54](analysis/tools/check.sh:54) ricava il controllo dal nome del file e accetta il contenuto cb2xml anche sotto `scc`.

   **Correzione richiesta:** confrontare la dichiarazione con l’insieme dei verdetti realmente prodotti nella corsa corrente, usando una registrazione delle scritture o una destinazione inizialmente vuota. Aggiungere la prova negativa con voce aggiunta e file residuo preesistente. Le mutazioni semplici confermano che entrambi leggono lo stesso TSV; questa mutazione li rende coerenti nell’errore.

2. **Importante — gli errori dei confronti `comm` vengono ignorati. Falso verde: sì.**

   Ho cancellato `gnucobol/verdetto-compile.txt` e fatto terminare le prime due chiamate a `comm` con codice **42**, senza risultati; le chiamate successive usano il comando reale. L’intero `C` termina con 0. Nel log compaiono entrambi gli errori, poi «9 file dichiarati, tutti presenti» e infine soltanto «8 verdetti/prove salvati coincidono».

   Evidenza: [lib.sh:90](analysis/tools/lib.sh:90) e la riga successiva leggono `comm` tramite sostituzione di processo senza controllarne l’esito; la funzione restituisce il proprio `rc`, rimasto zero.

   **Correzione richiesta:** acquisire e verificare esplicitamente l’esito di ogni comando necessario al confronto, propagando qualsiasi errore prima di dichiarare completo l’insieme. Includere una prova automatica con `comm` fallito e verdetto assente.

   Questa prova rispetta il confine di `CLAUDE.md`: il comando restituisce un errore esplicito, non dati falsi ben formati accompagnati da esito positivo.