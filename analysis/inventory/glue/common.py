"""Funzioni comuni degli script di colla dell'inventario (girano in container: /analysis, /legacy, /work)."""
import os


def manifest():
    rows = []
    with open("/analysis/manifest/sources.tsv", encoding="utf-8") as f:
        next(f)
        for line in f:
            p, t = line.rstrip("\n").split("\t")
            rows.append((p, t))
    return rows


def of_type(*types):
    return [p for p, t in manifest() if t in types]


def stem(path):
    return os.path.splitext(os.path.basename(path))[0].upper()


def read_lines(path):
    """Righe del file del legacy, senza fine riga; numerazione da 1 = indice + 1."""
    with open("/legacy/" + path, encoding="latin-1", newline="") as f:
        data = f.read()
    return [l.rstrip("\r") for l in data.split("\n")]


def write_tsv(path, header, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write("\t".join(header) + "\n")
        for r in rows:
            f.write("\t".join(str(x) for x in r) + "\n")


def read_tsv(path):
    with open(path, encoding="utf-8") as f:
        header = next(f).rstrip("\n").split("\t")
        return [dict(zip(header, l.rstrip("\n").split("\t"))) for l in f]
