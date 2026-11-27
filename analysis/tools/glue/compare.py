#!/usr/bin/env python3
"""Controlli a campione: confronta l'output normalizzato di uno strumento con gli attesi scritti a mano.

Uso: compare.py CHECK [TOOL] [--expected DIR] [--out DIR]
  CHECK: scc | scc-split | compile | copy | call | layout | jcl
  TOOL : per copy/call, lo strumento (cmt | cobmix | proleap)
Percorsi (nel container): /analysis/tools/out, /analysis/tools/expected, /analysis/manifest/sources.tsv, /legacy.
L'ultima riga stampata e' 'VERDETTO: pass' o 'VERDETTO: fail'; il codice di uscita e' 0 solo per pass.
"""
import csv
import os
import re
import sys

OUT = "/analysis/tools/out"
MANIFEST = "/analysis/manifest/sources.tsv"
LEGACY = "/legacy"

problems = []
notes = []


def bad(msg):
    problems.append(msg)


def note(msg):
    notes.append(msg)


def read_tsv(path, skip_comments=True):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or (skip_comments and line.startswith("#")):
                continue
            rows.append(line.split("\t"))
    return rows


def manifest_rows():
    return [r for r in read_tsv(MANIFEST)[1:]]


def app_cbl_programs():
    return sorted(os.path.splitext(os.path.basename(p))[0] for p, t in manifest_rows()
                  if t == "cobol" and p.startswith("app/cbl/"))


