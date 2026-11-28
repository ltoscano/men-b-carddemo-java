"""Prove negative delle fixture (issue #5).

Uso: negativi.py LEGACY DC MANIFESTO CARTELLA
Ogni prova altera una copia privata degli ingressi (dati, inventario, fisica, viste, attesi) oppure sostituisce per
la sola durata della prova un passo della colla, esegue la verifica completa (con il confronto con le uscite
versionate) e pretende che fallisca CON IL CODICE DICHIARATO. Una prova che fallisce per un altro motivo, o non
fallisce, e' una prova negativa fallita. Inventario finale: ogni codice di fixture.CODICI deve avere almeno una prova
superata che lo pretende. Esce con 0 solo se tutte le prove sono superate e ogni codice e' coperto; 2 per un errore
operativo o per il limite di tempo (900 s).
"""
import contextlib
import os
import re
import shutil
import signal
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import documento  # noqa: E402
import fixture as fx  # noqa: E402
import verificatore  # noqa: E402

LIMITE = 900
A = "app/data/ASCII/"
E = "app/data/EBCDIC/AWS.M2.CARDDEMO."


@contextlib.contextmanager
def sostituisci(oggetto, nome, valore):
    vecchio = getattr(oggetto, nome)
    setattr(oggetto, nome, valore)
    try:
        yield
    finally:
        setattr(oggetto, nome, vecchio)


def riga_inv(ing, file):
    for i, r in enumerate(ing.inventario):
        if r.startswith(file + "\t"):
            return i
    raise KeyError(file)


def cambia_inv(ing, file, colonna, valore):
    testa = ing.inventario[0].split("\t")
    i = riga_inv(ing, file)
    c = ing.inventario[i].split("\t")
    c[testa.index(colonna)] = valore
    ing.inventario[i] = "\t".join(c)


def cambia_fis(ing, file, colonna, valore):
    testa = ing.fisica[0].split("\t")
    for i, r in enumerate(ing.fisica):
        if r.startswith(file + "\t"):
            c = r.split("\t")
            c[testa.index(colonna)] = valore
            ing.fisica[i] = "\t".join(c)
            return
    raise KeyError(file)


def cambia_attesi(ing, nome, vecchio, nuovo):
    t = ing.attesi[nome]
    if vecchio not in t:
        raise KeyError(f"{vecchio!r} assente da attesi/{nome}")
    ing.attesi[nome] = t.replace(vecchio, nuovo, 1)


def togli_record_attesi(ing, nome, n):
    righe = ing.attesi[nome].split("\n")
    tenute = [r for r in righe if not (r.startswith(f"R\t{n}\t") or r.startswith(f"C\t{n}\t"))]
    if len(tenute) == len(righe):
        raise KeyError(f"record {n} assente da attesi/{nome}")
    ing.attesi[nome] = "\n".join(tenute)


def cambia_byte(ing, file, pos, nuovo):
    d = bytearray(ing.dati[file])
    if d[pos] == nuovo:
        raise ValueError("byte gia' uguale")
    d[pos] = nuovo
    ing.dati[file] = bytes(d)


def filtra_anomalie(tipo):
    originale = fx.elenca_anomalie

    def f(fd):
        originale(fd)
        fd.anomalie = [a for a in fd.anomalie if a[0] != tipo]
    return f


def filtra_confronto(tipi=None, aggiungi=None):
    originale = fx.confronta

    def f(fa, fe):
        out = [d for d in originale(fa, fe) if tipi is None or d[0] not in tipi]
        if aggiungi and fe.voce["file"] == E + "CARDDATA.PS":
            out.append(aggiungi)
        return out
    return f


# --- prove: (nome, codice atteso, preparazione) -------------------------------------------------------------------
# La preparazione riceve la copia degli ingressi e restituisce un gestore di contesto (o None).

def p_byte_alterato(ing):          # 1: un byte in un importo di un record senza atteso a mano (acctdata riga 10)
    cambia_byte(ing, A + "acctdata.txt", 9 * 301 + 17, ord("7"))


def p_record_tolto(ing):           # 2
    ing.dati[E + "CARDDATA.PS"] = ing.dati[E + "CARDDATA.PS"][150:]


def p_record_duplicato(ing):       # 2
    d = ing.dati[E + "CARDDATA.PS"]
    ing.dati[E + "CARDDATA.PS"] = d[:300] + d[150:300] + d[300:]


