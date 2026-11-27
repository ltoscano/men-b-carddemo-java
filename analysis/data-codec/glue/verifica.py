"""Verifica delle regole di codifica (issue #23).

Uso: verifica.py VETTORI OUT DOC OPZIONI [CODEC]
  VETTORI  cartella dei vettori (oracle-gnucobol.tsv, zos-ebcdic.tsv, oracle-oltre-picture.tsv)
  OUT      output rigenerato dell'analisi (censimento*.tsv, pagina*.tsv, sonde/)
  DOC      docs/legacy-map/data-contract/codifica.md
  OPZIONI  oracle/cobc.opts (le opzioni con cui la sonda deve risultare compilata)
  CODEC    facoltativo: file codec.py da usare al posto di quello di questa cartella (prove negative)

Controlli (tutti eseguiti; ogni difetto e' una riga "ERRORE [gruppo] ..."; uscita 1 se ce n'e' almeno uno):
  [vettori]     struttura dei vettori: colonne, forme, lunghezze, attesi presenti, fonti dichiarate e del profilo giusto
  [copertura]   ogni variante del censimento ha vettori in ogni profilo; copertura minima per categoria
  [decodifica]  il codec decodifica ogni vettore con lo stato e il valore attesi (campo dentro un record, con byte
                di guardia prima e dopo); [ricodifica] la ricodifica conservativa restituisce i byte originali;
                [scrittura] il valore decodificato, codificato come valore nuovo, da' i byte attesi;
                [codifica] ogni vettore di codifica da' i byte attesi o l'errore atteso
  [sonda]       le osservazioni della sonda (profilo oracle-gnucobol) coincidono con gli attesi: classe (IS NUMERIC),
                valore con MOVE e con ADD, byte scritti, byte del MOVE nei vettori di codifica; argomenti di
                compilazione e ambiente della sonda; [oltre-picture] le osservazioni dei binari oltre la PICTURE
  [documento]   codifica.md elenca ogni variante del censimento e definisce ogni fonte citata
  [pagina]      nessun byte distintivo fra 037 e 1047 in un campo alfanumerico; conclusione coerente con codifica.md
I messaggi di [decodifica], [sonda] e [oltre-picture] indicano categoria, variante, byte, valore atteso e ottenuto.
"""
import importlib.util
import os
import re
import sys
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comune import (CATEGORIE, COLONNE_VETTORI, STATI_CODIFICA, STATI_DECODIFICA, a_esa, da_esa,  # noqa: E402
                    forma_canonica, leggi_tsv, valore_a_testo, valore_da_testo)

PREFISSI_FONTE = {"oracle-gnucobol": ("GC-",), "zos-ebcdic": ("IBM-", "CP037", "ICU-", "ZOS-")}
# Byte di guardia attorno al campo nel record di prova: una lunghezza sbagliata li include o perde un byte del campo.
GUARDIA = {
    ("oracle-gnucobol", "alfanumerico"): 0x5A, ("zos-ebcdic", "alfanumerico"): 0xE9,
    ("oracle-gnucobol", "display"): 0x37, ("zos-ebcdic", "display"): 0xF7,
    ("oracle-gnucobol", "comp-3"): 0x1C, ("zos-ebcdic", "comp-3"): 0x1C,
    ("oracle-gnucobol", "comp"): 0x01, ("zos-ebcdic", "comp"): 0x01,
}
# Tabella del segno nell'ultima cifra, scritta qui una seconda volta e in modo indipendente dal codec, solo per
# la copertura: oracle (oracle/README.md) '{' 'A'-'I' positivi 0-9, '}' 'J'-'R' negativi 0-9; z/OS zona C/D.
TABELLA_SEGNO = {
    "oracle-gnucobol": [ord(c) for c in "{ABCDEFGHI}JKLMNOPQR"],
    "zos-ebcdic": [0xC0 + d for d in range(10)] + [0xD0 + d for d in range(10)],
}
ERRORI = []


def errore(gruppo, testo):
    ERRORI.append(f"ERRORE [{gruppo}] {testo}")


