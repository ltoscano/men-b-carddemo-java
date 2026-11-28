"""Prove negative della colla dei record per l'oracle (issue #53).

Uso: negativi.py LEGACY DC FIXTURE CARTELLA [--limite SECONDI]
Ogni prova altera UNA cosa: una copia privata degli ingressi (tabella, attesi a mano, file d'origine, JCL, contratto,
fixture), oppure per la sola durata della prova un passo della generazione, oppure il file scritto in una cartella
temporanea prima della verifica. Esegue generazione, scrittura e verifica come esegui.py e pretende che fallisca CON IL
CODICE DICHIARATO. Una prova che fallisce per un altro motivo, o non fallisce, e' una prova negativa fallita.
Inventario finale (censimento delle guardie): ogni chiamata es.errore("Xnn", ...) di oracle_dati.py e' una guardia;
ognuna deve essere scattata in almeno una prova superata che pretende il suo codice, e ogni chiamata deve avere un
codice letterale (una chiamata con il codice in una variabile non sarebbe censibile: e' un errore dell'inventario).
Esce con 0 solo se tutte le prove sono superate e ogni guardia e' coperta; 2 per un errore operativo o per il limite di
tempo (900 s).
"""
import contextlib
import os
import re
import shutil
import signal
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_dati as od  # noqa: E402

LIMITE = 900
ORIG = "app/data/EBCDIC/AWS.M2.CARDDEMO.ACCTDATA.PS"
JCL = "app/jcl/ACCTFILE.jcl"
CONTR = "CVACT01Y.ACCOUNT-RECORD"
FIX = "AWS.M2.CARDDEMO.ACCTDATA.PS"
ATT = "ACCTFILE.record.tsv"
L = 300


@contextlib.contextmanager
def sostituisci(oggetto, nome, valore):
    vecchio = getattr(oggetto, nome)
    setattr(oggetto, nome, valore)
    try:
        yield
    finally:
        setattr(oggetto, nome, vecchio)


# --- alterazioni degli ingressi (una per prova) ------------------------------------------------------------------------

def cambia_tab(ing, colonna, valore):
    testa = ing.tabella[0].split("\t")
    c = ing.tabella[1].split("\t")
    if c[testa.index(colonna)] == valore:
        raise ValueError(f"{colonna} vale gia' {valore}")
    c[testa.index(colonna)] = valore
    ing.tabella[1] = "\t".join(c)


def cambia_riga_jcl(ing, n, vecchio, nuovo):
    righe = list(ing.testo(JCL))
    if vecchio not in righe[n - 1]:
        raise ValueError(f"'{vecchio}' assente dalla riga {n} di {JCL}")
    righe[n - 1] = righe[n - 1].replace(vecchio, nuovo)
    ing.testi[JCL] = righe


def cambia_byte_orig(ing, record, offset, byte):
    d = bytearray(ing.byte(ORIG))
    p = (record - 1) * L + offset
    if d[p] == byte:
        raise ValueError("byte gia' uguale")
    d[p] = byte
    ing.dati[ORIG] = bytes(d)


def cambia_contratto(ing, campo, colonna, valore):
    righe = ing.contratto(CONTR)
    r = [x for x in righe if x["campo"] == campo]
    if len(r) != 1 or r[0][colonna] == valore:
        raise ValueError(f"{campo}.{colonna}: non alterabile in {valore}")
    r[0][colonna] = valore


def cambia_fixture(ing, vecchio, nuovo):
    t = ing.testo_fixture(FIX)
    if t.count(vecchio) < 1:
        raise ValueError(f"{vecchio!r} assente dalla fixture")
    ing.fixture[FIX] = t.replace(vecchio, nuovo, 1)


def righe_fixture(ing):
    return ing.testo_fixture(FIX).split("\n")


def riga_fixture(ing, n):
    righe = righe_fixture(ing)
    i = [k for k, l in enumerate(righe) if l.startswith(f"{n}\t")]
    if len(i) != 1:
        raise ValueError(f"record {n} della fixture")
    return righe, i[0]


