APPROVATA CON RISERVE

Validato `HEAD=dec220a`. Le mutazioni richieste ora falliscono; resta una lacuna minore sulla completezza dei verdetti salvati.

Tutte le prove nella tabella sono state **eseguite da me**. `C` indica `./analysis/run.sh --all --check`. Timeout imposti: 1.500 s per `--all`, 600 s per ogni `C`, 60 s per gli script di verifica. Ogni mutazione è stata ripristinata prima della successiva.

| Prova / mutazione | Comando | Esito osservato | Durata |
|---|---|---|---:|
| Rigenerazione 1 | `./analysis/run.sh --all` | 0 | 41,661 s |
| Controllo 1 | `C` | 0 | 63,478 s |
| Rigenerazione 2 | `./analysis/run.sh --all` | 0 | 41,937 s |
| Controllo 2 | `C` | 0 | 59,774 s |
| Cobmix: “scartato” → “adottato” nel documento | `C` | **1**, incoerenza documentale rilevata | 64,105 s |
| Verdetto scc: `pass` → `fail` | `C` | **1**, diverso dal ricalcolo | 56,220 s |
| Cancellata la prova della ripartizione `unavailable` | `C` | **1**, prova mancante | 2,181 s |
| Ripartizione dichiarata `available` | `C` | **1**, campioni codice/commenti discordanti | 2,438 s |
| Confronto attesi con giro 2; riconta righe/vuote e baseline dal sorgente | `python3 .validazione/campioni.py` | 0 | 0,069 s |
| Regressione: aggregato scc codice/commenti/vuote azzerato | `C` | **1**, somme incoerenti | 2,273 s |
| Regressione: campo rinominato nell’XML cb2xml, TSV invariato | `C` | **1**, rinormalizzazione diversa | 13,251 s |
| Regressione: `MVSWAIT` rinominato nel JSON cmt, TSV invariato | `C` | **1**, rinormalizzazione diversa | 13,026 s |
| Regressione: JCL `POSTTRAN/STEP15`, `PGM` → `PROC` | `C` | **1**, tipo errato | 4,549 s |
| Regressione: errori `CBSTM03A`, 39 → 9999 | `C` | **1**, discordanza con il log | 3,669 s |
| Cancellato il verdetto scc | `C` | **1**, `FileNotFoundError` nella fixture negativa | 74,606 s |
| Controllo dopo i ripristini | `C` | 0 | 68,464 s |
| **Cancellato il verdetto cb2xml** | `C` | **0, falso verde** | 60,761 s |
| Perimetro, Git, hash legacy e container dopo il ripristino | `python3 .validazione/finale.py` | 0 | 0,326 s |
| Due controlli consecutivi finali, senza mutazioni | `C`, poi `C` | 0 / 0 | 62,521 / 60,785 s |
| Verifica finale degli invarianti | `python3 .validazione/finale.py` | 0 | 0,354 s |

Non ho osservato falsi rossi nelle esecuzioni senza mutazioni. Ho usato le cache Docker presenti.

Lo stato dei tre rilievi del secondo giro è:

| Rilievo | Stato |
|---|---|
| Capacità conteggi disponibile nonostante campioni codice/commenti errati | **Chiuso**, secondo la specifica modificata |
| Cobmix dichiarabile adottato senza errore | **Chiuso** |
| Contenuto del verdetto scc incoerente con il ricalcolo | **Chiuso**; la cancellazione di un altro verdetto espone la lacuna distinta sotto |

La ripartizione codice/commenti è registrata `unavailable` in `capabilities.tsv:8` e `strumenti.md:110`. La prova salvata riproduce le differenze reali; cancellarla fa fallire il controllo. Dichiarare la capacità `available` fallisce direttamente sui campioni, prima del confronto documentale.

Ho **letto nuovamente i sei sorgenti**. Gli attesi attuali contengono soltanto i cinque campi manuali, senza colonne che sostituiscano i risultati errati di scc, e coincidono esattamente con i conteggi del secondo giro:

| Campione | Righe | Codice | Commenti | Vuote |
|---|---:|---:|---:|---:|
| `CVACT03Y.cpy` | 11 | 5 | 6 | 0 |
| `CVTRA05Y.cpy` | 21 | 15 | 6 | 0 |
| `COBSWAIT.cbl` | 41 | 13 | 22 | 6 |
| `POSTTRAN.jcl` | 45 | 22 | 23 | 0 |
| `CBACT01C.cbl` | 430 | 358 | 51 | 21 |
| `MVSWAIT.asm` | 30 | 14 | 16 | 0 |

La capacità **file, righe totali e vuote** è sostenuta dai campioni: righe e vuote coincidono con scc in tutti e sei. La verifica automatica sul sorgente conferma inoltre le baseline file/righe: `app/cbl` **31/20.650**, `app/cpy` **30/2.786**, `app/jcl` **38/2.429**. Confermati **186 file contati + 54 non contati = 240** nel manifesto sotto `app/`; la copertura mancante resta dichiarata. I 0,069 s misurano lo script, non la lettura manuale.

Il rilievo nuovo è:

1. **Minore — la riconciliazione non verifica la presenza di tutti i verdetti richiesti.**  
   Ho cancellato soltanto `analysis/tools/out/cb2xml/verdetto-layout.txt`: `C` termina con **0**, dichiarando «8 verdetti/prove salvati coincidono con il ricalcolo», invece dei nove normali.

   Evidenza: `analysis/tools/check.sh:52` enumera soltanto i file presenti; la riga 156 esclude i verdetti dal confronto con la rigenerazione; `analysis/tools/glue/check_docs.py:129` accetta implicitamente una lista di risultati vuota.

   **Correzione richiesta:** verificare l’insieme dei verdetti necessari alle prove eseguite, segnalando quelli mancanti, e aggiungere una prova negativa che cancelli il verdetto cb2xml.

   **Falso verde: sì**, sulla completezza delle evidenze consegnate. I campioni delle misure continuano a essere controllati.

Ho **letto integralmente** `diff-dal-giro-2.patch`, che coincide con il diff Git dal commit del secondo giro. Le cinque regressioni ripetute sopra non mostrano controlli indeboliti. Dalla lettura della colla e di `CopyLister.java` non risultano parser COBOL/JCL/copybook propri: vengono normalizzati output JSON/XML/CSV e usate le classi di ProLeap.

Il diff rispetto a `origin/main` comprende **129 file**, coincide con `file-modificati.txt` e tocca esclusivamente `analysis/` e `docs/legacy-map/strumenti.md`. Dopo i ripristini, `git status --short` mostra soltanto `.validazione/`; nessuna differenza negli output versionati, `git status --short legacy/` vuoto e hash del legacy invariati. Nessun container creato dalle prove è rimasto presente. Nessun comando globale di pulizia Docker, commit o push.