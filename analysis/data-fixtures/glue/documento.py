"""Documento generato docs/legacy-map/fixture.md (issue #5)."""
import hashlib
from collections import Counter

import fixture as fx
from fixture import base_nome


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
        o.append(f"| `{base_nome(p)}` | `{v['contratto']}` | {v['lunghezza']} | {len(ing.dati[p])} | "
                 f"{len(fd.record)} | {term} | {lun} | {prov} | {len(fd.anomalie)} |")
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
            o.append(f"| `{base_nome(p)}` | {t} | {len(rr)} | {gamme(rr)} |")
    if not any(fd.anomalie for fd in dec.values()):
        o.append("| - | nessuna | 0 | - |")
    o += ["", "## Differenze fra ASCII ed EBCDIC", "",
          "I record si abbinano per la chiave dell'inventario; nessuna differenza e' attesa a priori.", "",
          "| ASCII | EBCDIC | Tipo | Campo | Chiave | ASCII | EBCDIC |", "| --- | --- | --- | --- | --- | --- | --- |"]
    riass = []
    for (a, e), diff in confronti.items():
        conta = Counter(d[0] for d in diff)
        riass.append(f"- `{base_nome(a)}` / `{base_nome(e)}`: " +
                     (", ".join(f"{t} {n}" for t, n in sorted(conta.items())) if conta else "nessuna differenza"))
        for d in diff:
            if d[0].startswith("riempimento-uguale"):
                continue
            o.append(f"| `{base_nome(a)}` | `{base_nome(e)}` | {d[0]} | {d[2]} | `{d[1]}` | `{d[3]}` | `{d[4]}` |")
    o += ["", "Riepilogo per coppia (le differenze `riempimento-uguale` sono i campi delle righe ASCII corte riempiti "
          "con spazi, uguali all'EBCDIC; sono elencate nelle fixture `out/confronto-*.tsv`):", ""] + riass
    o += ["", "## Decisioni di decodifica", "",
          "- **Riempimento delle righe ASCII corte**: spazi (0x20) a destra fino alla lunghezza del record. Nessun JCL "
          "del repository carica i file `.txt` (provenienza `nessuno` verificata), quindi il JCL non determina la "
          "regola: e' una scelta dichiarata, applicata in un passo separato (`RIEMPI`). Le fixture distinguono i byte "
          "del file da quelli aggiunti (colonne 3 e 4, e l'origine `riempimento` del campo).",
          "- **Terminatori**: si legge ogni riga fino a LF; un CR subito prima di LF e' parte del terminatore (CRLF). "
          "I terminatori di ogni riga sono nelle fixture (colonna 2) e nella tabella sopra.",
          "- **EXPORT.DATA.PS**: la vista attiva si sceglie dal tipo di record come `CBIMPORT.cbl` (righe 272-284, "
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
        o.append(f"| `{base_nome(c[0])}` | {c[1]} | `{c[2]}` | {c[4]} | {c[5]} | {c[6]} |")
    o += ["", "## Conteggi", "", "| File | Record dalla dimensione | Righe fisiche | Decodificati | Negli attesi |",
          "| --- | ---: | ---: | ---: | ---: |"]
    for r in uscite["conteggi.tsv"].splitlines()[1:]:
        c = r.split("\t")
        o.append(f"| `{base_nome(c[0])}` | {c[1]} | {c[2]} | {c[3]} | {c[4]} |")
    o += ["", "## Limiti", "",
          "- Il riempimento delle righe ASCII corte e' una scelta, non un fatto del sorgente.",
          "- Le fixture descrivono i byte dei file del repository; il comportamento dei programmi su questi dati "
          "(oracle, #9) e il caricamento nei file indicizzati (issue successiva) sono fuori ambito.",
          "- Gli attesi a mano coprono alcuni record per file (primo, ultimo, negativi, anomali, uno per tipo "
          "dell'export, i record con differenze ASCII/EBCDIC); gli altri record sono coperti dai controlli d'insieme "
          "(totali, chiavi, ricodifica) e dal confronto con le fixture versionate.", ""]
    return "\n".join(o)
