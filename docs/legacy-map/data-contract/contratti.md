# Contratti fisici dei tracciati (vista generata)

Generato da `./analysis/run.sh data-contract` a partire dall'output di cb2xml 1.01.08 (dialetto Mainframe) e da `censimento.tsv`. Non si modifica a mano: i file leggibili da macchina sono `contratti/<contratto>.tsv` e `contratti.tsv`.

Colonne: posizione (`offset`) a base 0 e `lunghezza` in byte, da cb2xml; `segno` = `S` se la PIC inizia con S; cifre intere e decimali dalla lunghezza di visualizzazione e dalla scala di cb2xml; `area` = voce con REDEFINES che contiene il campo (i campi con area `-` formano il record base); gli `OCCURS` sono espansi, una riga per elemento, con `indice`.

## Indice

| contratto | radice | sorgente | righe | classificazione | byte | campi | somma base | variabile | scritti | RECORDSIZE (JCL) | DCB osservata |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `COCOM01Y.CARDDEMO-COMMAREA` | CARDDEMO-COMMAREA | app/cpy/COCOM01Y.cpy | copybook | stato-di-conversazione | 160 | 16 | 160 | - | - | - | - |
| `COSTM01.TRNX-RECORD` | TRNX-RECORD | app/cpy/COSTM01.CPY | copybook | record-di-file | 350 | 14 | 350 | - | - | 350 350 (app/jcl/CREASTMT.JCL:29) | - |
| `CSUSR01Y.SEC-USER-DATA` | SEC-USER-DATA | app/cpy/CSUSR01Y.cpy | copybook | record-di-file | 80 | 6 | 80 | - | - | 80 80 (app/jcl/DUSRSECJ.jcl:64); 80 80 (app/jcl/ESDSRRDS.jcl:65); 80 80 (app/jcl/ESDSRRDS.jcl:99) | - |
| `CUSTREC.CUSTOMER-RECORD` | CUSTOMER-RECORD | app/cpy/CUSTREC.cpy | copybook | record-di-file | 500 | 19 | 500 | - | - | - | - |
| `CVACT01Y.ACCOUNT-RECORD` | ACCOUNT-RECORD | app/cpy/CVACT01Y.cpy | copybook | record-di-file | 300 | 13 | 300 | - | 300 | 300 300 (app/jcl/ACCTFILE.jcl:36) | LRECL=300 RECFM=FB (app/jcl/CBIMPORT.jcl:42) |
| `CVACT02Y.CARD-RECORD` | CARD-RECORD | app/cpy/CVACT02Y.cpy | copybook | record-di-file | 150 | 7 | 150 | - | 150 | 150 150 (app/jcl/CARDFILE.jcl:50) | - |
| `CVACT03Y.CARD-XREF-RECORD` | CARD-XREF-RECORD | app/cpy/CVACT03Y.cpy | copybook | record-di-file | 50 | 4 | 50 | - | 50 | 50 50 (app/jcl/XREFFILE.jcl:39) | LRECL=50 RECFM=FB (app/jcl/CBIMPORT.jcl:47) |
| `CVCUS01Y.CUSTOMER-RECORD` | CUSTOMER-RECORD | app/cpy/CVCUS01Y.cpy | copybook | record-di-file | 500 | 19 | 500 | - | 500 | 500 500 (app/jcl/CUSTFILE.jcl:46); 500 500 (app/jcl/DEFCUST.jcl:35) | LRECL=500 RECFM=FB (app/jcl/CBIMPORT.jcl:37) |
| `CVEXPORT.EXPORT-RECORD` | EXPORT-RECORD | app/cpy/CVEXPORT.cpy | copybook | record-di-file | 500 | 66 | 500 | - | - | 500 500 (app/jcl/CBEXPORT.jcl:30) | - |
| `CVTRA01Y.TRAN-CAT-BAL-RECORD` | TRAN-CAT-BAL-RECORD | app/cpy/CVTRA01Y.cpy | copybook | record-di-file | 50 | 5 | 50 | - | - | 50 50 (app/jcl/TCATBALF.jcl:36) | - |
| `CVTRA02Y.DIS-GROUP-RECORD` | DIS-GROUP-RECORD | app/cpy/CVTRA02Y.cpy | copybook | record-di-file | 50 | 5 | 50 | - | - | 50 50 (app/jcl/DISCGRP.jcl:36) | - |
| `CVTRA03Y.TRAN-TYPE-RECORD` | TRAN-TYPE-RECORD | app/cpy/CVTRA03Y.cpy | copybook | record-di-file | 60 | 3 | 60 | - | - | 60 60 (app/jcl/TRANTYPE.jcl:36) | - |
| `CVTRA04Y.TRAN-CAT-RECORD` | TRAN-CAT-RECORD | app/cpy/CVTRA04Y.cpy | copybook | record-di-file | 60 | 4 | 60 | - | - | 60 60 (app/jcl/TRANCATG.jcl:36) | - |
| `CVTRA05Y.TRAN-RECORD` | TRAN-RECORD | app/cpy/CVTRA05Y.cpy | copybook | record-di-file | 350 | 14 | 350 | - | 350 | 350 350 (app/jcl/TRANBKP.jcl:54); 350 350 (app/jcl/TRANFILE.jcl:49) | LRECL=350 RECFM=FB (app/jcl/CBIMPORT.jcl:52) |
| `CVTRA06Y.DALYTRAN-RECORD` | DALYTRAN-RECORD | app/cpy/CVTRA06Y.cpy | copybook | record-di-file | 350 | 14 | 350 | - | - | - | - |
| `CBACT01C.FD-ACCTFILE-REC` | FD-ACCTFILE-REC | app/cbl/CBACT01C.cbl | 53-55 | record-di-file | 300 | 2 | 300 | - | - | - | - |
| `CBACT01C.OUT-ACCT-REC` | OUT-ACCT-REC | app/cbl/CBACT01C.cbl | 57-69 | record-di-file | 107 | 11 | 107 | - | 107 | - | LRECL=107 RECFM=FB (app/jcl/READACCT.jcl:39) |
| `CBACT01C.ARR-ARRAY-REC` | ARR-ARRAY-REC | app/cbl/CBACT01C.cbl | 72-78 | record-di-file | 110 | 12 | 110 | - | 110 | - | LRECL=110 RECFM=FB (app/jcl/READACCT.jcl:43) |
| `CBACT01C.VBR-REC` | VBR-REC | app/cbl/CBACT01C.cbl | 85-85 | record-di-file | 80 | 1 | 80 | 10-80 DEPENDING ON WS-RECD-LEN | 12,39 | - | LRECL=84 RECFM=VB (app/jcl/READACCT.jcl:47) |
| `CBACT01C.VBRC-REC1` | VBRC-REC1 | app/cbl/CBACT01C.cbl | 123-125 | record-di-file | 12 | 2 | 12 | - | - | - | - |
| `CBACT01C.VBRC-REC2` | VBRC-REC2 | app/cbl/CBACT01C.cbl | 126-130 | record-di-file | 39 | 4 | 39 | - | - | - | - |
| `CBACT02C.FD-CARDFILE-REC` | FD-CARDFILE-REC | app/cbl/CBACT02C.cbl | 38-40 | record-di-file | 150 | 2 | 150 | - | - | - | - |
| `CBACT03C.FD-XREFFILE-REC` | FD-XREFFILE-REC | app/cbl/CBACT03C.cbl | 38-40 | record-di-file | 50 | 2 | 50 | - | - | - | - |
| `CBCUS01C.FD-CUSTFILE-REC` | FD-CUSTFILE-REC | app/cbl/CBCUS01C.cbl | 38-40 | record-di-file | 500 | 2 | 500 | - | - | - | - |
| `CBACT04C.FD-TRAN-CAT-BAL-RECORD` | FD-TRAN-CAT-BAL-RECORD | app/cbl/CBACT04C.cbl | 62-67 | record-di-file | 50 | 4 | 50 | - | - | - | - |
| `CBACT04C.FD-XREFFILE-REC` | FD-XREFFILE-REC | app/cbl/CBACT04C.cbl | 70-74 | record-di-file | 50 | 4 | 50 | - | - | - | - |
| `CBACT04C.FD-DISCGRP-REC` | FD-DISCGRP-REC | app/cbl/CBACT04C.cbl | 77-82 | record-di-file | 50 | 4 | 50 | - | - | - | - |
| `CBACT04C.FD-ACCTFILE-REC` | FD-ACCTFILE-REC | app/cbl/CBACT04C.cbl | 85-87 | record-di-file | 300 | 2 | 300 | - | 300 | - | - |
| `CBACT04C.FD-TRANFILE-REC` | FD-TRANFILE-REC | app/cbl/CBACT04C.cbl | 90-92 | record-di-file | 350 | 2 | 350 | - | 350 | - | LRECL=350 RECFM=F (app/jcl/INTCALC.jcl:39) |
| `CBTRN01C.FD-TRAN-RECORD` | FD-TRAN-RECORD | app/cbl/CBTRN01C.cbl | 67-69 | record-di-file | 350 | 2 | 350 | - | - | - | - |
| `CBTRN01C.FD-CUSTFILE-REC` | FD-CUSTFILE-REC | app/cbl/CBTRN01C.cbl | 72-74 | record-di-file | 500 | 2 | 500 | - | - | - | - |
| `CBTRN01C.FD-XREFFILE-REC` | FD-XREFFILE-REC | app/cbl/CBTRN01C.cbl | 77-79 | record-di-file | 50 | 2 | 50 | - | - | - | - |
| `CBTRN01C.FD-CARDFILE-REC` | FD-CARDFILE-REC | app/cbl/CBTRN01C.cbl | 82-84 | record-di-file | 150 | 2 | 150 | - | - | - | - |
| `CBTRN01C.FD-ACCTFILE-REC` | FD-ACCTFILE-REC | app/cbl/CBTRN01C.cbl | 87-89 | record-di-file | 300 | 2 | 300 | - | - | - | - |
| `CBTRN01C.FD-TRANFILE-REC` | FD-TRANFILE-REC | app/cbl/CBTRN01C.cbl | 92-94 | record-di-file | 350 | 2 | 350 | - | - | - | - |
| `CBTRN02C.FD-TRAN-RECORD` | FD-TRAN-RECORD | app/cbl/CBTRN02C.cbl | 67-69 | record-di-file | 350 | 2 | 350 | - | - | - | - |
| `CBTRN02C.FD-TRANFILE-REC` | FD-TRANFILE-REC | app/cbl/CBTRN02C.cbl | 72-74 | record-di-file | 350 | 2 | 350 | - | 350 | - | - |
| `CBTRN02C.FD-XREFFILE-REC` | FD-XREFFILE-REC | app/cbl/CBTRN02C.cbl | 77-79 | record-di-file | 50 | 2 | 50 | - | - | - | - |
| `CBTRN02C.FD-REJS-RECORD` | FD-REJS-RECORD | app/cbl/CBTRN02C.cbl | 82-84 | record-di-file | 430 | 2 | 430 | - | 430 | - | LRECL=430 RECFM=F (app/jcl/POSTTRAN.jcl:36) |
| `CBTRN02C.FD-ACCTFILE-REC` | FD-ACCTFILE-REC | app/cbl/CBTRN02C.cbl | 87-89 | record-di-file | 300 | 2 | 300 | - | 300 | - | - |
| `CBTRN02C.FD-TRAN-CAT-BAL-RECORD` | FD-TRAN-CAT-BAL-RECORD | app/cbl/CBTRN02C.cbl | 92-97 | record-di-file | 50 | 4 | 50 | - | 50 | - | - |
| `CBACT04C.DB2-FORMAT-TS` | DB2-FORMAT-TS | app/cbl/CBACT04C.cbl | 150-150 | record-di-file | 26 | 1 | 26 | - | - | - | - |
| `CBTRN02C.DB2-FORMAT-TS` | DB2-FORMAT-TS | app/cbl/CBTRN02C.cbl | 159-159 | record-di-file | 26 | 1 | 26 | - | - | - | - |
| `CBTRN02C.REJECT-RECORD` | REJECT-RECORD | app/cbl/CBTRN02C.cbl | 176-178 | record-di-file | 430 | 2 | 430 | - | - | - | - |
| `CBTRN02C.WS-VALIDATION-TRAILER` | WS-VALIDATION-TRAILER | app/cbl/CBTRN02C.cbl | 180-182 | record-di-file | 80 | 2 | 80 | - | - | - | - |
| `CBTRN03C.FD-TRANFILE-REC` | FD-TRANFILE-REC | app/cbl/CBTRN03C.cbl | 62-65 | record-di-file | 350 | 3 | 350 | - | - | - | - |
| `CBTRN03C.FD-CARDXREF-REC` | FD-CARDXREF-REC | app/cbl/CBTRN03C.cbl | 68-70 | record-di-file | 50 | 2 | 50 | - | - | - | - |
| `CBTRN03C.FD-TRANTYPE-REC` | FD-TRANTYPE-REC | app/cbl/CBTRN03C.cbl | 73-75 | record-di-file | 60 | 2 | 60 | - | - | - | - |
| `CBTRN03C.FD-TRAN-CAT-RECORD` | FD-TRAN-CAT-RECORD | app/cbl/CBTRN03C.cbl | 78-82 | record-di-file | 60 | 3 | 60 | - | - | - | - |
| `CBTRN03C.FD-DATEPARM-REC` | FD-DATEPARM-REC | app/cbl/CBTRN03C.cbl | 88-88 | record-di-file | 80 | 1 | 80 | - | - | - | - |
| `CBTRN03C.WS-DATEPARM-RECORD` | WS-DATEPARM-RECORD | app/cbl/CBTRN03C.cbl | 122-125 | record-di-file | 21 | 3 | 21 | - | - | - | - |
| `CBEXPORT.EXPORT-OUTPUT-RECORD` | EXPORT-OUTPUT-RECORD | app/cbl/CBEXPORT.cbl | 92-92 | record-di-file | 500 | 1 | 500 | - | 500 | - | - |
| `CBIMPORT.EXPORT-INPUT-RECORD` | EXPORT-INPUT-RECORD | app/cbl/CBIMPORT.cbl | 79-79 | record-di-file | 500 | 1 | 500 | - | - | - | - |
| `CBIMPORT.ERROR-OUTPUT-RECORD` | ERROR-OUTPUT-RECORD | app/cbl/CBIMPORT.cbl | 109-109 | record-di-file | 132 | 1 | 132 | - | 132 | - | LRECL=132 RECFM=FB (app/jcl/CBIMPORT.jcl:60) |
| `CBIMPORT.WS-ERROR-RECORD` | WS-ERROR-RECORD | app/cbl/CBIMPORT.cbl | 152-160 | record-di-file | 130 | 8 | 130 | - | - | - | - |
| `CBSTM03B.FD-TRNXFILE-REC` | FD-TRNXFILE-REC | app/cbl/CBSTM03B.CBL | 59-63 | record-di-file | 350 | 3 | 350 | - | - | - | - |
| `CBSTM03B.FD-XREFFILE-REC` | FD-XREFFILE-REC | app/cbl/CBSTM03B.CBL | 66-68 | record-di-file | 50 | 2 | 50 | - | - | - | - |
| `CBSTM03B.FD-CUSTFILE-REC` | FD-CUSTFILE-REC | app/cbl/CBSTM03B.CBL | 71-73 | record-di-file | 500 | 2 | 500 | - | - | - | - |
| `CBSTM03B.FD-ACCTFILE-REC` | FD-ACCTFILE-REC | app/cbl/CBSTM03B.CBL | 76-78 | record-di-file | 300 | 2 | 300 | - | - | - | - |

