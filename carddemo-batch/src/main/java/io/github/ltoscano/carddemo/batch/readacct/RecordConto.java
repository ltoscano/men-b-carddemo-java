package io.github.ltoscano.carddemo.batch.readacct;

import java.math.BigDecimal;

/**
 * Valori di {@code ACCOUNT-RECORD} ({@code COPY CVACT01Y}, {@code CVACT01Y.cpy:4-17}) letti da una riga
 * della tabella {@code account}: un componente per campo elementare, nell'ordine del copybook, tranne il
 * {@code FILLER}, che non ha colonna (sono 178 spazi, ricomposti da {@link Cvact01y}). Gli importi sono
 * {@link BigDecimal} con la scala della colonna ({@code NUMERIC(12,2)}); i testi hanno la lunghezza piena
 * del campo, spazi finali compresi (contratto della tabella, issue #59).
 *
 * @param acctId {@code ACCT-ID PIC 9(11)}
 * @param acctActiveStatus {@code ACCT-ACTIVE-STATUS PIC X(01)}
 * @param acctCurrBal {@code ACCT-CURR-BAL PIC S9(10)V99}
 * @param acctCreditLimit {@code ACCT-CREDIT-LIMIT PIC S9(10)V99}
 * @param acctCashCreditLimit {@code ACCT-CASH-CREDIT-LIMIT PIC S9(10)V99}
 * @param acctOpenDate {@code ACCT-OPEN-DATE PIC X(10)}
 * @param acctExpiraionDate {@code ACCT-EXPIRAION-DATE PIC X(10)} (refuso del copybook conservato)
 * @param acctReissueDate {@code ACCT-REISSUE-DATE PIC X(10)}
 * @param acctCurrCycCredit {@code ACCT-CURR-CYC-CREDIT PIC S9(10)V99}
 * @param acctCurrCycDebit {@code ACCT-CURR-CYC-DEBIT PIC S9(10)V99}
 * @param acctAddrZip {@code ACCT-ADDR-ZIP PIC X(10)}
 * @param acctGroupId {@code ACCT-GROUP-ID PIC X(10)}
 */
public record RecordConto(BigDecimal acctId, String acctActiveStatus, BigDecimal acctCurrBal,
        BigDecimal acctCreditLimit, BigDecimal acctCashCreditLimit, String acctOpenDate, String acctExpiraionDate,
        String acctReissueDate, BigDecimal acctCurrCycCredit, BigDecimal acctCurrCycDebit, String acctAddrZip,
        String acctGroupId) {
}