def carica_codec(percorso):
    spec = importlib.util.spec_from_file_location("codec_in_prova", percorso)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _cat_guardia(cat):
    return "display" if cat.startswith("display") else cat


def chi(p, v, extra=""):
    return f"profilo {p} categoria {v['categoria']} variante {v['variante']}{extra}"


# --- vettori ---------------------------------------------------------------------------------------------------

def carica_vettori(cartella, codec, fonti):
    out = {}
    for p in ("oracle-gnucobol", "zos-ebcdic"):
        path = os.path.join(cartella, f"{p}.tsv")
        if not os.path.isfile(path):
            errore("vettori", f"{p}.tsv assente")
            out[p] = []
            continue
        testa, righe = leggi_tsv(path)
        if tuple(testa) != COLONNE_VETTORI:
            errore("vettori", f"{p}.tsv: colonne {testa}, attese {list(COLONNE_VETTORI)}")
            out[p] = []
            continue
        buone = []
        for v in righe:
            if controlla_riga(p, v, codec, fonti):
                buone.append(v)
        out[p] = buone
    return out


def controlla_riga(p, v, codec, fonti):
    dove = f"{p}.tsv riga {v['_riga']}"
    for c in COLONNE_VETTORI[:-1]:
        if v[c].strip() == "":
            errore("vettori", f"{dove}: vettore senza atteso (colonna {c} vuota)")
            return False
    cat, op = v["categoria"], v["operazione"]
    if cat not in CATEGORIE:
        errore("vettori", f"{dove}: categoria sconosciuta {cat}")
        return False
    try:
        g = codec.geometria(cat, v["variante"])
    except Exception as e:  # noqa: BLE001
        errore("vettori", f"{dove}: variante non valida {v['variante']}: {e}")
        return False
    if not v["fonte"].startswith(PREFISSI_FONTE[p]):
        errore("vettori", f"{dove}: fonte {v['fonte']} non appartiene al profilo {p} (i profili non si deducono l'uno dall'altro)")
    elif v["fonte"] not in fonti:
        errore("vettori", f"{dove}: fonte {v['fonte']} non definita in codifica.md")
    alfa = cat == "alfanumerico"
    try:
        if op == "decodifica":
            b = da_esa(v["ingresso"])
            if len(b) != g.lunghezza:
                errore("vettori", f"{dove}: {len(b)} byte d'ingresso, la variante {v['variante']} ne ha {g.lunghezza}")
                return False
            if v["stato"] not in STATI_DECODIFICA or v["move"] != "-":
                errore("vettori", f"{dove}: stato '{v['stato']}' o move '{v['move']}' non ammessi in decodifica")
                return False
            if v["stato"] == "valido":
                if v["valore"] == "-" or v["byte"] == "-":
                    errore("vettori", f"{dove}: vettore senza atteso (valido senza valore o senza byte di scrittura)")
                    return False
                if alfa:
                    valore_da_testo(v["valore"], True)
                else:
                    forma_canonica(v["valore"], g.decimali)
                if len(da_esa(v["byte"])) != g.lunghezza:
                    errore("vettori", f"{dove}: byte di scrittura di lunghezza diversa dal campo")
                    return False
            elif v["valore"] != "-" or v["byte"] != "-":
                errore("vettori", f"{dove}: stato {v['stato']} con un valore o dei byte attesi (il codec non assegna valori)")
                return False
        elif op == "codifica":
            if v["stato"] not in STATI_CODIFICA or v["valore"] != "-":
                errore("vettori", f"{dove}: stato '{v['stato']}' o valore '{v['valore']}' non ammessi in codifica")
                return False
            valore_da_testo(v["ingresso"], alfa)
            if v["stato"] == "ok":
                if v["byte"] == "-" or v["move"] == "-":
                    errore("vettori", f"{dove}: vettore senza atteso (codifica ok senza byte o senza move)")
                    return False
                if len(da_esa(v["byte"])) != g.lunghezza:
                    errore("vettori", f"{dove}: byte attesi di lunghezza diversa dal campo")
                    return False
            elif v["byte"] != "-":
                errore("vettori", f"{dove}: codifica in errore con byte attesi")
                return False
            if v["move"] != "-" and len(da_esa(v["move"])) != g.lunghezza:
                errore("vettori", f"{dove}: byte del MOVE di lunghezza diversa dal campo")
                return False
        else:
            errore("vettori", f"{dove}: operazione sconosciuta {op}")
            return False
    except ValueError as e:
        errore("vettori", f"{dove}: {e}")
        return False
    return True


