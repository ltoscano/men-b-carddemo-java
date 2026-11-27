# Contestazione avversariale delle bozze #24, #25 e #26

| | |
| --- | --- |
| Data | 27 novembre 2026, 15:00:56Z → 15:06:11Z |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #29 |
| Durata e costo | 5 min 15 s, 159.373 token |
| Esito | 17 rilievi: 7 bloccanti, 10 importanti |

Le tre issue erano bozze scritte per linee generali quando erano state divise da altre. La contestazione è servita a trasformarle in specifiche. Output integrale in `codex-rilievi.md`; le specifiche pubblicate di #24 e #26 in `dopo/`.

## Che cosa è cambiato
- **#24** conteneva tre routine indipendenti. Ora riguarda solo `COBDATFT`, che serve al pilota batch. `MVSWAIT` è in #36; `CEEDAYS` è in #37, rinviata perché serve solo a programmi online (voce 44 del registro).
- **`COBDATFT`**: l'assembler contiene due istruzioni che leggono o copiano più byte di quanti ne ha il letterale; quei byte dipendono dalla memoria del programma assemblato. Decisione (voce 42): l'oracle implementa solo i casi interamente determinati dal sorgente e si ferma in modo riconoscibile sugli altri.
- **#25** resta da riscrivere (lo si fa dopo il merge di #24, perché condividono i file della build): la contestazione ha stabilito che i TAB vanno espansi a 4 colonne (a 8 il testo esce dalla colonna 72), che la sola prova di avvio non basta e serve un piccolo scenario con i quattro file indicizzati, e che `CBEXPORT`/`CBIMPORT` vanno in una issue a parte (#38).
- **#26**: `var` vietato nei moduli che trattano importi (voce 43), perché un controllo sul sorgente non vede i tipi dedotti; matrice completa degli archi tra moduli; database vietati anche per via transitiva; regressioni come comando con il motivo del fallimento verificato.
- **Ordine**: le issue sull'oracle condividono i file di `oracle/build/`, quindi vanno in sequenza: #24, poi #25, poi #35, #36, #38.
