BOCCIATA

Il percorso usato da `CBACT01C` (`2 → 2`) risulta corretto nelle prove eseguite. La PR esclude però casi determinati dall’assembler e contiene un atteso, `N1`, che certifica il comportamento sbagliato.

Il diff modifica 24 file, tutti sotto `oracle/` e nel perimetro autorizzato. `legacy/` è invariato, pulito e fissato a `59cc6c2`. Nessun commit o push; al termine sorgenti tracciati e modulo originale della build risultano invariati.

**Prove eseguite**

Ho eseguito personalmente i comandi. Timeout esterni: build 600 s, ciascuna suite 900 s, ciascun controllo mutato 300 s, singole invocazioni Docker 120 s, con ulteriori timeout interni di 60 s. Nessun timeout è scaduto.

Per le mutazioni ho ricompilato moduli isolati e selezionato ciascuno mediante `ROUTINES_BIN_DIR`, senza sostituire il modulo della build originale.

| Comando/prova | Esito osservato | Durata |
|---|---|---:|
| `git diff --name-only origin/main...HEAD`; verifica submodule | Solo perimetro autorizzato; legacy pulito | <1 s |
| `./oracle/run.sh build` | **0**, 23 programmi compilati | 14,133 s |
| `./oracle/run.sh --all --check`, prima corsa | **0**, otto passi, 88 prove negative | 254,816 s |
| Stesso comando, seconda corsa immediatamente consecutiva | **0**, otto passi, 88 prove negative | 317,890 s |
| `DATFTPRB --parm …`, sette ingressi propri | Cinque ritorni conformi byte per byte; due arresti 97, uno indebito | 6,761 s complessivi |
| `routines --check`, variante che controlla il prefisso completo | **1**, divergenza di `N1`: il controllo respinge la correzione | 4,407 s |
| `routines --check`, scrittura aggiuntiva di `FF` nel byte 43 | **1**, differenze nell’area | 3,817 s |
| `routines --check`, scambio degli ultimi due caratteri prodotti dal tipo 2 | **1**, differenze nella data | 2,670 s |
| `routines --check`, sola eliminazione di `MOVE 0 TO RETURN-CODE` | **0**; il ritorno effettivo rimane 0 sotto GnuCOBOL | 34,795 s |
| `routines --check`, ritorno precaricato a 55 e mancato azzeramento | **1**, ritorno 55 rilevato | 4,427 s |
| `routines --check`, intera area impostata a `FF` prima di 97 | **0**, modifica non rilevata | 38,326 s |
| Chiamante strumentato con osservatore `atexit`, originale e variante precedente | Entrambi escono con 97; osservati rispettivamente area originale e 80 byte `FF` | 0,847 s |
| `CBACT01C`, file indicizzato temporaneo con due record propri | **0**, due record d’uscita | 0,564 s |
| Stesso `CBACT01C`, segnaposto di `origin/main` ricompilato al posto del modulo | **98**, messaggio del segnaposto | 0,534 s |
| Verifica finale di sorgenti, legacy e modulo della build | Invariati | 0,219 s |

Le ricompilazioni delle singole varianti sono terminate tutte con 0, in 0,5–1,7 secondi ciascuna. Comandi completi, sorgenti delle sonde e misure sono conservati in `.validazione/probes.py`, `.validazione/stale55.py` e nei relativi log e JSON.

Le regressioni `build`, `avvio`, `avviatore`, `abend`, `segno`, `dialetto` e `selftest` passano in entrambe le suite. Gli attesi preesistenti risultano invariati rispetto a `origin/main`; non ho eseguito separatamente una checkout di `main`. Le due corse consecutive danno entrambe 0: **nessun falso rosso osservato in queste corse**.

**Tabella ricavata dall’assembler**

Ho letto integralmente `COBDATFT.asm` e `COCDATFT.mac`. L’assembler z/OS non è stato eseguito: la derivazione seguente viene dalle istruzioni e dalle regole HLASM; le esecuzioni riguardano l’equivalente GnuCOBOL.

Indico con `A[n]` i byte dell’area, contando da 1:

| Byte | Campo |
|---|---|
| 1 | Selettore d’ingresso |
| 2–21 | Data d’ingresso |
| 22 | Selettore d’uscita |
| 23–42 | Data d’uscita |
| 43–80 | Messaggio |

