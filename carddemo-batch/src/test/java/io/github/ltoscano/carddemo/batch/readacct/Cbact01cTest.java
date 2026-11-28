package io.github.ltoscano.carddemo.batch.readacct;

import static io.github.ltoscano.carddemo.batch.readacct.Prove.conDebito;
import static io.github.ltoscano.carddemo.batch.readacct.Prove.conto;
import static io.github.ltoscano.carddemo.batch.readacct.Prove.esempio1;
import static io.github.ltoscano.carddemo.batch.readacct.Prove.hex;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
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
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Test di {@link Cbact01c} sui casi che i riferimenti di #55 non coprono (issue #67, controllo 2): addebito di
 * ciclo diverso da zero, ogni riga della tabella degli errori, riesecuzione fallita con file sentinella, forma
 * esatta delle righe di console non confrontate dal test di parita', tabella vuota, data di riemissione non
 * valida, ordine degli effetti. Gli attesi sono scritti a mano dalle regole di {@code docs/programmi/CBACT01C.md}
 * (quelli del conto 1 dei dati di esempio coincidono con le righe 1 dei riferimenti dello scenario esempio).
 */
class Cbact01cTest {

    // Conto 1 dei dati di esempio: record di OUTFILE (byte 77-78 convenzionali 00 00), ARRYFILE, VBRC-REC1/2.
    static final String OUT_E1 = "3030303030303030303031" + "59" + "30303030303030313934307b"
            + "30303030303032303230307b" + "30303030303031303230307b" + "323031342d31312d3230" + "323032352d30352d3230"
            + "3230323530353230" + "0000" + "30303030303030303030307b" + "0000000252500c" + "20202020202020202020";
    static final String ARR_E1 = "3030303030303030303031" + "30303030303030313934307b" + "0000000100500c"
            + "30303030303030313934307b" + "0000000152500c" + "30303030303031303235307d" + "0000000250000d"
            + "30303030303030303030307b" + "0000000000000c" + "30303030303030303030307b" + "0000000000000c" + "20202020";
    static final String VB1_E1 = "303030303030303030303159";
    static final String VB2_E1 = "3030303030303030303031" + "30303030303030313934307b" + "30303030303032303230307b"
            + "32303235";
    static final String SPAZI_178 = " ".repeat(178);

    @TempDir
    Path tmp;

    private final Prove.Registro registro = new Prove.Registro();
    private final Prove.Console console = new Prove.Console(registro);
    private final Prove.Uscite uscite = new Prove.Uscite(registro);

    private Path outfile() {
        return tmp.resolve("OUTFILE");
    }

    private Path arryfile() {
        return tmp.resolve("ARRYFILE");
    }

    private Path vbrcfile() {
        return tmp.resolve("VBRCFILE");
    }

    private Cbact01c programma(Prove.Conti conti) {
        return new Cbact01c(conti, uscite, outfile(), arryfile(), vbrcfile(), console);
    }

    /** Righe di console di un conto come il conto 1 di esempio, con chiave e addebito di ciclo dati (zonati). */
    static List<String> righeE1(String chiave, String debitoZonato) {
        return List.of(
                "ACCT-ID                 :" + chiave,
                "ACCT-ACTIVE-STATUS      :Y",
                "ACCT-CURR-BAL           :00000001940{",
                "ACCT-CREDIT-LIMIT       :00000020200{",
                "ACCT-CASH-CREDIT-LIMIT  :00000010200{",
                "ACCT-OPEN-DATE          :2014-11-20",
                "ACCT-EXPIRAION-DATE     :2025-05-20",
                "ACCT-REISSUE-DATE       :2025-05-20",
                "ACCT-CURR-CYC-CREDIT    :00000000000{",
                "ACCT-CURR-CYC-DEBIT     :" + debitoZonato,
                "ACCT-GROUP-ID           :          ",
                "-------------------------------------------------",
                "VBRC-REC1:" + chiave + "Y",
                "VBRC-REC2:" + chiave + "00000001940{00000020200{2025",
                accountRecordE1(chiave, debitoZonato));
    }

