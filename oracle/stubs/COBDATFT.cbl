      *****************************************************************
      * COBDATFT - equivalente dell'oracle MEN-B (non e' codice del
      * legacy) della routine assembler app/asm/COBDATFT.asm, chiamata
      * da CBACT01C (righe 223-231) con l'area di 80 byte di
      * app/cpy/CODATECN.cpy (in assembler: app/maclib/COCDATFT.mac).
      *
      * Riproduce solo cio' che le istruzioni determinano byte per byte
      * (issue #24, voce 42 del registro). Tabella dei casi, con le
      * righe dell'assembler: oracle/routines/cobdatft-casi.md e .tsv.
      * - Tipo d'ingresso '1', tipo d'uscita diverso da '2', byte 5-18
      *   della data d'ingresso diversi da '-INVALID INPUT': AAAAMMGG ->
      *   AAAA-MM-GG nei primi 10 byte della data d'uscita (righe 40-44).
      * - Tipo d'ingresso '2', tipo d'uscita diverso da '1':
      *   AAAA?MM?GG -> AAAAMMGG nei primi 8 byte (righe 51-53).
      * - Nessun controllo del calendario ne' delle cifre: l'assembler
      *   non ne fa. Tutti gli altri byte dell'area restano invariati.
      * - Codice di ritorno 0 (riga 61, SR R15,R15).
      * Casi non determinati dal sorgente: la routine scrive su stderr
      * "caso non riproducibile dall'oracle" e termina l'intera
      * esecuzione con codice di uscita 97, fisso:
      * - ogni ramo che arriva a GOTOERR (riga 56): MVC COERMSG copia 38
      *   byte da un letterale di 13; i 25 byte oltre il letterale
      *   dipendono dalla memoria del programma assemblato;
      * - tipo '1' con byte 5-18 della data uguali a '-INVALID INPUT'
      *   (riga 36): CLC confronta 20 byte (lunghezza di COINPDT) con il
      *   pool dei letterali, C'-' seguito da C'INVALID INPUT' (14 byte
      *   noti) e da 6 byte che dipendono dalla memoria.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. COBDATFT.
       DATA DIVISION.
       LINKAGE SECTION.
      * COCDATFT.mac righe 18-23 (CODATECN.cpy righe 17-52).
       01  LK-COREC.
           05  LK-COINTYPE         PIC X(01).
           05  LK-COINPDT          PIC X(20).
           05  LK-COOUTYPE         PIC X(01).
           05  LK-COOUTDT          PIC X(20).
           05  LK-COERMSG          PIC X(38).
       PROCEDURE DIVISION USING LK-COREC.
      * Righe 30-34: CLI COINTYPE,C'1' / C'2', altrimenti GOTOERR.
           EVALUATE TRUE
               WHEN LK-COINTYPE = '1'
                   PERFORM VALIDIN1
               WHEN LK-COINTYPE = '2'
                   PERFORM VALIDIN2
               WHEN OTHER
                   PERFORM NON-RIPRODUCIBILE
           END-EVALUATE
      * Righe 59-62: ripristino dei registri, R15 = 0, ritorno.
           MOVE 0 TO RETURN-CODE
           GOBACK.

       VALIDIN1.
      * Riga 36: CLC COINPDT+4,=C'-' (20 byte). Il secondo operando
      * e' il pool dei letterali: C'-' e subito dopo C'INVALID INPUT'
      * (14 byte noti), poi 6 byte ignoti. Se i byte 5-18 della data
      * differiscono dai 14 noti il confronto e' "diverso" qualunque
      * cosa segua; se coincidono l'esito dipende dai 6 byte ignoti.
           IF LK-COINPDT(5:14) = '-INVALID INPUT'
               PERFORM NON-RIPRODUCIBILE
           END-IF
      * Righe 38-39: CLI COOUTYPE,C'2' -> GOTOERR.
           IF LK-COOUTYPE = '2'
               PERFORM NON-RIPRODUCIBILE
           END-IF
      * Righe 40-44.
           MOVE LK-COINPDT(1:4) TO LK-COOUTDT(1:4)
           MOVE '-'             TO LK-COOUTDT(5:1)
           MOVE LK-COINPDT(5:2) TO LK-COOUTDT(6:2)
           MOVE '-'             TO LK-COOUTDT(8:1)
           MOVE LK-COINPDT(7:2) TO LK-COOUTDT(9:2).

       VALIDIN2.
      * Righe 49-50: CLI COOUTYPE,C'1' -> GOTOERR.
           IF LK-COOUTYPE = '1'
               PERFORM NON-RIPRODUCIBILE
           END-IF
      * Righe 51-53.
           MOVE LK-COINPDT(1:4) TO LK-COOUTDT(1:4)
           MOVE LK-COINPDT(6:2) TO LK-COOUTDT(5:2)
           MOVE LK-COINPDT(9:2) TO LK-COOUTDT(7:2).

       NON-RIPRODUCIBILE.
      * Riga 56 (o riga 36 con esito dipendente dalla memoria).
           DISPLAY 'MENB-ORACLE COBDATFT: caso non riproducibile'
                   ' dall''oracle'
                   UPON SYSERR
           MOVE 97 TO RETURN-CODE
           STOP RUN.
