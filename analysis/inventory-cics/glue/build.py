#!/usr/bin/env python3
"""Costruisce graph-cics.json e inventario-cics.md da out/blocchi.tsv, dal sorgente e dal grafo di base (#2).

Uso: build.py BLOCCHI.tsv REGOLE.txt PROVA.tsv DIAGNOSTICA.tsv OUTDIR
  REGOLE.txt  output di 'CicsLister --regole' (prova che ProLeap espone i blocchi)
  PROVA.tsv   risposta di CicsLister sul file di prova FIXCICS.cbl (prova sul formato fisso)
  DIAGNOSTICA.tsv  file in cui il preprocessore di ProLeap ha segnalato errori di sintassi (da extract.py)"""
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import base_graph, read_lines, sources, stem
from resolve import MOTIVI, Program, Universe, literal_content

CATEGORIA = {}
for _c in ("XCTL", "LINK", "START", "RETURN"):
    CATEGORIA[_c] = "trasferimento"
for _c in ("SEND MAP", "RECEIVE MAP", "SEND TEXT"):
    CATEGORIA[_c] = "mappe"
for _c in ("READ", "WRITE", "REWRITE", "DELETE", "STARTBR", "READNEXT", "READPREV", "ENDBR", "RESETBR", "UNLOCK"):
    CATEGORIA[_c] = "file"
for _c in ("WRITEQ TD", "WRITEQ TS", "READQ TD", "READQ TS", "DELETEQ TD", "DELETEQ TS", "WRITEQ", "READQ", "DELETEQ"):
    CATEGORIA[_c] = "coda"
for _c in ("SYNCPOINT", "SYNCPOINT ROLLBACK", "ABEND"):
    CATEGORIA[_c] = "transazione"
RUOLI = {"trasferimento": {"PROGRAM": "PROGRAM", "TRANSID": "TRANSID"}, "mappe": {"MAP": "MAP", "MAPSET": "MAPSET"},
         "file": {"FILE": "FILE", "DATASET": "FILE"}, "coda": {"QUEUE": "QUEUE", "QNAME": "QUEUE"}}
MODALITA = {"READ": "lettura", "WRITE": "scrittura", "REWRITE": "riscrittura", "DELETE": "cancellazione",
            "STARTBR": "scorrimento-inizio", "READNEXT": "scorrimento-avanti", "READPREV": "scorrimento-indietro",
            "ENDBR": "scorrimento-fine", "RESETBR": "scorrimento-riposizionamento", "UNLOCK": "rilascio"}
ORIGINE = {"PROGRAM": "EXEC CICS PROGRAM: programma non presente nel grafo di base",
           "TRANSID": "EXEC CICS TRANSID: transazione non presente nel grafo di base"}
RESOLVED = ("letterale", "costante")


def die(msg):
    print("COSTRUZIONE: " + msg, file=sys.stderr)
    sys.exit(1)


