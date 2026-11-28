"""Fixture verificate dai dati di esempio di CardDemo (issue #5).

Quattro passi, nell'ordine:
  1. struttura fisica di ogni file, senza contratto (dimensione, impronta, righe e terminatori per l'ASCII);
  2. riempimento delle righe ASCII corte: passo separato e visibile (RIEMPI), che distingue i byte del file da quelli
     aggiunti; la regola (spazi 0x20 a destra) e' una scelta dichiarata, perche' nessun JCL del repository carica i .txt;
  3. decodifica di ogni campo con il codec di #23 (analysis/data-codec/glue/codec.py), guidata dal contratto di #3 con
     l'adattatore di #43 (analysis/data-sentinelle/glue/controlli.py), entrambi importati in sola lettura;
  4. elenchi: anomalie, differenze ASCII/EBCDIC, chiavi, totali di controllo.
La verifica (verifica()) confronta tutto con gli attesi scritti a mano (inventario.tsv, fisica.tsv, viste-export.tsv,
attesi/) e ricalcola in modo indipendente gli elenchi. Ogni asserzione ha un codice (CODICI): negativi.py pretende per
ogni codice almeno una prova negativa che lo produca. Nessun valore e' riparato: un campo non valido resta non valido.
"""
import copy
import os
import re
import sys
from collections import Counter, OrderedDict
from decimal import Decimal

sys.path.insert(0, "/analysis/data-codec/glue")
sys.path.insert(0, "/analysis/data-sentinelle/glue")
import codec  # noqa: E402
from comune import a_esa, da_esa, leggi_tsv, valore_a_testo, valore_da_testo  # noqa: E402
from controlli import classifica_riga, ordina_contratto, righe_contratto, vista_contratto  # noqa: E402

PROFILO = {"ASCII": "oracle-gnucobol", "EBCDIC": "zos-ebcdic"}
PAGINA = {"ASCII": "latin-1", "EBCDIC": "cp037"}
CARTELLE = {"app/data/ASCII/": "ASCII", "app/data/EBCDIC/": "EBCDIC"}
EXPORT = "CVEXPORT.EXPORT-RECORD"
PROVENIENZE = ("carica", "consuma", "nessuno")
STATI = ("valido", "non-valido", "oltre-picture")
SPAZIO_ASCII = 0x20

