#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/adattamenti/check.sh. Verifica le copie di
# compilazione adattate di CBSTM03A (oracle/adattamenti/registro.md). Stampa una riga "DIFETTO: ..." per
# ogni difetto trovato e alla fine l'esito; esce con 1 se c'e' almeno un difetto, con 0 altrimenti.
#
#   verifica-copie.sh copie OUT
#       OUT/adattati contiene esattamente CBSTM03A.CBL e CUSTREC.cpy;
#       CUSTREC.cpy: identica alla riapplicazione indipendente (expand -t 4 di coreutils, non l'awk della
#       build) sull'originale; nessun TAB; nessun carattere diverso da spazio oltre la colonna 72; righe
#       con TAB nell'originale esattamente le 17 righe 6-22; le altre identiche byte per byte;
#       CBSTM03A.CBL: stesso numero di righe e di byte dell'originale; le righe diverse sono esattamente
#       le 23 righe non vuote di 266-291 (elenco fisso qui sotto), ognuna diversa solo nella colonna 7
#       (spazio -> '*'); le tre righe vuote 271, 274, 286 identiche e vuote; cmp conta 23 byte diversi.
#   verifica-copie.sh tracciato OUT
#       ricompila CBSTM03A in sola analisi con gli argomenti di cobc registrati dalla build in
#       OUT/log/CBSTM03A.log (stesse opzioni, stessa copia, stessa cartella -I) piu' -fsyntax-only,
#       il listato dei simboli (-t -ftsymbols) e l'elenco dei file letti (-MT -MF):
#       - il tracciato di CUSTOMER-RECORD visto dal compilatore (nome, posizione, lunghezza) coincide
#         con oracle/adattamenti/expected/custrec-tracciato.tsv, scritto a mano dal copybook;
#       - ogni campo di quell'atteso compare davvero alla riga dichiarata del copybook originale;
#       - i file letti sono esattamente la copia di CBSTM03A, COSTM01, CVACT03Y e CVACT01Y da
#         /legacy/app/cpy e CUSTREC dalla copia adattata.
#   verifica-copie.sh zos SORGENTE
#       nel SORGENTE (di norma l'originale /legacy/app/cbl/CBSTM03A.CBL) le occorrenze dei dati usati
#       dalle righe 266-291 sono esattamente quelle di oracle/adattamenti/expected/blocchi-zos.tsv.
# OUT e' la cartella della build vista dal container, sempre montata su /out (i percorsi registrati
# dalla build cominciano con /out).
# Solo per le prove negative del controllo: VERIFICA_LEGACY sostituisce la radice del legacy da cui si
# leggono gli originali (default /legacy), VERIFICA_ATTESI la cartella degli attesi.
set -u
. /oracle/ambiente.sh
EXP="${VERIFICA_ATTESI:-/oracle/adattamenti/expected}"
LEG="${VERIFICA_LEGACY:-/legacy}"
TAB="$(printf '\t')"
errs=0
err() { echo "DIFETTO: $*"; errs=$((errs + 1)); }
w="$(mktemp -d /tmp/verifica-copie.XXXXXX)" || { echo "DIFETTO: cartella temporanea non creabile"; exit 1; }
fine() {
  rm -rf "$w"
  if [ "$errs" -eq 0 ]; then echo "verifica riuscita: $1"; exit 0; fi
  echo "verifica fallita: $errs difetti"; exit 1
}
[ $# -eq 2 ] || { echo "uso: verifica-copie.sh copie OUT | tracciato OUT | zos SORGENTE" >&2; exit 2; }

# Le 23 righe non vuote dell'intervallo 266-291 (righe vuote: 271, 274, 286), scritte a mano.
RIGHE_ADATTATE="266 267 268 269 270 272 273 275 276 277 278 279 280 281 282 283 284 285 287 288 289 290 291"
RIGHE_VUOTE="271 274 286"
# Righe di CUSTREC.cpy che contengono TAB nell'originale (6-22), scritte a mano.
RIGHE_TAB="6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22"

case "$1" in
copie)
  out="$2"; ocp="$LEG/app/cpy/CUSTREC.cpy"; ocb="$LEG/app/cbl/CBSTM03A.CBL"
  ccp="$out/adattati/CUSTREC.cpy"; ccb="$out/adattati/CBSTM03A.CBL"
  # Contenuto della cartella delle copie.
  if [ -d "$out/adattati" ]; then
    if ls -A "$out/adattati" > "$w/ada.txt"; then
      got="$(LC_ALL=C sort "$w/ada.txt" | tr '\n' ' ')"
      [ "$got" = "CBSTM03A.CBL CUSTREC.cpy " ] || err "adattati/: contenuto '$got', atteso 'CBSTM03A.CBL CUSTREC.cpy '"
    else
      err "adattati/: elenco dei file fallito"
    fi
  else
    err "adattati/: cartella assente"
  fi
  # --- CUSTREC.cpy ---
  if [ -f "$ccp" ] && [ -r "$ccp" ] && [ -r "$ocp" ]; then
    if expand -t 4 "$ocp" > "$w/riapplicata.cpy"; then
      if ! cmp -s "$w/riapplicata.cpy" "$ccp"; then
        err "CUSTREC.cpy: la copia e' diversa dalla riapplicazione indipendente (expand -t 4) sull'originale:"
        diff "$w/riapplicata.cpy" "$ccp" | sed 's/^/      /'
      fi
    else
      err "CUSTREC.cpy: expand -t 4 sull'originale fallito"
    fi
    # grep: 0 = trovato, 1 = nessuna riga, altro = errore di lettura (che non deve passare per "nessuna").
    grep -n "$TAB" "$ccp" > "$w/tab-copia.txt"; rc=$?
    if [ "$rc" -gt 1 ]; then err "CUSTREC.cpy: lettura della copia fallita (grep $rc)"
    elif [ -s "$w/tab-copia.txt" ]; then err "CUSTREC.cpy: TAB nella copia (righe: $(cut -d: -f1 "$w/tab-copia.txt" | tr '\n' ' '))"; fi
    lunghe="$(awk 'substr($0, 73) ~ /[^ ]/ {printf "%d ", NR}' "$ccp")" || err "CUSTREC.cpy: lettura della copia fallita"
    [ -z "$lunghe" ] || err "CUSTREC.cpy: testo oltre la colonna 72 nelle righe: $lunghe"
    grep -n "$TAB" "$ocp" > "$w/tab-orig.txt"; rc=$?
    [ "$rc" -le 1 ] || err "CUSTREC.cpy: lettura dell'originale fallita (grep $rc)"
    tabo="$(cut -d: -f1 "$w/tab-orig.txt" | tr '\n' ' ' | sed 's/ $//')"
    [ "$tabo" = "$RIGHE_TAB" ] || err "CUSTREC.cpy: righe con TAB nell'originale '$tabo', attese '$RIGHE_TAB'"
    # Righe senza TAB nell'originale: identiche byte per byte nella copia; stesso numero di righe.
    diverse="$(awk -v T="$TAB" 'NR == FNR {o[FNR] = $0; no = FNR; next}
      { nc = FNR; if (!(FNR in o) || (index(o[FNR], T) == 0 && o[FNR] != $0)) printf "%d ", FNR }
      END { if (no != nc) printf "numero-di-righe:%d/%d ", no, nc }' "$ocp" "$ccp")" \
      || err "CUSTREC.cpy: confronto riga per riga fallito"
    [ -z "$diverse" ] || err "CUSTREC.cpy: righe senza TAB nell'originale cambiate nella copia: $diverse"
  else
    err "CUSTREC.cpy: copia o originale assente o illeggibile"
  fi
  # --- CBSTM03A.CBL ---
  if [ -f "$ccb" ] && [ -r "$ccb" ] && [ -r "$ocb" ]; then
    awk 'NR == FNR {o[FNR] = $0; no = FNR; next}
      { c[FNR] = $0; nc = FNR }
      END {
        if (no != nc) printf "DIFETTO: CBSTM03A.CBL: numero di righe %d, originale %d\n", nc, no
        m = (no > nc) ? no : nc
        for (i = 1; i <= m; i++) {
          if (o[i] == c[i]) continue
          printf "CAMBIATA %d\n", i
          if (i < 266 || i > 291) { printf "DIFETTO: CBSTM03A.CBL riga %d: modificata fuori dall intervallo 266-291\n", i; continue }
          if (o[i] == "") { printf "DIFETTO: CBSTM03A.CBL riga %d: riga vuota dell intervallo alterata\n", i; continue }
          if (length(o[i]) != length(c[i]) || substr(o[i], 1, 6) != substr(c[i], 1, 6) || substr(o[i], 8) != substr(c[i], 8) \
              || substr(o[i], 7, 1) != " " || substr(c[i], 7, 1) != "*")
            printf "DIFETTO: CBSTM03A.CBL riga %d: non e la sola sostituzione dello spazio in colonna 7 con *\n", i
        }
      }' "$ocb" "$ccb" > "$w/cbl.txt" || err "CBSTM03A.CBL: confronto riga per riga fallito"
    grep '^DIFETTO: ' "$w/cbl.txt"
    errs=$((errs + $(grep -c '^DIFETTO: ' "$w/cbl.txt")))
    cambiate="$(sed -n 's/^CAMBIATA //p' "$w/cbl.txt" | tr '\n' ' ' | sed 's/ $//')"
    if [ "$cambiate" != "$RIGHE_ADATTATE" ]; then
      for i in $RIGHE_ADATTATE; do
        case " $cambiate " in *" $i "*) ;; *) err "CBSTM03A.CBL riga $i: non commentata (attese le 23 righe non vuote di 266-291)" ;; esac
      done
      err "CBSTM03A.CBL: righe cambiate '$cambiate', attese '$RIGHE_ADATTATE'"
    fi
    for i in $RIGHE_VUOTE; do
      if lc="$(sed -n "${i}p" "$ccb")" && lo="$(sed -n "${i}p" "$ocb")"; then
        [ -z "$lc" ] && [ -z "$lo" ] || err "CBSTM03A.CBL riga $i: attesa vuota nell'originale e nella copia"
      else
        err "CBSTM03A.CBL riga $i: lettura fallita"
      fi
    done
    if so="$(wc -c < "$ocb")" && sc="$(wc -c < "$ccb")"; then
      [ "$so" -eq "$sc" ] || err "CBSTM03A.CBL: $sc byte, originale $so"
    else
      err "CBSTM03A.CBL: dimensioni non leggibili"
    fi
    # cmp -l: 0 = uguali, 1 = diversi, altro = errore (anche EOF su uno dei due, cioe' lunghezze diverse).
    cmp -l "$ocb" "$ccb" > "$w/cmp.txt" 2> "$w/cmp.err"; rc=$?
    if [ "$rc" -gt 1 ] || [ -s "$w/cmp.err" ]; then err "CBSTM03A.CBL: confronto byte per byte non completo (cmp $rc: $(head -n 1 "$w/cmp.err"))"; fi
    nb="$(wc -l < "$w/cmp.txt" | tr -d ' ')"
    [ "$nb" -eq 23 ] || err "CBSTM03A.CBL: $nb byte diversi dall'originale (cmp -l), attesi 23"
  else
    err "CBSTM03A.CBL: copia o originale assente o illeggibile"
  fi
  fine "copie adattate conformi: CUSTREC.cpy (17 righe con TAB espanse a 4 colonne, identica a expand -t 4), CBSTM03A.CBL (23 righe commentate in colonna 7)"
  ;;

