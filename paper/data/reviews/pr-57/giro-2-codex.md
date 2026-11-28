BOCCIATA

Validato lo SHA `fa3ba9331e80b87fd5507992f93719a3301a79b4`. Diff di correzione letto integralmente e coincidente con `git diff 0778d45 HEAD`: **10 file, tutti nel perimetro**. La PR complessiva contiene 19 file ammessi; nessuna modifica sotto `analysis/`.

| Rilievo precedente | Stato | Comando / controesempio rieseguito | Esito |
|---|---|---|---|
| 1. Identità dei vettori | **Non chiuso** | `./quality/regressioni-codec.sh`; `python3 /tmp/menb-val57b/adversarial.py` | La ripetizione letterale del primo vettore è respinta. Passa però la variante che verifica le sue colonne conservando impronta e identificativo delle altre righe: **falso verde**, con tutte le asserzioni attive. |
| 2. Bytecode e conversioni con perdita | **Non chiuso** | Suite codec; `python3 /tmp/menb-val57b/numeric-encode-probes.py` | `Math.pow` nel pacchetto fratello e `BigInteger.valueOf(x.longValue())` sono respinti. Due nuovi aggiramenti passano e producono byte errati: dettagli sotto. |
| 3. `X(10000)` | **Chiuso** | `./verify.sh`, test `confiniDeiConteggiPerOgniCategoria`; colla mediante `reference.py` | Java e Python accettano i 10.000 byte e conservano valore e ricodifica. |
| 4. Normalizzazione permissiva di `P` | **Chiuso** | Suite codec, caso `picture-p` | Mutante respinto per `P9(4)`; passano i nuovi test sulle altre forme vietate. |
| 5. Lettore TSV | **Chiuso** | `./verify.sh`; suite codec, casi `lettore-salta` e `lettore-salta-rapporto` | U+00A0 riconosciuto come riga vuota; entrambi gli scarti silenziosi sono rilevati. Python legge 375 vettori con U+00A0 iniziale. |
| 6. Strumenti dell’host | **Non chiuso rispetto al vincolo letterale** | Corsa `segno-scambiato` con PATH ristretto; lettura completa dello script | Perl eliminato e mutazioni containerizzate. Restano però comandi host oltre Docker e Git, elencati sotto. |
| 7. Esiti persi e comandi bloccati | **Chiuso** | `python3 /tmp/menb-val57b/shell-probes.py` | Mutatore con esito 2 o 4: suite fermata con 1. Mutatore bloccato: timeout rilevato. `cmp` con esito 2 produce 95; bloccato viene fermato dal limite esterno. |

Sull’host lo script usa realmente **Bash, Docker, Git, `cp`, `rm`, `mkdir`, `rmdir`, `chmod`, `id`, `env` e `sleep`**. Non usa Perl né gli strumenti di testo rimossi. Il vincolo letterale richiede di containerizzare anche le operazioni residue.

Le due divergenze Python dichiarate sono confermate: `9(30)` arrotonda `123456789012345678901234567890` e lo ricodifica come `123456789012345678901234567900`; `9(4)\n` è accettata da `geometria`. Sono entrambe dichiarate in `docs/contratti.md`. Nei TSV dei contratti il massimo rilevato è **16 cifre totali**, quindi non coinvolgono campi reali censiti. [Evidenza della colla](/tmp/menb-val57b/logs/reference.log).

Nuovi controesempi e difetti della correzione:

