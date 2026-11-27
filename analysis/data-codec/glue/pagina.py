"""Pagina di codici del profilo zos-ebcdic: i file di app/data/EBCDIC/ distinguono 037 da 1047? (issue #23)

Uso: pagina.py LEGACY CONTRATTI OUT
  LEGACY     radice del legacy (volume sensibile alle maiuscole, sola lettura)
  CONTRATTI  docs/legacy-map/data-contract/contratti/
  OUT        riceve pagina.tsv (ogni occorrenza di un byte distintivo, con il campo che la contiene) e
             pagina-esito.tsv (conteggi per file e conclusione)

Le due pagine candidate differiscono in sei byte (tabella DISTINTIVI, da ICU ibm-1047_P100-1995 e dalla
tabella 037 di Python, confrontate byte per byte: vedi codifica.md). Un byte distintivo dice qualcosa sulla
pagina solo se sta in un campo alfanumerico; dentro un campo binario o packed e' un numero. Per questo ogni
occorrenza si colloca nel campo del tracciato che la contiene. Nessun valore viene decodificato: si usa
solo la posizione (questa analisi non e' la decodifica dei file di esempio, che e' #5).

Tracciati: solo i file in cui compare almeno un byte distintivo hanno bisogno di un tracciato. Oggi e' il
solo AWS.M2.CARDDEMO.EXPORT.DATA.PS (record di 500 byte, contratto CVEXPORT.EXPORT-RECORD, area scelta dal
tipo di record secondo CBEXPORT.cbl). Un'occorrenza in un altro file fa fallire l'analisi: va dichiarato il
tracciato prima di concludere.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comune import leggi_tsv, scrivi_tsv  # noqa: E402

# byte: (carattere in 037, carattere in 1047)
DISTINTIVI = {
    0x5F: ("¬", "^"),
    0xAD: ("Ý", "["),
    0xB0: ("^", "¬"),
    0xBA: ("[", "Ý"),
    0xBB: ("]", "¨"),
    0xBD: ("¨", "]"),
}

EXPORT = "AWS.M2.CARDDEMO.EXPORT.DATA.PS"
# Tipo di record (EXPORT-REC-TYPE, byte 0, in EBCDIC uguale nelle due pagine) -> area di EXPORT-RECORD.
# Fonte: app/cbl/CBEXPORT.cbl, riga del MOVE del tipo e riga del primo campo dell'area (verificate sotto).
TIPI_EXPORT = {
    "C": (274, 282, "EXP-CUST-ID", "EXPORT-CUSTOMER-DATA"),
    "A": (343, 351, "EXP-ACCT-ID", "EXPORT-ACCOUNT-DATA"),
    "X": (407, 415, "EXP-XREF-CARD-NUM", "EXPORT-CARD-XREF-DATA"),
    "T": (462, 470, "EXP-TRAN-ID", "EXPORT-TRANSACTION-DATA"),
    "D": (527, 535, "EXP-CARD-NUM", "EXPORT-CARD-DATA"),
}


def _verifica_cbexport(legacy):
    with open(os.path.join(legacy, "app/cbl/CBEXPORT.cbl"), "rb") as f:
        righe = f.read().decode("latin-1").split("\n")
    for tipo, (r_tipo, r_campo, campo, _area) in TIPI_EXPORT.items():
        if f"MOVE '{tipo}' TO EXPORT-REC-TYPE" not in righe[r_tipo - 1]:
            raise SystemExit(f"ERRORE [pagina] CBEXPORT.cbl:{r_tipo}: non contiene MOVE '{tipo}' TO EXPORT-REC-TYPE")
        if f"TO {campo}" not in righe[r_campo - 1]:
            raise SystemExit(f"ERRORE [pagina] CBEXPORT.cbl:{r_campo}: non contiene TO {campo}")


def _campi(contratti, nome):
    _, righe = leggi_tsv(os.path.join(contratti, nome + ".tsv"))
    return [r for r in righe if r["tipo"] == "elementare"]


def _categoria(r):
    if r["usage"] == "DISPLAY" and r["pic"].startswith("X"):
        return "alfanumerico"
    return {"DISPLAY": "display", "COMP-3": "comp-3", "COMP": "comp"}[r["usage"]]


def main(legacy, contratti, out):
    _verifica_cbexport(legacy)
    campi = _campi(contratti, "CVEXPORT.EXPORT-RECORD")
    for tipo, (_, _, campo, area) in TIPI_EXPORT.items():
        if not any(r["campo"] == campo and r["area"] == area for r in campi):
            raise SystemExit(f"ERRORE [pagina] {campo} non e' nell'area {area} del contratto CVEXPORT")
    cartella = os.path.join(legacy, "app/data/EBCDIC")
    occorrenze, esiti = [], []
    for nome in sorted(os.listdir(cartella)):
        p = os.path.join(cartella, nome)
        if not os.path.isfile(p) or nome.startswith("."):
            continue
        with open(p, "rb") as f:
            dati = f.read()
        trovati = [(i, b) for i, b in enumerate(dati) if b in DISTINTIVI]
        in_alfa = 0
        if trovati and nome != EXPORT:
            raise SystemExit(f"ERRORE [pagina] {nome}: {len(trovati)} byte distintivi in un file senza tracciato dichiarato")
        for i, b in trovati:
            rec, off = divmod(i, 500)
            tipo = bytes([dati[rec * 500]]).decode("cp037")
            if tipo not in TIPI_EXPORT:
                raise SystemExit(f"ERRORE [pagina] {nome} record {rec + 1}: tipo di record sconosciuto {tipo!r}")
            area = TIPI_EXPORT[tipo][3]
            cont = [r for r in campi if int(r["offset"]) <= off < int(r["offset"]) + int(r["lunghezza"])
                    and r["area"] in ("-", area)]
            # il campo piu' interno: quello dell'area, se c'e', altrimenti quello del record base
            cont.sort(key=lambda r: (r["area"] == "-", int(r["lunghezza"])))
            if not cont:
                raise SystemExit(f"ERRORE [pagina] {nome} record {rec + 1} posizione {off}: nessun campo")
            c = cont[0]
            cat = _categoria(c)
            in_alfa += cat == "alfanumerico"
            occorrenze.append({"file": nome, "record": rec + 1, "posizione": off, "byte": f"{b:02X}",
                               "in_037": DISTINTIVI[b][0].encode("unicode_escape").decode("ascii"),
                               "in_1047": DISTINTIVI[b][1].encode("unicode_escape").decode("ascii"),
                               "tipo_record": tipo, "campo": c["campo"], "pic": c["pic"], "usage": c["usage"],
                               "categoria": cat})
        esiti.append({"file": nome, "byte": len(dati), "distintivi": len(trovati), "in_alfanumerici": in_alfa})
    scrivi_tsv(os.path.join(out, "pagina.tsv"),
               ["file", "record", "posizione", "byte", "in_037", "in_1047", "tipo_record", "campo", "pic", "usage",
                "categoria"], occorrenze)
    tot_alfa = sum(e["in_alfanumerici"] for e in esiti)
    conclusione = "037-convenzione" if tot_alfa == 0 else "da-decidere-sui-dati"
    esiti.append({"file": "CONCLUSIONE", "byte": "-", "distintivi": sum(e["distintivi"] for e in esiti),
                  "in_alfanumerici": conclusione})
    scrivi_tsv(os.path.join(out, "pagina-esito.tsv"), ["file", "byte", "distintivi", "in_alfanumerici"], esiti)
    print(f"pagina di codici: {len(occorrenze)} byte distintivi, {tot_alfa} in campi alfanumerici -> {conclusione}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("uso: pagina.py LEGACY CONTRATTI OUT")
    main(*sys.argv[1:])
