BOCCIATA

Validato `4b70d0e`. Ho riprodotto **due falsi verdi**: un errore esplicito del ricalcolo accettato come verdetto e una scrittura saltata accettata grazie al registro ereditato.

Tutte le prove sotto sono state **eseguite da me**. Abbreviazioni:

- `R` = `./analysis/run.sh --all`
- `C` = `./analysis/run.sh --all --check`
- `T` = `./analysis/run.sh tools --check`
- `W_x` = wrapper di `x` in testa al `PATH`, con diagnostica ed esito 42.

Timeout imposti: **600 s per ogni analisi**, 30–60 s per gli helper. Nessun timeout raggiunto. Comandi completi, log e durate sono nel registro locale (file locale del Validatore, non conservato).

| Prova | Comando | Esito osservato | Durata |
|---|---|---|---:|
| Rigenerazione 1 | `R` | 0; nessuna modifica tracciata | 124,946 s |
| Controllo 1 | `C` | 0 | 106,466 s |
| Rigenerazione 2 | `R` | 0; nessuna modifica tracciata | 161,517 s |
| Controllo 2 | `C` | 0 | 267,375 s |
| Voce `scc/verdetto-layout.txt` aggiunta e copia residua cb2xml | `R`, poi `C` | 1 / 1; cartella incompatibile con il controllo | 6,044 / 6,445 s |
| Verdetto GnuCOBOL cancellato; wrapper `comm` | `PATH=W_comm:$PATH T` | 1; file mancante; `comm` non viene usato | 0,084 s |
| Stessa cancellazione; `find` fallisce | `PATH=W_find:$PATH T` | 1; errore di enumerazione | 0,351 s |
| Stessa cancellazione; `sed` fallisce | `PATH=W_sed:$PATH T` | 1; errore di enumerazione | 0,198 s |
| Stessa cancellazione; `sort` fallisce | `PATH=W_sort:$PATH T` | 1 | 0,194 s |
| Stessa cancellazione; `awk` fallisce | `PATH=W_awk:$PATH T` | 1 | 0,215 s |
| Stessa cancellazione; `cut` fallisce | `PATH=W_cut:$PATH T` | 1 | 0,293 s |
| Stessa cancellazione; `uniq` fallisce | `PATH=W_uniq:$PATH T` | 1 | 0,198 s |
| Controllo sbagliato / strumento sbagliato / riga duplicata nel TSV | `T`, separatamente | 1 / 1 / 1; dichiarazione rifiutata | 0,048 / 0,060 / 0,061 s |
| Verdetto scc presente, sua scrittura saltata nel produttore | `R` | 1; nomina la scrittura mancante | 158,783 s |
| Stessa mutazione, con voce precedente in `WRITTEN` | `env WRITTEN=… R` | **0; falso verde** | 97,818 s |
| Creazione residuo reale del controllo CALL ProLeap | `verdict_text call proleap --out /analysis/tools/out` | 0; salva un traceback senza `VERDETTO:` | 0,757 s |
| Voce ProLeap aggiunta e residuo malformato | `C` | 1; riconcilia dieci file, poi fallisce nella fixture negativa | 115,195 s |
| Stessa voce aggiunta, nessuna prova la scrive | `R` | 1; verdetto non scritto nella corsa | 157,895 s |
| Cancellato `cb2xml/verdetto-layout.txt` | `C` | 1; nomina il file mancante | 4,726 s |
| Cancellato `cmt/verdetto-call.txt` | `C` | 1; nomina il file mancante | 5,214 s |
| Cancellato `gnucobol/verdetto-compile.txt` | `C` | 1; nomina il file mancante | 7,180 s |
| Cancellato `scc/prova-fallita-ripartizione.txt` | `C` | 1; nomina il file mancante | 9,632 s |
| PR 18: aggregato scc azzerato | `C` | 1; somme incoerenti | 17,522 s |
| PR 18: campo XML cb2xml rinominato, TSV invariato | `C` | 1; rinormalizzazione diversa | 73,904 s |
| PR 18: `POSTTRAN/STEP15`, `PGM → PROC` | `C` | 1; tipo errato | 14,070 s |
| PR 18: errori `CBSTM03A`, `39 → 9999` | `C` | 1; discordanza con le diagnostiche | 10,714 s |
| Salvataggio diagnostica del ricalcolo layout fallito | `PATH=W_docker:$PATH verdict_text …` | 0; salva soltanto intestazione e diagnostica | 0,162 s |
| Verifica diretta dell’errore sottostante | `PATH=W_docker:$PATH glue_run … layout --out …` | **42** | 0,034 s |
| Diagnostica residua e ricalcolo ancora fallito | `PATH=W_docker:$PATH C` | **0; falso verde, nove verdetti riconciliati** | 184,240 s |
| Verifica dei ripristini e del perimetro | `python3 /tmp/val31b-audit/final.py` | 0 | 0,249 s |
| Controllo finale consecutivo 1, senza mutazioni | `C` | 0 | 213,002 s |
| Controllo finale consecutivo 2, senza mutazioni | `C` | 0 | 103,365 s |
| Verifica finale di stato, hash e diff | `python3 /tmp/val31b-audit/final.py` | 0 | 0,173 s |

