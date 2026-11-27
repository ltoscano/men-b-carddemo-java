"""Lettura delle sentinelle dei tracciati e composizione dei loro byte (issue #43).

Una sentinella e' un record di prova scritto a mano leggendo il sorgente COBOL (copybook o programma), per una
coppia contratto/vista. Formato (UTF-8, campi separati da tabulazione; righe vuote e righe '#' ignorate):

  contratto        <contratto di #3>, per esempio COCOM01Y.CARDDEMO-COMMAREA
  vista            base | nome dell'area REDEFINES scelta (per esempio EXPORT-CUSTOMER-DATA)
  sentinella       nome della sentinella (coincide con il nome del file senza .tsv)
  sorgente         file del legacy che dichiara il tracciato, per esempio app/cpy/COCOM01Y.cpy
  radice           <riga> <nome>: la dichiarazione di livello 01 del tracciato
  lunghezza        somma delle lunghezze dei campi della vista, calcolata a mano
  fonte-lunghezza  <file:riga> <testo citato> | - <motivo>   (ripetibile) lunghezza dichiarata altrove
  prefisso         (solo record variabili) byte effettivamente scritti
  fonte-prefisso   (solo record variabili) <file:riga> <testo citato>
  record           i byte della sentinella in esadecimale (notazione dei vettori di #23: "HH" o "HH*n")
  ordinale riga nome picture usage indici da a tipo valore     intestazione della tabella dei campi, poi una riga
                   per campo elementare della vista, nell'ordine di dichiarazione:
     ordinale  numero d'ordine della dichiarazione elementare nel tracciato (tutte le aree, OCCURS non espansi)
     riga      riga della dichiarazione nel sorgente
     nome, picture, usage  come scritti nel sorgente ('-' se USAGE non e' scritta: DISPLAY implicito)
     indici    indici OCCURS separati da virgola, '-' se il campo non e' sotto un OCCURS
     da, a     intervallo di byte (da 1, estremi compresi), calcolato a mano sommando le lunghezze
     tipo      testo | intero | decimale
     valore    testo: notazione dei vettori di #23 ("..." con *n); intero/decimale: segno '-' facoltativo e,
               per decimale, esattamente tante cifre dopo il punto quante ne dichiara la PICTURE

Qui non si legge il contratto di #3 e non si usa il codec di #23: la composizione dei byte (componi) applica le
regole di rappresentazione del profilo oracle-gnucobol scritte qui una seconda volta, a partire dalla PICTURE e
dalla USAGE trascritte dal sorgente. Si usano da #23 solo la notazione esadecimale e quella dei valori (comune.py).
"""
import os
import re
import sys
from decimal import Decimal

sys.path.insert(0, "/analysis/data-codec/glue")
from comune import a_esa, da_esa, valore_a_testo, valore_da_testo  # noqa: E402

COLONNE = ["ordinale", "riga", "nome", "picture", "usage", "indici", "da", "a", "tipo", "valore"]
CHIAVI = ("contratto", "vista", "sentinella", "sorgente", "radice", "lunghezza", "fonte-lunghezza", "prefisso",
          "fonte-prefisso", "record")
RIPETIBILI = ("fonte-lunghezza",)
OBBLIGATORIE = ("contratto", "vista", "sentinella", "sorgente", "radice", "lunghezza", "fonte-lunghezza", "record")
TIPI = ("testo", "intero", "decimale")


class SentinellaErrore(ValueError):
    pass


# --- PICTURE e USAGE come scritte nel sorgente --------------------------------------------------------------------

_SIMBOLO = re.compile(r"(S)|([X9V])(?:\(([0-9]+)\))?")
USAGE_DISPLAY = ("-", "DISPLAY")
USAGE_BINARIO = ("COMP", "COMP-4", "BINARY", "COMPUTATIONAL", "COMPUTATIONAL-4")
USAGE_PACKED = ("COMP-3", "PACKED-DECIMAL", "COMPUTATIONAL-3")


