package io.github.ltoscano.carddemo.batch.readacct;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;

/**
 * File di uscita sul file system: creati con {@link StandardOpenOption#CREATE_NEW} (un file gia' esistente
 * e' un errore di creazione, come un data set gia' catalogato con {@code DISP=NEW}), scritti attraverso un
 * buffer, senza terminatori ne' intestazioni.
 */
public final class ApertureUsciteSuDisco implements ApertureUscite {

    /** Dimensione del buffer di scrittura di ogni file. */
    static final int BUFFER = 1 << 16;

    @Override
    public FileUscita apri(String dd, Path percorso) throws IOException {
        OutputStream flusso = Files.newOutputStream(percorso, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
        return new SuDisco(new BufferedOutputStream(flusso, BUFFER));
    }

    private static final class SuDisco implements FileUscita {

        private final OutputStream flusso;

        SuDisco(OutputStream flusso) {
            this.flusso = flusso;
        }

        @Override
        public void scrivi(byte[] record) throws IOException {
            flusso.write(record);
        }

        @Override
        public void chiudi() throws IOException {
            flusso.close();
        }
    }
}
