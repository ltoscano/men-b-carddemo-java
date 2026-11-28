import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

/**
 * Controllo del rapporto XML di surefire di un test, eseguito da verify.sh dentro il container
 * di build con il lanciatore di sorgenti del JDK:
 *
 * <pre>java quality/RapportoSurefire.java &lt;rapporto&gt; &lt;corsa&gt; &lt;classe&gt; &lt;metodo&gt;</pre>
 *
 * Esce con 0 solo se il rapporto e' un XML ben formato e completo (lo legge per intero il parser
 * del JDK), la radice e' il testsuite della classe attesa, la proprieta' menb.verify.run vale
 * l'identificativo della corsa corrente (quindi il rapporto e' di questa build), gli attributi
 * tests/skipped/failures/errors sono coerenti (tests uguale al numero di testcase, gli altri 0)
 * e il caso di test atteso compare senza skipped, failure, error o riesecuzioni. Altrimenti
 * stampa il motivo su stderr ed esce con 1.
 *
 * <p>Seconda forma, per i test dinamici (test dei vettori del codec, issue #54):
 *
 * <pre>java quality/RapportoSurefire.java &lt;rapporto&gt; &lt;corsa&gt; &lt;classe&gt; &lt;fabbrica&gt;=&lt;casi&gt;@&lt;file&gt; ...</pre>
 *
 * Stesse condizioni, ma i testcase devono essere esattamente {@code <fabbrica>()[1..casi]} per
 * ogni fabbrica dichiarata, ognuno con l'identificativo del vettore corrispondente del file, e i
 * saltati si controllano prima della corsa (vedi {@link #fabbriche}).
 */
public class RapportoSurefire {

    static final String PROPRIETA_CORSA = "menb.verify.run";
    static final String[] ESITI_NEGATIVI = {
        "skipped", "failure", "error", "rerunFailure", "rerunError", "flakyFailure", "flakyError"
    };

    public static void main(String[] args) {
        if (args.length >= 4 && args[3].contains("=")) {
            fabbriche(args);
            return;
        }
        if (args.length != 4 || args[1].isBlank()) {
            errore("uso: RapportoSurefire <rapporto> <corsa> <classe> <metodo>\n"
                    + "   oppure: RapportoSurefire <rapporto> <corsa> <classe> <fabbrica>=<casi>@<file> [...]");
        }
        String rapporto = args[0];
        String corsa = args[1];
        String classe = args[2];
        String metodo = args[3];

        Element suite = leggi(rapporto, classe);

        // Appartenenza alla corsa corrente: proprieta' registrata da surefire per questa build.
        corsaCorrente(suite, corsa);

        int tests = intero(suite, "tests");
        int skipped = intero(suite, "skipped");
        int failures = intero(suite, "failures");
        int errors = intero(suite, "errors");
        List<Element> casi = figli(suite, "testcase");
        if (tests < 1 || tests != casi.size()) {
            errore("tests=" + tests + " ma " + casi.size() + " testcase nel rapporto");
        }
        if (skipped != 0 || failures != 0 || errors != 0) {
            errore("skipped=" + skipped + " failures=" + failures + " errors=" + errors + " (attesi 0)");
        }

        Element atteso = null;
        for (Element c : casi) {
            esitoPositivo(c);
            if (classe.equals(c.getAttribute("classname")) && metodo.equals(c.getAttribute("name"))) {
                if (atteso != null) {
                    errore("testcase " + metodo + " ripetuto nel rapporto");
                }
                atteso = c;
            }
        }
        if (atteso == null) {
            errore("testcase " + classe + "." + metodo + " assente dal rapporto");
        }
        System.out.println(classe + "." + metodo + ": eseguito e riuscito; tests=" + tests
                + " skipped=0 failures=0 errors=0; " + PROPRIETA_CORSA + "=" + corsa);
    }

    /** Marcatore che il test dei vettori scrive su stdout dopo aver superato ogni controllo di un vettore. */
    static final String VERIFICATO = "VETTORE-VERIFICATO ";

