"""Record dei file indicizzati nel profilo dell'oracle GnuCOBOL (issue #53).

Per ogni riga della tabella scritta a mano (tabella.tsv) il file che il JCL carica nel KSDS (REPRO INFILE) si porta
dal profilo zos-ebcdic al profilo oracle-gnucobol CAMPO PER CAMPO: decodifica con il codec di #23
(analysis/data-codec/glue/codec.py) guidato dal contratto di #3 attraverso l'adattatore di #43
(analysis/data-sentinelle/glue/controlli.py), entrambi importati e non modificati, poi codifica del valore nel profilo
dell'oracle. Nessuna conversione di caratteri sull'intero record, nessuna regola di codifica riscritta qui. Un campo
non valido, non in rappresentazione canonica (la ricodifica cambierebbe la rappresentazione: sarebbe una
normalizzazione) o non ricodificabile ferma la generazione.

Due fasi separate:
  genera(ing, es)          -> controllo 1 (tabella contro JCL e contratto), poi i record prodotti, in memoria (nessuna
                              scrittura); con un errore non si produce nulla;
  verifica(ing, out, es)   -> i controlli 2, 4, 5 e l'elenco, sui file LETTI DAL DISCO in out/ (cio' che si versiona),
                              mai sui buffer della generazione. Il controllo 3 (controprova con il file ASCII) non e'
                              qui: lo fa controprova.sh con le sole utility POSIX, leggendo i byte per un'altra via.
Ogni guardia e' una chiamata a es.errore con un codice letterale proprio: un codice, una condizione, un sito.
negativi.py pretende per ogni sito una prova negativa che lo faccia scattare.
"""
import copy
import hashlib
import os
import re
import sys
from collections import OrderedDict

sys.path.insert(0, "/analysis/data-codec/glue")
sys.path.insert(0, "/analysis/data-sentinelle/glue")
import codec  # noqa: E402
from comune import a_esa, da_esa, valore_a_testo  # noqa: E402
from controlli import classifica_riga, ordina_contratto, righe_contratto, vista_contratto  # noqa: E402

ORIGINE = "zos-ebcdic"
ORACLE = "oracle-gnucobol"
TESTA_TABELLA = ["dd", "origine", "contratto", "chiave_lunghezza", "chiave_offset", "rif_chiave", "lunghezza_record",
                 "rif_lunghezza", "controprova", "uscita"]
TESTA_ATTESI = ["record", "chiave", "campo", "offset", "lunghezza", "ebcdic", "oracle"]
RECORD_A_SCELTA = 2          # oltre a primo, ultimo e record della differenza: due record a scelta (specifica, controllo 5)
CHIAVE_DIFFERENZA = 49       # il record di ACCT-ADDR-ZIP diverso fra ASCII ed EBCDIC (docs/legacy-map/fixture.md)
_RIF = re.compile(r"^(app/jcl/[A-Za-z0-9_]+\.(?:jcl|JCL)):([1-9][0-9]*)$")
_KEYS = re.compile(r"\bKEYS\(([0-9]+) +([0-9]+)\)")
_RECSIZE = re.compile(r"\bRECORDSIZE\(([0-9]+) +([0-9]+)\)")
_NAME = re.compile(r"\bDEFINE +CLUSTER +\(NAME\(([A-Z0-9.$#@]+)\)")
_REPRO = re.compile(r"\bREPRO +INFILE\(([A-Z0-9$#@]+)\) +OUTFILE\(([A-Z0-9$#@]+)\)")
_DD = re.compile(r"^//([A-Z0-9$#@]+) +DD\b")
_DSN = re.compile(r"\bDSN=([A-Z0-9.$#@]+)")
_INTERO = re.compile(r"^(0|[1-9][0-9]*)$")

