package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/** PROVA-REGOLE-27: test della classe lecita della controprova, copiato nel modulo solo durante il caso. */
class ProvaCoperturaTest {

    @Test
    void sommaDueNumeri() {
        assertEquals(5, new ProvaCopertura().somma(2, 3));
    }
}