I primi wrapper `find` e `sed` non intercettavano il comando eseguito da `out/`: quei tentativi terminarono con 1 per il file mancante, in 0,229/0,271 s. Li ho corretti e ripetuti; nella tabella sono riportate le prove con errore 42 effettivamente osservato.

Dopo ogni esecuzione di base e dopo il ripristino finale, `git status --porcelain` mostra soltanto `?? .validazione/`, già presente all’inizio. Non è quindi letteralmente vuoto, ma **non ci sono modifiche tracciate**. Output versionati e hash del legacy sono invariati. Entrambi i patch forniti coincidono esattamente con i diff Git; i cinque file modificati sono tutti ammessi. Nessun commit, push o comando globale Docker.

Lo stato dei due rilievi del primo giro è:

| Rilievo precedente | Stato al secondo giro |
|---|---|
| Voce aggiunta soddisfatta da un verdetto residuo | **Caso originale corretto**: produttore e controllore lo rifiutano. La nuova registrazione conserva però il bypass descritto nel rilievo 2 sotto. |
| Esito di `comm` ignorato | **Corretto**: `comm` è eliminato e i sei comandi sostitutivi provati con esito 42 fanno fallire il controllo. Il rilievo 1 sotto riguarda invece il ricalcolo del contenuto. |

Restano i seguenti rilievi:

1. **Importante — una diagnostica d’errore può essere riconciliata come verdetto valido. Falso verde: sì, dell’intero `C`.**

   Ho sostituito `docker` con un wrapper che fallisce **soltanto per il ricalcolo layout con `--out`**, stampando una diagnostica e restituendo **42**. Ho verificato separatamente quel codice di uscita. Il verdetto residuo è stato prodotto tramite la funzione reale `verdict_text` e contiene:

   ```text
   controllo: layout
   AUDIT: docker compare layout exit 42
   ```

   Con questo file e lo stesso guasto, `C` termina con **0** e dichiara nove verdetti coincidenti. Le altre invocazioni Docker vengono inoltrate al comando reale. Nessuno strumento restituisce dati falsi con esito positivo.

   Evidenza: [lib.sh:58](analysis/tools/lib.sh:58) nasconde l’errore con `|| true`; le nuove guardie in [check.sh:57](analysis/tools/check.sh:57) non lo recuperano. L’intestazione rende il risultato non vuoto e il confronto accetta due diagnostiche identiche.

   **Correzione richiesta:** distinguere un confronto concluso con `pass`/`fail` da un errore operativo; validare il formato e l’esito prima della registrazione e riconciliazione. Aggiungere una prova automatica con errore 42 e diagnostica residua. Riproduttore (file locale del Validatore, non conservato), log del falso verde (file locale del Validatore, non conservato).

2. **Importante — il registro delle scritture non viene inizializzato per la corsa. Falso verde: sì, del produttore `R`.**

   Non esiste un file registro da lasciare dalla corsa precedente: il registro è la variabile `WRITTEN`. Ho saltato esplicitamente la sola chiamata che scrive il verdetto scc, lasciando il file precedente sul disco e mantenendo attiva la prova dello strumento. Senza registro ereditato, `R` fallisce correttamente.

   Con la stessa mutazione e:

   ```bash
   env WRITTEN=$'scc/verdetto-scc.txt\tscc\t-\n' ./analysis/run.sh --all
   ```

   `R` termina invece con **0**, pur non avendo scritto quel verdetto.

   Evidenza: [lib.sh:142](analysis/tools/lib.sh:142) accoda al valore preesistente; la riga 155 lo usa come registro corrente. `run.sh` non lo azzera. Il bypass richiede stato importato dall’ambiente: non ho osservato persistenza automatica tra due invocazioni normali.

   **Correzione richiesta:** inizializzare incondizionatamente `WRITTEN` nel produttore prima delle prove e aggiungere il negativo con registro precedente e scrittura saltata. Riproduttore (file locale del Validatore, non conservato), log del falso verde (file locale del Validatore, non conservato).

Ho **letto** integralmente `diff-dal-giro-1.patch` e il workflow. La modifica a `reconcile` resta nel perimetro: cambia l’enumerazione per usare la dichiarazione unica, mantenendo il ricalcolo e il confronto dei contenuti. Non risultano modifiche alle funzioni comuni o alle altre analisi; le funzioni preesistenti di `tools/lib.sh` sono invariate. Non segnalo quindi una violazione di perimetro.

Non ho eseguito GitHub Actions, verificato online i collegamenti CI dichiarati o ricreato Docker senza cache. Le due esecuzioni finali consecutive sono entrambe verdi: **nessun falso rosso osservato senza mutazioni**.