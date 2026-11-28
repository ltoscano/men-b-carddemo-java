package io.github.ltoscano.carddemo.parity;

import java.io.IOException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import org.junit.jupiter.api.extension.ExtensionContext;
import org.junit.jupiter.api.extension.InvocationInterceptor;
import org.junit.jupiter.api.extension.ReflectiveInvocationContext;

/**
 * Estensione di {@link FallimentoAtteso} (issue #65).
 *
 * <ul>
 *   <li>caso marcato senza la sua riga in elenco, o con issue o motivo diversi dalla riga: fallito;</li>
 *   <li>corpo che lancia {@link MotivoDichiarato} con il codice dichiarato: riuscito, con una ricevuta
 *       (caso, issue, motivo, corsa) nella cartella delle ricevute;</li>
 *   <li>corpo che lancia altro (anche un {@link MotivoDichiarato} con un altro codice): fallito;</li>
 *   <li>corpo che riesce: fallito, con il messaggio che chiede di togliere marcatura e riga.</li>
 * </ul>
 *
 * <p>Parametri di configurazione JUnit, con ripiego sulle proprieta' di sistema omonime:
 * {@value #ELENCO} (file dell'elenco, obbligatorio), {@value #RICEVUTE} (cartella delle ricevute,
 * predefinita {@value #RICEVUTE_PREDEFINITE}), {@value #CORSA} (identificativo della corsa di verify.sh).
 */
final class FallimentoAttesoEstensione implements InvocationInterceptor {

    static final String ELENCO = "menb.fallimenti.elenco";
    static final String RICEVUTE = "menb.fallimenti.ricevute";
    static final String CORSA = "menb.verify.run";
    static final String RICEVUTE_PREDEFINITE = "target/ricevute-fallimento-atteso";
    static final String INTESTAZIONE = "classe\tmetodo\tissue\tmotivo";

    /** Riga dell'elenco: classe qualificata, metodo, issue, motivo. */
    record Riga(String classe, String metodo, int issue, String motivo) {
    }

    @Override
    public void interceptTestMethod(Invocation<Void> invocation, ReflectiveInvocationContext<Method> invocationContext,
            ExtensionContext context) throws Throwable {
        Method metodo = invocationContext.getExecutable();
        FallimentoAtteso marcatura = metodo.getAnnotation(FallimentoAtteso.class);
        if (marcatura == null) {
            invocation.proceed();
            return;
        }
        String classe = metodo.getDeclaringClass().getName();
        String caso = classe + "#" + metodo.getName();
        Riga riga = cerca(leggiElenco(percorso(context, ELENCO, null)), classe, metodo.getName());
        if (riga == null) {
            invocation.skip();
            throw new AssertionError("FALLIMENTO-ATTESO-NON-IN-ELENCO: " + caso
                    + " e' marcato @FallimentoAtteso ma non ha la sua riga in quality/fallimenti-attesi.tsv");
        }
        if (riga.issue() != marcatura.issue() || !riga.motivo().equals(marcatura.motivo())) {
            invocation.skip();
            throw new AssertionError("FALLIMENTO-ATTESO-DIVERSO-DALL-ELENCO: " + caso + ": marcatura issue="
                    + marcatura.issue() + " motivo=" + marcatura.motivo() + ", elenco issue=" + riga.issue()
                    + " motivo=" + riga.motivo());
        }
        try {
            invocation.proceed();
        } catch (MotivoDichiarato e) {
            if (!e.codice().equals(marcatura.motivo())) {
                throw new AssertionError("FALLIMENTO-ATTESO-MOTIVO-DIVERSO: " + caso + " doveva fallire per '"
                        + marcatura.motivo() + "' ed e' fallito per '" + e.codice() + "'", e);
            }
            scriviRicevuta(context, caso, marcatura, e);
            return;
        } catch (Throwable e) {
            throw new AssertionError("FALLIMENTO-ATTESO-MOTIVO-DIVERSO: " + caso + " doveva fallire per '"
                    + marcatura.motivo() + "' ed e' fallito per un altro motivo: " + e, e);
        }
        throw new AssertionError("FALLIMENTO-ATTESO-RIUSCITO: " + caso + " ora riesce: togliere la marcatura"
                + " @FallimentoAtteso e la sua riga da quality/fallimenti-attesi.tsv (issue " + marcatura.issue() + ")");
    }

