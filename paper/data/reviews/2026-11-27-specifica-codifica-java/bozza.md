## Obiettivo

Portare in Java, nel modulo `carddemo-domain`, le regole con cui i byte di un campo COBOL diventano un valore e viceversa (profilo `oracle-gnucobol`), e dimostrare che l'implementazione Java dà **gli stessi risultati** della colla di riferimento su tutti i vettori di prova di #23. È il primo dei contratti condivisi (divisa da #16) e serve al pilota: un programma tradotto deve leggere e scrivere record a larghezza fissa identici, byte per byte, a quelli dell'originale.

Classe di rischio: **piena** (dati, primo codice Java di dominio). Validazione con Codex.

## Dipendenze e perimetro

- Dipende da: #23 (regole e vettori: `docs/legacy-map/data-contract/codifica.md`, `analysis/data-codec/vettori/`), #26 e #27 (regole sul codice, copertura e analisi statica: mergiate).
- File ammessi: `carddemo-domain/src/main/java/**`, `carddemo-domain/src/test/java/**`, `carddemo-domain/src/test/resources/**`, `carddemo-domain/pom.xml` (solo se serve una dipendenza di test già gestita da Spring Boot), `docs/contratti.md` (nuovo: sezione "Codifica dei campi"), `quality/**` solo per adeguare conteggi o casi delle regressioni esistenti se l'arrivo di classi nel modulo li cambia (dichiarandolo).
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

I vettori di `analysis/data-codec/vettori/oracle-gnucobol.tsv` (scritti a mano e verificati sull'oracle in #23) sono la fonte unica. Un test parametrico li legge **tutti**, dal file del repository raggiunto con un percorso relativo alla radice del progetto (il test fallisce, non salta, se il file non si trova o se il numero di vettori letti è diverso da quello atteso, dichiarato nel test e aggiornabile solo insieme al file), e per ciascuno verifica stato, valore, ricodifica e, dove il vettore lo prevede, codifica del valore. Lo stesso per `oracle-oltre-picture.tsv` (lo stato atteso è "oltre la `PICTURE`", senza valore).

Poiché `./verify.sh` gira in un container che monta l'intero repository, il percorso è disponibile; nella build delle immagini (`docker/app.Dockerfile`) i test non girano con quel file: va verificato e dichiarato che cosa succede lì (il test non deve rendere rossa la build delle immagini né passare a vuoto in `./verify.sh`).

In più, test scritti a mano per ciò che i vettori non coprono in Java: campo incompleto e offset fuori dal record per ogni categoria; valore non rappresentabile in codifica; uso di scala sbagliata; e una prova che **nessun** percorso di decodifica passa per `double` (lo garantiscono già le regole di #26: il test dichiara di appoggiarsi a quelle).

### Prove negative

Sul modello delle regressioni esistenti in `quality/` (uno script nuovo, o casi aggiunti a uno esistente: scelta dichiarata), mutazioni del codice Java che devono far fallire `./verify.sh` nel test dei vettori, ciascuna per il motivo dichiarato: due righe della tabella del segno scambiate; ordine dei byte del binario invertito; un codice di segno `COMP-3` invertito; scala spostata di uno; un non valido convertito in zero; un valore assegnato a un caso oltre la `PICTURE`; ricodifica conservativa che normalizza lo zero negativo; il file dei vettori reso irraggiungibile (il test deve fallire, non essere saltato); un vettore tolto dal file senza aggiornare il numero atteso.

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
