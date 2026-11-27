#!/usr/bin/env python3
"""Conteggi INDIPENDENTI fatti sul sorgente (non usano ne' gli strumenti ne' l'estrattore di schede).

COPY e CALL (programmi e copybook): per riga, mascherando i letterali e togliendo `*>`; l'operando puo' stare sulla riga
successiva. CALL con letterale e CALL con operando in variabile si contano a parte.
EXEC e DD: per riga `//nome EXEC` / `//nome DD`; i dati in linea non sono schede: `DD *` termina a `/*`, a `//` o al
delimitatore DLM=; `DD DATA` termina solo a `/*` o al delimitatore DLM=. Per ogni passo il numero di DD che lo seguono.
Transazioni: `DEFINE TRANSACTION(` nei file csd, righe commento (primo carattere non bianco `*`) escluse.

Uso: counts.py OUT.json"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import of_type, read_lines, strip_cobol_inline_comment

LIT = re.compile(r"'[^']*'|\"[^\"]*\"")
WORD = r"(?<![A-Za-z0-9-])%s(?![A-Za-z0-9-])"


def code_lines(path):
    for line in read_lines(path):
        if len(line) > 6 and line[6] in "*/":
            continue
        yield strip_cobol_inline_comment(line[7:72])


def count_kw(path, kw):
    """(operando letterale, operando in variabile) dopo la parola chiave; per COPY il totale e' la somma."""
    lit = var = 0
    pending = False
    for s in code_lines(path):
        masked = LIT.sub(lambda m: "\0" * len(m.group()), s)
        if pending and masked.strip():
            first = s.lstrip()[:1]
            if first in "'\"":
                lit += 1
            elif re.match(r"[A-Za-z0-9]", first):
                var += 1
            pending = False
        for m in re.finditer(WORD % kw, masked.upper()):
            rest = s[m.end():].lstrip()
            if not rest:
                pending = True
            elif rest[0] in "'\"":
                lit += 1
            elif re.match(r"[A-Za-z0-9]", rest[0]):
                var += 1
    return lit, var


def jcl_counts(path):
    steps, jobdd = [], 0
    ins = None   # None | (modo, delimitatore)
    for l in read_lines(path):
        l = l[:72]
        if ins:
            mode, dlm = ins
            if dlm:
                if l.startswith(dlm):
                    ins = None
                continue
            if l.startswith("/*"):
                ins = None
                continue
            if mode == "*" and l.startswith("//"):
                ins = None        # una nuova scheda: si elabora qui sotto
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
            op = m.group(4)
            first = re.match(r"(\*|DATA)(?=[ ,]|$)", op.strip())
            if first:
                d = re.search(r"DLM=(?:'(..)'|(\S\S))", op)
                ins = (first.group(1), (d.group(1) or d.group(2)) if d else None)
    return {"exec": len(steps), "dd": sum(s[1] for s in steps) + jobdd, "dd_livello_job": jobdd, "passi": steps}


def csd_count(path):
    return sum(1 for l in read_lines(path) if not l.lstrip().startswith("*") and re.match(r"\s*DEFINE\s+TRANSACTION\(", l, re.I))


def main(out):
    res = {"copy": {}, "call": {}, "call_var": {}, "jcl": {}, "csd": {}}
    for p in of_type("cobol", "copybook"):
        res["copy"][p] = sum(count_kw(p, "COPY"))
        res["call"][p], res["call_var"][p] = count_kw(p, "CALL")
    for p in of_type("jcl", "proc"):
        res["jcl"][p] = jcl_counts(p)
    for p in of_type("csd"):
        res["csd"][p] = csd_count(p)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(res, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