# --- copertura -------------------------------------------------------------------------------------------------

def controlla_copertura(vettori, censimento, codec):
    varianti = {(r["categoria"], r["variante"]) for r in censimento}
    for p, righe in vettori.items():
        dec = [v for v in righe if v["operazione"] == "decodifica"]
        presenti = {(v["categoria"], v["variante"]) for v in dec}
        for k in sorted(varianti - presenti):
            errore("copertura", f"profilo {p}: variante del censimento senza vettori: {k[0]} {k[1]}")
        for k in sorted({(v["categoria"], v["variante"]) for v in righe} - varianti):
            errore("copertura", f"profilo {p}: variante dei vettori assente dal censimento: {k[0]} {k[1]}")
        for cat, var in sorted(varianti):
            rv = [v for v in dec if (v["categoria"], v["variante"]) == (cat, var)]
            g = codec.geometria(cat, var)
            {"display-con-segno": _cop_segno, "display-senza-segno": _cop_senza_segno, "comp-3": _cop_packed,
             "comp": _cop_binario, "alfanumerico": lambda *a: None}[cat](p, cat, var, g, rv)
        for cat in CATEGORIE:
            if not any(v["categoria"] == cat and v["operazione"] == "codifica" and v["stato"] == "ok" for v in righe):
                errore("copertura", f"profilo {p} categoria {cat}: nessun vettore di codifica di un valore nuovo")
            if cat != "alfanumerico" and not any(v["categoria"] == cat and v["operazione"] == "codifica"
                                                 and v["stato"] == "errore" for v in righe):
                errore("copertura", f"profilo {p} categoria {cat}: nessun vettore di codifica rifiutata")
        _cop_alfa(p, righe)


def _byte(v):
    return da_esa(v["ingresso"])


def _cifra(p, x):
    return 0x30 <= x <= 0x39 if p == "oracle-gnucobol" else 0xF0 <= x <= 0xF9


def _cop_segno(p, cat, var, g, rv):
    corpo_ok = [v for v in rv if all(_cifra(p, x) for x in _byte(v)[:-1])]
    for s in TABELLA_SEGNO[p]:
        if not any(_byte(v)[-1] == s and v["stato"] == "valido" for v in corpo_ok):
            errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca la riga {s:02X} della tabella del segno")
    alternativa = [v for v in corpo_ok if v["stato"] == "valido" and _cifra(p, _byte(v)[-1])]
    if not alternativa:
        errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca la rappresentazione alternativa (cifra senza segno)")
    fuori = [v for v in corpo_ok if v["stato"] == "non-valido" and _byte(v)[-1] not in TABELLA_SEGNO[p]
             and not _cifra(p, _byte(v)[-1])]
    if not fuori:
        errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca un byte fuori tabella")
    zero_neg = TABELLA_SEGNO[p][10]
    zero = 0x30 if p == "oracle-gnucobol" else 0xF0
    if not any(_byte(v)[-1] == zero_neg and set(_byte(v)[:-1]) == {zero} and v["stato"] == "valido" for v in rv):
        errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca lo zero negativo")


def _cop_senza_segno(p, cat, var, g, rv):
    spazio = 0x20 if p == "oracle-gnucobol" else 0x40
    if not any(v["stato"] == "valido" for v in rv):
        errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca un vettore di cifre valide")
    if not any(v["stato"] == "non-valido" and set(_byte(v)) == {spazio} for v in rv):
        errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca il campo di spazi")
    if not any(v["stato"] == "non-valido" and set(_byte(v)) != {spazio} and any(not _cifra(p, x) and x != spazio for x in _byte(v))
               for v in rv):
        errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca un carattere non numerico")


