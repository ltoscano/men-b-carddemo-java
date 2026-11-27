#!/usr/bin/env python3
"""Normalizza le risposte di ProLeap (CicsLister) in out/blocchi.tsv, validando OGNI risposta.

Uso: extract.py ELENCO RISPOSTE STDOUT-DELLO-STRUMENTO OUT.tsv DIAGNOSTICA.tsv
  ELENCO   i file passati allo strumento (uno per riga, ordine del manifesto)
  RISPOSTE cartella con una risposta <percorso con '_'>.tsv per file
Una risposta e' valida solo se: esiste, termina con fine riga, ha l'intestazione esatta, ogni riga ha 4 campi
(riga, riga_fine, colonna interi con riga <= riga_fine e colonna tra 8 e 72, testo non vuoto), righe in ordine,
e la chiusura '#fine<TAB>n<TAB>errori<TAB>riga del primo errore<TAB>riprese<TAB>incompleti' con n uguale alle righe lette
e nessun blocco incompleto. L'insieme delle risposte e' quello dell'elenco,
senza file in piu' ne' in meno, e lo strumento ha dichiarato di aver analizzato tutti i file.

Dal testo di ogni blocco (tra CICS e END-EXEC) si ricavano il comando e le opzioni (regola dichiarata):
  opzione   = PAROLA [ '(' argomento ')' ]   (spazi e righe ammessi prima di '('; parentesi annidate e letterali
              nell'argomento; argomento conservato com'e' scritto, salvo gli spazi e i fine riga fuori dai letterali,
              ridotti a uno spazio, e gli spazi agli estremi, tolti)
  comando   = prima parola, piu' la seconda se e' una parola qualificante della prima (tabella QUAL);
  opzioni   = tutte le parole dopo la prima, nell'ordine, qualificante compresa. Nomi in maiuscolo.
Un testo che non segue questa forma ferma l'estrazione (needs-spec-update): non si indovina."""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import response_name

HEADER = "riga\triga_fine\tcolonna\ttesto"
QUAL = {
    "SEND": {"MAP", "TEXT", "CONTROL", "PAGE"},
    "RECEIVE": {"MAP"},
    "WRITEQ": {"TD", "TS"}, "READQ": {"TD", "TS"}, "DELETEQ": {"TD", "TS"},
    "HANDLE": {"ABEND", "AID", "CONDITION"},
    "IGNORE": {"CONDITION"},
    "SYNCPOINT": {"ROLLBACK"},
    "INQUIRE": {"PROGRAM", "TRANSACTION", "FILE", "TERMINAL", "TASK"},
}
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*")


def die(msg):
    print("ESTRAZIONE: " + msg, file=sys.stderr)
    sys.exit(1)


