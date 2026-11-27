"""Verifica completa delle fixture (issue #5) e scrittura delle uscite.

Uso: verifica.py LEGACY DC MANIFESTO CARTELLA OUT [--confronta VERSIONATI]
Scrive OUT/out/<fixture ed elenchi> e OUT/fixture.md solo se la verifica riesce; stampa un errore per riga
("ERRORE [codice] testo") e, se non ce ne sono, la tabella dei conteggi e l'ultima riga "verifica riuscita: ...".
Esce con 1 se c'e' almeno un errore, 2 per un errore operativo o per il limite di tempo (300 s).
"""
import os
import signal
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import documento  # noqa: E402
import fixture as fx  # noqa: E402
import verificatore  # noqa: E402

LIMITE = 300


def scaduto(*_):
    print(f"ERRORE operativo: limite di {LIMITE} s superato", flush=True)
    os._exit(2)


def main(argv):
    if len(argv) not in (5, 7) or (len(argv) == 7 and argv[5] != "--confronta"):
        print(__doc__)
        return 2
    signal.signal(signal.SIGALRM, scaduto)
    signal.alarm(LIMITE)
    legacy, dc, man, cartella, out = argv[:5]
    versionati = argv[6] if len(argv) == 7 else None
    ing = fx.Ingressi(legacy, dc, man, cartella)
    es, voci, dec, confronti, att, uscite = verificatore.verifica(ing, versionati)
    for c, t in es.errori:
        print(f"ERRORE [{c}] {t}")
    if es.errori:
        print(f"verifica fallita: {len(es.errori)} errori, codici {sorted(es.codici())}")
        return 1
    os.makedirs(os.path.join(out, "out"))
    for n, testo in uscite.items():
        with open(os.path.join(out, "out", n), "w", encoding="utf-8") as f:
            f.write(testo)
    with open(os.path.join(out, "fixture.md"), "w", encoding="utf-8") as f:
        f.write(documento.documento(ing, voci, dec, confronti, att, uscite))
    print(uscite["conteggi.tsv"], end="")
    n_rec = sum(len(fd.record) for fd in dec.values())
    n_att = sum(len(a) for a in att.values() if a)
    print(f"verifica riuscita: {len(dec)} file, {n_rec} record decodificati, {n_att} record attesi a mano, "
          f"{len(confronti)} confronti ASCII/EBCDIC, {sum(len(fd.anomalie) for fd in dec.values())} anomalie")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # errore operativo: mai scambiabile per un esito
        print(f"ERRORE operativo: {type(e).__name__}: {e}")
        sys.exit(2)