def _cop_packed(p, cat, var, g, rv):
    accettati, rifiutati = ([0xC, 0xD, 0xF], [0xA, 0xB, 0xE]) if g.segno else ([0xF], [0xC, 0xD])
    cifre_ok = lambda b: all((x >> 4) <= 9 and (x & 0xF) <= 9 for x in b[:-1]) and (b[-1] >> 4) <= 9  # noqa: E731
    for s in accettati:
        if not any(v["stato"] == "valido" and (_byte(v)[-1] & 0xF) == s and cifre_ok(_byte(v)) for v in rv):
            errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca il codice di segno accettato {s:X}")
    for s in rifiutati:
        if not any(v["stato"] == "non-valido" and (_byte(v)[-1] & 0xF) == s and cifre_ok(_byte(v)) for v in rv):
            errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca il codice di segno non ammesso {s:X}")
    if not any(v["stato"] == "non-valido" and (_byte(v)[-1] & 0xF) in accettati and not cifre_ok(_byte(v)) for v in rv):
        errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca un semiottetto di cifra non valido")


def _cop_binario(p, cat, var, g, rv):
    mx = 10 ** (g.intere + g.decimali) - 1
    bits = g.lunghezza * 8
    richiesti = {"zero": 0, "estremo della PICTURE": mx,
                 "estremo fisico": (2 ** (bits - 1) - 1) if g.segno else (2 ** bits - 1)}
    if g.segno:
        richiesti.update({"estremo negativo della PICTURE": -mx, "estremo fisico negativo": -(2 ** (bits - 1))})
    presenti = {int.from_bytes(_byte(v), "big", signed=g.segno) for v in rv}
    for nome, n in richiesti.items():
        if n not in presenti:
            errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca {nome} ({n})")
    if not any(v["stato"] == "oltre-picture" for v in rv):
        errore("copertura", f"profilo {p} categoria {cat} variante {var}: manca un valore oltre la PICTURE")


def _cop_alfa(p, righe):
    alfa = [v for v in righe if v["categoria"] == "alfanumerico"]
    spazio = 0x20 if p == "oracle-gnucobol" else 0x40
    if not any(v["operazione"] == "codifica" and v["stato"] == "ok"
               and len(valore_da_testo(v["ingresso"], True)) < int(v["variante"][2:-1]) for v in alfa):
        errore("copertura", f"profilo {p} categoria alfanumerico: manca il riempimento a destra")
    if not any(v["operazione"] == "decodifica" and spazio not in _byte(v) and len(_byte(v)) > 1 for v in alfa):
        errore("copertura", f"profilo {p} categoria alfanumerico: manca il campo pieno")
    if not any(v["operazione"] == "codifica" and v["stato"] == "errore" for v in alfa):
        errore("copertura", f"profilo {p} categoria alfanumerico: manca il carattere o il testo non rappresentabile")
    if p == "zos-ebcdic":
        for x in (0x5F, 0xAD, 0xB0, 0xBA, 0xBB, 0xBD):
            if not any(v["operazione"] == "decodifica" and x in _byte(v) for v in alfa):
                errore("copertura", f"profilo {p} categoria alfanumerico: manca il byte {x:02X} che distingue 037 da 1047")


# --- codec contro i vettori ----------------------------------------------------------------------------------------

def _testo(valore, g):
    if valore is None:
        return "-"
    return valore_a_testo(valore, g.decimali if not isinstance(valore, str) else None)


