package io.github.ltoscano.carddemo.parity;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * Comparatore delle uscite di READACCT con i riferimenti di #55 (issue #65).
 *
 * <p>Il riferimento e' solo quello di {@code oracle/golden/readacct/generati/golden/<scenario>/}: il
 * comparatore non contiene valori attesi propri sul contenuto e non legge {@code esclusioni.tsv} ne'
 * {@code correzioni.tsv}. Attesi strutturali propri del contratto: lunghezze dei record fissi (107,
 * 110), forma del descrittore dei record variabili, 2 + 15 x N righe di console, codice di uscita 0.
 * Ogni differenza produce un {@link AssertionError} che nomina file, record e posizione (da 1).
 */
final class ComparatoreReadacct {

    static final int OUTFILE = 107;
    static final int ARRYFILE = 110;
    static final int VBRC_MASSIMO = 84;
    static final String OSSERVAZIONE = "#OSSERVAZIONE";

    /** Byte di riferimento: -1 dove il riferimento e' mascherato con {@code **}. */
    record Riferimento(int[] byteAttesi) {
    }

    private ComparatoreReadacct() {
    }

    /** Scenari ammessi come riferimento di parita': lo scenario osservazione di #55 no. */
    static Path scenario(String nome) {
        if (!"esempio".equals(nome) && !"mirato".equals(nome)) {
            throw new AssertionError("SCENARIO-NON-AMMESSO: '" + nome + "' non e' un riferimento di parita' (solo esempio e mirato)");
        }
        String radice = System.getProperty("menb.golden.readacct");
        if (radice == null || radice.isEmpty()) {
            throw new AssertionError("proprieta' menb.golden.readacct assente");
        }
        Path cartella = Path.of(radice, "generati", "golden", nome);
        if (Files.exists(cartella.resolve("MARCATURA"))) {
            try {
                if (Files.readString(cartella.resolve("MARCATURA"), StandardCharsets.ISO_8859_1).contains("OSSERVAZIONE")) {
                    throw new AssertionError("SCENARIO-NON-AMMESSO: " + cartella + " e' marcato OSSERVAZIONE");
                }
            } catch (IOException e) {
                throw new AssertionError("MARCATURA illeggibile in " + cartella, e);
            }
        }
        return cartella;
    }

    /** Confronta le tre uscite in {@code uscite}, la console e il codice di uscita con i riferimenti di {@code scenario}. */
    static void confronta(Path scenario, Path uscite, AvvioJob.Esito esito) throws IOException {
        List<Riferimento> out = leggiRiferimentoFisso(scenario.resolve("OUTFILE.riferimento.txt"), OUTFILE);
        int n = out.size();
        if (esito.uscita() != 0) {
            throw new AssertionError("CODICE-DI-USCITA: atteso 0, trovato " + esito.uscita() + "; " + esito.riassunto());
        }
        confrontaFisso("OUTFILE", uscite.resolve("OUTFILE"), out, OUTFILE);
        List<Riferimento> arry = leggiRiferimentoFisso(scenario.resolve("ARRYFILE.riferimento.txt"), ARRYFILE);
        if (arry.size() != n) {
            throw new AssertionError("RIFERIMENTO: ARRYFILE.riferimento.txt ha " + arry.size() + " record, OUTFILE " + n);
        }
        confrontaFisso("ARRYFILE", uscite.resolve("ARRYFILE"), arry, ARRYFILE);
        List<Riferimento> vbrc = leggiRiferimentoVariabile(scenario.resolve("VBRCFILE.riferimento.txt"));
        if (vbrc.size() != 2 * n) {
            throw new AssertionError("RIFERIMENTO: VBRCFILE.riferimento.txt ha " + vbrc.size() + " record, attesi " + 2 * n);
        }
        confrontaVariabile(uscite.resolve("VBRCFILE"), vbrc);
        confrontaConsole(scenario.resolve("console.riferimento.txt"), esito.stdout(), n);
    }