def p_atteso_alterato(ing):        # 3
    cambia_attesi(ing, "AWS.M2.CARDDEMO.DALYTRAN.PS.tsv", "\t-919.00\t", "\t-919.01\t")


def p_atteso_mancante(ing):        # 3
    del ing.attesi["trantype.txt.tsv"]


def p_atteso_senza_file(ing):
    ing.attesi["inesistente.txt.tsv"] = ing.attesi["trantype.txt.tsv"]


def p_file_senza_voce(ing):        # 3
    del ing.inventario[riga_inv(ing, A + "trancatg.txt")]


def p_voce_senza_file(ing):        # 3
    c = ing.inventario[riga_inv(ing, A + "trancatg.txt")].split("\t")
    c[0] = A + "inesistente.txt"
    ing.inventario.append("\t".join(c))


def p_voce_duplicata(ing):
    ing.inventario.append(ing.inventario[riga_inv(ing, E + "USRSEC.PS")])


def p_contratto_sbagliato(ing):    # 4: contratto delle carte al file dei conti (stessa lunghezza dichiarata)
    cambia_inv(ing, E + "ACCTDATA.PS", "contratto", "CVACT02Y.CARD-RECORD")


def p_lunghezza_sbagliata(ing):
    cambia_inv(ing, E + "USRSEC.PS", "lunghezza", "40")


def p_dataset_sbagliato(ing):
    cambia_inv(ing, E + "USRSEC.PS", "dataset", "AWS.M2.CARDDEMO.CARDDATA.VSAM.KSDS")


def p_corrispondenza_tolta(ing):
    cambia_inv(ing, E + "ACCDATA.PS", "corrispondente", "-")


def p_provenienza_riga(ing):
    cambia_inv(ing, E + "CARDDATA.PS", "riga", "app/jcl/CARDFILE.jcl:70")


def p_provenienza_nessuno(ing):
    cambia_inv(ing, E + "CARDDATA.PS", "provenienza", "nessuno")
    cambia_inv(ing, E + "CARDDATA.PS", "riga", "-")


def p_chiave_sbagliata(ing):
    cambia_inv(ing, E + "CARDDATA.PS", "chiave", "CARD-ACCT-ID")


def p_chiave_scelta(ing):
    cambia_inv(ing, E + "CARDDATA.PS", "fonte_chiave", "scelta")


def p_fis_dimensione(ing):
    cambia_fis(ing, E + "USRSEC.PS", "dimensione", "801")


def p_fis_impronta(ing):
    cambia_fis(ing, E + "USRSEC.PS", "impronta", "0" * 64)


def p_ebcdic_troncato(ing):
    ing.dati[E + "USRSEC.PS"] = ing.dati[E + "USRSEC.PS"][:-1]


def p_fis_record(ing):
    cambia_fis(ing, A + "trantype.txt", "record", "8")


def p_crlf_normalizzati(ing):      # 7
    ing.dati[A + "tcatbal.txt"] = ing.dati[A + "tcatbal.txt"].replace(b"\r\n", b"\n")


def p_coda(ing):
    ing.dati[A + "trantype.txt"] = ing.dati[A + "trantype.txt"] + b"01"


def p_fis_lunghezze(ing):
    cambia_fis(ing, A + "cardxref.txt", "lunghezze", "50:1-50")


def p_fis_riconciliazione(ing):    # solo le colonne a mano: coda dichiarata 1, dimensione invariata
    cambia_fis(ing, A + "trancatg.txt", "coda", "1")


def p_fis_voce_tolta(ing):
    ing.fisica = [r for r in ing.fisica if not r.startswith(E + "USRSEC.PS\t")]


def p_vista_tipo_in_piu(ing):
    ing.viste.append("Z\tEXPORT-CARD-DATA\t281\t2650-PROCESS-CARD-RECORD")


def p_vista_riga(ing):
    ing.viste = [r.replace("\t273\t", "\t274\t") for r in ing.viste]


def p_vista_scambiata(ing):        # 4: conti letti come riferimenti carta-conto
    ing.viste = [r.replace("A\tEXPORT-ACCOUNT-DATA", "A\tEXPORT-CARD-XREF-DATA") for r in ing.viste]


