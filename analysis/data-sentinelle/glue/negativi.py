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
  copertura (insieme atteso dai contratti, non dall'elenco): omissione-coordinata (file e nome tolti insieme, per ogni
    sentinella; e il controesempio della validazione con due offset scambiati), contratto-omesso, prefisso-duplicato,
    prefisso-omesso, prefisso-assente, prefisso-in-record-fisso; fonte-rimossa (fonte obbligatoria tolta)
  ricodifica: ricodifica-alterata e ricodifica-nel-prefisso (adattatore con la ricodifica alterata, solo in questo
    processo: il codec condiviso non si tocca), ricodifica-fuori-prefisso (controllo: un byte di riempimento alterato
    non e' un errore), record-allungato (ricomposizione del record)
  asserzione: una prova per ogni asserzione di controlli.py non gia' pretesa dalle famiglie sistematiche
Ogni prova dichiara i codici di asserzione che pretende ([C01], [S13], ...). Alla fine l'inventario confronta i codici
dichiarati in controlli.py con quelli pretesi da prove superate: un'asserzione senza prova fa fallire lo script.
Uscita 1 se una prova non fallisce, o non fallisce per il motivo dichiarato, o se un'asserzione resta senza prova.
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
import controlli  # noqa: E402
from controlli import PREFISSI_VARIABILE, VARIABILE, aree_contratto, ordina_contratto, verifica, vista_contratto  # noqa: E402
from sentinella import COLONNE, SentinellaErrore, analizza, componi, componi_campo, esa, leggi  # noqa: E402

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
    "omissione-coordinata": "[copertura] sentinella attesa (dal contratto) assente fra i file e non dichiarata",
    "contratto-omesso": "[copertura] contratto senza sentinella e senza coppie; sentinelle attese assenti",
    "prefisso-duplicato": "[copertura] prefisso diverso da quello del nome; prefisso atteso assente",
    "prefisso-omesso": "[copertura] sentinella del prefisso atteso (insieme fisso) assente e non dichiarata",
    "prefisso-assente": "[copertura] sentinella del record variabile senza prefisso",
    "prefisso-in-record-fisso": "[copertura] prefisso dichiarato in un record non variabile",
    "fonte-rimossa": "[sorgente] nessuna fonte esterna citata per un contratto che non e' in senza-fonte.tsv",
    "ricodifica-alterata": "[ricodifica] la ricodifica non ridà i byte effettivi (adattatore alterato in copia privata)",
    "ricodifica-nel-prefisso": "[ricodifica] byte alterato dentro il prefisso del record variabile",
    "ricodifica-fuori-prefisso": "nessun errore: il byte alterato e' nel riempimento, fuori dall'atteso (prova di "
                                 "controllo)",
    "record-allungato": "[ricodifica] i campi non ricompongono il record (byte in piu')",
    "asserzione": "il codice di asserzione dichiarato dalla prova (una prova per ogni asserzione non gia' pretesa "
                  "dalle famiglie sistematiche)",
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
        shutil.copy(os.path.join(os.path.dirname(viste), "senza-fonte.tsv"), os.path.join(self.base, "senza-fonte.tsv"))
        self.n = 0
        self.esiti = []          # (famiglia, nome, ok, diagnosi)
        self.non_applicabili = []  # (famiglia, oggetto, motivo)
        self.codici = {}         # codice di asserzione -> prove superate che lo pretendono

    def mondo(self):
        self.n += 1
        m = os.path.join(self.tmp, f"m{self.n}")
        shutil.copytree(self.base, m)
        return m

    def esegui(self, m, alterato=None):
        """Verifica completa del mondo m. 'alterato' sostituisce, solo in questo processo e solo per questa prova, il
        modulo codec visto dall'adattatore (copia privata alterata): il codec condiviso di #23 non si tocca."""
        originale = controlli.codec
        if alterato is not None:
            controlli.codec = alterato
        try:
            es, _ = verifica(self.legacy, os.path.join(m, "contratti"), os.path.join(m, "contratti.tsv"),
                             os.path.join(m, "sentinelle"), os.path.join(m, "viste.tsv"))
        finally:
            controlli.codec = originale
        shutil.rmtree(m)
        return es.errori

    def prova(self, famiglia, nome, m, attesa, codici=(), alterato=None):
        """La prova passa se l'attesa e' soddisfatta e ogni codice di asserzione in 'codici' compare negli errori:
        togliendo dal verificatore l'asserzione di uno di quei codici, la prova fallisce."""
        errori = self.esegui(m, alterato)
        ok, diag = attesa(errori)
        mancanti = [k for k in codici if not any(e.endswith(f" [{k}]") for e in errori)]
        if ok and mancanti:
            ok, diag = False, errori[:12] + [f"codici di asserzione attesi mancanti: {mancanti}"]
        if ok:
            for k in codici:
                self.codici.setdefault(k, []).append(f"{famiglia}: {nome}")
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

        def esegui(famiglia, nome, rr, idents, chiudi=True, testo=None, codici=()):
            ricalcola_gruppi(rr)
            if chiudi and not chiusa(rr, lung):
                raise SystemExit(f"mutazione {famiglia} {nome}: geometria non chiusa (errore del banco di prova)")
            m = b.mondo()
            scrivi_contratto(m, contratto, testa, rr)
            b.prova(famiglia, nome, m, attesa_decodifica(contratto, idents, testo=testo), codici=codici)

        def compensa(per, ident, d):
            """Il campo ident e' cambiato di d byte (+1 o -1) restando al suo offset: il campo adiacente della vista
            assorbe la differenza (il seguente cambia inizio, o il precedente cambia fine). Restituisce l'identita' del
            campo adiacente e una descrizione, o None se nessuno puo' assorbirla."""
            v, el = vista_di[ident]
            pos = [x["_identita"] for x in el].index(ident)
            verso = "in piu" if d > 0 else "in meno"
            if pos + 1 < len(el):
                vic = per[el[pos + 1]["_identita"]]
                if ridimensiona(vic, -d, contratto):
                    vic["offset"] = str(int(vic["offset"]) + d)
                    return vic["_identita"], (f"{abs(d)} byte {verso}, assorbiti da {vic['campo']} che inizia "
                                              f"{'dopo' if d > 0 else 'prima'}")
            if pos > 0:
                vic = per[el[pos - 1]["_identita"]]
                if ridimensiona(vic, -d, contratto):
                    per[ident]["offset"] = str(int(per[ident]["offset"]) - d)
                    return vic["_identita"], (f"{abs(d)} byte {verso}, assorbiti da {vic['campo']} che finisce "
                                              f"{'prima' if d > 0 else 'dopo'}")
            return None

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
                   rr, {ia, ic}, codici=("D05",) if ca == cc == "alfanumerico" else ())
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
                # scala: una cifra passa dalla parte intera ai decimali (o viceversa); con una sola cifra intera e
                # nessun decimale (9(1)) si aggiunge un decimale, 9(1)V9(1), e il campo adiacente assorbe il byte
                if g.intere > 1:
                    nuovo = (g.intere - 1, g.decimali + 1)
                elif g.decimali > 0:
                    nuovo = (g.intere + 1, g.decimali - 1)
                else:
                    nuovo = (g.intere, g.decimali + 1)
                rr, per = copia()
                imposta(per[ident], cat, g.segno, nuovo[0], nuovo[1])
                d = int(per[ident]["lunghezza"]) - g.lunghezza
                idents, descr = {ident}, f"{nome} {r['pic']} -> {per[ident]['pic']}"
                esito = compensa(per, ident, d) if d else None
                if d and esito is None:
                    b.na("scala", nome, f"{r['pic']} -> {per[ident]['pic']}: la lunghezza cambia e nessun campo "
                                        f"adiacente puo' assorbire il byte")
                else:
                    if esito:
                        idents.add(esito[0])
                        descr += f" ({esito[1]})"
                    esegui("scala", descr, rr, idents)
                if g.segno:
                    rr, per = copia()
                    imposta(per[ident], cat, False, g.intere, g.decimali)
                    esegui("segno", f"{nome} {r['pic']} -> {per[ident]['pic']}", rr, {ident}, codici=("D03",))
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
                        esito = compensa(per, ident, -d)
                        if esito is None:
                            b.na("picture", nome, "la lunghezza cambia e nessun campo adiacente puo' assorbire il byte")
                            continue
                        idents.add(esito[0])
                        descr += f" ({esito[1]})"
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
                   chiudi=False, testo="CampoIncompleto", codici=("D02",))
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
                        attesa_testi(f"{contratto}@{x}/", f"{contratto}@{y}/", gruppi=("copertura",)),
                        codici=("C06", "C07"))


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
                                                                   gruppi=("sentinella", "copertura")),
                        codici=("E01", "C19"))
            else:
                b.prova("campo-tolto", chi(s, c), m,
                        attesa_testi(re.compile(re.escape(f"dichiarazione saltata: riga {c['riga']}") + r"(?![0-9])"),
                                     f"{chi(s, c)}: campo della vista nel contratto senza atteso",
                                     gruppi=("sorgente", "copertura", "coerenza")), codici=("S13", "C06"))
            # byte alterato nel campo
            m = b.mondo()
            rec = bytearray(s["byte"])
            rec[c["da"] - 1] ^= 0x01
            riscrivi_sentinella(file_sentinella(m, s), chiavi={"record": esa(bytes(rec))})
            b.prova("byte-alterato", f"{chi(s, c)} byte {c['da']}", m,
                    attesa_decodifica(s["contratto"], {(c["ordinale"], c["indici"])}, consentiti=("coerenza", "unicita"),
                                      sentinella=s["sentinella"]), codici=("K01",))
            # valore atteso alterato
            m = b.mondo()
            t = [list(x) for x in tab]
            t[i][9] = altro_valore(c)
            riscrivi_sentinella(file_sentinella(m, s), campi=t)
            b.prova("valore-alterato", f"{chi(s, c)} {c['valore'][:40]} -> {t[i][9][:40]}", m,
                    attesa_decodifica(s["contratto"], {(c["ordinale"], c["indici"])}, consentiti=("coerenza", "unicita"),
                                      sentinella=s["sentinella"]), codici=("K01",))
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
                                 gruppi=("sorgente", "coerenza", "valori")), codici=("S09",))
        # atteso duplicato
        m = b.mondo()
        riscrivi_sentinella(file_sentinella(m, s), campi=tab[:1] + tab)
        b.prova("atteso-duplicato", f"{chi(s, s['campi'][0])}", m,
                attesa_testi(f"{chi(s, s['campi'][0])}: atteso duplicato nella sentinella",
                             gruppi=("sorgente", "copertura", "coerenza", "unicita")), codici=("C05", "S15"))
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
                    attesa_testi(f"{nome_s}: righe non in ordine crescente", gruppi=("sorgente", "decodifica")),
                    codici=("S12",))
            if c1["nome"] != c2["nome"]:
                m = b.mondo()
                t = [list(x) for x in tab]
                t[i][2], t[i + 1][2] = t[i + 1][2], t[i][2]
                riscrivi_sentinella(file_sentinella(m, s), campi=t)
                b.prova("nomi-scambiati", f"{nome_s} {c1['nome']} <-> {c2['nome']} ({c1['picture']})", m,
                        attesa_testi(f"riga {c1['riga']}: nome nel sorgente '{c1['nome']}', nella sentinella '{c2['nome']}'",
                                     gruppi=("sorgente", "decodifica")), codici=("S08", "D01"))
        # 6. due campi con lo stesso valore, byte ricomposti: ogni coppia di campi dello stesso tipo di valore in cui
        #    il valore del primo e' rappresentabile nel secondo (anche con PICTURE o USAGE diverse, per esempio
        #    EXPORT-SEQUENCE-NUM COMP e EXP-XREF-CUST-ID DISPLAY, entrambi interi di 9 cifre)
        n_coppie = 0
        for k1, c1 in enumerate(s["campi"]):
            for k2 in range(k1 + 1, len(s["campi"])):
                c2 = s["campi"][k2]
                if c1["tipo"] != c2["tipo"]:
                    continue
                # il valore di uno dei due si copia nell'altro, nel verso in cui e' rappresentabile
                if rappresentabile(c1, c2, s):
                    sorg, dest, k_dest = c1, c2, k2
                elif rappresentabile(c2, c1, s):
                    sorg, dest, k_dest = c2, c1, k1
                else:
                    continue
                n_coppie += 1
                m = b.mondo()
                t = [list(x) for x in tab]
                t[k_dest][9] = sorg["valore"]
                riscrivi_sentinella(file_sentinella(m, s), campi=t, ricomponi=True)
                stessi_byte = (c1["picture"], c1["usage"]) == (c2["picture"], c2["usage"])
                testi = [f"{nome_s}: {c1['nome']} e {c2['nome']} hanno lo stesso valore"]
                if stessi_byte:
                    testi.append(f"{nome_s}: {c1['nome']} e {c2['nome']} hanno gli stessi byte")
                b.prova("valori-uguali", f"{nome_s} {dest['nome']} = {sorg['nome']} ({sorg['picture']} {sorg['usage']}"
                        f" -> {dest['picture']} {dest['usage']})", m, attesa_testi(*testi, gruppi=("unicita", "valori")),
                        codici=("U02", "U01") if stessi_byte else ("U02",))
        if n_coppie == 0:
            b.na("valori-uguali", nome_s, "nessuna coppia di campi dello stesso tipo in cui il valore dell'uno stia "
                                          "nella PICTURE dell'altro")
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
                b.prova(fam, f"{chi(s, c)} {t0} -> {nuovo}", m, attesa_testi(testo, gruppi=("valori",)),
                        codici=({"segno-positivo": "V11", "decimale-con-zero": "V09", "cifra-mancante": "V08"}[fam],))
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
                        attesa_testi(f"{chi(s, c)}: valore tutto spazi o tutto zeri", gruppi=("valori", "unicita")),
                        codici=("V03",))
        # lunghezza e fonte
        m = b.mondo()
        riscrivi_sentinella(file_sentinella(m, s), chiavi={"lunghezza": str(s["lunghezza"] + 1)})
        b.prova("lunghezza-sbagliata", f"{nome_s} {s['lunghezza']} -> {s['lunghezza'] + 1}", m,
                attesa_testi(f"{nome_s}: i campi finiscono al byte {s['lunghezza']}, la lunghezza dichiarata e' "
                             f"{s['lunghezza'] + 1}", gruppi=("sorgente", "copertura", "decodifica", "coerenza")),
                codici=("S20", "S04") if any(f != "-" for f, _ in s["fonte-lunghezza"]) else ("S20",))
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
                                 gruppi=("sorgente",)), codici=("S03",))
            # fonte obbligatoria rimossa: commento del copybook, RECORDSIZE del JCL o FD del programma
            m = b.mondo()
            with open(file_sentinella(m, s), encoding="utf-8") as fh:
                righe_f = fh.read().split("\n")
            righe_f = [r for r in righe_f if not r.startswith("fonte-lunghezza\t")]
            k = next(n for n, r in enumerate(righe_f) if r.startswith("record\t"))
            righe_f.insert(k, "fonte-lunghezza\t-\tnessuna fonte esterna (prova negativa)")
            with open(file_sentinella(m, s), "w", encoding="utf-8") as fh:
                fh.write("\n".join(righe_f))
            tipi = ", ".join(sorted({"JCL" if "/jcl/" in f else ("FD" if f.endswith(".cbl:83") else "commento")
                                     for f, _ in fonti}))
            b.prova("fonte-rimossa", f"{nome_s} senza {', '.join(f for f, _ in fonti)} ({tipi})", m,
                    attesa_testi(f"{nome_s}: nessuna fonte esterna della lunghezza citata", gruppi=("sorgente",)),
                    codici=("S24",))
        else:
            b.na("fonte-sbagliata", nome_s, "nessuna fonte esterna della lunghezza da alterare")
            b.na("fonte-rimossa", nome_s, "nessuna fonte esterna da rimuovere: contratto di senza-fonte.tsv (vedi la "
                                          "prova senza-fonte-tolto)")


