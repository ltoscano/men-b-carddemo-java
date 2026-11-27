# Adattamenti dell'oracle (issue #25)

`CBSTM03A` è il batch che produce gli estratti conto, in testo (`STMTFILE`) e in HTML (`HTMLFILE`). Così com'è non compila con GnuCOBOL (esito di #1) e, anche compilato, non potrebbe girare in un container. Questo registro elenca i due soli adattamenti ammessi (voci 19 e 21 del registro delle approvazioni, `docs/registro-approvazioni.md`), lo scenario con cui si dimostra che la copia adattata produce davvero estratti conto, e ciò che resta non verificato.

Due fatti distinti, registrati entrambi:

- **l'originale è rifiutato da GnuCOBOL**: i risultati dell'analisi del legacy (`analysis/`, `docs/legacy-map/`) restano quelli dell'originale e non cambiano;
- **la copia adattata è eseguibile**: è quella che l'oracle compila ed esegue.

Gli adattamenti si applicano a **copie di compilazione** generate a ogni build da `adatta.sh` in `oracle/build/out/adattati/` (cartella nuova a ogni build, non versionata). Il legacy non si tocca. Le copie e lo script che le genera entrano nell'impronta della build (`oracle/lib.sh`: `adatta.sh` tra gli input, le copie tra gli artefatti).

## Adattamento 1: TAB in `CUSTREC.cpy`

