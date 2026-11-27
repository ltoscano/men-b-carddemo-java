# Contestazione avversariale del piano delle wave (v1)

| | |
| --- | --- |
| Data | 27 novembre 2026 |
| Oggetto | `docs/piano-wave.md` versione 1 e otto bozze di issue della Wave 0A (`bozze-v1/`) |
| Revisore | Codex CLI 0.172, modello `gpt-6.1-sol`, sandbox in sola lettura, nessun contesto oltre al repository |
| Durata | 6 min 26 s (09:21:16Z → 09:27:42Z) |
| Token | 152.899 |
| Esito | 23 rilievi: 5 bloccanti, 17 importanti, 1 minore. Tutti accolti |

Output integrale: `codex-rilievi.md` (i percorsi assoluti locali sono stati resi relativi; nient'altro è stato modificato).

## Comando

```sh
codex exec -s read-only -o codex-rilievi.md "<prompt>"
```

## Prompt

> Sei un revisore avversariale. Non hai altro contesto oltre a questo repository. Leggi CLAUDE.md, docs/piano-wave.md e le otto bozze di issue in .codex-review/ (specifiche della Wave 0A). Il sorgente legacy è in legacy/aws-mainframe-modernization-carddemo/ (sola lettura): usalo per verificare i fatti. Il tuo mandato è falsificare, non aiutare. Cerca: (1) affermazioni di fatto sul legacy che sono false o imprecise (nomi di file, programmi, lunghezze di record, chiavi, chiamate), citando file e riga; (2) criteri di accettazione non eseguibili, aggirabili o che passerebbero anche con un lavoro sbagliato; (3) dipendenze mancanti, cicliche o ordine delle wave sbagliato; (4) perimetri che si sovrappongono tra issue; (5) rischi di migrazione COBOL->Java o dell'oracle GnuCOBOL che il piano ignora; (6) richieste irrealistiche per un agente in una sola issue. Non modificare file. Rispondi in italiano con un elenco numerato di rilievi, ciascuno con: gravità (bloccante/importante/minore), dove, evidenza, correzione proposta. Niente elogi, niente riassunto del piano. Massimo 25 rilievi, i più gravi per primi.

## Verifica dei rilievi

Prima di accoglierli, nove affermazioni di fatto sono state ricontrollate sul sorgente dal pianificatore (rilievi 2, 3, 5, 7, 8, 9, 10, 16, 20): tutte confermate.

## Esito per rilievo

| # | Gravità | Rilievo in breve | Esito | Dove è stato recepito |
| ---: | --- | --- | --- | --- |
| 1 | bloccante | 0A-4 passa anche se nessun batch compila | accolto | 0A-4: insieme obbligatorio di programmi che devono compilare ed essere avviabili |
| 2 | bloccante | Manca il modo di passare il parametro di sistema a `CBACT04C` | accolto | 0A-4: avvio con parametri, con test sui byte ricevuti |
| 3 | bloccante | Indice alternativo di `XREFFILE`: duplicati nel JCL, non nel programma | accolto | 0A-3 (registrare), 0A-6 (due carte per conto) |
| 4 | bloccante | La riesecuzione può arrestarsi con effetti parziali | accolto | piano: l'abend è un risultato; 0A-10 |
| 5 | bloccante | `TRANREPT` legge un file di date che nessuno crea | accolto | 0A-9: manifesto degli input esterni per job |
| 6 | importante | Il contratto dati ignora i record definiti nei programmi | accolto | 0A-3 esteso |
| 7 | importante | Le fonti non concordano sul "ciclo giornaliero" | accolto | piano: scenari scelti dal gate umano dopo 0A-7 |
| 8 | importante | Chiave di `CBEXPORT` incoerente tra JCL e copybook | accolto | 0A-3: confronto DEFINE / SELECT / FD / copybook |
| 9 | importante | I glob `*.cbl` perdono i programmi `.CBL` | accolto | 0A-1: manifesto esplicito; `CLAUDE.md` |
| 10 | importante | Record iniziale di `TRANFILE` a zero binario | accolto | 0A-5: byte invalidi conservati e dichiarati |
| 11 | importante | I controlli del contratto dati non rilevano campi scambiati | accolto | 0A-3: record sentinella |
| 12 | importante | Le fixture possono essere sbagliate e passare | accolto | 0A-5: valori di riferimento indipendenti e round-trip |
| 13 | importante | Copertura della matrice aggirabile | accolto | 0A-11: decisioni e alternative con identificatore |
| 14 | importante | Mancano input di ambiente nella matrice (ora, identificativi, risposte CICS) | accolto | 0A-11 |
| 15 | importante | Confini di transazione CICS non rappresentati | accolto | 0A-11, 0B-4, rischi del Validatore |
| 16 | importante | I menu di base portano ai moduli opzionali | accolto | piano: decisione del gate umano |
| 17 | importante | Bersagli dinamici e job generati dall'online fuori dal grafo | accolto | 0A-2 esteso |
| 18 | importante | Issue che richiedono comandi fuori dal proprio perimetro | accolto | 0A-1: comando unico estendibile per cartella |
| 19 | importante | 0A-1 può chiudersi senza strumento, 0A-3 lo pretende | accolto | 0A-1: per ogni capacità obbligatoria un percorso utilizzabile, o issue di ripiego |
| 20 | importante | Il golden degli interessi non distingue troncamento e arrotondamento | accolto | 0A-6: fixture mirate |
| 21 | importante | Il pilota di signon dipende dai menu della wave dopo | accolto | Wave 2: si verifica solo il confine |
| 22 | importante | Issue troppo grandi (ciclo batch, `COACTUPC`) | accolto | 0A-6 divisa in quattro; online in due tempi |
| 23 | minore | Numerazioni delle wave incoerenti tra documenti | accolto | `CLAUDE.md` rimanda al piano come fonte unica |