CODICI = OrderedDict([
    ("I01", "file dati del manifesto senza voce nell'inventario"),
    ("I02", "voce dell'inventario senza file dati nel manifesto"),
    ("I03", "riga dell'inventario malformata o duplicata"),
    ("I04", "contratto sconosciuto o lunghezza diversa da quella del contratto"),
    ("I05", "contratto diverso da quello del dataset in file.tsv"),
    ("I06", "corrispondenza ASCII/EBCDIC non simmetrica, stessa codifica o contratto diverso"),
    ("I07", "provenienza carica/consuma non riscontrata nel JCL citato"),
    ("I08", "provenienza 'nessuno' smentita: un JCL del repository nomina il file"),
    ("I10", "coppie ASCII/EBCDIC dichiarate diverse da quelle dovute (stesso contratto in codifiche diverse)"),
    ("I09", "chiave di abbinamento diversa dalla chiave primaria dichiarata, o scelta dove una chiave esiste"),
    ("F01", "dimensione diversa da fisica.tsv"),
    ("F02", "impronta diversa da fisica.tsv"),
    ("F03", "dimensione EBCDIC non divisibile per la lunghezza del record"),
    ("F04", "numero di record diverso da fisica.tsv"),
    ("F05", "terminatori di riga diversi da fisica.tsv"),
    ("F06", "byte dopo l'ultimo terminatore diversi da fisica.tsv"),
    ("F07", "lunghezze delle righe diverse da fisica.tsv"),
    ("F08", "riconciliazione al byte di fisica.tsv non riuscita"),
    ("F09", "voce di fisica.tsv mancante, in piu' o malformata"),
    ("V01", "tipi di viste-export.tsv diversi dai WHEN dell'EVALUATE di CBIMPORT"),
    ("V02", "riga citata in viste-export.tsv senza WHEN/PERFORM dichiarati"),
    ("V03", "il paragrafo di CBIMPORT usa campi di una vista diversa da quella dichiarata"),
    ("V04", "viste di viste-export.tsv diverse dalle aree che ridefiniscono il carico nel contratto"),
    ("V05", "campi emessi per un record dell'export diversi da comuni + vista attiva"),
    ("D01", "stato di un campo diverso dall'atteso a mano"),
    ("D02", "valore di un campo diverso dall'atteso a mano"),
    ("D03", "byte di un record atteso diversi da quelli del file"),
    ("D04", "campi di un record atteso diversi da quelli decodificati"),
    ("D05", "record atteso inesistente nel file"),
    ("D06", "file senza attesi a mano, o attesi senza file"),
    ("D07", "attesi senza un record dovuto (primo, ultimo, negativo, anomalo, tipo dell'export, differenza)"),
    ("D08", "origine di un campo (file/riempimento) diversa dall'atteso"),
    ("D09", "attesi malformati"),
    ("R01", "la ricodifica conservativa di un campo non ridà i suoi byte"),
    ("R02", "i campi non ricompongono il record (buchi, sovrapposizioni, byte diversi)"),
    ("R04", "record della fixture diversi, per numero, ordine, byte, terminatori o riempimento, dai byte del file letti per altra via"),
    ("R03", "i byte ricomposti non coincidono con i byte della riga del file (ASCII)"),
    ("K01", "chiave di abbinamento duplicata"),
    ("A01", "riga corta o lunga assente dall'elenco delle anomalie"),
    ("A02", "campo non valido o oltre la PICTURE assente dall'elenco delle anomalie"),
    ("A03", "terminatore minoritario assente dall'elenco delle anomalie"),
    ("A04", "tipo di record dell'export non previsto assente dall'elenco delle anomalie"),
    ("A05", "voce dell'elenco delle anomalie senza riscontro"),
    ("P01", "record presente in una sola codifica assente dall'elenco delle differenze"),
    ("P02", "differenza di byte fra ASCII ed EBCDIC non coperta dall'elenco delle differenze"),
    ("P03", "voce dell'elenco delle differenze senza riscontro"),
    ("X01", "fixture rigenerata diversa da quella versionata"),
    ("X02", "totali di controllo diversi da quelli versionati"),
    ("X03", "elenchi (anomalie, differenze, chiavi, conteggi) diversi da quelli versionati"),
    ("X04", "tabella del documento generato malformata"),
    ("T01", "tracciato del contratto non utilizzabile"),
])


class Esito:
    def __init__(self):
        self.errori = []
        self.siti = []   # (file, riga) della chiamata, parallelo a errori: per il censimento delle guardie

    def errore(self, codice, testo):
        assert codice in CODICI, codice
        f = sys._getframe(1)
        self.errori.append((codice, testo))
        self.siti.append((os.path.basename(f.f_code.co_filename), f.f_lineno, codice))

    def codici(self):
        return {c for c, _ in self.errori}


# --- ingressi -------------------------------------------------------------------------------------------------------

def _tsv(path):
    testa, righe = leggi_tsv(path)
    return testa, righe


