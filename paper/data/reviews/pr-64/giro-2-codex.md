APPROVATA CON RISERVE

La riserva riguarda esclusivamente la corsa aggregata di `analysis`: un errore nel mio involucro Docker ha falsato la prova del timeout. Corretto l’involucro temporaneo, ho ripreso dal passo interrotto: tutti i passi rimanenti sono passati. Non ho ripetuto quelli già conclusi.

Per i comandi delle sonde, `L=/private/tmp/menb-val64b-logs`.

| Rilievo del primo giro | Stato | Comando | Esito |
|---|---|---|---|
| 1. Riferimenti finali non verificati | **Chiuso** | `bash "$L/producer-probes.sh"` | **10/10 alterazioni respinte**, nessuna pubblicazione e residui rimossi. Inclusi estrattore sul record 70 e primo conto della console. |
| 2. Errore di lettura dichiarato impossibile | **Chiuso** | `bash "$L/read-probe.sh"`; `bash "$L/more-host.sh"`; `./oracle/run.sh golden --check` | Pagina di 4096 byte, scostamento 8224: stato **43**, diagnostica richiesta, `CEE3ABD` **999/0**, codice **99**, nessuna pubblicazione. Con byte `81` anziché `80`, fallimento esplicito della guardia. Testi corretti; resta soltanto il richiamo storico all’affermazione errata. |
| 3. Esiti persi | **Chiuso** | `bash "$L/host-probes.sh"`; `bash "$L/cmp-host-probe.sh"`; `bash "$L/awk-host-probe.sh"` | Le chiamate problematiche a `cat`/`wc` sono eliminate. `find` e `cmp` con uscita 42 fanno fallire `c1`; l’errore di `awk` viene propagato. Anche `impronte.sh` rileva le uscite 42 provate. |
| 4. Token `zz` accettato come zero | **Chiuso** | `bash "$L/token-probes.sh"` | Verificatore e coerenza escono con **4**, sia con intestazione fisica `00`, sia alterata a `01`. |
| 5. Classificazione `VBRC-REC1:` | **Chiuso per decisione dell’Approvatore** | `git diff 5f21326 HEAD -- oracle/golden/readacct/console.tsv` | Cambia soltanto la motivazione; classificazione e riferimento restano invariati. Non risegnalato. |

Le ulteriori sonde sui produttori respingono: OUTFILE conto 20 byte 30, maschera spostata, correzione `7b` omessa nel conto 33, numerazione e lunghezza VB errate, scambio classe a/osservazione in entrambe le direzioni e ingresso pubblicato diverso dall’eseguito. I fisici restano invariati nelle sonde sui riferimenti. [Esiti]( /private/tmp/menb-val64b-logs/producer-status.txt)

Ho letto interamente il diff. Gli attesi del verificatore sono indipendenti dai produttori: regole proprie, ingresso e mappatura manuale dal sorgente; nessun riuso di estrattore, mascheratore o tabella delle correzioni.

Il diff resta nel perimetro. È vuoto:

```sh
git diff 5f21326 HEAD -- oracle/golden/readacct/generati oracle/golden/readacct/attesi-a-mano.tsv
```

Non ho ripetuto la ricostruzione dei 100 conti.

| Comando di accettazione | Esito |
|---|---|
| `./oracle/run.sh build` | **0**, 29 programmi |
| `./oracle/run.sh dati` | **0** |
| `./oracle/run.sh golden` | **0**, versionati invariati |
| `./oracle/run.sh golden --check` | **0**, 129 negative e 5 controprove |
| `./oracle/run.sh --all --check` | **0** |
| `./analysis/run.sh --all --check` | **1 per l’involucro di validazione**; ripresa dei passi rimanenti **tutta con 0** |

Gli **11 conteggi per passo coincidono con la CI** sullo SHA `805b0eb`: **635 negative, 27 controprove, 6 prove con file illeggibili**. [Confronto dettagliato](/private/tmp/menb-val64b-logs/--all_--check.log.counts.csv). CI [oracle](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46119169076) e [analysis](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46119169119) verdi. Il difetto noto #63 non si è manifestato.

**Nuovi rilievi sul diff: nessuno.** Nessuna modifica versionata richiesta.

Nessuna modifica finale ai versionati, nessun commit. Rimane soltanto `.validazione/`, già presente all’avvio. Nessun container o volume `menb-val64b-` rimasto; nessuna immagine o volume condiviso rimosso.