CODICI = OrderedDict([
    ("T01", "intestazione della tabella diversa da quella fissata"),
    ("T02", "riga della tabella con un numero di colonne diverso dall'intestazione"),
    ("T03", "valore numerico della tabella illeggibile"),
    ("T04", "nome DD ripetuto nella tabella"),
    ("T05", "tabella senza righe"),
    ("T06", "nome d'uscita diverso da <dd>.rec"),
    ("T07", "tabella con la sola intestazione"),
    ("G01", "dimensione del file d'origine non multipla della lunghezza del record"),
    ("G02", "contratto illeggibile o riga del contratto non classificabile"),
    ("G03", "i campi del contratto non coprono il record senza buchi ne' sovrapposizioni"),
    ("G04", "campo non valido nel profilo d'origine"),
    ("G05", "campo non in rappresentazione canonica nel profilo d'origine (la ricodifica lo normalizzerebbe)"),
    ("G06", "campo non ricodificabile nel profilo dell'oracle"),
    ("G07", "campo ricodificato di lunghezza diversa da quella del contratto"),
    ("G08", "chiave duplicata nel file d'origine (needs-spec-update)"),
    ("G09", "chiavi non strettamente crescenti nel file d'origine (needs-spec-update)"),
    ("G10", "file d'origine vuoto"),
    ("G11", "i campi del contratto coprono un numero di byte diverso dalla lunghezza del record"),
    ("J01", "riferimento al JCL malformato"),
    ("J02", "la riga citata per la chiave non contiene KEYS(lunghezza offset)"),
    ("J03", "KEYS del JCL diverso dalla chiave della tabella"),
    ("J04", "la riga citata per la lunghezza non contiene RECORDSIZE(media massima)"),
    ("J05", "RECORDSIZE medio del JCL diverso dalla lunghezza della tabella"),
    ("J06", "RECORDSIZE massimo del JCL diverso dalla lunghezza della tabella"),
    ("J07", "KEYS e RECORDSIZE citati da file JCL diversi"),
    ("J08", "KEYS e RECORDSIZE non appartengono allo stesso DEFINE CLUSTER"),
    ("J09", "il JCL non ha esattamente un REPRO INFILE(...) OUTFILE(...)"),
    ("J10", "la DD di OUTFILE non indica il cluster definito"),
    ("J11", "la DD di INFILE non indica il file d'origine della tabella"),
    ("J12", "lunghezza del contratto diversa dalla lunghezza della tabella"),
    ("J13", "nessun campo del contratto occupa esattamente i byte della chiave"),
    ("J14", "il contratto non ha esattamente una riga di livello 01"),
    ("J15", "file del JCL illeggibile"),
    ("J16", "riga citata oltre la fine del JCL"),
    ("F01", "fixture di #5 assente o con intestazione diversa (file, contratto, profilo)"),
    ("F02", "record della fixture diversi da 1..n o in numero diverso dai record prodotti"),
    ("F03", "campi di un record della fixture diversi da quelli del contratto"),
    ("F04", "stato di un campo prodotto diverso da quello della fixture"),
    ("F05", "valore di un campo prodotto diverso da quello della fixture"),
    ("F06", "riga della fixture malformata"),
    ("F07", "campo della fixture malformato"),
    ("F08", "record ripetuto nella fixture"),
    ("K01", "file prodotto di dimensione non multipla della lunghezza del record"),
    ("K02", "numero di record prodotti diverso da quello del file d'origine"),
    ("K03", "chiave duplicata nel file prodotto"),
    ("K04", "chiavi del file prodotto non strettamente crescenti"),
    ("K05", "file prodotto assente"),
    ("E01", "elenco (record, chiave, impronta) diverso da quello ricalcolato dal file prodotto"),
    ("A01", "attesi a mano assenti o con intestazione diversa"),
    ("A02", "riga degli attesi a mano con un numero di colonne diverso dall'intestazione"),
    ("A03", "numero di record attesi diverso da primo + ultimo + differenza + due a scelta"),
    ("A04", "il primo record del file non e' fra gli attesi"),
    ("A05", "l'ultimo record del file non e' fra gli attesi"),
    ("A06", "il record della differenza (chiave 49) non e' fra gli attesi"),
    ("A07", "campi di un record atteso diversi da quelli del contratto (nome, offset, lunghezza, ordine)"),
    ("A08", "byte EBCDIC attesi diversi da quelli del file d'origine"),
    ("A09", "byte attesi nel profilo dell'oracle diversi da quelli del file prodotto"),
    ("A10", "chiave attesa diversa dalla chiave del record prodotto"),
    ("A11", "record atteso oltre la fine del file"),
    ("A12", "chiavi ripetute negli attesi a mano"),
    ("A13", "valore numerico illeggibile negli attesi a mano"),
    ("A14", "esadecimale illeggibile negli attesi a mano"),
])


