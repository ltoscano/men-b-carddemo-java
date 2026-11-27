"""Prove negative delle sentinelle dei tracciati (issue #43).

Uso: negativi.py LEGACY CONTRATTI CONTRATTI_TSV SENTINELLE VISTE

Ogni prova costruisce un "mondo" privato (copia temporanea di contratti, contratti.tsv, sentinelle e viste.tsv, nel
container), vi applica una sola alterazione, esegue la verifica completa (controlli.verifica) e pretende che fallisca
per il motivo dichiarato. Il legacy non si altera mai (volume in sola lettura).

Mutazioni del contratto (copie private; metadati ridondanti coerenti: pic, usage, segno, cifre, lunghezza, offset; i
gruppi sono ricalcolati dai figli; la geometria di ogni vista resta chiusa, senza buchi ne' sovrapposizioni, ed e'
verificata prima di eseguire la prova). Diagnosi attesa: errori [decodifica] esattamente sui campi toccati
(identita': ordinale e indici), con valore atteso e ottenuto, e nessun errore di altri gruppi:
  1 scambio      ogni coppia di campi adiacenti (in una vista) di uguale lunghezza: offset scambiati
  2 confine      ogni confine fra campi adiacenti: spostato di un byte nei due versi (il campo a sinistra si allunga e
                 quello a destra si accorcia, o viceversa), in tutte le viste in cui il confine esiste; le coppie che
                 condividono un campo (fuori dalle REDEFINES) formano una sola mutazione. Non applicabile se un campo
                 e' binario (2/4/8 byte) o scenderebbe a zero byte o cifre, o se la geometria non resterebbe chiusa
  3 scala        ogni campo numerico: una cifra passa dalla parte intera ai decimali (o viceversa)
    segno        ogni campo con segno: segno tolto
    picture      ogni campo numerico: PICTURE accorciata di una cifra; se la lunghezza cambia, il campo adiacente della
                 vista assorbe il byte (diagnosi attesa su entrambi)
    tipo         ogni campo: COMP-3 letto come DISPLAY della stessa lunghezza, binario letto come alfanumerico, DISPLAY
                 numerico letto come alfanumerico, alfanumerico letto come DISPLAY numerico
    oltre        (solo il record variabile) campo spostato di un byte: rifiuto del codec CampoIncompleto
  4 vista        CVEXPORT: le etichette di due aree REDEFINES scambiate fra loro (diagnosi: [copertura])
Mutazioni delle sentinelle e degli elenchi:
  5 campo-tolto (anche "dichiarazione saltata"), atteso-duplicato, contratto-senza-sentinella, byte-alterato,
    valore-alterato, vista-mancante, vista-in-piu', contratto-in-piu'
  6 valori-uguali: due campi dello stesso record con lo stesso valore (diagnosi: [unicita])
  sorgente: riga-sbagliata, picture-sbagliata, omogenei-scambiati, nomi-scambiati, errore-ripetuto (stesso scambio
    nella sentinella e nel contratto: la decodifica passa, la verifica sorgente no), lunghezza-sbagliata,
    fonte-sbagliata
  valori: segno-positivo, decimale-con-zero, cifra-mancante, testo-vuoto
Uscita 1 se una prova non fallisce, o non fallisce per il motivo dichiarato.
"""
import copy
import os
import re
import shutil
import signal
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, "/analysis/data-codec/glue")
import codec  # noqa: E402
from censimento import classifica  # noqa: E402
from comune import leggi_tsv, scrivi_tsv, valore_a_testo  # noqa: E402
from controlli import VARIABILE, aree_contratto, ordina_contratto, verifica, vista_contratto  # noqa: E402
from sentinella import COLONNE, componi, esa, leggi  # noqa: E402

RE_DEC = re.compile(r"^ERRORE \[decodifica\] (\S+)@(\S+)/(\S+) #([0-9]+)(\([0-9,]+\))? (\S+): ")
_DEC = "errori [decodifica] esattamente sui campi toccati (campo, valore atteso, valore ottenuto), nessun altro gruppo"
DIAGNOSI = {
    "scambio": _DEC, "confine": _DEC, "scala": _DEC, "segno": _DEC, "picture": _DEC, "tipo": _DEC,
    "oltre": "[decodifica] rifiuto del codec CampoIncompleto sul campo spostato",
    "vista": "[copertura] campi delle due viste senza atteso / atteso senza campo",
    "campo-tolto": "[sorgente] dichiarazione saltata e [copertura] campo della vista senza atteso",
    "atteso-duplicato": "[copertura] atteso duplicato nella sentinella",
    "contratto-senza-sentinella": "[copertura] contratto senza sentinella",
    "contratto-in-piu": "[copertura] contratto dei copybook senza coppia e senza sentinella",
    "byte-alterato": "[decodifica] solo sul campo del byte alterato (ammesso [coerenza])",
    "valore-alterato": "[decodifica] solo sul campo del valore alterato (ammesso [coerenza])",
    "vista-mancante": "[copertura] vista (area REDEFINES del contratto) senza sentinella",
    "vista-in-piu": "[copertura] vista di viste.tsv che non e' un'area REDEFINES del contratto",
    "valori-uguali": "[unicita] stessi byte e stesso valore",
    "riga-sbagliata": "[sorgente] alla riga dichiarata nome diverso o nessuna dichiarazione elementare",
    "picture-sbagliata": "[sorgente] PICTURE del sorgente diversa da quella della sentinella",
    "omogenei-scambiati": "[sorgente] righe non in ordine crescente",
    "nomi-scambiati": "[sorgente] nome del sorgente diverso da quello della sentinella",
    "errore-ripetuto": "solo [sorgente] righe non in ordine crescente (la decodifica passa)",
    "lunghezza-sbagliata": "[sorgente] i campi finiscono prima della lunghezza dichiarata",
    "fonte-sbagliata": "[sorgente] testo citato non alla riga dichiarata",
    "segno-positivo": "[valori] campo con segno senza valore negativo nella vista",
    "decimale-con-zero": "[valori] cifre decimali non tutte diverse da zero",
    "cifra-mancante": "[valori] il valore non usa tutte le cifre della PICTURE",
    "testo-vuoto": "[valori] valore tutto spazi o tutto zeri",
}
CATEGORIE_USAGE = {"display-senza-segno": "DISPLAY", "display-con-segno": "DISPLAY", "comp-3": "COMP-3", "comp": "COMP"}


