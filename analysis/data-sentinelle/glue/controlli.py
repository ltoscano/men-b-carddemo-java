"""Controlli delle sentinelle dei tracciati (issue #43).

Gruppi di controllo (ogni difetto e' una riga "ERRORE [gruppo] ..."):
  [sentinella]  la sentinella si legge (formato, valori tipizzati)
  [sorgente]    verifica sorgente -> sentinella: alle righe dichiarate il sorgente dichiara quel nome, quella PICTURE e
                quella USAGE; le righe sono in ordine e coprono tutte le dichiarazioni elementari della vista, senza
                salti; ordinali coerenti; intervalli a mano contigui e lunghi quanto la PICTURE del sorgente; somma
                uguale alla lunghezza dichiarata altrove (citazione verificata sul file), dove la fonte esiste
  [coerenza]    i byte della sentinella sono quelli che la sua tabella descrive (composizione indipendente dal codec)
  [valori]      valori discriminanti per campo: nessun campo vuoto; numerici con tutte le cifre della PICTURE (prima
                cifra non zero), decimali tutti diversi da zero, ogni campo con segno negativo in almeno una
                sentinella della propria vista; [unicita] nessuna coppia di campi dello stesso record con gli stessi
                byte o lo stesso valore tipizzato
  [copertura]   insieme dei contratti, delle viste, delle sentinelle e dei campi (per identita'), nelle due direzioni
  [struttura]   il contratto si legge: righe elementari classificabili, lunghezza coerente con la PICTURE
  [decodifica]  ogni campo della vista, preso dal contratto di #3 (offset, PICTURE, USAGE) e decodificato con il codec
                di #23, deve dare esattamente il valore atteso (tipo, valore, scala); [ricodifica] la ricodifica
                conservativa ridà i byte originali e i campi della vista ricompongono il record
Identita' di un campo: contratto, vista, ordinale di dichiarazione, indici OCCURS. L'offset non ne fa parte.
"""
import os
import re
import sys
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, "/analysis/data-codec/glue")
import codec  # noqa: E402
from censimento import classifica  # noqa: E402
from comune import leggi_tsv  # noqa: E402
from sentinella import SentinellaErrore, analizza, componi, descrivi, leggi  # noqa: E402
from sorgente import SorgenteErrore, aree, elementari_vista, leggi_righe, tracciato  # noqa: E402

PROFILO = "oracle-gnucobol"
VARIABILE = "CBACT01C.VBR-REC"   # il record variabile aggiunto ai contratti dei copybook (voce 61 del registro)
RIEMPIMENTO = b"\x00"            # riempimento del carico di un record variabile, solo per la chiamata al codec


class Esito:
    def __init__(self):
        self.errori = []

    def errore(self, gruppo, testo):
        self.errori.append(f"ERRORE [{gruppo}] {testo}")


# --- contratto di #3 ------------------------------------------------------------------------------------------------

_INDICI = re.compile(r"\(([0-9]+)\)")


def righe_contratto(path):
    _, righe = leggi_tsv(path)
    return righe


def ordina_contratto(righe):
    """Ordinale di dichiarazione e indici di ogni riga elementare, dall'ordine delle righe del contratto: una
    dichiarazione sotto OCCURS ha piu' righe (una per occorrenza) con lo stesso ordinale e indici diversi; due righe
    con lo stesso percorso e gli stessi indici (FILLER ripetuti) sono dichiarazioni distinte."""
    visti, ordinali, conta = {}, {}, {}
    for r in righe:
        if r["tipo"] != "elementare":
            continue
        indici = tuple(int(i) for i in _INDICI.findall(r["percorso"]))
        nudo = _INDICI.sub("", r["percorso"])
        k = (nudo, indici)
        conta[k] = conta.get(k, 0) + 1
        chiave = (nudo, conta[k])
        if chiave not in ordinali:
            ordinali[chiave] = len(ordinali) + 1
        r["_identita"] = (ordinali[chiave], indici)
        visti[r["_identita"]] = visti.get(r["_identita"], 0) + 1
    return [k for k, n in visti.items() if n > 1]


def aree_contratto(righe):
    return sorted({r["area"] for r in righe if r["area"] != "-"})