    /**
     * Forma con le fabbriche di test dinamici (issue #54, test dei vettori del codec): ogni
     * argomento e' {@code <fabbrica>=<casi>@<file dei vettori>}. Dal file si ricavano gli
     * identificativi dei vettori, con la grammatica delle righe di {@code comune.py} (righe vuote
     * secondo {@code str.isspace} di Python e righe che iniziano con '#' ignorate, la prima riga
     * utile e' l'intestazione): {@code <nome del file>:<riga>:<prime 16 cifre esadecimali dello
     * SHA-256 della riga in UTF-8>}. Il file deve avere esattamente {@code casi} vettori; il rapporto
     * deve contenere esattamente i testcase {@code <fabbrica>()[1]} ... {@code <fabbrica>()[casi]},
     * e nessun altro; il k-esimo deve avere nel suo system-out una sola riga
     * {@code VETTORE-VERIFICATO <id>} con l'identificativo del k-esimo vettore del file. Si
     * controllano prima i saltati e il numero dei casi, poi gli identificativi, poi la corsa: un
     * test saltato perche' la proprieta' della corsa manca e' riportato come saltato.
     */
    static void fabbriche(String[] args) {
        String rapporto = args[0];
        String corsa = args[1];
        String classe = args[2];
        if (corsa.isBlank()) {
            errore("identificativo della corsa vuoto");
        }
        Map<String, String> attesi = new LinkedHashMap<>();
        StringBuilder riepilogo = new StringBuilder();
        for (int i = 3; i < args.length; i++) {
            Matcher m = Pattern.compile("([A-Za-z_][A-Za-z0-9_]*)=([1-9][0-9]{0,5})@(.+)").matcher(args[i]);
            if (!m.matches()) {
                errore("argomento non valido '" + args[i] + "': atteso <fabbrica>=<casi>@<file dei vettori>");
            }
            int n = Integer.parseInt(m.group(2));
            List<String> ids = identificativi(m.group(3));
            if (ids.size() != n) {
                errore(m.group(3) + ": " + ids.size() + " vettori nel file, attesi " + n);
            }
            for (int k = 1; k <= n; k++) {
                if (attesi.put(m.group(1) + "()[" + k + "]", ids.get(k - 1)) != null) {
                    errore("fabbrica " + m.group(1) + " ripetuta negli argomenti");
                }
            }
            riepilogo.append(' ').append(m.group(1)).append('=').append(n);
        }

        Element suite = leggi(rapporto, classe);
        int tests = intero(suite, "tests");
        int skipped = intero(suite, "skipped");
        int failures = intero(suite, "failures");
        int errors = intero(suite, "errors");
        List<Element> casi = figli(suite, "testcase");
        if (skipped != 0) {
            errore("test saltato: skipped=" + skipped + " (atteso 0; tests=" + tests + ")");
        }
        if (failures != 0 || errors != 0) {
            errore("failures=" + failures + " errors=" + errors + " (attesi 0)");
        }
        if (tests != attesi.size() || casi.size() != attesi.size()) {
            errore("tests=" + tests + " e " + casi.size() + " testcase nel rapporto, attesi " + attesi.size()
                    + " (" + riepilogo.toString().trim() + ")");
        }
        Set<String> visti = new LinkedHashSet<>();
        for (Element c : casi) {
            esitoPositivo(c);
            String nome = c.getAttribute("name");
            if (!classe.equals(c.getAttribute("classname")) || !attesi.containsKey(nome)) {
                errore("testcase inatteso: " + c.getAttribute("classname") + " " + nome);
            }
            if (!visti.add(nome)) {
                errore("testcase " + nome + " ripetuto nel rapporto");
            }
            List<String> marcatori = new ArrayList<>();
            for (Element out : figli(c, "system-out")) {
                for (String riga : out.getTextContent().split("\r?\n", -1)) {
                    if (riga.startsWith(VERIFICATO)) {
                        marcatori.add(riga.substring(VERIFICATO.length()));
                    }
                }
            }
            if (marcatori.size() != 1 || !marcatori.get(0).equals(attesi.get(nome))) {
                errore("testcase " + nome + ": vettore verificato " + marcatori + ", atteso [" + attesi.get(nome) + "]");
            }
        }
        corsaCorrente(suite, corsa);
        System.out.println(classe + ": eseguiti e riusciti" + riepilogo + ", ogni vettore verificato per identificativo"
                + " e nell'ordine del file; tests=" + tests + " skipped=0 failures=0 errors=0; " + PROPRIETA_CORSA + "=" + corsa);
    }

