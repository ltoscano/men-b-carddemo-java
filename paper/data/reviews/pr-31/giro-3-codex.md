APPROVATA

Validato `ceeddcf`. Timeout: 600 s per ogni analisi, 30–60 s per gli helper; nessuno raggiunto.

`git status` **non è letteralmente vuoto**: contiene soltanto `?? .validazione/`, già presente all’avvio. Dopo ogni corsa di base e al termine, nessuna modifica tracciata. Output versionati, indice e 329 file legacy invariati. Il diff dal secondo giro comprende tre file ammessi; quello complessivo della PR cinque, tutti nel perimetro.

Abbreviazioni: `R` = `./analysis/run.sh --all`; `C` = `./analysis/run.sh --all --check`; `W` = wrapper Docker che restituisce 42 soltanto per il ricalcolo layout indicato; `V` = funzione reale `verdict_compute layout "" --out /analysis/tools/out`, dopo aver caricato le librerie.

| Prova | Comando | Esito | Durata |
|---|---|---|---:|
| Rigenerazione 1 | `R` | 0 | 156,355 s |
| Controllo 1 | `C` | 0 | 173,799 s |
| Rigenerazione 2 | `R` | 0 | 110,774 s |
| Controllo 2 | `C` | 0 | 291,583 s |
| Errore Docker sottostante | `W glue_run … compare.py layout --out /analysis/tools/out` | 42, diagnostica verificata | 0,325 s |
| Preparazione della diagnostica residua | `W verdict_text layout "" --out /analysis/tools/out` | 0; produce intestazione e diagnostica senza esito | 0,047 s |
| Ricalcolo guasto e diagnostica residua | `W C`, residuo inserito prima di `3e` | 1; **riconciliazione finale**, file non valido | 188,437 s |
| Ricalcolo guasto e residuo valido | `W C` | 1; **riconciliazione finale**, errore operativo 42 | 158,877 s |
| Registro ereditato, scrittura scc saltata | `env WRITTEN=… R` | 1; nomina la scrittura mancante | 109,047 s |
| Cancellato `cb2xml/verdetto-layout.txt` | `C` | 1; nomina il file mancante | 8,500 s |
| Cancellato `cmt/verdetto-call.txt` | `C` | 1; nomina il file mancante | 8,712 s |
| Cancellato `gnucobol/verdetto-compile.txt` | `C` | 1; nomina il file mancante | 8,732 s |
| Verdetto layout copiato sotto `cmt` | `C` | 1; percorso non dovuto | 4,898 s |
| PR 18: aggregato scc azzerato | `C` | 1; somme incoerenti | 12,540 s |
| PR 18: campo XML cb2xml rinominato, TSV invariato | `C` | 1; rinormalizzazione diversa | 70,645 s |
| PR 18: `POSTTRAN/STEP15`, `PGM → PROC` | `C` | 1; tipo errato | 19,619 s |
| Risposta vuota, codice 0 | `V` con wrapper | 2; rifiutata | 0,185 s |
| Risposta troncata, codice 0 | `V` con wrapper | 2; rifiutata | 0,039 s |
| `pass`, codice 1 | `V` con wrapper | 2; rifiutata | 0,046 s |
| `fail`, codice 0 | `V` con wrapper | 2; rifiutata | 0,040 s |
| `pass`, codice 42 | `V` con wrapper | 2; rifiutata | 0,049 s |
| Traceback, codice 1 | `V` con wrapper | 2; rifiutata | 0,053 s |
| Testo dopo la riga di esito | `V` con wrapper | 2; rifiutata | 0,043 s |
| Controllo finale consecutivo 1 | `C` | 0; nove verdetti riconciliati | 255,478 s |
| Controllo finale consecutivo 2 | `C` | 0; nove verdetti riconciliati | 294,810 s |
| Stato, perimetro, indice e hash legacy | `python3 /tmp/val31c-audit/final.py` | 0; ripristini verificati | 0,346 s |

Per la diagnostica residua ho evitato il falso riscontro già descritto dall’Esecutore: il wrapper inserisce il residuo dopo le prove interne, immediatamente prima della riconciliazione finale. Il log raggiunge `3e`, poi segnala `verdetto salvato cb2xml/verdetto-layout.txt non valido`; nessuna fixture negativa è fallita. Con il residuo valido, nello stesso passo vengono invece segnalati il codice 42 e il ricalcolo non concluso.

Lo stato dei due rilievi del secondo giro è:

| Rilievo | Stato e classificazione |
|---|---|
| Diagnostica d’errore accettata come verdetto | **Chiuso.** Originariamente importante e capace di falso verde dell’intero controllo. Entrambe le varianti ora falliscono nella riconciliazione. **Falso verde attuale: non riprodotto. Escluso dalla regola: no**, è un errore operativo esplicito. Nessuna correzione residua richiesta. |
| Registro delle scritture ereditato | **Chiuso.** Originariamente importante e capace di falso verde del produttore. Il riproduttore richiesto ora fallisce nominando scc. **Falso verde attuale: non riprodotto.** Il riproduttore modifica deliberatamente lo script per saltare una scrittura: **questa parte rientra nell’esclusione della regola attuale**. Nessuna correzione residua richiesta. |

1. **Nessun rilievo nuovo o rimasto.** Dalla lettura integrale di `git diff 4b70d0e..HEAD` e dalle prove eseguite non emergono rilievi bloccanti, importanti o minori. Le due esecuzioni finali consecutive danno entrambe 0: nessun falso rosso osservato senza mutazioni. Nessuna correzione richiesta.

[Registro delle prove](file locale del Validatore, non conservato) e [riproduttori del secondo giro](file locale del Validatore, non conservato). Verifica locale con cache Docker; GitHub Actions non rieseguite. Nessun commit, push o comando Docker globale; nessuna rimozione delle immagini o del volume condivisi.