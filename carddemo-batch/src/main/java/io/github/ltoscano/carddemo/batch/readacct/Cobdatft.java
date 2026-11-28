package io.github.ltoscano.carddemo.batch.readacct;

import java.util.Arrays;

/**
 * Equivalente della routine assembler {@code COBDATFT} ({@code app/asm/COBDATFT.asm}) per la sola
 * combinazione che {@code CBACT01C} usa: tipo d'ingresso {@code '2'} e tipo d'uscita {@code '2'}
 * ({@code CBACT01C.cbl:225-226}), sull'area {@code CODATECN-REC} ({@code COPY CODATECN}).
 *
 * <p>Ramo {@code VALIDIN2} ({@code COBDATFT.asm:46-54}): il controllo dei separatori e' commentato
 * (righe 47-48) e con uscita {@code '2'} il salto all'errore non avviene (righe 49-50). Restano tre
 * {@code MVC} (righe 51-53): i caratteri 1-4, 6-7 e 9-10 della data d'ingresso diventano i byte 1-8 della
 * data d'uscita. Nessuna validazione: una data non valida passa cosi' com'e' (per esempio
 * {@code ABCDEFGHIJ} → {@code ABCDFGIJ}). Il ramo d'errore e le altre combinazioni non sono tradotti: il
 * programma non li usa ({@code oracle/routines/cobdatft-casi.md}).
 */
final class Cobdatft {

    /** Lunghezza di {@code CODATECN-INP-DATE} e di {@code CODATECN-0UT-DATE} ({@code X(20)}). */
    static final int LUNGHEZZA_DATA = 20;

    /**
     * Byte convenzionale del progetto per i byte che il sorgente non determina ({@code CODATECN-0UT-DATE}
     * e' {@code X(20)} senza {@code VALUE}, {@code CODATECN.cpy:39}): non e' un comportamento dell'originale.
     */
    static final byte NON_DETERMINATO = 0x00;

    private static final byte SPAZIO = 0x20;

    private Cobdatft() {
    }

    /**
     * {@code MOVE ACCT-REISSUE-DATE TO CODATECN-INP-DATE} ({@code CBACT01C.cbl:223}), {@code CALL 'COBDATFT'}
     * (riga 231) e {@code MOVE CODATECN-0UT-DATE TO OUT-ACCT-REISSUE-DATE} (riga 233).
     *
     * @param dataIngresso i 10 byte di {@code ACCT-REISSUE-DATE}
     * @return i primi 10 byte di {@code CODATECN-0UT-DATE}: 8 scritti dalla routine, gli ultimi 2
     *     {@link #NON_DETERMINATO}
     */
    static byte[] converti(byte[] dataIngresso) {
        if (dataIngresso.length != 10) {
            throw new IllegalArgumentException("data d'ingresso di " + dataIngresso.length + " byte, attesi 10");
        }
        // MOVE di un X(10) in un X(20): i 10 byte e poi 10 spazi di riempimento.
        byte[] ingresso = new byte[LUNGHEZZA_DATA];
        Arrays.fill(ingresso, SPAZIO);
        System.arraycopy(dataIngresso, 0, ingresso, 0, dataIngresso.length);
        byte[] uscita = new byte[LUNGHEZZA_DATA];
        Arrays.fill(uscita, NON_DETERMINATO);
        // MVC COOUTDT(4),COINPDT        (COBDATFT.asm:51)
        System.arraycopy(ingresso, 0, uscita, 0, 4);
        // MVC COOUTDT+4(2),COINPDT+5    (COBDATFT.asm:52)
        System.arraycopy(ingresso, 5, uscita, 4, 2);
        // MVC COOUTDT+6(2),COINPDT+8    (COBDATFT.asm:53)
        System.arraycopy(ingresso, 8, uscita, 6, 2);
        return Arrays.copyOf(uscita, 10);
    }
}
