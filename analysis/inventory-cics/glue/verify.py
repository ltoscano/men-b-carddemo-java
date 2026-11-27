#!/usr/bin/env python3
"""Verifica di graph-cics.json contro fonti INDIPENDENTI dalla colla che l'ha prodotto.

Uso: verify.py GRAPH BASE AWK.tsv ATTESI SCHEMA MODO [INVENTARIO.md]
  GRAPH     graph-cics.json da verificare          BASE    graph.json di #2 (o quello dei file di prova)
  AWK.tsv   elenco dei blocchi di crosscheck.sh     ATTESI  cartella degli attesi scritti a mano
  SCHEMA    graph-cics.schema.json (copertura degli attributi)
  MODO      legacy | fixture (quali attesi sono obbligatori)
Il sorgente si legge da CICS_LEGACY (default /legacy), il manifesto da CICS_MANIFEST.

Non importa nulla dalla colla (extract.py, resolve.py, build.py): blocchi, comando, opzioni, categoria, modalita',
bersagli, stato di risoluzione, nomi, identificativi dei nodi e archi sono ricalcolati qui dal sorgente, con una
implementazione scritta a parte delle stesse regole dichiarate. Fonti di confronto:
  - l'elenco awk (altro linguaggio, altro criterio di lettura) per posizione, numero e comando di ogni blocco;
  - il sorgente, letto qui, per opzioni, operandi, VALUE e modifiche;
  - il grafo di base per i nodi program/transaction/external e gli archi COPY;
  - gli attesi scritti a mano per tutti i blocchi di quattro programmi e dei file di prova.
Ogni insieme si confronta come multinsieme nelle due direzioni (liste e Counter, mai dizionari che si sovrascrivono).
Stampa 'VERIFICA: ...' per ogni difetto ed esce con 1 se ce n'e' almeno uno."""
import json
import os
import re
import sys
from collections import Counter, defaultdict

LEGACY = os.environ.get("CICS_LEGACY", "/legacy")
MANIFEST = os.environ.get("CICS_MANIFEST", "/analysis/manifest/sources.tsv")
GRAPH, BASE, AWK, EXP, SCHEMA, MODE = sys.argv[1:7]
MD = sys.argv[7] if len(sys.argv) > 7 else None
errors = []


def err(msg):
    errors.append(msg)
    print("VERIFICA: " + msg)


# ---------------------------------------------------------------------- regole dichiarate (riscritte qui)
CAT = {"trasferimento": "XCTL LINK START RETURN", "mappe": "SEND MAP|RECEIVE MAP|SEND TEXT",
       "file": "READ WRITE REWRITE DELETE STARTBR READNEXT READPREV ENDBR RESETBR UNLOCK",
       "coda": "WRITEQ TD|WRITEQ TS|READQ TD|READQ TS|DELETEQ TD|DELETEQ TS|WRITEQ|READQ|DELETEQ",
       "transazione": "SYNCPOINT|SYNCPOINT ROLLBACK|ABEND"}
CATEGORY = {}
for k, v in CAT.items():
    for c in (v.split("|") if "|" in v else v.split()):
        CATEGORY[c] = k
QUALIFIERS = {"SEND": "MAP TEXT CONTROL PAGE", "RECEIVE": "MAP", "WRITEQ": "TD TS", "READQ": "TD TS", "DELETEQ": "TD TS",
              "HANDLE": "ABEND AID CONDITION", "IGNORE": "CONDITION", "SYNCPOINT": "ROLLBACK",
              "INQUIRE": "PROGRAM TRANSACTION FILE TERMINAL TASK"}
ROLE_OF = {"trasferimento": {"PROGRAM": "PROGRAM", "TRANSID": "TRANSID"}, "mappe": {"MAP": "MAP", "MAPSET": "MAPSET"},
           "file": {"FILE": "FILE", "DATASET": "FILE"}, "coda": {"QUEUE": "QUEUE", "QNAME": "QUEUE"}}
MODE_OF = {"READ": "lettura", "WRITE": "scrittura", "REWRITE": "riscrittura", "DELETE": "cancellazione",
           "STARTBR": "scorrimento-inizio", "READNEXT": "scorrimento-avanti", "READPREV": "scorrimento-indietro",
           "ENDBR": "scorrimento-fine", "RESETBR": "scorrimento-riposizionamento", "UNLOCK": "rilascio"}
WHOLE_ARG_OPTS = {"PROGRAM", "TRANSID", "MAP", "MAPSET", "FILE", "DATASET", "QUEUE", "QNAME"}
READ_CONTEXT = {"IF", "EVALUATE", "WHEN", "UNTIL", "DISPLAY"}
BOUNDARY = set("ACCEPT ADD ALTER CALL CANCEL CLOSE COMPUTE CONTINUE DELETE DISPLAY DIVIDE ENTRY EVALUATE EXIT GO GOBACK IF "
               "INITIALIZE INSPECT MERGE MOVE MULTIPLY OPEN PERFORM READ RELEASE RETURN REWRITE SEARCH SET SORT START STOP "
               "STRING SUBTRACT UNSTRING WRITE WHEN UNTIL VARYING ELSE END-IF END-EVALUATE END-PERFORM END-READ END-SEARCH "
               "END-STRING END-UNSTRING END-CALL END-COMPUTE END-ADD END-SUBTRACT END-MULTIPLY END-DIVIDE END-WRITE "
               "END-REWRITE END-DELETE END-START END-RETURN END-ACCEPT END-DISPLAY".split())
ORDER = ["in-copybook", "espressione", "valore-vuoto", "copy-non-risolta", "non-definito", "definito-piu-volte",
         "fuori-working-storage", "occurs", "senza-value-letterale", "modificato"]
ORIGIN = {"PROGRAM": "EXEC CICS PROGRAM: programma non presente nel grafo di base",
          "TRANSID": "EXEC CICS TRANSID: transazione non presente nel grafo di base"}
DATANAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*$")
QUOTED = re.compile(r"""^(?:'([^']*)'|"([^"]*)")$""")

