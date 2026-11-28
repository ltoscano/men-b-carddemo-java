package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Direct tests of the vector reader against the grammar of {@code analysis/data-codec/glue/comune.py}
 * ({@code leggi_tsv}, {@code da_esa}, {@code valore_da_testo}), on temporary files: what it must
 * read, and what it must reject instead of skipping.
 */
class VectorFileTest {

    @TempDir
    Path dir;

    private Path file(String text) throws IOException {
        Path p = dir.resolve("v.tsv");
        Files.writeString(p, text, StandardCharsets.UTF_8);
        return p;
    }

    @Test
    void righeVuoteCommentiENotaFacoltativaComePython() throws IOException {
        String nbsp = String.valueOf((char) 0xA0);
        String text = nbsp + "\n"                       // only U+00A0: blank for str.strip()
                + "# commento\n"
                + "a\tb\tnota\n"
                + " \t \n"                              // spaces and a tab: blank
                + (char) 0x2007 + (char) 0x202F + (char) 0x1C + (char) 0x85 + "\n"   // Python whitespace too
                + "1\t2\tx\n"
                + "# commento in mezzo\n"
                + "3\t4\n"                              // nine columns out of ten: empty note
                + "\n";
        List<VectorFile.Row> rows = VectorFile.read(file(text));
        assertEquals(2, rows.size());
        assertEquals(List.of(6, 8), List.of(rows.get(0).line(), rows.get(1).line()));
        assertEquals("x", rows.get(0).get("nota"));
        assertEquals("", rows.get(1).get("nota"));
        assertEquals("3", rows.get(1).get("a"));
        assertTrue(rows.get(0).id().matches("v\\.tsv:6:[0-9a-f]{16}"), rows.get(0).id());
        // a line with a non-blank character is not blank: it is a data line (and here malformed)
        assertThrows(IOException.class, () -> VectorFile.read(file("a\tb\n" + nbsp + "x\n")));
    }

    @Test
    void righeSconosciuteRifiutateNonSaltate() throws IOException {
        assertThrows(IOException.class, () -> VectorFile.read(file("a\tb\tc\n1\t2\n")), "colonna mancante senza nota");
        assertThrows(IOException.class, () -> VectorFile.read(file("a\tb\tnota\n1\n")), "due colonne mancanti");
        assertThrows(IOException.class, () -> VectorFile.read(file("a\tb\tnota\n1\t2\t3\t4\n")), "colonna in piu'");
        assertThrows(IOException.class, () -> VectorFile.read(file("a\tb\n riga incomprensibile\n")), "riga che non e' un vettore");
        assertThrows(IOException.class, () -> VectorFile.read(file("# solo commenti\n\n")), "file vuoto");
        assertThrows(IOException.class, () -> VectorFile.read(dir.resolve("assente.tsv")), "file assente");
    }

    @Test
    void esadecimale() {
        assertArrayEquals(new byte[] {0x41, 0x20, 0x20, 0x20, 0x2E}, VectorFile.hex("41 20*3 2E"));
        for (String bad : List.of("", "-", "4", "41  42", "41 ", "4g", "41*0", "41*", "41*01", "0x41")) {
            assertThrows(IllegalArgumentException.class, () -> VectorFile.hex(bad), "'" + bad + "'");
        }
        assertThrows(IllegalArgumentException.class, () -> VectorFile.hex("41".toLowerCase(java.util.Locale.ROOT) + " 4a"));
    }

    @Test
    void valori() {
        assertEquals(new BigDecimal("-12.34"), VectorFile.number("-12.34"));
        assertEquals(2, VectorFile.number("0.00").scale());
        for (String bad : List.of("+1", "1.", ".5", "1e3", " 1", "1 ", "--1", "")) {
            assertThrows(IllegalArgumentException.class, () -> VectorFile.number(bad), "'" + bad + "'");
        }
        assertEquals("A" + " ".repeat(3) + ".", VectorFile.text("\"A\" \" \"*3 \".\""));
        assertEquals("", VectorFile.text("\"\""));
        assertEquals("\"\\/" + (char) 0 + (char) 0xFF + "\t", VectorFile.text("\"\\\"\\\\\\/\\u0000\\u00ff\\t\""));
        for (String bad : List.of("", "A", "\"A\" ", "\"A\"\"B\"", "\"A\" B", "\"\\x41\"", "\"\\u00g0\"", "\"\\u00\"",
                "\"A\"*0", "\"" + (char) 9 + "\"")) {
            assertThrows(IllegalArgumentException.class, () -> VectorFile.text(bad), "'" + bad + "'");
        }
    }
}
