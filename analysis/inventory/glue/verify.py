#!/usr/bin/env python3
"""Verifica di un grafo contro i conteggi indipendenti, il sorgente, l'output di mapa e gli attesi scritti a mano.

Uso: verify.py GRAPH.json COUNTS.json OUTDIR EXPECTEDDIR
Stampa un messaggio 'VERIFICA: ...' per ogni difetto e termina con codice 1 se ce n'e' almeno uno."""
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import manifest, of_type, read_lines, read_tsv, stem

GRAPH, COUNTS, OUT, EXP = sys.argv[1:5]
errors = []


def err(msg):
    errors.append(msg)
    print("VERIFICA: " + msg)


g = json.load(open(GRAPH, encoding="utf-8"))
counts = json.load(open(COUNTS, encoding="utf-8"))
nodes = {n["id"]: n for n in g["nodi"]}
edges = g["archi"]
TYPE_OF = dict(manifest())


def rows_of(path):
    return [l.rstrip("\n").split("\t") for l in open(path, encoding="utf-8") if l.strip() and not l.startswith("#")]


REQUIRED = ["edges_COBIL00C", "edges_CBTRN02C", "edges_CBACT01C", "contains_COACTUPC", "contains_COTRTLIC", "contains_parm",
            "csd_CARDDEMO", "jcl_POSTTRAN", "jcl_CREASTMT", "jcl_TRANEXTR", "jcl_TRANREPT", "jcl_REPROC", "livello_b", "totali", "anomalie_manuali"]
for r in REQUIRED:
    if not os.path.isfile(os.path.join(EXP, r + ".tsv")) or os.path.getsize(os.path.join(EXP, r + ".tsv")) == 0:
        err(f"manca il file degli attesi a mano {r}.tsv")
if errors:
    sys.exit(1)

# ------------------------------------------------------------------ 1. un nodo per ogni file sorgente del manifesto
for p in of_type("cobol"):
    n = nodes.get("program:" + stem(p))
    if not n or n.get("file") != p:
        err(f"manca il nodo program:{stem(p)} per il file cobol {p}")
for p in of_type("copybook"):
    if "copybook:" + stem(p) not in nodes:
        err(f"manca il nodo copybook per {p}")
for p in of_type("asm"):
    if "asm:" + stem(p) not in nodes:
        err(f"manca il nodo asm per {p}")
for p in of_type("jcl"):
    if "jcl-job:" + stem(p) not in nodes:
        err(f"manca il nodo jcl-job per {p}")
for p in of_type("proc"):
    if "proc:" + stem(p) not in nodes:
        err(f"manca il nodo proc per {p}")
for e in edges:
    for end in ("da", "a"):
        if e[end] not in nodes:
            err(f"arco {e['tipo']} {e['da']} -> {e['a']}: il nodo {e[end]} non esiste")

# ------------------------------------------------------------------ 2. COPY e CALL contro il conteggio indipendente
for tipo, key, label in (("COPY", "copy", "COPY"), ("CALL", "call", "CALL con letterale")):
    got = Counter()
    for e in edges:
        if e["tipo"] == tipo:
            for o in e["occorrenze"]:
                got[o["file"]] += 1
                if nodes.get(e["da"], {}).get("file") != o["file"]:
                    err(f"{tipo} {e['da']} -> {e['a']}: occorrenza in {o['file']} ma il nodo di partenza e' {nodes.get(e['da'], {}).get('file')}")
    for p, want in sorted(counts[key].items()):
        if got[p] != want:
            err(f"{label}: {p}: occorrenze nel grafo {got[p]}, conteggio indipendente sul sorgente {want}")

# ------------------------------------------------------------------ 3. transazioni
got = Counter()
for e in edges:
    if e["tipo"] == "TRANSAZIONE_PROGRAMMA":
        for o in e["occorrenze"]:
            got[o["file"]] += 1
for p, want in sorted(counts["csd"].items()):
    if got[p] != want:
        err(f"transazioni: {p}: nel grafo {got[p]}, DEFINE TRANSACTION nel sorgente {want}")