## `COCOM01Y.CARDDEMO-COMMAREA`

Radice `CARDDEMO-COMMAREA` di `app/cpy/COCOM01Y.cpy` (copybook), 160 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CARDDEMO-COMMAREA | 01 | gruppo | - | - | - | - | - | 0 | 160 | - | - | - |
| CDEMO-GENERAL-INFO | 05 | gruppo | - | - | - | - | - | 0 | 34 | - | - | - |
| CDEMO-FROM-TRANID | 10 | elementare | X(04) | DISPLAY | - | - | - | 0 | 4 | - | - | - |
| CDEMO-FROM-PROGRAM | 10 | elementare | X(08) | DISPLAY | - | - | - | 4 | 8 | - | - | - |
| CDEMO-TO-TRANID | 10 | elementare | X(04) | DISPLAY | - | - | - | 12 | 4 | - | - | - |
| CDEMO-TO-PROGRAM | 10 | elementare | X(08) | DISPLAY | - | - | - | 16 | 8 | - | - | - |
| CDEMO-USER-ID | 10 | elementare | X(08) | DISPLAY | - | - | - | 24 | 8 | - | - | - |
| CDEMO-USER-TYPE | 10 | elementare | X(01) | DISPLAY | - | - | - | 32 | 1 | - | - | - |
| CDEMO-PGM-CONTEXT | 10 | elementare | 9(01) | DISPLAY | - | 1 | 0 | 33 | 1 | - | - | - |
| CDEMO-CUSTOMER-INFO | 05 | gruppo | - | - | - | - | - | 34 | 84 | - | - | - |
| CDEMO-CUST-ID | 10 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 34 | 9 | - | - | - |
| CDEMO-CUST-FNAME | 10 | elementare | X(25) | DISPLAY | - | - | - | 43 | 25 | - | - | - |
| CDEMO-CUST-MNAME | 10 | elementare | X(25) | DISPLAY | - | - | - | 68 | 25 | - | - | - |
| CDEMO-CUST-LNAME | 10 | elementare | X(25) | DISPLAY | - | - | - | 93 | 25 | - | - | - |
| CDEMO-ACCOUNT-INFO | 05 | gruppo | - | - | - | - | - | 118 | 12 | - | - | - |
| CDEMO-ACCT-ID | 10 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 118 | 11 | - | - | - |
| CDEMO-ACCT-STATUS | 10 | elementare | X(01) | DISPLAY | - | - | - | 129 | 1 | - | - | - |
| CDEMO-CARD-INFO | 05 | gruppo | - | - | - | - | - | 130 | 16 | - | - | - |
| CDEMO-CARD-NUM | 10 | elementare | 9(16) | DISPLAY | - | 16 | 0 | 130 | 16 | - | - | - |
| CDEMO-MORE-INFO | 05 | gruppo | - | - | - | - | - | 146 | 14 | - | - | - |
| CDEMO-LAST-MAP | 10 | elementare | X(7) | DISPLAY | - | - | - | 146 | 7 | - | - | - |
| CDEMO-LAST-MAPSET | 10 | elementare | X(7) | DISPLAY | - | - | - | 153 | 7 | - | - | - |