def mutazioni_elenchi(b, contratti_dir):
    contratti = sorted(os.listdir(os.path.join(b.base, "sentinelle")))
    # contratto senza sentinella: cartella delle sentinelle tolta
    for c in contratti:
        m = b.mondo()
        shutil.rmtree(os.path.join(m, "sentinelle", c))
        b.prova("contratto-senza-sentinella", c, m, attesa_testi(f"contratto {c}: senza sentinella",
                                                                gruppi=("copertura",)), codici=("C09", "C19", "C12"))
    # contratto dei copybook in piu' nel file dei contratti (un contratto di programma marcato copybook)
    m = b.mondo()
    testa, righe = leggi_tsv(os.path.join(m, "contratti.tsv"))
    r = next(r for r in righe if r["righe"] != "copybook" and r["contratto"] != VARIABILE)
    r["righe"] = "copybook"
    scrivi_tsv(os.path.join(m, "contratti.tsv"), testa, righe)
    b.prova("contratto-in-piu", f"{r['contratto']} marcato copybook in contratti.tsv", m,
            attesa_testi(f"contratto {r['contratto']}: senza coppia contratto/vista in viste.tsv",
                         f"contratto {r['contratto']}: senza sentinella", gruppi=("copertura",)),
            codici=("C08", "C09"))
    # vista mancante in viste.tsv, vista in piu'
    with open(os.path.join(b.base, "viste.tsv"), encoding="utf-8") as f:
        viste = f.read().split("\n")
    for riga in [r for r in viste if r.startswith("CVEXPORT.EXPORT-RECORD\t") and "\tbase\t" not in r]:
        vista = riga.split("\t")[1]
        m = b.mondo()
        with open(os.path.join(m, "viste.tsv"), "w", encoding="utf-8") as f:
            f.write("\n".join(r for r in viste if r != riga))
        b.prova("vista-mancante", f"CVEXPORT.EXPORT-RECORD@{vista}", m,
                attesa_testi(f"sentinella attesa CVEXPORT.EXPORT-RECORD@{vista}/{vista} (dal contratto) non dichiarata",
                             f"REDEFINES {vista}", gruppi=("copertura", "sorgente")), codici=("C20", "S31", "C13"))
    m = b.mondo()
    with open(os.path.join(m, "viste.tsv"), "a", encoding="utf-8") as f:
        f.write("CVACT01Y.ACCOUNT-RECORD\tACCOUNT-RECORD-R\tapp/cpy/CVACT01Y.cpy\t4\tACCOUNT-RECORD-R\n")
    b.prova("vista-in-piu", "CVACT01Y.ACCOUNT-RECORD@ACCOUNT-RECORD-R", m,
            attesa_testi("sentinella CVACT01Y.ACCOUNT-RECORD@ACCOUNT-RECORD-R/ACCOUNT-RECORD-R dichiarata in viste.tsv "
                         "ma non attesa dal contratto", gruppi=("copertura", "sorgente")), codici=("C22", "S32", "C12"))
    # vista di una sentinella cambiata in un'altra vista esistente
    m = b.mondo()
    p = os.path.join(m, "sentinelle", "CVEXPORT.EXPORT-RECORD", "EXPORT-CARD-DATA.tsv")
    riscrivi_sentinella(p, chiavi={"vista": "EXPORT-CARD-XREF-DATA"})
    b.prova("vista", "CVEXPORT.EXPORT-RECORD: sentinella EXPORT-CARD-DATA dichiarata della vista EXPORT-CARD-XREF-DATA", m,
            attesa_testi("sentinella CVEXPORT.EXPORT-RECORD@EXPORT-CARD-DATA/EXPORT-CARD-DATA dichiarata in viste.tsv ma assente",
                         gruppi=("copertura", "sorgente", "decodifica", "unicita", "valori")),
            codici=("C12", "C13", "C19", "C21"))
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
                         gruppi=("sorgente",)), codici=("S12",))


