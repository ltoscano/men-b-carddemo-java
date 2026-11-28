BOCCIATA

Validato lo SHA `0778d455b0cdbc7629f169c57495ed79d70c5afb`. Nessun file fuori perimetro: 18 file ammessi, nessuna modifica a POM, `analysis/`, `oracle/` o `legacy/`.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Build e vettori | `./verify.sh` | **0**, anche dopo il ripristino delle mutazioni. 375 vettori + 10 osservazioni; 385 casi, zero saltati/errori/fallimenti |
| Regressioni codec | `./quality/regressioni-codec.sh` | **0**; tutte le 16 mutazioni previste rilevate |
| Regressioni verifica | `./quality/regressioni-verify.sh` | **0** |
| Regressioni regole | `./quality/regressioni-regole.sh` | **0** |
| Controprova copertura | `./quality/regressioni-copertura.sh controprova-lecita` | **0**; JaCoCo 8/8, SpotBugs 11 classi. L’adeguamento mantiene confronti esatti e non indebolisce il caso. Suite completa non eseguita, come richiesto |
| Smoke | `./smoke.sh`, ripetuto senza cache | **0**; in entrambe le build il test dei vettori mostra `Tests run: 2, Skipped: 2` |
| Perimetro | `git diff --name-only origin/main...HEAD` | Solo i 18 file ammessi |
| CI | `gh pr checks 57`; lettura del log con `gh run view 46081210209 --log` | Verde sullo stesso SHA. Conteggi uguali alla corsa locale: domain 394, loader 1, online 1, batch 1, parity 4 |
| Equivalenza supplementare | `bash /tmp/menb-val57/run-equivalence.sh` | **1**: confrontati 83 casi nuovi; 82 coincidenti, una divergenza descritta sotto |

Le controprove sul rapporto hanno prodotto questi risultati **reali di `verify.sh`**, senza falsificare metadati XML:

| Controprova | Codice | Osservazione |
|---|---:|---|
| Vettore e relativi conteggi nel test ridotti insieme | 1 | Maven verde; rapporto respinto: 384 casi invece di 385 |
| Factory con 375 casi vuoti | **0** | Falso verde |
| Casi senza asserzioni | **0** | Falso verde |
| Rapporto della corsa precedente | 1 | Respinto per identificativo della corsa |
| Test disabilitato con `menb.verify.run` presente | 1 | Respinto per `skipped=2` |
| Primo vettore verificato 375 volte | **0** | Falso verde |
| Lettore modificato per ignorare righe incomprensibili, con riga malformata nella vista temporanea | **0** | Falso verde |

Le mie mutazioni di segno `F` negativo, binario unsigned letto signed, troncamento in `encode`, normalizzazione del segno alternativo in `reencode`, offset doppio e completamento con zeri sono state respinte con codice **1**. Ignorare `P` è invece passato con **0**; ignorare la scala di una `V` supportata è stato respinto.

1. **Bloccante — Il rapporto certifica il numero dei casi senza provare quali vettori siano stati verificati.**  
   Evidenza: [OracleGnuCobolVectorsTest.java:69](/tmp/menb-val57-acceptance/carddemo-domain/src/test/java/io/github/ltoscano/carddemo/domain/OracleGnuCobolVectorsTest.java:69) e [RapportoSurefire.java:111](/tmp/menb-val57-acceptance/quality/RapportoSurefire.java:111). Le tre mutazioni “casi vuoti”, “nessuna asserzione” e “stesso vettore ripetuto” mantengono `verify.sh` verde e il messaggio «375 vettori eseguiti e riusciti».  
   **Schema generale:** cardinalità dei test scambiata per prova della copertura semantica.  
   **Correzione richiesta:** legare la prova di completamento all’identità e all’esito dei singoli vettori, per entrambe le factory, e aggiungere regressioni per queste tre mutazioni.  
   **Impatto:** falso verde dimostrato; parità non garantita. **Condizione:** modifiche a file versionati dei test; rapporti prodotti normalmente da JUnit.

2. **Bloccante — Il cancello automatico sugli importi lascia passare codice vietato e conversioni con perdita.**  
   L’ispezione ASM ha una prova negativa reale, ma [la scansione parte dalla directory del pacchetto `domain`](/tmp/menb-val57-acceptance/carddemo-domain/src/test/java/io/github/ltoscano/carddemo/domain/NoFloatingPointBytecodeTest.java:159). Una classe aggiunta nello stesso modulo, nel pacchetto fratello `io.github.ltoscano.carddemo.precision`, chiamata dal codec e contenente `Math.pow`, lascia `verify.sh` a **0**. Inoltre, sostituire l’intero esatto con `BigInteger.valueOf(scaled.unscaledValue().longValue())` passa: nel mutante, `18446744073709551617` in `9(20)` viene codificato come `00000000000000000001`.  
   **Schema generale:** perimetro incompleto dell’ispezione e assenza di controllo delle conversioni intere non esatte.  
   **Correzione richiesta:** coprire tutto il codice di produzione del modulo utilizzabile dal codec e intercettare le conversioni numeriche vietate; aggiungere entrambe le prove negative.  
   **Impatto:** falso verde e alterazione dei dati dimostrati nei mutanti. **Condizione:** sole modifiche versionate; nessun rapporto falsificato. Il codec originale non contiene queste conversioni.