def controlla_codec(codec, vettori):
    n = 0
    for p, righe in vettori.items():
        for v in righe:
            cat, var = v["categoria"], v["variante"]
            g = codec.geometria(cat, var)
            alfa = cat == "alfanumerico"
            n += 1
            if v["operazione"] == "decodifica":
                b = da_esa(v["ingresso"])
                gu = bytes([GUARDIA[(p, _cat_guardia(cat))]]) * 8
                id_ = chi(p, v, f" byte {v['ingresso']}")
                try:
                    r = codec.decodifica(p, cat, var, gu + b + gu, 8)
                except Exception as e:  # noqa: BLE001
                    errore("decodifica", f"{id_}: eccezione {type(e).__name__}: {e}")
                    continue
                if r.stato != v["stato"]:
                    errore("decodifica", f"{id_}: stato atteso {v['stato']}, ottenuto {r.stato}")
                atteso = None if v["valore"] == "-" else valore_da_testo(v["valore"], alfa)
                try:
                    ottenuto_t = _testo(r.valore, g)
                except Exception as e:  # noqa: BLE001
                    ottenuto_t = f"{r.valore!r} ({e})"
                if (atteso is None) != (r.valore is None) or (atteso is not None and atteso != r.valore):
                    errore("decodifica", f"{id_}: valore atteso {v['valore']}, ottenuto {ottenuto_t}")
                rc = codec.ricodifica(r)
                if bytes(rc) != b:
                    errore("ricodifica", f"{id_}: byte attesi {v['ingresso']}, ottenuti {a_esa(bytes(rc))}")
                if atteso is not None:
                    try:
                        w = codec.codifica(p, cat, var, atteso)
                        wt = a_esa(w)
                    except codec.CodificaErrore as e:
                        wt = f"errore ({e})"
                    except Exception as e:  # noqa: BLE001
                        wt = f"eccezione {type(e).__name__}: {e}"
                    if v["byte"] == "-" and not wt.startswith("errore") or v["byte"] != "-" and wt != a_esa(da_esa(v["byte"])):
                        errore("scrittura", f"{id_} valore {v['valore']}: byte attesi {v['byte']}, ottenuti {wt}")
            else:
                valore = valore_da_testo(v["ingresso"], alfa)
                id_ = chi(p, v, f" valore {v['ingresso']}")
                try:
                    w = codec.codifica(p, cat, var, valore)
                    wt = a_esa(w)
                except codec.CodificaErrore as e:
                    wt = f"errore ({e})"
                except Exception as e:  # noqa: BLE001
                    wt = f"eccezione {type(e).__name__}: {e}"
                atteso = "errore" if v["stato"] == "errore" else a_esa(da_esa(v["byte"]))
                if (atteso == "errore") != wt.startswith("errore") or (atteso != "errore" and wt != atteso):
                    errore("codifica", f"{id_}: atteso {atteso}, ottenuto {wt}")
    return n


# --- sonda -----------------------------------------------------------------------------------------------------------

def _numero_sonda(t):
    if not re.match(r"^[+-][0-9]{26}$", t):
        return None
    return Decimal(t).scaleb(-6)


def _uguali_num(osservato, atteso):
    n = _numero_sonda(osservato)
    return n is not None and n == atteso


def _mostra(t):
    n = _numero_sonda(t)
    return t if n is None else f"{n.normalize():f}" if n != 0 else "0"


