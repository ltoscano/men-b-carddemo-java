## Obiettivo
Chiudere i due rilievi rimasti al merge della PR #29 (oracle GnuCOBOL) e far eseguire i controlli dell'oracle alla CI.

Origine: giro 3 del Validatore sulla PR #29 (`paper/data/reviews/pr-29/giro-3-codex.md`), voce 39 del registro delle approvazioni.

## Dipendenze e perimetro
- Dipende da: #4 (mergiata).
- File coinvolti (i soli modificabili): `oracle/build/`, `oracle/README.md`, un **nuovo** file `.github/workflows/oracle.yml`.
- Fuori ambito: opzioni di compilazione, ambiente fissato, programmi, stub, attesi delle prove esistenti.

## Specifica
1. **Esito delle acquisizioni.** In `oracle/build/compile.sh` (intorno alle righe 125–144) i comandi che acquisiscono la configurazione (`cobc --info`, `cobcrun --runtime-config`, calcolo delle impronte dei file) non hanno l'esito controllato, o lo perdono in una pipeline. Con un `cobcrun` che produce l'output autentico e poi termina con 42, `--all --check` termina con 0. Ogni acquisizione deve avere l'esito verificato e propagato prima che l'impronta della build venga scritta.
2. **Percorso della configurazione alternativa.** Quando `cobc --info` riporta una riga `env: COB_CONFIG_DIR : <percorso>`, l'estrazione prende il nome della variabile al posto del percorso; il controllo resta giustamente rosso, ma la diagnostica è sbagliata (`can't cd to COB_CONFIG_DIR`) e il manifesto non contiene le impronte della cartella realmente usata. Va estratto il percorso.
3. **CI.** Il nuovo workflow esegue `./oracle/run.sh --all --check` a ogni push e pull request, con i submodule e un limite di tempo dichiarato.

## Invarianti da preservare
Tutte le prove negative esistenti continuano a dare l'esito atteso; nessun atteso cambia.

## Criteri di accettazione (verificabili)
- [ ] `./oracle/run.sh --all --check` termina con 0 due volte di seguito da clone pulito.
- [ ] Prova negativa automatica: comando di acquisizione con output autentico e ritorno diverso da zero → il controllo fallisce. Una per ciascun comando di acquisizione.
- [ ] Prova negativa esistente sulla configurazione alternativa: il manifesto contiene le impronte della cartella alternativa e nessun messaggio di errore spurio.
- [ ] Il nuovo workflow è verde sulla PR e diventa rosso alterando un valore atteso (commit temporaneo poi rimosso, collegamento nella PR).
- [ ] Il diff tocca solo i file del perimetro.

## Strategia di rollback
Revert della PR.

## Limiti per l'agente
- Nessuna modifica che cambi il comportamento dei programmi compilati.

