"""Composizione dei byte delle sentinelle (issue #43): strumento d'appoggio per chi le scrive.

Uso: componi.py scrivi|verifica SENTINELLA.tsv...
  scrivi    sostituisce la riga 'record' di ogni sentinella con i byte composti dalla sua tabella dei campi
  verifica  esce con 1 se la riga 'record' di una sentinella non coincide con i byte composti dalla tabella

Legge solo la sentinella: non legge il contratto di #3 e non usa il codec di #23 (vedi sentinella.py). I valori,
le PICTURE e gli intervalli della tabella sono scritti a mano dal sorgente; qui si traducono soltanto in byte.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sentinella import SentinellaErrore, componi, esa, leggi  # noqa: E402


def main(modo, files):
    errori = 0
    for path in files:
        try:
            s = leggi(path)
            b = componi(s)
        except SentinellaErrore as e:
            print(f"ERRORE [componi] {e}")
            errori += 1
            continue
        attesi = s["prefisso"] if s["prefisso"] is not None else s["lunghezza"]
        if len(b) != attesi:
            print(f"ERRORE [componi] {path}: {len(b)} byte composti, la sentinella ne dichiara {attesi}")
            errori += 1
            continue
        if modo == "verifica":
            if b != s["byte"]:
                print(f"ERRORE [componi] {path}: la riga 'record' non coincide con i byte composti dalla tabella")
                errori += 1
            continue
        with open(path, encoding="utf-8") as f:
            righe = f.read().split("\n")
        n = [i for i, r in enumerate(righe) if r.startswith("record\t")]
        if len(n) != 1:
            print(f"ERRORE [componi] {path}: righe 'record' trovate: {len(n)}")
            errori += 1
            continue
        righe[n[0]] = "record\t" + esa(b)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(righe))
        print(f"{path}: {len(b)} byte")
    if errori:
        raise SystemExit(1)


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("scrivi", "verifica"):
        raise SystemExit("uso: componi.py scrivi|verifica SENTINELLA.tsv...")
    main(sys.argv[1], sys.argv[2:])
