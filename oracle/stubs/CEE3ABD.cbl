      *****************************************************************
      * CEE3ABD - stub dell'oracle MEN-B (non e' codice del legacy).
      * Su z/OS CEE3ABD e' il servizio di Language Environment che
      * termina il programma con un arresto anomalo (abend) con codice
      * utente ABCODE; TIMING dice se farlo subito (0) o dopo la
      * gestione delle condizioni (1).
      *
      * Sotto GnuCOBOL questo stub:
      * - regge le due forme di chiamata del legacy:
      *     CALL 'CEE3ABD' USING ABCODE, TIMING  (es. CBACT01C)
      *     CALL 'CEE3ABD'                      (es. CBSTM03A)
      *   e distingue le due forme con C$NARG (numero di argomenti);
      * - scrive su stderr una riga riconoscibile con ABCODE e TIMING;
      * - termina l'intera esecuzione con codice di uscita 99, fisso:
      *   nessuno degli 11 programmi produce 99 da se' (RETURN-CODE
      *   usato solo da CBTRN02C, 4, e CSUTLDTC, severita' 0-4).
      * La terminazione usa STOP RUN: libcob chiude i file ancora
      * aperti (scrivendo cio' che e' in memoria) prima di uscire,
      * quindi i record gia' scritti non vanno persi. TIMING non
      * cambia nulla. Le differenze rispetto a z/OS sono nel README.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. CEE3ABD.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-NARGS                PIC S9(9) BINARY.
       LINKAGE SECTION.
       01  LK-ABCODE               PIC S9(9) BINARY.
       01  LK-TIMING               PIC S9(9) BINARY.
       PROCEDURE DIVISION USING LK-ABCODE LK-TIMING.
           CALL 'C$NARG' USING WS-NARGS
           IF WS-NARGS >= 2
               DISPLAY 'MENB-ORACLE CEE3ABD: ARRESTO ANOMALO ABCODE='
                       LK-ABCODE ' TIMING=' LK-TIMING
                       UPON SYSERR
           ELSE
               DISPLAY 'MENB-ORACLE CEE3ABD: ARRESTO ANOMALO'
                       ' SENZA ARGOMENTI'
                       UPON SYSERR
           END-IF
           MOVE 99 TO RETURN-CODE
           STOP RUN.
