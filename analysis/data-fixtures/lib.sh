# Funzioni delle fixture dai dati di esempio (issue #5), da includere dopo lib/common.sh e tools/lib.sh.
#
#   dfx_genera OUT [--confronta] [CARTELLA]
#       esegue glue/verifica.py: decodifica, verifica contro gli attesi a mano e ricalcolo degli elenchi; scrive le
#       fixture in OUT/out/, il documento in OUT/fixture.md e l'uscita della verifica in OUT/verifica.txt. Con
#       --confronta confronta anche le uscite con quelle versionate (CARTELLA/out/). CARTELLA (facoltativa, sotto
#       analysis/, default analysis/data-fixtures) contiene inventario, fisica, viste, attesi e out/: serve solo alle
#       prove negative di check.sh. Ogni uscita di una corsa precedente in OUT e' rimossa prima di cominciare: un
#       residuo non puo' far passare una corsa fallita.
#   dfx_esito FILE
#       stampa l'ultima riga di FILE se e' "verifica riuscita: ..."; ritorna 2 se FILE non si legge, 1 se l'esito
#       non e' quello.
#   dfx_negativi OUT_FILE
#       esegue le prove negative (glue/negativi.py) e ne scrive l'uscita in OUT_FILE.
# Il legacy si legge dal volume sensibile alle maiuscole (menb-analysis-legacy-<commit>), in sola lettura.
# Limite di tempo: allarme interno della colla (300 s la verifica, 900 s le prove negative), uscita 2 allo scadere.

DFX_DIR="$ANALYSIS_ROOT/data-fixtures"
DFX_DC="$REPO_ROOT/docs/legacy-map/data-contract"
DFX_DOC="$REPO_ROOT/docs/legacy-map/fixture.md"
DFX_LEGACY=/legvol

dfx_esito() {
  local ultima
  ultima="$(tail -n 1 "$1")" || return 2
  case "$ultima" in "verifica riuscita: "*) printf '%s\n' "$ultima" ;; *) return 1 ;; esac
}

dfx_genera() {
  local out="$1" opz="${2:-}" cartella="${3:-$DFX_DIR}" rc=0 c_cart extra=()
  case "$cartella" in "$ANALYSIS_ROOT"/*) ;; *) fail "la cartella delle fixture deve stare sotto analysis/" ;; esac
  c_cart="/analysis/${cartella#"$ANALYSIS_ROOT"/}"
  case "$opz" in --confronta) extra=(--confronta "$c_cart/out") ;; "") ;; *) fail "opzione sconosciuta: $opz" ;; esac
  mkdir -p "$out" || fail "cartella $out non creata"
  rm -rf "$out/out" "$out/fixture.md" "$out/verifica.txt" || fail "uscite precedenti in $out non rimosse"
  [ ! -e "$out/out" ] && [ ! -e "$out/fixture.md" ] && [ ! -e "$out/verifica.txt" ] || fail "uscite precedenti ancora presenti in $out"
  ensure_legacy_volume
  glue_run --rw "$out" --mount "$LEGACY_VOL:$DFX_LEGACY:ro" --mount "$DFX_DC:/dc:ro" -- \
    /analysis/data-fixtures/glue/verifica.py "$DFX_LEGACY" /dc /analysis/manifest/sources.tsv "$c_cart" \
    /work ${extra[@]+"${extra[@]}"} > "$out/verifica.txt" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -rf "$out/out" "$out/fixture.md"
    cat "$out/verifica.txt" >&2
    fail "verifica delle fixture fallita (uscita $rc)"
  fi
  rc=0; dfx_esito "$out/verifica.txt" > /dev/null || rc=$?
  case "$rc" in
    0) ;;
    1) cat "$out/verifica.txt" >&2; fail "verifica delle fixture senza esito riconoscibile" ;;
    *) fail "esito della verifica illeggibile (uscita $rc)" ;;
  esac
  [ -s "$out/fixture.md" ] && [ -d "$out/out" ] || fail "fixture o documento non scritti dalla verifica"
}

dfx_negativi() {
  local file="$1" rc=0
  ensure_legacy_volume
  glue_run --mount "$LEGACY_VOL:$DFX_LEGACY:ro" --mount "$DFX_DC:/dc:ro" -- \
    /analysis/data-fixtures/glue/negativi.py "$DFX_LEGACY" /dc /analysis/manifest/sources.tsv /analysis/data-fixtures \
    > "$file" 2>&1 || rc=$?
  return "$rc"
}