def vista_contratto(righe, vista):
    """Righe elementari del contratto nella vista: 'base' prende le righe senza area; un'area prende le proprie righe
    e quelle senza area che non stanno nell'oggetto che essa ridefinisce."""
    if vista == "base":
        return [r for r in righe if r["tipo"] == "elementare" and r["area"] == "-"]
    radici = [r for r in righe if r["area"] == vista and r["redefines"] != "-"]
    if len(radici) != 1:
        raise ValueError(f"vista {vista}: {len(radici)} righe REDEFINES con questa area nel contratto")
    rad = radici[0]
    padre = rad["percorso"].rsplit("/", 1)[0]
    bersagli = [r for r in righe if r["campo"] == rad["redefines"] and r["area"] == "-"
                and r["percorso"].rsplit("/", 1)[0] == padre]
    if len(bersagli) != 1:
        raise ValueError(f"vista {vista}: oggetto ridefinito {rad['redefines']} non trovato nel contratto")
    escluso = bersagli[0]["percorso"]
    out = []
    for r in righe:
        if r["tipo"] != "elementare":
            continue
        if r["area"] == vista:
            out.append(r)
        elif r["area"] == "-" and r["percorso"] != escluso and not r["percorso"].startswith(escluso + "/"):
            out.append(r)
    return out


# --- elenchi ----------------------------------------------------------------------------------------------------------

def leggi_viste(path):
    _, righe = leggi_tsv(path)
    out = []
    for r in righe:
        r["_sentinelle"] = [x for x in r["sentinelle"].split(",") if x]
        out.append(r)
    return out


def contratti_copybook(path_tsv):
    _, righe = leggi_tsv(path_tsv)
    return {r["contratto"]: r for r in righe}


def leggi_sentinelle(cartella, es):
    out = []
    if not os.path.isdir(cartella):
        es.errore("copertura", f"cartella delle sentinelle assente: {cartella}")
        return out
    for c in sorted(os.listdir(cartella)):
        d = os.path.join(cartella, c)
        if not os.path.isdir(d):
            es.errore("copertura", f"file inatteso fra le cartelle delle sentinelle: {c}")
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".tsv"):
                es.errore("copertura", f"file inatteso fra le sentinelle: {c}/{f}")
                continue
            try:
                out.append(leggi(os.path.join(d, f)))
            except (SentinellaErrore, ValueError) as e:
                es.errore("sentinella", str(e))
    return out


def nome_s(s):
    return f"{s['contratto']}@{s['vista']}/{s['sentinella']}"


def id_testo(s, ident, nome):
    o, ind = ident
    occ = "(" + ",".join(str(i) for i in ind) + ")" if ind else ""
    return f"{nome_s(s)} #{o}{occ} {nome}"


# --- [sorgente] -----------------------------------------------------------------------------------------------------

def _cita(legacy, fonte, testo, numero, es, s, cosa):
    try:
        f, riga = fonte.rsplit(":", 1)
        riga = int(riga)
    except ValueError:
        es.errore("sorgente", f"{nome_s(s)}: {cosa}: fonte non nella forma file:riga: {fonte}")
        return
    p = os.path.join(legacy, f)
    if not os.path.isfile(p):
        es.errore("sorgente", f"{nome_s(s)}: {cosa}: file citato assente: {f}")
        return
    righe = leggi_righe(p)
    if not 1 <= riga <= len(righe) or testo not in righe[riga - 1]:
        es.errore("sorgente", f"{nome_s(s)}: {cosa}: il testo citato '{testo}' non e' alla riga {fonte}")
        return
    if not re.search(r"(?<![0-9])" + str(numero) + r"(?![0-9])", testo):
        es.errore("sorgente", f"{nome_s(s)}: {cosa}: {numero} non compare nel testo citato '{testo}' ({fonte})")