    /** Riga del DISPLAY ACCOUNT-RECORD: i 300 byte del record, CAP, gruppo e i 178 spazi del FILLER compresi. */
    static String accountRecordE1(String chiave, String debitoZonato) {
        return chiave + "Y" + "00000001940{" + "00000020200{" + "00000010200{" + "2014-11-20" + "2025-05-20"
                + "2025-05-20" + "00000000000{" + debitoZonato + "A000000000" + "          " + SPAZI_178;
    }

    private static List<String> con(List<String> prima, String... dopo) {
        List<String> r = new ArrayList<>(prima);
        r.addAll(Arrays.asList(dopo));
        return r;
    }

    private static List<String> concatena(List<List<String>> parti) {
        List<String> r = new ArrayList<>();
        parti.forEach(r::addAll);
        return r;
    }

    private void nessunaUscita() {
        for (Path p : List.of(outfile(), arryfile(), vbrcfile())) {
            assertFalse(Files.exists(p), p.getFileName() + " rimasto dopo la fine anomala");
        }
    }

    private void fineAnomala(Prove.Conti conti, List<String> consoleAttesa) {
        FineAnomala e = assertThrows(FineAnomala.class, () -> programma(conti).esegui());
        assertEquals(consoleAttesa, console.righe(), "console fino al guasto (fase: " + e.fase() + ")");
        nessunaUscita();
    }

    private static byte[] vbrc(String... recordEsadecimali) {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        for (String r : recordEsadecimali) {
            byte[] dati = hex(r);
            b.writeBytes(new byte[] {0x00, (byte) (dati.length + 4), 0x00, 0x00});
            b.writeBytes(dati);
        }
        return b.toByteArray();
    }

    // --- corsa regolare -----------------------------------------------------------------------------------------

    @Test
    void contoDiEsempioUsciteEConsoleEsatte() throws Exception {
        programma(new Prove.Conti(List.of(esempio1()))).esegui();
        assertArrayEquals(hex(OUT_E1), Files.readAllBytes(outfile()), "OUTFILE");
        assertArrayEquals(hex(ARR_E1), Files.readAllBytes(arryfile()), "ARRYFILE");
        assertArrayEquals(hex("00100000" + VB1_E1 + "002b0000" + VB2_E1), Files.readAllBytes(vbrcfile()), "VBRCFILE");
        assertEquals(con(con(List.of(Cbact01c.START), righeE1("00000000001", "00000000000{").toArray(String[]::new)),
                Cbact01c.END), console.righe());
        assertTrue(console.svuotamenti > 0, "la console non e' stata svuotata");
    }

    @Test
    void tabellaVuotaTreFileVuotiEDueRighe() throws Exception {
        // Verificato contro l'oracle GnuCOBOL con un file dei conti vuoto (PR di #67): codice 0, due righe,
        // tre file di 0 byte.
        Prove.Conti conti = new Prove.Conti(List.of());
        programma(conti).esegui();
        assertEquals(List.of(Cbact01c.START, Cbact01c.END), console.righe());
        for (Path p : List.of(outfile(), arryfile(), vbrcfile())) {
            assertTrue(Files.isRegularFile(p), p.getFileName() + " non creato");
            assertEquals(0, Files.size(p), p.getFileName() + " non vuoto");
        }
        assertEquals(1, conti.aperture);
        assertEquals(1, conti.chiusure);
    }

    // --- addebito di ciclo diverso da zero: il programma prosegue, byte 91-97 convenzionali ---------------------
    // Rilievo 2 della validazione 1 della PR #70: si confrontano per intero i tre file (conto interessato e conti
    // successivi), con addebito positivo e negativo, nel primo conto e in uno successivo. Gli attesi sono scritti a
    // mano dai campi (Prove.out, arr, vbrc); quelli del conto 1 coincidono con le righe 1 dei riferimenti di #55.

