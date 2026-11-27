"""Struttura dei dati di un sorgente COBOL ricavata dal sorgente completo, indipendentemente dagli intervalli dichiarati nel
censimento (issue #3, giro 1 di validazione).

- confini di una radice: una voce di livello 01 (o 77) comprende tutte le frasi che la seguono fino alla prima frase che
  e' un'altra voce di livello 01/77, una FD/SD, una COPY, un'intestazione di sezione o di divisione; la sua ultima riga e'
  l'ultima riga di codice (non commento, non vuota) prima di quel confine;
- albero dei dati di un programma: voci della DATA DIVISION, con le COPY sostituite dalle voci del copybook, e per ogni voce
  il padre (per livello) e la radice;
- trasferimenti nella PROCEDURE DIVISION verso i record scritti: MOVE di una struttura intera (01 o gruppo) verso un record
  scritto o una sua parte; tutto il resto che scrive dentro un record scritto (MOVE di un campo o di un letterale,
  riferimenti con posizione, STRING, INITIALIZE, aritmetica) e' elencato come non coperto.
"""
import re

from comune import area_programma, frasi, parole

LIVELLI_RADICE = ("01", "1", "77")
RE_TESTATA = re.compile(r"\b(SECTION|DIVISION)\b")


def e_confine(testo):
    w = parole(testo.upper())
    if not w:
        return None
    if w[0] in LIVELLI_RADICE:
        return f"voce di livello {w[0]} {w[1] if len(w) > 1 else ''}".strip()
    if w[0] in ("FD", "SD", "COPY"):
        return f"{w[0]} {w[1] if len(w) > 1 else ''}".strip()
    if not w[0].isdigit() and RE_TESTATA.search(testo.upper()):
        return " ".join(w[:3])
    return None


def ultima_riga_codice(righe, prima_di):
    n = prima_di - 1
    while n >= 1:
        ind, t = area_programma(righe[n - 1])
        if ind not in "*/" and t.strip():
            return n
        n -= 1
    return n


def sezione_di(righe):
    """Mappa riga -> sezione (FILE, WORKING-STORAGE, LINKAGE, PROCEDURE, ...), in base alle intestazioni."""
    out, cur = {}, "-"
    ff = frasi(righe)
    for n, s in ff:
        m = re.match(r"^\s*([A-Z-]+)\s+(SECTION|DIVISION)\b", s.upper())
        if m and m.group(1) in ("FILE", "WORKING-STORAGE", "LINKAGE", "LOCAL-STORAGE", "PROCEDURE", "DATA"):
            cur = m.group(1)
        out[n] = cur
    return out


def estensione(righe, inizio):
    """(fine, confine) della radice che inizia alla riga 'inizio'; None se a quella riga non inizia una voce 01/77."""
    ff = frasi(righe)
    k = next((i for i, (n, s) in enumerate(ff) if n == inizio), None)
    if k is None or parole(ff[k][1])[:1] == [] or parole(ff[k][1])[0] not in LIVELLI_RADICE:
        return None
    for n, s in ff[k + 1:]:
        c = e_confine(s)
        if c:
            return ultima_riga_codice(righe, n), f"riga {n}: {c}"
    return ultima_riga_codice(righe, len(righe) + 1), "fine del file"


# ---------------------------------------------------------------- albero dei dati di un programma

class Voce:
    def __init__(self, nome, livello, riga, origine, padre):
        self.nome, self.livello, self.riga, self.origine, self.padre = nome, livello, riga, origine, padre
        self.figli = 0
        self.radice = self if padre is None else padre.radice

    def antenati(self):
        v = self
        while v is not None:
            yield v
            v = v.padre


