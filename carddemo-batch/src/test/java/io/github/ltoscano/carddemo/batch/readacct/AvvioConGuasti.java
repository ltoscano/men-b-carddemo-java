package io.github.ltoscano.carddemo.batch.readacct;

import io.github.ltoscano.carddemo.batch.BatchApplication;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.support.GenericApplicationContext;

/**
 * Applicazione dei soli test, lanciata da {@link ReadacctProcessoTest} in un processo proprio: l'applicazione
 * batch vera ({@link BatchApplication}, profilo {@code test}, standard output vero tramite
 * {@link UscitaConsole#standardOutput()}, uscita con {@code System.exit(SpringApplication.exit(...))} come nel
 * {@code main} di produzione), con al posto della tabella dei conti e dei file la sorgente finta e i file con
 * guasti di {@link Prove}. Due conti in ingresso.
 *
 * <p>Argomenti: il nome di un {@link GuastoDiProva}, poi gli argomenti dell'applicazione. Se all'apertura della
 * sorgente dei conti uno dei tre file di uscita esiste ancora, scrive {@value #SENTINELLA} sullo standard error.
 * Non e' un componente (nessuna annotazione): la scansione dei componenti non la vede.
 */
final class AvvioConGuasti {

    static final String SENTINELLA = "MENB-PROVA: FILE DI USCITA PRESENTE ALL'APERTURA DEI CONTI";

    private AvvioConGuasti() {
    }

    public static void main(String[] args) {
        GuastoDiProva guasto = GuastoDiProva.valueOf(args[0]);
        String[] applicazione = Arrays.copyOfRange(args, 1, args.length);
        Prove.Conti conti = new Prove.Conti(List.of(Prove.esempio1(), Prove.conDebito(Prove.esempio1(), 2, "0.00")));
        Prove.Uscite uscite = new Prove.Uscite(new Prove.Registro());
        guasto.applica(conti, uscite);
        List<Path> percorsi = new ArrayList<>();
        for (String a : applicazione) {
            for (String dd : List.of("OUTFILE=", "ARRYFILE=", "VBRCFILE=")) {
                if (a.startsWith(dd)) {
                    percorsi.add(Path.of(a.substring(dd.length())));
                }
            }
        }
        conti.sorvegliati = percorsi;
        ApplicationContextInitializer<GenericApplicationContext> sostituti = contesto -> {
            contesto.registerBean("sorgenteContiDiProva", SorgenteConti.class, () -> conti, d -> d.setPrimary(true));
            contesto.registerBean("apertureUsciteDiProva", ApertureUscite.class, () -> uscite, d -> d.setPrimary(true));
        };
        ConfigurableApplicationContext contesto = new SpringApplicationBuilder(BatchApplication.class).profiles("test")
                .initializers(sostituti).run(applicazione);
        if (conti.presentiAllApertura != null && conti.presentiAllApertura.contains(Boolean.TRUE)) {
            System.err.println(SENTINELLA);
        }
        System.exit(SpringApplication.exit(contesto));
    }
}
