package io.github.ltoscano.carddemo.domain;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Reader of the test vectors of #23 ({@code analysis/data-codec/vettori/*.tsv}), with the same
 * grammar as {@code analysis/data-codec/glue/comune.py}: {@code leggi_tsv} (lines 53-71),
 * {@code da_esa} (84-99) and {@code valore_da_testo} (118-140). Anything it does not understand
 * is an error, never a skipped line.
 */
final class VectorFile {

    /**
     * One data line: file name, line number (from 1) and raw text. There is a single
     * representation: the columns are always derived from the raw text, the same text the
     * identifier is computed on, and only {@link VectorFile#read} can build a row (private
     * constructor). {@link #id()} identifies the vector: {@code <file>:<line>:<first 16 hex digits
     * of the SHA-256 of the raw line, UTF-8>}. {@code quality/RapportoSurefire.java} computes the
     * same identifiers from the file and requires each of them, in order, in the report of the run.
     */
    static final class Row {
        private final String file;
        private final int line;
        private final String raw;
        private final List<String> header;

        private Row(String file, int line, String raw, String[] header) {
            this.file = file;
            this.line = line;
            this.raw = raw;
            this.header = List.of(header);
        }

        String file() {
            return file;
        }

        int line() {
            return line;
        }

        String raw() {
            return raw;
        }

        /** The value of a column, split from the raw text (nine columns out of ten: empty note). */
        String get(String column) {
            int c = header.indexOf(column);
            List<String> fields = splitFields(raw, header.size(), "nota".equals(header.get(header.size() - 1)));
            if (c < 0 || fields == null) {
                throw new IllegalStateException("riga " + line + ": colonna assente o riga malformata: " + column);
            }
            return fields.get(c);
        }

