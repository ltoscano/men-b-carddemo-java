package io.github.ltoscano.carddemo.parity;

/**
 * Fallimento per un motivo dichiarato in anticipo (issue #65). Lo lancia solo chi ha riconosciuto
 * il motivo con una regola esplicita (per READACCT: {@link AvvioJob#verificaJobPresente}); qualunque
 * altro errore resta un errore ordinario e non e' mai un fallimento atteso.
 */
final class MotivoDichiarato extends RuntimeException {

    private static final long serialVersionUID = 1L;

    private final String codice;

    MotivoDichiarato(String codice, String diagnosi) {
        super(codice + ": " + diagnosi);
        this.codice = codice;
    }

    String codice() {
        return codice;
    }
}
