package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import io.github.ltoscano.carddemo.domain.FieldCategory;
import io.github.ltoscano.carddemo.domain.FieldPicture;
import io.github.ltoscano.carddemo.domain.GnuCobolFieldCodec;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Appoggio ai test del caricamento dei conti (issue #60), indipendente dal caricatore: il tracciato
 * si legge dal contratto dati nel repository ({@code CVACT01Y.ACCOUNT-RECORD.tsv}, proprieta'
 * {@code menb.contratto.account}), non dalla tabella {@code CampoConto} del caricatore.
 *
 * <ul>
 *   <li>{@link #tracciato()}: i campi elementari del contratto, con la {@code PICTURE} normalizzata e
 *       la categoria ricavate qui da {@code pic}, {@code usage} e {@code segno};</li>
 *   <li>{@link #record}: costruisce un record di 300 byte da valori, con {@code encode} del codec;</li>
 *   <li>{@link #verificaCorrispondenza}: i controlli 1-4 della specifica tra un file e la tabella.
 *       Il ritorno al formato fisso ricompone i record con {@code encode} dalle righe lette via
 *       JDBC; chiavi e totali si ricavano dai byte del file con una lettura scritta qui, che non usa
 *       ne' il caricatore ne' la decodifica del codec.</li>
 * </ul>
 */
final class ContiDiProva {

    /** File dei conti che legge l'oracle (#53), letto dal repository; percorso passato dal POM. */
    static final String PROPRIETA_FILE = "menb.dati.acctfile";
    static final int LUNGHEZZA_RECORD = 300;
    static final int RECORD_DI_ESEMPIO = 50;

    private static final Pattern RIPETIZIONE = Pattern.compile("([X9])\\(([0-9]{1,6})\\)");
    private static final Pattern ALFANUMERICO = Pattern.compile("X+");
    private static final Pattern NUMERICO = Pattern.compile("(S?)(9+)(?:V(9+))?");
    private static final HexFormat HEX = HexFormat.of();
    /** Ultimo byte di un DISPLAY con segno nel profilo dell'oracle: { A..I positivi 0-9, } J..R negativi 0-9. */
    private static final String POSITIVI = "{ABCDEFGHI";
    private static final String NEGATIVI = "}JKLMNOPQR";

    private ContiDiProva() {
    }

    /** Campo elementare del contratto, con geometria ricavata nel test. */
    record Campo(String campo, int offset, int lunghezza, FieldCategory categoria, String picture, String colonna,
            int intere, int decimali) {

        FieldPicture geometria() {
            return FieldPicture.of(categoria, picture);
        }

        boolean filler() {
            return "FILLER".equals(campo);
        }

        boolean numerico() {
            return categoria != FieldCategory.ALPHANUMERIC;
        }
    }

    /** Campi elementari del contratto, FILLER compreso, nell'ordine del file. */
    static List<Campo> tracciato() throws Exception {
        Path contratto = AccountContrattoTest.fileContratto();
        List<String> righe = Files.readAllLines(contratto, StandardCharsets.UTF_8);
        assertFalse(righe.isEmpty(), "contratto vuoto: " + contratto);
        List<String> intestazione = Arrays.asList(righe.get(0).split("\t", -1));
        int campo = AccountContrattoTest.colonna(intestazione, "campo");
        int tipo = AccountContrattoTest.colonna(intestazione, "tipo");
        int pic = AccountContrattoTest.colonna(intestazione, "pic");
        int usage = AccountContrattoTest.colonna(intestazione, "usage");
        int segno = AccountContrattoTest.colonna(intestazione, "segno");
        int offset = AccountContrattoTest.colonna(intestazione, "offset");
        int lunghezza = AccountContrattoTest.colonna(intestazione, "lunghezza");
        int intere = AccountContrattoTest.colonna(intestazione, "cifre_intere");
        int decimali = AccountContrattoTest.colonna(intestazione, "cifre_decimali");
        List<Campo> out = new ArrayList<>();
        for (int i = 1; i < righe.size(); i++) {
            String[] v = righe.get(i).split("\t", -1);
            assertEquals(intestazione.size(), v.length, "colonne della riga " + (i + 1) + " del contratto");
            if (!"elementare".equals(v[tipo])) {
                continue;
            }
            assertEquals("DISPLAY", v[usage], "riga " + (i + 1) + ": USAGE non coperto");
            String[] geometria = normalizza(v[pic], v[segno], i + 1);
            String nome = v[campo];
            out.add(new Campo(nome, Integer.parseInt(v[offset]), Integer.parseInt(v[lunghezza]),
                    FieldCategory.valueOf(geometria[0]), geometria[1],
                    "FILLER".equals(nome) ? null : nome.toLowerCase(Locale.ROOT).replace('-', '_'),
                    "-".equals(v[intere]) ? 0 : Integer.parseInt(v[intere]),
                    "-".equals(v[decimali]) ? 0 : Integer.parseInt(v[decimali])));
        }
        assertFalse(out.isEmpty(), "nessun campo elementare nel contratto");
        return out;
    }

    /** Categoria e PICTURE normalizzata ({@code X(n)}, {@code 9(i)}, {@code S9(i)V9(d)}) dalla PICTURE del contratto. */
    static String[] normalizza(String picture, String segno, int riga) {
        Matcher m = RIPETIZIONE.matcher(picture);
        StringBuilder espansa = new StringBuilder();
        while (m.find()) {
            m.appendReplacement(espansa, m.group(1).repeat(Integer.parseInt(m.group(2))));
        }
        m.appendTail(espansa);
        String e = espansa.toString();
        if (ALFANUMERICO.matcher(e).matches()) {
            assertEquals("-", segno, "riga " + riga + ": segno di un alfanumerico");
            return new String[] {"ALPHANUMERIC", "X(" + e.length() + ")"};
        }
        Matcher n = NUMERICO.matcher(e);
        if (!n.matches()) {
            fail("riga " + riga + ": PICTURE " + picture + " non coperta");
        }
        boolean conSegno = "S".equals(n.group(1));
        assertEquals(conSegno ? "S" : "-", segno, "riga " + riga + ": colonna segno del contratto");
        String norm = (conSegno ? "S" : "") + "9(" + n.group(2).length() + ")"
                + (n.group(3) == null ? "" : "V9(" + n.group(3).length() + ")");
        return new String[] {conSegno ? "DISPLAY_SIGNED" : "DISPLAY_UNSIGNED", norm};
    }

    /** Il file dei conti di esempio, dal repository. */
    static Path fileDiEsempio() {
        String valore = System.getProperty(PROPRIETA_FILE);
        if (valore == null || valore.isBlank()) {
            fail("proprieta' di sistema " + PROPRIETA_FILE + " non impostata");
        }
        Path p = Path.of(valore);
        assertTrue(Files.isRegularFile(p), "file dei conti non trovato: " + p);
        return p;
    }

    /**
     * Record di 300 byte dai valori per colonna ({@link BigDecimal} per i numeri, {@link String} di
     * lunghezza piena per i testi), con {@code encode} del codec e il FILLER di spazi.
     */
    static byte[] record(List<Campo> tracciato, Map<String, Object> valori) {
        byte[] out = new byte[LUNGHEZZA_RECORD];
        Arrays.fill(out, (byte) ' ');
        for (Campo c : tracciato) {
            if (c.filler()) {
                continue;
            }
            Object v = valori.get(c.colonna());
            assertTrue(v != null, "valore mancante per " + c.colonna());
            byte[] b = c.numerico() ? GnuCobolFieldCodec.encode(c.geometria(), (BigDecimal) v)
                    : GnuCobolFieldCodec.encode(c.geometria(), (String) v);
            assertEquals(c.lunghezza(), b.length, "lunghezza codificata di " + c.campo());
            if (!c.numerico()) {
                assertEquals(c.lunghezza(), ((String) v).length(), "testo di lunghezza piena per " + c.campo());
            }
            System.arraycopy(b, 0, out, c.offset(), b.length);
        }
        return out;
    }

    static byte[] unisci(byte[]... record) {
        byte[] out = new byte[record.length * LUNGHEZZA_RECORD];
        for (int i = 0; i < record.length; i++) {
            assertEquals(LUNGHEZZA_RECORD, record[i].length, "lunghezza del record " + (i + 1));
            System.arraycopy(record[i], 0, out, i * LUNGHEZZA_RECORD, LUNGHEZZA_RECORD);
        }
        return out;
    }

    /**
     * La connessione, con un intermediario che registra in {@code legati}, nell'ordine, ogni
     * {@link BigDecimal} passato a {@code setBigDecimal} dei {@link PreparedStatement} che crea:
     * i parametri effettivamente consegnati al driver, prima che PostgreSQL arrotondi.
     */
    static Connection registraImporti(Connection c, List<BigDecimal> legati) {
        return (Connection) Proxy.newProxyInstance(ContiDiProva.class.getClassLoader(), new Class<?>[] {Connection.class},
                (proxy, metodo, argomenti) -> {
                    Object risultato = inoltra(c, metodo, argomenti);
                    if (risultato instanceof PreparedStatement ps && "prepareStatement".equals(metodo.getName())) {
                        return Proxy.newProxyInstance(ContiDiProva.class.getClassLoader(),
                                new Class<?>[] {PreparedStatement.class}, (p, m, a) -> {
                                    if ("setBigDecimal".equals(m.getName())) {
                                        legati.add((BigDecimal) a[1]);
                                    }
                                    return inoltra(ps, m, a);
                                });
                    }
                    return risultato;
                });
    }

    private static Object inoltra(Object bersaglio, Method metodo, Object[] argomenti) throws Throwable {
        try {
            return metodo.invoke(bersaglio, argomenti);
        } catch (InvocationTargetException e) {
            throw e.getCause();
        }
    }

    /**
     * Controllo 6: gli importi e le chiavi consegnati al driver ({@link #registraImporti}) sono, record
     * per record e nell'ordine delle colonne numeriche del contratto, i valori letti dai byte del file
     * con la lettura scritta qui, con la stessa scala ({@code equals}, non {@code compareTo}).
     */
    static void verificaParametri(String nome, byte[] file, List<BigDecimal> legati) throws Exception {
        List<BigDecimal> attesi = new ArrayList<>();
        for (int r = 0; r < file.length / LUNGHEZZA_RECORD; r++) {
            for (Campo campo : tracciato()) {
                if (campo.numerico()) {
                    attesi.add(leggiDisplay(file, r * LUNGHEZZA_RECORD, campo));
                }
            }
        }
        assertEquals(attesi.size(), legati.size(), nome + ": numero dei parametri numerici consegnati al driver");
        for (int i = 0; i < attesi.size(); i++) {
            BigDecimal atteso = attesi.get(i);
            BigDecimal legato = legati.get(i);
            assertEquals(atteso, legato, nome + ": parametro numerico " + (i + 1) + " consegnato al driver (valore e scala:"
                    + " atteso " + atteso.toPlainString() + " scala " + atteso.scale() + ", consegnato "
                    + (legato == null ? "null" : legato.toPlainString() + " scala " + legato.scale()) + ")");
        }
    }

    static long righe(Connection c) throws Exception {
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery("select count(*) from account")) {
            assertTrue(rs.next());
            return rs.getLong(1);
        }
    }

    /**
     * Controlli 1-4 della specifica tra il file e la tabella:
     * <ol>
     *   <li>righe = record e insieme delle chiavi uguale;</li>
     *   <li>ritorno al formato fisso: ogni riga, letta con {@code ORDER BY acct_id}, ricomposta con
     *       {@code encode} e 178 spazi di FILLER, e' uguale byte per byte al record del file;</li>
     *   <li>somma di ogni colonna numerica = somma dai byte del file (lettura scritta qui);</li>
     *   <li>sequenza delle chiavi con {@code ORDER BY acct_id} = sequenza del file.</li>
     * </ol>
     */
    static void verificaCorrispondenza(String nome, byte[] file, Connection c) throws Exception {
        List<Campo> tracciato = tracciato();
        assertEquals(0, file.length % LUNGHEZZA_RECORD, nome + ": dimensione del file");
        int record = file.length / LUNGHEZZA_RECORD;
        Campo chiave = tracciato.get(0);
        assertEquals("acct_id", chiave.colonna(), "primo campo del contratto");

        // 1. righe e chiavi; 4. ordine
        List<BigDecimal> chiaviFile = new ArrayList<>();
        for (int r = 0; r < record; r++) {
            chiaviFile.add(leggiDisplay(file, r * LUNGHEZZA_RECORD, chiave));
        }
        assertEquals(record, righe(c), nome + ": numero di righe diverso dal numero di record");
        List<BigDecimal> chiaviTabella = new ArrayList<>();
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery("select acct_id from account order by acct_id")) {
            while (rs.next()) {
                chiaviTabella.add(rs.getBigDecimal(1));
            }
        }
        assertEquals(new LinkedHashSet<>(chiaviFile).size(), chiaviFile.size(), nome + ": chiavi duplicate nel file");
        assertEquals(new HashSet<>(chiaviFile), new HashSet<>(chiaviTabella),
                nome + ": insieme delle chiavi diverso");
        assertEquals(chiaviFile, chiaviTabella, nome + ": sequenza delle chiavi (ORDER BY acct_id) diversa da quella del file");

        // 2. ritorno al formato fisso
        StringBuilder colonne = new StringBuilder();
        for (Campo campo : tracciato) {
            if (!campo.filler()) {
                colonne.append(colonne.length() == 0 ? "" : ", ").append(campo.colonna());
            }
        }
        int r = 0;
        try (PreparedStatement st = c.prepareStatement("select " + colonne + " from account order by acct_id");
                ResultSet rs = st.executeQuery()) {
            while (rs.next()) {
                assertTrue(r < record, nome + ": piu' righe che record");
                byte[] ricomposto = new byte[LUNGHEZZA_RECORD];
                for (Campo campo : tracciato) {
                    byte[] b;
                    if (campo.filler()) {
                        b = new byte[campo.lunghezza()];
                        Arrays.fill(b, (byte) ' ');
                    } else if (campo.numerico()) {
                        b = GnuCobolFieldCodec.encode(campo.geometria(), rs.getBigDecimal(campo.colonna()));
                    } else {
                        b = GnuCobolFieldCodec.encode(campo.geometria(), rs.getString(campo.colonna()));
                    }
                    assertEquals(campo.lunghezza(), b.length, nome + ": lunghezza ricomposta di " + campo.campo());
                    System.arraycopy(b, 0, ricomposto, campo.offset(), b.length);
                }
                byte[] atteso = Arrays.copyOfRange(file, r * LUNGHEZZA_RECORD, (r + 1) * LUNGHEZZA_RECORD);
                if (!Arrays.equals(atteso, ricomposto)) {
                    int i = Arrays.mismatch(atteso, ricomposto);
                    String dove = "?";
                    for (Campo campo : tracciato) {
                        if (i >= campo.offset() && i < campo.offset() + campo.lunghezza()) {
                            dove = campo.campo();
                        }
                    }
                    assertArrayEquals(atteso, ricomposto, nome + ": record " + (r + 1) + " ricomposto diverso dal file"
                            + " all'offset " + i + " del record (campo " + dove + "): file "
                            + HEX.formatHex(atteso) + ", ricomposto " + HEX.formatHex(ricomposto));
                }
                r++;
            }
        }
        assertEquals(record, r, nome + ": righe ricomposte");

        // 3. totali di controllo
        for (Campo campo : tracciato) {
            if (!campo.numerico()) {
                continue;
            }
            BigDecimal dalFile = BigDecimal.ZERO.setScale(campo.decimali());
            for (int k = 0; k < record; k++) {
                dalFile = dalFile.add(leggiDisplay(file, k * LUNGHEZZA_RECORD, campo));
            }
            BigDecimal dallaTabella;
            try (Statement st = c.createStatement();
                    ResultSet rs = st.executeQuery("select sum(" + campo.colonna() + ") from account")) {
                assertTrue(rs.next());
                // Tabella vuota: la somma e' NULL; il totale atteso e' lo zero alla scala della colonna.
                dallaTabella = rs.getBigDecimal(1) == null ? BigDecimal.ZERO.setScale(campo.decimali()) : rs.getBigDecimal(1);
            }
            assertEquals(dalFile, dallaTabella, nome + ": totale della colonna " + campo.colonna());
        }
        System.out.println("[caricamento] " + nome + ": " + record + " record, righe, chiavi, ordine, ritorno al formato"
                + " fisso e totali coincidono");
    }

    /**
     * Lettura indipendente di un campo DISPLAY dai byte del file (non usa il codec): cifre ASCII, e
     * per un campo con segno l'ultimo byte in {@code { A..I} (positivo) o {@code } J..R} (negativo).
     * Un byte fuori da queste regole fa fallire il test.
     */
    static BigDecimal leggiDisplay(byte[] file, int base, Campo campo) {
        boolean conSegno = campo.categoria() == FieldCategory.DISPLAY_SIGNED;
        assertTrue(conSegno || campo.categoria() == FieldCategory.DISPLAY_UNSIGNED, "non DISPLAY: " + campo.campo());
        StringBuilder cifre = new StringBuilder();
        boolean negativo = false;
        for (int i = 0; i < campo.lunghezza(); i++) {
            char ch = (char) (file[base + campo.offset() + i] & 0xFF);
            boolean ultimo = i == campo.lunghezza() - 1;
            if (ch >= '0' && ch <= '9') {
                cifre.append(ch);
            } else if (conSegno && ultimo && POSITIVI.indexOf(ch) >= 0) {
                cifre.append((char) ('0' + POSITIVI.indexOf(ch)));
            } else if (conSegno && ultimo && NEGATIVI.indexOf(ch) >= 0) {
                cifre.append((char) ('0' + NEGATIVI.indexOf(ch)));
                negativo = true;
            } else {
                fail("byte " + Integer.toHexString(ch) + " non DISPLAY in " + campo.campo() + " all'offset " + (base + campo.offset() + i));
            }
        }
        BigInteger n = new BigInteger(cifre.toString());
        return new BigDecimal(negativo ? n.negate() : n, campo.decimali());
    }
}
