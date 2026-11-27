#!/usr/bin/env python3
"""Rende counts.json (conteggi indipendenti in Python) come TSV 'tipo file valore', da confrontare con crosscheck.sh (awk). Uso: counts_tsv.py COUNTS.json"""
import json
import sys

c = json.load(open(sys.argv[1]))
rows = []
for p, n in c["copy"].items():
    rows.append(("copy", p, n))
for p, n in c["call"].items():
    rows.append(("call", p, n))
for p, v in c["jcl"].items():
    rows.append(("exec", p, v["exec"]))
    rows.append(("dd", p, v["dd"]))
for p, n in c["csd"].items():
    rows.append(("transazioni", p, n))
for r in sorted(rows):
    print("\t".join(str(x) for x in r))
