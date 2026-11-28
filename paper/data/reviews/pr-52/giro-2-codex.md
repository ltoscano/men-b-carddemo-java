**BOCCIATA**

Validato `18b4317`. Letto integralmente il diff correttivo, coincidente con `git diff 5ee7956..HEAD`. I cinque controesempi originali sono chiusi; le correzioni introducono però un nuovo falso verde.

Per i comandi delle sonde, `E=/tmp/menb-val52b-evidence`.

| Rilievo del primo giro | Stato | Comando eseguito | Esito |
|---|---|---|---|
| Attesa fissa di un secondo | **chiuso** | `python3 "$E/probes.py"` | Respinta con codice 1: minimi **1033–1092 ms**, tre tentativi per caso valido. Respinti anche **850 ms**: minimi **882–922 ms**. |
| SYSIN sovrascritto prima della lettura | **chiuso** | `python3 "$E/esegui-probes.py"`; `./oracle/run.sh routines --check` | Valore e impronta corretti con alias su `.ambiente`, `.stdout`, `.stderr`, rapporto, cartella di lavoro e collegamento simbolico. |
| Apertura fallita registrata come risultato del programma | **chiuso** | `python3 "$E/esegui-probes.py"` | Eliminando l’originale dopo l’impronta viene letta correttamente la copia. Aperture fallite sui descrittori 3/4/5: codice **2**, rapporto vuoto. |
| Mutazione del segno con più violazioni | **chiuso** | `python3 "$E/probes.py"`; `./oracle/run.sh routines --check` | Segno e ordine cambiano soltanto il decimale stampato; classificazione, esadecimale e arresto **97** rimangono invariati. `solo_diversi` conferma tutti gli insiemi dichiarati. |
| Radice del repository contenente spazi | **chiuso** | `./oracle/run.sh routines --check` | Controprova nella radice con spazi riuscita: tutti i **14 rapporti identici**. |

Rilievi nuovi:

1. **Bloccante — I tentativi nascondono un’attesa intermittente.**  
   In `oracle/routines/mvswait-run.sh:94–103` viene conservato il minimo, scartando l’esecuzione lenta. Una variante compilata che attende un secondo soltanto alla prima esecuzione misura **1065 ms**, poi **23 ms**: il controllo restituisce **0**. Tutti i **14 rapporti e 14 ambienti** coincidono esattamente con attesi e osservazioni. **Falso verde: sì, dimostrato.** [Evidenza](</tmp/menb-val52b-evidence/intermittent-results.log>).

   Il rischio opposto rimane: con la routine sana e quota Docker `--cpus=0.015`, i minimi dei casi `COBSWAIT` sono **885–1004 ms** dopo tre tentativi; il controllo fallisce pur producendo rapporti identici a quelli sani. È un falso rosso da carico simulato. Senza strozzatura ho misurato **33–144 ms**. [Log del carico](</tmp/menb-val52b-evidence/load015.log>).

   **Correzione richiesta:** non cancellare l’evidenza delle esecuzioni lente dell’artefatto; distinguere il carico dell’infrastruttura dalla violazione temporale e aggiungere una mutazione che attenda soltanto al primo tentativo.

2. **Importante — Esiti persi nelle nuove verifiche.**  
   Le asserzioni di `oracle/routines/mvswait-check.sh:265,271` accettano `97` anche quando `sed` restituisce **42**: entrambe terminano con **0** nella sonda. Inoltre, alle righe 403–407, il nuovo `case` perde l’esito di `printf`: **42** viene coperto dal successivo `chmod` riuscito. **Falso verde: sì, delle verifiche operative; non dimostrato un risultato MVSWAIT infedele.** [Evidenza](</tmp/menb-val52b-evidence/lost-status.log>).

   **Correzione richiesta:** acquisire e controllare separatamente l’esito di `sed`; controllare la scrittura dell’involucro prima del `chmod`, con controprove dedicate.

3. **Minore — Pulizia incompleta sulle uscite d’errore di SYSIN.**  
   La copia privata viene rimossa soltanto alla fine di `oracle/esegui.sh`, senza cleanup sulle uscite anticipate. Errori di `cp`, `wc`, `sha256sum`, registrazione dell’ambiente e apertura di stderr lasciano il temporaneo. Con `cp` a **42**, lo script restituisce **2** ma conserva anche un rapporto autentico precedente di **234 byte**; con `wc`/`sha256sum` rimangono inoltre i **9 byte** del SYSIN nella copia. **Falso verde/oracle riuscito infedele: non dimostrati**, perché i controlli rispettano il codice 2; restano temporanei e rapporti non correnti. [Evidenza](</tmp/menb-val52b-evidence/esegui-probes.log>).

   **Correzione richiesta:** cleanup sulle uscite anticipate e gestione esplicita dei rapporti precedenti, con prove che predispongano residui autentici anche prima degli errori di preparazione.

Il fallimento della misura temporale è invece gestito: `date` con esito **42**, oppure risposta non numerica con esito 0, produce codice **1**; nessun falso verde osservato.

Senza `--sysin`, rapporti **e ambienti coincidono byte per byte con `origin/main`**, usando gli stessi moduli, per `COBSWAIT`, `PARMECHO`, `CBACT01C`, `ABDUSING` e `WAITPRB`.

I comandi di accettazione sono stati completati nel clone pulito:

| Comando | Codice | Durata |
|---|---:|---:|
| `./oracle/run.sh build` | 0 | 8 s |
| `./oracle/run.sh routines --check` | 0 | 177 s |
| `./oracle/run.sh --all --check`, prima corsa | 0 | 606 s |
| Stesso comando, seconda corsa consecutiva | 0 | 310 s |
| `./analysis/run.sh --all --check` | 0 | 448 s |

Conteggi identici nella [CI dello SHA validato](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46083369001) e in entrambe le corse locali:

| Passo | Negative | Controprove | File illeggibili |
|---|---:|---:|---:|
| build | 172 | 4 | 5 |
| abend | 7 | 0 | 0 |
| adattamenti | 54 | 0 | 1 |
| avviatore | 5 | 0 | 0 |
| avvio | 14 | 1 | 0 |
| dialetto | 3 | 1 | 0 |
| routines | 135 | 9 | 0 |
| segno | 5 | 0 | 0 |
| selftest | 3 | 0 | 0 |

Perimetro rispettato: cinque file correttivi ammessi; **nessun atteso cambiato dal primo giro**. Clone e legacy puliti; nella cartella fornita rimane soltanto `.validazione/`, già presente inizialmente.

Nessuna correzione o commit effettuato. Rimossi i dieci tag di immagini e i due volumi privati `menb-val52b-`; nessuna risorsa del prefisso residua, nessuna risorsa condivisa rimossa.