## `COSTM01.TRNX-RECORD`

Radice `TRNX-RECORD` di `app/cpy/COSTM01.CPY` (copybook), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TRNX-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| TRNX-KEY | 05 | gruppo | - | - | - | - | - | 0 | 32 | - | - | - |
| TRNX-CARD-NUM | 10 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| TRNX-ID | 10 | elementare | X(16) | DISPLAY | - | - | - | 16 | 16 | - | - | - |
| TRNX-REST | 05 | gruppo | - | - | - | - | - | 32 | 318 | - | - | - |
| TRNX-TYPE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 32 | 2 | - | - | - |
| TRNX-CAT-CD | 10 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 34 | 4 | - | - | - |
| TRNX-SOURCE | 10 | elementare | X(10) | DISPLAY | - | - | - | 38 | 10 | - | - | - |
| TRNX-DESC | 10 | elementare | X(100) | DISPLAY | - | - | - | 48 | 100 | - | - | - |
| TRNX-AMT | 10 | elementare | S9(09)V99 | DISPLAY | S | 9 | 2 | 148 | 11 | - | - | - |
| TRNX-MERCHANT-ID | 10 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 159 | 9 | - | - | - |
| TRNX-MERCHANT-NAME | 10 | elementare | X(50) | DISPLAY | - | - | - | 168 | 50 | - | - | - |
| TRNX-MERCHANT-CITY | 10 | elementare | X(50) | DISPLAY | - | - | - | 218 | 50 | - | - | - |
| TRNX-MERCHANT-ZIP | 10 | elementare | X(10) | DISPLAY | - | - | - | 268 | 10 | - | - | - |
| TRNX-ORIG-TS | 10 | elementare | X(26) | DISPLAY | - | - | - | 278 | 26 | - | - | - |
| TRNX-PROC-TS | 10 | elementare | X(26) | DISPLAY | - | - | - | 304 | 26 | - | - | - |
| FILLER | 10 | elementare | X(20) | DISPLAY | - | - | - | 330 | 20 | - | - | - |

## `CSUSR01Y.SEC-USER-DATA`

Radice `SEC-USER-DATA` di `app/cpy/CSUSR01Y.cpy` (copybook), 80 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SEC-USER-DATA | 01 | gruppo | - | - | - | - | - | 0 | 80 | - | - | - |
| SEC-USR-ID | 05 | elementare | X(08) | DISPLAY | - | - | - | 0 | 8 | - | - | - |
| SEC-USR-FNAME | 05 | elementare | X(20) | DISPLAY | - | - | - | 8 | 20 | - | - | - |
| SEC-USR-LNAME | 05 | elementare | X(20) | DISPLAY | - | - | - | 28 | 20 | - | - | - |
| SEC-USR-PWD | 05 | elementare | X(08) | DISPLAY | - | - | - | 48 | 8 | - | - | - |
| SEC-USR-TYPE | 05 | elementare | X(01) | DISPLAY | - | - | - | 56 | 1 | - | - | - |
| SEC-USR-FILLER | 05 | elementare | X(23) | DISPLAY | - | - | - | 57 | 23 | - | - | - |

## `CUSTREC.CUSTOMER-RECORD`

Radice `CUSTOMER-RECORD` di `app/cpy/CUSTREC.cpy` (copybook), 500 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUSTOMER-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 500 | - | - | - |
| CUST-ID | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 0 | 9 | - | - | - |
| CUST-FIRST-NAME | 05 | elementare | X(25) | DISPLAY | - | - | - | 9 | 25 | - | - | - |
| CUST-MIDDLE-NAME | 05 | elementare | X(25) | DISPLAY | - | - | - | 34 | 25 | - | - | - |
| CUST-LAST-NAME | 05 | elementare | X(25) | DISPLAY | - | - | - | 59 | 25 | - | - | - |
| CUST-ADDR-LINE-1 | 05 | elementare | X(50) | DISPLAY | - | - | - | 84 | 50 | - | - | - |
| CUST-ADDR-LINE-2 | 05 | elementare | X(50) | DISPLAY | - | - | - | 134 | 50 | - | - | - |
| CUST-ADDR-LINE-3 | 05 | elementare | X(50) | DISPLAY | - | - | - | 184 | 50 | - | - | - |
| CUST-ADDR-STATE-CD | 05 | elementare | X(02) | DISPLAY | - | - | - | 234 | 2 | - | - | - |
| CUST-ADDR-COUNTRY-CD | 05 | elementare | X(03) | DISPLAY | - | - | - | 236 | 3 | - | - | - |
| CUST-ADDR-ZIP | 05 | elementare | X(10) | DISPLAY | - | - | - | 239 | 10 | - | - | - |
| CUST-PHONE-NUM-1 | 05 | elementare | X(15) | DISPLAY | - | - | - | 249 | 15 | - | - | - |
| CUST-PHONE-NUM-2 | 05 | elementare | X(15) | DISPLAY | - | - | - | 264 | 15 | - | - | - |
| CUST-SSN | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 279 | 9 | - | - | - |
| CUST-GOVT-ISSUED-ID | 05 | elementare | X(20) | DISPLAY | - | - | - | 288 | 20 | - | - | - |
| CUST-DOB-YYYYMMDD | 05 | elementare | X(10) | DISPLAY | - | - | - | 308 | 10 | - | - | - |
| CUST-EFT-ACCOUNT-ID | 05 | elementare | X(10) | DISPLAY | - | - | - | 318 | 10 | - | - | - |
| CUST-PRI-CARD-HOLDER-IND | 05 | elementare | X(01) | DISPLAY | - | - | - | 328 | 1 | - | - | - |
| CUST-FICO-CREDIT-SCORE | 05 | elementare | 9(03) | DISPLAY | - | 3 | 0 | 329 | 3 | - | - | - |
| FILLER | 05 | elementare | X(168) | DISPLAY | - | - | - | 332 | 168 | - | - | - |

## `CVACT01Y.ACCOUNT-RECORD`

Radice `ACCOUNT-RECORD` di `app/cpy/CVACT01Y.cpy` (copybook), 300 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ACCOUNT-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 300 | - | - | - |
| ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| ACCT-ACTIVE-STATUS | 05 | elementare | X(01) | DISPLAY | - | - | - | 11 | 1 | - | - | - |
| ACCT-CURR-BAL | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 12 | 12 | - | - | - |
| ACCT-CREDIT-LIMIT | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 24 | 12 | - | - | - |
| ACCT-CASH-CREDIT-LIMIT | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 36 | 12 | - | - | - |
| ACCT-OPEN-DATE | 05 | elementare | X(10) | DISPLAY | - | - | - | 48 | 10 | - | - | - |
| ACCT-EXPIRAION-DATE | 05 | elementare | X(10) | DISPLAY | - | - | - | 58 | 10 | - | - | - |
| ACCT-REISSUE-DATE | 05 | elementare | X(10) | DISPLAY | - | - | - | 68 | 10 | - | - | - |
| ACCT-CURR-CYC-CREDIT | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 78 | 12 | - | - | - |
| ACCT-CURR-CYC-DEBIT | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 90 | 12 | - | - | - |
| ACCT-ADDR-ZIP | 05 | elementare | X(10) | DISPLAY | - | - | - | 102 | 10 | - | - | - |
| ACCT-GROUP-ID | 05 | elementare | X(10) | DISPLAY | - | - | - | 112 | 10 | - | - | - |
| FILLER | 05 | elementare | X(178) | DISPLAY | - | - | - | 122 | 178 | - | - | - |

## `CVACT02Y.CARD-RECORD`

Radice `CARD-RECORD` di `app/cpy/CVACT02Y.cpy` (copybook), 150 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CARD-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 150 | - | - | - |
| CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| CARD-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 16 | 11 | - | - | - |
| CARD-CVV-CD | 05 | elementare | 9(03) | DISPLAY | - | 3 | 0 | 27 | 3 | - | - | - |
| CARD-EMBOSSED-NAME | 05 | elementare | X(50) | DISPLAY | - | - | - | 30 | 50 | - | - | - |
| CARD-EXPIRAION-DATE | 05 | elementare | X(10) | DISPLAY | - | - | - | 80 | 10 | - | - | - |
| CARD-ACTIVE-STATUS | 05 | elementare | X(01) | DISPLAY | - | - | - | 90 | 1 | - | - | - |
| FILLER | 05 | elementare | X(59) | DISPLAY | - | - | - | 91 | 59 | - | - | - |