# ---------------------------------------------------------------- scc
def check_scc(exp_dir):
    exp = {r[0]: r[1] for r in read_tsv(f"{exp_dir}/scc.tsv")}
    files = {}
    with open(f"{OUT}/scc/app-by-file.csv", encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            path = r["Provider"].replace("/legacy/", "", 1)
            if path in files:
                bad(f"file contato due volte da scc: {path}")
            vals = {k: int(r[k]) for k in ("Lines", "Code", "Comments", "Blanks", "Bytes")}
            if vals["Code"] + vals["Comments"] + vals["Blanks"] != vals["Lines"]:
                bad(f"{path}: righe {vals['Lines']} != codice + commenti + vuote ({vals['Code']}+{vals['Comments']}+{vals['Blanks']})")
            files[path] = (r["Language"], vals)
    mf = [p for p, _ in manifest_rows() if p.startswith("app/")]
    extra = sorted(set(files) - set(mf))
    if extra:
        bad(f"scc conta file che non sono nel manifesto: {extra[:5]}")
    missing = sorted(set(mf) - set(files))
    allowed_ext = set(exp["non_contate:estensioni"].split(","))
    explained = {exp["non_contato:file"]}
    for p in missing:
        ext = p.rsplit(".", 1)[-1].lower() if "." in os.path.basename(p) else ""
        if ext not in allowed_ext and p not in explained:
            bad(f"file del manifesto non contato da scc e senza spiegazione: {p}")
    if len(files) + len(missing) != len(mf):
        bad("contati + non contati != file del manifesto sotto app/")
    note(f"scc: {len(files)} file contati, {len(missing)} non contati, {len(mf)} nel manifesto sotto app/")
    # cartelle di baseline: tutte le colonne dell'aggregato contro la somma dei file
    dirs = {}
    for line in open(f"{OUT}/scc/dirs.csv", encoding="utf-8"):
        d, _, rest = line.rstrip("\n").partition(",")
        cols = rest.split(",")
        if cols[0] == "Language":
            continue
        acc = dirs.setdefault(d, dict.fromkeys(("Lines", "Code", "Comments", "Blanks", "Bytes", "Files"), 0))
        for k, idx in (("Lines", 1), ("Code", 2), ("Comments", 3), ("Blanks", 4), ("Bytes", 6), ("Files", 7)):
            acc[k] += int(cols[idx])
    for d in ("app/cbl", "app/cpy", "app/jcl"):
        agg = dirs.get(d)
        if agg is None:
            bad(f"{d}: aggregato assente in dirs.csv")
            continue
        for what, key in (("file", "Files"), ("righe", "Lines")):
            want = int(exp[f"cartella:{d}:{what}"])
            if agg[key] != want:
                bad(f"{d} {what}: atteso {want}, scc {agg[key]}")
        if agg["Code"] + agg["Comments"] + agg["Blanks"] != agg["Lines"]:
            bad(f"{d}: righe {agg['Lines']} != codice + commenti + vuote ({agg['Code']}+{agg['Comments']}+{agg['Blanks']})")
        sums = dict.fromkeys(agg, 0)
        for p, (_, v) in files.items():
            if p.startswith(d + "/") and p.count("/") == d.count("/") + 1:
                for k in ("Lines", "Code", "Comments", "Blanks", "Bytes"):
                    sums[k] += v[k]
                sums["Files"] += 1
        for k in agg:
            if sums[k] != agg[k]:
                bad(f"{d}: {k} dell'aggregato {agg[k]} != somma dei file {sums[k]}")
    # coerenza con il manifesto per le cartelle (file)
    for d, t in (("app/cbl/", "cobol"), ("app/cpy/", "copybook"), ("app/jcl/", "jcl")):
        n = sum(1 for p, tt in manifest_rows() if p.startswith(d) and p.count("/") == 2 and tt == t)
        got = dirs.get(d[:-1], {}).get("Files")
        if n != got:
            bad(f"{d}: manifesto {n} file di tipo {t}, scc {got}")
    # campioni contati a mano: righe totali e righe vuote (capacita' conteggi-file-righe-vuote)
    nsamp = 0
    for path, hand in scc_samples(exp_dir).items():
        if hand["Code"] + hand["Comments"] + hand["Blanks"] != hand["Lines"]:
            bad(f"{path}: il campione a mano non e' coerente (codice + commenti + vuote != righe)")
        if path not in files:
            bad(f"{path}: campione non presente nell'output di scc")
            continue
        got = files[path][1]
        for k in ("Lines", "Blanks"):
            if got[k] != hand[k]:
                bad(f"{path}: {k} atteso {hand[k]}, scc {got[k]}")
        nsamp += 1
    note(f"scc: {nsamp} campioni contati a mano (righe totali e righe vuote) confrontati")


def scc_samples(exp_dir):
    out = {}
    for r in read_tsv(f"{exp_dir}/scc_files.tsv"):
        out[r[0]] = dict(zip(("Lines", "Code", "Comments", "Blanks"), (int(x) for x in r[1:5])))
    return out


def check_scc_split(exp_dir):
    """Capacita' ripartizione-codice-commenti: i campioni a mano contro scc. Per questa capacita' l'esito
    atteso e' 'fail' (capacita' unavailable): il fallimento, con campioni e differenze, e' la prova richiesta."""
    files = {}
    with open(f"{OUT}/scc/app-by-file.csv", encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            files[r["Provider"].replace("/legacy/", "", 1)] = {k: int(r[k]) for k in ("Lines", "Code", "Comments", "Blanks")}
    ok = 0
    for path, hand in scc_samples(exp_dir).items():
        got = files.get(path)
        if got is None:
            bad(f"{path}: campione non presente nell'output di scc")
            continue
        diffs = [k for k in ("Code", "Comments") if got[k] != hand[k]]
        note(f"{path}: a mano codice {hand['Code']} commenti {hand['Comments']}; scc codice {got['Code']} commenti {got['Comments']}"
             f"{'  <- DIFFERENZA' if diffs else ''}")
        for k in diffs:
            bad(f"{path}: {k} atteso {hand[k]}, scc {got[k]}")
        ok += not diffs
    note(f"{ok} campioni su {len(scc_samples(exp_dir))} coincidono con scc")


# ---------------------------------------------------------------- compile
def check_compile(exp_dir):
    exp = {r[0]: r[1] for r in read_tsv(f"{exp_dir}/compile.tsv")}
    got = {r[0]: (int(r[1]), int(r[2]), int(r[3])) for r in read_tsv(f"{OUT}/gnucobol/syntax.tsv")[1:]}
    progs = app_cbl_programs()
    if sorted(got) != progs:
        bad(f"programmi compilati diversi dal manifesto: {sorted(set(got) ^ set(progs))}")
    if sorted(exp) != progs:
        bad(f"programmi attesi diversi dal manifesto: {sorted(set(exp) ^ set(progs))}")
    for p in progs:
        if p not in got or p not in exp:
            continue
        rc, errs, warns = got[p]
        # i conteggi del TSV si riconfrontano con le diagnostiche salvate
        try:
            log = open(f"{OUT}/gnucobol/log/{p}.log", encoding="utf-8", errors="replace").read()
        except OSError:
            bad(f"{p}: log delle diagnostiche assente")
            continue
        log_errs = log.count(": error: ")
        log_warns = log.count(": warning: ")
        if errs != log_errs:
            bad(f"{p}: errori nel TSV {errs}, nelle diagnostiche salvate {log_errs}")
        if warns != log_warns:
            bad(f"{p}: avvertimenti nel TSV {warns}, nelle diagnostiche salvate {log_warns}")
        failed = log_errs > 0
        if failed != (exp[p] == "errore"):
            bad(f"{p}: atteso {exp[p]}, cobc ha rilevato {log_errs} errori")
        if (rc != 0) != failed:
            bad(f"{p}: codice di uscita {rc} incoerente con {log_errs} errori")
    n_ok = sum(1 for p in got if got[p][1] == 0)
    note(f"cobc: {n_ok} programmi senza errori, {len(got) - n_ok} con errori (tutti attesi); conteggi riletti dai log")


# ---------------------------------------------------------------- copy
def check_copy(tool, exp_dir):
    exp = [tuple(r) for r in read_tsv(f"{exp_dir}/copy.tsv")[0:]]
    exp = [r for r in exp if r[0] != "programma"]
    got = [tuple(r) for r in read_tsv(f"{OUT}/{tool}/copy.tsv")[1:]]
    progs = app_cbl_programs()
    tool_progs = sorted({r[0] for r in got})
    note(f"{tool}: occorrenze COPY riportate per {len(tool_progs)} programmi, {len(got)} righe in tutto")
    for prog in sorted({r[0] for r in exp}):
        e = sorted(((int(r[1]), r[2], r[3]) for r in exp if r[0] == prog))
        g_rows = [r for r in got if r[0] == prog]
        if any(r[1] == "-" for r in g_rows):
            bad(f"{prog}: lo strumento non riporta il numero di riga delle occorrenze COPY ({len(g_rows)} righe, {len(e)} attese)")
        if g_rows and all(r[3] == "-" for r in g_rows) and any(x[2] for x in e):
            bad(f"{prog}: lo strumento non riporta le sostituzioni REPLACING (attese in {sum(1 for x in e if x[2])} occorrenze)")
        if len(g_rows) != len(e):
            bad(f"{prog}: occorrenze COPY riportate {len(g_rows)}, attese {len(e)}")
        if any(r[1] != "-" for r in g_rows):
            g = sorted(((int(r[1]), r[2], r[3] if r[3] != "-" else "") for r in g_rows))
            if g != e:
                diff = [x for x in e if x not in g][:3]
                bad(f"{prog}: occorrenze diverse dall'atteso, es. mancanti/diverse: {diff}")
        # occorrenze distinte di CSSETATY in COACTUPC
    # numero di COPY per ciascuno dei 31 programmi, contato nel sorgente con una ricerca testuale indipendente
    for r in read_tsv(f"{exp_dir}/copy_counts.tsv"):
        n = sum(1 for g in got if g[0] == r[0])
        if n != int(r[1]):
            bad(f"{r[0]}: occorrenze COPY riportate {n}, contate nel sorgente {r[1]}")
    if not set(tool_progs) <= set(progs):
        bad(f"{tool}: programmi riportati che non sono nel manifesto: {sorted(set(tool_progs) - set(progs))}")


# ---------------------------------------------------------------- call
def check_call(tool, exp_dir):
    exp = [(r[0], r[2]) for r in read_tsv(f"{exp_dir}/calls.tsv") if r[0] != "programma"]
    got = {tuple(r) for r in read_tsv(f"{OUT}/{tool}/calls.tsv")[1:]}
    inv_progs = {r[0] for r in read_tsv(f"{OUT}/{tool}/programs.tsv")[1:]}
    if sorted(inv_progs) != app_cbl_programs():
        bad(f"{tool}: programmi analizzati diversi dal manifesto")
    for e in exp:
        if e not in got:
            bad(f"CALL attesa non trovata: {e[0]} -> {e[1]}")
    # per i programmi con attesi, l'insieme delle CALL dello strumento deve coincidere (niente CALL inventate)
    for prog in sorted({e[0] for e in exp}):
        extra_calls = sorted(c for (p, c) in got if p == prog and (p, c) not in exp)
        if extra_calls:
            bad(f"{prog}: CALL riportate dallo strumento e assenti dagli attesi: {extra_calls}")
    xctl = [r for r in read_tsv(f"{exp_dir}/xctl.tsv") if r[0] != "programma"]
    seen = [(r[0], r[2]) for r in xctl if (r[0], r[2]) in got]
    note(f"{tool}: CALL attese trovate {len(exp) - sum(1 for e in exp if e not in got)}/{len(exp)}; "
         f"trasferimenti EXEC CICS XCTL attesi visti: {len(seen)}/{len(xctl)} (lo strumento "
         f"{'li vede' if seen else 'non li vede'})")


# ---------------------------------------------------------------- layout
def check_layout(exp_dir):
    lengths = {r[0]: int(r[1]) for r in read_tsv(f"{exp_dir}/lengths.tsv")}
    got_len = {r[0]: int(r[2]) for r in read_tsv(f"{OUT}/cb2xml/lengths.tsv")[1:]}
    for c, n in lengths.items():
        if got_len.get(c) != n:
            bad(f"{c}: lunghezza totale attesa {n}, cb2xml {got_len.get(c)}")
    layout = {}
    for r in read_tsv(f"{OUT}/cb2xml/layout.tsv")[1:]:
        layout.setdefault((r[0], r[1]), []).append((int(r[2]), int(r[3]), r[4], int(r[5]), r[6]))
    for r in read_tsv(f"{exp_dir}/layout.tsv"):
        key = (r[0], r[1])
        want = (int(r[2]), int(r[3]), r[4], int(r[5]), r[6])
        if want not in layout.get(key, []):
            bad(f"{r[0]}.{r[1]}: atteso offset/lunghezza/tipo/scala/redefines {want}, cb2xml {layout.get(key)}")
    # i sei campi attesi di CVACT01Y sono davvero i primi sei campi elementari, nell'ordine
    first = [r for r in read_tsv(f"{OUT}/cb2xml/layout.tsv")[1:] if r[0] == "CVACT01Y" and r[4] != "group"][:6]
    want_names = [r[1] for r in read_tsv(f"{exp_dir}/layout.tsv") if r[0] == "CVACT01Y"]
    if [r[1] for r in first] != want_names:
        bad(f"primi sei campi elementari di CVACT01Y: attesi {want_names}, cb2xml {[r[1] for r in first]}")
    # tre importi consecutivi di uguale ampiezza non scambiati: offset distinti e nell'ordine atteso
    offs = [layout.get(("CVACT01Y", n), [(None,)])[0][0] for n in ("ACCT-CURR-BAL", "ACCT-CREDIT-LIMIT", "ACCT-CASH-CREDIT-LIMIT")]
    if offs != [12, 24, 36]:
        bad(f"importi consecutivi di CVACT01Y scambiati o spostati: offset {offs}")
    # RECORDSIZE di CBEXPORT.jcl contro la lunghezza di CVEXPORT (si segnala, non si corregge)
    jcl = open(f"{LEGACY}/app/jcl/CBEXPORT.jcl", encoding="latin-1").read()
    m = re.search(r"RECORDSIZE\((\d+)\s+(\d+)\)", jcl)
    if not m:
        bad("RECORDSIZE non trovato in app/jcl/CBEXPORT.jcl")
    else:
        rs = int(m.group(1))
        tot = got_len.get("CVEXPORT")
        diff = "nessuna differenza" if rs == tot else f"DIFFERENZA: JCL {rs}, copybook {tot}"
        note(f"CVEXPORT: lunghezza cb2xml {tot} byte; RECORDSIZE(medio massimo) in CBEXPORT.jcl = {m.group(1)} {m.group(2)}: {diff}")


# ---------------------------------------------------------------- jcl
def check_jcl(exp_dir):
    steps = {(r[0], r[1]): (r[2], r[3]) for r in read_tsv(f"{OUT}/mapa/jcl_steps.tsv")[1:]}
    exp_steps = read_tsv(f"{exp_dir}/jcl_steps.tsv")
    for r in exp_steps:
        want = (r[2], r[3])
        if steps.get((r[0], r[1])) != want:
            bad(f"{r[0]}/{r[1]}: tipo e programma attesi {want}, mapa {steps.get((r[0], r[1]))}")
    # nessun passo in piu' o in meno per i job con attesi
    for job in sorted({r[0] for r in exp_steps}):
        e = {r[1] for r in exp_steps if r[0] == job}
        g = {k[1] for k in steps if k[0] == job}
        if e != g:
            bad(f"{job}: passi attesi {sorted(e)}, mapa {sorted(g)}")
    dd_got = {}
    for r in read_tsv(f"{OUT}/mapa/jcl_dd.tsv")[1:]:
        dd_got.setdefault((r[0], r[1]), {})[r[2]] = r[3]
    dd_exp = {}
    for r in read_tsv(f"{exp_dir}/jcl_dd.tsv"):
        dd_exp.setdefault((r[0], r[1]), {})[r[2]] = r[3]
    for key, e in dd_exp.items():
        g = dd_got.get(key, {})
        if g != e:
            bad(f"{key[0]}/{key[1]}: DD attese {sorted(e.items())}, mapa {sorted(g.items())}")
    note(f"mapa: passi attesi verificati {len(exp_steps)} (tipo e programma), DD di POSTTRAN/STEP15 verificate {len(dd_exp.get(('POSTTRAN', 'STEP15'), {}))}")


def main(argv):
    exp_dir = "/analysis/tools/expected"
    args = []
    i = 1
    while i < len(argv):
        if argv[i] == "--expected":
            exp_dir = argv[i + 1]
            i += 2
        elif argv[i] == "--out":
            global OUT
            OUT = argv[i + 1]
            i += 2
        else:
            args.append(argv[i])
            i += 1
    check = args[0]
    if check == "scc":
        check_scc(exp_dir)
    elif check == "scc-split":
        check_scc_split(exp_dir)
    elif check == "compile":
        check_compile(exp_dir)
    elif check == "copy":
        check_copy(args[1], exp_dir)
    elif check == "call":
        check_call(args[1], exp_dir)
    elif check == "layout":
        check_layout(exp_dir)
    elif check == "jcl":
        check_jcl(exp_dir)
    else:
        print("controllo sconosciuto", file=sys.stderr)
        return 2
    for n in notes:
        print("  " + n)
    for p in problems:
        print("  PROBLEMA: " + p)
    print("VERDETTO: " + ("fail" if problems else "pass"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
