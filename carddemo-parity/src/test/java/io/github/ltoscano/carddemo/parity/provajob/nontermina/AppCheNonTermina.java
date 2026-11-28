package io.github.ltoscano.carddemo.parity.provajob.nontermina;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Applicazione di prova dei test (issue #65, rilievo 2 del Validatore), non di produzione e senza
 * Spring: avvia un figlio ({@code sh}) che avvia un nipote ({@code sleep}), scrive i tre pid nel file
 * indicato dalla variabile d'ambiente {@code MENB_PID_FILE} e non termina. Serve a provare che allo
 * scadere del limite di tempo AvvioJob termina l'intero albero.
 */
public final class AppCheNonTermina {

    private AppCheNonTermina() {
    }

    public static void main(String[] args) throws Exception {
        Path file = Path.of(System.getenv("MENB_PID_FILE"));
        Path nipote = Path.of(file + ".nipote");
        Process figlio = new ProcessBuilder("sh", "-c", "sleep 600 & echo $! > '" + nipote + "'; wait")
                .redirectErrorStream(true).redirectOutput(ProcessBuilder.Redirect.DISCARD).start();
        for (int i = 0; i < 200 && (!Files.exists(nipote) || Files.size(nipote) == 0); i++) {
            Thread.sleep(50);
        }
        String pid = ProcessHandle.current().pid() + "\n" + figlio.pid() + "\n"
                + Files.readString(nipote, StandardCharsets.US_ASCII).trim() + "\n";
        Path provvisorio = Path.of(file + ".tmp");
        Files.writeString(provvisorio, pid, StandardCharsets.US_ASCII);
        Files.move(provvisorio, file);
        Thread.sleep(Long.MAX_VALUE);
    }
}
