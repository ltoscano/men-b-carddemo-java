"""Alterazioni per le prove negative di check.sh (issue #23) su una copia ("mondo") di vettori, output e documento.

Uso: altera.py NOME MONDO
  MONDO contiene vettori/ (copia di analysis/data-codec/vettori), out/ (copia dell'output rigenerato) e codifica.md.
Ogni alterazione verifica di aver cambiato davvero il file: una prova negativa vuota sarebbe un falso verde.
"""
import os
import sys


def _righe(path):
    with open(path, encoding="utf-8") as f:
        return f.read().split("\n")


def _scrivi(path, righe):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(righe))


def togli(path, pred, attese=1):
    r = _righe(path)
    nuove = [x for x in r if not pred(x)]
    if len(r) - len(nuove) != attese:
        raise SystemExit(f"alterazione non applicata a {path}: {len(r) - len(nuove)} righe tolte invece di {attese}")
    _scrivi(path, nuove)


def cambia(path, pred, fn):
    r = _righe(path)
    n = 0
    for i, x in enumerate(r):
        if pred(x):
            y = fn(x)
            if y == x:
                raise SystemExit(f"alterazione vuota su {path}")
            r[i] = y
            n += 1
    if n != 1:
        raise SystemExit(f"alterazione non applicata a {path}: {n} righe cambiate invece di 1")
    _scrivi(path, r)


def colonna(x, i, valore):
    c = x.split("\t")
    c[i] = valore
    return "\t".join(c)


def main(nome, mondo):
    v_o = os.path.join(mondo, "vettori", "oracle-gnucobol.tsv")
    v_z = os.path.join(mondo, "vettori", "zos-ebcdic.tsv")
    v_x = os.path.join(mondo, "vettori", "oracle-oltre-picture.tsv")
    doc = os.path.join(mondo, "codifica.md")
    out = os.path.join(mondo, "out")
    c = lambda x: x.split("\t")  # noqa: E731
    if nome == "vettore-senza-valore":
        cambia(v_o, lambda x: c(x)[:5] == ["display-con-segno", "S9(10)V9(2)", "decodifica", "30*7 31 32 33 34 42", "valido"],
               lambda x: colonna(x, 5, "-"))
    elif nome == "vettore-con-colonna-vuota":
        cambia(v_z, lambda x: c(x)[:4] == ["comp", "9(3)", "decodifica", "00 7B"], lambda x: colonna(x, 6, ""))
    elif nome == "variante-senza-vettori":
        togli(v_z, lambda x: c(x)[:3] == ["display-senza-segno", "9(16)", "decodifica"], attese=4)
    elif nome == "variante-del-censimento-in-piu":
        p = os.path.join(out, "censimento.tsv")
        r = _righe(p)
        r.insert(len(r) - 1, "comp\t9(4)\tCOMP\t-\t4\t0\t2\t1\tFINTO.CONTRATTO")
        _scrivi(p, r)
    elif nome == "riga-della-tabella-del-segno-tolta":
        togli(v_o, lambda x: c(x)[:4] == ["display-con-segno", "S9(4)V9(2)", "decodifica", "31 32 33 34 35 42"])
    elif nome == "codice-comp3-tolto":
        togli(v_z, lambda x: c(x)[:4] == ["comp-3", "S9(9)V9(2)", "decodifica", "00 00 01 23 45 6F"])
    elif nome == "estremo-binario-tolto":
        togli(v_o, lambda x: c(x)[:4] == ["comp", "9(11)", "decodifica", "00 00 00 17 48 76 E7 FF"])
    elif nome == "byte-distintivo-tolto":
        togli(v_z, lambda x: c(x)[:4] == ["alfanumerico", "X(10)", "decodifica", "BA BB B0 5F AD BD 40*4"])
    elif nome == "fonte-dell-altro-profilo":
        cambia(v_z, lambda x: c(x)[:4] == ["comp-3", "9(3)", "decodifica", "12 3F"], lambda x: colonna(x, 8, "GC-SRC-PACKED"))
    elif nome == "variante-tolta-dal-documento":
        togli(doc, lambda x: x.startswith("| comp | `9(11)` |"))
    elif nome == "fonte-tolta-dal-documento":
        togli(doc, lambda x: x.startswith("| `IBM-PG63-TRUNC` |"))
    elif nome == "pagina-byte-in-alfanumerico":
        cambia(os.path.join(out, "pagina.tsv"), lambda x: "\t494\t65\t" in x, lambda x: colonna(x, 10, "alfanumerico"))
    elif nome == "osservazione-mancante":
        togli(os.path.join(out, "sonde", "osservazioni.tsv"), lambda x: "\tdisplay-con-segno:S9(4)V9(2)\t" in x and "\t31 32 33 34 35 4A\t" in x)
    elif nome == "osservazione-in-piu":
        p = os.path.join(out, "sonde", "osservazioni.tsv")
        r = _righe(p)
        r.insert(1, "9\tdecodifica\tcomp:9(3)\t-\t+00000000000000000123000000\t+00000000000000000123000000\t00 7B\t00 7B")
        _scrivi(p, r)
    elif nome == "osservazione-alterata":
        cambia(os.path.join(out, "sonde", "osservazioni.tsv"),
               lambda x: "\tdisplay-con-segno:S9(10)V9(2)\t" in x and x.endswith("\t30*7 31 32 33 34 4A"),
               lambda x: colonna(x, 4, "+00000000000000000123410000"))
    elif nome == "oltre-picture-add-alterato":
        cambia(v_x, lambda x: c(x)[:2] == ["9(9)", "FF*4"], lambda x: colonna(x, 3, "4294967295"))
    elif nome == "oltre-picture-osservazione-tolta":
        togli(v_x, lambda x: c(x)[:2] == ["9(3)", "FF FF"])
    elif nome == "compilazione-senza-fsign":
        togli(os.path.join(out, "sonde", "compilazione.log"), lambda x: x == "arg -fsign=EBCDIC")
    elif nome == "ambiente-in-piu":
        p = os.path.join(out, "sonde", "ambiente.txt")
        r = _righe(p)
        r.insert(0, "COB_CONFIG_DIR=/tmp/altra")
        _scrivi(p, r)
    elif nome == "censimento-alterato":
        cambia(os.path.join(out, "censimento.tsv"), lambda x: x.startswith("comp\t9(9)\t"), lambda x: colonna(x, 7, "4"))
    else:
        raise SystemExit(f"alterazione sconosciuta: {nome}")
    print(f"alterazione applicata: {nome}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("uso: altera.py NOME MONDO")
    main(*sys.argv[1:])