def verifica_sorgente(s, legacy, es, alberi):
    p = os.path.join(legacy, s["sorgente"])
    if not os.path.isfile(p):
        es.errore("sorgente", f"{nome_s(s)}: sorgente assente: {s['sorgente']}")
        return
    chiave = (s["sorgente"], s["radice"])
    try:
        if chiave not in alberi:
            alberi[chiave] = tracciato(p, s["radice"][0], s["radice"][1])
        rad = alberi[chiave]
        attesi = elementari_vista(rad, s["vista"])
    except SorgenteErrore as e:
        es.errore("sorgente", f"{nome_s(s)}: {e}")
        return
    per_riga = {}
    for o, riga, nome, pic, usage, ind in attesi:
        per_riga[riga] = (o, nome, pic, usage)
    righe = leggi_righe(p)
    # 1. alla riga dichiarata: nome, PICTURE, USAGE
    for c in s["campi"]:
        if c["riga"] not in per_riga:
            testo = righe[c["riga"] - 1].strip() if 1 <= c["riga"] <= len(righe) else "(fuori dal file)"
            es.errore("sorgente", f"{nome_s(s)}: riga {c['riga']} ({c['nome']}): non e' una dichiarazione elementare "
                                  f"della vista nel sorgente: '{testo}'")
            continue
        o, nome, pic, usage = per_riga[c["riga"]]
        for cosa, sorg, sent in (("nome", nome, c["nome"]), ("PICTURE", pic, c["picture"]),
                                 ("USAGE", usage, c["usage"])):
            if sorg != sent:
                es.errore("sorgente", f"{nome_s(s)}: riga {c['riga']}: {cosa} nel sorgente '{sorg}', "
                                      f"nella sentinella '{sent}'")
        if o != c["ordinale"]:
            es.errore("sorgente", f"{nome_s(s)}: riga {c['riga']} ({nome}): ordinale nel sorgente {o}, "
                                  f"nella sentinella {c['ordinale']}")
    # 2. ordine e copertura senza salti
    seq_s = [(c["riga"], c["indici"]) for c in s["campi"]]
    seq_a = [(riga, ind) for _, riga, _, _, _, ind in attesi]
    for a, b in zip(seq_s, seq_s[1:]):
        if not (a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])):
            es.errore("sorgente", f"{nome_s(s)}: righe non in ordine crescente: riga {a[0]}{list(a[1]) or ''} "
                                  f"seguita da riga {b[0]}{list(b[1]) or ''}")
    if seq_s != seq_a:
        ss, sa = set(seq_s), set(seq_a)
        for r, ind in sorted(sa - ss):
            es.errore("sorgente", f"{nome_s(s)}: dichiarazione saltata: riga {r}{list(ind) or ''} "
                                  f"({per_riga[r][1]}) non e' nella sentinella")
        for r, ind in sorted(ss - sa):
            es.errore("sorgente", f"{nome_s(s)}: riga {r}{list(ind) or ''} nella sentinella ma non nella vista")
        if len(seq_s) != len(set(seq_s)):
            es.errore("sorgente", f"{nome_s(s)}: una dichiarazione compare piu' volte nella sentinella")
        if ss == sa and len(seq_s) == len(set(seq_s)):
            es.errore("sorgente", f"{nome_s(s)}: dichiarazioni in ordine diverso da quello del sorgente")
    # 3. intervalli a mano contigui e lunghi quanto la PICTURE del sorgente; somma e lunghezza dichiarata
    atteso = 1
    for c in s["campi"]:
        pic, usage = (per_riga[c["riga"]][2], per_riga[c["riga"]][3]) if c["riga"] in per_riga else (c["picture"], c["usage"])
        try:
            lung = analizza(pic, usage)["lunghezza"]
        except SentinellaErrore as e:
            es.errore("sorgente", f"{nome_s(s)}: riga {c['riga']}: {e}")
            continue
        if c["da"] != atteso:
            es.errore("sorgente", f"{nome_s(s)}: {c['nome']} (riga {c['riga']}): intervallo {c['da']}-{c['a']}, "
                                  f"atteso l'inizio a {atteso} (intervalli non contigui)")
        if c["a"] - c["da"] + 1 != lung:
            es.errore("sorgente", f"{nome_s(s)}: {c['nome']} (riga {c['riga']}): intervallo {c['da']}-{c['a']} di "
                                  f"{c['a'] - c['da'] + 1} byte, la PICTURE {pic} {usage} del sorgente ne da' {lung}")
        atteso = c["a"] + 1
    if atteso - 1 != s["lunghezza"]:
        es.errore("sorgente", f"{nome_s(s)}: i campi finiscono al byte {atteso - 1}, la lunghezza dichiarata e' "
                              f"{s['lunghezza']}")
    for fonte, testo in s["fonte-lunghezza"]:
        if fonte == "-":
            if len(s["fonte-lunghezza"]) > 1:
                es.errore("sorgente", f"{nome_s(s)}: fonte-lunghezza '-' insieme ad altre fonti")
            continue
        _cita(legacy, fonte, testo, s["lunghezza"], es, s, "lunghezza")
    if s["prefisso"] is not None:
        _cita(legacy, s["fonte-prefisso"][0], s["fonte-prefisso"][1], s["prefisso"], es, s, "prefisso")
        if not 0 < s["prefisso"] < s["lunghezza"]:
            es.errore("sorgente", f"{nome_s(s)}: prefisso {s['prefisso']} non minore della lunghezza {s['lunghezza']}")
    n = s["prefisso"] if s["prefisso"] is not None else s["lunghezza"]
    if len(s["byte"]) != n:
        es.errore("sorgente", f"{nome_s(s)}: record di {len(s['byte'])} byte, attesi {n}")


