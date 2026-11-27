"""Lettura minima delle dichiarazioni dati di un tracciato COBOL, per la verifica sorgente -> sentinella (issue #43).

Non e' un parser COBOL generale: legge solo le voci di descrizione dei dati dei tracciati coperti dalle sentinelle,
una voce per riga terminata dal punto, con le clausole PIC/PICTURE, USAGE (anche implicita: COMP, COMP-3, ...),
REDEFINES e OCCURS. Una riga che non sa leggere fa fallire la verifica: non si indovina. Le voci di livello 88
(nomi di condizione) non occupano byte e si saltano.

Il tracciato comincia alla riga della radice (livello 01, nome dichiarato dalla sentinella) e finisce alla voce
successiva di livello 01, 66 o 77, a un'intestazione di SECTION/DIVISION o FD/SD, o alla fine del file.
Non legge il contratto di #3: e' la terza lettura indipendente del sorgente (dopo cb2xml e la sentinella).
"""
import re

_VOCE = re.compile(r"^([0-9]{1,2})\s+([A-Z0-9][A-Z0-9-]*)(.*)$")
_FINE = re.compile(r"\b(SECTION|DIVISION)\s*\.|^(FD|SD)\s")
USAGE_PAROLE = ("COMP", "COMP-1", "COMP-2", "COMP-3", "COMP-4", "COMP-5", "BINARY", "PACKED-DECIMAL", "DISPLAY",
                "COMPUTATIONAL", "COMPUTATIONAL-3", "COMPUTATIONAL-4")


class SorgenteErrore(ValueError):
    pass


def leggi_righe(path):
    with open(path, "rb") as f:
        testo = f.read().decode("latin-1")
    return [r.rstrip("\r") for r in testo.split("\n")]


def commento(riga):
    return (len(riga) > 6 and riga[6] in "*/" and "\t" not in riga[:7]) or riga.lstrip().startswith("*")


def voce(riga):
    """dict della voce dichiarata su una riga, o None se la riga non e' una voce di descrizione dei dati."""
    t = riga.strip()
    m = _VOCE.match(t)
    if not m:
        return None
    livello, nome, resto = int(m.group(1)), m.group(2), m.group(3)
    if not t.endswith("."):
        raise SorgenteErrore(f"voce {nome} non terminata dal punto sulla stessa riga")
    v = {"livello": livello, "nome": nome, "pic": None, "usage": "-", "redefines": None, "occurs": None}
    if livello == 88:
        return v
    parole = resto.strip()
    if parole.endswith("."):
        parole = parole[:-1]
    p = parole.split()
    i = 0
    while i < len(p):
        w = p[i]
        if w in ("PIC", "PICTURE"):
            i += 1
            if i < len(p) and p[i] == "IS":
                i += 1
            if i >= len(p):
                raise SorgenteErrore(f"{nome}: PIC senza stringa")
            v["pic"] = p[i]
        elif w == "USAGE":
            i += 1
            if i < len(p) and p[i] == "IS":
                i += 1
            if i >= len(p) or p[i] not in USAGE_PAROLE:
                raise SorgenteErrore(f"{nome}: USAGE non riconosciuta")
            v["usage"] = p[i]
        elif w in USAGE_PAROLE:
            v["usage"] = w
        elif w == "REDEFINES":
            i += 1
            if i >= len(p):
                raise SorgenteErrore(f"{nome}: REDEFINES senza oggetto")
            v["redefines"] = p[i]
        elif w == "OCCURS":
            i += 1
            if i >= len(p) or not p[i].isdigit():
                raise SorgenteErrore(f"{nome}: OCCURS senza numero")
            v["occurs"] = int(p[i])
            if i + 1 < len(p) and p[i + 1] == "TIMES":
                i += 1
        else:
            raise SorgenteErrore(f"{nome}: clausola non riconosciuta '{w}'")
        i += 1
    return v


