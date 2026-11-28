BOCCIATA

Validazione sullo SHA `6bc58ba`. Ho riprodotto un falso verde: un caricatore che altera il `FILLER`, insieme a un `IDXDUMP` che copia l’ingresso, supera anche tutte le prove di `dati --check`; il mio lettore indipendente rifiuta l’indice prodotto.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| 1 — generazione | `./analysis/run.sh oracle-dati` | 0; versionati invariati |
| 1 — ripetibilità | `./analysis/run.sh oracle-dati --check`, due volte | 0 / 0; 151 prove negative per corsa |
| Build richiesta | `./oracle/run.sh build` | 0; 28 programmi |
| 2 — caricamento | `./oracle/run.sh dati` | 0 |
| 2 — ripetibilità | `./oracle/run.sh dati --check`, due volte | 0 / 0; 61 prove negative, 4 controprove |
| 3 — oracle completo | `./oracle/run.sh --all --check` | 0 |
| 3 — analisi completa | `./analysis/run.sh --all --check` | 0, conclusa entro 15 minuti; alternativa non necessaria |
| 4 — conteggi CI | Log locale confrontato tramite `gh` con run `46098647517` | Coincidenti per ogni passo |
| 5 — stato e perimetro | `git diff --exit-code`, `git status --short`, stato del submodule | Nessuna modifica introdotta; resta soltanto `?? .validazione/`, già presente all’inizio |
| 6 — CI finale | `gh pr view 58 --json headRefOid,statusCheckRollup` | `analysis-check`, `oracle-check`, `verify`, `smoke`: tutti `SUCCESS` sullo SHA finale |
| 7 — storia | `git show` dei quattro commit iniziali | Tabella e attesi `549f1d1` precedono la colla `4555b40`; attesi oracle `0840b1d` precedono `5aa49d0` |

File fuori perimetro: **nessuno**. Nessun atteso preesistente modificato; nella build cambiano soltanto `PROVE`, `ACCESSORI` e `PASSI`.

Conteggi locale/CI, espressi come **negative / controprove / prove con file illeggibili**:

| Passo | Locale = CI |
|---|---|
| build | 172 / 4 / 5 |
| abend | 7 / 0 / 0 |
| adattamenti | 54 / 0 / 1 |
| avviatore | 5 / 0 / 0 |
| avvio | 14 / 1 / 0 |
| dati | 61 / 4 / 0 |
| dialetto | 3 / 1 / 0 |
| routines | 141 / 10 / 0 |
| segno | 5 / 0 / 0 |
| selftest | 3 / 0 / 0 |

La conversione indipendente, campo per campo con pagina 037 e regola del segno C/D, coincide su **15.000/15.000 byte**, inclusi `FILLER`. Le chiavi sono precisamente 1–50, crescenti; i 250 importi hanno zona C, nessuno zona D. Gli attesi a mano coincidono con entrambi i profili. La sola differenza ASCII è lo ZIP del record 49: `A000000000` contro `ZEROAPR   `.

I riferimenti verificati nel legacy sono `app/jcl/ACCTFILE.jcl:25` (`DELETE`), `:40` (`KEYS`), `:41` (`RECORDSIZE`), `:57` (origine), `:61` (`REPRO`); `app/cbl/CBACT01C.cbl:29` e `:52` (`SELECT`/`FD`); `app/cpy/CVACT01Y.cpy:5–17` (campi e lunghezze). Per il file EBCDIC, la posizione verificata dello ZIP è il record 49, byte 103–112; nel file ASCII è la riga 49. Il precedente `IDXLOAD` riempie effettivamente con spazi e omette il controllo della chiusura dell’ingresso (`oracle/tests/IDXLOAD.cbl:126`, `:152`).

