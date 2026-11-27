"""Asserzioni della verifica delle fixture (issue #5). Ogni asserzione scrive un errore con un codice di fixture.CODICI."""
import hashlib
import os
import re
from collections import Counter
from decimal import Decimal

import fixture as fx
from fixture import base_nome, tabella, testo_valore


def _confina(testo, nome):
    """Il nome compare come parola intera (prima e dopo: niente lettere, cifre o punti)."""
    return re.search(r"(?<![A-Za-z0-9.])" + re.escape(nome) + r"(?![A-Za-z0-9.])", testo) is not None


def _rif(ref):
    f, _, n = ref.rpartition(":")
    return f, int(n)


# --- inventario -------------------------------------------------------------------------------------------------------

def verifica_inventario(ing, voci, es):
    presenti = {p for p, t in ing.manifesto if t == "data" and fx._codifica_cartella(p)}
    nomi = Counter(v["file"] for v in voci)
    for p, n in nomi.items():
        if n > 1:
            es.errore("I03", f"{p}: {n} voci nell'inventario")
    for p in sorted(presenti - set(nomi)):
        es.errore("I01", f"{p}: file dati del manifesto senza voce nell'inventario")
    for p in sorted(set(nomi) - presenti):
        es.errore("I02", f"{p}: voce dell'inventario senza file dati nel manifesto")
    contr = {r["contratto"]: r for r in ing.contratti_tsv}
    file_tsv = {r["dataset"]: r["contratto"] for r in ing.file_tsv}
    per_file = {v["file"]: v for v in voci}
    jcl = [p for p, t in ing.manifesto if t in ("jcl", "proc")]
    for v in voci:
        p = v["file"]
        if v["codifica"] != fx._codifica_cartella(p) or v["provenienza"] not in fx.PROVENIENZE:
            es.errore("I03", f"{p}: codifica {v['codifica']} o provenienza {v['provenienza']} non ammesse")
            continue
        c = contr.get(v["contratto"])
        if c is None or c["lunghezza"] != v["lunghezza"]:
            es.errore("I04", f"{p}: contratto {v['contratto']} sconosciuto o lunghezza {v['lunghezza']} diversa da "
                             f"{c['lunghezza'] if c else '?'}")
        if v["dataset"] != "-" and file_tsv.get(v["dataset"]) != v["contratto"]:
            es.errore("I05", f"{p}: contratto {v['contratto']}, ma file.tsv da' {file_tsv.get(v['dataset'])} per "
                             f"{v['dataset']}")
        # corrispondenze: simmetriche, codifica opposta, stesso contratto, lunghezza e dataset
        if v["corrispondente"] != "-":
            for q in v["corrispondente"].split(","):
                w = per_file.get(q)
                if (w is None or w["codifica"] == v["codifica"] or p not in w["corrispondente"].split(",")
                        or (w["contratto"], w["lunghezza"], w["dataset"]) != (v["contratto"], v["lunghezza"],
                                                                                v["dataset"])):
                    es.errore("I06", f"{p}: corrispondenza con {q} non simmetrica o incoerente")
        # provenienza
        nome = base_nome(p)
        if v["provenienza"] in ("carica", "consuma"):
            try:
                f, n = _rif(v["riga"])
                righe = ing.testo(f)
                ok = _confina(righe[n - 1], "DSN=" + nome)
                if v["provenienza"] == "carica":
                    tutto = "\n".join(righe)
                    ok = ok and _confina(tutto, "DSN=" + v["dataset"]) and "REPRO" in tutto
                else:
                    ok = ok and any(a["dataset"] == nome and a["jcl"] == f and a["riga_dsn"] == str(n)
                                    for a in ing.assegnazioni)
            except (ValueError, OSError, IndexError):
                ok = False
            if not ok:
                es.errore("I07", f"{p}: provenienza {v['provenienza']} {v['riga']} non riscontrata")
        else:
            chi = [j for j in jcl if _confina("\n".join(ing.testo(j)), nome)]
            if v["riga"] != "-" or chi:
                es.errore("I08", f"{p}: dichiarato senza caricatore, ma lo nominano {chi or v['riga']}")
        verifica_chiave(ing, v, es)


