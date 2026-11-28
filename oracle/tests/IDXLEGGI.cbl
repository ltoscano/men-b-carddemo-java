      *****************************************************************
      * IDXLEGGI - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy, issue #53, giro di correzione della PR #58).
      * Lettore INDIPENDENTE del file indicizzato dei conti: scritto
      * senza codice in comune con IDXDUMP (#25) e con IDXLOADF, legge
      * il file con il SELECT e l'FD di CBACT01C (app/cbl/CBACT01C.cbl,
      * righe 29-33 e 52-56: INDEXED, accesso sequenziale, chiave
      * FD-ACCT-ID PIC 9(11), record di 300 byte).
      * 1. Lettura sequenziale in ordine di chiave: conta i record,
      *    pretende chiavi strettamente crescenti (confronto dei byte)
      *    e lo stato 10 dopo l'ultimo record; copia ogni record letto,
      *    campo di gruppo per campo di gruppo, nel file della DD
      *    LETTURA (record fissi di 300 byte, senza separatori).
      * 2. Letture per chiave: per ogni chiave del PARM, START con
      *    KEY IS = e READ; pretende stato 00 per entrambe e la chiave
      *    letta uguale a quella chiesta; copia il record nel file della
      *    DD CHIAVI.
      * PARM: 'ACCTFILE' seguito da 0-3 chiavi di 11 cifre.
      * Esito: 0 se tutto riesce; 8 per ogni errore (PARM non valido,
      * stato di apertura, lettura, START, scrittura o chiusura diverso
      * da quello atteso, chiave non crescente o diversa).
      * Usato dal passo oracle/dati/.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. IDXLEGGI.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ACCT-FILE ASSIGN TO ACCTFILE
                  ORGANIZATION IS INDEXED
                  ACCESS MODE  IS SEQUENTIAL
                  RECORD KEY   IS FD-ACCT-ID
                  FILE STATUS  IS ST-CONTI.
           SELECT F-LETTURA ASSIGN TO LETTURA
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS  IS ST-LETTURA.
           SELECT F-CHIAVI ASSIGN TO CHIAVI
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS  IS ST-CHIAVI.
       DATA DIVISION.
       FILE SECTION.
       FD  ACCT-FILE.
       01  FD-ACCTFILE-REC.
           05 FD-ACCT-ID                        PIC 9(11).
           05 FD-ACCT-DATA                      PIC X(289).
       FD  F-LETTURA RECORDING MODE IS F.
       01  REC-LETTURA             PIC X(300).
       FD  F-CHIAVI RECORDING MODE IS F.
       01  REC-CHIAVI              PIC X(300).
       WORKING-STORAGE SECTION.
       01  ST-CONTI                PIC X(02).
       01  ST-LETTURA              PIC X(02).
       01  ST-CHIAVI               PIC X(02).
       01  N-RECORD                PIC 9(06) VALUE 0.
       01  N-CHIAVI                PIC 9(02) VALUE 0.
       01  N-RESTO                 PIC 9(02) VALUE 0.
       01  K                       PIC 9(02) VALUE 0.
       01  POS-CHIAVE              PIC 9(03) VALUE 0.
       01  CHIAVE-PRECEDENTE       PIC X(11) VALUE LOW-VALUES.
       01  CHIAVE-CHIESTA          PIC X(11).
       01  ANCORA                  PIC X(01) VALUE 'S'.
       LINKAGE SECTION.
       01  AREA-PARM.
           05  LUNGHEZZA-PARM      PIC S9(04) COMP.
           05  TESTO-PARM          PIC X(100).
       PROCEDURE DIVISION USING AREA-PARM.
       0000-INIZIO.
           IF LUNGHEZZA-PARM < 8 OR LUNGHEZZA-PARM > 41
               DISPLAY 'IDXLEGGI PARM NON VALIDO'
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           IF TESTO-PARM (1:8) NOT = 'ACCTFILE'
               DISPLAY 'IDXLEGGI PARM NON VALIDO: ' TESTO-PARM (1:8)
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           DIVIDE 11 INTO LUNGHEZZA-PARM GIVING N-CHIAVI
                  REMAINDER N-RESTO
           IF N-RESTO NOT = 8
               DISPLAY 'IDXLEGGI CHIAVI DEL PARM NON DI 11 CIFRE'
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           PERFORM 1000-SEQUENZIALE
           IF N-CHIAVI > 0
               PERFORM 2000-PER-CHIAVE
           END-IF
           MOVE 0 TO RETURN-CODE
           GOBACK.

       1000-SEQUENZIALE.
           OPEN INPUT ACCT-FILE
           IF ST-CONTI NOT = '00'
               DISPLAY 'IDXLEGGI ACCTFILE APERTURA STATO ' ST-CONTI
               PERFORM 9000-ERRORE
           END-IF
           OPEN OUTPUT F-LETTURA
           IF ST-LETTURA NOT = '00'
               DISPLAY 'IDXLEGGI LETTURA APERTURA STATO ' ST-LETTURA
               PERFORM 9000-ERRORE
           END-IF
           PERFORM UNTIL ANCORA = 'N'
               READ ACCT-FILE NEXT RECORD
               EVALUATE ST-CONTI
                 WHEN '00'
                     PERFORM 1100-REGISTRA
                 WHEN '10'
                     MOVE 'N' TO ANCORA
                 WHEN OTHER
                     DISPLAY 'IDXLEGGI ACCTFILE LETTURA STATO '
                             ST-CONTI ' DOPO ' N-RECORD ' RECORD'
                     PERFORM 9000-ERRORE
               END-EVALUATE
           END-PERFORM
           CLOSE ACCT-FILE
           IF ST-CONTI NOT = '00'
               DISPLAY 'IDXLEGGI ACCTFILE CHIUSURA STATO ' ST-CONTI
               PERFORM 9000-ERRORE
           END-IF
           CLOSE F-LETTURA
           IF ST-LETTURA NOT = '00'
               DISPLAY 'IDXLEGGI LETTURA CHIUSURA STATO ' ST-LETTURA
               PERFORM 9000-ERRORE
           END-IF
           DISPLAY 'IDXLEGGI ACCTFILE RECORD LETTI ' N-RECORD
                   ', FINE CON STATO 10'.

       1100-REGISTRA.
           IF N-RECORD > 0
              AND FD-ACCTFILE-REC (1:11) NOT > CHIAVE-PRECEDENTE
               DISPLAY 'IDXLEGGI CHIAVE NON CRESCENTE: '
                       FD-ACCTFILE-REC (1:11)
               PERFORM 9000-ERRORE
           END-IF
           MOVE FD-ACCTFILE-REC (1:11) TO CHIAVE-PRECEDENTE
           MOVE FD-ACCTFILE-REC TO REC-LETTURA
           WRITE REC-LETTURA
           IF ST-LETTURA NOT = '00'
               DISPLAY 'IDXLEGGI LETTURA SCRITTURA STATO ' ST-LETTURA
               PERFORM 9000-ERRORE
           END-IF
           ADD 1 TO N-RECORD.

       2000-PER-CHIAVE.
           OPEN INPUT ACCT-FILE
           IF ST-CONTI NOT = '00'
               DISPLAY 'IDXLEGGI ACCTFILE APERTURA STATO ' ST-CONTI
               PERFORM 9000-ERRORE
           END-IF
           OPEN OUTPUT F-CHIAVI
           IF ST-CHIAVI NOT = '00'
               DISPLAY 'IDXLEGGI CHIAVI APERTURA STATO ' ST-CHIAVI
               PERFORM 9000-ERRORE
           END-IF
           MOVE 9 TO POS-CHIAVE
           PERFORM VARYING K FROM 1 BY 1 UNTIL K > N-CHIAVI
               MOVE TESTO-PARM (POS-CHIAVE:11) TO CHIAVE-CHIESTA
               ADD 11 TO POS-CHIAVE
               MOVE CHIAVE-CHIESTA TO FD-ACCTFILE-REC (1:11)
               START ACCT-FILE KEY IS = FD-ACCT-ID
               IF ST-CONTI NOT = '00'
                   DISPLAY 'IDXLEGGI CHIAVE ' CHIAVE-CHIESTA
                           ' START STATO ' ST-CONTI
                   PERFORM 9000-ERRORE
               END-IF
               READ ACCT-FILE NEXT RECORD
               IF ST-CONTI NOT = '00'
                   DISPLAY 'IDXLEGGI CHIAVE ' CHIAVE-CHIESTA
                           ' READ STATO ' ST-CONTI
                   PERFORM 9000-ERRORE
               END-IF
               IF FD-ACCTFILE-REC (1:11) NOT = CHIAVE-CHIESTA
                   DISPLAY 'IDXLEGGI CHIAVE ' CHIAVE-CHIESTA
                           ' LETTA ' FD-ACCTFILE-REC (1:11)
                   PERFORM 9000-ERRORE
               END-IF
               MOVE FD-ACCTFILE-REC TO REC-CHIAVI
               WRITE REC-CHIAVI
               IF ST-CHIAVI NOT = '00'
                   DISPLAY 'IDXLEGGI CHIAVI SCRITTURA STATO ' ST-CHIAVI
                   PERFORM 9000-ERRORE
               END-IF
               DISPLAY 'IDXLEGGI ACCTFILE CHIAVE ' CHIAVE-CHIESTA
                       ' START 00 READ 00'
           END-PERFORM
           CLOSE ACCT-FILE
           IF ST-CONTI NOT = '00'
               DISPLAY 'IDXLEGGI ACCTFILE CHIUSURA STATO ' ST-CONTI
               PERFORM 9000-ERRORE
           END-IF
           CLOSE F-CHIAVI
           IF ST-CHIAVI NOT = '00'
               DISPLAY 'IDXLEGGI CHIAVI CHIUSURA STATO ' ST-CHIAVI
               PERFORM 9000-ERRORE
           END-IF.

       9000-ERRORE.
           MOVE 8 TO RETURN-CODE
           STOP RUN.