    /** Confronto integrale dei tre file e della console con gli attesi dei conti dati (chiave, addebito zonato). */
    private void tuttoUgualeAContiE1(long[] chiavi, String[] debitiZonati, String[] debitiOutfile) throws Exception {
        StringBuilder out = new StringBuilder();
        StringBuilder arr = new StringBuilder();
        StringBuilder vb = new StringBuilder();
        List<List<String>> righe = new ArrayList<>();
        righe.add(List.of(Cbact01c.START));
        for (int i = 0; i < chiavi.length; i++) {
            out.append(Prove.outE1(chiavi[i], debitiOutfile[i]));
            arr.append(Prove.arrE1(chiavi[i]));
            vb.append(Prove.vbrcE1(chiavi[i]));
            righe.add(righeE1(Prove.chiave(chiavi[i]), debitiZonati[i]));
        }
        righe.add(List.of(Cbact01c.END));
        assertEquals(out.toString(), Prove.HEX.formatHex(Files.readAllBytes(outfile())), "OUTFILE, tutti i byte");
        assertEquals(arr.toString(), Prove.HEX.formatHex(Files.readAllBytes(arryfile())), "ARRYFILE, tutti i byte");
        assertEquals(vb.toString(), Prove.HEX.formatHex(Files.readAllBytes(vbrcfile())), "VBRCFILE, tutti i byte");
        assertEquals(concatena(righe), console.righe(), "console");
    }

    @Test
    void gliAttesiScrittiAManoCoincidonoConIRiferimentiDelConto1() {
        // I costruttori di attesi di Prove, sul conto 1 di esempio, danno le righe 1 dei riferimenti di #55.
        assertEquals(OUT_E1, Prove.outE1(1, Prove.DEBITO_2525));
        assertEquals(ARR_E1, Prove.arrE1(1));
        assertEquals("00100000" + VB1_E1 + "002b0000" + VB2_E1, Prove.vbrcE1(1));
    }

    @Test
    void addebitoPositivoNelPrimoContoNegativoInUnSuccessivo() throws Exception {
        programma(new Prove.Conti(List.of(conDebito(esempio1(), 1, "10.00"), conDebito(esempio1(), 2, "0.00"),
                conDebito(esempio1(), 3, "-3.50"), conDebito(esempio1(), 4, "0.00")))).esegui();
        tuttoUgualeAContiE1(new long[] {1, 2, 3, 4},
                new String[] {"00000000100{", "00000000000{", "00000000035}", "00000000000{"},
                new String[] {Prove.DEBITO_NON_DETERMINATO, Prove.DEBITO_2525, Prove.DEBITO_NON_DETERMINATO,
                    Prove.DEBITO_2525});
    }

    @Test
    void addebitoNegativoNelPrimoContoPositivoInUnSuccessivo() throws Exception {
        programma(new Prove.Conti(List.of(conDebito(esempio1(), 1, "-0.01"), conDebito(esempio1(), 2, "9999999999.99"),
                conDebito(esempio1(), 3, "0.00")))).esegui();
        tuttoUgualeAContiE1(new long[] {1, 2, 3},
                new String[] {"00000000000J", "99999999999I", "00000000000{"},
                new String[] {Prove.DEBITO_NON_DETERMINATO, Prove.DEBITO_NON_DETERMINATO, Prove.DEBITO_2525});
    }
    // --- forma delle righe di console non confrontate dal test di parita' --------------------------------------

