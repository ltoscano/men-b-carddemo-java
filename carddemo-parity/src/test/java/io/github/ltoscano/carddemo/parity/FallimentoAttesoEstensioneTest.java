package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectMethod;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.platform.engine.TestExecutionResult;
import org.junit.platform.testkit.engine.EngineTestKit;
import org.junit.platform.testkit.engine.Event;
import org.junit.platform.testkit.engine.Events;

/**
 * Test del meccanismo del fallimento atteso (issue #65) su un caso campione dedicato, che vive qui e
 * resta dopo la traduzione: elenco e cartella delle ricevute sono temporanei, mai quelli del progetto.
 * Le classi campione sono annidate: surefire non le esegue da sole (esclusione predefinita {@code **}{@code /*$*}).
 */
class FallimentoAttesoEstensioneTest {

    static final String CAMPIONE = "motivo-campione";
    static final String C = "io.github.ltoscano.carddemo.parity.FallimentoAttesoEstensioneTest$Campione";

    @TempDir
    Path tmp;

    /** Casi campione: eseguiti solo attraverso EngineTestKit. */
    static class Campione {

        @Test
        @FallimentoAtteso(issue = 999, motivo = CAMPIONE)
        void fallisceComeDichiarato() {
            throw new MotivoDichiarato(CAMPIONE, "il caso campione fallisce come dichiarato");
        }

        @Test
        @FallimentoAtteso(issue = 999, motivo = CAMPIONE)
        void fallissePerAltro() {
            throw new IllegalStateException("errore del database simulato");
        }

        @Test
        @FallimentoAtteso(issue = 999, motivo = CAMPIONE)
        void fallissePerUnAltroMotivoDichiarato() {
            throw new MotivoDichiarato("altro-motivo", "motivo diverso");
        }

        @Test
        @FallimentoAtteso(issue = 999, motivo = CAMPIONE)
        void riesce() {
            // nessun errore: il caso ora riesce
        }
    }

    private Path elenco(String... metodi) throws IOException {
        StringBuilder testo = new StringBuilder("# elenco di prova\n").append(FallimentoAttesoEstensione.INTESTAZIONE).append('\n');
        for (String m : metodi) {
            testo.append(m).append('\n');
        }
        Path file = Files.createTempFile(tmp, "elenco-", ".tsv");
        Files.writeString(file, testo.toString(), StandardCharsets.UTF_8);
        return file;
    }

    private static String riga(String metodo, int issue, String motivo) {
        return Campione.class.getName() + "\t" + metodo + "\t" + issue + "\t" + motivo;
    }

    private Events esegui(String metodo, Path elenco, Path ricevute) {
        return EngineTestKit.engine("junit-jupiter")
                .selectors(selectMethod(Campione.class, metodo))
                .configurationParameter(FallimentoAttesoEstensione.ELENCO, elenco.toString())
                .configurationParameter(FallimentoAttesoEstensione.RICEVUTE, ricevute.toString())
                .configurationParameter(FallimentoAttesoEstensione.CORSA, "corsa-di-prova")
                .execute().testEvents();
    }

    private static String fallitoCon(Events eventi) {
        assertEquals(1, eventi.finished().count(), "un caso eseguito");
        assertEquals(1, eventi.failed().count(), "il caso doveva risultare fallito");
        Event e = eventi.failed().list().get(0);
        TestExecutionResult esito = e.getRequiredPayload(TestExecutionResult.class);
        String messaggio = esito.getThrowable().orElseThrow().getMessage();
        System.out.println("[fallimento-atteso] " + messaggio);
        return messaggio;
    }

    private static Path ricevuta(Path ricevute, String metodo) {
        return ricevute.resolve(Campione.class.getName() + "#" + metodo + ".ricevuta");
    }

