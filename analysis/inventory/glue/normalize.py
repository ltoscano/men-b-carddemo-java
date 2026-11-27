#!/usr/bin/env python3
"""Porta l'output grezzo di cobol-migration-toolkit e di mapa in TSV a colonne fisse. Non interpreta COBOL o JCL.

Uso: normalize.py cmt RAWDIR OUTDIR     (RAWDIR/<cartella>/inventory.json, una per cartella scandita)
     normalize.py mapa RAWDIR OUTDIR    (RAWDIR/*.csv, uno per file JCL)
"""
import csv
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import of_type, stem, write_tsv


def cmt(raw, out):
    by_stem = {stem(p): p for p in of_type("cobol")}
    rows = []
    for p in sorted(glob.glob(os.path.join(raw, "*", "inventory.json"))):
        inv = json.load(open(p, encoding="utf-8"))
        for u in inv["units"]:
            prog = stem(u["path"])
            if prog not in by_stem:
                print(f"cmt: unita' {u['path']} senza file nel manifesto", file=sys.stderr)
                return 1
            for c in u.get("calls", []):
                rows.append((by_stem[prog], c))
    rows.sort()
    write_tsv(os.path.join(out, "cmt_calls.tsv"), ["file", "chiamato"], rows)
    return 0


def mapa(raw, out):
    steps, dds = [], []
    for p in sorted(glob.glob(os.path.join(raw, "*.csv"))):
        with open(p, encoding="utf-8", newline="") as f:
            recs = [r for r in csv.reader(f) if r]
        path = None
        info = {}
        for r in recs:
            if r[0] == "FILE":
                assert r[1].startswith("/legacy/"), r[1]
                path = r[1][len("/legacy/"):]
            elif r[0] == "JOBSTEP":
                # JOBSTEP,nome,seq,jobUUID,stepUUID,PGM|PROC,nome
                info[r[4]] = (r[1], int(r[2]))
                steps.append((path, r[1], int(r[2]), r[5], r[6]))
            elif r[0] == "JOBSTEPDD":
                # JOBSTEPDD,dd,stepUUID,ddUUID,seq,classe,"dsn",disp1,disp2,disp3
                name, ordn = info[r[2]]
                dds.append((path, name, ordn, r[1], r[6], "/".join(x for x in r[7:10] if x), r[5]))
    steps.sort(key=lambda x: (x[0], x[2]))
    # l'ordine delle DD dentro un passo e' quello dell'output (non si riordina)
    order = {}
    for i, d in enumerate(dds):
        order[id(d)] = i
    dds.sort(key=lambda x: (x[0], x[2], order[id(x)]))
    write_tsv(os.path.join(out, "mapa_steps.tsv"), ["file", "passo", "ordinale", "tipo", "nome"], steps)
    write_tsv(os.path.join(out, "mapa_dd.tsv"), ["file", "passo", "ordinale", "dd", "dsn_risolto", "disp_effettivo", "classe"], dds)
    return 0


if __name__ == "__main__":
    sys.exit({"cmt": cmt, "mapa": mapa}[sys.argv[1]](sys.argv[2], sys.argv[3]))
