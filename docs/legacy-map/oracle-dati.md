# File indicizzati nell'oracle: record nel profilo GnuCOBOL (issue #53)

Documento generato da `./analysis/run.sh oracle-dati` (`analysis/oracle-dati/`): non modificarlo a mano. Il caricamento nel file indicizzato e la rilettura sono il passo `./oracle/run.sh dati` (`oracle/dati/`, `oracle/README.md`).

## Cosa si fa

Per ogni riga della tabella scritta a mano `analysis/oracle-dati/tabella.tsv` il file che il JCL carica nel KSDS (`REPRO INFILE`) si porta dal profilo `zos-ebcdic` al profilo `oracle-gnucobol` **campo per campo**: decodifica con il codec di #23 (`analysis/data-codec/glue/codec.py`) guidato dal contratto di #3 attraverso l'adattatore di #43 (`analysis/data-sentinelle/glue/controlli.py`), entrambi importati e non modificati, poi codifica del valore nel profilo dell'oracle. Nessuna conversione di caratteri sull'intero record. Un campo non valido, non in rappresentazione canonica (la ricodifica lo normalizzerebbe) o non ricodificabile ferma la generazione. Nessun valore riparato, nessun campo normalizzato, `FILLER` compreso.

**Decisione sul contenuto (delegata, issue #53).** I due file di esempio dei conti non concordano nel record con chiave 49 (`ACCT-ADDR-ZIP`, `docs/legacy-map/fixture.md`). Si carica il contenuto del file EBCDIC, perche' e' quello che `app/jcl/ACCTFILE.jcl` carica nel KSDS (`REPRO INFILE(ACCTDATA)`, DD alle righe 56-57). Il file ASCII serve da controprova.

## Tabella dei file

| DD | origine | contratto | chiave (KEYS) | record (RECORDSIZE) | controprova | uscita |
| --- | --- | --- | --- | --- | --- | --- |
| ACCTFILE | `app/data/EBCDIC/AWS.M2.CARDDEMO.ACCTDATA.PS` | CVACT01Y.ACCOUNT-RECORD | 11 byte dall'offset 0 (`app/jcl/ACCTFILE.jcl:40`) | 300 byte (`app/jcl/ACCTFILE.jcl:41`) | `app/data/ASCII/acctdata.txt` | `analysis/oracle-dati/out/ACCTFILE.rec` |

## ACCTFILE

- `ACCTFILE.rec`: 50 record di 300 byte senza terminatori (15000 byte), nell'ordine del file d'origine; SHA-256 `591952211bfa94397d633a6f6553cf6dda29051f978ec8c0459ed036431dd700`.
- Prima chiave `00000000001`, ultima `00000000050`; elenco completo (record, chiave, SHA-256 del record) in `ACCTFILE.elenco.tsv`.
- Campi DISPLAY con segno: 5 per record, 250 in tutto, di cui **0 negativi**. Questo file non esercita il segno negativo: ogni ultimo byte di un importo e' a zona C nel file d'origine e diventa uno dei caratteri positivi `{` `A`-`I` nell'oracle.
- Ordine delle chiavi. La chiave e' numerica `DISPLAY` senza segno (`9(11)`): cifre `F0`-`F9` in EBCDIC, `30`-`39` in ASCII, nello stesso ordine. Per questo l'ordine di chiave dell'oracle coincide con quello del mainframe per questo file. Non vale in generale per chiavi alfanumeriche (lettere, minuscole, spazi: le due collazioni differiscono, `oracle/README.md`).

Campi (contratto, vista base) e trasformazione:

| campo | offset | byte | categoria | profilo zos-ebcdic -> oracle-gnucobol |
| --- | --- | --- | --- | --- |
| ACCT-ID | 0 | 11 | display-senza-segno 9(11) | cifre Fd -> 3d |
| ACCT-ACTIVE-STATUS | 11 | 1 | alfanumerico X(1) | carattere della pagina 037 -> stesso carattere in ISO-8859-1 |
| ACCT-CURR-BAL | 12 | 12 | display-con-segno S9(10)V9(2) | cifre Fd -> 3d; ultimo byte C/D d -> carattere del segno (-fsign=EBCDIC) |
| ACCT-CREDIT-LIMIT | 24 | 12 | display-con-segno S9(10)V9(2) | cifre Fd -> 3d; ultimo byte C/D d -> carattere del segno (-fsign=EBCDIC) |
| ACCT-CASH-CREDIT-LIMIT | 36 | 12 | display-con-segno S9(10)V9(2) | cifre Fd -> 3d; ultimo byte C/D d -> carattere del segno (-fsign=EBCDIC) |
| ACCT-OPEN-DATE | 48 | 10 | alfanumerico X(10) | carattere della pagina 037 -> stesso carattere in ISO-8859-1 |
| ACCT-EXPIRAION-DATE | 58 | 10 | alfanumerico X(10) | carattere della pagina 037 -> stesso carattere in ISO-8859-1 |
| ACCT-REISSUE-DATE | 68 | 10 | alfanumerico X(10) | carattere della pagina 037 -> stesso carattere in ISO-8859-1 |
| ACCT-CURR-CYC-CREDIT | 78 | 12 | display-con-segno S9(10)V9(2) | cifre Fd -> 3d; ultimo byte C/D d -> carattere del segno (-fsign=EBCDIC) |
| ACCT-CURR-CYC-DEBIT | 90 | 12 | display-con-segno S9(10)V9(2) | cifre Fd -> 3d; ultimo byte C/D d -> carattere del segno (-fsign=EBCDIC) |
| ACCT-ADDR-ZIP | 102 | 10 | alfanumerico X(10) | carattere della pagina 037 -> stesso carattere in ISO-8859-1 |
| ACCT-GROUP-ID | 112 | 10 | alfanumerico X(10) | carattere della pagina 037 -> stesso carattere in ISO-8859-1 |
| FILLER | 122 | 178 | alfanumerico X(178) | carattere della pagina 037 -> stesso carattere in ISO-8859-1 |

Controprova con il file ASCII: i record prodotti coincidono byte per byte con le righe di `app/data/ASCII/acctdata.txt` senza terminatori tranne, esattamente, questi byte (`analysis/oracle-dati/attesi/ACCTFILE.controprova.tsv`, scritto a mano):

| record | chiave | campo | byte | file ASCII | prodotto (dal file EBCDIC) |
| --- | --- | --- | --- | --- | --- |
| 49 | 00000000049 | ACCT-ADDR-ZIP | 103-112 | `41 30 30 30 30 30 30 30 30 30` ('A000000000') | `5A 45 52 4F 41 50 52 20 20 20` ('ZEROAPR   ') |

## Controlli (tutti superati alla generazione)

| controllo | cosa | dove |
| --- | --- | --- |
| 1 | chiave e lunghezza della tabella rilette dal JCL (KEYS, RECORDSIZE dello stesso DEFINE CLUSTER, REPRO dal file d'origine al cluster) e confrontate con il contratto | `glue/oracle_dati.py` J |
| 2 | ogni campo prodotto, ridecodificato nel profilo dell'oracle, ha stato e valore della fixture EBCDIC di #5 (`analysis/data-fixtures/out/`, letta e non rigenerata) | `glue/oracle_dati.py` F |
| 3 | controprova byte per byte con il file ASCII, con la sola differenza scritta a mano | `controprova.sh`, solo utility POSIX (`tr`, `cmp`, `od`, `awk`, `wc`): i byte del file si leggono per una via indipendente dalla colla |
| 4 | record quanti nel file d'origine, chiavi uniche e strettamente crescenti nell'ordine del file (altrimenti la generazione si ferma: needs-spec-update) | `glue/oracle_dati.py` G08-G09, K |
| 5 | cinque record scritti a mano prima della colla (primo, ultimo, chiave 49, due a scelta) | `attesi/<dd>.record.tsv`, `glue/oracle_dati.py` A |

Ogni controllo ha le sue prove negative (`./analysis/run.sh oracle-dati --check`).