    @Test
    void numericiConSegnoRecordVariabiliEAccountRecordInFormaEsatta() throws Exception {
        RecordConto c = conto(12345678901L, "N", "-1234.57", "9999999999.99", "0.07", "2087-11-26", "2030-01-31",
                "2087-11-26", "12.34", "0.00", "12345-6789", "GRP-0010AB");
        RecordConto d = conto(99999999999L, "Y", "0.00", "-500.01", "-0.01", "2001-02-03", "2004-05-06", "2007-08-09",
                "-56.78", "-9999999999.99", "ZIP 000001", " D E      ");
        programma(new Prove.Conti(List.of(c, d))).esegui();
        List<String> attese = List.of(Cbact01c.START,
                "ACCT-ID                 :12345678901",
                "ACCT-ACTIVE-STATUS      :N",
                "ACCT-CURR-BAL           :00000012345P", // segno sovrapposto: 7 negativo
                "ACCT-CREDIT-LIMIT       :99999999999I", // 9 positivo
                "ACCT-CASH-CREDIT-LIMIT  :00000000000G", // 7 positivo, scala implicita
                "ACCT-OPEN-DATE          :2087-11-26",
                "ACCT-EXPIRAION-DATE     :2030-01-31",
                "ACCT-REISSUE-DATE       :2087-11-26",
                "ACCT-CURR-CYC-CREDIT    :00000000123D", // 4 positivo
                "ACCT-CURR-CYC-DEBIT     :00000000000{", // zero positivo
                "ACCT-GROUP-ID           :GRP-0010AB",
                "-------------------------------------------------",
                "VBRC-REC1:12345678901N",
                "VBRC-REC2:1234567890100000012345P99999999999I2087", // 39 byte
                "12345678901N00000012345P99999999999I00000000000G2087-11-262030-01-312087-11-2600000000123D"
                        + "00000000000{12345-6789GRP-0010AB" + SPAZI_178,
                "ACCT-ID                 :99999999999",
                "ACCT-ACTIVE-STATUS      :Y",
                "ACCT-CURR-BAL           :00000000000{",
                "ACCT-CREDIT-LIMIT       :00000005000J", // 1 negativo
                "ACCT-CASH-CREDIT-LIMIT  :00000000000J",
                "ACCT-OPEN-DATE          :2001-02-03",
                "ACCT-EXPIRAION-DATE     :2004-05-06",
                "ACCT-REISSUE-DATE       :2007-08-09",
                "ACCT-CURR-CYC-CREDIT    :00000000567Q", // 8 negativo
                "ACCT-CURR-CYC-DEBIT     :99999999999R", // 9 negativo
                "ACCT-GROUP-ID           : D E      ",
                "-------------------------------------------------",
                "VBRC-REC1:99999999999Y",
                "VBRC-REC2:9999999999900000000000{00000005000J2007",
                "99999999999Y00000000000{00000005000J00000000000J2001-02-032004-05-062007-08-0900000000567Q"
                        + "99999999999RZIP 000001 D E      " + SPAZI_178,
                Cbact01c.END);
        assertEquals(attese, console.righe());
        assertEquals(10 + 39, attese.get(14).length(), "riga VBRC-REC2: etichetta di 10 caratteri e 39 byte");
        assertEquals(300, attese.get(15).length(), "riga DISPLAY ACCOUNT-RECORD: 300 byte");
        // I tre file per intero (non solo alcune posizioni): primo conto con addebito zero (2525,00) e data
        // riordinata, secondo con addebito negativo (byte convenzionali) e importi negativi.
        assertEquals(Prove.out("12345678901", "N", "00000012345P", "99999999999I", "00000000000G", "2087-11-26",
                "2030-01-31", "20871126", "00000000123D", Prove.DEBITO_2525, "GRP-0010AB")
                + Prove.out("99999999999", "Y", "00000000000{", "00000005000J", "00000000000J", "2001-02-03",
                        "2004-05-06", "20070809", "00000000567Q", Prove.DEBITO_NON_DETERMINATO, " D E      "),
                Prove.HEX.formatHex(Files.readAllBytes(outfile())), "OUTFILE");
        assertEquals(Prove.arr("12345678901", "00000012345P") + Prove.arr("99999999999", "00000000000{"),
                Prove.HEX.formatHex(Files.readAllBytes(arryfile())), "ARRYFILE");
        assertEquals(Prove.vbrc("12345678901", "N", "00000012345P", "99999999999I", "2087")
                + Prove.vbrc("99999999999", "Y", "00000000000{", "00000005000J", "2007"),
                Prove.HEX.formatHex(Files.readAllBytes(vbrcfile())), "VBRCFILE");
    }

