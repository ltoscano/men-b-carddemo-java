# Funzioni del contratto dati (issue #3), da includere dopo lib/common.sh e tools/lib.sh.
#
# genera OUTDIR DOCDIR: rigenera dal legacy tutto cio' che questa analisi produce.
#   OUTDIR  riceve l'output grezzo e intermedio (cb2xml/, fonti/, tracciati.tsv, radici.tsv, discordanze-rilevate.tsv)
#   DOCDIR  riceve i documenti generati (contratti/, contratti.md, chiavi.tsv, chiavi.md, censimento.md)
# I file scritti a mano (censimento.tsv, relazioni.tsv, file.tsv, assegnazioni.tsv, discordanze.md e la parte
# iniziale di censimento.md) si leggono sempre da docs/legacy-map/data-contract/ (variabile DC_DOCS_IN).

DC_DIR="$ANALYSIS_ROOT/data-contract"
DC_DOCS="$REPO_ROOT/docs/legacy-map/data-contract"
DC_DOCS_IN="${DC_DOCS_IN:-$DC_DOCS}"

# Percorso, visto dai container della colla (analysis/ montata su /analysis), di una cartella sotto analysis/.
dc_cont() { echo "/analysis/${1#"$ANALYSIS_ROOT"/}"; }

# L'immagine di cb2xml e' quella del banco di prova (#1), condivisa: si usa cosi' com'e'. Si costruisce solo se manca
# (per esempio in un clone pulito in cui './analysis/run.sh tools' non e' ancora stato eseguito).
dc_cb2xml_image() {
  docker image inspect "$IMG_CB2XML" > /dev/null 2>&1 && return 0
  log "immagine $IMG_CB2XML assente: la costruisco dal Dockerfile del banco di prova"
  build_image "$IMG_CB2XML" "$DOCKER_DIR/cb2xml"
}

# Esegue cb2xml su ogni riga di LAVORI (id, sorgente, righe, input) in un solo container; scrive DEST/<id>.xml e DEST/<id>.log.
# Opzioni di rappresentazione identiche alla prova di #1: dialetto Mainframe, formato XML 2017.
dc_cb2xml() {
  local lavori="$1" frag="$2" dest="$3"
  mkdir -p "$dest"
  ensure_legacy_volume
  docker run --rm --name "menb-contract-cb2xml-$$-$RANDOM" --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$LEGACY_VOL:/legacy:ro" -v "$frag:/frag:ro" -v "$lavori:/lavori.tsv:ro" -v "$dest:/out" \
    --entrypoint sh "$IMG_CB2XML" -c '
      tail -n +2 /lavori.tsv | while IFS="	" read -r id sorgente righe input; do
        java -cp /opt/cb2xml/cb2xml.jar net.sf.cb2xml.Cb2Xml -cobol "$input" -xml "/out/$id.xml" -indentXml -Dialect Mainframe \
          > "/out/$id.log" 2>&1 || echo "cb2xml uscito con errore su $id" >> "/out/$id.log"
      done' || fail "esecuzione di cb2xml fallita"
}

genera() {
  local out="$1" doc="$2" w
  w="$(mktmp)"
  rm -rf "$out/cb2xml" "$out/fonti"
  mkdir -p "$out" "$doc"
  local docsm=(--mount "$DC_DOCS_IN:/docs:ro")
  # 1. frammenti dei programmi (righe dichiarate nel censimento) ed elenco degli input di cb2xml
  glue_run --rw "$w" "${docsm[@]}" -- /analysis/data-contract/glue/fonti.py frammenti /legacy /analysis/manifest/sources.tsv /docs/censimento.tsv /work \
    || fail "estrazione dei frammenti fallita"
  # 2. cb2xml su copybook e frammenti
  dc_cb2xml_image
  dc_cb2xml "$w/lavori.tsv" "$w/frag" "$out/cb2xml"
  cp "$w/lavori.tsv" "$out/cb2xml/lavori.tsv"
  # 3. estrazione testuale delle altre fonti (SELECT, FD, I/O, DEFINE, LISTCAT, voci)
  glue_run --rw "$out" "${docsm[@]}" -- /analysis/data-contract/glue/fonti.py estrai /legacy /analysis/manifest/sources.tsv /docs/censimento.tsv /work/fonti \
    || fail "estrazione testuale delle fonti fallita"
  # 4. contratti, chiavi e viste generate
  rm -rf "$doc/contratti"
  glue_run --mount "$out:/out" --rw "$doc" "${docsm[@]}" -- /analysis/data-contract/glue/contratti.py /out /docs /work \
    || fail "generazione dei contratti fallita"
  rm -rf "$w"
}
