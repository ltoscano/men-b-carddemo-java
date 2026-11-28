"""Documento generato docs/legacy-map/fixture.md (issue #5)."""
import hashlib
from collections import Counter

import fixture as fx
from fixture import base_nome


def cella(x):
    """Contenuto di una cella di tabella Markdown (GFM): '|' e a-capo protetti."""
    return str(x).replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ")


def riga(*celle):
    return "| " + " | ".join(cella(c) for c in celle) + " |"


def codice(x):
    return f"`{x}`"


def _separatori(l):
    """Separatori di cella di una riga di tabella: '|' non preceduti da un numero dispari di barre inverse."""
    n, i, barre = 0, 0, 0
    for ch in l:
        if ch == "\\":
            barre += 1
            continue
        if ch == "|" and barre % 2 == 0:
            n += 1
        barre = 0
    return n


def tabelle_malformate(testo):
    """Ogni riga di una tabella deve avere tanti separatori quanti l'intestazione."""
    out, attese = [], None
    for i, l in enumerate(testo.split("\n"), 1):
        if not l.startswith("|"):
            attese = None
            continue
        n = _separatori(l)
        if attese is None:
            attese = n
        elif n != attese:
            out.append(f"fixture.md:{i}: {n - 1} celle invece di {attese - 1}: {l[:80]}")
    return out


def gamme(numeri):
    """[1, 2, 3, 7] -> '1-3, 7'."""
    n = sorted({int(x) for x in numeri if x != "-"})
    out, i = [], 0
    while i < len(n):
        j = i
        while j + 1 < len(n) and n[j + 1] == n[j] + 1:
            j += 1
        out.append(f"{n[i]}-{n[j]}" if j > i else str(n[i]))
        i = j + 1
    return ", ".join(out) or "-"


