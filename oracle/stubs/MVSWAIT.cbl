      *****************************************************************
      * MVSWAIT - segnaposto dell'oracle MEN-B (non e' codice del
      * legacy). Nel legacy MVSWAIT e' una routine assembler
      * (app/asm/MVSWAIT.asm) che attende un tempo dato, chiamata da
      * COBSWAIT. La sua semantica non e' implementata qui (issue #24):
      * se viene chiamata, scrive una riga riconoscibile su stderr e
      * termina l'esecuzione con codice di uscita 98, fisso.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MVSWAIT.
       PROCEDURE DIVISION.
           DISPLAY 'MENB-ORACLE SEGNAPOSTO: MVSWAIT NON IMPLEMENTATO'
                   ' (ISSUE #24)'
                   UPON SYSERR
           MOVE 98 TO RETURN-CODE
           STOP RUN.