    private static String parametro(ExtensionContext context, String nome) {
        return context.getConfigurationParameter(nome).orElse(System.getProperty(nome));
    }

    private static Path percorso(ExtensionContext context, String nome, String predefinito) {
        String valore = parametro(context, nome);
        if (valore == null || valore.isEmpty()) {
            if (predefinito == null) {
                throw new AssertionError("FALLIMENTO-ATTESO-CONFIGURAZIONE: parametro " + nome + " assente");
            }
            valore = predefinito;
        }
        return Path.of(valore);
    }

    /** Legge l'elenco: commenti con '#', intestazione obbligatoria, quattro colonne per riga, nessun duplicato. */
    static List<Riga> leggiElenco(Path file) throws IOException {
        List<Riga> righe = new ArrayList<>();
        boolean intestazione = false;
        int n = 0;
        for (String testo : Files.readAllLines(file, StandardCharsets.UTF_8)) {
            n++;
            if (testo.startsWith("#") || testo.isEmpty()) {
                continue;
            }
            if (!intestazione) {
                if (!INTESTAZIONE.equals(testo)) {
                    throw new AssertionError("FALLIMENTO-ATTESO-ELENCO: intestazione non valida alla riga " + n + " di " + file);
                }
                intestazione = true;
                continue;
            }
            String[] colonne = testo.split("\t", -1);
            if (colonne.length != 4 || !colonne[2].matches("[1-9][0-9]{0,8}") || colonne[0].isEmpty()
                    || colonne[1].isEmpty() || colonne[3].isEmpty()) {
                throw new AssertionError("FALLIMENTO-ATTESO-ELENCO: riga " + n + " non valida in " + file + ": " + testo);
            }
            Riga riga = new Riga(colonne[0], colonne[1], Integer.parseInt(colonne[2]), colonne[3]);
            if (cerca(righe, riga.classe(), riga.metodo()) != null) {
                throw new AssertionError("FALLIMENTO-ATTESO-ELENCO: riga duplicata alla riga " + n + " di " + file);
            }
            righe.add(riga);
        }
        if (!intestazione) {
            throw new AssertionError("FALLIMENTO-ATTESO-ELENCO: intestazione assente in " + file);
        }
        return righe;
    }

    private static Riga cerca(List<Riga> righe, String classe, String metodo) {
        for (Riga r : righe) {
            if (r.classe().equals(classe) && r.metodo().equals(metodo)) {
                return r;
            }
        }
        return null;
    }

    private static void scriviRicevuta(ExtensionContext context, String caso, FallimentoAtteso marcatura,
            MotivoDichiarato e) throws IOException {
        String corsa = parametro(context, CORSA);
        Path cartella = percorso(context, RICEVUTE, RICEVUTE_PREDEFINITE);
        Files.createDirectories(cartella);
        String testo = "caso=" + caso + "\nissue=" + marcatura.issue() + "\nmotivo=" + marcatura.motivo()
                + "\ncorsa=" + (corsa == null || corsa.isEmpty() ? "-" : corsa) + "\ndiagnosi="
                + String.valueOf(e.getMessage()).replace('\n', ' ') + "\n";
        Files.writeString(cartella.resolve(caso + ".ricevuta"), testo, StandardCharsets.UTF_8);
        context.publishReportEntry("fallimento-atteso", caso + " issue=" + marcatura.issue() + " motivo=" + marcatura.motivo());
    }
}