def albero(righe, voci_copy, leggi_copy):
    """Voci della DATA DIVISION. leggi_copy(nome) -> lista di (livello, nome, riga) delle voci del copybook, o None."""
    voci, pila, dati = [], [], False
    for n, s in frasi(righe):
        su = s.upper()
        w = parole(su)
        if not w:
            continue
        if re.match(r"^\s*DATA\s+DIVISION\b", su):
            dati = True
            continue
        if re.match(r"^\s*PROCEDURE\s+DIVISION\b", su):
            break
        if not dati:
            continue
        if w[0] in ("FD", "SD") or (not w[0].isdigit() and RE_TESTATA.search(su)):
            pila = []
            continue
        if w[0] == "COPY":
            nome = w[1].rstrip(".")
            for liv, nm, r in (leggi_copy(nome) or []):
                pila = aggiungi(voci, pila, nm, liv, r, nome)
            continue
        if w[0].isdigit() and w[0] not in ("88", "66"):
            nm = parole(s)[1] if len(w) > 1 and w[1] not in ("PIC", "PICTURE", "REDEFINES", "OCCURS", "VALUE") else "FILLER"
            pila = aggiungi(voci, pila, nm.upper(), int(w[0]), n, "programma")
    return voci


def aggiungi(voci, pila, nome, livello, riga, origine):
    while pila and pila[-1].livello >= livello:
        pila.pop()
    padre = pila[-1] if pila else None
    v = Voce(nome, livello, riga, origine, padre)
    if padre:
        padre.figli += 1
    voci.append(v)
    return pila + [v]


# ---------------------------------------------------------------- trasferimenti nella PROCEDURE DIVISION

VERBI = {"MOVE", "WRITE", "READ", "REWRITE", "IF", "ELSE", "END-IF", "PERFORM", "END-PERFORM", "DISPLAY", "ADD", "SUBTRACT",
         "MULTIPLY", "DIVIDE", "COMPUTE", "SET", "STRING", "UNSTRING", "END-STRING", "END-UNSTRING", "INITIALIZE", "CALL",
         "OPEN", "CLOSE", "GO", "GOBACK", "STOP", "EVALUATE", "WHEN", "END-EVALUATE", "EXIT", "CONTINUE", "ACCEPT",
         "INSPECT", "END-READ", "END-WRITE", "END-REWRITE", "INVALID", "NOT", "AT", "ALTER", "SEARCH", "END-COMPUTE",
         "END-ADD", "END-SUBTRACT", "END-CALL", "ON", "OTHERWISE", "THEN", "UNTIL", "VARYING", "END-SEARCH", "START",
         "DELETE", "RETURN", "RELEASE", "SORT", "MERGE", "ROUNDED", "GIVING", "SIZE", "ERROR", "OVERFLOW", "EXCEPTION"}
FIGURATIVE = {"SPACE", "SPACES", "ZERO", "ZEROS", "ZEROES", "LOW-VALUE", "LOW-VALUES", "HIGH-VALUE", "HIGH-VALUES",
              "QUOTE", "QUOTES", "ALL", "NULL", "NULLS", "FUNCTION"}


def gettoni(righe):
    """Parole della PROCEDURE DIVISION con la riga: (riga, parola). I letterali diventano la parola LETTERALE;
    un riferimento con posizione o un indice '(...)' resta attaccato alla parola che lo precede."""
    out, attivo = [], False
    for n, r in enumerate(righe, 1):
        ind, t = area_programma(r)
        if ind in "*/":
            continue
        t = re.sub(r"'[^']*'?|\"[^\"]*\"?", " LETTERALE ", t).upper()
        if not attivo:
            if re.search(r"\bPROCEDURE\s+DIVISION\b", t):
                attivo = True
            continue
        t = re.sub(r"\s+\(", "(", t)
        for x in re.findall(r"[^\s]+", t):
            fine = x.endswith(".") and not re.match(r"^\d", x)
            x = x.rstrip(".,")
            if x:
                out.append((n, x))
            if fine:
                out.append((n, "."))
    return out


def destinazioni(toks, i):
    """Nomi di destinazione a partire da toks[i] fino al primo verbo o punto; salta le qualificazioni OF/IN."""
    out = []
    while i < len(toks) and toks[i][1] != "." and toks[i][1] not in VERBI:
        n, x = toks[i]
        if x in ("OF", "IN"):
            i += 2
            continue
        if x not in ("TO", "=", "CORR", "CORRESPONDING") and re.match(r"^[A-Z][A-Z0-9-]*(\(.*)?$", x):
            out.append((n, x))
        i += 1
    return out