class Esito:
    def __init__(self):
        self.errori = []
        self.siti = []   # (file, riga, codice) della chiamata: per il censimento delle guardie (negativi.py)

    def errore(self, codice, testo):
        assert codice in CODICI, codice
        f = sys._getframe(1)
        self.errori.append((codice, testo))
        self.siti.append((os.path.basename(f.f_code.co_filename), f.f_lineno, codice))

    def codici(self):
        return {c for c, _ in self.errori}


# --- ingressi ---------------------------------------------------------------------------------------------------------

def _righe_utili(testo):
    return [l for l in testo.split("\n") if l.strip() and not l.startswith("#")]


class Ingressi:
    """Tutto cio' che si legge, caricato una volta. Le prove negative ne alterano una copia privata."""

    def __init__(self, legacy, dc, fixture_dir, cartella):
        self.legacy, self.dc, self.fixture_dir, self.cartella = legacy, dc, fixture_dir, cartella
        with open(os.path.join(cartella, "tabella.tsv"), encoding="utf-8") as f:
            self.tabella = _righe_utili(f.read())
        self.attesi = {}
        d = os.path.join(cartella, "attesi")
        for n in sorted(os.listdir(d)):
            if n.endswith(".record.tsv"):
                with open(os.path.join(d, n), encoding="utf-8") as f:
                    self.attesi[n] = f.read()
        self.dati = {}        # file del legacy letti come byte
        self.testi = {}       # file del legacy letti come testo (JCL)
        self.fixture = {}     # fixture di #5 per nome del file d'origine
        self.contratti = {}

    def byte(self, path):
        if path not in self.dati:
            with open(os.path.join(self.legacy, path), "rb") as f:
                self.dati[path] = f.read()
        return self.dati[path]

    def testo(self, path):
        if path not in self.testi:
            with open(os.path.join(self.legacy, path), encoding="latin-1") as f:
                self.testi[path] = f.read().split("\n")
        return self.testi[path]

    def testo_fixture(self, nome):
        if nome not in self.fixture:
            p = os.path.join(self.fixture_dir, nome + ".tsv")
            if not os.path.isfile(p):
                return None
            with open(p, encoding="utf-8") as f:
                self.fixture[nome] = f.read()
        return self.fixture[nome]

    def contratto(self, nome):
        if nome not in self.contratti:
            righe = righe_contratto(os.path.join(self.dc, "contratti", nome + ".tsv"))
            ordina_contratto(righe)
            self.contratti[nome] = righe
        return self.contratti[nome]

    def copia(self):
        c = copy.copy(self)
        c.tabella = list(self.tabella)
        for k in ("attesi", "dati", "testi", "fixture"):
            setattr(c, k, dict(getattr(self, k)))
        c.contratti = {k: copy.deepcopy(v) for k, v in self.contratti.items()}
        return c


def voci_tabella(ing, es):
    """Righe della tabella come dict, con i numeri convertiti; righe difettose scartate dopo l'errore."""
    if not ing.tabella:
        es.errore("T05", "tabella.tsv: nessuna riga")
        return []
    testa = ing.tabella[0].split("\t")
    if testa != TESTA_TABELLA:
        es.errore("T01", f"tabella.tsv: intestazione {testa}, fissata {TESTA_TABELLA}")
        return []
    voci, visti = [], set()
    for r in ing.tabella[1:]:
        c = r.split("\t")
        if len(c) != len(testa):
            es.errore("T02", f"tabella.tsv: riga con {len(c)} colonne invece di {len(testa)}: {r[:80]}")
            continue
        v = dict(zip(testa, c))
        numeri = [k for k in ("chiave_lunghezza", "chiave_offset", "lunghezza_record") if not _INTERO.match(v[k])]
        if numeri:
            es.errore("T03", f"tabella.tsv: {v['dd']}: valori non numerici in {numeri}")
            continue
        for k in ("chiave_lunghezza", "chiave_offset", "lunghezza_record"):
            v[k] = int(v[k])
        if v["dd"] in visti:
            es.errore("T04", f"tabella.tsv: DD {v['dd']} ripetuto")
            continue
        visti.add(v["dd"])
        if v["uscita"] != v["dd"] + ".rec":
            es.errore("T06", f"tabella.tsv: {v['dd']}: uscita '{v['uscita']}', attesa '{v['dd']}.rec'")
            continue
        voci.append(v)
    if len(ing.tabella) == 1:
        es.errore("T07", "tabella.tsv: solo l'intestazione")
    return voci


