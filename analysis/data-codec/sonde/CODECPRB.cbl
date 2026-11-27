      *****************************************************************
      * CODECPRB - sonda delle regole di codifica (issue #23, MEN-B).
      * Non e' codice del legacy. Compilata ed eseguita nell'ambiente
      * dell'oracle (oracle/build/compile.sh uno, oracle/esegui.sh).
      * Legge CODECIN (assegnato con DD_CODECIN), un record fisso per
      * vettore, scritto da analysis/data-codec/glue/sonda.py:
      *   IN-ID     numero di riga del vettore nel file dei vettori
      *   IN-OP     D = decodifica (IN-DATI sono i byte grezzi del
      *             campo), C = codifica (IN-DATI e' il valore nuovo)
      *   IN-VAR    categoria:variante del censimento
      *   IN-NCAMPO lunghezza del campo; IN-NDATI byte utili di IN-DATI
      * Decodifica: i byte vanno nel campo con un MOVE alfanumerico
      * sulla REDEFINES (nessuna conversione); poi IS NUMERIC (prima di
      * ogni uso del campo), valore con MOVE e con ADD in campo largo,
      * byte del campo dopo l'uso, byte scritti da MOVE del valore
      * calcolato in un campo con la stessa PICTURE.
      * Codifica: MOVE del valore (S9(20)V9(6) SIGN LEADING SEPARATE,
      * o testo per gli alfanumerici) nel campo; byte risultanti.
      * Una riga su stdout per vettore, campi separati da '|':
      *   ID|OP|VAR|CLASSE|VALORE-MOVE|VALORE-ADD|SCRITTO|DOPO-USO
      * byte in esadecimale; '-' dove non si applica. Ultima riga FINE.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. CODECPRB.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-FILE ASSIGN TO CODECIN
                  ORGANIZATION IS SEQUENTIAL
                  ACCESS MODE  IS SEQUENTIAL
                  FILE STATUS  IS WS-STATO.
       DATA DIVISION.
       FILE SECTION.
       FD  IN-FILE RECORDING MODE IS F.
       01  IN-REC.
           05  IN-ID               PIC 9(6).
           05  IN-OP               PIC X(1).
           05  IN-VAR              PIC X(40).
           05  IN-NCAMPO           PIC 9(3).
           05  IN-NDATI            PIC 9(3).
           05  IN-DATI             PIC X(500).
           05  IN-VALORE REDEFINES IN-DATI.
               10  IN-VALORE-N     PIC S9(20)V9(6)
                                   SIGN IS LEADING SEPARATE.
               10  FILLER          PIC X(473).
       WORKING-STORAGE SECTION.
       01  WS-STATO                PIC X(02).
       01  WS-FINE                 PIC X(01) VALUE 'N'.
       01  WS-LETTI                PIC 9(6) VALUE 0.
       01  W-MOVE                  PIC S9(20)V9(6)
                                   SIGN IS LEADING SEPARATE.
       01  W-CALC                  PIC S9(20)V9(6)
                                   SIGN IS LEADING SEPARATE.
       01  O-CLASSE                PIC X(01).
       01  O-N                     PIC 9(3).
       01  O-SCRITTO               PIC X(500).
       01  O-DOPO                  PIC X(500).
       01  O-HAS-VAL               PIC X(01).
       01  O-LINEA                 PIC X(3200).
       01  O-PTR                   PIC 9(4).
       01  F-ALFA                  PIC X(500).
       01  G-ALFA                  PIC X(500).
       01  HX-TAB                  PIC X(16) VALUE '0123456789ABCDEF'.
       01  HX-IN                   PIC X(500).
       01  HX-N                    PIC 9(3).
       01  HX-OUT                  PIC X(1000).
       01  HX-I                    PIC 9(4).
       01  HX-B                    PIC 9(4).
       01  HX-H                    PIC 9(4).
       01  HX-L                    PIC 9(4).
       01  HX-SCRITTO              PIC X(1000).
       01  HX-DOPO                 PIC X(1000).
       01  F-DU1            PIC 9(1).
       01  F-DU1-X REDEFINES F-DU1 PIC X(1).
       01  G-DU1            PIC 9(1).
       01  G-DU1-X REDEFINES G-DU1 PIC X(1).
       01  F-DU3            PIC 9(3).
       01  F-DU3-X REDEFINES F-DU3 PIC X(3).
       01  G-DU3            PIC 9(3).
       01  G-DU3-X REDEFINES G-DU3 PIC X(3).
       01  F-DU4            PIC 9(4).
       01  F-DU4-X REDEFINES F-DU4 PIC X(4).
       01  G-DU4            PIC 9(4).
       01  G-DU4-X REDEFINES G-DU4 PIC X(4).
       01  F-DU7            PIC 9(7).
       01  F-DU7-X REDEFINES F-DU7 PIC X(7).
       01  G-DU7            PIC 9(7).
       01  G-DU7-X REDEFINES G-DU7 PIC X(7).
       01  F-DU9            PIC 9(9).
       01  F-DU9-X REDEFINES F-DU9 PIC X(9).
       01  G-DU9            PIC 9(9).
       01  G-DU9-X REDEFINES G-DU9 PIC X(9).
       01  F-DU11           PIC 9(11).
       01  F-DU11-X REDEFINES F-DU11 PIC X(11).
       01  G-DU11           PIC 9(11).
       01  G-DU11-X REDEFINES G-DU11 PIC X(11).
       01  F-DU16           PIC 9(16).
       01  F-DU16-X REDEFINES F-DU16 PIC X(16).
       01  G-DU16           PIC 9(16).
       01  G-DU16-X REDEFINES G-DU16 PIC X(16).
       01  F-DS42           PIC S9(4)V99.
       01  F-DS42-X REDEFINES F-DS42 PIC X(6).
       01  G-DS42           PIC S9(4)V99.
       01  G-DS42-X REDEFINES G-DS42 PIC X(6).
       01  F-DS92           PIC S9(9)V99.
       01  F-DS92-X REDEFINES F-DS92 PIC X(11).
       01  G-DS92           PIC S9(9)V99.
       01  G-DS92-X REDEFINES G-DS92 PIC X(11).
       01  F-DS102          PIC S9(10)V99.
       01  F-DS102-X REDEFINES F-DS102 PIC X(12).
       01  G-DS102          PIC S9(10)V99.
       01  G-DS102-X REDEFINES G-DS102 PIC X(12).
       01  F-PU3            PIC 9(3) COMP-3.
       01  F-PU3-X REDEFINES F-PU3 PIC X(2).
       01  G-PU3            PIC 9(3) COMP-3.
       01  G-PU3-X REDEFINES G-PU3 PIC X(2).
       01  F-PS92           PIC S9(9)V99 COMP-3.
       01  F-PS92-X REDEFINES F-PS92 PIC X(6).
       01  G-PS92           PIC S9(9)V99 COMP-3.
       01  G-PS92-X REDEFINES G-PS92 PIC X(6).
       01  F-PS102          PIC S9(10)V99 COMP-3.
       01  F-PS102-X REDEFINES F-PS102 PIC X(7).
       01  G-PS102          PIC S9(10)V99 COMP-3.
       01  G-PS102-X REDEFINES G-PS102 PIC X(7).
       01  F-BU3            PIC 9(3) COMP.
       01  F-BU3-X REDEFINES F-BU3 PIC X(2).
       01  G-BU3            PIC 9(3) COMP.
       01  G-BU3-X REDEFINES G-BU3 PIC X(2).
       01  F-BU9            PIC 9(9) COMP.
       01  F-BU9-X REDEFINES F-BU9 PIC X(4).
       01  G-BU9            PIC 9(9) COMP.
       01  G-BU9-X REDEFINES G-BU9 PIC X(4).
       01  F-BU11           PIC 9(11) COMP.
       01  F-BU11-X REDEFINES F-BU11 PIC X(8).
       01  G-BU11           PIC 9(11) COMP.
       01  G-BU11-X REDEFINES G-BU11 PIC X(8).
       01  F-BS102          PIC S9(10)V99 COMP.
       01  F-BS102-X REDEFINES F-BS102 PIC X(8).
       01  G-BS102          PIC S9(10)V99 COMP.
       01  G-BS102-X REDEFINES G-BS102 PIC X(8).
       PROCEDURE DIVISION.
           OPEN INPUT IN-FILE
           IF WS-STATO NOT = '00'
               DISPLAY 'CODECPRB ERRORE OPEN CODECIN ' WS-STATO
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           PERFORM UNTIL WS-FINE = 'Y'
               READ IN-FILE
                   AT END MOVE 'Y' TO WS-FINE
                   NOT AT END
                       ADD 1 TO WS-LETTI
                       PERFORM 1000-VETTORE
               END-READ
           END-PERFORM
           IF WS-STATO NOT = '10'
               DISPLAY 'CODECPRB ERRORE READ CODECIN ' WS-STATO
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           CLOSE IN-FILE
           DISPLAY 'FINE|' WS-LETTI
           GOBACK.
       1000-VETTORE.
           MOVE '-' TO O-CLASSE
           MOVE 'N' TO O-HAS-VAL
           MOVE ZERO TO W-MOVE W-CALC O-N
           MOVE SPACES TO O-SCRITTO O-DOPO
           EVALUATE IN-VAR
               WHEN 'display-senza-segno:9(1)'
                   IF IN-OP = 'D' PERFORM D-DU1
                   ELSE PERFORM C-DU1 END-IF
               WHEN 'display-senza-segno:9(3)'
                   IF IN-OP = 'D' PERFORM D-DU3
                   ELSE PERFORM C-DU3 END-IF
               WHEN 'display-senza-segno:9(4)'
                   IF IN-OP = 'D' PERFORM D-DU4
                   ELSE PERFORM C-DU4 END-IF
               WHEN 'display-senza-segno:9(7)'
                   IF IN-OP = 'D' PERFORM D-DU7
                   ELSE PERFORM C-DU7 END-IF
               WHEN 'display-senza-segno:9(9)'
                   IF IN-OP = 'D' PERFORM D-DU9
                   ELSE PERFORM C-DU9 END-IF
               WHEN 'display-senza-segno:9(11)'
                   IF IN-OP = 'D' PERFORM D-DU11
                   ELSE PERFORM C-DU11 END-IF
               WHEN 'display-senza-segno:9(16)'
                   IF IN-OP = 'D' PERFORM D-DU16
                   ELSE PERFORM C-DU16 END-IF
               WHEN 'display-con-segno:S9(4)V9(2)'
                   IF IN-OP = 'D' PERFORM D-DS42
                   ELSE PERFORM C-DS42 END-IF
               WHEN 'display-con-segno:S9(9)V9(2)'
                   IF IN-OP = 'D' PERFORM D-DS92
                   ELSE PERFORM C-DS92 END-IF
               WHEN 'display-con-segno:S9(10)V9(2)'
                   IF IN-OP = 'D' PERFORM D-DS102
                   ELSE PERFORM C-DS102 END-IF
               WHEN 'comp-3:9(3)'
                   IF IN-OP = 'D' PERFORM D-PU3
                   ELSE PERFORM C-PU3 END-IF
               WHEN 'comp-3:S9(9)V9(2)'
                   IF IN-OP = 'D' PERFORM D-PS92
                   ELSE PERFORM C-PS92 END-IF
               WHEN 'comp-3:S9(10)V9(2)'
                   IF IN-OP = 'D' PERFORM D-PS102
                   ELSE PERFORM C-PS102 END-IF
               WHEN 'comp:9(3)'
                   IF IN-OP = 'D' PERFORM D-BU3
                   ELSE PERFORM C-BU3 END-IF
               WHEN 'comp:9(9)'
                   IF IN-OP = 'D' PERFORM D-BU9
                   ELSE PERFORM C-BU9 END-IF
               WHEN 'comp:9(11)'
                   IF IN-OP = 'D' PERFORM D-BU11
                   ELSE PERFORM C-BU11 END-IF
               WHEN 'comp:S9(10)V9(2)'
                   IF IN-OP = 'D' PERFORM D-BS102
                   ELSE PERFORM C-BS102 END-IF
               WHEN OTHER
                   IF IN-VAR(1:13) = 'alfanumerico:'
                       IF IN-OP = 'D' PERFORM D-ALFA
                       ELSE PERFORM C-ALFA END-IF
                   ELSE
                       DISPLAY 'CODECPRB VARIANTE SCONOSCIUTA ' IN-VAR
                       MOVE 8 TO RETURN-CODE
                       GOBACK
                   END-IF
           END-EVALUATE
           PERFORM 2000-SCRIVI.
       2000-SCRIVI.
           MOVE O-SCRITTO TO HX-IN
           MOVE O-N TO HX-N
           PERFORM 3000-ESA
           MOVE HX-OUT TO HX-SCRITTO
           MOVE O-DOPO TO HX-IN
           PERFORM 3000-ESA
           MOVE HX-OUT TO HX-DOPO
           MOVE SPACES TO O-LINEA
           MOVE 1 TO O-PTR
           IF IN-OP = 'D'
               STRING IN-ID '|' IN-OP '|' IN-VAR DELIMITED BY SPACE
                      '|' O-CLASSE '|' DELIMITED BY SIZE
                      INTO O-LINEA WITH POINTER O-PTR
               IF O-HAS-VAL = 'S'
                   STRING W-MOVE '|' W-CALC '|'
                          HX-SCRITTO(1:2 * O-N) '|'
                          HX-DOPO(1:2 * O-N) DELIMITED BY SIZE
                          INTO O-LINEA WITH POINTER O-PTR
               ELSE
                   STRING HX-DOPO(1:2 * O-N) '|-|'
                          HX-SCRITTO(1:2 * O-N) '|'
                          HX-DOPO(1:2 * O-N) DELIMITED BY SIZE
                          INTO O-LINEA WITH POINTER O-PTR
               END-IF
           ELSE
               STRING IN-ID '|' IN-OP '|' IN-VAR DELIMITED BY SPACE
                      '|-|-|-|' HX-SCRITTO(1:2 * O-N) '|-'
                      DELIMITED BY SIZE
                      INTO O-LINEA WITH POINTER O-PTR
           END-IF
           DISPLAY O-LINEA(1:O-PTR - 1).
       3000-ESA.
           MOVE SPACES TO HX-OUT
           PERFORM VARYING HX-I FROM 1 BY 1 UNTIL HX-I > HX-N
               COMPUTE HX-B = FUNCTION ORD(HX-IN(HX-I:1)) - 1
               DIVIDE HX-B BY 16 GIVING HX-H REMAINDER HX-L
               MOVE HX-TAB(HX-H + 1:1) TO HX-OUT(2 * HX-I - 1:1)
               MOVE HX-TAB(HX-L + 1:1) TO HX-OUT(2 * HX-I:1)
           END-PERFORM.
       D-ALFA.
           MOVE IN-DATI(1:IN-NCAMPO) TO F-ALFA(1:IN-NCAMPO)
           MOVE F-ALFA(1:IN-NCAMPO) TO G-ALFA(1:IN-NCAMPO)
           MOVE F-ALFA TO O-DOPO
           MOVE G-ALFA TO O-SCRITTO
           MOVE IN-NCAMPO TO O-N.
       C-ALFA.
      * Il valore vuoto non ha un letterale COBOL: si scrive con SPACES,
      * che e' cio' che un MOVE di un valore piu' corto lascia nel campo
           IF IN-NDATI = 0
               MOVE SPACES TO G-ALFA(1:IN-NCAMPO)
           ELSE
               MOVE IN-DATI(1:IN-NDATI) TO G-ALFA(1:IN-NCAMPO)
           END-IF
           MOVE G-ALFA TO O-SCRITTO
           MOVE IN-NCAMPO TO O-N.
       D-DU1.
           MOVE IN-DATI(1:1) TO F-DU1-X
           IF F-DU1 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DU1 TO W-MOVE
           MOVE IN-DATI(1:1) TO F-DU1-X
           MOVE ZERO TO W-CALC
           ADD F-DU1 TO W-CALC
           MOVE F-DU1-X TO O-DOPO
           MOVE W-CALC TO G-DU1
           MOVE G-DU1-X TO O-SCRITTO
           MOVE 1 TO O-N.
       C-DU1.
           MOVE IN-VALORE-N TO G-DU1
           MOVE G-DU1-X TO O-SCRITTO
           MOVE 1 TO O-N.
       D-DU3.
           MOVE IN-DATI(1:3) TO F-DU3-X
           IF F-DU3 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DU3 TO W-MOVE
           MOVE IN-DATI(1:3) TO F-DU3-X
           MOVE ZERO TO W-CALC
           ADD F-DU3 TO W-CALC
           MOVE F-DU3-X TO O-DOPO
           MOVE W-CALC TO G-DU3
           MOVE G-DU3-X TO O-SCRITTO
           MOVE 3 TO O-N.
       C-DU3.
           MOVE IN-VALORE-N TO G-DU3
           MOVE G-DU3-X TO O-SCRITTO
           MOVE 3 TO O-N.
       D-DU4.
           MOVE IN-DATI(1:4) TO F-DU4-X
           IF F-DU4 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DU4 TO W-MOVE
           MOVE IN-DATI(1:4) TO F-DU4-X
           MOVE ZERO TO W-CALC
           ADD F-DU4 TO W-CALC
           MOVE F-DU4-X TO O-DOPO
           MOVE W-CALC TO G-DU4
           MOVE G-DU4-X TO O-SCRITTO
           MOVE 4 TO O-N.
       C-DU4.
           MOVE IN-VALORE-N TO G-DU4
           MOVE G-DU4-X TO O-SCRITTO
           MOVE 4 TO O-N.
       D-DU7.
           MOVE IN-DATI(1:7) TO F-DU7-X
           IF F-DU7 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DU7 TO W-MOVE
           MOVE IN-DATI(1:7) TO F-DU7-X
           MOVE ZERO TO W-CALC
           ADD F-DU7 TO W-CALC
           MOVE F-DU7-X TO O-DOPO
           MOVE W-CALC TO G-DU7
           MOVE G-DU7-X TO O-SCRITTO
           MOVE 7 TO O-N.
       C-DU7.
           MOVE IN-VALORE-N TO G-DU7
           MOVE G-DU7-X TO O-SCRITTO
           MOVE 7 TO O-N.
       D-DU9.
           MOVE IN-DATI(1:9) TO F-DU9-X
           IF F-DU9 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DU9 TO W-MOVE
           MOVE IN-DATI(1:9) TO F-DU9-X
           MOVE ZERO TO W-CALC
           ADD F-DU9 TO W-CALC
           MOVE F-DU9-X TO O-DOPO
           MOVE W-CALC TO G-DU9
           MOVE G-DU9-X TO O-SCRITTO
           MOVE 9 TO O-N.
       C-DU9.
           MOVE IN-VALORE-N TO G-DU9
           MOVE G-DU9-X TO O-SCRITTO
           MOVE 9 TO O-N.
       D-DU11.
           MOVE IN-DATI(1:11) TO F-DU11-X
           IF F-DU11 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DU11 TO W-MOVE
           MOVE IN-DATI(1:11) TO F-DU11-X
           MOVE ZERO TO W-CALC
           ADD F-DU11 TO W-CALC
           MOVE F-DU11-X TO O-DOPO
           MOVE W-CALC TO G-DU11
           MOVE G-DU11-X TO O-SCRITTO
           MOVE 11 TO O-N.
       C-DU11.
           MOVE IN-VALORE-N TO G-DU11
           MOVE G-DU11-X TO O-SCRITTO
           MOVE 11 TO O-N.
       D-DU16.
           MOVE IN-DATI(1:16) TO F-DU16-X
           IF F-DU16 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DU16 TO W-MOVE
           MOVE IN-DATI(1:16) TO F-DU16-X
           MOVE ZERO TO W-CALC
           ADD F-DU16 TO W-CALC
           MOVE F-DU16-X TO O-DOPO
           MOVE W-CALC TO G-DU16
           MOVE G-DU16-X TO O-SCRITTO
           MOVE 16 TO O-N.
       C-DU16.
           MOVE IN-VALORE-N TO G-DU16
           MOVE G-DU16-X TO O-SCRITTO
           MOVE 16 TO O-N.
       D-DS42.
           MOVE IN-DATI(1:6) TO F-DS42-X
           IF F-DS42 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DS42 TO W-MOVE
           MOVE IN-DATI(1:6) TO F-DS42-X
           MOVE ZERO TO W-CALC
           ADD F-DS42 TO W-CALC
           MOVE F-DS42-X TO O-DOPO
           MOVE W-CALC TO G-DS42
           MOVE G-DS42-X TO O-SCRITTO
           MOVE 6 TO O-N.
       C-DS42.
           MOVE IN-VALORE-N TO G-DS42
           MOVE G-DS42-X TO O-SCRITTO
           MOVE 6 TO O-N.
       D-DS92.
           MOVE IN-DATI(1:11) TO F-DS92-X
           IF F-DS92 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DS92 TO W-MOVE
           MOVE IN-DATI(1:11) TO F-DS92-X
           MOVE ZERO TO W-CALC
           ADD F-DS92 TO W-CALC
           MOVE F-DS92-X TO O-DOPO
           MOVE W-CALC TO G-DS92
           MOVE G-DS92-X TO O-SCRITTO
           MOVE 11 TO O-N.
       C-DS92.
           MOVE IN-VALORE-N TO G-DS92
           MOVE G-DS92-X TO O-SCRITTO
           MOVE 11 TO O-N.
       D-DS102.
           MOVE IN-DATI(1:12) TO F-DS102-X
           IF F-DS102 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-DS102 TO W-MOVE
           MOVE IN-DATI(1:12) TO F-DS102-X
           MOVE ZERO TO W-CALC
           ADD F-DS102 TO W-CALC
           MOVE F-DS102-X TO O-DOPO
           MOVE W-CALC TO G-DS102
           MOVE G-DS102-X TO O-SCRITTO
           MOVE 12 TO O-N.
       C-DS102.
           MOVE IN-VALORE-N TO G-DS102
           MOVE G-DS102-X TO O-SCRITTO
           MOVE 12 TO O-N.
       D-PU3.
           MOVE IN-DATI(1:2) TO F-PU3-X
           IF F-PU3 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-PU3 TO W-MOVE
           MOVE IN-DATI(1:2) TO F-PU3-X
           MOVE ZERO TO W-CALC
           ADD F-PU3 TO W-CALC
           MOVE F-PU3-X TO O-DOPO
           MOVE W-CALC TO G-PU3
           MOVE G-PU3-X TO O-SCRITTO
           MOVE 2 TO O-N.
       C-PU3.
           MOVE IN-VALORE-N TO G-PU3
           MOVE G-PU3-X TO O-SCRITTO
           MOVE 2 TO O-N.
       D-PS92.
           MOVE IN-DATI(1:6) TO F-PS92-X
           IF F-PS92 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-PS92 TO W-MOVE
           MOVE IN-DATI(1:6) TO F-PS92-X
           MOVE ZERO TO W-CALC
           ADD F-PS92 TO W-CALC
           MOVE F-PS92-X TO O-DOPO
           MOVE W-CALC TO G-PS92
           MOVE G-PS92-X TO O-SCRITTO
           MOVE 6 TO O-N.
       C-PS92.
           MOVE IN-VALORE-N TO G-PS92
           MOVE G-PS92-X TO O-SCRITTO
           MOVE 6 TO O-N.
       D-PS102.
           MOVE IN-DATI(1:7) TO F-PS102-X
           IF F-PS102 IS NUMERIC
               MOVE 'S' TO O-CLASSE
           ELSE
               MOVE 'N' TO O-CLASSE
           END-IF
           MOVE 'S' TO O-HAS-VAL
           MOVE F-PS102 TO W-MOVE
           MOVE IN-DATI(1:7) TO F-PS102-X
           MOVE ZERO TO W-CALC
           ADD F-PS102 TO W-CALC
           MOVE F-PS102-X TO O-DOPO
           MOVE W-CALC TO G-PS102
           MOVE G-PS102-X TO O-SCRITTO
           MOVE 7 TO O-N.
       C-PS102.
           MOVE IN-VALORE-N TO G-PS102
           MOVE G-PS102-X TO O-SCRITTO
           MOVE 7 TO O-N.
       D-BU3.
           MOVE IN-DATI(1:2) TO F-BU3-X
           MOVE '-' TO O-CLASSE
           MOVE 'S' TO O-HAS-VAL
           MOVE F-BU3 TO W-MOVE
           MOVE IN-DATI(1:2) TO F-BU3-X
           MOVE ZERO TO W-CALC
           ADD F-BU3 TO W-CALC
           MOVE F-BU3-X TO O-DOPO
           MOVE W-CALC TO G-BU3
           MOVE G-BU3-X TO O-SCRITTO
           MOVE 2 TO O-N.
       C-BU3.
           MOVE IN-VALORE-N TO G-BU3
           MOVE G-BU3-X TO O-SCRITTO
           MOVE 2 TO O-N.
       D-BU9.
           MOVE IN-DATI(1:4) TO F-BU9-X
           MOVE '-' TO O-CLASSE
           MOVE 'S' TO O-HAS-VAL
           MOVE F-BU9 TO W-MOVE
           MOVE IN-DATI(1:4) TO F-BU9-X
           MOVE ZERO TO W-CALC
           ADD F-BU9 TO W-CALC
           MOVE F-BU9-X TO O-DOPO
           MOVE W-CALC TO G-BU9
           MOVE G-BU9-X TO O-SCRITTO
           MOVE 4 TO O-N.
       C-BU9.
           MOVE IN-VALORE-N TO G-BU9
           MOVE G-BU9-X TO O-SCRITTO
           MOVE 4 TO O-N.
       D-BU11.
           MOVE IN-DATI(1:8) TO F-BU11-X
           MOVE '-' TO O-CLASSE
           MOVE 'S' TO O-HAS-VAL
           MOVE F-BU11 TO W-MOVE
           MOVE IN-DATI(1:8) TO F-BU11-X
           MOVE ZERO TO W-CALC
           ADD F-BU11 TO W-CALC
           MOVE F-BU11-X TO O-DOPO
           MOVE W-CALC TO G-BU11
           MOVE G-BU11-X TO O-SCRITTO
           MOVE 8 TO O-N.
       C-BU11.
           MOVE IN-VALORE-N TO G-BU11
           MOVE G-BU11-X TO O-SCRITTO
           MOVE 8 TO O-N.
       D-BS102.
           MOVE IN-DATI(1:8) TO F-BS102-X
           MOVE '-' TO O-CLASSE
           MOVE 'S' TO O-HAS-VAL
           MOVE F-BS102 TO W-MOVE
           MOVE IN-DATI(1:8) TO F-BS102-X
           MOVE ZERO TO W-CALC
           ADD F-BS102 TO W-CALC
           MOVE F-BS102-X TO O-DOPO
           MOVE W-CALC TO G-BS102
           MOVE G-BS102-X TO O-SCRITTO
           MOVE 8 TO O-N.
       C-BS102.
           MOVE IN-VALORE-N TO G-BS102
           MOVE G-BS102-X TO O-SCRITTO
           MOVE 8 TO O-N.
