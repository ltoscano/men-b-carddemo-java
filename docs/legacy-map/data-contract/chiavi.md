# Chiavi dei file a confronto tra le fonti (vista generata)

Generato da `./analysis/run.sh data-contract`. Fonti: `DEFINE` nei JCL (`KEYS(lunghezza offset)`, offset a base 0), `LISTCAT.txt` (`KEYLEN`, `RKP` o `AXRKP`), `SELECT` dei programmi con la posizione della chiave nel record dell'FD, e i campi del tracciato del dataset (`file.tsv`) che occupano gli stessi byte. Le differenze sono in `discordanze.md`.

## -

Tracciato: `-`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | FD-CUST-ID | SELECT+FD CBTRN01C | app/cbl/CBTRN01C.cbl:34 | 0 | 9 | UNIQUE | - | - | - |
| primaria | FD-XREF-CARD-NUM | SELECT+FD CBTRN01C | app/cbl/CBTRN01C.cbl:40 | 0 | 16 | UNIQUE | - | - | - |
| primaria | FD-CARD-NUM | SELECT+FD CBTRN01C | app/cbl/CBTRN01C.cbl:46 | 0 | 16 | UNIQUE | - | - | - |
| primaria | FD-ACCT-ID | SELECT+FD CBTRN01C | app/cbl/CBTRN01C.cbl:52 | 0 | 11 | UNIQUE | - | - | - |
| primaria | FD-TRANS-ID | SELECT+FD CBTRN01C | app/cbl/CBTRN01C.cbl:58 | 0 | 16 | UNIQUE | - | - | - |

## AWS.CUSTDATA.CLUSTER

Tracciato: `CVCUS01Y.CUSTOMER-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/DEFCUST.jcl:35 | 0 | 10 | UNIQUE | CUST-ID+CUST-FIRST-NAME[0..0] | - | parziale |

## AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS

Tracciato: `CVACT01Y.ACCOUNT-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/ACCTFILE.jcl:36 | 0 | 11 | UNIQUE | ACCT-ID | - | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:47 | 0 | 11 | UNIQUE | ACCT-ID | - | esatta |
| primaria | FD-ACCT-ID | SELECT+FD CBACT01C | app/cbl/CBACT01C.cbl:29 | 0 | 11 | UNIQUE | ACCT-ID | - | esatta |
| primaria | FD-ACCT-ID | SELECT+FD CBACT04C | app/cbl/CBACT04C.cbl:41 | 0 | 11 | UNIQUE | ACCT-ID | - | esatta |
| primaria | ACCT-ID | SELECT+FD CBEXPORT | app/cbl/CBEXPORT.cbl:41 | 0 | 11 | UNIQUE | ACCT-ID | - | esatta |
| primaria | FD-ACCT-ID | SELECT+FD CBSTM03B | app/cbl/CBSTM03B.CBL:49 | 0 | 11 | UNIQUE | ACCT-ID | - | esatta |
| primaria | FD-ACCT-ID | SELECT+FD CBTRN02C | app/cbl/CBTRN02C.cbl:51 | 0 | 11 | UNIQUE | ACCT-ID | - | esatta |

## AWS.M2.CARDDEMO.CARDDATA.VSAM.KSDS

