"""Ingresso e lettura della sonda CODECPRB (issue #23, profilo oracle-gnucobol).

  sonda.py ingresso VETTORI.tsv OUT.dat
      scrive il file letto dalla sonda (DD_CODECIN): un record fisso di 553 byte per ogni riga di
      decodifica e per ogni riga di codifica con un 'move' atteso. Non usa il codec: copia i byte
      d'ingresso dei vettori, o scrive il valore nuovo come S9(20)V9(6) SIGN LEADING SEPARATE (numerici)
      o come testo ISO-8859-1 (alfanumerici). In coda, i casi esaustivi della sonda (comune.casi_esaustivi):
      ogni valore 0-255 dell'ultimo byte e del primo byte del corpo per alcuni DISPLAY, id da 900001.
  sonda.py leggi RAPPORTO.txt OUT.tsv
      estrae dal rapporto di oracle/esegui.sh (sezione stdout) le righe della sonda e scrive le
      osservazioni, una per vettore; fallisce se manca la riga finale FINE, se il conteggio non torna,
      se il codice di uscita non e' 0 o se una riga e' malformata.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comune import a_esa, casi_esaustivi, da_esa, leggi_tsv, scrivi_tsv, valore_da_testo  # noqa: E402

LUNG_REC = 6 + 1 + 40 + 3 + 3 + 500


def _numero_separato(v):
    """Decimal -> testo di S9(20)V9(6) SIGN LEADING SEPARATE (27 byte)."""
    q = v.scaleb(6)
    if q != q.to_integral_value():
        raise SystemExit(f"valore {v}: piu' di 6 decimali, non rappresentabile nell'ingresso della sonda")
    n = int(q)
    if abs(n) >= 10 ** 26:
        raise SystemExit(f"valore {v}: troppo grande per l'ingresso della sonda")
    return ("-" if n < 0 else "+") + str(abs(n)).rjust(26, "0")


def ingresso(vettori, out):
    _, righe = leggi_tsv(vettori)
    n = 0
    with open(out, "wb") as f:
        for r in righe:
            cat, var, op = r["categoria"], r["variante"], r["operazione"]
            alfa = cat == "alfanumerico"
            ncampo = int(var[2:-1]) if alfa else 0
            if op == "decodifica":
                dati = da_esa(r["ingresso"])
                ncampo = ncampo or len(dati)
                codice = b"D"
            elif op == "codifica":
                if r["move"] == "-":
                    continue
                v = valore_da_testo(r["ingresso"], alfa)
                dati = v.encode("latin-1") if alfa else _numero_separato(v).encode("ascii")
                ncampo = ncampo or len(da_esa(r["move"]))
                codice = b"C"
            else:
                raise SystemExit(f"{vettori}:{r['_riga']}: operazione sconosciuta {op}")
            if len(dati) > 500 or len(f"{cat}:{var}") > 40:
                raise SystemExit(f"{vettori}:{r['_riga']}: vettore troppo lungo per la sonda")
            rec = (b"%06d" % r["_riga"]) + codice + f"{cat}:{var}".encode("ascii").ljust(40) \
                + (b"%03d" % ncampo) + (b"%03d" % len(dati)) + dati.ljust(500, b" ")
            assert len(rec) == LUNG_REC
            f.write(rec)
            n += 1
        e = 0
        for idc, _pos, cat, var, _b, dati in casi_esaustivi("oracle-gnucobol", solo_sonda=True):
            rec = (b"%06d" % idc) + b"D" + f"{cat}:{var}".encode("ascii").ljust(40) \
                + (b"%03d" % len(dati)) + (b"%03d" % len(dati)) + dati.ljust(500, b" ")
            assert len(rec) == LUNG_REC
            f.write(rec)
            e += 1
    print(f"ingresso della sonda: {n} record dai vettori, {e} casi esaustivi")


def leggi(rapporto, out):
    with open(rapporto, encoding="latin-1") as f:
        testo = f.read().split("\n")
    try:
        i_rc, i_out, i_err = testo.index("== codice di uscita"), testo.index("== stdout"), testo.index("== stderr")
    except ValueError:
        raise SystemExit(f"{rapporto}: rapporto malformato (sezioni mancanti)")
    rc = testo[i_rc + 1]
    if rc != "0":
        raise SystemExit(f"{rapporto}: la sonda e' terminata con codice {rc}:\n" + "\n".join(testo[i_out:i_err + 5]))
    righe = testo[i_out + 1:i_err]
    if not righe or not righe[-1].startswith("FINE|"):
        raise SystemExit(f"{rapporto}: manca la riga finale FINE della sonda (esecuzione incompleta)")
    attese = int(righe[-1].split("|")[1])
    oss = []
    for riga in righe[:-1]:
        c = riga.split("|")
        if len(c) != 8 or not c[0].isdigit() or c[1] not in ("D", "C"):
            raise SystemExit(f"{rapporto}: riga della sonda malformata: {riga!r}")
        idv, op, var, classe, vm, va, scritto, dopo = c
        esa = lambda h: "-" if h == "-" else a_esa(bytes.fromhex(h)) if h else "-"  # noqa: E731
        oss.append({"riga": int(idv), "operazione": "decodifica" if op == "D" else "codifica", "variante": var,
                    "classe": classe, "valore_move": vm if op == "D" and not var.startswith("alfanumerico:") else esa(vm),
                    "valore_add": va, "scritto": esa(scritto), "dopo": esa(dopo)})
    if len(oss) != attese:
        raise SystemExit(f"{rapporto}: la sonda dichiara {attese} record letti, righe stampate {len(oss)}")
    scrivi_tsv(out, ["riga", "operazione", "variante", "classe", "valore_move", "valore_add", "scritto", "dopo"], oss)
    print(f"osservazioni della sonda: {len(oss)}")


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("ingresso", "leggi"):
        raise SystemExit("uso: sonda.py ingresso VETTORI.tsv OUT.dat | sonda.py leggi RAPPORTO.txt OUT.tsv")
    {"ingresso": ingresso, "leggi": leggi}[sys.argv[1]](sys.argv[2], sys.argv[3])
