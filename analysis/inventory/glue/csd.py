#!/usr/bin/env python3
"""Transazione -> programma dai file CSD del manifesto (estrazione testuale minima: DEFINE TRANSACTION(...) e la
prima clausola PROGRAM(...) prima del DEFINE successivo). Uso: csd.py OUTDIR"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import of_type, read_lines, write_tsv

rows = []
for path in of_type("csd"):
    cur = None
    for n, line in enumerate(read_lines(path), 1):
        m = re.match(r"\s*DEFINE\s+(\w+)\((\w+)\)", line, re.I)
        if m:
            cur = None
            if m.group(1).upper() == "TRANSACTION":
                cur = [path, n, m.group(2).upper(), "", ""]
                rows.append(cur)
            continue
        if cur is not None and not cur[3]:
            p = re.search(r"\bPROGRAM\((\w+)\)", line, re.I)
            if p:
                cur[3], cur[4] = p.group(1).upper(), n
for r in rows:
    if not r[3]:
        print(f"CSD: transazione {r[2]} senza PROGRAM() in {r[0]}:{r[1]}", file=sys.stderr)
        sys.exit(1)
write_tsv(os.path.join(sys.argv[1], "csd.tsv"), ["file", "riga", "transazione", "programma", "riga_programma"], rows)