# Ogni attributo dello schema e come lo si verifica qui. Uno nuovo nello schema e non elencato fa fallire il controllo.
ATTRS = {
    "radice": {"versione_schema": "costante 1", "descrizione": "testo libero (nessuna fonte canonica: limite)",
               "grafo_base": "costante dello schema", "estrattore": "testo libero (limite)", "nodi": "vedi nodo",
               "occorrenze": "vedi occorrenza", "archi": "vedi arco"},
    "nodo": {"id": "ricavato dal bersaglio ricalcolato; unico; non in graph.json", "tipo": "prefisso dell'id",
             "nome": "parte finale dell'id", "mapset": "parte dell'id di cics-map", "tipo_coda": "parte dell'id di cics-queue",
             "origine": "ruolo degli archi entranti"},
    "opzione": {"nome": "sorgente (parser riscritto qui)", "argomento": "sorgente (parser riscritto qui)"},
    "bersaglio": {"ruolo": "categoria + opzione", "opzione": "sorgente", "operando": "sorgente",
                  "risoluzione": "regola ricalcolata", "nome": "letterale o VALUE nel sorgente",
                  "valore": "letterale della VALUE nel sorgente", "file_valore": "posizione della VALUE nel sorgente",
                  "riga_valore": "posizione della VALUE nel sorgente", "motivo": "primo motivo ricalcolato",
                  "modifica": "deve essere una modifica secondo la regola ricalcolata"},
    "occorrenza": {"id": "occ:file:riga:colonna", "file": "elenco awk", "riga": "elenco awk", "riga_fine": "elenco awk",
                   "colonna": "elenco awk", "da": "manifesto + grafo di base", "comando": "elenco awk e sorgente",
                   "categoria": "tabella dichiarata", "opzioni": "sorgente", "bersagli": "ricalcolati",
                   "modalita": "comando + UPDATE nel sorgente", "update": "UPDATE nel sorgente",
                   "tipo_coda": "TD/TS nel sorgente"},
    "arco": {"id": "occorrenza#ruolo", "occorrenza": "occorrenza esistente", "da": "da dell'occorrenza",
             "a": "bersaglio ricalcolato (tipo e nome)", "ruolo": "bersaglio ricalcolato", "comando": "comando dell'occorrenza"},
}

# ---------------------------------------------------------------------- input
g = json.load(open(GRAPH, encoding="utf-8"))
base = json.load(open(BASE, encoding="utf-8"))
schema = json.load(open(SCHEMA, encoding="utf-8"))
man = []
with open(MANIFEST, encoding="utf-8") as fh:
    next(fh)
    for line in fh:
        p, t = line.rstrip("\n").split("\t")
        if t in ("cobol", "copybook"):
            man.append((p, t))
KIND = dict(man)
base_ids = Counter(n["id"] for n in base["nodi"])
base_node = {n["id"]: n for n in base["nodi"]}
_src_cache = {}


def src(path):
    if path not in _src_cache:
        with open(os.path.join(LEGACY, path), encoding="latin-1", newline="") as fh:
            _src_cache[path] = [l.rstrip("\r") for l in fh.read().split("\n")]
    return _src_cache[path]


def is_comment(line):
    return len(line) > 6 and line[6] in "*/"


def cut_inline(code):
    q = None
    for i, c in enumerate(code):
        if q:
            q = None if c == q else q
        elif c in "'\"":
            q = c
        elif code[i:i + 2] == "*>":
            return code[:i]
    return code


# ---------------------------------------------------------------------- 0. attesi obbligatori, copertura dello schema
REQ = {"legacy": ["blocchi_COSGN00C", "blocchi_COACTUPC", "blocchi_COCRDLIC", "blocchi_COPAUS1C", "totali"],
       "fixture": ["blocchi_FIXCICS", "blocchi_FIXCPY", "blocchi_FIXCOPY2", "blocchi_FIXTGT", "conteggi"]}[MODE]
for r in REQ:
    if not os.path.isfile(os.path.join(EXP, r + ".tsv")):
        err(f"manca il file degli attesi a mano {r}.tsv")
if errors:
    sys.exit(1)
sch_attrs = {"radice": set(schema["properties"])}
for d in ("nodo", "opzione", "bersaglio", "occorrenza", "arco"):
    sch_attrs[d] = set(schema["$defs"][d]["properties"])
for d, s in sch_attrs.items():
    for a in sorted(s - set(ATTRS[d])):
        err(f"attributo dello schema non coperto: {d}.{a}")
    for a in sorted(set(ATTRS[d]) - s):
        err(f"attributo coperto ma assente dallo schema: {d}.{a}")
if g.get("versione_schema") != 1 or g.get("grafo_base") != "docs/legacy-map/graph.json":
    err("versione_schema o grafo_base diversi dalle costanti")

# ---------------------------------------------------------------------- 1. risposta del conteggio indipendente (awk)
awk_rows, awk_ok = [], True
lines = open(AWK, encoding="utf-8").read().split("\n")
if not lines or lines[-1] != "":
    err("elenco awk troncato (manca il fine riga finale)")
    awk_ok = False
lines = [l for l in lines if l != ""]
if not lines or not re.fullmatch(r"fine\t\d+", lines[-1]) or int(lines[-1].split("\t")[1]) != len(man):
    err(f"elenco awk incompleto: la chiusura non dichiara i {len(man)} file letti ({lines[-1] if lines else 'vuoto'!r})")
    awk_ok = False
for l in lines[:-1]:
    f = l.split("\t")
    if f[0] == "errore":
        err(f"conteggio awk: {l}")
    elif f[0] == "blocco" and len(f) == 6 and f[1] in KIND and all(x.isdigit() for x in f[2:5]):
        awk_rows.append((f[1], int(f[2]), int(f[3]), int(f[4]), f[5]))
    else:
        err(f"elenco awk: riga non riconoscibile {l[:80]!r}")
        awk_ok = False