    @Test
    void dataDiRiemissioneNonValidaPassaSenzaValidazione() throws Exception {
        RecordConto c = conto(7, "Y", "1.00", "2.00", "3.00", "2020-01-01", "2021-01-01", "ABCDEFGHIJ", "0.00", "0.00",
                "          ", "          ");
        programma(new Prove.Conti(List.of(c))).esegui();
        // OUTFILE 69-76: caratteri 1-4, 6-7, 9-10 dell'ingresso; 77-78 byte convenzionali; i tre file per intero.
        assertEquals(Prove.out("00000000007", "Y", "00000000010{", "00000000020{", "00000000030{", "2020-01-01",
                "2021-01-01", "ABCDFGIJ", "00000000000{", Prove.DEBITO_2525, "          "),
                Prove.HEX.formatHex(Files.readAllBytes(outfile())), "OUTFILE");
        assertEquals(Prove.arr("00000000007", "00000000010{"), Prove.HEX.formatHex(Files.readAllBytes(arryfile())),
                "ARRYFILE");
        assertEquals(Prove.vbrc("00000000007", "Y", "00000000010{", "00000000020{", "ABCD"),
                Prove.HEX.formatHex(Files.readAllBytes(vbrcfile())), "VBRCFILE: VB2-ACCT-REISSUE-YYYY = ABCD");
        assertEquals(List.of(Cbact01c.START,
                "ACCT-ID                 :00000000007",
                "ACCT-ACTIVE-STATUS      :Y",
                "ACCT-CURR-BAL           :00000000010{",
                "ACCT-CREDIT-LIMIT       :00000000020{",
                "ACCT-CASH-CREDIT-LIMIT  :00000000030{",
                "ACCT-OPEN-DATE          :2020-01-01",
                "ACCT-EXPIRAION-DATE     :2021-01-01",
                "ACCT-REISSUE-DATE       :ABCDEFGHIJ",
                "ACCT-CURR-CYC-CREDIT    :00000000000{",
                "ACCT-CURR-CYC-DEBIT     :00000000000{",
                "ACCT-GROUP-ID           :          ",
                "-------------------------------------------------",
                "VBRC-REC1:00000000007Y",
                "VBRC-REC2:0000000000700000000010{00000000020{ABCD",
                "00000000007Y00000000010{00000000020{00000000030{2020-01-012021-01-01ABCDEFGHIJ00000000000{"
                        + "00000000000{" + " ".repeat(20) + SPAZI_178,
                Cbact01c.END), console.righe());
    }

    @Test
    void cobdatftIngressoDueUscitaDue() {
        assertArrayEquals(hex("3230383731313236" + "0000"), Cobdatft.converti("2087-11-26".getBytes(StandardCharsets.US_ASCII)));
        assertArrayEquals(hex("414243444647494a" + "0000"),
                Cobdatft.converti("ABCDEFGHIJ".getBytes(StandardCharsets.US_ASCII)));
    }

    // --- ordine degli effetti ------------------------------------------------------------------------------------

