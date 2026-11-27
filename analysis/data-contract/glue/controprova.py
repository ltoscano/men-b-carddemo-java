"""Controprova semplice e indipendente dal rilevatore di struttura.py (issue #3, giro 2 di validazione).

Cerca, riga per riga, le istruzioni `MOVE <nome> TO <nome>` scritte su una sola riga nei programmi batch, in cui il primo
nome e' dichiarato (nel programma o in un copybook che il programma copia) a livello 01/77 o come gruppo (riga di
dichiarazione senza PIC seguita da una voce di livello superiore). Non usa l'albero dei dati ne' la scomposizione in
istruzioni di struttura.py.
"""
import os
import re

from comune import area_programma, leggi_righe, senza_letterali, stem

RE_MOVE = re.compile(r"^\s*MOVE\s+([A-Z][A-Z0-9-]*)\s+TO\s+([A-Z][A-Z0-9-]*)")
RE_DECL = r"^\s*(\d\d?)\s+{}(\s|\.|$)"
RE_COPY = re.compile(r"^\s*COPY\s+([A-Z0-9]+)")


def codice(righe):
    out = []
    for r in righe:
        ind, t = area_programma(r)
        out.append("" if ind in "*/" else senza_letterali(t).upper())
    return out


def struttura(nome, sorgenti):
    """True se 'nome' e' dichiarato come 01/77 o come gruppo in uno dei sorgenti (liste di righe di codice)."""
    rx = re.compile(RE_DECL.format(re.escape(nome)))
    for cod in sorgenti:
        for k, t in enumerate(cod):
            m = rx.match(t)
            if not m:
                continue
            liv = int(m.group(1))
            if liv in (1, 77):
                return True
            if "PIC" not in t.split():
                seg = next((x for x in cod[k + 1:] if x.strip()), "")
                ms = re.match(r"^\s*(\d\d?)\s", seg)
                if ms and int(ms.group(1)) > liv and int(ms.group(1)) != 88:
                    return True
    return False


def mosse_di_strutture(legacy, programma, copie):
    cod = codice(leggi_righe(os.path.join(legacy, programma)))
    sorgenti = [cod]
    for t in cod:
        m = RE_COPY.match(t)
        if m and m.group(1) in copie:
            sorgenti.append(codice(leggi_righe(os.path.join(legacy, copie[m.group(1)]))))
    inizio = next((k for k, t in enumerate(cod) if re.search(r"\bPROCEDURE\s+DIVISION\b", t)), len(cod))
    out = []
    for k in range(inizio + 1, len(cod)):
        m = RE_MOVE.match(cod[k])
        if m and struttura(m.group(1), sorgenti):
            out.append((k + 1, m.group(1), m.group(2)))
    return out


def indice_copie(manifesto_righe):
    return {stem(p).upper(): p for p in manifesto_righe}
