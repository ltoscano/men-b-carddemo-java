**BOCCIATA — riprodotto un nuovo falso verde: un comando di acquisizione della configurazione fallisce, ma l’intera suite passa.**

Validato `e34fcce`. Mutazioni ripristinate, nessun commit o push. Diff della PR solo sotto `oracle/`; legacy e `analysis/` intatti. Nessuna operazione Docker globale o su risorse `menb-analysis-*`.

Ho eseguito le prove riportate sotto. Timeout esterni specifici per comando, da 30 a 1200 s; nessuno scaduto. Comandi completi e tempi nel registro (file locale del Validatore, non conservato), mutazioni nello script riproducibile (file locale del Validatore, non conservato). Nella tabella, `V` indica l’esecuzione diretta di `oracle/build/verifica.sh` nel container; durate ed esiti multipli seguono l’ordine dei comandi.

| Prova | Comando | Esito | Durata |
|---|---|---|---:|
| Build iniziale | `./oracle/run.sh build` | **0** | 7,355 s |
| Prima suite completa | `./oracle/run.sh --all --check` | **0**, 72 negative e 3 controprove | 140,274 s |
| Seconda suite consecutiva | stesso comando | **0**, 72 negative e 3 controprove | 292,986 s |
| Perimetro, legacy, attesi precedenti | confronto Git e byte degli attesi | **0**: solo `oracle/`, legacy pulito, 18 attesi invariati | 0,258 s |
| Configurazione alternativa | `docker run … cp …`, aggiunta `perform-osvs: no` | **0** | 0,376 s |
| `COB_CONFIG_DIR` solo esportata in `compile.sh` | `build`; `V`; `dialetto` | **0 / 0 / 0**; configurazione originale, `B C D DONE` | 5,288 / 0,922 / 2,227 s |
| Variabile aggiunta all’elenco ammesso | `build --check`; `dialetto` | **1 / 0**; controllo rosso, flusso della sonda cambiato | 7,133 / 2,255 s |
| `COB_VARSEQ_FORMAT=1` ammessa al runtime | `build`; `V`; `avvio`; `avvio --check` | **0 / 1 / 0 / 1**; variabile presente nei programmi e rilevata | 4,808 / 0,783 / 5,487 / 5,804 s |
| `ibm.conf` realmente alterato nell’immagine derivata | `build --check`; `dialetto` | **1 / 0**; SHA diverso rilevato, sonda cambiata | 23,010 / 6,632 s |
| `-fno-binary-truncate` aggiunta in coda | `build --check` | **1**, argomenti diversi | 12,691 s |
| `-fsign=EBCDIC` rimossa | `build`; `segno --check` | **0 / 1**, valori e byte diversi | 13,823 / 4,651 s |
| Solo lunghezza PARM diminuita di uno | `build`; `avviatore --check` | **0 / 1**, lunghezza 9, testo completo | 14,493 / 5,164 s |
| `CEE3ABD` termina con 0 | `build`; `abend --check` | **0 / 1**, entrambe le chiamate rilevate | 14,323 / 5,588 s |
| Immagine con `cobcrun` che restituisce errore | `docker build …`; `docker run … cobcrun --runtime-config` | **0 / 42**; output autentico identico all’atteso | 2,205 / 0,964 s |
| Suite con quel comando in errore | `./oracle/run.sh --all --check` | **0: falso verde**, tutte le 72 negative e 3 controprove passano | 258,841 s |
| Build ripristinata | `./oracle/run.sh build` | **0** | 4,918 s |
| Rapporto runtime corrotto | `V` | **1**, configurazione diversa | 0,721 s |
| Build precedente a una modifica di `ambiente.sh` | `avvio --check` | **1**, build non aggiornata | 1,571 s |
| Esecuzione finale ripristinata | `./oracle/run.sh --all` | **0** | 19,081 s |
| Confronto finale indipendente | `python3 /tmp/val29c-compare.py` | **0**, 19 confronti identici agli attesi del giro 2; nessuna modifica tracciata residua | 0,291 s |

