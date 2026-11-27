#!/usr/bin/env bash
# Prova di ProLeap COBOL parser (seconda riserva per "grafi COPY e CALL"): provato perche' anche cobmix
# non conserva riga e sostituzioni. ProLeap non ha una riga di comando: si usa il suo preprocessore
# tramite una colla Java minima (docker/proleap/CopyLister.java) che stampa le istruzioni COPY.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
require_legacy
ensure_legacy_volume

build_image "$IMG_PROLEAP" "$DOCKER_DIR/proleap"
rm -rf "$OUT/proleap"
mkdir -p "$OUT/proleap"

printf 'proleap-cobol-parser 4.0.0 (pom), commit d1bfe75bdd6d480f70c74c6345bcc02610ac30d3, compilato dai sorgenti\n' > "$OUT/proleap/version.txt"
record proleap command.txt "per ogni programma P di app/cbl/ (elenco dal manifesto):
java -cp glue:proleap-classes:proleap-lib/* CopyLister /legacy/<P>      (in $IMG_PROLEAP)
CopyLister e' la colla in analysis/tools/docker/proleap/CopyLister.java: usa CobolLineReaderImpl e le altre classi di
normalizzazione delle righe di ProLeap, poi il parser del suo preprocessore (CobolPreprocessorParser) e stampa
riga, copybook e clausole REPLACING di ogni istruzione COPY. La ricerca dei copybook non e' coinvolta."

printf 'programma\triga\tcopybook\tsostituzioni\n' > "$OUT/proleap/copy.tsv"
while IFS= read -r rel; do
  prog="$(basename "$rel")"; prog="${prog%.*}"
  tool_run "$IMG_PROLEAP" "$OUT/proleap" -- "/legacy/$rel" | tail -n +2 | awk -F'\t' -v p="$prog" 'BEGIN{OFS="\t"} {print p, $1, $2, $3}' >> "$OUT/proleap/copy.tsv"
done < <(app_cbl_programs)
log "proleap: $(( $(wc -l < "$OUT/proleap/copy.tsv") - 1 )) istruzioni COPY elencate"