def p_vista_opaca(ing):            # 4: vista attiva sostituita dal carico opaco (vista base: EXPORT-RECORD-DATA X(460))
    originale = fx.campi_vista

    def f(ing_, contratto, vista, es):
        return originale(ing_, contratto, "base" if contratto == fx.EXPORT else vista, es)
    return sostituisci(fx, "campi_vista", f)


def p_profilo_sbagliato(ing):      # 5
    ing.profilo_forzato[E + "ACCTDATA.PS"] = "oracle-gnucobol"


def p_non_valido_a_zero(ing):      # 6: colla alterata che converte un campo non valido in zero
    originale = fx.DECODIFICA

    def f(profilo, cat, var, rec, off):
        r = originale(profilo, cat, var, rec, off)
        if r.stato == "non-valido":
            g = fx.codec.geometria(cat, var)
            return fx.codec.Risultato("valido", fx.Decimal(0).scaleb(-g.decimali), r.originali)
        return r
    return sostituisci(fx, "DECODIFICA", f)


def p_riga_corta_silenziosa(ing):  # 6
    return sostituisci(fx, "elenca_anomalie", filtra_anomalie("riga-corta"))


def p_non_valido_tolto(ing):       # 8 (anomalia tolta)
    return sostituisci(fx, "elenca_anomalie", filtra_anomalie("campo-non-valido"))


def p_terminatore_tolto(ing):
    return sostituisci(fx, "elenca_anomalie", filtra_anomalie("terminatore-minoritario"))


def p_tipo_sconosciuto_tolto(ing):
    d = bytearray(ing.dati[E + "EXPORT.DATA.PS"])
    d[200 * 500] = 0xE9   # 'Z' nel record 201 (tipo T, senza atteso)
    ing.dati[E + "EXPORT.DATA.PS"] = bytes(d)
    return sostituisci(fx, "elenca_anomalie", filtra_anomalie("tipo-export-sconosciuto"))


def p_anomalia_inventata(ing):
    originale = fx.elenca_anomalie

    def f(fd):
        originale(fd)
        if fd.voce["file"] == E + "USRSEC.PS":
            fd.anomalie.append(("riga-corta", "3", "-", "inventata"))
    return sostituisci(fx, "elenca_anomalie", f)


def p_differenza_tolta(ing):       # 8
    return sostituisci(fx, "confronta", filtra_confronto(tipi={"valore-diverso"}))


def p_solo_una_tolta(ing):
    cambia_byte(ing, E + "DISCGRP.PS", 20 * 50 + 9, 0xC1)   # chiave del record 21 cambiata nell'EBCDIC
    return sostituisci(fx, "confronta", filtra_confronto(tipi={"solo-ascii", "solo-ebcdic"}))


def p_differenza_inventata(ing):
    return sostituisci(fx, "confronta", filtra_confronto(
        aggiungi=("valore-diverso", "x", "CARD-CVV-CD", "record 3: inventata", "record 3: inventata")))


def p_ricodifica(ing):
    originale = fx.RICODIFICA

    def f(r):
        b = originale(r)
        return bytes([b[0] ^ 1]) + b[1:] if b else b
    return sostituisci(fx, "RICODIFICA", f)


def p_buco(ing):
    originale = fx.campi_vista

    def f(ing_, contratto, vista, es):
        c = originale(ing_, contratto, vista, es)
        return [r for r in c if r["campo"] != "CARD-CVV-CD"] if contratto == "CVACT02Y.CARD-RECORD" else c
    return sostituisci(fx, "campi_vista", f)


def p_riempimento_altera(ing):
    originale = fx.RIEMPI

    def f(riga, L):
        b, n = originale(riga, L)
        return (b"9" + b[1:], n) if riga.startswith(b"0000000000") else (b, n)
    return sostituisci(fx, "RIEMPI", f)


def p_tracciato(ing):
    def f(r, contratto):
        raise ValueError("tracciato rifiutato dalla prova")
    return sostituisci(fx, "classifica_riga", f)


def p_versionato_in_piu(ing):
    return "versionato-in-piu"


def p_attesi_malformati(ing):
    ing.attesi["trantype.txt.tsv"] += "\nC\t1\tsolo\tquattro\n"


def p_origine(ing):
    cambia_attesi(ing, "cardxref.txt.tsv", "\triempimento\t", "\tfile\t")


