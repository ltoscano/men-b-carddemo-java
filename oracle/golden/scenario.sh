#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/golden/run.sh (issue #55). Esegue CBACT01C (job READACCT) su uno
# scenario e raccoglie cio' che produce.
#   1. File indicizzato:
#      MODO pubblicato  IDX e' un file gia' caricato (scenario esempio: quello del passo dati); lo legge IDXLEGGI, il
#                       lettore indipendente di #53, in ordine di chiave;
#      MODO carica      INGRESSO si carica con oracle/dati/carica.sh di #53, riusato senza modificarlo (IDXLOADF scrive
#                       OUT/carico/ACCTFILE.dat.verifica, IDXLEGGI e IDXDUMP lo rileggono e lo confrontano); IDX = '-'.
#      In entrambi i casi la lettura in ordine di chiave (OUT/letto.bin) deve essere identica byte per byte a INGRESSO:
#      e' il file effettivamente letto, su cui run.sh verifica le proprieta' dello scenario.
#   2. CBACT01C con oracle/esegui.sh e i nomi DD di app/jcl/READACCT.jcl: DD_ACCTFILE, DD_OUTFILE, DD_ARRYFILE,
#      DD_VBRCFILE. Il passo PREDEL del JCL cancella le tre uscite prima del programma: qui le uscite si scrivono nella
#      cartella di lavoro che esegui.sh crea vuota (OUT/lavoro-CBACT01C/). Rapporto in OUT/CBACT01C.txt (codice di
#      uscita, stdout, stderr, file creati) e ambiente ricevuto in OUT/CBACT01C.ambiente.
#   3. Record logici di VBRCFILE con estrai-vb.sh in OUT/VBRCFILE.logici.txt.
# Solo per le prove negative: SCENARIO_USCITE sposta le tre uscite in un'altra cartella (gia' esistente) del container;
# SCENARIO_ESEGUI e SCENARIO_ESTRAI sostituiscono esegui.sh e estrai-vb.sh.
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0 riuscito; 1 errore dello strumento; 3 caricamento o
# lettura non riusciti; 4 lettura diversa da INGRESSO; 5 CBACT01C uscito con un codice diverso da 0 (rapporto e uscite
# restano in OUT per la diagnosi); 6 VBRCFILE malformato.
# Uso: scenario.sh MODO INGRESSO IDX OUT
set -u
ESEGUI="${SCENARIO_ESEGUI:-/oracle/esegui.sh}"
ESTRAI="${SCENARIO_ESTRAI:-/oracle/golden/estrai-vb.sh}"
die() { echo "scenario.sh: $*" >&2; exit 1; }
[ $# -eq 4 ] || die "uso: scenario.sh MODO INGRESSO IDX OUT"
modo="$1"; in="$2"; idx="$3"; out="$4"
[ -f "$in" ] || die "ingresso assente: $in"
[ ! -e "$out" ] || die "cartella dello scenario gia' presente (residuo di una corsa precedente): $out"
mkdir -p "$out" || die "cartella dello scenario non creata: $out"
# codice RAPPORTO: la seconda riga del rapporto di esegui.sh, validata.
codice() {
  c="$(sed -n '2p' "$1")" || die "rapporto illeggibile: $1 (sed)"
  case "$c" in ''|*[!0-9]*) die "codice di uscita non numerico nel rapporto $1: '$c'" ;; esac
  echo "$c"
}
case "$modo" in
  pubblicato)
    [ -f "$idx" ] || die "file indicizzato assente: $idx"
    mkdir -p "$out/lettura" || die "cartella della lettura non creata"
    PATH=/usr/bin:/bin sh "$ESEGUI" "$out/lettura" IDXLEGGI --parm ACCTFILE --dd "DD_ACCTFILE=$idx" \
      --dd "DD_LETTURA=$out/lettura/letto.bin" --dd "DD_CHIAVI=$out/lettura/chiavi.bin" || die "esecuzione di IDXLEGGI fallita (esegui.sh)"
    c="$(codice "$out/lettura/IDXLEGGI.txt")" || exit 1
    [ "$c" -eq 0 ] || { cat "$out/lettura/IDXLEGGI.txt" >&2; echo "scenario.sh: IDXLEGGI: codice di uscita $c, atteso 0" >&2; exit 3; }
    letto="$out/lettura/letto.bin" ;;
  carica)
    [ "$idx" = - ] || die "con MODO carica IDX deve essere '-'"
    r=0; sh /oracle/dati/carica.sh "$in" "$out/carico" > "$out/carico.log" 2>&1 || r=$?
    case "$r" in
      0) ;;
      3) cat "$out/carico.log" >&2; for f in IDXLOADF IDXLEGGI IDXDUMP; do for d in carico lettura rilettura; do
           [ ! -f "$out/carico/$d/$f.txt" ] || cat "$out/carico/$d/$f.txt" >&2 || die "rapporto illeggibile"; done; done
         echo "scenario.sh: caricamento o lettura non riusciti (carica.sh, uscita 3)" >&2; exit 3 ;;
      4) cat "$out/carico.log" >&2; echo "scenario.sh: lettura diversa dall'ingresso (carica.sh, uscita 4)" >&2; exit 4 ;;
      *) cat "$out/carico.log" >&2; die "carica.sh fallito (uscita $r)" ;;
    esac
    idx="$out/carico/ACCTFILE.dat.verifica"; letto="$out/carico/lavoro/lettura.bin" ;;
  *) die "MODO sconosciuto: $modo" ;;
esac
[ -f "$letto" ] || die "lettura assente: $letto"
r=0; cmp "$letto" "$in" > "$out/cmp.txt" 2>&1 || r=$?
case "$r" in
  0) ;;
  1) cat "$out/cmp.txt" >&2; echo "scenario.sh: il file indicizzato letto e' diverso dall'ingresso dello scenario" >&2; exit 4 ;;
  *) cat "$out/cmp.txt" >&2; die "confronto tra lettura e ingresso non eseguito (cmp, codice $r)" ;;
esac
cp "$letto" "$out/letto.bin" || die "lettura non copiata (cp)"
rm -f "$out/cmp.txt" || die "temporaneo non rimosso (rm)"
w="${SCENARIO_USCITE:-$out/lavoro-CBACT01C}"
PATH=/usr/bin:/bin sh "$ESEGUI" "$out" CBACT01C --dd "DD_ACCTFILE=$idx" \
  --dd "DD_OUTFILE=$w/OUTFILE" --dd "DD_ARRYFILE=$w/ARRYFILE" --dd "DD_VBRCFILE=$w/VBRCFILE" \
  || die "esecuzione di CBACT01C fallita (esegui.sh)"
c="$(codice "$out/CBACT01C.txt")" || exit 1
[ "$c" -eq 0 ] || { cat "$out/CBACT01C.txt" >&2 || die "rapporto illeggibile (cat)"
  echo "scenario.sh: CBACT01C: codice di uscita $c, atteso 0 (rapporto in $out/CBACT01C.txt)" >&2; exit 5; }
for f in OUTFILE ARRYFILE VBRCFILE; do [ -f "$w/$f" ] || die "uscita assente: $w/$f"; done
r=0; sh "$ESTRAI" "$w/VBRCFILE" "$out/VBRCFILE.logici.txt" || r=$?
case "$r" in
  0) ;;
  4) echo "scenario.sh: VBRCFILE malformato" >&2; exit 6 ;;
  *) die "estrazione dei record logici fallita (uscita $r)" ;;
esac
[ -f "$out/VBRCFILE.logici.txt" ] || die "record logici assenti"
echo "scenario.sh: $modo, CBACT01C terminato con 0; uscite in $w"
