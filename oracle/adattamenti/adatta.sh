#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/build/compile.sh (passo build). Genera le copie di
# compilazione di CBSTM03A con i due soli adattamenti ammessi (oracle/adattamenti/registro.md; voci 19
# e 21 del registro delle approvazioni). Il legacy non si tocca: si leggono gli originali e si scrivono
# copie nuove in una cartella che non deve esistere.
#
#   1. CUSTREC.cpy: ogni TAB diventa gli spazi che servono a raggiungere la tabulazione successiva, con
#      tabulazioni ogni LARGHEZZA_TAB colonne (4). Le righe senza TAB restano identiche byte per byte.
#   2. CBSTM03A.CBL: le righe non vuote dell'intervallo 266-291 (blocchi di controllo di z/OS) diventano
#      commenti: lo spazio in colonna 7 diventa '*'. Le righe vuote e tutte le altre restano identiche.
#
# Il controllo (oracle/adattamenti/verifica-copie.sh) riapplica la prima trasformazione con uno strumento
# diverso (expand di coreutils) e verifica la seconda byte per byte con un confronto riga per riga.
#
# Uso: adatta.sh RADICE-LEGACY CARTELLA-NUOVA
set -u
LARGHEZZA_TAB=4
die() { echo "adatta.sh: $*" >&2; exit 1; }
[ $# -eq 2 ] || die "uso: adatta.sh RADICE-LEGACY CARTELLA-NUOVA"
leg="$1"; dst="$2"
[ -f "$leg/app/cpy/CUSTREC.cpy" ] || die "originale assente: $leg/app/cpy/CUSTREC.cpy"
[ -f "$leg/app/cbl/CBSTM03A.CBL" ] || die "originale assente: $leg/app/cbl/CBSTM03A.CBL"
[ ! -e "$dst" ] || die "la cartella di destinazione esiste gia': $dst"
mkdir -p "$dst" || die "impossibile creare $dst"

# 1. Espansione dei TAB, colonna per colonna (la colonna conta da 0; un TAB porta al multiplo successivo).
awk -v W="$LARGHEZZA_TAB" '
  {
    out = ""; col = 0; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (c == "\t") { k = W - (col % W); out = out sprintf("%" k "s", ""); col += k }
      else { out = out c; col++ }
    }
    print out
  }' "$leg/app/cpy/CUSTREC.cpy" > "$dst/CUSTREC.cpy" || die "espansione dei TAB di CUSTREC.cpy fallita"

# 2. Righe 266-291: indicatore di commento in colonna 7, solo dove la colonna 7 e' uno spazio (le righe
#    vuote non corrispondono all'espressione e restano come sono).
sed '266,291s/^\(......\) /\1*/' "$leg/app/cbl/CBSTM03A.CBL" > "$dst/CBSTM03A.CBL" \
  || die "commento delle righe 266-291 di CBSTM03A.CBL fallito"

echo "adatta.sh: copie generate in $dst: CBSTM03A.CBL CUSTREC.cpy"
