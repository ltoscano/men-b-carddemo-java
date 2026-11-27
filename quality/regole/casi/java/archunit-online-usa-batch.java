package io.github.ltoscano.carddemo.online;

import io.github.ltoscano.carddemo.batch.BatchApplication;

/** PROVA-REGOLE-26: classe di online che usa una classe di batch. */
class ProvaRegole {
    Class<?> altro() {
        return BatchApplication.class;
    }
}
