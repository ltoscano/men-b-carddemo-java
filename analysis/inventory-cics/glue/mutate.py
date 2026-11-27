#!/usr/bin/env python3
"""Per le prove negative: copia graph-cics.json (o out/blocchi.tsv) alterando UN aspetto, come farebbe una colla sbagliata.
Ogni alterazione e' coerente al suo interno (occorrenza, archi e nodi cambiati insieme) quando la colla lo farebbe.
Uso: mutate.py KIND IN OUT"""
import copy
import json
import sys

kind, src, dst = sys.argv[1:4]

# ---------------------------------------------------------------------- alterazioni dell'estrazione (blocchi.tsv)
if kind.startswith("blocchi-"):
    rows = open(src, encoding="utf-8").read().split("\n")
    head, body = rows[0], [r for r in rows[1:] if r]
    if kind == "blocchi-meno-uno":                 # un blocco tolto (COACTUPC, READ UPDATE della riga 3921)
        body = [r for r in body if not r.startswith("app/cbl/COACTUPC.cbl\t3921\t")]
    elif kind == "blocchi-piu-uno":                # un blocco in piu': una copia del READ di COSGN00C su una riga senza EXEC
        r = next(r for r in body if r.startswith("app/cbl/COSGN00C.cbl\t211\t"))
        f = r.split("\t")
        f[1], f[2] = "220", "220"
        body.append("\t".join(f))
    elif kind == "blocchi-doppio":                 # l'estrattore duplica un blocco (COTRN02C:156, il controesempio del Validatore)
        body.append(next(r for r in body if r.startswith("app/cbl/COTRN02C.cbl\t156\t")))
    elif kind == "blocchi-opzione":                # un'opzione alterata nell'estrazione (COSGN00C:211, INTO)
        i = next(k for k, r in enumerate(body) if r.startswith("app/cbl/COSGN00C.cbl\t211\t"))
        assert '"SEC-USER-DATA"' in body[i]
        body[i] = body[i].replace('"SEC-USER-DATA"', '"SEC-USER-DATX"')
    elif kind == "blocchi-commento":               # un blocco su una riga di commento (FIXCICS.cbl:53, file di prova)
        body.append("app/cbl/FIXCICS.cbl\t53\t53\t17\tXCTL\t[[\"PROGRAM\", \"'COMMENTO'\"]]")
    else:
        raise SystemExit("alterazione sconosciuta " + kind)
    open(dst, "w", encoding="utf-8").write("\n".join([head] + body) + "\n")
    sys.exit(0)

g = json.load(open(src, encoding="utf-8"))
O, A, N = g["occorrenze"], g["archi"], g["nodi"]


def occ(file_end, riga, col=None):
    for o in O:
        if o["file"].endswith(file_end) and o["riga"] == riga and (col is None or o["colonna"] == col):
            return o
    raise SystemExit(f"occorrenza non trovata {file_end}:{riga}")


def arcs_of(o):
    return [a for a in A if a["occorrenza"] == o["id"]]


def drop_arcs(o):
    g["archi"] = [a for a in A if a["occorrenza"] != o["id"]]


def tgt(o, ruolo):
    return next(t for t in o["bersagli"] if t["ruolo"] == ruolo)


def add_node(node):
    if not any(n["id"] == node["id"] for n in N):
        N.append(node)


if kind == "categoria-syncpoint":            # SYNCPOINT classificato 'altro' (nessun bersaglio: resta valido per lo schema)
    occ("COACTUPC.cbl", 952)["categoria"] = "altro"
elif kind == "categoria-read-coerente":      # READ classificato 'altro' con bersagli, modalita' e archi tolti come farebbe la colla
    o = occ("COSGN00C.cbl", 211)
    o["categoria"] = "altro"
    for k in ("modalita", "update"):
        o.pop(k)
    o["bersagli"] = []
    drop_arcs(o)
    g["nodi"] = [n for n in N if n["id"] != "cics-file:USRSEC" or any(a["a"] == n["id"] for a in g["archi"])]
