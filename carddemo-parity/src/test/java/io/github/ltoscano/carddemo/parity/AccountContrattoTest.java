package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Controllo 2 di #59: corrispondenza tra la tabella {@code account} prodotta dalla migrazione e il
 * contratto dati del record {@code ACCOUNT-RECORD} di #3, letto dal repository (non copiato):
 * {@code docs/legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv}, percorso passato
 * dal POM come proprieta' di sistema {@code menb.contratto.account}.
 *
 * <p>Per ogni riga elementare del contratto diversa dal {@code FILLER} deve esistere, nello stesso
 * ordine, una colonna con il nome del campo (minuscolo, {@code -} diventa {@code _}) e il tipo dato
 * dalla regola scritta qui, indipendente dalle attese di {@link AccountSchemaTest}:
 * {@code X(n)} → {@code character(n)}; {@code 9(n)} → {@code numeric(n,0)};
 * {@code S9(i)V9(d)} → {@code numeric(i+d,d)} (le ripetizioni {@code 9(k)} e {@code 99...} si
 * espandono prima). Nessuna colonna in piu'. Una {@code PICTURE} o un {@code USAGE} che la regola
 * non copre fanno fallire il test.
 */
class AccountContrattoTest {

    static final String PROPRIETA_CONTRATTO = "menb.contratto.account";

    /** Ripetizione {@code X(n)} o {@code 9(n)}, con eventuali zeri iniziali ({@code X(01)} nel contratto). */
    static final Pattern RIPETIZIONE = Pattern.compile("([X9])\\(([0-9]{1,6})\\)");
    static final Pattern ALFANUMERICO = Pattern.compile("X+");
    static final Pattern NUMERICO = Pattern.compile("(S?)(9+)(?:V(9+))?");

    @Test
    void ogniCampoElementareDelContrattoHaLaSuaColonnaENessunaInPiu() throws Exception {
        List<String> attese = colonneDalContratto(fileContratto());
        assertFalse(attese.isEmpty(), "nessun campo elementare nel contratto");
        System.out.println("[contratto] colonne attese dal contratto: " + attese);

        List<String> lette;
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            PostgresDiProva.migraDaVuoto(postgres);
            try (Connection c = PostgresDiProva.connessione(postgres)) {
                lette = new ArrayList<>();
                for (String r : PostgresDiProva.righe(c, "select column_name, data_type, character_maximum_length,"
                        + " numeric_precision, numeric_scale from information_schema.columns"
                        + " where table_schema = 'public' and table_name = 'account' order by ordinal_position")) {
                    String[] v = r.split("\\|", -1);
                    switch (v[1]) {
                        case "character" -> lette.add(v[0] + " character(" + v[2] + ")");
                        case "numeric" -> lette.add(v[0] + " numeric(" + v[3] + "," + v[4] + ")");
                        default -> lette.add(v[0] + " " + v[1] + "(tipo fuori dalla regola)");
                    }
                }
            }
        }
        System.out.println("[contratto] colonne lette dal database: " + lette);

        Set<String> mancanti = new LinkedHashSet<>(attese);
        lette.forEach(mancanti::remove);
        Set<String> inPiu = new LinkedHashSet<>(lette);
        attese.forEach(inPiu::remove);
        assertTrue(mancanti.isEmpty(), "campi del contratto senza colonna corrispondente (nome e tipo): " + mancanti);
        assertTrue(inPiu.isEmpty(), "colonne senza campo corrispondente nel contratto: " + inPiu);
        assertEquals(attese, lette, "ordine delle colonne diverso da quello del contratto");
    }

    /** Percorso del contratto, passato dal POM; nessun ripiego. */
    static Path fileContratto() {
        String valore = System.getProperty(PROPRIETA_CONTRATTO);
        if (valore == null || valore.isBlank()) {
            fail("proprieta' di sistema " + PROPRIETA_CONTRATTO + " non impostata");
        }
        Path p = Path.of(valore);
        assertTrue(Files.isRegularFile(p), "contratto non trovato: " + p);
        return p;
    }

    /** "nome tipo" per ogni riga elementare non FILLER del contratto, nell'ordine del file. */
    static List<String> colonneDalContratto(Path contratto) throws Exception {
        List<String> righe = Files.readAllLines(contratto, StandardCharsets.UTF_8);
        assertFalse(righe.isEmpty(), "contratto vuoto: " + contratto);
        List<String> intestazione = Arrays.asList(righe.get(0).split("\t", -1));
        int campo = colonna(intestazione, "campo");
        int tipo = colonna(intestazione, "tipo");
        int pic = colonna(intestazione, "pic");
        int usage = colonna(intestazione, "usage");
        int intere = colonna(intestazione, "cifre_intere");
        int decimali = colonna(intestazione, "cifre_decimali");
        int lunghezza = colonna(intestazione, "lunghezza");
        List<String> out = new ArrayList<>();
        for (int i = 1; i < righe.size(); i++) {
            String[] v = righe.get(i).split("\t", -1);
            if (v.length != intestazione.size()) {
                fail("riga " + (i + 1) + " del contratto con " + v.length + " colonne, attese " + intestazione.size());
            }
            if (!"elementare".equals(v[tipo]) || "FILLER".equals(v[campo])) {
                continue;
            }
            if (!"DISPLAY".equals(v[usage])) {
                fail("riga " + (i + 1) + ": USAGE " + v[usage] + " non coperto dalla regola");
            }
            out.add(v[campo].toLowerCase(Locale.ROOT).replace('-', '_') + " "
                    + tipoDallaPicture(v[pic], v[intere], v[decimali], v[lunghezza], i + 1));
        }
        return out;
    }

    /** Regola dei tipi; controlla anche che cifre e lunghezza del contratto concordino con la PICTURE. */
    static String tipoDallaPicture(String picture, String intere, String decimali, String lunghezza, int riga) {
        Matcher m = RIPETIZIONE.matcher(picture);
        StringBuilder espansa = new StringBuilder();
        while (m.find()) {
            m.appendReplacement(espansa, m.group(1).repeat(Integer.parseInt(m.group(2))));
        }
        m.appendTail(espansa);
        String e = espansa.toString();
        if (ALFANUMERICO.matcher(e).matches()) {
            assertEquals(String.valueOf(e.length()), lunghezza, "riga " + riga + ": lunghezza di " + picture);
            return "character(" + e.length() + ")";
        }
        Matcher n = NUMERICO.matcher(e);
        if (n.matches()) {
            int i = n.group(2).length();
            int d = n.group(3) == null ? 0 : n.group(3).length();
            assertEquals(String.valueOf(i), intere, "riga " + riga + ": cifre intere di " + picture);
            assertEquals(String.valueOf(d), decimali, "riga " + riga + ": cifre decimali di " + picture);
            assertEquals(String.valueOf(i + d), lunghezza, "riga " + riga + ": lunghezza di " + picture);
            return "numeric(" + (i + d) + "," + d + ")";
        }
        fail("riga " + riga + ": PICTURE " + picture + " non coperta dalla regola");
        return null;
    }

    static int colonna(List<String> intestazione, String nome) {
        int i = intestazione.indexOf(nome);
        assertTrue(i >= 0, "colonna " + nome + " assente dall'intestazione del contratto: " + intestazione);
        return i;
    }
}