## `CVACT03Y.CARD-XREF-RECORD`

Radice `CARD-XREF-RECORD` di `app/cpy/CVACT03Y.cpy` (copybook), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CARD-XREF-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| XREF-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| XREF-CUST-ID | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 16 | 9 | - | - | - |
| XREF-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 25 | 11 | - | - | - |
| FILLER | 05 | elementare | X(14) | DISPLAY | - | - | - | 36 | 14 | - | - | - |

## `CVCUS01Y.CUSTOMER-RECORD`

Radice `CUSTOMER-RECORD` di `app/cpy/CVCUS01Y.cpy` (copybook), 500 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUSTOMER-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 500 | - | - | - |
| CUST-ID | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 0 | 9 | - | - | - |
| CUST-FIRST-NAME | 05 | elementare | X(25) | DISPLAY | - | - | - | 9 | 25 | - | - | - |
| CUST-MIDDLE-NAME | 05 | elementare | X(25) | DISPLAY | - | - | - | 34 | 25 | - | - | - |
| CUST-LAST-NAME | 05 | elementare | X(25) | DISPLAY | - | - | - | 59 | 25 | - | - | - |
| CUST-ADDR-LINE-1 | 05 | elementare | X(50) | DISPLAY | - | - | - | 84 | 50 | - | - | - |
| CUST-ADDR-LINE-2 | 05 | elementare | X(50) | DISPLAY | - | - | - | 134 | 50 | - | - | - |
| CUST-ADDR-LINE-3 | 05 | elementare | X(50) | DISPLAY | - | - | - | 184 | 50 | - | - | - |
| CUST-ADDR-STATE-CD | 05 | elementare | X(02) | DISPLAY | - | - | - | 234 | 2 | - | - | - |
| CUST-ADDR-COUNTRY-CD | 05 | elementare | X(03) | DISPLAY | - | - | - | 236 | 3 | - | - | - |
| CUST-ADDR-ZIP | 05 | elementare | X(10) | DISPLAY | - | - | - | 239 | 10 | - | - | - |
| CUST-PHONE-NUM-1 | 05 | elementare | X(15) | DISPLAY | - | - | - | 249 | 15 | - | - | - |
| CUST-PHONE-NUM-2 | 05 | elementare | X(15) | DISPLAY | - | - | - | 264 | 15 | - | - | - |
| CUST-SSN | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 279 | 9 | - | - | - |
| CUST-GOVT-ISSUED-ID | 05 | elementare | X(20) | DISPLAY | - | - | - | 288 | 20 | - | - | - |
| CUST-DOB-YYYY-MM-DD | 05 | elementare | X(10) | DISPLAY | - | - | - | 308 | 10 | - | - | - |
| CUST-EFT-ACCOUNT-ID | 05 | elementare | X(10) | DISPLAY | - | - | - | 318 | 10 | - | - | - |
| CUST-PRI-CARD-HOLDER-IND | 05 | elementare | X(01) | DISPLAY | - | - | - | 328 | 1 | - | - | - |
| CUST-FICO-CREDIT-SCORE | 05 | elementare | 9(03) | DISPLAY | - | 3 | 0 | 329 | 3 | - | - | - |
| FILLER | 05 | elementare | X(168) | DISPLAY | - | - | - | 332 | 168 | - | - | - |

## `CVEXPORT.EXPORT-RECORD`

Radice `EXPORT-RECORD` di `app/cpy/CVEXPORT.cpy` (copybook), 500 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXPORT-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 500 | - | - | - |
| EXPORT-REC-TYPE | 05 | elementare | X(1) | DISPLAY | - | - | - | 0 | 1 | - | - | - |
| EXPORT-TIMESTAMP | 05 | elementare | X(26) | DISPLAY | - | - | - | 1 | 26 | - | - | - |
| EXPORT-TIMESTAMP-R | 05 | gruppo | - | - | - | - | - | 1 | 26 | EXPORT-TIMESTAMP | EXPORT-TIMESTAMP-R | - |
| EXPORT-DATE | 10 | elementare | X(10) | DISPLAY | - | - | - | 1 | 10 | - | EXPORT-TIMESTAMP-R | - |
| EXPORT-DATE-TIME-SEP | 10 | elementare | X(1) | DISPLAY | - | - | - | 11 | 1 | - | EXPORT-TIMESTAMP-R | - |
| EXPORT-TIME | 10 | elementare | X(15) | DISPLAY | - | - | - | 12 | 15 | - | EXPORT-TIMESTAMP-R | - |
| EXPORT-SEQUENCE-NUM | 05 | elementare | 9(9) | COMP | - | 9 | 0 | 27 | 4 | - | - | - |
| EXPORT-BRANCH-ID | 05 | elementare | X(4) | DISPLAY | - | - | - | 31 | 4 | - | - | - |
| EXPORT-REGION-CODE | 05 | elementare | X(5) | DISPLAY | - | - | - | 35 | 5 | - | - | - |
| EXPORT-RECORD-DATA | 05 | elementare | X(460) | DISPLAY | - | - | - | 40 | 460 | - | - | - |
| EXPORT-CUSTOMER-DATA | 05 | gruppo | - | - | - | - | - | 40 | 460 | EXPORT-RECORD-DATA | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-ID | 10 | elementare | 9(09) | COMP | - | 9 | 0 | 40 | 4 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-FIRST-NAME | 10 | elementare | X(25) | DISPLAY | - | - | - | 44 | 25 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-MIDDLE-NAME | 10 | elementare | X(25) | DISPLAY | - | - | - | 69 | 25 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-LAST-NAME | 10 | elementare | X(25) | DISPLAY | - | - | - | 94 | 25 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-ADDR-LINES | 10 | gruppo | - | - | - | - | - | 119 | 50 | - | EXPORT-CUSTOMER-DATA | 1 |
| EXP-CUST-ADDR-LINE | 15 | elementare | X(50) | DISPLAY | - | - | - | 119 | 50 | - | EXPORT-CUSTOMER-DATA | 1 |
| EXP-CUST-ADDR-LINES | 10 | gruppo | - | - | - | - | - | 169 | 50 | - | EXPORT-CUSTOMER-DATA | 2 |
| EXP-CUST-ADDR-LINE | 15 | elementare | X(50) | DISPLAY | - | - | - | 169 | 50 | - | EXPORT-CUSTOMER-DATA | 2 |
| EXP-CUST-ADDR-LINES | 10 | gruppo | - | - | - | - | - | 219 | 50 | - | EXPORT-CUSTOMER-DATA | 3 |
| EXP-CUST-ADDR-LINE | 15 | elementare | X(50) | DISPLAY | - | - | - | 219 | 50 | - | EXPORT-CUSTOMER-DATA | 3 |
| EXP-CUST-ADDR-STATE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 269 | 2 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-ADDR-COUNTRY-CD | 10 | elementare | X(03) | DISPLAY | - | - | - | 271 | 3 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-ADDR-ZIP | 10 | elementare | X(10) | DISPLAY | - | - | - | 274 | 10 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-PHONE-NUMS | 10 | gruppo | - | - | - | - | - | 284 | 15 | - | EXPORT-CUSTOMER-DATA | 1 |
| EXP-CUST-PHONE-NUM | 15 | elementare | X(15) | DISPLAY | - | - | - | 284 | 15 | - | EXPORT-CUSTOMER-DATA | 1 |
| EXP-CUST-PHONE-NUMS | 10 | gruppo | - | - | - | - | - | 299 | 15 | - | EXPORT-CUSTOMER-DATA | 2 |
| EXP-CUST-PHONE-NUM | 15 | elementare | X(15) | DISPLAY | - | - | - | 299 | 15 | - | EXPORT-CUSTOMER-DATA | 2 |
| EXP-CUST-SSN | 10 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 314 | 9 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-GOVT-ISSUED-ID | 10 | elementare | X(20) | DISPLAY | - | - | - | 323 | 20 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-DOB-YYYY-MM-DD | 10 | elementare | X(10) | DISPLAY | - | - | - | 343 | 10 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-EFT-ACCOUNT-ID | 10 | elementare | X(10) | DISPLAY | - | - | - | 353 | 10 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-PRI-CARD-HOLDER-IND | 10 | elementare | X(01) | DISPLAY | - | - | - | 363 | 1 | - | EXPORT-CUSTOMER-DATA | - |
| EXP-CUST-FICO-CREDIT-SCORE | 10 | elementare | 9(03) | COMP-3 | - | 3 | 0 | 364 | 2 | - | EXPORT-CUSTOMER-DATA | - |
| FILLER | 10 | elementare | X(134) | DISPLAY | - | - | - | 366 | 134 | - | EXPORT-CUSTOMER-DATA | - |
| EXPORT-ACCOUNT-DATA | 05 | gruppo | - | - | - | - | - | 40 | 460 | EXPORT-RECORD-DATA | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-ID | 10 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 40 | 11 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-ACTIVE-STATUS | 10 | elementare | X(01) | DISPLAY | - | - | - | 51 | 1 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-CURR-BAL | 10 | elementare | S9(10)V99 | COMP-3 | S | 10 | 2 | 52 | 7 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-CREDIT-LIMIT | 10 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 59 | 12 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-CASH-CREDIT-LIMIT | 10 | elementare | S9(10)V99 | COMP-3 | S | 10 | 2 | 71 | 7 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-OPEN-DATE | 10 | elementare | X(10) | DISPLAY | - | - | - | 78 | 10 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-EXPIRAION-DATE | 10 | elementare | X(10) | DISPLAY | - | - | - | 88 | 10 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-REISSUE-DATE | 10 | elementare | X(10) | DISPLAY | - | - | - | 98 | 10 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-CURR-CYC-CREDIT | 10 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 108 | 12 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-CURR-CYC-DEBIT | 10 | elementare | S9(10)V99 | COMP | S | 10 | 2 | 120 | 8 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-ADDR-ZIP | 10 | elementare | X(10) | DISPLAY | - | - | - | 128 | 10 | - | EXPORT-ACCOUNT-DATA | - |
| EXP-ACCT-GROUP-ID | 10 | elementare | X(10) | DISPLAY | - | - | - | 138 | 10 | - | EXPORT-ACCOUNT-DATA | - |
| FILLER | 10 | elementare | X(352) | DISPLAY | - | - | - | 148 | 352 | - | EXPORT-ACCOUNT-DATA | - |
| EXPORT-TRANSACTION-DATA | 05 | gruppo | - | - | - | - | - | 40 | 460 | EXPORT-RECORD-DATA | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-ID | 10 | elementare | X(16) | DISPLAY | - | - | - | 40 | 16 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-TYPE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 56 | 2 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-CAT-CD | 10 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 58 | 4 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-SOURCE | 10 | elementare | X(10) | DISPLAY | - | - | - | 62 | 10 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-DESC | 10 | elementare | X(100) | DISPLAY | - | - | - | 72 | 100 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-AMT | 10 | elementare | S9(09)V99 | COMP-3 | S | 9 | 2 | 172 | 6 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-MERCHANT-ID | 10 | elementare | 9(09) | COMP | - | 9 | 0 | 178 | 4 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-MERCHANT-NAME | 10 | elementare | X(50) | DISPLAY | - | - | - | 182 | 50 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-MERCHANT-CITY | 10 | elementare | X(50) | DISPLAY | - | - | - | 232 | 50 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-MERCHANT-ZIP | 10 | elementare | X(10) | DISPLAY | - | - | - | 282 | 10 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-CARD-NUM | 10 | elementare | X(16) | DISPLAY | - | - | - | 292 | 16 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-ORIG-TS | 10 | elementare | X(26) | DISPLAY | - | - | - | 308 | 26 | - | EXPORT-TRANSACTION-DATA | - |
| EXP-TRAN-PROC-TS | 10 | elementare | X(26) | DISPLAY | - | - | - | 334 | 26 | - | EXPORT-TRANSACTION-DATA | - |
| FILLER | 10 | elementare | X(140) | DISPLAY | - | - | - | 360 | 140 | - | EXPORT-TRANSACTION-DATA | - |
| EXPORT-CARD-XREF-DATA | 05 | gruppo | - | - | - | - | - | 40 | 460 | EXPORT-RECORD-DATA | EXPORT-CARD-XREF-DATA | - |
| EXP-XREF-CARD-NUM | 10 | elementare | X(16) | DISPLAY | - | - | - | 40 | 16 | - | EXPORT-CARD-XREF-DATA | - |
| EXP-XREF-CUST-ID | 10 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 56 | 9 | - | EXPORT-CARD-XREF-DATA | - |
| EXP-XREF-ACCT-ID | 10 | elementare | 9(11) | COMP | - | 11 | 0 | 65 | 8 | - | EXPORT-CARD-XREF-DATA | - |
| FILLER | 10 | elementare | X(427) | DISPLAY | - | - | - | 73 | 427 | - | EXPORT-CARD-XREF-DATA | - |
| EXPORT-CARD-DATA | 05 | gruppo | - | - | - | - | - | 40 | 460 | EXPORT-RECORD-DATA | EXPORT-CARD-DATA | - |
| EXP-CARD-NUM | 10 | elementare | X(16) | DISPLAY | - | - | - | 40 | 16 | - | EXPORT-CARD-DATA | - |
| EXP-CARD-ACCT-ID | 10 | elementare | 9(11) | COMP | - | 11 | 0 | 56 | 8 | - | EXPORT-CARD-DATA | - |
| EXP-CARD-CVV-CD | 10 | elementare | 9(03) | COMP | - | 3 | 0 | 64 | 2 | - | EXPORT-CARD-DATA | - |
| EXP-CARD-EMBOSSED-NAME | 10 | elementare | X(50) | DISPLAY | - | - | - | 66 | 50 | - | EXPORT-CARD-DATA | - |
| EXP-CARD-EXPIRAION-DATE | 10 | elementare | X(10) | DISPLAY | - | - | - | 116 | 10 | - | EXPORT-CARD-DATA | - |
| EXP-CARD-ACTIVE-STATUS | 10 | elementare | X(01) | DISPLAY | - | - | - | 126 | 1 | - | EXPORT-CARD-DATA | - |
| FILLER | 10 | elementare | X(373) | DISPLAY | - | - | - | 127 | 373 | - | EXPORT-CARD-DATA | - |

