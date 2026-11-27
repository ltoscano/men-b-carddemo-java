"""Verifica delle sentinelle dei tracciati (issue #43): tutti i controlli di controlli.py, riepilogo e documento.

Uso: verifica.py LEGACY CONTRATTI CONTRATTI_TSV SENTINELLE VISTE [--doc FILE.md] [--senza-decodifica]
  LEGACY        radice del legacy (volume sensibile alle maiuscole)
  CONTRATTI     docs/legacy-map/data-contract/contratti/ (contratti di #3, un TSV per contratto)
  CONTRATTI_TSV docs/legacy-map/data-contract/contratti.tsv
  SENTINELLE    analysis/data-sentinelle/sentinelle/
  VISTE         analysis/data-sentinelle/viste.tsv
  --doc         scrive il documento generato (sentinelle.md)
  --senza-decodifica  esegue tutti i controlli tranne la decodifica guidata dal contratto
Uscita 1 se c'e' almeno un errore; l'ultima riga e' "verifica riuscita: ..." solo se non ce ne sono.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from controlli import RIEMPIMENTO, VARIABILE, verifica  # noqa: E402


def tabella_conteggi(rie):
    """Righe: contratto, vista, sentinella, campi attesi, campi elementari della vista nel contratto."""
    out = []
    for (c, v, n), (a, k) in sorted(rie["conteggi"].items()):
        out.append((c, v, n, a, k))
    return out


def documento(rie):
    tutti = rie["tutti"]
    conteggi = tabella_conteggi(rie)
    coppie = rie["coppie"]
    contratti = sorted({c for c, _ in coppie})
    righe = []
    a = righe.append
    a("# Sentinelle dei tracciati (vista generata)")
    a("")
    a("Generato da `./analysis/run.sh data-sentinelle` (issue #43). Non si modifica a mano: le sentinelle, scritte a mano "
      "leggendo i sorgenti, sono in `analysis/data-sentinelle/sentinelle/`, l'elenco delle coppie contratto/vista in "
      "`analysis/data-sentinelle/viste.tsv`.")
    a("")
    a("Una sentinella è un record di prova scritto a mano dal copybook: per ogni campo elementare dichiara riga, nome, "
      "`PICTURE` e `USAGE` del sorgente, l'intervallo di byte calcolato a mano e il valore atteso tipizzato. La "
      "verifica decodifica la sentinella con la colla di #23 (`analysis/data-codec/glue/codec.py`, profilo "
      "`oracle-gnucobol`) guidata dal contratto di #3: se il contratto mette un campo nel posto sbagliato, con il tipo, "
      "il segno o la scala sbagliati, il valore ottenuto differisce da quello atteso. La posizione dei campi non dipende "
      "dal profilo, quindi se ne usa uno solo.")
    a("")
    a("## Contratti e viste coperti")
    a("")
    a(f"Contratti dei copybook in `contratti.tsv` (colonna `righe` = `copybook`): {len(rie['copybook'])}; più "
      f"`{VARIABILE}` (record variabile). Coppie contratto/vista: {len(coppie)}; sentinelle: {len(conteggi)}.")
    a("")
    a("| contratto | vista | sentinella | campi attesi | campi della vista nel contratto |")
    a("| --- | --- | --- | ---: | ---: |")
    for c, v, n, at, k in conteggi:
        a(f"| `{c}` | {v} | {n} | {at} | {k} |")
    tot_cb = sum(int(tutti[c]["elementari"]) for c in rie["copybook"])
    a("")
    a(f"Campi elementari dei 15 contratti dei copybook secondo `contratti.tsv` (somma della colonna `elementari`, "
      f"tutte le aree comprese): {tot_cb}. Ogni campo elementare di ogni contratto compare in almeno una vista; "
      f"in `CVEXPORT.EXPORT-RECORD` i campi fuori dalle `REDEFINES` compaiono in tutte e sette le viste.")
    a("")
    a("## Contratti senza sentinella")
    a("")
    senza = sorted(c for c, r in tutti.items() if r["righe"] != "copybook" and c != VARIABILE)
    a(f"I {len(senza)} contratti dichiarati nei programmi (record di `FD` e aree di lavoro, per lo più chiave più area "
      "dati) non hanno sentinella (decisione delegata, voce 61 del registro): la loro geometria resta affidata ai "
      "controlli di #3.")
    a("")
    for c in senza:
        a(f"- `{c}` ({tutti[c]['sorgente']}, righe {tutti[c]['righe']})")
    a("")
    a("## Limiti")
    a("")
    a("- **Gruppi.** Offset e lunghezze dei gruppi del contratto non sono verificati qui: gli attesi riguardano solo i "
      "campi elementari (con gli indici `OCCURS` nell'identità). I gruppi restano affidati ai controlli di #3.")
    a(f"- **Record variabile `{VARIABILE}`.** Il contratto è un solo campo `X(80)` (`CBACT01C.cbl` 85); il programma ne "
      "scrive prefissi di 12 e 39 byte (righe 288 e 303). Il codec rifiuta un campo più corto della sua lunghezza "
      f"(`CampoIncompleto`), quindi per la sola chiamata al codec il carico è portato alla lunghezza della sentinella "
      f"(80 byte, dal sorgente) con il riempimento `{RIEMPIMENTO.hex().upper()}`; confronto e ricodifica sono limitati "
      "al prefisso effettivo e i byte di riempimento non fanno parte dell'atteso. Le strutture `VBRC-REC1` e "
      "`VBRC-REC2`, che danno forma ai due carichi, non appartengono a questo contratto e i loro campi non si "
      "decodificano qui. Le intestazioni fisiche del record variabile su disco sono escluse. Una lunghezza del campo "
      "diversa da 80 ma non minore di 39 non si vede da questi prefissi: resta affidata al confronto con cb2xml di #3.")
    a("- **Profilo.** Solo `oracle-gnucobol`: il profilo `zos-ebcdic` è fuori ambito.")
    a("- **Dichiarazioni che nessun valore distingue.** Dove due dichiarazioni danno gli stessi byte e lo stesso valore, "
      "nemmeno un valore discriminante le separa, e la proprietà resta affidata a #3 (confronto di `PICTURE`, segno e "
      "scala del contratto con cb2xml):")
    a("  - un segno **aggiunto** a un campo senza segno: in DISPLAY una cifra semplice si legge positiva, in COMP-3 il "
      "codice `F` è accettato anche con segno, in COMP un valore positivo sotto 2^(8n-1) ha la stessa rappresentazione;")
    a("  - nei campi di una sola cifra (`CDEMO-PGM-CONTEXT`, `9(01)`) non si può accorciare la `PICTURE` né spostare la "
      "scala senza cambiare la lunghezza: quelle due mutazioni non sono applicabili;")
    a("  - in COMP una `PICTURE` più lunga che resta nella stessa ampiezza (per esempio `9(9)` letto come `9(8)` è "
      "rilevato, ma `9(5)`-`9(9)` occupano tutti 4 byte e un valore di 9 cifre letto con `9(9)` o con una `PICTURE` "
      "più lunga nella stessa ampiezza non cambia);")
    a("  - USAGE equivalenti (`COMP`, `COMP-4`, `BINARY`) e `PICTURE` scritte in modi equivalenti (`X(04)` e `X(4)`).")
    a("- **Lunghezza dichiarata altrove.** La somma delle lunghezze a mano è confrontata con una lunghezza dichiarata "
      "altrove (commento `RECLN` del copybook, `RECORDSIZE` del JCL, `FD` del programma), con la riga citata e "
      "verificata sul file. Per `COCOM01Y.CARDDEMO-COMMAREA` nessuna fonte esterna dichiara la lunghezza: 160 byte è "
      "solo la somma dei campi, e il confronto non è richiesto.")
    a("")
    a("## Fonti della lunghezza")
    a("")
    a("| sentinella | lunghezza | fonte |")
    a("| --- | ---: | --- |")
    for s in sorted(rie["sentinelle"], key=lambda s: (s["contratto"], s["vista"], s["sentinella"])):
        f = "; ".join(f"`{fo}` «{t}»" if fo != "-" else f"nessuna ({t})" for fo, t in s["fonte-lunghezza"])
        if s["prefisso"] is not None:
            f += f"; prefisso {s['prefisso']}: `{s['fonte-prefisso'][0]}` «{s['fonte-prefisso'][1]}»"
        a(f"| `{s['contratto']}@{s['vista']}/{s['sentinella']}` | {s['lunghezza']} | {f} |")
    a("")
    return "\n".join(righe)


def main(argv):
    doc = None
    deco = True
    pos = []
    i = 0
    while i < len(argv):
        if argv[i] == "--doc":
            doc = argv[i + 1]
            i += 2
            continue
        if argv[i] == "--senza-decodifica":
            deco = False
        else:
            pos.append(argv[i])
        i += 1
    if len(pos) != 5:
        raise SystemExit(__doc__)
    es, rie = verifica(*pos, decodifica=deco)
    for e in es.errori:
        print(e)
    if es.errori:
        print(f"verifica fallita: {len(es.errori)} errori")
        raise SystemExit(1)
    conteggi = tabella_conteggi(rie)
    print("contratto\tvista\tsentinella\tcampi_attesi\tcampi_vista_contratto")
    for r in conteggi:
        print("\t".join(str(x) for x in r))
    if doc:
        with open(doc, "w", encoding="utf-8") as f:
            f.write(documento(rie))
    n_campi = sum(r[3] for r in conteggi)
    print(f"verifica riuscita: {len(rie['copybook'])} contratti dei copybook + {VARIABILE}, {len(rie['coppie'])} coppie "
          f"contratto/vista, {len(conteggi)} sentinelle, {n_campi} campi attesi"
          + ("" if deco else " (senza decodifica)"))


if __name__ == "__main__":
    main(sys.argv[1:])
