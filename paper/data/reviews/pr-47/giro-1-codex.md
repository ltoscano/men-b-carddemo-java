BOCCIATA

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Rigenerazione | `./analysis/run.sh data-codec` | **0**; 329 campi, 61 varianti, 266 osservazioni |
| File eseguibili | `test -x analysis/data-codec/run.sh && test -x analysis/data-codec/check.sh && test -x analysis/data-codec/deps` | **0** |
| Primo controllo | `./analysis/run.sh data-codec --check` | **0**; dettaglio di 139 prove negative omesso, rilievo 4 |
| Secondo controllo consecutivo | `./analysis/run.sh data-codec --check` | **0**; stessa omissione |
| Tutte le analisi | `./analysis/run.sh --all --check` | **0** |
| Oracle | `./oracle/run.sh --all --check` | **0** |
| Perimetro | `git diff --name-only origin/main...HEAD` | 26 file ammessi. **File fuori perimetro: nessuno** |
| Integrità | `git status --short`; stato del submodule; confronto di `legacy/` e `oracle/` con `origin/main` | Nessuna modifica prodotta dalle prove. Resta solo `?? .validazione/`, già presente all’inizio. Legacy e oracle invariati |
| CI sullo SHA `3d28d6e` | `gh api repos/ltoscano/men-b-carddemo-java/commits/3d28d6ef39d2c64c8537021a4585639816826d21/check-runs` | Tutti i controlli completati con successo, incluso [analysis-check](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46045380410/job/140663213770) |

1. **Bloccante — Copertura incompleta delle rappresentazioni alternative del segno: falso verde riprodotto.**  
   `glue/verifica.py:44–46` controlla soltanto i 20 byte delle rappresentazioni C/D; `:201–203` richiede una sola cifra alternativa. Per ciascuna delle tre varianti mancano nove cifre alternative, in entrambi i profili: complessivamente **54 combinazioni non provate**.

   Ho scambiato nella colla le cifre finali alternative 0 e 1, lasciando invariati vettori e attesi. L’intero `./analysis/run.sh data-codec --check`, comprese le prove negative automatiche, è terminato con **0**. Il mutante restituisce:
   - `31 32 33 34 35 30` → **1234.51**, anziché 1234.50;
   - `F1 F2 F3 F4 F5 F0` → **1234.51**, anziché 1234.50.

   **Schema generale:** il controllo verifica un rappresentante di una famiglia ammessa, anziché tutte le righe richieste dalla regola.  
   **Correzione richiesta:** completare tabella, vettori e copertura dei 30 byte ammessi per ogni variante e profilo; segnalare ogni byte mancante. Aggiungere una prova negativa sulle cifre alternative.  
   **Falso verde:** sì, dimostrato. **Regola sbagliata accettata:** sì.

2. **Bloccante — Un campo incompleto può diventare un numero valido, anche zero.**  
   `glue/codec.py:304` estrae una slice senza verificarne la lunghezza né i limiti dell’offset. `int.from_bytes` interpreta anche una sequenza vuota:

   ```python
   codec.decodifica("oracle-gnucobol", "comp", "9(3)", b"")
   # Risultato(stato='valido', valore=Decimal('0'), originali=b'')
   ```

   Riprodotto anche in `zos-ebcdic`. Un solo byte `01` viene accettato come 1 per campi binari da due o quattro byte; un offset oltre il record produce ancora zero valido. Anche `X(500)` accetta un record contenente un solo byte.

   **Schema generale:** la conversione precede la verifica della geometria fisica dell’ingresso. I test usano sempre record sufficientemente lunghi e non esercitano questo confine.  
   **Correzione richiesta:** rifiutare esplicitamente campi incompleti e offset fuori intervallo prima della conversione, senza assegnare valori; verificare questi casi per tutte le categorie.  
   **Falso verde:** sì, il difetto è presente mentre i controlli passano. **Regola sbagliata accettata:** sì, rappresentazioni di lunghezza errata diventano valide.

