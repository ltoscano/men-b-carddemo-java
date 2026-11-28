"""Documento generato docs/legacy-map/oracle-dati.md (issue #53). Nessuna guardia qui: solo testo dai riepiloghi."""
import hashlib
import os

import oracle_dati as od
from comune import da_esa


def cella(x):
    return str(x).replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ")


def riga(*celle):
    return "| " + " | ".join(cella(c) for c in celle) + " |"


def controprova(cartella, dd):
    """Righe del file scritto a mano della controprova (solo per citarle nel documento)."""
    p = os.path.join(cartella, "attesi", dd + ".controprova.tsv")
    if not os.path.isfile(p):
        return []
    with open(p, encoding="utf-8") as f:
        righe = [l.rstrip("\n").split("\t") for l in f if l.strip() and not l.startswith("#")]
    return [dict(zip(righe[0], r)) for r in righe[1:]]


def testo(ascii_esa):
    return da_esa(ascii_esa).decode("latin-1")


def documento(ing, riepiloghi):
    out = ["# File indicizzati nell'oracle: record nel profilo GnuCOBOL (issue #53)", "",
           "Documento generato da `./analysis/run.sh oracle-dati` (`analysis/oracle-dati/`): non modificarlo a mano. "
           "Il caricamento nel file indicizzato e la rilettura sono il passo `./oracle/run.sh dati` "
           "(`oracle/dati/`, `oracle/README.md`).", "",
           "## Cosa si fa", "",
           "Per ogni riga della tabella scritta a mano `analysis/oracle-dati/tabella.tsv` il file che il JCL carica nel "
           "KSDS (`REPRO INFILE`) si porta dal profilo `zos-ebcdic` al profilo `oracle-gnucobol` **campo per campo**: "
           "decodifica con il codec di #23 (`analysis/data-codec/glue/codec.py`) guidato dal contratto di #3 attraverso "
           "l'adattatore di #43 (`analysis/data-sentinelle/glue/controlli.py`), entrambi importati e non modificati, poi "
           "codifica del valore nel profilo dell'oracle. Nessuna conversione di caratteri sull'intero record. Un campo "
           "non valido, non in rappresentazione canonica (la ricodifica lo normalizzerebbe) o non ricodificabile ferma "
           "la generazione. Nessun valore riparato, nessun campo normalizzato, `FILLER` compreso.", "",
           "**Decisione sul contenuto (delegata, issue #53).** I due file di esempio dei conti non concordano nel record "
           "con chiave 49 (`ACCT-ADDR-ZIP`, `docs/legacy-map/fixture.md`). Si carica il contenuto del file EBCDIC, "
           "perche' e' quello che `app/jcl/ACCTFILE.jcl` carica nel KSDS (`REPRO INFILE(ACCTDATA)`, DD alle righe "
           "56-57). Il file ASCII serve da controprova.", "",
           "## Tabella dei file", "",
           riga("DD", "origine", "contratto", "chiave (KEYS)", "record (RECORDSIZE)", "controprova", "uscita"),
           riga("---", "---", "---", "---", "---", "---", "---")]
    for voce, _, _ in riepiloghi:
        out.append(riga(voce["dd"], f"`{voce['origine']}`", voce["contratto"],
                        f"{voce['chiave_lunghezza']} byte dall'offset {voce['chiave_offset']} (`{voce['rif_chiave']}`)",
                        f"{voce['lunghezza_record']} byte (`{voce['rif_lunghezza']}`)", f"`{voce['controprova']}`",
                        f"`analysis/oracle-dati/out/{voce['uscita']}`"))
    for voce, campi, dati in riepiloghi:
        L, a, k = voce["lunghezza_record"], voce["chiave_offset"], voce["chiave_lunghezza"]
        n = len(dati) // L
        recs = [dati[i:i + L] for i in range(0, len(dati), L)]
        con_segno = [c for c in campi if c["categoria"] == "display-con-segno"]
        negativi = 0
        for r in recs:
            for c in con_segno:
                v = od.codec.decodifica(od.ORACLE, c["categoria"], c["variante"], r, c["offset"]).valore
                negativi += v < 0
        out += ["", f"## {voce['dd']}", "",
                f"- `{voce['uscita']}`: {n} record di {L} byte senza terminatori ({len(dati)} byte), nell'ordine del "
                f"file d'origine; SHA-256 `{hashlib.sha256(dati).hexdigest()}`.",
                f"- Prima chiave `{recs[0][a:a + k].decode('latin-1')}`, ultima `{recs[-1][a:a + k].decode('latin-1')}`; "
                f"elenco completo (record, chiave, SHA-256 del record) in `{voce['dd']}.elenco.tsv`.",
                f"- Campi DISPLAY con segno: {len(con_segno)} per record, {len(con_segno) * n} in tutto, di cui "
                f"**{negativi} negativi**. Questo file non esercita il segno negativo: ogni ultimo byte di un importo e' "
                f"a zona C nel file d'origine e diventa uno dei caratteri positivi `{{` `A`-`I` nell'oracle.",
                "- Ordine delle chiavi. La chiave e' numerica `DISPLAY` senza segno (`9(11)`): cifre `F0`-`F9` in "
                "EBCDIC, `30`-`39` in ASCII, nello stesso ordine. Per questo l'ordine di chiave dell'oracle coincide con "
                "quello del mainframe per questo file. Non vale in generale per chiavi alfanumeriche (lettere, minuscole, "
                "spazi: le due collazioni differiscono, `oracle/README.md`).", "",
                "Campi (contratto, vista base) e trasformazione:", "",
                riga("campo", "offset", "byte", "categoria", "profilo zos-ebcdic -> oracle-gnucobol"),
                riga("---", "---", "---", "---", "---")]
        regola = {"alfanumerico": "carattere della pagina 037 -> stesso carattere in ISO-8859-1",
                  "display-senza-segno": "cifre Fd -> 3d",
                  "display-con-segno": "cifre Fd -> 3d; ultimo byte C/D d -> carattere del segno (-fsign=EBCDIC)"}
        for c in campi:
            out.append(riga(c["nome"], c["offset"], c["lunghezza"], f"{c['categoria']} {c['variante']}",
                            regola.get(c["categoria"], c["categoria"])))
        cp = controprova(ing.cartella, voce["dd"])
        out += ["", "Controprova con il file ASCII: i record prodotti coincidono byte per byte con le righe di "
                f"`{voce['controprova']}` senza terminatori tranne, esattamente, questi byte "
                f"(`analysis/oracle-dati/attesi/{voce['dd']}.controprova.tsv`, scritto a mano):", "",
                riga("record", "chiave", "campo", "byte", "file ASCII", "prodotto (dal file EBCDIC)"),
                riga("---", "---", "---", "---", "---", "---")]
        for r in cp:
            o = int(r["offset"])
            out.append(riga(r["record"], r["chiave"], r["campo"], f"{o + 1}-{o + int(r['lunghezza'])}",
                            f"`{r['ascii']}` ({testo(r['ascii'])!r})", f"`{r['prodotto']}` ({testo(r['prodotto'])!r})"))
    out += ["", "## Controlli (tutti superati alla generazione)", "",
            riga("controllo", "cosa", "dove"), riga("---", "---", "---"),
            riga("1", "chiave e lunghezza della tabella rilette dal JCL (KEYS, RECORDSIZE dello stesso DEFINE CLUSTER, "
                      "REPRO dal file d'origine al cluster) e confrontate con il contratto", "`glue/oracle_dati.py` J"),
            riga("2", "ogni campo prodotto, ridecodificato nel profilo dell'oracle, ha stato e valore della fixture EBCDIC "
                      "di #5 (`analysis/data-fixtures/out/`, letta e non rigenerata)", "`glue/oracle_dati.py` F"),
            riga("3", "controprova byte per byte con il file ASCII, con la sola differenza scritta a mano", "`controprova.sh`, "
                      "solo utility POSIX (`tr`, `cmp`, `od`, `awk`, `wc`): i byte del file si leggono per una via "
                      "indipendente dalla colla"),
            riga("4", "record quanti nel file d'origine, chiavi uniche e strettamente crescenti nell'ordine del file "
                      "(altrimenti la generazione si ferma: needs-spec-update)", "`glue/oracle_dati.py` G08-G09, K"),
            riga("5", "cinque record scritti a mano prima della colla (primo, ultimo, chiave 49, due a scelta)",
                 "`attesi/<dd>.record.tsv`, `glue/oracle_dati.py` A"),
            "", "Ogni controllo ha le sue prove negative (`./analysis/run.sh oracle-dati --check`).", ""]
    return "\n".join(out)