def campi_contratto(ing, voce, es):
    """Campi elementari della vista base del contratto, in ordine di offset, con categoria, variante e geometria."""
    try:
        righe = vista_contratto(ing.contratto(voce["contratto"]), "base")
        campi = []
        for r in sorted(righe, key=lambda x: int(x["offset"])):
            cat, var, g = classifica_riga(r, voce["contratto"])
            campi.append({"nome": r["campo"], "offset": int(r["offset"]), "lunghezza": g.lunghezza, "categoria": cat,
                          "variante": var, "scala": g.decimali})
    except (OSError, ValueError, SystemExit, codec.CodificaErrore) as e:
        es.errore("G02", f"{voce['dd']}: contratto {voce['contratto']}: {e}")
        return None
    pos = 0
    for c in campi:
        if c["offset"] != pos:
            es.errore("G03", f"{voce['dd']}: {c['nome']} all'offset {c['offset']}, atteso {pos}")
            return None
        pos += c["lunghezza"]
    if pos != voce["lunghezza_record"]:
        es.errore("G11", f"{voce['dd']}: i campi coprono {pos} byte, il record ne ha {voce['lunghezza_record']}")
        return None
    return campi


# --- generazione --------------------------------------------------------------------------------------------------------

DECODIFICA = codec.decodifica     # sostituibili solo dalle prove negative
CODIFICA = codec.codifica


class Prodotto:
    def __init__(self, voce, campi):
        self.voce, self.campi, self.record = voce, campi, []

    def byte(self):
        return b"".join(self.record)


def ricodifica_campo(voce, n, c, rec, es):
    """Byte del campo nel profilo dell'oracle, o None dopo un errore."""
    chi = f"{voce['dd']}#{n} {c['nome']}"
    ris = DECODIFICA(ORIGINE, c["categoria"], c["variante"], rec, c["offset"])
    if ris.stato != "valido":
        es.errore("G04", f"{chi}: stato {ris.stato} nel profilo {ORIGINE}, byte {a_esa(ris.originali)}")
        return None
    try:
        canonico = CODIFICA(ORIGINE, c["categoria"], c["variante"], ris.valore)
        nuovo = CODIFICA(ORACLE, c["categoria"], c["variante"], ris.valore)
    except codec.CodificaErrore as e:
        es.errore("G06", f"{chi}: valore {ris.valore!r} non codificabile: {e}")
        return None
    if canonico != ris.originali:
        es.errore("G05", f"{chi}: byte {a_esa(ris.originali)}, rappresentazione canonica {a_esa(canonico)}: "
                         f"ricodificarlo normalizzerebbe il campo")
        return None
    if len(nuovo) != c["lunghezza"]:
        es.errore("G07", f"{chi}: {len(nuovo)} byte nel profilo {ORACLE}, il campo ne ha {c['lunghezza']}")
        return None
    return nuovo


def genera_voce(ing, voce, es):
    """Record di una voce della tabella nel profilo dell'oracle. Il controllo 1 (tabella contro JCL e contratto) viene
    PRIMA della generazione: una tabella che non coincide con il JCL non produce nulla."""
    n0 = len(es.errori)
    campi = campi_contratto(ing, voce, es)
    controllo_jcl(ing, voce, es)
    controllo_contratto(ing, voce, es)
    if campi is None or len(es.errori) > n0:
        return None
    dati = ing.byte(voce["origine"])
    L = voce["lunghezza_record"]
    if len(dati) % L:
        es.errore("G01", f"{voce['origine']}: {len(dati)} byte, non multiplo di {L}")
        return None
    if not dati:
        es.errore("G10", f"{voce['origine']}: vuoto")
        return None
    p = Prodotto(voce, campi)
    for i in range(0, len(dati), L):
        rec, n = dati[i:i + L], i // L + 1
        pezzi = [ricodifica_campo(voce, n, c, rec, es) for c in campi]
        if any(x is None for x in pezzi):
            return None
        p.record.append(b"".join(pezzi))
    a, k = voce["chiave_offset"], voce["chiave_lunghezza"]
    chiavi = [r[a:a + k] for r in p.record]
    for n in range(1, len(chiavi)):
        if chiavi[n] == chiavi[n - 1]:
            es.errore("G08", f"{voce['dd']}: chiave {chiavi[n].decode('latin-1')} ripetuta ai record {n} e {n + 1}: "
                             f"REPRO su un KSDS vuoto la rifiuterebbe, comportamento del legacy da decidere "
                             f"(needs-spec-update)")
            return None
        if chiavi[n] < chiavi[n - 1]:
            es.errore("G09", f"{voce['dd']}: chiave del record {n + 1} ({chiavi[n].decode('latin-1')}) minore della "
                             f"precedente: REPRO su un KSDS vuoto richiede chiavi crescenti (needs-spec-update)")
            return None
    return p


