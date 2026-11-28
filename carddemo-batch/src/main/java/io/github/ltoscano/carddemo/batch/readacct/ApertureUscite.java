package io.github.ltoscano.carddemo.batch.readacct;

import java.io.IOException;
import java.nio.file.Path;

/**
 * Creazione dei file di uscita di {@code CBACT01C} ({@code OPEN OUTPUT}, righe 336, 354, 372), ciascuno
 * nuovo come con {@code DISP=(NEW,CATLG,DELETE)} ({@code READACCT.jcl:37-47}).
 */
public interface ApertureUscite {

    /**
     * Crea il file e lo apre in scrittura.
     *
     * @param dd nome DD del JCL ({@code OUTFILE}, {@code ARRYFILE}, {@code VBRCFILE})
     * @param percorso il file da creare; non deve esistere
     * @return il file aperto
     * @throws IOException se il file non si crea
     */
    FileUscita apri(String dd, Path percorso) throws IOException;
}
