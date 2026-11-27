#!/usr/bin/env python3
"""Porta l'output grezzo di cobol-migration-toolkit e di mapa in TSV a colonne fisse. Non interpreta COBOL o JCL.

Uso: normalize.py cmt RAWDIR OUTDIR     (RAWDIR/<cartella>/inventory.json, una per cartella scandita)
     normalize.py mapa RAWDIR OUTDIR    (RAWDIR/*.csv, uno per file JCL)
     normalize.py proleap LISTA RAWDIR OUTDIR   (LISTA: file cobol e copybook del manifesto; RAWDIR/<percorso con _>.tsv, uno per file)
"""
import csv
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import of_type, stem, write_tsv


def cmt(raw, out):
    by_stem = {stem(p): p for p in of_type("cobol", "copybook")}
    assert len(by_stem) == len(of_type("cobol", "copybook")), "nomi duplicati tra programmi e copybook"
    rows = []
    # una risposta per ogni cartella di programmi e copybook del manifesto, ne' di piu' ne' di meno
    want_dirs = {os.path.dirname(p).replace("/", "_") for p in of_type("cobol", "copybook")}
    have_dirs = {os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(raw, "*", "inventory.json"))}
    if want_dirs != have_dirs:
        print(f"cmt: risposte mancanti {sorted(want_dirs - have_dirs)} o inattese {sorted(have_dirs - want_dirs)}", file=sys.stderr)
        return 1
    for p in sorted(glob.glob(os.path.join(raw, "*", "inventory.json"))):
        inv = json.load(open(p, encoding="utf-8"))
        if not isinstance(inv, dict) or not isinstance(inv.get("units"), list) or not all(
                isinstance(u, dict) and isinstance(u.get("path"), str) and isinstance(u.get("calls", []), list)
                and all(isinstance(c, str) and c for c in u.get("calls", [])) for u in inv["units"]):
            print(f"cmt: {p}: risposta non riconoscibile (attesi 'units' con 'path' e 'calls')", file=sys.stderr)
            return 1
        for u in inv["units"]:
            prog = stem(u["path"])
            if prog not in by_stem:
                print(f"cmt: unita' {u['path']} senza file nel manifesto", file=sys.stderr)
                return 1
            for c in u.get("calls", []):
                rows.append((by_stem[prog], c))
    rows.sort()
    write_tsv(os.path.join(out, "cmt_calls.tsv"), ["file", "chiamato"], rows)
    return 0


# record di mapa riconosciuti: tipo -> numero di campi (campi del CSV, tipo compreso)
MAPA_RECORDS = {"FILE": 4, "JOB": 5, "JOBSTEP": 7, "JOBSTEPDD": 10, "PROC": 4, "PROCSTEP": 7, "PROCSTEPDD": 10, "JOBSTEPDSNRUN": 5}


def mapa_check(path, recs, log):
    """Valida struttura e tipi di record dell'output di mapa per UN file. Un output non riconoscibile e' un errore;
    un output ben formato ma povero (un job senza passi, o nessun record con il log 'contains neither jobs nor procs')
    e' il caso previsto che porta il file al livello B."""
    problems = []
    if "Processing complete" not in log:
        problems.append("il log di mapa non termina con 'Processing complete'")
    if not recs:
        if "contains neither jobs nor procs" not in log:
            problems.append("output vuoto senza il messaggio 'contains neither jobs nor procs' nel log")
        return problems
    if recs[0][0] != "FILE":
        problems.append("il primo record non e' FILE")
    if recs[0][0] == "FILE" and len(recs[0]) > 1 and recs[0][1] != "/legacy/" + path:
        problems.append(f"il record FILE indica {recs[0][1]!r}, atteso '/legacy/{path}'")
    jobs, steps = set(), set()
    for r in recs:
        n = MAPA_RECORDS.get(r[0])
        if n is None:
            problems.append(f"tipo di record sconosciuto {r[0][:30]!r}")
            continue
        if len(r) != n:
            problems.append(f"record {r[0]} con {len(r)} campi invece di {n}")
            continue
        if r[0] == "JOB":
            jobs.add(r[4])
        elif r[0] == "JOBSTEP":
            if r[3] not in jobs:
                problems.append(f"JOBSTEP {r[1]} riferito a un JOB sconosciuto")
            if not r[2].isdigit() or r[5] not in ("PGM", "PROC") or not r[6]:
                problems.append(f"JOBSTEP {r[1]} con campi non validi (seq {r[2]!r}, tipo {r[5]!r}, nome {r[6]!r})")
            steps.add(r[4])
        elif r[0] == "JOBSTEPDD":
            if r[2] not in steps:
                problems.append(f"JOBSTEPDD {r[1]} riferito a un passo sconosciuto")
            if not r[4].isdigit() or len(r[5]) != 1:
                problems.append(f"JOBSTEPDD {r[1]} con campi non validi")
    return problems


