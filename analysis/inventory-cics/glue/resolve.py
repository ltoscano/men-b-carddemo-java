"""Risoluzione degli operandi di bersaglio (colla). Tre stati: letterale, costante, non_risolto.

Regola (scritta anche in inventario-cics.md, sezione "Letterale, costante, variabile"):
* letterale: l'operando e' un solo letterale alfanumerico tra apici. Nome = contenuto senza gli spazi finali.
* costante: l'operando e' un solo nome di dato e, nel programma espanso con i suoi copybook (archi COPY del grafo di #2,
  REPLACING applicato come sostituzione di testo), valgono tutte: il blocco non sta in un copybook; nessuna COPY non
  risolta che possa definirlo; il nome e' definito una sola volta (livelli 01-49 e 77); sta in WORKING-STORAGE o
  LOCAL-STORAGE; ne' lui ne' un suo gruppo hanno OCCURS; ha una clausola VALUE con un letterale alfanumerico; nessuna
  istruzione lo modifica. Nome = contenuto del letterale della VALUE senza gli spazi finali.
* "modifica": ogni occorrenza, nella PROCEDURE DIVISION espansa, di un nome "collegato" che NON sta in uno di questi
  contesti di sola lettura. Collegati: tutti i dati la cui memoria puo' sovrapporsi a quella del dato, cioe' la chiusura
  transitiva che parte dal dato, dai suoi gruppi e dai suoi subordinati e aggiunge, per ogni REDEFINES che tocca un dato
  gia' raggiunto (come chi ridefinisce o come ridefinito), entrambi i dati con i loro gruppi e subordinati, finche' non si
  aggiunge piu' nulla; piu' i livelli 88 di ogni dato raggiunto e i 66 dei record raggiunti. Contesti di sola lettura:
    - argomento intero di una coppia comando/opzione dell'elenco READ_ONLY (argomenti che CICS legge e non scrive);
    - mittente di una MOVE (prima della parola TO);
    - dopo IF, EVALUATE, WHEN, UNTIL, DISPLAY, fino al verbo successivo.
  Tutto il resto conta come modifica (INITIALIZE, SET, CALL ... USING, READ ... INTO, STRING, COMPUTE, ogni altra
  opzione di EXEC CICS, ogni EXEC SQL/DLI, ...): e' una sovrastima voluta. Nel dubbio: non risolto.
* non_risolto: ogni altro caso, con il primo motivo che vale nell'ordine MOTIVI."""
import re

MOTIVI = ["in-copybook", "espressione", "valore-vuoto", "copy-non-risolta", "non-definito", "definito-piu-volte",
          "fuori-working-storage", "occurs", "senza-value-letterale", "modificato", "mapset-assente",
          "mapset-non-risolto", "tipo-coda-assente"]
# Coppie comando/opzione il cui argomento CICS legge soltanto (tipo "name" o "filename" nella sintassi IBM: e' il nome della
# risorsa da usare; "data-area" e' invece un campo in cui CICS puo' scrivere). Fonte: IBM CICS TS 6.x, pagine di sintassi
# https://www.ibm.com/docs/en/cics-ts/6.x?topic=summary-<comando> (xctl, link, start, return, send-map, receive-map, read,
# write, rewrite, delete, startbr, readnext, readprev, endbr, writeq-td, writeq-ts, readq-td, deleteq-ts) e la pagina
# "EXEC CICS command argument values". DATASET e' il nome storico di FILE negli stessi comandi: le pagine 6.x lette non lo
# citano (limite dichiarato in inventario-cics.md). Ogni coppia non elencata (ASSIGN PROGRAM, INQUIRE PROGRAM, INTO, SET,
# RIDFLD, LENGTH, RESP, COMMAREA, ABSTIME, ...) e' una possibile modifica.
FILE_CMDS = ("READ", "WRITE", "REWRITE", "DELETE", "STARTBR", "READNEXT", "READPREV", "ENDBR")
READ_ONLY = ({("XCTL", "PROGRAM"), ("LINK", "PROGRAM"), ("START", "TRANSID"), ("RETURN", "TRANSID"),
              ("SEND MAP", "MAP"), ("SEND MAP", "MAPSET"), ("RECEIVE MAP", "MAP"), ("RECEIVE MAP", "MAPSET"),
              ("WRITEQ TD", "QUEUE"), ("WRITEQ TS", "QUEUE"), ("READQ TD", "QUEUE"), ("DELETEQ TS", "QUEUE")}
             | {(c, o) for c in FILE_CMDS for o in ("FILE", "DATASET")})
