import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.StringReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.stream.Stream;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;

/**
 * Controllo dei rapporti di copertura (JaCoCo) e di analisi statica (SpotBugs), eseguito da
 * verify.sh dentro il container di build con il lanciatore di sorgenti del JDK, dopo Maven:
 *
 * <pre>java quality/RapportiQualita.java jacoco   &lt;radice&gt; &lt;corsa&gt;
 * java quality/RapportiQualita.java spotbugs &lt;radice&gt; &lt;corsa&gt; &lt;inizio-corsa-in-secondi-epoch&gt;</pre>
 *
 * I moduli e le loro classi non si leggono da un elenco: si ricavano dal contenuto della radice
 * in questa corsa (cartelle carddemo-* con pom.xml, classi compilate in target/classes).
 *
 * jacoco. Esce con 0 solo se: il rapporto aggregato (carddemo-parity/target/site/jacoco-aggregate/
 * jacoco.xml) e' un XML ben formato e completo e le sue sessioni portano tutte l'identificativo
 * della corsa; ogni modulo che ha eseguito test ha un file target/jacoco.exec ben formato le cui
 * sessioni portano l'identificativo della corsa (prova che l'agente era attivo in questa corsa
 * in quel modulo: la voce del modulo nel rapporto aggregato esiste anche con l'agente spento, a
 * copertura zero); ogni classe di produzione eseguibile compilata in questa corsa compare nel
 * gruppo del suo modulo, anche a copertura zero. Un modulo senza classi eseguibili (oggi domain e
 * loader hanno solo package-info) e' un'assenza lecita, distinta da un rapporto vuoto per errore.
 * Nessuna soglia di copertura.
 *
 * spotbugs. Esce con 0 solo se ogni modulo con codice di produzione (src/main/java) ha un rapporto
 * target/spotbugsXml.xml ben formato, prodotto dopo l'inizio di questa corsa, senza errori di
 * analisi, con zero difetti e con una voce per ogni classe compilata del modulo (analisi
 * effettiva, non solo l'intestazione del plugin nel log).
 *
 * Il rapporto JaCoCo contiene un DOCTYPE legittimo (report.dtd): lo si accetta senza alcun accesso
 * esterno (nessun DTD, nessuna entita' esterna, nessun XInclude).
 */
public class RapportiQualita {

    static final String RAPPORTO_JACOCO = "carddemo-parity/target/site/jacoco-aggregate/jacoco.xml";
    static final int VERSIONE_EXEC = 0x1007;
    static final List<String> ERRORI = new ArrayList<>();

    public static void main(String[] args) throws Exception {
        if (args.length == 3 && args[0].equals("jacoco")) {
            jacoco(Path.of(args[1]), corsa(args[2]));
        } else if (args.length == 4 && args[0].equals("spotbugs")) {
            spotbugs(Path.of(args[1]), corsa(args[2]), epoch(args[3]));
        } else {
            fatale("uso: RapportiQualita jacoco <radice> <corsa> | spotbugs <radice> <corsa> <inizio-epoch-secondi>");
        }
        if (!ERRORI.isEmpty()) {
            for (String e : ERRORI) {
                System.err.println("ERRORE: " + e);
            }
            System.exit(1);
        }
    }

    // ---- JaCoCo ---------------------------------------------------------------------------