def genera(ing, es):
    prodotti = []
    for voce in voci_tabella(ing, es):
        p = genera_voce(ing, voce, es)
        if p is not None:
            prodotti.append(p)
    return prodotti


def elenco(voce, dati):
    """Elenco leggibile del file prodotto: record, chiave, SHA-256 dei byte del record."""
    L, a, k = voce["lunghezza_record"], voce["chiave_offset"], voce["chiave_lunghezza"]
    righe = [f"# {voce['uscita']} (issue #53): {len(dati) // L} record di {L} byte senza terminatori, nell'ordine di "
             f"{voce['origine']}; chiave nei byte {a + 1}-{a + k}",
             "record\tchiave\tsha256"]
    for i in range(0, len(dati), L):
        r = dati[i:i + L]
        righe.append(f"{i // L + 1}\t{r[a:a + k].decode('latin-1')}\t{hashlib.sha256(r).hexdigest()}")
    return "\n".join(righe) + "\n"


def scrivi(prodotti, out):
    os.makedirs(out)
    for p in prodotti:
        with open(os.path.join(out, p.voce["uscita"]), "wb") as f:
            f.write(p.byte())
        with open(os.path.join(out, p.voce["dd"] + ".elenco.tsv"), "w", encoding="utf-8") as f:
            f.write(elenco(p.voce, p.byte()))


# --- verifica (sui file scritti) ----------------------------------------------------------------------------------------

def rif(r, es):
    m = _RIF.match(r)
    if not m:
        es.errore("J01", f"riferimento al JCL non valido: '{r}'")
        return None
    return m.group(1), int(m.group(2))


def riga_jcl(ing, path, n, es):
    try:
        righe = ing.testo(path)
    except OSError as e:
        es.errore("J15", f"{path}: {e}")
        return None
    if n > len(righe):
        es.errore("J16", f"{path}: riga {n} oltre la fine ({len(righe)} righe)")
        return None
    return righe[n - 1]


def controllo_jcl(ing, voce, es):
    """Controllo 1: chiave e lunghezza della tabella rilette dal JCL e confrontate con il contratto."""
    rk, rl = rif(voce["rif_chiave"], es), rif(voce["rif_lunghezza"], es)
    if rk is None or rl is None:
        return
    if rk[0] != rl[0]:
        es.errore("J07", f"{voce['dd']}: KEYS da {rk[0]}, RECORDSIZE da {rl[0]}")
        return
    path = rk[0]
    lk, ll = riga_jcl(ing, path, rk[1], es), riga_jcl(ing, path, rl[1], es)
    if lk is None or ll is None:
        return
    mk, ml = _KEYS.search(lk), _RECSIZE.search(ll)
    if not mk:
        es.errore("J02", f"{path}:{rk[1]}: nessun KEYS(lunghezza offset): {lk.strip()}")
    elif (int(mk.group(1)), int(mk.group(2))) != (voce["chiave_lunghezza"], voce["chiave_offset"]):
        es.errore("J03", f"{path}:{rk[1]}: KEYS({mk.group(1)} {mk.group(2)}), tabella "
                         f"({voce['chiave_lunghezza']} {voce['chiave_offset']})")
    if not ml:
        es.errore("J04", f"{path}:{rl[1]}: nessun RECORDSIZE(media massima): {ll.strip()}")
    else:
        if int(ml.group(1)) != voce["lunghezza_record"]:
            es.errore("J05", f"{path}:{rl[1]}: RECORDSIZE medio {ml.group(1)}, tabella {voce['lunghezza_record']}")
        if int(ml.group(2)) != voce["lunghezza_record"]:
            es.errore("J06", f"{path}:{rl[1]}: RECORDSIZE massimo {ml.group(2)}, tabella {voce['lunghezza_record']}")
    righe = ing.testo(path)
    nome = cluster(righe, rk[1], rl[1])
    if nome is None:
        es.errore("J08", f"{path}: righe {rk[1]} e {rl[1]} non nello stesso DEFINE CLUSTER")
    repro = [(i, m) for i, l in enumerate(righe, 1) for m in [_REPRO.search(l)] if m]
    if len(repro) != 1:
        es.errore("J09", f"{path}: {len(repro)} REPRO INFILE(...) OUTFILE(...)")
        return
    dsn = dsn_dd(righe)
    if nome is not None and dsn.get(repro[0][1].group(2)) != nome:
        es.errore("J10", f"{path}: OUTFILE({repro[0][1].group(2)}) indica {dsn.get(repro[0][1].group(2))}, il "
                         f"cluster definito e' {nome}")
    origine = voce["origine"].rsplit("/", 1)[-1]
    if dsn.get(repro[0][1].group(1)) != origine:
        es.errore("J11", f"{path}: INFILE({repro[0][1].group(1)}) indica {dsn.get(repro[0][1].group(1))}, la tabella "
                         f"carica {origine}")


