package io.github.ltoscano.carddemo.loader;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import org.junit.jupiter.api.Test;

class LoaderModuleTest {

    @Test
    void ilModuloVedeIlDominio() throws ClassNotFoundException {
        assertNotNull(Class.forName("io.github.ltoscano.carddemo.loader.package-info"));
        assertNotNull(Class.forName("io.github.ltoscano.carddemo.domain.package-info"));
    }
}