# ---------------------------------------------------------------------- 2. unicita' (prima di qualunque indice)
occs, arcs, nodes = g["occorrenze"], g["archi"], g["nodi"]
for k, n in Counter(o["id"] for o in occs).items():
    if n > 1:
        err(f"occorrenza {k}: presente {n} volte")
for k, n in Counter((o["file"], o["riga"], o["colonna"]) for o in occs).items():
    if n > 1:
        err(f"due occorrenze nella stessa posizione {k}")
for k, n in Counter(a["id"] for a in arcs).items():
    if n > 1:
        err(f"arco {k}: presente {n} volte")
for k, n in Counter(nd["id"] for nd in nodes).items():
    if n > 1:
        err(f"nodo {k}: presente {n} volte")
for nd in nodes:
    if nd["id"] in base_ids:
        err(f"nodo {nd['id']}: dichiarato in graph-cics.json ma esiste gia' in graph.json")

# ---------------------------------------------------------------------- 3. blocchi: grafo contro conteggio indipendente
got = Counter((o["file"], o["riga"], o["colonna"], o["riga_fine"], o["comando"]) for o in occs)
want = Counter(awk_rows)
for k in sorted(set(want) | set(got)):
    if got[k] != want[k]:
        err(f"blocco {k[0]}:{k[1]} col {k[2]} (fine {k[3]}, {k[4]}): nel grafo {got[k]}, nel conteggio indipendente {want[k]}")
per_file_g, per_file_a = Counter(o["file"] for o in occs), Counter(r[0] for r in awk_rows)
for p, _ in man:
    if per_file_g[p] != per_file_a[p]:
        err(f"{p}: blocchi nel grafo {per_file_g[p]}, conteggio indipendente sul sorgente {per_file_a[p]}")
cmd_g, cmd_a = Counter(o["comando"] for o in occs), Counter(r[4] for r in awk_rows)
for c in sorted(set(cmd_g) | set(cmd_a)):
    if cmd_g[c] != cmd_a[c]:
        err(f"comando {c}: occorrenze nel grafo {cmd_g[c]}, conteggio indipendente {cmd_a[c]}")


# ---------------------------------------------------------------------- 4. testo del blocco dal sorgente, opzioni
def block_text(o):
    """Testo tra CICS e END-EXEC letto qui dal sorgente (colonne 8-72, righe di commento e `*>` esclusi)."""
    L = src(o["file"])
    if not (1 <= o["riga"] <= o["riga_fine"] <= len(L)):
        return None, "righe fuori dal file"
    parts = []
    for n in range(o["riga"], o["riga_fine"] + 1):
        line = L[n - 1]
        if is_comment(line):
            if n == o["riga"]:
                return None, "la riga di EXEC e' un commento"
            continue
        code = cut_inline(line[7:72])
        if n == o["riga"]:
            off = o["colonna"] - 8
            m = re.match(r"EXEC\s+CICS(?![A-Za-z0-9-])", code[off:], re.I) if off >= 0 else None
            if not m and n == o["riga_fine"]:
                return None, f"alla colonna {o['colonna']} non c'e' EXEC CICS"
            if not m:
                m2 = re.match(r"EXEC\s*$", code[off:], re.I) if off >= 0 else None
                if not m2:
                    return None, f"alla colonna {o['colonna']} non c'e' EXEC CICS"
                parts.append("\x00EXEC-A-CAPO")
                continue
            code = code[off + m.end():]
        parts.append(code)
    text = "\n".join(parts)
    if text.startswith("\x00EXEC-A-CAPO\n"):
        m = re.match(r"\s*CICS(?![A-Za-z0-9-])", text[len("\x00EXEC-A-CAPO\n"):], re.I)
        if not m:
            return None, "EXEC non seguito da CICS"
        text = text[len("\x00EXEC-A-CAPO\n") + m.end():]
    ends = [m.start() for m in re.finditer(r"(?<![A-Za-z0-9-])END-EXEC(?![A-Za-z0-9-])", mask(text), re.I)]
    if not ends:
        return None, f"END-EXEC non trovato entro la riga {o['riga_fine']}"
    last_nl = text.rfind("\n")
    if ends[0] < last_nl:
        return None, f"il primo END-EXEC viene prima della riga {o['riga_fine']}"
    return text[:ends[0]], None


def mask(t):
    out, q = [], None
    for c in t:
        if q:
            out.append("#")
            q = None if c == q else q
        elif c in "'\"":
            q = c
            out.append("#")
        else:
            out.append(c)
    return "".join(out)


def options_of(text):
    """Parole e argomenti tra parentesi (bilanciate, letterali rispettati); argomento con gli spazi fuori dai letterali
    ridotti a uno e gli estremi tolti."""
    res, pos = [], 0
    word = re.compile(r"\s*([A-Za-z0-9][A-Za-z0-9-]*)")
    while True:
        m = word.match(text, pos)
        if not m:
            if text[pos:].strip():
                return None
            return res
        name, pos = m.group(1).upper(), m.end()
        m2 = re.compile(r"\s*\(").match(text, pos)
        if not m2:
            res.append((name, None))
            continue
        depth, k, q, buf = 1, m2.end(), None, []
        while k < len(text) and depth:
            c = text[k]
            if q:
                q = None if c == q else q
            elif c in "'\"":
                q = c
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            if depth:
                buf.append(c)
            k += 1
        if depth:
            return None
        arg = "".join(buf)
        pieces = re.split(r"('[^']*'|\"[^\"]*\")", arg)
        arg = "".join(p if i % 2 else re.sub(r"\s+", " ", p) for i, p in enumerate(pieces)).strip()
        res.append((name, arg))
        pos = k


# ---------------------------------------------------------------------- 5. programma espanso, dati, modifiche (riscritti)
copy_occ = defaultdict(list)
for e in base["archi"]:
    if e["tipo"] == "COPY":
        for oc in e["occorrenze"]:
            copy_occ[oc["file"]].append((oc["riga"], e["a"], [(s["da"], s["a"]) for s in oc.get("sostituzioni", [])]))