tracciato)
  out="$2"; logf="$out/log/CBSTM03A.log"
  [ -f "$logf" ] || { err "tracciato: log di compilazione di CBSTM03A assente"; fine ""; }
  # Argomenti della prima invocazione di cobc registrata dalla build.
  awk '/^== cobc$/ {n++; next} /^== / {next} n == 1 && /^arg / {print substr($0, 5)}' "$logf" > "$w/arg.txt" \
    || { err "tracciato: lettura del log di compilazione fallita"; fine ""; }
  na="$(wc -l < "$w/arg.txt")" && coda="$(tail -n 4 "$w/arg.txt" | tr '\n' ' ')" \
    || { err "tracciato: lettura degli argomenti fallita"; fine ""; }
  [ "$coda" = "-c -o /out/obj/CBSTM03A.o /out/adattati/CBSTM03A.CBL " ] \
    || { err "tracciato: argomenti registrati inattesi in coda: '$coda'"; fine ""; }
  head -n $((na - 4)) "$w/arg.txt" > "$w/opz.txt" && opz="$(cat "$w/opz.txt")" \
    || { err "tracciato: lettura degli argomenti fallita"; fine ""; }
  # Gli argomenti prima di quelli strutturali: la cartella adattata in testa, poi le opzioni.
  [ "$(sed -n 1p "$w/opz.txt")" = "-I/out/adattati" ] || { err "tracciato: il primo argomento registrato non e' -I/out/adattati"; fine ""; }
  # shellcheck disable=SC2086
  set -- $opz
  # La stessa compilazione, in sola analisi, con listato dei simboli ed elenco dei file letti.
  # shellcheck disable=SC2086
  if ! env -i $AMBIENTE_COBC timeout -k 10 300 cobc "$@" -fsyntax-only -t "$w/lista.lst" -ftsymbols \
       -MT dipendenze -MF "$w/dip.txt" /out/adattati/CBSTM03A.CBL > "$w/cobc.log" 2>&1; then
    err "tracciato: compilazione di controllo di CBSTM03A fallita con gli argomenti della build:"
    grep -E 'error' "$w/cobc.log" | head -n 20 | sed 's/^/      /'
    fine ""
  fi
  # Righe del listato dei simboli: SIZE TYPE LVL NAME [PICTURE]; da CUSTOMER-RECORD al livello 01 seguente.
  awk '$1 ~ /^[0-9][0-9][0-9][0-9][0-9]$/ && $3 ~ /^[0-9][0-9]$/ {
         if (dentro && ($3 == "01" || $3 == "77")) exit
         if ($3 == "01" && $4 == "CUSTOMER-RECORD") { dentro = 1; pos = 1; printf "%s\t1\t%d\n", $4, $1 + 0; next }
         if (dentro) { if ($3 != "05") printf "LIVELLO\t%s\t%s\n", $4, $3; printf "%s\t%d\t%d\n", $4, pos, $1 + 0; pos += $1 }
       }' "$w/lista.lst" > "$w/tracciato.txt" || err "tracciato: lettura del listato dei simboli fallita"
  awk -F"$TAB" '!/^#/ && $1 != "campo" {print $1 "\t" $2 "\t" $3}' "$EXP/custrec-tracciato.tsv" > "$w/atteso.txt" \
    || err "tracciato: lettura dell'atteso fallita"
  # L'atteso scritto a mano ha il record e i suoi 19 campi: un atteso vuoto o troncato non vale.
  [ "$(wc -l < "$w/atteso.txt")" -eq 20 ] || err "tracciato: l'atteso non ha 20 righe (record e 19 campi)"
  if ! cmp -s "$w/atteso.txt" "$w/tracciato.txt"; then
    err "tracciato di CUSTOMER-RECORD visto dal compilatore diverso dall'atteso scritto a mano (nome, posizione, lunghezza):"
    diff "$w/atteso.txt" "$w/tracciato.txt" | sed 's/^/      /'
  fi
  # Ogni campo dell'atteso alla riga dichiarata del copybook originale.
  awk -F"$TAB" '!/^#/ && $1 != "campo" {print $1 " " $4}' "$EXP/custrec-tracciato.tsv" > "$w/nomi-righe.txt" \
    || err "tracciato: lettura dell'atteso fallita"
  [ "$(wc -l < "$w/nomi-righe.txt")" -eq 20 ] || err "tracciato: righe del copybook non lette dall'atteso"
  while read -r nome riga; do
    sed -n "${riga}p" "$LEG/app/cpy/CUSTREC.cpy" | grep -Eq "(^|[^A-Z0-9-])$nome([^A-Z0-9-]|\$)" \
      || err "tracciato atteso: $nome non e' alla riga $riga di CUSTREC.cpy"
  done < "$w/nomi-righe.txt"
  # File letti dalla compilazione, nell'ordine. cobc prova le estensioni nell'ordine .CPY, .cpy: se la
  # cartella della build e' su un file system che non distingue le maiuscole (bind mount di macOS), apre
  # adattati/CUSTREC.CPY, che e' lo stesso file di adattati/CUSTREC.cpy. Un nome sotto /out/adattati/ si
  # riporta quindi al nome del file della cartella che e' lo stesso file (test -ef: stesso dispositivo e
  # inode); su un file system che distingue le maiuscole il nome resta quello che e'.
  awk '{for (i = 1; i <= NF; i++) if ($i != "\\" && $i !~ /:$/) print $i}' "$w/dip.txt" | awk '!s[$0]++' > "$w/letti-grezzi.txt"
  while read -r e; do
    case "$e" in
      /out/adattati/*)
        c="$e"
        for f in /out/adattati/*; do if [ "$e" -ef "$f" ]; then c="$f"; break; fi; done
        echo "$c" ;;
      *) echo "$e" ;;
    esac
  done < "$w/letti-grezzi.txt" > "$w/letti.txt"
  printf '%s\n' /out/adattati/CBSTM03A.CBL /legacy/app/cpy/COSTM01.CPY /legacy/app/cpy/CVACT03Y.cpy \
    /out/adattati/CUSTREC.cpy /legacy/app/cpy/CVACT01Y.cpy > "$w/letti-attesi.txt"
  if ! cmp -s "$w/letti-attesi.txt" "$w/letti.txt"; then
    err "copybook letti dalla compilazione di CBSTM03A diversi da quelli attesi (CUSTREC dalla copia, gli altri da /legacy/app/cpy):"
    diff "$w/letti-attesi.txt" "$w/letti.txt" | sed 's/^/      /'
  fi
  fine "tracciato di CUSTOMER-RECORD di 500 byte e 19 campi come l'atteso; copybook letti: CUSTREC dalla copia adattata, COSTM01, CVACT03Y, CVACT01Y da /legacy/app/cpy"
  ;;

zos)
  src="$2"
  [ -f "$src" ] || { err "zos: sorgente assente: $src"; fine ""; }
  awk -F"$TAB" '!/^#/ && $1 != "nome" {print $1}' "$EXP/blocchi-zos.tsv" | awk '!s[$0]++' > "$w/nomi.txt" \
    || err "zos: lettura dell'atteso fallita"
  # I nomi sono i 19 dati delle righe 266-291 e le loro dichiarazioni: un atteso vuoto o troncato non vale.
  [ "$(wc -l < "$w/nomi.txt")" -eq 19 ] || err "zos: l'atteso non elenca 19 nomi"
  : > "$w/trovate.txt"
  while read -r nome; do
    grep -n -i -E "(^|[^A-Za-z0-9-])$nome([^A-Za-z0-9-]|\$)" "$src" > "$w/g.txt"; rc=$?
    [ "$rc" -le 1 ] || err "zos: ricerca di $nome fallita (grep $rc)"
    cut -d: -f1 "$w/g.txt" | sed "s/^/$nome$TAB/" >> "$w/trovate.txt"
  done < "$w/nomi.txt"
  LC_ALL=C sort "$w/trovate.txt" > "$w/trovate.s"
  awk -F"$TAB" '!/^#/ && $1 != "nome" {print $1 "\t" $2}' "$EXP/blocchi-zos.tsv" | LC_ALL=C sort > "$w/attese.s" \
    || err "zos: lettura dell'atteso fallita"
  if ! cmp -s "$w/attese.s" "$w/trovate.s"; then
    err "occorrenze dei dati dei blocchi di controllo z/OS diverse da quelle attese (nome, riga):"
    diff "$w/attese.s" "$w/trovate.s" | sed 's/^/      /'
  fi
  fuori="$(awk -F"$TAB" '$2 > 261 && ($2 < 266 || $2 > 291) {printf "%s:%s ", $1, $2}' "$w/trovate.s")"
  [ -z "$fuori" ] || err "dati dei blocchi di controllo z/OS usati nella PROCEDURE DIVISION fuori dalle righe 266-291: $fuori"
  fine "$(wc -l < "$w/nomi.txt" | tr -d ' ') nomi, $(wc -l < "$w/trovate.s" | tr -d ' ') occorrenze: solo dichiarazioni (235-260) e righe 266-291"
  ;;
*) echo "uso: verifica-copie.sh copie OUT | tracciato OUT | zos SORGENTE" >&2; exit 2 ;;
esac
