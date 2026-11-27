# Contestazione avversariale delle specifiche #2, #3 e #4

| | |
| --- | --- |
| Data | 27 novembre 2026, 12:31:46Z → 12:36:22Z |
| Revisore | Codex CLI 0.172, `gpt-6.1-sol`, sola lettura, su `main` dopo il merge della PR #18 |
| Durata e costo | 4 min 36 s, 126.820 token |
| Esito | 18 rilievi: 2 bloccanti, 16 importanti. Tutti accolti |

`prima/` contiene le tre specifiche contestate, `dopo/` quelle pubblicate. Output integrale in `codex-rilievi.md`.

## Cosa è cambiato

Il rilievo ricorrente (6 su 18) è che ciascuna specifica conteneva più lavori indipendenti. Le tre issue sono state ristrette e ne sono nate quattro:

| Issue | Prima | Dopo |
| --- | --- | --- |
| #2 | inventario completo e grafo di tutte le dipendenze | solo dipendenze statiche (`COPY`, `CALL`, JCL, transazioni), con schema e occorrenze |
| #22 (nuova) | — | collegamenti `EXEC CICS` |
| #3 | contratto dati con record sentinella | censimento dei tracciati e contratto fisico |
| #23 (nuova) | — | record sentinella a byte fissati e regole di codifica |
| #4 | immagine, 14 programmi, stub, avviatore | immagine, 11 programmi compilabili, avviatore, arresto anomalo |
| #24 (nuova) | — | routine esterne `COBDATFT`, `MVSWAIT`, `CEEDAYS` |
| #25 (nuova) | — | `CBSTM03A`, `CBEXPORT`, `CBIMPORT` |

## Esito per rilievo

| # | Spec. | Gravità | Rilievo in breve | Esito |
| ---: | --- | --- | --- | --- |
| 1 | #4 | bloccante | `CBSTM03A` percorre blocchi di controllo z/OS: non basta togliere i TAB | accolto: `CBSTM03A` esce da #4; adattamento d'esecuzione autorizzato e delimitato in #25 (voce 21 del registro) |
| 2 | #3 | bloccante | Un solo record sentinella è impossibile con aree ridefinite | accolto: una sentinella per vista, in #23 |
| 3 | #3 | importante | I campi dei record variabili stanno in aree di lavoro, non nell'`FD` | accolto: censimento struttura → FD → lunghezza scritta |
| 4 | #4 | importante | Si poteva certificare un programma che non si avvia | accolto: prova di avvio reale per ogni eseguibile |
| 5 | tutte | importante | `--check` è verde anche se il controllo manca | accolto: presenza degli script verificata; il comando dell'oracle fallisce se manca `check.sh` |
| 6 | #2, #3 | importante | Funzioni esistenti indicate nel file sbagliato | accolto: corretti i riferimenti |
| 7 | #4 | importante | `CEE3ABD` è chiamato in due forme | accolto: due chiamanti di prova |
| 8 | #3 | importante | Manca un censimento che dica quali sono i tracciati | accolto: censimento con prove di completezza |
| 9 | #3 | importante | Il round-trip conferma anche un contratto sbagliato | accolto: byte fissati a mano, in #23 |
| 10 | #3 | importante | La rigenerazione poteva partire da output vecchi | accolto: cb2xml rieseguito durante il controllo |
| 11 | #2 | importante | Intere categorie di archi senza verifica | accolto: copertura per ogni tipo di arco; prove negative per categoria |
| 12 | #2 | importante | Gli strumenti non danno la riga delle `CALL` e delle DD | accolto: localizzatore di occorrenze autorizzato e delimitato |
| 13 | #2 | importante | Identità e cardinalità del grafo lasciate all'Esecutore | accolto: schema JSON; occorrenze distinte dagli archi |
| 14 | tutte | importante | Volume e immagini Docker condivisi tra Esecutori in parallelo | accolto: volume predisposto prima del lancio; prefissi distinti; divieto di scrivere nelle risorse condivise |
| 15 | #4 | importante | Semantica degli stub lasciata all'Esecutore; troppi lavori in una PR | accolto: routine in #24 |
| 16 | #3 | importante | Contenuto logico e rappresentazione fisica non distinti | accolto: #3 descrive il contenuto; profili e valori non validi in #23 (voce 20) |
| 17 | #4 | importante | Togliere gli spazi non prova l'equivalenza nel formato fisso | accolto: trasformazione fissata e riapplicata, in #25 |
| 18 | #2 | importante | "Inventario completo" eccede mezzi e perimetro | accolto: categorie non mappate dichiarate nell'inventario |
