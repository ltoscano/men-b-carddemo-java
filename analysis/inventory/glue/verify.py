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

GRAPH, COUNTS, OUT, EXP, SCHEMA = sys.argv[1:6]
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


REQUIRED = ["edges_COBIL00C", "edges_CBTRN02C", "edges_CBACT01C", "contains_COACTUPC", "contains_COTRTLIC", "contains_CSUTLDPY", "contains_CSDB2RPY", "contains_parm",
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
for tipo, key, label in (("COPY", "copy", "COPY"), ("CALL", "call", "CALL (letterali + operando in variabile)")):
    got = Counter()
    for e in edges:
        if e["tipo"] == tipo:
            for o in e["occorrenze"]:
                got[o["file"]] += 1
                if nodes.get(e["da"], {}).get("file") != o["file"]:
                    err(f"{tipo} {e['da']} -> {e['a']}: occorrenza in {o['file']} ma il nodo di partenza e' {nodes.get(e['da'], {}).get('file')}")
    for p, want in sorted(counts[key].items()):
        if key == "call":
            want += counts["call_var"][p]
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


# ------------------------------------------------------------------ 4b. ogni occorrenza e' legata a cio' che lo strumento (o l'estrattore dichiarato) riporta
def ctx_has(path, riga, name, span=3):
    ls = src(path)
    blob = " ".join(ls[riga - 1:riga - 1 + span]).upper().replace("'", " ").replace('"', " ")
    return re.search(r"(?<![A-Z0-9-])" + re.escape(name.upper()) + r"(?![A-Z0-9-])", blob) is not None


cpy_names = {stem(p) for p in of_type("copybook")}
prog_names = {stem(p) for p in of_type("cobol")}
asm_names = {stem(p) for p in of_type("asm")}
proc_names = {stem(p) for p in of_type("proc")}
src_prefix = {"cobol": "program", "copybook": "copybook"}


def multiset(rows):
    return Counter(rows)


# COPY: copy.tsv (ProLeap) <-> occorrenze COPY del grafo: file, riga, bersaglio, sostituzioni
want = []
for r in read_tsv(os.path.join(OUT, "copy.tsv")):
    nm = r["copybook"].upper()
    want.append((r["file"], int(r["riga"]), ("copybook:" if nm in cpy_names else "external:") + nm, r["sostituzioni"]))
    if not ctx_has(r["file"], int(r["riga"]), nm):
        err(f"COPY: {r['file']}:{r['riga']}: il nome {nm} non compare nelle righe del sorgente")
have = []
for e in edges:
    if e["tipo"] == "COPY":
        for o in e["occorrenze"]:
            have.append((o["file"], o["riga"], e["a"], ";".join(f"{x['da']}={x['a']}" for x in o.get("sostituzioni", []))))
            if e["da"] != src_prefix[TYPE_OF[o["file"]]] + ":" + stem(o["file"]):
                err(f"COPY {o['file']}:{o['riga']}: partenza {e['da']} non coerente con il file")
for r, n in (multiset(want) - multiset(have)).items():
    err(f"COPY: lo strumento riporta {r} ma il grafo non lo ha")
for r, n in (multiset(have) - multiset(want)).items():
    err(f"COPY: il grafo ha {r} che lo strumento non riporta (bersaglio o sostituzioni diversi)")

# CALL: call_occ.tsv (nomi di cmt + localizzatore) e call_dinamiche.tsv
want = []
for r in read_tsv(os.path.join(OUT, "call_occ.tsv")):
    nm = r["chiamato"].upper()
    t = "program:" if nm in prog_names else "asm:" if nm in asm_names else "external:"
    want.append((r["file"], int(r["riga"]), t + nm, ""))
    if not ctx_has(r["file"], int(r["riga"]), nm):
        err(f"CALL: {r['file']}:{r['riga']}: il nome {nm} non compare nelle righe del sorgente")
for r in read_tsv(os.path.join(OUT, "call_dinamiche.tsv")):
    want.append((r["file"], int(r["riga"]), "external:~NON-RISOLTO", r["operando"].upper()))
    if not ctx_has(r["file"], int(r["riga"]), r["operando"]):
        err(f"CALL: {r['file']}:{r['riga']}: l'operando {r['operando']} non compare nelle righe del sorgente")
have = []
for e in edges:
    if e["tipo"] == "CALL":
        for o in e["occorrenze"]:
            have.append((o["file"], o["riga"], e["a"], o.get("operando", "")))
            if ("non_risolto" in o) != (e["a"] == "external:~NON-RISOLTO"):
                err(f"CALL {o['file']}:{o['riga']}: bersaglio non risolto incoerente con l'occorrenza")
for r, n in (multiset(want) - multiset(have)).items():
    err(f"CALL: lo strumento riporta {r} ma il grafo non lo ha")
for r, n in (multiset(have) - multiset(want)).items():
    err(f"CALL: il grafo ha {r} che lo strumento non riporta (bersaglio diverso)")

# transazioni: csd.tsv <-> grafo, e programma dello stesso blocco DEFINE nel sorgente
want = []
for r in read_tsv(os.path.join(OUT, "csd.tsv")):
    pg = r["programma"]
    want.append((r["file"], int(r["riga"]), "transaction:" + r["transazione"], ("program:" if pg in prog_names else "external:") + pg, int(r["riga_programma"])))
    ls = src(r["file"])
    if not re.match(r"\s*DEFINE\s+TRANSACTION\(" + re.escape(r["transazione"]) + r"\)", ls[int(r["riga"]) - 1], re.I):
        err(f"CSD: {r['file']}:{r['riga']}: non e' DEFINE TRANSACTION({r['transazione']})")
    if not re.search(r"PROGRAM\(" + re.escape(pg) + r"\)", ls[int(r["riga_programma"]) - 1], re.I):
        err(f"CSD: {r['file']}:{r['riga_programma']}: non contiene PROGRAM({pg})")
    for mid in ls[int(r["riga"]):int(r["riga_programma"]) - 1]:
        if re.match(r"\s*DEFINE\b", mid, re.I):
            err(f"CSD: {r['file']}: tra le righe {r['riga']} e {r['riga_programma']} c'e' un altro DEFINE: il programma non e' dello stesso blocco")
have = []
for e in edges:
    if e["tipo"] == "TRANSAZIONE_PROGRAMMA":
        for o in e["occorrenze"]:
            have.append((o["file"], o["riga"], e["da"], e["a"], o["riga_programma"]))
for r, n in (multiset(want) - multiset(have)).items():
    err(f"CSD: lo strumento riporta {r} ma il grafo non lo ha")
for r, n in (multiset(have) - multiset(want)).items():
    err(f"CSD: il grafo ha {r} che l'estrazione non riporta (programma o riga diversi)")

# JCL: cards.tsv (+ mapa per il livello A) <-> passi, esecuzioni e DD del grafo, con il passo di appartenenza
cards = defaultdict(list)
for r in read_tsv(os.path.join(OUT, "cards.tsv")):
    cards[r["file"]].append(r)
mapa_dd_rows = defaultdict(lambda: defaultdict(list))
for r in read_tsv(os.path.join(OUT, "mapa_dd.tsv")):
    mapa_dd_rows[r["file"]][int(r["ordinale"])].append(r)
step_by = {(n["file"], n["ordinale"]): n for n in g["nodi"] if n["tipo"] == "jcl-step"}
exec_occ, dd_occ, contain_occ = {}, {}, {}
for e in edges:
    for o in e["occorrenze"]:
        if e["tipo"] == "PASSO_ESEGUE":
            exec_occ[(o["file"], o["riga"])] = (e, o)
        elif e["tipo"] in ("PASSO_DD", "JOB_DD"):
            dd_occ[(o["file"], o["riga"])] = (e, o)
        elif e["tipo"] in ("JOB_PASSO", "PROC_PASSO"):
            contain_occ[(o["file"], o["riga"])] = (e, o)


def dataset_expected(c, risolto):
    if c["in_linea"] == "1":
        return "dataset:~INSTREAM"
    if c["sysout"] == "1":
        return "dataset:~SYSOUT"
    if c["dummy"] == "1":
        return "dataset:~DUMMY"
    if not c["dsn"]:
        return "dataset:~SENZA-DSN"
    name = risolto if (risolto and not c["dsn"].startswith("&&")) else c["dsn"]
    m = re.match(r"^(.*)\(([^()]*)\)$", name)
    return "dataset:" + (m.group(1) if m else name)


seen_exec, seen_dd = set(), set()
for p in of_type("jcl", "proc"):
    container = ("proc:" if TYPE_OF[p] == "proc" else "jcl-job:") + stem(p)
    ks = defaultdict(int)
    for c in cards[p]:
        if c["scheda"] == "EXEC":
            key = (p, int(c["riga"]))
            seen_exec.add(key)
            st = step_by.get((p, int(c["passo"])))
            eo = exec_occ.get(key)
            if not st or not eo:
                err(f"JCL: {p}:{c['riga']}: EXEC {c['nome']} senza passo o senza esecuzione nel grafo")
                continue
            e, o = eo
            if st["riga"] != int(c["riga"]) or e["da"] != st["id"]:
                err(f"JCL: {p}:{c['riga']}: il passo {st['id']} non e' quello della scheda")
            if o["esecuzione"] != c["tipo_exec"] or o.get("parm", "") != c["parm"] or e["a"].split(":", 1)[1].upper() != c["esegue"].upper():
                err(f"JCL: {p}:{c['riga']}: esecuzione {e['a']} {o['esecuzione']} parm {o.get('parm', '')!r}, la scheda dice {c['tipo_exec']} {c['esegue']} parm {c['parm']!r}")
            tgt_ok = {"PGM": ("program:", "asm:", "utility:"), "PROC": ("proc:", "external:")}[c["tipo_exec"]]
            if not e["a"].startswith(tgt_ok):
                err(f"JCL: {p}:{c['riga']}: tipo di bersaglio {e['a']} incoerente con {c['tipo_exec']}")
            co = contain_occ.get(key)
            if not co or co[0]["da"] != container or co[0]["a"] != st["id"]:
                err(f"JCL: {p}:{c['riga']}: il passo non e' contenuto in {container}")
        else:
            key = (p, int(c["riga"]))
            seen_dd.add(key)
            do = dd_occ.get(key)
            if not do:
                err(f"JCL: {p}:{c['riga']}: DD {c['nome']} assente dal grafo")
                continue
            e, o = do
            ordn = int(c["passo"])
            if ordn == 0:
                if e["tipo"] != "JOB_DD" or e["da"] != container:
                    err(f"JCL: {p}:{c['riga']}: DD prima del primo passo ma attribuita a {e['da']} ({e['tipo']})")
            else:
                st = step_by.get((p, ordn))
                if e["tipo"] != "PASSO_DD" or not st or e["da"] != st["id"]:
                    err(f"JCL: {p}:{c['riga']}: DD {c['nome']} del passo {ordn} attribuita a {e['da']} ({e['tipo']})")
            mrow = None
            if o["fonte"] == "mapa":
                idx = ks[ordn]
                rows = mapa_dd_rows[p].get(ordn, [])
                mrow = rows[idx] if idx < len(rows) else None
                if mrow is None:
                    err(f"JCL: {p}:{c['riga']}: DD dichiarata fonte mapa ma mapa non ha la DD numero {idx + 1} del passo {ordn}")
            ks[ordn] += 1
            risolto = mrow["dsn_risolto"] if mrow else ""
            if o["dd"] != c["nome"] or e["a"] != dataset_expected(c, risolto):
                err(f"JCL: {p}:{c['riga']}: DD {o['dd']} -> {e['a']}, attesa {c['nome']} -> {dataset_expected(c, risolto)}")
            if o.get("dsn_sorgente", "") != c["dsn"] or o.get("disp_sorgente", "") != c["disp"]:
                err(f"JCL: {p}:{c['riga']}: dsn/disp sorgente del grafo ({o.get('dsn_sorgente', '')!r}, {o.get('disp_sorgente', '')!r}) diversi dalla scheda ({c['dsn']!r}, {c['disp']!r})")
            if mrow:
                realish = not (c["in_linea"] == "1" or c["sysout"] == "1" or c["dummy"] == "1" or not c["dsn"] or c["dsn"].startswith("&&"))
                want_r = mrow["dsn_risolto"] if realish else ""
                want_d = mrow["disp_effettivo"] if (mrow["disp_effettivo"] and (realish or c["disp"] or c["dsn"].startswith("&&"))) else ""
                if o.get("dsn_risolto", "") != want_r or o.get("disp_effettivo", "") != want_d:
                    err(f"JCL: {p}:{c['riga']}: dsn_risolto/disp_effettivo del grafo ({o.get('dsn_risolto', '')!r}, {o.get('disp_effettivo', '')!r}) diversi da mapa ({want_r!r}, {want_d!r})")
for key in set(exec_occ) - seen_exec:
    err(f"JCL: esecuzione nel grafo a {key[0]}:{key[1]} senza scheda EXEC")
for key in set(dd_occ) - seen_dd:
    err(f"JCL: DD nel grafo a {key[0]}:{key[1]} senza scheda DD")

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

# ------------------------------------------------------------------ 6b. ogni attributo scritto nel grafo e' confrontato con un valore ricavato dagli intermedi
# ATTRS: tutti gli attributi dello schema. Ognuno e' CONFRONTATO con gli intermedi (out/*.tsv, manifesto, sorgente) oppure e'
# DERIVATO con una regola scritta qui sotto e verificata. Un attributo dello schema che non e' in questo elenco fa fallire il controllo.
ATTRS = {
    "root.versione_schema": "derivato: costante 1, verificata",
    "root.descrizione": "derivato: testo fisso, deve essere una stringa non vuota che rimanda a inventario.md",
    "root.livelli_jcl": "confrontato con livello_b.tsv atteso, con jcl_livelli (mapa vs conteggio) e con la fonte di passi e DD",
    "root.nodi": "ogni nodo e' confrontato (vedi nodo.*)",
    "root.archi": "ogni arco e' confrontato (vedi arco.* e occ_*)",
    "nodo.id": "derivato: tipo:nome, verificato",
    "nodo.tipo": "derivato dal tipo di file nel manifesto o dagli archi; verificato con il prefisso dell'id",
    "nodo.nome": "confrontato: nome file senza estensione (manifesto), nome della transazione (csd.tsv), regola dei passi (cards.tsv), dataset (DD)",
    "nodo.file": "confrontato con il percorso nel manifesto, con csd.tsv o con cards.tsv",
    "nodo.modulo": "derivato dal percorso: 'base' se non inizia con app/app-, altrimenti la cartella del modulo; verificato",
    "nodo.riga": "confrontato con la riga della scheda EXEC (cards.tsv)",
    "nodo.ordinale": "confrontato con il numero d'ordine del passo (cards.tsv)",
    "nodo.contenitore": "derivato dal file (job o procedura) e confrontato con l'arco JOB_PASSO/PROC_PASSO",
    "nodo.fonte": "derivato dal livello del file (A: mapa, B e procedure: schede), verificato",
    "nodo.classe": "confrontato con la classificazione delle schede DD che puntano al dataset",
    "nodo.simbolico": "derivato: vero se il nome contiene & ed e' un dataset reale; verificato",
    "nodo.origine": "derivato dal tipo di arco entrante (COPY, CALL, transazione, procedura); verificato",
    "arco.tipo": "confrontato: ogni occorrenza di strumento/estrattore ha un arco di quel tipo",
    "arco.da": "confrontato con file del sorgente (COPY, CALL), csd.tsv, cards.tsv (passo di appartenenza)",
    "arco.a": "confrontato con copy.tsv, call_occ.tsv, csd.tsv, cards.tsv/mapa_dd.tsv",
    "arco.occorrenze": "confrontato come insieme, in entrambe le direzioni",
    "occ_copy.file": "confrontato con copy.tsv", "occ_copy.riga": "confrontato con copy.tsv e con il sorgente",
    "occ_copy.sostituzioni": "confrontato con copy.tsv (testo delle sostituzioni)",
    "sostituzione.da": "confrontato con copy.tsv (tramite le sostituzioni)", "sostituzione.a": "confrontato con copy.tsv (tramite le sostituzioni)",
    "occ_call.file": "confrontato con call_occ.tsv/call_dinamiche.tsv", "occ_call.riga": "confrontato con call_occ.tsv e con il sorgente",
    "occ_call.non_risolto": "derivato: vero se e solo se il bersaglio e' external:~NON-RISOLTO; verificato",
    "occ_call.operando": "confrontato con call_dinamiche.tsv",
    "occ_transazione.file": "confrontato con csd.tsv", "occ_transazione.riga": "confrontato con csd.tsv e con il sorgente",
    "occ_transazione.riga_programma": "confrontato con csd.tsv e con il sorgente (stesso blocco DEFINE)",
    "occ_contiene.file": "confrontato con cards.tsv", "occ_contiene.riga": "confrontato con la riga della scheda EXEC",
    "occ_contiene.fonte": "derivato dal livello del file; verificato",
    "occ_esegue.file": "confrontato con cards.tsv", "occ_esegue.riga": "confrontato con cards.tsv",
    "occ_esegue.esecuzione": "confrontato con cards.tsv (PGM o PROC)", "occ_esegue.parm": "confrontato con cards.tsv",
    "occ_esegue.fonte": "derivato dal livello del file; verificato",
    "occ_dd.file": "confrontato con cards.tsv", "occ_dd.riga": "confrontato con cards.tsv",
    "occ_dd.dd": "confrontato con cards.tsv", "occ_dd.livello": "confrontato: passo se la scheda segue un EXEC, job altrimenti",
    "occ_dd.fonte": "derivato dal livello del file; verificato",
    "occ_dd.classe": "confrontato con la classificazione della scheda DD (cards.tsv)",
    "occ_dd.dsn_sorgente": "confrontato con cards.tsv", "occ_dd.disp_sorgente": "confrontato con cards.tsv",
    "occ_dd.dsn_risolto": "confrontato con mapa_dd.tsv", "occ_dd.disp_effettivo": "confrontato con mapa_dd.tsv",
    "occ_dd.gdg": "derivato dal nome del dataset (suffisso numerico con segno tra parentesi); verificato",
    "occ_dd.generazione": "derivato dal nome del dataset; verificato", "occ_dd.membro": "derivato dal nome del dataset; verificato",
}
sch = json.load(open(SCHEMA, encoding="utf-8"))
in_schema = {"root." + k for k in sch["properties"]}
for d in ("nodo", "arco", "sostituzione", "occ_copy", "occ_call", "occ_transazione", "occ_contiene", "occ_esegue", "occ_dd"):
    in_schema |= {d + "." + k for k in sch["$defs"][d]["properties"]}
for k in sorted(in_schema - set(ATTRS)):
    err(f"attributo dello schema non coperto: {k} (aggiungerlo ad ATTRS in verify.py con il confronto o la regola di derivazione)")
for k in sorted(set(ATTRS) - in_schema):
    err(f"ATTRS elenca {k}, che non e' nello schema")

if g["versione_schema"] != 1 or not isinstance(g["descrizione"], str) or "inventario.md" not in g["descrizione"]:
    err("attributi radice: versione_schema o descrizione inattesi")
manif_path = {t: {stem(p): p for p in of_type(t)} for t in ("cobol", "copybook", "asm", "proc", "jcl")}


def modulo_rule(path):
    return path.split("/")[1] if path.startswith("app/app-") else "base"


inbound = defaultdict(list)
for e in edges:
    inbound[e["a"]].append(e)
ds_classes = defaultdict(set)


def classe_of(c):
    if c["in_linea"] == "1":
        return "instream"
    if c["sysout"] == "1":
        return "sysout"
    if c["dummy"] == "1":
        return "dummy"
    if c["dsn"].startswith("&&"):
        return "temporaneo"
    return "reale" if c["dsn"] else "senza-dsn"


def gdg_parts(c, risolto):
    if classe_of(c) in ("instream", "sysout", "dummy", "senza-dsn"):
        return None, None
    name = risolto if (classe_of(c) == "reale" and risolto) else c["dsn"]
    m = re.match(r"^(.*)\(([^()]*)\)$", name)
    if not m:
        return None, None
    return (m.group(2), None) if re.fullmatch(r"[+-]?\d+", m.group(2)) else (None, m.group(2))


csd_rows = {r["transazione"]: r for r in read_tsv(os.path.join(OUT, "csd.tsv"))}
for n in g["nodi"]:
    t = n["tipo"]
    if n["id"] != f"{t}:{n['nome']}":
        err(f"nodo {n['id']}: id diverso da tipo:nome")
    if t in ("program", "copybook", "asm", "proc"):
        mk = {"program": "cobol"}.get(t, t)
        if manif_path[mk].get(n["nome"]) != n.get("file"):
            err(f"nodo {n['id']}: file {n.get('file')} diverso dal manifesto {manif_path[mk].get(n['nome'])}")
    if t == "jcl-job" and manif_path["jcl"].get(n["nome"]) != n.get("file"):
        err(f"nodo {n['id']}: file {n.get('file')} diverso dal manifesto")
    if t in ("program", "copybook", "asm", "proc", "jcl-job", "transaction"):
        if n.get("modulo") != modulo_rule(n["file"]):
            err(f"nodo {n['id']}: modulo {n.get('modulo')} diverso dalla regola ({modulo_rule(n['file'])})")
    if t == "jcl-step" and "modulo" in n:
        err(f"nodo {n['id']}: un passo non ha l'attributo modulo")
    if t == "transaction":
        r = csd_rows.get(n["nome"])
        if not r or r["file"] != n["file"]:
            err(f"nodo {n['id']}: file {n.get('file')} diverso da csd.tsv")
    if t == "dataset":
        sym = "&" in n["nome"] and n["classe"] == "reale"
        if bool(n.get("simbolico")) != sym or ("simbolico" in n and not sym):
            err(f"nodo {n['id']}: simbolico {n.get('simbolico')} diverso dalla regola ({sym})")
    if t == "external":
        kinds = {e["tipo"] for e in inbound[n["id"]]}
        if "COPY" in kinds:
            want_o = "COPY non risolta: nessun copybook con questo nome nel manifesto"
        elif n["id"] == "external:~NON-RISOLTO":
            want_o = "CALL con bersaglio in variabile: il nome non e' un letterale e non e' risolto"
        elif "CALL" in kinds:
            want_o = "CALL: non e' un file del repository"
        elif "TRANSAZIONE_PROGRAMMA" in kinds:
            want_o = "transazione del CSD: programma non nel repository"
        else:
            want_o = "procedura non nel repository"
        if n.get("origine") != want_o:
            err(f"nodo {n['id']}: origine {n.get('origine')!r} diversa dalla regola ({want_o!r})")

for p in of_type("jcl", "proc"):
    cs = [c for c in cards[p] if c["scheda"] == "EXEC"]
    names = Counter(c["nome"] for c in cs)
    container = ("proc:" if TYPE_OF[p] == "proc" else "jcl-job:") + stem(p)
    want_f = "mapa" if lv.get(p) == "A" else "schede"
    for c in cs:
        st = step_by.get((p, int(c["passo"])))
        if not st:
            continue
        sname = c["nome"] if c["nome"] and names[c["nome"]] == 1 else f"{c['nome']}#{c['passo']}"
        want_n = ("proc." if TYPE_OF[p] == "proc" else "") + stem(p) + "/" + sname
        if st["nome"] != want_n or st["file"] != p or st["ordinale"] != int(c["passo"]) or st["riga"] != int(c["riga"]):
            err(f"nodo {st['id']}: nome/file/ordinale/riga ({st['nome']}, {st['file']}, {st['ordinale']}, {st['riga']}) diversi dalla scheda ({want_n}, {p}, {c['passo']}, {c['riga']})")
        if st.get("contenitore") != container:
            err(f"nodo {st['id']}: contenitore {st.get('contenitore')} diverso da {container}")
        if st.get("fonte") != want_f:
            err(f"nodo {st['id']}: fonte {st.get('fonte')} diversa da {want_f}")
        co = contain_occ.get((p, int(c["riga"])))
        if co and co[1]["fonte"] != want_f:
            err(f"{p}:{c['riga']}: fonte {co[1]['fonte']} dell'appartenenza al contenitore diversa da {want_f}")
        eo = exec_occ.get((p, int(c["riga"])))
        if eo and eo[1]["fonte"] != want_f:
            err(f"{p}:{c['riga']}: fonte {eo[1]['fonte']} dell'esecuzione diversa da {want_f}")
    mp = defaultdict(int)
    for c in cards[p]:
        if c["scheda"] != "DD":
            continue
        do = dd_occ.get((p, int(c["riga"])))
        if not do:
            continue
        e, o = do
        ordn = int(c["passo"])
        mrow = None
        if o["fonte"] == "mapa":
            rows = mapa_dd_rows[p].get(ordn, [])
            mrow = rows[mp[ordn]] if mp[ordn] < len(rows) else None
        mp[ordn] += 1
        risolto = mrow["dsn_risolto"] if mrow else ""
        gen, mem = gdg_parts(c, risolto)
        if o["classe"] != classe_of(c):
            err(f"{p}:{c['riga']}: classe {o['classe']} diversa dalla scheda ({classe_of(c)})")
        if o["gdg"] != (gen is not None) or o.get("generazione") != gen or o.get("membro") != mem:
            err(f"{p}:{c['riga']}: gdg/generazione/membro ({o['gdg']}, {o.get('generazione')}, {o.get('membro')}) diversi dal nome del dataset ({gen is not None}, {gen}, {mem})")
        if o["fonte"] != want_f:
            err(f"{p}:{c['riga']}: fonte DD {o['fonte']} diversa da {want_f}")
        ds_classes[e["a"]].add(classe_of(c))
for nid, cl in ds_classes.items():
    n = nodes.get(nid)
    if n and cl != {n.get("classe")}:
        err(f"nodo {nid}: classe {n.get('classe')} diversa da quella delle schede DD che lo usano ({sorted(cl)})")

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
            elif e["tipo"] == "CALL":
                det = o.get("operando", "")
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
