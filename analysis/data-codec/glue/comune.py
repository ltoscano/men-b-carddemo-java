"""Funzioni condivise dagli script di colla delle regole di codifica (issue #23).

Qui non c'e' nessuna regola di codifica: solo lettura e scrittura di TSV, la notazione esadecimale dei
vettori e la forma canonica dei valori. Le regole stanno in codec.py.
"""
import json
import os
import re
from decimal import Decimal, InvalidOperation

PROFILI = ("oracle-gnucobol", "zos-ebcdic")
CATEGORIE = ("alfanumerico", "display-senza-segno", "display-con-segno", "comp-3", "comp")
STATI_DECODIFICA = ("valido", "non-valido", "oltre-picture", "non-determinato")
STATI_CODIFICA = ("ok", "errore")
COLONNE_VETTORI = ("categoria", "variante", "operazione", "ingresso", "stato", "valore", "byte", "move", "fonte", "nota")


def leggi_tsv(path):
    """TSV con intestazione; ignora righe vuote e righe che iniziano con '#'. Restituisce (testa, righe),
    ogni riga e' un dict con in piu' '_riga' (numero di riga nel file, da 1)."""
    with open(path, encoding="utf-8") as f:
        grezze = [(n, r.rstrip("\n")) for n, r in enumerate(f, 1)]
    utili = [(n, r) for n, r in grezze if r.strip() and not r.startswith("#")]
    if not utili:
        raise SystemExit(f"{path}: file vuoto")
    testa = utili[0][1].split("\t")
    out = []
    for n, r in utili[1:]:
        campi = r.split("\t")
        if len(campi) == len(testa) - 1 and testa[-1] == "nota":
            campi.append("")   # nota vuota: gli editor tolgono la tabulazione finale
        if len(campi) != len(testa):
            raise SystemExit(f"{path}: riga {n}: {len(campi)} colonne invece di {len(testa)}")
        d = dict(zip(testa, campi))
        d["_riga"] = n
        out.append(d)
    return testa, out


def scrivi_tsv(path, testa, righe):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\t".join(testa) + "\n")
        for r in righe:
            f.write("\t".join(str(r[c]) for c in testa) + "\n")


# --- esadecimale dei vettori ----------------------------------------------------------------------
# Byte separati da spazi, due cifre esadecimali maiuscole ciascuno; "HH*n" ripete n volte il byte HH
# (serve ai campi lunghi: "40*177" sono 177 byte X'40').

_TOKEN = re.compile(r"^([0-9A-F]{2})(?:\*([1-9][0-9]*))?$")


def da_esa(testo):
    if testo in ("", "-"):
        raise ValueError(f"esadecimale assente: '{testo}'")
    out = bytearray()
    for t in testo.split(" "):
        m = _TOKEN.match(t)
        if not m:
            raise ValueError(f"byte esadecimale non valido: '{t}' in '{testo}'")
        out += bytes([int(m.group(1), 16)]) * int(m.group(2) or 1)
    return bytes(out)


def a_esa(dati):
    """Forma compatta: le ripetizioni di almeno 4 byte uguali diventano HH*n."""
    out, i = [], 0
    while i < len(dati):
        j = i
        while j < len(dati) and dati[j] == dati[i]:
            j += 1
        n = j - i
        if n >= 4:
            out.append(f"{dati[i]:02X}*{n}")
        else:
            out.extend(f"{dati[i]:02X}" for _ in range(n))
        i = j
    return " ".join(out)


# --- valori ------------------------------------------------------------------------------------------
# Numerici: segno '-' facoltativo, cifre, e se la scala e' > 0 esattamente 'scala' decimali dopo il punto.
# Lo zero non ha segno. Alfanumerici: uno o piu' pezzi separati da uno spazio; ogni pezzo e' una stringa
# JSON (fra doppi apici, con gli escape di JSON) seguita facoltativamente da "*n", che la ripete n volte:
# "A" " "*498 "." e' la stringa di 500 caratteri A, 498 spazi, punto.

_NUM = re.compile(r"^-?[0-9]+(\.[0-9]+)?$")
_PEZZO = re.compile(r'"((?:[^"\\]|\\.)*)"(?:\*([1-9][0-9]*))?(?: |$)')


def _alfa_da_testo(testo):
    out, i = [], 0
    if not testo:
        raise ValueError("valore alfanumerico vuoto")
    while i < len(testo):
        m = _PEZZO.match(testo, i)
        if not m:
            raise ValueError(f"valore alfanumerico non valido dalla posizione {i}: {testo}")
        out.append(json.loads('"' + m.group(1) + '"') * int(m.group(2) or 1))
        i = m.end()
    if testo.endswith(" "):
        raise ValueError(f"valore alfanumerico con spazio finale fuori dagli apici: {testo}")
    return "".join(out)


def _alfa_a_testo(s):
    if s == "":
        return '""'
    pezzi, i = [], 0
    while i < len(s):
        j = i
        while j < len(s) and s[j] == s[i]:
            j += 1
        if j - i >= 4:
            pezzi.append(("rip", s[i], j - i))
            i = j
        else:
            if pezzi and pezzi[-1][0] == "lit":
                pezzi[-1] = ("lit", pezzi[-1][1] + s[i:j], 0)
            else:
                pezzi.append(("lit", s[i:j], 0))
            i = j
    return " ".join(json.dumps(p[1], ensure_ascii=True) + (f"*{p[2]}" if p[0] == "rip" else "") for p in pezzi)


def valore_da_testo(testo, alfanumerico):
    if alfanumerico:
        return _alfa_da_testo(testo)
    if not _NUM.match(testo):
        raise ValueError(f"valore numerico non in forma canonica: '{testo}'")
    try:
        return Decimal(testo)
    except InvalidOperation:
        raise ValueError(f"valore numerico illeggibile: '{testo}'")


def valore_a_testo(valore, scala=None):
    """Forma canonica di un valore (Decimal o str). Per i Decimal 'scala' fissa i decimali."""
    if isinstance(valore, str):
        return _alfa_a_testo(valore)
    if scala is None:
        raise ValueError("scala mancante per un valore numerico")
    q = valore.quantize(Decimal(1).scaleb(-scala)) if scala > 0 else valore.quantize(Decimal(1))
    if q != valore:
        raise ValueError(f"valore {valore} con piu' di {scala} decimali")
    if q == 0:
        q = abs(q)
    return f"{q:f}"


def forma_canonica(testo, scala):
    """Verifica che un valore numerico dei vettori sia gia' in forma canonica per la scala data."""
    v = valore_da_testo(testo, False)
    c = valore_a_testo(v, scala)
    if c != testo:
        raise ValueError(f"valore '{testo}' non canonico per la scala {scala} (atteso '{c}')")
    return v