3. **Importante — Atteso z/OS errato per il semiottetto packed iniziale non nullo.**  
   `vettori/zos-ebcdic.tsv:229` classifica `10 00 00 01 23 45 6C`, variante `S9(10)V9(2)`, come `non-determinato`. La stessa regola compare in `codec.py:259` e `codifica.md:185`, con fonte `ZOS-NONDOC`.

   IBM stabilisce che i quattro bit iniziali inutilizzati di un packed con precisione pari devono essere zero perché il dato sia valido; l’APAR PI96135 aggiunge proprio il controllo di questa violazione. L’incertezza sul risultato di operazioni su dati non validi non rende indeterminata la validità della rappresentazione. [IBM APAR PI96135](https://www.ibm.com/support/pages/apar/PI96135)

   Ho sostituito temporaneamente quella classificazione con `non-valido`: `--check` termina con **1**, contestando «stato atteso non-determinato, ottenuto non-valido». Il golden attuale respinge quindi la classificazione documentata.

   **Schema generale:** una ricerca documentale incompleta viene trasformata in uno stato semantico e fissata negli attesi.  
   **Correzione richiesta:** classificare il caso come non valido, conservando byte e valore assente; aggiornare documento, fonte, atteso e prove negative. Cercare lo stesso schema negli altri casi dichiarati non documentati.  
   **Falso verde:** sì, sulla classificazione. **Regola sbagliata accettata:** sì.

4. **Minore — Non viene riportato il dettaglio di ogni prova negativa.**  
   `check.sh:52` filtra tutte le righe `ampiezza-*` e `scala-*`; `:53` stampa soltanto il totale. Nei due controlli osservati mancano nome e diagnosi individuali di **139 prove**, nonostante il criterio li richieda per ciascuna.

   **Schema generale:** informazioni richieste per verificare le prove vengono sostituite da un conteggio aggregato.  
   **Correzione richiesta:** riportare nome, motivo e diagnosi di ogni prova, senza sopprimere quelle per variante.  
   **Falso verde:** nessuno dimostrato da questa omissione isolata. **Regola sbagliata accettata:** nessuna direttamente.

Le sette mutazioni richieste sono state eseguite in una copia privata, usando sempre `./analysis/run.sh data-codec --check`:

| Mutazione autonoma | Esito | Diagnosi osservata |
|---|---:|---|
| Scambio G/H nella tabella del segno | 1 | 123.47 atteso, 123.48 ottenuto |
| Endianness invertita soltanto per quattro byte | 1 | `valido` atteso, `oltre-picture` ottenuto |
| Segno packed F interpretato negativo | 1 | 1234.56 atteso, −1234.56 ottenuto |
| Scala packed spostata verso l’alto | 1 | 1234.56 atteso, 12345.60 ottenuto |
| Zero negativo packed normalizzato in ricodifica | 1 | `…0D` atteso, `…0C` ottenuto, errore `[ricodifica]` |
| Zero assegnato a un binario firmato oltre PICTURE | 1 | valore assente atteso, 0.00 ottenuto |
| Lettera non valida convertita in zero | 1 | valore assente atteso, 0 ottenuto |

Il riconto indipendente conferma **239 alfanumerici, 50 DISPLAY senza segno, 23 DISPLAY con segno, 10 COMP-3 e 7 COMP**. Nessuna delle 61 varianti contrattuali è interamente priva di vettori. Ho confrontato tutti i **524 vettori** con regole ricavate separatamente: l’atteso contestato è quello del rilievo 3.

Per il segno, la tabella ricostruita comprende anche le alternative: nell’oracle `7B/+0`, `41–49/+1…9`, `7D/−0`, `4A–52/−1…9`, più `30–39/+0…9`; su z/OS `C0–C9/+0…9`, `D0–D9/−0…9`, `F0–F9/+0…9`, sotto le assunzioni `NOPFD/PRIM`. I codici packed ammessi sono C/D/F con segno e F senza segno; quelli prodotti sono C positivo/zero, D negativo, F senza segno. [IBM, controllo di classe](https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=arithmetic-checking-incompatible-data-numeric-class-test)

Ho verificato anche binari big-endian da 2/4/8 byte, complemento a due, DISPLAY senza segno e riempimento alfanumerico. Il confronto indipendente con ICU conferma i sei byte distintivi 037/1047 e le 17 occorrenze dichiarate. [IBM, formati numerici](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=arithmetic-formats-numeric-data), [IBM, elementi computazionali](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=clause-computational-items)

Le evidenze legacy comprendono `CVEXPORT.cpy:16,41,50,57,87,96`, le selezioni dei tipi in `CBEXPORT.cbl:274,343,407,462,527` e le opzioni JCL in `compile_batch.jcl.template:9` e `BUILDBAT.prc:36`. La sonda autonoma conferma per `FF FF FF FF`: **MOVE 4294967295, ADD −1, riscrittura `00 00 00 01`**; C generato e firma di `cob_add_int` sostengono la causa dichiarata.

La storia Git colloca i vettori in `aa22593`, prima delle osservazioni in `f289c91`; successivamente cambiano i dieci casi oltre PICTURE in `11ba1dd`, viene aggiunta la tabella delle osservazioni e viene aggiunto il vettore z/OS degli spazi. Non risultano altri adattamenti degli attesi originari.

Atteso alterato, output alterato e sonda terminata senza osservazioni sono stati respinti. Tutte le modifiche temporanee sono ripristinate; nessun commit. Non restano container, volumi o reti con prefisso `menb-val47-`.