| Voce | Contenuto |
| --- | --- |
| File | `app/cpy/CUSTREC.cpy` (incluso da `CBSTM03A` alla riga 55, `COPY CUSTREC`) |
| Righe | 6-22: le 17 righe che contengono caratteri TAB (due TAB in testa a ognuna; la riga 11 ne ha altri due in coda) |
| Trasformazione | ogni TAB diventa gli spazi che servono a raggiungere la tabulazione successiva, con **tabulazioni ogni 4 colonne**. Le altre righe restano identiche byte per byte. Effetto: in testa alle righe 6-22 i due TAB diventano 8 spazi, e il livello `05` comincia in colonna 14 invece che in colonna 12 come alla riga 5 |
| Perché 4 e non 8 | con tabulazioni ogni 8 colonne il testo della riga 6 supererebbe la colonna 72, che nel formato fisso è l'ultima letta: la `PIC` verrebbe troncata (rilievo 1 della contestazione della specifica). Verificato dalla prova negativa 1: con 8 colonne la compilazione con gli argomenti della build fallisce |
| Motivo | nel formato fisso GnuCOBOL rifiuta i TAB del copybook; sostituirli con spazi non cambia il programma |
| Voce del registro | 19 |
| Effetto osservabile | nessuno: il tracciato che ne risulta è quello del copybook (record di 500 byte, ogni campo nella sua posizione), verificato contro un atteso scritto a mano |
| Uso della copia | solo per compilare `CBSTM03A`: la build mette `-I/out/adattati` come primo argomento di `cobc` per questo solo programma (cobc cerca le cartelle `-I` nell'ordine dato). Gli altri programmi continuano a leggere `/legacy/app/cpy`: lo verificano gli argomenti di `cobc` registrati e confrontati da `build/verifica.sh` |

Come lo si verifica (`verifica-copie.sh copie` e `tracciato`, in `adattamenti --check`):

- la copia è identica alla riapplicazione della trasformazione sull'originale fatta con uno strumento diverso da quello della build (`expand -t 4` di coreutils; la build usa un `awk` che conta le colonne);
- nella copia non resta alcun TAB e nessuna riga ha caratteri diversi dallo spazio oltre la colonna 72;
- le righe con TAB dell'originale sono esattamente le 17 righe 6-22; tutte le altre sono identiche nella copia;
- `CBSTM03A` viene ricompilato in sola analisi con gli argomenti di `cobc` registrati dalla build (stesse opzioni, stessa copia, stessa cartella `-I`) più il listato dei simboli (`-t -ftsymbols`): il tracciato di `CUSTOMER-RECORD` visto dal compilatore (nome, posizione, lunghezza di ognuno dei 19 campi, record di 500 byte) coincide con `expected/custrec-tracciato.tsv`, scritto a mano leggendo il copybook, con la riga di ogni campo;
- nella stessa compilazione l'elenco dei file letti (`-MT -MF`) dice che `CUSTREC` viene dalla copia adattata e `COSTM01`, `CVACT03Y`, `CVACT01Y` da `/legacy/app/cpy`.

Su macOS la cartella della build è un bind mount che non distingue le maiuscole: `cobc` prova le estensioni nell'ordine `.CPY`, `.cpy` e apre `adattati/CUSTREC.CPY`, che lì è lo stesso file di `adattati/CUSTREC.cpy`. Il controllo dei file letti riporta un nome sotto `adattati/` al file della cartella che è lo stesso file (`test -ef`, stesso dispositivo e inode); su Linux il nome è già `CUSTREC.cpy`. La cartella contiene esattamente le due copie (verificato), quindi non c'è un altro file che possa essere letto al loro posto.

Se su z/OS il membro del copybook contenesse spazi e non TAB (i TAB potrebbero essere nati nel passaggio al repository) non è verificabile: il sorgente di riferimento è quello del repository al commit `59cc6c2`.

## Adattamento 2: blocchi di controllo z/OS in `CBSTM03A`

| Voce | Contenuto |
| --- | --- |
| File | `app/cbl/CBSTM03A.CBL` |
| Righe | 266-291 della `PROCEDURE DIVISION`: le 23 righe non vuote 266-270, 272-273, 275-285, 287-291. Le righe vuote 271, 274, 286 restano identiche |
| Trasformazione | lo spazio in colonna 7 diventa `*` (riga di commento). Nient'altro: stesso numero di righe, stesso numero di byte, 23 byte diversi in tutto. `ALTER` e `GO TO` (righe 298-314 e 725-852) non si toccano |
| Motivo | quelle righe seguono con puntatori i blocchi di controllo di z/OS: `PSAPTR` è un `POINTER` senza `VALUE` (nullo), e su z/OS all'indirizzo 0 c'è il PSA; da lì il TCB (offset 536), poi il TIOT (offset 12 del TCB), di cui stampano nome del job, passo e nomi DD. In un container all'indirizzo 0 non c'è nulla: il programma si fermerebbe alla prima lettura |
| Voce del registro | 21 |
| Effetto osservabile | le righe di console qui sotto non sono riprodotte dall'oracle |

**Righe di console non riprodotte dall'oracle** (su z/OS vanno a `SYSOUT` prima di qualsiasi apertura di file):

| Riga del sorgente | Testo |
| --- | --- |
| 270 | `Running JCL : <nome del job> Step <nome del passo>` |
| 275 | `DD Names from TIOT: ` |
| 279 | `: <nome DD> -- valid UCB` (una per ogni voce del TIOT con UCB) |
| 281 | `: <nome DD> --  null UCB` (una per ogni voce senza UCB; due spazi prima di `null`) |
| 288 o 290 | dopo il ciclo, una riga per la voce su cui il ciclo si è fermato: `: <nome DD> -- valid UCB` oppure `: <nome DD> -- null  UCB` (due spazi dopo `null`) |

Chi confronterà la console del Java con quella dell'oracle deve escludere queste righe: l'oracle non le produce e non inventa valori al loro posto.

### Nessun dato di quelle righe è letto altrove

Analisi sul sorgente originale; elenco completo in `expected/blocchi-zos.tsv`, verificato da `verifica-copie.sh zos` con una ricerca senza distinzione di maiuscole su tutto il sorgente.

| Dato | Dichiarazione | Usi (tutti nelle righe 266-291) |
| --- | --- | --- |
| `PSAPTR` | 235 (`WORKING-STORAGE`) | letto alla 266 |
| `BUMP-TIOT` | 236; ridefinito da `TIOT-INDEX` alla 237 | scritto alle 272 e 283 |
| `TIOT-INDEX` | 237 (`REDEFINES BUMP-TIOT`) | scritto alla 269, letto alle 273 e 284 |
| `ALIGN-PSA` | 240 (`LINKAGE`) | mai usato |
| `PSA-BLOCK`, `TCB-POINT` | 241, 243 | indirizzo impostato alla 266; `TCB-POINT` letto alla 267 |
| `TCB-BLOCK`, `TIOT-POINT` | 244, 246 | indirizzo impostato alla 267; `TIOT-POINT` letto alle 268 e 269 |
| `TIOT-BLOCK`, `TIOTNJOB`, `TIOTJSTP`, `TIOTPSTP` | 247-250 | indirizzo alla 268; `LENGTH OF` alla 272; `TIOTNJOB` e `TIOTJSTP` letti alla 270; `TIOTPSTP` mai usato |
| `TIOT-ENTRY`, `TIOT-SEG`, `TIO-LEN`, `TIOCDDNM`, `UCB-ADDR`, `NULL-UCB`, `END-OF-TIOT` | 251-260 | indirizzo alle 273 e 284; `LENGTH OF TIOT-SEG` alla 283; letti alle 276-281 e 287-290 |

Fuori dalle righe 266-291 questi nomi compaiono solo nelle loro dichiarazioni (righe 235-260). Sono tutti livelli 01 o loro subordinati, nessuno fa parte di un gruppo usato altrove, e l'unica `REDEFINES` è tra due di loro. Le righe commentate non contengono nomi di paragrafo né bersagli di `PERFORM` o `GO TO`: stanno nel primo paragrafo senza nome della `PROCEDURE DIVISION`, e l'ultima (291) chiude la propria frase con il punto. Commentate, il programma passa dall'inizio della `PROCEDURE DIVISION` direttamente a `OPEN OUTPUT STMT-FILE HTML-FILE` (riga 293), come l'originale dopo quel blocco. Le dichiarazioni di `LINKAGE` e `WORKING-STORAGE` usate solo lì restano come sono (GnuCOBOL avverte che `TIOT-INDEX` è più grande di `BUMP-TIOT`: è uno dei 5 avvertimenti di compilazione, gli altri 4 dicono che `ALTER` è obsoleto).

Come lo si verifica (`verifica-copie.sh copie`): confronto riga per riga tra copia e originale. Le righe diverse devono essere esattamente le 23 dell'elenco, ognuna diversa solo nella colonna 7 (spazio nell'originale, `*` nella copia); le righe vuote 271, 274, 286 vuote in entrambe; stesso numero di righe e di byte; `cmp -l` conta 23 byte diversi.