QUALIFIER = {"SEND": {"MAP", "TEXT", "CONTROL", "PAGE"}, "RECEIVE": {"MAP"}, "WRITEQ": {"TD", "TS"}, "READQ": {"TD", "TS"},
             "DELETEQ": {"TD", "TS"}, "HANDLE": {"ABEND", "AID", "CONDITION"}, "IGNORE": {"CONDITION"},
             "SYNCPOINT": {"ROLLBACK"}, "INQUIRE": {"PROGRAM", "TRANSACTION", "FILE", "TERMINAL", "TASK"}}
READ_VERBS = {"IF", "EVALUATE", "WHEN", "UNTIL", "DISPLAY"}
VERBS = {"ACCEPT", "ADD", "ALTER", "CALL", "CANCEL", "CLOSE", "COMPUTE", "CONTINUE", "DELETE", "DISPLAY", "DIVIDE",
         "ENTRY", "EVALUATE", "EXIT", "GO", "GOBACK", "IF", "INITIALIZE", "INSPECT", "MERGE", "MOVE", "MULTIPLY", "OPEN",
         "PERFORM", "READ", "RELEASE", "RETURN", "REWRITE", "SEARCH", "SET", "SORT", "START", "STOP", "STRING",
         "SUBTRACT", "UNSTRING", "WRITE", "WHEN", "UNTIL", "VARYING", "ELSE",
         "END-IF", "END-EVALUATE", "END-PERFORM", "END-READ", "END-SEARCH", "END-STRING", "END-UNSTRING", "END-CALL",
         "END-COMPUTE", "END-ADD", "END-SUBTRACT", "END-MULTIPLY", "END-DIVIDE", "END-WRITE", "END-REWRITE",
         "END-DELETE", "END-START", "END-RETURN", "END-ACCEPT", "END-DISPLAY"}
IBM_COPY = ("DFH", "CMQ")        # copybook di sistema CICS / MQ non presenti nel repository
IBM_DATA = ("DFH", "MQ")         # prefissi dei soli nomi che quei copybook definiscono (documentazione IBM)
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*")
LIT = re.compile(r"'[^']*'|\"[^\"]*\"")


def literal_content(op):
    if LIT.fullmatch(op):
        return op[1:-1]
    return None


def code_of(line):
    """Area del codice (colonne 8-72) di una riga non commento, senza il commento in linea `*>`; None se commento."""
    if len(line) > 6 and line[6] in "*/":
        return None
    code = line[7:72]
    q = None
    for i, c in enumerate(code):
        if q:
            if c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == "*" and code[i + 1:i + 2] == ">":
            return code[:i]
    return code


def tokenize(code):
    """Token di una riga di codice: letterali interi, '(', ')', '.' separatore (seguito da spazio o fine riga), parole."""
    out, i, n = [], 0, len(code)
    while i < n:
        c = code[i]
        if c in " \t,;":
            i += 1
        elif c in "'\"":
            j = code.find(c, i + 1)
            j = n - 1 if j < 0 else j
            out.append(code[i:j + 1])
            i = j + 1
        elif c in "()":
            out.append(c)
            i += 1
        elif c == "." and (i + 1 >= n or code[i + 1] in " \t"):
            out.append(".")
            i += 1
        else:
            j = i
            while j < n and code[j] not in " \t,;'\"()" and not (code[j] == "." and (j + 1 >= n or code[j + 1] in " \t")):
                j += 1
            out.append(code[i:j])
            i = j
    return out