# ------------------------------------------------------------------ 4. JCL: passi e DD per file e per passo
steps_by_file = defaultdict(list)
for n in g["nodi"]:
    if n["tipo"] == "jcl-step":
        steps_by_file[n["file"]].append(n)
dd_by_step = defaultdict(list)
job_dd_by_file = defaultdict(list)
for e in edges:
    if e["tipo"] == "PASSO_DD":
        dd_by_step[e["da"]].extend(e["occorrenze"])
    elif e["tipo"] == "JOB_DD":
        for o in e["occorrenze"]:
            job_dd_by_file[o["file"]].append(o)
tot_e = tot_d = 0
for p in of_type("jcl", "proc"):
    c = counts["jcl"][p]
    st = sorted(steps_by_file[p], key=lambda n: n["ordinale"])
    if len(st) != c["exec"]:
        err(f"JCL: {p}: passi nel grafo {len(st)}, EXEC nel sorgente {c['exec']}")
    dd_total = 0
    for i, n in enumerate(st):
        have = len(dd_by_step[n["id"]])
        dd_total += have
        if i < len(c["passi"]) and have != c["passi"][i][1]:
            err(f"JCL: {p}: passo {n['nome']} (riga {n['riga']}): DD nel grafo {have}, nel sorgente {c['passi'][i][1]}")
    if len(job_dd_by_file[p]) != c["dd_livello_job"]:
        err(f"JCL: {p}: DD a livello di job nel grafo {len(job_dd_by_file[p])}, nel sorgente {c['dd_livello_job']}")
    dd_total += len(job_dd_by_file[p])
    if dd_total != c["dd"]:
        err(f"JCL: {p}: DD nel grafo {dd_total}, nel sorgente {c['dd']}")
    if TYPE_OF[p] == "jcl":
        tot_e += c["exec"]
        tot_d += c["dd"]
tot = {r[0]: int(r[1]) for r in rows_of(os.path.join(EXP, "totali.tsv"))}
if (tot_e, tot_d) != (tot["esecuzioni"], tot["DD"]) or len(of_type("jcl")) != tot["file_jcl"]:
    err(f"JCL: totali del conteggio indipendente ({tot_e} EXEC, {tot_d} DD) diversi da quelli scritti a mano ({tot['esecuzioni']}, {tot['DD']})")
if counts["csd"].get("app/csd/CARDDEMO.CSD") != tot["transazioni_app_csd"]:
    err(f"CSD: transazioni di app/csd/CARDDEMO.CSD {counts['csd'].get('app/csd/CARDDEMO.CSD')}, scritte a mano {tot['transazioni_app_csd']}")
g_e = sum(1 for n in g["nodi"] if n["tipo"] == "jcl-step" and TYPE_OF[n["file"]] == "jcl")
g_d = sum(len(o) for k, o in dd_by_step.items() if TYPE_OF[nodes[k]["file"]] == "jcl") + sum(len(o) for k, o in job_dd_by_file.items() if TYPE_OF[k] == "jcl")
if (g_e, g_d) != (tot["esecuzioni"], tot["DD"]):
    err(f"JCL: nel grafo {g_e} passi e {g_d} DD, attesi {tot['esecuzioni']} e {tot['DD']}")

# ------------------------------------------------------------------ 5. ogni occorrenza punta a una riga che contiene l'istruzione
src_cache = {}


def src(p):
    if p not in src_cache:
        src_cache[p] = read_lines(p)
    return src_cache[p]


def line_of(o):
    ls = src(o["file"])
    return ls[o["riga"] - 1] if 1 <= o["riga"] <= len(ls) else ""


