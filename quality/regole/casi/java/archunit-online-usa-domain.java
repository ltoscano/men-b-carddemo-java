package io.github.ltoscano.carddemo.online;

import io.github.ltoscano.carddemo.domain.ProvaDominio;

/** PROVA-REGOLE-26: controprova lecita, online usa domain. */
class ProvaRegole {
    Class<?> altro() {
        return ProvaDominio.class;
    }
}
