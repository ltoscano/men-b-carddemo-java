      *****************************************************************
      * PERFPRB - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Sonda semantica su un'opzione ereditata dal
      * dialetto IBM di GnuCOBOL, perform-osvs (ibm-strict.conf):
      * "the exit point of any currently executing perform is
      * recognized if reached".
      * PERFORM P-A THRU P-D esegue P-A, che a sua volta esegue
      * PERFORM P-B THRU P-E. Quando il controllo arriva alla fine di
      * P-D, che e' il punto d'uscita del PERFORM esterno ancora attivo:
      * - con perform-osvs (configurazione dell'immagine) si torna al
      *   PERFORM esterno: righe B C D DONE;
      * - senza, si prosegue nel PERFORM interno fino a P-E e poi si
      *   ritorna in P-A: righe B C D E AFTER-INNER B C D DONE.
      * Un cambio della configurazione del compilatore che tolga
      * perform-osvs cambia quindi l'output di questo programma.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. PERFPRB.
       PROCEDURE DIVISION.
       P-MAIN.
           PERFORM P-A THRU P-D
           DISPLAY 'DONE'
           GOBACK.
       P-A.
           PERFORM P-B THRU P-E
           DISPLAY 'AFTER-INNER'.
       P-B.
           DISPLAY 'B'.
       P-C.
           DISPLAY 'C'.
       P-D.
           DISPLAY 'D'.
       P-E.
           DISPLAY 'E'.
