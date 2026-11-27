BOCCIATA

Revisionato SHA `ea254ca1455d98a6db6606f1916a84056841150a`. I due rilievi del secondo giro risultano chiusi, ma la correzione dell’arresto introduce un falso rosso dimostrato.

Timeout esterni: 900 s per la prima esecuzione, 150 s per le successive; nessuno è scattato. Per le mutazioni applicative: `MENB_HEALTH_TIMEOUT=8`, `MENB_BATCH_TIMEOUT=5`. Durate comprensive di build e pulizia. Uno shim Docker applica il prefisso richiesto; nelle prove sul residuo sostituisce anche il bind mount con un volume Linux.

| Prova eseguita / comando | Esito osservato | Durata |
|---|---|---:|
| Clone iniziale: `./verify.sh` | **0**, online sano, batch 0 | 35,766 s |
| `./verify.sh`: jar residuo, `repackage` rimosso, target `1777`, proprietario `1000:1000`, `--cap-drop=FOWNER` | **1**, errore reale di cancellazione; Maven non avviato; hash del jar invariato | 0,285 s |
| `./verify.sh`: online sano che ignora SIGTERM | **1**, SIGKILL e fallimento propagato | 16,968 s |
| `./verify.sh`: HTTP 200, radice `DOWN`, componente `UP` | **1**, salute respinta | 14,170 s |
| `./verify.sh`: connessioni accettate senza risposta | **1**, attesa limitata | 19,138 s |
| `./verify.sh`: asserzione del loader sostituita con `fail(...)` | **1**, `BUILD FAILURE` | 3,558 s |
| `./verify.sh`: cancellazione consentita, `repackage` ancora rimosso | **1**, build riuscita ma nessun eseguibile trovato | 5,705 s |
| `./verify.sh`: arresto regolare dopo 9,25 s, con audit dei segnali | **1 inatteso**, falso rosso | 17,015 s |
| Stessa prova, `./verify.sh` senza audit | **1 inatteso**, falso rosso riprodotto | 18,774 s |
| Sorgenti ripristinati: `./verify.sh` | **0**, verifica completata | 14,250 s |

Risultati e durate registrati (log locale del Validatore, non conservato).

| Rilievo del secondo giro | Stato |
|---|---|
| Cancellazione fallita ignorata, con possibile uso del jar residuo | **Chiuso** |
| Online che ignora SIGTERM: arresto forzato trattato come avviso | **Chiuso** |

1. **Importante — Falso rosso quando online termina nell’ultimo secondo dell’attesa di arresto.**  
   **Evidenza eseguita:** ho aggiunto temporaneamente un hook di shutdown che attende 9,25 s e completa normalmente. Online diventa sano e termina tramite SIGTERM entro i 10 s dichiarati. Tuttavia `stop_proc`, dopo l’ultima `sleep`, tenta direttamente SIGKILL e restituisce sempre 1. L’audit registra:
   ```text
   kill -TERM 323 rc=0
   kill -KILL 323 rc=1
   wait 323 rc=143
   ```
   Il processo era già terminato quando è stato tentato SIGKILL. Il nuovo controllo a `verify.sh:120` trasforma questo risultato errato in fallimento dell’intera verifica. La ripetizione senza audit conferma il falso rosso. Audit completo (log locale del Validatore, non conservato), completamento dell’hook (log locale del Validatore, non conservato).  
   **Correzione richiesta:** ricontrollare la sopravvivenza dopo l’ultima attesa e gestire anche la corsa tra controllo e invio di SIGKILL. Distinguere un processo già terminato da un errore reale di arresto; propagare il fallimento quando la forzatura è effettivamente necessaria o l’arresto fallisce. Ripetere la prova con uscita tra 9 e 10 s.

Ho **letto** entrambi i diff e verificato che coincidono con quelli Git. Il diff complessivo contiene **21 file, 538 inserzioni, nessun percorso fuori perimetro**; non emergono anticipazioni della #15, che non ho valutato. La CI è **solo letta** da `.validazione/ci.txt`: due `pass`, 42 e 43 s.

Mutazioni ripristinate, nessuna modifica tracciata residua. Rimossi tutti i container e il volume creati per le prove. Nessun commit o push.