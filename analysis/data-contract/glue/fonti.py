#!/usr/bin/env python3
"""Estrazione testuale minima e dichiarata dai sorgenti legacy (issue #3). Non sostituisce cb2xml: serve a
dargli in pasto i frammenti dei programmi e a mettere a confronto le fonti delle chiavi.

Uso:
  fonti.py frammenti LEGACY MANIFEST CENSIMENTO OUTDIR
      Scrive OUTDIR/frag/<id>.cbl (righe copiate verbatim dal programma, intervallo dichiarato nel censimento)
      e OUTDIR/lavori.tsv (id, sorgente, percorso dell'input visto dal container di cb2xml).
  fonti.py estrai LEGACY MANIFEST CENSIMENTO OUTDIR
      Scrive in OUTDIR: programmi.tsv, select.tsv, fd.tsv, io.tsv, define.tsv, listcat.tsv, voci.tsv.

Cosa si estrae e come (tutto riga per riga, senza interpretare la semantica):
  - programmi batch: programmi COBOL di app/cbl/ (dal manifesto) il cui codice non contiene EXEC CICS;
  - SELECT (FILE-CONTROL): ASSIGN, ORGANIZATION, ACCESS MODE, RECORD KEY, ALTERNATE RECORD KEY [WITH DUPLICATES];
  - FD (FILE SECTION): RECORDING MODE, RECORD CONTAINS, RECORD VARYING ... DEPENDING ON, radici 01 o COPY;
  - istruzioni READ/WRITE/REWRITE della PROCEDURE DIVISION con INTO/FROM (stessa riga o riga seguente) e
    MOVE <struttura> TO <01 di un FD del programma> (stessa riga);
  - DEFINE CLUSTER/ALTERNATEINDEX/PATH dei JCL (istruzioni IDCAMS in SYSIN *): NAME, KEYS, RECORDSIZE,
    UNIQUEKEY/NONUNIQUEKEY, RELATE, PATHENTRY, INDEXED/NONINDEXED/NUMBERED;
  - LISTCAT.txt: per ogni componente DATA, KEYLEN, RKP, AXRKP, AVGLRECL, MAXLRECL, NONUNIQKEY, l'associazione;
  - voci: livello, nome, PIC, USAGE, OCCURS, REDEFINES di ogni voce dei sorgenti dati dati a cb2xml, nell'ordine
    del sorgente (serve a confrontare nomi, ordine e PIC dei contratti con il sorgente).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comune import (area_programma, frasi, leggi_righe, leggi_tsv, parole, scrivi_tsv,  # noqa: E402
                    senza_letterali, stem)

RE_INTERVALLO = re.compile(r"^(\d+)-(\d+)$")


def copybook_del_manifesto(manifesto):
    return [r["path"] for r in leggi_tsv(manifesto)
            if r["type"] == "copybook" and r["path"].startswith("app/cpy/")]


def programmi_cobol(manifesto):
    return [r["path"] for r in leggi_tsv(manifesto) if r["type"] == "cobol" and r["path"].startswith("app/cbl/")]


def lavori(legacy, manifesto, censimento):
    """Elenco degli input di cb2xml: tutti i copybook di app/cpy/ e i frammenti dichiarati nel censimento."""
    out = []
    for p in copybook_del_manifesto(manifesto):
        out.append({"id": stem(p), "sorgente": p, "righe": "-", "input": "/legacy/" + p})
    for r in leggi_tsv(censimento):
        m = RE_INTERVALLO.match(r["frammento"])
        if not m:
            continue
        ident = stem(r["sorgente"]) + "." + r["radice"]
        out.append({"id": ident, "sorgente": r["sorgente"], "righe": r["frammento"], "input": f"/frag/{ident}.cbl"})
    ids = [x["id"] for x in out]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    if dup:
        raise SystemExit(f"identificativi duplicati tra gli input di cb2xml: {dup}")
    return out


def cmd_frammenti(legacy, manifesto, censimento, outdir):
    os.makedirs(os.path.join(outdir, "frag"), exist_ok=True)
    jobs = lavori(legacy, manifesto, censimento)
    for j in jobs:
        if j["righe"] == "-":
            continue
        a, b = map(int, RE_INTERVALLO.match(j["righe"]).groups())
        righe = leggi_righe(os.path.join(legacy, j["sorgente"]))
        if not (1 <= a <= b <= len(righe)):
            raise SystemExit(f"{j['id']}: intervallo {a}-{b} fuori dal file ({len(righe)} righe)")
        with open(os.path.join(outdir, "frag", j["id"] + ".cbl"), "w", encoding="latin-1", newline="\n") as f:
            for r in righe[a - 1:b]:
                f.write(r + "\n")
    scrivi_tsv(os.path.join(outdir, "lavori.tsv"), ["id", "sorgente", "righe", "input"], jobs)


# ---------------------------------------------------------------- programmi

def codice(righe):
    """Testo del codice (colonne 8-72, commenti esclusi, letterali svuotati), una voce per riga."""
    out = []
    for r in righe:
        ind, t = area_programma(r)
        out.append("" if ind in "*/" else senza_letterali(t))
    return out


def riga_di(righe_codice, regex, da=1):
    for n in range(da, len(righe_codice) + 1):
        if re.search(regex, righe_codice[n - 1]):
            return n
    return None


def valore_dopo(w, i, saltare=("IS", "ARE", "TO", "MODE", "ON")):
    j = i + 1
    while j < len(w) and w[j] in saltare:
        j += 1
    return w[j] if j < len(w) else "-"


def estrai_select(prog, righe, cod):
    a = riga_di(cod, r"\bFILE-CONTROL\b")
    b = riga_di(cod, r"\bDATA\s+DIVISION\b")
    out = []
    if not a or not b:
        return out
    for n, s in frasi(righe, a, b - 1):
        w = parole(s.upper())
        if not w or w[0] != "SELECT":
            continue
        rec = {"programma": prog, "riga": n, "file": w[1], "assign": "-", "organizzazione": "SEQUENTIAL",
               "accesso": "SEQUENTIAL", "chiave": "-", "alternativa": "-", "duplicati": "-"}
        for i, x in enumerate(w):
            if x == "ASSIGN":
                rec["assign"] = valore_dopo(w, i)
            elif x == "ORGANIZATION":
                rec["organizzazione"] = valore_dopo(w, i)
            elif x == "ACCESS":
                rec["accesso"] = valore_dopo(w, i)
            elif x == "KEY" and i > 0 and w[i - 1] == "RECORD" and (i < 2 or w[i - 2] != "ALTERNATE"):
                rec["chiave"] = valore_dopo(w, i)
            elif x == "ALTERNATE":
                k = i + 1
                while k < len(w) and w[k] in ("RECORD", "KEY", "IS"):
                    k += 1
                rec["alternativa"] = w[k] if k < len(w) else "-"
                rec["duplicati"] = "WITH DUPLICATES" if "DUPLICATES" in w[k:k + 4] else "no"
        out.append(rec)
    return out


def estrai_fd(prog, righe, cod):
    a = riga_di(cod, r"\bFILE\s+SECTION\b")
    b = riga_di(cod, r"\bWORKING-STORAGE\s+SECTION\b")
    out = []
    if not a or not b:
        return out
    cur = None
    for n, s in frasi(righe, a + 1, b - 1):
        w = parole(s.upper())
        if not w:
            continue
        if w[0] in ("FD", "SD"):
            cur = {"programma": prog, "fd": w[1], "riga": n, "registrazione": "-", "contiene": "-",
                   "varia_da": "-", "varia_a": "-", "dipende_da": "-", "radici": []}
            for i, x in enumerate(w):
                if x == "RECORDING":
                    cur["registrazione"] = valore_dopo(w, i)
                elif x == "CONTAINS":
                    cur["contiene"] = w[i + 1]
                elif x == "FROM" and "VARYING" in w:
                    cur["varia_da"] = w[i + 1]
                elif x == "TO" and "VARYING" in w and i + 1 < len(w) and w[i + 1].isdigit():
                    cur["varia_a"] = w[i + 1]
                elif x == "DEPENDING":
                    cur["dipende_da"] = valore_dopo(w, i)
            out.append(cur)
        elif cur is not None and w[0] in ("01", "1"):
            cur["radici"].append(f"{w[1]}@{n}")
        elif cur is not None and w[0] == "COPY":
            cur["radici"].append(f"COPY:{w[1]}@{n}")
    for r in out:
        r["radici"] = ",".join(r["radici"]) or "-"
    return out


RE_IO = re.compile(r"(?<![A-Z0-9-])(READ|WRITE|REWRITE)\s+([A-Z0-9][A-Z0-9-]*)(?:\s+RECORD)?(?:\s+(INTO|FROM)\s+([A-Z0-9][A-Z0-9-]*))?")


RE_MOVE = re.compile(r"(?<![A-Z0-9-])MOVE\s+([A-Z0-9][A-Z0-9-]*)\s+TO\s+([A-Z0-9][A-Z0-9-]*)")
FIGURATIVE = {"SPACE", "SPACES", "ZERO", "ZEROS", "ZEROES", "LOW-VALUE", "LOW-VALUES", "HIGH-VALUE", "HIGH-VALUES", "QUOTE", "QUOTES"}


def estrai_io(prog, cod, radici_fd=()):
    a = riga_di(cod, r"\bPROCEDURE\s+DIVISION\b")
    out = []
    if not a:
        return out
    for n in range(a + 1, len(cod) + 1):
        t = cod[n - 1].upper()
        for m in RE_IO.finditer(t):
            verbo, obj, prep, struct = m.groups()
            if prep is None:
                # INTO/FROM sulla riga di codice seguente
                k = n + 1
                while k <= len(cod) and not cod[k - 1].strip():
                    k += 1
                if k <= len(cod):
                    m2 = re.match(r"\s*(INTO|FROM)\s+([A-Z0-9][A-Z0-9-]*)", cod[k - 1].upper())
                    if m2:
                        prep, struct = m2.groups()
            out.append({"programma": prog, "riga": n, "verbo": verbo, "oggetto": obj,
                        "prep": prep or "-", "struttura": struct or "-"})
        # MOVE di una struttura nel record (01) di un FD del programma: composizione prima della scrittura
        for m in RE_MOVE.finditer(t):
            src, dst = m.groups()
            if dst in radici_fd and src not in FIGURATIVE:
                out.append({"programma": prog, "riga": n, "verbo": "MOVE", "oggetto": dst, "prep": "FROM", "struttura": src})
    return out


def batch(legacy, manifesto):
    out = []
    for p in programmi_cobol(manifesto):
        cod = codice(leggi_righe(os.path.join(legacy, p)))
        cics = any(re.search(r"\bEXEC\s+CICS\b", r.upper()) for r in cod)
        out.append({"programma": p, "exec_cics": "si" if cics else "no", "batch": "no" if cics else "si"})
    return out


# ---------------------------------------------------------------- voci dei sorgenti dati

USAGE = {"COMP": "COMP", "COMPUTATIONAL": "COMP", "COMP-4": "COMP", "COMPUTATIONAL-4": "COMP",
         "BINARY": "BINARY", "COMP-3": "COMP-3", "COMPUTATIONAL-3": "COMP-3", "PACKED-DECIMAL": "COMP-3",
         "COMP-5": "COMP-5", "COMP-1": "COMP-1", "COMP-2": "COMP-2", "DISPLAY": "DISPLAY"}


def voci(ident, righe):
    out = []
    for n, s in frasi(righe):
        w = parole(s)
        if not w or not w[0].isdigit() or w[0] in ("88", "66"):
            continue
        liv = w[0].zfill(2)
        # il nome resta come scritto nel sorgente (maiuscole e minuscole comprese)
        nome = w[1] if len(w) > 1 and w[1].upper() not in ("PIC", "PICTURE", "REDEFINES", "OCCURS", "VALUE") else "FILLER"
        v = {"id": ident, "riga": n, "livello": liv, "nome": nome, "pic": "-", "usage": "-", "occurs": "-",
             "redefines": "-"}
        i = 1
        while i < len(w):
            x = w[i].upper()
            if w[i][:1] in ("'", '"'):
                pass    # letterale di una clausola VALUE
            elif x in ("PIC", "PICTURE"):
                v["pic"] = valore_dopo(w, i, saltare=("IS",))
                i += 1
            elif x == "USAGE":
                v["usage"] = USAGE.get(valore_dopo([y.upper() for y in w], i, saltare=("IS",)), "?")
            elif x in USAGE and v["usage"] == "-":
                v["usage"] = USAGE[x]
            elif x == "OCCURS":
                v["occurs"] = w[i + 1]
            elif x == "REDEFINES":
                v["redefines"] = w[i + 1]
            i += 1
        out.append(v)
    return out


# ---------------------------------------------------------------- JCL e catalogo

def estrai_define(legacy, manifesto):
    out = []
    jcl = [r["path"] for r in leggi_tsv(manifesto) if r["type"] == "jcl" and r["path"].startswith("app/jcl/")]
    for p in jcl:
        righe = leggi_righe(os.path.join(legacy, p))
        n = 0
        while n < len(righe):
            r = righe[n]
            t = re.sub(r"/\*.*?\*/", " ", r[:72])
            if r.startswith("//") or r.startswith("/*") or not re.search(r"\bDEFINE\b", t):
                n += 1
                continue
            inizio, testo = n + 1, []
            while True:
                t = re.sub(r"/\*.*?\*/", " ", righe[n][:72]).rstrip()
                cont = t.endswith("-")
                testo.append(t[:-1] if cont else t)
                n += 1
                if not cont or n >= len(righe) or righe[n].startswith("/"):
                    break
            s = " ".join(testo).upper()
            m = re.search(r"\bDEFINE\s+(CLUSTER|ALTERNATEINDEX|AIX|PATH)\b", s)
            if not m:
                continue
            tipo = {"ALTERNATEINDEX": "AIX"}.get(m.group(1), m.group(1))

            def g(rx):
                mm = re.search(rx, s)
                return mm.groups() if mm else None
            nome = g(r"\bNAME\s*\(\s*([^)\s]+)\s*\)")
            keys = g(r"\bKEYS\s*\(\s*(\d+)[\s,]+(\d+)\s*\)")
            rs = g(r"\bRECORDSIZE\s*\(\s*(\d+)[\s,]+(\d+)\s*\)")
            rel = g(r"\bRELATE\s*\(\s*([^)\s]+)\s*\)")
            pe = g(r"\bPATHENTRY\s*\(\s*([^)\s]+)\s*\)")
            org = [k for k in ("NONINDEXED", "INDEXED", "NUMBERED", "LINEAR") if re.search(r"\b" + k + r"\b", s)]
            uni = "NONUNIQUEKEY" if re.search(r"\bNONUNIQUEKEY\b", s) else ("UNIQUEKEY" if re.search(r"\bUNIQUEKEY\b", s) else "-")
            out.append({"jcl": p, "riga": inizio, "tipo": tipo, "nome": nome[0] if nome else "-",
                        "keys_lunghezza": keys[0] if keys else "-", "keys_offset": keys[1] if keys else "-",
                        "recordsize_medio": rs[0] if rs else "-", "recordsize_max": rs[1] if rs else "-",
                        "unicita": uni, "relate": rel[0] if rel else "-", "pathentry": pe[0] if pe else "-",
                        "organizzazione": org[0] if org else "-"})
    return out


RE_LC_ENTRY = re.compile(r"^.(CLUSTER|AIX|PATH|DATA|INDEX|GDG BASE|NONVSAM) -+ (\S+)")


def estrai_listcat(legacy):
    p = "app/catlg/LISTCAT.txt"
    righe = leggi_righe(os.path.join(legacy, p))
    out, cur = [], None
    for n, r in enumerate(righe, 1):
        m = RE_LC_ENTRY.match(r)
        if m:
            cur = None
            if m.group(1) == "DATA":
                cur = {"riga": n, "componente": m.group(2), "associato": "-", "keylen": "-", "rkp": "-",
                       "axrkp": "-", "avglrecl": "-", "maxlrecl": "-", "unicita": "-", "organizzazione": "-"}
                out.append(cur)
            continue
        if cur is None:
            continue
        t = r[1:]
        ma = re.match(r"\s+(CLUSTER|AIX)-+(\S+)", t)
        if ma and cur["associato"] == "-":
            cur["associato"] = f"{ma.group(1)}:{ma.group(2)}"
        for k, campo in (("KEYLEN", "keylen"), ("RKP", "rkp"), ("AXRKP", "axrkp"), ("AVGLRECL", "avglrecl"),
                         ("MAXLRECL", "maxlrecl")):
            mk = re.search(r"(?<![A-Z])" + k + r"-+(\d+)", t)
            if mk:
                cur[campo] = mk.group(1)
        if re.search(r"\bNONUNIQKEY\b", t):
            cur["unicita"] = "NONUNIQKEY"
        elif re.search(r"\bUNIQKEY\b", t):
            cur["unicita"] = "UNIQKEY"
        mo = re.search(r"\b(NONINDEXED|INDEXED|NUMBERED|LINEAR)\b", t)
        if mo and cur["organizzazione"] == "-":
            cur["organizzazione"] = mo.group(1)
    for c in out:
        c["listcat"] = p
    return out


def cmd_estrai(legacy, manifesto, censimento, outdir):
    os.makedirs(outdir, exist_ok=True)
    progs = batch(legacy, manifesto)
    scrivi_tsv(os.path.join(outdir, "programmi.tsv"), ["programma", "exec_cics", "batch"], progs)
    sel, fds, ios = [], [], []
    for p in (x["programma"] for x in progs if x["batch"] == "si"):
        righe = leggi_righe(os.path.join(legacy, p))
        cod = codice(righe)
        sel += estrai_select(p, righe, cod)
        fdp = estrai_fd(p, righe, cod)
        fds += fdp
        radici_fd = {x.rpartition("@")[0] for f in fdp for x in f["radici"].split(",") if not x.startswith("COPY:")}
        ios += estrai_io(p, cod, radici_fd)
    scrivi_tsv(os.path.join(outdir, "select.tsv"),
               ["programma", "riga", "file", "assign", "organizzazione", "accesso", "chiave", "alternativa", "duplicati"], sel)
    scrivi_tsv(os.path.join(outdir, "fd.tsv"),
               ["programma", "fd", "riga", "registrazione", "contiene", "varia_da", "varia_a", "dipende_da", "radici"], fds)
    scrivi_tsv(os.path.join(outdir, "io.tsv"), ["programma", "riga", "verbo", "oggetto", "prep", "struttura"], ios)
    scrivi_tsv(os.path.join(outdir, "define.tsv"),
               ["jcl", "riga", "tipo", "nome", "keys_lunghezza", "keys_offset", "recordsize_medio", "recordsize_max",
                "unicita", "relate", "pathentry", "organizzazione"], estrai_define(legacy, manifesto))
    scrivi_tsv(os.path.join(outdir, "listcat.tsv"),
               ["listcat", "riga", "componente", "associato", "keylen", "rkp", "axrkp", "avglrecl", "maxlrecl",
                "unicita", "organizzazione"], estrai_listcat(legacy))
    vv = []
    for j in lavori(legacy, manifesto, censimento):
        righe = leggi_righe(os.path.join(legacy, j["sorgente"]))
        if j["righe"] != "-":
            a, b = map(int, RE_INTERVALLO.match(j["righe"]).groups())
            base = righe[a - 1:b]
            for v in voci(j["id"], base):
                v["riga"] = v["riga"] + a - 1
                vv.append(v)
        else:
            vv += voci(j["id"], righe)
    scrivi_tsv(os.path.join(outdir, "voci.tsv"),
               ["id", "riga", "livello", "nome", "pic", "usage", "occurs", "redefines"], vv)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "frammenti":
        cmd_frammenti(*sys.argv[2:6])
    elif cmd == "estrai":
        cmd_estrai(*sys.argv[2:6])
    else:
        raise SystemExit(__doc__)
