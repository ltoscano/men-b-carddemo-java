**BOCCIATA — resta un falso verde nel nuovo controllo delle righe `== codice`.**

| Rilievo precedente | Stato | Comando / controesempio rieseguito | Esito |
|---|---|---|---|
| 1. Elenco troncato in `esegui.sh` | **Chiuso** | `sh /oracle/esegui.sh /res PARMECHO --parm 2022071800`, con `ls` e separatamente `sort` troncati → 42 | Uscita **2**; `ZZ_INATTESO` realmente presente; rapporto diverso da quello sano; diagnostica di rapporto incompleto. |
| 2. Acquisizioni in `verifica.sh` | **Chiuso** | `verifica.sh` con `ls`, `awk` delle righe TSV e `grep` dell’elenco autentici → 42 | Uscita **1**, con diagnostiche pertinenti. `cut` e `basename` sono eliminati; equivalenza delle espansioni verificata. |
| 3. Produttori falliti nella build | **Chiuso** | `oracle/run.sh build` su copie: `in_container` → 42; acquisizione `awk` di `compile.sh` → 42 | Uscita **1**, bersagli raggiunti, nessuna `IMPRONTA`. La sostituzione `printf` di IFS è eliminata: TAB costante. |
| 4. Righe `== codice` mancanti | **Non chiuso integralmente** | `verifica.sh` con cancellazione totale, parziale, nel modulo e con duplicazioni | Cancellazioni e duplicazione eccedente → **1**. Cancellazione compensata da duplicazione → **0**: rilievo 1 sotto. |
| 5. Censimento fuori perimetro | **Chiuso** | Lettura della descrizione e del commento sulla issue #45 tramite `gh api` | Presenti tutte le **24 posizioni** richieste; relativi script invariati. |

1. **Importante — il conteggio totale non garantisce un codice per ciascuna invocazione.**  
   In `oracle/build/verifica.sh:130–142` si controllano soltanto numero complessivo e valore dei codici. Nella copia del log sano di `CBACT01C` ho cancellato il primo `== codice 0` e duplicato il secondo: il primo blocco `== cobc` resta senza codice, il secondo ne contiene due. `verifica.sh` restituisce **0**, dichiarando riuscita la verifica dei 26 programmi; anche `stamp_problem` restituisce **0**. [Log alterato](file locale del Validatore, non conservato), [esito della verifica](file locale del Validatore, non conservato).

   **Correzione richiesta:** verificare esattamente un codice per ogni blocco di invocazione, rifiutando codici mancanti o duplicati anche quando il totale coincide; aggiungere questa mutazione alle prove automatiche. **Falso verde: sì. Oracle infedele nei risultati dei programmi: non dimostrato; evidenza incompleta accettata: dimostrato.**

2. **Minore — la tabella dichiarata esaustiva omette `build/avvolgi.sh`.**  
   La ricerca indipendente trova due sostituzioni funzionali non censite: `prec="$(/usr/bin/grep …)"` alla riga 25 e `t="$(/usr/bin/mktemp …)"` alla riga 44, quest’ultima introdotta dalla correzione. Entrambe hanno l’esito controllato.

   **Correzione richiesta:** aggiungerle alla tabella con classificazione e copertura delle prove. **Falso verde: no. Oracle infedele: no.**

Il diff di correzione è stato letto integralmente e coincide con `git diff 6f4a613 HEAD -- oracle .github`. Le interfacce provate sono compatibili con `origin/main`: log di `compile.sh uno` identici per caso sano, sorgente assente e sorgente `.CBL`; rapporto e ambiente di `esegui.sh` identici; funzioni pubbliche di `lib.sh` conservate. Le espansioni coincidono sui 26 nomi reali, su un caso con spazi e su cinque conteggi numerici con spazi.

Nessuno dei **51 attesi preesistenti** è cambiato. Main termina con **0** e tutte le sue **167 righe** di prove negative e controprove ricompaiono identiche nella PR. Le sostituzioni ES07 e VF01 sono dichiarate nel diff.

Eseguiti:

- `./oracle/run.sh --all --check`: **0**, una corsa sul ramo.
- `./analysis/run.sh data-codec --check`: **0**.
- `gh pr checks 49`: **8/8 verdi** sullo SHA corrente `44f8c45ceb2630fa7818127eb08d1ca5108831cc`; conteggi locali identici alla [CI della PR](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46062328275).

Nessuna correzione, commit, push o avvio di workflow. Risorse Docker della validazione rimosse; nessuna risorsa condivisa rimossa.