class Ingressi:
    """Tutto cio' che la verifica legge, caricato una volta. Le prove negative ne alterano una copia privata."""

    def __init__(self, legacy, dc, manifesto, cartella):
        self.legacy, self.dc, self.cartella = legacy, dc, cartella
        _, man = _tsv(manifesto)
        self.manifesto = [(r["path"], r["type"]) for r in man]
        self.inventario = self._righe_grezze(os.path.join(cartella, "inventario.tsv"))
        self.fisica = self._righe_grezze(os.path.join(cartella, "fisica.tsv"))
        self.viste = self._righe_grezze(os.path.join(cartella, "viste-export.tsv"))
        self.attesi = {}
        dir_attesi = os.path.join(cartella, "attesi")
        for n in sorted(os.listdir(dir_attesi)):
            with open(os.path.join(dir_attesi, n), encoding="utf-8") as f:
                self.attesi[n] = f.read()
        self.dati = {}
        for p, t in self.manifesto:
            if t == "data" and _codifica_cartella(p):
                with open(os.path.join(legacy, p), "rb") as f:
                    self.dati[p] = f.read()
        self.contratti = {}
        _, self.contratti_tsv = _tsv(os.path.join(dc, "contratti.tsv"))
        _, self.file_tsv = _tsv(os.path.join(dc, "file.tsv"))
        _, self.chiavi_tsv = _tsv(os.path.join(dc, "chiavi.tsv"))
        _, self.assegnazioni = _tsv(os.path.join(dc, "assegnazioni.tsv"))
        self.testi = {}   # file del legacy letti come testo (JCL, CBIMPORT)
        self.profilo_forzato = {}   # solo per le prove negative: file -> profilo

    @staticmethod
    def _righe_grezze(path):
        with open(path, encoding="utf-8") as f:
            return [l.rstrip("\n") for l in f if l.strip() and not l.startswith("#")]

    def contratto(self, nome):
        if nome not in self.contratti:
            righe = righe_contratto(os.path.join(self.dc, "contratti", nome + ".tsv"))
            ordina_contratto(righe)
            self.contratti[nome] = righe
        return self.contratti[nome]

    def testo(self, path):
        if path not in self.testi:
            with open(os.path.join(self.legacy, path), encoding="latin-1") as f:
                self.testi[path] = f.read().split("\n")
        return self.testi[path]

    def copia(self):
        c = copy.copy(self)
        for k in ("inventario", "fisica", "viste", "manifesto"):
            setattr(c, k, list(getattr(self, k)))
        for k in ("attesi", "dati", "profilo_forzato", "testi"):
            setattr(c, k, dict(getattr(self, k)))
        c.contratti = {k: copy.deepcopy(v) for k, v in self.contratti.items()}
        return c


def _codifica_cartella(p):
    for pref, cod in CARTELLE.items():
        if p.startswith(pref) and "/" not in p[len(pref):]:
            return cod
    return None


def tabella(righe, es, codice, cosa):
    """Righe grezze TSV (la prima e' l'intestazione) -> lista di dict; righe malformate -> errore."""
    if not righe:
        es.errore(codice, f"{cosa}: tabella vuota")
        return []
    testa = righe[0].split("\t")
    out = []
    for r in righe[1:]:
        c = r.split("\t")
        if len(c) != len(testa):
            es.errore(codice, f"{cosa}: riga con {len(c)} colonne invece di {len(testa)}: {r[:80]}")
            continue
        out.append(dict(zip(testa, c)))
    return out


# --- 1. struttura fisica --------------------------------------------------------------------------------------------

def fisica_ascii(dati):
    """Righe del file: (byte della riga senza terminatore, terminatore 'CRLF'|'LF'|'nessuno'). Una coda senza
    terminatore e' una riga con terminatore 'nessuno'."""
    righe, i = [], 0
    while i < len(dati):
        j = dati.find(b"\n", i)
        if j < 0:
            righe.append((dati[i:], "nessuno"))
            break
        riga = dati[i:j]
        if riga.endswith(b"\r"):
            righe.append((riga[:-1], "CRLF"))
        else:
            righe.append((riga, "LF"))
        i = j + 1
    return righe


def intervalli(valori):
    """[v1, v1, v2] -> 'v1:1-2,v2:3' (numeri di riga da 1)."""
    out, i = [], 0
    while i < len(valori):
        j = i
        while j + 1 < len(valori) and valori[j + 1] == valori[i]:
            j += 1
        out.append(f"{valori[i]}:{i + 1}" + (f"-{j + 1}" if j > i else ""))
        i = j + 1
    return ",".join(out)


