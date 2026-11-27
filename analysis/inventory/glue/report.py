"""Scrive docs/legacy-map/inventario.md dal grafo (tutte le tabelle sono calcolate; il testo fisso descrive i metodi)."""
import os
import re
from collections import Counter, defaultdict

from common import manifest, of_type, read_lines, read_tsv

EXEC_VERBS = {
    "MOVE", "PERFORM", "IF", "EVALUATE", "EXEC", "CALL", "COMPUTE", "ADD", "SUBTRACT", "MULTIPLY", "DIVIDE", "GO", "GOBACK",
    "STOP", "STRING", "UNSTRING", "INITIALIZE", "DISPLAY", "READ", "WRITE", "REWRITE", "OPEN", "CLOSE", "ACCEPT", "INSPECT",
    "CONTINUE", "EXIT", "SET",
}


def table(header, rows):
    out = ["| " + " | ".join(header) + " |", "| " + " | ".join("---" for _ in header) + " |"]
    for r in rows:
        out.append("| " + " | ".join(str(x) for x in r) + " |")
    return "\n".join(out)


def executable_copybooks():
    res = []
    for p in of_type("copybook"):
        n, first, verbs = 0, None, set()
        for i, line in enumerate(read_lines(p), 1):
            if len(line) > 6 and line[6] in "*/":
                continue
            toks = line[7:72].split()
            if not toks:
                continue
            t = re.sub(r"[.,]$", "", toks[0].upper())
            if t in ("ELSE", "WHEN", "THEN") and len(toks) > 1:
                t = re.sub(r"[.,]$", "", toks[1].upper())
            if t in EXEC_VERBS:
                n += 1
                first = first or i
                verbs.add(t)
        if n:
            res.append((p, n, first, ", ".join(sorted(verbs))))
    return res


