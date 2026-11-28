# Funzioni dell'analisi oracle-dati (issue #53), da includere dopo lib/common.sh e tools/lib.sh.
#
#   odt_genera OUT [CARTELLA [LIMITE]]
#       esegue glue/esegui.py (controllo 1, generazione, controlli 2, 4, 5 sui file scritti) e poi controprova.sh
#       (controllo 3); scrive OUT/out/<dd>.rec e <dd>.elenco.tsv, OUT/oracle-dati.md, OUT/verifica.txt e
#       OUT/controprova.txt. Ogni uscita di una corsa precedente in OUT e' rimossa PRIMA di cominciare e, se un controllo
#       fallisce, anche le uscite della corsa corrente: un residuo non puo' far passare una corsa fallita. CARTELLA
#       (facoltativa, sotto analysis/, default analysis/oracle-dati) contiene tabella.tsv e attesi/: serve solo alle
#       prove negative di check.sh, come LIMITE (secondi, passato a esegui.py come --limite: prova del limite di tempo).
#   odt_controprova OUT_DIR CARTELLA [opzioni docker...]
#       controllo 3 (controprova.sh) sui file di OUT_DIR, in un container dell'immagine di base della colla, con le
#       sole utility POSIX; le opzioni docker in piu' servono solo alle prove sugli esiti. Uscita di controprova.sh.
#   odt_ultima FILE PREFISSO
#       stampa l'ultima riga di FILE se comincia con PREFISSO; 1 se non comincia cosi', 2 se FILE non si legge.
#   odt_negativi OUT_FILE [LIMITE]
#       prove negative della colla (glue/negativi.py), uscita in OUT_FILE; restituisce l'uscita di negativi.py.
# Il legacy si legge dal volume sensibile alle maiuscole (menb-analysis-legacy-<commit>), in sola lettura.
# Limiti di tempo: allarme interno della colla (300 s esegui.py, 900 s negativi.py, uscita 2) e `timeout` di 120 s
# intorno a controprova.sh nel container (uscita 124).

ODT_DIR="$ANALYSIS_ROOT/oracle-dati"
ODT_DC="$REPO_ROOT/docs/legacy-map/data-contract"
ODT_DOC="$REPO_ROOT/docs/legacy-map/oracle-dati.md"
ODT_LEGACY=/legvol
# Limite di tempo di controprova.sh nel container: 120 s. ODT_TIMEOUT_CONTROPROVA, letta a ogni chiamata, lo riduce:
# solo per la prova negativa del limite di tempo in check.sh.

odt_ultima() {
  local ultima
  ultima="$(tail -n 1 "$1")" || return 2
  case "$ultima" in "$2"*) printf '%s\n' "$ultima" ;; *) return 1 ;; esac
}

odt_cartella_c() { # percorso nel container di una cartella sotto analysis/
  case "$1" in "$ANALYSIS_ROOT"/*) printf '/analysis/%s\n' "${1#"$ANALYSIS_ROOT"/}" ;; *) return 1 ;; esac
}

odt_controprova() {
  local out="$1" cart="$2" c_cart uid gid
  shift 2
  c_cart="$(odt_cartella_c "$cart")" || { echo "odt_controprova: la cartella deve stare sotto analysis/" >&2; return 2; }
  uid="$(id -u)" && gid="$(id -g)" || { echo "odt_controprova: id fallito" >&2; return 2; }
  ensure_legacy_volume
  docker run --rm --network none --user "$uid:$gid" \
    -v "$ANALYSIS_ROOT:/analysis:ro" -v "$LEGACY_VOL:$ODT_LEGACY:ro" -v "$out:/prod:ro" "$@" "$GLUE_IMAGE" \
    timeout -k 10 "${ODT_TIMEOUT_CONTROPROVA:-120}" sh /analysis/oracle-dati/controprova.sh "$ODT_LEGACY" "$c_cart/tabella.tsv" "$c_cart/attesi" /prod \
    < /dev/null
}

odt_genera() {
  local out="$1" cartella="${2:-$ODT_DIR}" rc=0 c_cart extra=()
  [ -z "${3:-}" ] || extra=(--limite "$3")
  c_cart="$(odt_cartella_c "$cartella")" || fail "la cartella dell'analisi deve stare sotto analysis/"
  mkdir -p "$out" || fail "cartella $out non creata"
  rm -rf "$out/out" "$out/oracle-dati.md" "$out/verifica.txt" "$out/controprova.txt" || fail "uscite precedenti in $out non rimosse"
  [ ! -e "$out/out" ] && [ ! -e "$out/oracle-dati.md" ] && [ ! -e "$out/verifica.txt" ] && [ ! -e "$out/controprova.txt" ] \
    || fail "uscite precedenti ancora presenti in $out"
  ensure_legacy_volume
  glue_run --rw "$out" --mount "$LEGACY_VOL:$ODT_LEGACY:ro" --mount "$ODT_DC:/dc:ro" -- \
    /analysis/oracle-dati/glue/esegui.py "$ODT_LEGACY" /dc /analysis/data-fixtures/out "$c_cart" /work \
    ${extra[@]+"${extra[@]}"} > "$out/verifica.txt" 2>&1 < /dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -rf "$out/out" "$out/oracle-dati.md"
    cat "$out/verifica.txt" >&2
    fail "generazione o verifica dei record fallita (uscita $rc)"
  fi
  rc=0; odt_ultima "$out/verifica.txt" "verifica riuscita: " > /dev/null || rc=$?
  case "$rc" in
    0) ;;
    1) rm -rf "$out/out" "$out/oracle-dati.md"; cat "$out/verifica.txt" >&2; fail "verifica senza esito riconoscibile" ;;
    *) rm -rf "$out/out" "$out/oracle-dati.md"; fail "esito della verifica illeggibile (uscita $rc)" ;;
  esac
  [ -s "$out/oracle-dati.md" ] && [ -d "$out/out" ] || fail "record o documento non scritti dalla verifica"
  rc=0; odt_controprova "$out/out" "$cartella" > "$out/controprova.txt" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -rf "$out/out" "$out/oracle-dati.md"
    cat "$out/controprova.txt" >&2
    fail "controprova con il file ASCII fallita (uscita $rc)"
  fi
  rc=0; odt_ultima "$out/controprova.txt" "controprova riuscita: " > /dev/null || rc=$?
  case "$rc" in
    0) ;;
    1) rm -rf "$out/out" "$out/oracle-dati.md"; cat "$out/controprova.txt" >&2; fail "controprova senza esito riconoscibile" ;;
    *) rm -rf "$out/out" "$out/oracle-dati.md"; fail "esito della controprova illeggibile (uscita $rc)" ;;
  esac
}

odt_negativi() {
  local file="$1" rc=0 extra=()
  [ -z "${2:-}" ] || extra=(--limite "$2")
  ensure_legacy_volume
  glue_run --mount "$LEGACY_VOL:$ODT_LEGACY:ro" --mount "$ODT_DC:/dc:ro" -- \
    /analysis/oracle-dati/glue/negativi.py "$ODT_LEGACY" /dc /analysis/data-fixtures/out /analysis/oracle-dati \
    ${extra[@]+"${extra[@]}"} > "$file" 2>&1 < /dev/null || rc=$?
  return "$rc"
}
