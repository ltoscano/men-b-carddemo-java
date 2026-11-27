# Sentinelle dei tracciati (vista generata)

Generato da `./analysis/run.sh data-sentinelle` (issue #43). Non si modifica a mano: le sentinelle, scritte a mano leggendo i sorgenti, sono in `analysis/data-sentinelle/sentinelle/`, l'elenco delle coppie contratto/vista in `analysis/data-sentinelle/viste.tsv`.

Una sentinella è un record di prova scritto a mano dal copybook: per ogni campo elementare dichiara riga, nome, `PICTURE` e `USAGE` del sorgente, l'intervallo di byte calcolato a mano e il valore atteso tipizzato. La verifica decodifica la sentinella con la colla di #23 (`analysis/data-codec/glue/codec.py`, profilo `oracle-gnucobol`) guidata dal contratto di #3: se il contratto mette un campo nel posto sbagliato, con il tipo, il segno o la scala sbagliati, il valore ottenuto differisce da quello atteso. La posizione dei campi non dipende dal profilo, quindi se ne usa uno solo.

## Contratti e viste coperti

Contratti dei copybook in `contratti.tsv` (colonna `righe` = `copybook`): 15; più `CBACT01C.VBR-REC` (record variabile). Coppie contratto/vista: 22; sentinelle: 23.

| contratto | vista | sentinella | campi attesi | campi della vista nel contratto |
| --- | --- | --- | ---: | ---: |
| `CBACT01C.VBR-REC` | base | prefisso-12 | 1 | 1 |
| `CBACT01C.VBR-REC` | base | prefisso-39 | 1 | 1 |
| `COCOM01Y.CARDDEMO-COMMAREA` | base | base | 16 | 16 |
| `COSTM01.TRNX-RECORD` | base | base | 14 | 14 |
| `CSUSR01Y.SEC-USER-DATA` | base | base | 6 | 6 |
| `CUSTREC.CUSTOMER-RECORD` | base | base | 19 | 19 |
| `CVACT01Y.ACCOUNT-RECORD` | base | base | 13 | 13 |
| `CVACT02Y.CARD-RECORD` | base | base | 7 | 7 |
| `CVACT03Y.CARD-XREF-RECORD` | base | base | 4 | 4 |
| `CVCUS01Y.CUSTOMER-RECORD` | base | base | 19 | 19 |
| `CVEXPORT.EXPORT-RECORD` | EXPORT-ACCOUNT-DATA | EXPORT-ACCOUNT-DATA | 18 | 18 |
| `CVEXPORT.EXPORT-RECORD` | EXPORT-CARD-DATA | EXPORT-CARD-DATA | 12 | 12 |
| `CVEXPORT.EXPORT-RECORD` | EXPORT-CARD-XREF-DATA | EXPORT-CARD-XREF-DATA | 9 | 9 |
| `CVEXPORT.EXPORT-RECORD` | EXPORT-CUSTOMER-DATA | EXPORT-CUSTOMER-DATA | 24 | 24 |
| `CVEXPORT.EXPORT-RECORD` | EXPORT-TIMESTAMP-R | EXPORT-TIMESTAMP-R | 8 | 8 |
| `CVEXPORT.EXPORT-RECORD` | EXPORT-TRANSACTION-DATA | EXPORT-TRANSACTION-DATA | 19 | 19 |
| `CVEXPORT.EXPORT-RECORD` | base | base | 6 | 6 |
| `CVTRA01Y.TRAN-CAT-BAL-RECORD` | base | base | 5 | 5 |
| `CVTRA02Y.DIS-GROUP-RECORD` | base | base | 5 | 5 |
| `CVTRA03Y.TRAN-TYPE-RECORD` | base | base | 3 | 3 |
| `CVTRA04Y.TRAN-CAT-RECORD` | base | base | 4 | 4 |
| `CVTRA05Y.TRAN-RECORD` | base | base | 14 | 14 |
| `CVTRA06Y.DALYTRAN-RECORD` | base | base | 14 | 14 |

Campi elementari dei 15 contratti dei copybook secondo `contratti.tsv` (somma della colonna `elementari`, tutte le aree comprese): 209. Ogni campo elementare di ogni contratto compare in almeno una vista; in `CVEXPORT.EXPORT-RECORD` i campi fuori dalle `REDEFINES` compaiono in tutte e sette le viste.

## Identità dei campi

Un campo si identifica con contratto, vista, numero d'ordine della dichiarazione elementare nel tracciato (tutte le aree comprese, `OCCURS` non espansi) e indici `OCCURS`; l'offset non ne fa parte, perché è ciò che si prova. Nella sentinella l'ordinale è scritto a mano e confrontato con quello che la verifica ricava dal sorgente; nel contratto si ricava dall'ordine delle righe, e due righe con lo stesso percorso e gli stessi indici contano come dichiarazioni distinte. Percorsi ripetuti fra i campi elementari dei contratti di #3:

- `CBIMPORT.WS-ERROR-RECORD`: `WS-ERROR-RECORD/FILLER` 4 volte

Nei 16 contratti con sentinella: nessun percorso ripetuto.

## Contratti senza sentinella

I 43 contratti dichiarati nei programmi (record di `FD` e aree di lavoro, per lo più chiave più area dati) non hanno sentinella (decisione delegata, voce 61 del registro): la loro geometria resta affidata ai controlli di #3.

- `CBACT01C.ARR-ARRAY-REC` (app/cbl/CBACT01C.cbl, righe 72-78)
- `CBACT01C.FD-ACCTFILE-REC` (app/cbl/CBACT01C.cbl, righe 53-55)
- `CBACT01C.OUT-ACCT-REC` (app/cbl/CBACT01C.cbl, righe 57-69)
- `CBACT01C.VBRC-REC1` (app/cbl/CBACT01C.cbl, righe 123-125)
- `CBACT01C.VBRC-REC2` (app/cbl/CBACT01C.cbl, righe 126-130)
- `CBACT02C.FD-CARDFILE-REC` (app/cbl/CBACT02C.cbl, righe 38-40)
- `CBACT03C.FD-XREFFILE-REC` (app/cbl/CBACT03C.cbl, righe 38-40)
- `CBACT04C.DB2-FORMAT-TS` (app/cbl/CBACT04C.cbl, righe 150-150)
- `CBACT04C.FD-ACCTFILE-REC` (app/cbl/CBACT04C.cbl, righe 85-87)
- `CBACT04C.FD-DISCGRP-REC` (app/cbl/CBACT04C.cbl, righe 77-82)
- `CBACT04C.FD-TRAN-CAT-BAL-RECORD` (app/cbl/CBACT04C.cbl, righe 62-67)
- `CBACT04C.FD-TRANFILE-REC` (app/cbl/CBACT04C.cbl, righe 90-92)
- `CBACT04C.FD-XREFFILE-REC` (app/cbl/CBACT04C.cbl, righe 70-74)
- `CBCUS01C.FD-CUSTFILE-REC` (app/cbl/CBCUS01C.cbl, righe 38-40)
- `CBEXPORT.EXPORT-OUTPUT-RECORD` (app/cbl/CBEXPORT.cbl, righe 92-92)
- `CBIMPORT.ERROR-OUTPUT-RECORD` (app/cbl/CBIMPORT.cbl, righe 109-109)
- `CBIMPORT.EXPORT-INPUT-RECORD` (app/cbl/CBIMPORT.cbl, righe 79-79)
- `CBIMPORT.WS-ERROR-RECORD` (app/cbl/CBIMPORT.cbl, righe 152-160)
- `CBSTM03B.FD-ACCTFILE-REC` (app/cbl/CBSTM03B.CBL, righe 76-78)
- `CBSTM03B.FD-CUSTFILE-REC` (app/cbl/CBSTM03B.CBL, righe 71-73)
- `CBSTM03B.FD-TRNXFILE-REC` (app/cbl/CBSTM03B.CBL, righe 59-63)
- `CBSTM03B.FD-XREFFILE-REC` (app/cbl/CBSTM03B.CBL, righe 66-68)
- `CBTRN01C.FD-ACCTFILE-REC` (app/cbl/CBTRN01C.cbl, righe 87-89)
- `CBTRN01C.FD-CARDFILE-REC` (app/cbl/CBTRN01C.cbl, righe 82-84)
- `CBTRN01C.FD-CUSTFILE-REC` (app/cbl/CBTRN01C.cbl, righe 72-74)
- `CBTRN01C.FD-TRAN-RECORD` (app/cbl/CBTRN01C.cbl, righe 67-69)
- `CBTRN01C.FD-TRANFILE-REC` (app/cbl/CBTRN01C.cbl, righe 92-94)
- `CBTRN01C.FD-XREFFILE-REC` (app/cbl/CBTRN01C.cbl, righe 77-79)
- `CBTRN02C.DB2-FORMAT-TS` (app/cbl/CBTRN02C.cbl, righe 159-159)
- `CBTRN02C.FD-ACCTFILE-REC` (app/cbl/CBTRN02C.cbl, righe 87-89)
- `CBTRN02C.FD-REJS-RECORD` (app/cbl/CBTRN02C.cbl, righe 82-84)
- `CBTRN02C.FD-TRAN-CAT-BAL-RECORD` (app/cbl/CBTRN02C.cbl, righe 92-97)
- `CBTRN02C.FD-TRAN-RECORD` (app/cbl/CBTRN02C.cbl, righe 67-69)
- `CBTRN02C.FD-TRANFILE-REC` (app/cbl/CBTRN02C.cbl, righe 72-74)
- `CBTRN02C.FD-XREFFILE-REC` (app/cbl/CBTRN02C.cbl, righe 77-79)
- `CBTRN02C.REJECT-RECORD` (app/cbl/CBTRN02C.cbl, righe 176-178)
- `CBTRN02C.WS-VALIDATION-TRAILER` (app/cbl/CBTRN02C.cbl, righe 180-182)
- `CBTRN03C.FD-CARDXREF-REC` (app/cbl/CBTRN03C.cbl, righe 68-70)
- `CBTRN03C.FD-DATEPARM-REC` (app/cbl/CBTRN03C.cbl, righe 88-88)
- `CBTRN03C.FD-TRAN-CAT-RECORD` (app/cbl/CBTRN03C.cbl, righe 78-82)
- `CBTRN03C.FD-TRANFILE-REC` (app/cbl/CBTRN03C.cbl, righe 62-65)
- `CBTRN03C.FD-TRANTYPE-REC` (app/cbl/CBTRN03C.cbl, righe 73-75)
- `CBTRN03C.WS-DATEPARM-RECORD` (app/cbl/CBTRN03C.cbl, righe 122-125)

## Limiti

- **Gruppi.** Offset e lunghezze dei gruppi del contratto non sono verificati qui: gli attesi riguardano solo i campi elementari (con gli indici `OCCURS` nell'identità). I gruppi restano affidati ai controlli di #3.
- **Record variabile `CBACT01C.VBR-REC`.** Il contratto è un solo campo `X(80)` (`CBACT01C.cbl` 85); il programma ne scrive prefissi di 12 e 39 byte (righe 288 e 303). Il codec rifiuta un campo più corto della sua lunghezza (`CampoIncompleto`), quindi per la sola chiamata al codec il carico è portato alla lunghezza della sentinella (80 byte, dal sorgente) con il riempimento `00`; confronto e ricodifica sono limitati al prefisso effettivo e i byte di riempimento non fanno parte dell'atteso. Le strutture `VBRC-REC1` e `VBRC-REC2`, che danno forma ai due carichi, non appartengono a questo contratto e i loro campi non si decodificano qui. Le intestazioni fisiche del record variabile su disco sono escluse. Una lunghezza del campo diversa da 80 ma non minore di 39 non si vede da questi prefissi: resta affidata al confronto con cb2xml di #3.
- **Profilo.** Solo `oracle-gnucobol`: il profilo `zos-ebcdic` è fuori ambito.
- **Dichiarazioni che nessun valore distingue.** Dove due dichiarazioni danno gli stessi byte e lo stesso valore, nemmeno un valore discriminante le separa, e la proprietà resta affidata a #3 (confronto di `PICTURE`, segno e scala del contratto con cb2xml):
  - un segno **aggiunto** a un campo senza segno: in DISPLAY una cifra semplice si legge positiva, in COMP-3 il codice `F` è accettato anche con segno, in COMP un valore positivo sotto 2^(8n-1) ha la stessa rappresentazione;
  - nei campi di una sola cifra (`CDEMO-PGM-CONTEXT`, `9(01)`) non si può accorciare la `PICTURE` né spostare la scala senza cambiare la lunghezza: quelle due mutazioni non sono applicabili;
  - una `PICTURE` con una cifra **in più** che resta nella stessa ampiezza: in COMP `9(03)` e `9(04)` occupano 2 byte, `9(11)` e `9(12)` 8 byte, `S9(10)V99` e `S9(11)V99` 8 byte (`EXP-CARD-CVV-CD`, `EXP-XREF-ACCT-ID`, `EXP-CARD-ACCT-ID`, `EXP-ACCT-CURR-CYC-DEBIT`); in COMP-3 con un numero pari di cifre il semiottetto di riempimento diventa una cifra zero in testa (`S9(10)V99` e `S9(11)V99` occupano 7 byte: `EXP-ACCT-CURR-BAL`, `EXP-ACCT-CASH-CREDIT-LIMIT`). Una cifra **in meno** invece è sempre rilevata, perché ogni valore usa tutte le cifre della propria `PICTURE`;
  - USAGE equivalenti (`COMP`, `COMP-4`, `BINARY`) e `PICTURE` scritte in modi equivalenti (`X(04)` e `X(4)`).
- **Mutazioni non applicabili.** `check.sh` elenca, con il motivo, le prove negative che non si possono costruire (per esempio spostare di un byte il confine di un campo binario, che occupa solo 2, 4 o 8 byte, o accorciare un campo di un byte solo): non sono contate come superate. Per quei confini la proprietà resta affidata a #3.
- **Lunghezza dichiarata altrove.** La somma delle lunghezze a mano è confrontata con una lunghezza dichiarata altrove (commento `RECLN` del copybook, `RECORDSIZE` del JCL, `FD` del programma), con la riga citata e verificata sul file. Per `COCOM01Y.CARDDEMO-COMMAREA` nessuna fonte esterna dichiara la lunghezza: 160 byte è solo la somma dei campi, e il confronto non è richiesto.

## Fonti della lunghezza

| sentinella | lunghezza | fonte |
| --- | ---: | --- |
| `CBACT01C.VBR-REC@base/prefisso-12` | 80 | `app/cbl/CBACT01C.cbl:83` «FROM 10 TO 80»; prefisso 12: `app/cbl/CBACT01C.cbl:288` «MOVE 12 TO WS-RECD-LEN» |
| `CBACT01C.VBR-REC@base/prefisso-39` | 80 | `app/cbl/CBACT01C.cbl:83` «FROM 10 TO 80»; prefisso 39: `app/cbl/CBACT01C.cbl:303` «MOVE 39 TO WS-RECD-LEN» |
| `COCOM01Y.CARDDEMO-COMMAREA@base/base` | 160 | nessuna (nessuna fonte esterna: la COMMAREA non ha RECORDSIZE, FD ne' commento con la lunghezza; 160 e' solo la somma dei campi) |
| `COSTM01.TRNX-RECORD@base/base` | 350 | `app/jcl/CREASTMT.JCL:32` «RECORDSIZE(350 350)» |
| `CSUSR01Y.SEC-USER-DATA@base/base` | 80 | `app/jcl/DUSRSECJ.jcl:66` «RECORDSIZE(80,80)» |
| `CUSTREC.CUSTOMER-RECORD@base/base` | 500 | `app/cpy/CUSTREC.cpy:2` «RECLN 500» |
| `CVACT01Y.ACCOUNT-RECORD@base/base` | 300 | `app/cpy/CVACT01Y.cpy:2` «RECLN 300»; `app/jcl/ACCTFILE.jcl:41` «RECORDSIZE(300 300)» |
| `CVACT02Y.CARD-RECORD@base/base` | 150 | `app/cpy/CVACT02Y.cpy:2` «RECLN 150» |
| `CVACT03Y.CARD-XREF-RECORD@base/base` | 50 | `app/cpy/CVACT03Y.cpy:2` «RECLN 50» |
| `CVCUS01Y.CUSTOMER-RECORD@base/base` | 500 | `app/cpy/CVCUS01Y.cpy:2` «RECLN 500» |
| `CVEXPORT.EXPORT-RECORD@EXPORT-ACCOUNT-DATA/EXPORT-ACCOUNT-DATA` | 500 | `app/cpy/CVEXPORT.cpy:5` «Total Record Length: 500 bytes»; `app/jcl/CBEXPORT.jcl:33` «RECORDSIZE(500 500)» |
| `CVEXPORT.EXPORT-RECORD@EXPORT-CARD-DATA/EXPORT-CARD-DATA` | 500 | `app/cpy/CVEXPORT.cpy:5` «Total Record Length: 500 bytes»; `app/jcl/CBEXPORT.jcl:33` «RECORDSIZE(500 500)» |
| `CVEXPORT.EXPORT-RECORD@EXPORT-CARD-XREF-DATA/EXPORT-CARD-XREF-DATA` | 500 | `app/cpy/CVEXPORT.cpy:5` «Total Record Length: 500 bytes»; `app/jcl/CBEXPORT.jcl:33` «RECORDSIZE(500 500)» |
| `CVEXPORT.EXPORT-RECORD@EXPORT-CUSTOMER-DATA/EXPORT-CUSTOMER-DATA` | 500 | `app/cpy/CVEXPORT.cpy:5` «Total Record Length: 500 bytes»; `app/jcl/CBEXPORT.jcl:33` «RECORDSIZE(500 500)» |
| `CVEXPORT.EXPORT-RECORD@EXPORT-TIMESTAMP-R/EXPORT-TIMESTAMP-R` | 500 | `app/cpy/CVEXPORT.cpy:5` «Total Record Length: 500 bytes»; `app/jcl/CBEXPORT.jcl:33` «RECORDSIZE(500 500)» |
| `CVEXPORT.EXPORT-RECORD@EXPORT-TRANSACTION-DATA/EXPORT-TRANSACTION-DATA` | 500 | `app/cpy/CVEXPORT.cpy:5` «Total Record Length: 500 bytes»; `app/jcl/CBEXPORT.jcl:33` «RECORDSIZE(500 500)» |
| `CVEXPORT.EXPORT-RECORD@base/base` | 500 | `app/cpy/CVEXPORT.cpy:5` «Total Record Length: 500 bytes»; `app/jcl/CBEXPORT.jcl:33` «RECORDSIZE(500 500)» |
| `CVTRA01Y.TRAN-CAT-BAL-RECORD@base/base` | 50 | `app/cpy/CVTRA01Y.cpy:2` «RECLN = 50»; `app/jcl/TCATBALF.jcl:41` «RECORDSIZE(50 50)» |
| `CVTRA02Y.DIS-GROUP-RECORD@base/base` | 50 | `app/cpy/CVTRA02Y.cpy:2` «RECLN = 50» |
| `CVTRA03Y.TRAN-TYPE-RECORD@base/base` | 60 | `app/cpy/CVTRA03Y.cpy:2` «RECLN = 60» |
| `CVTRA04Y.TRAN-CAT-RECORD@base/base` | 60 | `app/cpy/CVTRA04Y.cpy:2` «RECLN = 60» |
| `CVTRA05Y.TRAN-RECORD@base/base` | 350 | `app/cpy/CVTRA05Y.cpy:2` «RECLN = 350» |
| `CVTRA06Y.DALYTRAN-RECORD@base/base` | 350 | `app/cpy/CVTRA06Y.cpy:2` «RECLN = 350» |