def controllo_contratto(ing, voce, es):
    """Controllo 1, seconda parte: lunghezza e chiave della tabella contro il contratto di #3. Un contratto illeggibile
    e' gia' l'errore G02 di campi_contratto: qui non si ripete."""
    try:
        righe = ing.contratto(voce["contratto"])
    except (OSError, ValueError, SystemExit):
        return
    tot = [r for r in righe if r["livello"] == "01"]
    if len(tot) != 1:
        es.errore("J14", f"{voce['contratto']}: {len(tot)} righe di livello 01")
    elif int(tot[0]["lunghezza"]) != voce["lunghezza_record"]:
        es.errore("J12", f"{voce['contratto']}: lunghezza {tot[0]['lunghezza']}, tabella {voce['lunghezza_record']}")
    chiave = [r for r in righe if r["tipo"] == "elementare" and r["area"] == "-"
              and int(r["offset"]) == voce["chiave_offset"] and int(r["lunghezza"]) == voce["chiave_lunghezza"]]
    if not chiave:
        es.errore("J13", f"{voce['contratto']}: nessun campo elementare nei byte {voce['chiave_offset']}+"
                         f"{voce['chiave_lunghezza']}")


def cluster(righe, *numeri):
    """Nome del DEFINE CLUSTER che contiene tutte le righe date (stesso enunciato di IDCAMS: nessun '/*' o '//' fra
    l'inizio del DEFINE e la riga), None se non c'e'."""
    nomi = set()
    for n in numeri:
        trovato = None
        for i in range(n, 0, -1):
            l = righe[i - 1]
            m = _NAME.search(l)
            if m:
                trovato = m.group(1)
                break
            if l.startswith("/*") or l.startswith("//"):
                break
        nomi.add(trovato)
    return nomi.pop() if len(nomi) == 1 else None


def dsn_dd(righe):
    """DSN di ogni DD del JCL: la DD inizia con '//NOME DD', continua sulle righe '//' senza nome."""
    out, dd = {}, None
    for l in righe:
        m = _DD.match(l)
        if m:
            dd = m.group(1)
        elif not l.startswith("//         ") and not l.startswith("//*"):
            dd = None
        if dd is None:
            continue
        d = _DSN.search(l)
        if d and dd not in out:
            out[dd] = d.group(1)
    return out


def leggi_fixture(ing, voce, campi, es):
    """Fixture di #5 del file d'origine: {numero di record: [(nome, stato, valore)]}."""
    nome = voce["origine"].rsplit("/", 1)[-1]
    testo = ing.testo_fixture(nome)
    attesa = f"# fixture di {voce['origine']} (issue #5): contratto {voce['contratto']}, profilo {ORIGINE}, "
    if testo is None or not testo.startswith(attesa):
        es.errore("F01", f"fixture di {nome}: assente o intestazione diversa da '{attesa}...'")
        return None
    out = {}
    for l in _righe_utili(testo):
        c = l.split("\t")
        if len(c) < 5 or not _INTERO.match(c[0]):
            es.errore("F06", f"fixture di {nome}: riga malformata: {l[:80]}")
            return None
        if int(c[0]) in out:
            es.errore("F08", f"fixture di {nome}: record {c[0]} ripetuto")
            return None
        campi_f = []
        for x in c[5:]:
            p = x.split("|")
            if len(p) > 4 and p[-1] in ("riempimento", "misto"):
                p = p[:-1]
            if len(p) < 4:
                es.errore("F07", f"fixture di {nome}: campo malformato: {x[:80]}")
                return None
            campi_f.append((p[0], p[1], "|".join(p[2:-1])))
        out[int(c[0])] = campi_f
    return out


