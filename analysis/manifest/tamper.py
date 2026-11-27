#!/usr/bin/env python3
"""Produce versioni alterate del manifesto o degli attesi, per i test negativi.

Uso:
  tamper.py manifest IN OUT   omette un file (app/cpy/CVACT01Y.cpy) e duplica un altro file dello stesso
                              tipo (app/cbl/CBACT01C.cbl, cobol): il numero di righe resta invariato
  tamper.py expected IN OUT   altera il valore atteso dei programmi cobol sotto app/cbl (31 -> 30)
"""
import sys


def main(mode: str, src: str, dst: str) -> int:
    lines = open(src, encoding="utf-8").read().split("\n")
    out = []
    if mode == "manifest":
        dropped = dup = False
        for l in lines:
            if l.startswith("app/cpy/CVACT01Y.cpy\t"):
                dropped = True
                continue
            out.append(l)
            if l.startswith("app/cbl/CBACT01C.cbl\t"):
                out.append(l)
                dup = True
        assert dropped and dup, "righe da alterare non trovate"
    elif mode == "expected":
        done = False
        for l in lines:
            if l.startswith("cobol_sotto_app_cbl\t"):
                l = "cobol_sotto_app_cbl\t30"
                done = True
            out.append(l)
        assert done, "riga da alterare non trovata"
    else:
        return 2
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