    @Test
    void ordineDegliEffettiPerConto() throws Exception {
        programma(new Prove.Conti(List.of(esempio1(), conDebito(esempio1(), 2, "0.00")))).esegui();
        List<String> atteso = new ArrayList<>();
        atteso.add("C:" + Cbact01c.START);
        for (String chiave : List.of("00000000001", "00000000002")) {
            List<String> righe = righeE1(chiave, "00000000000{");
            righe.subList(0, 12).forEach(r -> atteso.add("C:" + r));
            atteso.add("W:OUTFILE");
            atteso.add("W:ARRYFILE");
            atteso.add("C:" + righe.get(12));
            atteso.add("C:" + righe.get(13));
            atteso.add("W:VBRCFILE");
            atteso.add("W:VBRCFILE");
            atteso.add("C:" + righe.get(14));
        }
        atteso.add("C:" + Cbact01c.END);
        assertEquals(atteso, registro.eventi);
    }

    // --- errori: console esatta fino al guasto, nessun file rimasto ----------------------------------------------

    @Test
    void erroreNellAprireLAccessoAiConti() {
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        conti.guastoApertura = true;
        fineAnomala(conti, List.of(Cbact01c.START, "ERROR OPENING ACCTFILE", "ABENDING PROGRAM"));
    }

    @Test
    void erroreNelLeggereIlPrimoConto() {
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        conti.guastoLettura = 1;
        fineAnomala(conti, List.of(Cbact01c.START, "ERROR READING ACCOUNT FILE", "ABENDING PROGRAM"));
        assertEquals(1, conti.chiusure, "l'accesso ai conti si chiude alla fine anomala");
    }

    @Test
    void erroreAMetaLettura() {
        Prove.Conti conti = new Prove.Conti(List.of(esempio1(), conDebito(esempio1(), 2, "0.00"),
                conDebito(esempio1(), 3, "0.00")));
        conti.guastoLettura = 3;
        fineAnomala(conti, concatena(List.of(List.of(Cbact01c.START), righeE1("00000000001", "00000000000{"),
                righeE1("00000000002", "00000000000{"), List.of("ERROR READING ACCOUNT FILE", "ABENDING PROGRAM"))));
    }

    @Test
    void erroreNelCreareOutfile() {
        uscite.guastoCreazione = "OUTFILE";
        fineAnomala(new Prove.Conti(List.of(esempio1())),
                List.of(Cbact01c.START, "ERROR OPENING OUTFILE", "ABENDING PROGRAM"));
    }

    @Test
    void erroreNelCreareArryfile() {
        uscite.guastoCreazione = "ARRYFILE";
        fineAnomala(new Prove.Conti(List.of(esempio1())),
                List.of(Cbact01c.START, "ERROR OPENING ARRAYFILE", "ABENDING PROGRAM"));
    }

    @Test
    void erroreNelCreareVbrcfile() {
        uscite.guastoCreazione = "VBRCFILE";
        fineAnomala(new Prove.Conti(List.of(esempio1())),
                List.of(Cbact01c.START, "ERROR OPENING VBRC FILE", "ABENDING PROGRAM"));
    }

    @Test
    void erroreNelloScrivereOutfileNienteRigheVbrcNeAccountRecord() {
        uscite.guastoScritturaDd = "OUTFILE";
        uscite.guastoScritturaNumero = 2;
        List<String> secondo = righeE1("00000000002", "00000000000{");
        fineAnomala(new Prove.Conti(List.of(esempio1(), conDebito(esempio1(), 2, "0.00"))),
                concatena(List.of(List.of(Cbact01c.START), righeE1("00000000001", "00000000000{"), secondo.subList(0, 12),
                        List.of("ACCOUNT FILE WRITE STATUS IS:", "ABENDING PROGRAM"))));
    }

    @Test
    void erroreNelloScrivereArryfile() {
        uscite.guastoScritturaDd = "ARRYFILE";
        uscite.guastoScritturaNumero = 1;
        fineAnomala(new Prove.Conti(List.of(esempio1())), concatena(List.of(List.of(Cbact01c.START),
                righeE1("00000000001", "00000000000{").subList(0, 12),
                List.of("ACCOUNT FILE WRITE STATUS IS:", "ABENDING PROGRAM"))));
    }