    static void jacoco(Path radice, String corsa) throws IOException {
        List<Path> moduli = moduli(radice);
        TreeMap<String, Set<String>> attese = new TreeMap<>();
        TreeMap<String, Boolean> conTest = new TreeMap<>();
        int totaleAttese = 0;
        for (Path m : moduli) {
            String nome = m.getFileName().toString();
            Set<String> classi = new TreeSet<>();
            for (Classe c : classiCompilate(m)) {
                if (c.eseguibile) {
                    classi.add(c.nome);
                }
            }
            attese.put(nome, classi);
            totaleAttese += classi.size();
            conTest.put(nome, moduloEseguiTest(m, nome));
        }
        if (totaleAttese == 0) {
            errore("nessuna classe di produzione eseguibile compilata in questa corsa: elenco atteso non ricavabile");
        }

        // 1. prova dell'agente, modulo per modulo
        for (Path m : moduli) {
            String nome = m.getFileName().toString();
            if (!conTest.get(nome)) {
                System.out.println("JaCoCo " + nome + ": nessun test eseguito, agente non richiesto");
                continue;
            }
            Path exec = m.resolve("target/jacoco.exec");
            if (!Files.isRegularFile(exec)) {
                errore("agente JaCoCo non attivo in " + nome + ": file di esecuzione assente (" + exec + ")");
                continue;
            }
            try {
                List<String> sessioni = sessioniExec(exec);
                String sbagliata = sessioneNonDellaCorsa(sessioni, corsa);
                if (sessioni.isEmpty()) {
                    errore("agente JaCoCo non attivo in " + nome + ": nessuna sessione nel file di esecuzione " + exec);
                } else if (sbagliata != null) {
                    errore("agente JaCoCo di " + nome + ": sessione '" + sbagliata + "' non della corsa corrente '" + corsa + "'");
                } else {
                    System.out.println("JaCoCo " + nome + ": agente attivo in questa corsa (" + sessioni.size()
                            + " sessione/i " + corsa + ")");
                }
            } catch (IOException e) {
                errore("file di esecuzione JaCoCo di " + nome + " non leggibile o troncato: " + e);
            }
        }

        // 2. rapporto aggregato
        Path rapporto = radice.resolve(RAPPORTO_JACOCO);
        if (!Files.isRegularFile(rapporto)) {
            errore("rapporto JaCoCo assente: " + rapporto);
            return;
        }
        Document doc;
        try {
            doc = leggiXml(rapporto);
        } catch (Exception e) {
            errore("rapporto JaCoCo " + rapporto + " non leggibile o non e' XML ben formato e completo: " + e.getMessage());
            return;
        }
        Element radiceXml = doc.getDocumentElement();
        if (!"report".equals(radiceXml.getTagName())) {
            errore("radice del rapporto JaCoCo '" + radiceXml.getTagName() + "', attesa 'report'");
            return;
        }
        List<String> sessioni = new ArrayList<>();
        for (Element s : figli(radiceXml, "sessioninfo")) {
            sessioni.add(s.getAttribute("id"));
        }
        String sbagliata = sessioneNonDellaCorsa(sessioni, corsa);
        if (sessioni.isEmpty()) {
            errore("il rapporto JaCoCo non contiene sessioni: non e' di questa corsa");
        } else if (sbagliata != null) {
            errore("il rapporto JaCoCo non e' della corsa corrente: sessione '" + sbagliata + "', attesa '" + corsa + "'");
        }
        TreeMap<String, Set<String>> presenti = new TreeMap<>();
        for (Element g : figli(radiceXml, "group")) {
            Set<String> nomi = presenti.computeIfAbsent(g.getAttribute("name"), k -> new TreeSet<>());
            NodeList classi = g.getElementsByTagName("class");
            for (int i = 0; i < classi.getLength(); i++) {
                nomi.add(((Element) classi.item(i)).getAttribute("name"));
            }
        }
        int trovate = 0;
        for (var voce : attese.entrySet()) {
            String modulo = voce.getKey();
            Set<String> attesaModulo = voce.getValue();
            if (attesaModulo.isEmpty()) {
                System.out.println("JaCoCo " + modulo + ": nessuna classe eseguibile in questa corsa (assenza lecita)");
                continue;
            }
            Set<String> nelRapporto = presenti.get(modulo);
            if (nelRapporto == null || nelRapporto.isEmpty()) {
                errore("il modulo " + modulo + " ha " + attesaModulo.size()
                        + " classi eseguibili compilate ma manca dal rapporto JaCoCo");
                continue;
            }
            int mancanti = 0;
            for (String classe : attesaModulo) {
                if (!nelRapporto.contains(classe)) {
                    errore("classe " + classe.replace('/', '.') + " di " + modulo + " assente dal rapporto JaCoCo");
                    mancanti++;
                }
            }
            trovate += attesaModulo.size() - mancanti;
            System.out.println("JaCoCo " + modulo + ": " + (attesaModulo.size() - mancanti) + " di " + attesaModulo.size()
                    + " classi eseguibili presenti nel rapporto aggregato");
        }
        if (ERRORI.isEmpty()) {
            System.out.println("JaCoCo rapporto aggregato " + RAPPORTO_JACOCO + ": ben formato, corsa " + corsa + ", "
                    + trovate + " classi di produzione eseguibili tutte presenti");
        }
    }

