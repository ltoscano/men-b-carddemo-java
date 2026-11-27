## Obiettivo

Portare in Java, nel modulo `carddemo-domain`, le regole con cui i byte di un campo COBOL diventano un valore e viceversa (profilo `oracle-gnucobol`), e dimostrare che l'implementazione Java dà **gli stessi risultati** della colla di riferimento su tutti i vettori di prova di #23. È il primo dei contratti condivisi (divisa da #16) e serve al pilota: un programma tradotto deve leggere e scrivere record a larghezza fissa identici, byte per byte, a quelli dell'originale.

Classe di rischio: **piena** (dati, primo codice Java di dominio). Validazione con Codex.

## Dipendenze e perimetro

- Dipende da: #23 (regole e vettori: `docs/legacy-map/data-contract/codifica.md`, `analysis/data-codec/vettori/`), #26 e #27 (regole sul codice, copertura e analisi statica: mergiate).
- File ammessi: `carddemo-domain/src/main/java/**`, `carddemo-domain/src/test/java/**`, `carddemo-domain/src/test/resources/**`, `carddemo-domain/pom.xml` (solo se serve una dipendenza di test già gestita da Spring Boot), `docs/contratti.md` (nuovo: sezione "Codifica dei campi"), `verify.sh` e `quality/**` per: il controllo del rapporto del test dei vettori (vedi sotto), uno **script nuovo** di regressioni per il codec (`quality/regressioni-codec.sh`), e l'adeguamento dichiarato dei conteggi fissi delle regressioni esistenti che cambiano con l'arrivo di classi in `domain` (per esempio `quality/regressioni-copertura.sh` righe 788-789: classi eseguibili e analizzate del modulo).
- Sola lettura: `analysis/**`, `docs/legacy-map/**`, `oracle/`, `legacy/`. I vettori di #23 **non si copiano**: i test li leggono dal repository (vedi sotto).
- Fuori ambito: il profilo `zos-ebcdic`; la lettura di un record intero guidata da un contratto (arriva con le entità, Wave 1); aritmetica sugli importi, stato di conversazione, transazioni, ordinamento, errori (restano in #16); qualsiasi logica di CardDemo.

## Specifica

### Che cosa si implementa

Un piccolo insieme di tipi in `io.github.ltoscano.carddemo.domain` (nomi a scelta, in inglese come il resto del codice Java, documentati) che, per le cinque categorie di `codifica.md` (alfanumerico; `DISPLAY` senza segno; `DISPLAY` con segno nell'ultima cifra; `COMP-3`; `COMP`) e per una `PICTURE` data, offre le stesse tre operazioni della colla di riferimento, tenute distinte:
- **decodifica**: byte → stato (valido, non valido, oltre la `PICTURE`) e, solo se valido, valore; i byte originali restano disponibili;
- **ricodifica conservativa**: restituisce i byte letti (uno zero negativo resta tale);
- **codifica di un valore nuovo**: valore → byte nella rappresentazione che il profilo scrive; un valore non rappresentabile nel campo è rifiutato con un errore esplicito, non troncato in silenzio.
Regole vincolanti del progetto: i valori numerici sono `BigDecimal` (con la scala della `PICTURE`) o interi esatti, **mai** `double`/`float`; nessun valore per i campi non validi né per i binari oltre la `PICTURE` (voci 20 e 63 del registro); un campo incompleto o un offset fuori dal record sono rifiutati prima della conversione; il testo alfanumerico del profilo è una corrispondenza byte per byte dichiarata (quella di `codifica.md`), senza passare per la codifica predefinita della piattaforma.

Nessun contratto "per il futuro": niente lettura di copybook, niente annotazioni, niente generatori. Un bisogno ulteriore è `needs-spec-update`.

### La prova: gli stessi vettori della colla di riferimento

Fonte unica: `analysis/data-codec/vettori/oracle-gnucobol.tsv`. Alla contestazione contiene **375 vettori: 336 di decodifica e 39 di codifica** (25 che riescono, 14 che devono essere rifiutati). Il test li legge tutti dal file del repository, con un lettore che applica la stessa grammatica di quello di riferimento (`analysis/data-codec/glue/comune.py` righe 53-71, 84-99, 118-140: righe di commento anche in mezzo al file, nota finale facoltativa per cui alcune righe hanno nove colonne e non dieci, ripetizioni esadecimali, stringhe concatenate e ripetute). Una riga che il lettore non comprende fa fallire il test: non si scarta in silenzio. I conteggi attesi (375, 336, 39) sono dichiarati nel test.

Due percorsi distinti, secondo la colonna `operazione`:
- **decodifica**: stato; presenza o assenza del valore e, se presente, valore **e scala** (confronto con `equals`, non `compareTo`: una scala restituita sbagliata è un errore); ricodifica conservativa identica all'ingresso; se valido, codifica nuova del valore uguale alla colonna `byte` (che è la rappresentazione scritta dal profilo, non l'ingresso: per lo zero negativo differiscono);
- **codifica**: byte attesi, oppure rifiuto esplicito.
La colonna `move` descrive ciò che fa il COBOL in assegnazione (anche troncando) e **non** è un atteso per il Java.

`oracle-oltre-picture.tsv` ha un altro formato (variante, ingresso, e le osservazioni di `MOVE`, somma e riscrittura) e contiene gli stessi dieci casi già presenti tra i 375: se ne usa solo ingresso e variante, con atteso "oltre la `PICTURE`", nessun valore, ricodifica identica all'ingresso. I risultati aritmetici e di riscrittura non si implementano né si confrontano.

**Controlli esaustivi, come nella prova di riferimento** (i soli vettori non bastano: un parser che accetti `+123` in un `9(4)` li passa tutti): per ogni variante `DISPLAY`, con e senza segno, tutti i 256 valori dell'ultimo byte e del primo byte del corpo, contro una regola scritta nel test in modo indipendente dal codice di decodifica (come `analysis/data-codec/glue/verifica.py` righe 20-22 e 336-356). In particolare un segno iniziale in un campo senza segno è non valido.

**Offset.** Ogni vettore di decodifica è provato anche dentro un record più lungo, a un offset positivo, tra byte di guardia diversi prima e dopo (come `verifica.py` 425-429): valore e byte conservati devono appartenere solo al campo. Un codec che controlla i limiti e poi legge dall'inizio deve fallire.

**Dove gira il test.** `./verify.sh` monta l'intero repository, quindi il file è raggiungibile; la build delle immagini (`docker/app.Dockerfile`) copia solo POM, regole e moduli ed esegue i test senza quel file. Comportamento fissato qui, senza toccare il Dockerfile: il test dei vettori è **obbligatorio quando è presente la proprietà di sistema `menb.verify.run`**, che `verify.sh` passa già a Maven (in quel caso l'assenza del file è un fallimento), ed è **saltato, comparendo come saltato**, quando la proprietà manca (build delle immagini). Perché questo non diventi un modo di passare a vuoto, `verify.sh` controlla dopo Maven, con lo stesso meccanismo usato per il rapporto dei test di integrazione, che nel rapporto di questa corsa il test dei vettori risulti eseguito con il numero atteso di casi e zero saltati.

