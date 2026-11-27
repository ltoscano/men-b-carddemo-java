"""Regole di codifica dei campi di CardDemo, in due profili (issue #23).

Questo modulo e' la "colla" che le regole descrivono (docs/legacy-map/data-contract/codifica.md): byte di un
campo -> valore e valore -> byte, per ogni categoria del censimento. Si verifica contro i vettori scritti a
mano (vettori/*.tsv); il profilo oracle-gnucobol si verifica anche contro le sonde COBOL eseguite
nell'ambiente dell'oracle.

Tre operazioni distinte:
  decodifica(profilo, categoria, variante, record, offset) -> Risultato(stato, valore, originali)
      stato: valido | non-valido | oltre-picture. Il valore e' None se il campo non e' valido; i byte
      originali sono sempre conservati. Nessun valore inventato, nessuna normalizzazione in lettura, nessun
      record scartato. Prima di ogni conversione si verifica che il campo stia tutto nel record: offset
      negativo, oltre la fine o campo troncato -> CampoIncompleto (nessuno stato, nessun valore).
  ricodifica(risultato) -> bytes
      ricodifica conservativa: restituisce i byte originali, tali e quali (uno zero negativo resta tale,
      una rappresentazione alternativa ammessa resta com'e').
  codifica(profilo, categoria, variante, valore) -> bytes
      codifica di un valore nuovo nella rappresentazione prescritta dal profilo; CodificaErrore se il
      valore non e' rappresentabile (oltre la PICTURE, decimali oltre la scala, negativo in un campo senza
      segno, testo piu' lungo del campo, carattere non rappresentabile). Nessun troncamento silenzioso.
I due profili non si deducono l'uno dall'altro: ogni tabella qui sotto ha la sua fonte (codifica.md).
"""
import re
from collections import namedtuple
from decimal import Decimal

PROFILI = ("oracle-gnucobol", "zos-ebcdic")

Geometria = namedtuple("Geometria", "categoria variante segno intere decimali lunghezza")
Risultato = namedtuple("Risultato", "stato valore originali")


class CodificaErrore(ValueError):
    pass


class CampoIncompleto(CodificaErrore):
    """Il campo non sta tutto nel record (offset fuori intervallo o byte mancanti): nessuna conversione."""


# --- geometria: dalla variante (PICTURE normalizzata) a lunghezza, scala, segno -----------------------------

_VAR_X = re.compile(r"^X\(([1-9][0-9]*)\)$")
_VAR_9 = re.compile(r"^(S?)9\(([1-9][0-9]*)\)(?:V9\(([1-9][0-9]*)\))?$")


def _lunghezza_binario(cifre):
    # IBM: 1-4 cifre 2 byte, 5-9 cifre 4 byte, 10-18 cifre 8 byte (GnuCOBOL: binary-size 2-4-8 di -std=ibm)
    if 1 <= cifre <= 4:
        return 2
    if 5 <= cifre <= 9:
        return 4
    if 10 <= cifre <= 18:
        return 8
    raise CodificaErrore(f"binario con {cifre} cifre: nessuna regola")


def geometria(categoria, variante):
    if categoria == "alfanumerico":
        m = _VAR_X.match(variante)
        if not m:
            raise CodificaErrore(f"variante alfanumerica non valida: {variante}")
        n = int(m.group(1))
        return Geometria(categoria, variante, False, 0, 0, n)
    m = _VAR_9.match(variante)
    if not m:
        raise CodificaErrore(f"variante numerica non valida: {variante}")
    segno = m.group(1) == "S"
    intere = int(m.group(2))
    decimali = int(m.group(3) or 0)
    cifre = intere + decimali
    if categoria in ("display-senza-segno", "display-con-segno"):
        if segno != (categoria == "display-con-segno"):
            raise CodificaErrore(f"variante {variante} incoerente con la categoria {categoria}")
        lunghezza = cifre
    elif categoria == "comp-3":
        lunghezza = cifre // 2 + 1
    elif categoria == "comp":
        lunghezza = _lunghezza_binario(cifre)
    else:
        raise CodificaErrore(f"categoria senza regola: {categoria}")
    return Geometria(categoria, variante, segno, intere, decimali, lunghezza)


