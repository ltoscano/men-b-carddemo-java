#!/usr/bin/env python3
"""Genera il contratto dati (issue #3) dall'output di cb2xml e dalle fonti estratte.

Uso: contratti.py OUT DOCS DEST
  OUT   cartella dell'analisi (legge cb2xml/*.xml|log|lavori.tsv e fonti/*.tsv; scrive tracciati.tsv, radici.tsv,
        discordanze-rilevate.tsv)
  DOCS  cartella dei file scritti a mano (censimento.tsv, relazioni.tsv, file.tsv, assegnazioni.tsv, censimento.md)
  DEST  cartella dei documenti generati (contratti/*.tsv, contratti.tsv, contratti.md, chiavi.tsv, chiavi.md,
        censimento.md)

Posizioni e lunghezze vengono solo da cb2xml (attributi position, storage-length, display-length, scale, occurs,
redefines); qui si portano le posizioni a base 0, si espandono gli OCCURS (posizione del primo elemento + indice x
lunghezza dell'elemento) e si rileggono PIC e USAGE per segno e cifre. Le chiavi si riconducono ai campi
confrontando intervalli di byte.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comune import CON_CONTRATTO, leggi_tsv, scrivi_tsv, stem  # noqa: E402

USAGE = {None: "DISPLAY", "computational": "COMP", "computational-3": "COMP-3", "binary": "BINARY",
         "computational-5": "COMP-5", "computational-4": "COMP"}
RE_NUM = re.compile(r"^S?[9V()0-9]+$")

# Tipi di differenza che si annotano come dati osservati, senza interpretarli (gli altri sono discordanze tra fonti).
OSSERVAZIONI = ("lrecl", "nessun-jcl", "lunghezze-diverse", "ridefinizione-estesa")

COLONNE_CONTRATTO = ["campo", "livello", "tipo", "pic", "usage", "segno", "cifre_intere", "cifre_decimali",
                     "offset", "lunghezza", "redefines", "area", "occurs", "indice", "percorso"]


# ---------------------------------------------------------------- lettura di cb2xml

class Voce:
    def __init__(self, el, padre=None):
        self.nome = el.get("name")
        self.livello = el.get("level")
        self.pic = el.get("picture")
        self.usage = USAGE.get(el.get("usage"), el.get("usage"))
        self.scala = int(el.get("scale", "0"))
        self.pos = int(el.get("position"))
        self.lung = int(el.get("storage-length"))
        self.dlung = int(el.get("display-length"))
        self.occurs = int(el.get("occurs")) if el.get("occurs") else None
        self.redefines = el.get("redefines")
        self.padre = padre
        self.figli = [Voce(c, self) for c in el.findall("item")]

    def discendente(self, nome):
        for f in self.figli:
            if f.nome == nome:
                return f
            d = f.discendente(nome)
            if d:
                return d
        return None


def carica(out):
    """Restituisce (lavori, radici_per_id, esiti): per ogni input di cb2xml le voci di primo livello."""
    lavori = leggi_tsv(os.path.join(out, "cb2xml", "lavori.tsv"))
    radici, esiti = {}, {}
    for j in lavori:
        px = os.path.join(out, "cb2xml", j["id"] + ".xml")
        pl = os.path.join(out, "cb2xml", j["id"] + ".log")
        log = open(pl, encoding="utf-8", errors="replace").read().strip() if os.path.exists(pl) else "log assente"
        if not os.path.exists(px):
            radici[j["id"]], esiti[j["id"]] = [], "errore: xml assente"
            continue
        if os.path.getsize(px) == 0:
            radici[j["id"]] = []
            esiti[j["id"]] = "errore cb2xml: " + " | ".join(x.strip() for x in log.splitlines() if x.strip())
            continue
        root = ET.parse(px).getroot()
        radici[j["id"]] = [Voce(e) for e in root.findall("item")]
        esiti[j["id"]] = "ok" if not log else "ok con messaggi: " + " | ".join(log.splitlines())
    return lavori, radici, esiti


def tipo_numerico(v):
    return v.pic is not None and RE_NUM.match(v.pic.upper()) is not None


def cifre(v):
    if v.figli or not tipo_numerico(v):
        return "-", "-"
    return str(v.dlung - v.scala), str(v.scala)


def righe_tracciato(ident, radice):
    out = []

    def walk(v, percorso):
        p = percorso + [v.nome]
        out.append({"id": ident, "radice": radice.nome, "percorso": "/".join(p), "livello": v.livello, "nome": v.nome,
                    "pic": v.pic or "-", "usage": v.usage if not v.figli else "-", "scala": v.scala,
                    "offset": v.pos - 1, "lunghezza": v.lung, "occurs": v.occurs or "-",
                    "redefines": v.redefines or "-"})
        for f in v.figli:
            walk(f, p)
    walk(radice, [])
    return out


def contratto(radice):
    """Righe del contratto: ogni voce (gruppi ed elementari), OCCURS espansi con indice, posizioni a base 0."""
    out = []

    def emetti(v, delta, indice, percorso, area):
        a = v.redefines and v.nome or area
        ci, cd = cifre(v)
        elem = not v.figli
        nome_p = v.nome + (f"({indice[-1]})" if v.occurs else "")
        p = percorso + [nome_p]
        out.append({"campo": v.nome, "livello": v.livello, "tipo": "elementare" if elem else "gruppo",
                    "pic": v.pic or "-", "usage": v.usage if elem else "-",
                    "segno": "S" if elem and v.pic and v.pic.upper().startswith("S") else "-",
                    "cifre_intere": ci, "cifre_decimali": cd, "offset": v.pos - 1 + delta, "lunghezza": v.lung,
                    "redefines": v.redefines or "-", "area": a or "-", "occurs": v.occurs or "-",
                    "indice": ",".join(map(str, indice)) if indice else "-", "percorso": "/".join(p)})
        for f in v.figli:
            visita(f, delta, indice, p, a)

    def visita(v, delta, indice, percorso, area):
        if v.occurs:
            for k in range(1, v.occurs + 1):
                emetti(v, delta + (k - 1) * v.lung, indice + [k], percorso, area)
        else:
            emetti(v, delta, indice, percorso, area)
    visita(radice, 0, [], [], None)
    return out


# ---------------------------------------------------------------- riferimenti alle strutture

def id_lavoro(riga_censimento):
    fr = riga_censimento["frammento"]
    if fr.startswith("COPY "):
        return fr.split()[1]
    if re.match(r"^\d+-\d+$", fr):
        return stem(riga_censimento["sorgente"]) + "." + riga_censimento["radice"]
    return stem(riga_censimento["sorgente"])


def risolvi(ref, radici):
    """<STEM>.<RADICE>[:<VOCE>] -> Voce (None se non trovata)."""
    base, _, sub = ref.partition(":")
    st, _, rad = base.partition(".")
    for ident in (st, base):
        for r in radici.get(ident, []):
            if r.nome == rad:
                return r.discendente(sub) if sub else r
    return None


# ---------------------------------------------------------------- chiavi

def elementari_base(righe):
    return [r for r in righe if r["tipo"] == "elementare" and r["area"] == "-"]


def copertura(righe, off, lung):
    """Campi elementari (area base) che occupano i byte [off, off+lung) e tipo di copertura."""
    if righe is None or off is None:
        return "-", "-", "-"
    fine = off + lung
    campi = [r for r in elementari_base(righe) if r["offset"] < fine and r["offset"] + r["lunghezza"] > off]
    if not campi:
        return "-", "-", "nessun-campo"
    esatta = campi[0]["offset"] == off and campi[-1]["offset"] + campi[-1]["lunghezza"] == fine
    gruppo = [r["campo"] for r in righe if r["tipo"] == "gruppo" and r["area"] == "-" and r["offset"] == off
              and r["lunghezza"] == lung and r["livello"] not in ("01", "1")]
    nomi = []
    for r in campi:
        a, b = max(off, r["offset"]), min(fine, r["offset"] + r["lunghezza"])
        parz = "" if (a == r["offset"] and b == r["offset"] + r["lunghezza"]) else f"[{a - r['offset']}..{b - r['offset'] - 1}]"
        nomi.append(r["campo"] + parz)
    return "+".join(nomi), (gruppo[0] if gruppo else "-"), "esatta" if esatta else "parziale"


def calcola_chiavi(fonti, docs, contratti, fd_contratto, scoperte):
    define = leggi_tsv(os.path.join(fonti, "define.tsv"))
    listcat = leggi_tsv(os.path.join(fonti, "listcat.tsv"))
    select = leggi_tsv(os.path.join(fonti, "select.tsv"))
    files = {r["dataset"]: r for r in leggi_tsv(os.path.join(docs, "file.tsv"))}
    asse = {(r["programma"], r["file"]): r for r in leggi_tsv(os.path.join(docs, "assegnazioni.tsv"))}
    righe = []

    def cdat(ds):
        c = files.get(ds, {}).get("contratto", "-")
        return contratti.get(c)

    def riga(ds, chiave, nome, fonte, rif, off, lung, uni, base):
        campi, gruppo, cop = copertura(cdat(base), off, lung)
        righe.append({"dataset": ds, "chiave": chiave, "nome": nome, "fonte": fonte, "riferimento": rif,
                      "offset": "-" if off is None else off, "lunghezza": "-" if lung is None else lung,
                      "unicita": uni, "campi": campi, "gruppo": gruppo, "copertura": cop})
        return righe[-1]

    clusters = [d for d in define if d["tipo"] == "CLUSTER" and d["keys_offset"] != "-"]
    aix = [d for d in define if d["tipo"] == "AIX"]
    for ds in sorted({d["nome"] for d in clusters}):
        for d in (x for x in clusters if x["nome"] == ds):
            riga(ds, "primaria", "-", "JCL DEFINE CLUSTER", f"{d['jcl']}:{d['riga']}", int(d["keys_offset"]),
                 int(d["keys_lunghezza"]), "UNIQUE", ds)
        for lc in (x for x in listcat if x["associato"] == "CLUSTER:" + ds):
            riga(ds, "primaria", "-", "LISTCAT", f"{lc['listcat']}:{lc['riga']}", int(lc["rkp"]), int(lc["keylen"]),
                 "UNIQUE", ds)
        for a in (x for x in aix if x["relate"] == ds):
            riga(ds, "alternativa", a["nome"], "JCL DEFINE AIX", f"{a['jcl']}:{a['riga']}", int(a["keys_offset"]),
                 int(a["keys_lunghezza"]), a["unicita"] if a["unicita"] != "-" else "UNIQUEKEY", ds)
            for lc in (x for x in listcat if x["associato"] == "AIX:" + a["nome"]):
                if (ds, "alternativa", a["nome"], "LISTCAT") in {(r["dataset"], r["chiave"], r["nome"], r["fonte"]) for r in righe}:
                    continue
                riga(ds, "alternativa", a["nome"], "LISTCAT", f"{lc['listcat']}:{lc['riga']}", int(lc["axrkp"]),
                     int(lc["keylen"]), lc["unicita"] if lc["unicita"] != "-" else "UNIQKEY", ds)
    # SELECT dei programmi: posizione della chiave nel record dell'FD (o, se non c'e', nel record del dataset)
    for s in select:
        if s["organizzazione"] != "INDEXED":
            continue
        a = asse.get((s["programma"], s["file"]))
        ds = a["dataset"] if a else "-"
        rfd = fd_contratto.get((s["programma"], s["file"]))
        for chiave, nome, dup in (("primaria", s["chiave"], "-"), ("alternativa", s["alternativa"], s["duplicati"])):
            if nome == "-":
                continue
            v = next((r for r in (contratti.get(rfd) or []) if r["campo"] == nome), None)
            fonte = f"SELECT+FD {stem(s['programma'])}"
            uni = "UNIQUE" if chiave == "primaria" else ("WITH DUPLICATES" if dup == "WITH DUPLICATES" else "senza WITH DUPLICATES")
            rif = f"{s['programma']}:{s['riga']}"
            if v is None:
                v2 = next((r for r in (cdat(ds) or []) if r["campo"] == nome), None)
                r = riga(ds, chiave, nome, fonte + " (campo fuori dal record dell'FD)", rif,
                         v2["offset"] if v2 else None, v2["lunghezza"] if v2 else None, uni, ds)
                scoperte.append(("chiave-fuori-dal-record", f"{stem(s['programma'])}.{s['file']}",
                                 f"{stem(s['programma'])}: la {chiave} {nome} del file {s['file']} non e' un campo del record dell'FD ({rfd})"
                                 + (f"; nel tracciato del dataset ({files.get(ds, {}).get('contratto')}) e' a offset {v2['offset']}, lunghezza {v2['lunghezza']}" if v2 else ""),
                                 rif))
            else:
                r = riga(ds, chiave, nome, fonte, rif, v["offset"], v["lunghezza"], uni, ds)
                r["tipo_fd"] = v["pic"]
    return righe


def discordanze_chiavi(chiavi, define, listcat, contratti, files, scoperte):
    per_ds = {}
    for r in chiavi:
        per_ds.setdefault(r["dataset"], []).append(r)
    for ds, rr in sorted(per_ds.items()):
        jcl = [r for r in rr if r["fonte"].startswith("JCL DEFINE CLUSTER")]
        for kind in ("primaria", "alternativa"):
            ref = [r for r in rr if r["chiave"] == kind and r["fonte"].startswith("JCL DEFINE")]
            for r in (x for x in rr if x["chiave"] == kind and not x["fonte"].startswith("JCL DEFINE")):
                pari = [x for x in ref if kind == "primaria" or x["nome"] == r["nome"] or r["fonte"].startswith("SELECT")]
                for x in pari:
                    if (r["offset"], r["lunghezza"]) != (x["offset"], x["lunghezza"]) and r["offset"] != "-":
                        sigla = r["fonte"].split(" (")[0].replace("SELECT+FD ", "")
                        scoperte.append(("chiave-posizione", f"{ds}:{kind}:{sigla}:{r['nome']}",
                                         f"{ds}: chiave {kind} secondo {r['fonte']} ({r['nome']}) a offset {r['offset']} lunghezza {r['lunghezza']}, "
                                         f"secondo {x['fonte']} a offset {x['offset']} lunghezza {x['lunghezza']}",
                                         f"{r['riferimento']} ; {x['riferimento']}"))
                    if kind == "alternativa" and r["fonte"].startswith("SELECT"):
                        jdup = x["unicita"] == "NONUNIQUEKEY"
                        pdup = r["unicita"] == "WITH DUPLICATES"
                        if jdup != pdup:
                            scoperte.append(("chiave-unicita", f"{x['nome']}:{r['fonte'].split()[-1]}",
                                             f"{ds}: indice alternativo {x['nome']} definito {x['unicita']} nel JCL, mentre la ALTERNATE RECORD KEY "
                                             f"{r['nome']} e' dichiarata {r['unicita']}",
                                             f"{x['riferimento']} ; {r['riferimento']}"))
                    if kind == "alternativa" and r["fonte"] == "LISTCAT":
                        if (x["unicita"] == "NONUNIQUEKEY") != (r["unicita"] == "NONUNIQKEY"):
                            scoperte.append(("catalogo", f"{x['nome']}:unicita", f"{ds}: unicita' {x['unicita']} nel JCL, {r['unicita']} nel LISTCAT",
                                             f"{x['riferimento']} ; {r['riferimento']}"))
        for r in jcl:
            if r["copertura"] != "esatta":
                scoperte.append(("chiave-allineamento", f"{ds}:{r['riferimento']}",
                                 f"{ds}: KEYS({r['lunghezza']} {r['offset']}) copre i byte {r['offset']}..{int(r['offset']) + int(r['lunghezza']) - 1}, "
                                 f"che nel tracciato {files.get(ds, {}).get('contratto')} non coincidono con campi interi: {r['campi']}",
                                 r["riferimento"]))
        # tipo della chiave nel record dell'FD diverso da quello del campo del tracciato del dataset
        c = contratti.get(files.get(ds, {}).get("contratto", "-"))
        for r in rr:
            if r["fonte"].startswith("SELECT") and r.get("tipo_fd") and c and r["copertura"] == "esatta" and "+" not in r["campi"]:
                cv = next((x for x in c if x["campo"] == r["campi"] and x["area"] == "-"), None)
                if cv and cv["pic"] != "-" and r["tipo_fd"] != "-" and cv["pic"][0] != r["tipo_fd"][0]:
                    scoperte.append(("chiave-tipo", f"{ds}:{r['fonte'].split()[-1]}:{r['nome']}",
                                     f"{ds}: la chiave {r['nome']} e' PIC {r['tipo_fd']} nel record dell'FD, il campo {cv['campo']} "
                                     f"del tracciato e' PIC {cv['pic']}", r["riferimento"]))
    # DEFINE ripetute dello stesso dataset
    perdef = {}
    for d in define:
        perdef.setdefault((d["tipo"], d["nome"]), []).append(d)
    for (t, n), dd in sorted(perdef.items()):
        sig = {(d["keys_lunghezza"], d["keys_offset"], d["recordsize_medio"], d["recordsize_max"], d["unicita"], d["relate"]) for d in dd}
        if len(sig) > 1:
            scoperte.append(("define-multiple", n, f"{n}: DEFINE {t} diverse tra loro", " ; ".join(f"{d['jcl']}:{d['riga']}" for d in dd)))
    # DEFINE contro LISTCAT (lunghezze massime)
    for d in define:
        if d["tipo"] != "CLUSTER":
            continue
        for lc in (x for x in listcat if x["associato"] == "CLUSTER:" + d["nome"]):
            if lc["maxlrecl"] != d["recordsize_max"] or lc["avglrecl"] != d["recordsize_medio"]:
                scoperte.append(("catalogo", f"{d['nome']}:recordsize", f"{d['nome']}: RECORDSIZE({d['recordsize_medio']} {d['recordsize_max']}) nel JCL, "
                                 f"AVGLRECL {lc['avglrecl']} MAXLRECL {lc['maxlrecl']} nel LISTCAT", f"{d['jcl']}:{d['riga']} ; {lc['listcat']}:{lc['riga']}"))
    # RECORDSIZE contro lunghezza del tracciato del dataset
    for d in define:
        if d["tipo"] != "CLUSTER":
            continue
        c = files.get(d["nome"], {}).get("contratto", "-")
        if c in contratti and d["recordsize_max"] != "-" and int(d["recordsize_max"]) != contratti[c][0]["lunghezza"]:
            scoperte.append(("recordsize", f"{d['nome']}:{d['jcl']}:{d['riga']}",
                             f"{d['nome']}: RECORDSIZE massimo {d['recordsize_max']}, tracciato {c} di {contratti[c][0]['lunghezza']} byte",
                             f"{d['jcl']}:{d['riga']}"))


def discordanze_file(docs, fonti, contratti, fd_contratto, scoperte):
    files = {r["dataset"]: r for r in leggi_tsv(os.path.join(docs, "file.tsv"))}
    fds = {(r["programma"], r["fd"]): r for r in leggi_tsv(os.path.join(fonti, "fd.tsv"))}
    for a in leggi_tsv(os.path.join(docs, "assegnazioni.tsv")):
        ch = f"{stem(a['programma'])}.{a['file']}"
        if a["jcl"] == "-":
            scoperte.append(("nessun-jcl", ch, f"{stem(a['programma'])}: nessun JCL di app/jcl/ esegue il programma; il file {a['file']} "
                             f"(ASSIGN TO {a['dd']}) non e' ricondotto a un dataset", a["programma"]))
            continue
        if a["riga_dd"] == "-":
            scoperte.append(("dd-assente", ch, f"{stem(a['programma'])}: il file {a['file']} e' assegnato a {a['dd']}, ma il passo di {a['jcl']} "
                             f"non ha una DD {a['dd']}", a["jcl"]))
            continue
        c = fd_contratto.get((a["programma"], a["file"]))
        lfd = contratti[c][0]["lunghezza"] if c in contratti else None
        f = fds.get((a["programma"], a["file"]))
        if a["lrecl"] != "-" and lfd is not None and int(a["lrecl"]) != lfd:
            scoperte.append(("lrecl", ch, f"{stem(a['programma'])}: LRECL={a['lrecl']} RECFM={a['recfm']} nel JCL, record dell'FD {c} di {lfd} byte"
                             + (f" (FD a lunghezza variabile {f['varia_da']}-{f['varia_a']})" if f and f["varia_a"] != "-" else ""),
                             f"{a['jcl']}:{a['riga_dcb']}"))
        dsc = files.get(a["dataset"], {}).get("contratto")
        if dsc in contratti and lfd is not None and lfd != contratti[dsc][0]["lunghezza"]:
            scoperte.append(("fd-lunghezza", ch, f"{stem(a['programma'])}: record dell'FD {c} di {lfd} byte, tracciato del dataset {dsc} di "
                             f"{contratti[dsc][0]['lunghezza']}", f"{a['programma']} ; {a['jcl']}:{a['riga_dsn']}"))
    for (p, fd), f in sorted(fds.items()):
        c = fd_contratto.get((p, fd))
        if f["contiene"] != "-" and c in contratti and int(f["contiene"]) != contratti[c][0]["lunghezza"]:
            scoperte.append(("fd-lunghezza", f"{stem(p)}.{fd}:contains", f"{stem(p)}: RECORD CONTAINS {f['contiene']} ma il record {c} e' di "
                             f"{contratti[c][0]['lunghezza']} byte", f"{p}:{f['riga']}"))


# ---------------------------------------------------------------- viste Markdown

def md_tab(testa, righe):
    out = ["| " + " | ".join(testa) + " |", "|" + "|".join(" --- " for _ in testa) + "|"]
    for r in righe:
        out.append("| " + " | ".join(str(x).replace("|", "\\|") for x in r) + " |")
    return "\n".join(out)


GENERATO = "<!-- Da qui in poi il testo e' generato da analysis/data-contract (contratti.py): non modificarlo a mano. -->"


def main(out, docs, dest):
    fonti = os.path.join(out, "fonti")
    lavori, radici, esiti = carica(out)
    cens = leggi_tsv(os.path.join(docs, "censimento.tsv"))
    rel = leggi_tsv(os.path.join(docs, "relazioni.tsv"))
    asse = leggi_tsv(os.path.join(docs, "assegnazioni.tsv"))
    files = {r["dataset"]: r for r in leggi_tsv(os.path.join(docs, "file.tsv"))}
    fds = leggi_tsv(os.path.join(fonti, "fd.tsv"))
    define = leggi_tsv(os.path.join(fonti, "define.tsv"))
    listcat = leggi_tsv(os.path.join(fonti, "listcat.tsv"))

    # tracciati e radici (tutti gli input di cb2xml)
    trac, rad = [], []
    for j in lavori:
        if not radici[j["id"]]:
            rad.append({"id": j["id"], "sorgente": j["sorgente"], "righe": j["righe"], "radice": "-", "livello": "-",
                        "lunghezza": "-", "esito": esiti[j["id"]]})
        for r in radici[j["id"]]:
            rad.append({"id": j["id"], "sorgente": j["sorgente"], "righe": j["righe"], "radice": r.nome,
                        "livello": r.livello, "lunghezza": r.lung * (r.occurs or 1), "esito": esiti[j["id"]]})
            trac += righe_tracciato(j["id"], r)
    scrivi_tsv(os.path.join(out, "tracciati.tsv"),
               ["id", "radice", "percorso", "livello", "nome", "pic", "usage", "scala", "offset", "lunghezza", "occurs", "redefines"], trac)
    scrivi_tsv(os.path.join(out, "radici.tsv"), ["id", "sorgente", "righe", "radice", "livello", "lunghezza", "esito"], rad)

    # contratti
    contratti, indice = {}, []
    os.makedirs(os.path.join(dest, "contratti"), exist_ok=True)
    for c in cens:
        if c["classificazione"] not in CON_CONTRATTO or c["contratto"] == "-" or c["contratto"] in contratti:
            continue
        if c["frammento"].startswith("COPY "):
            continue
        v = next((r for r in radici.get(id_lavoro(c), []) if r.nome == c["radice"]), None)
        if v is None:
            continue   # segnalato dalla verifica
        righe = contratto(v)
        contratti[c["contratto"]] = righe
        scrivi_tsv(os.path.join(dest, "contratti", c["contratto"] + ".tsv"), COLONNE_CONTRATTO, righe)
    # record dell'FD per (programma, file) e informazioni dell'FD
    fd_contratto, fd_info = {}, {}
    for c in cens:
        if c["tipo"].startswith("FD:"):
            fd_contratto[(c["sorgente"], c["tipo"][3:])] = c["contratto"]
    for f in fds:
        fd_info[fd_contratto.get((f["programma"], f["fd"]))] = f
    for c in cens:
        if c["contratto"] == "-" or c["contratto"] not in contratti or c["frammento"].startswith("COPY "):
            continue
        righe = contratti[c["contratto"]]
        f = fd_info.get(c["contratto"]) if c["tipo"].startswith("FD:") else None
        scritte = sorted({int(r["trasferita"]) for r in rel if r["a"] == c["contratto"] and r["verbo"].startswith(("WRITE", "REWRITE"))})
        rs = sorted({f"{d['recordsize_medio']} {d['recordsize_max']} ({d['jcl']}:{d['riga']})" for d in define
                     if d["tipo"] == "CLUSTER" and files.get(d["nome"], {}).get("contratto") == c["contratto"]})
        dcb = sorted({f"LRECL={a['lrecl']} RECFM={a['recfm']} ({a['jcl']}:{a['riga_dcb']})" for a in asse
                      if a["lrecl"] != "-" and fd_contratto.get((a["programma"], a["file"])) == c["contratto"]})
        indice.append({"contratto": c["contratto"], "sorgente": c["sorgente"],
                       "righe": c["frammento"] if c["frammento"] != "-" else "copybook", "radice": c["radice"],
                       "classificazione": c["classificazione"], "lunghezza": righe[0]["lunghezza"],
                       "elementari": sum(1 for r in righe if r["tipo"] == "elementare"),
                       "somma_base": sum(r["lunghezza"] for r in elementari_base(righe)),
                       "variabile": f"{f['varia_da']}-{f['varia_a']} DEPENDING ON {f['dipende_da']}" if f and f["varia_a"] != "-" else "-",
                       "lunghezze_scritte": ",".join(map(str, scritte)) or "-",
                       "recordsize": "; ".join(rs) or "-", "dcb_osservata": "; ".join(dcb) or "-"})
    COL_IND = ["contratto", "sorgente", "righe", "radice", "classificazione", "lunghezza", "elementari", "somma_base",
               "variabile", "lunghezze_scritte", "recordsize", "dcb_osservata"]
    scrivi_tsv(os.path.join(dest, "contratti.tsv"), COL_IND, indice)

    # chiavi e discordanze rilevate automaticamente
    scoperte = []
    chiavi = calcola_chiavi(fonti, docs, contratti, fd_contratto, scoperte)
    discordanze_chiavi(chiavi, define, listcat, contratti, files, scoperte)
    discordanze_file(docs, fonti, contratti, fd_contratto, scoperte)
    # REDEFINES con estensione diversa dall'area ridefinita (in qualunque tracciato, non solo nei contratti)
    for j in lavori:
        for rr in radici[j["id"]]:
            def scan(v, rr=rr, j=j):
                for f in v.figli:
                    if f.redefines:
                        t = next((x for x in v.figli if x.nome == f.redefines), None)
                        if t and t.lung * (t.occurs or 1) != f.lung * (f.occurs or 1):
                            scoperte.append(("ridefinizione-estesa", f"{j['id']}:{f.nome}",
                                             f"{j['sorgente']}: {f.nome} ({f.lung * (f.occurs or 1)} byte) ridefinisce {t.nome} "
                                             f"({t.lung * (t.occurs or 1)} byte); cb2xml da' alla radice {rr.nome} {rr.lung} byte",
                                             j["sorgente"]))
                    scan(f)
            scan(rr)
    # strutture spostate in (o lette da) record di lunghezza diversa: dato osservato (riempimento o troncamento della MOVE)
    for r in rel:
        a, b = risolvi(r["da"], radici), risolvi(r["a"], radici)
        if a and b and a.lung != b.lung:
            scoperte.append(("lunghezze-diverse", f"{stem(r['programma'])}:{r['da']}->{r['a']}",
                             f"{stem(r['programma'])} {r['verbo']} (righe {r['righe']}): {r['da']} di {a.lung} byte, {r['a']} di {b.lung} byte",
                             f"{r['programma']}:{r['righe'].split(',')[0]}"))
    COL_CH = ["dataset", "chiave", "nome", "fonte", "riferimento", "offset", "lunghezza", "unicita", "campi", "gruppo", "copertura"]
    scrivi_tsv(os.path.join(dest, "chiavi.tsv"), COL_CH, chiavi)
    visti, disc = set(), []
    for tipo, chiave, descr, rif in scoperte:
        ident = f"{tipo}:{chiave}"
        if ident in visti:
            continue
        visti.add(ident)
        disc.append({"id": ident, "tipo": tipo,
                     "categoria": "osservazione" if tipo in OSSERVAZIONI else "discordanza",
                     "descrizione": descr, "riferimenti": rif})
    disc.sort(key=lambda d: d["id"])
    scrivi_tsv(os.path.join(out, "discordanze-rilevate.tsv"), ["id", "tipo", "categoria", "descrizione", "riferimenti"], disc)

    # ---- viste
    lung_ref = {}
    for r in rel:
        for k in ("da", "a"):
            v = risolvi(r[k], radici)
            lung_ref[r[k]] = v.lung if v else "?"
    # contratti.md
    m = ["# Contratti fisici dei tracciati (vista generata)", "",
         "Generato da `./analysis/run.sh data-contract` a partire dall'output di cb2xml 1.01.08 (dialetto Mainframe) e da "
         "`censimento.tsv`. Non si modifica a mano: i file leggibili da macchina sono `contratti/<contratto>.tsv` e `contratti.tsv`.", "",
         "Colonne: posizione (`offset`) a base 0 e `lunghezza` in byte, da cb2xml; `segno` = `S` se la PIC inizia con S; "
         "cifre intere e decimali dalla lunghezza di visualizzazione e dalla scala di cb2xml; `area` = voce con REDEFINES che "
         "contiene il campo (i campi con area `-` formano il record base); gli `OCCURS` sono espansi, una riga per elemento, con `indice`.", "",
         "## Indice", "",
         md_tab(["contratto", "radice", "sorgente", "righe", "classificazione", "byte", "campi", "somma base", "variabile",
                 "scritti", "RECORDSIZE (JCL)", "DCB osservata"],
                [[f"`{i['contratto']}`", i["radice"], i["sorgente"], i["righe"], i["classificazione"], i["lunghezza"],
                  i["elementari"], i["somma_base"], i["variabile"], i["lunghezze_scritte"], i["recordsize"], i["dcb_osservata"]]
                 for i in indice]), ""]
    for i in indice:
        m += [f"## `{i['contratto']}`", "", f"Radice `{i['radice']}` di `{i['sorgente']}` ({i['righe']}), {i['lunghezza']} byte.", "",
              md_tab(["campo", "liv.", "tipo", "PIC", "USAGE", "segno", "int.", "dec.", "offset", "byte", "REDEFINES", "area", "indice"],
                     [[r["campo"], r["livello"], r["tipo"], r["pic"], r["usage"], r["segno"], r["cifre_intere"], r["cifre_decimali"],
                       r["offset"], r["lunghezza"], r["redefines"], r["area"], r["indice"]] for r in contratti[i["contratto"]]]), ""]
    open(os.path.join(dest, "contratti.md"), "w", encoding="utf-8").write("\n".join(m).rstrip() + "\n")

    # chiavi.md
    m = ["# Chiavi dei file a confronto tra le fonti (vista generata)", "",
         "Generato da `./analysis/run.sh data-contract`. Fonti: `DEFINE` nei JCL (`KEYS(lunghezza offset)`, offset a base 0), "
         "`LISTCAT.txt` (`KEYLEN`, `RKP` o `AXRKP`), `SELECT` dei programmi con la posizione della chiave nel record dell'FD, "
         "e i campi del tracciato del dataset (`file.tsv`) che occupano gli stessi byte. Le differenze sono in `discordanze.md`.", ""]
    for ds in sorted({r["dataset"] for r in chiavi}):
        m += [f"## {ds}", "", f"Tracciato: `{files.get(ds, {}).get('contratto', '-')}`.", "",
              md_tab(["chiave", "nome", "fonte", "riferimento", "offset", "byte", "unicita'", "campi del tracciato", "gruppo", "copertura"],
                     [[r["chiave"], r["nome"], r["fonte"], r["riferimento"], r["offset"], r["lunghezza"], r["unicita"], r["campi"],
                       r["gruppo"], r["copertura"]] for r in chiavi if r["dataset"] == ds]), ""]
    m += ["## Discordanze e osservazioni rilevate automaticamente", "",
          md_tab(["id", "categoria", "descrizione", "riferimenti"],
                 [[f"`{d['id']}`", d["categoria"], d["descrizione"], d["riferimenti"]] for d in disc]), ""]
    open(os.path.join(dest, "chiavi.md"), "w", encoding="utf-8").write("\n".join(m).rstrip() + "\n")

    # censimento.md: parte scritta a mano + tabelle generate
    testo = open(os.path.join(docs, "censimento.md"), encoding="utf-8").read()
    testa = testo.split(GENERATO)[0].rstrip() + "\n\n" + GENERATO + "\n\n"
    rad_by = {}
    for r in rad:
        rad_by.setdefault(r["sorgente"] if r["righe"] == "-" else (r["sorgente"], r["righe"]), []).append(r)
    g = ["## Tabelle generate", "", "### Copybook di `app/cpy/`: radici trovate da cb2xml e classificazione", "",
         md_tab(["copybook", "radice", "riga", "byte (cb2xml)", "classificazione", "contratto", "motivo"],
                [[c["sorgente"].split("/")[-1], c["radice"], c["riga"],
                  next((r["lunghezza"] for r in rad if r["sorgente"] == c["sorgente"] and r["righe"] == "-" and r["radice"] == c["radice"]),
                       next((r["esito"] for r in rad if r["sorgente"] == c["sorgente"] and r["righe"] == "-" and r["radice"] == "-"), "-")),
                  c["classificazione"], f"`{c['contratto']}`" if c["contratto"] != "-" else "-", c["motivo"]]
                 for c in cens if c["tipo"] == "copybook"]), "",
         "### Programmi batch: FD e strutture di lavoro", ""]
    rows = []
    for c in (x for x in cens if x["tipo"] != "copybook"):
        ident = id_lavoro(c)
        v = next((r for r in radici.get(ident, []) if r.nome == c["radice"]), None)
        rows.append([c["sorgente"].split("/")[-1], c["tipo"], c["radice"], c["riga"], c["frammento"], v.lung if v else "?",
                     c["classificazione"], f"`{c['contratto']}`" if c["contratto"] != "-" else "-"])
    g += [md_tab(["programma", "tipo", "radice", "riga", "righe date a cb2xml", "byte (cb2xml)", "classificazione", "contratto"], rows), "",
          "### Relazioni struttura → record dell'FD", "",
          "Lunghezze scritte a mano in `relazioni.tsv` (colonne `a mano`) e lette da cb2xml (colonne `cb2xml`).", "",
          md_tab(["programma", "verbo", "righe", "da", "a", "byte da (a mano / cb2xml)", "byte a (a mano / cb2xml)", "trasferiti", "fonte", "nota"],
                 [[r["programma"].split("/")[-1], r["verbo"], r["righe"].replace(",", ", "), r["da"], r["a"],
                   f"{r['lunghezza_da']} / {lung_ref[r['da']]}", f"{r['lunghezza_a']} / {lung_ref[r['a']]}", r["trasferita"],
                   r["fonte_trasferita"], r["nota"]] for r in rel]), ""]
    open(os.path.join(dest, "censimento.md"), "w", encoding="utf-8").write(testa + "\n".join(g).rstrip() + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