# --- mondi --------------------------------------------------------------------------------------------------------------

class Banco:
    def __init__(self, legacy, contratti, contratti_tsv, sentinelle, viste):
        self.legacy = legacy
        self.tmp = tempfile.mkdtemp(prefix="issue43-negativi-")
        self.base = os.path.join(self.tmp, "base")
        os.makedirs(self.base)
        shutil.copytree(contratti, os.path.join(self.base, "contratti"))
        shutil.copy(contratti_tsv, os.path.join(self.base, "contratti.tsv"))
        shutil.copytree(sentinelle, os.path.join(self.base, "sentinelle"))
        shutil.copy(viste, os.path.join(self.base, "viste.tsv"))
        self.n = 0
        self.esiti = []          # (famiglia, nome, ok, diagnosi)
        self.non_applicabili = []  # (famiglia, oggetto, motivo)

    def mondo(self):
        self.n += 1
        m = os.path.join(self.tmp, f"m{self.n}")
        shutil.copytree(self.base, m)
        return m

    def esegui(self, m):
        es, _ = verifica(self.legacy, os.path.join(m, "contratti"), os.path.join(m, "contratti.tsv"),
                         os.path.join(m, "sentinelle"), os.path.join(m, "viste.tsv"))
        shutil.rmtree(m)
        return es.errori

    def prova(self, famiglia, nome, m, attesa):
        errori = self.esegui(m)
        ok, diag = attesa(errori)
        self.esiti.append((famiglia, nome, ok, diag))
        if ok:
            print(f"ok: {famiglia}: {nome} -> {len(errori)} errori; diagnosi:")
        else:
            print(f"PROVA NEGATIVA FALLITA: {famiglia}: {nome}; errori ottenuti ({len(errori)}):")
        for d in diag:
            print(f"    {d}")

    def na(self, famiglia, oggetto, motivo):
        self.non_applicabili.append((famiglia, oggetto, motivo))
        print(f"non applicabile: {famiglia}: {oggetto}: {motivo}")


# --- attese -------------------------------------------------------------------------------------------------------------

def _indici(t):
    return tuple(int(x) for x in t[1:-1].split(",")) if t else ()


def attesa_decodifica(contratto, idents, consentiti=(), sentinella=None, testo=None):
    """Errori [decodifica] esattamente sulle identita' attese (del contratto, ed eventualmente di una sola sentinella),
    nessun errore di gruppi diversi da [decodifica] e da quelli consentiti; se 'testo', ogni errore lo contiene."""
    attesi = set(idents)

    def p(errori):
        oss, fuori, altri, dec = set(), [], [], []
        for e in errori:
            if e.startswith("ERRORE [decodifica]"):
                m = RE_DEC.match(e)
                if not m or m.group(1) != contratto or (sentinella and m.group(3) != sentinella) \
                        or (testo and testo not in e):
                    fuori.append(e)
                else:
                    oss.add((int(m.group(4)), _indici(m.group(5))))
                    dec.append(e)
            elif not any(e.startswith(f"ERRORE [{g}]") for g in consentiti):
                altri.append(e)
        ok = oss == attesi and not fuori and not altri and bool(dec)
        if ok:
            return True, dec
        return False, (fuori + altri + dec)[:12] + [f"identita' osservate {sorted(oss)}, attese {sorted(attesi)}"]
    return p


def attesa_testi(*testi, gruppi=None):
    """Ogni testo atteso compare in almeno un errore; se 'gruppi', nessun errore fuori da quei gruppi."""
    def p(errori):
        trovati = [next((e for e in errori if (t.search(e) if isinstance(t, re.Pattern) else t in e)), None)
                   for t in testi]
        altri = [e for e in errori if gruppi and not any(e.startswith(f"ERRORE [{g}]") for g in gruppi)]
        ok = all(trovati) and not altri and bool(errori)
        if ok:
            return True, list(dict.fromkeys(trovati))
        mancanti = [getattr(t, "pattern", t) for t, x in zip(testi, trovati) if not x]
        return False, (altri + errori)[:12] + [f"testi attesi mancanti: {mancanti}"]
    return p


# --- contratti ----------------------------------------------------------------------------------------------------------

def leggi_contratto(path):
    testa, righe = leggi_tsv(path)
    ordina_contratto(righe)
    return testa, righe


def geom(r, contratto):
    cat, var, _, _, _ = classifica(dict(r, _contratto=contratto))
    return cat, codec.geometria(cat, var)


