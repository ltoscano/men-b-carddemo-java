#!/usr/bin/env python3
"""Costruisce graph.json e inventario.md dagli output delle analisi (colla: non analizza COBOL o JCL).

Uso: build.py COUNTS.json OUTDIR DOCSDIR
  OUTDIR  contiene copy.tsv, call_occ.tsv, call_dinamiche.tsv, call_non_riportate.tsv, csd.tsv, cards.tsv, mapa_*.tsv
          e riceve jcl_livelli.tsv
  DOCSDIR riceve graph.json e inventario.md
"""
import json
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import manifest, of_type, read_tsv, stem, write_tsv

COUNTS, OUT, DOCS = sys.argv[1:4]

M = manifest()
TYPE_OF = dict(M)
nodes = {}
edges = defaultdict(list)   # (tipo, da, a) -> occorrenze


def node(tipo, nome, **attrs):
    nid = f"{tipo}:{nome}"
    n = nodes.setdefault(nid, {"id": nid, "tipo": tipo, "nome": nome})
    for k, v in attrs.items():
        if v is not None:
            n[k] = v
    return nid


def edge(tipo, da, a, occ):
    edges[(tipo, da, a)].append(occ)


def modulo(path):
    parts = path.split("/")
    return "base" if parts[1] in ("cbl", "cpy", "cpy-bms", "jcl", "proc", "asm", "csd") else parts[1]


# ---------------------------------------------------------------- nodi da manifesto
prog_path = {stem(p): p for p in of_type("cobol")}
cpy_path = {stem(p): p for p in of_type("copybook")}
asm_path = {stem(p): p for p in of_type("asm")}
proc_path = {stem(p): p for p in of_type("proc")}
for s, p in prog_path.items():
    node("program", s, file=p, modulo=modulo(p))
for s, p in cpy_path.items():
    node("copybook", s, file=p, modulo=modulo(p))
for s, p in asm_path.items():
    node("asm", s, file=p, modulo=modulo(p))
for s, p in proc_path.items():
    node("proc", s, file=p, modulo=modulo(p))
assert len(prog_path) == len(of_type("cobol")) and len(cpy_path) == len(of_type("copybook")), "nomi duplicati nel manifesto"


def src_node(path):
    return {"cobol": "program", "copybook": "copybook"}[TYPE_OF[path]] + ":" + stem(path)


# ---------------------------------------------------------------- COPY
for r in read_tsv(os.path.join(OUT, "copy.tsv")):
    name = r["copybook"].upper()
    if name in cpy_path:
        target = f"copybook:{name}"
    else:
        target = node("external", name, origine="COPY non risolta: nessun copybook con questo nome nel manifesto")
    subs = []
    if r["sostituzioni"]:
        for part in r["sostituzioni"].split(";"):
            a, _, b = part.partition("=")
            subs.append({"da": a, "a": b})
    occ = {"file": r["file"], "riga": int(r["riga"])}
    if subs:
        occ["sostituzioni"] = subs
    edge("COPY", src_node(r["file"]), target, occ)

# ---------------------------------------------------------------- CALL
for r in read_tsv(os.path.join(OUT, "call_occ.tsv")):
    name = r["chiamato"].upper()
    if name in prog_path:
        target = f"program:{name}"
    elif name in asm_path:
        target = f"asm:{name}"
    else:
        target = node("external", name, origine="CALL: non e' un file del repository")
    edge("CALL", src_node(r["file"]), target, {"file": r["file"], "riga": int(r["riga"])})

# ---------------------------------------------------------------- transazioni
for r in read_tsv(os.path.join(OUT, "csd.tsv")):
    t = node("transaction", r["transazione"], file=r["file"], modulo=modulo(r["file"]))
    if r["programma"] in prog_path:
        target = f"program:{r['programma']}"
    else:
        target = node("external", r["programma"], origine="transazione del CSD: programma non nel repository")
    edge("TRANSAZIONE_PROGRAMMA", t, target, {"file": r["file"], "riga": int(r["riga"]), "riga_programma": int(r["riga_programma"])})

# ---------------------------------------------------------------- JCL
counts = json.load(open(COUNTS))
cards = defaultdict(list)
for r in read_tsv(os.path.join(OUT, "cards.tsv")):
    cards[r["file"]].append(r)
