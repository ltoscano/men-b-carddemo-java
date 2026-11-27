#!/usr/bin/env python3
"""Presenta a mapa le procedure di app/proc/ con il nome che si aspetta (senza estensione).

Uso: stage_procs.py stage DIR    copia byte per byte le procedure del manifesto in DIR
     stage_procs.py verify DIR   verifica che DIR contenga esattamente quelle copie, identiche agli originali
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import of_type, stem


def expected():
    return {stem(p): p for p in of_type("proc")}


def stage(d):
    os.makedirs(d, exist_ok=True)
    for name, p in sorted(expected().items()):
        shutil.copyfile("/legacy/" + p, os.path.join(d, name))


def verify(d):
    exp = expected()
    present = sorted(os.listdir(d))
    if present != sorted(exp):
        print(f"PROCEDURE: file presentati {present}, attesi {sorted(exp)}")
        return 1
    bad = 0
    for name, p in sorted(exp.items()):
        a = open("/legacy/" + p, "rb").read()
        b = open(os.path.join(d, name), "rb").read()
        if a != b:
            print(f"PROCEDURE: la copia {name} non e' identica all'originale {p}")
            bad = 1
    if not bad:
        print(f"PROCEDURE: {len(exp)} copie identiche byte per byte agli originali")
    return bad


if __name__ == "__main__":
    sys.exit({"stage": lambda: stage(sys.argv[2]) or 0, "verify": lambda: verify(sys.argv[2])}[sys.argv[1]]())