def controlla_sonda(vettori, oltre_path, out_sonde, opzioni):
    oss_path = os.path.join(out_sonde, "osservazioni.tsv")
    if not os.path.isfile(oss_path):
        errore("sonda", "osservazioni della sonda assenti")
        return 0
    _, oss = leggi_tsv(oss_path)
    per_riga = {}
    for o in oss:
        k = int(o["riga"])
        if k in per_riga:
            errore("sonda", f"due osservazioni per la riga {k} dei vettori")
        per_riga[k] = o
    _, oltre = leggi_tsv(oltre_path)
    oltre_k = {}
    for t in oltre:
        k = (t["variante"], a_esa(da_esa(t["ingresso"])))
        if k in oltre_k:
            errore("oltre-picture", f"riga {t['_riga']}: caso duplicato {k}")
        oltre_k[k] = t
    usati_oltre, usate = set(), set()
    n = 0
    for v in vettori["oracle-gnucobol"]:
        cat, var, op = v["categoria"], v["variante"], v["operazione"]
        if op == "codifica" and v["move"] == "-":
            continue
        o = per_riga.get(v["_riga"])
        id_ = chi("oracle-gnucobol", v, f" {'byte' if op == 'decodifica' else 'valore'} {v['ingresso']}")
        if o is None:
            errore("sonda", f"{id_}: nessuna osservazione della sonda (riga {v['_riga']} dei vettori)")
            continue
        usate.add(v["_riga"])
        n += 1
        if o["variante"] != f"{cat}:{var}" or o["operazione"] != op:
            errore("sonda", f"{id_}: l'osservazione della riga {v['_riga']} e' di {o['operazione']} {o['variante']}")
            continue
        if op == "codifica":
            if a_esa(da_esa(o["scritto"])) != a_esa(da_esa(v["move"])):
                errore("sonda", f"{id_}: byte del MOVE attesi {v['move']}, osservati {o['scritto']}")
            continue
        if cat in ("display-senza-segno", "display-con-segno", "comp-3"):
            attesa = "S" if v["stato"] == "valido" else "N"
            if o["classe"] != attesa:
                nomi = {"S": "valido", "N": "non-valido"}
                errore("sonda", f"{id_}: IS NUMERIC atteso {nomi[attesa]}, osservato {nomi.get(o['classe'], o['classe'])}")
        if v["stato"] == "valido":
            if cat == "alfanumerico":
                vm = da_esa(o["valore_move"]).decode("latin-1") if o["valore_move"] != "-" else None
                if vm != valore_da_testo(v["valore"], True):
                    errore("sonda", f"{id_}: valore atteso {v['valore']}, osservato {o['valore_move']}")
            else:
                atteso = Decimal(v["valore"])
                for col, nome in (("valore_move", "MOVE"), ("valore_add", "ADD")):
                    if not _uguali_num(o[col], atteso):
                        errore("sonda", f"{id_}: valore con {nome} atteso {v['valore']}, osservato {_mostra(o[col])}")
            if a_esa(da_esa(o["scritto"])) != a_esa(da_esa(v["byte"])):
                errore("sonda", f"{id_}: byte scritti attesi {v['byte']}, osservati {o['scritto']}")
        elif v["stato"] == "oltre-picture":
            k = (var, a_esa(da_esa(v["ingresso"])))
            t = oltre_k.get(k)
            if t is None:
                errore("oltre-picture", f"{id_}: caso oltre la PICTURE senza osservazione dichiarata in oracle-oltre-picture.tsv")
                continue
            usati_oltre.add(k)
            g_dec = len(t["move"].split(".")[1]) if "." in t["move"] else 0
            for col, nome in (("move", "MOVE"), ("add", "ADD")):
                atteso = forma_canonica(t[col], g_dec)
                if not _uguali_num(o["valore_" + col], atteso):
                    errore("oltre-picture", f"{id_}: valore con {nome} atteso {t[col]}, osservato {_mostra(o['valore_' + col])}")
            if a_esa(da_esa(o["scritto"])) != a_esa(da_esa(t["riscrittura"])):
                errore("oltre-picture", f"{id_}: riscrittura attesa {t['riscrittura']}, osservata {o['scritto']}")
    for k in sorted(set(oltre_k) - usati_oltre):
        errore("oltre-picture", f"osservazione dichiarata senza un vettore oltre-picture corrispondente: {k}")
    for k in sorted(set(per_riga) - usate):
        errore("sonda", f"osservazione della riga {k} senza un vettore corrispondente")
    _controlla_compilazione(out_sonde, opzioni)
    return n


