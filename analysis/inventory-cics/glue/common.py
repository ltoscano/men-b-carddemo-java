"""Funzioni comuni della colla di inventory-cics (gira in container: /analysis, /legacy, /docs, /work).

Le variabili d'ambiente servono a far girare la stessa colla sui file di prova:
  CICS_LEGACY    radice del sorgente (default /legacy)
  CICS_MANIFEST  manifesto dei sorgenti (default /analysis/manifest/sources.tsv)
  CICS_BASE      grafo di base di #2 (default /docs/graph.json)"""
import json
import os

LEGACY = os.environ.get("CICS_LEGACY", "/legacy")
MANIFEST = os.environ.get("CICS_MANIFEST", "/analysis/manifest/sources.tsv")
BASE = os.environ.get("CICS_BASE", "/docs/graph.json")


def manifest():
    rows = []
    with open(MANIFEST, encoding="utf-8") as f:
        header = next(f).rstrip("\n").split("\t")
        if header != ["path", "type"]:
            raise SystemExit(f"manifesto {MANIFEST}: intestazione inattesa {header}")
        for line in f:
            p, t = line.rstrip("\n").split("\t")
            rows.append((p, t))
    return rows


def sources():
    """Programmi e copybook del manifesto (percorso, tipo), nell'ordine del manifesto."""
    return [(p, t) for p, t in manifest() if t in ("cobol", "copybook")]


def stem(path):
    return os.path.splitext(os.path.basename(path))[0].upper()


def read_lines(path):
    """Righe del file del legacy, senza fine riga; numerazione da 1 = indice + 1."""
    with open(LEGACY + "/" + path, encoding="latin-1", newline="") as f:
        data = f.read()
    return [l.rstrip("\r") for l in data.split("\n")]


def base_graph():
    return json.load(open(BASE, encoding="utf-8"))


def response_name(path):
    return path.replace("/", "_") + ".tsv"