# --- [coerenza], [valori], [unicita] ------------------------------------------------------------------------------

def verifica_valori(s, es):
    try:
        b = componi(s)
        if b != s["byte"]:
            diff = next((i for i in range(min(len(b), len(s["byte"]))) if b[i] != s["byte"][i]), min(len(b), len(s["byte"])))
            es.errore("coerenza", f"{nome_s(s)}: i byte della riga 'record' non sono quelli descritti dalla tabella "
                                  f"(prima differenza al byte {diff + 1})")
    except SentinellaErrore as e:
        es.errore("coerenza", f"{nome_s(s)}: {e}")
    for c in s["campi"]:
        try:
            pic = analizza(c["picture"], c["usage"])
        except SentinellaErrore as e:
            es.errore("valori", f"{nome_s(s)}: {c['nome']}: {e}")
            continue
        c["_pic"] = pic
        chi = id_testo(s, (c["ordinale"], c["indici"]), c["nome"])
        if pic["classe"] == "X":
            if c["tipo"] != "testo":
                es.errore("valori", f"{chi}: campo alfanumerico con valore di tipo {c['tipo']}")
                continue
            v = c["v"]
            if not v or v.strip(" ") == "" or v.strip("0") == "":
                es.errore("valori", f"{chi}: valore tutto spazi o tutto zeri")
            elif v[0] == " " or v[-1] == " ":
                es.errore("valori", f"{chi}: valore con spazi in testa o in coda (deve riempire il campo)")
            continue
        tipo = "decimale" if pic["decimali"] else "intero"
        if c["tipo"] != tipo:
            es.errore("valori", f"{chi}: PICTURE {c['picture']} vuole un valore {tipo}, la sentinella da' {c['tipo']}")
            continue
        if tipo == "decimale" and len(c["valore"].split(".")[1]) != pic["decimali"]:
            es.errore("valori", f"{chi}: {c['valore']} non ha esattamente {pic['decimali']} decimali")
            continue
        n = int(c["v"].scaleb(pic["decimali"]))
        cifre = pic["intere"] + pic["decimali"]
        t = str(abs(n))
        if n == 0:
            es.errore("valori", f"{chi}: valore zero")
        elif len(t) != cifre:
            es.errore("valori", f"{chi}: {c['valore']} usa {len(t)} cifre, la PICTURE {c['picture']} ne ha {cifre} "
                                f"(prima cifra non zero richiesta)")
        if pic["decimali"] and "0" in t[-pic["decimali"]:]:
            es.errore("valori", f"{chi}: {c['valore']}: cifre decimali non tutte diverse da zero")
        if n < 0 and not pic["segno"]:
            es.errore("valori", f"{chi}: valore negativo in un campo senza segno")
    # unicita': byte (campi della stessa lunghezza) e valori tipizzati, a coppie
    pezzi = []
    for c in s["campi"]:
        if s["prefisso"] is not None:
            b = s["byte"][c["da"] - 1:min(c["a"], s["prefisso"])]
        else:
            b = s["byte"][c["da"] - 1:c["a"]]
        pezzi.append((c, b))
    for i, (c1, b1) in enumerate(pezzi):
        for c2, b2 in pezzi[i + 1:]:
            if b1 == b2:
                es.errore("unicita", f"{nome_s(s)}: {c1['nome']} e {c2['nome']} hanno gli stessi byte")
            if c1["tipo"] == c2["tipo"] and c1["v"] == c2["v"]:
                es.errore("unicita", f"{nome_s(s)}: {c1['nome']} e {c2['nome']} hanno lo stesso valore "
                                     f"({descrivi(c1['tipo'], c1['v'])})")