def unesc(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\":
            if i + 1 >= len(s):
                raise ValueError("escape troncato")
            n = s[i + 1]
            table = {"\\": "\\", "n": "\n", "r": "\r", "t": "\t"}
            if n not in table:
                raise ValueError("escape sconosciuto \\" + n)
            out.append(table[n])
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def norm_arg(raw):
    """Spazi e fine riga fuori dai letterali ridotti a uno spazio; estremi tolti."""
    out, q, prev_space = [], None, False
    for c in raw:
        if q:
            out.append(c)
            if c == q:
                q = None
            continue
        if c in "'\"":
            q = c
            out.append(c)
            prev_space = False
        elif c in " \t\r\n":
            if not prev_space:
                out.append(" ")
            prev_space = True
        else:
            out.append(c)
            prev_space = False
    if q:
        raise ValueError("letterale non chiuso nell'argomento")
    return "".join(out).strip()


def strip_comments(text):
    """Il preprocessore di ProLeap marca le righe di commento e i commenti in linea con `*>` (token nascosto COMMENTLINE):
    si toglie, riga per riga, da `*>` (fuori dai letterali) a fine riga."""
    out = []
    for line in text.split("\n"):
        q = None
        for i, c in enumerate(line):
            if q:
                if c == q:
                    q = None
            elif c in "'\"":
                q = c
            elif c == "*" and line[i + 1:i + 2] == ">":
                line = line[:i]
                break
        out.append(line)
    return "\n".join(out)


def parse_body(text):
    """Testo tra CICS e END-EXEC -> (comando, [(NOME, argomento o None), ...])."""
    text = strip_comments(text)
    toks, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
            continue
        m = WORD.match(text, i)
        if not m:
            raise ValueError(f"carattere inatteso {c!r} in posizione {i}")
        name = m.group().upper()
        i = m.end()
        j = i
        while j < n and text[j] in " \t\r\n":
            j += 1
        arg = None
        if j < n and text[j] == "(":
            depth, k, q = 0, j, None
            while k < n:
                ch = text[k]
                if q:
                    if ch == q:
                        q = None
                elif ch in "'\"":
                    q = ch
                elif ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            if k >= n:
                raise ValueError(f"parentesi non chiusa dopo {name}")
            arg = norm_arg(text[j + 1:k])
            if arg == "":
                raise ValueError(f"argomento vuoto per {name}")
            i = k + 1
        toks.append((name, arg))
    if not toks:
        raise ValueError("blocco senza comando")
    first = toks[0]
    if first[1] is not None:
        raise ValueError(f"il comando {first[0]} ha un argomento")
    cmd = first[0]
    if len(toks) > 1 and toks[1][0] in QUAL.get(cmd, ()):
        cmd = cmd + " " + toks[1][0]
    return cmd, toks[1:]


def read_response(path, rel):
    if not os.path.isfile(path):
        die(f"{rel}: risposta mancante")
    data = open(path, encoding="utf-8").read()
    if data == "":
        die(f"{rel}: risposta vuota")
    if not data.endswith("\n"):
        die(f"{rel}: risposta troncata (manca il fine riga finale)")
    lines = data[:-1].split("\n")
    if lines[0] != HEADER:
        die(f"{rel}: risposta non riconoscibile: intestazione {lines[0][:60]!r} diversa da {HEADER!r}")
    if len(lines) < 2 or not re.fullmatch(r"#fine(\t\d+){5}", lines[-1]):
        die(f"{rel}: risposta non riconoscibile: manca la chiusura '#fine'")
    want, errs, first_err, resumes, incomplete = (int(x) for x in lines[-1].split("\t")[1:])
    if incomplete:
        die(f"{rel}: {incomplete} blocchi EXEC CICS riconosciuti solo in parte dal preprocessore: needs-spec-update")
    if (errs == 0) != (first_err == 0) or (errs == 0 and resumes):
        die(f"{rel}: risposta non riconoscibile: diagnostica incoerente {lines[-1]!r}")
    rows = lines[1:-1]
    if want != len(rows):
        die(f"{rel}: risposta non riconoscibile: la chiusura dichiara {want} blocchi, le righe sono {len(rows)}")
    blocks, last = [], (0, 0)
    for r in rows:
        f = r.split("\t")
        if len(f) != 4 or not all(re.fullmatch(r"[1-9]\d*", x) for x in f[:3]):
            die(f"{rel}: risposta non riconoscibile: riga {r[:60]!r}")
        a, b, col = int(f[0]), int(f[1]), int(f[2])
        if b < a or not 8 <= col <= 72 or (a, col) <= last:
            die(f"{rel}: risposta non riconoscibile: posizione incoerente {a},{b},{col}")
        last = (a, col)
        try:
            text = unesc(f[3])
            cmd, opts = parse_body(text)
        except ValueError as e:
            die(f"{rel}:{a}: testo del blocco non riconoscibile ({e}): needs-spec-update")
        blocks.append((a, b, col, cmd, opts))
    return blocks, (errs, first_err, resumes)


def main(listfile, resp_dir, stdout_file, out, diag):
    files = [l.rstrip("\n") for l in open(listfile, encoding="utf-8") if l.strip()]
    if not files:
        die("elenco dei file vuoto")
    expected = {response_name(p) for p in files}
    present = set(os.listdir(resp_dir)) if os.path.isdir(resp_dir) else set()
    extra = sorted(present - expected)
    missing = sorted(expected - present)
    if missing:
        die(f"risposte mancanti: {missing[:5]}")
    if extra:
        die(f"risposte non attese (file non nell'elenco): {extra[:5]}")
    so = open(stdout_file, encoding="utf-8").read() if os.path.isfile(stdout_file) else ""
    if so != f"file analizzati\t{len(files)}\n":
        die(f"lo strumento non dichiara di aver analizzato i {len(files)} file dell'elenco: {so[:80]!r}")
    with open(out, "w", encoding="utf-8", newline="") as w, open(diag, "w", encoding="utf-8", newline="") as d:
        w.write("file\triga\triga_fine\tcolonna\tcomando\topzioni\n")
        d.write("file\terrori\tprima_riga_errore\triprese\tblocchi_dopo_il_primo_errore\n")
        for p in files:
            blocks, (errs, first_err, resumes) = read_response(os.path.join(resp_dir, response_name(p)), p)
            for a, b, col, cmd, opts in blocks:
                w.write(f"{p}\t{a}\t{b}\t{col}\t{cmd}\t{json.dumps([[k, v] for k, v in opts], ensure_ascii=False)}\n")
            if errs:
                d.write(f"{p}\t{errs}\t{first_err}\t{resumes}\t{sum(1 for x in blocks if x[0] > first_err)}\n")


if __name__ == "__main__":
    main(*sys.argv[1:6])
