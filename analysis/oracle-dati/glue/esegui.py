"""Generazione e verifica dei record per l'oracle (issue #53).

Uso: esegui.py LEGACY DC FIXTURE CARTELLA WORK [--limite SECONDI]
  LEGACY    radice del legacy (volume sensibile alle maiuscole)
  DC        docs/legacy-map/data-contract (contratti di #3)
  FIXTURE   analysis/data-fixtures/out (fixture di #5, lette e non rigenerate)
  CARTELLA  cartella dell'analisi (tabella.tsv, attesi/)
  WORK      destinazione: WORK/out/<dd>.rec e <dd>.elenco.tsv, WORK/oracle-dati.md
Esegue il controllo 1 e genera i record in memoria; se riesce li scrive in WORK/out/, poi esegue i controlli 2, 4, 5
sui file RILETTI DAL DISCO; se un controllo fallisce cancella WORK/out/. Il documento si scrive solo se tutto riesce.
Stampa un errore per riga ("ERRORE [codice] testo") e alla fine "verifica riuscita: ..." o "verifica fallita: ...".
Esce con 1 se c'e' un errore, 2 per un errore operativo o per il limite di tempo (300 s; --limite lo cambia, solo per la
prova negativa del limite).
"""
import os
import shutil
import signal
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import documento  # noqa: E402
import oracle_dati as od  # noqa: E402

LIMITE = 300


def scaduto(*_):
    print(f"ERRORE operativo: limite di {LIMITE} s superato", flush=True)
    os._exit(2)


def main(argv):
    global LIMITE
    if len(argv) == 7 and argv[5] == "--limite":    # solo per la prova negativa del limite di tempo (check.sh)
        LIMITE = float(argv[6])
        argv = argv[:5]
    if len(argv) != 5:
        print(__doc__)
        return 2
    signal.signal(signal.SIGALRM, scaduto)
    signal.setitimer(signal.ITIMER_REAL, LIMITE)
    legacy, dc, fixture, cartella, work = argv
    out = os.path.join(work, "out")
    doc = os.path.join(work, "oracle-dati.md")
    for p in (out, doc):
        if os.path.lexists(p):
            print(f"ERRORE operativo: {p} esiste gia': la destinazione deve essere vuota")
            return 2
    ing = od.Ingressi(legacy, dc, fixture, cartella)
    es = od.Esito()
    prodotti = od.genera(ing, es)
    if not es.errori:
        od.scrivi(prodotti, out)
        riepiloghi = od.verifica(ing, out, es)
    for c, t in es.errori:
        print(f"ERRORE [{c}] {t}")
    if es.errori:
        shutil.rmtree(out, ignore_errors=True)
        if os.path.lexists(out):
            print(f"ERRORE operativo: {out} non rimossa")
            return 2
        print(f"verifica fallita: {len(es.errori)} errori, codici {sorted(es.codici())}")
        return 1
    with open(doc, "w", encoding="utf-8") as f:
        f.write(documento.documento(ing, riepiloghi))
    for voce, _, dati in riepiloghi:
        print(f"{voce['dd']}: {len(dati) // voce['lunghezza_record']} record di {voce['lunghezza_record']} byte in "
              f"{voce['uscita']}; controlli 1, 2, 4, 5 superati (il 3 e' controprova.sh)")
    print(f"verifica riuscita: {len(riepiloghi)} file, "
          f"{sum(len(d) // v['lunghezza_record'] for v, _, d in riepiloghi)} record")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # errore operativo: mai scambiabile per un esito
        print(f"ERRORE operativo: {type(e).__name__}: {e}")
        sys.exit(2)
