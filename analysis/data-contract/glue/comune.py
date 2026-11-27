"""Funzioni condivise dagli script di colla del contratto dati (issue #3).

Nessuna di queste funzioni interpreta il COBOL oltre a quanto serve per un'estrazione testuale minima e
dichiarata: aree di formato fisso, righe di commento, frasi chiuse dal punto, parole fuori dai letterali.
"""
import os

# Classificazioni ammesse nel censimento e quelle che richiedono un contratto.
CLASSI = ("record-di-file", "stato-di-conversazione", "riga-di-report", "area-di-lavoro", "non-tracciato")
CON_CONTRATTO = ("record-di-file", "stato-di-conversazione")


def leggi_tsv(path):
    """Legge un TSV con intestazione; ignora le righe vuote e quelle che iniziano con '#'."""
    with open(path, encoding="utf-8") as f:
        righe = [r.rstrip("\n") for r in f if r.strip() and not r.startswith("#")]
    if not righe:
        return []
    testa = righe[0].split("\t")
    out = []
    for n, r in enumerate(righe[1:], 2):
        campi = r.split("\t")
        if len(campi) != len(testa):
            raise SystemExit(f"{path}: riga {n}: {len(campi)} colonne invece di {len(testa)}")
        out.append(dict(zip(testa, campi)))
    return out


def scrivi_tsv(path, testa, righe):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\t".join(testa) + "\n")
        for r in righe:
            valori = [r[c] for c in testa] if isinstance(r, dict) else list(r)
            f.write("\t".join(str(v) for v in valori) + "\n")


def leggi_righe(path):
    """Righe di un sorgente legacy, byte per byte (latin-1 conserva ogni byte), senza il fine riga."""
    with open(path, "rb") as f:
        dati = f.read().decode("latin-1")
    return dati.split("\n")[:-1] if dati.endswith("\n") else dati.split("\n")


def area_programma(riga):
    """Formato fisso COBOL: restituisce (indicatore colonna 7, testo delle colonne 8-72).
    Una riga piu' corta di 7 caratteri e' vuota."""
    if len(riga) < 7:
        return " ", ""
    return riga[6], riga[7:72]


def frasi(righe, inizio=1, fine=None):
    """Divide in frasi (chiuse da un punto seguito da spazio o fine riga, fuori dai letterali) le righe
    [inizio, fine] (numeri da 1). Salta i commenti (colonna 7 '*' o '/'). Una riga di continuazione
    (colonna 7 '-') prosegue il letterale aperto: se ne toglie il primo apice.
    Restituisce una lista di (riga_iniziale, testo)."""
    fine = len(righe) if fine is None else fine
    out, buf, riga0, in_lett, apice = [], [], None, False, None
    for n in range(inizio, fine + 1):
        ind, testo = area_programma(righe[n - 1])
        if ind in "*/":
            continue
        if ind == "-":
            s = testo.lstrip()
            if in_lett and s[:1] in ("'", '"'):
                s = s[1:]
            testo = s
        elif buf:
            testo = " " + testo
        i = 0
        while i < len(testo):
            c = testo[i]
            if riga0 is None and not c.isspace():
                riga0 = n
            if in_lett:
                buf.append(c)
                if c == apice:
                    in_lett = False
            elif c in ("'", '"'):
                in_lett, apice = True, c
                buf.append(c)
            elif c == "." and (i + 1 == len(testo) or testo[i + 1].isspace()):
                s = "".join(buf).strip()
                if s:
                    out.append((riga0, s))
                buf, riga0 = [], None
            else:
                buf.append(c)
            i += 1
    s = "".join(buf).strip()
    if s:
        out.append((riga0, s))
    return out


def parole(testo):
    """Parole di una frase, con i letterali come parola unica (apici compresi)."""
    out, i, n = [], 0, len(testo)
    while i < n:
        c = testo[i]
        if c.isspace() or c == ",":
            i += 1
            continue
        if c in ("'", '"'):
            j = testo.find(c, i + 1)
            j = n - 1 if j < 0 else j
            out.append(testo[i:j + 1])
            i = j + 1
            continue
        j = i
        while j < n and not testo[j].isspace() and testo[j] not in ("'", '"'):
            j += 1
        out.append(testo[i:j])
        i = j
    return out


def senza_letterali(testo):
    """Sostituisce il contenuto dei letterali con spazi (per cercare parole chiave nel codice)."""
    out, in_lett, apice = [], False, None
    for c in testo:
        if in_lett:
            out.append(" ")
            if c == apice:
                in_lett = False
        elif c in ("'", '"'):
            in_lett, apice = True, c
            out.append(" ")
        else:
            out.append(c)
    return "".join(out)


def stem(percorso):
    return os.path.splitext(os.path.basename(percorso))[0]
