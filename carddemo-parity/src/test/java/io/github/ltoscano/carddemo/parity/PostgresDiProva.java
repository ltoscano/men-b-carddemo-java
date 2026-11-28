package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.output.MigrateResult;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * Appoggio comune ai test della tabella dei conti (issue #59): PostgreSQL in un container
 * (immagine del servizio {@code db} di {@code compose.yaml}, con l'etichetta della corsa di
 * {@code ./verify.sh}), migrazione con Flyway e letture del catalogo.
 */
final class PostgresDiProva {

    /** Cartella delle migrazioni: quella predefinita di Spring Boot, nel jar di carddemo-domain. */
    static final String MIGRAZIONI = "classpath:db/migration";

    private PostgresDiProva() {
    }

    /** Avvia un PostgreSQL vuoto con l'immagine di compose.yaml; il chiamante lo chiude. */
    static PostgreSQLContainer avvia() throws Exception {
        String immagine = PostgresIntegrazioneTest.immagineDelServizioDb(PostgresIntegrazioneTest.fileCompose());
        PostgreSQLContainer postgres = new PostgreSQLContainer(
                DockerImageName.parse(immagine).asCompatibleSubstituteFor("postgres"));
        String corsa = System.getenv(PostgresIntegrazioneTest.VARIABILE_CORSA);
        if (corsa != null && !corsa.isEmpty()) {
            postgres.withLabel(PostgresIntegrazioneTest.ETICHETTA_CORSA, corsa);
        }
        postgres.start();
        assertEquals(immagine, postgres.getContainerInfo().getConfig().getImage(), "immagine del container avviato");
        return postgres;
    }

    static Connection connessione(PostgreSQLContainer postgres) throws SQLException {
        return DriverManager.getConnection(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword());
    }

    /** Flyway con la configurazione predefinita, come la usa Spring Boot, sulle migrazioni del progetto. */
    static Flyway flyway(PostgreSQLContainer postgres) {
        return Flyway.configure()
                .dataSource(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword())
                .locations(MIGRAZIONI)
                .load();
    }

    /** Applica le migrazioni a un database vuoto e controlla che sia stata applicata esattamente la V1. */
    static void migraDaVuoto(PostgreSQLContainer postgres) {
        MigrateResult esito = flyway(postgres).migrate();
        assertTrue(esito.success, "migrazione non riuscita");
        assertEquals(1, esito.migrationsExecuted, "migrazioni eseguite su un database vuoto");
        assertEquals("1", esito.targetSchemaVersion, "versione dello schema dopo la migrazione");
    }

    /** Righe di una query, colonne unite da '|', valori null come {@code <null>}. */
    static List<String> righe(Connection c, String sql) throws SQLException {
        List<String> out = new ArrayList<>();
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery(sql)) {
            int n = rs.getMetaData().getColumnCount();
            while (rs.next()) {
                StringBuilder riga = new StringBuilder();
                for (int i = 1; i <= n; i++) {
                    if (i > 1) {
                        riga.append('|');
                    }
                    String v = rs.getString(i);
                    riga.append(v == null ? "<null>" : v);
                }
                out.add(riga.toString());
            }
        }
        return out;
    }
}
