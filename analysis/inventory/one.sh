#!/usr/bin/env bash
# Esegue uno strumento su UN file del legacy (chiamato da xargs in parallelo da lib.sh). Variabili esportate: LEGACY_VOL, g, IMG_*.
set -u
kind="$1"; f="$2"
name="$(echo "$f" | tr '/' '_')"
case "$kind" in
  proleap)
    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$LEGACY_VOL:/legacy:ro" "$IMG_PROLEAP" "/legacy/$f" \
      > "$g/tmp/proleap/$name.tsv" 2> "$g/tmp/proleap/$name.err" ;;
  mapa)
    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$LEGACY_VOL:/legacy:ro" -v "$g/tmp/procs:/procs:ro" \
      -v "$g/tmp/mapa:/out" -w /tmp "$IMG_MAPA" -file "/legacy/$f" -include /procs -outcsv "/out/$name.csv" \
      > "$g/tmp/mapa/$name.stdout" 2>&1 ;;
  *) echo "one.sh: tipo sconosciuto $kind" >&2; exit 2 ;;
esac
