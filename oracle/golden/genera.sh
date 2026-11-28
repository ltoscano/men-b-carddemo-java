#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/golden/run.sh (issue #55). Genera da zero, in W, i golden del job
# READACCT e li verifica; run.sh pubblica il risultato solo se questo script termina con 0.
# Montaggi attesi (run.sh): /oracle (sola lettura), /oracle-bin (artefatti), /acct/ACCTFILE.dat (il file indicizzato del
# passo dati, sola lettura), W (scrittura) con W/in/esempio.rec (copia privata di analysis/oracle-dati/out/ACCTFILE.rec).
#   1. ingressi: mirato = esempio + sostituzioni-mirato.tsv; osservazione = mirato + sostituzioni-osservazione.tsv
#      (prepara.sh), ciascuno verificato da differenze.sh;
#   2. CBACT01C sui tre scenari (scenario.sh): esempio sul file del passo dati, gli altri caricati con carica.sh di #53;
#   3. proprieta' richieste sul file effettivamente letto (proprieta.sh);
#   4. raccolta in W/generati: golden/esempio, golden/mirato, osservazioni/osservazione (fisici, record logici,
#      rapporto, ambiente, ingresso, MARCATURA); riferimenti dei golden (maschera.sh: correzioni ed esclusioni);
#   5. controlli 2 (conteggi.sh), 3 (attesi.sh), 4 (verificatore.sh, sul riferimento corretto), coerenza tra fisico e
#      riferimento (coerenza.sh), 6 (riesecuzione.sh, osservazione), 5 (separazione.sh);
#   6. documento (documento.sh) in W/golden-readacct.md.
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0 riuscito; altrimenti il codice del primo passo fallito
# (1 errore dello strumento; 3, 4, 5, 6 come scenario.sh e i controlli).
# Uso: genera.sh TABELLE W
set -u
[ $# -eq 2 ] || { echo "genera.sh: uso: genera.sh TABELLE W" >&2; exit 1; }
T="$1"; W="$2"; G=/oracle/golden; N=50
passo() { # passo DESCRIZIONE comando...: esegue, e al primo fallimento esce con il suo codice
  pdesc="$1"; shift
  "$@"; r=$?
  [ "$r" -eq 0 ] || { echo "genera.sh: FALLITO ($pdesc), uscita $r" >&2; exit "$r"; }
}
die() { echo "genera.sh: $*" >&2; exit 1; }
for f in sostituzioni-mirato.tsv sostituzioni-osservazione.tsv proprieta.tsv esclusioni.tsv correzioni.tsv campi.tsv \
         console.tsv attesi-a-mano.tsv; do [ -f "$T/$f" ] || die "tabella assente: $T/$f"; done
[ -f "$W/in/esempio.rec" ] || die "ingresso assente: $W/in/esempio.rec"
[ ! -e "$W/generati" ] && [ ! -e "$W/s" ] || die "risultati di una corsa precedente in $W"

echo "== 1. ingressi"
passo "prepara mirato" sh "$G/prepara.sh" "$W/in/esempio.rec" "$T/sostituzioni-mirato.tsv" "$W/in/mirato.rec"
passo "differenze mirato" sh "$G/differenze.sh" "$W/in/esempio.rec" "$T/sostituzioni-mirato.tsv" "$W/in/mirato.rec"
passo "prepara osservazione" sh "$G/prepara.sh" "$W/in/mirato.rec" "$T/sostituzioni-osservazione.tsv" "$W/in/osservazione.rec"
passo "differenze osservazione" sh "$G/differenze.sh" "$W/in/mirato.rec" "$T/sostituzioni-osservazione.tsv" "$W/in/osservazione.rec"

echo "== 2. CBACT01C sui tre scenari"
mkdir -p "$W/s" || die "cartella degli scenari non creata"
passo "scenario esempio" sh "$G/scenario.sh" pubblicato "$W/in/esempio.rec" /acct/ACCTFILE.dat "$W/s/esempio"
passo "scenario mirato" sh "$G/scenario.sh" carica "$W/in/mirato.rec" - "$W/s/mirato"
passo "scenario osservazione" sh "$G/scenario.sh" carica "$W/in/osservazione.rec" - "$W/s/osservazione"

echo "== 3. proprieta' sul file letto"
for s in esempio mirato osservazione; do
  passo "proprieta $s" sh "$G/proprieta.sh" "$W/s/$s/letto.bin" "$s" "$T/proprieta.tsv" "$W/in/esempio.rec"
done

echo "== 4. raccolta e riferimenti"
raccogli() { # raccogli SCENARIO DEST MARCATURA
  s="$1"; d="$2"
  mkdir -p "$d" || die "cartella $d non creata"
  for f in OUTFILE ARRYFILE VBRCFILE; do cp "$W/s/$s/lavoro-CBACT01C/$f" "$d/$f" || die "copia di $s/$f fallita"; done
  cp "$W/s/$s/VBRCFILE.logici.txt" "$d/VBRCFILE.logici.txt" && cp "$W/s/$s/CBACT01C.txt" "$d/rapporto.txt" \
    && cp "$W/s/$s/CBACT01C.ambiente" "$d/ambiente.txt" && cp "$W/in/$s.rec" "$d/ingresso.rec" || die "copia di $s fallita"
  printf '%s\n' "$3" > "$d/MARCATURA" || die "MARCATURA di $s non scritta"
}
raccogli esempio "$W/generati/golden/esempio" "RIFERIMENTO DI PARITA' - scenario esempio: i 50 record di AWS.M2.CARDDEMO.ACCTDATA.PS (issue #55). Riferimento: *.riferimento.txt; i file fisici sono come li scrive l'oracle."
raccogli mirato "$W/generati/golden/mirato" "RIFERIMENTO DI PARITA' - scenario mirato: esempio con le sostituzioni di sostituzioni-mirato.tsv (issue #55). Riferimento: *.riferimento.txt; i file fisici sono come li scrive l'oracle."
raccogli osservazione "$W/generati/osservazioni/osservazione" "OSSERVAZIONE - scenario osservazione: NON e' un golden ne' un riferimento di parita' (issue #55). Registra cio' che fa GnuCOBOL con un debito di ciclo diverso da zero (OUT-ACCT-CURR-CYC-DEBIT non valorizzato), uno zero negativo e un segno alternativo."
# Si verifica cio' che si pubblica (giro 1 della PR #64): gli ingressi copiati nei golden si riverificano dopo la copia.
r=0; cmp "$W/generati/golden/esempio/ingresso.rec" "$W/in/esempio.rec" > "$W/cmp.txt" 2>&1 || r=$?
case "$r" in 0) ;; 1) cat "$W/cmp.txt" >&2; echo "genera.sh: ingresso pubblicato dello scenario esempio diverso dall'ingresso" >&2; exit 4 ;;
  *) cat "$W/cmp.txt" >&2; die "confronto dell'ingresso pubblicato non eseguito (cmp, codice $r)" ;; esac