PAT = {
    "COPY": lambda o, e: re.search(r"(?<![A-Z0-9-])COPY(?![A-Z0-9-])", line_of(o).upper()) is not None,
    "CALL": lambda o, e: re.search(r"(?<![A-Z0-9-])CALL(?![A-Z0-9-])", line_of(o).upper()) is not None,
    "TRANSAZIONE_PROGRAMMA": lambda o, e: re.match(r"\s*DEFINE\s+TRANSACTION\(" + e["da"].split(":", 1)[1] + r"\)", line_of(o), re.I) is not None
    and re.search(r"PROGRAM\(" + e["a"].split(":", 1)[1] + r"\)", src(o["file"])[o["riga_programma"] - 1], re.I) is not None,
    "JOB_PASSO": lambda o, e: re.match(r"^//\S*\s+EXEC(\s|$)", line_of(o)) is not None,
    "PROC_PASSO": lambda o, e: re.match(r"^//\S*\s+EXEC(\s|$)", line_of(o)) is not None,
    "PASSO_ESEGUE": lambda o, e: re.match(r"^//\S*\s+EXEC(\s|$)", line_of(o)) is not None,
    "PASSO_DD": lambda o, e: re.match(r"^//\S*\s+DD(\s|$)", line_of(o)) is not None,
    "JOB_DD": lambda o, e: re.match(r"^//\S*\s+DD(\s|$)", line_of(o)) is not None,
}
for e in edges:
    for o in e["occorrenze"]:
        if not PAT[e["tipo"]](o, e):
            err(f"riga: {e['tipo']} {e['da']} -> {e['a']}: la riga {o['riga']} di {o['file']} non contiene l'istruzione ({line_of(o)[:60].strip()!r})")

# ------------------------------------------------------------------ 6. livelli di copertura e fonti
exp_b = {r[0]: r for r in rows_of(os.path.join(EXP, "livello_b.tsv"))}
lv = g["livelli_jcl"]
b_now = sorted(p for p, v in lv.items() if v == "B")
if b_now != sorted(exp_b):
    err(f"livello B: i file nel grafo {b_now} sono diversi dall'elenco atteso {sorted(exp_b)}")
if sorted(lv) != sorted(of_type("jcl")):
    err("livello JCL: l'elenco dei file nel grafo non coincide con i jcl del manifesto")
for p, r in exp_b.items():
    c = counts["jcl"].get(p)
    if not c or (str(c["exec"]), str(c["dd"])) != (r[1], r[2]):
        err(f"livello B: {p}: numeri attesi ({r[1]}, {r[2]}) diversi dal conteggio indipendente")
mapa_steps = Counter(r["file"] for r in read_tsv(os.path.join(OUT, "mapa_steps.tsv")))
mapa_dd = Counter(r["file"] for r in read_tsv(os.path.join(OUT, "mapa_dd.tsv")))
for p in of_type("jcl", "proc"):
    want = "mapa" if (lv.get(p) == "A") else "schede"
    for n in steps_by_file[p]:
        if n["fonte"] != want:
            err(f"fonte: il passo {n['id']} dichiara '{n['fonte']}', atteso '{want}' (livello {lv.get(p, 'proc')})")
        if want == "mapa" and mapa_steps[p] != counts["jcl"][p]["exec"]:
            err(f"fonte: {p} dichiarato livello A ma mapa riporta {mapa_steps[p]} passi su {counts['jcl'][p]['exec']}")
    for k, occ in list(dd_by_step.items()):
        if nodes[k]["file"] == p:
            for o in occ:
                if o["fonte"] != want:
                    err(f"fonte: una DD di {k} dichiara '{o['fonte']}', atteso '{want}'")
    if want == "mapa" and mapa_dd[p] != counts["jcl"][p]["dd"]:
        err(f"fonte: {p} dichiarato livello A ma mapa riporta {mapa_dd[p]} DD su {counts['jcl'][p]['dd']}")
for p, occ in job_dd_by_file.items():
    for o in occ:
        if o["fonte"] != "schede" or o["livello"] != "job":
            err(f"DD a livello di job in {p} riga {o['riga']}: fonte/livello inattesi")
for e in edges:
    if e["tipo"] == "PASSO_DD":
        for o in e["occorrenze"]:
            if o["livello"] != "passo":
                err(f"PASSO_DD {e['da']}: DD di livello '{o['livello']}' attribuita a un passo")

