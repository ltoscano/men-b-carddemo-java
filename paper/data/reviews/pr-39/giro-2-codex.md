APPROVATA

| Rilievo della prima validazione | Stato | Comando | Esito |
|---|---|---|---|
| 1 — Esclusione indebita dei casi determinati e atteso N1 infedele | **Chiuso** | `python3 .validazione/giro2/probe.py` | `1 → 1`, `2031-12-09`: **`2031--1-2-`, RC 0**, resto dell’area conservato. Ex N1: `2025--0-3-`, RC 0. Prefisso esatto `-INVALID INPUT` nei byte 6–19: **97**. Differenza in ciascuna delle 14 posizioni, un byte alla volta: **RC 0**, tutti gli 80 byte conformi. |

Letto integralmente il diff di correzione e verificati routine, tabelle, PARM con spazi interni, `coerenza.sh` e attesi.

- **Prove negative:** `python3 .validazione/giro2/mutazioni.py` altera un byte dell’atteso D1E e il codice di N5 da 97 a 0. Il controllo fallisce con **1**, indicando rispettivamente le righe 6 e 2; dopo il ripristino torna **0**. La suite respinge anche le routine mutate che confrontano soltanto 1 o 13 byte oppure ignorano il prefisso esatto.
- **Perimetro:** `git diff --name-only 5c63275 HEAD` elenca dieci file, tutti sotto `oracle/`. Il patch fornito coincide integralmente con quello Git. `legacy/` pulito e fissato a `59cc6c2`.
- **Suite completa:** eseguito **una volta** `./oracle/run.sh --all --check`: **RC 0**, otto passi superati, **313,847 secondi**. Wrapper Docker limitato alla nomenclatura richiesta.

Rilievi nuovi: **nessuno**. Nelle modifiche esaminate non sono emersi nuovi falsi verdi o comportamenti infedeli dell’oracle.

File tracciati invariati, nessun commit. Risorse Docker proprie con prefisso `menb-val39b-` rimosse; nessuna risorsa condivisa rimossa.