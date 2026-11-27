#!/usr/bin/env python3
"""Per i test negativi: copia la cartella degli attesi e altera UN valore.

Uso: mutate.py KIND SRC_DIR DST_DIR
  KIND: scc | compile | copy-line | copy-replacing | call | layout-offset | layout-length | jcl-program | jcl-dd
"""
import os
import shutil
import sys

# (file, riga da cercare, riga sostitutiva)
M = {
    "scc": ("scc.tsv", "cartella:app/cbl:file\t31", "cartella:app/cbl:file\t30"),
    "compile": ("compile.tsv", "COSGN00C\terrore\t", "COSGN00C\tok\t"),
    "copy-line": ("copy.tsv", "COBIL00C\t63\tCOCOM01Y\t", "COBIL00C\t64\tCOCOM01Y\t"),
    "copy-replacing": ("copy.tsv", "COACTUPC\t3208\tCSSETATY\t(TESTVAR1)=ACCT-STATUS;", "COACTUPC\t3208\tCSSETATY\t(TESTVAR1)=ACCT-STATUZ;"),
    "copy-count": ("copy_counts.tsv", "CBACT04C\t5", "CBACT04C\t6"),
    "call": ("calls.tsv", "COBSWAIT\t38\tMVSWAIT\t", "COBSWAIT\t38\tMVSWAIX\t"),
    "layout-offset": ("layout.tsv", "CVACT01Y\tACCT-CURR-BAL\t12\t", "CVACT01Y\tACCT-CURR-BAL\t24\t"),
    "layout-length": ("lengths.tsv", "CVTRA05Y\t350\t", "CVTRA05Y\t351\t"),
    "jcl-program": ("jcl_steps.tsv", "POSTTRAN\tSTEP15\tPGM\tCBTRN02C\t", "POSTTRAN\tSTEP15\tPGM\tCBTRN03C\t"),
    "jcl-type": ("jcl_steps.tsv", "POSTTRAN\tSTEP15\tPGM\t", "POSTTRAN\tSTEP15\tPROC\t"),
    "scc-sample": ("scc_files.tsv", "app/cpy/CVACT03Y.cpy\t11\t5\t6\t0", "app/cpy/CVACT03Y.cpy\t11\t11\t0\t0"),
    "jcl-dd": ("jcl_dd.tsv", "POSTTRAN\tSTEP15\tDALYREJS\tAWS.M2.CARDDEMO.DALYREJS(+1)", "POSTTRAN\tSTEP15\tDALYREJS\tAWS.M2.CARDDEMO.DALYREJS"),
}


def main(kind, src, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    name, old, new = M[kind]
    path = os.path.join(dst, name)
    text = open(path, encoding="utf-8").read()
    assert text.count(old) >= 1, f"riga da alterare non trovata in {name}: {old!r}"
    text = text.replace(old, new, 1)
    open(path, "w", encoding="utf-8").write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