    /** Riferimento di un file a record fissi: una riga esadecimale per record, {@code **} per byte mascherato. */
    static List<Riferimento> leggiRiferimentoFisso(Path file, int lunghezza) throws IOException {
        List<Riferimento> record = new ArrayList<>();
        int r = 0;
        for (String riga : righe(file)) {
            r++;
            if (riga.length() != 2 * lunghezza) {
                throw new AssertionError("RIFERIMENTO: " + file.getFileName() + " riga " + r + " di " + riga.length()
                        + " caratteri invece di " + 2 * lunghezza);
            }
            record.add(new Riferimento(esadecimale(riga, file, r)));
        }
        return record;
    }

    /** Riferimento di VBRCFILE: righe {@code <numero di 6 cifre> <lunghezza di 3 cifre> <esadecimale>}. */
    static List<Riferimento> leggiRiferimentoVariabile(Path file) throws IOException {
        List<Riferimento> record = new ArrayList<>();
        int r = 0;
        for (String riga : righe(file)) {
            r++;
            String[] parti = riga.split(" ", -1);
            if (parti.length != 3 || !parti[0].equals(String.format("%06d", r)) || !parti[1].matches("[0-9]{3}")
                    || parti[2].length() != 2 * Integer.parseInt(parti[1])) {
                throw new AssertionError("RIFERIMENTO: VBRCFILE.riferimento.txt riga " + r + " non valida: " + riga);
            }
            record.add(new Riferimento(esadecimale(parti[2], file, r)));
        }
        return record;
    }

    private static List<String> righe(Path file) throws IOException {
        String testo = Files.readString(file, StandardCharsets.US_ASCII);
        if (testo.isEmpty() || !testo.endsWith("\n")) {
            throw new AssertionError("RIFERIMENTO: " + file + " vuoto o senza a capo finale");
        }
        return List.of(testo.substring(0, testo.length() - 1).split("\n", -1));
    }

    private static int[] esadecimale(String testo, Path file, int r) {
        int[] b = new int[testo.length() / 2];
        for (int i = 0; i < b.length; i++) {
            String coppia = testo.substring(2 * i, 2 * i + 2);
            if ("**".equals(coppia)) {
                b[i] = -1;
            } else if (coppia.matches("[0-9a-f]{2}")) {
                b[i] = Integer.parseInt(coppia, 16);
            } else {
                throw new AssertionError("RIFERIMENTO: " + file.getFileName() + " riga " + r + " posizione " + (i + 1)
                        + ": coppia non valida '" + coppia + "'");
            }
        }
        return b;
    }

    private static byte[] leggiUscita(String nome, Path file) throws IOException {
        if (!Files.isRegularFile(file)) {
            throw new AssertionError("FILE-ASSENTE: " + nome + " non e' stato scritto: " + file);
        }
        return Files.readAllBytes(file);
    }

    static void confrontaFisso(String nome, Path file, List<Riferimento> riferimento, int lunghezza) throws IOException {
        byte[] dati = leggiUscita(nome, file);
        int completi = dati.length / lunghezza;
        int resto = dati.length % lunghezza;
        int attesi = riferimento.size();
        int comuni = Math.min(completi, attesi);
        for (int r = 0; r < comuni; r++) {
            confrontaRecord(nome, r + 1, riferimento.get(r).byteAttesi(), dati, r * lunghezza, lunghezza);
        }
        if (completi < attesi) {
            if (resto > 0) {
                // record troncato: i suoi byte si confrontano con l'inizio del record di riferimento
                confrontaByte(nome, completi + 1, riferimento.get(completi).byteAttesi(), dati, completi * lunghezza, resto);
                throw new AssertionError(String.format("LUNGHEZZA: %s di %d byte: record %d troncato a %d byte su %d"
                        + " (fine del file all'offset %d)", nome, dati.length, completi + 1, resto, lunghezza, dati.length));
            }
            throw new AssertionError(String.format("NUMERO-DI-RECORD: %s ha %d record, attesi %d: primo record mancante %d"
                    + " (fine del file all'offset %d)", nome, completi, attesi, completi + 1, dati.length));
        }
        int fineAttesa = attesi * lunghezza;
        if (dati.length > fineAttesa) {
            if (resto == 0) {
                throw new AssertionError(String.format("NUMERO-DI-RECORD: %s ha %d record, attesi %d: primo record in eccesso %d"
                        + " all'offset %d", nome, completi, attesi, attesi + 1, fineAttesa));
            }
            throw new AssertionError(String.format("LUNGHEZZA: %s di %d byte: %d byte in eccesso dopo i %d record attesi,"
                    + " dall'offset %d (record %d)", nome, dati.length, dati.length - fineAttesa, attesi, fineAttesa, attesi + 1));
        }
    }

