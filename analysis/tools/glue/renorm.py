#!/usr/bin/env python3
"""Rigenera i TSV normalizzati dall'output GREZZO di uno strumento (in una cartella temporanea del container)
e verifica che coincidano byte per byte con quelli versionati.

Uso: renorm.py TOOL RAW_DIR VERSIONED_DIR
  TOOL: cmt | cb2xml            (cobmix e mapa non hanno il grezzo versionato: si rieseguono, vedi check.sh)
  RAW_DIR: cartella con l'output grezzo (di norma quella versionata; nei test negativi una copia alterata)
  VERSIONED_DIR: cartella con i TSV versionati da confrontare
"""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import normalize  # noqa: E402

TSV = {"cmt": ("copy.tsv", "calls.tsv", "programs.tsv"), "cb2xml": ("layout.tsv", "lengths.tsv")}


def main(tool, raw, versioned):
    tmp = tempfile.mkdtemp()
    work = os.path.join(tmp, tool)
    shutil.copytree(raw, work, ignore=shutil.ignore_patterns(*TSV[tool]))   # solo il grezzo, senza i TSV
    getattr(normalize, tool)(work)
    bad = 0
    for name in TSV[tool]:
        a = open(os.path.join(work, name), "rb").read()
        b = open(os.path.join(versioned, name), "rb").read()
        if a != b:
            print(f"RINORMALIZZAZIONE: {tool}/{name} rigenerato dal grezzo diverso da quello versionato", file=sys.stderr)
            bad = 1
    if not bad:
        print(f"{tool}: TSV rigenerati dal grezzo identici a quelli versionati ({', '.join(TSV[tool])})")
    return bad


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