def imposta(r, cat, segno=False, intere=0, dec=0, n=0):
    if cat == "alfanumerico":
        var = f"X({n})"
        r.update(pic=var, usage="DISPLAY", segno="-", cifre_intere="-", cifre_decimali="-")
    else:
        if cat.startswith("display"):
            cat = "display-con-segno" if segno else "display-senza-segno"
        var = ("S" if segno else "") + f"9({intere})" + (f"V9({dec})" if dec else "")
        r.update(pic=var, usage=CATEGORIE_USAGE[cat], segno="S" if segno else "-", cifre_intere=str(intere),
                 cifre_decimali=str(dec))
    r["lunghezza"] = str(codec.geometria(cat, var).lunghezza)


def ridimensiona(r, delta, contratto, perche=False):
    """Allunga (delta>0) o accorcia di |delta| byte un campo cambiandone la PICTURE. Restituisce True se fatto, False
    se non si puo'; con perche=True restituisce invece None se fatto, altrimenti il motivo."""
    cat, g = geom(r, contratto)
    motivo = None
    if cat == "alfanumerico":
        if g.lunghezza + delta < 1:
            motivo = f"{r['campo']} {r['pic']}: un byte solo, non si accorcia"
        else:
            imposta(r, cat, n=g.lunghezza + delta)
    elif cat.startswith("display"):
        if g.intere + delta < 1:
            motivo = f"{r['campo']} {r['pic']}: una sola cifra intera, non si accorcia"
        else:
            imposta(r, cat, g.segno, g.intere + delta, g.decimali)
    elif cat == "comp-3":
        if g.intere + 2 * delta < 1:
            motivo = f"{r['campo']} {r['pic']} COMP-3: non si accorcia di un byte"
        else:
            imposta(r, cat, g.segno, g.intere + 2 * delta, g.decimali)
    else:
        motivo = f"{r['campo']} {r['pic']} COMP: un binario occupa solo 2, 4 o 8 byte"
    if motivo is None and int(r["lunghezza"]) != g.lunghezza + delta:
        raise SystemExit(f"ridimensiona: {r['campo']} non e' cambiato di {delta} byte")
    if perche:
        return motivo
    return motivo is None


def ricalcola_gruppi(righe):
    el = [r for r in righe if r["tipo"] == "elementare"]
    for g in righe:
        if g["tipo"] != "gruppo":
            continue
        figli = [e for e in el if e["percorso"].startswith(g["percorso"] + "/")]
        if figli:
            a = min(int(e["offset"]) for e in figli)
            b = max(int(e["offset"]) + int(e["lunghezza"]) for e in figli)
            g["offset"], g["lunghezza"] = str(a), str(b - a)


def chiusa(righe, lunghezza):
    """Ogni vista copre esattamente 0..lunghezza senza buchi ne' sovrapposizioni."""
    for v in ["base"] + aree_contratto(righe):
        pos = 0
        for r in sorted(vista_contratto(righe, v), key=lambda r: int(r["offset"])):
            if int(r["offset"]) != pos:
                return False
            pos += int(r["lunghezza"])
        if pos != lunghezza:
            return False
    return True


def scrivi_contratto(m, contratto, testa, righe):
    scrivi_tsv(os.path.join(m, "contratti", contratto + ".tsv"), testa, righe)


# --- sentinelle ---------------------------------------------------------------------------------------------------------

def file_sentinella(m, s):
    return os.path.join(m, "sentinelle", s["contratto"], s["sentinella"] + ".tsv")


def riscrivi_sentinella(path, campi=None, chiavi=None, ricomponi=False):
    """Riscrive una sentinella: 'campi' sostituisce la tabella (liste di 10 colonne), 'chiavi' le righe d'intestazione
    (dict chiave -> valore); con 'ricomponi' la riga record e' ricomposta dalla tabella (coerenza conservata)."""
    with open(path, encoding="utf-8") as f:
        righe = f.read().split("\n")
    i_tab = righe.index("\t".join(COLONNE))
    testa = righe[:i_tab + 1]
    if chiavi:
        for k, v in chiavi.items():
            testa = [k + "\t" + v if r.split("\t")[0] == k else r for r in testa]
    corpo = righe[i_tab + 1:] if campi is None else ["\t".join(str(x) for x in c) for c in campi] + [""]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(testa + corpo))
    if ricomponi:
        s = leggi(path)
        riscrivi_sentinella(path, chiavi={"record": esa(componi(s))})


def tabella(s):
    out = []
    for c in s["campi"]:
        out.append([c["ordinale"], c["riga"], c["nome"], c["picture"], c["usage"],
                    ",".join(str(i) for i in c["indici"]) or "-", c["da"], c["a"], c["tipo"], c["valore"]])
    return out


def chi(s, c):
    occ = "(" + ",".join(str(i) for i in c["indici"]) + ")" if c["indici"] else ""
    return f"{s['contratto']}@{s['vista']}/{s['sentinella']} #{c['ordinale']}{occ} {c['nome']}"


def altro_valore(c):
    """Un valore atteso diverso, nella stessa forma (testo: ultimo carattere cambiato; numero: ultima cifra)."""
    if c["tipo"] == "testo":
        v = c["v"]
        return valore_a_testo(v[:-1] + ("Q" if v[-1] != "Q" else "W"))
    t = c["valore"]
    d = int(t[-1])
    return t[:-1] + str(d + 1 if d < 9 else 1)


# --- famiglie -----------------------------------------------------------------------------------------------------------

