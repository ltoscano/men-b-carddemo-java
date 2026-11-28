#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/golden/run.sh (issue #55). Controllo 6, osservazione dichiarata:
# seconda esecuzione di CBACT01C in una cartella in cui i tre file d'uscita esistono gia'. Il JCL (READACCT.jcl) li
# cancella prima con il passo PREDEL (DISP=(MOD,DELETE,DELETE), righe 22-28) e li crea con DISP=(NEW,CATLG,DELETE)
# (righe 37-48): su z/OS il programma non trova mai file preesistenti. Qui si registra che cosa fa GnuCOBOL con
# OPEN OUTPUT su un file che esiste: i tre file si preparano con 20000 byte "R" ciascuno (piu' lunghi delle uscite),
# il programma gira con DD_OUTFILE, DD_ARRYFILE, DD_VBRCFILE puntati su di essi, e si confrontano le uscite con quelle
# della prima esecuzione (PRIMA: cartella con OUTFILE, ARRYFILE, VBRCFILE).
# Scrive in OUT: rapporto.txt (esegui.sh), ambiente.txt, esito.txt (una riga per file: dimensione prima, dopo, se
# identico alla prima esecuzione).
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0; 1 errore dello strumento; 5 programma uscito con un
# codice diverso da 0.
# Uso: riesecuzione.sh IDX PRIMA OUT
set -u
die() { echo "riesecuzione.sh: $*" >&2; exit 1; }
[ $# -eq 3 ] || die "uso: riesecuzione.sh IDX PRIMA OUT"
idx="$1"; prima="$2"; out="$3"
[ -f "$idx" ] || die "file indicizzato assente: $idx"
[ ! -e "$out" ] || die "cartella gia' presente (residuo): $out"
mkdir -p "$out/esistenti" "$out/esecuzione" || die "cartelle non create"
dd if=/dev/zero bs=20000 count=1 of="$out/zeri" 2> "$out/dd.log" || die "file di preparazione non creato (dd)"
for f in OUTFILE ARRYFILE VBRCFILE; do
  [ -f "$prima/$f" ] || die "uscita della prima esecuzione assente: $prima/$f"
  tr '\000' R < "$out/zeri" > "$out/esistenti/$f" || die "file preesistente $f non creato (tr)"
done
rm -f "$out/zeri" "$out/dd.log" || die "temporanei non rimossi"
PATH=/usr/bin:/bin sh /oracle/esegui.sh "$out/esecuzione" CBACT01C --dd "DD_ACCTFILE=$idx" \
  --dd "DD_OUTFILE=$out/esistenti/OUTFILE" --dd "DD_ARRYFILE=$out/esistenti/ARRYFILE" --dd "DD_VBRCFILE=$out/esistenti/VBRCFILE" \
  || die "esecuzione di CBACT01C fallita (esegui.sh)"
c="$(sed -n '2p' "$out/esecuzione/CBACT01C.txt")" || die "rapporto illeggibile (sed)"
case "$c" in ''|*[!0-9]*) die "codice non numerico nel rapporto: '$c'" ;; esac
[ "$c" -eq 0 ] || { echo "riesecuzione.sh: CBACT01C uscito con $c" >&2; exit 5; }
: > "$out/esito.txt" || die "esito non scrivibile"
for f in OUTFILE ARRYFILE VBRCFILE; do
  d="$(wc -c < "$out/esistenti/$f")" || die "dimensione di $f non letta (wc)"
  d="${d#"${d%%[! ]*}"}"; d="${d%"${d##*[! ]}"}"
  case "$d" in ''|*[!0-9]*) die "dimensione non numerica: '$d'" ;; esac
  r=0; cmp -s "$out/esistenti/$f" "$prima/$f" || r=$?
  case "$r" in 0) u=si ;; 1) u=no ;; *) die "confronto di $f non eseguito (cmp, codice $r)" ;; esac
  echo "$f: prima dell'esecuzione 20000 byte R, dopo $d byte, identico alla prima esecuzione: $u" >> "$out/esito.txt" || die "esito non scritto"
done
mv "$out/esecuzione/CBACT01C.txt" "$out/rapporto.txt" && mv "$out/esecuzione/CBACT01C.ambiente" "$out/ambiente.txt" \
  || die "rapporto non spostato (mv)"
rm -rf "$out/esecuzione" || die "cartella di esecuzione non rimossa"
echo "riesecuzione.sh: osservazione registrata in $out"