## `CVTRA01Y.TRAN-CAT-BAL-RECORD`

Radice `TRAN-CAT-BAL-RECORD` di `app/cpy/CVTRA01Y.cpy` (copybook), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TRAN-CAT-BAL-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| TRAN-CAT-KEY | 05 | gruppo | - | - | - | - | - | 0 | 17 | - | - | - |
| TRANCAT-ACCT-ID | 10 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| TRANCAT-TYPE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 11 | 2 | - | - | - |
| TRANCAT-CD | 10 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 13 | 4 | - | - | - |
| TRAN-CAT-BAL | 05 | elementare | S9(09)V99 | DISPLAY | S | 9 | 2 | 17 | 11 | - | - | - |
| FILLER | 05 | elementare | X(22) | DISPLAY | - | - | - | 28 | 22 | - | - | - |

## `CVTRA02Y.DIS-GROUP-RECORD`

Radice `DIS-GROUP-RECORD` di `app/cpy/CVTRA02Y.cpy` (copybook), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIS-GROUP-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| DIS-GROUP-KEY | 05 | gruppo | - | - | - | - | - | 0 | 16 | - | - | - |
| DIS-ACCT-GROUP-ID | 10 | elementare | X(10) | DISPLAY | - | - | - | 0 | 10 | - | - | - |
| DIS-TRAN-TYPE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 10 | 2 | - | - | - |
| DIS-TRAN-CAT-CD | 10 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 12 | 4 | - | - | - |
| DIS-INT-RATE | 05 | elementare | S9(04)V99 | DISPLAY | S | 4 | 2 | 16 | 6 | - | - | - |
| FILLER | 05 | elementare | X(28) | DISPLAY | - | - | - | 22 | 28 | - | - | - |

## `CVTRA03Y.TRAN-TYPE-RECORD`

Radice `TRAN-TYPE-RECORD` di `app/cpy/CVTRA03Y.cpy` (copybook), 60 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TRAN-TYPE-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 60 | - | - | - |
| TRAN-TYPE | 05 | elementare | X(02) | DISPLAY | - | - | - | 0 | 2 | - | - | - |
| TRAN-TYPE-DESC | 05 | elementare | X(50) | DISPLAY | - | - | - | 2 | 50 | - | - | - |
| FILLER | 05 | elementare | X(08) | DISPLAY | - | - | - | 52 | 8 | - | - | - |

## `CVTRA04Y.TRAN-CAT-RECORD`

Radice `TRAN-CAT-RECORD` di `app/cpy/CVTRA04Y.cpy` (copybook), 60 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TRAN-CAT-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 60 | - | - | - |
| TRAN-CAT-KEY | 05 | gruppo | - | - | - | - | - | 0 | 6 | - | - | - |
| TRAN-TYPE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 0 | 2 | - | - | - |
| TRAN-CAT-CD | 10 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 2 | 4 | - | - | - |
| TRAN-CAT-TYPE-DESC | 05 | elementare | X(50) | DISPLAY | - | - | - | 6 | 50 | - | - | - |
| FILLER | 05 | elementare | X(04) | DISPLAY | - | - | - | 56 | 4 | - | - | - |

## `CVTRA05Y.TRAN-RECORD`