**Rilievo del secondo giro: chiuso.** L’export viene filtrato da `env -i`; ambiente e `cobc --info` restano quelli dell’immagine. Quando la variabile arriva davvero al compilatore, il controllo fallisce e la sonda cambia comportamento. Anche gli attacchi al runtime e al file dell’immagine vengono rilevati.

La sonda `PERFORM` è corretta come discriminatore dell’impostazione **GnuCOBOL** `perform-osvs`. L’atteso `B C D DONE` non è però giustificato dalla regola IBM: l’intervallo interno `P-B..P-E` attraversa l’uscita `P-D` dell’intervallo esterno attivo. IBM richiede intervalli interni interamente inclusi o esclusi, ammettendo l’uscita comune. Qui le uscite sono diverse. Ho eseguito GnuCOBOL e letto la documentazione; **non ho eseguito Enterprise COBOL**. Non considero questa sonda una dimostrazione di fedeltà o infedeltà IBM. [Regola IBM](https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=statement-basic-perform), [configurazione GnuCOBOL](https://gnucobol.sourceforge.io/doc/gnucobol.html).

Non ho osservato falsi rossi. Dopo il ripristino, avvio, avviatore, arresto anomalo e segno producono gli stessi risultati precedenti: 19 confronti byte per byte contro 18 file attesi, perché `ABDFILE.hex` si applica a entrambi i chiamanti.

1. **Importante — codici di errore delle acquisizioni ignorati.**

   Evidenza: [compile.sh:144](oracle/build/compile.sh:144) esegue `cobcrun --runtime-config` senza controllarne il ritorno; la decisione finale considera soltanto gli esiti delle compilazioni. Anche altre acquisizioni alle righe 125–141 ignorano errori o li nascondono nelle pipeline.

   **Riproduzione eseguita:** nell’immagine derivata ho rinominato il vero `cobcrun` e installato un involucro che lo esegue, ne conserva l’output autentico e, dopo il successo, termina con 42. I 2766 byte prodotti coincidono esattamente con l’atteso. Il comando diretto restituisce **42**, ma `--all --check` restituisce **0**. Log completo del falso verde (file locale del Validatore, non conservato).

   **Classificazione:** falso verde dimostrato; nessuna infedeltà dei programmi dimostrata da questa prova. **Rientra nel mandato:** il comando fallisce, i dati non sono falsificati e gli script dell’oracle registrano ciò che eseguono. Non ricade nelle esclusioni dichiarate.

   **Correzione richiesta:** propagare esplicitamente gli errori di tutte le acquisizioni e dei passaggi nelle pipeline, prima di scrivere l’impronta. Aggiungere una prova negativa con output autentico completo e ritorno non zero.

2. **Minore — estrazione errata del percorso alternativo della configurazione.**

   Evidenza: [compile.sh:140](oracle/build/compile.sh:140) usa `$2` anche per la riga:

   ```text
     env: COB_CONFIG_DIR    : /oracle/.work/val29c-review/config
   ```

   Con il separatore `: `, `$2` contiene `COB_CONFIG_DIR`, non il percorso. Nella prova eseguita il manifesto contiene soltanto `cartella COB_CONFIG_DIR` e compare `can't cd to COB_CONFIG_DIR`. La sonda conferma invece che il compilatore ha usato realmente la cartella alternativa.

   **Classificazione:** nessuno dei due impatti richiesti: il controllo resta correttamente rosso per la variabile vietata. È un difetto diagnostico, **entro il perimetro e non escluso dai limiti dichiarati**.

   **Correzione richiesta:** estrarre correttamente il percorso dalla riga `env:`, verificarne la lettura e controllare nella prova negativa che il manifesto contenga davvero gli hash della cartella alternativa.