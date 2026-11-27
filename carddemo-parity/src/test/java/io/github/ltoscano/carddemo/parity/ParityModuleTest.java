package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import org.junit.jupiter.api.Test;

class ParityModuleTest {

    @Test
    void ilModuloVedeTuttiGliAltri() throws ClassNotFoundException {
        assertNotNull(Class.forName("io.github.ltoscano.carddemo.domain.package-info"));
        assertNotNull(Class.forName("io.github.ltoscano.carddemo.loader.package-info"));
        assertNotNull(Class.forName("io.github.ltoscano.carddemo.online.OnlineApplication"));
        assertNotNull(Class.forName("io.github.ltoscano.carddemo.batch.BatchApplication"));
    }
}
