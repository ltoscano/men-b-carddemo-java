      *****************************************************************
      * IDXLOAD - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Carica uno dei quattro file indicizzati letti da
      * CBSTM03B (app/cbl/CBSTM03B.CBL, righe 31-53 e 58-78) da un file
      * di testo con un record per riga (DD ENTRATA). Il file da
      * caricare si sceglie con il PARM: TRNXFILE, XREFFILE, CUSTFILE
      * o ACCTFILE. Chiavi e lunghezze dei record sono quelle di
      * CBSTM03B: 350 byte con chiave nei byte 1-32, 50 byte con
      * chiave 1-16, 500 byte con chiave 1-9, 300 byte con chiave 1-11
      * PIC 9(11).
      * Ogni riga diventa un record: i suoi byte all'inizio, spazi fino
      * alla lunghezza del record (riempimento del file a righe). Le
      * righe si scrivono nell'ordine del file con accesso sequenziale:
      * una chiave non crescente o doppia ferma il caricamento.
      * Esito: 0 se tutti i record sono scritti, 8 per ogni errore
      * (PARM sconosciuto, riga oltre la lunghezza del record, stato
      * di file diverso da 00). Usato dal passo oracle/adattamenti/.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. IDXLOAD.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ENTRATA ASSIGN TO ENTRATA
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS  IS ENT-STATUS.
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
       DATA DIVISION.
       FILE SECTION.
      * Riga d'ingresso: al massimo 500 byte (il record piu' lungo);
      * WS-ENT-LEN riceve la lunghezza effettiva della riga letta.
       FD  ENTRATA
           RECORD IS VARYING IN SIZE FROM 1 TO 501 CHARACTERS
           DEPENDING ON WS-ENT-LEN.
       01  ENT-REC                 PIC X(501).
      * Tracciati di CBSTM03B (righe 58-78), con gli stessi nomi.
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
       WORKING-STORAGE SECTION.
       01  ENT-STATUS              PIC X(02).
       01  IDX-STATUS              PIC X(02).
       01  WS-ENT-LEN              PIC 9(04) COMP.
       01  WS-REC-LEN              PIC 9(04) COMP.
       01  WS-RIGA                 PIC X(500).
       01  WS-SCRITTI              PIC 9(06) VALUE 0.
       01  WS-FINE                 PIC X(01) VALUE 'N'.
       01  WS-LEN-ED               PIC ZZZ9.
       LINKAGE SECTION.
       01  EXTERNAL-PARMS.
           05  PARM-LENGTH         PIC S9(04) COMP.
           05  PARM-DD             PIC X(08).
       PROCEDURE DIVISION USING EXTERNAL-PARMS.
           EVALUATE PARM-DD
             WHEN 'TRNXFILE' MOVE 350 TO WS-REC-LEN
                             OPEN OUTPUT TRNX-FILE
             WHEN 'XREFFILE' MOVE 50  TO WS-REC-LEN
                             OPEN OUTPUT XREF-FILE
             WHEN 'CUSTFILE' MOVE 500 TO WS-REC-LEN
                             OPEN OUTPUT CUST-FILE
             WHEN 'ACCTFILE' MOVE 300 TO WS-REC-LEN
                             OPEN OUTPUT ACCT-FILE
             WHEN OTHER
                 DISPLAY 'IDXLOAD PARM SCONOSCIUTO: ' PARM-DD
                 MOVE 8 TO RETURN-CODE
                 GOBACK
           END-EVALUATE
           IF IDX-STATUS NOT = '00'
               DISPLAY 'IDXLOAD ' PARM-DD ' ERRORE OPEN ' IDX-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           OPEN INPUT ENTRATA
           IF ENT-STATUS NOT = '00'
               DISPLAY 'IDXLOAD ENTRATA ERRORE OPEN ' ENT-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           PERFORM UNTIL WS-FINE = 'Y'
               READ ENTRATA
                 AT END MOVE 'Y' TO WS-FINE
               END-READ
               IF WS-FINE = 'N'
                   PERFORM 1000-SCRIVI
               END-IF
           END-PERFORM
           IF ENT-STATUS NOT = '10'
               DISPLAY 'IDXLOAD ENTRATA ERRORE READ ' ENT-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           CLOSE ENTRATA
           EVALUATE PARM-DD
             WHEN 'TRNXFILE' CLOSE TRNX-FILE
             WHEN 'XREFFILE' CLOSE XREF-FILE
             WHEN 'CUSTFILE' CLOSE CUST-FILE
             WHEN 'ACCTFILE' CLOSE ACCT-FILE
           END-EVALUATE
           IF IDX-STATUS NOT = '00'
               DISPLAY 'IDXLOAD ' PARM-DD ' ERRORE CLOSE ' IDX-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           DISPLAY 'IDXLOAD ' PARM-DD ' RECORD SCRITTI ' WS-SCRITTI
           MOVE 0 TO RETURN-CODE
           GOBACK.

       1000-SCRIVI.
           IF ENT-STATUS NOT = '00' OR WS-ENT-LEN > WS-REC-LEN
                                    OR WS-ENT-LEN = 0
               MOVE WS-ENT-LEN TO WS-LEN-ED
               DISPLAY 'IDXLOAD ' PARM-DD ' RIGA ' WS-SCRITTI
                       ' NON CARICABILE: STATO ' ENT-STATUS
                       ' LUNGHEZZA ' WS-LEN-ED
               MOVE 8 TO RETURN-CODE
               STOP RUN
           END-IF
           MOVE SPACES TO WS-RIGA
           MOVE ENT-REC (1:WS-ENT-LEN) TO WS-RIGA
           EVALUATE PARM-DD
             WHEN 'TRNXFILE'
                 MOVE WS-RIGA (1:350) TO FD-TRNXFILE-REC
                 WRITE FD-TRNXFILE-REC
             WHEN 'XREFFILE'
                 MOVE WS-RIGA (1:50) TO FD-XREFFILE-REC
                 WRITE FD-XREFFILE-REC
             WHEN 'CUSTFILE'
                 MOVE WS-RIGA (1:500) TO FD-CUSTFILE-REC
                 WRITE FD-CUSTFILE-REC
             WHEN 'ACCTFILE'
                 MOVE WS-RIGA (1:300) TO FD-ACCTFILE-REC
                 WRITE FD-ACCTFILE-REC
           END-EVALUATE
           IF IDX-STATUS NOT = '00'
               DISPLAY 'IDXLOAD ' PARM-DD ' ERRORE WRITE ' IDX-STATUS
                       ' AL RECORD ' WS-SCRITTI
               MOVE 8 TO RETURN-CODE
               STOP RUN
           END-IF
           ADD 1 TO WS-SCRITTI.