Le righe 17–29 e 59–60 gestiscono registri, indirizzamento e aree di salvataggio; non modificano l’area dell’argomento. La riga 27 acquisisce il suo indirizzo. `EQU`, `USING`, `DROP` e la DSECT definiscono indirizzi e attributi. Le righe 61–62 azzerano R15 e ritornano: **ogni ritorno normale dell’assembler ha codice 0, anche dopo `GOTOERR`**.

Le lunghezze implicite sono effettivamente 20 alla riga 36 e 38 alla riga 56. Il punto decisivo è il pool: gli unici due letterali sono lunghi 1 e 13 byte; appartengono entrambi al quinto segmento, nell’ordine di apparizione, senza spazio intermedio. Pertanto il confronto della riga 36 ha **14 byte iniziali noti**, `-INVALID INPUT`, seguiti da sei byte non determinati. Questa è una deduzione dalle regole documentate, non una supposizione sul caricatore. [Manuale IBM HLASM, “Lengths” e “Literal pool”, pp. 79 e 179](https://publibz.boulder.ibm.com/epubs/pdf/asmr1022.pdf)

Definisco gli effetti completi:

| Effetto | Scritture | Byte conservati | Istruzioni |
|---|---|---|---|
| **F1** | `23–26 ← 2–5`; `27 ← '-'`; `28–29 ← 6–7`; `30 ← '-'`; `31–32 ← 8–9` | 1–22, 33–80 | 40–44 |
| **F2** | `23–26 ← 2–5`; `27–28 ← 7–8`; `29–30 ← 10–11` | 1–22, 31–80 | 51–53 |
| **E** | `43–55 ← 'INVALID INPUT'`; `56–80 ←` 25 byte oltre il letterale | 1–42 | 56 |

Sia **P** il contenuto iniziale di `A[6–19]`, confrontato con `-INVALID INPUT`.

| Ingresso | Uscita | Contenuto rilevante | Letture nell’area | Effetto dell’assembler | RC assembler / trattamento oracle prescritto |
|---|---|---|---|---|---|
| `1` | ≠`2` | `A[6] ≠ '-'` | 1; operando CLC 6–25; 22; sorgenti 2–9 | **F1** | 0 / riprodurre |
| `1` | ≠`2` | `A[6]='-'`, ma **P differisce** dal prefisso noto | Come sopra | **F1** | 0 / riprodurre |
| `1` | ≠`2` | **P coincide** col prefisso noto | 1; CLC 6–25; ulteriori letture secondo il ramo | **E** se uguaglianza completa; altrimenti **F1** | 0 / arresto 97, perché dipende dai sei byte ignoti |
| `1` | `2` | Qualsiasi | 1; CLC 6–25; 22 se il CLC è diverso | Sempre **E**, tramite 37 oppure 39 | 0 / arresto 97 |
| `2` | ≠`1` | Qualsiasi, anche cifre o separatori anomali | 1, 22; 2–5, 7–8, 10–11 | **F2** | 0 / riprodurre |
| `2` | `1` | Qualsiasi | 1, 22 | **E** | 0 / arresto 97 |
| ≠`1`,`2` | Qualsiasi | Qualsiasi | 1 | **E** | 0 / arresto 97 |

Il CLC della riga 36 attraversa anche il selettore d’uscita e i primi tre byte dell’uscita iniziale: il suo operando è `A[6–25]`. Dopo i 14 byte noti restano dunque da confrontare `A[20–25]`.

Le righe 47–48 sono commentate. Nessun altro ramo valida calendario, cifre o separatori.

Il confronto con la PR dà questi risultati:

- **C1 e C4:** scritture, conservazioni e attesi dei sette casi dichiarati determinati sono conformi.
- **C2:** classificazione troppo ampia. Contiene anche la seconda riga determinata della mia tabella.
- **N1:** atteso errato. Con `2025-03-17`, alla riga 36 il confronto differisce già nel secondo carattere: `0` contro `I`. La riga 37 non salta. Le righe 40–44 producono **`2025--0-3-`**, conservano tutti gli altri byte e ritornano 0. L’atteso prescrive invece 97.
- **C3, C5, C6 e N2–N4:** esclusione corretta; la riga 56 rende indeterminati i 25 byte finali del messaggio.
- **Nessun caso dichiarato determinato nella PR** risulta dipendere da byte oltre i letterali.

Questa correzione applica la “Decisione già presa”: amplia la riproduzione ai risultati determinati e mantiene 97 dove restano byte ignoti.

Per il chiamante legacy, le righe **51–53** trasferiscono:

| Caratteri della data d’ingresso | Caratteri della data d’uscita | Byte dell’area |
|---|---|---|
| 1–4 | 1–4 | 2–5 → 23–26 |
| 6–7 | 5–6 | 7–8 → 27–28 |
| 9–10 | 7–8 | 10–11 → 29–30 |

I caratteri 5 e 8 vengono saltati. I caratteri d’uscita **9–20 restano invariati**. Alla riga 233, `CBACT01C` copia i primi dieci caratteri: comprende quindi anche due byte conservati, senza aggiungere automaticamente spazi.

Le sonde proprie hanno osservato:

| Selettori e data | Risultato |
|---|---|
| `2 → 2`, `2031-12-09` | `20311209`, poi dodici `A5`; RC 0 |
| `2 → 2`, `WXYZ@ab#cd0123456789` | `WXYZabcd`, poi dodici `A5`; RC 0 |
| `2 → ?`, `LMNO!pq$rt` | `LMNOpqrt`, poi dodici `A5`; RC 0 |
| `1 → 1`, `20311209` | `2031-12-09`, poi dieci `A5`; RC 0 |
| `1 → ?`, `ABCDxYzZ` | `ABCD-xY-zZ`, poi dieci `A5`; RC 0 |
| `1 → 1`, `2031-12-09` | **97 indebito**; dovrebbe produrre `2031--1-2-`, RC 0 |
| `1 → 1`, `ABCD-INVALID INPUTuv` | 97, coerente con la dipendenza residua |

Per i primi cinque casi ho confrontato **tutti gli 80 byte**, oltre al ritorno.

Nell’esecuzione reale di `CBACT01C`, i due campi d’uscita sono risultati `20311209 00 00` e `WXYZabcd 00 00`: i due byte finali conservavano gli zeri iniziali dell’oracle. Rimettendo il vecchio segnaposto, lo stesso programma termina con 98 alla chiamata. **Il programma carica effettivamente il nuovo modulo.**

**Rilievi**

1. **Bloccante — esclusione indebita di casi determinati e atteso `N1` infedele. Falso verde: sì. Oracle infedele: sì.**

   Evidenza: `oracle/stubs/COBDATFT.cbl:58–60` arresta ogni ingresso di tipo 1 con quinto carattere `-`. `oracle/routines/cobdatft-casi.md:49–52,61` giustifica questa esclusione rinunciando a ricostruire il pool. Le regole HLASM e le righe assembler **36–44** determinano invece numerosi ingressi di quella classe, incluso `N1`.

   Le due suite verdi certificano l’arresto sbagliato. Inoltre ho ricompilato una variante che verifica il prefisso completo: produce l’area prevista dall’assembler e **fa fallire `--check` proprio su `N1`**, confermando che l’atteso impedisce la correzione.

   **Correzione richiesta:** distinguere la coincidenza dell’intero prefisso noto dalla sua differenza; aggiornare routine, entrambe le tabelle, documentazione e atteso `N1`. Estendere anche lo schema di `coerenza.sh`, oggi limitato alla condizione sul solo byte 6, e aggiungere un vero caso residuo con prefisso `-INVALID INPUT`; ciò richiede consentire lo spazio interno al PARM, attualmente vietato alla riga 109. Conservare l’arresto 97 per i rami realmente non riproducibili.

La scrittura prima di 97 merita una precisazione sulla portata delle prove: il controllo rimane verde anche con 80 byte trasformati in `FF`, come verificato dall’osservatore d’uscita. **Non dimostra quindi la conservazione dell’area nei rami 97.** Non la considero un ulteriore rilievo bloccante: il confronto integrale dell’area è richiesto esplicitamente per i casi determinati, mentre per quelli esclusi il contratto prescrive arresto e messaggio.