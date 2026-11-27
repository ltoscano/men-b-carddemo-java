import java.io.File;
import java.util.ArrayList;
import java.util.List;
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
 */
public class RapportoSurefire {

    static final String PROPRIETA_CORSA = "menb.verify.run";
    static final String[] ESITI_NEGATIVI = {
        "skipped", "failure", "error", "rerunFailure", "rerunError", "flakyFailure", "flakyError"
    };

    public static void main(String[] args) {
        if (args.length != 4 || args[1].isBlank()) {
            errore("uso: RapportoSurefire <rapporto> <corsa> <classe> <metodo>");
        }
        String rapporto = args[0];
        String corsa = args[1];
        String classe = args[2];
        String metodo = args[3];

        Document doc;
        try {
            DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
            f.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
            f.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            f.setNamespaceAware(false);
            DocumentBuilder b = f.newDocumentBuilder();
            doc = b.parse(new File(rapporto));
        } catch (Exception e) {
            errore("rapporto " + rapporto + " non leggibile o non e' XML ben formato e completo: " + e.getMessage());
            return;
        }

        Element suite = doc.getDocumentElement();
        if (!"testsuite".equals(suite.getTagName())) {
            errore("radice del rapporto '" + suite.getTagName() + "', attesa 'testsuite'");
        }
        if (!classe.equals(suite.getAttribute("name"))) {
            errore("testsuite '" + suite.getAttribute("name") + "', atteso '" + classe + "'");
        }

        // Appartenenza alla corsa corrente: proprieta' registrata da surefire per questa build.
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
            for (String negativo : ESITI_NEGATIVI) {
                if (!figli(c, negativo).isEmpty()) {
                    errore("testcase " + c.getAttribute("name") + " con esito '" + negativo + "'");
                }
            }
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