def analizza(picture, usage):
    """dict con classe ('X' o '9'), segno, intere, decimali, rappresentazione, lunghezza in byte."""
    pos, x, intere, decimali, segno, v = 0, 0, 0, 0, False, False
    while pos < len(picture):
        m = _SIMBOLO.match(picture, pos)
        if not m:
            raise SentinellaErrore(f"PICTURE non riconosciuta: {picture}")
        if m.group(1):
            if pos != 0:
                raise SentinellaErrore(f"S non in testa alla PICTURE {picture}")
            segno = True
        else:
            n = int(m.group(3) or 1)
            if n == 0:
                raise SentinellaErrore(f"ripetizione nulla nella PICTURE {picture}")
            s = m.group(2)
            if s == "X":
                x += n
            elif s == "V":
                if v or n != 1:
                    raise SentinellaErrore(f"V ripetuta nella PICTURE {picture}")
                v = True
            elif v:
                decimali += n
            else:
                intere += n
        pos = m.end()
    if x and (intere or decimali or segno or v):
        raise SentinellaErrore(f"PICTURE mista non prevista: {picture}")
    if x:
        if usage not in USAGE_DISPLAY:
            raise SentinellaErrore(f"PICTURE alfanumerica {picture} con USAGE {usage}")
        return {"classe": "X", "segno": False, "intere": 0, "decimali": 0, "rappr": "display", "lunghezza": x}
    cifre = intere + decimali
    if cifre == 0:
        raise SentinellaErrore(f"PICTURE senza cifre: {picture}")
    if usage in USAGE_DISPLAY:
        rappr, lung = "display", cifre
    elif usage in USAGE_PACKED:
        rappr, lung = "packed", cifre // 2 + 1
    elif usage in USAGE_BINARIO:
        rappr = "binario"
        if cifre <= 4:
            lung = 2
        elif cifre <= 9:
            lung = 4
        elif cifre <= 18:
            lung = 8
        else:
            raise SentinellaErrore(f"binario con {cifre} cifre: {picture}")
    else:
        raise SentinellaErrore(f"USAGE non prevista: {usage}")
    return {"classe": "9", "segno": segno, "intere": intere, "decimali": decimali, "rappr": rappr, "lunghezza": lung}


# --- valori tipizzati ------------------------------------------------------------------------------------------------

_INTERO = re.compile(r"^-?[1-9][0-9]*$")
_DECIMALE = re.compile(r"^-?[0-9]+\.[0-9]+$")


def valore_tipizzato(tipo, testo):
    """Il valore atteso come oggetto Python: str per testo, Decimal (esponente 0 o -scala) per i numeri."""
    if tipo == "testo":
        return valore_da_testo(testo, True)
    if tipo == "intero":
        if not _INTERO.match(testo):
            raise SentinellaErrore(f"intero non in forma canonica: {testo}")
        return Decimal(testo)
    if tipo == "decimale":
        if not _DECIMALE.match(testo):
            raise SentinellaErrore(f"decimale non in forma canonica: {testo}")
        return Decimal(testo)
    raise SentinellaErrore(f"tipo sconosciuto: {tipo}")


def descrivi(tipo, valore):
    """Testo di un valore tipizzato per i messaggi (mai usato nei confronti)."""
    if tipo == "testo":
        return "testo " + valore_a_testo(valore)
    return f"{tipo} {valore:f}"


# --- composizione dei byte (profilo oracle-gnucobol), indipendente dal codec --------------------------------------
# Alfanumerico: un byte per carattere (ISO-8859-1). DISPLAY: cifre ASCII, segno nell'ultima cifra con la convenzione
# EBCDIC di -fsign=EBCDIC ('{' 'A'-'I' positivi 0-9, '}' 'J'-'R' negativi 0-9). COMP-3: due cifre per byte, ultimo
# semiottetto C (positivo), D (negativo), F (senza segno). COMP: big-endian, complemento a due se con segno.

POSITIVI = "{ABCDEFGHI"
NEGATIVI = "}JKLMNOPQR"


