import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

/**
 * Controllo delle ricevute dei fallimenti attesi (issue #65), lanciato da verify.sh:
 * {@code java quality/RicevuteFallimentiAttesi.java <elenco.tsv> <cartella ricevute> <id corsa>}.
 *
 * <p>Ogni riga dell'elenco pretende la ricevuta della corsa corrente, con caso, issue e motivo della
 * riga; ogni ricevuta presente deve avere la sua riga. L'elenco e' letto qui con un proprio parser,
 * non con quello dell'estensione dei test. Esce con 0 se tutto torna, 1 altrimenti.
 */
public final class RicevuteFallimentiAttesi {

    private RicevuteFallimentiAttesi() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3 || args[2].isEmpty()) {
            System.err.println("uso: RicevuteFallimentiAttesi <elenco.tsv> <cartella ricevute> <id corsa>");
            System.exit(1);
        }
        Path elenco = Path.of(args[0]);
        Path cartella = Path.of(args[1]);
        String corsa = args[2];
        List<String> attese = new ArrayList<>();
        int errori = 0;
        boolean intestazione = false;
        for (String riga : Files.readAllLines(elenco, StandardCharsets.UTF_8)) {
            if (riga.isEmpty() || riga.startsWith("#")) {
                continue;
            }
            if (!intestazione) {
                if (!riga.equals("classe\tmetodo\tissue\tmotivo")) {
                    System.err.println("ERRORE: intestazione dell'elenco non valida: " + riga);
                    System.exit(1);
                }
                intestazione = true;
                continue;
            }
            String[] c = riga.split("\t", -1);
            if (c.length != 4) {
                System.err.println("ERRORE: riga dell'elenco non valida: " + riga);
                System.exit(1);
            }
            String caso = c[0] + "#" + c[1];
            String nome = caso + ".ricevuta";
            attese.add(nome);
            Path file = cartella.resolve(nome);
            if (!Files.isRegularFile(file)) {
                System.err.println("ERRORE: ricevuta assente per " + caso + " (riga dell'elenco senza fallimento atteso riconosciuto"
                        + " in questa corsa: caso non marcato, non eseguito o fallito per un altro motivo)");
                errori++;
                continue;
            }
            List<String> r = Files.readAllLines(file, StandardCharsets.UTF_8);
            List<String> attesa = List.of("caso=" + caso, "issue=" + c[2], "motivo=" + c[3], "corsa=" + corsa);
            if (r.size() < 5 || !r.subList(0, 4).equals(attesa) || !r.get(4).startsWith("diagnosi=")) {
                System.err.println("ERRORE: ricevuta di " + caso + " non di questa corsa o diversa dalla riga: " + r);
                errori++;
            }
        }
        if (!intestazione) {
            System.err.println("ERRORE: intestazione dell'elenco assente");
            System.exit(1);
        }
        if (Files.isDirectory(cartella)) {
            try (Stream<Path> presenti = Files.list(cartella)) {
                for (Path p : (Iterable<Path>) presenti::iterator) {
                    if (!attese.contains(p.getFileName().toString())) {
                        System.err.println("ERRORE: ricevuta senza riga nell'elenco: " + p.getFileName());
                        errori++;
                    }
                }
            }
        } else if (Files.exists(cartella)) {
            System.err.println("ERRORE: " + cartella + " non e' una cartella");
            errori++;
        }
        if (errori > 0) {
            System.exit(1);
        }
        System.out.println("ricevute dei fallimenti attesi: " + attese.size() + " righe, tutte con la ricevuta della corsa " + corsa);
    }
}
