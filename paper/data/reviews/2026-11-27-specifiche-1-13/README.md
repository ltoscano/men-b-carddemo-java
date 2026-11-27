# Contestazione avversariale delle specifiche #1 e #13

| | |
| --- | --- |
| Data | 27 novembre 2026 |
| Oggetto | specifiche delle issue #1 (0A-1) e #13 (0B-1), prima di passarle a `ready` |
| Revisore | Codex CLI 0.172, modello `gpt-6.1-sol`, sandbox in sola lettura |
| Primo tentativo | 09:38:44Z → interrotto alle 09:58:43Z: processo fermo in attesa di input (1.199 s persi) |
| Secondo tentativo | 09:59:29Z → 10:02:20Z: 171 s, 72.056 token |
| Esito | 12 rilievi: 2 bloccanti, 9 importanti, 1 minore. Tutti accolti |

`bozze/` contiene le due specifiche com'erano prima; `specifica-*-dopo.md` come sono state pubblicate. Output integrale di Codex in `codex-rilievi.md` (percorsi locali resi relativi).

## Comando

```sh
codex exec -s read-only -o codex-rilievi.md "<prompt>" < /dev/null
```

Senza `< /dev/null` il comando, lanciato da uno script, resta in attesa di input.

## Prompt

> Sei un revisore avversariale di specifiche. Non hai altro contesto oltre a questo repository. In .codex-review/ ci sono sedici bozze di issue (01-12 Wave 0A, 13-16 Wave 0B); i riferimenti #N nelle bozze corrispondono al numero del file. Leggi CLAUDE.md e docs/piano-wave.md per il contesto. Devi contestare SOLO due specifiche, quelle che stanno per essere affidate a un agente esecutore: .codex-review/01.md e .codex-review/13.md. Le altre servono solo a capire le dipendenze. Il sorgente legacy è in legacy/aws-mainframe-modernization-carddemo/ (sola lettura): verifica su di esso ogni affermazione di fatto. Il tuo mandato è falsificare. Per ciascuna delle due specifiche cerca: (1) fatti falsi o imprecisi, con file e riga; (2) criteri di accettazione non eseguibili, ambigui, o che passerebbero con un lavoro sbagliato o incompleto; (3) istruzioni contraddittorie o che un agente non può soddisfare restando nel perimetro di file dichiarato; (4) cose che l'agente dovrà per forza decidere da solo perché la specifica tace; (5) richieste irrealistiche per una sola PR. Non modificare file. Rispondi in italiano con un elenco numerato, ciascun rilievo con: specifica (01 o 13), gravità (bloccante/importante/minore), evidenza, correzione proposta. Niente elogi né riassunti. Massimo 16 rilievi, i più gravi per primi.

## Esito per rilievo

| # | Specifica | Gravità | Rilievo in breve | Correzione applicata |
| ---: | ---: | --- | --- | --- |
| 1 | #1 | bloccante | Se nessuno strumento è adottabile per una capacità, i controlli obbligatori non possono passare | stato `available` / `unavailable` per capacità, con controlli sostitutivi |
| 2 | #13 | bloccante | Ammessa una PR senza workflow, ma richiesta la CI verde | PR in bozza e issue non conclusa finché il workflow manca |
| 3 | #1 | importante | Manifesto limitato ad `app/`, ma altre issue usano `README.md` e `scripts/` | manifesto esteso all'intero submodule |
| 4 | #1 | importante | Ordine alfabetico del comando unico contrario alle dipendenze | file `deps` per cartella e ordine topologico, con test |
| 5 | #13 | importante | Lo scheletro può mancare di ciò che serve a #14 (HTTP, salute) | dipendenze HTTP e salute già in #13; dichiarato cosa #14 potrà modificare |
| 6 | #1 | importante | Il controllo sui tracciati guarda solo le lunghezze totali | tabella attesa a mano di offset, tipo e scala, con campi binari, packed e ridefiniti |
| 7 | #1 | importante | Nessun controllo indipendente sull'analisi JCL | attesi a mano per `POSTTRAN.jcl` |
| 8 | #13 | importante | "Avviabile" non verificato sull'artefatto prodotto | `verify.sh` avvia i jar prodotti; jar ordinari per `parity` |
| 9 | #1 | importante | Confronto delle `COPY` per insieme: si perdono le occorrenze con `REPLACING` diversi | confronto per occorrenza e riga |
| 10 | #1 | importante | Controlli del manifesto solo sui conteggi | confronto dell'elenco completo, con test negativo |
| 11 | #1 | importante | Ambiguo quanti candidati vadano provati | candidati obbligatori e riserve; `non provato` distinto da `scartato` |
| 12 | #13 | minore | "Ultima versione stabile" di Boot e Batch non definita | Boot GA compatibile con Java 21; Batch gestito da Boot; fonte registrata |
