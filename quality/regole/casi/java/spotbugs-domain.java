package io.github.ltoscano.carddemo.domain;

/** PROVA-REGOLE-27: difetto di prova (dereferenziazione di un valore sempre nullo), copiato nel modulo solo durante il caso. */
public class ProvaRegole {

    public int lunghezza() {
        String s = null;
        return s.length();
    }
}