def p_stato_atteso(ing):
    cambia_attesi(ing, "AWS.M2.CARDDEMO.DALYTRAN.PS.INIT.tsv", "\tnon-valido\t-\t-\t", "\tvalido\tintero\t0\t")


def p_byte_attesi(ing):
    t = ing.attesi["trancatg.txt.tsv"]
    i = t.index("\nR\t1\t")
    j = t.index("\t", t.index("\t", i + 4) + 1) + 1
    ing.attesi["trancatg.txt.tsv"] = t[:j] + ("31" if t[j:j + 2] != "31" else "32") + t[j + 2:]


def p_campo_atteso_tolto(ing):
    righe = ing.attesi["carddata.txt.tsv"].split("\n")
    i = next(k for k, r in enumerate(righe) if r.startswith("C\t1\t"))
    del righe[i]
    ing.attesi["carddata.txt.tsv"] = "\n".join(righe)


def p_record_atteso_inesistente(ing):
    righe = ing.attesi["trantype.txt.tsv"].split("\n")
    ing.attesi["trantype.txt.tsv"] = "\n".join(r.replace("\t7\t", "\t9999\t", 1) if r[:2] in ("R\t", "C\t") else r
                                               for r in righe)


def p_ultimo_tolto(ing):
    togli_record_attesi(ing, "carddata.txt.tsv", 50)


def p_negativo_tolto(ing):
    togli_record_attesi(ing, "dailytran.txt.tsv", 2)


def p_tipo_export_tolto(ing):
    togli_record_attesi(ing, "AWS.M2.CARDDEMO.EXPORT.DATA.PS.tsv", 101)


def p_differenza_attesa_tolta(ing):
    togli_record_attesi(ing, "discgrp.txt.tsv", 34)


def senza_versionati(gestore=None):
    """La prova si esegue senza il confronto con le uscite versionate: simula la rigenerazione dopo l'alterazione,
    cosi' fallisce solo grazie a un controllo indipendente dalle fixture versionate."""
    return ("senza-versionati", gestore)


def p_coppia_omessa(ing):          # omissione bilaterale: entrambe le corrispondenze di tcatbal tolte
    cambia_inv(ing, A + "tcatbal.txt", "corrispondente", "-")
    cambia_inv(ing, E + "TCATBALF.PS", "corrispondente", "-")
    return senza_versionati()


def p_alias_omesso(ing):           # omissione bilaterale dell'alias dei conti
    cambia_inv(ing, A + "acctdata.txt", "corrispondente", E + "ACCTDATA.PS")
    cambia_inv(ing, E + "ACCDATA.PS", "corrispondente", "-")
    return senza_versionati()


def p_coppia_inventata(ing):       # coppia dichiarata in entrambi i versi fra contratti diversi
    cambia_inv(ing, A + "trantype.txt", "corrispondente", E + "TRANTYPE.PS," + E + "USRSEC.PS")
    cambia_inv(ing, E + "USRSEC.PS", "corrispondente", A + "trantype.txt")
    return senza_versionati()


def p_codifica_cartella(ing):
    cambia_inv(ing, E + "USRSEC.PS", "codifica", "ASCII")


def p_provenienza_ignota(ing):
    cambia_inv(ing, E + "USRSEC.PS", "provenienza", "copiato")


def p_lettura_ascii(ing):          # la colla legge un byte diverso dal file (descrizione), poi si rigenera
    originale = fx.fisica_ascii

    def f(dati):
        righe = originale(dati)
        if righe and righe[0][0].startswith(b"0000000000") and len(righe) > 9:
            r, t = righe[9]
            righe[9] = (r[:40] + (b"Q" if r[40:41] != b"Q" else b"R") + r[41:], t)
        return righe
    return senza_versionati(sostituisci(fx, "fisica_ascii", f))


def p_lettura_ebcdic(ing):         # byte assoluto 88072 dell'export (record 177) letto D7 -> C2, poi si rigenera
    originale = fx.record_ebcdic

    def f(dati, L):
        rec = originale(dati, L)
        if L == 500 and len(rec) == 500:
            n, b = rec[176]
            rec[176] = (n, b[:72] + bytes([0xC2]) + b[73:])
        return rec
    return senza_versionati(sostituisci(fx, "record_ebcdic", f))