    /** Sessioni di un file di esecuzione JaCoCo (formato binario: intestazione, sessioni, dati). */
    static List<String> sessioniExec(Path exec) throws IOException {
        List<String> sessioni = new ArrayList<>();
        try (DataInputStream in = new DataInputStream(new BufferedInputStream(Files.newInputStream(exec)))) {
            if (in.readUnsignedByte() != 0x01 || in.readChar() != 0xC0C0) {
                throw new IOException("intestazione non valida");
            }
            int versione = in.readChar();
            if (versione != VERSIONE_EXEC) {
                throw new IOException("versione del formato 0x" + Integer.toHexString(versione) + " non gestita");
            }
            int tipo;
            while ((tipo = in.read()) != -1) {
                if (tipo == 0x10) {
                    sessioni.add(in.readUTF());
                    in.readLong();
                    in.readLong();
                } else if (tipo == 0x11) {
                    in.readLong();
                    in.readUTF();
                    int lunghezza = 0;
                    int scatto = 0;
                    int b;
                    do {
                        b = in.readUnsignedByte();
                        lunghezza |= (b & 0x7f) << scatto;
                        scatto += 7;
                    } while ((b & 0x80) != 0 && scatto < 35);
                    byte[] sonde = in.readNBytes((lunghezza + 7) / 8);
                    if (sonde.length != (lunghezza + 7) / 8) {
                        throw new IOException("file troncato");
                    }
                } else {
                    throw new IOException("blocco di tipo 0x" + Integer.toHexString(tipo) + " sconosciuto");
                }
            }
        }
        return sessioni;
    }

    static String sessioneNonDellaCorsa(List<String> sessioni, String corsa) {
        for (String s : sessioni) {
            if (!corsa.equals(s)) {
                return s;
            }
        }
        return null;
    }

    /** Un modulo "esegue test" se ha rapporti di surefire in questa corsa; se ha sorgenti di test ma nessun rapporto e' un errore. */
    static boolean moduloEseguiTest(Path modulo, String nome) throws IOException {
        int rapporti = 0;
        Path reports = modulo.resolve("target/surefire-reports");
        if (Files.isDirectory(reports)) {
            try (Stream<Path> s = Files.list(reports)) {
                rapporti = (int) s.filter(p -> {
                    String n = p.getFileName().toString();
                    return n.startsWith("TEST-") && n.endsWith(".xml");
                }).count();
            }
        }
        int sorgentiDiTest = 0;
        Path src = modulo.resolve("src/test/java");
        if (Files.isDirectory(src)) {
            try (Stream<Path> s = Files.walk(src)) {
                sorgentiDiTest = (int) s.filter(p -> p.toString().endsWith(".java")).count();
            }
        }
        if (rapporti == 0 && sorgentiDiTest > 0) {
            errore("il modulo " + nome + " ha " + sorgentiDiTest + " sorgenti di test ma nessun rapporto di surefire in questa corsa");
        }
        return rapporti > 0;
    }

    // ---- SpotBugs -------------------------------------------------------------------------

