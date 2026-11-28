#!/bin/sh
# Eseguito DENTRO il container dell'oracle da genera.sh (issue #55, giro 1 della PR #64: si verifica cio' che si
# pubblica). Il documento generato elenca ogni file dei golden con dimensione e SHA-256 (righe "| `<percorso>` | <byte> |
# `<sha256>` | ..."): qui, indipendentemente da documento.sh, ogni file di GENERATI deve comparire esattamente una volta
# con la sua dimensione e la sua impronta, e ogni riga dell'elenco deve corrispondere a un file esistente.
# Ogni comando ha l'esito controllato; nessuna pipeline. Uscite: 0; 1 errore dello strumento; 4 difformita'.
# Uso: impronte.sh DOCUMENTO GENERATI
set -u
die() { echo "impronte.sh: $*" >&2; [ -z "${lav:-}" ] || rm -rf "$lav"; exit 1; }
[ $# -eq 2 ] || die "uso: impronte.sh DOCUMENTO GENERATI"
doc="$1"; g="$2"; lav=""
[ -f "$doc" ] && [ -d "$g" ] || die "documento o cartella assenti"
lav="$(mktemp -d /tmp/issue55-impronte.XXXXXX)" || die "cartella temporanea non creata (mktemp)"
( cd "$g" && find . -type f > "$lav/elenco" ) || die "elenco dei file fallito (find)"
: > "$lav/reali" || die "file temporaneo non scrivibile"
while read -r f; do
  b="$(wc -c < "$g/$f")" || die "dimensione di $f non letta (wc)"
  b="${b#"${b%%[! ]*}"}"; b="${b%"${b##*[! ]}"}"
  case "$b" in ''|*[!0-9]*) die "dimensione non numerica: '$b'" ;; esac
  h="$(sha256sum < "$g/$f")" || die "impronta di $f non calcolata (sha256sum)"
  h="${h%% *}"
  case "$h" in *[!0-9a-f]*|'') die "impronta non valida: '$h'" ;; esac
  [ "${#h}" -eq 64 ] || die "impronta non valida: '$h'"
  echo "${f#./} $b $h" >> "$lav/reali" || die "elenco non scritto"
done < "$lav/elenco"
r=0
awk -v FR="$lav/reali" -v FD="$doc" '
  FILENAME == FR { R[$1] = $2 " " $3; nr++; next }
  FILENAME == FD && /^\| `[^`]+` \| [0-9]+ \| `[0-9a-f]+` \|/ {
    split($0, c, "|"); f = c[2]; gsub(/[ `]/, "", f); b = c[3]; gsub(/ /, "", b); h = c[4]; gsub(/[ `]/, "", h)
    if (f in VISTO) { print "file elencato due volte: " f; err++; next }
    VISTO[f] = 1; nd++
    if (!(f in R)) { print "file elencato ma assente: " f; err++; next }
    if (R[f] != b " " h) { print f ": nel documento " b " " h ", reale " R[f]; err++ } }
  END { for (f in R) if (!(f in VISTO)) { print "file non elencato nel documento: " f; err++ }
        if (nr == 0) { print "nessun file nei golden"; err++ }
        if (err) exit 4
        printf "impronte: %d file elencati nel documento con dimensione e SHA-256 reali\n", nd }' "$lav/reali" "$doc" > "$lav/esito" 2>&1 || r=$?
case "$r" in
  0) cat "$lav/esito" || die "esito non stampato (cat)" ;;
  4) cat "$lav/esito" >&2; rm -rf "$lav"; echo "impronte.sh: DOCUMENTO NON COERENTE con i golden" >&2; exit 4 ;;
  *) cat "$lav/esito" >&2; die "confronto non eseguito (awk, codice $r)" ;;
esac
rm -rf "$lav" || { echo "impronte.sh: temporanei non rimossi" >&2; exit 1; }