def p_lettura_record_perso(ing):
    originale = fx.record_ebcdic

    def f(dati, L):
        rec = originale(dati, L)
        return rec[:-1] if L == 150 else rec
    return senza_versionati(sostituisci(fx, "record_ebcdic", f))


def p_lettura_ordine(ing):         # due righe ASCII scambiate dalla colla
    originale = fx.fisica_ascii

    def f(dati):
        righe = originale(dati)
        if len(righe) == 300:
            righe[4], righe[5] = righe[5], righe[4]
        return righe
    return senza_versionati(sostituisci(fx, "fisica_ascii", f))


def p_lettura_terminatore(ing):
    originale = fx.fisica_ascii

    def f(dati):
        righe = originale(dati)
        return [(r, "LF") for r, _ in righe] if len(righe) == 7 else righe
    return senza_versionati(sostituisci(fx, "fisica_ascii", f))


def p_tabella_non_protetta(ing):
    return sostituisci(documento, "cella", lambda x: str(x))


def p_contratto_inesistente(ing):
    cambia_inv(ing, E + "USRSEC.PS", "contratto", "NESSUNO.RECORD")


def p_copertura_corta(ing):
    originale = fx.campi_vista

    def f(ing_, contratto, vista, es):
        c = originale(ing_, contratto, vista, es)
        return c[:-1] if contratto == "CVACT02Y.CARD-RECORD" else c
    return sostituisci(fx, "campi_vista", f)


def p_chiave_incalcolabile(ing):
    cambia_inv(ing, E + "USRSEC.PS", "chiave", "SEC-USR-NESSUNO")


def p_lunghezza_illeggibile(ing):
    cambia_inv(ing, E + "USRSEC.PS", "lunghezza", "ottanta")


def p_fonte_chiave(ing):
    cambia_inv(ing, E + "USRSEC.PS", "fonte_chiave", "app/jcl/DUSRSECJ.jcl:65")


def p_chiave_non_contigua(ing):
    cambia_inv(ing, E + "USRSEC.PS", "chiave", "SEC-USR-ID+SEC-USR-LNAME")


def p_fisica_illeggibile(ing):
    cambia_fis(ing, E + "USRSEC.PS", "dimensione", "ottocento")


def p_paragrafo_assente(ing):      # copia privata del testo di CBIMPORT con l'intestazione del paragrafo rinominata
    righe = list(ing.testo("app/cbl/CBIMPORT.cbl"))
    i = [k for k, l in enumerate(righe) if re.match(r"^\s{7,8}2300-PROCESS-CUSTOMER-RECORD\.", l)]
    if len(i) != 1:
        raise KeyError("intestazione 2300-PROCESS-CUSTOMER-RECORD")
    righe[i[0]] = righe[i[0]].replace("2300-PROCESS-CUSTOMER-RECORD", "2300-ALTRO-NOME")
    ing.testi["app/cbl/CBIMPORT.cbl"] = righe


def p_anomalo_tolto(ing):          # tcatbal: l'unico record anomalo (terminatore) e' il 50
    togli_record_attesi(ing, "tcatbal.txt.tsv", 50)


