#!/usr/bin/env python3
"""Verifica il manifesto contro la fonte di verita' (git ls-files) e contro gli attesi scritti a mano.

Uso: verify.py MANIFEST EXPECTED < output di `git ls-files -z`
Esce con 0 se tutto coincide, 1 altrimenti (stampando ogni discrepanza).
"""
import sys

TYPES = {"cobol", "copybook", "bms", "jcl", "proc", "asm", "macro", "csd", "ctl", "ddl",
         "dcl", "ims", "data", "scheduler", "script", "doc", "sample", "other"}


def main(manifest_path: str, expected_path: str) -> int:
    errors = []
    ls = [x.decode("utf-8") for x in sys.stdin.buffer.read().split(b"\0") if x]
    ls_set = set(ls)
    if len(ls) != len(ls_set):
        errors.append("git ls-files restituisce percorsi duplicati (inatteso)")

    with open(manifest_path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if not lines or lines[0] != "path\ttype":
        errors.append("intestazione mancante o errata (atteso 'path<TAB>type')")
    rows = []
    for n, line in enumerate(lines[1:], start=2):
        cols = line.split("\t")
        if len(cols) != 2:
            errors.append(f"riga {n}: attese 2 colonne, trovate {len(cols)}")
            continue
        rows.append((cols[0], cols[1]))

    paths = [p for p, _ in rows]
    seen = set()
    for p in paths:
        if p in seen:
            errors.append(f"percorso duplicato nel manifesto: {p}")
        seen.add(p)
    for p in sorted(ls_set - seen):
        errors.append(f"file tracciato assente dal manifesto: {p}")
    for p in sorted(seen - ls_set):
        errors.append(f"file nel manifesto ma non tracciato: {p}")
    for p, t in rows:
        if t not in TYPES:
            errors.append(f"tipo non ammesso '{t}' per {p}")

    exp = {}
    with open(expected_path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            k, v = line.rstrip("\n").split("\t")[:2]
            exp[k] = v

    cobol = [p for p, t in rows if t == "cobol"]
    got = {
        "file_totali": len(ls),
        "cobol_totali": len(cobol),
        "cobol_sotto_app_cbl": sum(1 for p in cobol if p.startswith("app/cbl/")),
        "cobol_estensione_maiuscola": sum(1 for p in cobol if p.endswith(".CBL")),
    }
    for k, v in got.items():
        if k in exp and str(v) != exp[k]:
            errors.append(f"{k}: atteso {exp[k]}, trovato {v}")
        elif k not in exp and k != "file_totali":
            errors.append(f"{k}: nessun valore atteso in {expected_path}")
    for k, t in (x for x in exp.items() if x[0].startswith("tipo:")):
        path = k[5:]
        d = dict(rows)
        if d.get(path) != t:
            errors.append(f"tipo di {path}: atteso {t}, trovato {d.get(path)}")

    for e in errors:
        print("MANIFESTO: " + e, file=sys.stderr)
    if not errors:
        print(f"manifesto ok: {len(rows)} file, {got['cobol_totali']} cobol "
              f"({got['cobol_sotto_app_cbl']} sotto app/cbl/)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