    /** Identificativi dei vettori di un file TSV, nell'ordine del file (vedi {@link #fabbriche}). */
    static List<String> identificativi(String percorso) {
        Path p = Path.of(percorso);
        List<String> righe;
        try {
            righe = Files.readAllLines(p, StandardCharsets.UTF_8);
        } catch (IOException e) {
            errore("file dei vettori " + percorso + " non leggibile: " + e);
            return List.of();
        }
        List<String> out = new ArrayList<>();
        boolean intestazione = true;
        for (int i = 0; i < righe.size(); i++) {
            String r = righe.get(i);
            if (r.codePoints().allMatch(RapportoSurefire::spazioPython) || r.startsWith("#")) {
                continue;
            }
            if (intestazione) {
                intestazione = false;
                continue;
            }
            try {
                byte[] h = MessageDigest.getInstance("SHA-256").digest(r.getBytes(StandardCharsets.UTF_8));
                out.add(p.getFileName() + ":" + (i + 1) + ":" + HexFormat.of().formatHex(h).substring(0, 16));
            } catch (NoSuchAlgorithmException e) {
                errore("SHA-256 non disponibile: " + e);
            }
        }
        return out;
    }

    /** {@code str.isspace} di Python per un carattere: categoria Zs, o classe bidirezionale WS, B o S. */
    static boolean spazioPython(int c) {
        byte d = Character.getDirectionality(c);
        return Character.getType(c) == Character.SPACE_SEPARATOR || d == Character.DIRECTIONALITY_WHITESPACE
                || d == Character.DIRECTIONALITY_PARAGRAPH_SEPARATOR || d == Character.DIRECTIONALITY_SEGMENT_SEPARATOR;
    }

    static Element leggi(String rapporto, String classe) {
        Document doc = null;
        try {
            DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
            f.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
            f.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            f.setNamespaceAware(false);
            DocumentBuilder b = f.newDocumentBuilder();
            doc = b.parse(new File(rapporto));
        } catch (Exception e) {
            errore("rapporto " + rapporto + " non leggibile o non e' XML ben formato e completo: " + e.getMessage());
            return null;
        }

        Element suite = doc.getDocumentElement();
        if (!"testsuite".equals(suite.getTagName())) {
            errore("radice del rapporto '" + suite.getTagName() + "', attesa 'testsuite'");
        }
        if (!classe.equals(suite.getAttribute("name"))) {
            errore("testsuite '" + suite.getAttribute("name") + "', atteso '" + classe + "'");
        }
        return suite;
    }

    /** La proprieta' menb.verify.run del rapporto deve valere l'identificativo della corsa. */
    static void corsaCorrente(Element suite, String corsa) {
        List<String> valori = new ArrayList<>();
        for (Element props : figli(suite, "properties")) {
            for (Element p : figli(props, "property")) {
                if (PROPRIETA_CORSA.equals(p.getAttribute("name"))) {
                    valori.add(p.getAttribute("value"));
                }
            }
        }
        if (valori.size() != 1 || !corsa.equals(valori.get(0))) {
            errore("il rapporto non e' della corsa corrente: " + PROPRIETA_CORSA + " = " + valori
                    + ", attesa '" + corsa + "'");
        }
    }

    /** Nessun esito negativo (saltato, fallito, in errore, rieseguito) nel testcase. */
    static void esitoPositivo(Element c) {
        for (String negativo : ESITI_NEGATIVI) {
            if (!figli(c, negativo).isEmpty()) {
                errore("testcase " + c.getAttribute("name") + " con esito '" + negativo + "'");
            }
        }
    }

    static List<Element> figli(Element padre, String nome) {
        List<Element> out = new ArrayList<>();
        NodeList nodi = padre.getChildNodes();
        for (int i = 0; i < nodi.getLength(); i++) {
            Node n = nodi.item(i);
            if (n instanceof Element e && nome.equals(e.getTagName())) {
                out.add(e);
            }
        }
        return out;
    }

    static int intero(Element e, String attributo) {
        String v = e.getAttribute(attributo);
        if (!v.matches("[0-9]{1,9}")) {
            errore("attributo " + attributo + "='" + v + "' assente o non numerico");
        }
        return Integer.parseInt(v);
    }

    static void errore(String messaggio) {
        System.err.println("ERRORE: " + messaggio);
        System.exit(1);
    }
}
