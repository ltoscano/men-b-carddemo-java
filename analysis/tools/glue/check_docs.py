#!/usr/bin/env python3
"""Verifica la coerenza tra docs/legacy-map/strumenti.md, capabilities.tsv e le prove in analysis/tools/out/.

Uso: check_docs.py CAPABILITIES.tsv STRUMENTI.md OUT_DIR
Controlla:
  - una riga per ogni candidato (nove nomi fissi), nella tabella che inizia con '| Strumento |';
  - per i candidati provati: versione, licenza, ultimo rilascio, comando, esito e verdetto compilati, e una cartella di prove in out/;
  - per i candidati non provati: verdetto esattamente 'non provato' e nessuna cartella in out/;
  - la tabella finale '| Capacità |' riporta le stesse capacita', stati e strumenti di capabilities.tsv;
  - gli strumenti indicati in capabilities.tsv hanno verdetto 'adottato...' nella tabella dei candidati.
"""
import os
import sys

CANDIDATES = [  # (nome nella tabella, cartella in out/)
    ("scc", "scc"), ("GnuCOBOL", "gnucobol"), ("cobol-migration-toolkit", "cmt"), ("cobmix", "cobmix"),
    ("ProLeap COBOL parser", "proleap"), ("Koopa", "koopa"), ("cb2xml", "cb2xml"), ("JRecord", "jrecord"), ("mapa", "mapa"),
]


def table_after(lines, header_prefix):
    """Restituisce le righe dati della prima tabella la cui intestazione inizia con header_prefix."""
    for i, l in enumerate(lines):
        if l.startswith(header_prefix):
            rows = []
            for r in lines[i + 2:]:
                if not r.startswith("|"):
                    break
                rows.append([c.strip() for c in r.strip().strip("|").split("|")])
            return [c.strip() for c in l.strip().strip("|").split("|")], rows
    return None, []


def clean(s):
    return s.replace("**", "").replace("`", "").strip()


def main(caps_path, doc_path, out_dir):
    errors = []
    lines = open(doc_path, encoding="utf-8").read().split("\n")

    hdr, rows = table_after(lines, "| Strumento |")
    if hdr is None:
        print("DOC: tabella dei candidati ('| Strumento |') non trovata", file=sys.stderr)
        return 1
    col = {clean(h): i for i, h in enumerate(hdr)}
    for need in ("Versione", "Licenza", "Ultimo rilascio", "Comando", "Esito", "Verdetto"):
        if need not in col:
            errors.append(f"colonna mancante nella tabella dei candidati: {need}")
    by_name = {}
    for r in rows:
        by_name[clean(r[0])] = r
    verdict_of = {}
    for name, d in CANDIDATES:
        r = by_name.get(name)
        if r is None:
            errors.append(f"candidato senza riga nella tabella: {name}")
            continue
        verdetto = clean(r[col["Verdetto"]]) if "Verdetto" in col else ""
        verdict_of[d] = verdetto
        provato = os.path.isdir(os.path.join(out_dir, d))
        if verdetto.lower().startswith("non provato"):
            if verdetto.lower() != "non provato":
                errors.append(f"{name}: per i non provati il verdetto e' esattamente 'non provato'")
            if provato:
                errors.append(f"{name}: dichiarato 'non provato' ma esiste out/{d}")
        else:
            if not provato:
                errors.append(f"{name}: dichiarato provato ma manca la cartella di prove out/{d}")
            for c in ("Versione", "Licenza", "Ultimo rilascio", "Comando", "Esito"):
                if c in col and not clean(r[col[c]]):
                    errors.append(f"{name}: cella '{c}' vuota")
            esito = clean(r[col["Esito"]]).lower() if "Esito" in col else ""
            if not any(esito.startswith(x) for x in ("funziona", "in parte", "non funziona")):
                errors.append(f"{name}: esito deve iniziare con funziona / in parte / non funziona")
            if not ("adottat" in verdetto.lower() or "scartat" in verdetto.lower()):
                errors.append(f"{name}: verdetto deve dire adottato o scartato (con motivo)")
    extra = set(by_name) - {n for n, _ in CANDIDATES}
    if extra:
        errors.append(f"righe non previste nella tabella dei candidati: {sorted(extra)}")

    # tabella finale delle capacita'
    chdr, crows = table_after(lines, "| Capacità |")
    if chdr is None:
        errors.append("tabella finale delle capacita' ('| Capacità |') non trovata")
        crows = []
    ccol = {clean(h): i for i, h in enumerate(chdr or [])}
    caps = []
    for l in open(caps_path, encoding="utf-8"):
        l = l.rstrip("\n")
        if not l or l.startswith("#"):
            continue
        caps.append(l.split("\t"))
    caps = caps[1:]  # intestazione
    doc_caps = {clean(r[0]): r for r in crows}
    if set(doc_caps) != {c[0] for c in caps}:
        errors.append(f"capacita' diverse tra documento e capabilities.tsv: {sorted(set(doc_caps) ^ {c[0] for c in caps})}")
    for c in caps:
        r = doc_caps.get(c[0])
        if not r:
            continue
        if clean(r[ccol["Stato"]]) != c[2]:
            errors.append(f"{c[0]}: stato nel documento '{clean(r[ccol['Stato']])}' diverso da capabilities.tsv '{c[2]}'")
        if clean(r[ccol["Strumenti"]]) != c[3]:
            errors.append(f"{c[0]}: strumenti nel documento '{clean(r[ccol['Strumenti']])}' diversi da capabilities.tsv '{c[3]}'")
        if c[2] == "available":
            for t in c[3].split("+"):
                v = verdict_of.get(t, "")
                if not v.lower().startswith("adottato"):
                    errors.append(f"{c[0]}: lo strumento '{t}' e' available ma il suo verdetto e' '{v}'")

    for e in errors:
        print("DOC: " + e, file=sys.stderr)
    if not errors:
        print(f"strumenti.md coerente: {len(CANDIDATES)} candidati, {len(caps)} capacita'")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