def mutazioni_contratto(b, contratti_dir):
    for f in sorted(os.listdir(os.path.join(b.base, "sentinelle"))):
        contratto = f
        testa, righe = leggi_contratto(os.path.join(contratti_dir, contratto + ".tsv"))
        lung = int(next(r for r in righe if r["livello"] == "01")["lunghezza"])
        viste = ["base"] + aree_contratto(righe)
        coppie, campi, vista_di = {}, {}, {}
        for v in viste:
            el = sorted(vista_contratto(righe, v), key=lambda r: int(r["offset"]))
            for r in el:
                campi.setdefault(r["_identita"], r)
                vista_di.setdefault(r["_identita"], (v, el))
            for a, c in zip(el, el[1:]):
                coppie.setdefault((a["_identita"], c["_identita"]), (a, c))

        def copia():
            rr = copy.deepcopy(righe)
            return rr, {r["_identita"]: r for r in rr if r["tipo"] == "elementare"}

        def esegui(famiglia, nome, rr, idents, chiudi=True, testo=None):
            ricalcola_gruppi(rr)
            if chiudi and not chiusa(rr, lung):
                raise SystemExit(f"mutazione {famiglia} {nome}: geometria non chiusa (errore del banco di prova)")
            m = b.mondo()
            scrivi_contratto(m, contratto, testa, rr)
            b.prova(famiglia, nome, m, attesa_decodifica(contratto, idents, testo=testo))

        # 1. scambio di campi adiacenti di uguale lunghezza
        n = 0
        for (ia, ic), (a, c) in coppie.items():
            if a["lunghezza"] != c["lunghezza"]:
                continue
            n += 1
            rr, per = copia()
            per[ia]["offset"], per[ic]["offset"] = per[ic]["offset"], per[ia]["offset"]
            ca, cc = geom(a, contratto)[0], geom(c, contratto)[0]
            genere = "stesso tipo" if ca == cc else "tipo diverso"
            esegui("scambio", f"{contratto} {a['campo']} <-> {c['campo']} ({a['lunghezza']} byte, {genere}: {ca}/{cc})",
                   rr, {ia, ic})
        if n == 0:
            b.na("scambio", contratto, "nessuna coppia di campi adiacenti di uguale lunghezza")
        # 2. confine spostato di un byte: in ogni vista in cui il confine esiste, il campo che vi finisce e quello che
        #    vi comincia; le viste in cui un campo lo attraversa (un'altra area REDEFINES) restano come sono
        if len(campi) < 2:
            b.na("confine", contratto, "un solo campo elementare: nessun confine fra campi")
        confini = sorted({int(r["offset"]) for v in viste for r in vista_contratto(righe, v)} - {0})
        gruppi_confine = []
        for pos in confini:
            # coppie (sinistro, destro) al confine, una per vista; le coppie che condividono un campo (per esempio un
            # campo fuori dalle REDEFINES, presente in tutte le viste) formano una sola mutazione
            gruppi = []
            for v in viste:
                el = vista_contratto(righe, v)
                a = [r for r in el if int(r["offset"]) + int(r["lunghezza"]) == pos]
                c = [r for r in el if int(r["offset"]) == pos]
                if len(a) == 1 and len(c) == 1:
                    nuovo = ({a[0]["_identita"]: a[0]}, {c[0]["_identita"]: c[0]})
                    for g in [g for g in gruppi if set(g[0]) & set(nuovo[0]) or set(g[1]) & set(nuovo[1])]:
                        gruppi.remove(g)
                        nuovo[0].update(g[0])
                        nuovo[1].update(g[1])
                    gruppi.append(nuovo)
            gruppi_confine += [(pos, sx, dx) for sx, dx in gruppi]
        for pos, sx, dx in gruppi_confine:
            nomi = "/".join(r["campo"] for r in sx.values()) + " | " + "/".join(r["campo"] for r in dx.values())
            for delta in (1, -1):
                rr, per = copia()
                verso = f"{contratto} byte {pos} -> {pos + delta} ({nomi})"
                motivi = [x for x in [ridimensiona(per[i], delta, contratto, perche=True) for i in sx] +
                          [ridimensiona(per[i], -delta, contratto, perche=True) for i in dx] if x]
                if motivi:
                    b.na("confine", verso, "; ".join(motivi))
                    continue
                for i in dx:
                    per[i]["offset"] = str(int(per[i]["offset"]) + delta)
                ricalcola_gruppi(rr)
                if not chiusa(rr, lung):
                    b.na("confine", verso, "un campo spostato sta anche in una vista in cui il confine non esiste: si "
                                           "aprirebbe un buco o una sovrapposizione, che rileva gia' #3")
                    continue
                esegui("confine", verso, rr, set(sx) | set(dx))
        # 3. per campo: scala, segno, picture, tipo
        for ident, r in campi.items():
            cat, g = geom(r, contratto)
            nome = f"{contratto} {r['campo']}{'(' + ','.join(map(str, ident[1])) + ')' if ident[1] else ''}"
            if cat != "alfanumerico":
                if g.intere > 1:
                    nuovo = (g.intere - 1, g.decimali + 1)
                elif g.decimali > 0:
                    nuovo = (g.intere + 1, g.decimali - 1)
                else:
                    nuovo = None
                if nuovo:
                    rr, per = copia()
                    imposta(per[ident], cat, g.segno, nuovo[0], nuovo[1])
                    esegui("scala", f"{nome} {r['pic']} -> {per[ident]['pic']}", rr, {ident})
                else:
                    b.na("scala", nome, f"{r['pic']}: una sola cifra, la scala non si sposta senza cambiare lunghezza")
                if g.segno:
                    rr, per = copia()
                    imposta(per[ident], cat, False, g.intere, g.decimali)
                    esegui("segno", f"{nome} {r['pic']} -> {per[ident]['pic']}", rr, {ident})
                # picture accorciata di una cifra
                if g.intere > 1:
                    nuovo = (g.intere - 1, g.decimali)
                elif g.decimali > 0:
                    nuovo = (g.intere, g.decimali - 1)
                else:
                    nuovo = None
                if not nuovo:
                    b.na("picture", nome, f"{r['pic']}: una sola cifra, non si accorcia")
                else:
                    rr, per = copia()
                    imposta(per[ident], cat, g.segno, nuovo[0], nuovo[1])
                    d = g.lunghezza - int(per[ident]["lunghezza"])
                    idents = {ident}
                    descr = f"{nome} {r['pic']} {r['usage']} -> {per[ident]['pic']}"
                    if d:
                        v, el = vista_di[ident]
                        pos = [x["_identita"] for x in el].index(ident)
                        fatto = False
                        if pos + 1 < len(el):
                            vic = per[el[pos + 1]["_identita"]]
                            if ridimensiona(vic, d, contratto):
                                vic["offset"] = str(int(vic["offset"]) - d)
                                idents.add(vic["_identita"])
                                descr += f" ({d} byte in meno, assorbiti da {vic['campo']} che inizia prima)"
                                fatto = True
                        if not fatto and pos > 0:
                            vic = per[el[pos - 1]["_identita"]]
                            if ridimensiona(vic, d, contratto):
                                per[ident]["offset"] = str(int(per[ident]["offset"]) + d)
                                idents.add(vic["_identita"])
                                descr += f" ({d} byte in meno, assorbiti da {vic['campo']} che finisce dopo)"
                                fatto = True
                        if not fatto:
                            b.na("picture", nome, "la lunghezza cambia e nessun campo adiacente puo' assorbire il byte")
                            continue
                    else:
                        descr += " (stessa lunghezza)"
                    esegui("picture", descr, rr, idents)
            # tipo cambiato
            rr, per = copia()
            if cat == "comp-3":
                dec = min(g.decimali, g.lunghezza - 1)
                imposta(per[ident], "display-senza-segno", g.segno, g.lunghezza - dec, dec)
            elif cat == "comp" or cat.startswith("display"):
                imposta(per[ident], "alfanumerico", n=g.lunghezza)
            else:
                imposta(per[ident], "display-senza-segno", False, g.lunghezza, 0)
            esegui("tipo", f"{nome} {r['pic']} {r['usage']} -> {per[ident]['pic']} {per[ident]['usage']}", rr, {ident})
        if not any(geom(r, contratto)[0] != "alfanumerico" for r in campi.values()):
            for fam in ("scala", "segno", "picture"):
                b.na(fam, contratto, "nessun campo numerico")
        elif not any(geom(r, contratto)[1].segno for r in campi.values()):
            b.na("segno", contratto, "nessun campo con segno")
        # campo oltre il record (solo il record variabile)
        if contratto == VARIABILE:
            rr, per = copia()
            (ident, r), = campi.items()
            per[ident]["offset"] = "1"
            esegui("oltre", f"{contratto} {r['campo']} spostato al byte 2: non sta nel carico di 80 byte", rr, {ident},
                   chiudi=False, testo="CampoIncompleto")
        # 4. viste di CVEXPORT scambiate
        ar = aree_contratto(righe)
        if len(ar) < 2:
            b.na("vista", contratto, f"{len(ar)} aree REDEFINES: nessuno scambio di viste")
        for i, x in enumerate(ar):
            for y in ar[i + 1:]:
                rr, _ = copia()
                for r in rr:
                    if r["area"] == x:
                        r["area"] = y
                    elif r["area"] == y:
                        r["area"] = x
                m = b.mondo()
                scrivi_contratto(m, contratto, testa, rr)
                b.prova("vista", f"{contratto} aree {x} e {y} scambiate", m,
                        attesa_testi(f"{contratto}@{x}/", f"{contratto}@{y}/", gruppi=("copertura",)))