| Controprova specifica | Esito osservato |
|---|---|
| Lettore COBOL mio, `SELECT`/`FD` di CBACT01C | 50 record, tutti i byte uguali, ordine crescente, EOF 10; `START`/`READ` su 1, 25 e 49: stato 00 |
| Ingressi 14.999, 15.001 e 299 byte | `IDXLOADF` termina con 8 |
| Ingresso vuoto | Caricatore 0; passo `dati` 1, nessun indice pubblicato |
| NUL, LF/CR e `0x1A` nel `FILLER` | Conservati byte per byte |
| Chiave non numerica | Caricatore 0 e byte conservati; `dati` respinge l’ingresso |
| Record 10 e 11 scambiati | Stato WRITE 21 dopo 10 record, uscita 8 |
| `FILLER` e relativo hash nell’elenco alterati insieme | Rifiutati con `F05` |
| Segno riscritto con zona F | Controllo semantico 2 accetta; controprova ASCII respinge |
| Conversione errata di `ACCT-GROUP-ID` in tutti i record | Generazione respinta con `F05` |
| Controprova modificata per accettare differenze aggiuntive | `oracle-dati --check` fallisce sulla prova del `FILLER` |
| Caricatore che riempie il record corto / salta l’ultimo | Rilevati dal passo e dai controlli |
| `dati` rimosso da `PASSI` / cartella cancellata | Entrambe le mutazioni rilevate |
| Indice precedente seguito da caricamento fallito | Rimosso; restano invece residui sugli errori preliminari descritti sotto |

Il controllo 2 condivide codec e adattatore con la generazione; legge però la fixture preesistente. Il controllo 3 usa una via distinta, con utility POSIX. Il backend osservato è BDB: l’indice consiste nel solo `ACCTFILE.dat`, senza componenti `.idx`.

Il ramo READ d’errore è raggiungibile senza modificare libcob: `/proc/self/mem` produce stato 30 e uscita 8. Non attesto la copertura dei rami CLOSE: l’errore nativo di chiusura iniettato non ha prodotto uno stato COBOL diverso da 00.

Rilievi:

1. **Bloccante — rilettura “indipendente” dipendente dallo stesso programma.**  
   In `oracle/dati/check.sh:49–58`, `rileggi` richiama ancora `IDXDUMP`, usato anche da `carica.sh` e dalla verifica finale. Ho mantenuto le dichiarazioni controllate e sostituito la lettura dell’indice con una copia dell’ingresso/rilettura precedente: build, `dati` e tutte le 61 prove passano. Aggiungendo al caricatore `MOVE "." TO ENT-REC(181:1)`, passano ancora; il mio lettore termina con 8 al primo record. [Mutazioni riproducibili](/tmp/menb-val58-logs/false-green-mutations.patch), [log del falso verde](/tmp/menb-val58-logs/combined-check.log), [lettura indipendente](/tmp/menb-val58-logs/combined-independent.log).  
   **Schema:** generatore e verifiche possono confermarsi copiando lo stesso ingresso senza osservare l’artefatto. **Correzione richiesta:** controllo indipendente che legga realmente l’indice e prove negative delle due sostituzioni sopra. **Falso verde/oracle infedele:** entrambi dimostrati. **Riproduzione:** modifica di sorgenti versionati in una copia e normale rebuild; nessuna falsificazione di attesi o impronte.

2. **Bloccante — risultato precedente conservato quando fallisce la preparazione.**  
   `oracle/dati/run.sh:32–37` può uscire prima dell’installazione della trap a riga 51. Dopo una corsa valida, ingresso inesistente oppure directory degli attesi assente danno uscita 1 ma lasciano il vecchio `ACCTFILE.dat` al percorso stabile. [Evidenza](/tmp/menb-val58-logs/lifecycle.log).  
   **Schema:** invalidazione dell’artefatto applicata soltanto a una parte delle uscite d’errore. **Correzione richiesta:** garantire la rimozione del risultato corrente anche per errori preliminari, inclusi build, binari, ingresso e attesi; aggiungere prove con residuo sano. **Falso verde:** il comando resta rosso; **oracle infedele:** possibile per chi consuma il file rimasto. **Riproduzione:** nessuna modifica versionata né artefatto falsificato.

