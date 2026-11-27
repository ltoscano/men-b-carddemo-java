## Obiettivo

Fissare le regole con cui i byte di un campo diventano un valore e viceversa, e dimostrare con record di prova scritti a mano che il contratto dati di #3 è giusto. È il ponte tra il contratto (dove sta ogni campo) e tutto ciò che leggerà o scriverà dati: fixture, loader, confronti di parità.

Classe di rischio: **piena** (dati). Validazione con Codex.

## Dipendenze e perimetro

- Dipende da: #3 (mergiata: `docs/legacy-map/data-contract/`, `analysis/data-contract/`), #4 (oracle, per il profilo GnuCOBOL).
- File ammessi: `analysis/data-codec/**` (nuova analisi: `run.sh`, `check.sh`, `deps`, colla, sentinelle, attesi), `docs/legacy-map/data-contract/codifica.md` (nuovo).
- Sola lettura: i contratti di #3 (`docs/legacy-map/data-contract/contratti/*.tsv`, `contratti.tsv`, `censimento.tsv`), `legacy/`, `oracle/`.
- Fuori ambito: correggere il contratto (se una sentinella lo smentisce: `needs-spec-update` con l'evidenza); decodificare i file di esempio interi (#5); codice Java (#16); file sotto `analysis/tools/`, `analysis/lib/`, `analysis/manifest/`, `analysis/run.sh`, `analysis/data-contract/`.

## Specifica

Tutto gira in container, con il comando `./analysis/run.sh data-codec` e `--check`, secondo le convenzioni delle altre analisi (rigenerazione in cartella temporanea, confronto con i file versionati, prove negative automatiche).

### Regole di codifica

`codifica.md` descrive, per ogni **tipo di rappresentazione** presente nei contratti (ricavati dai contratti stessi, con il conteggio dei campi per tipo: alfanumerico; numerico `DISPLAY` senza segno; numerico `DISPLAY` con segno nell'ultima cifra; `COMP-3`; `COMP`/binario; eventuali altri trovati), la regola byte → valore e valore → byte:
- lunghezza in byte in funzione della `PICTURE`; posizione del punto decimale implicito; riempimento e allineamento;
- per il segno nell'ultima cifra: la tabella completa byte → (cifra, segno), distinta per profilo;
- per `COMP-3`: semiottetti e codici del segno accettati in lettura e prodotto in scrittura;
- per il binario: ordine dei byte e ampiezza.

Due **profili** distinti e dichiarati, mai mescolati:
- `zos-ebcdic`: i byte come sono su z/OS (riferimento: la documentazione IBM Enterprise COBOL, citata per pagina o sezione);
- `oracle-gnucobol`: i byte come li legge e scrive l'oracle di questo repository, con le opzioni di `oracle/cobc.opts` (in particolare `-fsign=EBCDIC`, voce 29 del registro) sui file ASCII di `app/data/ASCII/`. Ogni regola di questo profilo è **osservata**: un programma COBOL di prova compilato con le opzioni dell'oracle scrive e rilegge il campo, e il risultato è confrontato con la regola. Il programma di prova e il modo di eseguirlo stanno in `analysis/data-codec/`; l'immagine dell'oracle si usa in sola lettura (non si ricostruisce con modifiche, non si tocca `oracle/`).

**Valori numerici non validi** (voce 20 del registro): se i byte di un campo numerico non rispettano la regola del tipo, la decodifica conserva i byte, marca il campo come non valido e non gli assegna alcun valore; non converte in zero, non scarta il record. La ricodifica restituisce i byte originali.

### Sentinelle

Per **ogni contratto** di `contratti.tsv` (e, dove un tracciato ha aree `REDEFINES`, per **ogni vista**, perché le aree ridefinite occupano gli stessi byte): un record sentinella per ciascun profilo, scritto a mano come byte (esadecimale), in cui ogni campo ha un valore riconoscibile e **diverso da quello di ogni altro campo dello stesso record**, anche a parità di lunghezza e tipo. Accanto, i valori attesi campo per campo, scritti a mano.

Le sentinelle sono **indipendenti dal contratto sotto prova**: si scrivono leggendo il copybook (file e riga per ogni campo), non generandole dal contratto né dalla colla di decodifica. Il modo in cui se ne garantisce l'indipendenza è dichiarato in `codifica.md`. Se il numero di contratti rende irrealistico scriverle tutte a mano, ci si ferma con `needs-spec-update` proponendo un criterio di selezione motivato: non si riduce l'insieme in silenzio.

Record a lunghezza variabile o con `OCCURS`: contenuto, lunghezza effettiva e capienza massima sono tenuti distinti, e almeno una sentinella copre il caso.

### Controlli

- **Round-trip**: per ogni sentinella, byte → valori (uguali agli attesi) → byte (identici agli originali).
- **Copertura**: ogni contratto e ogni vista hanno la loro sentinella; ogni tipo di rappresentazione ha almeno un valore positivo, uno negativo (se ha segno), lo zero, il massimo, e un caso non valido.
- **Prove negative** (automatiche, ciascuna fallisce per il motivo dichiarato):
  1. per **ogni** contratto, due campi di uguale lunghezza scambiati nel contratto (dove esistono): la decodifica non coincide con gli attesi;
  2. un offset spostato di uno; una scala cambiata; un segno tolto;
  3. un byte alterato in una sentinella; un valore atteso alterato;
  4. un contratto senza sentinella;
  5. una regola del profilo `oracle-gnucobol` alterata nella colla: l'osservazione con il programma di prova la smentisce;
  6. un campo non valido convertito in zero dalla colla: il controllo sui non validi fallisce.

## Invarianti di parità

- Nessun valore inventato per byte non validi. Nessuna normalizzazione (spazi, zeri, segno preferito) in lettura; in scrittura si produce ciò che il profilo prescrive.
- I due profili non si deducono l'uno dall'altro: ogni regola ha la sua fonte.

## Criteri di accettazione

- [ ] `./analysis/run.sh data-codec` termina con 0; `run.sh`, `check.sh`, `deps` esistono e sono eseguibili.
- [ ] `./analysis/run.sh data-codec --check` termina con 0, due volte di seguito, con tutte le prove negative elencate eseguite e riportate una per una.
- [ ] `./analysis/run.sh --all --check` termina con 0.
- [ ] Il numero di sentinelle coincide con il numero di contratti e viste, mostrato da un comando riportato nella PR.
- [ ] `git status --short` vuoto dopo i controlli; `legacy/` invariato; `git diff --name-only origin/main...HEAD` elenca solo file ammessi.
- [ ] CI verde, compreso `analysis-check`.

## Strategia di rollback

Revert del commit di merge: la cartella `analysis/data-codec/` e `codifica.md` spariscono; nulla dipende ancora da essi.

## Limiti per l'agente

- Regole comuni alle analisi: sorgenti enumerati dal manifesto, mai da un glob; legacy letto dal volume Docker sensibile alle maiuscole; immagini e volumi condivisi non si rimuovono né si ricostruiscono con modifiche; nessun comando Docker globale.
- Negli script ogni comando ha l'esito controllato; limite di tempo sui comandi che possono restare in attesa; nessun residuo di una corsa precedente può soddisfare un controllo.
- Non adottare una libreria di decodifica senza provarla contro le sentinelle e registrarla in `codifica.md` (JRecord è tra i non provati: si può provare, non è richiesto).
- Autocontrollo prima della PR come da `paper/data/prompts/esecutore.md`. File temporanei con prefisso `issue23-`. Non mergiare.