def mutazioni_sentinelle(b):
    sentinelle = []
    for c in sorted(os.listdir(os.path.join(b.base, "sentinelle"))):
        for f in sorted(os.listdir(os.path.join(b.base, "sentinelle", c))):
            sentinelle.append(leggi(os.path.join(b.base, "sentinelle", c, f)))
    for s in sentinelle:
        nome_s = f"{s['contratto']}@{s['vista']}/{s['sentinella']}"
        tab = tabella(s)
        for i, c in enumerate(s["campi"]):
            # 5. campo tolto: dichiarazione saltata e atteso mancante
            m = b.mondo()
            riscrivi_sentinella(file_sentinella(m, s), campi=tab[:i] + tab[i + 1:])
            if len(tab) == 1:
                # una sentinella senza campi non si legge: la diagnosi e' il rifiuto della sentinella stessa
                b.prova("campo-tolto", chi(s, c), m, attesa_testi(f"{s['sentinella']}.tsv: nessun campo",
                                                                   gruppi=("sentinella", "copertura")))
            else:
                b.prova("campo-tolto", chi(s, c), m,
                        attesa_testi(re.compile(re.escape(f"dichiarazione saltata: riga {c['riga']}") + r"(?![0-9])"),
                                     f"{chi(s, c)}: campo della vista nel contratto senza atteso",
                                     gruppi=("sorgente", "copertura", "coerenza")))
            # byte alterato nel campo
            m = b.mondo()
            rec = bytearray(s["byte"])
            rec[c["da"] - 1] ^= 0x01
            riscrivi_sentinella(file_sentinella(m, s), chiavi={"record": esa(bytes(rec))})
            b.prova("byte-alterato", f"{chi(s, c)} byte {c['da']}", m,
                    attesa_decodifica(s["contratto"], {(c["ordinale"], c["indici"])}, consentiti=("coerenza", "unicita"),
                                      sentinella=s["sentinella"]))
            # valore atteso alterato
            m = b.mondo()
            t = [list(x) for x in tab]
            t[i][9] = altro_valore(c)
            riscrivi_sentinella(file_sentinella(m, s), campi=t)
            b.prova("valore-alterato", f"{chi(s, c)} {c['valore'][:40]} -> {t[i][9][:40]}", m,
                    attesa_decodifica(s["contratto"], {(c["ordinale"], c["indici"])}, consentiti=("coerenza", "unicita"),
                                      sentinella=s["sentinella"]))
            # riga sbagliata
            m = b.mondo()
            t = [list(x) for x in tab]
            t[i][1] = c["riga"] + 1
            riscrivi_sentinella(file_sentinella(m, s), campi=t)
            b.prova("riga-sbagliata", f"{chi(s, c)} riga {c['riga']} -> {c['riga'] + 1}", m,
                    attesa_testi(re.compile(re.escape(f"{nome_s}: riga {c['riga'] + 1}") + r"(?![0-9])"),
                                 gruppi=("sorgente",)))
            # PICTURE trascritta male (prima ripetizione +1)
            m = b.mondo()
            t = [list(x) for x in tab]
            mm = re.search(r"\(([0-9]+)\)", c["picture"])
            t[i][3] = c["picture"][:mm.start(1)] + str(int(mm.group(1)) + 1).rjust(len(mm.group(1)), "0") + c["picture"][mm.end(1):]
            riscrivi_sentinella(file_sentinella(m, s), campi=t)
            b.prova("picture-sbagliata", f"{chi(s, c)} {c['picture']} -> {t[i][3]}", m,
                    attesa_testi(f"riga {c['riga']}: PICTURE nel sorgente '{c['picture']}', nella sentinella '{t[i][3]}'",
                                 gruppi=("sorgente", "coerenza", "valori")))
        # atteso duplicato
        m = b.mondo()
        riscrivi_sentinella(file_sentinella(m, s), campi=tab[:1] + tab)
        b.prova("atteso-duplicato", f"{chi(s, s['campi'][0])}", m,
                attesa_testi(f"{chi(s, s['campi'][0])}: atteso duplicato nella sentinella",
                             gruppi=("sorgente", "copertura", "coerenza", "unicita")))
        # due campi omogenei adiacenti scambiati (riga, nome, ordinale; intervalli e valori fermi) e solo i nomi
        for i, (c1, c2) in enumerate(zip(s["campi"], s["campi"][1:])):
            if (c1["picture"], c1["usage"]) != (c2["picture"], c2["usage"]):
                continue
            m = b.mondo()
            t = [list(x) for x in tab]
            for k in (0, 1, 2, 5):
                t[i][k], t[i + 1][k] = t[i + 1][k], t[i][k]
            riscrivi_sentinella(file_sentinella(m, s), campi=t)
            b.prova("omogenei-scambiati", f"{nome_s} {c1['nome']}{list(c1['indici']) or ''} <-> {c2['nome']}"
                    f"{list(c2['indici']) or ''} ({c1['picture']})", m,
                    attesa_testi(f"{nome_s}: righe non in ordine crescente", gruppi=("sorgente", "decodifica")))
            if c1["nome"] != c2["nome"]:
                m = b.mondo()
                t = [list(x) for x in tab]
                t[i][2], t[i + 1][2] = t[i + 1][2], t[i][2]
                riscrivi_sentinella(file_sentinella(m, s), campi=t)
                b.prova("nomi-scambiati", f"{nome_s} {c1['nome']} <-> {c2['nome']} ({c1['picture']})", m,
                        attesa_testi(f"riga {c1['riga']}: nome nel sorgente '{c1['nome']}', nella sentinella '{c2['nome']}'",
                                     gruppi=("sorgente", "decodifica")))
        # 6. due campi con lo stesso valore (stessa lunghezza e tipo), byte ricomposti
        coppia = next(((c1, c2) for k, c1 in enumerate(s["campi"]) for c2 in s["campi"][k + 1:]
                       if (c1["picture"], c1["usage"], c1["tipo"]) == (c2["picture"], c2["usage"], c2["tipo"])), None)
        if coppia is None:
            b.na("valori-uguali", nome_s, "nessuna coppia di campi con la stessa PICTURE, USAGE e tipo")
        else:
            c1, c2 = coppia
            m = b.mondo()
            t = [list(x) for x in tab]
            t[s["campi"].index(c2)][9] = c1["valore"]
            riscrivi_sentinella(file_sentinella(m, s), campi=t, ricomponi=True)
            b.prova("valori-uguali", f"{nome_s} {c2['nome']} = {c1['nome']}", m,
                    attesa_testi(f"{nome_s}: {c1['nome']} e {c2['nome']} hanno gli stessi byte",
                                 f"{nome_s}: {c1['nome']} e {c2['nome']} hanno lo stesso valore", gruppi=("unicita",)))
        # valori discriminanti
        for i, c in enumerate(s["campi"]):
            if c["tipo"] == "testo":
                continue
            t0 = c["valore"]
            casi = []
            if t0.startswith("-"):
                casi.append(("segno-positivo", t0[1:], "senza valore negativo"))
            if c["tipo"] == "decimale":
                casi.append(("decimale-con-zero", t0[:-1] + "0", "cifre decimali non tutte diverse da zero"))
            corpo = t0.lstrip("-")
            if len(corpo.replace(".", "")) > 1 and corpo[1] != ".":
                casi.append(("cifra-mancante", t0[:len(t0) - len(corpo)] + corpo[1:].lstrip("0"), "cifre, la PICTURE"))
            for fam, nuovo, testo in casi:
                m = b.mondo()
                t = [list(x) for x in tab]
                t[i][9] = nuovo
                riscrivi_sentinella(file_sentinella(m, s), campi=t, ricomponi=True)
                b.prova(fam, f"{chi(s, c)} {t0} -> {nuovo}", m, attesa_testi(testo, gruppi=("valori",)))
        for i, c in enumerate(s["campi"]):
            if c["tipo"] != "testo":
                continue
            n = (min(c["a"], s["prefisso"]) if s["prefisso"] else c["a"]) - c["da"] + 1
            for carattere, come in ((" ", "spazi"), ("0", "zeri")):
                m = b.mondo()
                t = [list(x) for x in tab]
                t[i][9] = valore_a_testo(carattere * n)
                riscrivi_sentinella(file_sentinella(m, s), campi=t, ricomponi=True)
                b.prova("testo-vuoto", f"{chi(s, c)} tutto {come}", m,
                        attesa_testi(f"{chi(s, c)}: valore tutto spazi o tutto zeri", gruppi=("valori", "unicita")))
        # lunghezza e fonte
        m = b.mondo()
        riscrivi_sentinella(file_sentinella(m, s), chiavi={"lunghezza": str(s["lunghezza"] + 1)})
        b.prova("lunghezza-sbagliata", f"{nome_s} {s['lunghezza']} -> {s['lunghezza'] + 1}", m,
                attesa_testi(f"{nome_s}: i campi finiscono al byte {s['lunghezza']}, la lunghezza dichiarata e' "
                             f"{s['lunghezza'] + 1}", gruppi=("sorgente", "copertura", "decodifica", "coerenza")))
        fonti = [(f, t) for f, t in s["fonte-lunghezza"] if f != "-"]
        if fonti:
            f, t = fonti[0]
            file_, riga = f.rsplit(":", 1)
            m = b.mondo()
            with open(file_sentinella(m, s), encoding="utf-8") as fh:
                testo = fh.read().replace(f"fonte-lunghezza\t{f}\t", f"fonte-lunghezza\t{file_}:{int(riga) + 1}\t", 1)
            with open(file_sentinella(m, s), "w", encoding="utf-8") as fh:
                fh.write(testo)
            b.prova("fonte-sbagliata", f"{nome_s} {f} -> {file_}:{int(riga) + 1}", m,
                    attesa_testi(f"lunghezza: il testo citato '{t}' non e' alla riga {file_}:{int(riga) + 1}",
                                 gruppi=("sorgente",)))
        else:
            b.na("fonte-sbagliata", nome_s, "nessuna fonte esterna della lunghezza da alterare")