def _controlla_compilazione(out_sonde, opzioni):
    opts = []
    with open(opzioni, encoding="utf-8") as f:
        for riga in f:
            riga = riga.split("#", 1)[0].strip()
            if riga:
                opts.append(riga)
    attese = [opts + ["-c", "-o", "/w/build/obj/CODECPRB.o", "/sonde/CODECPRB.cbl"],
              ["-x", "-A", "-DMENB_ENTRY=CODECPRB", "-o", "/w/build/bin/CODECPRB", "/oracle/launcher/avvia.c",
               "/w/build/obj/CODECPRB.o"]]
    inv, cur = [], None
    path = os.path.join(out_sonde, "compilazione.log")
    if not os.path.isfile(path):
        errore("sonda", "log di compilazione della sonda assente")
        return
    with open(path, encoding="latin-1") as f:
        for riga in f.read().split("\n"):
            if riga == "== cobc":
                cur = []
                inv.append(cur)
            elif riga.startswith("arg ") and cur is not None:
                cur.append(riga[4:])
    if inv != attese:
        errore("sonda", f"argomenti di compilazione della sonda {inv}, attesi {attese} (opzioni di oracle/cobc.opts)")
    amb = os.path.join(out_sonde, "ambiente.txt")
    atteso = ["PATH=/usr/bin:/bin", "HOME=/tmp", "LC_ALL=C", "COB_LIBRARY_PATH=/oracle-bin", "DD_CODECIN=/w/ingresso.dat"]
    with open(amb, encoding="latin-1") as f:
        visto = [r for r in f.read().split("\n") if r]
    if visto != atteso:
        errore("sonda", f"ambiente della sonda {visto}, atteso {atteso}")


# --- documento e pagina ------------------------------------------------------------------------------------------------

def fonti_documento(doc):
    with open(doc, encoding="utf-8") as f:
        testo = f.read()
    return testo, set(re.findall(r"^\| `([A-Z0-9][A-Z0-9-]+)` \|", testo, re.M))


def controlla_documento(testo, censimento):
    for r in censimento:
        if f"| {r['categoria']} | `{r['variante']}` |" not in testo:
            errore("documento", f"codifica.md: manca la variante {r['categoria']} {r['variante']} nella tabella delle varianti")


def controlla_pagina(out, testo):
    _, occ = leggi_tsv(os.path.join(out, "pagina.tsv")) if os.path.getsize(os.path.join(out, "pagina.tsv")) > 0 else ([], [])
    for o in occ:
        if o["categoria"] == "alfanumerico":
            errore("pagina", f"{o['file']} record {o['record']} posizione {o['posizione']}: byte distintivo {o['byte']} "
                             f"nel campo alfanumerico {o['campo']}: la pagina va scelta sui dati")
    _, esiti = leggi_tsv(os.path.join(out, "pagina-esito.tsv"))
    concl = [e for e in esiti if e["file"] == "CONCLUSIONE"]
    if len(concl) != 1:
        errore("pagina", "pagina-esito.tsv senza conclusione")
        return
    c = concl[0]["in_alfanumerici"]
    if c != "037-convenzione":
        errore("pagina", f"conclusione {c}: il profilo zos-ebcdic adotta 037 come convenzione, va rivisto")
    if "Conclusione: `037-convenzione`" not in testo:
        errore("pagina", "codifica.md non dichiara la conclusione 037-convenzione")


def main(argv):
    if len(argv) not in (5, 6):
        raise SystemExit("uso: verifica.py VETTORI OUT DOC OPZIONI [CODEC]")
    vett, out, doc, opzioni = argv[1:5]
    codec = carica_codec(argv[5] if len(argv) == 6 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "codec.py"))
    _, censimento = leggi_tsv(os.path.join(out, "censimento.tsv"))
    testo, fonti = fonti_documento(doc)
    vettori = carica_vettori(vett, codec, fonti)
    controlla_copertura(vettori, censimento, codec)
    n_codec = controlla_codec(codec, vettori)
    n_sonda = controlla_sonda(vettori, os.path.join(vett, "oracle-oltre-picture.tsv"), os.path.join(out, "sonde"), opzioni)
    controlla_documento(testo, censimento)
    controlla_pagina(out, testo)
    if ERRORI:
        print("\n".join(ERRORI))
        print(f"verifica fallita: {len(ERRORI)} errori")
        return 1
    print(f"verifica riuscita: {len(censimento)} varianti coperte; {n_codec} vettori sul codec "
          f"({len(vettori['oracle-gnucobol'])} oracle-gnucobol, {len(vettori['zos-ebcdic'])} zos-ebcdic); "
          f"{n_sonda} osservazioni della sonda coincidono con gli attesi; pagina 037 per convenzione")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