def expanded(path, subs=(), chain=()):
    """Righe di codice (file, riga, testo) del file con i copybook inseriti al posto delle istruzioni COPY."""
    out, missing = [], set()
    raw = src(path)
    code = []
    for n, line in enumerate(raw, 1):
        if is_comment(line):
            continue
        t = cut_inline(line[7:72])
        for a, b in subs:
            t = t.replace(a, b)
        code.append((n, t))
    at = defaultdict(list)
    for riga, target, s in copy_occ.get(path, []):
        at[riga].append((target, s))
    idx = 0
    while idx < len(code):
        n, t = code[idx]
        if n not in at:
            out.append((path, n, t))
            idx += 1
            continue
        joined, spans = "", []
        for j in range(idx, len(code)):
            spans.append((len(joined), j))
            joined += code[j][1] + "\n"
        m = re.search(r"(?i)(?<![A-Za-z0-9-])COPY\s+(?:'[^']*'|\"[^\"]*\"|[A-Za-z0-9-]+).*?\.(?=\s)", joined, re.S)
        if not m or m.start() >= len(code[idx][1]) + 1:
            raise SystemExit(f"VERIFICA: {path}:{n}: COPY del grafo di base non trovata nel sorgente")
        end_j = max(j for off, j in spans if off <= m.end() - 1)
        end_off = next(off for off, j in spans if j == end_j)
        if t[:m.start()].strip():
            out.append((path, n, t[:m.start()]))
        for target, s in at[n]:
            f = base_node.get(target, {}).get("file") if target.startswith("copybook:") else None
            if f is None:
                missing.add(target.split(":", 1)[1].upper())
            elif f in chain:
                raise SystemExit(f"VERIFICA: COPY ricorsiva {chain}")
            else:
                sub_out, sub_missing = expanded(f, s, chain + (f,))
                out.extend(sub_out)
                missing |= sub_missing
        rest = code[end_j][1][m.end() - end_off:]
        if rest.strip():
            out.append((path, code[end_j][0], rest))
        idx = end_j + 1
    return out, missing


TOKEN = re.compile(r"""'[^']*'?|"[^"]*"?|[()]|\.(?=\s|$)|[^\s(),;'"]+?(?=\.(?:\s|$)|[\s(),;'"]|$)""")


class Prog:
    def __init__(self, path):
        lines, self.missing = expanded(path, (), (path,))
        self.toks = []
        for f, n, t in lines:
            for m in TOKEN.finditer(t):
                self.toks.append((m.group(), f, n))
        U = [x[0].upper() for x in self.toks]
        self.pd = next((i for i in range(len(U) - 1) if U[i] == "PROCEDURE" and U[i + 1] == "DIVISION"), len(U))
        self.U = U
        self.entries = []
        self._data()

    def _data(self):
        section, cur, i = None, [], 0
        while i < self.pd:
            u = self.U[i]
            if u == "EXEC":
                while i < self.pd and self.U[i] != "END-EXEC":
                    i += 1
                cur = []
                i += 1
                continue
            if u == ".":
                words = [self.U[k] for k in cur]
                if len(words) == 2 and words[1] == "SECTION":
                    section = words[0]
                elif words and re.fullmatch(r"\d\d?", words[0]):
                    self.entries.append(self._entry(cur, section))
                cur = []
            else:
                cur.append(i)
            i += 1
        stack = []
        for e in self.entries:
            lv = e["level"]
            if lv in (1, 77):
                stack = [e]
                e["parent"] = None
            elif lv == 66:
                e["parent"] = stack[0] if stack else None
            elif lv == 88:
                e["parent"] = stack[-1] if stack else None
            else:
                while stack and stack[-1]["level"] >= lv:
                    stack.pop()
                e["parent"] = stack[-1] if stack else None
                stack.append(e)

    def _entry(self, idxs, section):
        T = [self.toks[k] for k in idxs]
        W = [self.U[k] for k in idxs]
        e = {"level": int(W[0]), "name": None, "section": section, "occurs": "OCCURS" in W, "value": None, "redef": None}
        clause = {"PIC", "PICTURE", "VALUE", "VALUES", "REDEFINES", "OCCURS", "USAGE", "COMP", "COMP-3", "BINARY",
                  "PACKED-DECIMAL", "RENAMES"}
        if len(W) > 1 and DATANAME.match(T[1][0]) and W[1] not in clause:
            e["name"] = W[1]
        if "REDEFINES" in W and W.index("REDEFINES") + 1 < len(W):
            e["redef"] = W[W.index("REDEFINES") + 1]
        for j, w in enumerate(W):
            if w in ("VALUE", "VALUES"):
                k = j + 1 + (1 if j + 1 < len(W) and W[j + 1] in ("IS", "ARE") else 0)
                if e["level"] != 88 and k < len(T) and QUOTED.match(T[k][0]):
                    e["value"] = T[k]
                break
        return e

    def chain(self, e):
        out = []
        while e is not None:
            out.append(e)
            e = e["parent"]
        return out

    def below(self, e):
        return [x for x in self.entries if e in self.chain(x)]

    def linked_names(self, e):
        up = self.chain(e)
        core = up + self.below(e)
        ids = {id(x) for x in core}
        group = list(core) + [c for a in up for c in self.entries if c["level"] == 88 and c["parent"] is a]
        core_names = {x["name"] for x in core if x["name"]}
        for y in self.entries:
            if y["redef"] and y["redef"] in core_names:
                group += self.below(y)
        for x in core:
            if x["redef"]:
                for z in self.entries:
                    if z["name"] == x["redef"]:
                        group += self.below(z)
        group += [y for y in self.entries if y["level"] == 66 and y["parent"] is up[-1]]
        del ids
        return {x["name"] for x in group if x["name"] and x["name"] != "FILLER"}

    def changes(self, names):
        """Posizioni (file, riga) delle occorrenze dei nomi fuori dai contesti di sola lettura (scansione all'indietro)."""
        out, U, T = set(), self.U, self.toks
        blocks, i = [], self.pd
        while i < len(U):
            if U[i] == "EXEC":
                j = i
                while j < len(U) and U[j] != "END-EXEC":
                    j += 1
                blocks.append((i, j))
                i = j
            i += 1
        block_of = {}
        for a, b in blocks:
            for k in range(a, b + 1):
                block_of[k] = (a, b)
        for i in range(self.pd, len(U)):
            name = U[i].lstrip(":")
            if name not in names:
                continue
            if i in block_of:
                a, b = block_of[i]
                if a + 1 <= b and U[a + 1] == "CICS" and U[i - 1] == "(" and i + 1 < len(U) and U[i + 1] == ")" \
                        and U[i - 2] in WHOLE_ARG_OPTS and not U[i].startswith(":"):
                    continue
                out.add((T[i][1], T[i][2]))
                continue
            k, saw_to, ok = i - 1, False, False
            while k >= self.pd:
                if k in block_of or U[k] == ".":
                    break
                if U[k] == "TO":
                    saw_to = True
                if U[k] in BOUNDARY:
                    ok = U[k] in READ_CONTEXT or (U[k] == "MOVE" and not saw_to)
                    break
                k -= 1
            if not ok:
                out.add((T[i][1], T[i][2]))
        return out