    private static void confrontaRecord(String nome, int record, int[] atteso, byte[] dati, int base, int lunghezza) {
        if (atteso.length != lunghezza) {
            throw new AssertionError("LUNGHEZZA-RECORD: " + nome + " record " + record + " di " + lunghezza
                    + " byte, atteso " + atteso.length);
        }
        confrontaByte(nome, record, atteso, dati, base, lunghezza);
    }

    /** Confronta i primi {@code n} byte del record con il riferimento, saltando i byte mascherati. */
    private static void confrontaByte(String nome, int record, int[] atteso, byte[] dati, int base, int n) {
        for (int i = 0; i < n; i++) {
            int trovato = dati[base + i] & 0xff;
            if (atteso[i] >= 0 && atteso[i] != trovato) {
                throw new AssertionError(String.format("BYTE-DIVERSO: %s record %d posizione %d: atteso %02x, trovato %02x",
                        nome, record, i + 1, atteso[i], trovato));
            }
        }
    }

    /** Record logici di VBRCFILE secondo il contratto: descrittore di 4 byte, lunghezza compresa del descrittore. */
    static List<byte[]> leggiVariabile(byte[] dati) {
        List<byte[]> record = new ArrayList<>();
        AssertionError errore = leggiVariabile(dati, record);
        if (errore != null) {
            throw errore;
        }
        return record;
    }

    /** Legge in {@code record} i record fino al primo descrittore non valido e ne restituisce l'errore (null se nessuno). */
    static AssertionError leggiVariabile(byte[] dati, List<byte[]> record) {
        try {
            leggiFinoAlPrimoErrore(dati, record);
            return null;
        } catch (AssertionError e) {
            return e;
        }
    }

    private static void leggiFinoAlPrimoErrore(byte[] dati, List<byte[]> record) {
        int p = 0;
        while (p < dati.length) {
            int r = record.size() + 1;
            if (dati.length - p < 4) {
                throw new AssertionError("DESCRITTORE: VBRCFILE record " + r + " (byte " + (p + 1) + "): descrittore troncato");
            }
            int lunghezza = ((dati[p] & 0xff) << 8) | (dati[p + 1] & 0xff);
            if (dati[p + 2] != 0 || dati[p + 3] != 0) {
                throw new AssertionError(String.format("DESCRITTORE: VBRCFILE record %d (byte %d): byte 3-4 del descrittore %02x %02x, attesi 00 00",
                        r, p + 1, dati[p + 2] & 0xff, dati[p + 3] & 0xff));
            }
            if (lunghezza < 5 || lunghezza > VBRC_MASSIMO) {
                throw new AssertionError("DESCRITTORE: VBRCFILE record " + r + " (byte " + (p + 1) + "): lunghezza "
                        + lunghezza + " fuori da 5-" + VBRC_MASSIMO);
            }
            if (p + lunghezza > dati.length) {
                throw new AssertionError("DESCRITTORE: VBRCFILE record " + r + " (byte " + (p + 1) + "): lunghezza "
                        + lunghezza + " oltre la fine del file");
            }
            byte[] logico = new byte[lunghezza - 4];
            System.arraycopy(dati, p + 4, logico, 0, logico.length);
            record.add(logico);
            p += lunghezza;
        }
    }

