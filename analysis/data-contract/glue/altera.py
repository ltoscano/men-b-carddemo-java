#!/usr/bin/env python3
"""Alterazioni per le prove negative di check.sh (issue #3). Ogni alterazione lavora su una copia ("mondo") con
le cartelle out/ (output dell'analisi), docs/ (docs/legacy-map/data-contract) ed exp/ (attesi scritti a mano),
e deve far fallire un controllo preciso.

Uso: altera.py TIPO MONDO
"""
import os
import sys


def leggi(p):
    return open(p, encoding="utf-8").read()


def scrivi(p, s):
    open(p, "w", encoding="utf-8").write(s)


def sostituisci(p, vecchio, nuovo, conta=1):
    s = leggi(p)
    if s.count(vecchio) < 1:
        raise SystemExit(f"alterazione non applicabile a {p}: '{vecchio}' assente")
    scrivi(p, s.replace(vecchio, nuovo, conta))


def righe_tsv(p):
    return leggi(p).split("\n")


def tsv_modifica(p, filtro, modifica):
    """Applica modifica(campi) alle righe dati di un TSV per cui filtro(campi) e' vero; almeno una."""
    rr = righe_tsv(p)
    testa = None
    n = 0
    for i, r in enumerate(rr):
        if not r or r.startswith("#"):
            continue
        c = r.split("\t")
        if testa is None:
            testa = c
            continue
        d = dict(zip(testa, c))
        if filtro(d):
            nuovo = modifica(d)
            rr[i] = None if nuovo is None else "\t".join(nuovo[k] for k in testa)
            n += 1
    if n == 0:
        raise SystemExit(f"alterazione non applicabile a {p}: nessuna riga selezionata")
    scrivi(p, "\n".join(r for r in rr if r is not None))


def scambia_campi(p, a, b):
    """Scambia i nomi (e i percorsi) di due campi di un contratto, lasciando posizioni e lunghezze."""
    def f(d):
        nome = b if d["campo"] == a else a
        d["percorso"] = d["percorso"].rsplit("/", 1)[0] + "/" + nome
        d["campo"] = nome
        return d
    tsv_modifica(p, lambda d: d["campo"] in (a, b), f)


