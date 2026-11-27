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


# Verbi COBOL: una frase o istruzione termina al punto, al verbo che apre l'istruzione successiva o a un terminatore esplicito.
VERBI = {"MOVE", "WRITE", "READ", "REWRITE", "IF", "ELSE", "END-IF", "PERFORM", "END-PERFORM", "DISPLAY", "ADD", "SUBTRACT",
         "MULTIPLY", "DIVIDE", "COMPUTE", "SET", "STRING", "UNSTRING", "END-STRING", "END-UNSTRING", "INITIALIZE", "CALL",
         "OPEN", "CLOSE", "GO", "GOBACK", "STOP", "EVALUATE", "WHEN", "END-EVALUATE", "EXIT", "CONTINUE", "ACCEPT",
         "INSPECT", "END-READ", "END-WRITE", "END-REWRITE", "INVALID", "NOT", "AT", "ALTER", "SEARCH", "END-COMPUTE",
         "END-ADD", "END-SUBTRACT", "END-MULTIPLY", "END-DIVIDE", "END-CALL", "ON", "OTHERWISE", "THEN", "UNTIL",
         "VARYING", "END-SEARCH", "START", "DELETE", "RETURN", "RELEASE", "SORT", "MERGE"}
# Parole chiave che possono stare dentro un'istruzione: non sono nomi di dati.
CHIAVI = VERBI | {"TO", "FROM", "GIVING", "BY", "INTO", "ROUNDED", "OF", "IN", "AND", "OR", "IS", "THAN", "EQUAL", "GREATER",
                  "LESS", "DELIMITED", "SIZE", "ERROR", "OVERFLOW", "EXCEPTION", "CORR", "CORRESPONDING", "WITH", "POINTER",
                  "TRUE", "FALSE", "ALSO", "REMAINDER"}
FIGURATIVE = {"SPACE", "SPACES", "ZERO", "ZEROS", "ZEROES", "LOW-VALUE", "LOW-VALUES", "HIGH-VALUE", "HIGH-VALUES",
              "QUOTE", "QUOTES", "ALL", "NULL", "NULLS", "FUNCTION"}
RE_GETTONE = re.compile(r"\d+\.\d+|[A-Z0-9][A-Z0-9-]*[A-Z0-9]|[A-Z0-9]|\*\*|[=+*/()<>:,]|-|\.")


def gettoni(righe):
    """Elementi della PROCEDURE DIVISION, ciascuno con la riga: (riga, testo). Nomi, numeri, operatori e parentesi sono
    elementi separati; i letterali diventano l'elemento LETTERALE; il punto di fine frase e' l'elemento '.'."""
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
        for x in RE_GETTONE.findall(t):
            out.append((n, x))
    return out


def nome_dati(x):
    return re.match(r"^[A-Z][A-Z0-9-]*$", x) is not None and x not in CHIAVI and x != "LETTERALE"


def operandi(toks, i, fermati=()):
    """Operandi da toks[i] fino al punto, a un verbo o a una parola in 'fermati'. Ogni operando: (riga, nome, posizione),
    dove posizione e' True se il nome e' seguito da '(...)' (indice o riferimento a posizione), che viene consumato.
    Le qualificazioni OF/IN saltano il nome che segue. Ritorna (operandi, indice dove ci si e' fermati)."""
    out = []
    while i < len(toks):
        n, x = toks[i]
        if x == "." or x in VERBI or x in fermati:
            break
        if x in ("OF", "IN"):
            i += 2
            continue
        if nome_dati(x) or x == "LETTERALE" or re.match(r"^\d", x):
            pos = False
            if i + 1 < len(toks) and toks[i + 1][1] == "(" and nome_dati(x):
                prof, k = 0, i + 1
                while k < len(toks):
                    if toks[k][1] == "(":
                        prof += 1
                    elif toks[k][1] == ")":
                        prof -= 1
                        if prof == 0:
                            break
                    elif toks[k][1] in (".",) or toks[k][1] in VERBI:
                        break
                    k += 1
                pos, i = True, k
            out.append((n, x, pos))
        i += 1
    return out, i