    @Test
    void erroreNelloScrivereIlPrimoRecordVariabile() {
        uscite.guastoScritturaDd = "VBRCFILE";
        uscite.guastoScritturaNumero = 1;
        fineAnomala(new Prove.Conti(List.of(esempio1())), concatena(List.of(List.of(Cbact01c.START),
                righeE1("00000000001", "00000000000{").subList(0, 14),
                List.of("ACCOUNT FILE WRITE STATUS IS:", "ABENDING PROGRAM"))));
        assertEquals(List.of("W:OUTFILE", "W:ARRYFILE"),
                registro.eventi.stream().filter(e -> e.startsWith("W:")).toList(), "scritture riuscite prima del guasto");
    }

    @Test
    void erroreNelloScrivereIlSecondoRecordVariabile() {
        uscite.guastoScritturaDd = "VBRCFILE";
        uscite.guastoScritturaNumero = 2;
        fineAnomala(new Prove.Conti(List.of(esempio1())), concatena(List.of(List.of(Cbact01c.START),
                righeE1("00000000001", "00000000000{").subList(0, 14),
                List.of("ACCOUNT FILE WRITE STATUS IS:", "ABENDING PROGRAM"))));
    }

    @Test
    void erroreNelChiudereLAccessoAiConti() {
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        conti.guastoChiusura = true;
        fineAnomala(conti, concatena(List.of(List.of(Cbact01c.START), righeE1("00000000001", "00000000000{"),
                List.of("ERROR CLOSING ACCOUNT FILE", "ABENDING PROGRAM"))));
        assertEquals(1, conti.chiusure, "la chiusura fallita non si ripete");
    }

    @Test
    void erroreNelChiudereUnFileDiUscitaDopoLaFineNessunaRigaInPiu() {
        for (String dd : List.of("OUTFILE", "ARRYFILE", "VBRCFILE")) {
            Prove.Registro r = new Prove.Registro();
            Prove.Console c = new Prove.Console(r);
            Prove.Uscite u = new Prove.Uscite(r);
            u.guastoChiusura = dd;
            FineAnomala e = assertThrows(FineAnomala.class, () -> new Cbact01c(new Prove.Conti(List.of(esempio1())), u,
                    outfile(), arryfile(), vbrcfile(), c).esegui());
            assertEquals(Cbact01c.FASE_CHIUSURA_USCITE, e.fase());
            assertEquals(con(con(List.of(Cbact01c.START), righeE1("00000000001", "00000000000{").toArray(String[]::new)),
                    Cbact01c.END), c.righe(), "guasto alla chiusura di " + dd);
            nessunaUscita();
        }
    }

    // --- riesecuzione fallita: i file della corsa precedente non restano -----------------------------------------

    private void sentinelle() throws IOException {
        for (Path p : List.of(outfile(), arryfile(), vbrcfile())) {
            Files.write(p, "SSSSSSSSSSSSSSSSSSSS".getBytes(StandardCharsets.US_ASCII));
        }
    }

    @Test
    void riesecuzioneFallitaAllAperturaConTreFileSentinella() throws Exception {
        sentinelle();
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        conti.guastoApertura = true;
        fineAnomala(conti, List.of(Cbact01c.START, "ERROR OPENING ACCTFILE", "ABENDING PROGRAM"));
    }

    @Test
    void riesecuzioneFallitaInScritturaConTreFileSentinella() throws Exception {
        sentinelle();
        uscite.guastoScritturaDd = "ARRYFILE";
        uscite.guastoScritturaNumero = 2;
        fineAnomala(new Prove.Conti(List.of(esempio1(), conDebito(esempio1(), 2, "0.00"))),
                concatena(List.of(List.of(Cbact01c.START), righeE1("00000000001", "00000000000{"),
                        righeE1("00000000002", "00000000000{").subList(0, 12),
                        List.of("ACCOUNT FILE WRITE STATUS IS:", "ABENDING PROGRAM"))));
    }