Radice `TRAN-RECORD` di `app/cpy/CVTRA05Y.cpy` (copybook), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TRAN-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| TRAN-ID | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| TRAN-TYPE-CD | 05 | elementare | X(02) | DISPLAY | - | - | - | 16 | 2 | - | - | - |
| TRAN-CAT-CD | 05 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 18 | 4 | - | - | - |
| TRAN-SOURCE | 05 | elementare | X(10) | DISPLAY | - | - | - | 22 | 10 | - | - | - |
| TRAN-DESC | 05 | elementare | X(100) | DISPLAY | - | - | - | 32 | 100 | - | - | - |
| TRAN-AMT | 05 | elementare | S9(09)V99 | DISPLAY | S | 9 | 2 | 132 | 11 | - | - | - |
| TRAN-MERCHANT-ID | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 143 | 9 | - | - | - |
| TRAN-MERCHANT-NAME | 05 | elementare | X(50) | DISPLAY | - | - | - | 152 | 50 | - | - | - |
| TRAN-MERCHANT-CITY | 05 | elementare | X(50) | DISPLAY | - | - | - | 202 | 50 | - | - | - |
| TRAN-MERCHANT-ZIP | 05 | elementare | X(10) | DISPLAY | - | - | - | 252 | 10 | - | - | - |
| TRAN-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 262 | 16 | - | - | - |
| TRAN-ORIG-TS | 05 | elementare | X(26) | DISPLAY | - | - | - | 278 | 26 | - | - | - |
| TRAN-PROC-TS | 05 | elementare | X(26) | DISPLAY | - | - | - | 304 | 26 | - | - | - |
| FILLER | 05 | elementare | X(20) | DISPLAY | - | - | - | 330 | 20 | - | - | - |

## `CVTRA06Y.DALYTRAN-RECORD`

Radice `DALYTRAN-RECORD` di `app/cpy/CVTRA06Y.cpy` (copybook), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DALYTRAN-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| DALYTRAN-ID | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| DALYTRAN-TYPE-CD | 05 | elementare | X(02) | DISPLAY | - | - | - | 16 | 2 | - | - | - |
| DALYTRAN-CAT-CD | 05 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 18 | 4 | - | - | - |
| DALYTRAN-SOURCE | 05 | elementare | X(10) | DISPLAY | - | - | - | 22 | 10 | - | - | - |
| DALYTRAN-DESC | 05 | elementare | X(100) | DISPLAY | - | - | - | 32 | 100 | - | - | - |
| DALYTRAN-AMT | 05 | elementare | S9(09)V99 | DISPLAY | S | 9 | 2 | 132 | 11 | - | - | - |
| DALYTRAN-MERCHANT-ID | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 143 | 9 | - | - | - |
| DALYTRAN-MERCHANT-NAME | 05 | elementare | X(50) | DISPLAY | - | - | - | 152 | 50 | - | - | - |
| DALYTRAN-MERCHANT-CITY | 05 | elementare | X(50) | DISPLAY | - | - | - | 202 | 50 | - | - | - |
| DALYTRAN-MERCHANT-ZIP | 05 | elementare | X(10) | DISPLAY | - | - | - | 252 | 10 | - | - | - |
| DALYTRAN-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 262 | 16 | - | - | - |
| DALYTRAN-ORIG-TS | 05 | elementare | X(26) | DISPLAY | - | - | - | 278 | 26 | - | - | - |
| DALYTRAN-PROC-TS | 05 | elementare | X(26) | DISPLAY | - | - | - | 304 | 26 | - | - | - |
| FILLER | 05 | elementare | X(20) | DISPLAY | - | - | - | 330 | 20 | - | - | - |

## `CBACT01C.FD-ACCTFILE-REC`

Radice `FD-ACCTFILE-REC` di `app/cbl/CBACT01C.cbl` (53-55), 300 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-ACCTFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 300 | - | - | - |
| FD-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| FD-ACCT-DATA | 05 | elementare | X(289) | DISPLAY | - | - | - | 11 | 289 | - | - | - |

## `CBACT01C.OUT-ACCT-REC`

Radice `OUT-ACCT-REC` di `app/cbl/CBACT01C.cbl` (57-69), 107 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OUT-ACCT-REC | 01 | gruppo | - | - | - | - | - | 0 | 107 | - | - | - |
| OUT-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| OUT-ACCT-ACTIVE-STATUS | 05 | elementare | X(01) | DISPLAY | - | - | - | 11 | 1 | - | - | - |
| OUT-ACCT-CURR-BAL | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 12 | 12 | - | - | - |
| OUT-ACCT-CREDIT-LIMIT | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 24 | 12 | - | - | - |
| OUT-ACCT-CASH-CREDIT-LIMIT | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 36 | 12 | - | - | - |
| OUT-ACCT-OPEN-DATE | 05 | elementare | X(10) | DISPLAY | - | - | - | 48 | 10 | - | - | - |
| OUT-ACCT-EXPIRAION-DATE | 05 | elementare | X(10) | DISPLAY | - | - | - | 58 | 10 | - | - | - |
| OUT-ACCT-REISSUE-DATE | 05 | elementare | X(10) | DISPLAY | - | - | - | 68 | 10 | - | - | - |
| OUT-ACCT-CURR-CYC-CREDIT | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 78 | 12 | - | - | - |
| OUT-ACCT-CURR-CYC-DEBIT | 05 | elementare | S9(10)V99 | COMP-3 | S | 10 | 2 | 90 | 7 | - | - | - |
| OUT-ACCT-GROUP-ID | 05 | elementare | X(10) | DISPLAY | - | - | - | 97 | 10 | - | - | - |

## `CBACT01C.ARR-ARRAY-REC`

Radice `ARR-ARRAY-REC` di `app/cbl/CBACT01C.cbl` (72-78), 110 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ARR-ARRAY-REC | 01 | gruppo | - | - | - | - | - | 0 | 110 | - | - | - |
| ARR-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| ARR-ACCT-BAL | 05 | gruppo | - | - | - | - | - | 11 | 19 | - | - | 1 |
| ARR-ACCT-CURR-BAL | 10 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 11 | 12 | - | - | 1 |
| ARR-ACCT-CURR-CYC-DEBIT | 10 | elementare | S9(10)V99 | COMP-3 | S | 10 | 2 | 23 | 7 | - | - | 1 |
| ARR-ACCT-BAL | 05 | gruppo | - | - | - | - | - | 30 | 19 | - | - | 2 |
| ARR-ACCT-CURR-BAL | 10 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 30 | 12 | - | - | 2 |
| ARR-ACCT-CURR-CYC-DEBIT | 10 | elementare | S9(10)V99 | COMP-3 | S | 10 | 2 | 42 | 7 | - | - | 2 |
| ARR-ACCT-BAL | 05 | gruppo | - | - | - | - | - | 49 | 19 | - | - | 3 |
| ARR-ACCT-CURR-BAL | 10 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 49 | 12 | - | - | 3 |
| ARR-ACCT-CURR-CYC-DEBIT | 10 | elementare | S9(10)V99 | COMP-3 | S | 10 | 2 | 61 | 7 | - | - | 3 |
| ARR-ACCT-BAL | 05 | gruppo | - | - | - | - | - | 68 | 19 | - | - | 4 |
| ARR-ACCT-CURR-BAL | 10 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 68 | 12 | - | - | 4 |
| ARR-ACCT-CURR-CYC-DEBIT | 10 | elementare | S9(10)V99 | COMP-3 | S | 10 | 2 | 80 | 7 | - | - | 4 |
| ARR-ACCT-BAL | 05 | gruppo | - | - | - | - | - | 87 | 19 | - | - | 5 |
| ARR-ACCT-CURR-BAL | 10 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 87 | 12 | - | - | 5 |
| ARR-ACCT-CURR-CYC-DEBIT | 10 | elementare | S9(10)V99 | COMP-3 | S | 10 | 2 | 99 | 7 | - | - | 5 |
| ARR-FILLER | 05 | elementare | X(04) | DISPLAY | - | - | - | 106 | 4 | - | - | - |

## `CBACT01C.VBR-REC`

Radice `VBR-REC` di `app/cbl/CBACT01C.cbl` (85-85), 80 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| VBR-REC | 01 | elementare | X(80) | DISPLAY | - | - | - | 0 | 80 | - | - | - |

## `CBACT01C.VBRC-REC1`

Radice `VBRC-REC1` di `app/cbl/CBACT01C.cbl` (123-125), 12 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| VBRC-REC1 | 01 | gruppo | - | - | - | - | - | 0 | 12 | - | - | - |
| VB1-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| VB1-ACCT-ACTIVE-STATUS | 05 | elementare | X(01) | DISPLAY | - | - | - | 11 | 1 | - | - | - |

## `CBACT01C.VBRC-REC2`

Radice `VBRC-REC2` di `app/cbl/CBACT01C.cbl` (126-130), 39 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| VBRC-REC2 | 01 | gruppo | - | - | - | - | - | 0 | 39 | - | - | - |
| VB2-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| VB2-ACCT-CURR-BAL | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 11 | 12 | - | - | - |
| VB2-ACCT-CREDIT-LIMIT | 05 | elementare | S9(10)V99 | DISPLAY | S | 10 | 2 | 23 | 12 | - | - | - |
| VB2-ACCT-REISSUE-YYYY | 05 | elementare | X(04) | DISPLAY | - | - | - | 35 | 4 | - | - | - |