def nome_base(x):
    return x.split("(", 1)[0]


def scansiona(righe, voci, scritti):
    """Restituisce (trasferimenti, non_coperti). scritti: nomi delle strutture che finiscono in un file (record delle
    WRITE/REWRITE e strutture delle WRITE/REWRITE ... FROM). Ogni istruzione si analizza solo fino al suo termine."""
    per_nome = {}
    for v in voci:
        per_nome.setdefault(v.nome, []).append(v)

    def record_di(nome):
        for v in per_nome.get(nome, []):
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
            src, j = operandi(toks, i + 1, fermati=("TO",))
            grezzi = [t for _, t in toks[i + 1:j]]
            if j < len(toks) and toks[j][1] == "TO":
                dd, j = operandi(toks, j + 1)
            else:
                dd = []
            for _, d, dpos in dd:
                rec = record_di(d)
                if rec is None:
                    continue
                s = " ".join(grezzi)
                if len(src) != 1 or src[0][1] == "LETTERALE" or src[0][1] in FIGURATIVE or re.match(r"^\d", src[0][1]) \
                        or "FUNCTION" in grezzi or not per_nome.get(src[0][1]):
                    nonc.append((n, "MOVE di un letterale o di un'espressione", s, d, rec))
                elif src[0][2]:
                    nonc.append((n, "MOVE con riferimento a posizione nella sorgente", s, d, rec))
                elif any(c.figli or c.livello in (1, 77) for c in per_nome[src[0][1]]):
                    v = next(c for c in per_nome[src[0][1]] if c.figli or c.livello in (1, 77))
                    trasf.append({"riga": n, "verbo": "MOVE", "sorgente": src[0][1], "radice_sorgente": v.radice.nome,
                                  "destinazione": d, "posizione_destinazione": "si" if dpos else "no", "record": rec})
                else:
                    nonc.append((n, "MOVE di un campo (composizione campo per campo)", s, d, rec))
            i = max(j, i + 1)
        elif x in ("STRING", "UNSTRING"):
            _, j = operandi(toks, i + 1, fermati=("INTO", "END-STRING", "END-UNSTRING"))
            if j < len(toks) and toks[j][1] == "INTO":
                dd, j = operandi(toks, j + 1, fermati=("DELIMITER", "COUNT", "TALLYING", "END-STRING", "END-UNSTRING"))
                for _, d, _p in dd[:1 if x == "STRING" else len(dd)]:
                    rec = record_di(d)
                    if rec:
                        nonc.append((n, x, "-", d, rec))
            i = max(j, i + 1)
        elif x == "INITIALIZE":
            dd, j = operandi(toks, i + 1, fermati=("REPLACING",))
            for _, d, _p in dd:
                rec = record_di(d)
                if rec:
                    nonc.append((n, "INITIALIZE", "-", d, rec))
            i = max(j, i + 1)
        elif x in ("ADD", "SUBTRACT", "COMPUTE", "MULTIPLY", "DIVIDE"):
            if x == "COMPUTE":
                dd, j = operandi(toks, i + 1, fermati=("=", "EQUAL"))
                if not (j < len(toks) and toks[j][1] in ("=", "EQUAL")):
                    dd = []
            else:
                _, j = operandi(toks, i + 1, fermati=("TO", "FROM", "GIVING", "BY", "INTO"))
                dd = []
                while j < len(toks) and toks[j][1] in ("TO", "FROM", "GIVING", "BY", "INTO"):
                    altri, j = operandi(toks, j + 1, fermati=("TO", "FROM", "GIVING", "BY", "INTO"))
                    # in ADD/SUBTRACT ... TO/FROM ... sono destinazioni gli operandi dopo TO, FROM (SUBTRACT) e GIVING;
                    # in MULTIPLY/DIVIDE quelli dopo BY/INTO (senza GIVING) e dopo GIVING
                    dd += [a for a in altri if nome_dati(a[1])]
            for _, d, _p in dd:
                rec = record_di(d)
                if rec:
                    nonc.append((n, "aritmetica (" + x + ")", "-", d, rec))
            i = max(j, i + 1)
        else:
            i += 1
    return trasf, nonc
