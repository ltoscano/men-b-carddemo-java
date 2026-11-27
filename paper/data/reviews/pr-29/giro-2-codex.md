**BOCCIATA — riprodotto un nuovo falso verde tramite configurazione del compilatore letta dall’ambiente.**

Validato SHA `486d069`. Nessun commit o push. Mutazioni ripristinate, legacy intatto, diff della PR limitato a `oracle/`. Nessuna operazione Docker globale o su risorse `menb-analysis-*`.

Ho letto specifica, commenti, risposta dell’Esecutore, patch e sorgenti. Le prove sotto sono state eseguite da me. Timeout esterni: 600 s per build e suite complete, 150–180 s per sonde Docker, 30 s per controlli locali. Comandi completi, codici e tempi sono nel registro delle esecuzioni (file locale del Validatore, non conservato); mutazioni riproducibili in mutate.py (file locale del Validatore, non conservato) e regressions.py (file locale del Validatore, non conservato).

| Prova e comando | Esito osservato | Durata |
|---|---|---:|
| `./oracle/run.sh build` iniziale | **0**, 21 programmi | 4,887 s |
| `./oracle/run.sh --all --check`, prima esecuzione | **0**, 55 prove negative | 60,392 s |
| Stesso comando, subito dopo | **0**, 55 prove negative | 49,382 s |
| `--all --check`, `-fno-binary-truncate` aggiunto realmente in coda e registrato | **1**, argomenti diversi | 6,025 s |
| `--all --check`, stessa opzione in mezzo agli argomenti | **1**, argomenti diversi | 5,623 s |
| `--all --check`, `-fsign=ASCII` dopo `-fsign=EBCDIC` | **1**, argomenti diversi | 5,461 s |
| Sonda `PERFORM`, compilata con configurazione originale e con `COB_CONFIG_DIR` alternativo | **0**, comportamenti diversi | 1,080 s |
| `--all --check`, configurazione alternativa tramite ambiente | **0: falso verde**, tutte le 55 prove negative passano | 48,145 s |
| Estrazione indipendente dei byte di `dailytran.txt` e `acctdata.txt` | **0**, risultati sotto | 0,024 s |
| Build originale; `./oracle/run.sh segno --check` | **0**; **0** | 2,899 + 2,530 s |
| Rimozione di `-fsign=EBCDIC`, build; `segno --check` | Build **0**; controllo **1**, valori e byte differenti | 2,605 + 0,969 s |
| Sonde mie su `PIC 9`, `COMP-3`, `SIGN SEPARATE` e `CVACT01Y` | **0**, risultati sotto | 0,887 s |
| `env UNO_OPZIONI=/non-esiste ./oracle/run.sh build` | **0**, opzioni originali | 8,257 s |
| `compile.sh tutto` e `uno`, entrambi con `UNO_OPZIONI=/non-esiste` passato dentro il container | `tutto` riesce; `uno` fallisce come atteso | 2,521 s complessivi |
| Solo lunghezza PARM diminuita di uno: build; `avviatore --check` | **0**; **1**, lunghezza 9 con testo completo | 10,278 + 3,461 s |
| `CEE3ABD` termina con 0: build; `abend --check` | **0**; **1**, entrambe le chiamate intercettate | 9,434 + 2,832 s |
| `CBACT03C` sostituito con `CBACT02C`: `avvio --check`; verifica diretta | **1**, impronta; **1**, simbolo mancante | 0,906 + 3,430 s |
| Sonde mie sulle affermazioni del README | **0**, risultati sotto | 5,009 s |
| `./oracle/run.sh --all --check` finale, dopo i ripristini | **0**, 55 prove negative | 89,084 s |
| `git diff --exit-code`, stato legacy e perimetro PR | **0**, nessuna modifica tracciata residua | 0,134 s |

Due tentativi iniziali della mia sonda hanno avuto errori di compilazione propri — identificatore riservato e formato del `COPY` — corretti prima della prova valida. Sono registrati nei log, non sono difetti della PR.

**Stato dei due rilievi del primo giro**

| Rilievo | Stato |
|---|---|
| Controllo delle opzioni per prefisso | **Chiuso**: attacco originale e varianti sugli argomenti respinti. Il problema ambientale sotto è una prova nuova e distinta. |
| Segno DISPLAY senza `-fsign=EBCDIC` | **Chiuso**: opzione applicata, risultati corretti e rimozione intercettata. |