        String id() {
            try {
                byte[] h = MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8));
                return file + ":" + line + ":" + HexFormat.of().formatHex(h).substring(0, 16);
            } catch (NoSuchAlgorithmException e) {
                throw new IllegalStateException(e);
            }
        }
    }

    /**
     * Python's {@code str.isspace} for one character: general category Zs, or bidirectional class
     * WS, B or S. Wider than {@link Character#isWhitespace} (it includes U+00A0, U+2007, U+202F,
     * U+001C-U+001F, U+0085).
     */
    static boolean pythonSpace(int c) {
        byte dir = Character.getDirectionality(c);
        return Character.getType(c) == Character.SPACE_SEPARATOR
                || dir == Character.DIRECTIONALITY_WHITESPACE
                || dir == Character.DIRECTIONALITY_PARAGRAPH_SEPARATOR
                || dir == Character.DIRECTIONALITY_SEGMENT_SEPARATOR;
    }

    /** {@code not r.strip()} in Python: the line is empty or made only of Python whitespace. */
    static boolean blank(String line) {
        return line.codePoints().allMatch(VectorFile::pythonSpace);
    }

    private static final Pattern HEX_TOKEN = Pattern.compile("([0-9A-F]{2})(?:\\*([1-9][0-9]*))?");
    private static final Pattern NUMBER = Pattern.compile("-?[0-9]+(\\.[0-9]+)?");
    private static final Pattern PIECE = Pattern.compile("\"((?:[^\"\\\\]|\\\\.)*)\"(?:\\*([1-9][0-9]*))?(?: |$)");

    private VectorFile() {
    }

    /** The columns of a raw line ({@code leggi_tsv}), or null if their number is wrong. */
    static List<String> splitFields(String raw, int columns, boolean optionalNote) {
        List<String> fields = new ArrayList<>(Arrays.asList(raw.split("\t", -1)));
        if (fields.size() == columns - 1 && optionalNote) {
            fields.add("");
        }
        return fields.size() == columns ? fields : null;
    }

    /** {@code leggi_tsv}: header, then rows; blank lines and lines starting with '#' are ignored. */
    static List<Row> read(Path path) throws IOException {
        if (!Files.isRegularFile(path)) {
            throw new IOException("file dei vettori assente o non leggibile: " + path);
        }
        List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
        String[] header = null;
        List<Row> rows = new ArrayList<>();
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            if (blank(line) || line.startsWith("#")) {
                continue;
            }
            if (header == null) {
                header = line.split("\t", -1);
                continue;
            }
            List<String> fields = splitFields(line, header.length, "nota".equals(header[header.length - 1]));
            if (fields == null) {
                throw new IOException(path + ": riga " + (i + 1) + ": " + line.split("\t", -1).length
                        + " colonne invece di " + header.length);
            }
            rows.add(new Row(path.getFileName().toString(), i + 1, line, header));
        }
        if (header == null) {
            throw new IOException(path + ": file vuoto");
        }
        return rows;
    }

    /** {@code da_esa}: bytes separated by single spaces, "HH*n" repeats HH n times. */
    static byte[] hex(String text) {
        if (text.isEmpty() || "-".equals(text)) {
            throw new IllegalArgumentException("esadecimale assente: '" + text + "'");
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (String token : text.split(" ", -1)) {
            Matcher m = HEX_TOKEN.matcher(token);
            if (!m.matches()) {
                throw new IllegalArgumentException("byte esadecimale non valido: '" + token + "' in '" + text + "'");
            }
            int b = Integer.parseInt(m.group(1), 16);
            int times = m.group(2) == null ? 1 : Integer.parseInt(m.group(2));
            for (int k = 0; k < times; k++) {
                out.write(b);
            }
        }
        return out.toByteArray();
    }

    /** {@code valore_da_testo}, numeric case: optional '-', digits, optional fraction. */
    static BigDecimal number(String text) {
        if (!NUMBER.matcher(text).matches()) {
            throw new IllegalArgumentException("valore numerico non in forma canonica: '" + text + "'");
        }
        return new BigDecimal(text);
    }

    /**
     * {@code valore_da_testo}, alphanumeric case: one or more JSON strings separated by one space,
     * each optionally followed by "*n" (repeated n times).
     */
    static String text(String text) {
        if (text.isEmpty()) {
            throw new IllegalArgumentException("valore alfanumerico vuoto");
        }
        StringBuilder out = new StringBuilder();
        Matcher m = PIECE.matcher(text);
        int i = 0;
        while (i < text.length()) {
            m.region(i, text.length());
            if (!m.lookingAt()) {
                throw new IllegalArgumentException("valore alfanumerico non valido dalla posizione " + i + ": " + text);
            }
            String piece = jsonString(m.group(1));
            int times = m.group(2) == null ? 1 : Integer.parseInt(m.group(2));
            out.append(piece.repeat(times));
            i = m.end();
        }
        if (text.endsWith(" ")) {
            throw new IllegalArgumentException("valore alfanumerico con spazio finale fuori dagli apici: " + text);
        }
        return out.toString();
    }

    /** Body of a JSON string (between the quotes), with the JSON escapes; as Python json.loads. */
    private static String jsonString(String body) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < body.length(); i++) {
            char c = body.charAt(i);
            if (c < 0x20) {
                throw new IllegalArgumentException("carattere di controllo non ammesso in una stringa JSON: " + body);
            }
            if (c != '\\') {
                out.append(c);
                continue;
            }
            if (i + 1 >= body.length()) {
                throw new IllegalArgumentException("escape incompleto: " + body);
            }
            char e = body.charAt(++i);
            switch (e) {
                case '"', '\\', '/' -> out.append(e);
                case 'b' -> out.append('\b');
                case 'f' -> out.append('\f');
                case 'n' -> out.append('\n');
                case 'r' -> out.append('\r');
                case 't' -> out.append('\t');
                case 'u' -> {
                    if (i + 4 >= body.length()) {
                        throw new IllegalArgumentException("escape esadecimale incompleto: " + body);
                    }
                    String digits = body.substring(i + 1, i + 5);
                    if (!digits.matches("[0-9a-fA-F]{4}")) {
                        throw new IllegalArgumentException("escape esadecimale non valido: " + body);
                    }
                    out.append((char) Integer.parseInt(digits, 16));
                    i += 4;
                }
                default -> throw new IllegalArgumentException("escape non valido '\\" + e + "': " + body);
            }
        }
        return out.toString();
    }
}