_progs = {}


def prog(path):
    if path not in _progs:
        _progs[path] = Prog(path)
    return _progs[path]


def classify(path, kind, operand):
    """Ritorna (risoluzione, nome, extra) secondo la regola dichiarata, ricalcolata qui."""
    m = QUOTED.match(operand)
    if m:
        name = (m.group(1) if m.group(1) is not None else m.group(2)).rstrip(" ")
        return ("letterale", name, {}) if name else ("non_risolto", None, {"motivo": "valore-vuoto"})
    if kind == "copybook":
        return "non_risolto", None, {"motivo": "in-copybook"}
    if not DATANAME.match(operand):
        return "non_risolto", None, {"motivo": "espressione"}
    P, N = prog(path), operand.upper()
    if any(not c.startswith(("DFH", "CMQ")) for c in P.missing) or (P.missing and N.startswith(("DFH", "MQ"))):
        return "non_risolto", None, {"motivo": "copy-non-risolta"}
    defs = [e for e in P.entries if e["name"] == N and e["level"] not in (66, 88)]
    if not defs:
        return "non_risolto", None, {"motivo": "non-definito"}
    if len(defs) > 1:
        return "non_risolto", None, {"motivo": "definito-piu-volte"}
    e = defs[0]
    if e["section"] not in ("WORKING-STORAGE", "LOCAL-STORAGE"):
        return "non_risolto", None, {"motivo": "fuori-working-storage"}
    if any(x["occurs"] for x in P.chain(e)):
        return "non_risolto", None, {"motivo": "occurs"}
    if e["value"] is None:
        return "non_risolto", None, {"motivo": "senza-value-letterale"}
    ch = P.changes(P.linked_names(e))
    if ch:
        return "non_risolto", None, {"motivo": "modificato", "modifiche": ch}
    lit, vf, vl = e["value"]
    name = lit[1:-1].rstrip(" ")
    if not name:
        return "non_risolto", None, {"motivo": "valore-vuoto"}
    return "costante", name, {"valore": lit, "file_valore": vf, "riga_valore": vl}


