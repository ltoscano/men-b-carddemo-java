APPROVATA

Esaminato `b7aa5a30a5eeba2ac7913334d8a658ef670b0082`. Tutti i sei rilievi sono chiusi.

Nella tabella, `S` indica `./analysis/run.sh data-sentinelle`. Le alterazioni sono state applicate esclusivamente a copie private.

| Rilievo | Stato | Comando | Esito |
|---|---|---|---|
| 1. Copertura incompleta | Chiuso | `S` e `S --check` | **1** per eliminazione coordinata di `EXPORT-ACCOUNT-DATA.tsv` e relativa riga, anche con gli offset scambiati; **1** eliminando `prefisso-39` insieme al nome; **1** con due prefissi da 12 byte. |
| 2. Fonte obbligatoria omessa | Chiuso | `S` e `S --check` | **1**, con `S24`, sostituendo la fonte di `CUSTREC` con “nessuna fonte”. |
| 3. Ricodifica senza controprove | Chiuso | `S --check`, con entrambi i controlli disattivati | **1**; falliscono le prove di ricodifica e ricomposizione. L’inventario segnala `R01` e `R02` scoperti. |
| 4. Non applicabilità errate | Chiuso | `S --check`; compilazione della sonda con `cobc -free -x` | La scala di `CDEMO-PGM-CONTEXT` produce **7.9**; la coppia richiesta produce `U02` sul valore **900000004**. GnuCOBOL conferma `PIC V9`: **un byte, `.7`**. |
| 5. Riempimento variabile confrontato | Chiuso | `S`, alterando soltanto il byte 80 ricodificato | **0**, nessun errore; prefissi invariati. |
| 6. Errore operativo di `diff` accettato | Chiuso | `bash .validazione/val51b/diff2.sh` | Il vero `diff` esce con **2**; il blocco estratto da `check.sh` termina con **1**, dichiarando errore operativo. |

L’atteso delle **23 sentinelle** deriva dai contratti e dall’insieme fisso dei prefissi `{12,39}`; accorciare l’elenco manuale non lo riduce. Aggiungere `CUSTREC` o `COSTM01` a `senza-fonte.tsv`, rimuovendone contestualmente la citazione, produce **1**: rispettivamente `S27` e `S26`.

Il meccanismo dei codici è onesto: una prova accredita il codice soltanto se compare negli errori. Ho disattivato singolarmente **C23, S27 e V04**: `--check` termina sempre con **1**, indicando rispettivamente le prove `prefisso-duplicato`, `senza-fonte-con-recln` e `spazio-in-testa`; l’inventario nomina il codice scoperto. Per `C23` compare esplicitamente «codici di asserzione attesi mancanti», pur essendo presenti gli altri errori attesi.

Le due asserzioni eliminate erano irraggiungibili: `ordina_contratto` assegna identità univoche per costruzione. Verificate anche **5.460 sequenze** con percorsi ripetuti e `OCCURS`, senza collisioni.

**Rilievi nuovi: nessuno.**

Verifiche finali:

- `./analysis/run.sh data-sentinelle --check`: **0**; 2.792 prove superate, 98 non applicabili, 81 asserzioni coperte.
- `./analysis/run.sh --all --check`: **0**.
- `gh pr checks 51` e API dei check sullo SHA corrente: tutti gli **otto check verdi**, inclusi `analysis-check`, `oracle-check`, `verify` e `smoke`.
- Sentinelle, attesi, `viste.tsv`, `analysis/data-codec/` e `legacy/` invariati rispetto a `faf2559`. I **36 file** del diff `origin/main...HEAD` sono tutti ammessi.

Nessun file tracciato modificato, nessun commit. Risorse Docker `menb-val51b-` rimosse; nessun residuo. Evidenze in `.validazione/val51b/`.