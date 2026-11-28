#!/bin/sh
# Controllo 3 dell'issue #53: controprova byte per byte con il file ASCII. Eseguito DENTRO un container (immagine di
# base della colla, solo le sue utility POSIX: awk, tr, cmp, od, wc, mktemp, rm), MAI con la colla Python che ha
# prodotto i record: i byte del file ASCII e del file prodotto si leggono qui per un'altra via.
#
# Per ogni riga di TABELLA con una controprova:
#   - il file ASCII ha n righe di esattamente L byte, ciascuna chiusa da LF, e nient'altro (dimensione n*(L+1));
#   - tolti i terminatori (tr -d '\n') restano n*L byte; il file prodotto ha anch'esso n*L byte;
#   - cmp -l elenca i byte diversi; l'elenco deve essere ESATTAMENTE quello che si ricava dal file scritto a mano
#     ATTESI/<dd>.controprova.tsv: per ogni sua riga, i byte del file ASCII e del prodotto a quella posizione sono quelli
#     scritti, la chiave del record prodotto e' quella scritta, e i byte che differiscono sono tutti e soli quelli
#     elencati da cmp. Una differenza mancante o in piu', o byte diversi da quelli scritti, sono un difetto.
#
# Uso: controprova.sh LEGACY TABELLA ATTESI OUT
# Stampa una riga "DIFETTO: ..." per difetto e alla fine "controprova riuscita: ..." o "controprova fallita: ...".
# Esiti: 0 riuscita; 1 difetto; 2 errore operativo (un comando fallito o una risposta malformata: mai un esito).
set -u
set -o pipefail
[ $# -eq 4 ] || { echo "uso: controprova.sh LEGACY TABELLA ATTESI OUT" >&2; exit 2; }
legacy="$1"; tab="$2"; att="$3"; out="$4"
TAB='	'
# Gli errori operativi vanno su stderr: anche da dentro una sostituzione di comando arrivano al chiamante.
op() { echo "ERRORE operativo: $*" >&2; exit 2; }
errs=0
dif() { echo "DIFETTO: $*"; errs=$((errs + 1)); }
numero() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
w="$(mktemp -d /tmp/issue53-controprova.XXXXXX)" || op "cartella temporanea non creabile (mktemp)"
[ -d "$w" ] || op "mktemp non ha creato la cartella temporanea: '$w'"
trap 'rm -rf "$w" || { echo "ERRORE operativo: temporanei non rimossi (rm)" >&2; exit 2; }' EXIT

# dimensione FILE: byte del file, validati (wc -c con l'esito controllato e la risposta numerica).
dimensione() {
  d="$(wc -c < "$1")" || op "dimensione di $1 non leggibile (wc)"
  set -- $d
  [ $# -eq 1 ] && numero "$1" || op "risposta di wc non numerica: '$d'"
  echo "$1"
}
# esa FILE POSIZIONE LUNGHEZZA: i byte in esadecimale maiuscolo, separati da uno spazio (od e tr con l'esito
# controllato; il numero di byte letti deve essere LUNGHEZZA).
esa() {
  h="$(od -An -v -tx1 -j "$2" -N "$3" "$1")" || op "lettura di $1 fallita (od)"
  h="$(printf '%s' "$h" | tr 'abcdef' 'ABCDEF')" || op "conversione dell'esadecimale fallita (tr)"
  n="$3"; f="$1"
  set -- $h
  [ $# -eq "$n" ] || op "od ha restituito $# byte invece di $n da $f"
  echo "$*"
}

# Righe della tabella: dd, chiave_lunghezza, chiave_offset, lunghezza_record, controprova, uscita (per nome di colonna).
awk -F'\t' '/^#/ || !NF { next }
  !h { for (i = 1; i <= NF; i++) c[$i] = i; h = 1
       if (!("dd" in c) || !("chiave_lunghezza" in c) || !("chiave_offset" in c) || !("lunghezza_record" in c) \
           || !("controprova" in c) || !("uscita" in c)) exit 3
       next }
  { print $c["dd"] "\t" $c["chiave_lunghezza"] "\t" $c["chiave_offset"] "\t" $c["lunghezza_record"] "\t" \
          $c["controprova"] "\t" $c["uscita"] }' "$tab" > "$w/tabella"
r=$?; [ "$r" -eq 0 ] || op "tabella $tab illeggibile o senza le colonne necessarie (awk, codice $r)"
[ -s "$w/tabella" ] || op "tabella $tab senza righe"
riass=""
while IFS="$TAB" read -r dd kl ko L cp usc; do
  [ "$cp" != - ] || continue
  for v in "$kl" "$ko" "$L"; do numero "$v" || op "$dd: valore non numerico nella tabella: '$v'"; done
  [ "$L" -gt 0 ] || op "$dd: lunghezza del record nulla"
  A="$legacy/$cp"; R="$out/$usc"; H="$att/$dd.controprova.tsv"
  [ -f "$A" ] || op "$dd: file ASCII assente: $cp"
  [ -f "$R" ] || { dif "$dd: file prodotto assente: $usc"; continue; }
  [ -f "$H" ] || { dif "$dd: controprova scritta a mano assente: $dd.controprova.tsv"; continue; }
  # 1. struttura del file ASCII: n righe di L byte chiuse da LF.
  sa="$(dimensione "$A")" || exit 2
  n=$((sa / (L + 1)))
  if [ "$n" -eq 0 ] || [ $((n * (L + 1))) -ne "$sa" ]; then
    dif "$dd: $cp ha $sa byte, non n righe di $L byte piu' LF"; continue
  fi
  LC_ALL=C awk -v L="$L" 'length($0) != L { print "riga " NR ": " length($0) " byte" } END { print "righe " NR }' \
    "$A" > "$w/righe"
  r=$?; [ "$r" -eq 0 ] || op "$dd: righe di $cp non contate (awk, codice $r)"
  righe="$(awk 'END { print NR }' "$w/righe")" || op "$dd: conteggio delle righe illeggibile (awk)"
  ultima="$(awk 'END { print $0 }' "$w/righe")" || op "$dd: conteggio delle righe illeggibile (awk)"
  if [ "$righe" != 1 ] || [ "$ultima" != "righe $n" ]; then
    dif "$dd: $cp non e' fatto di $n righe di $L byte chiuse da LF:"
    while IFS= read -r x; do echo "    $x"; done < "$w/righe"
    continue
  fi
  # 2. record senza terminatori e dimensione del prodotto.
  tr -d '\n' < "$A" > "$w/ascii" || op "$dd: terminatori non rimossi (tr)"
  s1="$(dimensione "$w/ascii")" || exit 2
  [ "$s1" -eq $((n * L)) ] || op "$dd: tolti i terminatori restano $s1 byte invece di $((n * L)) (tr)"
  sr="$(dimensione "$R")" || exit 2
  if [ "$sr" -ne $((n * L)) ]; then dif "$dd: $usc ha $sr byte, attesi $n record di $L ($((n * L)))"; continue; fi
  # 3. differenze reali: cmp -l, una riga per byte diverso (posizione da 1, ottale, ottale). 0 nessuna, 1 qualcuna.
  r=0; cmp -l "$w/ascii" "$R" > "$w/cmp" 2> "$w/cmp.err" || r=$?
  case "$r" in 0|1) ;; *) op "$dd: confronto non eseguito (cmp, codice $r)" ;; esac
  [ -s "$w/cmp.err" ] && op "$dd: cmp ha scritto su stderr: $(awk 'NR == 1' "$w/cmp.err")"
  awk '{ if (NF != 3 || $1 !~ /^[0-9]+$/ || $2 !~ /^[0-7]+$/ || $3 !~ /^[0-7]+$/) exit 3; printf "%d %d %d\n", $1, $2, $3 }' \
    "$w/cmp" > "$w/reali"
  r=$?; [ "$r" -eq 0 ] || op "$dd: uscita di cmp malformata (awk, codice $r)"
  # 4. differenze attese, dal file scritto a mano; per ogni riga si rileggono i byte dei due file.
  awk -F'\t' '/^#/ || !NF { next } !h { h = 1; if ($0 != "record\tchiave\tcampo\toffset\tlunghezza\tascii\tprodotto") exit 3; next }
    { if (NF != 7) exit 4; print }' "$H" > "$w/attese"
  r=$?
  case "$r" in
    0) ;;
    3|4) dif "$dd: $dd.controprova.tsv malformato (codice $r: 3 intestazione, 4 colonne)"; continue ;;
    *) op "$dd: $dd.controprova.tsv illeggibile (awk, codice $r)" ;;
  esac
  : > "$w/previste" || op "$dd: file temporaneo non scrivibile"
  while IFS="$TAB" read -r rec chiave campo off len ea ep; do
    for v in "$rec" "$off" "$len"; do numero "$v" || { dif "$dd: valore non numerico nella controprova: '$v'"; continue 2; }; done
    set -- $ea; na=$#; set -- $ep
    if [ "$na" -ne "$len" ] || [ $# -ne "$len" ]; then dif "$dd: record $rec $campo: $na e $# byte scritti, lunghezza $len"; continue; fi
    if [ "$rec" -lt 1 ] || [ "$rec" -gt "$n" ] || [ $((off + len)) -gt "$L" ]; then dif "$dd: record $rec $campo fuori dal file"; continue; fi
    pos=$(((rec - 1) * L + off))
    fa="$(esa "$w/ascii" "$pos" "$len")" || exit 2
    fp="$(esa "$R" "$pos" "$len")" || exit 2
    [ "$fa" = "$ea" ] || dif "$dd: record $rec $campo: byte del file ASCII '$fa', scritti a mano '$ea'"
    [ "$fp" = "$ep" ] || dif "$dd: record $rec $campo: byte del prodotto '$fp', scritti a mano '$ep'"
    fk="$(esa "$R" $(((rec - 1) * L + ko)) "$kl")" || exit 2
    hk="$(printf '%s' "$chiave" | od -An -v -tx1)" || op "$dd: chiave non convertibile (od)"
    hk="$(printf '%s' "$hk" | tr 'abcdef' 'ABCDEF')" || op "$dd: conversione dell'esadecimale fallita (tr)"
    set -- $hk
    [ $# -eq "${#chiave}" ] || op "$dd: od ha restituito $# byte per una chiave di ${#chiave} caratteri"
    [ "$fk" = "$*" ] || dif "$dd: record $rec: chiave del prodotto '$fk', scritta a mano '$chiave' ($*)"
    # byte che differiscono fra i due valori scritti: le righe che cmp -l deve produrre
    i=0; set -- $ep
    for a in $ea; do
      p="$1"; shift
      case "$a$p" in *[!0-9A-F]*) dif "$dd: record $rec $campo: esadecimale non valido '$a' '$p'"; continue 2 ;; esac
      if [ "$a" != "$p" ]; then
        printf '%d %o %o\n' $((pos + i + 1)) "0x$a" "0x$p" >> "$w/previste" || op "$dd: file temporaneo non scrivibile"
      fi
      i=$((i + 1))
    done
  done < "$w/attese"
  # 5. le differenze reali devono essere esattamente quelle previste: nessuna mancante, nessuna in piu'.
  # (il file delle previste si riconosce dal nome, non da FNR == NR: con le previste vuote quella condizione varrebbe
  # anche per le reali, che diventerebbero "previste")
  awk -v L="$L" -v P="$w/previste" 'FILENAME == P { p[$0] = 1; next } { r[$0] = 1 }
    END { for (k in r) if (!(k in p)) { split(k, x, " "); printf "differenza non attesa al byte %d (record %d, posizione %d)\n", x[1], int((x[1] - 1) / L) + 1, (x[1] - 1) % L + 1 }
          for (k in p) if (!(k in r)) { split(k, x, " "); printf "differenza attesa assente al byte %d (record %d, posizione %d)\n", x[1], int((x[1] - 1) / L) + 1, (x[1] - 1) % L + 1 } }' \
    "$w/previste" "$w/reali" > "$w/scarti"
  r=$?; [ "$r" -eq 0 ] || op "$dd: confronto delle differenze non eseguito (awk, codice $r)"
  while IFS= read -r x; do dif "$dd: $x"; done < "$w/scarti"
  nr="$(awk 'END { print NR }' "$w/reali")" || op "$dd: differenze non contate (awk)"
  riass="$riass $dd: $n record, $nr byte diversi dal file ASCII, tutti e soli quelli scritti a mano;"
done < "$w/tabella"
if [ "$errs" -ne 0 ]; then echo "controprova fallita: $errs difetti"; exit 1; fi
[ -n "$riass" ] || op "nessuna riga della tabella ha una controprova"
echo "controprova riuscita:${riass%;}"
exit 0