Tracciato: `CVACT02Y.CARD-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/CARDFILE.jcl:50 | 0 | 16 | UNIQUE | CARD-NUM | - | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:190 | 0 | 16 | UNIQUE | CARD-NUM | - | esatta |
| alternativa | AWS.M2.CARDDEMO.CARDDATA.VSAM.AIX | JCL DEFINE AIX | app/jcl/CARDFILE.jcl:83 | 16 | 11 | NONUNIQUEKEY | CARD-ACCT-ID | - | esatta |
| alternativa | AWS.M2.CARDDEMO.CARDDATA.VSAM.AIX | LISTCAT | app/catlg/LISTCAT.txt:271 | 16 | 11 | NONUNIQKEY | CARD-ACCT-ID | - | esatta |
| primaria | FD-CARD-NUM | SELECT+FD CBACT02C | app/cbl/CBACT02C.cbl:29 | 0 | 16 | UNIQUE | CARD-NUM | - | esatta |
| primaria | CARD-NUM | SELECT+FD CBEXPORT | app/cbl/CBEXPORT.cbl:59 | 0 | 16 | UNIQUE | CARD-NUM | - | esatta |

## AWS.M2.CARDDEMO.CARDXREF.VSAM.KSDS

Tracciato: `CVACT03Y.CARD-XREF-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/XREFFILE.jcl:39 | 0 | 16 | UNIQUE | XREF-CARD-NUM | - | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:393 | 0 | 16 | UNIQUE | XREF-CARD-NUM | - | esatta |
| alternativa | AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX | JCL DEFINE AIX | app/jcl/XREFFILE.jcl:72 | 25 | 11 | NONUNIQUEKEY | XREF-ACCT-ID | - | esatta |
| alternativa | AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX | LISTCAT | app/catlg/LISTCAT.txt:472 | 25 | 11 | NONUNIQKEY | XREF-ACCT-ID | - | esatta |
| primaria | FD-XREF-CARD-NUM | SELECT+FD CBACT03C | app/cbl/CBACT03C.cbl:29 | 0 | 16 | UNIQUE | XREF-CARD-NUM | - | esatta |
| primaria | FD-XREF-CARD-NUM | SELECT+FD CBACT04C | app/cbl/CBACT04C.cbl:34 | 0 | 16 | UNIQUE | XREF-CARD-NUM | - | esatta |
| alternativa | FD-XREF-ACCT-ID | SELECT+FD CBACT04C | app/cbl/CBACT04C.cbl:34 | 25 | 11 | senza WITH DUPLICATES | XREF-ACCT-ID | - | esatta |
| primaria | XREF-CARD-NUM | SELECT+FD CBEXPORT | app/cbl/CBEXPORT.cbl:47 | 0 | 16 | UNIQUE | XREF-CARD-NUM | - | esatta |
| primaria | FD-XREF-CARD-NUM | SELECT+FD CBSTM03B | app/cbl/CBSTM03B.CBL:37 | 0 | 16 | UNIQUE | XREF-CARD-NUM | - | esatta |
| primaria | FD-XREF-CARD-NUM | SELECT+FD CBTRN02C | app/cbl/CBTRN02C.cbl:40 | 0 | 16 | UNIQUE | XREF-CARD-NUM | - | esatta |
| primaria | FD-XREF-CARD-NUM | SELECT+FD CBTRN03C | app/cbl/CBTRN03C.cbl:33 | 0 | 16 | UNIQUE | XREF-CARD-NUM | - | esatta |

## AWS.M2.CARDDEMO.CUSTDATA.VSAM.KSDS

Tracciato: `CVCUS01Y.CUSTOMER-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/CUSTFILE.jcl:46 | 0 | 9 | UNIQUE | CUST-ID | - | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:620 | 0 | 9 | UNIQUE | CUST-ID | - | esatta |
| primaria | FD-CUST-ID | SELECT+FD CBCUS01C | app/cbl/CBCUS01C.cbl:29 | 0 | 9 | UNIQUE | CUST-ID | - | esatta |
| primaria | CUST-ID | SELECT+FD CBEXPORT | app/cbl/CBEXPORT.cbl:35 | 0 | 9 | UNIQUE | CUST-ID | - | esatta |
| primaria | FD-CUST-ID | SELECT+FD CBSTM03B | app/cbl/CBSTM03B.CBL:43 | 0 | 9 | UNIQUE | CUST-ID | - | esatta |

## AWS.M2.CARDDEMO.DISCGRP.VSAM.KSDS

Tracciato: `CVTRA02Y.DIS-GROUP-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/DISCGRP.jcl:36 | 0 | 16 | UNIQUE | DIS-ACCT-GROUP-ID+DIS-TRAN-TYPE-CD+DIS-TRAN-CAT-CD | DIS-GROUP-KEY | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:886 | 0 | 16 | UNIQUE | DIS-ACCT-GROUP-ID+DIS-TRAN-TYPE-CD+DIS-TRAN-CAT-CD | DIS-GROUP-KEY | esatta |
| primaria | FD-DISCGRP-KEY | SELECT+FD CBACT04C | app/cbl/CBACT04C.cbl:47 | 0 | 16 | UNIQUE | DIS-ACCT-GROUP-ID+DIS-TRAN-TYPE-CD+DIS-TRAN-CAT-CD | DIS-GROUP-KEY | esatta |