def verifica_chiave(ing, v, es):
    p = v["file"]
    prim = [r for r in ing.chiavi_tsv if r["dataset"] == v["dataset"] and r["chiave"] == "primaria"
            and r["fonte"] == "JCL DEFINE CLUSTER"]
    if v["fonte_chiave"] == "scelta":
        if prim:
            es.errore("I09", f"{p}: chiave dichiarata come scelta, ma {v['dataset']} ha la chiave primaria "
                             f"{prim[0]['riferimento']}")
        return
    r = [x for x in prim if x["riferimento"] == v["fonte_chiave"]]
    if not r:
        es.errore("I09", f"{p}: nessuna chiave primaria di {v['dataset']} in {v['fonte_chiave']} (chiavi.tsv)")
        return
    off, lun = int(r[0]["offset"]), int(r[0]["lunghezza"])
    m = fx._SPAN.match(v["chiave"])
    if m:
        span = (int(m.group(1)), int(m.group(2)))
    else:
        try:
            campi = {c["campo"]: c for c in fx.campi_vista(ing, v["contratto"], "base", es) or []}
            parti = [campi[n] for n in v["chiave"].split("+")]
            a = int(parti[0]["offset"])
            fine = a
            for c in parti:
                if int(c["offset"]) != fine:
                    raise KeyError(c["campo"])
                fine += int(c["lunghezza"])
            span = (a, fine - a)
        except KeyError as e:
            es.errore("I09", f"{p}: chiave {v['chiave']}: campo {e} assente o non contiguo")
            return
    if span != (off, lun):
        es.errore("I09", f"{p}: chiave {v['chiave']} = byte {span}, la KEYS di {v['fonte_chiave']} = {(off, lun)}")


# --- fisica -------------------------------------------------------------------------------------------------------

def _espandi(testo):
    out = []
    for pezzo in testo.split(","):
        val, _, rng = pezzo.rpartition(":")
        a, _, b = rng.partition("-")
        out += [(int(a) + i, val) for i in range(int(b or a) - int(a) + 1)]
    return out


def verifica_fisica(ing, voci, es):
    fis = {r["file"]: r for r in tabella(ing.fisica, es, "F09", "fisica.tsv")}
    per_file = {v["file"]: v for v in voci}
    for p in sorted(set(per_file) ^ set(fis)):
        es.errore("F09", f"{p}: voce {'mancante' if p in per_file else 'in piu'} in fisica.tsv")
    for p in sorted(set(per_file) & set(fis)):
        v, f = per_file[p], fis[p]
        if p not in ing.dati:
            continue
        d = ing.dati[p]
        try:
            if int(f["dimensione"]) != len(d):
                es.errore("F01", f"{p}: dimensione {len(d)}, fisica.tsv {f['dimensione']}")
            if hashlib.sha256(d).hexdigest() != f["impronta"]:
                es.errore("F02", f"{p}: impronta diversa da fisica.tsv")
            L = int(v["lunghezza"])
            if v["codifica"] == "EBCDIC":
                if len(d) % L:
                    es.errore("F03", f"{p}: {len(d)} byte non divisibili per {L}")
                if len(d) // L != int(f["record"]):
                    es.errore("F04", f"{p}: {len(d) // L} record dalla dimensione, fisica.tsv {f['record']}")
                continue
            righe = fx.fisica_ascii(d)
            if len(righe) != int(f["record"]):
                es.errore("F04", f"{p}: {len(righe)} righe fisiche, fisica.tsv {f['record']}")
            term = [t for _, t in righe]
            if [x for _, x in _espandi(f["terminatori"])] != term or [n for n, _ in _espandi(f["terminatori"])] != \
                    list(range(1, len(term) + 1)):
                es.errore("F05", f"{p}: terminatori {fx.intervalli(term)}, fisica.tsv {f['terminatori']}")
            coda = sum(len(r) for r, t in righe if t == "nessuno")
            if coda != int(f["coda"]):
                es.errore("F06", f"{p}: {coda} byte dopo l'ultimo terminatore, fisica.tsv {f['coda']}")
            lun = [str(len(r)) for r, t in righe if t != "nessuno"]
            if fx.intervalli(lun) != f["lunghezze"]:
                es.errore("F07", f"{p}: lunghezze {fx.intervalli(lun)}, fisica.tsv {f['lunghezze']}")
            # riconciliazione dalle sole colonne scritte a mano
            somma = sum(int(x) for _, x in _espandi(f["lunghezze"]))
            peso = {"CRLF": 2, "LF": 1}
            somma += sum(peso.get(x, 0) for _, x in _espandi(f["terminatori"])) + int(f["coda"])
            if somma != int(f["dimensione"]):
                es.errore("F08", f"{p}: righe + terminatori + coda = {somma}, dimensione {f['dimensione']}")
        except (ValueError, KeyError) as e:
            es.errore("F09", f"{p}: voce di fisica.tsv illeggibile ({e})")