# ---------------------------------------------------------------------- 6. ogni occorrenza ricalcolata dal sorgente
required_arcs = Counter()      # (occorrenza, ruolo, a) ricalcolati qui
declared_arcs = Counter()      # (occorrenza, ruolo, a) dai bersagli risolti del grafo
target_roles = defaultdict(set)
occ_by_id = {}
recomputed = []                # (file, riga, colonna, comando, categoria, modalita'/coda, bersagli) ricalcolati qui
for o in occs:
    occ_by_id.setdefault(o["id"], o)
    p = o["file"]
    where = f"{p}:{o['riga']}"
    if o["id"] != f"occ:{p}:{o['riga']}:{o['colonna']}":
        err(f"{where}: id {o['id']} diverso da occ:file:riga:colonna")
    kind = KIND.get(p)
    if kind is None:
        err(f"{where}: file non nel manifesto come programma o copybook")
        continue
    stem = os.path.splitext(os.path.basename(p))[0].upper()
    want_da = ("program:" if kind == "cobol" else "copybook:") + stem
    if o["da"] != want_da or want_da not in base_ids:
        err(f"{where}: da {o['da']}, atteso {want_da} (presente in graph.json: {want_da in base_ids})")
    text, why = block_text(o)
    if text is None:
        err(f"{where}: il sorgente non contiene il blocco dichiarato ({why})")
        continue
    opts = options_of(text)
    if not opts or opts[0][1] is not None:
        err(f"{where}: testo del blocco non riconoscibile dal parser di verifica")
        continue
    cmd = opts[0][0]
    if len(opts) > 1 and opts[1][0] in QUALIFIERS.get(cmd, "").split():
        cmd += " " + opts[1][0]
    opts = opts[1:]
    if o["comando"] != cmd:
        err(f"{where}: comando {o['comando']!r}, nel sorgente {cmd!r}")
    have_opts = [(x.get("nome"), x.get("argomento")) for x in o["opzioni"]]
    if have_opts != opts:
        err(f"{where}: opzioni {have_opts} diverse dal sorgente {opts}")
    cat = CATEGORY.get(cmd, "altro")
    if o["categoria"] != cat:
        err(f"{where}: categoria {o['categoria']!r}, per il comando {cmd} e' {cat!r}")
    names = [k for k, _ in opts]
    if cat == "file":
        upd = "UPDATE" in names
        if o.get("update") is not upd:
            err(f"{where}: update {o.get('update')!r}, nel sorgente UPDATE {'presente' if upd else 'assente'}")
        if o.get("modalita") != MODE_OF.get(cmd.split()[0], "?") + ("-update" if upd else ""):
            err(f"{where}: modalita {o.get('modalita')!r} incoerente con {cmd} e UPDATE {'presente' if upd else 'assente'}")
    elif "modalita" in o or "update" in o:
        err(f"{where}: modalita/update su un comando che non e' sui file")
    qtype = ("TD" if "TD" in names else "TS" if "TS" in names else "assente") if cat == "coda" else None
    if o.get("tipo_coda") != qtype:
        err(f"{where}: tipo_coda {o.get('tipo_coda')!r}, nel sorgente {qtype!r}")
    # bersagli ricalcolati
    roles = ROLE_OF.get(cat, {})
    mine = []
    for k, v in opts:
        if k in roles and v is not None:
            res, nm, extra = classify(p, kind, v)
            mine.append({"ruolo": roles[k], "opzione": k, "operando": v, "risoluzione": res, "nome": nm, **extra})
    by_role = defaultdict(list)
    for t in mine:
        by_role[t["ruolo"]].append(t)
    for t in by_role.get("MAP", []):
        if t["risoluzione"] != "non_risolto":
            ms = by_role.get("MAPSET", [])
            why2 = "mapset-assente" if not ms else None if ms[0]["risoluzione"] != "non_risolto" else "mapset-non-risolto"
            if why2:
                t.update({"risoluzione": "non_risolto", "nome": None, "motivo": why2})
                for k in ("valore", "file_valore", "riga_valore"):
                    t.pop(k, None)
    for t in by_role.get("QUEUE", []):
        if t["risoluzione"] != "non_risolto" and qtype == "assente":
            t.update({"risoluzione": "non_risolto", "nome": None, "motivo": "tipo-coda-assente"})
            for k in ("valore", "file_valore", "riga_valore"):
                t.pop(k, None)
    have = o["bersagli"]
    if [(t["ruolo"], t["opzione"], t["operando"]) for t in have] != [(t["ruolo"], t["opzione"], t["operando"]) for t in mine]:
        err(f"{where}: bersagli {[(t['ruolo'], t['opzione'], t['operando']) for t in have]} diversi dal sorgente "
            f"{[(t['ruolo'], t['opzione'], t['operando']) for t in mine]}")
        continue
    for h, m in zip(have, mine):
        tag = f"{where}: {h['ruolo']} {h['operando']}"
        if h["risoluzione"] != m["risoluzione"]:
            err(f"{tag}: risoluzione {h['risoluzione']!r}, per la regola dichiarata {m['risoluzione']!r}"
                + (f" ({m['motivo']})" if m.get("motivo") else ""))
            continue
        if m["risoluzione"] == "non_risolto":
            if h.get("motivo") != m["motivo"]:
                err(f"{tag}: motivo {h.get('motivo')!r}, per la regola dichiarata {m['motivo']!r}")
            if m["motivo"] == "modificato":
                loc = h.get("modifica") or {}
                if (loc.get("file"), loc.get("riga")) not in m["modifiche"]:
                    err(f"{tag}: la modifica citata {loc} non e' una modifica secondo la regola")
            for k in ("nome", "valore", "file_valore", "riga_valore"):
                if k in h:
                    err(f"{tag}: attributo {k} su un bersaglio non risolto")
        else:
            if h.get("nome") != m["nome"]:
                err(f"{tag}: nome {h.get('nome')!r}, nel sorgente {m['nome']!r}")
            for k in ("valore", "file_valore", "riga_valore"):
                if h.get(k) != m.get(k):
                    err(f"{tag}: {k} {h.get(k)!r}, nel sorgente {m.get(k)!r}")
            if "motivo" in h or "modifica" in h:
                err(f"{tag}: motivo su un bersaglio risolto")
    # archi richiesti: dal bersaglio ricalcolato qui (tipo e nome), e dai bersagli dichiarati nel grafo
    for m in mine:
        if m["risoluzione"] == "non_risolto":
            continue
        r, nm = m["ruolo"], m["nome"]
        if r == "PROGRAM":
            a = ("program:" if "program:" + nm in base_ids else "external:") + nm
        elif r == "TRANSID":
            a = ("transaction:" if "transaction:" + nm in base_ids else "external:") + nm
        elif r == "MAPSET":
            a = "cics-mapset:" + nm
        elif r == "MAP":
            a = f"cics-map:{by_role['MAPSET'][0]['nome']}/{nm}"
        elif r == "FILE":
            a = "cics-file:" + nm
        else:
            a = f"cics-queue:{qtype}/{nm}"
        required_arcs[(o["id"], r, a)] += 1
        target_roles[a].add(r)
        m["target"] = a
    for h in have:
        if h["risoluzione"] in ("letterale", "costante"):
            declared_arcs[(o["id"], h["ruolo"])] += 1
    extra = (" " + MODE_OF[cmd] + ("-update" if "UPDATE" in names else "")) if cat == "file" else (" " + qtype) if cat == "coda" else ""
    recomputed.append((p, o["riga"], o["colonna"], cmd, cat, extra, mine))

# ---------------------------------------------------------------------- 7. archi nelle due direzioni, nodi
present = Counter()
present_roles = Counter()
for a in arcs:
    o = occ_by_id.get(a["occorrenza"])
    if o is None:
        err(f"arco {a['id']}: l'occorrenza {a['occorrenza']} non esiste")
        continue
    if a["id"] != f"{a['occorrenza']}#{a['ruolo']}":
        err(f"arco {a['id']}: id diverso da occorrenza#ruolo")
    if a["da"] != o["da"] or a["comando"] != o["comando"]:
        err(f"arco {a['id']}: da/comando ({a['da']}, {a['comando']}) diversi dall'occorrenza ({o['da']}, {o['comando']})")
    present[(a["occorrenza"], a["ruolo"], a["a"])] += 1
    present_roles[(a["occorrenza"], a["ruolo"])] += 1
for k in sorted(set(required_arcs) | set(present)):
    if required_arcs[k] != present[k]:
        err(f"arco {k[1]} {k[0]} -> {k[2]}: richiesto dal sorgente {required_arcs[k]}, presente nel grafo {present[k]}")