def componi_campo(pic, tipo, valore):
    if pic["classe"] == "X":
        if tipo != "testo":
            raise SentinellaErrore(f"campo alfanumerico con valore di tipo {tipo}")
        return valore.encode("latin-1")
    if tipo == "testo":
        raise SentinellaErrore("campo numerico con valore di tipo testo")
    n = int(valore.scaleb(pic["decimali"]))
    if Decimal(n) != valore.scaleb(pic["decimali"]):
        raise SentinellaErrore(f"{valore}: piu' decimali di quanti ne dichiari la PICTURE")
    cifre = pic["intere"] + pic["decimali"]
    if abs(n) >= 10 ** cifre:
        raise SentinellaErrore(f"{valore}: oltre la PICTURE")
    if n < 0 and not pic["segno"]:
        raise SentinellaErrore(f"{valore}: negativo in un campo senza segno")
    if pic["rappr"] == "display":
        t = str(abs(n)).rjust(cifre, "0")
        if pic["segno"]:
            t = t[:-1] + (NEGATIVI if n < 0 else POSITIVI)[int(t[-1])]
        return t.encode("latin-1")
    if pic["rappr"] == "packed":
        t = str(abs(n)).rjust(pic["lunghezza"] * 2 - 1, "0")
        s = [int(c) for c in t] + [(0xD if n < 0 else 0xC) if pic["segno"] else 0xF]
        return bytes((s[i] << 4) | s[i + 1] for i in range(0, len(s), 2))
    return n.to_bytes(pic["lunghezza"], "big", signed=pic["segno"])


# --- lettura ---------------------------------------------------------------------------------------------------------

def leggi(path):
    """dict con le chiavi d'intestazione e 'campi' (lista di dict con i valori gia' tipizzati)."""
    with open(path, encoding="utf-8") as f:
        righe = [(n, r.rstrip("\n")) for n, r in enumerate(f, 1)]
    s = {"_file": path, "fonte-lunghezza": [], "campi": []}
    tabella = False
    for n, r in righe:
        if not r.strip() or r.startswith("#"):
            continue
        p = r.split("\t")
        if not tabella:
            if p == COLONNE:
                tabella = True
                continue
            k = p[0]
            if k not in CHIAVI:
                raise SentinellaErrore(f"{path}:{n}: chiave sconosciuta '{k}'")
            if k in RIPETIBILI:
                if len(p) != 3:
                    raise SentinellaErrore(f"{path}:{n}: {k} vuole due valori (fonte e testo)")
                s[k].append((p[1], p[2]))
            else:
                if k in s:
                    raise SentinellaErrore(f"{path}:{n}: chiave ripetuta '{k}'")
                if k == "radice":
                    if len(p) != 3:
                        raise SentinellaErrore(f"{path}:{n}: radice vuole riga e nome")
                    s[k] = (int(p[1]), p[2])
                elif k == "fonte-prefisso":
                    if len(p) != 3:
                        raise SentinellaErrore(f"{path}:{n}: fonte-prefisso vuole fonte e testo")
                    s[k] = (p[1], p[2])
                else:
                    if len(p) != 2:
                        raise SentinellaErrore(f"{path}:{n}: {k} vuole un valore")
                    s[k] = p[1]
            continue
        if len(p) != len(COLONNE):
            raise SentinellaErrore(f"{path}:{n}: {len(p)} colonne invece di {len(COLONNE)}")
        c = dict(zip(COLONNE, p))
        c["_riga_file"] = n
        try:
            c["ordinale"] = int(c["ordinale"])
            c["riga"] = int(c["riga"])
            c["da"] = int(c["da"])
            c["a"] = int(c["a"])
            c["indici"] = () if c["indici"] == "-" else tuple(int(i) for i in c["indici"].split(","))
        except ValueError as e:
            raise SentinellaErrore(f"{path}:{n}: numero non valido ({e})")
        if c["tipo"] not in TIPI:
            raise SentinellaErrore(f"{path}:{n}: tipo '{c['tipo']}' non tra {TIPI}")
        try:
            c["v"] = valore_tipizzato(c["tipo"], c["valore"])
        except (ValueError, SentinellaErrore) as e:
            raise SentinellaErrore(f"{path}:{n}: {e}")
        s["campi"].append(c)
    if not tabella:
        raise SentinellaErrore(f"{path}: manca l'intestazione della tabella dei campi")
    for k in OBBLIGATORIE:
        if k not in s or (k in RIPETIBILI and not s[k]):
            raise SentinellaErrore(f"{path}: manca '{k}'")
    if not s["campi"]:
        raise SentinellaErrore(f"{path}: nessun campo")
    if ("prefisso" in s) != ("fonte-prefisso" in s):
        raise SentinellaErrore(f"{path}: prefisso e fonte-prefisso vanno dichiarati insieme")
    try:
        s["lunghezza"] = int(s["lunghezza"])
        s["prefisso"] = int(s["prefisso"]) if "prefisso" in s else None
        s["byte"] = da_esa(s["record"])
    except ValueError as e:
        raise SentinellaErrore(f"{path}: {e}")
    nome = os.path.basename(path)[:-4] if path.endswith(".tsv") else None
    if nome != s["sentinella"]:
        raise SentinellaErrore(f"{path}: il nome del file non coincide con 'sentinella' ({s['sentinella']})")
    if os.path.basename(os.path.dirname(path)) != s["contratto"]:
        raise SentinellaErrore(f"{path}: la cartella non coincide con 'contratto' ({s['contratto']})")
    return s


