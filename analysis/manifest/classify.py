#!/usr/bin/env python3
"""Classifica i file tracciati del legacy: legge da stdin l'output di `git ls-files -z`
e scrive su stdout il manifesto TSV (percorso<TAB>tipo), ordinato byte per byte.

Regole, applicate nell'ordine (la prima che corrisponde vince; il confronto e' senza
distinzione di maiuscole):
  1. cartella samples/            -> sample
  2. cartella diagrams/           -> doc
  3. cartella scripts/markers/    -> other   (file-marcatore senza estensione, non sorgenti)
  4. cartella scripts/            -> script  (sh, awk, template JCL usato dagli script)
  5. file di primo livello LICENSE, NOTICE -> doc
  6. estensione (ultimo suffisso dopo il punto):
       cbl->cobol  cpy->copybook  bms->bms  jcl->jcl  prc->proc  asm->asm  mac->macro
       csd->csd  ctl->ctl  ddl->ddl  dcl->dcl  psb,dbd->ims  ca7,controlm->scheduler
       md,png,drawio->doc
       ps,dat,txt,init->data   (dati di esempio e listato catalogo)
  7. altrimenti                   -> other   (.gitkeep, .gitignore, ...)
Ogni file riceve esattamente un tipo.
"""
import sys

TYPES = ("cobol", "copybook", "bms", "jcl", "proc", "asm", "macro", "csd", "ctl", "ddl",
         "dcl", "ims", "data", "scheduler", "script", "doc", "sample", "other")

EXT = {
    "cbl": "cobol", "cpy": "copybook", "bms": "bms", "jcl": "jcl", "prc": "proc",
    "asm": "asm", "mac": "macro", "csd": "csd", "ctl": "ctl", "ddl": "ddl", "dcl": "dcl",
    "psb": "ims", "dbd": "ims", "ca7": "scheduler", "controlm": "scheduler",
    "md": "doc", "png": "doc", "drawio": "doc",
    "ps": "data", "dat": "data", "txt": "data", "init": "data",
}


def classify(path: str) -> str:
    p = path.lower()
    if p.startswith("samples/"):
        return "sample"
    if p.startswith("diagrams/"):
        return "doc"
    if p.startswith("scripts/markers/"):
        return "other"
    if p.startswith("scripts/"):
        return "script"
    if p in ("license", "notice"):
        return "doc"
    base = p.rsplit("/", 1)[-1]
    if "." in base:
        return EXT.get(base.rsplit(".", 1)[1], "other")
    return "other"


def main() -> int:
    raw = sys.stdin.buffer.read()
    paths = [x.decode("utf-8") for x in raw.split(b"\0") if x]
    rows = sorted(((p, classify(p)) for p in paths), key=lambda r: r[0].encode("utf-8"))
    out = sys.stdout
    out.write("path\ttype\n")
    for p, t in rows:
        assert t in TYPES, t
        assert "\t" not in p and "\n" not in p, p
        out.write(f"{p}\t{t}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
