package io.github.ltoscano.carddemo.parity;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import org.junit.jupiter.api.extension.ExtendWith;

/**
 * Marca un caso di test che oggi deve fallire per un motivo dichiarato (issue #65).
 *
 * <p>Il caso risulta riuscito solo se il corpo lancia {@link MotivoDichiarato} con il codice
 * {@link #motivo()}; risulta fallito se lancia altro o se riesce. Ogni caso marcato deve avere la
 * sua riga in {@code quality/fallimenti-attesi.tsv} (classe, metodo, issue, motivo), e ogni riga
 * deve avere la ricevuta della corsa: vedi {@link FallimentoAttesoEstensione} e {@code verify.sh}.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
@ExtendWith(FallimentoAttesoEstensione.class)
@interface FallimentoAtteso {

    /** Issue che togliera' la marcatura. */
    int issue();

    /** Codice del motivo dichiarato, uguale a {@link MotivoDichiarato#codice()} e alla colonna dell'elenco. */
    String motivo();
}