# ------------------------------------------------------------------ 7. attesi scritti a mano
def edge_rows(da=None, tipi=None):
    out = set()
    for e in edges:
        if (da is not None and e["da"] != da) or (tipi and e["tipo"] not in tipi):
            continue
        for o in e["occorrenze"]:
            if e["tipo"] == "COPY":
                det = ";".join(f"{s['da']}={s['a']}" for s in o.get("sostituzioni", []))
            elif e["tipo"] == "TRANSAZIONE_PROGRAMMA":
                det = str(o["riga_programma"])
            else:
                det = ""
            out.add((e["tipo"], e["da"], e["a"], o["file"], str(o["riga"]), det))
    return out


for f in sorted(glob.glob(os.path.join(EXP, "edges_*.tsv"))):
    want = {tuple(r) for r in rows_of(f)}
    da = next(iter(want))[1]
    have = edge_rows(da, ("COPY", "CALL"))
    for r in sorted(want - have):
        err(f"atteso a mano {os.path.basename(f)}: manca {r}")
    for r in sorted(have - want):
        err(f"atteso a mano {os.path.basename(f)}: arco uscente non atteso {r}")
for f in sorted(glob.glob(os.path.join(EXP, "contains_*.tsv"))) + [os.path.join(EXP, "csd_CARDDEMO.tsv")]:
    if f.endswith("contains_parm.tsv"):
        continue
    want = {tuple(r) for r in rows_of(f)}
    have = edge_rows()
    for r in sorted(want - have):
        err(f"atteso a mano {os.path.basename(f)}: manca {r}")


def jcl_rows(prefix, container):
    out = set()
    for e in edges:
        if e["tipo"] == "PASSO_ESEGUE" and e["da"].startswith("jcl-step:" + prefix + "/"):
            for o in e["occorrenze"]:
                out.add(("STEP", e["da"], str(o["riga"]), o["esecuzione"], e["a"].split(":", 1)[1], o.get("parm", ""), o["fonte"], e["a"]))
        elif e["tipo"] in ("PASSO_DD", "JOB_DD") and (e["da"].startswith("jcl-step:" + prefix + "/") or e["da"] == container):
            for o in e["occorrenze"]:
                out.add(("DD", e["da"], str(o["riga"]), o["dd"], o.get("dsn_sorgente", ""), o.get("disp_sorgente", ""), e["a"],
                         o.get("generazione", ""), o["livello"], o["fonte"], o.get("dsn_risolto", ""), o.get("disp_effettivo", "")))
    return out


for f in sorted(glob.glob(os.path.join(EXP, "jcl_*.tsv"))):
    want = {tuple(r) for r in rows_of(f)}
    first = next(iter(sorted(want)))[1]
    prefix = first[len("jcl-step:"):].split("/")[0]
    container = ("proc:" + prefix[5:]) if prefix.startswith("proc.") else "jcl-job:" + prefix
    have = jcl_rows(prefix, container)
    for r in sorted(want - have):
        err(f"atteso a mano {os.path.basename(f)}: manca {r}")
    for r in sorted(have - want):
        err(f"atteso a mano {os.path.basename(f)}: riga del grafo non attesa {r}")
want = {tuple(r) for r in rows_of(os.path.join(EXP, "contains_parm.tsv"))}
have = set()
for e in edges:
    if e["tipo"] == "PASSO_ESEGUE":
        for o in e["occorrenze"]:
            have.add(("STEP", e["da"], str(o["riga"]), o["esecuzione"], e["a"].split(":", 1)[1], o.get("parm", ""), o["fonte"], e["a"]))
for r in sorted(want - have):
    err(f"atteso a mano contains_parm.tsv: manca {r}")
for e in edges:
    if e["tipo"] == "PASSO_ESEGUE" and e["da"].startswith("jcl-step:FTPJCL/"):
        if any("parm" in o for o in e["occorrenze"]):
            err("FTPJCL: PARM attribuito a un passo ma la sola occorrenza e' in una riga di commento")

# anomalie del sorgente verificate a mano
for p, riga, needle, _ in rows_of(os.path.join(EXP, "anomalie_manuali.tsv")):
    ls = src(p)
    if needle not in ls[int(riga) - 1]:
        err(f"anomalia manuale: {p}:{riga} non contiene {needle!r}")

print(f"verifica: {len(errors)} difetti")
sys.exit(1 if errors else 0)