mapa_steps, mapa_dd = defaultdict(list), defaultdict(lambda: defaultdict(list))
for r in read_tsv(os.path.join(OUT, "mapa_steps.tsv")):
    mapa_steps[r["file"]].append(r)
for r in read_tsv(os.path.join(OUT, "mapa_dd.tsv")):
    mapa_dd[r["file"]][int(r["ordinale"])].append(r)


def split_cards(path):
    steps, jobdd = [], []
    for c in cards[path]:
        if c["scheda"] == "EXEC":
            steps.append({"exec": c, "dd": []})
        elif steps:
            steps[-1]["dd"].append(c)
        else:
            jobdd.append(c)
    return steps, jobdd


def effective_names(dds):
    """Nome di ogni DD; una DD senza nome (concatenazione) eredita quello della precedente, come la riporta mapa."""
    out, last = [], ""
    for d in dds:
        last = d["nome"] or last
        out.append(last)
    return out


def decide_level(path):
    """A se mapa coincide con il conteggio indipendente e con le schede su passi, programmi e DD; altrimenti B, con il motivo."""
    steps, jobdd = split_cards(path)
    cnt = counts["jcl"][path]
    ms = mapa_steps.get(path, [])
    mdd = sum(len(v) for v in mapa_dd.get(path, {}).values())
    base = (cnt["exec"], cnt["dd"], len(ms), mdd)
    if len(ms) != cnt["exec"] or len(steps) != cnt["exec"]:
        return "B", base, f"passi: mapa {len(ms)}, sorgente {cnt['exec']}"
    if mdd != cnt["dd"]:
        return "B", base, f"DD: mapa {mdd}, sorgente {cnt['dd']}"
    for i, (m, s) in enumerate(zip(ms, steps)):
        c = s["exec"]
        if (m["passo"], m["tipo"], m["nome"]) != (c["nome"], c["tipo_exec"], c["esegue"]):
            return "B", base, f"passo {i + 1}: mapa {m['passo']}/{m['tipo']}/{m['nome']}, schede {c['nome']}/{c['tipo_exec']}/{c['esegue']}"
        mine = mapa_dd[path].get(int(m["ordinale"]), [])
        if len(mine) != len(s["dd"]) or len(mine) != cnt["passi"][i][1]:
            return "B", base, f"passo {c['nome']}: DD mapa {len(mine)}, sorgente {cnt['passi'][i][1]}"
        if [d["dd"] for d in mine] != effective_names(s["dd"]):
            return "B", base, f"passo {c['nome']}: nomi delle DD diversi"
    if jobdd:
        return "B", base, "DD a livello di job: mapa non le riporta"
    return "A", base, ""


def classify(c):
    if c["in_linea"] == "1":
        return "instream"
    if c["sysout"] == "1":
        return "sysout"
    if c["dummy"] == "1":
        return "dummy"
    if c["dsn"].startswith("&&"):
        return "temporaneo"
    if c["dsn"]:
        return "reale"
    return "senza-dsn"


PSEUDO = {"instream": "~INSTREAM", "sysout": "~SYSOUT", "dummy": "~DUMMY", "senza-dsn": "~SENZA-DSN"}


def dataset_ref(c, risolto):
    cls = classify(c)
    name = risolto if (cls == "reale" and risolto) else c["dsn"]
    gen = membro = None
    if cls in PSEUDO:
        return node("dataset", PSEUDO[cls], classe=cls), cls, gen, membro
    m = re.match(r"^(.*)\(([^()]*)\)$", name)
    if m:
        name = m.group(1)
        if re.fullmatch(r"[+-]?\d+", m.group(2)):
            gen = m.group(2)
        else:
            membro = m.group(2)
    attrs = {"classe": cls}
    if "&" in name and cls == "reale":
        attrs["simbolico"] = True
    return node("dataset", name, **attrs), cls, gen, membro