def controllo_fixture(ing, voce, campi, dati, es):
    """Controllo 2: ogni campo del record prodotto, ridecodificato nel profilo dell'oracle, ha lo stato e il valore
    della fixture EBCDIC di #5 (letta, non rigenerata)."""
    fix = leggi_fixture(ing, voce, campi, es)
    if fix is None or campi is None:
        return
    L = voce["lunghezza_record"]
    n = len(dati) // L
    if sorted(fix) != list(range(1, n + 1)):
        es.errore("F02", f"{voce['dd']}: record della fixture {min(fix, default=0)}..{max(fix, default=0)} "
                         f"({len(fix)}), prodotti {n}")
        return
    nomi = [c["nome"] for c in campi]
    for k in range(1, n + 1):
        rec = dati[(k - 1) * L:k * L]
        if [x[0] for x in fix[k]] != nomi:
            es.errore("F03", f"{voce['dd']}#{k}: campi della fixture {[x[0] for x in fix[k]]}, contratto {nomi}")
            continue
        for c, (_, stato_f, valore_f) in zip(campi, fix[k]):
            ris = codec.decodifica(ORACLE, c["categoria"], c["variante"], rec, c["offset"])
            if ris.stato != stato_f:
                es.errore("F04", f"{voce['dd']}#{k} {c['nome']}: stato {ris.stato}, fixture {stato_f}")
                continue
            v = "-" if ris.stato != "valido" else valore_a_testo(ris.valore, None if isinstance(ris.valore, str)
                                                                     else c["scala"])
            if v != valore_f:
                es.errore("F05", f"{voce['dd']}#{k} {c['nome']}: valore {v}, fixture {valore_f}")


def controllo_chiavi(ing, voce, dati, es):
    """Controllo 4: 50 record (quanti nel file d'origine), chiavi uniche e strettamente crescenti nell'ordine del file."""
    L, a, k = voce["lunghezza_record"], voce["chiave_offset"], voce["chiave_lunghezza"]
    if len(dati) % L:
        es.errore("K01", f"{voce['uscita']}: {len(dati)} byte, non multiplo di {L}")
        return False
    n_orig = len(ing.byte(voce["origine"])) // L
    if len(dati) // L != n_orig:
        es.errore("K02", f"{voce['uscita']}: {len(dati) // L} record, il file d'origine ne ha {n_orig}")
    chiavi = [dati[i + a:i + a + k] for i in range(0, len(dati), L)]
    for n in range(1, len(chiavi)):
        if chiavi[n] == chiavi[n - 1]:
            es.errore("K03", f"{voce['uscita']}: chiave {chiavi[n].decode('latin-1')} ai record {n} e {n + 1}")
        elif chiavi[n] < chiavi[n - 1]:
            es.errore("K04", f"{voce['uscita']}: chiave del record {n + 1} minore della precedente")
    return True


def leggi_attesi(ing, voce, es):
    nome = voce["dd"] + ".record.tsv"
    testo = ing.attesi.get(nome)
    righe = _righe_utili(testo) if testo is not None else []
    if not righe or righe[0].split("\t") != TESTA_ATTESI:
        es.errore("A01", f"attesi/{nome}: assente o intestazione diversa da {TESTA_ATTESI}")
        return None
    out = []
    for r in righe[1:]:
        c = r.split("\t")
        if len(c) != len(TESTA_ATTESI):
            es.errore("A02", f"attesi/{nome}: {len(c)} colonne invece di {len(TESTA_ATTESI)}: {r[:80]}")
            return None
        v = dict(zip(TESTA_ATTESI, c))
        numeri = [x for x in ("record", "offset", "lunghezza") if not _INTERO.match(v[x])]
        if numeri:
            es.errore("A13", f"attesi/{nome}: {numeri} non numerici: {r[:80]}")
            return None
        for x in ("record", "offset", "lunghezza"):
            v[x] = int(v[x])
        try:
            v["ebcdic"], v["oracle"] = da_esa(v["ebcdic"]), da_esa(v["oracle"])
        except ValueError as e:
            es.errore("A14", f"attesi/{nome}: {e}: {r[:80]}")
            return None
        out.append(v)
    return out


