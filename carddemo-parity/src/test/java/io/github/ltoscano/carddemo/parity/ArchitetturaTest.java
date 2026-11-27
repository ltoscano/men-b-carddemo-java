package io.github.ltoscano.carddemo.parity;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.core.importer.ImportOption;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

/**
 * Accessi tra classi dei moduli (#26): codice di produzione di domain, loader, online, batch.
 * Matrice: domain non vede nessuno; loader, online e batch vedono solo domain; parity non e'
 * analizzato (puo' vedere tutti). Contano ereditarieta', firme, annotazioni, campi e metodi.
 */
class ArchitetturaTest {

    private static final String BASE = "io.github.ltoscano.carddemo.";
    private static final List<String> MODULI = List.of("domain", "loader", "online", "batch");

    private static JavaClasses classi;

    @BeforeAll
    static void importa() {
        String[] pacchetti = MODULI.stream().map(m -> BASE + m).toArray(String[]::new);
        classi = new ClassFileImporter()
                .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
                .importPackages(pacchetti);
    }

    @Test
    void l_insieme_analizzato_non_e_vuoto_e_copre_ogni_modulo() {
        assertFalse(classi.isEmpty(), "nessuna classe analizzata");
        for (String modulo : MODULI) {
            boolean presente = false;
            for (JavaClass c : classi) {
                String pacchetto = c.getPackageName();
                if (pacchetto.equals(BASE + modulo) || pacchetto.startsWith(BASE + modulo + ".")) {
                    presente = true;
                    break;
                }
            }
            assertTrue(presente, "nessuna classe analizzata per il modulo " + modulo);
        }
    }

    @Test
    void ogni_modulo_vede_solo_i_moduli_ammessi() {
        Map<String, List<String>> vietati = Map.of(
                "domain", List.of("loader", "online", "batch", "parity"),
                "loader", List.of("online", "batch", "parity"),
                "online", List.of("loader", "batch", "parity"),
                "batch", List.of("loader", "online", "parity"));
        for (String modulo : MODULI) {
            String[] daVietare = vietati.get(modulo).stream()
                    .flatMap(m -> Stream.of(BASE + m, BASE + m + ".."))
                    .toArray(String[]::new);
            noClasses().that().resideInAnyPackage(BASE + modulo, BASE + modulo + "..")
                    .should().dependOnClassesThat().resideInAnyPackage(daVietare)
                    .because("il modulo " + modulo + " non puo' dipendere da quelli vietati")
                    .check(classi);
        }
    }
}