def _valore(intero, g):
    return Decimal(intero).scaleb(-g.decimali)


def _intero(valore, g):
    """Valore nuovo -> intero scalato; CodificaErrore se non rappresentabile nella PICTURE."""
    if not isinstance(valore, Decimal):
        raise CodificaErrore(f"valore numerico atteso, ricevuto {valore!r}")
    scalato = valore.scaleb(g.decimali)
    if scalato != scalato.to_integral_value():
        raise CodificaErrore(f"{valore}: decimali oltre la scala {g.decimali}")
    n = int(scalato)
    if n < 0 and not g.segno:
        raise CodificaErrore(f"{valore}: negativo in un campo senza segno")
    if abs(n) >= 10 ** (g.intere + g.decimali):
        raise CodificaErrore(f"{valore}: oltre la PICTURE {g.variante}")
    return n


# --- alfanumerico ---------------------------------------------------------------------------------------------
# oracle-gnucobol: i byte sono i caratteri, uno a uno (ISO-8859-1, identita' sui byte); riempimento X'20'.
# zos-ebcdic: pagina di codici 037; riempimento X'40'. Carattere non rappresentabile: errore esplicito.

_ALFA = {"oracle-gnucobol": ("latin-1", 0x20), "zos-ebcdic": ("cp037", 0x40)}


def _dec_alfa(profilo, b):
    pagina, _ = _ALFA[profilo]
    return Risultato("valido", b.decode(pagina), b)


def _cod_alfa(profilo, g, valore):
    if not isinstance(valore, str):
        raise CodificaErrore(f"valore alfanumerico atteso, ricevuto {valore!r}")
    pagina, spazio = _ALFA[profilo]
    try:
        b = valore.encode(pagina, errors="strict")
    except UnicodeEncodeError as e:
        raise CodificaErrore(f"carattere non rappresentabile in {pagina}: {valore[e.start]!r}")
    if len(b) > g.lunghezza:
        raise CodificaErrore(f"testo di {len(b)} byte in un campo di {g.lunghezza}")
    return b + bytes([spazio]) * (g.lunghezza - len(b))


# --- DISPLAY (zoned), oracle-gnucobol ---------------------------------------------------------------------------
# Cifre ASCII '0'-'9'. Segno nell'ultimo byte con la convenzione EBCDIC (-fsign=EBCDIC, oracle/README.md):
# byte -> (cifra, segno). In lettura e' ammessa anche una cifra semplice, positiva (cob_check_numdisp).

SEGNO_ORACLE = {
    0x7B: (0, 1),   # {
    0x41: (1, 1),   # A
    0x42: (2, 1),   # B
    0x43: (3, 1),   # C
    0x44: (4, 1),   # D
    0x45: (5, 1),   # E
    0x46: (6, 1),   # F
    0x47: (7, 1),   # G
    0x48: (8, 1),   # H
    0x49: (9, 1),   # I
    0x7D: (0, -1),  # }
    0x4A: (1, -1),  # J
    0x4B: (2, -1),  # K
    0x4C: (3, -1),  # L
    0x4D: (4, -1),  # M
    0x4E: (5, -1),  # N
    0x4F: (6, -1),  # O
    0x50: (7, -1),  # P
    0x51: (8, -1),  # Q
    0x52: (9, -1),  # R
}
SCRIVI_SEGNO_ORACLE = {v: k for k, v in SEGNO_ORACLE.items()}


def _cifra_ascii(x):
    return x - 0x30 if 0x30 <= x <= 0x39 else None


