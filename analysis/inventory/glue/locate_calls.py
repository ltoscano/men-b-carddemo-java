#!/usr/bin/env python3
"""Localizzatore di occorrenze delle CALL statiche (colla, non parser).

Dato l'elenco dei nomi gia' trovati da cobol-migration-toolkit (cmt_calls.tsv: programmi e copybook), trova nel sorgente
la riga di ogni istruzione CALL 'NOME' (commenti di riga e `*>` esclusi, area di codice colonne 8-72, continuazioni di
riga considerate: il letterale puo' stare a capo). Ogni occorrenza ha la propria riga. Elenca a parte le CALL il cui
operando non e' un letterale (bersaglio in variabile: occorrenze con bersaglio non risolto) e i letterali che lo
strumento non aveva riportato.

Uso: locate_calls.py INDIR OUTDIR     (INDIR contiene cmt_calls.tsv)"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import of_type, read_lines, read_tsv, strip_cobol_inline_comment, write_tsv

TOKEN = re.compile(r"'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"|[A-Za-z0-9][A-Za-z0-9-]*|\S")


def code_text(lines):
    """Testo dell'area di codice delle righe non commento, con la riga di ogni carattere."""
    text, where = [], []
    for n, line in enumerate(lines, 1):
        ind = line[6] if len(line) > 6 else " "
        if ind in "*/":
            continue
        code = strip_cobol_inline_comment(line[7:72])
        if ind == "-":
            code = code.lstrip()
            # prosecuzione di un letterale: il primo apice e' il segno di prosecuzione, non fa parte del testo
            if text and code[:1] in "'\"" and sum(1 for c in "".join(text) if c == code[0]) % 2 == 1:
                code = code[1:]
        elif text:
            text.append(" ")
            where.append(n)
        text.append(code)
        where.extend([n] * len(code))
    return "".join(text), where


def main(indir, outdir):
    calls = {}
    for r in read_tsv(os.path.join(indir, "cmt_calls.tsv")):
        calls.setdefault(r["file"], set()).add(r["chiamato"].upper())
    occ, dyn, extra, missing = [], [], [], []
    for path in of_type("cobol", "copybook"):
        text, where = code_text(read_lines(path))
        toks = [(m.group(), m.start()) for m in TOKEN.finditer(text)]
        found = set()
        for i, (t, pos) in enumerate(toks[:-1]):
            if t.upper() != "CALL":
                continue
            nxt = toks[i + 1][0]
            line = where[pos]
            if nxt[0] in "'\"":
                name = nxt[1:-1].upper()
                if name in calls.get(path, ()):
                    occ.append((path, line, name))
                    found.add(name)
                else:
                    extra.append((path, line, name))
            elif re.match(r"[A-Za-z0-9]", nxt):
                dyn.append((path, line, nxt.upper()))
        for name in sorted(calls.get(path, set()) - found):
            missing.append((path, name))
    if missing:
        for m in missing:
            print(f"LOCALIZZATORE: {m[0]}: nome {m[1]} riportato dallo strumento ma nessuna istruzione CALL trovata", file=sys.stderr)
        return 1
    occ.sort()
    write_tsv(os.path.join(outdir, "call_occ.tsv"), ["file", "riga", "chiamato"], occ)
    write_tsv(os.path.join(outdir, "call_dinamiche.tsv"), ["file", "riga", "operando"], sorted(dyn))
    write_tsv(os.path.join(outdir, "call_non_riportate.tsv"), ["file", "riga", "chiamato"], sorted(extra))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