def documento(ing, voci, dec, confronti, att, uscite):
    o = ["# Fixture dai dati di esempio di CardDemo", "",
         "Documento generato da `./analysis/run.sh data-fixtures` (issue #5): non modificare a mano.", "",
         "Ogni file di `app/data/ASCII/` e `app/data/EBCDIC/` e' decodificato campo per campo con il codec di #23 "
         "(`analysis/data-codec/glue/codec.py`; ASCII con il profilo `oracle-gnucobol`, EBCDIC con `zos-ebcdic`), "
         "guidato dal contratto del record (#3) attraverso l'adattatore di #43, senza riparare alcun valore. Le "
         "fixture sono in `analysis/data-fixtures/out/` (una riga per record; per campo nome, stato, valore e byte "
         "originali), con l'elenco delle anomalie di ogni file e le differenze fra le due codifiche.", "",
         "## File, record, lunghezze, terminatori", "",
         "| File | Contratto | Lung. | Byte | Record | Terminatori | Righe (lunghezza:righe) | Provenienza | Anomalie |",
         "| --- | --- | ---: | ---: | ---: | --- | --- | --- | ---: |"]
    for p, fd in dec.items():
        v = fd.voce
        if v["codifica"] == "ASCII":
            term = fx.intervalli([t for _, t in fd.righe])
            lun = fx.intervalli([str(len(r)) for r, _ in fd.righe])
        else:
            term = lun = "-"
        prov = v["provenienza"] + (f" (`{v['riga']}`)" if v["riga"] != "-" else "")
        o.append(riga(codice(base_nome(p)), codice(v["contratto"]), v["lunghezza"], len(ing.dati[p]),
                      len(fd.record), term, lun, prov, len(fd.anomalie)))
    imp = Counter(hashlib.sha256(ing.dati[p]).hexdigest() for p in dec)
    uguali = [[base_nome(p) for p in dec if hashlib.sha256(ing.dati[p]).hexdigest() == h] for h, n in imp.items()
              if n > 1]
    o += ["", "File identici byte per byte (stessa impronta SHA-256): " +
          ("; ".join(" = ".join(f"`{x}`" for x in g) for g in uguali) if uguali else "nessuno") +
          ". Sono decodificati e confrontati entrambi, senza deduplicazione.", "",
          "## Anomalie", "", "| File | Tipo | Quante | Record |", "| --- | --- | ---: | --- |"]
    for p, fd in dec.items():
        per = {}
        for t, r, c, _ in fd.anomalie:
            per.setdefault(t, []).append(r)
        for t, rr in sorted(per.items()):
            o.append(riga(codice(base_nome(p)), t, len(rr), gamme(rr)))
    senza = [base_nome(p) for p, fd in dec.items() if not fd.anomalie]
    o += ["", "File senza anomalie: " + (", ".join(codice(x) for x in senza) if senza else "nessuno") + "."]
    o += ["", "## Differenze fra ASCII ed EBCDIC", "",
          "I record si abbinano per la chiave dell'inventario; nessuna differenza e' attesa a priori.", "",
          "| ASCII | EBCDIC | Tipo | Campo | Chiave | ASCII | EBCDIC | Spiegazione |",
          "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    riass = []
    for (a, e), diff in confronti.items():
        conta = Counter(d[0] for d in diff)
        riass.append(f"- `{base_nome(a)}` / `{base_nome(e)}`: " +
                     (", ".join(f"{t} {n}" for t, n in sorted(conta.items())) if conta else "nessuna differenza"))
        for d in diff:
            if d[0].startswith("riempimento-uguale"):
                continue
            spieg = ("riempimento dichiarato della riga ASCII corta" if d[0].startswith("riempimento")
                     else "non spiegata dal repository: i due file di esempio non concordano")
            o.append(riga(codice(base_nome(a)), codice(base_nome(e)), d[0], d[2], codice(d[1]), codice(d[3]),
                          codice(d[4]), spieg))
    o += ["", "Riepilogo per coppia (le differenze `riempimento-uguale` sono i campi delle righe ASCII corte riempiti "
          "con spazi, uguali all'EBCDIC; sono elencate nelle fixture `out/confronto-*.tsv`):", ""] + riass
    o += osservazioni(ing, dec)
    o += ["", "## Decisioni di decodifica", "",
          "- **Riempimento delle righe ASCII corte**: spazi (0x20) a destra fino alla lunghezza del record. Nessun JCL "
          "del repository carica i file `.txt` (provenienza `nessuno` verificata), quindi il JCL non determina la "
          "regola: e' una scelta dichiarata, applicata in un passo separato (`RIEMPI`). Le fixture distinguono i byte "
          "del file da quelli aggiunti (colonne 3 e 4, e l'origine `riempimento` del campo).",
          "- **Terminatori**: si legge ogni riga fino a LF; un CR subito prima di LF e' parte del terminatore (CRLF). "
          "I terminatori di ogni riga sono nelle fixture (colonna 2) e nella tabella sopra.",
          "- **EXPORT.DATA.PS**: la vista attiva si sceglie dal tipo di record come `CBIMPORT.cbl` (righe 272-285, "
          "`analysis/data-fixtures/viste-export.tsv`); si decodificano i campi comuni e quelli della sola vista "
          "attiva. Un tipo non previsto avrebbe solo i campi comuni e un'anomalia. L'area `EXPORT-TIMESTAMP-R` "
          "ridefinisce un campo comune, decodificato intero.",
          "- **DALYTRAN.PS.INIT**: decodificato con il contratto del KSDS in cui `TRANFILE.jcl` lo carica "
          "(`CVTRA05Y.TRAN-RECORD`); i byte a zero binario restano tali e i campi numerici risultano non validi.",
          "- **Chiavi**: la chiave di abbinamento e' la KEYS del JCL; per il giornaliero (sequenziale) `DALYTRAN-ID` "
          "e' una scelta; per l'export la KEYS(4 28) si usa com'e', in byte, anche se taglia due campi.", "",
          "## Chiavi", "", "| File | Chiave | Definizione | Record | Distinti | Unica |", "| --- | --- | --- | ---: | ---: | --- |"]
    for r in uscite["chiavi.tsv"].splitlines()[1:]:
        c = r.split("\t")
        o.append(riga(codice(base_nome(c[0])), c[1], codice(c[2]), c[4], c[5], c[6]))
    o += ["", "## Conteggi", "", "| File | Record dalla dimensione | Righe fisiche | Decodificati | Negli attesi |",
          "| --- | ---: | ---: | ---: | ---: |"]
    for r in uscite["conteggi.tsv"].splitlines()[1:]:
        c = r.split("\t")
        o.append(riga(codice(base_nome(c[0])), c[1], c[2], c[3], c[4]))
    o += ["", "## Limiti", "",
          "- Il riempimento delle righe ASCII corte e' una scelta, non un fatto del sorgente.",
          "- Le fixture descrivono i byte dei file del repository; il comportamento dei programmi su questi dati "
          "(oracle, #9) e il caricamento nei file indicizzati (issue successiva) sono fuori ambito.",
          "- Gli attesi a mano coprono alcuni record per file (primo, ultimo, negativi, anomali, uno per tipo "
          "dell'export, i record con differenze ASCII/EBCDIC); gli altri record sono coperti dai controlli d'insieme "
          "(totali, chiavi, ricodifica) e dal confronto con le fixture versionate.", ""]
    return "\n".join(o)


def _corse(b, uguale):
    """Intervalli [a, b] (offset nel record) dei byte per cui uguale(byte) e' vero."""
    out, i = [], 0
    while i < len(b):
        if uguale(b[i]):
            j = i
            while j + 1 < len(b) and uguale(b[j + 1]):
                j += 1
            out.append((i, j))
            i = j + 1
        else:
            i += 1
    return out


def osservazioni(ing, dec):
    """Osservazioni sui byte, ricavate dai dati: nessun valore cambia, si riportano record e offset."""
    o = ["", "## Osservazioni sui dati", "",
         "Ricavate dai byte a ogni rigenerazione; stati e valori dei campi restano quelli delle fixture. Offset assoluti "
         "nel file, da 0, estremi compresi.", "", "### Byte nulli (0x00) nei campi DISPLAY", "",
         "| File | Record | Offset assoluti | Campi | Byte non nulli del record (se i nulli sono la maggioranza) |",
         "| --- | ---: | --- | --- | --- |"]
    trovati = False
    for p, fd in dec.items():
        inizio = 0
        for r in fd.record:
            b = r["riga"]
            if fd.voce["codifica"] == "EBCDIC":
                inizio = (r["n"] - 1) * len(b)
            # solo nei campi DISPLAY (alfanumerici e zonati): nei binari e nei packed 0x00 e' una cifra normale
            display = bytearray(b)
            for c in r["campi"]:
                if c.categoria in ("comp", "comp-3"):
                    display[c.offset:c.offset + c.lunghezza] = b"\x01" * c.lunghezza
            nulli = _corse(bytes(display), lambda x: x == 0)
            if nulli:
                trovati = True
                campi = [c.nome for c in r["campi"] if any(c.offset <= y and x < c.offset + c.lunghezza
                                                           for x, y in nulli)]
                nn = "-"
                if sum(y - x + 1 for x, y in nulli) * 2 > len(b):
                    nn = "; ".join(f"{inizio + x}-{inizio + y}: {fx.a_esa(b[x:y + 1])}"
                                   for x, y in _corse(b, lambda x: x != 0)) or "nessuno"
                o.append(riga(codice(base_nome(p)), r["n"], ", ".join(f"{inizio + x}-{inizio + y}" for x, y in nulli),
                              ", ".join(campi), nn))
            if fd.voce["codifica"] == "ASCII":
                inizio += len(b) + {"CRLF": 2, "LF": 1}.get(r["term"], 0)
    if not trovati:
        o.append(riga("-", "-", "nessuno", "-", "-"))
    o += ["", "Nei campi alfanumerici i byte nulli sono caratteri U+0000 (validi); nei numerici rendono il campo non "
          "valido (anomalie).", "", "### Numeri di sequenza dell'export", ""]
    for p, fd in dec.items():
        if fd.voce["contratto"] != fx.EXPORT:
            continue
        prec, salti = None, []
        for r in fd.record:
            c = next((c for c in r["campi"] if c.nome == "EXPORT-SEQUENCE-NUM"), None)
            v = int(c.valore) if c is not None and c.stato == "valido" else None
            if prec is not None and v is not None and v != prec[1] + 1:
                salti.append(f"record {prec[0]} -> {r['n']}: {prec[1]} -> {v}")
            prec = (r["n"], v) if v is not None else None
        o.append(f"- {codice(base_nome(p))}: " + ("; ".join(salti) if salti else "nessun salto") +
                 ". `CBEXPORT.cbl` (righe 529-530) aggiunge 1 a ogni record scritto: il salto non e' spiegato dal "
                 "repository.")
    return o