def write(graph, path, out, counts):
    nodes = {n["id"]: n for n in graph["nodi"]}
    edges = graph["archi"]
    by_type = Counter(n["tipo"] for n in graph["nodi"])
    e_by = defaultdict(lambda: [0, 0])
    for e in edges:
        e_by[e["tipo"]][0] += 1
        e_by[e["tipo"]][1] += len(e["occorrenze"])

    inbound = defaultdict(list)
    for e in edges:
        inbound[e["a"]].append(e)

    L = []
    w = L.append
    w("# Inventario strutturale e grafo delle dipendenze statiche (Wave 0A, issue #2)\n")
    w("Questo documento riassume `docs/legacy-map/graph.json` (formato fissato da `graph.schema.json`) e registra le anomalie "
      "trovate. **Il grafo non e' completo**: la sezione \"Categorie non ancora mappate\" dice cosa manca. Tutto cio' che "
      "segue e' scritto da `analysis/inventory/` e si rigenera con un comando; non e' stato modificato a mano.\n")
    w("## Come si rigenera\n")
    w("Sull'host servono Git e Docker (piu' bash e le utility POSIX). Il sorgente si legge dal volume Docker sensibile alle maiuscole di #1.\n")
    w("```\ngit submodule update --init\n./analysis/run.sh inventory           # rigenera analysis/inventory/out/, graph.json e questo file\n"
      "./analysis/run.sh inventory --check   # rigenera in una cartella temporanea, confronta con il versionato, conteggi indipendenti, attesi a mano, prove negative\n"
      "./analysis/run.sh --all --check       # tutte le analisi\n```\n")

    w("## Contenuto del grafo\n")
    w(table(["Tipo di nodo", "Nodi"], sorted(by_type.items())))
    w("")
    w(table(["Tipo di arco", "Archi", "Occorrenze"], [(t, a, o) for t, (a, o) in sorted(e_by.items())]))
    w("\nUn arco e' una terna (tipo, da, a); ogni occorrenza porta file e riga (e, secondo il tipo, sostituzioni `REPLACING`, `PARM`, "
      "nome della DD, `DISP`, generazione GDG, fonte). Due `COPY` dello stesso copybook con `REPLACING` diversi sono due occorrenze.\n")

    w("## Strumenti e colla\n")
    w("Gli strumenti sono quelli adottati in #1 (`docs/legacy-map/strumenti.md`). La colla elencata qui lavora su nomi gia' "
      "trovati da uno strumento o su parole chiave a formato fisso; non e' un parser.\n")
    w("| Archi | Strumento | Colla scritta in questa issue |\n| --- | --- | --- |")
    w("| `COPY` (programmi e copybook) | ProLeap (colla Java di #1), un file per volta | nessuna: riga e sostituzioni sono quelle di ProLeap |")
    w("| `CALL` statiche (programmi e copybook) | cobol-migration-toolkit (nomi, una scansione per cartella di programmi e di copybook) | **localizzatore di occorrenze** (`glue/locate_calls.py`): per ogni nome gia' trovato dallo strumento cerca nel sorgente le istruzioni `CALL 'NOME'` (area di codice colonne 8-72, commenti esclusi, letterale anche a capo); ogni occorrenza ha la sua riga |")
    w("| Transazione → programma | nessuno strumento | **estrazione testuale** (`glue/csd.py`): `DEFINE TRANSACTION(X)` e la prima clausola `PROGRAM(Y)` prima del `DEFINE` successivo, nei quattro file `csd` del manifesto |")
    w("| JCL, livello A | mapa, un file per volta | procedure di `app/proc/` presentate a mapa in copie temporanee senza estensione (il nome che mapa cerca), identiche byte per byte agli originali e verificate; non versionate |")
    w("| JCL, livello B | nessuno strumento | **estrattore di schede** (`glue/cards.py`): righe `//nome EXEC` e `//nome DD` e continuazioni (operando che termina con virgola, commenti `//*` in mezzo, colonne 1-72, dati in linea esclusi); ricava `PGM=`/`PROC=`, `PARM=`, `DSN=`, `DISP=`, `SYSOUT=`, `*`, `DUMMY` cosi' come scritti. Non risolve simboli, non espande procedure, non valuta condizioni |")
    w("| JCL, `PARM=` e riga di `EXEC`/DD | mapa non li riporta | l'estrattore di schede, per tutti i file (anche al livello A) |\n")
    w("**Livelli JCL.** Un file `jcl` e' al livello A se l'output di mapa coincide con il conteggio indipendente e con le schede: stesso numero di `EXEC`, "
      "stesso numero di DD per ogni passo, stessi nomi di passo, programma e DD (una DD senza nome eredita quello della precedente, come in mapa), nessuna DD a livello di job. "
      "Altrimenti e' al livello B. Ogni passo e ogni DD dichiara la `fonte` (`mapa` o `schede`). Un fallimento di mapa non diventa un valore atteso: l'elenco dei file al livello B e' "
      "in `analysis/inventory/expected/livello_b.tsv` con la causa, e `--check` fallisce se l'elenco cambia.\n")
    w("**Forma sorgente e forma risolta.** Per ogni DD si registrano, quando esistono, `dsn_sorgente` e `disp_sorgente` (testo del sorgente, simboli come scritti) e `dsn_risolto` e "
      "`disp_effettivo` (da mapa, che risolve i simboli e riempie i valori impliciti: `SHR` diventa `SHR/KEEP/KEEP`; per le DD senza DSN, `SYSOUT=*`, `*`, `DUMMY`, in cui il sorgente non ha `DISP`, mapa inventa `NEW/DELETE/DELETE` e `disp_effettivo` non si registra). Al livello B esiste solo la forma del sorgente. "
      "Il nodo `dataset` usa il nome risolto se c'e', altrimenti quello del sorgente (con i simboli, marcato `simbolico`). `(+1)`/`(0)`/`(-1)` e' la generazione GDG "
      "(`gdg`, `generazione`); `(NOME)` e' il membro. `SYSOUT`, dati in linea, `DUMMY` sono nodi pseudo (`dataset:~SYSOUT`, `~INSTREAM`, `~DUMMY`).\n")
    w("**DD a livello di job.** `JOBLIB` e ogni DD prima del primo passo sono archi `JOB_DD` dal job, con `livello: job`, mai attribuiti a un passo.\n")
    w("**Procedure.** Una `proc` ha i suoi passi (`PROC_PASSO`), ricavati con l'estrattore di schede; un passo `EXEC PROC=` punta al nodo `proc`.\n")
    w("**Risoluzione dei `COPY`.** Il nome si cerca tra i file `copybook` del manifesto (maiuscole ignorate, estensione tolta; i nomi sono unici). Un nome senza file e' un nodo `external` (per esempio `DFHAID`).\n")
    w("**Scelte dove la specifica lasciava margine.** I quattro file CSD del manifesto sono tutti letti (anche quelli dei moduli opzionali); i job dei moduli opzionali sono nel grafo; "
      "un `PGM=` che non e' un programma o un modulo assembler del repository e' un nodo `utility`; un nome di passo ripetuto o assente si distingue con `#n` (ordinale); i passi di una procedura si chiamano `proc.NOME/PASSO` perche' un job e una procedura possono avere lo stesso nome (`TRANREPT`).\n")

    # --------------------------------------------------------------- JCL
    w("## Copertura dei JCL\n")
    liv = read_tsv(os.path.join(out, "jcl_livelli.tsv"))
    tot_e = sum(int(r["exec_sorgente"]) for r in liv)
    tot_d = sum(int(r["dd_sorgente"]) for r in liv)
    nA = sum(1 for r in liv if r["livello"] == "A")
    jf = set(of_type("jcl"))
    n_steps = sum(1 for n in graph["nodi"] if n["tipo"] == "jcl-step" and n["file"] in jf)
    n_dd = sum(1 for e in edges if e["tipo"] in ("PASSO_DD", "JOB_DD") for o in e["occorrenze"] if o["file"] in jf)
    w(f"{len(liv)} file `jcl`: {nA} al livello A, {len(liv) - nA} al livello B. Totale sul sorgente (conteggio indipendente): {tot_e} `EXEC` e {tot_d} DD; "
      f"nel grafo i passi sono {n_steps} e le DD {n_dd}.\n")
    w("### File passati al livello B (mapa non coincide con il sorgente)\n")
    cause = {r[0]: r[3] for r in (l.rstrip("\n").split("\t") for l in open("/analysis/inventory/expected/livello_b.tsv", encoding="utf-8") if not l.startswith("#"))}
    w(table(["File", "EXEC sorgente", "DD sorgente", "EXEC mapa", "DD mapa", "Motivo del confronto", "Causa (letta nel sorgente e nel log)"],
            [(f"`{r['file']}`", r["exec_sorgente"], r["dd_sorgente"], r["exec_mapa"], r["dd_mapa"], r["motivo"], cause.get(r["file"], "non nota"))
             for r in liv if r["livello"] == "B"]))
    w("\n### Tutti i file jcl\n")
    w(table(["File", "EXEC", "DD", "Livello"], [(f"`{r['file']}`", r["exec_sorgente"], r["dd_sorgente"], r["livello"]) for r in liv]))
    w("")

    # --------------------------------------------------------------- anomalie
    w("## Anomalie\n")
    exec_in = {e["a"] for e in edges if e["tipo"] in ("PASSO_ESEGUE", "TRANSAZIONE_PROGRAMMA")}
    w("### Programmi senza un arco diretto da un job o da una transazione\n")
    rows = []
    jcl_lines = {p: read_lines(p) for p in of_type("jcl", "proc")}
    for n in graph["nodi"]:
        if n["tipo"] == "program" and n["id"] not in exec_in:
            callers = sorted({e["da"].split(":", 1)[1] for e in inbound[n["id"]] if e["tipo"] == "CALL"})
            hits = []
            for p, ls in jcl_lines.items():
                for i, l in enumerate(ls, 1):
                    if not l.startswith("//*") and re.search(r"(?<![A-Za-z0-9-])" + n["nome"] + r"(?![A-Za-z0-9-])", l[:72]):
                        hits.append(f"`{os.path.basename(p)}:{i}`")
            rows.append((f"`{n['nome']}`", n["modulo"], ", ".join(f"`{c}`" for c in callers) or "-", ", ".join(hits[:4]) or "-"))
    w(f"{len(rows)} programmi. **Questa tabella dice solo che nel grafo non c'e' un arco `PASSO_ESEGUE` o `TRANSAZIONE_PROGRAMMA` verso il programma; non dice che nessun job lo lanci.** "
      "I lanci che passano per categorie non mappate (programma indicato nel `PARM` di un `DFSRRC00`/`IKJEFT01`, nel `SYSTSIN` o nel `SYSIN` in linea, transazioni IMS) non sono archi. "
      "L'ultima colonna e' una ricerca testuale del nome nelle righe non commento dei JCL, non un arco: e' un indizio da verificare, non un risultato. "
      "\"Chiamato da\" elenca i programmi o i copybook con una `CALL` verso il programma.\n")
    w(table(["Programma", "Modulo", "Chiamato (CALL) da", "Menzioni nei JCL (ricerca testuale)"], rows))
    w("\n### Copybook mai copiati\n")
    copied = {e["a"] for e in edges if e["tipo"] == "COPY"}
    rows = [(f"`{n['nome']}`", n["modulo"]) for n in graph["nodi"] if n["tipo"] == "copybook" and n["id"] not in copied]
    w(f"{len(rows)} copybook.\n")
    w(table(["Copybook", "Modulo"], rows))
    w("\n### COPY non risolte (nessun copybook con quel nome nel manifesto)\n")
    rows = []
    for n in graph["nodi"]:
        if n["tipo"] == "external" and any(e["tipo"] == "COPY" for e in inbound[n["id"]]):
            occ = sum(len(e["occorrenze"]) for e in inbound[n["id"]] if e["tipo"] == "COPY")
            rows.append((f"`{n['nome']}`", occ, ", ".join(sorted({e['da'].split(':', 1)[1] for e in inbound[n["id"]] if e["tipo"] == "COPY"}))))
    w(table(["Copybook", "Occorrenze", "Programmi"], rows))
    w("\n### Bersagli `external` (non presenti nel repository)\n")
    rows = []
    for n in graph["nodi"]:
        if n["tipo"] == "external":
            kinds = Counter(e["tipo"] for e in inbound[n["id"]])
            occ = sum(len(e["occorrenze"]) for e in inbound[n["id"]])
            rows.append((f"`{n['nome']}`", ", ".join(f"{k} ({v})" for k, v in sorted(kinds.items())), occ))
    w(table(["Nome", "Archi entranti", "Occorrenze"], rows))
    w("\n### Copybook che contengono istruzioni eseguibili\n")
    w("Individuati dal primo termine di ogni riga di codice (colonne 8-72, commenti esclusi, dopo `ELSE`/`WHEN`/`THEN` il termine successivo) tra: "
      + ", ".join(f"`{v}`" for v in sorted(EXEC_VERBS)) + ". E' una ricerca per parola chiave, non un'analisi: non dice se il copybook e' usato nella `PROCEDURE DIVISION`.\n")
    ex = executable_copybooks()
    w(table(["Copybook", "Righe con istruzioni", "Prima riga", "Verbi"], [(f"`{p}`", n, f, v) for p, n, f, v in ex]))
    w("\n### File del manifesto di tipo sorgente senza nodo nel grafo\n")
    in_graph = {n.get("file") for n in graph["nodi"]}
    unmapped = defaultdict(list)
    for p, t in manifest():
        if t in ("cobol", "copybook", "jcl", "proc", "asm", "csd") and p not in in_graph:
            unmapped[t].append(p)
    if not unmapped:
        w("Nessuno per i tipi `cobol`, `copybook`, `jcl`, `proc`, `asm`, `csd`.\n")
    else:
        w(table(["Tipo", "File"], [(t, ", ".join(f"`{p}`" for p in ps)) for t, ps in sorted(unmapped.items())]))
    other = Counter(t for p, t in manifest() if t in ("bms", "ctl", "dcl", "ddl", "ims", "macro", "scheduler") )
    w("Tipi di file sorgente che non hanno nodi perche' fuori ambito (vedi sotto): " + ", ".join(f"{t} ({n})" for t, n in sorted(other.items())) + ".\n")
    w("### CALL con bersaglio in variabile e letterali non riportati dallo strumento\n")
    dyn = read_tsv(os.path.join(out, "call_dinamiche.tsv"))
    non = read_tsv(os.path.join(out, "call_non_riportate.tsv"))
    w(f"CALL con operando in variabile: {len(dyn)}. Sono occorrenze `CALL` verso il nodo `external:~NON-RISOLTO`, con l'operando scritto nel sorgente; il programma chiamato a tempo di esecuzione non e' determinato dall'analisi statica. "
      f"CALL con letterale che cobol-migration-toolkit non aveva riportato: {len(non)}.\n")
    w(table(["File", "Riga", "Operando"], [(f"`{r['file']}`", r["riga"], f"`{r['operando']}`") for r in dyn]))
    w("\n### Archi che partono da un copybook\n")
    w("`COPY` e `CALL` si cercano in programmi **e in tutti i copybook** (il contenuto decide, non l'elenco dei copybook gia' noti come eseguibili). "
      "Un copybook con una `CALL` crea un percorso programma -> copybook -> chiamato. Gli altri archi del grafo (JCL, CSD) non esistono nei copybook.\n")
    rows = [(f"`{e['da'].split(':', 1)[1]}`", e["tipo"], f"`{e['a']}`", len(e["occorrenze"]), ", ".join(str(o["riga"]) for o in e["occorrenze"]))
            for e in edges if e["da"].startswith("copybook:")]
    w(table(["Copybook", "Arco", "Bersaglio", "Occorrenze", "Righe"], rows))
    w("")
    w("### Passi senza nome unico, DD a livello di job, DD concatenate\n")
    dup = [n["id"] for n in graph["nodi"] if n["tipo"] == "jcl-step" and "#" in n["id"]]
    w("Passi il cui nome si ripete o manca nel sorgente (distinti con `#n`): " + (", ".join(f"`{i}`" for i in dup) or "nessuno") + ".\n")
    jd = sorted((e["da"], o["file"], o["riga"], o["dd"] or "(senza nome)") for e in edges if e["tipo"] == "JOB_DD" for o in e["occorrenze"])
    w("\nDD a livello di job (prima del primo passo; `JOBLIB` e DD concatenate):\n")
    w(table(["Job", "File", "Riga", "DD"], [(f"`{a}`", f"`{b}`", c, f"`{d}`") for a, b, c, d in jd]))
    w("\n### Anomalie del sorgente verificate a mano\n")
    man = [l.rstrip("\n").split("\t") for l in open("/analysis/inventory/expected/anomalie_manuali.tsv", encoding="utf-8") if not l.startswith("#")]
    w("Registrate, non corrette. `--check` verifica che ogni riga contenga il testo indicato.\n")
    w(table(["File", "Riga", "Descrizione"], [(f"`{f}`", r, d) for f, r, _, d in man]))
    w("")

    # --------------------------------------------------------------- non mappato
    w("## Categorie non ancora mappate\n")
    w("Il grafo non e' completo. Fuori ambito di questa issue:\n")
    w("| Categoria | Dove |\n| --- | --- |")
    w("| Comandi `EXEC CICS`: trasferimenti (`XCTL`, `LINK`, `RETURN TRANSID`), mappe BMS, file, code, job generati dall'online | issue #22 |")
    w("| `EXEC SQL` e chiamate IMS (`CBLTDLI`, `EXEC DLI`) dei moduli opzionali; le chiamate `CALL 'CBLTDLI'` e `CALL 'MQ...'` sono nel grafo come `CALL` verso nodi `external`, la loro semantica no | Wave 6 |")
    w("| Tracciati dei record e dei campi | issue #3 |")
    w("| Flussi batch (ordine dei job, dataset prodotti e consumati nel ciclo) | issue #7 |")
    w("| Comportamento | issue #11 |")
    w("| File `bms`, `ctl`, `dcl`, `ddl`, `ims`, `macro`, `scheduler` (CA7, Control-M), `data`, `sample`: nessun nodo | non assegnata qui |")
    w("| Definizioni di file e programmi nei CSD (`DEFINE FILE`, `DEFINE PROGRAM`), `DSN` dentro `SYSIN` dei JCL, `PARM` risolti, `COND`, `IF/THEN` dei JCL | non mappati |")
    w("| `COPY` dentro `EXEC SQL INCLUDE`; `REPLACE`; la risoluzione del programma chiamato da una `CALL` con operando in variabile (elencate sopra, bersaglio non risolto); i lanci di programmi che passano per `PARM`, `SYSTSIN` o `SYSIN` in linea dei JCL | non mappati |\n")

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
