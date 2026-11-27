## Obiettivo

Sostituire nell'oracle il segnaposto di `MVSWAIT` con un equivalente verificato, e rendere eseguibile `COBSWAIT` (job `WAITSTEP`), che oggi si ferma con il codice 98 del segnaposto.

Classe di rischio: **piena** (oracle). Validazione con Codex.

## Dipendenze e perimetro

- Dipende da: #4, #24, #35 (mergiate).
- Sorgenti di riferimento (sola lettura): `app/asm/MVSWAIT.asm`, `app/cbl/COBSWAIT.cbl`, `app/jcl/WAITSTEP.jcl`.
- File ammessi: `oracle/stubs/MVSWAIT.cbl`, `oracle/routines/**` (casi, attesi e documentazione di `MVSWAIT`, accanto a quelli di `COBDATFT`), `oracle/esegui.sh` (solo per l'ingresso `SYSIN`, vedi sotto), `oracle/avvio/expected/COBSWAIT.txt` e gli script di `oracle/avvio/` se la prova di avvio di `COBSWAIT` cambia, `oracle/build/check.sh` e `oracle/build/expected/**` solo se gli elenchi fissi lo richiedono, `oracle/tests/**` (programmi di prova nuovi), `oracle/README.md`.
- Fuori ambito: `CEEDAYS` (#37, rinviata); un'attesa reale; l'emulazione della macro `ASMWAIT`; qualsiasi file sotto `analysis/`, `legacy/`.

## Specifica

### Che cosa fa l'originale (da riportare in `oracle/routines/mvswait-casi.md` con le righe)

`MVSWAIT.asm` righe 19-27: salva i registri; legge per riferimento **un intero di 4 byte** (riga 20-21: indirizzo del primo argomento, poi il valore); lo copia in un'area propria (22); chiama la macro `ASMWAIT` su quell'area (23), che avvia l'attesa; ripristina i registri (24); scrive `X'FF'` nel byte 12 dell'area di salvataggio del chiamante (25, il sorgente stesso si chiede a che serva); azzera il registro 15 e ritorna (26-27). Non valida l'argomento, non lo modifica, non scrive nulla a console, ritorna sempre 0. La macro `ASMWAIT` non è nel repository: l'unità di misura (centesimi di secondo) è documentata solo dal commento di `WAITSTEP.jcl` riga 20 (`00003600 = 36 SECONDS`) e va dichiarata come tale.

`COBSWAIT.cbl` righe 30-40: legge 8 caratteri da `SYSIN` (`ACCEPT PARM-VALUE FROM SYSIN`), li sposta in un `PIC 9(8) COMP` e chiama `MVSWAIT`. `WAITSTEP.jcl` riga 26 fornisce `00003600` seguito da un commento sulla stessa scheda.

### L'equivalente

`oracle/stubs/MVSWAIT.cbl`, in COBOL, compilato come gli altri moduli:
- riceve per riferimento l'intero di 4 byte e **non lo modifica**;
- **non attende** (adattamento temporale dichiarato: l'oracle deve essere ripetibile e veloce; la durata dell'attesa non è un effetto che la migrazione deve riprodurre al centesimo, ma il valore richiesto sì);
- scrive su **stderr** una sola riga riconoscibile come dell'oracle e non del legacy, con il valore ricevuto in decimale e in esadecimale, per esempio `MENB-ORACLE MVSWAIT: ATTESA RICHIESTA 0000003600 (X'00000E10') CENTESIMI DI SECONDO, NON ESEGUITA`: così il valore passato dal chiamante è osservabile nei rapporti; su stdout nulla, come l'originale;
- ritorna 0.
La scrittura di `X'FF'` nell'area di salvataggio (riga 25) non ha un equivalente osservabile in GnuCOBOL: è dichiarata non riprodotta, con la riga.

Trattamento degli argomenti: l'originale non valida nulla, quindi **ogni** valore dei 4 byte è un caso determinato (nessun arresto 97): la riga riporta il valore senza segno e i byte. La tabella dei casi lo dice esplicitamente, compresi zero, il massimo di `9(8)`, valori oltre la `PICTURE` ma rappresentabili in 4 byte, e il bit alto acceso.

### `SYSIN` nell'oracle

Oggi `oracle/esegui.sh` esegue ogni programma con l'ingresso standard vuoto. Si aggiunge un'opzione `--sysin FILE` (retrocompatibile: senza l'opzione il comportamento e il formato del rapporto restano identici, e nessun atteso esistente cambia) che collega il file all'ingresso standard del programma. Il rapporto registra che un `SYSIN` è stato fornito e la sua impronta, in una sezione che compare solo quando l'opzione è usata. `--sysin` non si confonde con `--parm`: sono due ingressi diversi sul mainframe (schede `SYSIN DD *` e `PARM=`).

Il contenuto di `SYSIN` per `WAITSTEP` è la scheda del JCL così com'è (`00003600      VALUE IN CENTISECONDS…`, 80 colonne): il programma ne legge i primi 8 caratteri. Il file di prova si ricava dal JCL con un comando riportato, non si riscrive a mano.

### Casi e attesi (`oracle/routines/`, passo `routines`)

Scritti a mano dal sorgente **prima** di eseguire, con una tabella dei casi come per `COBDATFT`:
- chiamata diretta con un programma di prova (`oracle/tests/`): almeno zero, 1, 3600, 99999999, 100000000, `X'7FFFFFFF'`, `X'80000000'`, `X'FFFFFFFF'`; per ciascuno: riga su stderr attesa, argomento invariato dopo la chiamata (tutti i 4 byte), codice di ritorno 0, e byte adiacenti all'argomento invariati;
- tramite `COBSWAIT` con `--sysin`: la scheda di `WAITSTEP.jcl` (atteso: valore 3600); una scheda con 8 cifre diverse.
- **Ingressi di `COBSWAIT` il cui esito non è determinato dal sorgente**: `SYSIN` vuoto, meno di 8 caratteri, caratteri non numerici. Il `MOVE` di un alfanumerico non numerico in un campo binario non ha un risultato definito che si possa attribuire a z/OS leggendo il sorgente. Per questi casi si **registra ciò che fa GnuCOBOL** (osservazione, in un file separato dagli attesi ricavati dal sorgente) e si dichiara che non è un riferimento per la migrazione: nessun atteso "ricavato" li copre. Se l'osservazione contraddice una previsione fatta prima, lo si riferisce.

La prova di avvio di `COBSWAIT` (`oracle/avvio/expected/COBSWAIT.txt`) oggi pretende il 98 del segnaposto: va aggiornata all'esito con ingresso vuoto, che rientra nei casi osservati; l'atteso lo dichiara.

### Prove negative (automatiche, ciascuna fallisce per il motivo dichiarato)

1. il segnaposto rimesso al posto del modulo: `COBSWAIT` termina con 98 e il controllo fallisce;
2. una routine che modifica l'argomento; una che ritorna un codice diverso da 0; una che scrive su stdout; una che attende davvero (limite di tempo breve nella prova: il controllo fallisce per durata, non resta appeso);
3. una routine che riporta il valore con l'ordine dei byte invertito o con il segno;
4. `--sysin` con file inesistente → errore esplicito di `esegui.sh`; `--sysin` ignorato (ingresso vuoto al posto del file) → atteso di `COBSWAIT` non coincide;
5. un byte alterato in ciascun atteso; un caso senza atteso; un atteso senza caso;
6. senza `--sysin`, il rapporto di un programma qualunque è identico byte per byte a quello di `origin/main` (controprova della retrocompatibilità).

## Invarianti di parità

- Nessun valore inventato: ciò che non è determinato dal sorgente è osservazione dichiarata, non atteso.
- Nessun atteso preesistente cambia, tranne `avvio/expected/COBSWAIT.txt` (dichiarato); nessuna prova negativa preesistente cambia esito.
- Le interfacce di `esegui.sh`, `compile.sh uno` e `lib.sh` usate dalle analisi restano compatibili.

## Criteri di accettazione

- [ ] `./oracle/run.sh build` termina con 0.
- [ ] `./oracle/run.sh routines --check` termina con 0, con ogni prova negativa riportata con nome e motivo; la tabella dei casi di `MVSWAIT` è coerente con casi e attesi (controllo di coerenza come per `COBDATFT`).
- [ ] `./oracle/run.sh --all --check` termina con 0 due volte di seguito da clone pulito.
- [ ] `./analysis/run.sh --all --check` termina con 0.
- [ ] `git status --short` vuoto dopo i controlli; `legacy/` invariato; `git diff --name-only origin/main...HEAD` elenca solo file ammessi.
- [ ] CI verde, compreso `oracle-check`, con lo stesso numero di prove per passo in CI e in locale.

## Strategia di rollback

Revert del commit di merge: torna il segnaposto e `COBSWAIT` torna a fermarsi con 98.

## Limiti per l'agente

- Negli script del perimetro ogni comando ha l'esito controllato, con gli esiti ammessi dichiarati; limite di tempo sui comandi che possono restare in attesa; nessun residuo di una corsa precedente può soddisfare un controllo; i controlli pretendono l'insieme atteso, non "almeno uno"; ogni asserzione ha una prova negativa che fallisce solo grazie a essa.
- Docker condiviso: nessun comando globale; immagini e volumi condivisi non si rimuovono.
- Autocontrollo prima della PR come da `paper/data/prompts/esecutore.md`. File di appoggio sull'host con prefisso `issue36-`. Non mergiare.