class Universe:
    """Il programma con i suoi copybook espansi (archi COPY del grafo di base)."""

    def __init__(self, prog, read_lines, copies, node_file):
        self.read_lines, self.copies, self.node_file = read_lines, copies, node_file
        self.unresolved = set()
        self.records = []          # (file, riga, codice)
        self._expand(prog, [], [prog])

    def _expand(self, path, repl, stack):
        lines = self.read_lines(path)
        by_line = {}
        for riga, target, subs in self.copies.get(path, []):
            by_line.setdefault(riga, []).append((target, subs))
        i = 0
        while i < len(lines):
            ln = i + 1
            code = code_of(lines[i])
            if code is not None:
                for da, a in repl:
                    code = code.replace(da, a)
            if ln in by_line and code is not None:
                m = re.search(r"(?<![A-Za-z0-9-])COPY(?![A-Za-z0-9-])", code.upper())
                if not m:
                    raise SystemExit(f"{path}:{ln}: il grafo di base indica una COPY ma la riga non la contiene")
                before = code[:m.start()]
                end_line, after = self._copy_end(lines, i, m.start(), repl)
                if before.strip():
                    self.records.append((path, ln, before))
                for target, subs in by_line[ln]:
                    f = self.node_file.get(target)
                    if f is None:
                        self.unresolved.add(target.split(":", 1)[1].upper())
                    elif f in stack:
                        raise SystemExit(f"COPY ricorsiva: {stack + [f]}")
                    else:
                        self._expand(f, [(s["da"], s["a"]) for s in subs], stack + [f])
                if after.strip():
                    self.records.append((path, end_line + 1, after))
                i = end_line + 1
                continue
            if code is not None:
                self.records.append((path, ln, code))
            i += 1

    def _copy_end(self, lines, i0, pos, repl):
        """Riga (indice) e testo che segue il punto che chiude l'istruzione COPY iniziata alla riga i0, colonna pos."""
        i, start, q, pseudo = i0, pos, None, False
        while i < len(lines):
            code = code_of(lines[i])
            if code is None:
                i += 1
                start = 0
                continue
            for da, a in repl:
                code = code.replace(da, a)
            k = start
            while k < len(code):
                c = code[k]
                if q:
                    if c == q:
                        q = None
                elif code.startswith("==", k):
                    pseudo = not pseudo
                    k += 2
                    continue
                elif not pseudo and c in "'\"":
                    q = c
                elif not pseudo and c == "." and (k + 1 >= len(code) or code[k + 1] in " \t"):
                    return i, code[k + 1:]
                k += 1
            i += 1
            start = 0
        raise SystemExit("istruzione COPY senza punto finale")


class Item:
    def __init__(self, level, name, section, file, line):
        self.level, self.name, self.section, self.file, self.line = level, name, section, file, line
        self.parent, self.children = None, []
        self.occurs = False
        self.redefines = None
        self.value = None          # (letterale, file, riga)


