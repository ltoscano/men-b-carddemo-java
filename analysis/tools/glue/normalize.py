#!/usr/bin/env python3
"""Colla: porta l'output grezzo di ciascuno strumento in TSV semplici, senza interpretare COBOL o JCL.
Si limita a rileggere i formati degli strumenti (JSON, XML, CSV) e a riordinarli in colonne fisse.

Uso: normalize.py {cmt|cobmix|cb2xml|mapa} DIR     (DIR contiene l'output dello strumento e riceve i TSV)
"""
import csv
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET


def write_tsv(path, header, rows):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\t".join(header) + "\n")
        for r in rows:
            f.write("\t".join(str(x) for x in r) + "\n")


def cmt(d):
    inv = json.load(open(os.path.join(d, "inventory.json"), encoding="utf-8"))
    copy_rows, call_rows, prog_rows = [], [], []
    for u in sorted(inv["units"], key=lambda u: u["path"]):
        prog = os.path.splitext(os.path.basename(u["path"]))[0]
        prog_rows.append((prog,))
        repl = set(u.get("copy_replacing", []))
        for c in u.get("copybooks", []):
            # lo strumento non riporta ne' la riga ne' le sostituzioni: '-' = dato non fornito
            copy_rows.append((prog, "-", c, "REPLACING" if c in repl else "-"))
        for c in u.get("calls", []):
            call_rows.append((prog, c))
    write_tsv(os.path.join(d, "copy.tsv"), ["programma", "riga", "copybook", "sostituzioni"], copy_rows)
    write_tsv(os.path.join(d, "calls.tsv"), ["chiamante", "chiamato"], call_rows)
    write_tsv(os.path.join(d, "programs.tsv"), ["programma"], prog_rows)


def cobmix(d):
    rows = []
    for p in sorted(glob.glob(os.path.join(d, "*.json"))):
        prog = os.path.splitext(os.path.basename(p))[0]
        g = json.load(open(p, encoding="utf-8"))
        for e in g["edges"]:
            if e.get("type") == "includes":
                # nessuna riga, nessuna sostituzione nel grafo: '-' = dato non fornito (resta l'ordine di apparizione)
                rows.append((prog, "-", e["target"].split(":", 1)[1], "-"))
    write_tsv(os.path.join(d, "copy.tsv"), ["programma", "riga", "copybook", "sostituzioni"], rows)


def tipo(item):
    usage = item.get("usage")
    pic = item.get("picture")
    if usage == "computational":
        return "COMP"
    if usage == "computational-3":
        return "COMP-3"
    if usage:
        return usage
    if pic is None:
        return "group"
    if pic.upper().startswith("X") or pic.upper().startswith("A"):
        return "X"
    return "S9" if pic.upper().startswith("S") else "9"


def cb2xml(d):
    rows, totals = [], []
    for p in sorted(glob.glob(os.path.join(d, "*.xml"))):
        name = os.path.splitext(os.path.basename(p))[0]
        root = ET.parse(p).getroot()

        def walk(item):
            rows.append((name, item.get("name"), int(item.get("position")) - 1, int(item.get("storage-length")),
                         tipo(item), int(item.get("scale", "0")), item.get("redefines", "-")))
            for ch in item.findall("item"):
                walk(ch)

        for top in root.findall("item"):
            totals.append((name, top.get("name"), int(top.get("storage-length"))))
            walk(top)
    write_tsv(os.path.join(d, "layout.tsv"), ["copybook", "campo", "offset", "lunghezza", "tipo", "scala", "redefines"], rows)
    write_tsv(os.path.join(d, "lengths.tsv"), ["copybook", "record", "lunghezza"], totals)


def mapa(d):
    steps, dds = [], []
    for p in sorted(glob.glob(os.path.join(d, "*.csv"))):
        job_of_file = {}
        step_info = {}
        with open(p, encoding="utf-8", newline="") as f:
            recs = [r for r in csv.reader(f) if r]
        for r in recs:
            if r[0] == "JOB":
                job_of_file[r[4]] = r[1]
            elif r[0] == "JOBSTEP":
                # JOBSTEP,nome,seq,jobUUID,stepUUID,PGM|PROC,nome
                step_info[r[4]] = (job_of_file[r[3]], r[1])
                steps.append((job_of_file[r[3]], r[1], r[5], r[6]))
            elif r[0] == "JOBSTEPDD":
                # JOBSTEPDD,dd,stepUUID,ddUUID,seq,tipo,"dsn",disp1,disp2,disp3
                j, s = step_info[r[2]]
                dsn = r[6]
                dds.append((j, s, r[1], dsn, "/".join(x for x in r[7:10] if x)))
    write_tsv(os.path.join(d, "jcl_steps.tsv"), ["job", "passo", "tipo", "programma"], steps)
    write_tsv(os.path.join(d, "jcl_dd.tsv"), ["job", "passo", "dd", "dataset", "disp"], dds)


if __name__ == "__main__":
    {"cmt": cmt, "cobmix": cobmix, "cb2xml": cb2xml, "mapa": mapa}[sys.argv[1]](sys.argv[2])