# --- viste dell'export --------------------------------------------------------------------------------------------

def verifica_viste(ing, es):
    viste = fx.viste_export(ing, es)
    src = "app/cbl/CBIMPORT.cbl"
    righe = ing.testo(src)
    ev = [i for i, l in enumerate(righe) if re.search(r"\bEVALUATE\s+EXPORT-REC-TYPE\b", l)]
    whens = set()
    if len(ev) == 1:
        for l in righe[ev[0] + 1:]:
            if re.search(r"\bEND-EVALUATE\b", l):
                break
            m = re.search(r"\bWHEN\s+'(.)'", l)
            if m:
                whens.add(m.group(1))
    if whens != set(viste):
        es.errore("V01", f"tipi dichiarati {sorted(viste)}, WHEN di CBIMPORT {sorted(whens)}")
    contratto = ing.contratto(fx.EXPORT)
    aree = {r["area"] for r in contratto if r["redefines"] == "EXPORT-RECORD-DATA"}
    if aree != {r["vista"] for r in viste.values()}:
        es.errore("V04", f"viste dichiarate {sorted(r['vista'] for r in viste.values())}, aree che ridefiniscono "
                         f"EXPORT-RECORD-DATA {sorted(aree)}")
    campi_area = {}
    for r in contratto:
        if r["area"] in aree:
            campi_area.setdefault(r["area"], set()).add(r["campo"])
    for t, r in sorted(viste.items()):
        try:
            n = int(r["riga"])
            ok = (re.search(r"\bWHEN\s+'" + re.escape(t) + "'", righe[n - 1])
                  and re.search(r"\bPERFORM\s+" + re.escape(r["paragrafo"]) + r"\b", righe[n]))
        except (ValueError, IndexError):
            ok = False
        if not ok:
            es.errore("V02", f"tipo {t}: alla riga {r['riga']} di {src} non ci sono WHEN '{t}' e PERFORM "
                             f"{r['paragrafo']}")
            continue
        inizio = [i for i, l in enumerate(righe) if re.match(r"^\s{7,8}" + re.escape(r["paragrafo"]) + r"\.", l)]
        if len(inizio) != 1:
            es.errore("V02", f"tipo {t}: paragrafo {r['paragrafo']} non trovato in {src}")
            continue
        corpo = []
        for l in righe[inizio[0] + 1:]:
            if re.match(r"^\s{7,8}[0-9A-Z][0-9A-Z-]*\.\s*$", l):
                break
            if len(l) > 6 and l[6] != "*":
                corpo.append(l[7:72])
        testo = "\n".join(corpo)
        usate = {a for a, campi in campi_area.items() if any(_confina(testo, c) for c in campi if c != "FILLER")}
        if usate != {r["vista"]}:
            es.errore("V03", f"tipo {t}: {r['paragrafo']} usa campi delle viste {sorted(usate)}, dichiarata "
                             f"{r['vista']}")


