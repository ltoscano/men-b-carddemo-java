BOCCIATA

I comandi principali terminano con successo, ma ho riprodotto controlli verdi su output errati. La prova negativa del manifesto non corrisponde inoltre al caso richiesto dalla specifica.

Tutte le prove sono state eseguite da me, con timeout: 1.500 secondi per la rigenerazione completa, 600 per i controlli, 90 per ciascuna mutazione. Ho usato le cache Docker presenti; non ho ricostruito tutte le immagini con `--no-cache`.

| Criterio | Comando eseguito | Esito osservato | Durata |
|---|---|---|---:|
| Perimetro | `git diff --stat origin/main...HEAD` | 125 file; esclusivamente `analysis/` e `docs/legacy-map/strumenti.md`. Elenco identico a `file-modificati.txt` | 0,009 s |
| Esecuzione completa | `./analysis/run.sh --all` | Codice 1: Buildx non può scrivere nella propria cartella, per restrizione della sandbox | 0,996 s |
| Esecuzione completa, ripetuta | `env BUILDX_CONFIG=<tmp>/buildx ./analysis/run.sh --all` | Codice 0 | 41,479 s |
| Controlli dopo la rigenerazione | `./analysis/run.sh --all --check` | Codice 0; eseguiti manifesto, selftest del dispatcher, campioni e prove negative incluse | 9,954 s |
| Manifesto deterministico | `./analysis/run.sh manifest`, ripetuto due volte; `cmp` con la copia della prima esecuzione | Entrambe codice 0; file identici | 0,294 + 0,296 s; confronto 0,003 s |
| Documento e capacità | `./analysis/run.sh --all --check` | Controllo verde: nove candidati, cinque capacità coerenti formalmente | Incluso nei 9,954 s |
| Versioni fissate | `./analysis/run.sh --all --check` | Controllo verde; letti anche i sette Dockerfile e l’immagine della colla | Incluso nei 9,954 s |
| Output versionati invariati | `git status --short`; `git diff --exit-code` | Solo `.validazione/` non tracciata, già presente inizialmente; nessuna differenza versionata | 0,049 + 0,036 s |
| Legacy invariato | `git status --short legacy/` | Vuoto | 0,030 s |
| Verifica finale dopo i ripristini | `./analysis/run.sh --all --check` | Codice 0 | 9,389 s |

Le alterazioni dei campioni effettivamente confrontati fanno fallire i controlli:

| Controllo alterato | Esito di `manifest --check` oppure `tools --check` | Durata |
|---|---|---:|
| Manifesto: file omesso | Codice 1 | 0,269 s |
| scc: atteso 31 → 30 file | Codice 1 | 0,275 s |
| Compilazione: COSGN00C atteso senza errori | Codice 1 | 0,504 s |
| COPY: sostituzione di CSSETATY alterata | Codice 1 | 0,751 s |
| CALL: MVSWAIT sostituito | Codice 1 | 0,982 s |
| Tracciato: offset di ACCT-CURR-BAL alterato | Codice 1 | 1,244 s |
| JCL: dataset GDG alterato | Codice 1 | 1,482 s |
| Candidato scartato: verdetto cobmix cambiato in `pass` | Codice 1 | 1,754 s |
| Immagini: digest della base rimosso | Codice 1 | 7,351 s |
| Documento: stato della capacità alterato | Codice 1 | 7,352 s |

I rilievi sono questi.

1. **Importante — i conteggi di codice, commenti e righe vuote non vengono controllati.**  
   Evidenza: `analysis/tools/glue/compare.py:57` legge soltanto `Lines` dal CSV per file; alle righe 80–85 confronta soltanto file e righe complessive delle cartelle. Ho azzerato `Code`, `Comments` e `Blanks` in `analysis/tools/out/scc/dirs.csv`: `tools --check` è rimasto verde, codice 0 in **10,262 s**, anche con somme palesemente incoerenti. La capacità obbligatoria comprende queste tre grandezze. Inoltre, per 54 file di `app/` il conteggio resta assente; il documento rinvia i BMS a un «altro mezzo» non consegnato (`strumenti.md:55`).  
   **Correzione richiesta:** aggiungere campioni indipendenti per codice/commenti/vuote, verificare le somme e la coerenza fra output per file e aggregati; delimitare esplicitamente la copertura consegnata e quella mancante.

