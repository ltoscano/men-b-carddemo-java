import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.StringReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
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
 * <pre>java quality/RapportiQualita.java jacoco   &lt;radice&gt; &lt;corsa&gt; &lt;pom-effettivi&gt;
 * java quality/RapportiQualita.java spotbugs &lt;radice&gt; &lt;corsa&gt; &lt;inizio-corsa-in-secondi-epoch&gt; &lt;pom-effettivi&gt;</pre>
 *
 * &lt;pom-effettivi&gt; e' l'output di maven-help-plugin:effective-pom sul reattore (un elemento
 * projects con un project per modulo): la configurazione dei plugin si legge da li', come
 * la vede Maven (ereditarieta', profili, proprieta' risolte), non cercando testo nei POM.
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
        if (args.length == 4 && args[0].equals("jacoco")) {
            jacoco(Path.of(args[1]), corsa(args[2]), Path.of(args[3]));
        } else if (args.length == 5 && args[0].equals("spotbugs")) {
            spotbugs(Path.of(args[1]), corsa(args[2]), epoch(args[3]), Path.of(args[4]));
        } else {
            fatale("uso: RapportiQualita jacoco <radice> <corsa> <pom-effettivi> | spotbugs <radice> <corsa> <inizio-epoch-secondi> <pom-effettivi>");
        }
        if (!ERRORI.isEmpty()) {
            for (String e : ERRORI) {
                System.err.println("ERRORE: " + e);
            }
            System.exit(1);
        }
    }

    // ---- JaCoCo ---------------------------------------------------------------------------

    static void jacoco(Path radice, String corsa, Path effettivi) throws IOException {
        List<Path> moduli = moduli(radice);
        controllaConfigMaven(radice);
        controllaProfili(radice, moduli);
        Document eff = leggiEffettivi(effettivi);
        if (eff != null) {
            controllaProprieta(eff);
            controllaConfigurazioneJacoco(eff, radice, corsa, moduli);
        }
        Set<String> sessioniAmmesse = new TreeSet<>();
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
            // L'agente di ogni modulo registra "<corsa>:<modulo>": la prova identifica corsa e produttore.
            String attesa = sessioneModulo(corsa, nome);
            sessioniAmmesse.add(attesa);
            Path exec = m.resolve("target/jacoco.exec");
            if (!Files.isRegularFile(exec)) {
                errore("agente JaCoCo non attivo in " + nome + ": file di esecuzione assente (" + exec + ")");
                continue;
            }
            try {
                List<String> sessioni = sessioniExec(exec);
                String sbagliata = sessioneNonDellaCorsa(sessioni, attesa);
                if (sessioni.isEmpty()) {
                    errore("agente JaCoCo non attivo in " + nome + ": nessuna sessione nel file di esecuzione " + exec);
                } else if (sbagliata != null) {
                    errore("agente JaCoCo di " + nome + ": sessione '" + sbagliata + "' non della corsa corrente per questo modulo, attesa '"
                            + attesa + "'");
                } else {
                    System.out.println("JaCoCo " + nome + ": agente attivo in questa corsa (" + sessioni.size()
                            + " sessione/i " + attesa + ")");
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
        if (sessioni.isEmpty()) {
            errore("il rapporto JaCoCo non contiene sessioni: non e' di questa corsa");
        }
        for (String sessione : sessioni) {
            if (!sessioniAmmesse.contains(sessione)) {
                errore("il rapporto JaCoCo non e' della corsa corrente: sessione '" + sessione + "' non tra quelle dei moduli di questa corsa "
                        + sessioniAmmesse);
            }
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

    static String sessioneModulo(String corsa, String modulo) {
        return corsa + ":" + modulo;
    }

    static String sessioneNonDellaCorsa(List<String> sessioni, String attesa) {
        for (String s : sessioni) {
            if (!attesa.equals(s)) {
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

    static final String ESCLUSIONI = "quality/regole/spotbugs-esclusioni.xml";
    /** Configurazione di SpotBugs fissata e motivata in docs/sviluppo.md; il filtro di esclusioni e' l'unica chiave facoltativa. */
    static final Map<String, String> CONFIG_SPOTBUGS = Map.of(
            "effort", "Max", "threshold", "Medium", "failOnError", "true", "xmlOutput", "true", "includeTests", "false");

    /**
     * Un file di esclusioni e' ammesso solo come {@value #ESCLUSIONI}, con la sola struttura
     * FindBugsFilter/Match e un commento con il motivo subito prima di ogni Match. Ogni altra
     * struttura (Class, Bug, Package, And, Or, Not... al primo livello, testo, altri elementi) e'
     * respinta, anche se SpotBugs la accetterebbe: la grammatica del controllo non e' piu' stretta
     * di quella dello strumento perche' cio' che non si riconosce non passa.
     */
    static void controllaFileEsclusioni(Path file) {
        try {
            Element r = leggiXml(file).getDocumentElement();
            if (!"FindBugsFilter".equals(r.getTagName())) {
                errore(ESCLUSIONI + ": radice '" + r.getTagName() + "', attesa 'FindBugsFilter'");
                return;
            }
            int n = 0;
            for (Node c = r.getFirstChild(); c != null; c = c.getNextSibling()) {
                if (c instanceof Element e) {
                    if (!"Match".equals(e.getTagName())) {
                        errore("struttura di esclusione non ammessa in " + ESCLUSIONI + ": <" + e.getTagName()
                                + "> al primo livello; sono ammessi solo elementi <Match>, ciascuno preceduto da un commento con il motivo");
                        continue;
                    }
                    n++;
                    Node prec = c.getPreviousSibling();
                    while (prec != null && prec.getNodeType() == Node.TEXT_NODE && prec.getTextContent().isBlank()) {
                        prec = prec.getPreviousSibling();
                    }
                    if (prec == null || prec.getNodeType() != Node.COMMENT_NODE || prec.getTextContent().isBlank()) {
                        errore("esclusione SpotBugs senza motivo in " + ESCLUSIONI + " (Match n. " + n + "): serve un commento subito prima");
                    }
                } else if (c.getNodeType() == Node.TEXT_NODE || c.getNodeType() == Node.CDATA_SECTION_NODE) {
                    if (!c.getTextContent().isBlank()) {
                        errore("testo non ammesso in " + ESCLUSIONI);
                    }
                } else if (c.getNodeType() != Node.COMMENT_NODE) {
                    errore("nodo non ammesso in " + ESCLUSIONI + " (tipo " + c.getNodeType() + ")");
                }
            }
            System.out.println("SpotBugs esclusioni: " + n + " in " + ESCLUSIONI + ", ciascuna con il motivo");
        } catch (Exception e) {
            errore(ESCLUSIONI + " non leggibile o non e' XML ben formato: " + e.getMessage());
        }
    }

    /**
     * Configurazione EFFETTIVA di SpotBugs in ogni modulo con codice di produzione, letta dal POM
     * effettivo: versione e dipendenze come nel POM padre, configurazione del plugin e dell'unica
     * esecuzione (analisi-difetti: fase verify, obiettivo check) uguali a quella fissata, nessuna
     * chiave in piu' (onlyAnalyze, visitors, omitVisitors, filtri diversi...). Restituisce il file
     * di esclusioni configurato (uguale in tutti i moduli) o null.
     */
    static Path controllaConfigurazioneSpotbugs(Document eff, Path radice, List<Path> moduli) {
        Element padre = progettoRadice(eff);
        Element gestito = plugin(padre, true, "spotbugs-maven-plugin");
        if (gestito == null) {
            errore("POM padre senza spotbugs-maven-plugin in pluginManagement");
            return null;
        }
        Path filtroAtteso = radice.toAbsolutePath().normalize().resolve(ESCLUSIONI);
        Set<String> filtri = new TreeSet<>();
        Path configurato = null;
        for (Path m : moduli) {
            String nome = m.getFileName().toString();
            if (!Files.isDirectory(m.resolve("src/main/java"))) {
                continue;
            }
            Element prog = progetto(eff, nome);
            Element pl = prog == null ? null : plugin(prog, false, "spotbugs-maven-plugin");
            if (pl == null) {
                errore("configurazione effettiva di SpotBugs: " + nome + " non dichiara spotbugs-maven-plugin");
                continue;
            }
            List<String> diff = new ArrayList<>();
            if (!testoFiglio(pl, "version").equals(testoFiglio(gestito, "version"))) {
                diff.add("versione " + testoFiglio(pl, "version") + " invece di " + testoFiglio(gestito, "version"));
            }
            if (!dipendenze(pl).equals(dipendenze(gestito))) {
                diff.add("dipendenze del plugin " + dipendenze(pl) + " invece di " + dipendenze(gestito));
            }
            Map<String, String> conf = mappa(figlio(pl, "configuration"));
            String filtro = conf.remove("excludeFilterFile");
            if (!conf.equals(CONFIG_SPOTBUGS)) {
                diff.add("configurazione " + new TreeMap<>(conf) + " invece di " + new TreeMap<>(CONFIG_SPOTBUGS));
            }
            Map<String, Element> esecuzioni = esecuzioni(pl);
            if (!esecuzioni.keySet().equals(Set.of("analisi-difetti"))) {
                diff.add("esecuzioni " + esecuzioni.keySet() + " invece di [analisi-difetti]");
            } else {
                Element e = esecuzioni.get("analisi-difetti");
                if (!"verify".equals(testoFiglio(e, "phase")) || !goals(e).equals(Set.of("check"))) {
                    diff.add("esecuzione analisi-difetti con fase '" + testoFiglio(e, "phase") + "' e obiettivi " + goals(e));
                }
                Map<String, String> ce = mappa(figlio(e, "configuration"));
                String filtroEsec = ce.remove("excludeFilterFile");
                if (!ce.equals(CONFIG_SPOTBUGS) || !java.util.Objects.equals(filtro, filtroEsec)) {
                    diff.add("configurazione dell'esecuzione " + new TreeMap<>(ce) + " invece di " + new TreeMap<>(CONFIG_SPOTBUGS));
                }
            }
            // ${project.parent.basedir} non e' risolta dall'interpolazione del modello (la risolve Maven al
            // momento di valutare il parametro): ogni modulo ha per genitore la radice del reattore.
            if (filtro != null) {
                filtro = filtro.replace("${project.parent.basedir}", radice.toAbsolutePath().normalize().toString());
            }
            if (filtro != null && !Path.of(filtro).toAbsolutePath().normalize().equals(filtroAtteso)) {
                diff.add("filtro di esclusioni '" + filtro + "' invece di " + filtroAtteso);
            }
            filtri.add(String.valueOf(filtro));
            if (filtro != null) {
                configurato = filtroAtteso;
            }
            if (!diff.isEmpty()) {
                errore("configurazione effettiva di SpotBugs in " + nome + " diversa da quella fissata nel POM padre: " + String.join("; ", diff));
            } else {
                System.out.println("SpotBugs " + nome + ": configurazione effettiva uguale a quella fissata (effort Max, soglia Medium, nessun ambito o rilevatore ridefinito)");
            }
        }
        if (filtri.size() > 1) {
            errore("il filtro di esclusioni non e' lo stesso in tutti i moduli: " + filtri);
        }
        return configurato;
    }

    static void controllaEsclusioni(Path radice, Path configurato) {
        Path file = radice.resolve(ESCLUSIONI);
        if (configurato == null) {
            if (Files.exists(file)) {
                errore(ESCLUSIONI + " esiste ma nessun modulo lo configura (excludeFilterFile): le esclusioni non sarebbero applicate");
            }
            return;
        }
        if (!Files.isRegularFile(file)) {
            errore("filtro di esclusioni configurato ma " + ESCLUSIONI + " assente");
            return;
        }
        controllaFileEsclusioni(file);
    }

    static void spotbugs(Path radice, String corsa, long inizioSecondi, Path effettivi) throws IOException {
        controllaConfigMaven(radice);
        controllaProfili(radice, moduli(radice));
        Document eff = leggiEffettivi(effettivi);
        if (eff != null) {
            controllaProprieta(eff);
            controllaEsclusioni(radice, controllaConfigurazioneSpotbugs(eff, radice, moduli(radice)));
        }
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

    // ---- configurazione effettiva (POM effettivo) -----------------------------------------------

    /**
     * Configurazione EFFETTIVA di JaCoCo in ogni modulo: versione come nel POM padre, nessuna
     * configurazione a livello di plugin (niente skip, includes, excludes), esattamente l'esecuzione
     * dell'agente (fase initialize, prepare-agent, destFile e sessionId "corsa:modulo", nessuna
     * altra chiave) e, solo nel modulo del rapporto aggregato, l'esecuzione report-aggregate (fase
     * verify, solo outputDirectory e formats=XML).
     */
    static void controllaConfigurazioneJacoco(Document eff, Path radice, String corsa, List<Path> moduli) {
        Element padre = progettoRadice(eff);
        Element riferimento = plugin(padre, false, "jacoco-maven-plugin");
        if (riferimento == null) {
            errore("POM padre senza jacoco-maven-plugin");
            return;
        }
        String modulo_aggregato = RAPPORTO_JACOCO.substring(0, RAPPORTO_JACOCO.indexOf('/'));
        Path base = radice.toAbsolutePath().normalize();
        for (Path m : moduli) {
            String nome = m.getFileName().toString();
            Element prog = progetto(eff, nome);
            Element pl = prog == null ? null : plugin(prog, false, "jacoco-maven-plugin");
            if (pl == null) {
                errore("configurazione effettiva di JaCoCo: " + nome + " non ha jacoco-maven-plugin");
                continue;
            }
            List<String> diff = new ArrayList<>();
            if (!testoFiglio(pl, "version").equals(testoFiglio(riferimento, "version"))) {
                diff.add("versione " + testoFiglio(pl, "version") + " invece di " + testoFiglio(riferimento, "version"));
            }
            Map<String, String> conf = mappa(figlio(pl, "configuration"));
            if (!conf.isEmpty()) {
                diff.add("configurazione a livello di plugin " + new TreeMap<>(conf) + " (attesa vuota)");
            }
            Map<String, Element> esecuzioni = esecuzioni(pl);
            Set<String> attese = nome.equals(modulo_aggregato) ? Set.of("agente-copertura", "rapporto-aggregato") : Set.of("agente-copertura");
            if (!esecuzioni.keySet().equals(attese)) {
                diff.add("esecuzioni " + new TreeSet<>(esecuzioni.keySet()) + " invece di " + new TreeSet<>(attese));
            }
            Element agente = esecuzioni.get("agente-copertura");
            if (agente != null) {
                Map<String, String> ca = mappa(figlio(agente, "configuration"));
                String destFile = ca.remove("destFile");
                String sessione = ca.remove("sessionId");
                if (!ca.isEmpty()) {
                    diff.add("configurazione dell'agente con chiavi in piu' " + new TreeMap<>(ca));
                }
                if (destFile == null || !Path.of(destFile).toAbsolutePath().normalize().equals(base.resolve(nome).resolve("target/jacoco.exec"))) {
                    diff.add("destFile '" + destFile + "'");
                }
                if (!sessioneModulo(corsa, nome).equals(sessione)) {
                    diff.add("sessionId '" + sessione + "' invece di '" + sessioneModulo(corsa, nome) + "'");
                }
                if (!"initialize".equals(testoFiglio(agente, "phase")) || !goals(agente).equals(Set.of("prepare-agent"))) {
                    diff.add("esecuzione dell'agente con fase '" + testoFiglio(agente, "phase") + "' e obiettivi " + goals(agente));
                }
            }
            Element aggregato = esecuzioni.get("rapporto-aggregato");
            if (aggregato != null) {
                Map<String, String> cr = mappa(figlio(aggregato, "configuration"));
                String uscita = cr.remove("outputDirectory");
                String formati = cr.remove("formats");
                if (!cr.isEmpty()) {
                    diff.add("configurazione del rapporto con chiavi in piu' " + new TreeMap<>(cr));
                }
                if (uscita == null || !Path.of(uscita).toAbsolutePath().normalize().equals(base.resolve(nome).resolve("target/site/jacoco-aggregate"))) {
                    diff.add("outputDirectory '" + uscita + "'");
                }
                if (!"[format=XML]".equals(formati)) {
                    diff.add("formati " + formati + " invece di [format=XML]");
                }
                if (!"verify".equals(testoFiglio(aggregato, "phase")) || !goals(aggregato).equals(Set.of("report-aggregate"))) {
                    diff.add("esecuzione del rapporto con fase '" + testoFiglio(aggregato, "phase") + "' e obiettivi " + goals(aggregato));
                }
            }
            if (!diff.isEmpty()) {
                errore("configurazione effettiva di JaCoCo in " + nome + " diversa da quella fissata: " + String.join("; ", diff));
            } else {
                System.out.println("JaCoCo " + nome + ": configurazione effettiva uguale a quella fissata (nessun skip, includes o excludes)");
            }
        }
    }

    /**
     * Le proprieta' di sistema di Maven che il POM effettivo non mostra (skip, includes, excludes,
     * soglie dei plugin) potrebbero arrivare da file versionati letti da Maven: non sono ammessi.
     */
    static void controllaConfigMaven(Path radice) {
        for (String f : new String[] {".mvn/maven.config", ".mvn/jvm.config"}) {
            if (Files.exists(radice.resolve(f))) {
                errore("file " + f + " presente: puo' cambiare la configurazione dei plugin senza comparire nel POM effettivo");
            }
        }
    }

    /** Versioni fissate: le uniche proprieta' spotbugs.* e jacoco.* ammesse nei POM. */
    static final Map<String, String> PROPRIETA_AMMESSE = Map.of("spotbugs.version", "4.10.5", "jacoco.version", "0.8.16");

    /**
     * Molti parametri dei plugin si impostano anche con una proprieta' del POM (spotbugs.onlyAnalyze,
     * spotbugs.omitVisitors, spotbugs.maxRank, jacoco.skip...) senza comparire nella sezione
     * configuration. Nelle properties del POM effettivo di ogni progetto, quindi, le uniche proprieta'
     * il cui nome comincia per "spotbugs." o "jacoco." sono spotbugs.version e jacoco.version, con i
     * valori fissati; ogni altra e' un errore che nomina proprieta' e modulo.
     */
    static void controllaProprieta(Document eff) {
        for (Element prog : figli(eff.getDocumentElement(), "project")) {
            String modulo = testoFiglio(prog, "artifactId");
            Element props = figlio(prog, "properties");
            if (props == null) {
                continue;
            }
            NodeList nodi = props.getChildNodes();
            for (int i = 0; i < nodi.getLength(); i++) {
                if (nodi.item(i) instanceof Element e) {
                    String nome = e.getTagName();
                    if (!nome.startsWith("spotbugs.") && !nome.startsWith("jacoco.")) {
                        continue;
                    }
                    String atteso = PROPRIETA_AMMESSE.get(nome);
                    if (atteso == null) {
                        errore("proprieta' non ammessa nel POM effettivo di " + modulo + ": " + nome + " = '" + e.getTextContent().trim()
                                + "' (le uniche proprieta' spotbugs.* e jacoco.* ammesse sono " + new TreeSet<>(PROPRIETA_AMMESSE.keySet()) + ")");
                    } else if (!atteso.equals(e.getTextContent().trim())) {
                        errore("proprieta' " + nome + " nel POM effettivo di " + modulo + " vale '" + e.getTextContent().trim()
                                + "' invece del valore fissato '" + atteso + "'");
                    }
                }
            }
        }
    }

    /**
     * I POM del progetto (padre e moduli) non possono contenere profili: un profilo attivato da una
     * condizione che cambia durante la corsa (per esempio l'assenza di un file che la build stessa
     * crea) e' attivo in mvn verify e spento quando si genera il POM effettivo, e il controllo
     * leggerebbe un'altra configurazione. La regola e' l'assenza di profili, anche se innocui.
     * Si leggono i POM sorgente con il parser XML: un commento che nomina la parola non conta.
     */
    static void controllaProfili(Path radice, List<Path> moduli) {
        List<Path> pom = new ArrayList<>(List.of(radice.resolve("pom.xml")));
        for (Path m : moduli) {
            pom.add(m.resolve("pom.xml"));
        }
        for (Path p : pom) {
            try {
                Element r = leggiXml(p).getDocumentElement();
                if (!figli(r, "profiles").isEmpty()) {
                    errore("profili non ammessi in " + p + ": i POM del progetto non possono contenere <profiles>");
                }
            } catch (Exception e) {
                errore("POM " + p + " non leggibile: " + e.getMessage());
            }
        }
    }

    /** POM effettivi del reattore; un file assente o malformato e' un errore. */
    static Document leggiEffettivi(Path file) {
        try {
            if (!Files.isRegularFile(file) || Files.size(file) == 0) {
                errore("POM effettivi assenti o vuoti: " + file);
                return null;
            }
            Document d = leggiXml(file);
            if (!"projects".equals(d.getDocumentElement().getTagName())) {
                errore("POM effettivi: radice '" + d.getDocumentElement().getTagName() + "', attesa 'projects'");
                return null;
            }
            return d;
        } catch (Exception e) {
            errore("POM effettivi " + file + " non leggibili: " + e.getMessage());
            return null;
        }
    }

    static Element progettoRadice(Document eff) {
        return figli(eff.getDocumentElement(), "project").get(0);
    }

    static Element progetto(Document eff, String artifactId) {
        for (Element p : figli(eff.getDocumentElement(), "project")) {
            if (artifactId.equals(testoFiglio(p, "artifactId"))) {
                return p;
            }
        }
        return null;
    }

    /** Plugin con l'artifactId dato in build/plugins (o build/pluginManagement/plugins). */
    static Element plugin(Element progetto, boolean gestito, String artifactId) {
        Element build = figlio(progetto, "build");
        if (build == null) {
            return null;
        }
        Element contenitore = gestito ? figlio(figlio(build, "pluginManagement"), "plugins") : figlio(build, "plugins");
        if (contenitore == null) {
            return null;
        }
        for (Element p : figli(contenitore, "plugin")) {
            if (artifactId.equals(testoFiglio(p, "artifactId"))) {
                return p;
            }
        }
        return null;
    }

    static Element figlio(Element padre, String nome) {
        if (padre == null) {
            return null;
        }
        List<Element> f = figli(padre, nome);
        return f.isEmpty() ? null : f.get(0);
    }

    static String testoFiglio(Element padre, String nome) {
        Element f = figlio(padre, nome);
        return f == null ? "" : f.getTextContent().trim();
    }

    /** Elementi figli diretti di una configurazione: nome -> valore (testo, oppure [figlio=valore;...] ordinato). */
    static Map<String, String> mappa(Element configurazione) {
        Map<String, String> m = new TreeMap<>();
        if (configurazione == null) {
            return m;
        }
        NodeList nodi = configurazione.getChildNodes();
        for (int i = 0; i < nodi.getLength(); i++) {
            if (nodi.item(i) instanceof Element e) {
                m.put(e.getTagName(), canonico(e));
            }
        }
        return m;
    }

    static String canonico(Element e) {
        List<String> figliCanonici = new ArrayList<>();
        NodeList nodi = e.getChildNodes();
        for (int i = 0; i < nodi.getLength(); i++) {
            if (nodi.item(i) instanceof Element c) {
                figliCanonici.add(c.getTagName() + "=" + canonico(c));
            }
        }
        if (figliCanonici.isEmpty()) {
            return e.getTextContent().trim();
        }
        java.util.Collections.sort(figliCanonici);
        return "[" + String.join(";", figliCanonici) + "]";
    }

    static Map<String, Element> esecuzioni(Element plugin) {
        Map<String, Element> m = new TreeMap<>();
        Element contenitore = figlio(plugin, "executions");
        if (contenitore != null) {
            for (Element e : figli(contenitore, "execution")) {
                String id = testoFiglio(e, "id");
                m.put(id.isEmpty() ? "default" : id, e);
            }
        }
        return m;
    }

    static Set<String> goals(Element esecuzione) {
        Set<String> out = new TreeSet<>();
        Element g = figlio(esecuzione, "goals");
        if (g != null) {
            for (Element x : figli(g, "goal")) {
                out.add(x.getTextContent().trim());
            }
        }
        return out;
    }

    static Set<String> dipendenze(Element plugin) {
        Set<String> out = new TreeSet<>();
        Element d = figlio(plugin, "dependencies");
        if (d != null) {
            for (Element x : figli(d, "dependency")) {
                out.add(testoFiglio(x, "groupId") + ":" + testoFiglio(x, "artifactId") + ":" + testoFiglio(x, "version"));
            }
        }
        return out;
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
        if (!ERRORI.contains(messaggio)) {
            ERRORI.add(messaggio);
        }
    }

    static void fatale(String messaggio) {
        System.err.println("ERRORE: " + messaggio);
        System.exit(1);
    }
}