def mutazioni_elenchi(b, contratti_dir):
    contratti = sorted(os.listdir(os.path.join(b.base, "sentinelle")))
    # contratto senza sentinella: cartella delle sentinelle tolta
    for c in contratti:
        m = b.mondo()
        shutil.rmtree(os.path.join(m, "sentinelle", c))
        b.prova("contratto-senza-sentinella", c, m, attesa_testi(f"contratto {c}: senza sentinella",
                                                                gruppi=("copertura",)))
    # contratto dei copybook in piu' nel file dei contratti (un contratto di programma marcato copybook)
    m = b.mondo()
    testa, righe = leggi_tsv(os.path.join(m, "contratti.tsv"))
    r = next(r for r in righe if r["righe"] != "copybook" and r["contratto"] != VARIABILE)
    r["righe"] = "copybook"
    scrivi_tsv(os.path.join(m, "contratti.tsv"), testa, righe)
    b.prova("contratto-in-piu", f"{r['contratto']} marcato copybook in contratti.tsv", m,
            attesa_testi(f"contratto {r['contratto']}: senza coppia contratto/vista in viste.tsv",
                         f"contratto {r['contratto']}: senza sentinella", gruppi=("copertura",)))
    # vista mancante in viste.tsv, vista in piu'
    with open(os.path.join(b.base, "viste.tsv"), encoding="utf-8") as f:
        viste = f.read().split("\n")
    for riga in [r for r in viste if r.startswith("CVEXPORT.EXPORT-RECORD\t") and "\tbase\t" not in r]:
        vista = riga.split("\t")[1]
        m = b.mondo()
        with open(os.path.join(m, "viste.tsv"), "w", encoding="utf-8") as f:
            f.write("\n".join(r for r in viste if r != riga))
        b.prova("vista-mancante", f"CVEXPORT.EXPORT-RECORD@{vista}", m,
                attesa_testi(f"contratto CVEXPORT.EXPORT-RECORD: vista {vista} (area REDEFINES del contratto) senza "
                             f"sentinella", gruppi=("copertura", "sorgente")))
    m = b.mondo()
    with open(os.path.join(m, "viste.tsv"), "a", encoding="utf-8") as f:
        f.write("CVACT01Y.ACCOUNT-RECORD\tACCOUNT-RECORD-R\tapp/cpy/CVACT01Y.cpy\t4\tACCOUNT-RECORD-R\n")
    b.prova("vista-in-piu", "CVACT01Y.ACCOUNT-RECORD@ACCOUNT-RECORD-R", m,
            attesa_testi("contratto CVACT01Y.ACCOUNT-RECORD: vista ACCOUNT-RECORD-R di viste.tsv non e' un'area "
                         "REDEFINES del contratto", gruppi=("copertura", "sorgente")))
    # vista di una sentinella cambiata in un'altra vista esistente
    m = b.mondo()
    p = os.path.join(m, "sentinelle", "CVEXPORT.EXPORT-RECORD", "EXPORT-CARD-DATA.tsv")
    riscrivi_sentinella(p, chiavi={"vista": "EXPORT-CARD-XREF-DATA"})
    b.prova("vista", "CVEXPORT.EXPORT-RECORD: sentinella EXPORT-CARD-DATA dichiarata della vista EXPORT-CARD-XREF-DATA", m,
            attesa_testi("sentinella CVEXPORT.EXPORT-RECORD@EXPORT-CARD-DATA/EXPORT-CARD-DATA dichiarata in viste.tsv ma assente",
                         gruppi=("copertura", "sorgente", "decodifica", "unicita", "valori")))
    # errore di lettura ripetuto uguale nella sentinella e nel contratto: CVEXPORT.cpy 26-27
    m = b.mondo()
    p = os.path.join(m, "sentinelle", "CVEXPORT.EXPORT-RECORD", "EXPORT-CUSTOMER-DATA.tsv")
    s = leggi(p)
    t = tabella(s)
    i = next(k for k, c in enumerate(s["campi"]) if c["nome"] == "EXP-CUST-FIRST-NAME")
    for k in (0, 1, 2):
        t[i][k], t[i + 1][k] = t[i + 1][k], t[i][k]
    riscrivi_sentinella(p, campi=t)
    testa, righe = leggi_contratto(os.path.join(contratti_dir, "CVEXPORT.EXPORT-RECORD.tsv"))
    a = next(r for r in righe if r["campo"] == "EXP-CUST-FIRST-NAME")
    c = next(r for r in righe if r["campo"] == "EXP-CUST-MIDDLE-NAME")
    a["offset"], c["offset"] = c["offset"], a["offset"]
    scrivi_contratto(m, "CVEXPORT.EXPORT-RECORD", testa, righe)
    b.prova("errore-ripetuto", "CVEXPORT.EXPORT-RECORD: righe 26-27 di CVEXPORT.cpy scambiate nella sentinella e nel "
            "contratto, la decodifica passa", m,
            attesa_testi("CVEXPORT.EXPORT-RECORD@EXPORT-CUSTOMER-DATA/EXPORT-CUSTOMER-DATA: righe non in ordine crescente",
                         gruppi=("sorgente",)))