## `CBACT02C.FD-CARDFILE-REC`

Radice `FD-CARDFILE-REC` di `app/cbl/CBACT02C.cbl` (38-40), 150 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-CARDFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 150 | - | - | - |
| FD-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-CARD-DATA | 05 | elementare | X(134) | DISPLAY | - | - | - | 16 | 134 | - | - | - |

## `CBACT03C.FD-XREFFILE-REC`

Radice `FD-XREFFILE-REC` di `app/cbl/CBACT03C.cbl` (38-40), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-XREFFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| FD-XREF-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-XREF-DATA | 05 | elementare | X(34) | DISPLAY | - | - | - | 16 | 34 | - | - | - |

## `CBCUS01C.FD-CUSTFILE-REC`

Radice `FD-CUSTFILE-REC` di `app/cbl/CBCUS01C.cbl` (38-40), 500 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-CUSTFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 500 | - | - | - |
| FD-CUST-ID | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 0 | 9 | - | - | - |
| FD-CUST-DATA | 05 | elementare | X(491) | DISPLAY | - | - | - | 9 | 491 | - | - | - |

## `CBACT04C.FD-TRAN-CAT-BAL-RECORD`

Radice `FD-TRAN-CAT-BAL-RECORD` di `app/cbl/CBACT04C.cbl` (62-67), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRAN-CAT-BAL-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| FD-TRAN-CAT-KEY | 05 | gruppo | - | - | - | - | - | 0 | 17 | - | - | - |
| FD-TRANCAT-ACCT-ID | 10 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| FD-TRANCAT-TYPE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 11 | 2 | - | - | - |
| FD-TRANCAT-CD | 10 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 13 | 4 | - | - | - |
| FD-FD-TRAN-CAT-DATA | 05 | elementare | X(33) | DISPLAY | - | - | - | 17 | 33 | - | - | - |

## `CBACT04C.FD-XREFFILE-REC`

Radice `FD-XREFFILE-REC` di `app/cbl/CBACT04C.cbl` (70-74), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-XREFFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| FD-XREF-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-XREF-CUST-NUM | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 16 | 9 | - | - | - |
| FD-XREF-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 25 | 11 | - | - | - |
| FD-XREF-FILLER | 05 | elementare | X(14) | DISPLAY | - | - | - | 36 | 14 | - | - | - |

## `CBACT04C.FD-DISCGRP-REC`

Radice `FD-DISCGRP-REC` di `app/cbl/CBACT04C.cbl` (77-82), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-DISCGRP-REC | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| FD-DISCGRP-KEY | 05 | gruppo | - | - | - | - | - | 0 | 16 | - | - | - |
| FD-DIS-ACCT-GROUP-ID | 10 | elementare | X(10) | DISPLAY | - | - | - | 0 | 10 | - | - | - |
| FD-DIS-TRAN-TYPE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 10 | 2 | - | - | - |
| FD-DIS-TRAN-CAT-CD | 10 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 12 | 4 | - | - | - |
| FD-DISCGRP-DATA | 05 | elementare | X(34) | DISPLAY | - | - | - | 16 | 34 | - | - | - |

## `CBACT04C.FD-ACCTFILE-REC`

Radice `FD-ACCTFILE-REC` di `app/cbl/CBACT04C.cbl` (85-87), 300 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-ACCTFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 300 | - | - | - |
| FD-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| FD-ACCT-DATA | 05 | elementare | X(289) | DISPLAY | - | - | - | 11 | 289 | - | - | - |

## `CBACT04C.FD-TRANFILE-REC`

Radice `FD-TRANFILE-REC` di `app/cbl/CBACT04C.cbl` (90-92), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRANFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| FD-TRANS-ID | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-ACCT-DATA | 05 | elementare | X(334) | DISPLAY | - | - | - | 16 | 334 | - | - | - |

## `CBTRN01C.FD-TRAN-RECORD`

Radice `FD-TRAN-RECORD` di `app/cbl/CBTRN01C.cbl` (67-69), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRAN-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| FD-TRAN-ID | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-CUST-DATA | 05 | elementare | X(334) | DISPLAY | - | - | - | 16 | 334 | - | - | - |

## `CBTRN01C.FD-CUSTFILE-REC`

Radice `FD-CUSTFILE-REC` di `app/cbl/CBTRN01C.cbl` (72-74), 500 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-CUSTFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 500 | - | - | - |
| FD-CUST-ID | 05 | elementare | 9(09) | DISPLAY | - | 9 | 0 | 0 | 9 | - | - | - |
| FD-CUST-DATA | 05 | elementare | X(491) | DISPLAY | - | - | - | 9 | 491 | - | - | - |

## `CBTRN01C.FD-XREFFILE-REC`

Radice `FD-XREFFILE-REC` di `app/cbl/CBTRN01C.cbl` (77-79), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-XREFFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| FD-XREF-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-XREF-DATA | 05 | elementare | X(34) | DISPLAY | - | - | - | 16 | 34 | - | - | - |

## `CBTRN01C.FD-CARDFILE-REC`

Radice `FD-CARDFILE-REC` di `app/cbl/CBTRN01C.cbl` (82-84), 150 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-CARDFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 150 | - | - | - |
| FD-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-CARD-DATA | 05 | elementare | X(134) | DISPLAY | - | - | - | 16 | 134 | - | - | - |

## `CBTRN01C.FD-ACCTFILE-REC`

Radice `FD-ACCTFILE-REC` di `app/cbl/CBTRN01C.cbl` (87-89), 300 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-ACCTFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 300 | - | - | - |
| FD-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| FD-ACCT-DATA | 05 | elementare | X(289) | DISPLAY | - | - | - | 11 | 289 | - | - | - |

## `CBTRN01C.FD-TRANFILE-REC`

Radice `FD-TRANFILE-REC` di `app/cbl/CBTRN01C.cbl` (92-94), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRANFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| FD-TRANS-ID | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-ACCT-DATA | 05 | elementare | X(334) | DISPLAY | - | - | - | 16 | 334 | - | - | - |

## `CBTRN02C.FD-TRAN-RECORD`

Radice `FD-TRAN-RECORD` di `app/cbl/CBTRN02C.cbl` (67-69), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRAN-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| FD-TRAN-ID | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-CUST-DATA | 05 | elementare | X(334) | DISPLAY | - | - | - | 16 | 334 | - | - | - |

## `CBTRN02C.FD-TRANFILE-REC`

Radice `FD-TRANFILE-REC` di `app/cbl/CBTRN02C.cbl` (72-74), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRANFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| FD-TRANS-ID | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-ACCT-DATA | 05 | elementare | X(334) | DISPLAY | - | - | - | 16 | 334 | - | - | - |

## `CBTRN02C.FD-XREFFILE-REC`

Radice `FD-XREFFILE-REC` di `app/cbl/CBTRN02C.cbl` (77-79), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-XREFFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| FD-XREF-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-XREF-DATA | 05 | elementare | X(34) | DISPLAY | - | - | - | 16 | 34 | - | - | - |

## `CBTRN02C.FD-REJS-RECORD`

Radice `FD-REJS-RECORD` di `app/cbl/CBTRN02C.cbl` (82-84), 430 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-REJS-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 430 | - | - | - |
| FD-REJECT-RECORD | 05 | elementare | X(350) | DISPLAY | - | - | - | 0 | 350 | - | - | - |
| FD-VALIDATION-TRAILER | 05 | elementare | X(80) | DISPLAY | - | - | - | 350 | 80 | - | - | - |

## `CBTRN02C.FD-ACCTFILE-REC`

Radice `FD-ACCTFILE-REC` di `app/cbl/CBTRN02C.cbl` (87-89), 300 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-ACCTFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 300 | - | - | - |
| FD-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| FD-ACCT-DATA | 05 | elementare | X(289) | DISPLAY | - | - | - | 11 | 289 | - | - | - |

## `CBTRN02C.FD-TRAN-CAT-BAL-RECORD`

Radice `FD-TRAN-CAT-BAL-RECORD` di `app/cbl/CBTRN02C.cbl` (92-97), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRAN-CAT-BAL-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| FD-TRAN-CAT-KEY | 05 | gruppo | - | - | - | - | - | 0 | 17 | - | - | - |
| FD-TRANCAT-ACCT-ID | 10 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| FD-TRANCAT-TYPE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 11 | 2 | - | - | - |
| FD-TRANCAT-CD | 10 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 13 | 4 | - | - | - |
| FD-FD-TRAN-CAT-DATA | 05 | elementare | X(33) | DISPLAY | - | - | - | 17 | 33 | - | - | - |

## `CBACT04C.DB2-FORMAT-TS`

Radice `DB2-FORMAT-TS` di `app/cbl/CBACT04C.cbl` (150-150), 26 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DB2-FORMAT-TS | 01 | elementare | X(26) | DISPLAY | - | - | - | 0 | 26 | - | - | - |

## `CBTRN02C.DB2-FORMAT-TS`