class Program:
    def __init__(self, universe):
        self.u = universe
        toks = []
        for f, ln, code in universe.records:
            for t in tokenize(code):
                toks.append((t, f, ln))
        up = [t.upper() for t, _, _ in toks]
        self.proc_start = None
        for k in range(len(up) - 1):
            if up[k] == "PROCEDURE" and up[k + 1] == "DIVISION":
                self.proc_start = k
                break
        data = toks[:self.proc_start] if self.proc_start is not None else toks
        self.items = self._data(data)
        self.proc = toks[self.proc_start:] if self.proc_start is not None else []

    def _data(self, toks):
        items, section, stack, entry = [], None, [], []
        k = 0
        while k < len(toks):
            t = toks[k][0].upper()
            if t == "EXEC":                     # EXEC SQL INCLUDE / DECLARE nella DATA DIVISION: si salta
                while k < len(toks) and toks[k][0].upper() != "END-EXEC":
                    k += 1
                k += 1
                entry = []
                continue
            if t == ".":
                self._entry(entry, items, stack, section)
                if len(entry) >= 2 and entry[-1][0].upper() == "SECTION":
                    section = entry[-2][0].upper()
                entry = []
            else:
                entry.append(toks[k])
            k += 1
        return items

    def _entry(self, entry, items, stack, section):
        if not entry or not re.fullmatch(r"\d{1,2}", entry[0][0]):
            return
        level = int(entry[0][0])
        words = [t for t, _, _ in entry]
        uw = [w.upper() for w in words]
        name = None
        if len(words) > 1 and NAME.fullmatch(words[1]) and uw[1] not in ("PIC", "PICTURE", "VALUE", "VALUES", "REDEFINES", "OCCURS", "USAGE", "COMP", "COMP-3", "BINARY", "PACKED-DECIMAL", "RENAMES"):
            name = uw[1]
        it = Item(level, name, section, entry[0][1], entry[1][2] if len(entry) > 1 else entry[0][2])
        if level == 88:
            parent = next((s for s in reversed(stack) if s.level != 88), None)
        elif level in (1, 77, 66):
            parent = None
            stack.clear()
        else:
            while stack and (stack[-1].level >= level or stack[-1].level == 88):
                stack.pop()
            parent = stack[-1] if stack else None
        if level == 66:
            parent = next((s for s in reversed(items) if s.level == 1), None)
        it.parent = parent
        if parent:
            parent.children.append(it)
        if "OCCURS" in uw:
            it.occurs = True
        if "REDEFINES" in uw:
            j = uw.index("REDEFINES")
            it.redefines = uw[j + 1] if j + 1 < len(uw) else None
        for j, w in enumerate(uw):
            if w in ("VALUE", "VALUES"):
                k = j + 1
                if k < len(uw) and uw[k] in ("IS", "ARE"):
                    k += 1
                if k < len(entry) and LIT.fullmatch(words[k]) and level != 88:
                    it.value = (words[k], entry[k][1], entry[k][2])
                break
        items.append(it)
        if level not in (66, 88):
            stack.append(it)

    # ------------------------------------------------------------------ relazioni
    @staticmethod
    def subtree(it):
        out, todo = [], [it]
        while todo:
            x = todo.pop()
            out.append(x)
            todo.extend(x.children)
        return out

    @staticmethod
    def ancestors(it):
        out, x = [], it
        while x:
            out.append(x)
            x = x.parent
        return out

    def related(self, it):
        """Nomi dei dati che possono sovrapporsi in memoria al dato (chiusura transitiva attraverso le REDEFINES)."""
        pairs = []
        for y in self.items:
            if y.redefines:
                pairs.extend((y, z) for z in self.items if z.name == y.redefines and z is not y)
        region = set(self.ancestors(it)) | set(self.subtree(it))
        grown = True
        while grown:
            grown = False
            for y, z in pairs:
                if y in region or z in region:
                    add = set(self.ancestors(y)) | set(self.subtree(y)) | set(self.ancestors(z)) | set(self.subtree(z))
                    if not add <= region:
                        region |= add
                        grown = True
        rel = set(region)
        for a in region:
            rel.update(c for c in a.children if c.level == 88)
        roots = {x for x in region if x.parent is None}
        rel.update(y for y in self.items if y.level == 66 and y.parent in roots)
        return {x.name for x in rel if x.name and x.name != "FILLER"}

    def modifications(self, names):
        """Occorrenze (file, riga) di un nome di `names` nella PROCEDURE DIVISION che non stanno in un contesto di sola lettura."""
        mods, toks, k = [], self.proc, 0
        last_verb, seen_to = None, False
        while k < len(toks):
            t, f, ln = toks[k]
            u = t.upper()
            if u == "EXEC":
                kind = toks[k + 1][0].upper() if k + 1 < len(toks) else ""
                j = k + 1
                block = []
                while j < len(toks) and toks[j][0].upper() != "END-EXEC":
                    block.append(toks[j])
                    j += 1
                if kind == "CICS":
                    mods.extend(self._cics_mods(block[1:], names))
                else:
                    mods.extend((bf, bl) for bt, bf, bl in block if bt.upper().lstrip(":") in names)
                k = j + 1
                last_verb, seen_to = None, False
                continue
            if u == ".":
                last_verb, seen_to = None, False
            elif u in VERBS:
                last_verb, seen_to = u, False
            elif u == "TO":
                seen_to = True
            elif u in names:
                if last_verb in READ_VERBS or (last_verb == "MOVE" and not seen_to):
                    pass
                else:
                    mods.append((f, ln))
            k += 1
        return mods

    @staticmethod
    def _cics_mods(block, names):
        words = [t.upper() for t, _, _ in block]
        cmd = words[0] if words else ""
        if len(words) > 1 and words[1] in QUALIFIER.get(cmd, ()):
            cmd = cmd + " " + words[1]
        mods, k = [], 0
        while k < len(block):
            t, f, ln = block[k]
            if t == "(":
                k += 1
                continue
            opt = t.upper()
            if k + 1 < len(block) and block[k + 1][0] == "(":
                depth, j, arg = 0, k + 1, []
                while j < len(block):
                    if block[j][0] == "(":
                        depth += 1
                        if depth > 1:
                            arg.append(block[j])
                    elif block[j][0] == ")":
                        depth -= 1
                        if depth == 0:
                            break
                        arg.append(block[j])
                    else:
                        arg.append(block[j])
                    j += 1
                whole = len(arg) == 1 and (cmd, opt) in READ_ONLY
                if not whole:
                    mods.extend((af, al) for at, af, al in arg if at.upper() in names)
                k = j + 1
            else:
                if opt in names:
                    mods.append((f, ln))
                k += 1
        return mods

    # ------------------------------------------------------------------ risoluzione
    def resolve(self, operand):
        """Ritorna un dizionario: risoluzione, e nome/valore/file_valore/riga_valore oppure motivo (e modifica)."""
        lit = literal_content(operand)
        if lit is not None:
            name = lit.rstrip(" ")
            if not name:
                return {"risoluzione": "non_risolto", "motivo": "valore-vuoto"}
            return {"risoluzione": "letterale", "nome": name}
        if not NAME.fullmatch(operand):
            return {"risoluzione": "non_risolto", "motivo": "espressione"}
        n = operand.upper()
        other = {c for c in self.u.unresolved if not c.startswith(IBM_COPY)}
        if other or (self.u.unresolved and n.startswith(IBM_DATA)):
            return {"risoluzione": "non_risolto", "motivo": "copy-non-risolta"}
        defs = [it for it in self.items if it.name == n and it.level not in (66, 88)]
        if not defs:
            return {"risoluzione": "non_risolto", "motivo": "non-definito"}
        if len(defs) > 1:
            return {"risoluzione": "non_risolto", "motivo": "definito-piu-volte"}
        it = defs[0]
        if it.section not in ("WORKING-STORAGE", "LOCAL-STORAGE"):
            return {"risoluzione": "non_risolto", "motivo": "fuori-working-storage"}
        if any(a.occurs for a in self.ancestors(it)):
            return {"risoluzione": "non_risolto", "motivo": "occurs"}
        if it.value is None:
            return {"risoluzione": "non_risolto", "motivo": "senza-value-letterale"}
        mods = self.modifications(self.related(it))
        if mods:
            return {"risoluzione": "non_risolto", "motivo": "modificato", "modifica": {"file": mods[0][0], "riga": mods[0][1]}}
        lit, vf, vl = it.value
        name = lit[1:-1].rstrip(" ")
        if not name:
            return {"risoluzione": "non_risolto", "motivo": "valore-vuoto"}
        return {"risoluzione": "costante", "nome": name, "valore": lit, "file_valore": vf, "riga_valore": vl}