1. **Bloccante — Impronta e dati verificati possono riferirsi a vettori diversi.**  
   `Row` mantiene separatamente `raw` e `columns`; l’impronta usa soltanto `raw`. Ho sostituito il controllo con:
   ```java
   check(new VectorFile.Row(r.file(), r.line(), r.raw(), rows.get(0).columns()));
   ```
   Tutte le asserzioni rimangono operative, ma verificano 375 volte i dati del primo vettore. Gli identificativi stampati restano quelli attesi: **`verify.sh` termina con 0**. Anche identificativi incorporati nel test permettono questa combinazione. [Patch](/tmp/menb-val57b/logs/hash-different-vector.patch), [esiti](/tmp/menb-val57b/logs/adversarial-summary.log).

   **Correzione richiesta:** vincolare l’identità ai dati effettivamente controllati, impedire rappresentazioni incoerenti tra testo e colonne e aggiungere questa regressione. **Falso verde: sì. Richiede una modifica versionata dei test.**

   Il solo anticipo del marcatore passa, ma non costituisce un falso verde autonomo: un’asserzione fallita continua a fermare Maven. Il controllore legge effettivamente gli identificativi attesi dal TSV: variando una nota nella vista temporanea, il rapporto genuino viene respinto per impronta diversa. Non segnalo il test svuotato delle asserzioni.

2. **Bloccante — Il nuovo controllo numerico ignora chiamate ereditate e restringimenti primitivi.**  
   Due mutanti, con **sole modifiche al codice di produzione**, passano `verify.sh`:
   
   - `longValue()` ereditato da una sottoclasse di `BigInteger`: l’owner nel bytecode è la sottoclasse, esclusa dall’insieme controllato.
   - `(int) n.longValueExact()`: la chiamata esatta è ammessa e l’istruzione successiva `L2I` non viene rilevata.

   Applicando questi percorsi a `9(21)`, entrambi scrivono `000000000000000000001`. La colla scrive rispettivamente:
   
   - `18446744073709551617` → `018446744073709551617`;
   - `4294967297` → `000000000004294967297`.

   [Esiti delle build e codifiche](/tmp/menb-val57b/logs/numeric-encode-summary.log), [attesi Python](/tmp/menb-val57b/logs/numeric-reference.log).

   **Correzione richiesta:** risolvere anche i metodi ereditati e controllare i restringimenti primitivi potenzialmente distruttivi, con regressioni per entrambi. **Falso verde e codifica infedele: sì. Richiede modifiche versionate alla produzione.**

3. **Importante — La pulizia di `crea` cancella un file preesistente.**  
   `crea` inserisce il percorso in `CREATED` prima della creazione. Se Java trova il file già esistente, lo rifiuta; il ripristino lo cancella comunque. La sonda isolata sulle funzioni effettive termina con 1 e mostra `PREEXISTING_FILE_PRESENT_AFTER_CLEANUP False`. [Prova](/tmp/menb-val57b/logs/create-probe.log).

   **Correzione richiesta:** verificare l’assenza iniziale e registrare soltanto creazioni realmente avvenute, preservando i file preesistenti. **Falso verde: no; codifica infedele: no; perdita del file durante la pulizia: sì.** Nel caso standard la collisione richiede una revisione con `precision/Scale.java` già presente.

Le invocazioni richieste hanno dato:

| Comando | Esito |
|---|---|
| `./verify.sh` | **0**; 385 casi vettori, zero saltati |
| `./smoke.sh` | **0** |
| `./quality/regressioni-codec.sh` | **0**; 23 mutazioni rilevate più base |
| `./quality/regressioni-verify.sh` | **1**, per interferenza del mio proxy nel solo caso senza socket |
| `./quality/regressioni-regole.sh` | **0** |
| `./quality/regressioni-copertura.sh controprova-lecita` | **0**; JaCoCo 8/8, SpotBugs 11 classi |

Ho corretto l’harness e rieseguito **soltanto** il controesempio senza socket: fallisce con 1 e “Could not find a valid Docker environment”, come richiesto. Non attribuisco l’esito della prima corsa a un difetto della PR.

[CI verde sullo SHA attuale](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46090163300). Conteggi identici alla corsa locale: **domain 399, loader 1, online 1, batch 1, parity 4**.

Nessuna modifica versionata rimasta, nessun commit, push o workflow avviato. `.validazione/` preservata. Risorse Docker della validazione rimosse; immagini e volumi condivisi conservati.