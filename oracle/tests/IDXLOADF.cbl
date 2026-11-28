      *****************************************************************
      * IDXLOADF - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy, issue #53). Carica un file indicizzato da un file
      * sequenziale di record a lunghezza fissa SENZA terminatori (DD
      * ENTRATA), record per record nell'ordine del file, con accesso
      * sequenziale: nessun riempimento, nessun troncamento, nessuna
      * conversione. Il file si sceglie con il PARM; oggi solo
      * ACCTFILE, con organizzazione, chiave e lunghezza del SELECT e
      * dell'FD di CBACT01C (app/cbl/CBACT01C.cbl, righe 29-33 e
      * 52-56): INDEXED, chiave FD-ACCT-ID PIC 9(11) nei byte 1-11,
      * record di 300 byte.
      * Diverso da IDXLOAD (#25), che legge righe di testo, le riempie
      * di spazi e non controlla lo stato di chiusura dell'ingresso.
      * GnuCOBOL 3.2 legge l'ultimo record incompleto di un file
      * sequenziale a record fissi con stato 00, lasciando nell'area i
      * byte del record precedente (osservato, issue #53): per questo
      * la dimensione dell'ingresso si legge PRIMA di aprirlo, con
      * CBL_CHECK_FILE_EXIST sullo stesso nome che si apre, e deve
      * essere un multiplo esatto della lunghezza del record; alla
      * fine i record letti devono essere dimensione / lunghezza.
      * Una chiave non crescente o doppia ferma il caricamento: la
      * WRITE in accesso sequenziale da' stato 21 (osservato).
      * Esito: 0 se tutti i record sono scritti con ogni stato atteso;
      * 8 per ogni errore (PARM sconosciuto, DD_ENTRATA non impostata,
      * ingresso assente o di dimensione non multipla, stato di
      * apertura, lettura, scrittura o chiusura diverso da quello
      * atteso, record letti diversi da quelli attesi). Il file
      * indicizzato scritto in parte resta: lo rimuove il chiamante
      * (oracle/dati/run.sh). Usato dal passo oracle/dati/.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. IDXLOADF.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ENTRATA ASSIGN USING WS-NOME-ENTRATA
                  ORGANIZATION IS SEQUENTIAL
                  FILE STATUS  IS ENT-STATUS.
           SELECT ACCT-FILE ASSIGN TO ACCTFILE
                  ORGANIZATION IS INDEXED
                  ACCESS MODE  IS SEQUENTIAL
                  RECORD KEY   IS FD-ACCT-ID
                  FILE STATUS  IS IDX-STATUS.
       DATA DIVISION.
       FILE SECTION.
       FD  ENTRATA RECORDING MODE IS F.
       01  ENT-REC                 PIC X(300).
      * Tracciato di CBACT01C (righe 52-56), con gli stessi nomi.
       FD  ACCT-FILE.
       01  FD-ACCTFILE-REC.
           05 FD-ACCT-ID                        PIC 9(11).
           05 FD-ACCT-DATA                      PIC X(289).
       WORKING-STORAGE SECTION.
       01  ENT-STATUS              PIC X(02).
       01  IDX-STATUS              PIC X(02).
       01  WS-NOME-ENTRATA         PIC X(256) VALUE SPACES.
      * Area di CBL_CHECK_FILE_EXIST: dimensione in 8 byte binari
      * big-endian (binary-byteorder big-endian di -std=ibm), poi data
      * e ora (non usate).
       01  WS-DETTAGLI.
           05 WS-DIMENSIONE        PIC 9(18) COMP.
           05 FILLER               PIC X(08).
       01  WS-ESITO-CHECK          PIC S9(09) COMP VALUE 0.
       01  WS-LUNGHEZZA            PIC 9(04) VALUE 300.
       01  WS-ATTESI               PIC 9(09) VALUE 0.
       01  WS-RESTO                PIC 9(04) VALUE 0.
       01  WS-SCRITTI              PIC 9(06) VALUE 0.
       01  WS-FINE                 PIC X(01) VALUE 'N'.
       01  WS-DIM-ED               PIC Z(17)9.
       01  WS-ATT-ED               PIC Z(8)9.
       01  WS-ESITO-ED             PIC -(9)9.
       LINKAGE SECTION.
       01  EXTERNAL-PARMS.
           05  PARM-LENGTH         PIC S9(04) COMP.
           05  PARM-DD             PIC X(08).
       PROCEDURE DIVISION USING EXTERNAL-PARMS.
           EVALUATE PARM-DD
             WHEN 'ACCTFILE' MOVE 300 TO WS-LUNGHEZZA
             WHEN OTHER
                 DISPLAY 'IDXLOADF PARM SCONOSCIUTO: ' PARM-DD
                 MOVE 8 TO RETURN-CODE
                 GOBACK
           END-EVALUATE
           ACCEPT WS-NOME-ENTRATA FROM ENVIRONMENT 'DD_ENTRATA'
               ON EXCEPTION
                   DISPLAY 'IDXLOADF DD_ENTRATA NON IMPOSTATA'
                   MOVE 8 TO RETURN-CODE
                   GOBACK
           END-ACCEPT
           IF WS-NOME-ENTRATA = SPACES
               DISPLAY 'IDXLOADF DD_ENTRATA VUOTA'
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           CALL 'CBL_CHECK_FILE_EXIST' USING WS-NOME-ENTRATA
                                             WS-DETTAGLI
           MOVE RETURN-CODE TO WS-ESITO-CHECK
           IF WS-ESITO-CHECK NOT = 0
               MOVE WS-ESITO-CHECK TO WS-ESITO-ED
               DISPLAY 'IDXLOADF ENTRATA ASSENTE: CBL_CHECK_FILE_EXIST '
                       WS-ESITO-ED
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           DIVIDE WS-DIMENSIONE BY WS-LUNGHEZZA GIVING WS-ATTESI
                  REMAINDER WS-RESTO
           IF WS-RESTO NOT = 0
               MOVE WS-DIMENSIONE TO WS-DIM-ED
               DISPLAY 'IDXLOADF ENTRATA DI ' FUNCTION TRIM (WS-DIM-ED)
                       ' BYTE, NON MULTIPLA DI ' WS-LUNGHEZZA
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           OPEN INPUT ENTRATA
           IF ENT-STATUS NOT = '00'
               DISPLAY 'IDXLOADF ENTRATA ERRORE OPEN ' ENT-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           OPEN OUTPUT ACCT-FILE
           IF IDX-STATUS NOT = '00'
               DISPLAY 'IDXLOADF ' PARM-DD ' ERRORE OPEN ' IDX-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           PERFORM UNTIL WS-FINE = 'Y'
               READ ENTRATA
               EVALUATE ENT-STATUS
                 WHEN '00'
                     PERFORM 1000-SCRIVI
                 WHEN '10'
                     MOVE 'Y' TO WS-FINE
                 WHEN OTHER
                     DISPLAY 'IDXLOADF ENTRATA ERRORE READ ' ENT-STATUS
                             ' DOPO IL RECORD ' WS-SCRITTI
                     MOVE 8 TO RETURN-CODE
                     GOBACK
               END-EVALUATE
           END-PERFORM
           IF WS-SCRITTI NOT = WS-ATTESI
               MOVE WS-ATTESI TO WS-ATT-ED
               DISPLAY 'IDXLOADF ' PARM-DD ' RECORD LETTI ' WS-SCRITTI
                       ', ATTESI ' FUNCTION TRIM (WS-ATT-ED)
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           CLOSE ENTRATA
           IF ENT-STATUS NOT = '00'
               DISPLAY 'IDXLOADF ENTRATA ERRORE CLOSE ' ENT-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           CLOSE ACCT-FILE
           IF IDX-STATUS NOT = '00'
               DISPLAY 'IDXLOADF ' PARM-DD ' ERRORE CLOSE ' IDX-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           DISPLAY 'IDXLOADF ' PARM-DD ' RECORD SCRITTI ' WS-SCRITTI
           MOVE 0 TO RETURN-CODE
           GOBACK.

       1000-SCRIVI.
           WRITE FD-ACCTFILE-REC FROM ENT-REC
           IF IDX-STATUS NOT = '00'
               DISPLAY 'IDXLOADF ' PARM-DD ' ERRORE WRITE ' IDX-STATUS
                       ' DOPO IL RECORD ' WS-SCRITTI
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           ADD 1 TO WS-SCRITTI.
