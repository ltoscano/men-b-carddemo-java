#!/usr/bin/env python3
"""Controlli del contratto dati (issue #3). Esce con 1 al primo gruppo di errori (li stampa tutti).

Uso: verifica.py OUT DOCS GEN EXPECTED LEGACY MANIFEST
  OUT       output dell'analisi (cb2xml/, fonti/, tracciati.tsv, radici.tsv, discordanze-rilevate.tsv)
  DOCS      file scritti a mano (censimento.tsv, relazioni.tsv, file.tsv, assegnazioni.tsv, discordanze.md)
  GEN       documenti generati (contratti/, contratti.tsv, chiavi.tsv)
  EXPECTED  attesi scritti a mano (analysis/data-contract/expected)

Ogni errore ha la forma "ERRORE [gruppo] messaggio": le prove negative di check.sh cercano gruppo e messaggio.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comune import CLASSI, CON_CONTRATTO, area_programma, leggi_righe, leggi_tsv, senza_letterali, stem  # noqa: E402

ERRORI = []
INIZIO = [0]
RE_NUM = re.compile(r"^S?[9V()0-9]+$")
# Per CVEXPORT la specifica chiede le sole aree ridefinite: si confrontano le righe dentro un'area con REDEFINES e quelle ridefinite.
SELEZIONE = {"CVEXPORT.EXPORT-RECORD": "ridefinite"}


def err(gruppo, msg):
    ERRORI.append(f"ERRORE [{gruppo}] {msg}")


def ok(msg):
    if len(ERRORI) == INIZIO[0]:
        print(f"   ok: {msg}")


def intero(x):
    try:
        return int(x)
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------- PIC e USAGE (calcolo indipendente da cb2xml)

def espandi_pic(pic):
    return re.sub(r"(.)\((\d+)\)", lambda m: m.group(1) * int(m.group(2)), pic.upper())


def lunghezza_da_pic(pic, usage):
    p = espandi_pic(pic)
    if usage in ("COMP", "BINARY", "COMP-5"):
        d = p.count("9")
        return 2 if d <= 4 else 4 if d <= 9 else 8
    if usage == "COMP-3":
        return p.count("9") // 2 + 1
    n, i = 0, 0
    while i < len(p):
        if p.startswith(("CR", "DB"), i):
            n, i = n + 2, i + 2
            continue
        if p[i] not in "SVP":
            n += 1
        i += 1
    return n


def cifre_da_pic(pic):
    p = espandi_pic(pic).lstrip("S")
    intera, _, dec = p.partition("V")
    return intera.count("9"), dec.count("9")


def categoria(r):
    if r["tipo"] == "gruppo":
        return "gruppo"
    if RE_NUM.match(r["pic"].upper()):
        return "numerico-" + r["usage"]
    if re.match(r"^[XA()0-9]+$", r["pic"].upper()):
        return "alfanumerico"
    return "editato"


# ---------------------------------------------------------------- caricamento

class Dati:
    def __init__(self, out, docs, gen, exp, legacy, manifesto):
        self.out, self.docs, self.gen, self.exp, self.legacy = out, docs, gen, exp, legacy
        f = os.path.join(out, "fonti")
        self.manifesto = leggi_tsv(manifesto)
        self.cens = leggi_tsv(os.path.join(docs, "censimento.tsv"))
        self.rel = leggi_tsv(os.path.join(docs, "relazioni.tsv"))
        self.files = leggi_tsv(os.path.join(docs, "file.tsv"))
        self.asse = leggi_tsv(os.path.join(docs, "assegnazioni.tsv"))
        self.radici = leggi_tsv(os.path.join(out, "radici.tsv"))
        self.trac = leggi_tsv(os.path.join(out, "tracciati.tsv"))
        self.lavori = leggi_tsv(os.path.join(out, "cb2xml", "lavori.tsv"))
        self.fd = leggi_tsv(os.path.join(f, "fd.tsv"))
        self.sel = leggi_tsv(os.path.join(f, "select.tsv"))
        self.io = leggi_tsv(os.path.join(f, "io.tsv"))
        self.define = leggi_tsv(os.path.join(f, "define.tsv"))
        self.voci = leggi_tsv(os.path.join(f, "voci.tsv"))
        self.progr = leggi_tsv(os.path.join(f, "programmi.tsv"))
        self.est = leggi_tsv(os.path.join(f, "estensioni.tsv"))
        self.trasf = leggi_tsv(os.path.join(f, "trasferimenti.tsv"))
        self.nonc = leggi_tsv(os.path.join(f, "non-coperti.tsv"))
        self.comp = leggi_tsv(os.path.join(gen, "composizioni.tsv"))
        self.chiavi = leggi_tsv(os.path.join(gen, "chiavi.tsv"))
        self.indice = leggi_tsv(os.path.join(gen, "contratti.tsv"))
        self.rilevate = leggi_tsv(os.path.join(out, "discordanze-rilevate.tsv"))
        self.contratti = {}
        d = os.path.join(gen, "contratti")
        for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if n.endswith(".tsv"):
                rr = leggi_tsv(os.path.join(d, n))
                for r in rr:
                    r["offset"], r["lunghezza"] = intero(r["offset"]), intero(r["lunghezza"])
                self.contratti[n[:-4]] = rr
        self.sorgenti = {}

    def righe(self, path):
        if path not in self.sorgenti:
            self.sorgenti[path] = leggi_righe(os.path.join(self.legacy, path))
        return self.sorgenti[path]

    def codice(self, path, n):
        r = self.righe(path)
        if not (1 <= n <= len(r)):
            return None
        ind, t = area_programma(r[n - 1])
        return "" if ind in "*/" else senza_letterali(t).upper()


def id_lavoro(c):
    fr = c["frammento"]
    if fr.startswith("COPY "):
        return fr.split()[1]
    if re.match(r"^\d+-\d+$", fr):
        return stem(c["sorgente"]) + "." + c["radice"]
    return stem(c["sorgente"])


def lunghezza_ref(D, ref):
    base, _, sub = ref.partition(":")
    st, _, rad = base.partition(".")
    for ident in (st, base):
        rows = [t for t in D.trac if t["id"] == ident and t["radice"] == rad]
        if rows:
            if not sub:
                return intero(rows[0]["lunghezza"])
            s = next((t for t in rows if t["nome"] == sub), None)
            return intero(s["lunghezza"]) if s else None
    return None


# ---------------------------------------------------------------- A. censimento

def controlla_censimento(D):
    copy_manif = sorted(r["path"] for r in D.manifesto if r["type"] == "copybook" and r["path"].startswith("app/cpy/"))
    cens_cpy = {c["sorgente"] for c in D.cens if c["tipo"] == "copybook"}
    for p in copy_manif:
        if p not in cens_cpy:
            err("censimento", f"copybook del manifesto assente dal censimento: {p}")
    for p in sorted(cens_cpy - set(copy_manif)):
        err("censimento", f"copybook nel censimento ma non nel manifesto: {p}")
    for c in D.cens:
        if c["classificazione"] not in CLASSI:
            err("censimento", f"{c['sorgente']} {c['radice']}: classificazione non ammessa '{c['classificazione']}'")
        if c["classificazione"] in CON_CONTRATTO and c["contratto"] == "-":
            err("censimento", f"{c['sorgente']} {c['radice']}: classificata {c['classificazione']} ma senza contratto")
        if c["classificazione"] not in CON_CONTRATTO and c["contratto"] != "-":
            err("censimento", f"{c['sorgente']} {c['radice']}: contratto indicato per una radice classificata {c['classificazione']}")
    # radici dei copybook contro cb2xml
    for p in copy_manif:
        rows = [c for c in D.cens if c["sorgente"] == p]
        ident = stem(p)
        rad = [r for r in D.radici if r["id"] == ident]
        uno = {r["radice"] for r in rad if r["livello"] in ("01", "1")}
        cr = {c["radice"] for c in rows if c["radice"] != "-"}
        for x in sorted(uno - cr):
            err("censimento", f"{p}: radice di livello 01 trovata da cb2xml e assente dal censimento: {x}")
        for x in sorted(cr - uno):
            err("censimento", f"{p}: radice '{x}' del censimento non trovata da cb2xml tra le radici di livello 01")
        if not uno and [c["radice"] for c in rows] != ["-"]:
            err("censimento", f"{p}: nessuna radice di livello 01 secondo cb2xml: il censimento deve avere una sola riga con radice '-'")
        errore = any(r["esito"].startswith("errore") for r in rad)
        nt = any(c["classificazione"] == "non-tracciato" for c in rows)
        if errore != nt:
            err("censimento", f"{p}: classificato {'non-tracciato' if nt else rows[0]['classificazione'] if rows else '?'} "
                              f"ma cb2xml {'non ' if errore else ''}ha riconosciuto descrizioni di dati ({rad[0]['esito'] if rad else 'nessun esito'})")
    # righe citate e frammenti
    for c in D.cens:
        if c["radice"] == "-":
            continue
        n = intero(c["riga"])
        t = D.codice(c["sorgente"], n) if n else None
        if c["frammento"].startswith("COPY "):
            x = c["frammento"].split()[1]
            if t is None or not re.search(r"\bCOPY\s+" + re.escape(x) + r"\b", t):
                err("censimento", f"{c['sorgente']}:{c['riga']}: la riga non contiene COPY {x}")
        elif t is None or not re.search(r"(^|\s)0?1\s+" + re.escape(c["radice"]) + r"(\s|\.|$)", t):
            err("censimento", f"{c['sorgente']}:{c['riga']}: la riga non dichiara l'01 {c['radice']}")
        m = re.match(r"^(\d+)-(\d+)$", c["frammento"])
        if m:
            if m.group(1) != c["riga"]:
                err("censimento", f"{c['sorgente']} {c['radice']}: il frammento {c['frammento']} non inizia alla riga dell'01 ({c['riga']})")
            rad = [r["radice"] for r in D.radici if r["id"] == id_lavoro(c)]
            if rad != [c["radice"]]:
                err("censimento", f"{c['sorgente']} {c['radice']}: il frammento {c['frammento']} contiene le radici {rad}, attesa solo {c['radice']}")
    # confini ricavati dal sorgente completo: l'intervallo dichiarato deve coincidere; la sezione deve essere quella del tipo;
    # cb2xml deve avere per la radice tante voci quante il sorgente fino al confine
    est = {(e["sorgente"], e["radice"], e["inizio"]): e for e in D.est}
    for c in D.cens:
        if c["radice"] == "-" or c["frammento"].startswith("COPY "):
            continue
        e = est.get((c["sorgente"], c["radice"], c["riga"]))
        if e is None or e["fine"] == "-":
            err("censimento", f"{c['sorgente']} {c['radice']}: confini non ricavabili dal sorgente a partire dalla riga {c['riga']}")
            continue
        m = re.match(r"^(\d+)-(\d+)$", c["frammento"])
        if m and (m.group(1), m.group(2)) != (e["inizio"], e["fine"]):
            err("censimento", f"{c['sorgente']} {c['radice']}: intervallo dichiarato {c['frammento']}, nel sorgente la struttura va "
                              f"da {e['inizio']} a {e['fine']} (confine: {e['confine']})")
        attesa = {"WORKING-STORAGE": "WORKING-STORAGE", "LINKAGE": "LINKAGE"}.get(c["tipo"], "FILE" if c["tipo"].startswith("FD:") else "-")
        if c["tipo"] != "copybook" and e["sezione"] != attesa:
            err("censimento", f"{c['sorgente']} {c['radice']}: tipo {c['tipo']}, ma la riga {c['riga']} e' nella sezione {e['sezione']}")
        ident = id_lavoro(c)
        n = sum(1 for t in D.trac if t["id"] == ident and t["radice"] == c["radice"])
        if str(n) != e["voci"]:
            err("tracciati", f"{c['sorgente']} {c['radice']}: cb2xml ha {n} voci, il sorgente ne ha {e['voci']} fino al confine ({e['confine']})")
    ok(f"censimento: {len(copy_manif)} copybook del manifesto, {len(D.cens)} radici, righe citate verificate; confini, sezioni "
       f"e numero di voci di ogni radice ricavati dal sorgente completo e uguali a censimento e cb2xml")
    # FD dei programmi batch
    batch = [p["programma"] for p in D.progr if p["batch"] == "si"]
    nfd = 0
    for f in D.fd:
        nfd += 1
        attese = set()
        for x in f["radici"].split(","):
            if x == "-":
                continue
            nome, _, riga = x.rpartition("@")
            attese.add((("COPY " + nome[5:]) if nome.startswith("COPY:") else nome, riga))
        trovate = {(c["frammento"] if c["frammento"].startswith("COPY ") else c["radice"], c["riga"])
                   for c in D.cens if c["sorgente"] == f["programma"] and c["tipo"] == "FD:" + f["fd"]}
        if not trovate:
            err("censimento", f"FD {f['fd']} di {f['programma']} (riga {f['riga']}) assente dal censimento")
        elif trovate != attese:
            err("censimento", f"FD {f['fd']} di {f['programma']}: 01 nel censimento {sorted(trovate)}, nel sorgente {sorted(attese)}")
    fdset = {(f["programma"], "FD:" + f["fd"]) for f in D.fd}
    for c in D.cens:
        if c["tipo"].startswith("FD:") and (c["sorgente"], c["tipo"]) not in fdset:
            err("censimento", f"{c['sorgente']}: {c['tipo']} del censimento non esiste nel sorgente")
        if c["tipo"] != "copybook" and c["sorgente"] not in batch:
            err("censimento", f"{c['sorgente']}: non e' un programma batch")
    ok(f"FD dei programmi batch: {nfd} FD in {len({f['programma'] for f in D.fd})} programmi, tutte nel censimento con i loro 01")
    # contratti presenti, e solo quelli censiti
    attesi = {}
    for c in D.cens:
        if c["classificazione"] not in CON_CONTRATTO:
            continue
        atteso = (c["frammento"].split()[1] if c["frammento"].startswith("COPY ") else stem(c["sorgente"])) + "." + c["radice"]
        if c["contratto"] != atteso:
            err("censimento", f"{c['sorgente']} {c['radice']}: contratto '{c['contratto']}', atteso '{atteso}'")
        attesi[c["contratto"]] = c
    for k in sorted(attesi):
        if k not in D.contratti:
            err("contratti", f"contratto mancante: {k} (radice classificata {attesi[k]['classificazione']})")
    for k in sorted(set(D.contratti) - set(attesi)):
        err("contratti", f"contratto senza radice censita come record o stato: {k}")
    ind = {i["contratto"] for i in D.indice}
    for k in sorted(set(attesi) ^ ind):
        err("contratti", f"indice contratti.tsv incoerente con il censimento per {k}")
    ok(f"contratti: {len(attesi)} radici classificate record o stato, {len(D.contratti)} file di contratto")


# ---------------------------------------------------------------- A bis. relazioni struttura -> FD

def nome_ref(ref):
    base, _, sub = ref.partition(":")
    return sub or base.partition(".")[2]


def controlla_relazioni(D):
    io = {(r["programma"], int(r["riga"])): r for r in D.io}
    fd_di = {}
    for c in D.cens:
        if c["tipo"].startswith("FD:"):
            fd_di.setdefault((c["sorgente"], c["tipo"][3:]), set()).add(c["radice"])
    fdinfo = {}
    for f in D.fd:
        for x in f["radici"].split(","):
            nome = x.rpartition("@")[0]
            fdinfo[(f["programma"], nome)] = f
    coperte = set()
    for r in D.rel:
        p = r["programma"]
        da, a, v = nome_ref(r["da"]), nome_ref(r["a"]), r["verbo"]
        for n in map(int, r["righe"].split(",")):
            coperte.add((p, n))
            if v == "MOVE":
                t = D.codice(p, n) or ""
                if not re.search(r"\bMOVE\s+" + re.escape(da) + r"\s+TO\s+" + re.escape(a) + r"\b", t):
                    err("relazioni", f"{p}:{n}: la riga non contiene MOVE {da} TO {a}")
                continue
            x = io.get((p, n))
            if x is None or x["verbo"] == "MOVE":
                err("relazioni", f"{p}:{n}: nessuna istruzione {v} a questa riga")
                continue
            verbo = {"READ": "READ", "READ-INTO": "READ", "WRITE": "WRITE", "WRITE-FROM": "WRITE", "REWRITE-FROM": "REWRITE"}.get(v)
            if x["verbo"] != verbo:
                err("relazioni", f"{p}:{n}: istruzione {x['verbo']}, relazione {v}")
            if v in ("READ", "READ-INTO"):
                if da not in fd_di.get((p, x["oggetto"]), set()):
                    err("relazioni", f"{p}:{n}: READ {x['oggetto']}, ma {da} non e' un 01 di quell'FD")
                if v == "READ-INTO" and x["struttura"] != a:
                    err("relazioni", f"{p}:{n}: READ ... INTO {x['struttura']}, relazione verso {a}")
                if v == "READ" and (x["prep"] != "-" or da != a):
                    err("relazioni", f"{p}:{n}: READ senza INTO attesa")
            else:
                if x["oggetto"] != a:
                    err("relazioni", f"{p}:{n}: {x['verbo']} {x['oggetto']}, relazione verso {a}")
                if v.endswith("FROM") and x["struttura"] != da:
                    err("relazioni", f"{p}:{n}: {x['verbo']} ... FROM {x['struttura']}, relazione da {da}")
                if v == "WRITE" and (x["prep"] != "-" or da != a):
                    err("relazioni", f"{p}:{n}: WRITE senza FROM attesa")
        # lunghezze
        for k, ref in (("lunghezza_da", r["da"]), ("lunghezza_a", r["a"])):
            l = lunghezza_ref(D, ref)
            if l is None:
                err("relazioni", f"{p}: struttura {ref} non trovata nell'output di cb2xml")
            elif intero(r[k]) != l:
                err("relazioni", f"{p} righe {r['righe']}: {k} {r[k]} scritta a mano, cb2xml {l} per {ref}")
        t, ft = intero(r["trasferita"]), r["fonte_trasferita"]
        if ft == "FD":
            atteso = intero(r["lunghezza_da"]) if v.startswith("READ") else intero(r["lunghezza_a"])
            if t != atteso:
                err("relazioni", f"{p} righe {r['righe']}: trasferiti {t}, la lunghezza del record dell'FD e' {atteso}")
        elif ft == "destinazione":
            if v != "MOVE" or t != intero(r["lunghezza_a"]):
                err("relazioni", f"{p} righe {r['righe']}: trasferiti {t}, destinazione di {r['lunghezza_a']} byte")
        elif ft.startswith("riga:"):
            f = fdinfo.get((p, a.split(":")[0] if v != "MOVE" else nome_ref(r["a"])))
            n = intero(ft[5:])
            if f is None or f["dipende_da"] == "-":
                err("relazioni", f"{p} righe {r['righe']}: lunghezza da riga {n} ma {a} non e' il record di un FD variabile")
            else:
                t2 = D.codice(p, n) or ""
                if not re.search(r"\bMOVE\s+" + str(t) + r"\s+TO\s+" + re.escape(f["dipende_da"]) + r"\b", t2):
                    err("relazioni", f"{p}:{n}: la riga non contiene MOVE {t} TO {f['dipende_da']}")
                if not (int(f["varia_da"]) <= t <= int(f["varia_a"])):
                    err("relazioni", f"{p}: {t} byte fuori dall'intervallo {f['varia_da']}-{f['varia_a']} dell'FD {f['fd']}")
        else:
            err("relazioni", f"{p} righe {r['righe']}: fonte_trasferita non ammessa '{ft}'")
    mosse = {(r["programma"], int(n)) for r in D.rel if r["verbo"] == "MOVE" for n in r["righe"].split(",")}
    for (p, n), x in sorted(io.items()):
        if (p, n) not in coperte:
            err("relazioni", f"{p}:{n}: {x['verbo']} {x['oggetto']} non coperta da alcuna relazione")
        elif x["verbo"] == "MOVE" and (p, n) not in mosse:
            err("relazioni", f"{p}:{n}: MOVE {x['struttura']} TO {x['oggetto']} non coperta da una relazione MOVE")
    # le radici collegate a un file (estremi di una relazione, senza ':') devono essere censite come record o righe di report
    classe = {}
    for c in D.cens:
        if c["radice"] != "-":
            st = c["frammento"].split()[1] if c["frammento"].startswith("COPY ") else stem(c["sorgente"])
            classe.setdefault(f"{st}.{c['radice']}", set()).add(c["classificazione"])
    for r in D.rel:
        for ref in (r["da"], r["a"]):
            if ":" in ref:
                continue
            cl = classe.get(ref)
            if not cl:
                err("relazioni", f"{r['programma']} righe {r['righe']}: {ref} non e' una radice del censimento")
            elif not cl <= {"record-di-file", "riga-di-report"}:
                err("relazioni", f"{r['programma']} righe {r['righe']}: {ref} e' letto o scritto in un file ma e' classificato {sorted(cl)}")
    for r in D.rel:
        for ref in (r["da"], r["a"]):
            if ":" in ref and ref.partition(":")[0] not in classe:
                err("relazioni", f"{r['programma']} righe {r['righe']}: la radice di {ref} non e' nel censimento")
    # trasferimenti di strutture intere verso i record scritti, ricavati dal sorgente completo: ognuno deve essere una
    # relazione MOVE e la struttura sorgente deve essere censita come record (o riga di report)
    for t in D.trasf:
        p, n = t["programma"], int(t["riga"])
        if not any(r["programma"] == p and r["verbo"] == "MOVE" and str(n) in r["righe"].split(",")
                   and nome_ref(r["da"]) == t["sorgente"] and nome_ref(r["a"]) == t["destinazione"] for r in D.rel):
            err("relazioni", f"{p}:{n}: MOVE {t['sorgente']} TO {t['destinazione']} (struttura intera verso il record "
                             f"{t['record']}) non coperta da una relazione")
        chiavi = [k for k in classe if k.endswith("." + t["radice_sorgente"])
                  and (k.startswith(stem(p) + ".") or k.split(".")[0] in {stem(x["sorgente"]) for x in D.cens if x["tipo"] == "copybook"})]
        if not chiavi:
            err("censimento", f"{p}:{n}: la struttura {t['radice_sorgente']}, trasferita intera nel record {t['record']}, "
                              f"non e' nel censimento")
        elif not any(classe[k] <= {"record-di-file", "stato-di-conversazione", "riga-di-report"} for k in chiavi):
            err("censimento", f"{p}:{n}: la struttura {t['radice_sorgente']}, trasferita nel record {t['record']}, e' classificata "
                              f"{sorted(set().union(*(classe[k] for k in chiavi)))}")
    usate = {ref.partition(":")[0] for r in D.rel for ref in (r["da"], r["a"])}
    for c in D.cens:
        if c["tipo"] in ("WORKING-STORAGE", "LINKAGE") and f"{stem(c['sorgente'])}.{c['radice']}" not in usate:
            err("relazioni", f"{c['sorgente']} {c['radice']}: struttura di lavoro censita ma in nessuna relazione")
    ok(f"relazioni: {len(D.rel)} relazioni; {len(io)} istruzioni READ/WRITE/REWRITE e MOVE verso un 01 di FD dei programmi batch "
       f"tutte coperte; estremi censiti come record o righe di report; lunghezze uguali a cb2xml")


# ---------------------------------------------------------------- B. contratti

def controlla_contratti(D):
    segnalate = {(r["contratto"], r["campo"]) for r in leggi_tsv(os.path.join(D.exp, "ridefinizioni-segnalate.tsv"))}
    rs_per_c = {}
    for f in D.files:
        for d in D.define:
            if d["tipo"] == "CLUSTER" and d["nome"] == f["dataset"]:
                rs_per_c.setdefault(f["contratto"], []).append(d)
    fd_per_c = {}
    for c in D.cens:
        if c["tipo"].startswith("FD:"):
            f = next((x for x in D.fd if x["programma"] == c["sorgente"] and x["fd"] == c["tipo"][3:]), None)
            if f:
                fd_per_c.setdefault(c["contratto"], []).append(f)
    for k, rr in sorted(D.contratti.items()):
        if not rr or rr[0]["livello"] not in ("01", "1"):
            err("contratti", f"{k}: la prima riga non e' la radice di livello 01")
            continue
        tot = rr[0]["lunghezza"]
        el = [r for r in rr if r["tipo"] == "elementare"]
        for area in sorted({r["area"] for r in el}):
            rows = sorted((r for r in el if r["area"] == area), key=lambda r: r["offset"])
            if area == "-":
                start, lung = 0, tot
            else:
                a = next((r for r in rr if r["campo"] == area and r["redefines"] != "-"), None)
                if a is None:
                    err("contratti", f"{k}: area {area} senza la voce con REDEFINES")
                    continue
                start, lung = a["offset"], a["lunghezza"]
            pos = start
            for r in rows:
                if r["offset"] != pos:
                    err("contratti", f"{k}: {'buco' if r['offset'] > pos else 'sovrapposizione'} prima di {r['campo']} "
                                     f"(area {area}): offset {r['offset']}, atteso {pos}")
                pos = r["offset"] + r["lunghezza"]
            if pos != start + lung:
                err("contratti", f"{k}: i campi dell'area {area} finiscono a {pos}, l'area a {start + lung}")
        somma = sum(r["lunghezza"] for r in el if r["area"] == "-")
        if somma != tot:
            err("contratti", f"{k}: somma delle lunghezze {somma} diversa dalla lunghezza del record {tot}")
        # aree ridefinite: stessa estensione dell'area ridefinita, oppure segnalate
        for r in rr:
            if r["redefines"] == "-":
                continue
            padre = r["percorso"].rpartition("/")[0]
            t = next((x for x in rr if x["campo"] == r["redefines"] and x["percorso"].rpartition("/")[0] == padre), None)
            if t is None:
                err("contratti", f"{k}: {r['campo']} ridefinisce {r['redefines']}, che non e' nel contratto")
            elif t["offset"] != r["offset"]:
                err("contratti", f"{k}: {r['campo']} a offset {r['offset']}, l'area ridefinita {t['campo']} a {t['offset']}")
            elif t["lunghezza"] != r["lunghezza"] and (k, r["campo"]) not in segnalate:
                err("contratti", f"{k}: {r['campo']} ({r['lunghezza']} byte) ridefinisce {t['campo']} ({t['lunghezza']} byte) e non e' segnalata")
        # RECORDSIZE e FD
        for d in rs_per_c.get(k, []):
            if intero(d["recordsize_max"]) != tot:
                err("contratti", f"{k}: lunghezza {tot}, RECORDSIZE massimo {d['recordsize_max']} in {d['jcl']}:{d['riga']}")
        for f in fd_per_c.get(k, []):
            if f["contiene"] != "-" and intero(f["contiene"]) != tot:
                err("contratti", f"{k}: lunghezza {tot}, RECORD CONTAINS {f['contiene']} in {f['programma']}:{f['riga']}")
            if f["varia_a"] != "-" and intero(f["varia_a"]) != tot:
                err("contratti", f"{k}: lunghezza {tot}, massimo del record variabile {f['varia_a']} in {f['programma']}:{f['riga']}")
        # PIC, USAGE, segno, cifre
        for r in el:
            if r["pic"] == "-":
                err("contratti", f"{k}: campo elementare {r['campo']} senza PIC")
                continue
            lp = lunghezza_da_pic(r["pic"], r["usage"])
            if lp != r["lunghezza"]:
                err("contratti", f"{k}: {r['campo']} PIC {r['pic']} {r['usage']}: {r['lunghezza']} byte nel contratto, {lp} calcolati dalla PIC")
            segno = "S" if r["pic"].upper().startswith("S") else "-"
            if r["segno"] != segno:
                err("contratti", f"{k}: {r['campo']} segno '{r['segno']}', la PIC {r['pic']} dice '{segno}'")
            if RE_NUM.match(r["pic"].upper()):
                ci, cd = cifre_da_pic(r["pic"])
                if (intero(r["cifre_intere"]), intero(r["cifre_decimali"])) != (ci, cd):
                    err("contratti", f"{k}: {r['campo']} cifre {r['cifre_intere']}+{r['cifre_decimali']}, la PIC {r['pic']} ne ha {ci}+{cd}")
            elif (r["cifre_intere"], r["cifre_decimali"]) != ("-", "-"):
                err("contratti", f"{k}: {r['campo']} non numerico con cifre {r['cifre_intere']}+{r['cifre_decimali']}")
    ok(f"contratti: {len(D.contratti)} contratti senza buchi ne' sovrapposizioni, somme = lunghezze = RECORDSIZE/FD, "
       f"lunghezze, segno e cifre di ogni campo uguali al calcolo dalla PIC")


def controlla_tracciati(D):
    """Nomi, livelli, ordine, PIC, USAGE, OCCURS, REDEFINES di cb2xml contro il testo del sorgente; lunghezze contro la PIC."""
    per_id_t, per_id_v = {}, {}
    for t in D.trac:
        per_id_t.setdefault(t["id"], []).append(t)
    for v in D.voci:
        per_id_v.setdefault(v["id"], []).append(v)
    n = 0
    for j in D.lavori:
        tt, vv = per_id_t.get(j["id"], []), per_id_v.get(j["id"], [])
        if len(tt) != len(vv):
            err("tracciati", f"{j['id']}: {len(tt)} voci secondo cb2xml, {len(vv)} nel sorgente")
        for t, v in zip(tt, vv):
            n += 1
            gruppo = t["pic"] == "-"
            atteso = (v["livello"], v["nome"], v["pic"].upper(), v["occurs"], v["redefines"])
            trovato = (t["livello"].zfill(2), t["nome"], t["pic"].upper(), t["occurs"], t["redefines"])
            if atteso != trovato:
                err("tracciati", f"{j['id']} (riga {v['riga']}): sorgente {atteso}, cb2xml {trovato}")
                break
            if not gruppo:
                u = v["usage"] if v["usage"] != "-" else "DISPLAY"
                if u != t["usage"]:
                    err("tracciati", f"{j['id']} {t['nome']}: USAGE {u} nel sorgente, {t['usage']} da cb2xml")
                lp = lunghezza_da_pic(t["pic"], t["usage"])
                if lp != intero(t["lunghezza"]):
                    err("tracciati", f"{j['id']} {t['nome']}: PIC {t['pic']} {t['usage']} = {lp} byte, cb2xml {t['lunghezza']}")
    # ogni contratto ripete, nell'ordine, le voci del tracciato della sua radice (primo elemento degli OCCURS)
    for k, rr in D.contratti.items():
        c = next((x for x in D.cens if x["contratto"] == k and not x["frammento"].startswith("COPY ")), None)
        if c is None:
            continue
        tt = [t for t in per_id_t.get(id_lavoro(c), []) if t["radice"] == c["radice"]]
        primi = [r for r in rr if r["indice"] == "-" or set(r["indice"].split(",")) == {"1"}]
        a = [(t["nome"], t["livello"], t["pic"], t["redefines"], t["occurs"]) for t in tt]
        b = [(r["campo"], r["livello"], r["pic"], r["redefines"], r["occurs"]) for r in primi]
        if a != b:
            diff = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
            err("tracciati", f"contratto {k}: voce {diff + 1} diversa dal tracciato di cb2xml "
                             f"({b[diff] if diff < len(b) else 'assente'} contro {a[diff] if diff < len(a) else 'assente'})")
        for r, t in zip(primi, tt):
            if r["offset"] != int(t["offset"]) or r["lunghezza"] != int(t["lunghezza"]):
                err("tracciati", f"contratto {k}: {r['campo']} offset/lunghezza {r['offset']}/{r['lunghezza']}, cb2xml {t['offset']}/{t['lunghezza']}")
                break
    ok(f"tracciati: {n} voci di cb2xml uguali al sorgente per nome, livello, ordine, PIC, USAGE, OCCURS, REDEFINES; "
       f"lunghezze uguali al calcolo dalla PIC; contratti uguali ai tracciati")


# ---------------------------------------------------------------- C. attesi scritti a mano

# Contenuto minimo degli attesi, fissato dai criteri di accettazione di #3: un file di attesi svuotato o accorciato non deve
# far passare il controllo.
LUNGHEZZE_SPEC = {"CSUSR01Y": 80, "CVACT01Y": 300, "CVACT02Y": 150, "CVACT03Y": 50, "CVCUS01Y": 500, "CVTRA05Y": 350,
                  "CVTRA06Y": 350, "CVTRA01Y": 50, "CVTRA02Y": 50, "CVTRA03Y": 60, "CVTRA04Y": 60, "CVEXPORT": 500}
CAMPI_SPEC = ("CVACT01Y.ACCOUNT-RECORD", "CVTRA01Y.TRAN-CAT-BAL-RECORD", "CVEXPORT.EXPORT-RECORD")
DISCORDANZE_SPEC = ("chiave-unicita:AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX:", "chiave-allineamento:AWS.M2.CARDDEMO.EXPORT.DATA:")


def controlla_presenza_attesi(D):
    lun = {e["copybook"]: intero(e["lunghezza"]) for e in leggi_tsv(os.path.join(D.exp, "lunghezze.tsv"))}
    for cb, n in LUNGHEZZE_SPEC.items():
        if lun.get(cb) != n:
            err("attesi", f"lunghezze.tsv: {cb} deve valere {n} (criterio di accettazione), trovato {lun.get(cb)}")
    campi = {}
    for e in leggi_tsv(os.path.join(D.exp, "campi.tsv")):
        campi[e["contratto"]] = campi.get(e["contratto"], 0) + 1
    for k in CAMPI_SPEC:
        if not campi.get(k):
            err("attesi", f"campi.tsv: mancano i campi attesi di {k}")
    if not any(k.startswith("CBACT01C.") and k != "CBACT01C.VBR-REC" for k in campi):
        err("attesi", "campi.tsv: manca una struttura di lavoro di CBACT01C")
    if len(leggi_tsv(os.path.join(D.exp, "relazioni-CBACT01C.tsv"))) != 4:
        err("attesi", "relazioni-CBACT01C.tsv: attese 4 relazioni (due MOVE e due WRITE del file variabile)")
    ids = [e["id"] for e in leggi_tsv(os.path.join(D.exp, "discordanze-attese.tsv"))]
    for pre in DISCORDANZE_SPEC:
        if not any(i.startswith(pre) for i in ids):
            err("attesi", f"discordanze-attese.tsv: manca la discordanza chiesta dalla specifica {pre}...")
    cl = {(e["dataset"], e["chiave"]) for e in leggi_tsv(os.path.join(D.exp, "chiavi-dataset.tsv"))}
    if ("AWS.M2.CARDDEMO.EXPORT.DATA", "primaria") not in cl or ("AWS.M2.CARDDEMO.CARDXREF.VSAM.KSDS", "alternativa") not in cl:
        err("attesi", "chiavi-dataset.tsv: mancano le chiavi del file di export o dell'indice alternativo di XREFFILE")
    ok("attesi: presenti i contenuti chiesti dai criteri di accettazione (12 lunghezze; campi di CVACT01Y, CVTRA01Y, "
       "CVEXPORT e di una struttura di CBACT01C; relazioni del file variabile; due discordanze)")


def controlla_attesi(D):
    for e in leggi_tsv(os.path.join(D.exp, "lunghezze.tsv")):
        k = f"{e['copybook']}.{e['radice']}"
        rr = D.contratti.get(k)
        if not rr:
            err("lunghezze", f"{k}: contratto assente")
            continue
        if rr[0]["lunghezza"] != int(e["lunghezza"]):
            err("lunghezze", f"{k}: lunghezza attesa {e['lunghezza']}, contratto {rr[0]['lunghezza']}")
        r = next((x for x in D.radici if x["id"] == e["copybook"] and x["radice"] == e["radice"]), None)
        if r is None or intero(r["lunghezza"]) != int(e["lunghezza"]):
            err("lunghezze", f"{k}: lunghezza attesa {e['lunghezza']}, cb2xml {r['lunghezza'] if r else 'assente'}")
    ok("lunghezze attese dei 12 record uguali a contratti e cb2xml")
    attesi = {}
    for e in leggi_tsv(os.path.join(D.exp, "campi.tsv")):
        attesi.setdefault(e["contratto"], []).append(e)
    for k, ee in attesi.items():
        rr = D.contratti.get(k)
        if rr is None:
            err("campi", f"{k}: contratto assente")
            continue
        if SELEZIONE.get(k) == "ridefinite":
            bersagli = {r["redefines"] for r in rr}
            rr = [r for r in rr if r["area"] != "-" or r["campo"] in bersagli]
        if len(rr) != len(ee):
            err("campi", f"{k}: {len(ee)} righe attese, {len(rr)} nel contratto")
        for i, (e, r) in enumerate(zip(ee, rr), 1):
            trovato = {"campo": r["campo"], "indice": r["indice"], "offset": str(r["offset"]), "lunghezza": str(r["lunghezza"]),
                       "tipo": categoria(r), "scala": r["cifre_decimali"], "segno": r["segno"]}
            for col in ("campo", "indice", "offset", "lunghezza", "tipo", "scala", "segno"):
                if e[col] != trovato[col]:
                    err("campi", f"{k} riga {i} ({e['campo']}): {col} atteso {e[col]}, contratto {trovato[col]}")
    ok(f"campi attesi scritti a mano uguali ai contratti: {', '.join(f'{k} ({len(v)} righe)' for k, v in attesi.items())}")
    for e in leggi_tsv(os.path.join(D.exp, "relazioni-CBACT01C.tsv")):
        if not any(all(r[c] == e[c] for c in ("programma", "verbo", "righe", "da", "a", "trasferita")) for r in D.rel):
            err("relazioni-attese", f"relazione attesa assente da relazioni.tsv: {e['verbo']} {e['righe']} {e['da']} -> {e['a']} ({e['trasferita']} byte)")
        for ref in (e["da"], e["a"]):
            if ref not in D.contratti:
                err("relazioni-attese", f"{ref}: contratto assente")
    ok("relazioni attese del file variabile di CBACT01C presenti, con i contratti delle strutture di lavoro")


# ---------------------------------------------------------------- C bis. chiavi e discordanze

def controlla_chiavi(D):
    att = {}
    for e in leggi_tsv(os.path.join(D.exp, "chiavi-dataset.tsv")):
        att[(e["dataset"], e["chiave"], e["nome"])] = (e["offset"], e["lunghezza"], e["campi"], e["copertura"])
    trov = {}
    for r in D.chiavi:
        if r["fonte"].startswith("JCL DEFINE"):
            trov.setdefault((r["dataset"], r["chiave"], r["nome"]), set()).add((r["offset"], r["lunghezza"], r["campi"], r["copertura"]))
    for k in sorted(set(att) | set(trov)):
        if k not in trov:
            err("chiavi", f"{k[0]} chiave {k[1]} {k[2]}: attesa {att[k]}, assente dalle chiavi generate")
        elif k not in att:
            err("chiavi", f"{k[0]} chiave {k[1]} {k[2]}: generata {sorted(trov[k])}, non attesa")
        elif trov[k] != {att[k]}:
            err("chiavi", f"{k[0]} chiave {k[1]} {k[2]}: attesa {att[k]}, generata {sorted(trov[k])}")
    attp = {}
    for e in leggi_tsv(os.path.join(D.exp, "chiavi-programmi.tsv")):
        attp[(e["programma"], e["chiave"], e["nome"])] = (e["offset"], e["lunghezza"], e["unicita"], e["nel_record_fd"])
    trovp = {}
    for r in D.chiavi:
        if r["fonte"].startswith("SELECT+FD"):
            p = r["fonte"].split()[1]
            trovp[(p, r["chiave"], r["nome"])] = (r["offset"], r["lunghezza"], r["unicita"], "no" if "fuori dal record" in r["fonte"] else "si")
    for k in sorted(set(attp) | set(trovp)):
        if trovp.get(k) != attp.get(k):
            err("chiavi", f"{k[0]} chiave {k[1]} {k[2]}: attesa {attp.get(k)}, generata {trovp.get(k)}")
    ok(f"chiavi: {len(att)} chiavi dei file VSAM e {len(attp)} chiavi delle SELECT uguali agli attesi scritti a mano")


def controlla_discordanze(D):
    md = open(os.path.join(D.docs, "discordanze.md"), encoding="utf-8").read()
    ids = {r["id"] for r in D.rilevate}
    for r in D.rilevate:
        if f"`{r['id']}`" not in md:
            err("discordanze", f"discordanza rilevata e assente da discordanze.md: {r['id']}")
    for e in leggi_tsv(os.path.join(D.exp, "discordanze-attese.tsv")):
        if e["id"] not in ids:
            err("discordanze", f"discordanza attesa non rilevata dal confronto delle fonti: {e['id']}")
        if f"`{e['id']}`" not in md:
            err("discordanze", f"discordanza attesa assente da discordanze.md: {e['id']}")
    tipi = {r["tipo"] for r in D.rilevate} | {"chiave-unicita", "chiave-allineamento", "chiave-fuori-dal-record", "chiave-posizione",
                                              "chiave-tipo", "catalogo", "recordsize", "define-multiple", "dd-assente", "lrecl",
                                              "nessun-jcl", "fd-lunghezza", "lunghezze-diverse", "ridefinizione-estesa"}
    for m in re.finditer(r"`([a-z-]+):([^`]+)`", md):
        if m.group(1) in tipi and f"{m.group(1)}:{m.group(2)}" not in ids:
            err("discordanze", f"discordanze.md cita {m.group(1)}:{m.group(2)}, che il confronto delle fonti non rileva")
    ok(f"discordanze: {len(ids)} rilevate, tutte in discordanze.md; le attese dalla specifica sono rilevate e scritte")


# ---------------------------------------------------------------- E. assegnazioni e file

def controlla_assegnazioni(D):
    sel = {(s["programma"], s["file"]) for s in D.sel}
    ass = [(a["programma"], a["file"]) for a in D.asse]
    for k in sorted(sel - set(ass)):
        err("assegnazioni", f"SELECT {k[1]} di {k[0]} senza assegnazione")
    for k in sorted(set(ass) - sel):
        err("assegnazioni", f"assegnazione {k[1]} di {k[0]} senza SELECT nel sorgente")
    for k in sorted({x for x in ass if ass.count(x) > 1}):
        err("assegnazioni", f"assegnazione ripetuta: {k}")
    dd_sel = {(s["programma"], s["file"]): s["assign"] for s in D.sel}
    for a in D.asse:
        if dd_sel.get((a["programma"], a["file"])) not in (None, a["dd"]):
            err("assegnazioni", f"{a['programma']} {a['file']}: ASSIGN TO {dd_sel[(a['programma'], a['file'])]}, assegnazione {a['dd']}")
        if a["jcl"] == "-":
            continue
        righe = D.righe(a["jcl"])
        testo = "\n".join(righe)
        pgms = re.findall(r"PGM=([A-Z0-9]+)", testo)
        prog = stem(a["programma"])
        chiamato = any(re.search(r"CALL\s+'" + prog + "'", "\n".join(D.righe(p["programma"]))) for p in D.progr if stem(p["programma"]) in pgms)
        if prog not in pgms and not chiamato:
            err("assegnazioni", f"{a['jcl']}: nessun passo esegue {prog} (ne' un programma che lo chiama)")
        if a["riga_dd"] != "-":
            n = int(a["riga_dd"])
            if not re.match(r"^//" + re.escape(a["dd"]) + r"\s+DD\b", righe[n - 1]):
                err("assegnazioni", f"{a['jcl']}:{n}: la riga non e' la DD {a['dd']}")
            if a["dataset"] not in righe[int(a["riga_dsn"]) - 1] or "DSN=" not in righe[int(a["riga_dsn"]) - 1]:
                err("assegnazioni", f"{a['jcl']}:{a['riga_dsn']}: la riga non contiene DSN={a['dataset']}")
        elif re.search(r"^//" + re.escape(a["dd"]) + r"\s+DD\b", testo, re.M):
            err("assegnazioni", f"{a['jcl']}: la DD {a['dd']} esiste ma l'assegnazione dice assente")
        if a["riga_dcb"] != "-":
            t = righe[int(a["riga_dcb"]) - 1]
            if f"LRECL={a['lrecl']}" not in t or f"RECFM={a['recfm']}" not in t:
                err("assegnazioni", f"{a['jcl']}:{a['riga_dcb']}: la riga non contiene LRECL={a['lrecl']} e RECFM={a['recfm']}")
    # file.tsv: il contratto dichiarato per un dataset deve essere il tracciato con cui i programmi batch assegnati a quel
    # dataset leggono o scrivono il record (COPY nell'FD, READ ... INTO, WRITE/REWRITE ... FROM), quando c'e' questa evidenza
    cpy = {stem(c["sorgente"]) for c in D.cens if c["tipo"] == "copybook"}
    evid = {}
    for a in D.asse:
        fdr = next((c for c in D.cens if c["sorgente"] == a["programma"] and c["tipo"] == "FD:" + a["file"]), None)
        if fdr is None or a["dataset"] in ("-", ""):
            continue
        e = evid.setdefault(a["dataset"], set())
        if fdr["frammento"].startswith("COPY "):
            e.add(fdr["contratto"])
            continue
        ref = f"{stem(fdr['sorgente'])}.{fdr['radice']}"
        for r in D.rel:
            if r["programma"] != a["programma"]:
                continue
            altro = r["a"] if r["da"] == ref and r["verbo"] == "READ-INTO" else (r["da"] if r["a"] == ref and r["verbo"] in ("WRITE-FROM", "REWRITE-FROM") else None)
            if altro and ":" not in altro and altro.split(".")[0] in cpy:
                e.add(altro)
    nevid = 0
    for f in D.files:
        e = evid.get(f["dataset"], set())
        if e:
            nevid += 1
            if e != {f["contratto"]}:
                err("assegnazioni", f"file.tsv: {f['dataset']} ha contratto {f['contratto']}, ma i programmi lo leggono o scrivono con {sorted(e)}")
    clusters = {d["nome"] for d in D.define if d["tipo"] == "CLUSTER"}
    fset = {f["dataset"] for f in D.files}
    for x in sorted(clusters - fset):
        err("assegnazioni", f"DEFINE CLUSTER {x} assente da file.tsv")
    for x in sorted(fset - clusters):
        err("assegnazioni", f"file.tsv: {x} non e' definito da alcuna DEFINE CLUSTER")
    for f in D.files:
        if f["contratto"] != "-" and f["contratto"] not in D.contratti:
            err("assegnazioni", f"file.tsv: contratto {f['contratto']} di {f['dataset']} inesistente")
    ok(f"assegnazioni: {len(D.asse)} SELECT ricondotte alle DD (righe verificate sul JCL); {len(fset)} DEFINE CLUSTER in file.tsv, "
       f"{nevid} con il contratto confermato dai programmi che li usano")


FINE_ISTRUZIONE = re.compile(r"(?<![A-Z0-9-])(MOVE|STRING|UNSTRING|INITIALIZE|ADD|SUBTRACT|COMPUTE|MULTIPLY|DIVIDE|IF|ELSE|"
                             r"END-IF|PERFORM|WRITE|REWRITE|READ|DISPLAY|SET|CALL|EVALUATE|WHEN|END-EVALUATE|GO|"
                             r"END-STRING|END-UNSTRING|END-COMPUTE|CONTINUE|EXIT|GOBACK)(?![A-Z0-9-])|\.(\s|$)")


def testo_istruzione(D, p, n, verbo):
    """Testo dell'istruzione 'verbo' che inizia alla riga n: dal verbo fino al verbo successivo o al punto (al massimo
    20 righe). Implementazione indipendente da struttura.py, sul testo del sorgente. None se a quella riga il verbo manca."""
    t = D.codice(p, n) or ""
    m = re.search(r"(?<![A-Z0-9-])" + re.escape(verbo) + r"(?![A-Z0-9-])", t)
    if not m:
        return None
    testo = t[m.end():]
    for k in range(n + 1, n + 20):
        testo += " " + (D.codice(p, k) or "")
    f = FINE_ISTRUZIONE.search(testo)
    return testo[:f.start()] if f else testo


def controlla_istruzioni(D):
    """Ogni voce di trasferimenti e non coperti: la riga citata deve aprire un'istruzione del tipo dichiarato che contiene
    la destinazione (non un'istruzione successiva). Poi la controprova testuale delle MOVE di strutture intere."""
    for nome, righe in (("trasferimenti", D.trasf), ("non-coperti", D.nonc)):
        for r in righe:
            tipo = r.get("tipo", r.get("verbo", "MOVE"))
            verbo = re.search(r"\(([A-Z]+)\)", tipo).group(1) if tipo.startswith("aritmetica") else tipo.split()[0]
            testo = testo_istruzione(D, r["programma"], int(r["riga"]), verbo)
            if testo is None:
                err(nome, f"{r['programma']}:{r['riga']}: la riga non apre un'istruzione {verbo}")
            elif not re.search(r"(?<![A-Z0-9-])" + re.escape(r["destinazione"]) + r"(?![A-Z0-9-])", testo):
                err(nome, f"{r['programma']}:{r['riga']}: l'istruzione {verbo} che inizia a questa riga non ha la destinazione "
                          f"{r['destinazione']}")
    # controprova indipendente: MOVE <nome> TO <nome> su una riga, con il primo nome dichiarato 01/77 o gruppo
    from controprova import indice_copie, mosse_di_strutture
    copie = indice_copie([r["path"] for r in D.manifesto if r["type"] == "copybook" and r["path"].startswith("app/cpy/")])
    escluse = {e["destinazione"] for e in leggi_tsv(os.path.join(D.exp, "controprova-escluse.tsv"))}
    tr = {(t["programma"], t["riga"]): t for t in D.trasf}
    trovate, n = set(), 0
    for p in (x["programma"] for x in D.progr if x["batch"] == "si"):
        for riga, a, b in mosse_di_strutture(D.legacy, p, copie):
            n += 1
            trovate.add((p, str(riga)))
            if (p, str(riga)) in tr:
                continue
            if b not in escluse:
                err("controprova", f"{p}:{riga}: MOVE {a} TO {b} e' un trasferimento di struttura intera che non e' tra i "
                                   f"trasferimenti e la cui destinazione non e' dichiarata esclusa")
    for k, t in sorted(tr.items()):
        if k not in trovate:
            err("controprova", f"{k[0]}:{k[1]}: trasferimento {t['sorgente']} -> {t['destinazione']} non trovato dalla controprova")
    ok(f"istruzioni: {len(D.trasf)} trasferimenti e {len(D.nonc)} punti non coperti aprono alla riga citata un'istruzione del "
       f"tipo dichiarato con quella destinazione; controprova testuale: {n} MOVE di strutture intere, "
       f"{len(trovate & set(tr))} tra i trasferimenti, le altre verso destinazioni dichiarate escluse")


def controlla_composizioni(D):
    """Posizione nel record dei campi delle strutture trasferite: generata dalle relazioni MOVE e da cb2xml, contro gli attesi."""
    gen = {(c["struttura"], c["record"], c["campo_record"], c["campo"], c["indice"]): c for c in D.comp}
    att = leggi_tsv(os.path.join(D.exp, "composizioni.tsv"))
    for e in att:
        g = gen.get((e["struttura"], e["record"], e["campo_record"], e["campo"], e["indice"]))
        if g is None:
            err("composizioni", f"{e['struttura']} -> {e['record']}: campo {e['campo']} atteso e assente dalle composizioni generate")
        elif (g["offset_nel_record"], g["lunghezza"]) != (e["offset_nel_record"], e["lunghezza"]):
            err("composizioni", f"{e['struttura']} -> {e['record']}: {e['campo']} atteso a offset {e['offset_nel_record']} per "
                                f"{e['lunghezza']} byte, generato a {g['offset_nel_record']} per {g['lunghezza']}")
    if not any(e["struttura"] == "CBTRN02C.WS-VALIDATION-TRAILER" for e in att):
        err("attesi", "composizioni.tsv: manca la composizione del trailer di validazione di CBTRN02C")
    strutture = {r["da"] for r in D.rel if r["verbo"] == "MOVE" and r["da"] in D.contratti}
    for s in sorted(strutture - {c["struttura"] for c in D.comp}):
        err("composizioni", f"{s}: struttura trasferita in un record senza composizione generata")
    ok(f"composizioni: {len(D.comp)} campi di {len(strutture)} strutture trasferite con la loro posizione nel record; "
       f"{len(att)} attesi scritti a mano coincidono")


def main(argv):
    D = Dati(*argv[1:7])
    for nome, f in (("A. censimento", controlla_censimento), ("A. relazioni", controlla_relazioni),
                    ("B. contratti", controlla_contratti), ("B. tracciati", controlla_tracciati),
                    ("C. attesi", controlla_attesi), ("C. presenza degli attesi", controlla_presenza_attesi), ("C. chiavi", controlla_chiavi), ("C. discordanze", controlla_discordanze),
                    ("E. assegnazioni", controlla_assegnazioni), ("F. composizioni", controlla_composizioni),
                    ("G. istruzioni e controprova", controlla_istruzioni)):
        print(f"{nome}")
        INIZIO[0] = len(ERRORI)
        f(D)
        if len(ERRORI) > INIZIO[0]:
            print(f"   {len(ERRORI) - INIZIO[0]} errori")
    for e in ERRORI:
        print(e)
    if ERRORI:
        print(f"VERIFICA FALLITA: {len(ERRORI)} errori")
        return 1
    print("VERIFICA SUPERATA")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