def dd_edge(path, da, tipo, c, m, livello, fonte):
    risolto = m["dsn_risolto"] if m else ""
    nid, cls, gen, membro = dataset_ref(c, risolto)
    occ = {"file": path, "riga": int(c["riga"]), "dd": c["nome"], "livello": livello, "fonte": fonte, "classe": cls}
    if c["dsn"]:
        occ["dsn_sorgente"] = c["dsn"]
    if c["disp"]:
        occ["disp_sorgente"] = c["disp"]
    if m:
        if cls == "reale" and m["dsn_risolto"]:
            occ["dsn_risolto"] = m["dsn_risolto"]
        if m["disp_effettivo"] and (cls not in PSEUDO or c["disp"]):
            occ["disp_effettivo"] = m["disp_effettivo"]
    occ["gdg"] = gen is not None
    if gen is not None:
        occ["generazione"] = gen
    if membro:
        occ["membro"] = membro
    edge(tipo, da, nid, occ)


livelli = []


def jcl_file(path, level):
    is_proc = TYPE_OF[path] == "proc"
    s = stem(path)
    container = node("proc", s, file=path, modulo=modulo(path)) if is_proc else node("jcl-job", s, file=path, modulo=modulo(path))
    steps, jobdd = split_cards(path)
    names = defaultdict(int)
    for st in steps:
        names[st["exec"]["nome"]] += 1
    fonte = "schede" if (level == "B" or is_proc) else "mapa"
    ms = mapa_steps.get(path, [])
    for i, st in enumerate(steps):
        c = st["exec"]
        nm = c["nome"]
        sname = nm if nm and names[nm] == 1 else f"{nm}#{i + 1}"
        sid = node("jcl-step", f"{'proc.' if is_proc else ''}{s}/{sname}", file=path, riga=int(c["riga"]), ordinale=i + 1, contenitore=container, fonte=fonte)
        edge("PROC_PASSO" if is_proc else "JOB_PASSO", container, sid, {"file": path, "riga": int(c["riga"]), "fonte": fonte})
        tgt = c["esegue"]
        if c["tipo_exec"] == "PROC":
            target = f"proc:{tgt.upper()}" if tgt.upper() in proc_path else node("external", tgt, origine="procedura non nel repository")
        elif tgt in prog_path:
            target = f"program:{tgt}"
        elif tgt in asm_path:
            target = f"asm:{tgt}"
        else:
            target = node("utility", tgt)
        occ = {"file": path, "riga": int(c["riga"]), "esecuzione": c["tipo_exec"], "fonte": fonte}
        if c["parm"]:
            occ["parm"] = c["parm"]
        edge("PASSO_ESEGUE", sid, target, occ)
        mdds = mapa_dd[path].get(int(ms[i]["ordinale"]), []) if fonte == "mapa" else []
        for k, d in enumerate(st["dd"]):
            dd_edge(path, sid, "PASSO_DD", d, mdds[k] if fonte == "mapa" else None, "passo", fonte)
    for d in jobdd:
        dd_edge(path, container, "JOB_DD", d, None, "job", "schede")


for path in of_type("jcl"):
    lv, base, motivo = decide_level(path)
    livelli.append((path, lv) + base + (motivo,))
    jcl_file(path, lv)
for path in of_type("proc"):
    jcl_file(path, "B")
write_tsv(os.path.join(OUT, "jcl_livelli.tsv"), ["file", "livello", "exec_sorgente", "dd_sorgente", "exec_mapa", "dd_mapa", "motivo"], livelli)


# ---------------------------------------------------------------- serializzazione
def occ_key(o):
    return (o["file"], o["riga"], json.dumps(o, sort_keys=True))


graph = {
    "versione_schema": 1,
    "descrizione": "Grafo delle dipendenze statiche di CardDemo (analysis/inventory). Non e' completo: vedi la sezione "
                   "'Categorie non ancora mappate' di docs/legacy-map/inventario.md.",
    "livelli_jcl": {p: lv for p, lv, *_ in livelli},
    "nodi": sorted(nodes.values(), key=lambda n: n["id"]),
    "archi": [
        {"tipo": t, "da": da, "a": a, "occorrenze": sorted(occ, key=occ_key)}
        for (t, da, a), occ in sorted(edges.items())
    ],
}
for n in graph["nodi"]:
    assert n["id"] == f"{n['tipo']}:{n['nome']}"
with open(os.path.join(DOCS, "graph.json"), "w", encoding="utf-8") as f:
    json.dump(graph, f, indent=1, ensure_ascii=False, sort_keys=True)
    f.write("\n")

import report  # noqa: E402

report.write(graph, os.path.join(DOCS, "inventario.md"), OUT, counts)