def cambia_attesi(ing, vecchio, nuovo, conta=1):
    t = ing.attesi[ATT]
    if t.count(vecchio) < conta:
        raise ValueError(f"{vecchio!r} assente dagli attesi")
    ing.attesi[ATT] = t.replace(vecchio, nuovo, conta)


def righe_attesi_record(ing, record, f):
    """Applica f a ogni riga degli attesi del record (lista di colonne -> lista di colonne o None per toglierla)."""
    out, toccate = [], 0
    for l in ing.attesi[ATT].split("\n"):
        c = l.split("\t")
        if not l.startswith("#") and len(c) == 7 and c[0] == str(record):
            toccate += 1
            c = f(c)
            if c is None:
                continue
            l = "\t".join(c)
        out.append(l)
    if not toccate:
        raise ValueError(f"record {record} assente dagli attesi")
    ing.attesi[ATT] = "\n".join(out)


def col(i, v):
    def f(c):
        c = list(c)
        c[i] = v
        return c
    return f


# --- alterazioni del file scritto, prima della verifica -----------------------------------------------------------------

def dopo(f):
    return ("dopo", f)


def altera_rec(fun):
    def f(out):
        p = os.path.join(out, "ACCTFILE.rec")
        with open(p, "rb") as x:
            d = bytearray(x.read())
        d2 = fun(d)
        if d2 == d:
            raise ValueError("alterazione del file scritto senza effetto")
        with open(p, "wb") as x:
            x.write(bytes(d2))
    return f


def scambia_record(d, a, b):
    d = bytearray(d)
    ra, rb = d[(a - 1) * L:a * L], d[(b - 1) * L:b * L]
    d[(a - 1) * L:a * L], d[(b - 1) * L:b * L] = rb, ra
    return d


def byte_in(d, record, offset, valore):
    d = bytearray(d)
    d[(record - 1) * L + offset] = valore
    return d


def p_rimuovi_rec(out):
    os.remove(os.path.join(out, "ACCTFILE.rec"))


def p_elenco(out):
    p = os.path.join(out, "ACCTFILE.elenco.tsv")
    with open(p, encoding="utf-8") as f:
        t = f.read()
    t2 = t.replace("\n7\t00000000007\t", "\n7\t00000000070\t", 1)
    if t2 == t:
        raise ValueError("elenco non alterato")
    with open(p, "w", encoding="utf-8") as f:
        f.write(t2)


# --- passi della generazione sostituiti ---------------------------------------------------------------------------------

def codifica_che_fallisce(prof, cat, var, valore):
    if prof == od.ORACLE and cat == "display-con-segno":
        raise od.codec.CodificaErrore("prova negativa: codifica rifiutata")
    return od.codec.codifica(prof, cat, var, valore)


def codifica_lunga(prof, cat, var, valore):
    b = od.codec.codifica(prof, cat, var, valore)
    return b + b" " if prof == od.ORACLE and cat == "alfanumerico" else b


# --- elenco delle prove: (nome, codice atteso, preparazione) -------------------------------------------------------------

