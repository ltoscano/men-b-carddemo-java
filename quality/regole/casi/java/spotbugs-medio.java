package io.github.ltoscano.carddemo.online;

/** PROVA-REGOLE-27: difetto di prova di confidenza media (esposizione di un campo modificabile), copiato nel modulo solo durante il caso. */
public class ProvaRegole {

    private final int[] valori = {1, 2, 3};

    public int[] valori() {
        return valori;
    }
}