def verifica_campi_export(ing, dec, es):
    viste = fx.viste_export(ing, es)
    # comuni ricavati qui dal contratto, indipendentemente da fx.campi_comuni: elementari senza area, tranne il carico
    nomi_comuni = [fx.nome_campo(r) for r in ing.contratto(fx.EXPORT) if r["tipo"] == "elementare"
                   and r["area"] == "-" and r["campo"] != "EXPORT-RECORD-DATA"]
    for p, fd in dec.items():
        if fd.voce["contratto"] != fx.EXPORT:
            continue
        attesi_per_tipo = {}
        for t, r in viste.items():
            area = [fx.nome_campo(x) for x in ing.contratto(fx.EXPORT) if x["area"] == r["vista"]
                    and x["tipo"] == "elementare"]
            attesi_per_tipo[t] = sorted(nomi_comuni + area)
        for rec in fd.record:
            t = rec["byte"][:1].decode("cp037")
            atteso = attesi_per_tipo.get(t, sorted(nomi_comuni))
            if sorted(c.nome for c in rec["campi"]) != atteso:
                es.errore("V05", f"{base_nome(p)}#{rec['n']} tipo {t}: campi emessi diversi da comuni + vista attiva")


# --- attesi a mano ------------------------------------------------------------------------------------------------

def _uguale(att, c):
    if att["stato"] != c.stato:
        return "stato"
    if c.stato != "valido":
        return None
    if att["tipo"] != fx.tipo_valore(c) or type(att["valore"]) is not type(c.valore):
        return "valore"
    if isinstance(c.valore, Decimal):
        if att["valore"] != c.valore or att["valore"].as_tuple().exponent != c.valore.as_tuple().exponent:
            return "valore"
    elif att["valore"] != c.valore:
        return "valore"
    return None


def verifica_attesi(ing, dec, att, confronti, es):
    nomi_dati = {base_nome(p) + ".tsv" for p in dec}
    for n in sorted(set(ing.attesi) - nomi_dati):
        es.errore("D06", f"attesi/{n}: nessun file dati corrispondente")
    for p, fd in dec.items():
        a = att.get(p)
        if a is None:
            es.errore("D06", f"{p}: nessun atteso a mano (attesi/{base_nome(p)}.tsv)")
            continue
        per_n = {r["n"]: r for r in fd.record}
        for n, ra in a.items():
            chi = f"{base_nome(p)}#{n}"
            r = per_n.get(n)
            if r is None:
                es.errore("D05", f"{chi}: record atteso, il file ne ha {len(fd.record)}")
                continue
            if ra["byte"] != r["riga"]:
                es.errore("D03", f"{chi}: byte attesi diversi da quelli del file")
            dc = {c.nome: c for c in r["campi"]}
            if set(dc) != set(ra["campi"]):
                es.errore("D04", f"{chi}: campi attesi {len(ra['campi'])}, decodificati {len(dc)}; mancanti "
                                 f"{sorted(set(dc) - set(ra['campi']))[:4]}, in piu' {sorted(set(ra['campi']) - set(dc))[:4]}")
            for nome in sorted(set(dc) & set(ra["campi"])):
                c, x = dc[nome], ra["campi"][nome]
                d = _uguale(x, c)
                if d == "stato":
                    es.errore("D01", f"{chi} {nome}: atteso {x['stato']}, ottenuto {c.stato} [{fx.a_esa(c.originali)}]")
                elif d == "valore":
                    es.errore("D02", f"{chi} {nome}: atteso {x['tipo']} {x['testo']}, ottenuto {fx.tipo_valore(c)} "
                                     f"{testo_valore(c)}")
                if x["origine"] != c.origine:
                    es.errore("D08", f"{chi} {nome}: origine attesa {x['origine']}, ottenuta {c.origine}")
        dovuti(p, fd, a, confronti, es)