elif kind == "letterale-cambiato":           # bersaglio letterale cambiato, arco coerente (COSGN00C:231 COADM01C -> COMEN01C)
    o = occ("COSGN00C.cbl", 231)
    tgt(o, "PROGRAM")["nome"] = "COMEN01C"
    arcs_of(o)[0]["a"] = "program:COMEN01C"
elif kind == "arco-tolto-base":              # arco eliminato con l'occorrenza conservata, verso un nodo di graph.json
    o = occ("COSGN00C.cbl", 231)
    drop_arcs(o)
elif kind == "arco-tolto-nuovo":             # arco eliminato verso un nodo nuovo (il nodo resta con altri archi)
    o = occ("COACTUPC.cbl", 3703)
    drop_arcs(o)
elif kind == "scambio-read-update":          # i bersagli dei due READ UPDATE di COACTUPC scambiati (occorrenze e archi)
    a, b = occ("COACTUPC.cbl", 3894), occ("COACTUPC.cbl", 3921)
    a["bersagli"], b["bersagli"] = b["bersagli"], a["bersagli"]
    aa, bb = arcs_of(a)[0], arcs_of(b)[0]
    aa["a"], bb["a"] = bb["a"], aa["a"]
elif kind == "scambio-solo-archi":           # solo i bersagli degli archi scambiati, occorrenze intatte
    aa, bb = arcs_of(occ("COACTUPC.cbl", 3894))[0], arcs_of(occ("COACTUPC.cbl", 3921))[0]
    aa["a"], bb["a"] = bb["a"], aa["a"]
elif kind == "move-come-costante":           # dato valorizzato con MOVE fatto passare per costante (COCRDLIC:538)
    o = occ("COCRDLIC.cbl", 538)
    t = tgt(o, "PROGRAM")
    t.pop("motivo")
    t.update({"risoluzione": "costante", "nome": "COCRDSLC", "valore": "'COCRDSLC'", "file_valore": "app/cbl/COCRDLIC.cbl", "riga_valore": 196})
    A.append({"id": o["id"] + "#PROGRAM", "occorrenza": o["id"], "da": o["da"], "a": "program:COCRDSLC", "ruolo": "PROGRAM", "comando": o["comando"]})
elif kind == "modificato-come-costante":     # (file di prova) dato con VALUE modificato da MOVE fatto passare per costante
    o = occ("FIXCICS.cbl", 45)
    t = tgt(o, "FILE")
    for k in ("motivo", "modifica"):
        t.pop(k)
    t.update({"risoluzione": "costante", "nome": "ALTRO", "valore": "'ALTRO   '", "file_valore": "app/cbl/FIXCICS.cbl", "riga_valore": 7})
    A.append({"id": o["id"] + "#FILE", "occorrenza": o["id"], "da": o["da"], "a": "cics-file:ALTRO", "ruolo": "FILE", "comando": o["comando"]})
    add_node({"id": "cics-file:ALTRO", "tipo": "cics-file", "nome": "ALTRO"})
elif kind == "costante-non-risolta":         # costante lasciata non risolta (COPAUS1C:248, l'unico LINK), arco tolto
    o = occ("COPAUS1C.cbl", 248)
    t = tgt(o, "PROGRAM")
    for k in ("nome", "valore", "file_valore", "riga_valore"):
        t.pop(k)
    t.update({"risoluzione": "non_risolto", "motivo": "senza-value-letterale"})
    drop_arcs(o)
elif kind == "read-update-scambiati":        # READ e READ UPDATE scambiati (COACTUPC:3703 e 3894)
    a, b = occ("COACTUPC.cbl", 3703), occ("COACTUPC.cbl", 3894)
    a["modalita"], a["update"] = "lettura-update", True
    b["modalita"], b["update"] = "lettura", False