## Integrazione nella build

`CBSTM03A` entra in `oracle/programs.tsv` come eseguibile: i programmi del legacy compilati diventano 12. `build/compile.sh` lo compila dalla copia (elenco fisso `ADATTATI`), con un solo argomento in più rispetto agli altri eseguibili:

```
cobc -I/out/adattati <opzioni di cobc.opts> -c -o /out/obj/CBSTM03A.o /out/adattati/CBSTM03A.CBL
cobc -x -A -DMENB_ENTRY=CBSTM03A -o /out/bin/CBSTM03A /oracle/launcher/avvia.c /out/obj/CBSTM03A.o
```

`build/check.sh` lo verifica come gli altri, con questi argomenti esatti (prove negative: `-I/out/adattati` tolto dal log, sorgente originale al posto della copia, `CBCUS01C` ricompilato davvero con `-I/out/adattati`, copia cancellata o alterata dopo la build, generazione delle copie che fallisce). `CBSTM03B` resta il modulo compilato dall'originale. Il comando resta `./oracle/run.sh build`. La prova di avvio (`avvio`) lancia anche `CBSTM03A` senza file: apre `STMTFILE` e `HTMLFILE` (vuoti), trova `TRNXFILE` assente e si ferma come prescrive il sorgente (righe 736-742 e 921-923): `ERROR OPENING TRNXFILE`, `RETURN CODE: 35`, `ABENDING PROGRAM`, codice 99.