3. **Importante — pubblicazione prima dell’ultima verifica.**  
   Il `mv` al percorso stabile avviene in `oracle/dati/run.sh:93`; la rilettura finale inizia a riga 104. Intercettando quella chiamata e facendola fallire con 42, ho osservato il file già pubblicato prima della verifica. Dopo l’errore viene rimosso. [Evidenza](/tmp/menb-val58-logs/lifecycle.log).  
   **Schema:** risultato visibile durante una verifica ancora pendente. **Correzione richiesta:** pubblicare come ultimo atto il medesimo artefatto già verificato, aggiungendo una prova sul momento della pubblicazione. **Falso verde finale:** non osservato; **oracle non verificato disponibile:** sì. **Riproduzione:** nessuna modifica versionata né falsificazione di artefatti; solo errore di comando.

4. **Importante — controllo della dimensione separato dal file effettivamente letto.**  
   Tra `CBL_CHECK_FILE_EXIST` e `OPEN INPUT` (`oracle/tests/IDXLOADF.cbl:95–114`) ho sostituito tramite rename il file da 15.000 byte con quello da 14.999. Il caricatore **non modificato** scrive 50 record ed esce con 0. La sonda conferma che GnuCOBOL restituisce 00 per il record incompleto. [Evidenza](/tmp/menb-val58-logs/rename-race.log).  
   **Schema:** metadati verificati su una versione del file e lettura su un’altra. **Correzione richiesta:** verificare la completezza dei record rispetto all’ingresso realmente aperto/letto e aggiungere la prova di sostituzione. **Falso verde:** del caricatore; il confronto di `dati` respinge invece la diversa lunghezza. **Oracle infedele:** possibile nell’uso diretto del caricatore. **Riproduzione:** nessuna modifica versionata; sostituzione dell’ingresso generato dopo uno `stat` reale.

5. **Importante — esiti di comando ancora ignorati.**  
   `oracle/dati/check.sh:65` e `analysis/oracle-dati/check.sh:75,131,140` trattano l’errore di `cmp` come differenza. Con `cmp` che esegue il confronto e poi restituisce 42, entrambi gli helper accettano una modifica nulla. A riga 133 dell’analisi c’è anche un `wc` non controllato dentro `[ ]`. Inoltre `oracle/dati/run.sh:43–49` restituisce 0 quando la rimozione dei temporanei fallisce: riprodotto con `rm` a 42, cartella rimasta e solo messaggio diagnostico. [Evidenza helper](/tmp/menb-val58-logs/lifecycle.log), [evidenza cleanup](/tmp/menb-val58-logs/cleanup-oracle.log).  
   **Schema:** errore operativo confuso con risultato ordinario oppure ridotto a messaggio. **Correzione richiesta:** distinguere esplicitamente `cmp` 0/1/errore, controllare le sostituzioni e propagare il fallimento della pulizia; estendere le prove anche all’ultima invocazione di `rm`. **Falso verde operativo:** dimostrato; alterazione dell’oracle non dimostrata da questi soli casi. **Riproduzione:** nessuna modifica versionata o falsificazione di artefatti; comandi che restituiscono errore.

6. **Minore — documentazione contraddittoria dopo l’aggiunta del passo.**  
   `oracle/README.md:240` afferma ancora che file indicizzati reali vengono creati e letti *solo* nello scenario `CBSTM03A`, contraddicendo il nuovo passo `dati` descritto nello stesso documento.  
   **Schema:** descrizione generale rimasta allo stato precedente. **Correzione richiesta:** aggiornare quel paragrafo. **Falso verde/oracle infedele:** no. **Riproduzione:** semplice lettura; correzione del file versionato, nessun artefatto coinvolto.

I [log completi dell’analisi](/tmp/menb-val58-logs/analysis-all.log) e [dell’oracle](/tmp/menb-val58-logs/oracle-all.log) riportano nomi e diagnosi delle prove automatiche. Tutte le modifiche temporanee sono state ripristinate; nessun commit. Container, volumi e immagini con prefisso `menb-val58-` sono stati rimossi; risorse condivise conservate.