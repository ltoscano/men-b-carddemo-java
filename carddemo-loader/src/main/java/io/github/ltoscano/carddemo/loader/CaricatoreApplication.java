package io.github.ltoscano.carddemo.loader;

import java.io.IOException;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import javax.sql.DataSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ConfigurableApplicationContext;

/**
 * Applicazione del caricatore dei conti (issue #60): all'avvio Spring Boot applica la migrazione con
 * Flyway (la stessa risorsa {@code db/migration/V1__account.sql} di {@code carddemo-domain}), poi
 * {@link CaricatoreConti} carica il file indicato come unico argomento posizionale e l'applicazione
 * termina con il codice dell'esito:
 * <ul>
 *   <li>{@value #USCITA_RIUSCITA}: file caricato per intero;</li>
 *   <li>{@value #USCITA_RIFIUTATO}: caricamento rifiutato (file non conforme o tabella non vuota),
 *       nessuna riga scritta;</li>
 *   <li>{@value #USCITA_ERRORE}: argomenti sbagliati, file illeggibile, avvio o database falliti.</li>
 * </ul>
 * Indirizzo, utente e password del database arrivano da {@code SPRING_DATASOURCE_URL},
 * {@code SPRING_DATASOURCE_USERNAME}, {@code SPRING_DATASOURCE_PASSWORD} (impostate da
 * {@code compose.yaml}).
 */
@SpringBootApplication
public class CaricatoreApplication {

    public static final int USCITA_RIUSCITA = 0;
    public static final int USCITA_RIFIUTATO = 1;
    public static final int USCITA_ERRORE = 2;

    private static final Logger LOG = LoggerFactory.getLogger(CaricatoreApplication.class);

    public static void main(String[] args) {
        System.exit(esegui(args));
    }

    /**
     * Avvia il contesto (migrazione compresa), carica il file e chiude il contesto.
     *
     * @param args un argomento posizionale, il file dei conti, piu' eventuali opzioni di Spring
     *     Boot ({@code --nome=valore})
     * @return il codice di uscita
     */
    public static int esegui(String... args) {
        List<String> posizionali = new ArrayList<>();
        for (String a : args) {
            if (!a.startsWith("--")) {
                posizionali.add(a);
            }
        }
        if (posizionali.size() != 1) {
            LOG.error("CARICAMENTO FALLITO: atteso un solo argomento, il file dei conti; ricevuti {}", posizionali);
            return USCITA_ERRORE;
        }
        Path file = Path.of(posizionali.get(0));
        try (ConfigurableApplicationContext contesto = SpringApplication.run(CaricatoreApplication.class, args);
                Connection connessione = contesto.getBean(DataSource.class).getConnection()) {
            int record = CaricatoreConti.carica(file, connessione);
            LOG.info("CARICAMENTO RIUSCITO: {} record caricati da {} nella tabella account", record, file);
            return USCITA_RIUSCITA;
        } catch (CaricamentoRifiutato e) {
            LOG.error("CARICAMENTO RIFIUTATO: {}", e.getMessage());
            return USCITA_RIFIUTATO;
        } catch (IOException | SQLException | RuntimeException e) {
            LOG.error("CARICAMENTO FALLITO: {}", e.toString(), e);
            return USCITA_ERRORE;
        }
    }
}
