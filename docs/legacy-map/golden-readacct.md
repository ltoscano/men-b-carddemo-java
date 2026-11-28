# Golden del job READACCT (`CBACT01C`): l'output di riferimento del pilota batch (issue #55)

Documento generato da `./oracle/run.sh golden` (`oracle/golden/`): non modificarlo a mano. I file elencati sono in `oracle/golden/readacct/generati/`; le tabelle scritte a mano in `oracle/golden/readacct/`.

## Cosa si fa

Il programma pilota `CBACT01C` (job `app/jcl/READACCT.jcl`, passo `STEP05`) gira nell'oracle GnuCOBOL (`oracle/esegui.sh`, nomi DD del JCL: `DD_ACCTFILE`, `DD_OUTFILE`, `DD_ARRYFILE`, `DD_VBRCFILE`) su tre ingressi noti. Il passo `PREDEL` del JCL cancella le tre uscite prima del programma: l'oracle parte da una cartella di lavoro vuota (creata da `esegui.sh`). Cio' che il programma scrive, con le correzioni e le esclusioni dichiarate, e' il valore atteso del test di parita' Java.

| Scenario | Classe | Ingresso | Record |
| --- | --- | --- | --- |
| `esempio` | riferimento di parita' | `analysis/oracle-dati/out/ACCTFILE.rec` (i 50 record di `AWS.M2.CARDDEMO.ACCTDATA.PS`, #53), letto dal file indicizzato del passo `dati` | 50 |
| `mirato` | riferimento di parita' | esempio con le 10 sostituzioni canoniche di `sostituzioni-mirato.tsv`, caricato con `oracle/dati/carica.sh` (#53) | 50 |
| `osservazione` | **osservazione, non golden** | mirato con le 4 sostituzioni di `sostituzioni-osservazione.tsv` (debito di ciclo diverso da zero, zero negativo, segno alternativo) | 50 |

Ogni ingresso derivato e' verificato da `differenze.sh` (la differenza completa dalla base coincide con la tabella; valori e canonicita' decodificati con le regole di #23) e ogni proprieta' richiesta (`proprieta.tsv`) e' verificata sul file indicizzato effettivamente letto con `IDXLEGGI` dopo il caricamento (`proprieta.sh`).

## Sostituzioni dello scenario mirato

