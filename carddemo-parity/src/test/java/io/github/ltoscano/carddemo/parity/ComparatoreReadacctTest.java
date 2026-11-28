package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.TreeSet;
import java.util.function.Consumer;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Test del comparatore di READACCT (issue #65), non marcati: devono passare ora.
 *
 * <p>Le uscite fedeli simulate si costruiscono dai file fisici dell'oracle versionati da #55
 * ({@code OUTFILE}, {@code ARRYFILE}, {@code VBRCFILE}, standard output in {@code rapporto.txt}),
 * con le correzioni di {@code correzioni.tsv} applicate e il descrittore dei record variabili
 * convertito nella forma del contratto. Nessuna logica di CBACT01C: solo copie e conversioni di formato.
 */
class ComparatoreReadacctTest {

    @TempDir
    Path tmp;

    /** Uscite simulate in memoria: tre file, standard output, codice di uscita. */
    static final class Uscite {
        byte[] outfile;
        byte[] arryfile;
        byte[] vbrcfile;
        List<byte[]> console;
        int uscita;
        boolean senzaArryfile;
    }

    // ---- simulatore ----

    private static Path radice() {
        return Path.of(System.getProperty("menb.golden.readacct"));
    }

    /** Converte il formato fisico di GnuCOBOL (lunghezza dei soli dati) in quello del contratto (lunghezza + 4). */
    static byte[] convertiDescrittori(byte[] gnucobol) {
        byte[] dati = gnucobol.clone();
        int p = 0;
        while (p < dati.length) {
            int lunghezza = ((dati[p] & 0xff) << 8) | (dati[p + 1] & 0xff);
            int nuova = lunghezza + 4;
            dati[p] = (byte) (nuova >> 8);
            dati[p + 1] = (byte) nuova;
            p += 4 + lunghezza;
        }
        assertEquals(dati.length, p, "VBRCFILE dell'oracle non terminato su un confine di record");
        return dati;
    }

    /** Applica correzioni.tsv al file fisico dell'oracle, solo dove l'oracle ha scritto il byte dichiarato. */
    static byte[] applicaCorrezioni(String scenario, String file, byte[] fisico, int lunghezza) throws IOException {
        byte[] dati = fisico.clone();
        int applicate = 0;
        for (String riga : Files.readAllLines(radice().resolve("correzioni.tsv"), StandardCharsets.UTF_8)) {
            if (riga.startsWith("#") || riga.startsWith("scenario\t") || riga.isEmpty()) {
                continue;
            }
            String[] c = riga.split("\t", -1);
            if (!(c[0].equals("*") || c[0].equals(scenario)) || !c[1].equals(file)) {
                continue;
            }
            assertEquals("*", c[2], "correzione con chiave non gestita dal simulatore: " + riga);
            int posizione = Integer.parseInt(c[3]);
            for (int base = 0; base < dati.length; base += lunghezza) {
                assertEquals(Integer.parseInt(c[4], 16), dati[base + posizione - 1] & 0xff, "byte dell'oracle da correggere");
                dati[base + posizione - 1] = (byte) Integer.parseInt(c[5], 16);
                applicate++;
            }
        }
        assertTrue(applicate > 0 || !"ARRYFILE".equals(file), "nessuna correzione applicata a ARRYFILE");
        return dati;
    }

    /** Standard output dell'oracle: la sezione "== stdout" di rapporto.txt, una riga per DISPLAY. */
    static List<byte[]> consoleDellOracle(Path scenario) throws IOException {
        byte[] rapporto = Files.readAllBytes(scenario.resolve("rapporto.txt"));
        String testo = new String(rapporto, StandardCharsets.ISO_8859_1);
        int inizio = testo.indexOf("== stdout\n");
        assertTrue(inizio >= 0, "sezione stdout assente in rapporto.txt");
        inizio += "== stdout\n".length();
        int fine = testo.indexOf("\n== ", inizio);
        assertTrue(fine > inizio, "fine della sezione stdout assente in rapporto.txt");
        byte[] stdout = Arrays.copyOfRange(rapporto, inizio, fine + 1);
        return ComparatoreReadacct.righeConsole(stdout);
    }

    static Uscite fedeli(String nome) throws IOException {
        Path scenario = ComparatoreReadacct.scenario(nome);
        Uscite u = new Uscite();
        u.outfile = applicaCorrezioni(nome, "OUTFILE", Files.readAllBytes(scenario.resolve("OUTFILE")), ComparatoreReadacct.OUTFILE);
        u.arryfile = applicaCorrezioni(nome, "ARRYFILE", Files.readAllBytes(scenario.resolve("ARRYFILE")),
                ComparatoreReadacct.ARRYFILE);
        u.vbrcfile = convertiDescrittori(Files.readAllBytes(scenario.resolve("VBRCFILE")));
        u.console = new ArrayList<>(consoleDellOracle(scenario));
        u.uscita = 0;
        return u;
    }

    private void confronta(String nome, Uscite u) throws IOException {
        Path cartella = Files.createTempDirectory(tmp, "uscite-");
        Files.write(cartella.resolve("OUTFILE"), u.outfile);
        if (!u.senzaArryfile) {
            Files.write(cartella.resolve("ARRYFILE"), u.arryfile);
        }
        Files.write(cartella.resolve("VBRCFILE"), u.vbrcfile);
        ByteArrayOutputStream stdout = new ByteArrayOutputStream();
        for (byte[] riga : u.console) {
            stdout.write(riga);
            stdout.write('\n');
        }
        ComparatoreReadacct.confronta(ComparatoreReadacct.scenario(nome), cartella,
                new AvvioJob.Esito(u.uscita, stdout.toByteArray(), new byte[0]));
    }

    /** Un'alterazione sulle uscite fedeli di mirato: respinta con la diagnosi attesa. */
    private void respinto(String caso, Consumer<Uscite> alterazione, String diagnosi) throws IOException {
        Uscite u = fedeli("mirato");
        alterazione.accept(u);
        AssertionError e = assertThrows(AssertionError.class, () -> confronta("mirato", u), caso + ": non respinto");
        System.out.println("[comparatore] " + caso + " -> " + e.getMessage());
        assertTrue(e.getMessage().startsWith(diagnosi), caso + ": diagnosi inattesa: " + e.getMessage());
    }

    /** Come {@link #respinto}, ma la diagnosi deve coincidere per intero. */
    private void esatto(String caso, Consumer<Uscite> alterazione, String diagnosi) throws IOException {
        Uscite u = fedeli("mirato");
        alterazione.accept(u);
        AssertionError e = assertThrows(AssertionError.class, () -> confronta("mirato", u), caso + ": non respinto");
        System.out.println("[comparatore] " + caso + " -> " + e.getMessage());
        assertEquals(diagnosi, e.getMessage(), caso + ": diagnosi inattesa");
    }

    private static void scambia(byte[] dati, int a, int b, int lunghezza) {
        byte[] t = Arrays.copyOfRange(dati, a * lunghezza, (a + 1) * lunghezza);
        System.arraycopy(dati, b * lunghezza, dati, a * lunghezza, lunghezza);
        System.arraycopy(t, 0, dati, b * lunghezza, lunghezza);
    }

    private static byte[] riga(String testo) {
        return testo.getBytes(StandardCharsets.ISO_8859_1);
    }

    // ---- uscite fedeli ----

    @Test
    void conversioneDelDescrittoreSuiPrimiByteScrittiAMano() throws IOException {
        byte[] fisico = Files.readAllBytes(ComparatoreReadacct.scenario("esempio").resolve("VBRCFILE"));
        assertArrayEquals(new byte[] {0x00, 0x0C, 0x00, 0x00}, Arrays.copyOfRange(fisico, 0, 4), "formato di GnuCOBOL");
        byte[] convertito = convertiDescrittori(fisico);
        assertArrayEquals(new byte[] {0x00, 0x10, 0x00, 0x00}, Arrays.copyOfRange(convertito, 0, 4), "primo descrittore");
        assertArrayEquals(new byte[] {0x00, 0x2B, 0x00, 0x00}, Arrays.copyOfRange(convertito, 16, 20), "secondo descrittore");
        assertEquals(fisico.length, convertito.length, "la conversione non cambia la lunghezza");
    }

    @Test
    void usciteFedeliSimulateAccettatePerEsempioEMirato() throws IOException {
        confronta("esempio", fedeli("esempio"));
        confronta("mirato", fedeli("mirato"));
    }

    @Test
    void loScenarioOsservazioneNonEAmmesso() {
        AssertionError e = assertThrows(AssertionError.class, () -> ComparatoreReadacct.scenario("osservazione"));
        assertTrue(e.getMessage().startsWith("SCENARIO-NON-AMMESSO"), e.getMessage());
    }

    // ---- prove negative, una alterazione alla volta ----

    @Test
    void outfileByteAlteratoInPosizioneDeterminata() throws IOException {
        respinto("OUTFILE record 3 byte 20", u -> u.outfile[2 * 107 + 19] ^= 0x01, "BYTE-DIVERSO: OUTFILE record 3 posizione 20:");
    }

    @Test
    void outfileConfiniDellaMascheraEDataRespinti() throws IOException {
        respinto("OUTFILE byte 76", u -> u.outfile[75] ^= 0x01, "BYTE-DIVERSO: OUTFILE record 1 posizione 76:");
        respinto("OUTFILE byte 79", u -> u.outfile[78] ^= 0x01, "BYTE-DIVERSO: OUTFILE record 1 posizione 79:");
        respinto("OUTFILE byte 72 (data)", u -> u.outfile[71] ^= 0x01, "BYTE-DIVERSO: OUTFILE record 1 posizione 72:");
    }

    @Test
    void arryfileByteAlterato() throws IOException {
        respinto("ARRYFILE record 2 byte 5", u -> u.arryfile[110 + 4] ^= 0x01, "BYTE-DIVERSO: ARRYFILE record 2 posizione 5:");
    }

    @Test
    void arryfileByte80E99ComeLiScriveLOracleRespinti() throws IOException {
        respinto("ARRYFILE byte 80 = 30", u -> u.arryfile[79] = 0x30, "BYTE-DIVERSO: ARRYFILE record 1 posizione 80:");
        respinto("ARRYFILE byte 99 = 30", u -> u.arryfile[98] = 0x30, "BYTE-DIVERSO: ARRYFILE record 1 posizione 99:");
    }

    @Test
    void recordInMenoInPiuEScambiati() throws IOException {
        esatto("OUTFILE un record in meno", u -> u.outfile = Arrays.copyOf(u.outfile, u.outfile.length - 107),
                "NUMERO-DI-RECORD: OUTFILE ha 49 record, attesi 50: primo record mancante 50 (fine del file all'offset 5243)");
        esatto("OUTFILE un record in piu'", u -> {
            byte[] piu = Arrays.copyOf(u.outfile, u.outfile.length + 107);
            System.arraycopy(u.outfile, u.outfile.length - 107, piu, u.outfile.length, 107);
            u.outfile = piu;
        }, "NUMERO-DI-RECORD: OUTFILE ha 51 record, attesi 50: primo record in eccesso 51 all'offset 5350");
        respinto("OUTFILE record 1 e 2 scambiati", u -> scambia(u.outfile, 0, 1, 107), "BYTE-DIVERSO: OUTFILE record 1 posizione 11:");
    }

    @Test
    void fileTroncatiParzialiOConRecordInPiuDiconoRecordEOffset() throws IOException {
        esatto("OUTFILE troncato a meta' dell'ultimo record", u -> u.outfile = Arrays.copyOf(u.outfile, u.outfile.length - 70),
                "LUNGHEZZA: OUTFILE di 5280 byte: record 50 troncato a 37 byte su 107 (fine del file all'offset 5280)");
        esatto("OUTFILE con 10 byte in eccesso", u -> u.outfile = Arrays.copyOf(u.outfile, u.outfile.length + 10),
                "LUNGHEZZA: OUTFILE di 5360 byte: 10 byte in eccesso dopo i 50 record attesi, dall'offset 5350 (record 51)");
        esatto("ARRYFILE vuoto", u -> u.arryfile = new byte[0],
                "NUMERO-DI-RECORD: ARRYFILE ha 0 record, attesi 50: primo record mancante 1 (fine del file all'offset 0)");
        esatto("VBRCFILE senza l'ultimo record", u -> u.vbrcfile = Arrays.copyOf(u.vbrcfile, u.vbrcfile.length - 43),
                "NUMERO-DI-RECORD: VBRCFILE ha 99 record, attesi 100: primo record mancante 100 (fine del file all'offset 2907)");
        esatto("VBRCFILE con un record in piu'", u -> {
            byte[] piu = Arrays.copyOf(u.vbrcfile, u.vbrcfile.length + 43);
            System.arraycopy(u.vbrcfile, u.vbrcfile.length - 43, piu, u.vbrcfile.length, 43);
            u.vbrcfile = piu;
        }, "NUMERO-DI-RECORD: VBRCFILE ha 101 record, attesi 100: primo record in eccesso 101 all'offset 2950");
    }

    @Test
    void vbrcfileLunghezzaDescrittoreInversoEFormatoGnuCobolRespinti() throws IOException {
        respinto("VBRCFILE record 2 di 38 byte", u -> {
            // secondo record: descrittore 00 2A e un byte di dati in meno
            byte[] v = new byte[u.vbrcfile.length - 1];
            System.arraycopy(u.vbrcfile, 0, v, 0, 16 + 4 + 38);
            System.arraycopy(u.vbrcfile, 16 + 4 + 39, v, 16 + 4 + 38, u.vbrcfile.length - (16 + 4 + 39));
            v[17] = 0x2A;
            u.vbrcfile = v;
        }, "LUNGHEZZA-RECORD: VBRCFILE record 2 di 38 byte, atteso 39");
        respinto("VBRCFILE descrittore a byte invertiti", u -> {
            u.vbrcfile[0] = 0x00;
            u.vbrcfile[1] = 0x00;
            u.vbrcfile[2] = 0x10;
            u.vbrcfile[3] = 0x00;
        }, "DESCRITTORE: VBRCFILE record 1 (byte 1): byte 3-4 del descrittore 10 00");
        respinto("VBRCFILE nel formato di GnuCOBOL", u -> {
            try {
                u.vbrcfile = Files.readAllBytes(ComparatoreReadacct.scenario("mirato").resolve("VBRCFILE"));
            } catch (IOException e) {
                throw new IllegalStateException(e);
            }
        }, "LUNGHEZZA-RECORD: VBRCFILE record 1 di 8 byte, atteso 12");
    }

    @Test
    void consoleAlterataRespinta() throws IOException {
        respinto("console riga 2 alterata", u -> u.console.set(1, riga("ACCT-ID                 :00000000009")),
                "CONSOLE: riga 2 colonna 36:");
        respinto("console riga 12 con uno spazio finale in meno", u -> {
            String r = new String(u.console.get(11), StandardCharsets.ISO_8859_1);
            assertTrue(r.endsWith(" "), "la riga 12 doveva finire con uno spazio: «" + r + "»");
            u.console.set(11, riga(r.substring(0, r.length() - 1)));
        }, "CONSOLE: riga 12 colonna 35:");
        respinto("console una riga in meno", u -> u.console.remove(u.console.size() - 1),
                "CONSOLE: 751 righe sullo standard output, attese 752 (2 + 15 x 50): prima riga mancante 752 «");
        respinto("console una riga in piu' in fondo", u -> u.console.add(riga("INFO fine del job READACCT")),
                "CONSOLE: 753 righe sullo standard output, attese 752 (2 + 15 x 50): prima riga in eccesso 753"
                        + " «INFO fine del job READACCT»");
        respinto("console una riga di log in piu'", u -> u.console.add(0, riga("INFO avvio del job READACCT")),
                "CONSOLE: riga 1 colonna 1:");
    }

    @Test
    void codiceDiUscitaEFileAssenteRespinti() throws IOException {
        respinto("codice di uscita 1", u -> u.uscita = 1, "CODICE-DI-USCITA: atteso 0, trovato 1");
        respinto("ARRYFILE assente", u -> u.senzaArryfile = true, "FILE-ASSENTE: ARRYFILE");
    }

    // ---- controprove: cio' che il test NON garantisce ----

    @Test
    void controprovaByteMascheratoAccettato() throws IOException {
        Uscite u = fedeli("mirato");
        u.outfile[76] = 'Z';
        u.outfile[107 + 77] = 'Z';
        confronta("mirato", u);
    }

    @Test
    void controprovaRigaDiOsservazioneConContenutoDiversoAccettata() throws IOException {
        Uscite u = fedeli("mirato");
        List<byte[]> riferimento = ComparatoreReadacct.righeConsole(
                Files.readAllBytes(ComparatoreReadacct.scenario("mirato").resolve("console.riferimento.txt")));
        assertTrue(new String(riferimento.get(3), StandardCharsets.ISO_8859_1).startsWith("#OSSERVAZIONE"), "riga 4");
        u.console.set(3, riga("contenuto qualsiasi"));
        confronta("mirato", u);
    }

    // ---- maschere dei riferimenti contro esclusioni.tsv ----

    @Test
    void byteMascheratiDeiRiferimentiSonoEsattamenteQuelliDiEsclusioni() throws IOException {
        List<String[]> esclusioni = esclusioni();
        for (String nome : List.of("esempio", "mirato")) {
            assertEquals(maschereAttese(nome, esclusioni), maschereTrovate(nome), "maschere di " + nome);
        }
        // prova negativa: una riga di esclusione in piu' rende diversi i due insiemi
        List<String[]> conRigaInPiu = new ArrayList<>(esclusioni);
        conRigaInPiu.add(new String[] {"*", "ARRYFILE", "*", "5", "1"});
        assertNotEquals(maschereAttese("mirato", conRigaInPiu), maschereTrovate("mirato"));
    }

    private static List<String[]> esclusioni() throws IOException {
        List<String[]> righe = new ArrayList<>();
        for (String r : Files.readAllLines(radice().resolve("esclusioni.tsv"), StandardCharsets.UTF_8)) {
            if (!r.startsWith("#") && !r.startsWith("scenario\t") && !r.isEmpty()) {
                righe.add(r.split("\t", -1));
            }
        }
        return righe;
    }

    /** Insieme "file chiave posizione" dei byte esclusi, dalle righe di esclusioni.tsv. */
    private static TreeSet<String> maschereAttese(String nome, List<String[]> esclusioni) throws IOException {
        Path scenario = ComparatoreReadacct.scenario(nome);
        TreeSet<String> attese = new TreeSet<>();
        for (String[] c : esclusioni) {
            if (!(c[0].equals("*") || c[0].equals(nome))) {
                continue;
            }
            for (String chiave : chiavi(scenario)) {
                if (c[2].equals("*") || c[2].equals(chiave)) {
                    for (int i = 0; i < Integer.parseInt(c[4]); i++) {
                        attese.add(c[1] + " " + chiave + " " + (Integer.parseInt(c[3]) + i));
                    }
                }
            }
        }
        return attese;
    }

    private static List<String> chiavi(Path scenario) throws IOException {
        List<String> chiavi = new ArrayList<>();
        byte[] ingresso = Files.readAllBytes(scenario.resolve("ingresso.rec"));
        for (int p = 0; p < ingresso.length; p += ContiDiProva.LUNGHEZZA_RECORD) {
            chiavi.add(new String(ingresso, p, 11, StandardCharsets.US_ASCII));
        }
        return chiavi;
    }

    /** Insieme "file chiave posizione" dei {@code **} nei tre riferimenti (chiave: ACCT-ID dell'ingresso, per ordine). */
    private static TreeSet<String> maschereTrovate(String nome) throws IOException {
        Path scenario = ComparatoreReadacct.scenario(nome);
        List<String> chiavi = chiavi(scenario);
        TreeSet<String> trovate = new TreeSet<>();
        aggiungi(trovate, "OUTFILE", ComparatoreReadacct.leggiRiferimentoFisso(scenario.resolve("OUTFILE.riferimento.txt"), 107),
                chiavi, 1);
        aggiungi(trovate, "ARRYFILE", ComparatoreReadacct.leggiRiferimentoFisso(scenario.resolve("ARRYFILE.riferimento.txt"), 110),
                chiavi, 1);
        List<ComparatoreReadacct.Riferimento> vbrc = ComparatoreReadacct.leggiRiferimentoVariabile(
                scenario.resolve("VBRCFILE.riferimento.txt"));
        for (int r = 0; r < vbrc.size(); r++) {
            aggiungi(trovate, r % 2 == 0 ? "VBRC1" : "VBRC2", List.of(vbrc.get(r)), List.of(chiavi.get(r / 2)), 1);
        }
        return trovate;
    }

    private static void aggiungi(TreeSet<String> insieme, String file, List<ComparatoreReadacct.Riferimento> record,
            List<String> chiavi, int base) {
        assertEquals(chiavi.size(), record.size(), "record di " + file);
        for (int r = 0; r < record.size(); r++) {
            int[] b = record.get(r).byteAttesi();
            for (int i = 0; i < b.length; i++) {
                if (b[i] < 0) {
                    insieme.add(file + " " + chiavi.get(r) + " " + (i + base));
                }
            }
        }
    }
}