## Scenario (passo `adattamenti`)

`./oracle/run.sh adattamenti` esegue `CBSTM03A` su quattro file indicizzati costruiti a ogni corsa, in una cartella nuova, dai file di testo di `scenario/`:

1. `IDXLOAD` (`oracle/tests/IDXLOAD.cbl`, compilato con le stesse opzioni) carica ogni file con le chiavi e le lunghezze di `CBSTM03B` (righe 31-53 e 58-78): `TRNXFILE` 350 byte, chiave 1-32; `XREFFILE` 50 byte, chiave 1-16; `CUSTFILE` 500 byte, chiave 1-9; `ACCTFILE` 300 byte, chiave 1-11. Scrive in accesso sequenziale nell'ordine del testo: una chiave non crescente ferma il caricamento;
2. prima di eseguire `CBSTM03A`, `IDXDUMP` (indipendente da `IDXLOAD`) rilegge ogni file in ordine di chiave e `verifica-carico.sh` lo confronta record per record con il testo: numero di record, byte, chiavi e ordine, lunghezza delle righe, riempimento con spazi fino alla lunghezza del record. Un caricamento infedele ferma lo scenario (prova negativa 8: caricatore che azzera il FICO);
3. `CBSTM03A` gira con `oracle/esegui.sh`; `STMTFILE` e `HTMLFILE` non hanno DD e si creano nella cartella di lavoro del programma (con `-std=ibm` senza variabile `DD_<nome>` il file prende il nome DD).

### Carte, clienti, conti

Righe prese dai dati di esempio (`app/data/ASCII/`) senza modifiche; provenienza in `scenario/origine.tsv`, verificata da `origine.sh` sui dati del legacy.

| Carta (`cardxref.txt`) | Cliente (`custdata.txt`) | Conto (`acctdata.txt`) | Movimenti |
| --- | --- | --- | --- |
| `0500024453765740` (riga 1) | `000000050` Aniya Alba Von, riga 50 | `00000000050`, saldo +492,00, riga 50 | 2 |
| `0683586198171516` (riga 2) | `000000027` Ward Henri Jones, riga 27 | `00000000027`, saldo +284,00, riga 27 | 0 |
| `0923877193247330` (riga 3) | `000000002` Enrico April Rosenbaum, riga 2 | `00000000002`, saldo +158,00, riga 2 | 2 |

Le righe di `cardxref.txt` hanno 36 caratteri: i 14 byte di `FILLER` di `CVACT03Y` (byte 37-50) mancano nel file e il caricamento li riempie con spazi (riempimento dichiarato e verificato). Nei file di testo clienti e conti sono in ordine di chiave (2, 27, 50), come vuole il caricamento sequenziale.

La carta senza movimenti sta in mezzo: per lei la ricerca nella tabella dei movimenti (righe 417-432) si ferma sulla condizione `WS-CARD-NUM (CR-JMP) > XREF-CARD-NUM` (riga 419) senza scrivere movimenti.

Distribuzione 2 + 2 + 0 invece di 2 + 1: con un solo movimento il totale della carta coincide per forza con il suo importo, e la specifica chiede importi e totali tutti diversi. Con 2 + 2 i sette valori sono tutti diversi: importi +183,88, -47,88, +355,11, -763,00; totali +136,00, 0,00, -407,89. Un movimento attribuito alla carta sbagliata o un totale non azzerato al cambio di carta (righe 819-825, 316-326, 416-434) cambierebbe almeno uno di questi valori (per esempio il terzo totale diventerebbe -271,89).

### Movimenti

I movimenti hanno il tracciato di `TRNXFILE` (`COSTM01.CPY`, 350 byte), cioè quello prodotto dal passo `SORT` di `CREASTMT.JCL` (righe 44-59): `OUTREC FIELDS=(1:263,16,17:1,262,279:279,50)` applicato ai record di `TRANSACT`. Si costruiscono applicando la stessa trasformazione a quattro righe di `dailytran.txt`, che ha lo stesso tracciato di `TRANSACT` (`CVTRA06Y` = `CVTRA05Y`, campo per campo):

