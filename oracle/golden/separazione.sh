#!/bin/sh
# Eseguito DENTRO il container dell'oracle (issue #55). Controllo 5: lo scenario osservazione non compare tra i golden
# e ha la marcatura di osservazione.
#   - GENERATI/golden contiene esattamente le cartelle esempio e mirato, ognuna con MARCATURA che comincia con
#     "RIFERIMENTO DI PARITA'";
#   - GENERATI/osservazioni/osservazione esiste, la sua MARCATURA comincia con "OSSERVAZIONE", e sotto osservazioni/ non
#     c'e' alcun file *.riferimento.txt;
#   - nessun file dei golden e' identico a un file d'uscita dello scenario osservazione (OUTFILE, ARRYFILE, VBRCFILE,
#     rapporto.txt).
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0; 1 errore dello strumento; 4 violazione.
# Uso: separazione.sh GENERATI
set -u
die() { echo "separazione.sh: $*" >&2; exit 1; }
viola() { echo "separazione.sh: CONTROLLO 5 FALLITO: $*" >&2; exit 4; }
[ $# -eq 1 ] || die "uso: separazione.sh GENERATI"
g="$1"
[ -d "$g/golden" ] || viola "cartella dei golden assente"
el="$(ls -A "$g/golden")" || die "cartella dei golden non elencabile (ls)"
el="$(echo $el)"
[ "$el" = "esempio mirato" ] || viola "i golden sono '$el', attesi esattamente 'esempio mirato'"
for s in esempio mirato; do
  [ -f "$g/golden/$s/MARCATURA" ] || viola "golden/$s senza MARCATURA"
  m="$(sed -n '1p' "$g/golden/$s/MARCATURA")" || die "MARCATURA illeggibile (sed)"
  case "$m" in "RIFERIMENTO DI PARITA'"*) ;; *) viola "golden/$s: marcatura '$m'" ;; esac
done
o="$g/osservazioni/osservazione"
[ -f "$o/MARCATURA" ] || viola "scenario osservazione senza MARCATURA"
m="$(sed -n '1p' "$o/MARCATURA")" || die "MARCATURA illeggibile (sed)"
case "$m" in "OSSERVAZIONE"*) ;; *) viola "scenario osservazione: marcatura '$m'" ;; esac
rif="$(find "$g/osservazioni" -name '*.riferimento.txt')" || die "ricerca dei riferimenti fallita (find)"
[ -z "$rif" ] || viola "riferimenti tra le osservazioni: $rif"
for s in esempio mirato; do
  for f in "$g/golden/$s"/*; do
    for x in OUTFILE ARRYFILE VBRCFILE rapporto.txt; do
      r=0; cmp -s "$f" "$o/$x" || r=$?
      case "$r" in
        0) viola "$f e' identico a osservazioni/osservazione/$x" ;;
        1) ;;
        *) [ -f "$o/$x" ] || viola "osservazioni/osservazione/$x assente"; die "confronto non eseguito (cmp, codice $r)" ;;
      esac
    done
  done
done
echo "separazione: golden = esempio, mirato (marcati riferimento); osservazione marcata e fuori dai golden, senza riferimenti"
