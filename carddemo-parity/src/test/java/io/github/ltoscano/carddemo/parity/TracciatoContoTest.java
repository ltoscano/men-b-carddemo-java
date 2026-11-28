package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;

import io.github.ltoscano.carddemo.loader.CampoConto;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * Issue #60: il tracciato del caricatore ({@link CampoConto}) coincide riga per riga con il contratto
 * dati {@code CVACT01Y.ACCOUNT-RECORD.tsv} letto dal repository (proprieta' {@code menb.contratto.account}):
 * per ogni campo elementare, FILLER compreso e nello stesso ordine, nome, offset, lunghezza,
 * categoria e {@code PICTURE} normalizzata (ricavate dal contratto con la regola di
 * {@link ContiDiProva#normalizza}) e colonna della tabella; nessuna riga in piu' o in meno; la
 * lunghezza del record e' quella del gruppo di livello 01.
 */
class TracciatoContoTest {

    @Test
    void ilTracciatoDelCaricatoreCoincideRigaPerRigaConIlContratto() throws Exception {
        List<String> dalContratto = new ArrayList<>();
        for (ContiDiProva.Campo c : ContiDiProva.tracciato()) {
            dalContratto.add(c.campo() + "|" + c.offset() + "|" + c.lunghezza() + "|" + c.categoria() + "|"
                    + c.picture() + "|" + c.colonna());
        }
        List<String> dalCaricatore = new ArrayList<>();
        for (CampoConto c : CampoConto.values()) {
            dalCaricatore.add(c.campo() + "|" + c.offset() + "|" + c.lunghezza() + "|" + c.categoria() + "|"
                    + c.picture() + "|" + c.colonna());
            assertEquals(c.lunghezza(), c.geometria().length(), "geometria di " + c.campo());
            assertEquals(c.picture(), c.geometria().picture(), "PICTURE della geometria di " + c.campo());
            assertEquals(c.categoria(), c.geometria().category(), "categoria della geometria di " + c.campo());
        }
        System.out.println("[tracciato] dal contratto:  " + dalContratto);
        System.out.println("[tracciato] dal caricatore: " + dalCaricatore);
        assertEquals(dalContratto.size(), dalCaricatore.size(), "numero di campi elementari");
        for (int i = 0; i < dalContratto.size(); i++) {
            assertEquals(dalContratto.get(i), dalCaricatore.get(i), "riga " + (i + 1) + " del tracciato");
        }

        // Lunghezza del record: gruppo ACCOUNT-RECORD (livello 01) del contratto.
        List<String> righe = Files.readAllLines(AccountContrattoTest.fileContratto(), StandardCharsets.UTF_8);
        List<String> intestazione = Arrays.asList(righe.get(0).split("\t", -1));
        String[] gruppo = righe.get(1).split("\t", -1);
        assertEquals("ACCOUNT-RECORD", gruppo[AccountContrattoTest.colonna(intestazione, "campo")], "prima riga del contratto");
        assertEquals("01", gruppo[AccountContrattoTest.colonna(intestazione, "livello")], "livello del gruppo");
        assertEquals(String.valueOf(CampoConto.LUNGHEZZA_RECORD),
                gruppo[AccountContrattoTest.colonna(intestazione, "lunghezza")], "lunghezza del record");
        CampoConto ultimo = CampoConto.values()[CampoConto.values().length - 1];
        assertEquals(CampoConto.LUNGHEZZA_RECORD, ultimo.offset() + ultimo.lunghezza(), "fine dell'ultimo campo");
    }
}