| Campo di `TRNXFILE` (`COSTM01`) | Byte in `TRNXFILE` | Da `dailytran.txt` (`CVTRA06Y`) |
| --- | --- | --- |
| `TRNX-CARD-NUM` | 1-16 | 263-278 `DALYTRAN-CARD-NUM` |
| `TRNX-ID` | 17-32 | 1-16 `DALYTRAN-ID` |
| `TRNX-TYPE-CD` | 33-34 | 17-18 |
| `TRNX-CAT-CD` | 35-38 | 19-22 |
| `TRNX-SOURCE` | 39-48 | 23-32 |
| `TRNX-DESC` | 49-148 | 33-132 |
| `TRNX-AMT` | 149-159 | 133-143 |
| `TRNX-MERCHANT-ID` | 160-168 | 144-152 |
| `TRNX-MERCHANT-NAME` | 169-218 | 153-202 |
| `TRNX-MERCHANT-CITY` | 219-268 | 203-252 |
| `TRNX-MERCHANT-ZIP` | 269-278 | 253-262 |
| `TRNX-ORIG-TS` | 279-304 | 279-304 `DALYTRAN-ORIG-TS` |
| `TRNX-PROC-TS` | 305-330 | 305-328 (i primi 24 byte di `DALYTRAN-PROC-TS`: l'`OUTREC` copia 50 byte da 279) e 2 spazi |
| `FILLER` | 331-350 | spazi |

I byte 329-350 non sono determinati dal JCL: cosa scriva DFSORT oltre il record riformattato quando `LRECL` è più lungo non è verificato (servirebbe z/OS). Qui sono spazi. `CBSTM03A` non li emette: copia `TRNX-REST` nella tabella e ne scrive solo `TRNX-DESC` e `TRNX-AMT`. Anche `DALYTRAN-PROC-TS` è vuoto nei dati di esempio (il file giornaliero non è ancora registrato); nel flusso reale `TRANSACT` ha quel campo valorizzato da `CBTRN02C`, e anch'esso non è emesso.

| Riga di `trnxfile.txt` | Riga di `dailytran.txt` | Carta | `TRNX-ID` | Descrizione | Importo |
| --- | --- | --- | --- | --- | --- |
| 1 | 21 | `0500024453765740` | `0000000058866561` | Purchase at Blick-Rippin | `0000001838H` = +183,88 |
| 2 | 184 | `0500024453765740` | `0000000577826814` | Return item at DuBuque, Wuckert and Mraz | `0000000478Q` = -47,88 |
| 3 | 24 | `0923877193247330` | `0000000070754800` | Purchase at Blick, Kris and Gerlach | `0000003551A` = +355,11 |
| 4 | 87 | `0923877193247330` | `0000000274427056` | Return item at Gibson-Maggio | `0000007630}` = -763,00 |

Il segno è nell'ultimo carattere, con la convenzione EBCDIC dei dati del legacy (`H` = 8 positivo, `Q` = 8 negativo, `A` = 1 positivo, `}` = 0 negativo; vedi la sezione "Segno dei numeri DISPLAY" di `oracle/README.md`). Le righe sono in ordine di chiave (carta, poi identificativo).

### Attesi e cosa è verificato a mano

| File | Cosa contiene | Come è stato scritto |
| --- | --- | --- |
| `expected/verifica-a-mano.tsv` | 117 righe: 72 campi dinamici (nome, indirizzo, conto, saldo, FICO, identificativo, descrizione e importo di ogni movimento in entrambi gli output; il totale solo nel testo, perché il sorgente non lo scrive nell'HTML, righe 433-454), 33 chiusure (per l'HTML, ciò che segue ogni campo fino alla fine del record: fissa dove il campo finisce), 12 marcatori di inizio e fine estratto. Per ognuna: file, record, posizione, lunghezza, valore, riga del sorgente | **a mano dagli ingressi e dal sorgente, prima di eseguire `CBSTM03A` sullo scenario** (versionato nel commit `15f6c08`, che precede la prima esecuzione). Alla prima esecuzione tutti i 117 valori coincidevano |
| `expected/record.tsv` | numero e lunghezza dei record: `STMTFILE` 61 da 80 byte, `HTMLFILE` 236 da 100 | a mano dal sorgente, nello stesso commit |
| `expected/CBSTM03A.txt`, `.ambiente` | rapporto: codice 0, stdout vuoto, file creati con le dimensioni; ambiente ricevuto | a mano nello stesso commit; la riga di libxml2 su stderr è quella che compare in ogni programma dell'oracle |
| `expected/STMTFILE`, `expected/HTMLFILE` | l'output registrato, confrontato byte per byte | **registrato** dalla prima esecuzione, dopo che i valori a mano erano stati verificati |
| `expected/senza-ACCTFILE.txt` | arresto della prova negativa 9 | codice 99 e stdout a mano dal sorgente (righe 807-813 e 921-923) e dallo stub di `CEE3ABD`; le 5 righe `libcob: warning: implicit CLOSE of ...` su stderr e il loro ordine (inverso a quello di apertura) sono **osservati**: dipendono da libcob, non dal sorgente COBOL |
| `oracle/avvio/expected/CBSTM03A.txt` | arresto senza file | come sopra; l'ordine delle 2 righe di libcob segue quello osservato nella prova 9 |
| `expected/custrec-tracciato.tsv`, `expected/blocchi-zos.tsv` | tracciato di `CUSTREC`; occorrenze dei dati delle righe 266-291 | a mano dal copybook e dal sorgente, nello stesso commit |

**Non verificato a mano:** il testo fisso dell'estratto (righe di trattini e di asterischi, intestazioni, etichette) e il markup HTML (le righe `HTML-L01`…`HTML-L80` e le parti fisse delle righe con campi). Sono nell'output registrato e il confronto byte per byte ne fissa il contenuto, ma nessuno li ha ricavati a mano.

Comportamenti del sorgente visibili nell'output, ricavati a mano e confermati:

- la città è troncata al primo spazio (`STRING ... DELIMITED BY ' '`, righe 472-481): `New Aricchester` → `New`, `Port Dwight` → `Port`, `West Bernita` → `West`;
- nell'HTML nome e righe d'indirizzo si fermano ai primi due spazi consecutivi e sono seguiti da due spazi e `</p>` (righe 560-592);
- saldo con `PIC 9(9).99-` (zeri iniziali, spazio finale se positivo); importi e totali con `PIC Z(9).99-` (zero → `         .00 `, negativo con `-` finale);
- `ST-ACCT-ID` e `ST-FICO-SCORE` sono `PIC X(20)`: nell'HTML il valore è seguito dagli spazi di riempimento prima di `</p>`.

### I quattro rami di apertura

Le aperture riuscite non stampano nulla (righe 730-815), quindi la dimostrazione è indiretta:

1. **Flusso letto sul sorgente.** `WS-FL-DD` vale `TRNXFILE` all'avvio (riga 67). `0000-START` (righe 298-314) fa `ALTER 8100-FILE-OPEN TO PROCEED TO 8100-TRNXFILE-OPEN` e `GO TO 8100-FILE-OPEN`: apertura e prima lettura di `TRNXFILE`, poi `WS-FL-DD` = `READTRNX` e il ciclo di `8500-READTRNX-READ` legge tutti i movimenti; alla fine (`8599-EXIT`) `WS-FL-DD` = `XREFFILE` e si torna a `0000-START`, che con un nuovo `ALTER` porta a `8200-XREFFILE-OPEN`; da lì `CUSTFILE` → `8300`, `ACCTFILE` → `8400`, che con `GO TO 1000-MAINLINE` comincia gli estratti. A `1000-MAINLINE` si arriva solo da `8400-ACCTFILE-OPEN`, a cui si arriva solo dal ramo `ACCTFILE`, il cui valore è impostato solo da `8300`, e così a ritroso fino a `TRNXFILE`. Ogni apertura che non restituisce `00` o `04` stampa `ERROR OPENING <DD>` e termina con 99.
2. **Ritorno normale.** Codice di uscita 0 e stdout vuoto: nessuna apertura né lettura ha fallito.
3. **Output completi verificati.** Tre estratti, uno per carta, con i quattro movimenti alle carte giuste: i movimenti sono stati letti e messi in tabella, e i tre file con accesso diretto sono stati letti per chiave.
4. **Prove negative.** Con un `ALTER` reindirizzato (prova 6) l'output cambia: l'`ALTER` ha effetto nell'oracle. Con `ACCTFILE` assente (prova 9) il programma passa dai primi tre rami e si ferma al quarto con il messaggio prescritto.

### Prove negative di `adattamenti --check`

Ognuna deve fallire per il motivo dichiarato (sottostringa del messaggio d'errore, `expect_fail` in `oracle/lib.sh`):

1. `adatta.sh` con tabulazioni ogni 8 colonne: la compilazione con gli argomenti della build fallisce; testo oltre la colonna 72;
2. un TAB lasciato nella riga 7 della copia di `CUSTREC`;
3. `CUST-MIDDLE-NAME` spostato di una colonna (stesso testo, spazi diversi): fallisce il confronto con la riapplicazione indipendente, mentre il tracciato resta valido;
4. riga 270 non commentata; riga 293 commentata; riga 300 modificata; riga vuota 271 alterata;
5. `CBSTM03B.so` assente, con un residuo sano della corsa buona nella cartella d'uscita: `libcob: error: module 'CBSTM03B' not found` alla prima `CALL`;
6. `ALTER` della riga 300 reindirizzato a `8200-XREFFILE-OPEN` in una copia di prova, compilata davvero: l'output differisce;
7. importo del primo movimento cambiato (+183,88 → +183,89): differiscono l'output registrato e i valori ricavati a mano, e la provenienza dichiarata non regge più;
8. un byte alterato in `STMTFILE`, `HTMLFILE` e nel rapporto attesi; il FICO alterato in `verifica-a-mano.tsv`; un caricatore che azzera il FICO dei clienti, compilato davvero: la verifica del caricamento ferma lo scenario prima di `CBSTM03A`;
9. `ACCTFILE` assente: codice 99, distinto dal successo, e arresto uguale a `expected/senza-ACCTFILE.txt`.

Prove dei controlli propri: campo di 4 byte nella copia (tracciato), copybook in più nella cartella delle copie (letto al posto di quello del legacy), `TIOTNJOB` letto alla riga 293 di una copia dell'originale, provenienza alterata o non dichiarata, record in più o in meno, campo oltre il record nella tabella a mano, ambiente atteso diverso, righe con TAB dell'originale diverse da 6-22, riga senza TAB cambiata, riga in più, 24 byte diversi, argomenti registrati inattesi, atteso del tracciato con la riga sbagliata o troncato, atteso delle occorrenze troncato, chiavi non crescenti nel caricamento, riga di testo più lunga del dichiarato, copia adattata cambiata dopo la build.

## Limiti

- Le righe di console delle righe 266-291 non sono riprodotte (tabella sopra).
- I byte 329-350 dei movimenti dopo l'`OUTREC` di DFSORT non sono determinati dal JCL; qui spazi, non emessi.
- Lo scenario attraversa un solo cammino di `ALTER` e `GO TO`: quello normale, più i rami di errore delle prove 5, 6 e 9. Il comportamento di `CBSTM03A` sui dati di esempio completi (più di 10 movimenti per carta, più di 51 carte con movimenti: la tabella `WS-TRNX-TABLE` ha `OCCURS 51` e `OCCURS 10`) è fuori da questa issue (#5 e successive).
- Gli avvertimenti di libcob alla chiusura implicita dei file e il loro ordine sono osservati, non ricavati.
- I comandi nel container hanno un limite di tempo (`timeout` dentro il container); `docker run` e `docker build` stessi no, come nel resto dell'oracle (`oracle/README.md`, "Limiti").