def dovuti(p, fd, a, confronti, es):
    """Record che gli attesi devono contenere, ricavati dai dati e non da un elenco scritto a mano."""
    chi = base_nome(p)
    per_n = {r["n"]: r for r in fd.record}
    if fd.record and (fd.record[0]["n"] not in a or fd.record[-1]["n"] not in a):
        es.errore("D07", f"{chi}: attesi senza il primo o l'ultimo record")

    def neg(r):
        return any(c.stato == "valido" and not isinstance(c.valore, str) and c.valore < 0 for c in r["campi"])
    if any(neg(r) for r in fd.record) and not any(n in per_n and neg(per_n[n]) for n in a):
        es.errore("D07", f"{chi}: il file ha importi negativi, gli attesi nessun record negativo")
    anomali = {int(x[1]) for x in fd.anomalie if x[1] != "-"}
    if anomali and not anomali & set(a):
        es.errore("D07", f"{chi}: il file ha record anomali ({len(anomali)}), gli attesi nessuno")
    if fd.voce["contratto"] == fx.EXPORT:
        tipi = {r["byte"][:1] for r in fd.record}
        coperti = {per_n[n]["byte"][:1] for n in a if n in per_n}
        for t in sorted(tipi - coperti):
            es.errore("D07", f"{chi}: nessun record atteso del tipo {fx.a_esa(t)}")
    for (fa, fe), diff in confronti.items():
        if p not in (fa, fe):
            continue
        lato = 3 if p == fa else 4
        rec = {int(d[lato].split(":")[0].split()[1]) for d in diff
               if d[0] in ("valore-diverso", "stato-diverso", "rappresentazione-diversa")}
        if rec and not rec & set(a):
            es.errore("D07", f"{chi}: differenze ASCII/EBCDIC nei record {sorted(rec)[:5]}, nessuno negli attesi")


# --- elenchi: ricalcolo indipendente ------------------------------------------------------------------------------

