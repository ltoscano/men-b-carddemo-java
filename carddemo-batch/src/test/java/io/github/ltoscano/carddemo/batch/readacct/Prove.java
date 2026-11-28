package io.github.ltoscano.carddemo.batch.readacct;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;

/**
 * Strumenti dei test di {@link Cbact01c}: conti scritti a mano, una sorgente dei conti finta con guasti a
 * comando, file di uscita veri (sul disco del test) con guasti a comando, una console in memoria e un
 * registro comune degli effetti (righe di console e scritture, nell'ordine in cui avvengono).
 *
 * <p>Nessun database: la sorgente finta sostituisce l'accesso ai conti per provocare gli errori di ogni
 * fase. La lettura vera da PostgreSQL la provano il test di parita' ({@code carddemo-parity}) e lo smoke.
 */
final class Prove {

    static final HexFormat HEX = HexFormat.of();

    private Prove() {
    }

    /** Un conto con i valori dati come testo (importi con due decimali, testi di lunghezza piena). */
    static RecordConto conto(long id, String stato, String saldo, String limite, String limiteAnticipi, String apertura,
            String scadenza, String riemissione, String creditoCiclo, String debitoCiclo, String cap, String gruppo) {
        return new RecordConto(BigDecimal.valueOf(id), stato, new BigDecimal(saldo), new BigDecimal(limite),
                new BigDecimal(limiteAnticipi), apertura, scadenza, riemissione, new BigDecimal(creditoCiclo),
                new BigDecimal(debitoCiclo), cap, gruppo);
    }

    /** Il primo conto dei dati di esempio (record 1 di {@code ingresso.rec} dello scenario esempio, #55). */
    static RecordConto esempio1() {
        return conto(1, "Y", "194.00", "2020.00", "1020.00", "2014-11-20", "2025-05-20", "2025-05-20", "0.00", "0.00",
                "A000000000", "          ");
    }

    /** Lo stesso conto con un'altra chiave e un altro addebito di ciclo. */
    static RecordConto conDebito(RecordConto c, long id, String debito) {
        return new RecordConto(BigDecimal.valueOf(id), c.acctActiveStatus(), c.acctCurrBal(), c.acctCreditLimit(),
                c.acctCashCreditLimit(), c.acctOpenDate(), c.acctExpiraionDate(), c.acctReissueDate(),
                c.acctCurrCycCredit(), new BigDecimal(debito), c.acctAddrZip(), c.acctGroupId());
    }

    static byte[] hex(String esadecimale) {
        return HEX.parseHex(esadecimale);
    }

    static String latin1(byte[] b) {
        return new String(b, StandardCharsets.ISO_8859_1);
    }

    /** Registro comune degli effetti: {@code C:<riga>} per la console, {@code W:<dd>} per una scrittura. */
    static final class Registro {
        final List<String> eventi = Collections.synchronizedList(new ArrayList<>());
    }

    /** Console in memoria: tiene i byte e registra ogni riga completa nel registro. */
    static final class Console extends OutputStream {
        private final ByteArrayOutputStream tutto = new ByteArrayOutputStream();
        private final ByteArrayOutputStream riga = new ByteArrayOutputStream();
        private final Registro registro;
        int svuotamenti;

        Console(Registro registro) {
            this.registro = registro;
        }

        @Override
        public void write(int b) {
            tutto.write(b);
            if (b == '\n') {
                registro.eventi.add("C:" + latin1(riga.toByteArray()));
                riga.reset();
            } else {
                riga.write(b);
            }
        }

        @Override
        public void flush() {
            svuotamenti++;
        }

        byte[] byteScritti() {
            return tutto.toByteArray();
        }

        /** Le righe della console, senza i LF; l'ultima riga deve essere terminata. */
        List<String> righe() {
            String t = latin1(tutto.toByteArray());
            if (t.isEmpty()) {
                return List.of();
            }
            if (!t.endsWith("\n")) {
                throw new AssertionError("ultima riga della console senza LF: " + t);
            }
            return List.of(t.substring(0, t.length() - 1).split("\n", -1));
        }
    }

    /**
     * Sorgente dei conti finta: restituisce i conti dati nell'ordine dato. Guasti: all'apertura, alla lettura
     * numero {@code guastoLettura} (da 1; 0 nessuno), alla chiusura. Conta aperture e chiusure.
     */
    static final class Conti implements SorgenteConti {
        final List<RecordConto> conti;
        boolean guastoApertura;
        int guastoLettura;
        boolean guastoChiusura;
        int aperture;
        int chiusure;

        Conti(List<RecordConto> conti) {
            this.conti = conti;
        }

        @Override
        public CursoreConti apri() throws Exception {
            aperture++;
            if (guastoApertura) {
                throw new java.sql.SQLException("guasto di prova all'apertura");
            }
            return new CursoreConti() {
                private int letti;

                @Override
                public Optional<RecordConto> prossimo() throws Exception {
                    if (guastoLettura == letti + 1) {
                        throw new java.sql.SQLException("guasto di prova alla lettura " + (letti + 1));
                    }
                    if (letti == conti.size()) {
                        return Optional.empty();
                    }
                    return Optional.of(conti.get(letti++));
                }

                @Override
                public void chiudi() throws Exception {
                    chiusure++;
                    if (guastoChiusura) {
                        throw new java.sql.SQLException("guasto di prova alla chiusura");
                    }
                }
            };
        }
    }

    /**
     * File di uscita veri ({@link ApertureUsciteSuDisco}) con guasti a comando: alla creazione di un DD, alla
     * scrittura numero n di un DD (da 1), alla chiusura di un DD. Ogni scrittura riuscita va nel registro.
     */
    static final class Uscite implements ApertureUscite {
        private final ApertureUsciteSuDisco disco = new ApertureUsciteSuDisco();
        private final Registro registro;
        String guastoCreazione;
        String guastoScritturaDd;
        int guastoScritturaNumero;
        String guastoChiusura;

        Uscite(Registro registro) {
            this.registro = registro;
        }

        @Override
        public FileUscita apri(String dd, Path percorso) throws IOException {
            if (dd.equals(guastoCreazione)) {
                throw new IOException("guasto di prova alla creazione di " + dd);
            }
            FileUscita vero = disco.apri(dd, percorso);
            return new FileUscita() {
                private int scritture;

                @Override
                public void scrivi(byte[] record) throws IOException {
                    scritture++;
                    if (dd.equals(guastoScritturaDd) && scritture == guastoScritturaNumero) {
                        throw new IOException("guasto di prova alla scrittura " + scritture + " di " + dd);
                    }
                    vero.scrivi(record);
                    registro.eventi.add("W:" + dd);
                }

                @Override
                public void chiudi() throws IOException {
                    vero.chiudi();
                    if (dd.equals(guastoChiusura)) {
                        throw new IOException("guasto di prova alla chiusura di " + dd);
                    }
                }
            };
        }
    }
}