def controllo_attesi(ing, voce, campi, dati, es):
    """Controllo 5: i cinque record scritti a mano coincidono, campo per campo, con i byte EBCDIC del file d'origine e
    con i byte del file prodotto."""
    att = leggi_attesi(ing, voce, es)
    if att is None or campi is None:
        return
    L, a, k = voce["lunghezza_record"], voce["chiave_offset"], voce["chiave_lunghezza"]
    orig = ing.byte(voce["origine"])
    n = len(dati) // L
    per_rec = OrderedDict()
    for v in att:
        per_rec.setdefault(v["record"], []).append(v)
    chiavi = {v["chiave"] for v in att}
    if len(per_rec) != 3 + RECORD_A_SCELTA:
        es.errore("A03", f"attesi/{voce['dd']}.record.tsv: {len(per_rec)} record, attesi {3 + RECORD_A_SCELTA} (primo, "
                         f"ultimo, chiave {CHIAVE_DIFFERENZA} e {RECORD_A_SCELTA} a scelta)")
    if len(chiavi) != len(per_rec):
        es.errore("A12", f"attesi/{voce['dd']}.record.tsv: {len(chiavi)} chiavi distinte per {len(per_rec)} record")
    if 1 not in per_rec:
        es.errore("A04", f"attesi/{voce['dd']}.record.tsv: manca il primo record")
    if n not in per_rec:
        es.errore("A05", f"attesi/{voce['dd']}.record.tsv: manca l'ultimo record ({n})")
    if str(CHIAVE_DIFFERENZA).zfill(k) not in chiavi:
        es.errore("A06", f"attesi/{voce['dd']}.record.tsv: manca il record con chiave {CHIAVE_DIFFERENZA}")
    attesi_campi = [(c["nome"], c["offset"], c["lunghezza"]) for c in campi]
    for r, righe in per_rec.items():
        if not 1 <= r <= n:
            es.errore("A11", f"attesi: record {r} oltre la fine del file ({n} record)")
            continue
        if [(v["campo"], v["offset"], v["lunghezza"]) for v in righe] != attesi_campi:
            es.errore("A07", f"attesi: record {r}: campi {[(v['campo'], v['offset']) for v in righe]} diversi dal "
                             f"contratto")
            continue
        po, pp = orig[(r - 1) * L:r * L], dati[(r - 1) * L:r * L]
        for v in righe:
            o, l = v["offset"], v["lunghezza"]
            if v["ebcdic"] != po[o:o + l]:
                es.errore("A08", f"attesi: record {r} {v['campo']}: EBCDIC atteso {a_esa(v['ebcdic'])}, nel file "
                                 f"{a_esa(po[o:o + l])}")
            if v["oracle"] != pp[o:o + l]:
                es.errore("A09", f"attesi: record {r} {v['campo']}: atteso {a_esa(v['oracle'])}, prodotto "
                                 f"{a_esa(pp[o:o + l])}")
        if {v["chiave"] for v in righe} != {pp[a:a + k].decode("latin-1")}:
            es.errore("A10", f"attesi: record {r}: chiavi attese {sorted({v['chiave'] for v in righe})}, prodotta "
                             f"{pp[a:a + k].decode('latin-1')}")


def verifica(ing, out, es):
    """Controlli 2, 4, 5 ed elenco, sui file di out/ letti dal disco (il controllo 1 precede la generazione).
    Restituisce i riepiloghi per il documento."""
    riepiloghi = []
    for voce in voci_tabella(ing, es):
        campi = campi_contratto(ing, voce, es)
        p = os.path.join(out, voce["uscita"])
        if not os.path.isfile(p):
            es.errore("K05", f"{voce['uscita']}: assente in out/")
            continue
        with open(p, "rb") as f:
            dati = f.read()
        if not controllo_chiavi(ing, voce, dati, es):
            continue
        controllo_fixture(ing, voce, campi, dati, es)
        controllo_attesi(ing, voce, campi, dati, es)
        pe = os.path.join(out, voce["dd"] + ".elenco.tsv")
        scritto = None
        if os.path.isfile(pe):
            with open(pe, encoding="utf-8") as f:
                scritto = f.read()
        if scritto != elenco(voce, dati):
            es.errore("E01", f"{voce['dd']}.elenco.tsv: assente o diverso da quello ricalcolato da {voce['uscita']}")
        riepiloghi.append((voce, campi, dati))
    return riepiloghi
