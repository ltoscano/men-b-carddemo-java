#!/usr/bin/env python3
"""Per le prove negative: copia graph.json alterando UN aspetto. Uso: mutate.py KIND IN.json OUT.json"""
import copy
import json
import sys

kind, src, dst = sys.argv[1:4]
g = json.load(open(src, encoding="utf-8"))
E = g["archi"]


def find(tipo, da=None, a=None):
    for e in E:
        if e["tipo"] == tipo and (da is None or e["da"] == da) and (a is None or e["a"] == a):
            return e
    raise SystemExit(f"arco non trovato {tipo} {da} {a}")


if kind == "drop-copy-category":
    g["archi"] = [e for e in E if e["tipo"] != "COPY"]
elif kind == "drop-dd-category":
    g["archi"] = [e for e in E if e["tipo"] not in ("PASSO_DD", "JOB_DD")]
elif kind == "drop-transaction-category":
    g["archi"] = [e for e in E if e["tipo"] != "TRANSAZIONE_PROGRAMMA"]
elif kind == "drop-occurrence":              # una COPY di CBACT04C (non negli attesi a mano)
    e = find("COPY", "program:CBACT04C")
    e["occorrenze"].pop()
    if not e["occorrenze"]:
        E.remove(e)
elif kind == "drop-occurrence-handwritten":  # una COPY di COBIL00C (negli attesi a mano)
    e = find("COPY", "program:COBIL00C", "copybook:CVACT01Y")
    E.remove(e)
elif kind == "alter-line":                    # la riga di una CALL di CBSTM03A spostata di una riga
    find("CALL", "program:CBSTM03A")["occorrenze"][0]["riga"] += 1
elif kind == "alter-line-handwritten":        # la riga di una COPY di COBIL00C
    find("COPY", "program:COBIL00C", "copybook:COTTL01Y")["occorrenze"][0]["riga"] += 1
elif kind == "merge-replacing":               # due COPY di CSSETATY con REPLACING diversi fuse in una
    e = find("COPY", "program:COACTUPC", "copybook:CSSETATY")
    occ = e["occorrenze"]
    with_r = [o for o in occ if "sostituzioni" in o]
    a, b = with_r[0], with_r[1]
    assert a["sostituzioni"] != b["sostituzioni"]
    occ.remove(b)
elif kind == "level-b-to-a":                  # TRANEXTR spostato al livello A senza che mapa lo analizzi
    g["livelli_jcl"]["app/app-transaction-type-db2/jcl/TRANEXTR.jcl"] = "A"
    for n in g["nodi"]:
        if n["tipo"] == "jcl-step" and n["file"].endswith("TRANEXTR.jcl"):
            n["fonte"] = "mapa"
    for e in E:
        for o in e["occorrenze"]:
            if o["file"].endswith("TRANEXTR.jcl") and "fonte" in o:
                o["fonte"] = "mapa"
elif kind == "jobdd-to-step":                 # una DD di livello job attribuita a un passo
    je = find("JOB_DD")
    o = je["occorrenze"].pop(0)
    if not je["occorrenze"]:
        E.remove(je)
    step = next(n for n in g["nodi"] if n["tipo"] == "jcl-step" and n["file"] == o["file"] and n["ordinale"] == 1)
    o = copy.deepcopy(o)
    target = "dataset:" + o.get("dsn_sorgente", "X").split("(")[0]
    E.append({"tipo": "PASSO_DD", "da": step["id"], "a": target, "occorrenze": [o]})
elif kind == "dd-job-level-marked-step":      # la stessa DD marcata livello 'passo' ma lasciata sul job
    find("JOB_DD")["occorrenze"][0]["livello"] = "passo"
elif kind == "drop-dd-occurrence":            # una DD di POSTTRAN
    e = find("PASSO_DD", "jcl-step:POSTTRAN/STEP15", "dataset:AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS")
    E.remove(e)
elif kind == "alter-parm":
    find("PASSO_ESEGUE", "jcl-step:INTCALC/STEP15")["occorrenze"][0]["parm"] = "'2022071801'"
else:
    raise SystemExit("mutazione sconosciuta: " + kind)
with open(dst, "w", encoding="utf-8") as f:
    json.dump(g, f, indent=1, ensure_ascii=False, sort_keys=True)
    f.write("\n")