    static void spotbugs(Path radice, String corsa, long inizioSecondi) throws IOException {
        int analizzati = 0;
        for (Path m : moduli(radice)) {
            String nome = m.getFileName().toString();
            if (!Files.isDirectory(m.resolve("src/main/java"))) {
                System.out.println("SpotBugs " + nome + ": nessun codice di produzione, non richiesto");
                continue;
            }
            analizzati++;
            Path rapporto = m.resolve("target/spotbugsXml.xml");
            if (!Files.isRegularFile(rapporto)) {
                errore("rapporto SpotBugs assente per " + nome + ": " + rapporto);
                continue;
            }
            Document doc;
            try {
                doc = leggiXml(rapporto);
            } catch (Exception e) {
                errore("rapporto SpotBugs di " + nome + " non leggibile o non e' XML ben formato e completo: " + e.getMessage());
                continue;
            }
            Element suite = doc.getDocumentElement();
            if (!"BugCollection".equals(suite.getTagName())) {
                errore("radice del rapporto SpotBugs di " + nome + " '" + suite.getTagName() + "', attesa 'BugCollection'");
                continue;
            }
            String ts = suite.getAttribute("analysisTimestamp");
            if (!ts.matches("[0-9]{10,16}") || Long.parseLong(ts) < inizioSecondi * 1000L) {
                errore("il rapporto SpotBugs di " + nome + " non e' di questa corsa: analysisTimestamp='" + ts
                        + "' precedente all'inizio (" + inizioSecondi + " s)");
                continue;
            }
            List<Element> errori = figli(suite, "Errors");
            if (errori.size() != 1 || !"0".equals(errori.get(0).getAttribute("errors"))
                    || !"0".equals(errori.get(0).getAttribute("missingClasses"))) {
                errore("SpotBugs ha segnalato errori di analisi o classi mancanti in " + nome);
                continue;
            }
            List<Element> riepilogo = figli(suite, "FindBugsSummary");
            if (riepilogo.size() != 1) {
                errore("rapporto SpotBugs di " + nome + " senza FindBugsSummary");
                continue;
            }
            int difetti = figli(suite, "BugInstance").size();
            if (difetti != 0 || !"0".equals(riepilogo.get(0).getAttribute("total_bugs"))) {
                errore("SpotBugs ha segnalato difetti in " + nome + " (BugInstance: " + difetti + ")");
                continue;
            }
            Set<String> analizzate = new HashSet<>();
            NodeList stats = riepilogo.get(0).getElementsByTagName("ClassStats");
            for (int i = 0; i < stats.getLength(); i++) {
                analizzate.add(((Element) stats.item(i)).getAttribute("class"));
            }
            List<Classe> compilate = classiCompilate(m);
            int mancanti = 0;
            for (Classe c : compilate) {
                if (!analizzate.contains(c.nome.replace('/', '.'))) {
                    errore("classe " + c.nome.replace('/', '.') + " di " + nome + " non analizzata da SpotBugs");
                    mancanti++;
                }
            }
            if (compilate.isEmpty()) {
                errore("il modulo " + nome + " ha codice di produzione ma nessuna classe compilata da analizzare");
            } else if (mancanti == 0) {
                System.out.println("SpotBugs " + nome + ": " + compilate.size() + " classi analizzate, 0 difetti, 0 errori di analisi");
            }
        }
        if (analizzati == 0) {
            errore("nessun modulo con codice di produzione: analisi SpotBugs non verificabile");
        }
    }

    // ---- moduli e classi compilate ----------------------------------------------------------

    static List<Path> moduli(Path radice) throws IOException {
        List<Path> out = new ArrayList<>();
        try (Stream<Path> s = Files.list(radice)) {
            s.filter(p -> p.getFileName().toString().startsWith("carddemo-") && Files.isRegularFile(p.resolve("pom.xml")))
                    .sorted().forEach(out::add);
        }
        if (out.isEmpty()) {
            fatale("nessun modulo carddemo-* trovato in " + radice);
        }
        return out;
    }

    record Classe(String nome, boolean eseguibile) { }

    static List<Classe> classiCompilate(Path modulo) throws IOException {
        Path dir = modulo.resolve("target/classes");
        List<Classe> out = new ArrayList<>();
        if (!Files.isDirectory(dir)) {
            if (Files.isDirectory(modulo.resolve("src/main/java"))) {
                errore("il modulo " + modulo.getFileName() + " ha sorgenti di produzione ma nessuna classe compilata in questa corsa");
            }
            return out;
        }
        List<Path> file = new ArrayList<>();
        try (Stream<Path> s = Files.walk(dir)) {
            s.filter(p -> p.toString().endsWith(".class")).sorted().forEach(file::add);
        }
        for (Path f : file) {
            String rel = dir.relativize(f).toString().replace('\\', '/');
            out.add(new Classe(rel.substring(0, rel.length() - ".class".length()), eseguibile(f)));
        }
        return out;
    }

