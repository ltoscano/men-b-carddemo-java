BOCCIATA

| Rilievo del primo giro | Stato | Comando/prova rieseguita | Esito |
|---|---|---|---|
| 1. Round-trip circolare | **Chiuso** | Rigenerazione nella copia con byte 88072 letto D7→C2; `run-probe.sh` | Rigenerazione e controllo successivo escono con **1, R04**. R04 rileva anche byte ASCII alterato, record perso in coda, terminatori modificati e riempimento con zeri. |
| 2. Coppie incomplete | **Chiuso** | Omissioni bilaterali TCATBAL e alias ACCDATA, senza confronto con i versionati | Entrambe falliscono con **I10**, anche se i confronti scendono a nove. |
| 3. Esiti shell persi | **Chiuso** | `tail` stampa l’output reale ed esce con 7; `grep` esce con 2 | Generazione e controllo escono con **1**, diagnosticando l’errore operativo. Nessun altro falso verde individuato nelle modifiche shell. |
| 4. Censimento e residuo | **Non chiuso** | `negativi.py` su cinque copie, ciascuna con una sola guardia disattivata; prova residuo di `check.sh` | Provenienza, conteggio R04 e omissione I10 vengono nominate come scoperte. **Tabella vuota e campo atteso duplicato lasciano invece tutte le 84 prove verdi.** La parte relativa al residuo è chiusa: attraversa `dfx_genera` e verifica la rimozione dalla destinazione effettiva. |
| 5. Riferimento DUSRSECJ | **Chiuso** | `nl -ba …/DUSRSECJ.jcl` | I dieci dati sono alle righe **35–44**, come nell’inventario corretto. |
| 6. Osservazioni omesse | **Chiuso** | Lettura binaria dal volume Docker; sequenza decodificata indipendentemente con `int.from_bytes` | INIT: 342 NUL, poi `F0 F0 F0 F0 F0 F1 F0 F0`. Export: venti NUL agli offset **25128–25147** e **49628–49647**. Record 450/451: sequenza **450→460**. Documento coerente. |
| 7. Tabelle Markdown | **Chiuso** | Controllo indipendente dei separatori; prova `tabella-non-protetta` | **Sei tabelle, 93 righe**, colonne coerenti; chiave composta protetta. La mutazione fallisce con X04. |

R04 non richiama `fisica_ascii`, `record_ebcdic` o `RIEMPI`: le alterazioni di queste funzioni sono intercettate. Non ho individuato una funzione condivisa di trasformazione dei record che renda verdi i controesempi richiesti.

I10 ricava le coppie dovute dall’uguaglianza dei contratti fra codifiche diverse. Svuotare le dichiarazioni non svuota l’insieme dovuto. Alterare anche i contratti per azzerarlo produce errori **D06, I04, I05, I09 e T01**.

Il nuovo rilievo sul meccanismo di correzione, che mantiene aperto il punto 4, è:

- **Importante — il censimento continua a non coprire ogni guardia logica.** La ricerca delle chiamate letterali esclude `es.errore(codice, …)` in `fixture.py:178,185`; inoltre più condizioni con `raise ValueError` confluiscono nell’unico sito D09. Disattivando soltanto la condizione sul campo atteso duplicato (`fixture.py:616–617`), `negativi.py` termina con **0: 84 prove superate, ogni sito coperto**. Aggiungendo poi una riga `C` duplicata agli attesi nella copia privata, il verificatore originale segnala D09; quello mutato restituisce **zero errori**. [Log delle rimozioni](/tmp/issue5-menb-val56b/logs/mutants-summary.log), [controesempio](/tmp/issue5-menb-val56b/logs/hidden-guard-atteso-campo-duplicato.log). **Correzione richiesta:** censire e provare separatamente anche le guardie con codice variabile e quelle espresse tramite eccezioni. **Falso verde: sì, della suite negativa. Fixture infedeli: non dimostrate da questo controesempio.**

Ho letto integralmente il diff: **nove file modificati, tutti ammessi**. Anche il diff complessivo della PR resta nel perimetro. `git diff 488621b HEAD -- analysis/data-fixtures/out analysis/data-fixtures/attesi` è vuoto.

I comandi di accettazione hanno dato:

- `./analysis/run.sh data-fixtures`: **0**, rigenerazione senza differenze; 22 file, 1.813 record, 55 record attesi. Script richiesti eseguibili.
- `./analysis/run.sh data-fixtures --check`, due volte consecutive: **0 e 0**, 84 prove negative e 92 righe `ok`, identiche alla [CI sullo SHA b272c0a](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46085520767/job/140794070683). Tutti i job risultano verdi.
- `./analysis/run.sh --all --check`, eseguito una volta: **1**, corsa invalidata dal mio wrapper Docker, che rinominava il container ma non il bersaglio di `docker kill`. Arresto in `inventory-cics` dopo 61 secondi; **non attribuito alla PR**. [Log](/tmp/issue5-menb-val56b/logs/all-check.log).
- Diff dei versionati vuoto; legacy pulito a `59cc6c2`. Resta soltanto `?? .validazione/`, già presente inizialmente.

Nessuna correzione o commit. Risorse Docker `menb-val56b-` rimosse; nessuna immagine o volume condiviso rimosso.