    @Test
    void corpoCheFallisceComeDichiaratoRiesceConRicevuta() throws IOException {
        Path ricevute = tmp.resolve("ricevute");
        Events eventi = esegui("fallisceComeDichiarato", elenco(riga("fallisceComeDichiarato", 999, CAMPIONE)), ricevute);
        assertEquals(1, eventi.succeeded().count(), "il caso doveva risultare riuscito");
        assertEquals(0, eventi.failed().count());
        List<String> righe = Files.readAllLines(ricevuta(ricevute, "fallisceComeDichiarato"), StandardCharsets.UTF_8);
        assertEquals("caso=" + Campione.class.getName() + "#fallisceComeDichiarato", righe.get(0));
        assertEquals("issue=999", righe.get(1));
        assertEquals("motivo=" + CAMPIONE, righe.get(2));
        assertEquals("corsa=corsa-di-prova", righe.get(3));
    }

    @Test
    void corpoCheFallissePerUnAltroMotivoRisultaFallitoSenzaRicevuta() throws IOException {
        Path ricevute = tmp.resolve("ricevute");
        String m = fallitoCon(esegui("fallissePerAltro", elenco(riga("fallissePerAltro", 999, CAMPIONE)), ricevute));
        assertEquals("FALLIMENTO-ATTESO-MOTIVO-DIVERSO: " + C + "#fallissePerAltro doveva fallire per 'motivo-campione'"
                + " ed e' fallito per un altro motivo: java.lang.IllegalStateException: errore del database simulato", m);
        m = fallitoCon(esegui("fallissePerUnAltroMotivoDichiarato",
                elenco(riga("fallissePerUnAltroMotivoDichiarato", 999, CAMPIONE)), ricevute));
        assertEquals("FALLIMENTO-ATTESO-MOTIVO-DIVERSO: " + C + "#fallissePerUnAltroMotivoDichiarato doveva fallire per"
                + " 'motivo-campione' ed e' fallito per 'altro-motivo'", m);
        assertFalse(Files.exists(ricevute), "nessuna ricevuta per un motivo diverso");
    }

    @Test
    void corpoCheRiesceRisultaFallitoConLaRichiestaDiTogliereLaMarcatura() throws IOException {
        Path ricevute = tmp.resolve("ricevute");
        String m = fallitoCon(esegui("riesce", elenco(riga("riesce", 999, CAMPIONE)), ricevute));
        assertEquals("FALLIMENTO-ATTESO-RIUSCITO: " + C + "#riesce ora riesce: togliere la marcatura @FallimentoAtteso"
                + " e la sua riga da quality/fallimenti-attesi.tsv (issue 999)", m);
        assertFalse(Files.exists(ricevute));
    }

    @Test
    void casoMarcatoSenzaRigaOConRigaDiversaRisultaFallito() throws IOException {
        Path ricevute = tmp.resolve("ricevute");
        String m = fallitoCon(esegui("fallisceComeDichiarato", elenco(riga("riesce", 999, CAMPIONE)), ricevute));
        assertEquals("FALLIMENTO-ATTESO-NON-IN-ELENCO: " + C + "#fallisceComeDichiarato e' marcato @FallimentoAtteso"
                + " ma non ha la sua riga in quality/fallimenti-attesi.tsv", m);
        m = fallitoCon(esegui("fallisceComeDichiarato", elenco(riga("fallisceComeDichiarato", 998, CAMPIONE)), ricevute));
        assertEquals("FALLIMENTO-ATTESO-DIVERSO-DALL-ELENCO: " + C + "#fallisceComeDichiarato: marcatura issue=999"
                + " motivo=motivo-campione, elenco issue=998 motivo=motivo-campione", m);
        m = fallitoCon(esegui("fallisceComeDichiarato", elenco(riga("fallisceComeDichiarato", 999, "altro")), ricevute));
        assertEquals("FALLIMENTO-ATTESO-DIVERSO-DALL-ELENCO: " + C + "#fallisceComeDichiarato: marcatura issue=999"
                + " motivo=motivo-campione, elenco issue=999 motivo=altro", m);
        assertFalse(Files.exists(ricevute));
    }

    @Test
    void elencoDelProgettoBenFormato() throws IOException {
        Path elenco = Path.of(System.getProperty(FallimentoAttesoEstensione.ELENCO));
        for (FallimentoAttesoEstensione.Riga r : FallimentoAttesoEstensione.leggiElenco(elenco)) {
            assertFalse(r.classe().contains("$"), "riga dell'elenco su una classe annidata: " + r);
        }
    }
}