def _dec_display_oracle(g, b):
    cifre = []
    corpo, ultimo = (b[:-1], b[-1]) if g.segno else (b, None)
    for x in corpo:
        c = _cifra_ascii(x)
        if c is None:
            return Risultato("non-valido", None, b)
        cifre.append(c)
    segno = 1
    if g.segno:
        c = _cifra_ascii(ultimo)
        if c is None:
            if ultimo not in SEGNO_ORACLE:
                return Risultato("non-valido", None, b)
            c, segno = SEGNO_ORACLE[ultimo]
        cifre.append(c)
    n = int("".join(str(c) for c in cifre))
    return Risultato("valido", _valore(segno * n, g), b)


def _cod_display_oracle(g, valore):
    n = _intero(valore, g)
    testo = str(abs(n)).rjust(g.lunghezza, "0")
    b = bytearray(testo.encode("ascii"))
    if g.segno:
        segno = -1 if n < 0 else 1
        b[-1] = SCRIVI_SEGNO_ORACLE[(b[-1] - 0x30, segno)]
    return bytes(b)


# --- DISPLAY (zoned), zos-ebcdic --------------------------------------------------------------------------------
# Ogni byte: zona (semiottetto alto) e cifra (semiottetto basso). Cifre con zona F. Ultimo byte di un campo con
# segno: zona C positivo, D negativo, F ammessa (NUMPROC(NOPFD), NUMCLS(PRIM)); in scrittura C/D (zero: C).

ZONE_SEGNO_ZOS = {0xC: 1, 0xD: -1, 0xF: 1}
ZONA_SCRITTA_ZOS = {1: 0xC, -1: 0xD}


def _dec_display_zos(g, b):
    cifre = []
    corpo, ultimo = (b[:-1], b[-1]) if g.segno else (b, None)
    for x in corpo:
        if x >> 4 != 0xF or (x & 0xF) > 9:
            return Risultato("non-valido", None, b)
        cifre.append(x & 0xF)
    segno = 1
    if g.segno:
        zona, c = ultimo >> 4, ultimo & 0xF
        if zona not in ZONE_SEGNO_ZOS or c > 9:
            return Risultato("non-valido", None, b)
        segno = ZONE_SEGNO_ZOS[zona]
        cifre.append(c)
    n = int("".join(str(c) for c in cifre))
    return Risultato("valido", _valore(segno * n, g), b)


def _cod_display_zos(g, valore):
    n = _intero(valore, g)
    testo = str(abs(n)).rjust(g.lunghezza, "0")
    b = bytearray(0xF0 | int(c) for c in testo)
    if g.segno:
        segno = -1 if n < 0 else 1
        b[-1] = (ZONA_SCRITTA_ZOS[segno] << 4) | (b[-1] & 0xF)
    return bytes(b)


# --- COMP-3 (packed decimal) -----------------------------------------------------------------------------------
# Due cifre per byte, ultimo semiottetto = segno. Con un numero pari di cifre il primo semiottetto e' di
# riempimento. Codici del segno accettati in lettura, per profilo e per campo con/senza segno; in scrittura
# C positivo e zero, D negativo, F senza segno; riempimento 0.

SEGNI_PACKED = {
    # profilo: (codici accettati con segno -> segno, codici accettati senza segno -> segno)
    "oracle-gnucobol": ({0xC: 1, 0xD: -1, 0xF: 1}, {0xF: 1}),
    "zos-ebcdic": ({0xC: 1, 0xD: -1, 0xF: 1}, {0xF: 1}),
}
SEGNO_SCRITTO_PACKED = {1: 0xC, -1: 0xD, 0: 0xF}


def _semiottetti(b):
    out = []
    for x in b:
        out.append(x >> 4)
        out.append(x & 0xF)
    return out