3. **Importante — Limite della `PICTURE` aggiunto senza autorizzazione nella specifica.**  
   [FieldPicture.java:14](/tmp/menb-val57-acceptance/carddemo-domain/src/main/java/io/github/ltoscano/carddemo/domain/FieldPicture.java:14) limita ogni conteggio a quattro cifre. Nel confronto indipendente, `ALPHANUMERIC X(10000)`, byte **`41 × 10000`**, produce nella colla: stato valido, valore `"A" × 10000`, nessuna scala e ricodifica identica. Java rifiuta la `PICTURE`. È l’unica divergenza sui miei 83 casi.  
   **Schema generale:** restrizione arbitraria della grammatica dichiarata equivalente al riferimento.  
   **Correzione richiesta:** allineare i conteggi rappresentabili alla colla oppure ottenere una restrizione esplicita della specifica; verificare i confini per tutte le categorie interessate.  
   **Impatto:** contratto infedele al riferimento; la suite resta verde. **Condizione:** nessuna modifica versionata né falsificazione: basta l’ingresso API indicato.

4. **Importante — La normalizzazione permissiva della `PICTURE` sfugge ai test.**  
   La mutazione `NUMERIC.matcher(picture.replace("P", ""))` passa `verify.sh` con **0**. Per `P9(4)` e byte **`32 33 34 35`**, il mutante restituisce valido, valore `2345`, scala `0`, ricodifica identica; la colla rifiuta la variante. Entrambe le implementazioni originali rifiutano `P`: non occorre aggiungerne il supporto.  
   **Schema generale:** mancano prove negative contro trasformazioni che rendono accettabili forme estranee alla grammatica.  
   **Correzione richiesta:** aggiungere casi e regressioni che impongano il rifiuto di `P` e delle altre forme non ammesse, senza eliminazioni permissive di simboli o clausole.  
   **Impatto:** falso verde e divergenza dal riferimento nel mutante. **Condizione:** modifica versionata del parser; nessun artefatto falsificato.

5. **Importante — La grammatica del lettore TSV non coincide interamente con Python e manca la prova negativa dello scarto silenzioso.**  
   Sulle **375 righe originali non ho trovato interpretazioni differenti**. Esiste però un controesempio: una riga iniziale composta da **U+00A0** viene ignorata da `comune.py:58`, mentre [VectorFile.java:53](/tmp/menb-val57-acceptance/carddemo-domain/src/test/java/io/github/ltoscano/carddemo/domain/VectorFile.java:53) la considera intestazione e fallisce successivamente con “10 colonne invece di 1”. Python legge tutti i 375 vettori. Inoltre il mutante che salta righe malformate passa con una riga incomprensibile aggiunta alla vista temporanea.  
   **Schema generale:** equivalenza del lettore verificata soltanto sul campione corrente.  
   **Correzione richiesta:** allineare il riconoscimento delle righe vuote e aggiungere test diretti della grammatica e del rifiuto delle righe sconosciute.  
   **Impatto:** divergenza del lettore e falso verde nel mutante; nessuna divergenza numerica osservata sui 375 originali. **Condizione:** per U+00A0 basta un TSV temporaneo; lo scarto silenzioso richiede anche la modifica versionata del lettore.

6. **Importante — Nuova dipendenza dall’host: Perl.**  
   [regressioni-codec.sh:34](/tmp/menb-val57-acceptance/quality/regressioni-codec.sh:34) dichiara Perl come prerequisito e la riga 183 lo esegue sull’host. Contraddice il vincolo Docker e Git; la versione dello strumento dipende dall’host.  
   **Schema generale:** strumentazione di validazione eseguita fuori dal container.  
   **Correzione richiesta:** eseguire le mutazioni con strumenti containerizzati e fissati.  
   **Impatto:** nessun falso verde o oracle infedele dimostrato; riproducibilità non rispettata. **Condizione:** host senza Perl, senza modifiche versionate o artefatti falsificati.

7. **Importante — Esiti persi e attese senza limite nella funzione di mutazione.**  
   In [regressioni-codec.sh:181](/tmp/menb-val57-acceptance/quality/regressioni-codec.sh:181), `grep`, Perl e `cmp` non usano il limitatore. Riproducendo isolatamente la funzione `muta`, un `cmp` terminato con **2** viene trattato come “file diverso”: la funzione termina con **0**. Un Perl bloccato supera tre secondi con `SHORT_TIMEOUT=1`; l’ho arrestato io. Anche altre chiamate nuove, come `awk` e `wc`, sono fuori dal limitatore.  
   **Schema generale:** gestione non uniforme di errore, differenza attesa e timeout.  
   **Correzione richiesta:** applicare limiti alle chiamate esterne e distinguere esplicitamente gli esiti `cmp` 0, 1 ed errore; aggiungere prove di comando fallito e bloccato.  
   **Impatto:** falso verde del controllo di avvenuta mutazione e possibile blocco della suite; nessun oracle numerico infedele dimostrato. **Condizione:** comando esterno che fallisce o si blocca, senza modificare sorgenti o metadati dei rapporti.

I cinque esempi documentati corrispondono al legacy: `CVACT01Y.cpy:5,6,7` e `CVEXPORT.cpy:25,50`, sotto `legacy/aws-mainframe-modernization-carddemo/app/cpy/`. Le ulteriori verifiche delle varianti sono registrate in [legacy-facts.log](/tmp/menb-val57/logs/legacy-facts.log).

Prove riproducibili: [driver delle mutazioni](/tmp/menb-val57/adversarial.py), [esiti del rapporto](/tmp/menb-val57/logs/adversarial-gate.log), [esiti del codec](/tmp/menb-val57/logs/adversarial-codec.log), [83 casi indipendenti](/tmp/menb-val57/cases.tsv).

Nessuna modifica versionata rimasta, nessun commit. Ripristinata `.validazione/` preesistente; shim della suite rimosso dal repository e dal PATH. Risorse Docker `menb-val57-` rimosse, senza cancellazioni globali o di risorse condivise.