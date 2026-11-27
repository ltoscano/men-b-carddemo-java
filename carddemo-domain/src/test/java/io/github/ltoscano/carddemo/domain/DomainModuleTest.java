package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import org.junit.jupiter.api.Test;

class DomainModuleTest {

    @Test
    void ilPacchettoDelModuloEsiste() throws ClassNotFoundException {
        assertNotNull(Class.forName("io.github.ltoscano.carddemo.domain.package-info"));
    }
}