2. **Importante — il controllo accetta output grezzi incompatibili con i TSV che certifica.**  
   Evidenza: `analysis/tools/glue/compare.py:151` verifica le CALL nel TSV; alle righe 168–174 verifica i tracciati nei TSV. Non rilegge gli output originari. Ho:
   - rinominato `ACCT-CURR-BAL` nell’XML `CVACT01Y.xml`: codice **0**, **8,231 s**;
   - sostituito `MVSWAIT` con `INVENTATO` nell’`inventory.json` di cmt: codice **0**, **7,861 s**.

   I campioni normalizzati rimasti invariati nascondono entrambe le alterazioni.  
   **Correzione richiesta:** rigenerare temporaneamente i TSV dagli output grezzi durante il controllo e verificarne la corrispondenza con quelli versionati, prima del confronto con gli attesi.

3. **Importante — il controllo JCL ignora se il passo esegua un programma o una procedura.**  
   Evidenza: `analysis/tools/glue/compare.py:198` scarta la colonna `tipo`. Ho cambiato `POSTTRAN/STEP15` da `PGM` a `PROC`, lasciando `CBTRN02C`: codice **0**, **8,507 s**. Nel sorgente, `$LEGACY/app/jcl/POSTTRAN.jcl:23` contiene esplicitamente `EXEC PGM=CBTRN02C`.  
   **Correzione richiesta:** includere il tipo del passo negli attesi e nel confronto, con prova negativa `PGM` → `PROC`.

4. **Importante — il numero degli errori di compilazione può essere falso senza far fallire il controllo.**  
   Evidenza: `analysis/tools/glue/compare.py:106–111` riduce il numero degli errori al predicato `> 0`. Ho cambiato gli errori di `CBSTM03A` da **39 a 9999**, conservando il log originale: codice **0**, **7,904 s**.  
   **Correzione richiesta:** confrontare i conteggi del TSV con le diagnostiche salvate nei log e aggiungere una prova negativa sul numero, oltre a quella sull’esito.

5. **Minore — manca la prova negativa automatica esattamente richiesta per il manifesto.**  
   Evidenza: `analysis/manifest/tamper.py:18` omette `CVACT01Y.cpy`, di tipo `copybook`; alla riga 22 duplica `CBACT01C.cbl`, di tipo `cobol`. Anche la descrizione alle righe 5–6 li presenta erroneamente come dello stesso tipo.  
   Ho eseguito separatamente il caso richiesto: omissione di `CVACT01Y.cpy` e duplicazione di `CVACT03Y.cpy`. Il controllo fallisce correttamente, codice **1**, **0,339 s**, segnalando entrambe le anomalie. È quindi incompleta la prova inclusa, non difettoso questo confronto del manifesto.  
   **Correzione richiesta:** usare due file dello stesso tipo nella fixture automatica e aggiornare i messaggi attesi.

6. **Importante — il documento trasforma un limite degli strumenti provati in un’impossibilità dell’analisi statica.**  
   Evidenza: `docs/legacy-map/strumenti.md:79` afferma che nessuno strumento statico risolve `CDEMO-MENU-OPT-PGMNAME(WS-OPTION)`. Nel legacy, `app/cpy/COMEN02Y.cpy:28` contiene il valore costante `COACTVWC`, la riga 34 contiene `COACTUPC`, e le righe 93–97 espongono quei dati mediante `REDEFINES` e tabella. Il trasferimento è in `app/cbl/COMEN01C.cbl:185`. Le destinazioni candidate sono dunque ricavabili staticamente dal sorgente.  
   **Correzione richiesta:** limitare l’affermazione agli strumenti effettivamente provati, distinguendo la destinazione scelta durante l’esecuzione dall’insieme delle destinazioni possibili.