PROVE = [
    # tabella
    ("tabella-vuota", "T05", lambda ing: setattr(ing, "tabella", [])),
    ("tabella-intestazione", "T01", lambda ing: ing.tabella.__setitem__(0, ing.tabella[0].replace("uscita", "file"))),
    ("tabella-colonna-mancante", "T02", lambda ing: ing.tabella.__setitem__(1, ing.tabella[1].rsplit("\t", 1)[0])),
    ("tabella-chiave-non-numerica", "T03", lambda ing: cambia_tab(ing, "chiave_lunghezza", "undici")),
    ("tabella-dd-ripetuto", "T04", lambda ing: ing.tabella.append(ing.tabella[1])),
    ("tabella-uscita-diversa", "T06", lambda ing: cambia_tab(ing, "uscita", "ACCTFILE.dat")),
    ("tabella-solo-intestazione", "T07", lambda ing: setattr(ing, "tabella", ing.tabella[:1])),
    # controllo 1: tabella contro JCL e contratto (prima della generazione)
    ("tabella-chiave-diversa-dal-jcl", "J03", lambda ing: cambia_tab(ing, "chiave_lunghezza", "12")),
    ("tabella-lunghezza-diversa-dal-jcl", "J05", lambda ing: cambia_tab(ing, "lunghezza_record", "299")),
    ("tabella-lunghezza-diversa-dal-jcl-massimo", "J06", lambda ing: cambia_tab(ing, "lunghezza_record", "299")),
    ("tabella-lunghezza-diversa-dal-contratto", "J12", lambda ing: cambia_tab(ing, "lunghezza_record", "299")),
    ("jcl-keys-diverso", "J03", lambda ing: cambia_riga_jcl(ing, 40, "KEYS(11 0)", "KEYS(10 0)")),
    ("jcl-recordsize-medio-diverso", "J05", lambda ing: cambia_riga_jcl(ing, 41, "RECORDSIZE(300 300)", "RECORDSIZE(299 300)")),
    ("jcl-recordsize-massimo-diverso", "J06", lambda ing: cambia_riga_jcl(ing, 41, "RECORDSIZE(300 300)", "RECORDSIZE(300 301)")),
    ("rif-chiave-malformato", "J01", lambda ing: cambia_tab(ing, "rif_chiave", "ACCTFILE.jcl:40")),
    ("rif-jcl-diversi", "J07", lambda ing: cambia_tab(ing, "rif_lunghezza", "app/jcl/CARDFILE.jcl:41")),
    ("rif-chiave-senza-keys", "J02", lambda ing: cambia_tab(ing, "rif_chiave", "app/jcl/ACCTFILE.jcl:41")),
    ("rif-lunghezza-senza-recordsize", "J04", lambda ing: cambia_tab(ing, "rif_lunghezza", "app/jcl/ACCTFILE.jcl:40")),
    ("rif-oltre-la-fine", "J16", lambda ing: cambia_tab(ing, "rif_chiave", "app/jcl/ACCTFILE.jcl:999")),
    ("rif-jcl-assente", "J15", lambda ing: (cambia_tab(ing, "rif_chiave", "app/jcl/NESSUNO.jcl:40"),
                                            cambia_tab(ing, "rif_lunghezza", "app/jcl/NESSUNO.jcl:41"))),
    ("define-interrotto", "J08", lambda ing: cambia_riga_jcl(ing, 39, "          ) -", "/*")),
    ("repro-assente", "J09", lambda ing: cambia_riga_jcl(ing, 61, "REPRO INFILE", "COPY INFILE")),
    ("outfile-altro-dataset", "J10", lambda ing: cambia_riga_jcl(ing, 59, "ACCTDATA.VSAM.KSDS", "ALTRO.VSAM.KSDS")),
    # stesso contenuto (alias ACCDATA.PS, stessa impronta): solo il controllo sul JCL distingue il file caricato
    ("origine-alias-non-caricato-dal-jcl", "J11", lambda ing: cambia_tab(ing, "origine", "app/data/EBCDIC/AWS.M2.CARDDEMO.ACCDATA.PS")),
    ("contratto-lunghezza", "J12", lambda ing: cambia_contratto(ing, "ACCOUNT-RECORD", "lunghezza", "301")),
    ("contratto-senza-livello-01", "J14", lambda ing: cambia_contratto(ing, "ACCOUNT-RECORD", "livello", "02")),
    ("chiave-senza-campo", "J13", lambda ing: (cambia_tab(ing, "chiave_lunghezza", "12"),
                                               cambia_riga_jcl(ing, 40, "KEYS(11 0)", "KEYS(12 0)"))),
    # generazione
    ("contratto-inesistente", "G02", lambda ing: cambia_tab(ing, "contratto", "NESSUNO.RECORD")),
    ("contratto-buco", "G03", lambda ing: cambia_contratto(ing, "ACCT-ACTIVE-STATUS", "offset", "12")),
    ("contratto-copertura-corta", "G11", lambda ing: cambia_contratto(ing, "FILLER", "pic", "X(177)")
     or cambia_contratto(ing, "FILLER", "lunghezza", "177")),
    ("origine-non-multipla", "G01", lambda ing: ing.dati.__setitem__(ORIG, ing.byte(ORIG)[:-1])),
    ("origine-record-tolto", "F02", lambda ing: ing.dati.__setitem__(ORIG, ing.byte(ORIG)[:-L])),
    ("origine-vuota", "G10", lambda ing: ing.dati.__setitem__(ORIG, b"")),
    ("campo-numerico-non-valido", "G04", lambda ing: cambia_byte_orig(ing, 3, 0, 0x40)),
    ("segno-zona-F-non-canonico", "G05", lambda ing: cambia_byte_orig(ing, 5, 23, 0xF0)),
    ("codifica-rifiutata", "G06", lambda ing: sostituisci(od, "CODIFICA", codifica_che_fallisce)),
    ("codifica-lunghezza-sbagliata", "G07", lambda ing: sostituisci(od, "CODIFICA", codifica_lunga)),
    ("chiave-duplicata", "G08", lambda ing: ing.dati.__setitem__(
        ORIG, ing.byte(ORIG)[:2 * L] + ing.byte(ORIG)[L:2 * L] + ing.byte(ORIG)[3 * L:])),
    ("due-record-scambiati", "G09", lambda ing: ing.dati.__setitem__(
        ORIG, bytes(scambia_record(ing.byte(ORIG), 10, 11)))),
    # controllo 4 e file scritto
    ("file-scritto-assente", "K05", lambda ing: dopo(p_rimuovi_rec)),
    ("file-scritto-troncato", "K01", lambda ing: dopo(altera_rec(lambda d: d[:-1]))),
    ("file-scritto-record-tolto", "K02", lambda ing: dopo(altera_rec(lambda d: d[:-L]))),
    ("file-scritto-chiave-duplicata", "K03", lambda ing: dopo(altera_rec(lambda d: d[:2 * L] + d[L:2 * L] + d[3 * L:]))),
    ("file-scritto-record-scambiati", "K04", lambda ing: dopo(altera_rec(lambda d: scambia_record(d, 10, 11)))),
    ("elenco-alterato", "E01", lambda ing: dopo(p_elenco)),
    # controllo 2: fixture di #5
    ("fixture-assente", "F01", lambda ing: ing.fixture.__setitem__(FIX, None) or setattr(ing, "testo_fixture", lambda n: None)),
    ("fixture-altro-contratto", "F01", lambda ing: cambia_fixture(ing, "contratto CVACT01Y.ACCOUNT-RECORD", "contratto CVACT02Y.CARD-RECORD")),
    ("fixture-riga-malformata", "F06", lambda ing: cambia_fixture(ing, "\n7\t-\t300\t", "\nsette\t-\t300\t")),
    ("fixture-campo-malformato", "F07", lambda ing: cambia_fixture(ing, "\tACCT-ACTIVE-STATUS|valido|\"Y\"|E8\t",
                                                                   "\tACCT-ACTIVE-STATUS|valido\t")),
    ("fixture-record-ripetuto", "F08", lambda ing: ing.fixture.__setitem__(
        FIX, ing.testo_fixture(FIX) + "\n".join(l for l in righe_fixture(ing) if l.startswith("50\t")) + "\n")),
    ("fixture-record-in-meno", "F02", lambda ing: ing.fixture.__setitem__(
        FIX, "\n".join(l for l in righe_fixture(ing) if not l.startswith("50\t")))),
    ("fixture-campo-rinominato", "F03", lambda ing: cambia_fixture(ing, "\n8\t-\t300\t0\tbase\tACCT-ID|",
                                                                   "\n8\t-\t300\t0\tbase\tACCT-NUM|")),
    ("fixture-stato-diverso", "F04", lambda ing: cambia_fixture(ing, "\n9\t-\t300\t0\tbase\tACCT-ID|valido|",
                                                                "\n9\t-\t300\t0\tbase\tACCT-ID|non-valido|")),
    ("fixture-valore-diverso", "F05", lambda ing: cambia_fixture(ing, "ACCT-CURR-BAL|valido|194.00|", "ACCT-CURR-BAL|valido|194.01|")),
    ("prodotto-byte-numerico-alterato", "F05", lambda ing: dopo(altera_rec(lambda d: byte_in(d, 12, 20, 0x39)))),
    ("prodotto-byte-filler-alterato", "F05", lambda ing: dopo(altera_rec(lambda d: byte_in(d, 13, 200, 0x2E)))),
    ("prodotto-segno-negativo", "F05", lambda ing: dopo(altera_rec(lambda d: byte_in(d, 14, 23, 0x7D)))),
    ("prodotto-byte-non-valido", "F04", lambda ing: dopo(altera_rec(lambda d: byte_in(d, 15, 30, 0x20)))),
    # controllo 5: attesi a mano
    ("attesi-assenti", "A01", lambda ing: ing.attesi.pop(ATT)),
    ("attesi-colonne", "A02", lambda ing: righe_attesi_record(ing, 30, lambda c: c[:6])),
    ("attesi-offset-non-numerico", "A13", lambda ing: righe_attesi_record(ing, 30, col(3, "x"))),
    ("attesi-esadecimale-illeggibile", "A14", lambda ing: righe_attesi_record(ing, 30, col(6, "ZZ"))),
    ("attesi-quattro-record", "A03", lambda ing: righe_attesi_record(ing, 30, lambda c: None)),
    ("attesi-chiavi-ripetute", "A12", lambda ing: righe_attesi_record(ing, 30, col(1, "00000000039"))),
    ("attesi-senza-primo", "A04", lambda ing: righe_attesi_record(ing, 1, col(0, "2"))),
    ("attesi-senza-ultimo", "A05", lambda ing: righe_attesi_record(ing, 50, col(0, "48"))),
    ("attesi-senza-chiave-49", "A06", lambda ing: righe_attesi_record(ing, 49, col(1, "00000000048"))),
    ("attesi-campo-spostato", "A07", lambda ing: cambia_attesi(ing, "39\t00000000039\tACCT-GROUP-ID\t112\t",
                                                               "39\t00000000039\tACCT-GROUP-ID\t113\t")),
    ("attesi-ebcdic-alterato", "A08", lambda ing: cambia_attesi(ing, "F0*7 F8 F4 F3 F0 C0", "F0*7 F8 F4 F4 F0 C0")),
    ("attesi-oracle-alterato", "A09", lambda ing: cambia_attesi(ing, "30*7 38 34 33 30 7B", "30*7 38 34 34 30 7B")),
    ("prodotto-zip-49-ascii", "A09", lambda ing: dopo(altera_rec(lambda d: d[:48 * L + 102] + b"A000000000" + d[48 * L + 112:]))),
    ("attesi-chiave-diversa", "A10", lambda ing: righe_attesi_record(ing, 50, col(1, "00000000051"))),
    ("attesi-record-oltre-la-fine", "A11", lambda ing: righe_attesi_record(ing, 30, col(0, "60"))),
]

