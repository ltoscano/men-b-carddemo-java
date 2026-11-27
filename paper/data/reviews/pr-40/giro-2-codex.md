BOCCIATA

Validato SHA `29ef8ec`. Letto integralmente il diff di correzione.

| Rilievo precedente | Stato | Comando / verifica | Esito |
|---|---|---|---|
| 1. Escape Unicode | **Chiuso** | Regressioni; `javac`; `mvn -B -pl carddemo-domain -am validate` | I quattro controesempi compilano e vengono respinti con `UNICODE-ESCAPE-VIETATO`. Respinte anche più `u` consecutive e sequenze con 1–4 backslash. |
| 2. Database sotto altre coordinate | **Non chiuso** | Regressioni `db-servicemix-*`, `db-classi-hsqldb`; controprove descritte sotto | I bundle originali sono vietati; il test riconosce un driver presente e la sua rimozione viene rilevata. Restano scoperti classpath richiesti dalla specifica. |
| 3. ArchUnit assente nella build delle immagini | **Limite documentato** | `nl -ba docs/sviluppo.md` | Riga 177: Enforcer e Checkstyle nelle immagini; ArchUnit e controllo delle classi in `verify.sh`. Conforme alla decisione. |
| 4. Sorgente residuo dopo scrittura fallita | **Chiuso** | `bash <cartella temporanea>/partial.sh`; `bash <cartella temporanea>/signal.sh` | Scrittura parziale seguita da errore: uscita 1. Interruzione: 143. In entrambi i casi nessun sorgente residuo. |
| 5. Strumenti locali senza timeout | **Limite documentato** | `nl -ba docs/sviluppo.md` | Riga 178: esiti controllati, timeout escluso per strumenti locali e previsto per comandi che possono attendere. Conforme alla specifica aggiornata. |

| Verifica richiesta | Comando | Esito |
|---|---|---|
| Perimetro | `git diff --name-only origin/main...HEAD` | **47 file, tutti ammessi** |
| Verifica ordinaria | `MENB_BUILD_CACHE_VOLUME=menb-val40b-m2 ./verify.sh` | **0**; 16 regole Enforcer riuscite, 4 Checkstyle, test delle classi eseguito |
| Regressioni | `MENB_BUILD_CACHE_VOLUME=menb-val40b-m2 ./quality/regressioni-regole.sh` | **0**; base più 39 casi, ripristino completato |
| Smoke ordinario | `MENB_SMOKE_PROJECT=menb-val40b-smoke ./smoke.sh` | **0**, `SMOKE RIUSCITO` |
| Smoke con campo `double` in produzione `online` | `MENB_SMOKE_PROJECT=menb-val40b-negative ./smoke.sh` | **1**, fallimento **in build** per `FP-VIETATO`; campo poi rimosso |

1. **Importante — Il nuovo controllo delle classi vede soltanto il classpath di `parity`. Falso verde: sì.**

   In [DatabaseIncorporatiTest.java:30](carddemo-parity/src/test/java/io/github/ltoscano/carddemo/parity/DatabaseIncorporatiTest.java:30), `Class.forName` usa esclusivamente il classloader del test in `parity`. Le dipendenze `optional`, `test` e `provided` degli altri moduli non vengono propagate a quel classpath.

   **Evidenza:** ho copiato senza modifiche il JAR ufficiale HSQLDB 2.7.3 sotto coordinate `it.menb:val40b-driver:1.0`, mantenendo le classi note. Aggiunto a `online`, ho eseguito:

   ```sh
   mvn -B clean verify \
     -Dtest=ArchitetturaTest,DatabaseIncorporatiTest,ValDriverTest \
     -Dsurefire.failIfNoSpecifiedTests=false
   ```

   | Dichiarazione in `online` | Driver caricabile nel modulo | Esito Maven |
   |---|---|---|
   | `compile` | Sì | **1**, rilevato dal test in `parity` |
   | `optional` | Sì | **0** |
   | `test` | Sì | **0** |
   | `provided` | Sì | **0** |

   Nei tre casi verdi sono eseguiti tutti i controlli: 16 regole Enforcer, 4 Checkstyle e ArchUnit; `DatabaseIncorporatiTest` passa. Un test aggiuntivo in `online` conferma con `Class.forName` che il driver è caricabile. Nessuna opzione `skip`, nessuna classe rinominata: il caso resta fuori dal limite concordato sulle coordinate ignote **senza** classi note.

   **Correzione richiesta:** controllare i classpath effettivi di ciascun modulo, includendo gli ambiti richiesti, e aggiungere regressioni per queste tre dichiarazioni sotto coordinate diverse. [Riproduzione](file locale del Validatore, non conservato), [log optional](file locale del Validatore, non conservato), [controprova compile](file locale del Validatore, non conservato).

Prove eseguite in cloni temporanei, con adattamenti ai soli nomi Docker. Modifiche temporanee ripristinate; risorse Docker `menb-val40b-` rimosse. Ramo originale invariato, nessun commit.