def rappresentabile(c1, c2, s):
    """Il valore atteso di c1 si puo' scrivere nel campo c2 (stesso tipo; testo della stessa lunghezza scritta)."""
    try:
        pic = analizza(c2["picture"], c2["usage"])
        b = componi_campo(pic, c1["tipo"], c1["v"])
    except SentinellaErrore:
        return False
    if pic["classe"] == "X":
        n = (min(c2["a"], s["prefisso"]) if s["prefisso"] else c2["a"]) - c2["da"] + 1
        return len(b) == n
    return True


class CodecAlterato:
    """Copia privata del codec vista dall'adattatore: tutto come il codec di #23, salvo la ricodifica, che passa per
    'altera'. Serve solo a raggiungere le asserzioni di ricodifica; il file del codec condiviso non si tocca."""

    def __init__(self, altera):
        self._altera = altera

    def __getattr__(self, nome):
        return getattr(codec, nome)

    def ricodifica(self, risultato):
        return self._altera(codec.ricodifica(risultato))


def attesa_nessun_errore(errori):
    """Per le prove di controllo (non negative): la verifica deve passare."""
    return (not errori), (["nessun errore"] if not errori else errori[:12])


def scrivi_testo(path, testo):
    with open(path, "w", encoding="utf-8") as f:
        f.write(testo)


