package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.ltoscano.carddemo.loader.CaricatoreConti;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * Issue #60, controllo 8: la regola sugli importi estesa al caricatore. Le classi di produzione
 * compilate di {@code carddemo-loader} (la cartella o il jar da cui il test le carica) si ispezionano
 * con la stessa logica di {@link NoFloatingPointBytecodeTest} di {@code carddemo-domain}, riusata
 * attraverso il jar delle sue classi di test, non copiata ({@code supers} e {@code findings}, visibili
 * nel pacchetto: per questo il test sta nel pacchetto {@code io.github.ltoscano.carddemo.domain} anche
 * se vive in {@code carddemo-parity}). Nessuna istruzione, firma, costante o chiamata in virgola
 * mobile, nessuna conversione con perdita su un {@code Number}, nessun restringimento primitivo: per
 * il caricatore non c'e' alcuna eccezione ammessa.
 */
class IspezioneBytecodeCaricatoreTest {

    private static final Set<String> CLASSI_ATTESE = Set.of(
            "io/github/ltoscano/carddemo/loader/CampoConto",
            "io/github/ltoscano/carddemo/loader/CaricamentoRifiutato",
            "io/github/ltoscano/carddemo/loader/CaricatoreApplication",
            "io/github/ltoscano/carddemo/loader/CaricatoreConti");

    @Test
    void nessunaVirgolaMobileNeConversioniConPerditaNelleClassiDelCaricatore() throws Exception {
        Path radice = Path.of(CaricatoreConti.class.getProtectionDomain().getCodeSource().getLocation().toURI());
        List<byte[]> classi = new ArrayList<>();
        Set<String> nomi = new TreeSet<>();
        if (Files.isDirectory(radice)) {
            List<Path> file;
            try (Stream<Path> s = Files.walk(radice)) {
                file = s.filter(f -> f.toString().endsWith(".class")).sorted().toList();
            }
            for (Path f : file) {
                String nome = radice.relativize(f).toString().replace('\\', '/');
                nomi.add(nome.substring(0, nome.length() - ".class".length()));
                classi.add(Files.readAllBytes(f));
            }
        } else {
            try (JarFile jar = new JarFile(radice.toFile())) {
                Enumeration<JarEntry> voci = jar.entries();
                while (voci.hasMoreElements()) {
                    JarEntry v = voci.nextElement();
                    if (v.getName().endsWith(".class")) {
                        nomi.add(v.getName().substring(0, v.getName().length() - ".class".length()));
                        try (InputStream in = jar.getInputStream(v)) {
                            classi.add(in.readAllBytes());
                        }
                    }
                }
            }
        }
        System.out.println("[bytecode] classi del caricatore ispezionate da " + radice + ": " + nomi);
        assertTrue(nomi.containsAll(CLASSI_ATTESE), "classi del caricatore non trovate in " + radice + ": " + nomi);
        for (String n : nomi) {
            assertTrue(n.startsWith("io/github/ltoscano/carddemo/loader/"), "classe estranea al caricatore: " + n);
        }
        Map<String, String> supers = NoFloatingPointBytecodeTest.supers(classi);
        List<String> trovati = new ArrayList<>();
        for (byte[] c : classi) {
            trovati.addAll(NoFloatingPointBytecodeTest.findings(c, supers));
        }
        assertEquals(List.of(), trovati,
                "virgola mobile, conversioni con perdita o restringimenti nelle classi compilate del caricatore");
    }
}