## AWS.M2.CARDDEMO.EXPORT.DATA

Tracciato: `CVEXPORT.EXPORT-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/CBEXPORT.jcl:30 | 28 | 4 | UNIQUE | EXPORT-SEQUENCE-NUM[1..3]+EXPORT-BRANCH-ID[0..0] | - | parziale |
| primaria | EXPORT-SEQUENCE-NUM | SELECT+FD CBEXPORT (campo fuori dal record dell'FD) | app/cbl/CBEXPORT.cbl:65 | 27 | 4 | UNIQUE | EXPORT-SEQUENCE-NUM | - | esatta |
| primaria | EXPORT-SEQUENCE-NUM | SELECT+FD CBIMPORT (campo fuori dal record dell'FD) | app/cbl/CBIMPORT.cbl:37 | 27 | 4 | UNIQUE | EXPORT-SEQUENCE-NUM | - | esatta |

## AWS.M2.CARDDEMO.TCATBALF.VSAM.KSDS

Tracciato: `CVTRA01Y.TRAN-CAT-BAL-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/TCATBALF.jcl:36 | 0 | 17 | UNIQUE | TRANCAT-ACCT-ID+TRANCAT-TYPE-CD+TRANCAT-CD | TRAN-CAT-KEY | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:1361 | 0 | 17 | UNIQUE | TRANCAT-ACCT-ID+TRANCAT-TYPE-CD+TRANCAT-CD | TRAN-CAT-KEY | esatta |
| primaria | FD-TRAN-CAT-KEY | SELECT+FD CBACT04C | app/cbl/CBACT04C.cbl:28 | 0 | 17 | UNIQUE | TRANCAT-ACCT-ID+TRANCAT-TYPE-CD+TRANCAT-CD | TRAN-CAT-KEY | esatta |
| primaria | FD-TRAN-CAT-KEY | SELECT+FD CBTRN02C | app/cbl/CBTRN02C.cbl:57 | 0 | 17 | UNIQUE | TRANCAT-ACCT-ID+TRANCAT-TYPE-CD+TRANCAT-CD | TRAN-CAT-KEY | esatta |

## AWS.M2.CARDDEMO.TRANCATG.VSAM.KSDS

Tracciato: `CVTRA04Y.TRAN-CAT-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/TRANCATG.jcl:36 | 0 | 6 | UNIQUE | TRAN-TYPE-CD+TRAN-CAT-CD | TRAN-CAT-KEY | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:1465 | 0 | 6 | UNIQUE | TRAN-TYPE-CD+TRAN-CAT-CD | TRAN-CAT-KEY | esatta |
| primaria | FD-TRAN-CAT-KEY | SELECT+FD CBTRN03C | app/cbl/CBTRN03C.cbl:45 | 0 | 6 | UNIQUE | TRAN-TYPE-CD+TRAN-CAT-CD | TRAN-CAT-KEY | esatta |

## AWS.M2.CARDDEMO.TRANSACT.VSAM.KSDS

Tracciato: `CVTRA05Y.TRAN-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/TRANBKP.jcl:54 | 0 | 16 | UNIQUE | TRAN-ID | - | esatta |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/TRANFILE.jcl:49 | 0 | 16 | UNIQUE | TRAN-ID | - | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:3583 | 0 | 16 | UNIQUE | TRAN-ID | - | esatta |
| alternativa | AWS.M2.CARDDEMO.TRANSACT.VSAM.AIX | JCL DEFINE AIX | app/jcl/TRANFILE.jcl:82 | 304 | 26 | NONUNIQUEKEY | TRAN-PROC-TS | - | esatta |
| alternativa | AWS.M2.CARDDEMO.TRANSACT.VSAM.AIX | LISTCAT | app/catlg/LISTCAT.txt:3664 | 304 | 26 | NONUNIQKEY | TRAN-PROC-TS | - | esatta |
| alternativa | AWS.M2.CARDDEMO.TRANSACT.VSAM.AIX | JCL DEFINE AIX | app/jcl/TRANIDX.jcl:25 | 304 | 26 | NONUNIQUEKEY | TRAN-PROC-TS | - | esatta |
| primaria | TRAN-ID | SELECT+FD CBEXPORT | app/cbl/CBEXPORT.cbl:53 | 0 | 16 | UNIQUE | TRAN-ID | - | esatta |
| primaria | FD-TRANS-ID | SELECT+FD CBTRN02C | app/cbl/CBTRN02C.cbl:34 | 0 | 16 | UNIQUE | TRAN-ID | - | esatta |