rm -f "$W/cmp.txt" || die "temporaneo non rimosso"
passo "differenze mirato, ingressi pubblicati" sh "$G/differenze.sh" "$W/generati/golden/esempio/ingresso.rec" "$T/sostituzioni-mirato.tsv" "$W/generati/golden/mirato/ingresso.rec"
passo "differenze osservazione, ingressi pubblicati" sh "$G/differenze.sh" "$W/generati/golden/mirato/ingresso.rec" "$T/sostituzioni-osservazione.tsv" "$W/generati/osservazioni/osservazione/ingresso.rec"
for s in esempio mirato; do
  passo "riferimenti $s" sh "$G/maschera.sh" "$s" "$W/generati/golden/$s" "$T/esclusioni.tsv" "$T/correzioni.tsv" "$T/console.tsv"
done

echo "== 5. controlli"
for s in esempio mirato; do
  d="$W/generati/golden/$s"
  passo "controllo 2, $s" sh "$G/conteggi.sh" "$d/ingresso.rec" "$d" "$N"
  passo "controllo 3, $s" sh "$G/attesi.sh" "$T/attesi-a-mano.tsv" "$T/sostituzioni-mirato.tsv" "$T/esclusioni.tsv" "$s" "$d"
  passo "controllo 4, $s" sh "$G/verificatore.sh" "$s" "$d/ingresso.rec" "$d" "$T/campi.tsv" "$T/esclusioni.tsv"
  passo "coerenza fisico/riferimento, $s" sh "$G/coerenza.sh" "$s" "$d" "$T/esclusioni.tsv" "$T/correzioni.tsv"
done
passo "controllo 2, osservazione" sh "$G/conteggi.sh" "$W/generati/osservazioni/osservazione/ingresso.rec" "$W/generati/osservazioni/osservazione" "$N"
passo "controllo 6, riesecuzione" sh "$G/riesecuzione.sh" /acct/ACCTFILE.dat "$W/generati/golden/esempio" "$W/riesecuzione"
mkdir -p "$W/generati/osservazioni/riesecuzione" || die "cartella della riesecuzione non creata"
for f in rapporto.txt ambiente.txt esito.txt; do
  cp "$W/riesecuzione/$f" "$W/generati/osservazioni/riesecuzione/$f" || die "copia di riesecuzione/$f fallita"
done
passo "controllo 5" sh "$G/separazione.sh" "$W/generati"

echo "== 6. documento"
passo "documento" sh "$G/documento.sh" "$W/generati" "$T" "$W/golden-readacct.md"
passo "impronte del documento" sh "$G/impronte.sh" "$W/golden-readacct.md" "$W/generati"
echo "genera.sh: golden generati e verificati in $W/generati"