    /**
     * Rilievo 4 della validazione 1 della PR #70: non basta lo stato finale, conta il momento. PREDEL
     * (READACCT.jcl:22-28) e' il primo atto: con tre file sentinella, al primo byte della console (il DISPLAY
     * della riga 141) e all'apertura dell'accesso ai conti (0000-ACCTFILE-OPEN) i tre file non ci sono gia' piu'.
     */
    @Test
    void predelPrimaDelPrimoDisplayEDellAperturaDeiConti() throws Exception {
        sentinelle();
        List<Path> uscite = List.of(outfile(), arryfile(), vbrcfile());
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        conti.sorvegliati = uscite;
        console.sorvegliati = uscite;
        programma(conti).esegui();
        assertEquals(List.of(false, false, false), console.presentiAlPrimoDisplay,
                "presenza di OUTFILE, ARRYFILE, VBRCFILE al primo DISPLAY");
        assertEquals(List.of(false, false, false), conti.presentiAllApertura,
                "presenza di OUTFILE, ARRYFILE, VBRCFILE all'apertura dell'accesso ai conti");
        assertEquals(Cbact01c.START, console.righe().get(0));
    }

    @Test
    void predelPrimaDellAperturaAncheQuandoLAperturaFallisce() throws Exception {
        sentinelle();
        List<Path> uscite = List.of(outfile(), arryfile(), vbrcfile());
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        conti.sorvegliati = uscite;
        console.sorvegliati = uscite;
        conti.guastoApertura = true;
        fineAnomala(conti, List.of(Cbact01c.START, "ERROR OPENING ACCTFILE", "ABENDING PROGRAM"));
        assertEquals(List.of(false, false, false), console.presentiAlPrimoDisplay);
        assertEquals(List.of(false, false, false), conti.presentiAllApertura);
    }

    /**
     * Un errore della JVM (un {@link Error}) non e' una fine anomala del programma e non diventa {@link FineAnomala}
     * (il processo esce con il codice di Spring Batch, vedi {@link ReadacctProcessoTest}), ma la pulizia vale:
     * console svuotata, nessuna riga del ramo d'errore, nessuno dei tre file rimasto.
     */
    @Test
    void erroreDellaJvmSvuotaLaConsoleENonLasciaFile() throws Exception {
        sentinelle();
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        conti.erroreGraveApertura = true;
        AssertionError e = assertThrows(AssertionError.class, () -> programma(conti).esegui());
        assertTrue(e.getMessage().startsWith("errore grave di prova"), e.getMessage());
        assertEquals(List.of(Cbact01c.START), console.righe());
        assertTrue(console.svuotamenti > 0, "la console non e' stata svuotata prima di propagare l'errore");
        nessunaUscita();
    }

    @Test
    void riesecuzioneRiuscitaSostituisceIFileSentinella() throws Exception {
        sentinelle();
        programma(new Prove.Conti(List.of(esempio1()))).esegui();
        assertArrayEquals(hex(OUT_E1), Files.readAllBytes(outfile()));
        assertArrayEquals(hex(ARR_E1), Files.readAllBytes(arryfile()));
        assertArrayEquals(vbrc(VB1_E1, VB2_E1), Files.readAllBytes(vbrcfile()));
    }

    // --- lettura: ordine dichiarato ------------------------------------------------------------------------------

    @Test
    void laLetturaDichiaraLOrdineCrescentePerAcctId() {
        // L'indice della chiave primaria puo' restituire le righe in ordine anche senza dichiararlo: si controlla
        // il testo dell'interrogazione.
        String sql = SorgenteContiJdbc.LETTURA.toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", " ").trim();
        assertTrue(sql.startsWith("select acct_id, acct_active_status,"), sql);
        assertTrue(sql.endsWith(" from account order by acct_id"), "ordine per acct_id crescente non dichiarato: " + sql);
        assertEquals(sql.indexOf(" order by "), sql.lastIndexOf(" order by "), sql);
    }
}
