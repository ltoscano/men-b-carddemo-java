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
elif kind == "drop-copybook-call":            # la CALL dentro il copybook CSUTLDPY (riga 293) tolta
    E.remove(find("CALL", "copybook:CSUTLDPY", "program:CSUTLDTC"))
elif kind == "copy-target":                   # la COPY di COCRDUPC riga 268 punta a un altro copybook (conteggi invariati)
    src_e = find("COPY", "program:COCRDUPC", "copybook:CVCRD01Y")
    o = src_e["occorrenze"].pop(0)
    assert o["riga"] == 268
    if not src_e["occorrenze"]:
        E.remove(src_e)
    find("COPY", "program:COCRDUPC", "copybook:CVACT02Y")["occorrenze"].append(o)
elif kind == "swap-dd-between-steps":         # due DD di COMBTRAN scambiate fra due passi (conteggi per passo invariati)
    def take(step, ddname):
        for e in E:
            if e["tipo"] == "PASSO_DD" and e["da"] == step:
                for o in e["occorrenze"]:
                    if o["dd"] == ddname:
                        e["occorrenze"].remove(o)
                        return e["a"], o
        raise SystemExit("DD non trovata")

    def put(step, a, o):
        for e in E:
            if e["tipo"] == "PASSO_DD" and e["da"] == step and e["a"] == a:
                e["occorrenze"].append(o)
                return
        E.append({"tipo": "PASSO_DD", "da": step, "a": a, "occorrenze": [o]})
    s1, s2 = "jcl-step:COMBTRAN/STEP05R", "jcl-step:COMBTRAN/STEP10"
    a1, o1 = take(s1, "SORTIN")
    a2, o2 = take(s2, "TRANVSAM")
    put(s2, a1, o1)
    put(s1, a2, o2)
    g["archi"] = [e for e in E if e["occorrenze"]]
elif kind == "transaction-to-other-program":  # CCUP puntata al programma di CT02, con la riga PROGRAM di CT02 (coerente)
    e = find("TRANSAZIONE_PROGRAMMA", "transaction:CCUP")
    o = e["occorrenze"][0]
    E.remove(e)
    o["riga_programma"] = 440
    find("TRANSAZIONE_PROGRAMMA", "transaction:CT02").__setitem__("a", "program:COTRN02C")
    E.append({"tipo": "TRANSAZIONE_PROGRAMMA", "da": "transaction:CCUP", "a": "program:COTRN02C", "occorrenze": [o]})
elif kind == "dataset-renamed":               # il dataset TCATBALF di INTCALC sostituito con LOADLIB, anche nei campi DSN
    e = find("PASSO_DD", "jcl-step:INTCALC/STEP15", "dataset:AWS.M2.CARDDEMO.TCATBALF.VSAM.KSDS")
    e["a"] = "dataset:AWS.M2.CARDDEMO.LOADLIB"
    for o in e["occorrenze"]:
        o["dsn_sorgente"] = o["dsn_risolto"] = "AWS.M2.CARDDEMO.LOADLIB"
elif kind == "exec-target":                   # WAITSTEP: il programma eseguito da COBSWAIT a CBACT01C
    find("PASSO_ESEGUE", "jcl-step:WAITSTEP/WAIT")["a"] = "program:CBACT01C"
elif kind == "dd-disp":                       # il DISP di una DD alterato (resto invariato)
    find("PASSO_DD", "jcl-step:POSTTRAN/STEP15", "dataset:AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS")["occorrenze"][0]["disp_sorgente"] = "OLD"
elif kind == "gdg-generation":                # generazione GDG alterata su una DD non campionata a mano (COMBTRAN SORTOUT)
    find("PASSO_DD", "jcl-step:COMBTRAN/STEP05R", "dataset:AWS.M2.CARDDEMO.TRANSACT.COMBINED")["occorrenze"][0]["generazione"] = "-1"
elif kind == "gdg-flag":                      # il flag gdg spento su una DD (+1)
    find("PASSO_DD", "jcl-step:INTCALC/STEP15", "dataset:AWS.M2.CARDDEMO.SYSTRAN")["occorrenze"][0]["gdg"] = False
elif kind == "member-altered":                # membro alterato (CREADB21 riga 46, livello B)
    e = find("PASSO_DD", "jcl-step:CREADB21/FREEPLN", "dataset:&LBNM..CNTL")
    assert e["occorrenze"][0]["membro"] == "DB2FREE"
    e["occorrenze"][0]["membro"] = "FAKE"
elif kind == "container-altered":             # metadato contenitore di un passo alterato
    next(n for n in g["nodi"] if n["id"] == "jcl-step:WAITSTEP/WAIT")["contenitore"] = "proc:REPROC"
elif kind == "dd-classe":                     # classe di una DD SYSOUT alterata
    find("PASSO_DD", "jcl-step:INTCALC/STEP15", "dataset:~SYSOUT")["occorrenze"][0]["classe"] = "reale"
