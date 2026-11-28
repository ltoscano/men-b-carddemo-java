package io.github.ltoscano.carddemo.batch.readacct;

import java.io.BufferedOutputStream;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.OutputStream;

/**
 * Dove il programma scrive le righe dei {@code DISPLAY}: nell'applicazione lo standard output del processo
 * (descrittore 1, senza passare da {@code System.out}, cosi' un errore di scrittura non si perde); nei test
 * un flusso in memoria. Il flusso non ha un metodo di chiusura raggiungibile da Spring: lo standard output
 * non si chiude con il contesto.
 */
public final class UscitaConsole {

    private final OutputStream flusso;

    private UscitaConsole(OutputStream flusso) {
        this.flusso = flusso;
    }

    /** Dimensione del buffer della console dello standard output. */
    static final int BUFFER = 1 << 16;

    /** @return la console dello standard output del processo, con un buffer che il programma svuota */
    public static UscitaConsole standardOutput() {
        return new UscitaConsole(new BufferedOutputStream(new FileOutputStream(FileDescriptor.out), BUFFER));
    }

    /** @return una console che scrive in {@code flusso} (test) */
    public static UscitaConsole su(OutputStream flusso) {
        return new UscitaConsole(flusso);
    }

    OutputStream flusso() {
        return flusso;
    }
}