def main(tipo, m):
    out, docs, exp = (os.path.join(m, x) for x in ("out", "docs", "exp"))
    con = os.path.join(docs, "contratti")
    cens = os.path.join(docs, "censimento.tsv")
    if tipo == "contratto-cancellato":
        os.remove(os.path.join(con, "CVTRA05Y.TRAN-RECORD.tsv"))
    elif tipo == "radice-cancellata":
        tsv_modifica(cens, lambda d: d["sorgente"] == "app/cpy/CVTRA05Y.cpy", lambda d: None)
    elif tipo == "fd-cancellata":
        tsv_modifica(cens, lambda d: d["tipo"] == "FD:VBRC-FILE", lambda d: None)
    elif tipo == "cbact01c-solo-fd":
        # il contratto della struttura di lavoro contiene solo il campo generico dell'FD
        for n in ("CBACT01C.VBRC-REC1.tsv", "CBACT01C.VBRC-REC2.tsv"):
            src = righe_tsv(os.path.join(con, "CBACT01C.VBR-REC.tsv"))
            scrivi(os.path.join(con, n), "\n".join(src))
    elif tipo == "cbact01c-solo-fd-censimento":
        # le strutture di lavoro declassate e i loro contratti tolti: per il file variabile resta solo l'01 generico dell'FD
        def f(d):
            d["classificazione"], d["contratto"] = "area-di-lavoro", "-"
            return d
        tsv_modifica(cens, lambda d: d["radice"] in ("VBRC-REC1", "VBRC-REC2"), f)
        for n in ("CBACT01C.VBRC-REC1.tsv", "CBACT01C.VBRC-REC2.tsv"):
            os.remove(os.path.join(con, n))
        tsv_modifica(os.path.join(docs, "contratti.tsv"), lambda d: d["radice"] in ("VBRC-REC1", "VBRC-REC2"), lambda d: None)
    elif tipo == "campi-scambiati":
        scambia_campi(os.path.join(con, "CVACT01Y.ACCOUNT-RECORD.tsv"), "ACCT-CREDIT-LIMIT", "ACCT-CASH-CREDIT-LIMIT")
    elif tipo == "campi-scambiati-ovunque":
        # scambio coerente in XML grezzo, tracciati e contratto: resta il confronto con il sorgente e con gli attesi
        p = os.path.join(out, "cb2xml", "CVACT01Y.xml")
        s = leggi(p).replace('"ACCT-CREDIT-LIMIT"', '"@@"').replace('"ACCT-CASH-CREDIT-LIMIT"', '"ACCT-CREDIT-LIMIT"').replace('"@@"', '"ACCT-CASH-CREDIT-LIMIT"')
        scrivi(p, s)
        def f(d):
            d["nome"] = "ACCT-CASH-CREDIT-LIMIT" if d["nome"] == "ACCT-CREDIT-LIMIT" else "ACCT-CREDIT-LIMIT"
            d["percorso"] = d["percorso"].rsplit("/", 1)[0] + "/" + d["nome"]
            return d
        tsv_modifica(os.path.join(out, "tracciati.tsv"), lambda d: d["id"] == "CVACT01Y" and d["nome"] in ("ACCT-CREDIT-LIMIT", "ACCT-CASH-CREDIT-LIMIT"), f)
        scambia_campi(os.path.join(con, "CVACT01Y.ACCOUNT-RECORD.tsv"), "ACCT-CREDIT-LIMIT", "ACCT-CASH-CREDIT-LIMIT")
    elif tipo == "campi-scambiati-senza-attesi":
        # due campi di 50 byte scambiati in un contratto che non ha una tabella attesa scritta a mano
        scambia_campi(os.path.join(con, "CVTRA05Y.TRAN-RECORD.tsv"), "TRAN-MERCHANT-NAME", "TRAN-MERCHANT-CITY")
    elif tipo == "scala-alterata":
        def f(d):
            d["cifre_intere"], d["cifre_decimali"] = "9", "3"
            return d
        tsv_modifica(os.path.join(con, "CVACT01Y.ACCOUNT-RECORD.tsv"), lambda d: d["campo"] == "ACCT-CURR-BAL", f)
    elif tipo == "scala-alterata-con-pic":
        def f(d):
            d["pic"], d["cifre_intere"], d["cifre_decimali"] = "S9(9)V999", "9", "3"
            return d
        tsv_modifica(os.path.join(con, "CVACT01Y.ACCOUNT-RECORD.tsv"), lambda d: d["campo"] == "ACCT-CURR-BAL", f)
    elif tipo == "segno-alterato":
        def f(d):
            d["segno"] = "-"
            return d
        tsv_modifica(os.path.join(con, "CVTRA01Y.TRAN-CAT-BAL-RECORD.tsv"), lambda d: d["campo"] == "TRAN-CAT-BAL", f)
    elif tipo == "usage-alterato":
        def f(d):
            d["usage"] = "DISPLAY"
            return d
        tsv_modifica(os.path.join(con, "CVEXPORT.EXPORT-RECORD.tsv"), lambda d: d["campo"] == "EXP-ACCT-CURR-BAL", f)
    elif tipo == "posizione-alterata":
        def f(d):
            d["offset"] = str(int(d["offset"]) + 1)
            return d
        tsv_modifica(os.path.join(con, "CVTRA05Y.TRAN-RECORD.tsv"), lambda d: d["campo"] == "TRAN-DESC", f)
    elif tipo == "lunghezza-alterata":
        def f(d):
            d["lunghezza"] = "9"
            return d
        tsv_modifica(os.path.join(con, "CVTRA03Y.TRAN-TYPE-RECORD.tsv"), lambda d: d["campo"] == "FILLER", f)
    elif tipo == "ridefinizione-accorciata":
        def f(d):
            d["lunghezza"] = str(int(d["lunghezza"]) - 1)
            return d
        tsv_modifica(os.path.join(con, "CVEXPORT.EXPORT-RECORD.tsv"),
                     lambda d: d["campo"] == "EXPORT-ACCOUNT-DATA" or (d["area"] == "EXPORT-ACCOUNT-DATA" and d["campo"] == "FILLER"), f)
    elif tipo == "lunghezza-attesa-alterata":
        sostituisci(os.path.join(exp, "lunghezze.tsv"), "CVTRA05Y\tTRAN-RECORD\t350", "CVTRA05Y\tTRAN-RECORD\t351")
    elif tipo == "chiave-spostata":
        def f(d):
            d["offset"] = "1"
            return d
        tsv_modifica(os.path.join(docs, "chiavi.tsv"),
                     lambda d: d["dataset"] == "AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS" and d["fonte"] == "JCL DEFINE CLUSTER", f)
    elif tipo == "chiave-alternativa-spostata":
        def f(d):
            d["offset"] = "26"
            return d
        tsv_modifica(os.path.join(docs, "chiavi.tsv"), lambda d: d["nome"] == "FD-XREF-ACCT-ID", f)
    elif tipo == "chiave-attesa-spostata":
        sostituisci(os.path.join(exp, "chiavi-dataset.tsv"), "AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS\tprimaria\t-\t0\t11",
                    "AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS\tprimaria\t-\t1\t11")
    elif tipo == "discordanza-cancellata":
        p = os.path.join(docs, "discordanze.md")
        s = leggi(p).replace("`chiave-unicita:AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX:CBACT04C`", "la discordanza dell'indice alternativo")
        scrivi(p, s)
    elif tipo == "discordanza-non-rilevata":
        tsv_modifica(os.path.join(out, "discordanze-rilevate.tsv"), lambda d: d["id"].startswith("chiave-allineamento:AWS.M2.CARDDEMO.EXPORT"), lambda d: None)
    elif tipo == "discordanza-inventata":
        p = os.path.join(docs, "discordanze.md")
        scrivi(p, leggi(p) + "\n- `chiave-unicita:AWS.M2.CARDDEMO.TRANSACT.VSAM.AIX:CBTRN02C` (inventata)\n")
    elif tipo == "relazione-lunghezza":
        def f(d):
            d["lunghezza_da"] = "40"
            return d
        tsv_modifica(os.path.join(docs, "relazioni.tsv"), lambda d: d["da"] == "CBACT01C.VBRC-REC2", f)
    elif tipo == "relazione-mancante":
        tsv_modifica(os.path.join(docs, "relazioni.tsv"), lambda d: d["programma"] == "app/cbl/CBACT04C.cbl" and d["righe"] == "500", lambda d: None)
    elif tipo == "relazione-trasferita":
        def f(d):
            d["trasferita"] = "13"
            return d
        tsv_modifica(os.path.join(docs, "relazioni.tsv"), lambda d: d["da"] == "CBACT01C.VBR-REC" and d["righe"] == "290", f)
    elif tipo == "non-tracciato-falso":
        def f(d):
            d["classificazione"], d["contratto"] = "non-tracciato", "-"
            return d
        tsv_modifica(cens, lambda d: d["sorgente"] == "app/cpy/CVACT02Y.cpy", f)
    elif tipo == "riga-citata-errata":
        def f(d):
            d["riga"] = "5"
            return d
        tsv_modifica(cens, lambda d: d["sorgente"] == "app/cpy/CVACT01Y.cpy", f)
    elif tipo == "assegnazione-errata":
        def f(d):
            d["riga_dsn"] = "32"
            return d
        tsv_modifica(os.path.join(docs, "assegnazioni.tsv"), lambda d: d["programma"] == "app/cbl/CBACT04C.cbl" and d["file"] == "XREF-FILE", f)
    elif tipo == "attesi-svuotati":
        p = os.path.join(exp, "campi.tsv")
        scrivi(p, "\n".join(r for r in righe_tsv(p) if r.startswith("#") or r.startswith("contratto\t")) + "\n")
    elif tipo == "lunghezza-attesa-cancellata":
        tsv_modifica(os.path.join(exp, "lunghezze.tsv"), lambda d: d["copybook"] == "CVEXPORT", lambda d: None)
    elif tipo == "discordanza-attesa-cancellata":
        tsv_modifica(os.path.join(exp, "discordanze-attese.tsv"), lambda d: d["id"].startswith("chiave-unicita:"), lambda d: None)
    elif tipo == "relazione-move-mancante":
        tsv_modifica(os.path.join(docs, "relazioni.tsv"), lambda d: d["programma"] == "app/cbl/CBTRN03C.cbl" and d["righe"] == "295", lambda d: None)
    elif tipo == "record-declassato":
        # un record letto da file (CUSTREC, spostato da CBSTM03A) declassato ad area di lavoro, con il contratto tolto
        def f(d):
            d["classificazione"], d["contratto"] = "area-di-lavoro", "-"
            return d
        tsv_modifica(cens, lambda d: d["sorgente"] == "app/cpy/CUSTREC.cpy", f)
        os.remove(os.path.join(con, "CUSTREC.CUSTOMER-RECORD.tsv"))
        tsv_modifica(os.path.join(docs, "contratti.tsv"), lambda d: d["contratto"] == "CUSTREC.CUSTOMER-RECORD", lambda d: None)
    elif tipo == "frammento-accorciato":
        def f(d):
            d["frammento"] = "152-159"
            return d
        tsv_modifica(cens, lambda d: d["radice"] == "WS-ERROR-RECORD", f)

        def g(d):
            d["lunghezza_da"] = "87"
            return d
        tsv_modifica(os.path.join(docs, "relazioni.tsv"), lambda d: d["da"] == "CBIMPORT.WS-ERROR-RECORD", g)
    elif tipo in ("composizione-eliminata", "timestamp-eliminato", "timestamp-cbact04c-eliminato"):
        prog, rad = {"composizione-eliminata": ("CBTRN02C", "WS-VALIDATION-TRAILER"), "timestamp-eliminato": ("CBTRN02C", "DB2-FORMAT-TS"),
                     "timestamp-cbact04c-eliminato": ("CBACT04C", "DB2-FORMAT-TS")}[tipo]
        tsv_modifica(cens, lambda d: d["radice"] == rad and d["sorgente"] == f"app/cbl/{prog}.cbl", lambda d: None)
        tsv_modifica(os.path.join(docs, "relazioni.tsv"), lambda d: d["da"] == f"{prog}.{rad}", lambda d: None)
    elif tipo == "trasferimento-tolto":
        tsv_modifica(os.path.join(out, "fonti", "trasferimenti.tsv"),
                     lambda d: d["programma"] == "app/cbl/CBACT04C.cbl" and d["riga"] == "497", lambda d: None)
    elif tipo == "non-coperto-spostato":
        def f(d):
            d["riga"], d["tipo"] = "464", "aritmetica (COMPUTE)"
            return d
        tsv_modifica(os.path.join(out, "fonti", "non-coperti.tsv"),
                     lambda d: d["programma"] == "app/cbl/CBACT04C.cbl" and d["destinazione"] == "TRAN-AMT", f)
    elif tipo == "sezione-errata":
        def f(d):
            d["tipo"] = "LINKAGE"
            return d
        tsv_modifica(cens, lambda d: d["radice"] == "VBRC-REC1", f)
    elif tipo == "file-contratto-scambiato":
        scambio = {"CVTRA01Y.TRAN-CAT-BAL-RECORD": "CVTRA02Y.DIS-GROUP-RECORD", "CVTRA02Y.DIS-GROUP-RECORD": "CVTRA01Y.TRAN-CAT-BAL-RECORD"}

        def f(d):
            d["contratto"] = scambio[d["contratto"]]
            return d
        tsv_modifica(os.path.join(docs, "file.tsv"), lambda d: d["contratto"] in scambio, f)
    elif tipo == "voce-tracciato-tolta":
        tsv_modifica(os.path.join(out, "tracciati.tsv"), lambda d: d["id"] == "CVACT01Y" and d["nome"] == "FILLER", lambda d: None)
    elif tipo == "composizione-spostata":
        def f(d):
            d["offset_nel_record"] = "351"
            return d
        tsv_modifica(os.path.join(docs, "composizioni.tsv"), lambda d: d["campo"] == "WS-VALIDATION-FAIL-REASON", f)
    elif tipo == "xml-alterato":
        sostituisci(os.path.join(out, "cb2xml", "CVTRA02Y.xml"), '"DIS-INT-RATE"', '"DIS-INT-RATE-X"')
    elif tipo == "xml-cancellato":
        os.remove(os.path.join(out, "cb2xml", "CVACT01Y.xml"))
    elif tipo == "log-cancellato":
        os.remove(os.path.join(out, "cb2xml", "CSSETATY.log"))
    elif tipo == "fonte-cancellata":
        os.remove(os.path.join(out, "fonti", "listcat.tsv"))
    else:
        raise SystemExit(f"tipo di alterazione sconosciuto: {tipo}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