| Chiave | Campo | Byte | Valore | Motivo |
| --- | --- | --- | --- | --- |
| 00000000003 | ACCT-CURR-BAL | 303030303030313233343550 | -1234.57 | saldo negativo (P = cifra 7 negativa); i dati di esempio non hanno importi negativi |
| 00000000004 | ACCT-CREDIT-LIMIT | 30303030303030353030304a | -500.01 | limite di credito negativo (J = cifra 1 negativa) |
| 00000000005 | ACCT-CASH-CREDIT-LIMIT | 303030303030303030303047 | +0.07 | limite di anticipo diverso dal limite di credito dello stesso conto (credito 3819.00) |
| 00000000006 | ACCT-CREDIT-LIMIT | 393939393939393939393949 | +9999999999.99 | importo con tutte le cifre a 9 (I = cifra 9 positiva) |
| 00000000007 | ACCT-CURR-BAL | 30303030303030303030307b | +0.00 | zero positivo nel saldo di un conto che nei dati di esempio ha saldo 193.00 |
| 00000000008 | ACCT-CURR-CYC-CREDIT | 303030303030303031323344 | +12.34 | credito di ciclo diverso da zero, positivo (D = cifra 4 positiva) |
| 00000000009 | ACCT-CURR-CYC-CREDIT | 303030303030303035363751 | -56.78 | credito di ciclo diverso da zero, negativo (Q = cifra 8 negativa) |
| 00000000010 | ACCT-GROUP-ID | 4752502d303031304142 | GRP-0010AB | gruppo non vuoto (nei dati di esempio e' sempre di spazi) |
| 00000000011 | ACCT-ACTIVE-STATUS | 4e | N | stato diverso da Y |
| 00000000012 | ACCT-REISSUE-DATE | 323038372d31312d3236 | 2087-11-26 | data di riemissione con anno, mese e giorno diversi tra loro e da quelli delle date di riemissione degli altri conti (anni 2023-2025, nessun mese 11, nessun giorno 26) |

Sostituzioni aggiunte dallo scenario osservazione:

| Chiave | Campo | Byte | Valore | Canonica | Motivo |
| --- | --- | --- | --- | --- | --- |
| 00000000001 | ACCT-CURR-CYC-DEBIT | 30303030303030303130307b | +10.00 | si | debito di ciclo diverso da zero nel primo record del file |
| 00000000020 | ACCT-CURR-CYC-DEBIT | 30303030303030303033357d | -3.50 | si | debito di ciclo diverso da zero in un record successivo |
| 00000000021 | ACCT-CURR-BAL | 30303030303030303030307d | -0.00 | no | zero negativo nel saldo (campo copiato in OUTFILE, ARRYFILE e VBRCFILE) |
| 00000000022 | ACCT-CREDIT-LIMIT | 303030303030383539393030 | +8599.00 | no | segno alternativo: ultimo byte 30 (cifra semplice) invece di 7B, stesso valore del dato di esempio |

## File, dimensioni e impronte

| File | Byte | SHA-256 | Natura |
| --- | --- | --- | --- |
| `golden/esempio/ARRYFILE` | 5500 | `ff033653be454b12352edbf3426f8122c25ffbc4d1818d19b13a452bb87a0bfc` | file fisico dell'oracle (osservazione: il riferimento e' il .riferimento.txt) |
| `golden/esempio/ARRYFILE.riferimento.txt` | 11050 | `642f5262136e779d2b1d8ece9d8af75c1d771bbc09151d028bf6302996b50a49` | **riferimento di parita'** (correzioni applicate, esclusioni mascherate con `**`) |
| `golden/esempio/MARCATURA` | 175 | `2b707e71f92412432eca6f19266138c70f2dc3e3b0e43c791d0169244fc491ba` | marcatura |
| `golden/esempio/OUTFILE` | 5350 | `6afb545394178bc7b22b50d46fb3867c51b4f29d432b77a17687688c7df71b8c` | file fisico dell'oracle (osservazione: il riferimento e' il .riferimento.txt) |
| `golden/esempio/OUTFILE.riferimento.txt` | 10750 | `3ff4e53b06044c98fde468cfd32b3fe156927730c301ef9ec68f754fd904af15` | **riferimento di parita'** (correzioni applicate, esclusioni mascherate con `**`) |
| `golden/esempio/VBRCFILE` | 2950 | `5031a2ba5fe40319c386bd9f62f3259d45f568cadae39e5528fd01353f860c71` | file fisico GnuCOBOL a record variabili (osservazione) |
| `golden/esempio/VBRCFILE.logici.txt` | 6300 | `814870b4485e3c0a018fcd4f04bb412f4af94b72537c3fa6db8d0b48ce8b7295` | record logici estratti dal fisico (estrai-vb.sh) |
| `golden/esempio/VBRCFILE.riferimento.txt` | 6300 | `814870b4485e3c0a018fcd4f04bb412f4af94b72537c3fa6db8d0b48ce8b7295` | **riferimento di parita'**: sequenza dei record logici |
| `golden/esempio/ambiente.txt` | 246 | `e3a0340a0d72ea14220f8b76b98c726c0eeee7883d18807913fbaf4c0f03bcfb` | variabili ricevute dal programma |
| `golden/esempio/console.riferimento.txt` | 21126 | `0b5d979339fa05d2cc8df370b630c0ed204f703e68291c30429b3d855131f9b5` | **riferimento di parita'** per le righe di classe a; le altre sono marcate `#OSSERVAZIONE` |
| `golden/esempio/ingresso.rec` | 15000 | `591952211bfa94397d633a6f6553cf6dda29051f978ec8c0459ed036431dd700` | ingresso dello scenario (record di 300 byte) |
| `golden/esempio/rapporto.txt` | 41775 | `63e067fe160817b9dc721248b6bdd4aec1c1247c0737056daaa8f9f03cd3e642` | rapporto di esegui.sh: codice di uscita (riferimento: 0), stdout, stderr (osservazione), file |
| `golden/mirato/ARRYFILE` | 5500 | `4d9897a631f3104206c41cbdcec71779e5a7b33272d1793d489c7f2d0ceb719a` | file fisico dell'oracle (osservazione: il riferimento e' il .riferimento.txt) |
| `golden/mirato/ARRYFILE.riferimento.txt` | 11050 | `c0705f94fdc07caee5080d5c1a2114079f03e3642819a28eab5398b4feb43032` | **riferimento di parita'** (correzioni applicate, esclusioni mascherate con `**`) |
| `golden/mirato/MARCATURA` | 186 | `4e5fa6bbb694fd42a5c514625d5eb13ede6d24f137c03eee09c9e9c752621d0e` | marcatura |
| `golden/mirato/OUTFILE` | 5350 | `92a05348e01ceb274839dd7c9ee09484f2ffb9ce792dc09fd8dba88f8d55ed5d` | file fisico dell'oracle (osservazione: il riferimento e' il .riferimento.txt) |
| `golden/mirato/OUTFILE.riferimento.txt` | 10750 | `8cdbf8d30521d8ce06796eb066d6e22672f3ce4b6a0faaa639c1386df2a337a0` | **riferimento di parita'** (correzioni applicate, esclusioni mascherate con `**`) |
| `golden/mirato/VBRCFILE` | 2950 | `71912c931c1965842c5309a53badaa04535fb6dc569220642403594c048dd2ff` | file fisico GnuCOBOL a record variabili (osservazione) |
| `golden/mirato/VBRCFILE.logici.txt` | 6300 | `445ef8d8dc24a82b3f3d2d808fb7547e7c060b47f4f37706a48cd58c4de211d7` | record logici estratti dal fisico (estrai-vb.sh) |
| `golden/mirato/VBRCFILE.riferimento.txt` | 6300 | `445ef8d8dc24a82b3f3d2d808fb7547e7c060b47f4f37706a48cd58c4de211d7` | **riferimento di parita'**: sequenza dei record logici |
| `golden/mirato/ambiente.txt` | 265 | `13030e05e61e43e9349c98a256cb2bdd5d5d78ff848b08049a7acd9b50c74d48` | variabili ricevute dal programma |
| `golden/mirato/console.riferimento.txt` | 21126 | `4d90540765b0a3aea56fd5c49d13ed9e633dda04b33e5bf8512d660bd8add42c` | **riferimento di parita'** per le righe di classe a; le altre sono marcate `#OSSERVAZIONE` |
| `golden/mirato/ingresso.rec` | 15000 | `8929276bb3b1f465f4abe226b5c735b60e3f0991ffeb7c440ae545a7a24ffcb6` | ingresso dello scenario (record di 300 byte) |
| `golden/mirato/rapporto.txt` | 41775 | `170544e7c3f0eb6792b0a19b82d344dbf682aacdf06dcafcb67e3520491886f8` | rapporto di esegui.sh: codice di uscita (riferimento: 0), stdout, stderr (osservazione), file |
| `osservazioni/osservazione/ARRYFILE` | 5500 | `7d24fc030ab716d4c7f5e984dc2484b8af101f2767cb1b8f390dc8cf9107cf43` | osservazione |
| `osservazioni/osservazione/MARCATURA` | 252 | `d1af831b91925a52c1e6e0ad0d7b5b8a227b75e80ded0878322200f71fced437` | marcatura |
| `osservazioni/osservazione/OUTFILE` | 5350 | `6c7972019b4ae49cac76969e4f1799dc1f92e90ee62e94f9a4a4e2ee94c9ca82` | osservazione |
| `osservazioni/osservazione/VBRCFILE` | 2950 | `908e661f6e5e0570266c71c51909cc13d6ad9a67036b35144270a5e57147fd56` | osservazione |
| `osservazioni/osservazione/VBRCFILE.logici.txt` | 6300 | `4527ee445dbe7d19b1ee7aa6048275d0c784d4d3b0e7facdf3712fc01a309fd4` | osservazione |
| `osservazioni/osservazione/ambiente.txt` | 289 | `4a9c5148b6cdbdf3bf115d67472185ee31998fa9818af3389a1451f594035a3e` | osservazione |
| `osservazioni/osservazione/ingresso.rec` | 15000 | `961cad5a11407d57515e801ac98e1db832fdb9aec2417c9bc83060d37fc8a21d` | osservazione |
| `osservazioni/osservazione/rapporto.txt` | 41775 | `917dcd94b56ebd7b1e3dfb220f6a515c10eb21fbf0e67357bc3bc62ba7115e4c` | osservazione |
| `osservazioni/riesecuzione/ambiente.txt` | 237 | `2e92f5951c35a704211c9ccd57d82b48241ba0f4f1eddb7e3f1f6cf06e271a89` | osservazione |
| `osservazioni/riesecuzione/esito.txt` | 290 | `a285e86c7e48be8dfba6be39bd3a8c6333ca04e740f4ffffc53ecab360a69fdd` | osservazione |
| `osservazioni/riesecuzione/rapporto.txt` | 41734 | `ea2d04c59e4abf2f5961136c69bd8186ba8936caa18f6a965b29db8be686d2fc` | osservazione |

