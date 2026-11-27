      *****************************************************************
      * IDXDUMP - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Rilegge uno dei quattro file indicizzati di
      * CBSTM03B (TRNXFILE, XREFFILE, CUSTFILE, ACCTFILE, scelto con il
      * PARM) in ordine di chiave, con le stesse chiavi e lunghezze di
      * CBSTM03B (righe 31-53 e 58-78), e scrive ogni record, byte per
      * byte, nel file sequenziale a record fissi della DD USCITA (350,
      * 50, 500 o 300 byte, senza separatori). Il controllo confronta
      * quel file con i file di testo d'ingresso: e' la verifica del
      * caricamento fatto da IDXLOAD, indipendente da IDXLOAD.
      * Esito: 0 se la lettura arriva alla fine del file (stato 10)
      * senza errori, 8 altrimenti. Usato dal passo oracle/adattamenti/.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. IDXDUMP.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT TRNX-FILE ASSIGN TO TRNXFILE
                  ORGANIZATION IS INDEXED
                  ACCESS MODE  IS SEQUENTIAL
                  RECORD KEY   IS FD-TRNXS-ID
                  FILE STATUS  IS IDX-STATUS.
           SELECT XREF-FILE ASSIGN TO XREFFILE
                  ORGANIZATION IS INDEXED
                  ACCESS MODE  IS SEQUENTIAL
                  RECORD KEY   IS FD-XREF-CARD-NUM
                  FILE STATUS  IS IDX-STATUS.
           SELECT CUST-FILE ASSIGN TO CUSTFILE
                  ORGANIZATION IS INDEXED
                  ACCESS MODE  IS SEQUENTIAL
                  RECORD KEY   IS FD-CUST-ID
                  FILE STATUS  IS IDX-STATUS.
           SELECT ACCT-FILE ASSIGN TO ACCTFILE
                  ORGANIZATION IS INDEXED
                  ACCESS MODE  IS SEQUENTIAL
                  RECORD KEY   IS FD-ACCT-ID
                  FILE STATUS  IS IDX-STATUS.
      * Quattro descrizioni dello stesso file d'uscita (DD USCITA), una
      * per lunghezza di record: se ne apre una sola per esecuzione.
           SELECT U-TRNX ASSIGN TO USCITA
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS  IS USC-STATUS.
           SELECT U-XREF ASSIGN TO USCITA
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS  IS USC-STATUS.
           SELECT U-CUST ASSIGN TO USCITA
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS  IS USC-STATUS.
           SELECT U-ACCT ASSIGN TO USCITA
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS  IS USC-STATUS.
       DATA DIVISION.
       FILE SECTION.
       FD  TRNX-FILE.
       01  FD-TRNXFILE-REC.
           05 FD-TRNXS-ID.
              10  FD-TRNX-CARD                  PIC X(16).
              10  FD-TRNX-ID                    PIC X(16).
           05 FD-ACCT-DATA                      PIC X(318).
       FD  XREF-FILE.
       01  FD-XREFFILE-REC.
           05 FD-XREF-CARD-NUM                  PIC X(16).
           05 FD-XREF-DATA                      PIC X(34).
       FD  CUST-FILE.
       01  FD-CUSTFILE-REC.
           05 FD-CUST-ID                        PIC X(09).
           05 FD-CUST-DATA                      PIC X(491).
       FD  ACCT-FILE.
       01  FD-ACCTFILE-REC.
           05 FD-ACCT-ID                        PIC 9(11).
           05 FD-ACCT-DATA                      PIC X(289).
       FD  U-TRNX RECORDING MODE IS F.
       01  U-TRNX-REC              PIC X(350).
       FD  U-XREF RECORDING MODE IS F.
       01  U-XREF-REC              PIC X(50).
       FD  U-CUST RECORDING MODE IS F.
       01  U-CUST-REC              PIC X(500).
       FD  U-ACCT RECORDING MODE IS F.
       01  U-ACCT-REC              PIC X(300).
       WORKING-STORAGE SECTION.
       01  IDX-STATUS              PIC X(02).
       01  USC-STATUS              PIC X(02).
       01  WS-LETTI                PIC 9(06) VALUE 0.
       LINKAGE SECTION.
       01  EXTERNAL-PARMS.
           05  PARM-LENGTH         PIC S9(04) COMP.
           05  PARM-DD             PIC X(08).
       PROCEDURE DIVISION USING EXTERNAL-PARMS.
           EVALUATE PARM-DD
             WHEN 'TRNXFILE' OPEN INPUT TRNX-FILE
             WHEN 'XREFFILE' OPEN INPUT XREF-FILE
             WHEN 'CUSTFILE' OPEN INPUT CUST-FILE
             WHEN 'ACCTFILE' OPEN INPUT ACCT-FILE
             WHEN OTHER
                 DISPLAY 'IDXDUMP PARM SCONOSCIUTO: ' PARM-DD
                 MOVE 8 TO RETURN-CODE
                 GOBACK
           END-EVALUATE
           IF IDX-STATUS NOT = '00'
               DISPLAY 'IDXDUMP ' PARM-DD ' ERRORE OPEN ' IDX-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           EVALUATE PARM-DD
             WHEN 'TRNXFILE' OPEN OUTPUT U-TRNX
             WHEN 'XREFFILE' OPEN OUTPUT U-XREF
             WHEN 'CUSTFILE' OPEN OUTPUT U-CUST
             WHEN 'ACCTFILE' OPEN OUTPUT U-ACCT
           END-EVALUATE
           IF USC-STATUS NOT = '00'
               DISPLAY 'IDXDUMP USCITA ERRORE OPEN ' USC-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           PERFORM 1000-LEGGI
           PERFORM UNTIL IDX-STATUS NOT = '00'
               PERFORM 2000-SCRIVI
               PERFORM 1000-LEGGI
           END-PERFORM
           IF IDX-STATUS NOT = '10'
               DISPLAY 'IDXDUMP ' PARM-DD ' ERRORE READ ' IDX-STATUS
                       ' DOPO IL RECORD ' WS-LETTI
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           EVALUATE PARM-DD
             WHEN 'TRNXFILE' CLOSE TRNX-FILE U-TRNX
             WHEN 'XREFFILE' CLOSE XREF-FILE U-XREF
             WHEN 'CUSTFILE' CLOSE CUST-FILE U-CUST
             WHEN 'ACCTFILE' CLOSE ACCT-FILE U-ACCT
           END-EVALUATE
           IF IDX-STATUS NOT = '00' OR USC-STATUS NOT = '00'
               DISPLAY 'IDXDUMP ' PARM-DD ' ERRORE CLOSE ' IDX-STATUS
                       ' ' USC-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           DISPLAY 'IDXDUMP ' PARM-DD ' RECORD LETTI ' WS-LETTI
           MOVE 0 TO RETURN-CODE
           GOBACK.

       1000-LEGGI.
           EVALUATE PARM-DD
             WHEN 'TRNXFILE' READ TRNX-FILE
             WHEN 'XREFFILE' READ XREF-FILE
             WHEN 'CUSTFILE' READ CUST-FILE
             WHEN 'ACCTFILE' READ ACCT-FILE
           END-EVALUATE.

       2000-SCRIVI.
           ADD 1 TO WS-LETTI
           EVALUATE PARM-DD
             WHEN 'TRNXFILE' WRITE U-TRNX-REC FROM FD-TRNXFILE-REC
             WHEN 'XREFFILE' WRITE U-XREF-REC FROM FD-XREFFILE-REC
             WHEN 'CUSTFILE' WRITE U-CUST-REC FROM FD-CUSTFILE-REC
             WHEN 'ACCTFILE' WRITE U-ACCT-REC FROM FD-ACCTFILE-REC
           END-EVALUATE
           IF USC-STATUS NOT = '00'
               DISPLAY 'IDXDUMP USCITA ERRORE WRITE ' USC-STATUS
               MOVE 8 TO RETURN-CODE
               STOP RUN
           END-IF.
