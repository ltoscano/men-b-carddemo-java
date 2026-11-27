"""Prove negative sulla colla (issue #23): ogni prova altera il testo di codec.py (una regola), lascia fermi vettori e
attesi, esegue il confronto della colla con i vettori e pretende che fallisca per il motivo dichiarato.

Uso: negativi.py VETTORI CENSIMENTO.tsv DOC
Ogni mutazione passa per gli stessi confronti della verifica sulla colla: vettori, casi esaustivi dei DISPLAY, geometria.
Per ogni mutazione:
  - ogni testo da sostituire deve comparire esattamente una volta in codec.py (una mutazione che non cambia
    nulla renderebbe la prova vuota);
  - il confronto deve produrre almeno un errore e, tra gli errori, la riga attesa (sottostringa), che indica
    categoria, byte (o valore), atteso e ottenuto; un'eccezione del codec non vale come rilevamento.
Mutazioni generate per variante (una per ogni variante del censimento): ampiezza aumentata di un byte; per ogni
variante numerica, scala spostata di uno.
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verifica  # noqa: E402
from comune import leggi_tsv  # noqa: E402

QUI = os.path.dirname(os.path.abspath(__file__))
O, Z = "profilo oracle-gnucobol", "profilo zos-ebcdic"

MUTAZIONI = [
    # segno nell'ultima cifra
    ("segno-oracle-righe-B-C-scambiate",
     [("0x42: (2, 1),   # B", "0x42: (3, 1),   # B"), ("0x43: (3, 1),   # C", "0x43: (2, 1),   # C")],
     f"[decodifica] {O} categoria display-con-segno variante S9(10)V9(2) byte 30*7 31 32 33 34 42: valore atteso 123.42, ottenuto 123.43"),
    ("segno-oracle-J-positivo",
     [("0x4A: (1, -1),  # J", "0x4A: (1, 1),  # J")],
     f"[decodifica] {O} categoria display-con-segno variante S9(10)V9(2) byte 30*7 31 32 33 34 4A: valore atteso -123.41, ottenuto 123.41"),
    ("segno-oracle-graffa-chiusa-positiva",
     [("0x7D: (0, -1),  # }", "0x7D: (0, 1),  # }")],
     f"[decodifica] {O} categoria display-con-segno variante S9(9)V9(2) byte 30*6 39 31 39 30 7D: valore atteso -919.00, ottenuto 919.00"),
    ("segno-oracle-cifra-semplice-rifiutata",
     [("        c = _cifra_ascii(ultimo)\n", "        c = None\n")],
     f"[decodifica] {O} categoria display-con-segno variante S9(10)V9(2) byte 30*7 31 32 33 34 34: stato atteso valido, ottenuto non-valido"),
    ("segno-oracle-fuori-tabella-accettato-come-gnucobol",
     [("            if ultimo not in SEGNO_ORACLE:\n                return Risultato(\"non-valido\", None, b)\n            c, segno = SEGNO_ORACLE[ultimo]",
       "            c, segno = SEGNO_ORACLE.get(ultimo, (ultimo & 0x0F, 1))")],
     f"[decodifica] {O} categoria display-con-segno variante S9(10)V9(2) byte 30*7 31 32 33 34 70: stato atteso non-valido, ottenuto valido"),
    ("display-oracle-corpo-non-controllato",
     [("    for x in corpo:\n        c = _cifra_ascii(x)\n        if c is None:\n            return Risultato(\"non-valido\", None, b)\n        cifre.append(c)",
       "    for x in corpo:\n        cifre.append(x & 0x0F)")],
     f"[decodifica] {O} categoria display-con-segno variante S9(10)V9(2) byte 41 30*6 31 32 33 34 7B: stato atteso non-valido, ottenuto valido"),
    ("segno-zos-zone-C-D-scambiate",
     [("ZONE_SEGNO_ZOS = {0xC: 1, 0xD: -1, 0xF: 1}", "ZONE_SEGNO_ZOS = {0xC: -1, 0xD: 1, 0xF: 1}")],
     f"[decodifica] {Z} categoria display-con-segno variante S9(10)V9(2) byte F0*7 F1 F2 F3 F4 C1: valore atteso 123.41, ottenuto -123.41"),
    ("segno-zos-zona-F-rifiutata",
     [("ZONE_SEGNO_ZOS = {0xC: 1, 0xD: -1, 0xF: 1}", "ZONE_SEGNO_ZOS = {0xC: 1, 0xD: -1}")],
     f"[decodifica] {Z} categoria display-con-segno variante S9(10)V9(2) byte F0*7 F1 F2 F3 F4 F4: stato atteso valido, ottenuto non-valido"),
    ("segno-zos-zona-B-accettata",
     [("ZONE_SEGNO_ZOS = {0xC: 1, 0xD: -1, 0xF: 1}", "ZONE_SEGNO_ZOS = {0xC: 1, 0xD: -1, 0xF: 1, 0xB: -1}")],
     f"[decodifica] {Z} categoria display-con-segno variante S9(10)V9(2) byte F0*7 F1 F2 F3 F4 B4: stato atteso non-valido, ottenuto valido"),
    ("display-zos-zona-delle-cifre-non-controllata",
     [("        if x >> 4 != 0xF or (x & 0xF) > 9:", "        if (x & 0xF) > 9:")],
     f"[decodifica] {Z} categoria display-con-segno variante S9(10)V9(2) byte C1 F0*6 F1 F2 F3 F4 C0: stato atteso non-valido, ottenuto valido"),
    ("scrittura-zos-zona-F-per-i-positivi",
     [("ZONA_SCRITTA_ZOS = {1: 0xC, -1: 0xD}", "ZONA_SCRITTA_ZOS = {1: 0xF, -1: 0xD}")],
     f"[scrittura] {Z} categoria display-con-segno variante S9(10)V9(2) byte F0*7 F1 F2 F3 F4 C1 valore 123.41: byte attesi F0*7 F1 F2 F3 F4 C1, ottenuti F0*7 F1 F2 F3 F4 F1"),
    # binario
    ("binario-ordine-dei-byte-invertito",
     [('ORDINE_BINARIO = "big"', 'ORDINE_BINARIO = "little"')],
     f"[decodifica] {O} categoria comp variante 9(3) byte 00 7B: valore atteso 123, ottenuto -"),
    ("binario-senza-segno-letto-con-segno",
     [("    n = int.from_bytes(b, ORDINE_BINARIO, signed=g.segno)", "    n = int.from_bytes(b, ORDINE_BINARIO, signed=True)")],
     f"[decodifica] {O} categoria comp variante 9(3) byte FF FF: stato atteso oltre-picture, ottenuto valido"),
    ("binario-oltre-picture-con-valore",
     [('        return Risultato("oltre-picture", None, b)', '        return Risultato("oltre-picture", _valore(n, g), b)')],
     f"[decodifica] {O} categoria comp variante 9(9) byte FF*4: valore atteso -, ottenuto 4294967295"),
    ("binario-oltre-picture-con-valore-solo-oracle",
     [('        return Risultato("oltre-picture", None, b)',
       '        return Risultato("oltre-picture", _valore(n, g) if profilo == "oracle-gnucobol" else None, b)')],
     f"[decodifica] {O} categoria comp variante 9(3) byte 03 E8: valore atteso -, ottenuto 1000"),
    ("binario-limite-della-picture-spostato",
     [("    if abs(n) >= 10 ** (g.intere + g.decimali):\n        return Risultato",
       "    if abs(n) > 10 ** (g.intere + g.decimali):\n        return Risultato")],
     f"[decodifica] {O} categoria comp variante 9(3) byte 03 E8: stato atteso oltre-picture, ottenuto valido"),
    # comp-3
    ("comp3-oracle-codici-C-D-invertiti",
     [('"oracle-gnucobol": ({0xC: 1, 0xD: -1, 0xF: 1}, {0xF: 1}),', '"oracle-gnucobol": ({0xC: -1, 0xD: 1, 0xF: 1}, {0xF: 1}),')],
     f"[decodifica] {O} categoria comp-3 variante S9(9)V9(2) byte 00 00 01 23 45 6C: valore atteso 1234.56, ottenuto -1234.56"),
    ("comp3-zos-codici-C-D-invertiti",
     [('"zos-ebcdic": ({0xC: 1, 0xD: -1, 0xF: 1}, {0xF: 1}),', '"zos-ebcdic": ({0xC: -1, 0xD: 1, 0xF: 1}, {0xF: 1}),')],
     f"[decodifica] {Z} categoria comp-3 variante S9(10)V9(2) byte 00 00 00 01 23 45 6D: valore atteso -1234.56, ottenuto 1234.56"),
    ("comp3-oracle-F-rifiutato-con-segno",
     [('"oracle-gnucobol": ({0xC: 1, 0xD: -1, 0xF: 1}, {0xF: 1}),', '"oracle-gnucobol": ({0xC: 1, 0xD: -1}, {0xF: 1}),')],
     f"[decodifica] {O} categoria comp-3 variante S9(9)V9(2) byte 00 00 01 23 45 6F: stato atteso valido, ottenuto non-valido"),
    ("comp3-zos-B-accettato",
     [('"zos-ebcdic": ({0xC: 1, 0xD: -1, 0xF: 1}, {0xF: 1}),', '"zos-ebcdic": ({0xC: 1, 0xD: -1, 0xF: 1, 0xB: -1}, {0xF: 1}),')],
     f"[decodifica] {Z} categoria comp-3 variante S9(9)V9(2) byte 00 00 01 23 45 6B: stato atteso non-valido, ottenuto valido"),
    ("comp3-oracle-C-accettato-senza-segno",
     [('"oracle-gnucobol": ({0xC: 1, 0xD: -1, 0xF: 1}, {0xF: 1}),', '"oracle-gnucobol": ({0xC: 1, 0xD: -1, 0xF: 1}, {0xF: 1, 0xC: 1}),')],
     f"[decodifica] {O} categoria comp-3 variante 9(3) byte 12 3C: stato atteso non-valido, ottenuto valido"),
    ("comp3-semiottetti-di-cifra-non-controllati",
     [("    if any(c > 9 for c in cifre) or any(c > 9 for c in riempimento):", "    if any(c > 9 for c in riempimento):")],
     f"[decodifica] {O} categoria comp-3 variante S9(9)V9(2) byte 00 00 0A 23 45 6C: stato atteso non-valido, ottenuto valido"),
    ("comp3-riempimento-rifiutato-anche-nell-oracle",
     [('        if profilo == "zos-ebcdic":\n            return Risultato("non-valido", None, b)',
       '        if True:\n            return Risultato("non-valido", None, b)')],
     f"[decodifica] {O} categoria comp-3 variante S9(10)V9(2) byte 10 00 00 01 23 45 6C: stato atteso valido, ottenuto non-valido"),
    ("comp3-riempimento-accettato-su-zos",
     [('        if profilo == "zos-ebcdic":\n            return Risultato("non-valido", None, b)',
       '        if False:\n            return Risultato("non-valido", None, b)')],
     f"[decodifica] {Z} categoria comp-3 variante S9(10)V9(2) byte 10 00 00 01 23 45 6C: stato atteso non-valido, ottenuto valido"),
    ("comp3-zos-riempimento-2-accettato",
     [("    if any(c != 0 for c in riempimento):", "    if any(c not in (0, 2) for c in riempimento):")],
     f"[decodifica] {Z} categoria comp-3 variante S9(10)V9(2) byte 20 00 00 01 23 45 6C: stato atteso non-valido, ottenuto valido"),
    ("comp3-oracle-codice-0-accettato-con-segno",
     [('"oracle-gnucobol": ({0xC: 1, 0xD: -1, 0xF: 1}, {0xF: 1}),', '"oracle-gnucobol": ({0xC: 1, 0xD: -1, 0xF: 1, 0x0: 1}, {0xF: 1}),')],
     f"[decodifica] {O} categoria comp-3 variante S9(9)V9(2) byte 00 00 01 23 45 60: stato atteso non-valido, ottenuto valido"),
    ("comp3-cifre-7-8-scambiate",
     [("    n = int(\"\".join(str(c) for c in cifre))\n    return Risultato(\"valido\", _valore(accettati[codice] * n, g), b)",
       "    n = int(\"\".join(str({7: 8, 8: 7}.get(c, c)) for c in cifre))\n    return Risultato(\"valido\", _valore(accettati[codice] * n, g), b)")],
     f"[decodifica] {O} categoria comp-3 variante S9(9)V9(2) byte 00 00 07 78 87 8C: valore atteso 7788.78, ottenuto 8877.87"),
    ("comp3-riempimento-contato-nel-valore",
     [("    cifre = cifre[len(cifre) - cifre_pic:]\n", "")],
     f"[decodifica] {O} categoria comp-3 variante S9(10)V9(2) byte 10 00 00 01 23 45 6C: valore atteso 1234.56, ottenuto 10000001234.56"),
    ("comp3-scrittura-C-nei-campi-senza-segno",
     [("SEGNO_SCRITTO_PACKED = {1: 0xC, -1: 0xD, 0: 0xF}", "SEGNO_SCRITTO_PACKED = {1: 0xC, -1: 0xD, 0: 0xC}")],
     f"[scrittura] {O} categoria comp-3 variante 9(3) byte 12 3F valore 123: byte attesi 12 3F, ottenuti 12 3C"),
    # non validi, ricodifica conservativa
    ("non-valido-convertito-in-zero",
     [("    return r\n\n\ndef ricodifica",
       "    if r.stato == \"non-valido\":\n        r = Risultato(r.stato, Decimal(0), r.originali)\n    return r\n\n\ndef ricodifica")],
     f"[decodifica] {O} categoria display-senza-segno variante 9(1) byte 20: valore atteso -, ottenuto 0"),
    ("non-valido-promosso-a-valido-zero",
     [("    return r\n\n\ndef ricodifica",
       "    if r.stato == \"non-valido\" and r.originali[:1] in (b\" \", b\"@\"):\n        r = Risultato(\"valido\", Decimal(0), r.originali)\n    return r\n\n\ndef ricodifica")],
     f"[decodifica] {O} categoria display-senza-segno variante 9(4) byte 20 20 20 20: stato atteso non-valido, ottenuto valido"),
    ("ricodifica-normalizza-lo-zero-negativo",
     [("def ricodifica(risultato):\n    return risultato.originali",
       "def ricodifica(risultato):\n    b = bytearray(risultato.originali)\n    if risultato.valore == 0 and b:\n"
       "        b[-1] = {0x7D: 0x7B, 0xD0: 0xC0, 0x0D: 0x0C}.get(b[-1], b[-1])\n    return bytes(b)")],
     f"[ricodifica] {O} categoria display-con-segno variante S9(10)V9(2) byte 30*11 7D: byte attesi 30*11 7D, ottenuti 30*11 7B"),
    # alfanumerico
    ("alfa-zos-pagina-500-invece-di-037",
     [('"zos-ebcdic": ("cp037", 0x40)', '"zos-ebcdic": ("cp500", 0x40)')],
     f"[decodifica] {Z} categoria alfanumerico variante X(10) byte BA BB B0 5F AD BD 40*4: valore atteso"),
    ("alfa-oracle-riempimento-X00",
     [('"oracle-gnucobol": ("latin-1", 0x20)', '"oracle-gnucobol": ("latin-1", 0x00)')],
     f'[codifica] {O} categoria alfanumerico variante X(10) valore "AB": atteso 41 42 20*8, ottenuto 41 42 00*8'),
    ("alfa-riempimento-a-sinistra",
     [("    return b + bytes([spazio]) * (g.lunghezza - len(b))", "    return bytes([spazio]) * (g.lunghezza - len(b)) + b")],
     f'[codifica] {O} categoria alfanumerico variante X(10) valore "AB": atteso 41 42 20*8, ottenuto 20*8 41 42'),
    ("alfa-testo-lungo-troncato-in-silenzio",
     [("    if len(b) > g.lunghezza:\n        raise CodificaErrore", "    if len(b) > g.lunghezza:\n        b = b[:g.lunghezza]\n    if False:\n        raise CodificaErrore")],
     f'[codifica] {O} categoria alfanumerico variante X(10) valore "ABCDEFGHIJK": atteso errore, ottenuto 41 42 43 44 45 46 47 48 49 4A'),
    # codifica di valori nuovi
    ("codifica-decimali-troncati-in-silenzio",
     [("    if scalato != scalato.to_integral_value():\n        raise", "    if False:\n        raise")],
     f"[codifica] {O} categoria display-con-segno variante S9(10)V9(2) valore 1.234: atteso errore, ottenuto 30*9 31 32 43"),
    ("codifica-oltre-la-picture-accettata",
     [("    if abs(n) >= 10 ** (g.intere + g.decimali):\n        raise CodificaErrore", "    if False:\n        raise CodificaErrore")],
     f"[codifica] {O} categoria display-senza-segno variante 9(4) valore 12345: atteso errore, ottenuto"),
    ("codifica-negativo-in-campo-senza-segno",
     [("    if n < 0 and not g.segno:", "    if False:")],
     f"[codifica] {O} categoria display-senza-segno variante 9(4) valore -5: atteso errore, ottenuto 30 30 30 35"),
    # giro di correzione 1: rappresentazioni alternative, cifre del corpo, casi esaustivi, alfanumerico, geometria
    ("segno-oracle-cifre-semplici-0-1-scambiate",
     [("        c = _cifra_ascii(ultimo)\n", "        c = {0: 1, 1: 0}.get(_cifra_ascii(ultimo), _cifra_ascii(ultimo))\n")],
     f"[decodifica] {O} categoria display-con-segno variante S9(4)V9(2) byte 31 32 33 34 35 30: valore atteso 1234.50, ottenuto 1234.51"),
    ("segno-zos-zona-F-cifre-0-1-scambiate",
     [("        segno = ZONE_SEGNO_ZOS[zona]\n        cifre.append(c)",
       "        segno = ZONE_SEGNO_ZOS[zona]\n        cifre.append({0: 1, 1: 0}.get(c, c) if zona == 0xF else c)")],
     f"[decodifica] {Z} categoria display-con-segno variante S9(4)V9(2) byte F1 F2 F3 F4 F5 F0: valore atteso 1234.50, ottenuto 1234.51"),
    ("display-oracle-cifre-5-6-scambiate",
     [("    return x - 0x30 if 0x30 <= x <= 0x39 else None", "    return {5: 6, 6: 5}.get(x - 0x30, x - 0x30) if 0x30 <= x <= 0x39 else None")],
     f"[decodifica] {O} categoria display-senza-segno variante 9(1) byte 36: valore atteso 6, ottenuto 5"),
    ("display-zos-cifre-7-8-scambiate-nel-corpo",
     [("        cifre.append(x & 0xF)\n", "        cifre.append({7: 8, 8: 7}.get(x & 0xF, x & 0xF))\n")],
     f"[decodifica] {Z} categoria display-senza-segno variante 9(1) byte F7: valore atteso 7, ottenuto 8"),
    ("segno-oracle-byte-5B-accettato",
     [("    0x7B: (0, 1),   # {", "    0x5B: (0, 1),\n    0x7B: (0, 1),   # {")],
     f"[esaustivo] {O} categoria display-con-segno variante S9(4)V9(2) byte 31*5 5B (segno 5B): stato atteso non-valido, ottenuto valido"),
    ("alfa-zos-pagina-1140-invece-di-037",
     [('"zos-ebcdic": ("cp037", 0x40)', '"zos-ebcdic": ("cp1140", 0x40)')],
     f"[decodifica] {Z} categoria alfanumerico variante X(289) byte"),
    ("alfa-oracle-iso-8859-15-invece-dell-identita",
     [('"oracle-gnucobol": ("latin-1", 0x20)', '"oracle-gnucobol": ("iso8859_15", 0x20)')],
     f"[decodifica] {O} categoria alfanumerico variante X(289) byte"),
    ("geometria-campo-troncato-accettato",
     [("    if offset + g.lunghezza > len(record):", "    if False:")],
     f"[geometria] {O} categoria comp variante 9(3) byte 00 7B (record troncato di un byte): atteso CampoIncompleto, ottenuto stato valido valore 0"),
    ("geometria-offset-negativo-accettato",
     [("    if not isinstance(offset, int) or isinstance(offset, bool) or offset < 0:", "    if not isinstance(offset, int):")],
     f"[geometria] {O} categoria alfanumerico variante X(1) byte 41 (offset negativo): atteso CampoIncompleto"),
]

RIGA_GEOMETRIA = "    return Geometria(categoria, variante, segno, intere, decimali, lunghezza)"
RIGA_GEOMETRIA_ALFA = "        return Geometria(categoria, variante, False, 0, 0, n)"
RIGA_SCALA = "    return Decimal(intero).scaleb(-g.decimali)"


def per_variante(censimento):
    out = []
    for r in censimento:
        c, v = r["categoria"], r["variante"]
        cond = f"(1 if (categoria, variante) == ({c!r}, {v!r}) else 0)"
        if c == "alfanumerico":
            sost = [(RIGA_GEOMETRIA_ALFA, f"        return Geometria(categoria, variante, False, 0, 0, n + {cond})")]
        else:
            sost = [(RIGA_GEOMETRIA, f"    return Geometria(categoria, variante, segno, intere, decimali, lunghezza + {cond})")]
        for p in (O, Z):
            out.append((f"ampiezza-{c}-{v}-{p.split()[1]}", sost, f"[decodifica] {p} categoria {c} variante {v} byte"))
        if c != "alfanumerico":
            cs = f"(1 if (g.categoria, g.variante) == ({c!r}, {v!r}) else 0)"
            out.append((f"scala-{c}-{v}", [(RIGA_SCALA, f"    return Decimal(intero).scaleb(-(g.decimali + {cs}))")],
                        f"[decodifica] {O} categoria {c} variante {v} byte"))
    return out


def carica_da_testo(testo, nome):
    spec = importlib.util.spec_from_loader(nome, loader=None)
    mod = importlib.util.module_from_spec(spec)
    exec(compile(testo, f"<{nome}>", "exec"), mod.__dict__)  # noqa: S102
    return mod


def main(vett, censimento_path, doc):
    with open(os.path.join(QUI, "codec.py"), encoding="utf-8") as f:
        sorgente = f.read()
    originale = carica_da_testo(sorgente, "codec_originale")
    _, censimento = leggi_tsv(censimento_path)
    _, fonti = verifica.fonti_documento(doc)
    vettori = verifica.carica_vettori(vett, originale, fonti)
    verifica.controlla_codec(originale, vettori); verifica.controlla_esaustivi_codec(originale); verifica.controlla_geometria(originale, vettori)
    if verifica.ERRORI:
        print("\n".join(verifica.ERRORI))
        raise SystemExit("la colla non mutata non supera i vettori: prove negative non eseguibili")
    falliti = 0
    tutte = MUTAZIONI + per_variante(censimento)
    for nome, sostituzioni, atteso in tutte:
        testo = sorgente
        for vecchio, nuovo in sostituzioni:
            n = testo.count(vecchio)
            if n != 1:
                print(f"PROVA NEGATIVA NON APPLICABILE ({nome}): il testo da sostituire compare {n} volte in codec.py")
                falliti += 1
                break
            testo = testo.replace(vecchio, nuovo)
        else:
            if testo == sorgente:
                print(f"PROVA NEGATIVA VUOTA ({nome}): codec.py non e' cambiato")
                falliti += 1
                continue
            verifica.ERRORI.clear()
            mod = carica_da_testo(testo, "codec_mutato")
            verifica.controlla_codec(mod, vettori); verifica.controlla_esaustivi_codec(mod); verifica.controlla_geometria(mod, vettori)
            trovati = [e for e in verifica.ERRORI if atteso in e and "attes" in e and "ottenut" in e and "eccezione" not in e]
            if not verifica.ERRORI:
                print(f"PROVA NEGATIVA FALLITA ({nome}): il confronto non si e' accorto della mutazione")
                falliti += 1
            elif not trovati:
                print(f"PROVA NEGATIVA FALLITA ({nome}): il confronto e' fallito ma non per il motivo atteso ('{atteso}'):")
                print("\n".join("    " + e for e in verifica.ERRORI[:5]))
                falliti += 1
            else:
                print(f"ok: {nome} -> {len(verifica.ERRORI)} errori, tra cui: {trovati[0]}")
    verifica.ERRORI.clear()
    if falliti:
        print(f"prove negative sulla colla: {falliti} su {len(tutte)} non superate")
        return 1
    print(f"prove negative sulla colla: {len(tutte)} su {len(tutte)} superate "
          f"({len(MUTAZIONI)} sulle regole, {len(tutte) - len(MUTAZIONI)} per variante)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("uso: negativi.py VETTORI CENSIMENTO.tsv DOC")
    sys.exit(main(*sys.argv[1:]))
