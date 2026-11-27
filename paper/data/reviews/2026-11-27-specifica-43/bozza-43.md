## Obiettivo

Dimostrare con record di prova scritti a mano che i contratti dati di #3 mettono ogni campo al posto giusto, con il tipo giusto. Le regole di codifica (come i byte di un campo diventano un valore) sono già provate da #23; qui si prova la **geometria**: quale campo sta dove.

Classe di rischio: **piena** (dati). Validazione con Codex.

## Dipendenze e perimetro

- Dipende da: #3 (contratti), #23 (colla di decodifica `analysis/data-codec/glue/codec.py`, profilo `oracle-gnucobol`).
- File ammessi: `analysis/data-sentinelle/**` (nuova analisi: `run.sh`, `check.sh`, `deps` con `data-codec`, colla, sentinelle, attesi), `docs/legacy-map/data-contract/sentinelle.md` (nuovo, generato).
- Sola lettura: `analysis/data-codec/**`, `analysis/data-contract/**`, `docs/legacy-map/data-contract/` (tranne il file nuovo), `analysis/tools/`, `analysis/lib/`, `analysis/manifest/`, `analysis/run.sh`, `oracle/`, `legacy/`. La colla di #23 si **usa**, non si copia né si modifica: se non basta (per esempio manca un'interfaccia per decodificare un record intero dato un contratto), ci si ferma con `needs-spec-update`.
- Fuori ambito: correggere un contratto (se una sentinella lo smentisce: `needs-spec-update` con l'evidenza, sorgente alla mano); il profilo `zos-ebcdic`; decodificare i file di esempio (#5).

## Specifica

Comando: `./analysis/run.sh data-sentinelle` e `--check`, con le convenzioni delle altre analisi.

### Quali contratti (decisione delegata, voce 61 del registro)

I **15 contratti definiti nei copybook** elencati in `docs/legacy-map/data-contract/contratti.tsv` (colonna `righe` = `copybook`; alla scrittura: 209 campi elementari, da `COCOM01Y.CARDDEMO-COMMAREA` a `CVTRA06Y.DALYTRAN-RECORD`), più il record variabile `CBACT01C.VBR-REC`. L'elenco si ricava dal file con un comando e il controllo fallisce se un contratto di copybook non ha sentinella. I 43 contratti restanti, dichiarati nei programmi (record di `FD`, per lo più chiave più area dati), non hanno sentinella: lo si dichiara come limite in `sentinelle.md`, con l'elenco.

Un solo profilo, `oracle-gnucobol`: la posizione dei campi non dipende dal profilo.

### Viste

`CVEXPORT.EXPORT-RECORD` ha sei `REDEFINES` (una sul timestamp, cinque sul payload), indipendenti tra loro. Sentinelle: una per ciascuna delle aree del payload (compresa quella base) con il timestamp in forma base, più una con il timestamp ridefinito. L'elenco delle coppie contratto/vista è un file versionato scritto a mano leggendo il copybook; il controllo verifica l'**insieme** delle coppie contro le aree `REDEFINES` presenti nel contratto (colonna `area`), nelle due direzioni.

### Identità dei campi

Nome e percorso non bastano: `CBIMPORT.WS-ERROR-RECORD` ha quattro `FILLER` con lo stesso percorso (non è tra i 15, ma lo stesso può accadere altrove: verificarlo). Identificatore stabile di un campo: contratto, vista, numero d'ordine di dichiarazione nel copybook, indici `OCCURS`. L'offset **non** fa parte dell'identità (è ciò che si prova). Gli attesi hanno cardinalità e unicità verificate: una riga per ogni campo elementare della vista, nessuna in più.

### Sentinelle

Per ogni coppia contratto/vista: il record come byte (esadecimale) e, campo per campo, il valore atteso. Regole:
- scritte **leggendo il copybook** (file e riga per ogni campo, lunghezza ricavata dalla `PICTURE` a mano), non generate dal contratto né dalla colla; `sentinelle.md` dichiara come se ne garantisce l'indipendenza, e la storia Git deve mostrarle committate prima della prima esecuzione della colla su di esse;
- ogni campo ha un valore riconoscibile e **diverso da ogni altro campo dello stesso record**, anche a parità di tipo e lunghezza; nessun campo è tutto spazi o tutto zeri; i `FILLER` hanno anch'essi un contenuto riconoscibile;
- i campi numerici con segno compaiono con valori sia positivi sia negativi nell'insieme delle sentinelle; i campi con decimali hanno cifre decimali diverse da zero;
- la somma delle lunghezze scritte a mano deve dare la lunghezza del record dichiarata nel copybook o nel JCL: è un primo controllo, indipendente dal contratto.

Record variabile `CBACT01C.VBR-REC`: due sentinelle, per i due carichi che il programma scrive davvero (12 e 39 byte, `CBACT01C.cbl` 287-305), con lunghezza effettiva e capienza (80) distinte; i byte oltre la lunghezza effettiva non partecipano al confronto; le intestazioni fisiche su disco sono escluse e lo si dichiara.

### Controlli

- **Decodifica**: ogni sentinella è decodificata con la colla di #23 guidata dal contratto di #3; ogni campo deve dare esattamente il valore atteso, e la ricodifica conservativa deve ridare i byte originali.
- **Copertura**: insieme dei contratti, insieme delle viste, insieme dei campi (per identità), nelle due direzioni.
- **Prove negative** automatiche su **copie private** del contratto, con i metadati ridondanti mantenuti coerenti tra loro (così che fallisca il confronto della decodifica e non un controllo strutturale di #3); la diagnosi nomina campo, valore atteso e valore ottenuto:
  1. per **ogni** contratto, ogni coppia di campi adiacenti di uguale lunghezza e tipo scambiata (dove esiste);
  2. per ogni contratto, un offset spostato di uno con i successivi a cascata; una lunghezza allungata a spese del campo seguente;
  3. una scala cambiata; un segno tolto; un tipo cambiato (`COMP-3` letto come `DISPLAY`);
  4. una vista di `CVEXPORT` scambiata con un'altra;
  5. una sentinella senza un campo atteso; un atteso duplicato; un contratto senza sentinella; un byte alterato in una sentinella; un valore atteso alterato;
  6. una sentinella con due campi dello stesso valore (deve essere rifiutata dal controllo di unicità: altrimenti lo scambio non sarebbe visibile).

`sentinelle.md` (generato): elenco di contratti e viste coperti, numero di campi, elenco dei contratti senza sentinella, limiti.

## Invarianti di parità

- Se una sentinella scritta dal copybook non coincide con il contratto, non si adatta né l'una né l'altro: ci si ferma, sorgente alla mano, e si riferisce chi ha ragione.

## Criteri di accettazione

- [ ] `./analysis/run.sh data-sentinelle` termina con 0 e rigenera senza differenze; `run.sh`, `check.sh`, `deps` esistono e sono eseguibili.
- [ ] `./analysis/run.sh data-sentinelle --check` termina con 0 due volte di seguito, con ogni prova negativa riportata con nome e diagnosi.
- [ ] Un comando riportato nella PR mostra: contratti di copybook nel file dei contratti, coppie contratto/vista con sentinella, campi attesi per coppia e campi elementari della vista nel contratto; i numeri coincidono.
- [ ] `./analysis/run.sh --all --check` termina con 0.
- [ ] `git status --short` vuoto dopo i controlli; `legacy/` invariato; `git diff --name-only origin/main...HEAD` elenca solo file ammessi.
- [ ] CI verde, compreso `analysis-check`.

## Strategia di rollback

Revert del commit di merge: nulla dipende ancora da `analysis/data-sentinelle/`.

## Limiti per l'agente

- Regole comuni alle analisi: legacy letto dal volume Docker sensibile alle maiuscole; immagini e volumi condivisi non si rimuovono né si ricostruiscono con modifiche; nessun comando Docker globale.
- Negli script ogni comando ha l'esito controllato, con gli esiti ammessi dichiarati (attenzione a `$(...)` dentro altri comandi e a `echo … | grep -q` sotto `pipefail`); limite di tempo sui comandi che possono restare in attesa; nessun residuo di una corsa precedente può soddisfare un controllo; i controlli pretendono l'insieme atteso, non "almeno uno".
- Autocontrollo prima della PR come da `paper/data/prompts/esecutore.md`. File di appoggio sull'host con prefisso `issue43-`. Non mergiare.