elif kind == "map-mapset-scambiati":         # MAP e MAPSET scambiati (COSGN00C:110), archi e nodi coerenti
    o = occ("COSGN00C.cbl", 110)
    m, s = tgt(o, "MAP"), tgt(o, "MAPSET")
    m["ruolo"], m["opzione"], s["ruolo"], s["opzione"] = "MAPSET", "MAPSET", "MAP", "MAP"
    o["bersagli"] = [s, m]
    for a in arcs_of(o):
        if a["ruolo"] == "MAP":
            a["ruolo"], a["id"], a["a"] = "MAPSET", o["id"] + "#MAPSET", "cics-mapset:COSGN0A"
        else:
            a["ruolo"], a["id"], a["a"] = "MAP", o["id"] + "#MAP", "cics-map:COSGN0A/COSGN00"
    add_node({"id": "cics-mapset:COSGN0A", "tipo": "cics-mapset", "nome": "COSGN0A"})
    add_node({"id": "cics-map:COSGN0A/COSGN00", "tipo": "cics-map", "nome": "COSGN00", "mapset": "COSGN0A"})
elif kind == "arco-nodo-inesistente":        # arco verso un nodo che non esiste
    arcs_of(occ("COSGN00C.cbl", 211))[0]["a"] = "cics-file:NONESISTE"
elif kind == "occorrenza-doppia-riga":       # occorrenza duplicata sulla stessa riga (altra colonna, id coerente)
    o = copy.deepcopy(occ("COSGN00C.cbl", 236))
    o["colonna"] += 1
    o["id"] = f"occ:{o['file']}:{o['riga']}:{o['colonna']}"
    O.append(o)
    A.append({"id": o["id"] + "#PROGRAM", "occorrenza": o["id"], "da": o["da"], "a": "program:COMEN01C", "ruolo": "PROGRAM", "comando": "XCTL"})
elif kind == "occorrenza-doppia-identica":   # la stessa occorrenza due volte
    O.append(copy.deepcopy(occ("COSGN00C.cbl", 236)))
elif kind == "commento-come-blocco":         # (file di prova) un blocco su una riga di commento contato come vero
    O.append({"id": "occ:app/cbl/FIXCICS.cbl:53:17", "file": "app/cbl/FIXCICS.cbl", "riga": 53, "riga_fine": 53, "colonna": 17,
              "da": "program:FIXCICS", "comando": "XCTL", "categoria": "trasferimento", "opzioni": [{"nome": "PROGRAM", "argomento": "'COMMENTO'"}],
              "bersagli": [{"ruolo": "PROGRAM", "opzione": "PROGRAM", "operando": "'COMMENTO'", "risoluzione": "letterale", "nome": "COMMENTO"}]})
    A.append({"id": "occ:app/cbl/FIXCICS.cbl:53:17#PROGRAM", "occorrenza": "occ:app/cbl/FIXCICS.cbl:53:17", "da": "program:FIXCICS",
              "a": "external:COMMENTO", "ruolo": "PROGRAM", "comando": "XCTL"})
    add_node({"id": "external:COMMENTO", "tipo": "external", "nome": "COMMENTO", "origine": "EXEC CICS PROGRAM: programma non presente nel grafo di base"})
elif kind == "tipo-bersaglio-external":      # bersaglio con nome giusto e tipo sbagliato: program:COADM01C -> external:COADM01C
    arcs_of(occ("COSGN00C.cbl", 231))[0]["a"] = "external:COADM01C"
    add_node({"id": "external:COADM01C", "tipo": "external", "nome": "COADM01C", "origine": "EXEC CICS PROGRAM: programma non presente nel grafo di base"})
elif kind == "tipo-bersaglio-transazione":   # TRANSID verso external invece che transaction (CC00 esiste in graph.json)
    arcs_of(occ("COSGN00C.cbl", 98))[0]["a"] = "external:CC00"
    add_node({"id": "external:CC00", "tipo": "external", "nome": "CC00", "origine": "EXEC CICS TRANSID: transazione non presente nel grafo di base"})
elif kind == "riga-valore":                  # riga della VALUE di una costante spostata
    tgt(occ("COSGN00C.cbl", 98), "TRANSID")["riga_valore"] += 1
elif kind == "valore":                       # letterale della VALUE alterato (nome invariato)
    tgt(occ("COSGN00C.cbl", 211), "FILE")["valore"] = "'USRSEC'"