def verifica_negativi_per_vista(sentinelle, es):
    """Ogni campo con segno ha un valore negativo in almeno una sentinella della propria vista."""
    gruppi = {}
    for s in sentinelle:
        for c in s["campi"]:
            if c.get("_pic") and c["_pic"]["segno"]:
                k = (s["contratto"], s["vista"], c["ordinale"], c["indici"], c["nome"])
                gruppi.setdefault(k, []).append(c["v"] < 0)
    for (contratto, vista, o, ind, nome), negs in sorted(gruppi.items()):
        if not any(negs):
            es.errore("valori", f"{contratto}@{vista} #{o} {nome}: campo con segno senza valore negativo in "
                                f"nessuna sentinella della vista")


# --- [decodifica], [ricodifica], [struttura] -----------------------------------------------------------------------

def _ottenuto(r):
    """(tipo, valore) di un risultato del codec, senza conversioni a testo."""
    v = r.valore
    if isinstance(v, str):
        return "testo", v
    if isinstance(v, Decimal):
        return ("decimale" if v.as_tuple().exponent < 0 else "intero"), v
    return "?", v


def uguali(tipo_a, va, tipo_o, vo):
    if tipo_a != tipo_o or type(va) is not type(vo):
        return False
    if isinstance(va, Decimal):
        return va == vo and va.as_tuple().exponent == vo.as_tuple().exponent
    return va == vo


def classifica_riga(r, contratto):
    r = dict(r)
    r["_contratto"] = contratto
    try:
        cat, var, _, _, _ = classifica(r)
    except SystemExit as e:
        raise ValueError(str(e))
    g = codec.geometria(cat, var)
    if g.lunghezza != int(r["lunghezza"]):
        raise ValueError(f"{contratto} {r['campo']}: la PICTURE {r['pic']} {r['usage']} da' {g.lunghezza} byte, "
                         f"il contratto ne dichiara {r['lunghezza']}")
    return cat, var, g