Test scritti a mano per ciò che i vettori non coprono: campo incompleto e offset fuori dal record per ogni categoria; valore non rappresentabile in codifica; **cifre frazionarie non rappresentabili rifiutate, scale diverse accettate quando la conversione è esatta** (come la colla: per `S9(4)V9(2)` si accettano `1`, `1.2`, `1.20`, `1.200` e si rifiuta `1.234`).

**Nessun passaggio per `double`.** Le regole di #26 sono un controllo sul testo e non vedono i tipi impliciti delle espressioni (limite dichiarato in `docs/sviluppo.md`: `BigDecimal.valueOf(Math.pow(10, scale))` passa). Non le si dichiara una garanzia. Si richiede una verifica esplicita: l'elenco, nella PR, di ogni conversione e chiamata numerica del codec con il tipo che restituisce, e un controllo automatico sulle classi compilate del codec (per esempio un test ArchUnit o un'ispezione del bytecode) che nessun metodo usi tipi o metodi in virgola mobile.

### Prove negative

In uno script nuovo, `quality/regressioni-codec.sh`, sul modello di `quality/regressioni-copertura.sh` (corsa di base, mutazione, ripristino anche su interruzione, motivo verificato, selezione dei casi per nome), mutazioni che devono far fallire `./verify.sh` per il motivo dichiarato. Le mutazioni del file dei vettori si applicano a una **vista temporanea** montata nel container al posto del file, senza modificare `analysis/` nel working tree. Casi: due righe della tabella del segno scambiate; ordine dei byte del binario invertito; un codice di segno `COMP-3` invertito; scala spostata di uno; un non valido convertito in zero; un valore assegnato a un caso oltre la `PICTURE`; ricodifica conservativa che normalizza lo zero negativo; il file dei vettori reso irraggiungibile (il test deve fallire, non essere saltato); un vettore tolto dal file senza aggiornare il numero atteso; un segno iniziale accettato in un campo senza segno; lettura sempre dall'offset zero; scala restituita sbagliata con valore numericamente uguale; una chiamata che passa per `double`; il test dei vettori saltato durante `./verify.sh` (proprietà tolta): il controllo del rapporto fallisce.

### Documentazione

`docs/contratti.md`, sezione "Codifica dei campi": per ogni categoria, un esempio preso da un copybook di CardDemo (file e riga), i byte, il valore, e la chiamata Java corrispondente; il rimando a `codifica.md` per le regole complete; ciò che il contratto non fa.

## Invarianti di parità

- Per ogni vettore, Java e colla di riferimento danno lo stesso stato, lo stesso valore e gli stessi byte. Nessuna "miglioria": se una regola di `codifica.md` sembra strana, è quella osservata sull'oracle.

## Criteri di accettazione

- [ ] `./verify.sh` termina con 0; il suo output mostra il test dei vettori eseguito con il numero di vettori atteso (tutti, nessuno saltato).
- [ ] Le prove negative elencate falliscono ciascuna per il motivo dichiarato, con un comando riportato; working tree pulito alla fine.
- [ ] `./quality/regressioni-verify.sh`, `./quality/regressioni-regole.sh`, `./quality/regressioni-copertura.sh` restano verdi (adeguamenti dichiarati).
- [ ] `./smoke.sh` termina con 0.
- [ ] `git diff --name-only origin/main...HEAD` elenca solo file ammessi; nessuna modifica sotto `analysis/`.
- [ ] CI verde.

## Strategia di rollback

Revert del commit di merge: il modulo torna vuoto; nulla dipende ancora da questi tipi.

## Limiti per l'agente

- Le regole sul codice di #26 valgono: niente `double`, `float`, `var`; niente escape Unicode nel sorgente. SpotBugs alla soglia fissata deve restare senza difetti, senza esclusioni.
- Negli script ogni comando ha l'esito controllato; limite di tempo sui comandi che possono restare in attesa; nessun residuo di una corsa precedente può soddisfare un controllo.
- Docker condiviso: risorse con prefisso proprio, nessun comando globale.
- Autocontrollo prima della PR come da `paper/data/prompts/esecutore.md`. File di appoggio sull'host con prefisso `issue54-`. Non mergiare. Mantieni nel corpo della PR la riga di chiusura dell'issue.