def identita(c):
    """Identita' di un campo nella sentinella: ordinale di dichiarazione e indici OCCURS (mai l'offset)."""
    return (c["ordinale"], c["indici"])


def testo_identita(contratto, vista, sentinella, ident, nome):
    ordinale, indici = ident
    occ = "(" + ",".join(str(i) for i in indici) + ")" if indici else ""
    return f"{contratto}@{vista}/{sentinella} #{ordinale}{occ} {nome}"


def componi(s):
    """I byte che la tabella dei campi descrive: ogni valore composto dalla propria PICTURE e messo nel proprio
    intervallo. Errore se gli intervalli non sono contigui da 1, se un intervallo non ha la lunghezza ricavata dalla
    PICTURE o se un valore alfanumerico non riempie esattamente il campo (o la parte scritta del prefisso)."""
    out = bytearray()
    atteso = 1
    for c in s["campi"]:
        try:
            pic = analizza(c["picture"], c["usage"])
        except SentinellaErrore as e:
            raise SentinellaErrore(f"{s['_file']}: {c['nome']}: {e}")
        if c["da"] != atteso:
            raise SentinellaErrore(f"{c['nome']} (riga {c['_riga_file']}): inizia a {c['da']}, atteso {atteso}")
        if c["a"] - c["da"] + 1 != pic["lunghezza"]:
            raise SentinellaErrore(f"{c['nome']}: intervallo {c['da']}-{c['a']} di {c['a'] - c['da'] + 1} byte, "
                                   f"la PICTURE {c['picture']} {c['usage']} ne da' {pic['lunghezza']}")
        try:
            b = componi_campo(pic, c["tipo"], c["v"])
        except SentinellaErrore as e:
            raise SentinellaErrore(f"{s['_file']}: {c['nome']}: {e}")
        scritti = pic["lunghezza"]
        if s["prefisso"] is not None:
            scritti = max(0, min(c["a"], s["prefisso"]) - c["da"] + 1)
        if pic["classe"] == "X":
            if len(b) != scritti:
                raise SentinellaErrore(f"{c['nome']}: testo di {len(b)} byte per {scritti} byte da scrivere")
        elif scritti != pic["lunghezza"]:
            raise SentinellaErrore(f"{c['nome']}: campo numerico troncato dal prefisso")
        out += b[:scritti]
        atteso = c["a"] + 1
    return bytes(out)


def esa(dati):
    return a_esa(dati)
