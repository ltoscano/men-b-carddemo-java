package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

import java.nio.file.Path;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Test di parita' di READACCT (CBACT01C), scritto prima della traduzione (issue #65).
 *
 * <p>Ogni caso: PostgreSQL reale e vuoto, migrazione, conti caricati con il caricatore di #60
 * dall'ingresso dello scenario e verificati con il codificatore indipendente; poi il jar eseguibile di
 * carddemo-batch con il comando del contratto ({@code docs/contratti.md}) e i confronti di
 * {@link ComparatoreReadacct} con i riferimenti di #55. Finche' il job non esiste i casi sono marcati
 * {@link FallimentoAtteso}: la traduzione (issue #67) toglie marcatura e righe dell'elenco.
 */
class ReadacctParitaTest {

    /** Cartella nuova per ogni caso (uscite, log dei processi, ingresso permutato). */
    @TempDir
    Path tmp;

    @Test
    void esempio() throws Exception {
        primoAvvio("esempio", tmp);
    }

    @Test
    void mirato() throws Exception {
        primoAvvio("mirato", tmp);
    }

    /** Due avvii sugli stessi percorsi e sullo stesso database; prima del secondo, file sentinella. */
    @Test
    void miratoRiesecuzione() throws Exception {
        Path scenario = ComparatoreReadacct.scenario("mirato");
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            ParitaReadacct.prepara(postgres, ParitaReadacct.ingresso(scenario), scenario);
            Path uscite = ParitaReadacct.cartellaUscite(tmp);
            ParitaReadacct.avviaEConfronta(AvvioJob.comandoJar(), ParitaReadacct.ambiente(postgres), scenario, uscite,
                    tmp.resolve("log"));
            ParitaReadacct.riavviaSuSentinelle(AvvioJob.comandoJar(), ParitaReadacct.ambiente(postgres), scenario, uscite,
                    tmp.resolve("log"));
        }
    }

    /** Conti inseriti in ordine fisico inverso: le uscite devono coincidere con gli stessi riferimenti. */
    @Test
    void miratoOrdineDiLettura() throws Exception {
        Path scenario = ComparatoreReadacct.scenario("mirato");
        Path permutato = ParitaReadacct.permutato(ParitaReadacct.ingresso(scenario), tmp);
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            ParitaReadacct.prepara(postgres, permutato, scenario);
            List<String> fisico = ParitaReadacct.chiaviInOrdineFisico(postgres);
            assertEquals(ParitaReadacct.chiaviDelFile(permutato), fisico, "ordine fisico delle righe dopo il caricamento");
            assertNotEquals(ParitaReadacct.chiaviDelFile(ParitaReadacct.ingresso(scenario)), fisico,
                    "l'ordine fisico doveva essere diverso dall'ordine delle chiavi");
            ParitaReadacct.avviaEConfronta(AvvioJob.comandoJar(), ParitaReadacct.ambiente(postgres), scenario,
                    ParitaReadacct.cartellaUscite(tmp), tmp.resolve("log"));
        }
    }

    private static void primoAvvio(String nome, Path tmp) throws Exception {
        Path scenario = ComparatoreReadacct.scenario(nome);
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            ParitaReadacct.prepara(postgres, ParitaReadacct.ingresso(scenario), scenario);
            ParitaReadacct.avviaEConfronta(AvvioJob.comandoJar(), ParitaReadacct.ambiente(postgres), scenario,
                    ParitaReadacct.cartellaUscite(tmp), tmp.resolve("log"));
        }
    }
}
