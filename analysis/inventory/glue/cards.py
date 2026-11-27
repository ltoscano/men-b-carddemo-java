#!/usr/bin/env python3
"""Estrattore di schede JCL (colla, non parser; livello B della copertura e fonte di riga/forma-sorgente per il livello A).

Riconosce le schede `//nome EXEC ...` e `//nome DD ...` e le loro continuazioni (operando che termina con virgola, righe
commento `//*` in mezzo), colonne 1-72. Ne ricava, cosi' come scritti: nome, PGM= o PROC=, PARM=, DSN=, DISP=, SYSOUT=,
`*`/DATA, DUMMY. Non interpreta simboli, non espande procedure, non valuta condizioni, non costruisce un albero.
I dati in linea (dopo `DD *` o `DD DATA`, fino a `/*` o a una scheda `//`) non sono schede.

Uso: cards.py OUTDIR       scrive OUTDIR/cards.tsv per i file `jcl` e `proc` del manifesto"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import of_type, read_lines, write_tsv


def first_field(s):
    """Campo operando: fino al primo spazio fuori dagli apici (il resto e' commento)."""
    q = None
    for i, c in enumerate(s):
        if q:
            if c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == " ":
            return s[:i]
    return s


def split_top(s):
    out, depth, q, cur = [], 0, None, ""
    for c in s:
        if q:
            cur += c
            if c == q:
                q = None
        elif c in "'\"":
            q = c
            cur += c
        elif c == "(":
            depth += 1
            cur += c
        elif c == ")":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += c
    out.append(cur)
    return out


def cards_of(path):
    lines = [l[:72] for l in read_lines(path)]
    n = len(lines)
    i = 0
    step = 0
    out = []
    instream = False
    while i < n:
        l = lines[i]
        if instream:
            if l.startswith("/*") or l.startswith("//"):
                instream = False
            else:
                i += 1
                continue
        if not l.startswith("//") or l.startswith("//*") or not l[2:].strip():
            i += 1
            continue
        m = re.match(r"//(\S*)\s+(\S+)\s*(.*)$", l)
        if not m:
            i += 1
            continue
        name, op, rest = m.group(1), m.group(2).upper(), m.group(3)
        start = i + 1
        operand = first_field(rest)
        j = i
        while operand.endswith(",") and j + 1 < n:
            j += 1
            while j < n and lines[j].startswith("//*"):
                j += 1
            if j >= n or not lines[j].startswith("//"):
                break
            operand += first_field(lines[j][2:].lstrip())
        i = j + 1
        if op == "EXEC":
            step += 1
            params = split_top(operand)
            kind, target, parm = "", "", ""
            for k, p in enumerate(params):
                u = p.upper()
                if u.startswith("PGM="):
                    kind, target = "PGM", p[4:]
                elif u.startswith("PROC="):
                    kind, target = "PROC", p[5:]
                elif u.startswith("PARM="):
                    parm = p[5:]
                elif k == 0 and "=" not in p:
                    kind, target = "PROC", p
            out.append((path, start, "EXEC", name, step, kind, target, parm, "", "", 0, 0, 0))
        elif op == "DD":
            params = split_top(operand)
            dsn = disp = ""
            sysout = instr = dummy = 0
            for k, p in enumerate(params):
                u = p.upper()
                if u.startswith("DSN=") or u.startswith("DSNAME="):
                    dsn = p.split("=", 1)[1]
                elif u.startswith("DISP="):
                    disp = p[5:]
                elif u.startswith("SYSOUT="):
                    sysout = 1
                elif k == 0 and (p == "*" or u == "DATA"):
                    instr = 1
                elif k == 0 and u == "DUMMY":
                    dummy = 1
            if instr:
                instream = True
            out.append((path, start, "DD", name, step, "", "", "", dsn, disp, sysout, instr, dummy))
    return out


if __name__ == "__main__":
    rows = []
    for p in of_type("jcl", "proc"):
        rows.extend(cards_of(p))
    write_tsv(os.path.join(sys.argv[1], "cards.tsv"),
              ["file", "riga", "scheda", "nome", "passo", "tipo_exec", "esegue", "parm", "dsn", "disp", "sysout", "in_linea", "dummy"], rows)