def tracciato(path, riga_radice, nome_radice):
    """Albero del tracciato: dict radice con 'figli'; ogni nodo ha riga, livello, nome, pic, usage, redefines, occurs.
    Aggiunge 'ordinale' (numero d'ordine di dichiarazione) ai nodi elementari, in ordine di sorgente."""
    righe = leggi_righe(path)
    if not 1 <= riga_radice <= len(righe):
        raise SorgenteErrore(f"{path}: riga della radice {riga_radice} fuori dal file")
    r = voce(righe[riga_radice - 1])
    if r is None or r["livello"] != 1 or r["nome"] != nome_radice:
        raise SorgenteErrore(f"{path}:{riga_radice}: non dichiara '01 {nome_radice}'")
    r.update(riga=riga_radice, figli=[])
    pila = [r]
    for n in range(riga_radice + 1, len(righe) + 1):
        t = righe[n - 1]
        if not t.strip() or commento(t):
            continue
        if _FINE.search(t.strip()):
            break
        try:
            v = voce(t)
        except SorgenteErrore as e:
            raise SorgenteErrore(f"{path}:{n}: {e}")
        if v is None:
            raise SorgenteErrore(f"{path}:{n}: riga non riconosciuta: {t.strip()}")
        if v["livello"] in (1, 66, 77):
            break
        if v["livello"] == 88:
            continue
        v.update(riga=n, figli=[])
        while pila and pila[-1]["livello"] >= v["livello"]:
            pila.pop()
        if not pila:
            raise SorgenteErrore(f"{path}:{n}: livello {v['livello']} fuori dal tracciato")
        if pila[-1]["pic"] is not None:
            raise SorgenteErrore(f"{path}:{n}: voce subordinata a un campo elementare")
        pila[-1]["figli"].append(v)
        pila.append(v)
    k = 0
    for nodo in nodi(r):
        if nodo["pic"] is not None:
            if nodo["figli"]:
                raise SorgenteErrore(f"{path}:{nodo['riga']}: campo con PIC e voci subordinate")
            k += 1
            nodo["ordinale"] = k
    return r


def nodi(n):
    yield n
    for f in n["figli"]:
        yield from nodi(f)


def aree(radice):
    """Nodi con REDEFINES (le aree ridefinite), in ordine di sorgente."""
    return [n for n in nodi(radice) if n["redefines"]]


def _padre(radice, figlio):
    for n in nodi(radice):
        if any(f is figlio for f in n["figli"]):
            return n
    return None


def elementari_vista(radice, vista):
    """Lista ordinata di (ordinale, riga, nome, pic, usage, indici) dei campi elementari della vista: 'base' esclude
    ogni area REDEFINES; il nome di un'area la sceglie al posto dell'oggetto che ridefinisce, e esclude le altre."""
    ar = aree(radice)
    escludi = set()
    scelta = None
    for a in ar:
        if a["nome"] == vista:
            scelta = a
        else:
            escludi.add(id(a))
    if vista != "base":
        if scelta is None:
            raise SorgenteErrore(f"vista {vista}: nessuna REDEFINES con questo nome nel sorgente")
        padre = _padre(radice, scelta)
        bersagli = [f for f in padre["figli"] if f["nome"] == scelta["redefines"] and not f["redefines"]]
        if len(bersagli) != 1:
            raise SorgenteErrore(f"vista {vista}: oggetto ridefinito {scelta['redefines']} non trovato (o ripetuto)")
        escludi.add(id(bersagli[0]))
    out = []

    def visita(n, indici):
        if id(n) in escludi:
            return
        giri = range(1, n["occurs"] + 1) if n["occurs"] else [None]
        for i in giri:
            ind = indici + (i,) if i is not None else indici
            if n["pic"] is not None:
                out.append((n["ordinale"], n["riga"], n["nome"], n["pic"], n["usage"], ind))
            else:
                for f in n["figli"]:
                    visita(f, ind)

    visita(radice, ())
    return out