def scaduto(*_):
    raise SystemExit("prove negative: tempo scaduto (1200 s)")


def main(argv):
    if len(argv) != 5:
        raise SystemExit(__doc__)
    legacy, contratti, contratti_tsv, sentinelle, viste = argv
    signal.signal(signal.SIGALRM, scaduto)
    signal.alarm(1200)
    b = Banco(legacy, contratti, contratti_tsv, sentinelle, viste)
    try:
        es, _ = verifica(legacy, contratti, contratti_tsv, sentinelle, viste)
        if es.errori:
            for e in es.errori:
                print(e)
            raise SystemExit("la verifica fallisce gia' senza alterazioni: le prove negative non avrebbero senso")
        mutazioni_contratto(b, contratti)
        mutazioni_sentinelle(b)
        mutazioni_elenchi(b, contratti)
    finally:
        shutil.rmtree(b.tmp, ignore_errors=True)
    fallite = [e for e in b.esiti if not e[2]]
    famiglie = {}
    for fam, _, ok, _ in b.esiti:
        famiglie.setdefault(fam, [0, 0])
        famiglie[fam][0 if ok else 1] += 1
    na = {}
    for fam, _, _ in b.non_applicabili:
        na[fam] = na.get(fam, 0) + 1
    contratti = sorted(os.listdir(sentinelle))
    applicata = {}
    for fam, nome, _, _ in b.esiti:
        m = re.match(r"[A-Z0-9]+\.[A-Z0-9-]+", nome)
        applicata.setdefault(fam, set()).add(m.group(0) if m else "?")
    print("riepilogo per famiglia (superate / fallite / non applicabili; diagnosi attesa; contratti a cui e' applicata):")
    for fam in sorted(set(famiglie) | set(na)):
        sup, fal = famiglie.get(fam, [0, 0])
        app = applicata.get(fam, set())
        quali = "tutti i " + str(len(contratti)) if len(app) == len(contratti) else (", ".join(sorted(app)) or "nessuno")
        print(f"  {fam}: {sup} / {fal} / {na.get(fam, 0)}; attesa: {DIAGNOSI.get(fam, '?')}; applicata a: {quali}")
    if fallite:
        print(f"prove negative: {len(fallite)} FALLITE su {len(b.esiti)}")
        raise SystemExit(1)
    print(f"prove negative: {len(b.esiti)} superate, {len(b.non_applicabili)} non applicabili (elencate sopra, non "
          f"contate come superate)")


if __name__ == "__main__":
    main(sys.argv[1:])