def decodifica_sentinella(s, righe, es, conteggi):
    try:
        campi = vista_contratto(righe, s["vista"])
    except ValueError as e:
        es.errore("copertura", f"{nome_s(s)}: {e}")
        return
    per_id = {}
    for r in campi:
        per_id.setdefault(r["_identita"], []).append(r)
    attesi = {}
    for c in s["campi"]:
        k = (c["ordinale"], c["indici"])
        if k in attesi:
            es.errore("copertura", f"{id_testo(s, k, c['nome'])}: atteso duplicato nella sentinella")
        attesi[k] = c
    conteggi[(s["contratto"], s["vista"], s["sentinella"])] = (len(s["campi"]), len(campi))
    for k in sorted(set(per_id) - set(attesi)):
        es.errore("copertura", f"{id_testo(s, k, per_id[k][0]['campo'])}: campo della vista nel contratto senza "
                               f"atteso nella sentinella")
    for k in sorted(set(attesi) - set(per_id)):
        es.errore("copertura", f"{id_testo(s, k, attesi[k]['nome'])}: atteso senza campo corrispondente nella "
                               f"vista del contratto")
    if s["prefisso"] is not None:
        buf = s["byte"] + RIEMPIMENTO * (s["lunghezza"] - len(s["byte"]))
        limite = s["prefisso"]
    else:
        buf, limite = s["byte"], len(s["byte"])
    pezzi = []
    for k in sorted(set(attesi) & set(per_id)):
        c = attesi[k]
        if len(per_id[k]) != 1:
            es.errore("copertura", f"{id_testo(s, k, c['nome'])}: {len(per_id[k])} righe del contratto con la stessa identita'")
            continue
        r = per_id[k][0]
        chi = id_testo(s, k, c["nome"])
        if r["campo"] != c["nome"]:
            es.errore("decodifica", f"{chi}: nome nel contratto {r['campo']}")
        try:
            cat, var, g = classifica_riga(r, s["contratto"])
            off = int(r["offset"])
        except (ValueError, codec.CodificaErrore) as e:
            es.errore("struttura", f"{chi}: {e}")
            continue
        atteso = descrivi(c["tipo"], c["v"])
        try:
            ris = codec.decodifica(PROFILO, cat, var, buf, off)
        except codec.CampoIncompleto as e:
            es.errore("decodifica", f"{chi}: atteso {atteso}, ottenuto rifiuto del codec CampoIncompleto ({e})")
            continue
        if ris.stato != "valido":
            es.errore("decodifica", f"{chi}: atteso {atteso}, ottenuto stato {ris.stato} ({cat} {var} all'offset {off})")
            continue
        tipo_o, v_o = _ottenuto(ris)
        scritti = max(0, min(off + g.lunghezza, limite) - off)
        if s["prefisso"] is not None:
            if tipo_o != "testo":
                es.errore("decodifica", f"{chi}: campo numerico in un record variabile: confronto sul prefisso non previsto")
                continue
            v_o = v_o[:scritti]
        if not uguali(c["tipo"], c["v"], tipo_o, v_o):
            es.errore("decodifica", f"{chi}: atteso {atteso}, ottenuto {descrivi(tipo_o, v_o) if tipo_o != '?' else repr(v_o)} "
                                    f"({cat} {var} all'offset {off})")
            continue
        orig = codec.ricodifica(ris)
        if orig != buf[off:off + g.lunghezza]:
            es.errore("ricodifica", f"{chi}: la ricodifica conservativa non ridà i byte originali")
            continue
        pezzi.append((off, orig[:scritti]))
    if len(pezzi) == len(attesi) == len(per_id):
        pezzi.sort()
        if b"".join(p for _, p in pezzi) != s["byte"]:
            es.errore("ricodifica", f"{nome_s(s)}: i campi della vista non ricompongono il record (buchi o sovrapposizioni)")


# --- verifica completa ------------------------------------------------------------------------------------------------