def read_blocks(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        if next(f).rstrip("\n") != "file\triga\triga_fine\tcolonna\tcomando\topzioni":
            die("intestazione di blocchi.tsv inattesa")
        for l in f:
            p, a, b, c, cmd, opts = l.rstrip("\n").split("\t")
            rows.append((p, int(a), int(b), int(c), cmd, [tuple(x) for x in json.loads(opts)]))
    return rows


def main(blocks_path, rules_path, proof_path, diag_path, outdir):
    base = base_graph()
    bnodes = {n["id"]: n for n in base["nodi"]}
    node_file = {n["id"]: n["file"] for n in base["nodi"] if n["tipo"] == "copybook"}
    copies = defaultdict(list)
    for e in base["archi"]:
        if e["tipo"] == "COPY":
            for o in e["occorrenze"]:
                copies[o["file"]].append((o["riga"], e["a"], o.get("sostituzioni", [])))
    kinds = dict(sources())
    blocks = read_blocks(blocks_path)
    programs = {}

    def program(p):
        if p not in programs:
            programs[p] = Program(Universe(p, read_lines, copies, node_file))
        return programs[p]

    occs, arcs, new_nodes = [], [], {}
    for p, a, b, col, cmd, opts in blocks:
        kind = kinds.get(p)
        if kind not in ("cobol", "copybook"):
            die(f"{p}: non e' un programma o un copybook del manifesto")
        da = ("program:" if kind == "cobol" else "copybook:") + stem(p)
        if da not in bnodes:
            die(f"{p}: il nodo {da} non esiste nel grafo di base")
        cat = CATEGORIA.get(cmd, "altro")
        oid = f"occ:{p}:{a}:{col}"
        occ = {"id": oid, "file": p, "riga": a, "riga_fine": b, "colonna": col, "da": da, "comando": cmd,
               "categoria": cat, "opzioni": [{"nome": k} if v is None else {"nome": k, "argomento": v} for k, v in opts]}
        names = [k for k, _ in opts]
        if cat == "file":
            upd = "UPDATE" in names
            occ["modalita"] = MODALITA[cmd] + ("-update" if upd else "")
            occ["update"] = upd
        if cat == "coda":
            occ["tipo_coda"] = "TD" if "TD" in names else "TS" if "TS" in names else "assente"
        roles = RUOLI.get(cat, {})
        targets = []
        for k, v in opts:
            if k in roles:
                if v is None:
                    die(f"{p}:{a}: l'opzione {k} non ha argomento: needs-spec-update")
                if any(t["opzione"] in roles and roles[t["opzione"]] == roles[k] for t in targets):
                    die(f"{p}:{a}: due operandi per il ruolo {roles[k]}: needs-spec-update")
                t = {"ruolo": roles[k], "opzione": k, "operando": v}
                if kind == "copybook" and literal_content(v) is None:
                    t.update({"risoluzione": "non_risolto", "motivo": "in-copybook"})
                else:
                    t.update(program(p).resolve(v))
                targets.append(t)
        by_role = {t["ruolo"]: t for t in targets}
        if "MAP" in by_role and by_role["MAP"]["risoluzione"] in RESOLVED:
            ms = by_role.get("MAPSET")
            why = "mapset-assente" if ms is None else None if ms["risoluzione"] in RESOLVED else "mapset-non-risolto"
            if why:
                m = by_role["MAP"]
                for k in ("nome", "valore", "file_valore", "riga_valore"):
                    m.pop(k, None)
                m.update({"risoluzione": "non_risolto", "motivo": why})
        if "QUEUE" in by_role and by_role["QUEUE"]["risoluzione"] in RESOLVED and occ["tipo_coda"] == "assente":
            q = by_role["QUEUE"]
            for k in ("nome", "valore", "file_valore", "riga_valore"):
                q.pop(k, None)
            q.update({"risoluzione": "non_risolto", "motivo": "tipo-coda-assente"})
        occ["bersagli"] = targets
        occs.append(occ)
        for t in targets:
            if t["risoluzione"] not in RESOLVED:
                continue
            r, nm = t["ruolo"], t["nome"]
            if r == "PROGRAM":
                tid = "program:" + nm if "program:" + nm in bnodes else "external:" + nm
            elif r == "TRANSID":
                tid = "transaction:" + nm if "transaction:" + nm in bnodes else "external:" + nm
            elif r == "MAPSET":
                tid = "cics-mapset:" + nm
            elif r == "MAP":
                tid = f"cics-map:{by_role['MAPSET']['nome']}/{nm}"
            elif r == "FILE":
                tid = "cics-file:" + nm
            else:
                tid = f"cics-queue:{occ['tipo_coda']}/{nm}"
            arcs.append({"id": f"{oid}#{r}", "occorrenza": oid, "da": da, "a": tid, "ruolo": r, "comando": cmd})
            if tid not in bnodes:
                tipo = tid.split(":", 1)[0]
                node = {"id": tid, "tipo": tipo, "nome": nm}
                if tipo == "external":
                    node["origine"] = ORIGINE[r]
                elif tipo == "cics-map":
                    node["mapset"] = by_role["MAPSET"]["nome"]
                elif tipo == "cics-queue":
                    node["tipo_coda"] = occ["tipo_coda"]
                if tid in new_nodes and new_nodes[tid] != node:
                    die(f"nodo {tid} con attributi diversi da due archi: {new_nodes[tid]} / {node}")
                new_nodes[tid] = node

    graph = {
        "versione_schema": 1,
        "descrizione": "Comandi EXEC CICS di CardDemo (analysis/inventory-cics, issue #22): un'occorrenza per ogni blocco, "
                       "archi per i bersagli scritti nel sorgente (letterali o costanti). I nodi program:, copybook:, "
                       "transaction: ed external: gia' presenti stanno in graph.json; qui solo i nodi nuovi. "
                       "Regole e limiti in inventario-cics.md.",
        "grafo_base": "docs/legacy-map/graph.json",
        "estrattore": "ProLeap COBOL parser d1bfe75, regola execCicsStatement del preprocessore (analysis/inventory-cics/docker/proleap-cics)",
        "nodi": [new_nodes[k] for k in sorted(new_nodes)],
        "occorrenze": occs,
        "archi": arcs,
    }
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "graph-cics.json"), "w", encoding="utf-8") as f:
        json.dump(graph, f, indent=1, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    with open(os.path.join(outdir, "inventario-cics.md"), "w", encoding="utf-8") as f:
        f.write(report(graph, base, kinds, copies, rules_path, proof_path, diag_path))


# ---------------------------------------------------------------------- inventario-cics.md
def fmt_target(t, arcs_of):
    if t["risoluzione"] in RESOLVED:
        a = arcs_of.get(t["ruolo"])
        return f"`{a}` ({t['risoluzione']})"
    return f"`{t['operando']}` non risolto ({t['motivo']})"


def report(g, base, kinds, copies, rules_path, proof_path, diag_path):
    occs, arcs = g["occorrenze"], g["archi"]
    arcs_by_occ = defaultdict(dict)
    for a in arcs:
        arcs_by_occ[a["occorrenza"]][a["ruolo"]] = a["a"]
    by_file = defaultdict(list)
    for o in occs:
        by_file[o["file"]].append(o)
    L = []
    w = L.append
    w("# Inventario dei comandi EXEC CICS di CardDemo\n")
    w("Generato da `./analysis/run.sh inventory-cics` (issue #22): non modificare a mano. Controlli: "
      "`./analysis/run.sh inventory-cics --check`. Il grafo e' `docs/legacy-map/graph-cics.json` (formato in "
      "`graph-cics.schema.json`); fa riferimento ai nodi di `graph.json` (#2) per identificativo e non lo modifica.\n")
    w("## Strumento di estrazione\n")
    rules = [l.rstrip("\n").split("\t") for l in open(rules_path, encoding="utf-8") if l.strip()]
    w("Prima di scrivere un estrattore si e' verificato se ProLeap (gia' adottato in #1 per le COPY) espone i blocchi "
      "`EXEC CICS ... END-EXEC` con riga e testo. Il parser del suo preprocessore ha la regola e i token che servono "
      "(output di `CicsLister --regole` sull'immagine costruita):\n")
    w("| voce | nome | stato |\n| --- | --- | --- |")
    for r in rules:
        w(f"| {r[0]} | `{r[1]}` | {r[2] if len(r) > 2 else 'presente'} |")
    w("")
    proof = [l.rstrip("\n").split("\t") for l in open(proof_path, encoding="utf-8")][1:-1]
    rows68 = [r for r in proof if r[0] == "68"]
    multi = [r for r in proof if r[0] != r[1]]
    w("Sul file di prova `analysis/inventory-cics/fixtures/legacy/app/cbl/FIXCICS.cbl` la colla `CicsLister` (che usa "
      f"solo classi di ProLeap) restituisce {len(proof)} blocchi con riga di `EXEC`, riga di `END-EXEC`, colonna e testo: "
      f"la riga 53 (blocco commentato, `*` in colonna 7) {'non compare' if not any(r[0] == '53' for r in proof) else 'COMPARE'}; "
      f"la riga 54 (`*>` seguito da un blocco) {'non compare' if not any(r[0] == '54' for r in proof) else 'COMPARE'}; "
      f"la riga 55 (blocco dentro un letterale) {'non compare' if not any(r[0] == '55' for r in proof) else 'COMPARE'}; "
      f"la riga 68 ha {len(rows68)} blocchi (colonne {', '.join(r[2] for r in rows68)}); "
      f"{len(multi)} blocchi occupano piu' righe. Quindi ProLeap si usa: nessun riconoscitore di blocchi scritto in proprio. "
      "La colla scrive il testo tra `CICS` e `END-EXEC`; comando e opzioni li ricava `glue/extract.py` con la regola "
      "dichiarata in testa al file. Il controllo indipendente (`crosscheck.sh`, awk) riconta i blocchi riga per riga.\n")
    diag = [l.rstrip("\n").split("\t") for l in open(diag_path, encoding="utf-8")][1:]
    w("Limite trovato: il preprocessore di ProLeap non conosce `EXEC DLI` (IMS). Al primo errore di sintassi la sua regola "
      "iniziale termina e, con il recupero standard di ANTLR, tutti i blocchi successivi del file andrebbero persi. La colla "
      "scarta il solo token in errore e riprende l'analisi dal token successivo (nessuna regola della grammatica cambia); "
      "errori e riprese sono dichiarati in ogni risposta. File in cui e' successo:\n")
    w("| file | errori di sintassi | riga del primo | riprese | blocchi dopo il primo errore (persi senza ripresa) |")
    w("| --- | ---: | ---: | ---: | ---: |")
    for d in diag:
        w(f"| {d[0]} | {d[1]} | {d[2]} | {d[3]} | {d[4]} |")
    w(f"\nTotale dei blocchi che senza la ripresa sarebbero stati persi: {sum(int(d[4]) for d in diag)}.\n")
    w("## Totali\n")
    files = sorted(by_file)
    mods = Counter("base" if p.startswith("app/cbl/") or p.startswith("app/cpy/") else p.split("/")[1] for p in (o["file"] for o in occs))
    w(f"- blocchi `EXEC CICS`: **{len(occs)}** in **{len(files)}** file "
      f"({sum(1 for p in files if kinds[p] == 'cobol')} programmi, {sum(1 for p in files if kinds[p] == 'copybook')} copybook);")
    for m in sorted(mods):
        w(f"- modulo `{m}`: {mods[m]} blocchi;")
    tot_src = sum(1 for p, t in kinds.items())
    w(f"- file analizzati (programmi e copybook del manifesto): {tot_src};")
    fc = [o for o in occs if o["categoria"] == "file"]
    w(f"- comandi sui file: {len(fc)}, con nome di file costante {sum(1 for o in fc for t in o['bersagli'] if t['risoluzione'] == 'costante')}, "
      f"letterale {sum(1 for o in fc for t in o['bersagli'] if t['risoluzione'] == 'letterale')}, "
      f"non risolto {sum(1 for o in fc for t in o['bersagli'] if t['risoluzione'] == 'non_risolto')};")
    rt = [t for o in occs if o["comando"] == "RETURN" for t in o["bersagli"]]
    w(f"- `RETURN` con `TRANSID`: {len(rt)}, costante {sum(1 for t in rt if t['risoluzione'] == 'costante')}, "
      f"letterale {sum(1 for t in rt if t['risoluzione'] == 'letterale')}, non risolto {sum(1 for t in rt if t['risoluzione'] == 'non_risolto')};")
    allt = [t for o in occs for t in o["bersagli"]]
    w(f"- operandi di bersaglio: {len(allt)}; letterali {sum(1 for t in allt if t['risoluzione'] == 'letterale')}, "
      f"costanti {sum(1 for t in allt if t['risoluzione'] == 'costante')}, non risolti {sum(1 for t in allt if t['risoluzione'] == 'non_risolto')}; "
      f"archi {len(arcs)}; nodi nuovi {len(g['nodi'])}.\n")
    w("## Comandi trovati\n")
    w("Elenco prodotto dall'estrazione, non scritto a mano.\n")
    w("| comando | categoria | blocchi |\n| --- | --- | ---: |")
    cc = Counter((o["comando"], o["categoria"]) for o in occs)
    for (c, k), n in sorted(cc.items(), key=lambda x: (x[0][1], x[0][0])):
        w(f"| `{c}` | {k} | {n} |")
    w("")
    w("## Per programma\n")
    w("Per ogni programma con blocchi propri o ereditati da un copybook (archi COPY di `graph.json`). Un blocco che sta "
      "in un copybook e' un'occorrenza del copybook: qui e' ripetuto sotto ogni programma che lo include.\n")
    inc = defaultdict(set)
    for p, lst in copies.items():
        for riga, target, subs in lst:
            inc[p].add(target)
    cp_file = {n["id"]: n.get("file") for n in base["nodi"]}
    for p in [q for q, t in kinds.items() if t == "cobol"]:
        own = by_file.get(p, [])
        inh = [o for c in sorted(inc.get(p, ())) for o in by_file.get(cp_file.get(c), [])]
        if not own and not inh:
            continue
        w(f"### `{stem(p)}` ({p})\n")
        for title, cat in (("Trasferimenti", "trasferimento"), ("Mappe", "mappe"), ("File", "file"), ("Code", "coda")):
            items = []
            for o in own + inh:
                if o["categoria"] != cat:
                    continue
                where = f"{o['riga']}" if o["file"] == p else f"{o['file']}:{o['riga']}"
                extra = f" {o['modalita']}" if cat == "file" else f" {o['tipo_coda']}" if cat == "coda" else ""
                tg = "; ".join(f"{t['ruolo']} {fmt_target(t, arcs_by_occ[o['id']])}" for t in o["bersagli"]) or "nessun bersaglio"
                items.append(f"riga {where}: `{o['comando']}`{extra}: {tg}")
            if items:
                w(f"- {title}:")
                for it in items:
                    w(f"  - {it}")
        sp = [f"{o['riga']} (`{o['comando']}`)" for o in own + inh if o["categoria"] == "transazione"]
        if sp:
            w(f"- `SYNCPOINT`, rollback e `ABEND`: righe {', '.join(sp)}")
        w("")
    w("## Bersagli non risolti\n")
    w("Registrati con l'operando, mai omessi e mai indovinati: la risoluzione delle variabili e' la issue #46.\n")
    w("| file | riga | comando | ruolo | operando | motivo |\n| --- | ---: | --- | --- | --- | --- |")
    for o in occs:
        for t in o["bersagli"]:
            if t["risoluzione"] == "non_risolto":
                w(f"| {o['file']} | {o['riga']} | `{o['comando']}` | {t['ruolo']} | `{t['operando']}` | {t['motivo']} |")
    w("")
    w("## Letterale, costante, variabile\n")
    w("Regola applicata a ogni operando di bersaglio (`glue/resolve.py`, ricontrollata con un'implementazione separata in "
      "`glue/verify.py`):\n")
    w("- **letterale**: l'operando e' un solo letterale alfanumerico tra apici; nome = contenuto senza gli spazi finali.")
    w("- **costante**: l'operando e' un solo nome di dato e, nel programma espanso con i suoi copybook (archi COPY di #2, "
      "`REPLACING` applicato come sostituzione di testo): il blocco non sta in un copybook; nessuna COPY non risolta puo' "
      "definirlo (i copybook di sistema `DFH*` e `CMQ*`, assenti dal repository, definiscono solo nomi `DFH*` e `MQ*`); il nome "
      "e' definito una sola volta (livelli 01-49 e 77); sta in `WORKING-STORAGE` o `LOCAL-STORAGE`; ne' lui ne' un suo gruppo "
      "hanno `OCCURS`; ha `VALUE` con un letterale alfanumerico; nessuna istruzione lo modifica. Nome = contenuto del letterale "
      "senza gli spazi finali; l'occorrenza cita file e riga del letterale della `VALUE`.")
    w("- **modifica**: un'occorrenza, nella `PROCEDURE DIVISION` espansa, di un nome collegato (il dato, i suoi gruppi, i suoi "
      "subordinati, chi ridefinisce o e' ridefinito da uno di questi con i suoi subordinati, i livelli 88 e 66 relativi) fuori "
      "da questi contesti di sola lettura: argomento intero di `PROGRAM`, `TRANSID`, `MAP`, `MAPSET`, `FILE`, `DATASET`, "
      "`QUEUE`, `QNAME` in un `EXEC CICS`; mittente di una `MOVE` (prima di `TO`); dopo `IF`, `EVALUATE`, `WHEN`, `UNTIL`, "
      "`DISPLAY` fino al verbo successivo. Tutto il resto conta come modifica (`INITIALIZE`, `SET`, `CALL ... USING`, "
      "`STRING`, `COMPUTE`, ogni altra opzione di `EXEC CICS`, ogni `EXEC SQL` o `EXEC DLI`, ...): sovrastima voluta.")
    w("- **non risolto**: ogni altro caso; il motivo e' il primo che vale nell'ordine: " + ", ".join(f"`{m}`" for m in MOTIVI) + ". "
      "Una mappa e' risolta solo se lo sono la mappa e il suo mapset; una coda solo se `TD` o `TS` e' scritto nel comando.\n")
    w("## Limiti\n")
    w("- Si registra che un comando ha `RESP`, `NOHANDLE` o un `HANDLE`, non che cosa comporta (fuori ambito).")
    w("- I bersagli in variabile (tabelle di menu, campi della COMMAREA, dati valorizzati con `MOVE`), l'arco online -> batch "
      "di `CORPT00C` e le voci di menu verso i moduli opzionali sono nella issue #46.")
    w("- Nessun collegamento fra file CICS (`cics-file:`) e dataset dei JCL, ne' fra mapset e sorgenti BMS.")
    w("- La regola di modifica e' una sovrastima: un dato letto in un contesto non elencato (per esempio in una `STRING`) "
      "risulta modificato e resta non risolto. Non produce mai una costante falsa, puo' produrre un non risolto in piu'.")
    w("- Le righe di continuazione (`-` in colonna 7) non sono gestite dalla colla di risoluzione; nel legacy compaiono solo in "
      "`CBSTM03A`, che non ha blocchi `EXEC CICS`. Il preprocessore di ProLeap le unisce alla riga precedente: un blocco dopo "
      "una continuazione avrebbe la riga sbagliata, e il confronto con il conteggio indipendente lo segnalerebbe.")
    w("- Un `EXEC` e il suo `CICS` su due righe diverse non sono riconosciuti da ProLeap (`NEWLINE` e' un token della regola); "
      "nel legacy non accade, e il conteggio indipendente li conterebbe, facendo fallire il controllo.")
    w("")
    return "\n".join(L)


if __name__ == "__main__":
    main(*sys.argv[1:6])
