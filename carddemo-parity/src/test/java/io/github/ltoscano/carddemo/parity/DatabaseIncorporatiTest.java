package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * Database incorporati vietati (#26), controllo sulle classi: il classpath di parity (che
 * dipende da tutti i moduli) non deve contenere il driver di H2, HSQLDB o Derby, qualunque
 * sia la coordinata Maven che li porta (anche bundle ripubblicati). Limite: classi
 * rinominate o database non elencati non sono rilevati.
 */
class DatabaseIncorporatiTest {

    private static final List<String> CLASSI_VIETATE = List.of(
            "org.h2.Driver",
            "org.h2.jdbcx.JdbcDataSource",
            "org.hsqldb.jdbc.JDBCDriver",
            "org.hsqldb.jdbcDriver",
            "org.apache.derby.jdbc.EmbeddedDriver",
            "org.apache.derby.iapi.jdbc.AutoloadedDriver");

    @Test
    void nessun_driver_di_database_incorporato_e_caricabile() {
        List<String> trovate = new ArrayList<>();
        for (String nome : CLASSI_VIETATE) {
            try {
                Class.forName(nome, false, DatabaseIncorporatiTest.class.getClassLoader());
                trovate.add(nome);
            } catch (ClassNotFoundException assente) {
                // atteso: la classe non c'e'
            }
        }
        assertTrue(trovate.isEmpty(), "DATABASE-INCORPORATO-CLASSE-VIETATA: " + trovate);
    }
}
