      *****************************************************************
      * CEEDAYS - segnaposto dell'oracle MEN-B (non e' codice del
      * legacy). Su z/OS CEEDAYS e' il servizio di Language Environment
      * che converte una data nel numero di giorni dal 14 ottobre 1582,
      * chiamato da CSUTLDTC. La sua semantica non e' implementata qui
      * (issue #24): se viene chiamato, scrive una riga riconoscibile
      * su stderr e termina l'esecuzione con codice di uscita 98, fisso.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. CEEDAYS.
       PROCEDURE DIVISION.
           DISPLAY 'MENB-ORACLE SEGNAPOSTO: CEEDAYS NON IMPLEMENTATO'
                   ' (ISSUE #24)'
                   UPON SYSERR
           MOVE 98 TO RETURN-CODE
           STOP RUN.
