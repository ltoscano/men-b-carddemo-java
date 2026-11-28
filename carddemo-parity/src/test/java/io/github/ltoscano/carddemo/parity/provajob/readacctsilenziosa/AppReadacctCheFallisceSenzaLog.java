package io.github.ltoscano.carddemo.parity.provajob.readacctsilenziosa;

import java.util.Map;

import org.springframework.boot.SpringApplication;

import io.github.ltoscano.carddemo.parity.provajob.readacctfallisce.AppReadacctCheFallisce;

/**
 * Applicazione di prova dei test (issue #65, controprova del bloccante della seconda validazione),
 * non di produzione: la stessa configurazione di {@link AppReadacctCheFallisce} (job READACCT avviato
 * che stampa la traccia nativa del job assente e fallisce con 1), con {@code logging.level.root=WARN}
 * fissato nell'applicazione stessa (proprieta' predefinita, non ambiente ne' argomenti): le righe INFO
 * di avvio di Spring Batch non compaiono. Il riconoscimento del job assente deve respingerla con
 * un'evidenza che non dipende dai log.
 */
public final class AppReadacctCheFallisceSenzaLog {

    private AppReadacctCheFallisceSenzaLog() {
    }

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(AppReadacctCheFallisce.class);
        app.setDefaultProperties(Map.of("logging.level.root", "WARN"));
        int codice = SpringApplication.exit(app.run(args));
        System.exit(codice == 0 ? 0 : 1);
    }
}