def _dec_packed(profilo, g, b):
    s = _semiottetti(b)
    cifre, codice = s[:-1], s[-1]
    cifre_pic = g.intere + g.decimali
    riempimento = cifre[: len(cifre) - cifre_pic]
    cifre = cifre[len(cifre) - cifre_pic:]
    if any(c > 9 for c in cifre) or any(c > 9 for c in riempimento):
        return Risultato("non-valido", None, b)
    accettati = SEGNI_PACKED[profilo][0 if g.segno else 1]
    if codice not in accettati:
        return Risultato("non-valido", None, b)
    if any(c != 0 for c in riempimento):
        # GnuCOBOL: cifra valida, ignorata nel valore (cob_decimal_set_packed salta il primo semiottetto).
        # z/OS: i quattro bit iniziali di un packed a precisione pari devono essere 0 (APAR PI96135): non valido.
        if profilo == "zos-ebcdic":
            return Risultato("non-valido", None, b)
    n = int("".join(str(c) for c in cifre))
    return Risultato("valido", _valore(accettati[codice] * n, g), b)


def _cod_packed(g, valore):
    n = _intero(valore, g)
    cifre = [int(c) for c in str(abs(n)).rjust(g.lunghezza * 2 - 1, "0")]
    codice = SEGNO_SCRITTO_PACKED[(-1 if n < 0 else 1) if g.segno else 0]
    s = cifre + [codice]
    return bytes((s[i] << 4) | s[i + 1] for i in range(0, len(s), 2))


# --- COMP (binario) -----------------------------------------------------------------------------------------------
# Big-endian, 2/4/8 byte; con segno: complemento a due. Un valore fisicamente rappresentabile ma oltre la
# PICTURE e' "oltre-picture" e non riceve un valore in nessuno dei due profili (voce 63 del registro):
# GnuCOBOL gli attribuisce valori diversi secondo l'operazione (vettori/oracle-oltre-picture.tsv), z/OS non
# lo determina (TRUNC(STD) regola i campi riceventi).

ORDINE_BINARIO = "big"


def _dec_binario(profilo, g, b):
    n = int.from_bytes(b, ORDINE_BINARIO, signed=g.segno)
    if abs(n) >= 10 ** (g.intere + g.decimali):
        return Risultato("oltre-picture", None, b)
    return Risultato("valido", _valore(n, g), b)


def _cod_binario(g, valore):
    n = _intero(valore, g)
    return n.to_bytes(g.lunghezza, ORDINE_BINARIO, signed=g.segno)


# --- interfaccia ---------------------------------------------------------------------------------------------------

def _profilo(p):
    if p not in PROFILI:
        raise CodificaErrore(f"profilo sconosciuto: {p}")
    return p


def decodifica(profilo, categoria, variante, record, offset=0):
    _profilo(profilo)
    g = geometria(categoria, variante)
    if not isinstance(offset, int) or isinstance(offset, bool) or offset < 0:
        raise CampoIncompleto(f"offset {offset!r} fuori intervallo")
    if offset + g.lunghezza > len(record):
        raise CampoIncompleto(f"campo {categoria} {variante} di {g.lunghezza} byte all'offset {offset}: "
                              f"il record ne ha {len(record)}")
    b = bytes(record[offset:offset + g.lunghezza])
    if categoria == "alfanumerico":
        r = _dec_alfa(profilo, b)
    elif categoria in ("display-senza-segno", "display-con-segno"):
        r = _dec_display_oracle(g, b) if profilo == "oracle-gnucobol" else _dec_display_zos(g, b)
    elif categoria == "comp-3":
        r = _dec_packed(profilo, g, b)
    elif categoria == "comp":
        r = _dec_binario(profilo, g, b)
    else:
        raise CodificaErrore(f"categoria senza regola: {categoria}")
    return r


def ricodifica(risultato):
    return risultato.originali


def codifica(profilo, categoria, variante, valore):
    _profilo(profilo)
    g = geometria(categoria, variante)
    if categoria == "alfanumerico":
        return _cod_alfa(profilo, g, valore)
    if categoria in ("display-senza-segno", "display-con-segno"):
        return _cod_display_oracle(g, valore) if profilo == "oracle-gnucobol" else _cod_display_zos(g, valore)
    if categoria == "comp-3":
        return _cod_packed(g, valore)
    if categoria == "comp":
        return _cod_binario(g, valore)
    raise CodificaErrore(f"categoria senza regola: {categoria}")