    static void confrontaVariabile(Path file, List<Riferimento> riferimento) throws IOException {
        // i record letti prima di un descrittore non valido si confrontano per primi: la diagnosi e' la prima differenza
        List<byte[]> trovati = new ArrayList<>();
        AssertionError errore = leggiVariabile(leggiUscita("VBRCFILE", file), trovati);
        int comuni = Math.min(trovati.size(), riferimento.size());
        for (int r = 0; r < comuni; r++) {
            byte[] logico = trovati.get(r);
            int[] atteso = riferimento.get(r).byteAttesi();
            if (logico.length != atteso.length) {
                throw new AssertionError("LUNGHEZZA-RECORD: VBRCFILE record " + (r + 1) + " di " + logico.length
                        + " byte, atteso " + atteso.length);
            }
            confrontaRecord("VBRCFILE", r + 1, atteso, logico, 0, logico.length);
        }
        if (errore != null) {
            throw errore;
        }
        if (trovati.size() != riferimento.size()) {
            // offset del primo record mancante o in eccesso: somma dei record letti, ciascuno con il suo descrittore
            int k = Math.min(trovati.size(), riferimento.size());
            long offset = 0;
            for (int r = 0; r < k; r++) {
                offset += trovati.get(r).length + 4;
            }
            throw new AssertionError(String.format("NUMERO-DI-RECORD: VBRCFILE ha %d record, attesi %d: primo record %s %d %s %d",
                    trovati.size(), riferimento.size(), trovati.size() < riferimento.size() ? "mancante" : "in eccesso", k + 1,
                    trovati.size() < riferimento.size() ? "(fine del file all'offset" : "all'offset", offset)
                    + (trovati.size() < riferimento.size() ? ")" : ""));
        }
    }

    /** Colonna (da 1) del primo carattere diverso tra due righe; se una e' l'inizio dell'altra, la lunghezza della piu' corta + 1. */
    static int colonna(byte[] a, byte[] b) {
        int n = Math.min(a.length, b.length);
        for (int i = 0; i < n; i++) {
            if (a[i] != b[i]) {
                return i + 1;
            }
        }
        return n + 1;
    }

    /** Righe dello standard output: ogni riga terminata da LF, nessun CR. */
    static List<byte[]> righeConsole(byte[] stdout) {
        List<byte[]> righe = new ArrayList<>();
        ByteArrayOutputStream riga = new ByteArrayOutputStream();
        for (byte b : stdout) {
            if (b == '\n') {
                righe.add(riga.toByteArray());
                riga.reset();
            } else if (b == '\r') {
                throw new AssertionError("CONSOLE: carattere CR nella riga " + (righe.size() + 1) + " dello standard output");
            } else {
                riga.write(b);
            }
        }
        if (riga.size() > 0) {
            throw new AssertionError("CONSOLE: ultima riga dello standard output senza a capo: «"
                    + new String(riga.toByteArray(), StandardCharsets.ISO_8859_1) + "»");
        }
        return righe;
    }

    static void confrontaConsole(Path riferimento, byte[] stdout, int n) throws IOException {
        List<byte[]> attese = righeConsole(Files.readAllBytes(riferimento));
        if (attese.size() != 2 + 15 * n) {
            throw new AssertionError("RIFERIMENTO: console.riferimento.txt ha " + attese.size() + " righe, attese " + (2 + 15 * n));
        }
        List<byte[]> trovate = righeConsole(stdout);
        int comuni = Math.min(attese.size(), trovate.size());
        for (int i = 0; i < comuni; i++) {
            String attesa = new String(attese.get(i), StandardCharsets.ISO_8859_1);
            if (attesa.startsWith(OSSERVAZIONE)) {
                continue;
            }
            if (!java.util.Arrays.equals(attese.get(i), trovate.get(i))) {
                throw new AssertionError("CONSOLE: riga " + (i + 1) + " colonna " + colonna(attese.get(i), trovate.get(i))
                        + ": attesa «" + attesa + "», trovata «" + new String(trovate.get(i), StandardCharsets.ISO_8859_1) + "»");
            }
        }
        if (trovate.size() < attese.size()) {
            throw new AssertionError("CONSOLE: " + trovate.size() + " righe sullo standard output, attese " + attese.size()
                    + " (2 + 15 x " + n + "): prima riga mancante " + (comuni + 1) + " «"
                    + new String(attese.get(comuni), StandardCharsets.ISO_8859_1) + "»");
        }
        if (trovate.size() > attese.size()) {
            throw new AssertionError("CONSOLE: " + trovate.size() + " righe sullo standard output, attese " + attese.size()
                    + " (2 + 15 x " + n + "): prima riga in eccesso " + (comuni + 1) + " «"
                    + new String(trovate.get(comuni), StandardCharsets.ISO_8859_1) + "»");
        }
    }
}