Ho letto direttamente i sorgenti per verificare gli attesi, senza ricavarli dagli output degli strumenti:

- `COACTUPC.cbl:3208–3211`: `CSSETATY` sostituisce i tre segnaposto con `ACCT-STATUS`, `ACSTTUS`, `CACTUPA`; a `3214–3217` cambia in `OPEN-YEAR`, `OPNYEAR`, `CACTUPA`. Gli attesi conservano queste occorrenze distinte.
- `CVACT01Y.cpy:5–10`: ampiezze 11, 1, 12, 12, 12, 10; offset risultanti **0, 11, 12, 24, 36, 48**, coerenti con gli attesi.
- `CVEXPORT.cpy:10–19`: timestamp all’offset 1, overlay sul timestamp, sequenza binaria all’offset 27; le dichiarazioni `COMP-3` e `COMP` campionate sono alle righe 41, 50 e 57.
- `POSTTRAN.jcl:24–42`: confermate le nove DD, comprese le continuazioni e `DALYREJS(+1)` alla riga 38.
- Confermate le CALL richieste in `CBACT01C.cbl:231` e `COBSWAIT.cbl:38`.

Questi riscontri confermano la **coerenza dei campioni**; dai file non si può dimostrare il procedimento storico con cui l’Esecutore ha scritto gli attesi.

Quanto alle adozioni: i campioni richiesti sostengono ProLeap per COPY, cmt per le CALL campionate, cb2xml per i tracciati e mapa per programmi/DD, con i difetti dei controlli sopra elencati. GnuCOBOL produce le diagnostiche dichiarate; scc consegna una copertura parziale. `CopyLister.java:40–60` usa normalizzatori, lexer, parser e contesti sintattici di ProLeap: resta colla, senza grammatica o parser propri. L’accoppiata ProLeap per COPY e cmt per CALL è coerente con la specifica, che ammette un primo candidato insufficiente e non impone un solo strumento per entrambe.

Le licenze dichiarate risultano coerenti con le fonti consultate in rete: [scc MIT](https://github.com/boyter/scc/blob/v4.1.0/LICENSE), [cmt Apache-2.0](https://raw.githubusercontent.com/makedirectory/cobol-migration-toolkit/2e2a9e0fadf9a19a4fc6f974d9f684bc03b4e7d6/LICENSE), [ProLeap MIT](https://github.com/uwol/proleap-cobol-parser/blob/d1bfe75bdd6d480f70c74c6345bcc02610ac30d3/LICENSE), [cb2xml LGPL-2.1](https://github.com/bmTas/cb2xml/blob/master/LICENSE), [mapa MIT](https://raw.githubusercontent.com/cschneid-the-elder/mapa/d05705af310730c3e9aa848e824755e652618512/LICENSE), [GnuCOBOL GPL-3+/runtime LGPL-3+](https://metadata.ftp-master.debian.org/changelogs/main/g/gnucobol3/gnucobol3_3.2-3_copyright). I [metadati PyPI di cobmix](https://pypi.org/pypi/cobmix/0.1.2/json) non dichiarano una licenza: resta appropriato «non accertata».

Dalla lettura degli script non emergono dipendenze operative dall’host oltre a quelle ammesse, percorsi locali o segreti. I test del dispatcher hanno eseguito produttore/consumatore, ordinamento, dipendenze mancanti e cicliche, arresto al primo errore. Ho confrontato anche i sorgenti nel volume Docker con quelli del clone: nessuna differenza di byte.

Tutte le mutazioni sono state ripristinate con `git checkout`, usando un indice temporaneo perché la sandbox vieta di scrivere in `.git`. Nessun commit o push; nessun container creato dalla validazione è rimasto presente. Comandi e durate sono nel registro delle prove (log locale del Validatore, non conservato).