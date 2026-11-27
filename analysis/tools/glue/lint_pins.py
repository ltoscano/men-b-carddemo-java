#!/usr/bin/env python3
"""Verifica che ogni immagine abbia versione fissata: basi con digest, strumenti con versione esplicita.

Regole: ogni FROM ha @sha256:; nessun tag 'latest'; ogni 'pip install' ha una versione (==) o un archivio
con commit completo; ogni ADD/curl di un binario scaricato ha un checksum SHA-256; i tag delle immagini in
analysis/tools/lib.sh portano una versione.
Uso: lint_pins.py ANALYSIS_DIR
"""
import glob
import os
import re
import sys


def main(root):
    errors = []
    files = sorted(glob.glob(os.path.join(root, "**", "Dockerfile"), recursive=True))
    if not files:
        errors.append("nessun Dockerfile trovato")
    for p in files:
        rel = os.path.relpath(p, root)
        text = open(p, encoding="utf-8").read()
        # unisce le righe continuate con backslash
        logical = re.sub(r"\\\n", " ", text)
        for line in logical.split("\n"):
            s = line.strip()
            if s.startswith("FROM ") and "@sha256:" not in s:
                errors.append(f"{rel}: FROM senza digest: {s}")
            if "latest" in s and not s.startswith("#"):
                errors.append(f"{rel}: tag 'latest': {s}")
            if "pip install" in s and not s.startswith("#"):
                if "==" not in s and not re.search(r"/archive/[0-9a-f]{40}\.tar\.gz", s):
                    errors.append(f"{rel}: pip install senza versione fissata: {s}")
            if s.startswith("ADD ") and "http" in s and "--checksum=sha256:" not in s:
                errors.append(f"{rel}: ADD da URL senza checksum SHA-256: {s}")
            if "curl" in s and "http" in s and "sha256sum" not in s and not s.startswith("#"):
                errors.append(f"{rel}: download con curl senza verifica sha256sum: {s}")
            if "apt-get install" in s and "gnucobol3" in s and "gnucobol3=" not in s:
                errors.append(f"{rel}: gnucobol3 senza versione fissata: {s}")
    lib = open(os.path.join(root, "tools", "lib.sh"), encoding="utf-8").read()
    for m in re.finditer(r'^(IMG_\w+)="([^"]+)"', lib, re.M):
        if not re.search(r":([0-9][0-9a-zA-Z.\-]*|[0-9a-f]{7})$", m.group(2)):
            errors.append(f"tools/lib.sh: {m.group(1)}={m.group(2)} senza tag di versione")
    for e in errors:
        print("VERSIONI: " + e, file=sys.stderr)
    if not errors:
        print(f"versioni fissate: {len(files)} Dockerfile controllati, tutti con basi per digest e strumenti per versione")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