PROVE = [
    ("byte-alterato-fixture", "X01", p_byte_alterato), ("byte-alterato-totale", "X02", p_byte_alterato),
    ("byte-alterato-impronta", "F02", p_byte_alterato),
    ("record-tolto", "F04", p_record_tolto), ("record-duplicato-conteggio", "F04", p_record_duplicato),
    ("record-duplicato-unicita", "K01", p_record_duplicato),
    ("atteso-alterato", "D02", p_atteso_alterato), ("atteso-mancante", "D06", p_atteso_mancante),
    ("atteso-senza-file", "D06", p_atteso_senza_file), ("file-senza-voce", "I01", p_file_senza_voce),
    ("voce-senza-file", "I02", p_voce_senza_file), ("voce-duplicata", "I03", p_voce_duplicata),
    ("contratto-sbagliato", "D04", p_contratto_sbagliato), ("contratto-sbagliato-inventario", "I05",
                                                           p_contratto_sbagliato),
    ("lunghezza-sbagliata", "I04", p_lunghezza_sbagliata), ("dataset-sbagliato", "I05", p_dataset_sbagliato),
    ("corrispondenza-tolta", "I06", p_corrispondenza_tolta), ("provenienza-riga", "I07", p_provenienza_riga),
    ("provenienza-nessuno", "I08", p_provenienza_nessuno), ("chiave-sbagliata", "I09", p_chiave_sbagliata),
    ("chiave-scelta", "I09", p_chiave_scelta),
    ("fisica-dimensione", "F01", p_fis_dimensione), ("fisica-impronta", "F02", p_fis_impronta),
    ("ebcdic-troncato", "F03", p_ebcdic_troncato), ("fisica-record", "F04", p_fis_record),
    ("crlf-normalizzati", "F05", p_crlf_normalizzati), ("coda-senza-terminatore", "F06", p_coda),
    ("fisica-lunghezze", "F07", p_fis_lunghezze), ("fisica-riconciliazione", "F08", p_fis_riconciliazione),
    ("fisica-voce-tolta", "F09", p_fis_voce_tolta),
    ("vista-tipo-in-piu", "V01", p_vista_tipo_in_piu), ("vista-riga", "V02", p_vista_riga),
    ("vista-scambiata-paragrafo", "V03", p_vista_scambiata), ("vista-scambiata-aree", "V04", p_vista_scambiata),
    ("vista-scambiata-attesi", "D04", p_vista_scambiata),
    ("vista-opaca-campi", "V05", p_vista_opaca), ("vista-opaca-attesi", "D04", p_vista_opaca),
    ("profilo-sbagliato", "D02", p_profilo_sbagliato), ("non-valido-a-zero", "D01", p_non_valido_a_zero),
    ("stato-atteso-alterato", "D01", p_stato_atteso),
    ("riga-corta-silenziosa", "A01", p_riga_corta_silenziosa), ("non-valido-tolto", "A02", p_non_valido_tolto),
    ("terminatore-tolto", "A03", p_terminatore_tolto), ("tipo-sconosciuto-tolto", "A04", p_tipo_sconosciuto_tolto),
    ("anomalia-inventata", "A05", p_anomalia_inventata),
    ("differenza-tolta", "P02", p_differenza_tolta), ("solo-una-codifica-tolta", "P01", p_solo_una_tolta),
    ("differenza-inventata", "P03", p_differenza_inventata),
    ("ricodifica-alterata", "R01", p_ricodifica), ("campo-tolto-buco", "R02", p_buco),
    ("riempimento-altera-riga", "R03", p_riempimento_altera), ("tracciato-rifiutato", "T01", p_tracciato),
    ("versionato-in-piu", "X03", p_versionato_in_piu), ("attesi-malformati", "D09", p_attesi_malformati),
    ("origine-alterata", "D08", p_origine), ("byte-attesi-alterati", "D03", p_byte_attesi),
    ("campo-atteso-tolto", "D04", p_campo_atteso_tolto), ("record-atteso-inesistente", "D05",
                                                         p_record_atteso_inesistente),
    ("ultimo-tolto", "D07", p_ultimo_tolto), ("negativo-tolto", "D07", p_negativo_tolto),
    ("tipo-export-tolto", "D07", p_tipo_export_tolto), ("differenza-attesa-tolta", "D07", p_differenza_attesa_tolta),
    ("coppia-omessa-bilaterale", "I10", p_coppia_omessa), ("alias-conti-omesso", "I10", p_alias_omesso),
    ("coppia-inventata", "I10", p_coppia_inventata), ("codifica-cartella", "I03", p_codifica_cartella),
    ("provenienza-ignota", "I03", p_provenienza_ignota),
    ("lettura-ascii-alterata", "R04", p_lettura_ascii), ("lettura-ebcdic-alterata", "R04", p_lettura_ebcdic),
    ("lettura-record-perso", "R04", p_lettura_record_perso), ("lettura-ordine-scambiato", "R04", p_lettura_ordine),
    ("lettura-terminatore-alterato", "R04", p_lettura_terminatore),
    ("tabella-non-protetta", "X04", p_tabella_non_protetta),
    ("anomalie-diverse-dal-versionato", "X03", p_riga_corta_silenziosa),
    ("contratto-inesistente", "T01", p_contratto_inesistente), ("copertura-corta", "R02", p_copertura_corta),
    ("ricodifica-alterata-record", "R02", p_ricodifica), ("chiave-incalcolabile", "T01", p_chiave_incalcolabile),
    ("lunghezza-illeggibile", "I03", p_lunghezza_illeggibile), ("fonte-chiave-sbagliata", "I09", p_fonte_chiave),
    ("chiave-non-contigua", "I09", p_chiave_non_contigua), ("fisica-illeggibile", "F09", p_fisica_illeggibile),
    ("paragrafo-assente", "V02", p_paragrafo_assente), ("anomalo-tolto", "D07", p_anomalo_tolto),
]