for k in sorted(set(declared_arcs) | set(present_roles)):
    if declared_arcs[k] != present_roles[k]:
        err(f"occorrenza {k[0]} ruolo {k[1]}: bersagli risolti nel grafo {declared_arcs[k]}, archi {present_roles[k]}")
new = {}
for nd in nodes:
    new.setdefault(nd["id"], nd)
incoming = defaultdict(set)
for a in arcs:
    incoming[a["a"]].add(a["ruolo"])
    if a["a"] not in base_ids and a["a"] not in new:
        err(f"arco {a['id']}: il nodo {a['a']} non esiste ne' in graph.json ne' in graph-cics.json")
for nid, nd in new.items():
    if not incoming.get(nid):
        err(f"nodo {nid}: nessun arco entrante")
    tipo, rest = nid.split(":", 1)
    want = {"id": nid, "tipo": tipo}
    if tipo == "cics-map":
        want["mapset"], want["nome"] = rest.split("/", 1)
    elif tipo == "cics-queue":
        want["tipo_coda"], want["nome"] = rest.split("/", 1)
    else:
        want["nome"] = rest
    if tipo == "external":
        rl = incoming.get(nid, set())
        if len(rl) != 1:
            err(f"nodo {nid}: archi entranti con ruoli diversi {sorted(rl)}")
        want["origine"] = ORIGIN.get(next(iter(rl)), "?") if rl else "?"
    if nd != want:
        err(f"nodo {nid}: attributi {nd} diversi da quelli ricavati dall'identificativo e dagli archi {want}")
for a, rl in target_roles.items():
    if a not in base_ids and a not in new:
        err(f"bersaglio {a} richiesto dal sorgente ma nodo assente")

# ---------------------------------------------------------------------- 8. attesi scritti a mano
arcs_by_occ = defaultdict(list)
for a in arcs:
    arcs_by_occ[a["occorrenza"]].append(a)


def row(o):
    att = "modalita=" + o["modalita"] if "modalita" in o else "tipo_coda=" + o["tipo_coda"] if "tipo_coda" in o else "-"
    op = " | ".join(x["nome"] + (f"({x['argomento']})" if "argomento" in x else "") for x in o["opzioni"]) or "-"
    bs = []
    for t in o["bersagli"]:
        s = f"{t['ruolo']}={t['opzione']}({t['operando']}) {t['risoluzione']}"
        if t["risoluzione"] != "non_risolto":
            s += " " + str(t.get("nome"))
        if t["risoluzione"] == "costante":
            s += f" @{t.get('file_valore')}:{t.get('riga_valore')}"
        if t["risoluzione"] == "non_risolto":
            s += " !" + str(t.get("motivo"))
        bs.append(s)
    ar = " | ".join(a["ruolo"] + ">" + a["a"] for a in arcs_by_occ.get(o["id"], [])) or "-"
    return "\t".join([o["file"], str(o["riga"]), str(o["riga_fine"]), o["comando"], o["categoria"], att, op, " | ".join(bs) or "-", ar])


HDR = "file\triga\triga_fine\tcomando\tcategoria\tattributi\topzioni\tbersagli\tarchi"
for fn in sorted(x for x in os.listdir(EXP) if x.startswith("blocchi_") and x.endswith(".tsv")):
    rows = open(os.path.join(EXP, fn), encoding="utf-8").read().split("\n")
    if rows[0] != HDR or rows[-1] != "":
        err(f"{fn}: intestazione o fine riga finale non validi")
        continue
    rows = rows[1:-1]
    target = os.path.splitext(fn)[0][len("blocchi_"):]
    files = [p for p, _ in man if os.path.splitext(os.path.basename(p))[0].upper() == target]
    if len(files) != 1:
        err(f"{fn}: il programma {target} non e' (una sola volta) nel manifesto")
        continue
    gotrows = [row(o) for o in sorted((o for o in occs if o["file"] == files[0]), key=lambda o: (o["riga"], o["colonna"]))]
    for i in range(max(len(rows), len(gotrows))):
        a = rows[i] if i < len(rows) else None
        b = gotrows[i] if i < len(gotrows) else None
        if a != b:
            err(f"{fn}: riga {i + 1}: atteso {a!r}, nel grafo {b!r}")
if MODE == "legacy":
    tot = {}
    for l in open(os.path.join(EXP, "totali.tsv"), encoding="utf-8").read().split("\n")[1:]:
        if l:
            k, v = l.split("\t")
            tot[k] = int(v)
    base_mod = lambda p: p.startswith("app/cbl/") or p.startswith("app/cpy/")
    counted = {"blocchi": len(awk_rows), "file_con_blocchi": len({r[0] for r in awk_rows}),
               "blocchi_nei_copybook": sum(1 for r in awk_rows if KIND[r[0]] == "copybook"),
               "blocchi_base": sum(1 for r in awk_rows if base_mod(r[0])),
               "blocchi_moduli_opzionali": sum(1 for r in awk_rows if not base_mod(r[0]))}
    for k in sorted(set(tot) | set(counted)):
        if tot.get(k) != counted.get(k):
            err(f"totali: {k} scritto a mano {tot.get(k)}, conteggio indipendente {counted.get(k)}")
else:
    exp_counts = {}
    for l in open(os.path.join(EXP, "conteggi.tsv"), encoding="utf-8").read().split("\n")[1:]:
        if l:
            k, v = l.split("\t")
            exp_counts[k] = int(v)
    for p, _ in man:
        if exp_counts.get(p) != per_file_a[p]:
            err(f"conteggi.tsv: {p} scritto a mano {exp_counts.get(p)}, conteggio indipendente {per_file_a[p]}")

