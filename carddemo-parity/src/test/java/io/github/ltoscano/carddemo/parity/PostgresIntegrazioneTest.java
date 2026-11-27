package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import com.github.dockerjava.api.command.InspectContainerResponse;
import com.github.dockerjava.api.exception.NotFoundException;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;
import org.yaml.snakeyaml.Yaml;

/**
 * Test di integrazione di esempio: avvia PostgreSQL in un container con Testcontainers, usando
 * l'immagine del servizio {@code db} di {@code compose.yaml} (tag e digest), crea una tabella
 * temporanea propria, scrive, rilegge e la elimina. Non introduce schema.
 *
 * <p>Se Docker non e' raggiungibile il test fallisce: nessuna annotazione o condizione lo salta.
 */
class PostgresIntegrazioneTest {

    /** Proprieta' di sistema con il percorso di compose.yaml, impostata dal POM del modulo. */
    static final String PROPRIETA_COMPOSE = "menb.compose.file";

    /** Variabile d'ambiente con l'identificativo della corsa di ./verify.sh. */
    static final String VARIABILE_CORSA = "MENB_VERIFY_RUN_ID";

    /** Etichetta con cui ./verify.sh riconosce e rimuove i container avviati dai test. */
    static final String ETICHETTA_CORSA = "menb.verify.run";

    @Test
    void avviaLImmagineDiComposeScriveRileggeEdElimina() throws Exception {
        Path compose = fileCompose();
        String immagine = immagineDelServizioDb(compose);
        // Tag e digest obbligatori: "nome:tag@sha256:...", con il tag dopo l'ultima '/'.
        int chiocciola = immagine.indexOf("@sha256:");
        int duepunti = chiocciola < 0 ? -1 : immagine.lastIndexOf(':', chiocciola);
        if (chiocciola < 0 || duepunti < 0 || immagine.lastIndexOf('/', chiocciola) > duepunti) {
            fail("l'immagine del servizio db in " + compose + " deve avere tag e digest: '" + immagine + "'");
        }
        String digest = immagine.substring(chiocciola + 1);
        System.out.println("[integrazione] compose: " + compose);
        System.out.println("[integrazione] immagine del servizio db: " + immagine);

        String corsa = System.getenv(VARIABILE_CORSA);
        String idContainer;
        // L'immagine e' quella di compose.yaml, cosi' com'e' scritta: Testcontainers la legge
        // come "postgres:<tag>" con versione "sha256:...", quindi va dichiarata compatibile.
        DockerImageName nome = DockerImageName.parse(immagine).asCompatibleSubstituteFor("postgres");
        try (PostgreSQLContainer postgres = new PostgreSQLContainer(nome)) {
            if (corsa != null && !corsa.isEmpty()) {
                postgres.withLabel(ETICHETTA_CORSA, corsa);
            }
            postgres.start();
            InspectContainerResponse info = postgres.getContainerInfo();
            idContainer = info.getId();
            String immagineAvviata = info.getConfig().getImage();
            List<String> digestDellImmagine = DockerClientFactory.instance().client()
                    .inspectImageCmd(info.getImageId()).exec().getRepoDigests();
            System.out.println("[integrazione] container avviato: " + idContainer);
            System.out.println("[integrazione] immagine del container avviato: " + immagineAvviata);
            System.out.println("[integrazione] digest dell'immagine avviata: " + digestDellImmagine);

            // L'immagine del container effettivamente avviato coincide con quella di compose.yaml:
            // riferimento completo (tag e digest) e digest del contenuto.
            assertEquals(immagine, immagineAvviata, "immagine del container avviato");
            assertNotNull(digestDellImmagine, "digest dell'immagine avviata");
            assertTrue(digestDellImmagine.stream().anyMatch(d -> d.endsWith("@" + digest)),
                    "l'immagine avviata non ha il digest " + digest + ": " + digestDellImmagine);

            try (Connection connessione = DriverManager.getConnection(
                    postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword())) {
                scriviRileggiElimina(connessione);
            }
        }
        // Chiuso il blocco, il container non esiste piu'.
        try {
            DockerClientFactory.instance().client().inspectContainerCmd(idContainer).exec();
            fail("il container " + idContainer + " esiste ancora dopo l'arresto");
        } catch (NotFoundException atteso) {
            System.out.println("[integrazione] container " + idContainer + " rimosso");
        }
    }

    private static void scriviRileggiElimina(Connection connessione) throws Exception {
        try (Statement st = connessione.createStatement()) {
            try (ResultSet rs = st.executeQuery("select version()")) {
                assertTrue(rs.next());
                System.out.println("[integrazione] " + rs.getString(1));
            }
            st.execute("create temporary table menb_prova_integrazione"
                    + " (id integer primary key, testo varchar(40) not null)");
        }
        try (PreparedStatement ins = connessione.prepareStatement(
                "insert into menb_prova_integrazione (id, testo) values (?, ?)")) {
            ins.setInt(1, 1);
            ins.setString(2, "uno");
            ins.addBatch();
            ins.setInt(1, 2);
            ins.setString(2, "due");
            ins.addBatch();
            int[] righe = ins.executeBatch();
            assertEquals(2, righe.length);
        }
        try (Statement st = connessione.createStatement()) {
            StringBuilder letto = new StringBuilder();
            try (ResultSet rs = st.executeQuery("select id, testo from menb_prova_integrazione order by id")) {
                while (rs.next()) {
                    letto.append(rs.getInt(1)).append('=').append(rs.getString(2)).append(';');
                }
            }
            assertEquals("1=uno;2=due;", letto.toString(), "righe rilette");
            System.out.println("[integrazione] righe scritte e rilette: " + letto);

            st.execute("drop table menb_prova_integrazione");
            try (ResultSet rs = st.executeQuery("select to_regclass('menb_prova_integrazione') is null")) {
                assertTrue(rs.next());
                assertTrue(rs.getBoolean(1), "la tabella esiste ancora dopo drop");
            }
            System.out.println("[integrazione] tabella menb_prova_integrazione eliminata");
        }
    }

    /** Percorso di compose.yaml alla radice del repository, passato dal POM; nessun ripiego. */
    static Path fileCompose() {
        String valore = System.getProperty(PROPRIETA_COMPOSE);
        if (valore == null || valore.isBlank()) {
            fail("proprieta' di sistema " + PROPRIETA_COMPOSE + " non impostata");
        }
        Path compose = Path.of(valore);
        assertTrue(compose.isAbsolute(), PROPRIETA_COMPOSE + " non e' un percorso assoluto: " + valore);
        assertTrue(Files.isRegularFile(compose), "compose.yaml non trovato: " + compose);
        return compose;
    }

    /** Valore di services.db.image in compose.yaml. */
    @SuppressWarnings("unchecked")
    static String immagineDelServizioDb(Path compose) throws Exception {
        Object radice;
        try (Reader lettore = Files.newBufferedReader(compose, StandardCharsets.UTF_8)) {
            radice = new Yaml().load(lettore);
        }
        Object servizi = radice instanceof Map<?, ?> m ? m.get("services") : null;
        Object db = servizi instanceof Map<?, ?> m ? m.get("db") : null;
        Object immagine = db instanceof Map<?, ?> m ? m.get("image") : null;
        if (!(immagine instanceof String testo) || testo.isBlank()) {
            fail("services.db.image assente o non testuale in " + compose + ": " + immagine);
            return null;
        }
        assertFalse(testo.contains("$"), "services.db.image contiene una variabile: " + testo);
        return testo;
    }
}
