      *****************************************************************
      * DTCCALL - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Richiama il modulo CSUTLDTC con i tre argomenti
      * che usa CORPT00C (righe 129-136 e 392-394): data, formato,
      * area del risultato. CSUTLDTC chiama a sua volta CEEDAYS, che
      * qui e' un segnaposto (issue #24): ci si aspetta che il
      * segnaposto termini l'esecuzione con codice 98. La prova dimostra
      * che il modulo CSUTLDTC si carica e arriva alla chiamata.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. DTCCALL.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  CSUTLDTC-PARM.
           05  CSUTLDTC-DATE                   PIC X(10).
           05  CSUTLDTC-DATE-FORMAT            PIC X(10).
           05  CSUTLDTC-RESULT                 PIC X(80).
       PROCEDURE DIVISION.
           MOVE '2022-07-18' TO CSUTLDTC-DATE
           MOVE 'YYYY-MM-DD' TO CSUTLDTC-DATE-FORMAT
           MOVE SPACES       TO CSUTLDTC-RESULT
           DISPLAY 'DTCCALL CALL CSUTLDTC'
           CALL 'CSUTLDTC' USING CSUTLDTC-DATE
                                 CSUTLDTC-DATE-FORMAT
                                 CSUTLDTC-RESULT
           DISPLAY 'DTCCALL RITORNO RESULT=' CSUTLDTC-RESULT
           GOBACK.