Radice `DB2-FORMAT-TS` di `app/cbl/CBTRN02C.cbl` (159-159), 26 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DB2-FORMAT-TS | 01 | elementare | X(26) | DISPLAY | - | - | - | 0 | 26 | - | - | - |

## `CBTRN02C.REJECT-RECORD`

Radice `REJECT-RECORD` di `app/cbl/CBTRN02C.cbl` (176-178), 430 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| REJECT-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 430 | - | - | - |
| REJECT-TRAN-DATA | 05 | elementare | X(350) | DISPLAY | - | - | - | 0 | 350 | - | - | - |
| VALIDATION-TRAILER | 05 | elementare | X(80) | DISPLAY | - | - | - | 350 | 80 | - | - | - |

## `CBTRN02C.WS-VALIDATION-TRAILER`

Radice `WS-VALIDATION-TRAILER` di `app/cbl/CBTRN02C.cbl` (180-182), 80 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WS-VALIDATION-TRAILER | 01 | gruppo | - | - | - | - | - | 0 | 80 | - | - | - |
| WS-VALIDATION-FAIL-REASON | 05 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 0 | 4 | - | - | - |
| WS-VALIDATION-FAIL-REASON-DESC | 05 | elementare | X(76) | DISPLAY | - | - | - | 4 | 76 | - | - | - |

## `CBTRN03C.FD-TRANFILE-REC`

Radice `FD-TRANFILE-REC` di `app/cbl/CBTRN03C.cbl` (62-65), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRANFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| FD-TRANS-DATA | 05 | elementare | X(304) | DISPLAY | - | - | - | 0 | 304 | - | - | - |
| FD-TRAN-PROC-TS | 05 | elementare | X(26) | DISPLAY | - | - | - | 304 | 26 | - | - | - |
| FD-FILLER | 05 | elementare | X(20) | DISPLAY | - | - | - | 330 | 20 | - | - | - |

## `CBTRN03C.FD-CARDXREF-REC`

Radice `FD-CARDXREF-REC` di `app/cbl/CBTRN03C.cbl` (68-70), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-CARDXREF-REC | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| FD-XREF-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-XREF-DATA | 05 | elementare | X(34) | DISPLAY | - | - | - | 16 | 34 | - | - | - |

## `CBTRN03C.FD-TRANTYPE-REC`

Radice `FD-TRANTYPE-REC` di `app/cbl/CBTRN03C.cbl` (73-75), 60 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRANTYPE-REC | 01 | gruppo | - | - | - | - | - | 0 | 60 | - | - | - |
| FD-TRAN-TYPE | 05 | elementare | X(02) | DISPLAY | - | - | - | 0 | 2 | - | - | - |
| FD-TRAN-DATA | 05 | elementare | X(58) | DISPLAY | - | - | - | 2 | 58 | - | - | - |

## `CBTRN03C.FD-TRAN-CAT-RECORD`

Radice `FD-TRAN-CAT-RECORD` di `app/cbl/CBTRN03C.cbl` (78-82), 60 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRAN-CAT-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 60 | - | - | - |
| FD-TRAN-CAT-KEY | 05 | gruppo | - | - | - | - | - | 0 | 6 | - | - | - |
| FD-TRAN-TYPE-CD | 10 | elementare | X(02) | DISPLAY | - | - | - | 0 | 2 | - | - | - |
| FD-TRAN-CAT-CD | 10 | elementare | 9(04) | DISPLAY | - | 4 | 0 | 2 | 4 | - | - | - |
| FD-TRAN-CAT-DATA | 05 | elementare | X(54) | DISPLAY | - | - | - | 6 | 54 | - | - | - |

## `CBTRN03C.FD-DATEPARM-REC`

Radice `FD-DATEPARM-REC` di `app/cbl/CBTRN03C.cbl` (88-88), 80 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-DATEPARM-REC | 01 | elementare | X(80) | DISPLAY | - | - | - | 0 | 80 | - | - | - |

## `CBTRN03C.WS-DATEPARM-RECORD`

Radice `WS-DATEPARM-RECORD` di `app/cbl/CBTRN03C.cbl` (122-125), 21 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WS-DATEPARM-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 21 | - | - | - |
| WS-START-DATE | 05 | elementare | X(10) | DISPLAY | - | - | - | 0 | 10 | - | - | - |
| FILLER | 05 | elementare | X(01) | DISPLAY | - | - | - | 10 | 1 | - | - | - |
| WS-END-DATE | 05 | elementare | X(10) | DISPLAY | - | - | - | 11 | 10 | - | - | - |

## `CBEXPORT.EXPORT-OUTPUT-RECORD`

Radice `EXPORT-OUTPUT-RECORD` di `app/cbl/CBEXPORT.cbl` (92-92), 500 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXPORT-OUTPUT-RECORD | 01 | elementare | X(500) | DISPLAY | - | - | - | 0 | 500 | - | - | - |

## `CBIMPORT.EXPORT-INPUT-RECORD`

Radice `EXPORT-INPUT-RECORD` di `app/cbl/CBIMPORT.cbl` (79-79), 500 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXPORT-INPUT-RECORD | 01 | elementare | X(500) | DISPLAY | - | - | - | 0 | 500 | - | - | - |

## `CBIMPORT.ERROR-OUTPUT-RECORD`

Radice `ERROR-OUTPUT-RECORD` di `app/cbl/CBIMPORT.cbl` (109-109), 132 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ERROR-OUTPUT-RECORD | 01 | elementare | X(132) | DISPLAY | - | - | - | 0 | 132 | - | - | - |

## `CBIMPORT.WS-ERROR-RECORD`

Radice `WS-ERROR-RECORD` di `app/cbl/CBIMPORT.cbl` (152-160), 130 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WS-ERROR-RECORD | 01 | gruppo | - | - | - | - | - | 0 | 130 | - | - | - |
| ERR-TIMESTAMP | 05 | elementare | X(26) | DISPLAY | - | - | - | 0 | 26 | - | - | - |
| FILLER | 05 | elementare | X(01) | DISPLAY | - | - | - | 26 | 1 | - | - | - |
| ERR-RECORD-TYPE | 05 | elementare | X(01) | DISPLAY | - | - | - | 27 | 1 | - | - | - |
| FILLER | 05 | elementare | X(01) | DISPLAY | - | - | - | 28 | 1 | - | - | - |
| ERR-SEQUENCE | 05 | elementare | 9(07) | DISPLAY | - | 7 | 0 | 29 | 7 | - | - | - |
| FILLER | 05 | elementare | X(01) | DISPLAY | - | - | - | 36 | 1 | - | - | - |
| ERR-MESSAGE | 05 | elementare | X(50) | DISPLAY | - | - | - | 37 | 50 | - | - | - |
| FILLER | 05 | elementare | X(43) | DISPLAY | - | - | - | 87 | 43 | - | - | - |

## `CBSTM03B.FD-TRNXFILE-REC`

Radice `FD-TRNXFILE-REC` di `app/cbl/CBSTM03B.CBL` (59-63), 350 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-TRNXFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 350 | - | - | - |
| FD-TRNXS-ID | 05 | gruppo | - | - | - | - | - | 0 | 32 | - | - | - |
| FD-TRNX-CARD | 10 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-TRNX-ID | 10 | elementare | X(16) | DISPLAY | - | - | - | 16 | 16 | - | - | - |
| FD-ACCT-DATA | 05 | elementare | X(318) | DISPLAY | - | - | - | 32 | 318 | - | - | - |

## `CBSTM03B.FD-XREFFILE-REC`

Radice `FD-XREFFILE-REC` di `app/cbl/CBSTM03B.CBL` (66-68), 50 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-XREFFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 50 | - | - | - |
| FD-XREF-CARD-NUM | 05 | elementare | X(16) | DISPLAY | - | - | - | 0 | 16 | - | - | - |
| FD-XREF-DATA | 05 | elementare | X(34) | DISPLAY | - | - | - | 16 | 34 | - | - | - |

## `CBSTM03B.FD-CUSTFILE-REC`

Radice `FD-CUSTFILE-REC` di `app/cbl/CBSTM03B.CBL` (71-73), 500 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-CUSTFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 500 | - | - | - |
| FD-CUST-ID | 05 | elementare | X(09) | DISPLAY | - | - | - | 0 | 9 | - | - | - |
| FD-CUST-DATA | 05 | elementare | X(491) | DISPLAY | - | - | - | 9 | 491 | - | - | - |

## `CBSTM03B.FD-ACCTFILE-REC`

Radice `FD-ACCTFILE-REC` di `app/cbl/CBSTM03B.CBL` (76-78), 300 byte.

| campo | liv. | tipo | PIC | USAGE | segno | int. | dec. | offset | byte | REDEFINES | area | indice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FD-ACCTFILE-REC | 01 | gruppo | - | - | - | - | - | 0 | 300 | - | - | - |
| FD-ACCT-ID | 05 | elementare | 9(11) | DISPLAY | - | 11 | 0 | 0 | 11 | - | - | - |
| FD-ACCT-DATA | 05 | elementare | X(289) | DISPLAY | - | - | - | 11 | 289 | - | - | - |