def leggi_testo(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def sostituisci(path, vecchio, nuovo):
    t = leggi_testo(path)
    if t.count(vecchio) != 1:
        raise SystemExit(f"banco di prova: '{vecchio}' non compare esattamente una volta in {path}")
    scrivi_testo(path, t.replace(vecchio, nuovo))


def togli_da_viste(m, contratto, vista=None, sentinella=None):
    """Toglie da viste.tsv una sentinella (e la riga, se resta vuota), una vista o tutte le righe di un contratto."""
    p = os.path.join(m, "viste.tsv")
    out = []
    for r in leggi_testo(p).split("\n"):
        c = r.split("\t")
        if len(c) == 5 and c[0] == contratto and (vista is None or c[1] == vista):
            if sentinella is not None:
                resto = [x for x in c[4].split(",") if x != sentinella]
                if resto:
                    out.append("\t".join(c[:4] + [",".join(resto)]))
            continue
        out.append(r)
    scrivi_testo(p, "\n".join(out))


def mutazioni_copertura(b, contratti_dir):
    """Omissioni coordinate di file ed elenco: l'insieme atteso viene dai contratti, non dall'elenco."""
    sent = os.path.join(b.base, "sentinelle")
    tutte = [(c, f[:-4]) for c in sorted(os.listdir(sent)) for f in sorted(os.listdir(os.path.join(sent, c)))]
    for c, n in tutte:
        s = leggi(os.path.join(sent, c, n + ".tsv"))
        m = b.mondo()
        os.remove(os.path.join(m, "sentinelle", c, n + ".tsv"))
        togli_da_viste(m, c, s["vista"], n)
        b.prova("omissione-coordinata", f"{c}@{s['vista']}/{n}: file tolto e nome tolto da viste.tsv", m,
                attesa_testi(f"sentinella attesa {c}@{s['vista']}/{n} (dal contratto) assente fra i file",
                             f"sentinella attesa {c}@{s['vista']}/{n} (dal contratto) non dichiarata in viste.tsv",
                             gruppi=("copertura", "sorgente")), codici=("C19", "C20"))
    # il controesempio della validazione: vista tolta da file ed elenco e due offset scambiati in quella vista
    m = b.mondo()
    os.remove(os.path.join(m, "sentinelle", "CVEXPORT.EXPORT-RECORD", "EXPORT-ACCOUNT-DATA.tsv"))
    togli_da_viste(m, "CVEXPORT.EXPORT-RECORD", "EXPORT-ACCOUNT-DATA")
    testa, righe = leggi_contratto(os.path.join(contratti_dir, "CVEXPORT.EXPORT-RECORD.tsv"))
    a = next(r for r in righe if r["campo"] == "EXP-ACCT-OPEN-DATE")
    c = next(r for r in righe if r["campo"] == "EXP-ACCT-REISSUE-DATE")
    a["offset"], c["offset"] = c["offset"], a["offset"]
    scrivi_contratto(m, "CVEXPORT.EXPORT-RECORD", testa, righe)
    b.prova("omissione-coordinata", "CVEXPORT.EXPORT-RECORD@EXPORT-ACCOUNT-DATA tolta da file ed elenco, con "
            "EXP-ACCT-OPEN-DATE e EXP-ACCT-REISSUE-DATE scambiati nel contratto", m,
            attesa_testi("sentinella attesa CVEXPORT.EXPORT-RECORD@EXPORT-ACCOUNT-DATA/EXPORT-ACCOUNT-DATA (dal "
                         "contratto) assente fra i file", gruppi=("copertura", "sorgente")), codici=("C19", "C20"))
    for c in sorted(os.listdir(sent)):
        m = b.mondo()
        shutil.rmtree(os.path.join(m, "sentinelle", c))
        togli_da_viste(m, c)
        b.prova("contratto-omesso", f"{c}: cartella delle sentinelle e righe di viste.tsv tolte", m,
                attesa_testi(f"contratto {c}: senza sentinella", f"contratto {c}: senza coppia contratto/vista",
                             gruppi=("copertura",)), codici=("C08", "C09", "C19", "C20"))
    # prefissi del record variabile: duplicato, sostituito, tolto con il suo nome, assente
    d = os.path.join("sentinelle", VARIABILE)
    m = b.mondo()
    t = leggi_testo(os.path.join(m, d, "prefisso-12.tsv")).replace("sentinella\tprefisso-12", "sentinella\tprefisso-39")
    scrivi_testo(os.path.join(m, d, "prefisso-39.tsv"), t)
    b.prova("prefisso-duplicato", "prefisso-39.tsv con il carico e il prefisso di prefisso-12", m,
            attesa_testi(f"{VARIABILE}@base/prefisso-39: la sentinella dichiara il prefisso 12",
                         gruppi=("copertura", "unicita")), codici=("C23",))
    m = b.mondo()
    os.remove(os.path.join(m, d, "prefisso-39.tsv"))
    t = leggi_testo(os.path.join(m, d, "prefisso-12.tsv")).replace("sentinella\tprefisso-12", "sentinella\tprefisso-12b")
    scrivi_testo(os.path.join(m, d, "prefisso-12b.tsv"), t)
    sostituisci(os.path.join(m, "viste.tsv"), "prefisso-12,prefisso-39", "prefisso-12,prefisso-12b")
    b.prova("prefisso-duplicato", "due sentinelle sul prefisso di 12 byte (prefisso-12 e prefisso-12b), elenco "
            "aggiornato, prefisso-39 tolto", m,
            attesa_testi(f"sentinella attesa {VARIABILE}@base/prefisso-39 (dal contratto) assente",
                         f"sentinella {VARIABILE}@base/prefisso-12b presente ma non attesa", gruppi=("copertura",)),
            codici=("C19", "C20", "C21", "C22", "C23"))
    for p in PREFISSI_VARIABILE:
        m = b.mondo()
        os.remove(os.path.join(m, d, f"prefisso-{p}.tsv"))
        togli_da_viste(m, VARIABILE, "base", f"prefisso-{p}")
        b.prova("prefisso-omesso", f"prefisso-{p}.tsv e il suo nome in viste.tsv tolti", m,
                attesa_testi(f"sentinella attesa {VARIABILE}@base/prefisso-{p} (dal contratto) assente fra i file",
                             gruppi=("copertura",)), codici=("C19", "C20"))
    m = b.mondo()
    p12 = os.path.join(m, d, "prefisso-12.tsv")
    scrivi_testo(p12, "\n".join(r for r in leggi_testo(p12).split("\n")
                               if not r.startswith("prefisso\t") and not r.startswith("fonte-prefisso\t")))
    b.prova("prefisso-assente", "prefisso-12.tsv senza le righe prefisso e fonte-prefisso", m,
            attesa_testi(f"{VARIABILE}@base/prefisso-12: sentinella del record variabile senza prefisso",
                         gruppi=("copertura", "sorgente", "decodifica", "ricodifica", "coerenza", "unicita")),
            codici=("C25",))
    m = b.mondo()
    pc = os.path.join(m, "sentinelle", "COCOM01Y.CARDDEMO-COMMAREA", "base.tsv")
    sostituisci(pc, "lunghezza\t160\n", "lunghezza\t160\nprefisso\t12\nfonte-prefisso\tapp/cbl/CBACT01C.cbl:288\t"
                                       "MOVE 12 TO WS-RECD-LEN\n")
    b.prova("prefisso-in-record-fisso", "COCOM01Y con un prefisso di 12 byte", m,
            attesa_testi("COCOM01Y.CARDDEMO-COMMAREA@base/base: prefisso dichiarato in un record non variabile",
                         gruppi=("copertura", "sorgente", "decodifica", "ricodifica", "unicita", "coerenza")),
            codici=("C24",))


def mutazioni_ricodifica(b):
    """Asserzioni di ricodifica: byte ricodificati e ricomposizione del record."""
    # adattatore con la ricodifica alterata nel primo byte di ogni campo: [ricodifica] su ogni campo
    b.prova("ricodifica-alterata", "ricodifica che cambia il primo byte di ogni campo", b.mondo(),
            attesa_testi("la ricodifica conservativa non ridà i byte effettivi del campo", gruppi=("ricodifica",)),
            codici=("R01",), alterato=CodecAlterato(lambda x: bytes([x[0] ^ 1]) + x[1:]))
    # record variabile: un byte cambiato DENTRO il prefisso (12esimo) e' un errore; fuori dal prefisso (80esimo) no
    b.prova("ricodifica-nel-prefisso", f"{VARIABILE}: ricodifica che cambia il byte 12 del campo di 80", b.mondo(),
            attesa_testi(f"{VARIABILE}@base/prefisso-12 #1 VBR-REC: la ricodifica conservativa",
                         f"{VARIABILE}@base/prefisso-39 #1 VBR-REC: la ricodifica conservativa", gruppi=("ricodifica",)),
            codici=("R01",),
            alterato=CodecAlterato(lambda x: x[:11] + bytes([x[11] ^ 1]) + x[12:] if len(x) == 80 else x))
    b.prova("ricodifica-fuori-prefisso", f"{VARIABILE}: ricodifica che cambia solo il byte 80 (riempimento): nessun "
            "errore (prova di controllo, non negativa)", b.mondo(), attesa_nessun_errore,
            alterato=CodecAlterato(lambda x: x[:79] + bytes([x[79] ^ 1]) if len(x) == 80 else x))
    # un byte in piu' in coda al record: ogni campo si decodifica, ma i campi non ricompongono il record
    m = b.mondo()
    p = os.path.join(m, "sentinelle", "CVTRA03Y.TRAN-TYPE-RECORD", "base.tsv")
    s = leggi(p)
    riscrivi_sentinella(p, chiavi={"record": esa(s["byte"] + b"\x5a")})
    b.prova("record-allungato", "CVTRA03Y: un byte in piu' in coda al record", m,
            attesa_testi("CVTRA03Y.TRAN-TYPE-RECORD@base/base: i campi della vista non ricompongono il record",
                         gruppi=("ricodifica", "sorgente", "coerenza")), codici=("R02", "S23"))


def mutazioni_asserzioni(b, contratti_dir):
    """Una prova per ogni asserzione di controlli.py non gia' pretesa dalle famiglie sistematiche."""
    S = "sentinelle"
    cocom = os.path.join(S, "COCOM01Y.CARDDEMO-COMMAREA", "base.tsv")
    tra3 = os.path.join(S, "CVTRA03Y.TRAN-TYPE-RECORD", "base.tsv")
    tra2 = os.path.join(S, "CVTRA02Y.DIS-GROUP-RECORD", "base.tsv")
    cust = os.path.join(S, "CVEXPORT.EXPORT-RECORD", "EXPORT-CUSTOMER-DATA.tsv")
    p12 = os.path.join(S, VARIABILE, "prefisso-12.tsv")

    def prova(nome, modifica, codici, *testi, gruppi=None):
        m = b.mondo()
        modifica(m)
        b.prova("asserzione", nome, m, attesa_testi(*testi, gruppi=gruppi) if testi else attesa_codici, codici=codici)

    def campo(m, rel, nome_campo, colonna, valore, ricomponi=False):
        """Cambia una colonna della riga di un campo (per nome) in una sentinella."""
        path = os.path.join(m, rel)
        s = leggi(path)
        t = tabella(s)
        k = next(i for i, c in enumerate(s["campi"]) if c["nome"] == nome_campo)
        for col, val in (colonna.items() if isinstance(colonna, dict) else [(colonna, valore)]):
            t[k][COLONNE.index(col)] = val
        riscrivi_sentinella(path, campi=t, ricomponi=ricomponi)

    def contratto(m, nome, modifica_righe):
        testa, righe = leggi_contratto(os.path.join(contratti_dir, nome + ".tsv"))
        modifica_righe(righe)
        scrivi_contratto(m, nome, testa, righe)

    def riga_contratto(righe, campo_):
        return next(r for r in righe if r["campo"] == campo_)

    prova("cartella-sentinelle-assente", lambda m: shutil.rmtree(os.path.join(m, S)), ("C01",),
          "cartella delle sentinelle assente")
    prova("file-fra-le-cartelle", lambda m: scrivi_testo(os.path.join(m, S, "LEGGIMI.txt"), "x\n"), ("C02",),
          "file inatteso fra le cartelle delle sentinelle: LEGGIMI.txt", gruppi=("copertura",))
    prova("file-fra-le-sentinelle", lambda m: scrivi_testo(os.path.join(m, S, "COCOM01Y.CARDDEMO-COMMAREA", "nota.txt"),
                                                          "x\n"), ("C03",),
          "file inatteso fra le sentinelle: COCOM01Y.CARDDEMO-COMMAREA/nota.txt", gruppi=("copertura",))

    def area_senza_redefines(m):
        def f(righe):
            riga_contratto(righe, "EXPORT-ACCOUNT-DATA")["redefines"] = "-"
        contratto(m, "CVEXPORT.EXPORT-RECORD", f)
    prova("area-senza-redefines", area_senza_redefines, ("C04", "C15", "C16"),
          "vista EXPORT-ACCOUNT-DATA: 0 righe REDEFINES con questa area nel contratto")

    def sentinella_di_programma(m):
        c = "CBACT01C.FD-ACCTFILE-REC"
        os.makedirs(os.path.join(m, S, c))
        t = leggi_testo(os.path.join(m, cocom)).replace("contratto\tCOCOM01Y.CARDDEMO-COMMAREA", f"contratto\t{c}")
        scrivi_testo(os.path.join(m, S, c, "base.tsv"), t)
    prova("contratto-di-programma-con-sentinella", sentinella_di_programma, ("C10",),
          "contratto CBACT01C.FD-ACCTFILE-REC: con sentinella o in viste.tsv, ma non tra i contratti dei copybook")

    def riga_ripetuta(m):
        p = os.path.join(m, "viste.tsv")
        r = next(x for x in leggi_testo(p).split("\n") if x.startswith("CVTRA03Y.TRAN-TYPE-RECORD\t"))
        scrivi_testo(p, leggi_testo(p) + r + "\n")
    prova("coppia-ripetuta", riga_ripetuta, ("C11",), "coppia CVTRA03Y.TRAN-TYPE-RECORD@base ripetuta in viste.tsv",
          gruppi=("copertura",))
    prova("contratto-assente", lambda m: os.remove(os.path.join(m, "contratti", "CVTRA03Y.TRAN-TYPE-RECORD.tsv")),
          ("C14",), "contratto CVTRA03Y.TRAN-TYPE-RECORD: file del contratto assente")
    prova("sorgente-diverso-in-viste", lambda m: sostituisci(os.path.join(m, "viste.tsv"),
                                                             "COCOM01Y.CARDDEMO-COMMAREA\tbase\tapp/cpy/COCOM01Y.cpy",
                                                             "COCOM01Y.CARDDEMO-COMMAREA\tbase\tapp/cpy/ALTRO.cpy"),
          ("C17", "C18"), "contratto COCOM01Y.CARDDEMO-COMMAREA: sorgente in viste.tsv diverso", gruppi=("copertura",))
    prova("sorgente-assente", lambda m: sostituisci(os.path.join(m, cocom), "sorgente\tapp/cpy/COCOM01Y.cpy",
                                                    "sorgente\tapp/cpy/COCOM01Y.CPY"),
          ("C18", "S05", "S29"), "COCOM01Y.CARDDEMO-COMMAREA@base/base: sorgente assente: app/cpy/COCOM01Y.CPY")
    prova("sentinella-illeggibile", lambda m: campo(m, tra3, "TRAN-TYPE", "tipo", "boh"), ("E01",),
          "tipo 'boh' non tra")
    prova("fonte-senza-riga", lambda m: sostituisci(os.path.join(m, tra3), "app/cpy/CVTRA03Y.cpy:2\t", "app/cpy/CVTRA03Y.cpy\t"),
          ("S01",), "fonte non nella forma file:riga", gruppi=("sorgente",))
    prova("fonte-file-assente", lambda m: sostituisci(os.path.join(m, tra3), "app/cpy/CVTRA03Y.cpy:2\t",
                                                      "app/cpy/NONESISTE.cpy:2\t"),
          ("S02",), "file citato assente: app/cpy/NONESISTE.cpy", gruppi=("sorgente",))
    prova("radice-sbagliata", lambda m: sostituisci(os.path.join(m, tra3), "radice\t4\t", "radice\t5\t"),
          ("S06", "S29"), "CVTRA03Y.TRAN-TYPE-RECORD@base/base: ", gruppi=("sorgente", "copertura"))
    prova("riga-su-un-commento", lambda m: campo(m, tra3, "TRAN-TYPE", "riga", "2"), ("S07", "S13", "S14"),
          "CVTRA03Y.TRAN-TYPE-RECORD@base/base: riga 2 (TRAN-TYPE): non e' una dichiarazione elementare",
          gruppi=("sorgente",))
    prova("usage-sbagliata", lambda m: campo(m, cust, "EXP-CUST-ID", "usage", "-"), ("S10",),
          "riga 25: USAGE nel sorgente 'COMP', nella sentinella '-'")
    prova("ordinale-sbagliato", lambda m: campo(m, cocom, "CDEMO-FROM-TRANID", "ordinale", "99"), ("S11",),
          "riga 21 (CDEMO-FROM-TRANID): ordinale nel sorgente 1, nella sentinella 99")
    prova("riga-di-un'altra-vista", lambda m: campo(m, cust, "EXP-CUST-PRI-CARD-HOLDER-IND", "riga", "49"),
          ("S07", "S14"), "riga 49 nella sentinella ma non nella vista")

    def righe_permutate(m):
        path = os.path.join(m, cocom)
        s = leggi(path)
        t = tabella(s)
        t[0], t[2] = t[2], t[0]
        riscrivi_sentinella(path, campi=t)
    prova("righe-permutate", righe_permutate, ("S16",),
          "COCOM01Y.CARDDEMO-COMMAREA@base/base: dichiarazioni in ordine diverso da quello del sorgente")

    def picture_illeggibile(m):
        campo(m, tra3, "TRAN-TYPE", "riga", "2")
        campo(m, tra3, "TRAN-TYPE", "picture", "Z(02)")
    prova("picture-illeggibile", picture_illeggibile, ("S17", "V01", "K02"), "PICTURE non riconosciuta: Z(02)")

    def intervallo_spostato(m):
        campo(m, cocom, "CDEMO-FROM-PROGRAM", "da", "6")
        campo(m, cocom, "CDEMO-FROM-PROGRAM", "a", "13")
    prova("intervallo-spostato", intervallo_spostato, ("S18",),
          "CDEMO-FROM-PROGRAM (riga 22): intervallo 6-13, atteso l'inizio a 5")
    prova("intervallo-lungo", lambda m: campo(m, cocom, "CDEMO-FROM-PROGRAM", "a", "13"), ("S19",),
          "CDEMO-FROM-PROGRAM (riga 22): intervallo 5-13 di 9 byte")
    prova("fonte-trattino-con-altre", lambda m: sostituisci(os.path.join(m, tra3), "record\t",
                                                            "fonte-lunghezza\t-\tnessuna\nrecord\t"),
          ("S21",), "fonte-lunghezza '-' insieme ad altre fonti", gruppi=("sorgente",))
    prova("prefisso-non-minore", lambda m: sostituisci(os.path.join(m, p12), "prefisso\t12\n", "prefisso\t80\n"),
          ("S22",), "prefisso 80 non minore della lunghezza 80")
    prova("senza-fonte-tolto", lambda m: sostituisci(os.path.join(m, "senza-fonte.tsv"), "COCOM01Y.CARDDEMO-COMMAREA\t",
                                                     "COCOM01Y.CARDDEMO-COMMAREA-NO\t"),
          ("S24", "S28"), "COCOM01Y.CARDDEMO-COMMAREA@base/base: nessuna fonte esterna della lunghezza citata",
          gruppi=("sorgente",))
    prova("senza-fonte-ma-citata", lambda m: sostituisci(os.path.join(m, cocom), "fonte-lunghezza\t-\t",
                                                         "fonte-lunghezza\tapp/cpy/CVTRA03Y.cpy:2\tRECLN = 60\n"
                                                         "fonte-lunghezza\t-\t"),
          ("S25",), "il contratto e' in senza-fonte.tsv ma la sentinella cita app/cpy/CVTRA03Y.cpy:2")

    def elencato(contratto_, path_sent, vecchia):
        def f(m):
            p = os.path.join(m, "senza-fonte.tsv")
            scrivi_testo(p, leggi_testo(p) + f"{contratto_}\tprova negativa\n")
            pp = os.path.join(m, path_sent)
            t = leggi_testo(pp).split("\n")
            t = [r for r in t if not r.startswith("fonte-lunghezza\t")]
            k = next(n for n, r in enumerate(t) if r.startswith("record\t"))
            t.insert(k, "fonte-lunghezza\t-\tnessuna fonte esterna (prova negativa)")
            scrivi_testo(pp, "\n".join(t))
        return f
    prova("senza-fonte-con-recordsize", elencato("COSTM01.TRNX-RECORD", os.path.join(S, "COSTM01.TRNX-RECORD", "base.tsv"),
                                                 None),
          ("S26",), "senza-fonte.tsv: COSTM01.TRNX-RECORD dichiarato senza fonte, ma il contratto di #3 riporta "
                    "recordsize=", gruppi=("sorgente",))
    prova("senza-fonte-con-recln", elencato("CUSTREC.CUSTOMER-RECORD", os.path.join(S, "CUSTREC.CUSTOMER-RECORD", "base.tsv"),
                                            None),
          ("S27",), "senza-fonte.tsv: CUSTREC.CUSTOMER-RECORD dichiarato senza fonte, ma app/cpy/CUSTREC.cpy:2 dichiara "
                    "una lunghezza", gruppi=("sorgente",))
    prova("senza-fonte-contratto-estraneo", lambda m: scrivi_testo(os.path.join(m, "senza-fonte.tsv"),
                                                                   leggi_testo(os.path.join(m, "senza-fonte.tsv")) +
                                                                   "CBACT01C.FD-ACCTFILE-REC\tprova\n"),
          ("S28",), "senza-fonte.tsv: CBACT01C.FD-ACCTFILE-REC non e' fra i contratti con sentinella",
          gruppi=("sorgente",))
    prova("dichiarazione-sbagliata-in-viste", lambda m: sostituisci(os.path.join(m, "viste.tsv"), "app/cpy/COCOM01Y.cpy\t19\t",
                                                                    "app/cpy/COCOM01Y.cpy\t20\t"),
          ("S30",), "COCOM01Y.CARDDEMO-COMMAREA@base: viste.tsv cita la riga 20", gruppi=("sorgente",))
    prova("alfanumerico-con-intero", lambda m: campo(m, cocom, "CDEMO-USER-TYPE", {"tipo": "intero", "valore": "3"}, None),
          ("V02",), "campo alfanumerico con valore di tipo intero")

    def spazio_in_testa(m):
        campo(m, cocom, "CDEMO-FROM-TRANID", "valore", '" CT0"', ricomponi=True)
    prova("spazio-in-testa", spazio_in_testa, ("V04",), "CDEMO-FROM-TRANID: valore con spazi in testa o in coda",
          gruppi=("valori",))

    def numerico_con_testo(m):
        campo(m, cocom, "CDEMO-CUST-ID", {"tipo": "testo", "valore": '"912345678"'}, None)
    prova("numerico-con-testo", numerico_con_testo, ("V05",), "PICTURE 9(09) vuole un valore intero, la sentinella "
                                                             "da' testo")
    prova("decimali-mancanti", lambda m: campo(m, tra2, "DIS-INT-RATE", "valore", "-1234.5", ricomponi=True), ("V06",),
          "-1234.5 non ha esattamente 2 decimali", gruppi=("valori", "decodifica"))
    prova("valore-zero", lambda m: campo(m, tra2, "DIS-INT-RATE", "valore", "0.00", ricomponi=True), ("V07",),
          "DIS-INT-RATE: valore zero", gruppi=("valori",))
    prova("negativo-senza-segno", lambda m: campo(m, tra2, "DIS-TRAN-CAT-CD", "valore", "-4007"), ("V10",),
          "DIS-TRAN-CAT-CD: valore negativo in un campo senza segno")

    def variabile_numerico(m):
        def f(righe):
            r = riga_contratto(righe, "VBR-REC")
            r.update(pic="9(11)", usage="DISPLAY", segno="-", cifre_intere="11", cifre_decimali="0", lunghezza="11")
        contratto(m, VARIABILE, f)
    prova("variabile-numerico", variabile_numerico, ("D04",), "campo numerico in un record variabile")

    def contratto_incoerente(m):
        def f(righe):
            riga_contratto(righe, "CDEMO-CUST-ID")["cifre_intere"] = "8"
        contratto(m, "COCOM01Y.CARDDEMO-COMMAREA", f)
    prova("contratto-incoerente", contratto_incoerente, ("T01",), "CDEMO-CUST-ID: PIC 9(09) incoerente",
          gruppi=("struttura",))


def attesa_codici(errori):
    return bool(errori), errori[:12]


def codici_sorgente():
    """Codici di asserzione dichiarati in controlli.py (ogni stringa fra apici della forma lettera + due cifre)."""
    with open(controlli.__file__, encoding="utf-8") as f:
        return set(re.findall(r'"([CDEKRSTUV][0-9]{2})"', f.read()))


def inventario(dichiarati, provati):
    """Codici di asserzione senza una prova negativa superata che li pretenda."""
    return sorted(set(dichiarati) - set(provati))


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
        mutazioni_copertura(b, contratti)
        mutazioni_ricodifica(b)
        mutazioni_asserzioni(b, contratti)
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
    # inventario: ogni asserzione di controlli.py ha almeno una prova superata che la pretende (e che fallirebbe se
    # l'asserzione fosse tolta); l'inventario stesso si prova con un codice inventato
    dichiarati = codici_sorgente()
    print(f"inventario delle asserzioni di controlli.py ({len(dichiarati)} codici): codice -> prove che lo pretendono")
    for k in sorted(dichiarati):
        prove = b.codici.get(k, [])
        print(f"  {k}: {len(prove)} prove" + (f", tra cui: {prove[0]}" if prove else " -- NESSUNA PROVA"))
    scoperti = inventario(dichiarati, b.codici)
    if inventario(dichiarati | {"X99"}, b.codici) != sorted(set(scoperti) | {"X99"}):
        print("INVENTARIO NON AFFIDABILE: un codice inventato (X99) non risulta scoperto")
        raise SystemExit(1)
    print("  controllo dell'inventario: un codice inventato (X99) risulta scoperto, come deve")
    if not dichiarati:
        print("INVENTARIO VUOTO: nessun codice di asserzione letto da controlli.py")
        raise SystemExit(1)
    if scoperti:
        print(f"ASSERZIONI SENZA PROVA NEGATIVA: {', '.join(scoperti)}")
    if fallite or scoperti:
        print(f"prove negative: {len(fallite)} FALLITE su {len(b.esiti)}; asserzioni senza prova: {len(scoperti)}")
        raise SystemExit(1)
    print(f"prove negative: {len(b.esiti)} superate, {len(b.non_applicabili)} non applicabili (elencate sopra, non "
          f"contate come superate), {len(dichiarati)} asserzioni tutte coperte")


if __name__ == "__main__":
    main(sys.argv[1:])