def nome_base(x):
    return x.split("(", 1)[0]


def scansiona(righe, voci, scritti):
    """Restituisce (trasferimenti, non_coperti). scritti: nomi delle strutture che finiscono in un file (record delle
    WRITE/REWRITE e strutture delle WRITE/REWRITE ... FROM)."""
    per_nome = {}
    for v in voci:
        per_nome.setdefault(v.nome, []).append(v)

    def record_di(nome):
        for v in per_nome.get(nome_base(nome), []):
            for a in v.antenati():
                if a.nome in scritti:
                    return a.nome
        return None

    toks = gettoni(righe)
    trasf, nonc = [], []
    i = 0
    while i < len(toks):
        n, x = toks[i]
        if x == "MOVE":
            j = i + 1
            src = []
            while j < len(toks) and toks[j][1] != "TO" and toks[j][1] != ".":
                src.append(toks[j][1])
                j += 1
            for dn, d in destinazioni(toks, j + 1):
                rec = record_di(d)
                if rec is None:
                    continue
                s = src[0] if len(src) == 1 else " ".join(src)
                cand = per_nome.get(nome_base(s), []) if len(src) == 1 else []
                if len(src) != 1 or s in FIGURATIVE or s == "LETTERALE" or re.match(r"^[-+]?\d", s) or not cand:
                    nonc.append((n, "MOVE di un letterale o di un'espressione", " ".join(src), d, rec))
                elif "(" in s:
                    nonc.append((n, "MOVE con riferimento a posizione nella sorgente", s, d, rec))
                elif any(c.figli or c.livello in (1, 77) for c in cand):
                    v = next(c for c in cand if c.figli or c.livello in (1, 77))
                    trasf.append({"riga": n, "verbo": "MOVE", "sorgente": nome_base(s), "radice_sorgente": v.radice.nome,
                                  "destinazione": nome_base(d), "posizione_destinazione": "si" if "(" in d else "no",
                                  "record": rec})
                else:
                    nonc.append((n, "MOVE di un campo (composizione campo per campo)", s, d, rec))
            i = j
        elif x == "STRING" or x == "UNSTRING":
            j = i + 1
            while j < len(toks) and toks[j][1] not in ("INTO", ".", "END-STRING", "END-UNSTRING"):
                j += 1
            if j < len(toks) and toks[j][1] == "INTO":
                for dn, d in destinazioni(toks, j + 1)[:1 if x == "STRING" else 99]:
                    rec = record_di(d)
                    if rec:
                        nonc.append((n, x, "-", d, rec))
            i = j
        elif x == "INITIALIZE":
            for dn, d in destinazioni(toks, i + 1):
                rec = record_di(d)
                if rec:
                    nonc.append((n, "INITIALIZE", "-", d, rec))
            i += 1
        elif x in ("ADD", "SUBTRACT", "COMPUTE", "MULTIPLY", "DIVIDE"):
            j = i + 1
            if x == "COMPUTE":
                dd = []
                while j < len(toks) and toks[j][1] != "=":
                    if re.match(r"^[A-Z]", toks[j][1]) and toks[j][1] not in ("ROUNDED",):
                        dd.append((toks[j][0], toks[j][1]))
                    j += 1
            else:
                while j < len(toks) and toks[j][1] not in ("TO", "FROM", "GIVING", "BY", "INTO", ".") and toks[j][1] not in VERBI:
                    j += 1
                dd = destinazioni(toks, j + 1) if j < len(toks) and toks[j][1] in ("TO", "FROM", "GIVING", "BY", "INTO") else []
            for dn, d in dd:
                rec = record_di(d)
                if rec:
                    nonc.append((n, "aritmetica (" + x + ")", "-", d, rec))
            i = j
        else:
            i += 1
    return trasf, nonc