def mapa(raw, out):
    steps, dds = [], []
    bad = 0
    for jp in of_type("jcl"):
        name = jp.replace("/", "_")
        cpath = os.path.join(raw, name + ".csv")
        lpath = os.path.join(raw, name + ".stdout")
        if not os.path.isfile(cpath) or not os.path.isfile(lpath):
            print(f"mapa: {jp}: output o log mancante", file=sys.stderr)
            bad += 1
            continue
        try:
            with open(cpath, encoding="utf-8", newline="") as f:
                recs = [r for r in csv.reader(f) if r]
        except (UnicodeDecodeError, csv.Error) as e:
            print(f"mapa: {jp}: CSV illeggibile ({e})", file=sys.stderr)
            bad += 1
            continue
        log = open(lpath, encoding="utf-8", errors="replace").read()
        probs = mapa_check(jp, recs, log)
        if probs:
            for pr in probs:
                print(f"mapa: {jp}: output non riconoscibile: {pr}", file=sys.stderr)
            bad += 1
            continue
        path = jp
        info = {}
        for r in recs:
            if r[0] == "JOBSTEP":
                # JOBSTEP,nome,seq,jobUUID,stepUUID,PGM|PROC,nome
                info[r[4]] = (r[1], int(r[2]))
                steps.append((path, r[1], int(r[2]), r[5], r[6]))
            elif r[0] == "JOBSTEPDD":
                # JOBSTEPDD,dd,stepUUID,ddUUID,seq,classe,"dsn",disp1,disp2,disp3
                name_, ordn = info[r[2]]
                dds.append((path, name_, ordn, r[1], r[6], "/".join(x for x in r[7:10] if x), r[5]))
    if bad:
        return 1
    steps.sort(key=lambda x: (x[0], x[2]))
    # l'ordine delle DD dentro un passo e' quello dell'output (non si riordina)
    order = {}
    for i, d in enumerate(dds):
        order[id(d)] = i
    dds.sort(key=lambda x: (x[0], x[2], order[id(x)]))
    write_tsv(os.path.join(out, "mapa_steps.tsv"), ["file", "passo", "ordinale", "tipo", "nome"], steps)
    write_tsv(os.path.join(out, "mapa_dd.tsv"), ["file", "passo", "ordinale", "dd", "dsn_risolto", "disp_effettivo", "classe"], dds)
    return 0


PROLEAP_HEADER = "riga\tcopybook\tsostituzioni"


def proleap_check(path, text):
    """Valida UNA risposta di ProLeap (CopyLister): intestazione esatta, poi solo righe 'riga<TAB>copybook<TAB>sostituzioni'.
    Ammessa anche con zero COPY (solo l'intestazione), mai vuota o non riconoscibile. Ritorna (righe, problemi)."""
    problems, rows = [], []
    if not text:
        return rows, ["risposta vuota"]
    if not text.endswith("\n"):
        problems.append("risposta non terminata da fine riga (troncata?)")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if not lines or lines[0] != PROLEAP_HEADER:
        problems.append(f"intestazione {lines[0][:40]!r} diversa da {PROLEAP_HEADER!r}" if lines else "nessuna riga")
        return rows, problems
    for i, ln in enumerate(lines[1:], start=2):
        f = ln.split("\t")
        if len(f) != 3 or not f[0].isdigit() or int(f[0]) < 1 or not re.fullmatch(r"[A-Za-z0-9#@$-]+", f[1]):
            problems.append(f"riga {i} della risposta non riconoscibile: {ln[:40]!r}")
            continue
        rows.append((path, f[0], f[1], f[2]))
    return rows, problems


def proleap(lista, raw, out):
    expected = of_type("cobol", "copybook")
    listed = [l.rstrip("\n") for l in open(lista, encoding="utf-8") if l.strip()]
    if sorted(listed) != sorted(expected):
        print("proleap: l'elenco dei file analizzati non coincide con programmi e copybook del manifesto", file=sys.stderr)
        return 1
    rows, bad = [], 0
    for p in listed:
        tp = os.path.join(raw, p.replace("/", "_") + ".tsv")
        if not os.path.isfile(tp):
            print(f"proleap: {p}: risposta mancante", file=sys.stderr)
            bad += 1
            continue
        try:
            text = open(tp, encoding="utf-8", newline="").read()
        except UnicodeDecodeError:
            print(f"proleap: {p}: risposta illeggibile", file=sys.stderr)
            bad += 1
            continue
        r, probs = proleap_check(p, text)
        for pr in probs:
            print(f"proleap: {p}: risposta non riconoscibile: {pr}", file=sys.stderr)
        bad += bool(probs)
        rows.extend(r)
    if bad:
        return 1
    write_tsv(os.path.join(out, "copy.tsv"), ["file", "riga", "copybook", "sostituzioni"], rows)
    return 0


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "proleap":
        sys.exit(proleap(*sys.argv[2:5]))
    sys.exit({"cmt": cmt, "mapa": mapa}[mode](*sys.argv[2:4]))