# ---------------------------------------------------------------------- 9. affermazioni di inventario-cics.md
if MD:
    md = open(MD, encoding="utf-8").read()
    files_with = sorted({r[0] for r in awk_rows})
    line = f"- blocchi `EXEC CICS`: **{len(awk_rows)}** in **{len(files_with)}** file"
    if line not in md:
        err(f"inventario-cics.md: manca o e' diversa la riga dei totali ({line!r})")
    # bersagli non risolti: ricalcolati qui, non letti dal grafo
    unres = Counter((p, r, cmd, t["ruolo"], t["operando"], t["motivo"]) for p, r, c, cmd, cat, ex, mine in recomputed
                    for t in mine if t["risoluzione"] == "non_risolto")
    table = Counter((f, int(r), c, ru, op, mo) for f, r, c, ru, op, mo in
                    re.findall(r"^\| (app/\S+) \| (\d+) \| `([^`]+)` \| (\w+) \| `([^`]*)` \| ([a-z-]+) \|$", md, re.M))
    if table != unres:
        err(f"inventario-cics.md: tabella dei bersagli non risolti diversa dal ricalcolo: in piu' {sorted(table - unres)[:3]}, "
            f"mancano {sorted(unres - table)[:3]}")
    # comandi trovati: dal conteggio awk e dalla tabella delle categorie
    rows_cmd = Counter({(c, k): int(n) for c, k, n in re.findall(r"^\| `([A-Z0-9 -]+)` \| ([a-z]+) \| (\d+) \|$", md, re.M)})
    want_cmd = Counter({(c, CATEGORY.get(c, "altro")): n for c, n in cmd_a.items()})
    if rows_cmd != want_cmd:
        err(f"inventario-cics.md: tabella dei comandi diversa dal conteggio indipendente: {sorted((rows_cmd - want_cmd) | (want_cmd - rows_cmd))[:4]}")
    # totali sui file e sui RETURN TRANSID
    ft = [t for p, r, c, cmd, cat, ex, mine in recomputed if cat == "file" for t in mine]
    nf = sum(1 for x in recomputed if x[4] == "file")
    want_f = (f"- comandi sui file: {nf}, con nome di file costante {sum(t['risoluzione'] == 'costante' for t in ft)}, "
              f"letterale {sum(t['risoluzione'] == 'letterale' for t in ft)}, non risolto {sum(t['risoluzione'] == 'non_risolto' for t in ft)};")
    rt = [t for p, r, c, cmd, cat, ex, mine in recomputed if cmd == "RETURN" for t in mine]
    want_r = (f"- `RETURN` con `TRANSID`: {len(rt)}, costante {sum(t['risoluzione'] == 'costante' for t in rt)}, "
              f"letterale {sum(t['risoluzione'] == 'letterale' for t in rt)}, non risolto {sum(t['risoluzione'] == 'non_risolto' for t in rt)};")
    for want_line in (want_f, want_r):
        if want_line not in md.split("\n"):
            err(f"inventario-cics.md: manca o e' diversa la riga {want_line!r}")
    # per programma: ogni voce ricalcolata qui (blocchi propri e ereditati dai copybook con gli archi COPY di graph.json)
    def item(prog_path, x):
        p, r, c, cmd, cat, ex, mine = x
        where = f"{r}" if p == prog_path else f"{p}:{r}"
        tg = "; ".join(f"{t['ruolo']} `{t['target']}` ({t['risoluzione']})" if t["risoluzione"] != "non_risolto"
                       else f"{t['ruolo']} `{t['operando']}` non risolto ({t['motivo']})" for t in mine) or "nessun bersaglio"
        return f"  - riga {where}: `{cmd}`{ex}: {tg}"
    by_src = defaultdict(list)
    for x in recomputed:
        by_src[x[0]].append(x)
    includes = defaultdict(dict)   # programma -> {id del copybook: file}, in ordine di id come nel riepilogo
    for p0, lst in copy_occ.items():
        for riga, target, s in lst:
            f = base_node.get(target, {}).get("file") if target.startswith("copybook:") else None
            if f:
                includes[p0][target] = f
    sections = {}
    for mm in re.finditer(r"^### `([A-Z0-9-]+)` \((app/\S+)\)\n(.*?)(?=^### |^## )", md, re.M | re.S):
        sections[mm.group(2)] = mm.group(3)
    want_sections = set()
    for p, kind in man:
        if kind != "cobol":
            continue
        xs = sorted(by_src.get(p, []), key=lambda x: (x[1], x[2])) + \
             [x for c in sorted(includes.get(p, {})) for x in sorted(by_src.get(includes[p][c], []), key=lambda x: (x[1], x[2]))]
        if not xs:
            continue
        want_sections.add(p)
        body = sections.get(p)
        if body is None:
            err(f"inventario-cics.md: manca la sezione del programma {p}")
            continue
        want_items = Counter(item(p, x) for x in xs if x[4] in ("trasferimento", "mappe", "file", "coda"))
        have_items = Counter(l for l in body.split("\n") if l.startswith("  - riga "))
        if want_items != have_items:
            err(f"inventario-cics.md: {p}: voci diverse dal ricalcolo: in piu' {sorted(have_items - want_items)[:2]}, mancano {sorted(want_items - have_items)[:2]}")
        sp = [f"{x[1]} (`{x[3]}`)" for x in xs if x[4] == "transazione"]
        sp_line = f"- `SYNCPOINT`, rollback e `ABEND`: righe {', '.join(sp)}" if sp else None
        have_sp = [l for l in body.split("\n") if l.startswith("- `SYNCPOINT`")]
        if have_sp != ([sp_line] if sp_line else []):
            err(f"inventario-cics.md: {p}: riga dei punti di SYNCPOINT diversa dal ricalcolo ({have_sp} / {sp_line!r})")
    for p in sorted(set(sections) - want_sections):
        err(f"inventario-cics.md: sezione del programma {p} senza blocchi")

if errors:
    print(f"VERIFICA FALLITA: {len(errors)} difetti")
    sys.exit(1)
print(f"verifica superata: {len(occs)} occorrenze, {len(arcs)} archi, {len(nodes)} nodi nuovi; "
      f"{len(awk_rows)} blocchi nel conteggio indipendente")
