#!/usr/bin/env python3
"""Conteggi INDIPENDENTI fatti sul sorgente (non usano ne' gli strumenti ne' l'estrattore di schede).

COPY e CALL: per riga, mascherando i letterali; il nome puo' stare sulla riga successiva (COPY\\n NOME, CALL\\n 'NOME').
EXEC e DD: per riga `//nome EXEC` / `//nome DD`, dati in linea esclusi; per ogni passo il numero di DD che lo seguono.
Transazioni: occorrenze di `DEFINE TRANSACTION(` nei file csd.

Uso: counts.py OUT.json"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import of_type, read_lines

LIT = re.compile(r"'[^']*'|\"[^\"]*\"")
WORD = r"(?<![A-Za-z0-9-])%s(?![A-Za-z0-9-])"


def code_lines(path):
    for line in read_lines(path):
        if len(line) > 6 and line[6] in "*/":
            continue
        yield line[7:72]


def count_kw(path, kw, want_literal):
    n = 0
    pending = False
    for s in code_lines(path):
        orig = s
        masked = LIT.sub(lambda m: "\0" * len(m.group()), s)
        if pending and masked.strip():
            first = orig.lstrip()[:1]
            ok = (first in "'\"") if want_literal else bool(re.match(r"[A-Za-z0-9'\"]", first))
            n += 1 if ok else 0
            pending = False
        for m in re.finditer(WORD % kw, masked.upper()):
            rest = orig[m.end():].lstrip()
            if not rest:
                pending = True
                continue
            if want_literal:
                n += 1 if rest[0] in "'\"" else 0
            else:
                n += 1 if re.match(r"[A-Za-z0-9'\"]", rest[0]) else 0
    return n


def jcl_counts(path):
    steps, jobdd = [], 0
    instream = False
    for l in read_lines(path):
        l = l[:72]
        if instream:
            if l.startswith("/*") or l.startswith("//"):
                instream = False
            else:
                continue
        if l.startswith("//*"):
            continue
        m = re.match(r"^//(\S*)\s+(EXEC|DD)(\s|$)(.*)", l)
        if not m:
            continue
        if m.group(2) == "EXEC":
            steps.append([m.group(1), 0])
        else:
            if steps:
                steps[-1][1] += 1
            else:
                jobdd += 1
            if re.match(r"(\*|DATA)(\s|,|$)", m.group(4)):
                instream = True
    return {"exec": len(steps), "dd": sum(s[1] for s in steps) + jobdd, "dd_livello_job": jobdd, "passi": steps}


def main(out):
    res = {"copy": {}, "call": {}, "jcl": {}, "csd": {}}
    for p in of_type("cobol", "copybook"):
        res["copy"][p] = count_kw(p, "COPY", False)
    for p in of_type("cobol"):
        res["call"][p] = count_kw(p, "CALL", True)
    for p in of_type("jcl", "proc"):
        res["jcl"][p] = jcl_counts(p)
    for p in of_type("csd"):
        res["csd"][p] = sum(1 for l in read_lines(p) if re.match(r"\s*DEFINE\s+TRANSACTION\(", l, re.I))
    with open(out, "w", encoding="utf-8") as f:
        json.dump(res, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