elif kind == "exec-fonte":
    find("PASSO_ESEGUE", "jcl-step:INTCALC/STEP15")["occorrenze"][0]["fonte"] = "schede"
elif kind == "contain-fonte":
    find("JOB_PASSO", "jcl-job:INTCALC")["occorrenze"][0]["fonte"] = "schede"
elif kind == "node-modulo":
    next(n for n in g["nodi"] if n["id"] == "program:CBPAUP0C")["modulo"] = "base"
elif kind == "step-ordinale":
    next(n for n in g["nodi"] if n["id"] == "jcl-step:CARDFILE/STEP10")["ordinale"] = 99
elif kind == "dataset-simbolico":
    next(n for n in g["nodi"] if n["id"] == "dataset:AWS.M2.CARDDEMO.LOADLIB")["simbolico"] = True
elif kind == "external-origine":
    next(n for n in g["nodi"] if n["id"] == "external:CEE3ABD")["origine"] = "x"
elif kind == "transaction-file":
    next(n for n in g["nodi"] if n["id"] == "transaction:CAUP")["modulo"] = "app-vsam-mq"
elif kind == "extra-exec":                    # esecuzione falsa accanto a quella vera, stesso file e stessa riga (mutazione del Validatore, giro 3)
    true_e = find("PASSO_ESEGUE", "jcl-step:ACCTFILE/STEP05", "utility:IDCAMS")
    E.append({"tipo": "PASSO_ESEGUE", "da": "jcl-step:ACCTFILE/STEP05", "a": "program:CBACT01C", "occorrenze": [copy.deepcopy(true_e["occorrenze"][0])]})
elif kind == "extra-exec-same-edge":          # la stessa occorrenza di esecuzione ripetuta dentro lo stesso arco
    e = find("PASSO_ESEGUE", "jcl-step:ACCTFILE/STEP05", "utility:IDCAMS")
    e["occorrenze"].append(copy.deepcopy(e["occorrenze"][0]))
elif kind == "extra-dd":                      # una DD di INTCALC/STEP15 ripetuta su un altro dataset dello stesso passo
    src_e = find("PASSO_DD", "jcl-step:INTCALC/STEP15", "dataset:~SYSOUT")
    other = next(e for e in E if e["tipo"] == "PASSO_DD" and e["da"] == src_e["da"] and e["a"] != src_e["a"])
    other["occorrenze"].append(copy.deepcopy(src_e["occorrenze"][0]))
elif kind == "extra-contain":                 # appartenenza falsa di un passo a una procedura, stessa riga dell'appartenenza vera
    true_e = find("JOB_PASSO", "jcl-job:INTCALC")
    E.append({"tipo": "PROC_PASSO", "da": "proc:REPROC", "a": true_e["a"], "occorrenze": [copy.deepcopy(true_e["occorrenze"][0])]})
elif kind == "exec-type-utility":             # COBSWAIT e' un programma COBOL del manifesto: nome giusto, tipo utility (mutazione del Validatore, giro 3)
    find("PASSO_ESEGUE", "jcl-step:WAITSTEP/WAIT")["a"] = "utility:COBSWAIT"
    g["nodi"].append({"id": "utility:COBSWAIT", "tipo": "utility", "nome": "COBSWAIT"})
elif kind == "exec-type-external":            # REPROC e' una procedura del manifesto: nome giusto, tipo external
    find("PASSO_ESEGUE", "jcl-step:PRTCATBL/STEP05R")["a"] = "external:REPROC"
    g["nodi"].append({"id": "external:REPROC", "tipo": "external", "nome": "REPROC", "origine": "procedura non nel repository"})
elif kind == "dup-node":                      # un nodo presente due volte
    g["nodi"].append(copy.deepcopy(next(n for n in g["nodi"] if n["id"] == "jcl-step:WAITSTEP/WAIT")))
elif kind == "dup-edge":                      # un arco presente due volte
    E.append(copy.deepcopy(find("PASSO_ESEGUE", "jcl-step:ACCTFILE/STEP10", "utility:IDCAMS")))
elif kind == "orphan-node":                   # un dataset che nessun arco usa
    g["nodi"].append({"id": "dataset:AWS.M2.CARDDEMO.FANTASMA", "tipo": "dataset", "nome": "AWS.M2.CARDDEMO.FANTASMA", "classe": "reale"})
elif kind == "extra-step-node":               # un passo in piu' senza scheda EXEC
    g["nodi"].append({"id": "jcl-step:WAITSTEP/FINTO", "tipo": "jcl-step", "nome": "WAITSTEP/FINTO", "file": "app/jcl/WAITSTEP.jcl", "riga": 99,
                      "ordinale": 7, "contenitore": "jcl-job:WAITSTEP", "fonte": "mapa"})
else:
    raise SystemExit("mutazione sconosciuta: " + kind)
with open(dst, "w", encoding="utf-8") as f:
    json.dump(g, f, indent=1, ensure_ascii=False, sort_keys=True)
    f.write("\n")