def verifica(legacy, cartella_contratti, contratti_tsv, cartella_sentinelle, viste_tsv, decodifica=True):
    """Esegue tutti i controlli; restituisce (Esito, riepilogo). Con decodifica=False salta solo [decodifica]."""
    es = Esito()
    sentinelle = leggi_sentinelle(cartella_sentinelle, es)
    viste = leggi_viste(viste_tsv)
    tutti = contratti_copybook(contratti_tsv)
    copybook = {c for c, r in tutti.items() if r["righe"] == "copybook"}
    attesi_contratti = copybook | {VARIABILE}
    # [copertura] contratti
    in_viste = {v["contratto"] for v in viste}
    in_sent = {s["contratto"] for s in sentinelle}
    for c in sorted(attesi_contratti - in_viste):
        es.errore("copertura", f"contratto {c}: senza coppia contratto/vista in viste.tsv")
    for c in sorted(attesi_contratti - in_sent):
        es.errore("copertura", f"contratto {c}: senza sentinella")
    for c in sorted((in_viste | in_sent) - attesi_contratti):
        es.errore("copertura", f"contratto {c}: con sentinella ma non tra i contratti dei copybook (ne' {VARIABILE})")
    # [copertura] coppie e sentinelle
    coppie = {}
    for v in viste:
        k = (v["contratto"], v["vista"])
        if k in coppie:
            es.errore("copertura", f"coppia {k[0]}@{k[1]} ripetuta in viste.tsv")
        coppie[k] = v
    dich = {(v["contratto"], v["vista"], n) for v in viste for n in v["_sentinelle"]}
    pres = {(s["contratto"], s["vista"], s["sentinella"]) for s in sentinelle}
    for c, vi, n in sorted(dich - pres):
        es.errore("copertura", f"sentinella {c}@{vi}/{n} dichiarata in viste.tsv ma assente")
    for c, vi, n in sorted(pres - dich):
        es.errore("copertura", f"sentinella {c}@{vi}/{n} presente ma non dichiarata in viste.tsv")
    # contratti di #3 e viste
    contratti = {}
    for c in sorted(attesi_contratti & (in_viste | in_sent)):
        p = os.path.join(cartella_contratti, c + ".tsv")
        if not os.path.isfile(p):
            es.errore("copertura", f"contratto {c}: file del contratto assente")
            continue
        righe = righe_contratto(p)
        dup = ordina_contratto(righe)
        for k in dup:
            es.errore("struttura", f"contratto {c}: identita' {k} ripetuta")
        contratti[c] = righe
        v_attese = {"base"} | set(aree_contratto(righe))
        v_dich = {vi for (cc, vi) in coppie if cc == c}
        for vi in sorted(v_attese - v_dich):
            es.errore("copertura", f"contratto {c}: vista {vi} (area REDEFINES del contratto) senza sentinella")
        for vi in sorted(v_dich - v_attese):
            es.errore("copertura", f"contratto {c}: vista {vi} di viste.tsv non e' un'area REDEFINES del contratto")
        if c in tutti and tutti[c]["sorgente"] not in {coppie[k]["sorgente"] for k in coppie if k[0] == c}:
            es.errore("copertura", f"contratto {c}: sorgente in viste.tsv diverso da quello del contratto ({tutti[c]['sorgente']})")
    # [sorgente]: viste.tsv contro le REDEFINES del sorgente; sentinelle contro il sorgente
    alberi = {}
    for (c, vi), v in sorted(coppie.items()):
        ss = [s for s in sentinelle if s["contratto"] == c and s["vista"] == vi]
        if not ss:
            continue
        s0 = ss[0]
        if v["sorgente"] != s0["sorgente"]:
            es.errore("copertura", f"{c}@{vi}: sorgente in viste.tsv {v['sorgente']}, nella sentinella {s0['sorgente']}")
        p = os.path.join(legacy, s0["sorgente"])
        try:
            rad = tracciato(p, s0["radice"][0], s0["radice"][1])
            nomi_aree = {a["nome"]: a["riga"] for a in aree(rad)}
        except (SorgenteErrore, OSError) as e:
            es.errore("sorgente", f"{c}@{vi}: {e}")
            continue
        riga_attesa = rad["riga"] if vi == "base" else nomi_aree.get(vi)
        if str(riga_attesa) != v["dichiarazione"]:
            es.errore("sorgente", f"{c}@{vi}: viste.tsv cita la riga {v['dichiarazione']}, il sorgente dichiara la "
                                  f"vista alla riga {riga_attesa}")
        if vi == "base":
            v_src = {"base"} | set(nomi_aree)
            v_dich = {x for (cc, x) in coppie if cc == c}
            for x in sorted(v_src - v_dich):
                es.errore("sorgente", f"contratto {c}: REDEFINES {x} (riga {nomi_aree[x]}) senza vista in viste.tsv")
            for x in sorted(v_dich - v_src):
                es.errore("sorgente", f"contratto {c}: vista {x} di viste.tsv senza REDEFINES nel sorgente")
    for s in sentinelle:
        if (s["contratto"], s["vista"]) not in coppie:
            continue
        verifica_sorgente(s, legacy, es, alberi)
        verifica_valori(s, es)
        if s["contratto"] in tutti and tutti[s["contratto"]].get("recordsize", "-") not in ("-", "") \
                and all(f == "-" for f, _ in s["fonte-lunghezza"]):
            es.errore("sorgente", f"{nome_s(s)}: il contratto di #3 cita una RECORDSIZE ({tutti[s['contratto']]['recordsize']}) "
                                  f"ma la sentinella non cita nessuna lunghezza dichiarata")
    verifica_negativi_per_vista(sentinelle, es)
    # [decodifica]
    conteggi = {}
    for s in sentinelle if decodifica else []:
        if s["contratto"] in contratti and (s["contratto"], s["vista"]) in coppie:
            decodifica_sentinella(s, contratti[s["contratto"]], es, conteggi)
    riepilogo = {"copybook": sorted(copybook), "conteggi": conteggi, "coppie": sorted(coppie),
                 "tutti": tutti, "sentinelle": sentinelle, "contratti": contratti}
    return es, riepilogo