## AWS.M2.CARDDEMO.TRANTYPE.VSAM.KSDS

Tracciato: `CVTRA03Y.TRAN-TYPE-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/TRANTYPE.jcl:36 | 0 | 2 | UNIQUE | TRAN-TYPE | - | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:3769 | 0 | 2 | UNIQUE | TRAN-TYPE | - | esatta |
| primaria | FD-TRAN-TYPE | SELECT+FD CBTRN03C | app/cbl/CBTRN03C.cbl:39 | 0 | 2 | UNIQUE | TRAN-TYPE | - | esatta |

## AWS.M2.CARDDEMO.TRXFL.VSAM.KSDS

Tracciato: `COSTM01.TRNX-RECORD`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/CREASTMT.JCL:29 | 0 | 32 | UNIQUE | TRNX-CARD-NUM+TRNX-ID | TRNX-KEY | esatta |
| primaria | FD-TRNXS-ID | SELECT+FD CBSTM03B | app/cbl/CBSTM03B.CBL:31 | 0 | 32 | UNIQUE | TRNX-CARD-NUM+TRNX-ID | TRNX-KEY | esatta |

## AWS.M2.CARDDEMO.USRSEC.VSAM.KSDS

Tracciato: `CSUSR01Y.SEC-USER-DATA`.

| chiave | nome | fonte | riferimento | offset | byte | unicita' | campi del tracciato | gruppo | copertura |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primaria | - | JCL DEFINE CLUSTER | app/jcl/DUSRSECJ.jcl:64 | 0 | 8 | UNIQUE | SEC-USR-ID | - | esatta |
| primaria | - | LISTCAT | app/catlg/LISTCAT.txt:3873 | 0 | 8 | UNIQUE | SEC-USR-ID | - | esatta |

## Discordanze e osservazioni rilevate automaticamente

| id | categoria | descrizione | riferimenti |
| --- | --- | --- | --- |
| `chiave-allineamento:AWS.CUSTDATA.CLUSTER:app/jcl/DEFCUST.jcl:35` | discordanza | AWS.CUSTDATA.CLUSTER: KEYS(10 0) copre i byte 0..9, che nel tracciato CVCUS01Y.CUSTOMER-RECORD non coincidono con campi interi: CUST-ID+CUST-FIRST-NAME[0..0] | app/jcl/DEFCUST.jcl:35 |
| `chiave-allineamento:AWS.M2.CARDDEMO.EXPORT.DATA:app/jcl/CBEXPORT.jcl:30` | discordanza | AWS.M2.CARDDEMO.EXPORT.DATA: KEYS(4 28) copre i byte 28..31, che nel tracciato CVEXPORT.EXPORT-RECORD non coincidono con campi interi: EXPORT-SEQUENCE-NUM[1..3]+EXPORT-BRANCH-ID[0..0] | app/jcl/CBEXPORT.jcl:30 |
| `chiave-fuori-dal-record:CBEXPORT.EXPORT-OUTPUT` | discordanza | CBEXPORT: la primaria EXPORT-SEQUENCE-NUM del file EXPORT-OUTPUT non e' un campo del record dell'FD (CBEXPORT.EXPORT-OUTPUT-RECORD); nel tracciato del dataset (CVEXPORT.EXPORT-RECORD) e' a offset 27, lunghezza 4 | app/cbl/CBEXPORT.cbl:65 |
| `chiave-fuori-dal-record:CBIMPORT.EXPORT-INPUT` | discordanza | CBIMPORT: la primaria EXPORT-SEQUENCE-NUM del file EXPORT-INPUT non e' un campo del record dell'FD (CBIMPORT.EXPORT-INPUT-RECORD); nel tracciato del dataset (CVEXPORT.EXPORT-RECORD) e' a offset 27, lunghezza 4 | app/cbl/CBIMPORT.cbl:37 |
| `chiave-posizione:AWS.M2.CARDDEMO.EXPORT.DATA:primaria:CBEXPORT:EXPORT-SEQUENCE-NUM` | discordanza | AWS.M2.CARDDEMO.EXPORT.DATA: chiave primaria secondo SELECT+FD CBEXPORT (campo fuori dal record dell'FD) (EXPORT-SEQUENCE-NUM) a offset 27 lunghezza 4, secondo JCL DEFINE CLUSTER a offset 28 lunghezza 4 | app/cbl/CBEXPORT.cbl:65 ; app/jcl/CBEXPORT.jcl:30 |
| `chiave-posizione:AWS.M2.CARDDEMO.EXPORT.DATA:primaria:CBIMPORT:EXPORT-SEQUENCE-NUM` | discordanza | AWS.M2.CARDDEMO.EXPORT.DATA: chiave primaria secondo SELECT+FD CBIMPORT (campo fuori dal record dell'FD) (EXPORT-SEQUENCE-NUM) a offset 27 lunghezza 4, secondo JCL DEFINE CLUSTER a offset 28 lunghezza 4 | app/cbl/CBIMPORT.cbl:37 ; app/jcl/CBEXPORT.jcl:30 |
| `chiave-tipo:AWS.M2.CARDDEMO.CUSTDATA.VSAM.KSDS:CBSTM03B:FD-CUST-ID` | discordanza | AWS.M2.CARDDEMO.CUSTDATA.VSAM.KSDS: la chiave FD-CUST-ID e' PIC X(09) nel record dell'FD, il campo CUST-ID del tracciato e' PIC 9(09) | app/cbl/CBSTM03B.CBL:43 |
| `chiave-unicita:AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX:CBACT04C` | discordanza | AWS.M2.CARDDEMO.CARDXREF.VSAM.KSDS: indice alternativo AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX definito NONUNIQUEKEY nel JCL, mentre la ALTERNATE RECORD KEY FD-XREF-ACCT-ID e' dichiarata senza WITH DUPLICATES | app/jcl/XREFFILE.jcl:72 ; app/cbl/CBACT04C.cbl:34 |
| `dd-assente:CBIMPORT.CARD-OUTPUT` | discordanza | CBIMPORT: il file CARD-OUTPUT e' assegnato a CARDOUT, ma il passo di app/jcl/CBIMPORT.jcl non ha una DD CARDOUT | app/jcl/CBIMPORT.jcl |
| `lrecl:CBACT01C.VBRC-FILE` | osservazione | CBACT01C: LRECL=84 RECFM=VB nel JCL, record dell'FD CBACT01C.VBR-REC di 80 byte (FD a lunghezza variabile 10-80) | app/jcl/READACCT.jcl:47 |
| `lunghezze-diverse:CBACT01C:CBACT01C.VBRC-REC1->CBACT01C.VBR-REC` | osservazione | CBACT01C MOVE (righe 289): CBACT01C.VBRC-REC1 di 12 byte, CBACT01C.VBR-REC di 80 byte | app/cbl/CBACT01C.cbl:289 |
| `lunghezze-diverse:CBACT01C:CBACT01C.VBRC-REC2->CBACT01C.VBR-REC` | osservazione | CBACT01C MOVE (righe 304): CBACT01C.VBRC-REC2 di 39 byte, CBACT01C.VBR-REC di 80 byte | app/cbl/CBACT01C.cbl:304 |
| `lunghezze-diverse:CBIMPORT:CBIMPORT.WS-ERROR-RECORD->CBIMPORT.ERROR-OUTPUT-RECORD` | osservazione | CBIMPORT WRITE-FROM (righe 439): CBIMPORT.WS-ERROR-RECORD di 130 byte, CBIMPORT.ERROR-OUTPUT-RECORD di 132 byte | app/cbl/CBIMPORT.cbl:439 |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.HTML-LINES:HTML-L11->CBSTM03A.FD-HTMLFILE-REC` | osservazione | CBSTM03A WRITE-FROM (righe 530): CBSTM03A.HTML-LINES:HTML-L11 di 59 byte, CBSTM03A.FD-HTMLFILE-REC di 100 byte | app/cbl/CBSTM03A.CBL:530 |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT->COSTM01.TRNX-RECORD` | osservazione | CBSTM03A MOVE (righe 756,839): CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT di 1000 byte, COSTM01.TRNX-RECORD di 350 byte | app/cbl/CBSTM03A.CBL:756 |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT->CUSTREC.CUSTOMER-RECORD` | osservazione | CBSTM03A MOVE (righe 388): CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT di 1000 byte, CUSTREC.CUSTOMER-RECORD di 500 byte | app/cbl/CBSTM03A.CBL:388 |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT->CVACT01Y.ACCOUNT-RECORD` | osservazione | CBSTM03A MOVE (righe 412): CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT di 1000 byte, CVACT01Y.ACCOUNT-RECORD di 300 byte | app/cbl/CBSTM03A.CBL:412 |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT->CVACT03Y.CARD-XREF-RECORD` | osservazione | CBSTM03A MOVE (righe 364): CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT di 1000 byte, CVACT03Y.CARD-XREF-RECORD di 50 byte | app/cbl/CBSTM03A.CBL:364 |
| `lunghezze-diverse:CBSTM03B:CBSTM03B.FD-ACCTFILE-REC->CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT` | osservazione | CBSTM03B READ-INTO (righe 215): CBSTM03B.FD-ACCTFILE-REC di 300 byte, CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT di 1000 byte | app/cbl/CBSTM03B.CBL:215 |
| `lunghezze-diverse:CBSTM03B:CBSTM03B.FD-CUSTFILE-REC->CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT` | osservazione | CBSTM03B READ-INTO (righe 190): CBSTM03B.FD-CUSTFILE-REC di 500 byte, CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT di 1000 byte | app/cbl/CBSTM03B.CBL:190 |
| `lunghezze-diverse:CBSTM03B:CBSTM03B.FD-TRNXFILE-REC->CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT` | osservazione | CBSTM03B READ-INTO (righe 141): CBSTM03B.FD-TRNXFILE-REC di 350 byte, CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT di 1000 byte | app/cbl/CBSTM03B.CBL:141 |
| `lunghezze-diverse:CBSTM03B:CBSTM03B.FD-XREFFILE-REC->CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT` | osservazione | CBSTM03B READ-INTO (righe 165): CBSTM03B.FD-XREFFILE-REC di 50 byte, CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT di 1000 byte | app/cbl/CBSTM03B.CBL:165 |
| `lunghezze-diverse:CBTRN03C:CBTRN03C.FD-DATEPARM-REC->CBTRN03C.WS-DATEPARM-RECORD` | osservazione | CBTRN03C READ-INTO (righe 221): CBTRN03C.FD-DATEPARM-REC di 80 byte, CBTRN03C.WS-DATEPARM-RECORD di 21 byte | app/cbl/CBTRN03C.cbl:221 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.REPORT-ACCOUNT-TOTALS->CBTRN03C.FD-REPTFILE-REC` | osservazione | CBTRN03C MOVE (righe 308): CVTRA07Y.REPORT-ACCOUNT-TOTALS di 112 byte, CBTRN03C.FD-REPTFILE-REC di 133 byte | app/cbl/CBTRN03C.cbl:308 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.REPORT-GRAND-TOTALS->CBTRN03C.FD-REPTFILE-REC` | osservazione | CBTRN03C MOVE (righe 320): CVTRA07Y.REPORT-GRAND-TOTALS di 112 byte, CBTRN03C.FD-REPTFILE-REC di 133 byte | app/cbl/CBTRN03C.cbl:320 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.REPORT-NAME-HEADER->CBTRN03C.FD-REPTFILE-REC` | osservazione | CBTRN03C MOVE (righe 325): CVTRA07Y.REPORT-NAME-HEADER di 115 byte, CBTRN03C.FD-REPTFILE-REC di 133 byte | app/cbl/CBTRN03C.cbl:325 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.REPORT-PAGE-TOTALS->CBTRN03C.FD-REPTFILE-REC` | osservazione | CBTRN03C MOVE (righe 295): CVTRA07Y.REPORT-PAGE-TOTALS di 112 byte, CBTRN03C.FD-REPTFILE-REC di 133 byte | app/cbl/CBTRN03C.cbl:295 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.TRANSACTION-DETAIL-REPORT->CBTRN03C.FD-REPTFILE-REC` | osservazione | CBTRN03C MOVE (righe 371): CVTRA07Y.TRANSACTION-DETAIL-REPORT di 114 byte, CBTRN03C.FD-REPTFILE-REC di 133 byte | app/cbl/CBTRN03C.cbl:371 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.TRANSACTION-HEADER-1->CBTRN03C.FD-REPTFILE-REC` | osservazione | CBTRN03C MOVE (righe 333): CVTRA07Y.TRANSACTION-HEADER-1 di 114 byte, CBTRN03C.FD-REPTFILE-REC di 133 byte | app/cbl/CBTRN03C.cbl:333 |
| `nessun-jcl:CBTRN01C.ACCOUNT-FILE` | osservazione | CBTRN01C: nessun JCL di app/jcl/ esegue il programma; il file ACCOUNT-FILE (ASSIGN TO ACCTFILE) non e' ricondotto a un dataset | app/cbl/CBTRN01C.cbl |
| `nessun-jcl:CBTRN01C.CARD-FILE` | osservazione | CBTRN01C: nessun JCL di app/jcl/ esegue il programma; il file CARD-FILE (ASSIGN TO CARDFILE) non e' ricondotto a un dataset | app/cbl/CBTRN01C.cbl |
| `nessun-jcl:CBTRN01C.CUSTOMER-FILE` | osservazione | CBTRN01C: nessun JCL di app/jcl/ esegue il programma; il file CUSTOMER-FILE (ASSIGN TO CUSTFILE) non e' ricondotto a un dataset | app/cbl/CBTRN01C.cbl |
| `nessun-jcl:CBTRN01C.DALYTRAN-FILE` | osservazione | CBTRN01C: nessun JCL di app/jcl/ esegue il programma; il file DALYTRAN-FILE (ASSIGN TO DALYTRAN) non e' ricondotto a un dataset | app/cbl/CBTRN01C.cbl |
| `nessun-jcl:CBTRN01C.TRANSACT-FILE` | osservazione | CBTRN01C: nessun JCL di app/jcl/ esegue il programma; il file TRANSACT-FILE (ASSIGN TO TRANFILE) non e' ricondotto a un dataset | app/cbl/CBTRN01C.cbl |
| `nessun-jcl:CBTRN01C.XREF-FILE` | osservazione | CBTRN01C: nessun JCL di app/jcl/ esegue il programma; il file XREF-FILE (ASSIGN TO XREFFILE) non e' ricondotto a un dataset | app/cbl/CBTRN01C.cbl |
| `ridefinizione-estesa:COADM02Y:CDEMO-ADMIN-OPTIONS` | osservazione | app/cpy/COADM02Y.cpy: CDEMO-ADMIN-OPTIONS (405 byte) ridefinisce CDEMO-ADMIN-OPTIONS-DATA (270 byte); cb2xml da' alla radice CARDDEMO-ADMIN-MENU-OPTIONS 407 byte | app/cpy/COADM02Y.cpy |
| `ridefinizione-estesa:COMEN02Y:CDEMO-MENU-OPTIONS` | osservazione | app/cpy/COMEN02Y.cpy: CDEMO-MENU-OPTIONS (552 byte) ridefinisce CDEMO-MENU-OPTIONS-DATA (506 byte); cb2xml da' alla radice CARDDEMO-MAIN-MENU-OPTIONS 554 byte | app/cpy/COMEN02Y.cpy |
