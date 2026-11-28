package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.ltoscano.carddemo.domain.FieldCategory;
import io.github.ltoscano.carddemo.domain.FieldPicture;
import io.github.ltoscano.carddemo.loader.CampoConto;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * Issue #60, controllo 7: i tracciati confrontati campo per campo direttamente con le righe del
 * contratto dati {@code CVACT01Y.ACCOUNT-RECORD.tsv} letto dal repository (proprieta'
 * {@code menb.contratto.account}), senza passare da altro codice dei test.
 *
 * <ul>
 *   <li>il tracciato del caricatore ({@link CampoConto});</li>
 *   <li>a parte, il modello che usa il codificatore dei test ({@link ContiDiProva#tracciato()}).</li>
 * </ul>
 *
 * <p>Per ogni riga elementare del contratto, FILLER compreso e nello stesso ordine: nome
 * ({@code campo}), posizione ({@code offset}), lunghezza ({@code lunghezza}), categoria (da
 * {@code usage}, {@code pic} e {@code segno}), {@code PICTURE} normalizzata (da {@code lunghezza},
 * {@code cifre_intere}, {@code cifre_decimali}), colonna; e la geometria del codec (lunghezza in byte,
 * cifre intere, scala) uguale alle colonne del contratto. Nessuna riga in piu' o in meno.
 */
class TracciatoContoTest {

    /** Un campo come lo dichiara un tracciato, per il confronto. */
    record Riga(String campo, int offset, int lunghezza, FieldCategory categoria, String picture, String colonna,
            FieldPicture geometria) {
    }

    @Test
    void ilTracciatoDelCaricatoreCoincideRigaPerRigaConIlContratto() throws Exception {
        List<Riga> righe = new ArrayList<>();
        for (CampoConto c : CampoConto.values()) {
            righe.add(new Riga(c.campo(), c.offset(), c.lunghezza(), c.categoria(), c.picture(), c.colonna(), c.geometria()));
        }
        confrontaConIlContratto("caricatore", righe);
        CampoConto ultimo = CampoConto.values()[CampoConto.values().length - 1];
        assertEquals(CampoConto.LUNGHEZZA_RECORD, ultimo.offset() + ultimo.lunghezza(), "fine dell'ultimo campo");
        assertEquals(gruppo().get("lunghezza"), String.valueOf(CampoConto.LUNGHEZZA_RECORD), "lunghezza del record");
    }

    @Test
    void ilModelloDelCodificatoreDeiTestCoincideRigaPerRigaConIlContratto() throws Exception {
        List<Riga> righe = new ArrayList<>();
        for (ContiDiProva.Campo c : ContiDiProva.tracciato()) {
            righe.add(new Riga(c.campo(), c.offset(), c.lunghezza(), c.categoria(), c.picture(), c.colonna(), c.geometria()));
            assertEquals(c.geometria().integerDigits(), c.intere(), "cifre intere del modello per " + c.campo());
            assertEquals(c.geometria().scale(), c.decimali(), "cifre decimali del modello per " + c.campo());
        }
        confrontaConIlContratto("modello dei test", righe);
        assertEquals(gruppo().get("lunghezza"), String.valueOf(ContiDiProva.LUNGHEZZA_RECORD), "lunghezza del record");
    }

    /** Confronto riga per riga con le righe elementari del contratto, lette qui. */
    static void confrontaConIlContratto(String chi, List<Riga> righe) throws Exception {
        List<Map<String, String>> contratto = righeDelContratto();
        assertTrue(contratto.size() > 1, "contratto senza campi elementari");
        System.out.println("[tracciato] " + chi + ": " + righe);
        assertEquals(contratto.size(), righe.size(), chi + ": numero di campi elementari");
        for (int i = 0; i < contratto.size(); i++) {
            Map<String, String> t = contratto.get(i);
            Riga r = righe.get(i);
            String dove = chi + ", riga " + (i + 1) + " (" + t.get("campo") + "): ";
            assertEquals("DISPLAY", t.get("usage"), dove + "USAGE fuori dalla regola");
            assertEquals(t.get("campo"), r.campo(), dove + "nome");
            assertEquals(Integer.parseInt(t.get("offset")), r.offset(), dove + "posizione");
            assertEquals(Integer.parseInt(t.get("lunghezza")), r.lunghezza(), dove + "lunghezza");
            boolean testo = t.get("pic").startsWith("X");
            FieldCategory categoria = testo ? FieldCategory.ALPHANUMERIC
                    : "S".equals(t.get("segno")) ? FieldCategory.DISPLAY_SIGNED : FieldCategory.DISPLAY_UNSIGNED;
            assertEquals(categoria, r.categoria(), dove + "categoria");
            String picture;
            int intere = 0;
            int decimali = 0;
            if (testo) {
                picture = "X(" + Integer.parseInt(t.get("lunghezza")) + ")";
            } else {
                intere = Integer.parseInt(t.get("cifre_intere"));
                decimali = Integer.parseInt(t.get("cifre_decimali"));
                picture = ("S".equals(t.get("segno")) ? "S" : "") + "9(" + intere + ")" + (decimali > 0 ? "V9(" + decimali + ")" : "");
            }
            assertEquals(picture, r.picture(), dove + "PICTURE normalizzata");
            assertEquals("FILLER".equals(t.get("campo")) ? null : t.get("campo").toLowerCase(Locale.ROOT).replace('-', '_'),
                    r.colonna(), dove + "colonna");
            assertEquals(Integer.parseInt(t.get("lunghezza")), r.geometria().length(), dove + "lunghezza della geometria");
            assertEquals(intere, r.geometria().integerDigits(), dove + "cifre intere della geometria");
            assertEquals(decimali, r.geometria().scale(), dove + "scala della geometria");
            assertEquals(categoria, r.geometria().category(), dove + "categoria della geometria");
        }
    }

    /** Righe elementari del contratto, come mappe intestazione → valore, nell'ordine del file. */
    static List<Map<String, String>> righeDelContratto() throws Exception {
        List<Map<String, String>> out = new ArrayList<>();
        for (Map<String, String> r : tutteLeRighe()) {
            if ("elementare".equals(r.get("tipo"))) {
                out.add(r);
            }
        }
        return out;
    }

    /** Il gruppo ACCOUNT-RECORD di livello 01 (prima riga del contratto). */
    static Map<String, String> gruppo() throws Exception {
        Map<String, String> g = tutteLeRighe().get(0);
        assertEquals("ACCOUNT-RECORD", g.get("campo"), "prima riga del contratto");
        assertEquals("01", g.get("livello"), "livello del gruppo");
        return g;
    }

    private static List<Map<String, String>> tutteLeRighe() throws Exception {
        List<String> righe = Files.readAllLines(AccountContrattoTest.fileContratto(), StandardCharsets.UTF_8);
        List<String> intestazione = Arrays.asList(righe.get(0).split("\t", -1));
        List<Map<String, String>> out = new ArrayList<>();
        for (int i = 1; i < righe.size(); i++) {
            String[] v = righe.get(i).split("\t", -1);
            assertEquals(intestazione.size(), v.length, "colonne della riga " + (i + 1) + " del contratto");
            Map<String, String> m = new LinkedHashMap<>();
            for (int k = 0; k < v.length; k++) {
                m.put(intestazione.get(k), v[k]);
            }
            out.add(m);
        }
        return out;
    }
}
