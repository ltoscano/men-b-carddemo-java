BOCCIATA

Validato lo SHA `9078e2b0fb58f08d69224d1f9061e4994b993e33`.

I comandi `ProbeMain` indicano il driver JUnit dell’audit, eseguito nel container con classpath e proprietà della build corrente.

| Rilievo precedente | Stato | Comando/prova | Esito |
|---|---|---|---|
| 1 — riconoscimento del job assente | **Non chiuso** | `ProbeMain run ReadacctParitaTest`, separatamente con i due jar di controprova | Con log predefiniti entrambi danno **4 fallimenti non attesi, zero ricevute**. Con WARN il job realmente avviato torna a produrre **4 falsi verdi e 4 ricevute**. |
| 2 — albero dei processi | **Non chiuso** | Caso `AvvioJobTest#alloScadereDelLimiteSiTerminaLInteroAlbero` ×3; `ProbeMain interrupt`; `ProbeMain interruptCleanup` | Timeout **3/3 riusciti**, senza superstiti né zombie. Interruzione durante l’attesa pulisce. Interruzione durante la pulizia lascia radice e figlio vivi, nipote zombie. |
| 3 — diagnosi | **Chiuso** | `ProbeMain run ComparatoreReadacctTest` e controllo manuale | Record, offset e colonne corretti; maschere accettate, byte 76 e 79 e formato GnuCOBOL respinti. Nessun cambiamento degli esiti accettati/respinti rilevato. |

Per le diagnosi ho verificato anche i conteggi: `49×107=5243`; record 50 troncato a 37 byte → EOF `5280`; record aggiuntivo 51 → offset `5350`; VBRC → offset `2907` e `2950`. Le colonne della console sono correttamente **36** e **35**, contate da 1.

L’applicazione attuale senza READACCT produce ancora quattro fallimenti attesi con ricevuta. Il criterio non dipende dai numeri di riga di Spring Boot. La transizione simulata con uscite fedeli passa **4/4**, togliendo soltanto marcature e righe dell’elenco, senza ricevute.

| Comando di accettazione | Codice |
|---|---:|
| `./verify.sh` | **0** |
| `./smoke.sh` | **0** |
| `./quality/regressioni-verify.sh` | **0** |
| `./quality/regressioni-regole.sh` | **0** |

Conteggi locali e [CI sullo SHA finale](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46130079159) coincidono: **25 classi, 476 test**; comparatore 15, estensione 5, avvio 6, parità 4.

Il diff completo coincide con i due commit di correzione: **12 file, tutti nel perimetro**. Le tre nuove applicazioni sono assenti dal jar di produzione, dalle dipendenze annidate e dal jar dell’immagine. I nuovi casi sono obbligatori per nome: togliendo quello sul timeout, `verify.sh` termina con **1**, per testcase assente. Gli override dell’host tramite `JAVA_TOOL_OPTIONS` e `MAVEN_OPTS` non propagano `menb.avvio.limite` alla verifica.

Restano questi difetti:

1. **Bloccante — falso verde quando i log di avvio sono soppressi.**  
   Configurando `logging.level.root=WARN` nel jar di controprova, il job entra realmente nel tasklet, stampa la traccia prevista e fallisce. Le due righe INFO cercate spariscono: passano **tutti i 6 test di avvio e i 4 casi di parità**, con quattro ricevute. Compare persino l’errore nativo del passo READACCT, ignorato dal rilevatore. Il controllo sul classpath dei test non copre quindi la configurazione reale del jar.  
   **Impatto:** può far passare una traduzione sbagliata nella fase marcata.  
   **Correzione richiesta:** distinguere l’avvio mediante un’evidenza indipendente dai log opzionali e rendere obbligatoria la controprova con WARN configurato nel jar.

2. **Importante — un’interruzione durante `terminaAlbero` abbandona la pulizia.**  
   Riproduzione: sospendere il figlio con `SIGSTOP`, attendere che il timeout termini il nipote, interrompere il thread durante `onExit().get(...)`. Il metodo propaga `InterruptedException` prima di terminare gli antenati: osservati Java vivo, shell sospesa e `sleep` zombie.  
   **Impatto:** nessuna delle due categorie di errore di parità; difetto di isolamento e pulizia.  
   **Correzione richiesta:** completare la terminazione dell’albero anche durante un’interruzione della pulizia, propagandola successivamente, e aggiungere una prova obbligatoria per questa finestra.

Nessuna modifica versionata o commit. Risorse Docker dell’audit rimosse; immagini e volumi condivisi intatti.