Formato dei file prodotti da GnuCOBOL: OUTFILE e ARRYFILE sono record fissi di 107 e 110 byte senza terminatori ne' intestazioni (dimensione esatta 107 x 50 e 110 x 50, controllo 2). VBRCFILE (`RECORDING MODE IS V`, `RECORD VARYING FROM 10 TO 80`) ha davanti a ogni record 2 byte di lunghezza in big-endian, senza l'intestazione, e 2 byte `00`: formato `COB_VARSEQ_FORMAT` 0, il predefinito (`/usr/share/gnucobol/config/runtime.cfg` dell'immagine: "0 means 2 byte record length (big-endian) + 2 NULs"; "'length' is the data length, does not include the prefix"). Su z/OS (`RECFM=VB,LRECL=84`) il descrittore di record e' di 4 byte e comprende se stesso: il formato fisico non e' un riferimento; il riferimento e' la sequenza dei record logici (due per conto, 12 e 39 byte), estratta con `estrai-vb.sh` e riletta per una via indipendente dal verificatore.

## Che cosa e' riferimento di parita' e che cosa e' osservazione

| Uscita | Riferimento di parita' (scenari esempio e mirato) | Osservazione |
| --- | --- | --- |
| OUTFILE | `OUTFILE.riferimento.txt`: 105 byte su 107 per record (77-78 esclusi) | il file fisico, compresi i byte 77-78 (`00 00` nell'oracle) |
| ARRYFILE | `ARRYFILE.riferimento.txt`: 110 byte su 110, con i byte 80 e 99 corretti (vedi sotto) | il file fisico, con i byte 80 e 99 come li scrive GnuCOBOL (`30`) |
| VBRCFILE | `VBRCFILE.riferimento.txt`: lunghezza e contenuto di ogni record logico | il file fisico |
| Console | `console.riferimento.txt`: righe di classe a | righe di classe b e c (tabella sotto) |
| Codice di uscita | 0 | - |
| stderr | - | avviso di libxml2 e tre righe `libcob: warning: implicit CLOSE` (il programma chiude solo ACCTFILE, riga 390) |
| Scenario osservazione | - | tutto (cartella `osservazioni/osservazione`, marcata `OSSERVAZIONE`) |
| Riesecuzione | - | `osservazioni/riesecuzione` (controllo 6) |

Il file fisico differisce dal riferimento solo nelle posizioni delle tabelle delle correzioni e delle esclusioni (`coerenza.sh`).

## Campi non determinati dal sorgente

Ricerca dei campi delle aree di uscita non valorizzati a ogni record (righe di `app/cbl/CBACT01C.cbl`):

| Campo o area | Determinato? | Perche' |
| --- | --- | --- |
| `OUT-ACCT-REISSUE-DATE` byte 9-10 (OUTFILE 77-78) | **no** | `CODATECN-0UT-DATE` e' `X(20)` senza `VALUE` (`app/cpy/CODATECN.cpy:39-51`); `COBDATFT` (caso C4) ne scrive i primi 8 byte (`app/asm/COBDATFT.asm:51-53`); il programma ne copia 10 (righe 223-233). Su z/OS il valore iniziale senza `VALUE` e' imprevedibile (IBM, *Enterprise COBOL for z/OS 6.4 Language Reference*, VALUE clause: "If the initial value is not explicitly specified, the value is unpredictable", https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=entry-value-clause); nell'oracle `defaultbyte 0` da' `00 00`. Esclusi |
| `OUT-ACCT-CURR-CYC-DEBIT` con debito d'ingresso diverso da zero | **no** | righe 236-238: nessuna istruzione lo valorizza; resta il contenuto dell'area del record. IBM non lo definisce: "the information in the area referenced by record-name-1 is unavailable, except as specified by the SAME RECORD AREA clause" (*Enterprise COBOL 6.1 Language Reference*, Common processing facilities, frasi INTO e FROM, https://www.ibm.com/docs/en/SS6SG3_6.1.0/lr/ref/rlpdscpf.html). Nei dati degli scenari esempio e mirato il debito e' sempre zero (verificato da `proprieta.sh`): l'uscita e' 2525,00, determinata. Solo nello scenario osservazione |
| `ARR-ACCT-CURR-BAL(4)`, `(5)`, `ARR-ACCT-CURR-CYC-DEBIT(4)`, `(5)`, `ARR-FILLER` | si' | `INITIALIZE ARR-ARRAY-REC` a ogni record (riga 169): ZERO ai numerici, SPACE agli alfanumerici; `ARR-FILLER` e' un nome, non la parola `FILLER`, quindi e' inizializzato (IBM, INITIALIZE statement rules, regole 1 e 2). Per due byte l'oracle sbaglia: sezione seguente |
| byte di `VBR-REC` oltre la lunghezza scritta | non scritti | `WRITE VBR-REC` scrive `WS-RECD-LEN` byte (12 o 39, righe 288-290, 303-305): i byte oltre non entrano nel record logico |
| `VBRC-REC1` | si' | `INITIALIZE` (riga 175) e poi i due campi (righe 277-279) |
| `VBRC-REC2` | si' | non inizializzato, ma i suoi quattro campi (39 byte) sono valorizzati a ogni record (righe 277-282) |
| `WS-REISSUE-DATE` / `WS-ACCT-REISSUE-YYYY` | si' | riceve `ACCT-REISSUE-DATE` a ogni record (righe 223-224) |
| aree di `CODATECN` tra una chiamata e l'altra | si', tranne i byte 9-20 della data d'uscita | tipo, data d'ingresso (10 byte piu' 10 spazi di riempimento del `MOVE`) e tipo d'uscita a ogni record (righe 223-226); `COBDATFT` scrive i primi 8 byte della data d'uscita; il messaggio d'errore non e' mai scritto nel caso C4 e non e' copiato in uscita |

Tabella delle posizioni escluse (`esclusioni.tsv`, unica fonte delle maschere):

| Scenario | File | Chiave | Posizione | Lunghezza | Motivo | Riga |
| --- | --- | --- | --- | --- | --- | --- |
| * | OUTFILE | * | 77 | 2 | ultimi due byte di OUT-ACCT-REISSUE-DATE: CODATECN-0UT-DATE e' X(20) senza VALUE, COBDATFT (caso C4) ne scrive solo i primi 8 byte, CBACT01C non inizializza l'area e ne copia i primi 10; su z/OS il valore iniziale senza VALUE e' imprevedibile (IBM, VALUE clause), nell'oracle defaultbyte 0 da' 00 00 | cpy/CODATECN.cpy:39-51; asm/COBDATFT.asm:51-53; cbl/CBACT01C.cbl:223-233 |
| osservazione | OUTFILE | 00000000001 | 91 | 7 | OUT-ACCT-CURR-CYC-DEBIT con ACCT-CURR-CYC-DEBIT diverso da zero: nessuna istruzione lo valorizza; resta il contenuto iniziale dell'area del record (primo record) | cbl/CBACT01C.cbl:236-238 |
| osservazione | OUTFILE | 00000000020 | 91 | 7 | OUT-ACCT-CURR-CYC-DEBIT con ACCT-CURR-CYC-DEBIT diverso da zero: resta cio' che l'area conteneva dopo la WRITE precedente (su z/OS non definito: IBM, Common processing facilities, INTO and FROM phrases) | cbl/CBACT01C.cbl:236-238,243 |
| osservazione | OUTFILE | 00000000021 | 13 | 12 | OUT-ACCT-CURR-BAL da uno zero negativo: il MOVE tra zonati con segno su z/OS genera il segno preferito con NUMPROC(NOPFD) e usa il segno dato con NUMPROC(PFD) (IBM, Sign representation of zoned and packed-decimal data); il repository non fissa NUMPROC | cbl/CBACT01C.cbl:218 |
| osservazione | ARRYFILE | 00000000021 | 12 | 12 | ARR-ACCT-CURR-BAL(1) da uno zero negativo: stessa riserva su NUMPROC | cbl/CBACT01C.cbl:255 |
| osservazione | ARRYFILE | 00000000021 | 31 | 12 | ARR-ACCT-CURR-BAL(2) da uno zero negativo: stessa riserva su NUMPROC | cbl/CBACT01C.cbl:257 |
| osservazione | VBRC2 | 00000000021 | 12 | 12 | VB2-ACCT-CURR-BAL da uno zero negativo: stessa riserva su NUMPROC | cbl/CBACT01C.cbl:280 |
| osservazione | OUTFILE | 00000000022 | 25 | 12 | OUT-ACCT-CREDIT-LIMIT da un segno alternativo (cifra semplice, zona F su z/OS): stessa riserva su NUMPROC | cbl/CBACT01C.cbl:219 |
| osservazione | VBRC2 | 00000000022 | 24 | 12 | VB2-ACCT-CREDIT-LIMIT da un segno alternativo: stessa riserva su NUMPROC | cbl/CBACT01C.cbl:281 |

Che cosa ha scritto l'oracle nelle posizioni escluse (osservazione, letta dai file fisici; nello scenario osservazione: debito del primo record dall'area iniziale, del record 20 dal record precedente; zero negativo conservato dal `MOVE` di GnuCOBOL; segno alternativo riscritto in forma canonica):

| Scenario | File | Chiave | Byte | Valori osservati |
| --- | --- | --- | --- | --- |
| esempio | OUTFILE | * | 77-78 | `0000` (50 record) |
| mirato | OUTFILE | * | 77-78 | `0000` (50 record) |
| osservazione | OUTFILE | * | 77-78 | `0000` (50 record) |
| osservazione | OUTFILE | 00000000001 | 91-97 | `00000000000000` (1 record) |
| osservazione | OUTFILE | 00000000020 | 91-97 | `0000000252500c` (1 record) |
| osservazione | OUTFILE | 00000000021 | 13-24 | `30303030303030303030307d` (1 record) |
| osservazione | ARRYFILE | 00000000021 | 12-23 | `30303030303030303030307d` (1 record) |
| osservazione | ARRYFILE | 00000000021 | 31-42 | `30303030303030303030307d` (1 record) |
| osservazione | VBRC2 | 00000000021 | 12-23 | `30303030303030303030307d` (1 record) |
| osservazione | OUTFILE | 00000000022 | 25-36 | `30303030303038353939307b` (1 record) |
| osservazione | VBRC2 | 00000000022 | 24-35 | `30303030303038353939307b` (1 record) |

## Posizioni in cui l'oracle sbaglia: correzioni

Alla prima esecuzione l'oracle ha smentito un atteso scritto a mano: nei byte 80 e 99 di ogni record di ARRYFILE (ultimo byte di `ARR-ACCT-CURR-BAL(4)` e `(5)`, valorizzati solo da `INITIALIZE`, riga 169) GnuCOBOL scrive `30` (cifra semplice), mentre le regole IBM danno lo zero con segno C, `7B` nel profilo dell'oracle. Nello stesso oracle `MOVE` e `COMPUTE` di zero scrivono `7B` (`oracle/README.md`, "Segno dei numeri DISPLAY"): e' l'`INITIALIZE` di GnuCOBOL a non applicare la convenzione di `-fsign=EBCDIC` (causa e opzioni: issue #62). Un errore noto dell'oracle non diventa riferimento: il riferimento porta il byte della regola, attraverso questa tabella (`correzioni.tsv`), condizionata al byte che l'oracle scrive oggi (un byte diverso fa fallire il passo). Il verificatore indipendente non legge la tabella: ricava il byte dalla regola.

| File | Chiave | Posizione | Byte dell'oracle | Byte di riferimento | Regola e fonte | Riga |
| --- | --- | --- | --- | --- | --- | --- |
| ARRYFILE | * | 80 | 30 | 7b | INITIALIZE: ZERO e' il mittente implicito dei riceventi numerici (IBM, Enterprise COBOL 6.4 Language Reference, INITIALIZE statement rules, regola 2); il ricevente S9(10)V99 riceve il segno preferito C (IBM, Enterprise COBOL 6.3 Programming Guide, Sign representation of zoned and packed-decimal data: con NUMPROC(NOPFD) the preferred sign is always generated in the receiver; con NUMPROC(PFD) when unsigned data is moved to signed data); nel profilo dell'oracle lo zero con segno C e' 7B (codifica.md) | cbl/CBACT01C.cbl:169 (ARR-ACCT-CURR-BAL(4), ultimo byte) |
| ARRYFILE | * | 99 | 30 | 7b | come la riga precedente | cbl/CBACT01C.cbl:169 (ARR-ACCT-CURR-BAL(5), ultimo byte) |

Fonti: IBM, *Enterprise COBOL for z/OS 6.4 Language Reference*, INITIALIZE statement rules, regola 2: "ZERO is the implied sending item for receiving items of category numeric or numeric-edited" (https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=statement-initialize-rules); IBM, *Enterprise COBOL 6.3 Programming Guide*, Sign representation of zoned and packed-decimal data: con `NUMPROC(NOPFD)` "The preferred sign is always generated in the receiver", con `NUMPROC(PFD)` "The preferred sign is generated only where necessary (for example, when unsigned data is moved to signed data)" (https://www.ibm.com/docs/en/SS6SG3_6.3.0/pg/ref/rpari25.html); segno preferito X'C' per positivo o zero (pagina NUMPROC).

Ricerca di ogni campo numerico con segno valorizzato da `INITIALIZE` e scritto in uscita (`CBACT01C` ha due `INITIALIZE`, righe 169 e 175):

| Campo | Byte | GnuCOBOL scrive | Regola IBM | Esito |
| --- | --- | --- | --- | --- |
| `ARR-ACCT-CURR-BAL(1)`-`(3)` | 12-23, 31-42, 50-61 | (sovrascritti dalle righe 255, 257, 259) | - | nessuna correzione |
| `ARR-ACCT-CURR-CYC-DEBIT(1)`-`(3)` | 24-30, 43-49, 62-68 | (sovrascritti dalle righe 256, 258, 260) | - | nessuna correzione |
| `ARR-ACCT-CURR-BAL(4)` | 69-80 | `30` x 12 | `30` x 11, `7B` | **corretto il byte 80** |
| `ARR-ACCT-CURR-CYC-DEBIT(4)` | 81-87 | `00 00 00 00 00 00 0C` | `00 00 00 00 00 00 0C` | coincidono |
| `ARR-ACCT-CURR-BAL(5)` | 88-99 | `30` x 12 | `30` x 11, `7B` | **corretto il byte 99** |
| `ARR-ACCT-CURR-CYC-DEBIT(5)` | 100-106 | `00 00 00 00 00 00 0C` | `00 00 00 00 00 00 0C` | coincidono |
| `VBRC-REC1` (riga 175) | - | - | nessun campo con segno | - |

## Console

Assunzione dichiarata sul legacy: compilazione IBM con `DISPSIGN(COMPAT)`, il valore predefinito (IBM, *Enterprise COBOL 6.4 Programming Guide*, DISPSIGN: "Default is: DISPSIGN(COMPAT)", https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=options-dispsign): un numerico zonato con segno esce con il segno sovrapposto all'ultima cifra. GnuCOBOL lo stampa con 12 cifre e il segno in coda (`000000019400+`). Il verificatore controlla ogni riga, comprese quelle di classe b, ricavandola dal record d'ingresso: il valore stampato da GnuCOBOL e' quello del campo, e la forma IBM e' la stessa sequenza di cifre con l'ultima che porta il segno (la regola dei byte del campo). Su z/OS un operando piu' lungo del record del dispositivo continua nel record successivo (IBM, DISPLAY statement: "Any operand being printed or displayed when the end of a record is reached is continued in the next record"; record logico predefinito 120 caratteri, massimo 255, https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=statements-display-statement); GnuCOBOL scrive una riga sola. Il riferimento e' il testo della riga, non la forma dei record SYSOUT.

| Posizione | Riga | Prefisso | Classe | Motivo |
| --- | --- | --- | --- | --- |
| inizio | 141 | START OF EXECUTION OF PROGRAM CBACT01C | a | solo letterale |
| 1 | 201 | ACCT-ID                 : | a | letterale e ACCT-ID PIC 9(11), senza segno |
| 2 | 202 | ACCT-ACTIVE-STATUS      : | a | letterale e PIC X(01) |
| 3 | 203 | ACCT-CURR-BAL           : | b | PIC S9(10)V99: IBM con DISPSIGN(COMPAT) sovrappone il segno all'ultima cifra, GnuCOBOL stampa 12 cifre e il segno in coda |
| 4 | 204 | ACCT-CREDIT-LIMIT       : | b | PIC S9(10)V99, come sopra |
| 5 | 205 | ACCT-CASH-CREDIT-LIMIT  : | b | PIC S9(10)V99, come sopra |
| 6 | 206 | ACCT-OPEN-DATE          : | a | letterale e PIC X(10) |
| 7 | 207 | ACCT-EXPIRAION-DATE     : | a | letterale e PIC X(10) |
| 8 | 208 | ACCT-REISSUE-DATE       : | a | letterale e PIC X(10) |
| 9 | 209 | ACCT-CURR-CYC-CREDIT    : | b | PIC S9(10)V99, come sopra |
| 10 | 210 | ACCT-CURR-CYC-DEBIT     : | b | PIC S9(10)V99, come sopra |
| 11 | 211 | ACCT-GROUP-ID           : | a | letterale e PIC X(10) |
| 12 | 212 | ------------------------------------------------- | a | solo letterale |
| 13 | 283 | VBRC-REC1: | a | letterale e gruppo di 12 byte (PIC 9(11) e PIC X(01)): nessun campo con segno, entro il record del dispositivo (decisione dell'Approvatore, 28 novembre 2026) |
| 14 | 284 | VBRC-REC2: | b | gruppo che contiene due PIC S9(10)V99: i loro byte di segno arrivano alla console cosi' come sono in memoria (la specifica la classifica osservazione) |
| 15 | 151 | - | c | DISPLAY ACCOUNT-RECORD, gruppo di 300 byte: su z/OS un operando piu' lungo del record del dispositivo continua nel record successivo (IBM, DISPLAY statement), GnuCOBOL scrive una riga sola |
| fine | 158 | END OF EXECUTION OF PROGRAM CBACT01C | a | solo letterale; ultima riga della corsa regolare |

## Differenze GnuCOBOL / z/OS che toccano questo job

| Tema | GnuCOBOL (oracle) | z/OS | Fonte | Trattamento |
| --- | --- | --- | --- | --- |
| Campo senza `VALUE` | `00` (`defaultbyte 0`) | imprevedibile | IBM, VALUE clause | OUTFILE 77-78 esclusi |
| `INITIALIZE` di un zonato con segno | ultimo byte `30` (cifra semplice) | zona C (`7B` nel profilo) | IBM, INITIALIZE statement rules; Sign representation | correzione condizionata (ARRYFILE 80, 99) |
| `MOVE` tra zonati con segno, rappresentazione non canonica | osservato nello scenario osservazione | segno preferito con `NUMPROC(NOPFD)`, segno dato con `NUMPROC(PFD)` | IBM, Sign representation | escluso (solo osservazione) |
| Area del record dopo `WRITE` | conserva i byte | non disponibile | IBM, Common processing facilities | debito non zero solo nello scenario osservazione |
| Record variabili | 2 byte di lunghezza + 2 byte `00` | RDW di 4 byte | `runtime.cfg`; JCL `RECFM=VB` | riferimento = record logici |
| `DISPLAY` di numerici con segno | segno separato in coda | segno sovrapposto (`DISPSIGN(COMPAT)`) | IBM, DISPSIGN | righe di classe b: osservazione |
| `DISPLAY` di 300 byte | una riga | piu' record | IBM, DISPLAY statement | riga di classe c: osservazione |
| File d'uscita non chiusi dal programma | `implicit CLOSE` su stderr | chiusura alla fine dell'unita' di esecuzione: **non verificato** nella documentazione IBM | - | stderr: osservazione |
| Arresto con file aperti | lo stub `CEE3ABD` chiude i file e lascia le uscite parziali | `DISP=(NEW,CATLG,DELETE)`: alla fine anomala i data set nuovi si cancellano | IBM, z/OS 3.1 MVS JCL Reference, DISP parameter (https://www.ibm.com/docs/en/zos/3.1.0?topic=d-parameter-field-2) | osservazione (prova negativa del ramo d'errore) |
| `OPEN OUTPUT` su file esistente | vedi riesecuzione | non accade: `PREDEL` cancella prima | `READACCT.jcl:22-48` | osservazione (controllo 6) |

## Osservazioni registrate

Riesecuzione (controllo 6): seconda esecuzione con i tre file d'uscita gia' presenti, ciascuno di 20000 byte `R`.

- OUTFILE: prima dell'esecuzione 20000 byte R, dopo 5350 byte, identico alla prima esecuzione: si
- ARRYFILE: prima dell'esecuzione 20000 byte R, dopo 5500 byte, identico alla prima esecuzione: si
- VBRCFILE: prima dell'esecuzione 20000 byte R, dopo 2950 byte, identico alla prima esecuzione: si

Ramo d'errore del programma (prove negative di `oracle/golden/check.sh`):

- **Errore di lettura** (stato diverso da 00 e 10): **non provocabile** nel container senza modificare il programma. Prove tentate: pagine del file Berkeley DB alterate (sei varianti); record di 299 byte (letti con stato 00); record di 301 byte (errore all'apertura, stato 39, ramo di apertura).
- **Limite dell'oracle**: un file indicizzato corrotto (pagina Berkeley DB alterata) non produce un errore ma una **fine file silenziosa**: il programma esce con 0 e le uscite sono troncate, con solo righe `BDB0058`/`PANIC` su stderr. Il passo lo attenua rileggendo il file con `IDXLEGGI` prima dell'esecuzione (la lettura deve coincidere con l'ingresso) e pretendendo il numero di record atteso (controllo 2).
- **Errore di scrittura**: raggiungibile, con le uscite su un file system pieno (tmpfs di 8 KiB). Diagnostica `ACCOUNT FILE WRITE STATUS IS:` e `FILE STATUS IS: NNNN00..` (34 osservato con 8 KiB, 30 con 12 KiB), `ABENDING PROGRAM`, `CEE3ABD` con `ABCODE=+0000000999 TIMING=+0000000000` (righe 406-410), codice dell'oracle 99, nessun golden pubblicato. Lo stub lascia i file parziali, mentre il JCL li cancellerebbe (`DISP=(NEW,CATLG,DELETE)`, `READACCT.jcl:37-47`): osservazione distinta.

## Controlli

`./oracle/run.sh golden` genera e verifica; `./oracle/run.sh golden --check` rigenera da zero due volte e confronta, poi esegue le prove negative.

| Controllo | Che cosa | Script |
| --- | --- | --- |
| 1 | golden rigenerati da zero coincidenti byte per byte con i versionati (due corse) | `check.sh` |
| 2 | N record in OUTFILE e ARRYFILE, 2N record logici, ordine e chiavi dell'ingresso, dimensione del fisico | `conteggi.sh` |
| 3 | attesi scritti a mano (`attesi-a-mano.tsv`, 15 conti) uguali ai golden; posizioni ND = escluse | `attesi.sh` |
| 4 | verificatore indipendente su tutti i record degli scenari esempio e mirato, sul riferimento corretto | `verificatore.sh` |
| 4b | fisico e riferimento differiscono solo nelle posizioni delle due tabelle | `coerenza.sh` |
| 5 | scenario osservazione fuori dai golden, marcato | `separazione.sh` |
| 6 | riesecuzione con file preesistenti (osservazione) | `riesecuzione.sh` |
| - | sostituzioni e proprieta' degli scenari derivati | `differenze.sh`, `proprieta.sh` |
