      *****************************************************************
      * COBDATFT - segnaposto dell'oracle MEN-B (non e' codice del
      * legacy). Nel legacy COBDATFT e' una routine assembler
      * (app/asm/COBDATFT.asm) di conversione di date, chiamata da
      * CBACT01C. La sua semantica non e' implementata qui (issue #24):
      * se viene chiamata, scrive una riga riconoscibile su stderr e
      * termina l'esecuzione con codice di uscita 98, fisso.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. COBDATFT.
       PROCEDURE DIVISION.
           DISPLAY 'MENB-ORACLE SEGNAPOSTO: COBDATFT NON IMPLEMENTATO'
                   ' (ISSUE #24)'
                   UPON SYSERR
           MOVE 98 TO RETURN-CODE
           STOP RUN.