elif kind == "opzione-tolta":                # un'opzione tolta dall'elenco
    occ("COSGN00C.cbl", 151)["opzioni"].pop()
elif kind == "argomento":                    # argomento di un'opzione non di bersaglio alterato
    occ("COSGN00C.cbl", 211)["opzioni"][1]["argomento"] = "SEC-USER-DATX"
elif kind == "riga-fine":                    # riga di END-EXEC alterata
    occ("COSGN00C.cbl", 211)["riga_fine"] += 1
elif kind == "comando":                      # comando cambiato (stessa categoria)
    occ("COSGN00C.cbl", 231)["comando"] = "LINK"
    arcs_of(occ("COSGN00C.cbl", 231))[0]["comando"] = "LINK"
elif kind == "motivo":                       # motivo di un non risolto alterato
    tgt(occ("COACTUPC.cbl", 956), "PROGRAM")["motivo"] = "modificato"
    tgt(occ("COACTUPC.cbl", 956), "PROGRAM")["modifica"] = {"file": "app/cbl/COACTUPC.cbl", "riga": 939}
elif kind == "modifica-falsa":               # (file di prova) la modifica citata non e' una modifica
    tgt(occ("FIXCICS.cbl", 45), "FILE")["modifica"]["riga"] = 40
elif kind == "nodo-mapset":                  # attributo mapset di una mappa alterato
    next(n for n in N if n["tipo"] == "cics-map")["mapset"] = "ALTRO"
elif kind == "nodo-origine":                 # (file di prova) origine di un external alterata
    next(n for n in N if n["id"] == "external:NOPROG")["origine"] = "EXEC CICS TRANSID: transazione non presente nel grafo di base"
elif kind == "nodo-orfano":                  # nodo nuovo senza archi
    N.append({"id": "cics-file:ORFANO", "tipo": "cics-file", "nome": "ORFANO"})
elif kind == "nodo-doppio":                  # nodo nuovo presente due volte
    N.append(copy.deepcopy(N[0]))
elif kind == "nodo-gia-in-base":             # nodo dichiarato qui ma gia' presente in graph.json
    N.append({"id": "external:DFHAID", "tipo": "external", "nome": "DFHAID", "origine": "EXEC CICS PROGRAM: programma non presente nel grafo di base"})
elif kind == "arco-doppio":                  # arco ripetuto
    A.append(copy.deepcopy(A[0]))
elif kind == "da-sbagliato":                 # occorrenza e archi attribuiti a un altro programma
    o = occ("COSGN00C.cbl", 231)
    o["da"] = "program:COMEN01C"
    for a in arcs_of(o):
        a["da"] = "program:COMEN01C"
elif kind in ("redefines-catena-costante", "assign-costante"):   # (file di prova) costante falsa, arco coerente
    o = occ("FIXRDEF.cbl", 49 if kind == "redefines-catena-costante" else 54)
    t = tgt(o, "PROGRAM")
    for k in ("motivo", "modifica"):
        t.pop(k)
    riga = 6 if kind == "redefines-catena-costante" else 33
    t.update({"risoluzione": "costante", "nome": "FIXTGT", "valore": "'FIXTGT'", "file_valore": "app/cbl/FIXRDEF.cbl", "riga_valore": riga})
    A.append({"id": o["id"] + "#PROGRAM", "occorrenza": o["id"], "da": o["da"], "a": "program:FIXTGT", "ruolo": "PROGRAM", "comando": o["comando"]})
elif kind == "categoria-mappa-file":         # bersaglio di tipo sbagliato fra i nodi nuovi: mapset -> file
    o = occ("COSGN00C.cbl", 110)
    for a in arcs_of(o):
        if a["ruolo"] == "MAPSET":
            a["a"] = "cics-file:COSGN00"
    add_node({"id": "cics-file:COSGN00", "tipo": "cics-file", "nome": "COSGN00"})
else:
    raise SystemExit("alterazione sconosciuta " + kind)
json.dump(g, open(dst, "w", encoding="utf-8"), indent=1, ensure_ascii=False, sort_keys=True)