def verifica_anomalie(ing, dec, es):
    for p, fd in dec.items():
        chi = base_nome(p)
        el = {(t, r, c) for t, r, c, _ in fd.anomalie}
        trovate = set()
        L = int(fd.voce["lunghezza"])
        if fd.voce["codifica"] == "ASCII":
            # dai soli byte del file: righe e terminatori
            dati = ing.dati[p]
            pezzi = dati.split(b"\n")
            if pezzi and pezzi[-1] == b"":
                pezzi = pezzi[:-1]
            terms = ["CRLF" if x.endswith(b"\r") else "LF" for x in pezzi]
            if not dati.endswith(b"\n") and pezzi:
                terms[-1] = "nessuno"
            for n, x in enumerate(pezzi, 1):
                lung = len(x) - (1 if terms[n - 1] == "CRLF" else 0)
                if lung != L:
                    k = ("riga-corta" if lung < L else "riga-lunga", str(n), "-")
                    trovate.add(k)
                    if k not in el:
                        es.errore("A01", f"{chi}: riga {n} di {lung} byte su {L} assente dalle anomalie")
            conta = Counter(terms)
            if len(conta) > 1:
                magg = conta.most_common(1)[0][0]
                for n, t in enumerate(terms, 1):
                    if t != magg:
                        k = ("terminatore-minoritario", str(n), "-")
                        trovate.add(k)
                        if k not in el:
                            es.errore("A03", f"{chi}: riga {n} con {t} (prevale {magg}) assente dalle anomalie")
        for rec in fd.record:
            for c in rec["campi"]:
                if c.stato != "valido":
                    k = (f"campo-{c.stato}", str(rec["n"]), c.nome)
                    trovate.add(k)
                    if k not in el:
                        es.errore("A02", f"{chi}#{rec['n']} {c.nome}: {c.stato} assente dalle anomalie")
        if fd.voce["contratto"] == fx.EXPORT:
            noti = set(fx.viste_export(ing, es))
            dati = ing.dati[p]
            for i in range(0, len(dati) - L + 1, L):
                t = dati[i:i + 1].decode("cp037")
                if t not in noti:
                    k = ("tipo-export-sconosciuto", str(i // L + 1), "EXPORT-REC-TYPE")
                    trovate.add(k)
                    if k not in el:
                        es.errore("A04", f"{chi}#{i // L + 1}: tipo {t!r} non previsto assente dalle anomalie")
        for k in sorted(el - trovate):
            if k[0] != "chiave-duplicata":
                es.errore("A05", f"{chi}: anomalia {k} senza riscontro")


def verifica_confronti(ing, dec, confronti, es):
    for (fa, fe), diff in confronti.items():
        chi = f"{base_nome(fa)}/{base_nome(fe)}"
        A, E = dec[fa], dec[fe]
        L = int(A.voce["lunghezza"])
        # chiavi dai byte grezzi agli offset della chiave, come caratteri
        campi = {c.nome: c for c in A.record[0]["campi"]} if A.record else {}
        span = []
        for n in A.voce["chiave"].split("+"):
            if n in campi:
                span.append((campi[n].offset, campi[n].lunghezza))

        def chiave_grezza(rec, pagina):
            return "|".join(rec["byte"][o:o + l].decode(pagina) for o, l in span)
        ka = {chiave_grezza(r, "latin-1"): r for r in A.record}
        ke = {chiave_grezza(r, "cp037"): r for r in E.record}
        el = {(d[0], d[2], d[3].split(":")[0], d[4].split(":")[0]) for d in diff}
        solo = {d[0]: set() for d in diff}
        for d in diff:
            solo[d[0]].add(d[3] if d[0] == "solo-ascii" else d[4])
        for k, r in ka.items():
            if k not in ke and f"record {r['n']}" not in solo.get("solo-ascii", set()):
                es.errore("P01", f"{chi}: record ASCII {r['n']} senza corrispondente, assente dalle differenze")
        for k, r in ke.items():
            if k not in ka and f"record {r['n']}" not in solo.get("solo-ebcdic", set()):
                es.errore("P01", f"{chi}: record EBCDIC {r['n']} senza corrispondente, assente dalle differenze")
        coperti = set()
        for k in set(ka) & set(ke):
            ra, re_ = ka[k], ke[k]
            ca = ra["byte"].decode("latin-1")
            ce = re_["byte"].decode("cp037")
            for c in ra["campi"]:
                seg = slice(c.offset, c.offset + c.lunghezza)
                if ca[seg] != ce[seg] or c.origine != "file":
                    chiave_el = (f"record {ra['n']}", f"record {re_['n']}")
                    if not any((t, c.nome) + chiave_el == x for x in el for t in (x[0],)):
                        es.errore("P02", f"{chi}: record {ra['n']}/{re_['n']} {c.nome}: byte diversi o riempiti, "
                                         f"assente dalle differenze")
                    coperti.add((c.nome,) + chiave_el)
        for d in diff:
            if d[0].startswith("solo-"):
                continue
            if (d[2], d[3].split(":")[0], d[4].split(":")[0]) not in coperti:
                es.errore("P03", f"{chi}: differenza {d[0]} {d[2]} {d[3].split(':')[0]} senza riscontro nei byte")


# --- versionati ---------------------------------------------------------------------------------------------------

def verifica_versionati(uscite, cartella, es):
    nomi = set(os.listdir(cartella)) if os.path.isdir(cartella) else set()
    for n, testo in uscite.items():
        try:
            with open(os.path.join(cartella, n), encoding="utf-8") as f:
                vecchio = f.read()
        except OSError:
            vecchio = None
        if vecchio == testo:
            continue
        cod = "X02" if n == "totali.tsv" else ("X01" if n.endswith(".tsv") and not (
            n.endswith(".anomalie.tsv") or n.startswith("confronto-") or n in ("chiavi.tsv", "conteggi.tsv"))
            else "X03")
        es.errore(cod, f"out/{n}: rigenerato diverso dal versionato{' (assente)' if vecchio is None else ''}")
    for n in sorted(nomi - set(uscite) - {"fixture.md"}):
        es.errore("X03", f"out/{n}: file versionato non piu' prodotto")


def verifica(ing, versionati=None):
    es = fx.Esito()
    voci, dec, confronti, att, uscite = fx.genera(ing, es)
    verifica_inventario(ing, voci, es)
    verifica_fisica(ing, voci, es)
    verifica_viste(ing, es)
    verifica_campi_export(ing, dec, es)
    verifica_attesi(ing, dec, att, confronti, es)
    verifica_anomalie(ing, dec, es)
    verifica_confronti(ing, dec, confronti, es)
    if versionati is not None:
        verifica_versionati(uscite, versionati, es)
    return es, voci, dec, confronti, att, uscite