_CHIAMATA = re.compile(r"\.errore\(")
_SITO = re.compile(r"\.errore\(\s*\"([A-Z][0-9]{2})\"")


def censimento():
    """Ogni chiamata .errore( in oracle_dati.py e' una guardia: (file, riga, codice). Una chiamata senza codice
    letterale e' un errore dell'inventario."""
    siti, non_letterali = set(), []
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "oracle_dati.py")
    with open(p, encoding="utf-8") as f:
        for i, l in enumerate(f, 1):
            if l.lstrip().startswith("def errore("):
                continue
            n = len(_CHIAMATA.findall(l))
            m = _SITO.findall(l)
            if n != len(m):
                non_letterali.append(i)
            for c in m:
                siti.add(("oracle_dati.py", i, c))
    return siti, non_letterali


def esegui(ing, gestore):
    """Generazione, scrittura in una cartella temporanea, eventuale alterazione del file scritto, verifica."""
    es = od.Esito()
    tmp = tempfile.mkdtemp(prefix="issue53-neg.")
    try:
        ctx = gestore if hasattr(gestore, "__enter__") else contextlib.nullcontext()
        with ctx:
            prodotti = od.genera(ing, es)
            if not es.errori:
                out = os.path.join(tmp, "out")
                od.scrivi(prodotti, out)
                if isinstance(gestore, tuple) and gestore[0] == "dopo":
                    gestore[1](out)
                od.verifica(ing, out, es)
    finally:
        shutil.rmtree(tmp)
    return es