    /**
     * Una classe e' eseguibile se non e' sintetica e ha almeno un metodo con codice che JaCoCo non
     * scarta: sono scartati i metodi sintetici (salvo le lambda), values/valueOf degli enum e il
     * costruttore privato senza argomenti e senza corpo (5 byte di codice).
     */
    static boolean eseguibile(Path file) throws IOException {
        try (DataInputStream in = new DataInputStream(new BufferedInputStream(Files.newInputStream(file)))) {
            if (in.readInt() != 0xCAFEBABE) {
                throw new IOException(file + ": non e' un file di classe");
            }
            in.readUnsignedShort();
            in.readUnsignedShort();
            int n = in.readUnsignedShort();
            String[] utf8 = new String[n];
            for (int i = 1; i < n; i++) {
                int tag = in.readUnsignedByte();
                switch (tag) {
                    case 1 -> utf8[i] = in.readUTF();
                    case 3, 4, 9, 10, 11, 12, 17, 18 -> in.skipNBytes(4);
                    case 5, 6 -> {
                        in.skipNBytes(8);
                        i++;
                    }
                    case 7, 8, 16, 19, 20 -> in.skipNBytes(2);
                    case 15 -> in.skipNBytes(3);
                    default -> throw new IOException(file + ": voce " + tag + " sconosciuta nel pool di costanti");
                }
            }
            int accesso = in.readUnsignedShort();
            in.readUnsignedShort();
            in.readUnsignedShort();
            in.skipNBytes(2L * in.readUnsignedShort());
            int campi = in.readUnsignedShort();
            for (int i = 0; i < campi; i++) {
                in.skipNBytes(6);
                int attributi = in.readUnsignedShort();
                for (int a = 0; a < attributi; a++) {
                    in.skipNBytes(2);
                    in.skipNBytes(Integer.toUnsignedLong(in.readInt()));
                }
            }
            boolean eseguibile = false;
            boolean sintetica = (accesso & 0x1000) != 0;
            boolean enumerazione = (accesso & 0x4000) != 0;
            int metodi = in.readUnsignedShort();
            for (int i = 0; i < metodi; i++) {
                int flag = in.readUnsignedShort();
                String nome = utf8[in.readUnsignedShort()];
                String descrittore = utf8[in.readUnsignedShort()];
                int attributi = in.readUnsignedShort();
                for (int a = 0; a < attributi; a++) {
                    String nomeAttributo = utf8[in.readUnsignedShort()];
                    long lunghezza = Integer.toUnsignedLong(in.readInt());
                    if ("Code".equals(nomeAttributo)) {
                        in.skipNBytes(4);
                        long codice = Integer.toUnsignedLong(in.readInt());
                        in.skipNBytes(lunghezza - 8);
                        boolean scartato = ((flag & 0x1000) != 0 && !nome.startsWith("lambda$"))
                                || (enumerazione && (nome.equals("values") || nome.equals("valueOf")))
                                || (nome.equals("<init>") && descrittore.equals("()V") && (flag & 0x0002) != 0 && codice == 5);
                        if (!scartato) {
                            eseguibile = true;
                        }
                    } else {
                        in.skipNBytes(lunghezza);
                    }
                }
            }
            return eseguibile && !sintetica;
        }
    }

    // ---- XML ------------------------------------------------------------------------------

    /**
     * Parser DOM che accetta il DOCTYPE ma non fa alcun accesso esterno: nessun DTD esterno,
     * nessuna entita' esterna, nessun XInclude; ogni risoluzione di entita' restituisce vuoto.
     */
    static Document leggiXml(Path file) throws Exception {
        DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
        f.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        f.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
        f.setFeature("http://xml.org/sax/features/external-general-entities", false);
        f.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
        f.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
        f.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
        f.setXIncludeAware(false);
        f.setExpandEntityReferences(false);
        f.setNamespaceAware(false);
        DocumentBuilder b = f.newDocumentBuilder();
        b.setEntityResolver((publicId, systemId) -> new InputSource(new StringReader("")));
        try (var in = Files.newInputStream(file)) {
            return b.parse(in);
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

    static String corsa(String v) {
        if (v.isBlank()) {
            fatale("identificativo di corsa vuoto");
        }
        return v;
    }

    static long epoch(String v) {
        if (!v.matches("[0-9]{9,11}")) {
            fatale("inizio corsa non valido: '" + v + "'");
        }
        return Long.parseLong(v);
    }

    static void errore(String messaggio) {
        ERRORI.add(messaggio);
    }

    static void fatale(String messaggio) {
        System.err.println("ERRORE: " + messaggio);
        System.exit(1);
    }
}