La verifica manuale parte dai byte, non dagli attesi dell’oracle. `CVTRA06Y` pone l’importo dopo 132 byte; l’ultima cifra incorporata dà:

| Record | Byte 133–143 | Decodifica manuale |
|---|---|---:|
| 1 | `0000005047G` | `G` = +7 → **+504,77** |
| 2 | `0000009190}` | `}` = −0 → **−919,00** |
| 23 | `0000000709R` | `R` = −9 → **−70,99** |
| 26 | `0000003250{` | `{` = +0 → **+325,00** |

Tutti i 300 record hanno nell’ultima posizione un carattere della convenzione dichiarata. Senza l’opzione ho osservato rispettivamente +504,70, +919,00, +70,90, +325,00; il controllo fallisce.

Le sonde mie (file locale del Validatore, non conservato) leggono e riscrivono record fissi con `PIC 9`, `COMP-3` firmato e non firmato, `SIGN LEADING SEPARATE` e `SIGN TRAILING SEPARATE`, usando valori positivi e negativivi dove ammessi. Con e senza `-fsign=EBCDIC`, valori e file prodotti sono identici byte per byte, anche rispetto all’ingresso. **Nessuna differenza nei casi provati**, senza generalizzazione a ogni operazione possibile.

Con il copybook originale `CVACT01Y`, `ACCT-CURR-BAL` occupa i byte 13–24: 11 byte di ID più un byte di stato. Il primo record di `acctdata.txt` contiene `00000001940{`: dodici cifre, due decimali, `{` positivo → **+194,00**, valore confermato dalla sonda. Ho verificato anche +158,00 e +147,00 nei record successivi.

Le nuove affermazioni del README sul segno corrispondono alle osservazioni. Ho inoltre riprodotto le misure marcate «misurata in validazione»:

- troncamento **2345 / 12345**;
- aritmetica intermedia **15,40 / 15,48**;
- confronto `'0'`/`'A'` invertito dalla collazione EBCDIC, mentre BDB restituisce sempre **0, A**;
- alternativa duplicata: stato **22**;
- record variabile `ABC`: **`00 03 00 00 41 42 43`**;
- salto di `NEXT SENTENCE` oltre il punto;
- inizializzazione **X'00'**, contro spazio/`'0'` con `defaultbyte=init`;
- output identico di `M03BCALL` con collegamento statico e dinamico.

Sono risultati delle sonde; la parità generale con z/OS resta non eseguita. La lettura del diff non ha prodotto altri rilievi dimostrati. Le esecuzioni consecutive non hanno mostrato falsi rossi.

1. **Importante — la configurazione effettiva del compilatore può cambiare senza che il controllo fallisca. Impatto: falso verde dimostrato; semantica dell’oracle alterata nella sonda. Non ho dimostrato una divergenza sui dati degli undici programmi integri.**

   [compile.sh:43](oracle/build/compile.sh#L43) registra e passa correttamente gli argomenti, ma lascia che `cobc` legga configurazione dall’ambiente. [verifica.sh:98](oracle/build/verifica.sh#L98) verifica versioni e backend, ignorando la configurazione alternativa che compare già nel rapporto d’ambiente. Il limite descritto in [README.md:180](oracle/README.md#L180) riguarda invece argomenti registrati falsamente: è un caso diverso.

   **Riproduzione eseguita:** ho copiato la configurazione originale dell’immagine, aggiunto `perform-osvs: no` a `ibm.conf` ed esportato dentro `compile.sh`:

   ```sh
   export COB_CONFIG_DIR=/oracle/.work/review/config
   ```

   Gli argomenti passati e registrati restano esattamente quelli attesi. Il rapporto reale (file locale del Validatore, non conservato) dichiara la variabile alternativa; nessuno strumento mente. L’intero controllo passa (file locale del Validatore, non conservato) con 55 prove negative.

   La mia sonda PERFORM (file locale del Validatore, non conservato) produce con la configurazione originale `B C D DONE`; con quella alternativa produce `B C D E AFTER-INNER B C D DONE`. È quindi una modifica semantica reale invisibile al cancello.

   La mutazione introduce l’export **dentro lo script**: non dimostra contaminazione dalla sola variabile impostata nella shell host.

   **Correzione richiesta:** fissare e verificare anche ambiente e file di configurazione effettivamente letti dal compilatore, includendoli nell’impronta quando esterni all’immagine; aggiungere questa prova negativa e dichiarare nel README il limite specifico finché rimane.