_SITO = re.compile(r"\.errore\(\s*\"([A-Z][0-9]{2})\"")


def censimento():
    """Ogni chiamata es.errore("Xnn", ...) nei moduli della verifica e' una guardia: (file, riga, codice)."""
    out = set()
    qui = os.path.dirname(os.path.abspath(__file__))
    for nome in ("fixture.py", "verificatore.py"):
        with open(os.path.join(qui, nome), encoding="utf-8") as f:
            for i, l in enumerate(f, 1):
                for m in _SITO.finditer(l):
                    out.add((nome, i, m.group(1)))
    return out


def scaduto(*_):
    print(f"ERRORE operativo: limite di {LIMITE} s superato", flush=True)
    os._exit(2)


def main(argv):
    if len(argv) != 4:
        print(__doc__)
        return 2
    signal.signal(signal.SIGALRM, scaduto)
    signal.alarm(LIMITE)
    legacy, dc, man, cartella = argv
    versionati = os.path.join(cartella, "out")
    ing = fx.Ingressi(legacy, dc, man, cartella)
    es = verificatore.verifica(ing.copia(), versionati)[0]
    if es.errori:
        for c, t in es.errori[:10]:
            print(f"ERRORE [{c}] {t}")
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
        tmp = None
        try:
            vers = versionati
            if gestore == "versionato-in-piu":
                tmp = tempfile.mkdtemp()
                vers = os.path.join(tmp, "out")
                shutil.copytree(versionati, vers)
                with open(os.path.join(vers, "residuo.tsv"), "w") as f:
                    f.write("x\n")
                gestore = None
            if isinstance(gestore, tuple) and gestore[0] == "senza-versionati":
                vers, gestore = None, gestore[1]
            with (gestore or contextlib.nullcontext()):
                es = verificatore.verifica(copia, vers)[0]
        finally:
            if tmp:
                shutil.rmtree(tmp)
        trovati = [t for c, t in es.errori if c == codice]
        if trovati:
            superate += 1
            coperti.add(codice)
            siti |= {(f, r, c) for f, r, c in es.siti if c == codice}
            altri = sorted(es.codici() - {codice})
            print(f"ok: {nome} -> [{codice}] {trovati[0][:150]}" + (f" (anche {', '.join(altri)})" if altri else ""))
        else:
            fallite += 1
            print(f"PROVA NEGATIVA FALLITA ({nome}): atteso [{codice}], ottenuti {sorted(es.codici()) or 'nessun errore'}")
            for c, t in es.errori[:5]:
                print(f"   [{c}] {t[:160]}")
    scoperti = [c for c in fx.CODICI if c not in coperti]
    for c in scoperti:
        print(f"INVENTARIO: il codice [{c}] ({fx.CODICI[c]}) non ha alcuna prova negativa superata")
    cens = censimento()
    siti_scoperti = sorted(cens - siti)
    for f, r, c in siti_scoperti:
        print(f"INVENTARIO: la guardia {f}:{r} [{c}] non e' mai scattata in una prova superata che pretende [{c}]")
    fuori = sorted(siti - cens)
    for f, r, c in fuori:
        print(f"INVENTARIO: errore [{c}] da {f}:{r}, riga non censita (censimento incompleto)")
    if fallite or scoperti or siti_scoperti or fuori:
        print(f"prove negative: {superate} superate, {fallite} fallite, {len(scoperti)} codici e "
              f"{len(siti_scoperti) + len(fuori)} guardie scoperti")
        return 1
    print(f"inventario: {len(fx.CODICI)} codici e {len(cens)} guardie (chiamate es.errore censite nel sorgente), "
          f"ognuna scattata in almeno una prova superata che pretende il suo codice")
    print(f"prove negative: {superate} superate, ogni sito coperto")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:
        print(f"ERRORE operativo: {type(e).__name__}: {e}")
        sys.exit(2)
