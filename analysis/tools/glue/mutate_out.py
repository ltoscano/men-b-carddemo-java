#!/usr/bin/env python3
"""Per i test negativi: copia la cartella degli output degli strumenti e altera UN valore dell'output.

Uso: mutate_out.py KIND SRC_OUT DST_OUT
  KIND: scc-aggregate-zero | scc-file-comments | compile-count | jcl-type | cb2xml-rename | cmt-call-rename
Le ultime due alterano l'output GREZZO (XML / JSON) lasciando invariati i TSV normalizzati.
"""
import os
import shutil
import sys

M = {
    # (file, vecchio, nuovo)
    "scc-aggregate-zero": ("scc/dirs.csv", "app/cbl,COBOL,20650,15855,2575,2220,", "app/cbl,COBOL,20650,0,0,0,"),
    "scc-file-comments": ("scc/app-by-file.csv", "COBOL,/legacy/app/cpy/CVACT03Y.cpy,CVACT03Y.cpy,11,5,6,0,", "COBOL,/legacy/app/cpy/CVACT03Y.cpy,CVACT03Y.cpy,11,11,0,0,"),
    "compile-count": ("gnucobol/syntax.tsv", "CBSTM03A\t1\t39\t0", "CBSTM03A\t1\t9999\t0"),
    "jcl-type": ("mapa/jcl_steps.tsv", "POSTTRAN\tSTEP15\tPGM\tCBTRN02C", "POSTTRAN\tSTEP15\tPROC\tCBTRN02C"),
    "cb2xml-rename": ("cb2xml/CVACT01Y.xml", 'name="ACCT-CURR-BAL"', 'name="ACCT-CURR-BALX"'),
    "cmt-call-rename": ("cmt/inventory.json", '"MVSWAIT"', '"INVENTATO"'),
}


def main(kind, src, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    name, old, new = M[kind]
    path = os.path.join(dst, name)
    text = open(path, encoding="utf-8").read()
    assert old in text, f"testo da alterare non trovato in {name}: {old!r}"
    open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
