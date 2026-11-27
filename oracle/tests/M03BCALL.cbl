      *****************************************************************
      * M03BCALL - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Richiama il modulo CBSTM03B con un'area valida,
      * definita come WS-M03B-AREA di CBSTM03A (righe 71-85), e ne
      * stampa il codice di ritorno LK-M03B-RC:
      * - per ciascuno dei quattro file gestiti (TRNXFILE, XREFFILE,
      *   CUSTFILE, ACCTFILE) chiede l'apertura (operazione 'O'); senza
      *   file d'ingresso ci si aspetta lo stato '35' (file assente);
      * - con un nome DD che CBSTM03B non gestisce (WHEN OTHER) il
      *   codice di ritorno resta quello impostato prima della CALL.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. M03BCALL.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-M03B-AREA.
           05  WS-M03B-DD          PIC X(08).
           05  WS-M03B-OPER        PIC X(01).
           05  WS-M03B-RC          PIC X(02).
           05  WS-M03B-KEY         PIC X(25).
           05  WS-M03B-KEY-LN      PIC S9(4).
           05  WS-M03B-FLDT        PIC X(1000).
       PROCEDURE DIVISION.
           MOVE 'TRNXFILE' TO WS-M03B-DD
           PERFORM 1000-APRI
           MOVE 'XREFFILE' TO WS-M03B-DD
           PERFORM 1000-APRI
           MOVE 'CUSTFILE' TO WS-M03B-DD
           PERFORM 1000-APRI
           MOVE 'ACCTFILE' TO WS-M03B-DD
           PERFORM 1000-APRI
           MOVE 'NONGEST ' TO WS-M03B-DD
           MOVE 'O'        TO WS-M03B-OPER
           MOVE 'XX'       TO WS-M03B-RC
           CALL 'CBSTM03B' USING WS-M03B-AREA
           DISPLAY 'M03BCALL ' WS-M03B-DD ' O RC=' WS-M03B-RC
           GOBACK.
       1000-APRI.
           MOVE 'O'        TO WS-M03B-OPER
           MOVE ZERO       TO WS-M03B-RC
           MOVE SPACES     TO WS-M03B-KEY
           MOVE ZERO       TO WS-M03B-KEY-LN
           MOVE SPACES     TO WS-M03B-FLDT
           CALL 'CBSTM03B' USING WS-M03B-AREA
           DISPLAY 'M03BCALL ' WS-M03B-DD ' O RC=' WS-M03B-RC.