def scaduto(*_):
    print(f"ERRORE operativo: limite di {LIMITE} s superato", flush=True)
    os._exit(2)


def main(argv):
    global LIMITE
    if len(argv) == 6 and argv[4] == "--limite":    # solo per la prova negativa del limite di tempo (check.sh)
        LIMITE = float(argv[5])
        argv = argv[:4]
    if len(argv) != 4:
        print(__doc__)
        return 2
    signal.signal(signal.SIGALRM, scaduto)
    signal.setitimer(signal.ITIMER_REAL, LIMITE)
    legacy, dc, fixture, cartella = argv
    ing = od.Ingressi(legacy, dc, fixture, cartella)
    es = esegui(ing, None)    # anche popola le cache (testi, contratti, fixture) che le copie ereditano
    if es.errori:
        for c, x in es.errori[:10]:
            print(f"ERRORE [{c}] {x}")
        print("ERRORE operativo: la verifica sugli ingressi non alterati fallisce: prove negative non significative")
        return 2
    superate, fallite, coperti, siti = 0, 0, set(), set()
    for nome, codice, prepara in PROVE:
        copia = ing.copia()
        try:
            gestore = prepara(copia)
        except (KeyError, ValueError, IndexError) as e:
            print(f"PROVA NEGATIVA FALLITA ({nome}): alterazione non applicabile ({e})")
            fallite += 1
            continue
        if isinstance(gestore, tuple) and gestore[0] != "dopo":
            gestore = None
        try:
            es = esegui(copia, gestore)
        except ValueError as e:
            print(f"PROVA NEGATIVA FALLITA ({nome}): alterazione non applicabile ({e})")
            fallite += 1
            continue
        trovati = [x for c, x in es.errori if c == codice]
        if trovati:
            superate += 1
            coperti.add(codice)
            siti |= {(f, r, c) for f, r, c in es.siti if c == codice}
            altri = sorted(es.codici() - {codice})
            print(f"ok: {nome} -> [{codice}] {trovati[0][:150]}" + (f" (anche {', '.join(altri)})" if altri else ""))
        else:
            fallite += 1
            print(f"PROVA NEGATIVA FALLITA ({nome}): atteso [{codice}], ottenuti {sorted(es.codici()) or 'nessun errore'}")
            for c, x in es.errori[:5]:
                print(f"   [{c}] {x[:160]}")
    scoperti = [c for c in od.CODICI if c not in coperti]
    for c in scoperti:
        print(f"INVENTARIO: il codice [{c}] ({od.CODICI[c]}) non ha alcuna prova negativa superata")
    cens, non_letterali = censimento()
    for r in non_letterali:
        print(f"INVENTARIO: oracle_dati.py:{r}: chiamata .errore( senza codice letterale (non censibile)")
    siti_scoperti = sorted(cens - siti)
    for f, r, c in siti_scoperti:
        print(f"INVENTARIO: la guardia {f}:{r} [{c}] non e' mai scattata in una prova superata che pretende [{c}]")
    fuori = sorted(siti - cens)
    for f, r, c in fuori:
        print(f"INVENTARIO: errore [{c}] da {f}:{r}, riga non censita (censimento incompleto)")
    if fallite or scoperti or siti_scoperti or fuori or non_letterali:
        print(f"prove negative: {superate} superate, {fallite} fallite, {len(scoperti)} codici e "
              f"{len(siti_scoperti) + len(fuori) + len(non_letterali)} guardie scoperti")
        return 1
    print(f"inventario: {len(od.CODICI)} codici e {len(cens)} guardie (chiamate es.errore censite in oracle_dati.py), "
          f"ognuna scattata in almeno una prova superata che pretende il suo codice")
    print(f"prove negative: {superate} superate, ogni guardia coperta")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:
        print(f"ERRORE operativo: {type(e).__name__}: {e}")
        sys.exit(2)
