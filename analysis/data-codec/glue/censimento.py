"""Censimento delle rappresentazioni dei campi (issue #23), ricavato dai contratti di #3.

Uso: censimento.py CARTELLA_CONTRATTI OUT
  CARTELLA_CONTRATTI  docs/legacy-map/data-contract/contratti/ (un TSV per contratto)
  OUT                 riceve censimento.tsv (una riga per variante) e censimento-categorie.tsv

Un campo elementare e' una riga 'elementare' di un contratto (gli OCCURS sono gia' espansi da #3, una riga
per elemento: si contano come i contratti li contano). La categoria dipende da USAGE e PICTURE; la variante
e' la PICTURE normalizzata (X(n), 9(i), S9(i)V9(d)), cioe' cio' da cui la regola ricava lunghezza, scala,
segno e limiti. Una combinazione che non ha categoria fa fallire il censimento: nessuna rappresentazione
resta senza regola.
Controllo incrociato: la lunghezza che la regola (codec.geometria) ricava dalla variante deve coincidere
con la lunghezza del contratto, campo per campo.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comune import CATEGORIE, leggi_tsv, scrivi_tsv  # noqa: E402
import codec  # noqa: E402

PIC_X = re.compile(r"^X\((\d+)\)$")
PIC_9 = re.compile(r"^(S?)9\((\d+)\)(?:V(9+|9\((\d+)\)))?$")


def classifica(campo):
    """(categoria, variante, segno, intere, decimali) di una riga elementare; SystemExit se senza regola."""
    pic, usage, segno = campo["pic"], campo["usage"], campo["segno"]
    m = PIC_X.match(pic)
    if m and usage == "DISPLAY" and segno == "-":
        n = int(m.group(1))
        return "alfanumerico", f"X({n})", "-", "-", "-"
    m = PIC_9.match(pic)
    if m:
        s = m.group(1) == "S"
        intere = int(m.group(2))
        if m.group(3) is None:
            dec = 0
        elif m.group(4) is not None:
            dec = int(m.group(4))
        else:
            dec = len(m.group(3))
        # coerenza con le colonne del contratto (che vengono da cb2xml)
        if (segno == "S") != s or str(intere) != campo["cifre_intere"] or str(dec) != campo["cifre_decimali"]:
            raise SystemExit(f"ERRORE [censimento] {campo['_contratto']} {campo['campo']}: PIC {pic} incoerente con "
                             f"segno/cifre del contratto ({segno}, {campo['cifre_intere']}, {campo['cifre_decimali']})")
        var = ("S" if s else "") + f"9({intere})" + (f"V9({dec})" if dec else "")
        cat = {"DISPLAY": "display-con-segno" if s else "display-senza-segno", "COMP-3": "comp-3", "COMP": "comp"}.get(usage)
        if cat is not None:
            return cat, var, "S" if s else "-", str(intere), str(dec)
    raise SystemExit(f"ERRORE [censimento] {campo['_contratto']} {campo['campo']}: rappresentazione senza regola "
                     f"(PIC {pic}, USAGE {usage}, segno {segno})")


def main(cartella, out):
    varianti = {}
    for nome in sorted(os.listdir(cartella)):
        if not nome.endswith(".tsv"):
            continue
        contratto = nome[:-4]
        _, righe = leggi_tsv(os.path.join(cartella, nome))
        for r in righe:
            if r["tipo"] != "elementare":
                continue
            r["_contratto"] = contratto
            cat, var, segno, intere, dec = classifica(r)
            g = codec.geometria(cat, var)
            if g.lunghezza != int(r["lunghezza"]):
                raise SystemExit(f"ERRORE [censimento] {contratto} {r['campo']}: la regola di {cat} {var} da' "
                                 f"{g.lunghezza} byte, il contratto {r['lunghezza']}")
            k = (cat, var)
            v = varianti.setdefault(k, {"categoria": cat, "variante": var, "usage": r["usage"], "segno": segno,
                                        "cifre_intere": intere, "cifre_decimali": dec, "lunghezza": g.lunghezza,
                                        "campi": 0, "contratti": set()})
            v["campi"] += 1
            v["contratti"].add(contratto)
    if not varianti:
        raise SystemExit(f"ERRORE [censimento] nessun campo elementare in {cartella}")
    ordine = {c: i for i, c in enumerate(CATEGORIE)}
    righe = sorted(varianti.values(), key=lambda v: (ordine[v["categoria"]], v["lunghezza"], v["variante"]))
    for v in righe:
        v["contratti"] = ",".join(sorted(v["contratti"]))
    scrivi_tsv(os.path.join(out, "censimento.tsv"),
               ["categoria", "variante", "usage", "segno", "cifre_intere", "cifre_decimali", "lunghezza", "campi", "contratti"],
               righe)
    cat_righe = []
    for c in CATEGORIE:
        vs = [v for v in righe if v["categoria"] == c]
        con = sum(v["campi"] for v in vs if v["segno"] == "S")
        senza = sum(v["campi"] for v in vs if v["segno"] != "S")
        lung = sorted({v["lunghezza"] for v in vs})
        cat_righe.append({"categoria": c, "campi": con + senza, "con_segno": con, "senza_segno": senza,
                          "varianti": len(vs), "lunghezze": ",".join(str(x) for x in lung) or "-"})
    scrivi_tsv(os.path.join(out, "censimento-categorie.tsv"),
               ["categoria", "campi", "con_segno", "senza_segno", "varianti", "lunghezze"], cat_righe)
    tot = sum(r["campi"] for r in cat_righe)
    print(f"censimento: {tot} campi elementari, {len(righe)} varianti; " +
          ", ".join(f"{r['categoria']} {r['campi']}" for r in cat_righe))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("uso: censimento.py CARTELLA_CONTRATTI OUT")
    main(sys.argv[1], sys.argv[2])
