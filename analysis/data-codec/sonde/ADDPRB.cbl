      *****************************************************************
      * ADDPRB - programma di prova (issue #23, MEN-B), non e' codice
      * del legacy. Serve solo a ispezionare il C che cobc genera per
      * ADD di un 9(9) COMP a un campo largo (verifica manuale della
      * causa del caso FF FF FF FF, codifica.md). Non e' eseguito dai
      * controlli. Comando, nell'immagine dell'oracle:
      *   env -i PATH=/usr/bin:/bin HOME=/tmp LC_ALL=C cobc -std=ibm
      *     -fbinary-truncate -fsingle-quote -fsign=EBCDIC -C
      *     -o ADDPRB.c ADDPRB.cbl
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. ADDPRB.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  F-BU9                   PIC 9(9) COMP.
       01  W-CALC                  PIC S9(20)V9(6)
                                   SIGN IS LEADING SEPARATE.
       PROCEDURE DIVISION.
           MOVE ZERO TO W-CALC
           ADD F-BU9 TO W-CALC
           GOBACK.