# --- 2. riempimento (scelta dichiarata) -----------------------------------------------------------------------------

def riempi(riga, lunghezza):
    """Riga ASCII -> (record di 'lunghezza' byte, byte presi dal file). Riga corta: spazi 0x20 a destra (scelta
    dichiarata, nessun JCL la determina); riga lunga: si prendono i primi 'lunghezza' byte (l'eccedenza e' un'anomalia)."""
    if len(riga) >= lunghezza:
        return bytes(riga[:lunghezza]), lunghezza
    return bytes(riga) + bytes([SPAZIO_ASCII]) * (lunghezza - len(riga)), len(riga)


def record_ebcdic(dati, L):
    """Record di un file a lunghezza fissa: (numero da 1, byte). Un'eventuale coda incompleta non e' un record (F03)."""
    return [(i // L + 1, dati[i:i + L]) for i in range(0, len(dati) - len(dati) % L, L)]


RIEMPI = riempi           # sostituibile solo dalle prove negative
DECODIFICA = codec.decodifica
RICODIFICA = codec.ricodifica


# --- 3. decodifica ----------------------------------------------------------------------------------------------------

def nome_campo(r):
    ind = r["_identita"][1]
    return r["campo"] + (f"({','.join(str(i) for i in ind)})" if ind else "")


def viste_export(ing, es):
    v = tabella(ing.viste, es, "V02", "viste-export.tsv")
    return {r["tipo"]: r for r in v}


def campi_vista(ing, contratto, vista, es):
    try:
        righe = ing.contratto(contratto)
        campi = vista_contratto(righe, vista)
    except (OSError, ValueError) as e:
        es.errore("T01", f"{contratto} vista {vista}: {e}")
        return None
    return sorted(campi, key=lambda r: int(r["offset"]))


def campi_comuni(ing, es):
    """Campi comuni dell'export: quelli presenti in tutte le viste del carico (cioe' fuori da EXPORT-RECORD-DATA)."""
    insiemi = []
    for t, r in sorted(viste_export(ing, es).items()):
        c = campi_vista(ing, EXPORT, r["vista"], es)
        if c is None:
            return None
        insiemi.append({nome_campo(x): x for x in c})
    if not insiemi:
        return None
    comuni = set(insiemi[0])
    for s in insiemi[1:]:
        comuni &= set(s)
    return sorted((insiemi[0][n] for n in comuni), key=lambda r: int(r["offset"]))


class Campo:
    __slots__ = ("nome", "offset", "lunghezza", "stato", "valore", "scala", "originali", "origine", "categoria")


def decodifica_record(ing, voce, buf, presi, campi, es, chi):
    """Decodifica i campi (righe del contratto) di un record; presi = byte presi dal file (il resto e' riempimento)."""
    profilo = ing.profilo_forzato.get(voce["file"], PROFILO[voce["codifica"]])
    out = []
    for r in campi:
        try:
            cat, var, g = classifica_riga(r, voce["contratto"])
            off = int(r["offset"])
            ris = DECODIFICA(profilo, cat, var, buf, off)
        except (ValueError, codec.CodificaErrore) as e:
            es.errore("T01", f"{chi} {nome_campo(r)}: {e}")
            return None
        c = Campo()
        c.nome, c.offset, c.lunghezza, c.categoria = nome_campo(r), off, g.lunghezza, cat
        c.stato, c.valore, c.scala, c.originali = ris.stato, ris.valore, g.decimali, ris.originali
        if off + g.lunghezza <= presi:
            c.origine = "file"
        elif off >= presi:
            c.origine = "riempimento"
        else:
            c.origine = "misto"
        if RICODIFICA(ris) != bytes(buf[off:off + g.lunghezza]):
            es.errore("R01", f"{chi} {c.nome}: la ricodifica conservativa non ridà i byte del campo")
        out.append(c)
    return out


def testo_valore(c):
    if c.stato != "valido":
        return "-"
    if isinstance(c.valore, str):
        return valore_a_testo(c.valore)
    return valore_a_testo(c.valore, c.scala)


def ricomponi(campi, lunghezza, es, chi):
    pos, pezzi = 0, []
    for c in sorted(campi, key=lambda x: x.offset):
        if c.offset != pos:
            es.errore("R02", f"{chi}: {'buco' if c.offset > pos else 'sovrapposizione'} all'offset {pos} ({c.nome})")
            return None
        pezzi.append(RICODIFICA(codec.Risultato(c.stato, c.valore, c.originali)))
        pos += c.lunghezza
    if pos != lunghezza:
        es.errore("R02", f"{chi}: i campi coprono {pos} byte su {lunghezza}")
        return None
    return b"".join(pezzi)


class FileDecodificato:
    def __init__(self, voce):
        self.voce = voce
        self.record = []     # dict: n, term, presi, vista, campi, byte, riga
        self.righe = []      # solo ASCII: (byte, terminatore)
        self.anomalie = []   # (tipo, record, campo, dettaglio)


def decodifica_file(ing, voce, es):
    fd = FileDecodificato(voce)
    dati = ing.dati[voce["file"]]
    L = int(voce["lunghezza"])
    chi_f = voce["file"].rsplit("/", 1)[-1]
    if voce["codifica"] == "ASCII":
        fd.righe = fisica_ascii(dati)
        grezzi = []
        for n, (riga, term) in enumerate(fd.righe, 1):
            buf, presi = RIEMPI(riga, L)
            grezzi.append((n, buf, presi, term, riga))
    else:
        grezzi = [(n, r, L, "-", r) for n, r in record_ebcdic(dati, L)]
    viste = viste_export(ing, es) if voce["contratto"] == EXPORT else None
    comuni = campi_comuni(ing, es) if viste is not None else None
    base = None if viste is not None else campi_vista(ing, voce["contratto"], "base", es)
    for n, buf, presi, term, riga in grezzi:
        chi = f"{chi_f}#{n}"
        if viste is not None:
            tipo = bytes(buf[:1]).decode(PAGINA[voce["codifica"]])
            if tipo in viste:
                vista = viste[tipo]["vista"]
                campi = campi_vista(ing, EXPORT, vista, es)
            else:
                vista, campi = "comuni", comuni
        else:
            vista, campi = "base", base
        if campi is None:
            return None
        dec = decodifica_record(ing, voce, buf, presi, campi, es, chi)
        if dec is None:
            return None
        if vista != "comuni":
            ric = ricomponi(dec, L, es, chi)
            if ric is not None and ric != bytes(buf):
                es.errore("R02", f"{chi}: i campi ricomposti non danno i byte del record")
            if ric is not None and ric[:min(presi, len(riga))] != bytes(riga[:presi]):
                es.errore("R03", f"{chi}: i byte ricomposti non coincidono con i byte della riga del file")
        fd.record.append({"n": n, "term": term, "presi": presi, "vista": vista, "campi": dec, "byte": bytes(buf),
                          "riga": bytes(riga)})
    elenca_anomalie(fd)
    return fd


def elenca_anomalie(fd):
    v = fd.voce
    L = int(v["lunghezza"])
    if v["codifica"] == "ASCII":
        conta = Counter(t for _, t in fd.righe)
        maggiore = conta.most_common(1)[0][0] if conta else None
        for n, (riga, term) in enumerate(fd.righe, 1):
            if len(riga) < L:
                fd.anomalie.append(("riga-corta", str(n), "-", f"{len(riga)} byte su {L}: {L - len(riga)} byte di "
                                                                f"riempimento (spazi) nella fixture"))
            elif len(riga) > L:
                fd.anomalie.append(("riga-lunga", str(n), "-", f"{len(riga)} byte su {L}: eccedenza "
                                                                f"{a_esa(riga[L:])} non decodificata"))
            if len(conta) > 1 and term != maggiore:
                fd.anomalie.append(("terminatore-minoritario", str(n), "-",
                                    f"{term} in un file con {maggiore} su {conta[maggiore]} righe"))
    for rec in fd.record:
        if rec["vista"] == "comuni":
            fd.anomalie.append(("tipo-export-sconosciuto", str(rec["n"]), "EXPORT-REC-TYPE",
                                f"tipo {a_esa(rec['byte'][:1])}: decodificati solo i campi comuni"))
        for c in rec["campi"]:
            if c.stato != "valido":
                fd.anomalie.append((f"campo-{c.stato}", str(rec["n"]), c.nome, a_esa(c.originali)))


# --- chiavi, totali ---------------------------------------------------------------------------------------------------

_SPAN = re.compile(r"^@([0-9]+)\+([1-9][0-9]*)$")


def valore_chiave(voce, rec):
    k = voce["chiave"]
    m = _SPAN.match(k)
    if m:
        a, l = int(m.group(1)), int(m.group(2))
        return a_esa(rec["byte"][a:a + l])
    per_nome = {c.nome: c for c in rec["campi"]}
    parti = []
    for n in k.split("+"):
        c = per_nome.get(n)
        if c is None:
            return None
        parti.append(testo_valore(c) if c.stato == "valido" else "!" + a_esa(c.originali))
    return "|".join(parti)


def chiavi_alternative(ing, voce):
    out = set()
    for r in ing.chiavi_tsv:
        if r["dataset"] == voce["dataset"] and r["chiave"] == "alternativa" and r["fonte"].startswith("JCL DEFINE"):
            out.add((int(r["offset"]), int(r["lunghezza"]), r["campi"]))
    return sorted(out)


def calcola_chiavi(ing, fd, es):
    v = fd.voce
    righe = []
    valori = [valore_chiave(v, r) for r in fd.record]
    conta = Counter(valori)
    dup = sorted(k for k, n in conta.items() if n > 1 and k is not None)
    if None in conta:
        es.errore("T01", f"{v['file']}: chiave {v['chiave']} non calcolabile dai campi decodificati")
    for k in dup:
        es.errore("K01", f"{v['file']}: chiave {v['chiave']} duplicata: {k} ({conta[k]} record)")
        fd.anomalie.append(("chiave-duplicata", "-", v["chiave"], f"{k} in {conta[k]} record"))
    righe.append((v["file"], "abbinamento", v["chiave"], v["fonte_chiave"], len(valori), len(conta),
                  "si" if not dup else "no"))
    for off, lun, campi in chiavi_alternative(ing, v):
        c = Counter(a_esa(r["byte"][off:off + lun]) for r in fd.record)
        righe.append((v["file"], "alternativa", f"@{off}+{lun} {campi}", "chiavi.tsv", len(fd.record), len(c),
                      "si" if all(x == 1 for x in c.values()) else "no"))
    return righe


def calcola_totali(fd):
    tot = OrderedDict()
    for rec in fd.record:
        for c in rec["campi"]:
            if c.categoria == "alfanumerico":
                continue
            k = (rec["vista"], c.nome)
            t = tot.setdefault(k, {"valido": 0, "non-valido": 0, "oltre-picture": 0, "somma": Decimal(0), "scala": c.scala})
            t[c.stato] += 1
            if c.stato == "valido":
                t["somma"] += c.valore
    return [(fd.voce["file"], vista, nome, t["valido"], t["non-valido"], t["oltre-picture"],
             valore_a_testo(t["somma"], t["scala"])) for (vista, nome), t in sorted(tot.items())]


# --- 4. confronto ASCII/EBCDIC ----------------------------------------------------------------------------------------

def confronta(fa, fe):
    """Differenze fra il file ASCII fa e il file EBCDIC fe, abbinati per chiave (stesso contratto)."""
    out = []
    ka = OrderedDict((valore_chiave(fa.voce, r), r) for r in fa.record)
    ke = OrderedDict((valore_chiave(fe.voce, r), r) for r in fe.record)
    for k in ka:
        if k not in ke:
            out.append(("solo-ascii", k, "-", f"record {ka[k]['n']}", "-"))
    for k in ke:
        if k not in ka:
            out.append(("solo-ebcdic", k, "-", "-", f"record {ke[k]['n']}"))
    for k in ka:
        if k not in ke:
            continue
        ra, re_ = ka[k], ke[k]
        ce = {c.nome: c for c in re_["campi"]}
        for a in ra["campi"]:
            e = ce.get(a.nome)
            if e is None:
                continue
            da = f"{a.stato} {testo_valore(a)} [{a_esa(a.originali)}]"
            de = f"{e.stato} {testo_valore(e)} [{a_esa(e.originali)}]"
            if a.stato != e.stato:
                tipo = "stato-diverso"
            elif testo_valore(a) != testo_valore(e):
                tipo = "valore-diverso"
            elif a.originali.decode("latin-1") != e.originali.decode("cp037"):
                tipo = "rappresentazione-diversa"
            else:
                tipo = None
            if a.origine != "file":
                tipo = "riempimento-" + ("uguale" if tipo is None else "diverso")
            if tipo:
                out.append((tipo, k, a.nome, f"record {ra['n']}: {da}", f"record {re_['n']}: {de}"))
    return out


def coppie(voci):
    return [(e["corrispondente"], e["file"]) for e in voci
            if e["codifica"] == "EBCDIC" and e["corrispondente"] != "-"]


# --- generazione ----------------------------------------------------------------------------------------------------

def base_nome(p):
    return p.rsplit("/", 1)[-1]


def riga_fixture(rec):
    celle = [str(rec["n"]), rec["term"], str(rec["presi"]), str(len(rec["byte"]) - rec["presi"]), rec["vista"]]
    for c in rec["campi"]:
        cella = f"{c.nome}|{c.stato}|{testo_valore(c)}|{a_esa(c.originali)}"
        if c.origine != "file":
            cella += f"|{c.origine}"
        celle.append(cella)
    return "\t".join(celle)


def testo_fixture(fd):
    v = fd.voce
    out = [f"# fixture di {v['file']} (issue #5): contratto {v['contratto']}, profilo {PROFILO[v['codifica']]}, "
           f"{len(fd.record)} record",
           "# colonne: record, terminatore, byte del file, byte di riempimento, vista, poi un campo per colonna: "
           "nome|stato|valore|byte originali[|origine se non dal file]"]
    out += [riga_fixture(r) for r in fd.record]
    return "\n".join(out) + "\n"


def testo_tsv(testa, righe):
    return "\n".join(["\t".join(testa)] + ["\t".join(str(x) for x in r) for r in righe]) + "\n"


def genera(ing, es):
    """Decodifica tutti i file dell'inventario; restituisce (decodificati per file, uscite {nome: testo})."""
    voci = tabella(ing.inventario, es, "I03", "inventario.tsv")
    dec, uscite = OrderedDict(), OrderedDict()
    for v in sorted(voci, key=lambda x: x["file"]):
        if v["file"] not in ing.dati or v.get("codifica") not in PROFILO:
            continue
        try:
            if int(v["lunghezza"]) <= 0:
                raise ValueError
        except ValueError:
            es.errore("I03", f"{v['file']}: lunghezza non valida {v['lunghezza']!r}")
            continue
        fd = decodifica_file(ing, v, es)
        if fd is not None:
            dec[v["file"]] = fd
    chiavi, totali, conteggi = [], [], []
    for p, fd in dec.items():
        chiavi += calcola_chiavi(ing, fd, es)
        totali += calcola_totali(fd)
        uscite[f"{base_nome(p)}.tsv"] = testo_fixture(fd)
    confronti = OrderedDict()
    for a, e in coppie(voci):
        if a in dec and e in dec:
            confronti[(a, e)] = confronta(dec[a], dec[e])
            uscite[f"confronto-{base_nome(e)}.tsv"] = testo_tsv(("tipo", "chiave", "campo", "ascii", "ebcdic"),
                                                                 confronti[(a, e)])
    for p, fd in dec.items():
        uscite[f"{base_nome(p)}.anomalie.tsv"] = testo_tsv(("tipo", "record", "campo", "dettaglio"), fd.anomalie)
    att = {}
    for p, fd in dec.items():
        a = leggi_attesi(ing, p, es)
        att[p] = a
        L = int(fd.voce["lunghezza"])
        dalla_dim = str(len(ing.dati[p]) // L) if fd.voce["codifica"] == "EBCDIC" else "-"
        righe_f = str(len(fd.righe)) if fd.voce["codifica"] == "ASCII" else "-"
        conteggi.append((p, dalla_dim, righe_f, len(fd.record), len(a) if a is not None else 0))
    uscite["chiavi.tsv"] = testo_tsv(("file", "chiave", "definizione", "fonte", "record", "distinti", "unica"), chiavi)
    uscite["totali.tsv"] = testo_tsv(("file", "vista", "campo", "validi", "non_validi", "oltre_picture", "somma"),
                                     totali)
    uscite["conteggi.tsv"] = testo_tsv(("file", "record_dalla_dimensione", "righe_fisiche", "record_decodificati",
                                        "record_negli_attesi"), conteggi)
    return voci, dec, confronti, att, uscite


# --- attesi a mano ----------------------------------------------------------------------------------------------------

def leggi_attesi(ing, p, es):
    nome = base_nome(p) + ".tsv"
    if nome not in ing.attesi:
        return None
    rec = OrderedDict()
    for i, l in enumerate(ing.attesi[nome].split("\n"), 1):
        if not l.strip() or l.startswith("#"):
            continue
        c = l.split("\t")
        try:
            if c[0] == "R" and len(c) == 4:
                n = int(c[1])
                if n in rec:
                    raise ValueError(f"record {n} ripetuto")
                rec[n] = {"motivi": set(c[2].split(",")), "byte": _esa_libera(c[3]), "campi": OrderedDict()}
            elif c[0] == "C" and len(c) == 9:
                n = int(c[1])
                if n not in rec:
                    raise ValueError(f"campo prima del suo record {n}")
                nome_c = c[2] + (f"({c[3]})" if c[3] != "-" else "")
                if nome_c in rec[n]["campi"]:
                    raise ValueError(f"campo {nome_c} ripetuto")
                if c[4] not in ("file", "riempimento", "misto") or c[5] not in STATI:
                    raise ValueError(f"origine o stato non ammessi: {c[4]} {c[5]}")
                if c[5] == "valido":
                    if c[6] not in ("testo", "intero", "decimale"):
                        raise ValueError(f"tipo non ammesso: {c[6]}")
                    v = valore_da_testo(c[7], c[6] == "testo")
                else:
                    v = None
                rec[n]["campi"][nome_c] = {"origine": c[4], "stato": c[5], "tipo": c[6], "valore": v, "testo": c[7]}
            else:
                raise ValueError(f"riga non riconosciuta ({len(c)} colonne)")
        except (ValueError, IndexError) as e:
            es.errore("D09", f"attesi/{nome}:{i}: {e}")
    return rec


def _esa_libera(t):
    t = t.strip()
    if " " not in t and "*" not in t and len(t) % 2 == 0 and len(t) > 2:
        return bytes.fromhex(t)
    return da_esa(t.upper())


def tipo_valore(c):
    if isinstance(c.valore, str):
        return "testo"
    return "decimale" if c.scala > 0 else "intero"
