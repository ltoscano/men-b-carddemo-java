#!/usr/bin/env bash
# Regressioni dei controlli di copertura (JaCoCo) e analisi statica (SpotBugs) di #27.
# Corsa di base verde di ./verify.sh, poi una mutazione isolata per caso, con ripristino anche
# su interruzione. Ogni alterazione di un rapporto o difetto di prova si rileva ATTRAVERSO
# ./verify.sh (non chiamando direttamente quality/RapportiQualita.java: cosi' si prova anche che
# il cancello lo invoca), per il motivo dichiarato: ogni caso controlla il codice di uscita e i
# messaggi attesi, e che nel log non ci siano marcatori di un fallimento per un'altra ragione
# (compilazione, download, limite di tempo). Si esegue a richiesta (non fa parte di ./verify.sh
# ne' della CI obbligatoria), da un albero di lavoro pulito: ./quality/regressioni-copertura.sh
#
# Casi:
#   base                       ./verify.sh senza mutazioni: deve riuscire e la sua corsa deve essere
#                              completa (ogni controllo eseguito, contato nel log); ne conserva
#                              rapporto aggregato, file di esecuzione di online e rapporto SpotBugs di batch
#   rapporto-*                 il rapporto aggregato JaCoCo, dopo il vero Maven: assente, troncato,
#                              di un'altra corsa, privo del gruppo di un modulo con classi, privo di
#                              una sola classe di un modulo che resta presente, mai prodotto (aggregato
#                              in skip in parity)
#   esecuzione-troncata        il file di esecuzione di un modulo troncato
#   agente-spento-<modulo>     agente JaCoCo spento in online, batch (codice eseguito) e in domain,
#                              loader (oggi senza righe di produzione): manca la prova dell'agente
#   agente-residuo-online      agente spento in online e, dopo Maven, il file di esecuzione sano di
#                              un'altra corsa rimesso al suo posto: non vale come prova
#   difetto-<modulo>           una classe con un difetto di SpotBugs alla soglia scelta, in ciascuno
#                              dei quattro moduli (quattro categorie diverse)
#   spotbugs-*                 rapporto SpotBugs assente, troncato, di un'altra corsa, privo di una classe
#   cancello-*                 SpotBugs in skip in un modulo (loader, batch), tolto dal POM padre; il
#                              controllo dei rapporti tolto da verify.sh: su codice sano Maven e lo
#                              script restano verdi, quindi il caso passa solo se la corsa di base
#                              (la verifica di completezza) si accorge che il controllo manca
#   controprova-lecita         una classe nuova senza difetti e con un test non fa fallire nulla
#
# Prerequisiti: bash, git, Docker. Variabili opzionali: MENB_BUILD_CACHE_VOLUME (passata a
# ./verify.sh), MENB_COPERTURA_TIMEOUT (secondi per ogni ./verify.sh, predefinito 1800),
# MENB_COPERTURA_SHORT_TIMEOUT (altri comandi esterni, predefinito 60), MENB_COPERTURA_LOGS
# (cartella esistente in cui conservare il log di ogni caso, <caso>.log).
# Esce con 0 solo se tutti i casi danno l'esito atteso e alla fine git status e' pulito.
set -euo pipefail

case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) SCRIPT_DIR="." ;;
esac
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)" || { echo "ERRORE: radice del repository non raggiungibile" >&2; exit 1; }
[ -f "${ROOT}/verify.sh" ] || { echo "ERRORE: ${ROOT}/verify.sh non trovato" >&2; exit 1; }
# shellcheck source=quality/limite.sh
. "${ROOT}/quality/limite.sh" || { echo "ERRORE: caricamento di quality/limite.sh fallito" >&2; exit 1; }
CASE_TIMEOUT="${MENB_COPERTURA_TIMEOUT:-1800}"
SHORT_TIMEOUT="${MENB_COPERTURA_SHORT_TIMEOUT:-60}"
check_seconds MENB_COPERTURA_TIMEOUT "${CASE_TIMEOUT}" || exit 1
check_seconds MENB_COPERTURA_SHORT_TIMEOUT "${SHORT_TIMEOUT}" || exit 1

CASI="${ROOT}/quality/regole/casi/java"
PKG_DIR="io/github/ltoscano/carddemo"
RAPPORTO_JACOCO="carddemo-parity/target/site/jacoco-aggregate/jacoco.xml"
REAL_DOCKER="$(command -v docker)" || { echo "ERRORE: docker non trovato sul PATH" >&2; exit 1; }
case "${REAL_DOCKER}" in
  /*) ;;
  *) echo "ERRORE: percorso di docker non assoluto: '${REAL_DOCKER}'" >&2; exit 1 ;;
esac

TMP_BASE="${TMPDIR:-/tmp}"
WORK="${TMP_BASE%/}/menb-copertura-$$-${RANDOM}${RANDOM}"
limited "${SHORT_TIMEOUT}" mkdir -m 700 "${WORK}" </dev/null || { echo "ERRORE: creazione di ${WORK} fallita" >&2; exit 1; }
LOG_DIR="${MENB_COPERTURA_LOGS:-${WORK}}"
RESULTS=()     # una riga per caso: nome|codice|esito|motivo
SAVED=()      # file salvati: indice -> percorso originale (copia in ${WORK}/bak/<indice>)
CREATED=()    # file creati dai casi, da rimuovere
RESTORE_FAILED=0
FAILED=""
CLEANUP_ARMED=0

# Ripristina i file salvati e rimuove quelli creati. Idempotente; ogni esito e' controllato.
ripristina() {
  local i f
  for ((i = ${#SAVED[@]} - 1; i >= 0; i--)); do
    f="${SAVED[i]}"
    if ! limited "${SHORT_TIMEOUT}" cp -p "${WORK}/bak/${i}" "${f}" </dev/null; then
      echo "ERRORE: ripristino di ${f} fallito" >&2
      RESTORE_FAILED=1
    fi
  done
  SAVED=()
  for f in ${CREATED[@]+"${CREATED[@]}"}; do
    if ! limited "${SHORT_TIMEOUT}" rm -f "${f}" </dev/null; then
      echo "ERRORE: rimozione di ${f} fallita" >&2
      RESTORE_FAILED=1
    fi
  done
  CREATED=()
  return 0
}

# Stato dell'albero: 0 pulito, 1 sporco, 2 git fallito.
git_clean() {
  if ! limited_out "${WORK}/git-status.out" "${SHORT_TIMEOUT}" git -C "${ROOT}" status --porcelain --untracked-files=all </dev/null; then
    echo "ERRORE: git status fallito" >&2
    return 2
  fi
  if [ -n "${LIMITED_OUT}" ]; then
    printf '%s\n' "${LIMITED_OUT}" >&2
    return 1
  fi
  return 0
}

on_exit() {
  local rc=$?
  trap - EXIT HUP INT TERM
  stop_limited
  if [ "${CLEANUP_ARMED}" -eq 1 ]; then
    echo "== ripristino"
    ripristina
    [ "${RESTORE_FAILED}" -eq 0 ] || [ "${rc}" -ne 0 ] || rc=1
    if ! git_clean; then
      echo "ERRORE: dopo il ripristino git status non e' pulito o non verificabile (vedi sopra)" >&2
      [ "${rc}" -ne 0 ] || rc=1
    else
      echo "== git status pulito"
    fi
  fi
  if ! limited "${SHORT_TIMEOUT}" rm -rf "${WORK}" </dev/null; then
    echo "ERRORE: cancellazione di ${WORK} fallita" >&2
    [ "${rc}" -ne 0 ] || rc=1
  fi
  if [ "${rc}" -eq 0 ]; then
    echo "== REGRESSIONI RIUSCITE: tutti i casi rilevati"
  else
    echo "== REGRESSIONI FALLITE (codice ${rc})" >&2
  fi
  exit "${rc}"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[ -d "${LOG_DIR}" ] || { echo "ERRORE: MENB_COPERTURA_LOGS non e' una cartella esistente: '${LOG_DIR}'" >&2; exit 1; }
limited "${SHORT_TIMEOUT}" mkdir "${WORK}/bak" </dev/null || { echo "ERRORE: creazione di ${WORK}/bak fallita" >&2; exit 1; }
if ! git_clean; then
  echo "ERRORE: l'albero di lavoro non e' pulito o git non risponde (vedi sopra): impossibile garantire il ripristino" >&2
  exit 1
fi
CLEANUP_ARMED=1

# ---- mutazioni sul working tree -----------------------------------------------------------

salva() { # file
  local n="${#SAVED[@]}"
  limited "${SHORT_TIMEOUT}" cp -p "$1" "${WORK}/bak/${n}" </dev/null || { echo "ERRORE: copia di $1 fallita" >&2; exit 1; }
  SAVED+=("$1")
}

# Sostituisce $1 con l'output del programma awk $2 (con argomenti ulteriori). Esito controllato.
awk_su() { # file programma [-v var=valore ...]
  local file="$1" prog="$2" out="${WORK}/awk.tmp"
  shift 2
  awk "$@" "${prog}" "${file}" > "${out}" || { echo "ERRORE: awk su ${file} fallito" >&2; exit 1; }
  limited "${SHORT_TIMEOUT}" cp "${out}" "${file}" </dev/null || { echo "ERRORE: scrittura di ${file} fallita" >&2; exit 1; }
}

# Dopo la prima riga di $2 che contiene il testo letterale $3 inserisce il testo $4. Verifica che
# la mutazione sia stata applicata.
mut_dopo() { # file-relativo ancora testo
  local f="${ROOT}/$1"
  salva "${f}"
  awk_su "${f}" '{ print } index($0, ancora) && !fatto { print testo; fatto = 1 }' -v "ancora=$2" -v "testo=$3"
  grep -qF -- "$3" "${f}" || { echo "ERRORE: mutazione non applicata a $1" >&2; exit 1; }
}

# Rimuove da $1 il blocco <plugin> con l'artifactId $2.
mut_senza_plugin() { # file-relativo artifactId
  local f="${ROOT}/$1" before after
  salva "${f}"
  before="$(grep -c "<artifactId>$2</artifactId>" "${f}")" || before=0
  awk_su "${f}" '$0 ~ "^[ \t]*<plugin>" { buf = $0; dentro = 1; next }
    dentro { buf = buf "\n" $0; if ($0 ~ "</plugin>") { dentro = 0; if (buf !~ "<artifactId>" art "</artifactId>") print buf }; next }
    { print }' -v "art=$2"
  after="$(grep -c "<artifactId>$2</artifactId>" "${f}")" || after=0
  [ "${after}" -lt "${before}" ] || { echo "ERRORE: blocco $2 non rimosso da $1" >&2; exit 1; }
}

# Sostituisce in verify.sh il testo letterale $1 con $2 (una sola volta), verificando l'effetto.
mut_verify() { # cercato sostituto
  local f="${ROOT}/verify.sh" before after
  salva "${f}"
  before="$(grep -cF -- "$1" "${f}")" || before=0
  [ "${before}" -ge 1 ] || { echo "ERRORE: '$1' non trovato in verify.sh: mutazione non applicabile" >&2; exit 1; }
  awk_su "${f}" 'BEGIN { n = length(cercato) } { i = index($0, cercato); if (i > 0 && !fatto) { $0 = substr($0, 1, i - 1) sostituto substr($0, i + n); fatto = 1 } print }' \
    -v "cercato=$1" -v "sostituto=$2"
  after="$(grep -cF -- "$1" "${f}")" || after=0
  [ "${after}" -lt "${before}" ] || { echo "ERRORE: mutazione di verify.sh non applicata" >&2; exit 1; }
}

# Copia nel modulo una classe di prova con il nome ProvaRegole (registrata per il ripristino
# PRIMA di scrivere: la redirezione crea il file anche se sed poi fallisce a meta').
aggiungi_classe() { # modulo file-caso nome-file-destinazione [src/main|src/test]
  local mod="$1" caso="$2" nome="$3" area="${4:-src/main}" pkg dest
  pkg="${mod#carddemo-}"
  dest="${ROOT}/${mod}/${area}/java/${PKG_DIR}/${pkg}/${nome}.java"
  [ ! -e "${dest}" ] || { echo "ERRORE: ${dest} esiste gia'" >&2; exit 1; }
  CREATED+=("${dest}")
  limited "${SHORT_TIMEOUT}" cp "${CASI}/${caso}.java" "${dest}" </dev/null || { echo "ERRORE: copia del caso ${caso} fallita" >&2; exit 1; }
  grep -q 'PROVA-REGOLE-27' "${dest}" || { echo "ERRORE: caso ${caso} non applicato" >&2; exit 1; }
}

# ---- esecuzione di ./verify.sh --------------------------------------------------------------

RUN_RC=0
RUN_SECONDS=0
RUN_LOG_FILE=""
RUN_LOG=""

# run_verify <caso> [PATH alternativo]: ./verify.sh con il limite di una build; output in
# ${LOG_DIR}/<caso>.log (riscritto a ogni corsa).
run_verify() {
  local name="$1" started log
  log="${LOG_DIR}/${name}.log"
  started="${SECONDS}"
  RUN_RC=0
  limited "${CASE_TIMEOUT}" env PATH="${2:-${PATH}}" "${ROOT}/verify.sh" </dev/null >"${log}" 2>&1 || RUN_RC=$?
  RUN_SECONDS=$((SECONDS - started))
  RUN_LOG_FILE="${log}"
  if ! RUN_LOG="$(<"${log}")"; then
    echo "ERRORE [${name}]: lettura del log ${log} fallita" >&2
    return 1
  fi
  return 0
}

show_tail() {
  local lines=() line i start
  while IFS= read -r line; do lines+=("${line}"); done <<EOF
${RUN_LOG}
EOF
  start=$(( ${#lines[@]} > 25 ? ${#lines[@]} - 25 : 0 ))
  for ((i = start; i < ${#lines[@]}; i++)); do printf '     | %s\n' "${lines[i]}"; done
  return 0
}

# Marcatori di un fallimento per una ragione diversa da quella dichiarata.
MOTIVI_ERRATI=("COMPILATION ERROR" "Could not resolve" "Could not transfer" "Non-resolvable" "Cannot access" "Unknown host" "superato il limite")

# expect <caso> <ko|ok> <messaggio atteso>...: decide su RUN_RC e RUN_LOG. Un caso ko deve
# uscire con un codice diverso da 0 (e non 124), mostrare ogni messaggio atteso e nessun marcatore
# di un'altra ragione.
expect() {
  local name="$1" want="$2" msg missing="" wrong="" m motivo
  shift 2
  motivo="$*"
  for msg in "$@"; do
    case "${RUN_LOG}" in
      *"${msg}"*) ;;
      *) missing="${missing} [${msg}]" ;;
    esac
  done
  for m in "${MOTIVI_ERRATI[@]}"; do
    case "${RUN_LOG}" in
      *"${m}"*) wrong="${wrong} [${m}]" ;;
    esac
  done
  local verdict="rilevato"
  if [ "${RUN_RC}" -eq 124 ]; then
    verdict="NON RILEVATO: superato il limite di ${CASE_TIMEOUT}s"
  elif [ "${want}" = "ok" ] && [ "${RUN_RC}" -ne 0 ]; then
    verdict="NON RIUSCITO: codice ${RUN_RC}, atteso 0"
  elif [ "${want}" = "ko" ] && [ "${RUN_RC}" -eq 0 ]; then
    verdict="NON RILEVATO: codice 0"
  elif [ -n "${missing}" ]; then
    verdict="MOTIVO NON QUELLO ATTESO: messaggi assenti:${missing}"
  elif [ -n "${wrong}" ]; then
    verdict="MOTIVO ERRATO: marcatori di un altro fallimento:${wrong}"
  elif [ "${want}" = "ok" ]; then
    verdict="riuscito"
  fi
  printf '== [%s] codice %s, %ss: %s\n' "${name}" "${RUN_RC}" "${RUN_SECONDS}" "${verdict}"
  RESULTS+=("${name}|${RUN_RC}|${verdict}|${motivo}")
  case "${verdict}" in
    rilevato | riuscito) ;;
    *)
      show_tail
      FAILED="${FAILED} ${name}"
      ;;
  esac
  return 0
}

# conta <log> <descrizione> <attese> <testo>: scrive su stdout la descrizione se il numero di
# occorrenze del testo non e' quello atteso.
conta() {
  local n
  n="$(grep -cF -- "$4" "$1")" || n=0
  if [ "${n}" -ne "$3" ]; then
    echo "controllo mancante o saltato: $2 (attese $3 occorrenze di '$4', trovate ${n})"
  fi
}

# Verifica di completezza di una corsa: ogni controllo e' stato eseguito, il numero atteso di
# volte. Stampa i controlli mancanti, uno per riga; nessun output = corsa completa.
completezza() { # log
  local l="$1"
  conta "${l}" "agente JaCoCo (padre + 5 moduli)" 6 "jacoco:0.8.16:prepare-agent (agente-copertura)"
  conta "${l}" "rapporto aggregato JaCoCo prodotto da parity" 1 "jacoco:0.8.16:report-aggregate (rapporto-aggregato) @ carddemo-parity"
  conta "${l}" "analisi SpotBugs eseguita (4 moduli)" 4 "--- spotbugs:4.10.5.0:check (analisi-difetti) @"
  conta "${l}" "SpotBugs senza difetti (4 moduli)" 4 "BugInstance size is 0"
  conta "${l}" "prova dell'agente verificata da verify.sh (5 moduli)" 5 ": agente attivo in questa corsa"
  conta "${l}" "rapporto aggregato verificato da verify.sh" 1 "classi di produzione eseguibili tutte presenti"
  conta "${l}" "rapporti SpotBugs verificati da verify.sh (4 moduli)" 4 "classi analizzate, 0 difetti, 0 errori di analisi"
  conta "${l}" "verifica completata" 1 "== verifica completata"
}

# ---- shim: alterazione dei rapporti dopo il vero Maven, dentro il container di build --------
# Lo shim di docker inoltra al vero docker e, nel solo "docker run", monta <cartella> in
# /menb-shim e mette /menb-shim/bin in testa al PATH del container: li' c'e' un mvn che esegue
# il vero Maven e poi lo script /menb-shim/mut.sh (la mutazione). Lo shim registra di aver
# applicato la mutazione; se il marcatore manca il caso fallisce invece di passare.

docker_shim_body() { # cartella-montata
  printf "real=%q\nshim=%q\n" "${REAL_DOCKER}" "$1"
  printf '%s\n' \
    'if [ "${1:-}" = run ]; then' \
    '  shift' \
    '  exec "${real}" run -v "${shim}:/menb-shim" \' \
    '    -e PATH=/menb-shim/bin:/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"' \
    'fi' \
    'exec "${real}" "$@"'
}

scrivi() { # file contenuto [eseguibile]
  printf '%s\n' "$2" >"$1" || { echo "ERRORE: scrittura di $1 fallita" >&2; exit 1; }
  if [ "${3:-}" = x ]; then
    limited "${SHORT_TIMEOUT}" chmod +x "$1" </dev/null || { echo "ERRORE: chmod di $1 fallito" >&2; exit 1; }
  fi
}

# Prologo di ogni mutazione: cambia <file> <espressione perl> modifica il file e fallisce se non
# cambia nulla (una mutazione che non altera il rapporto non dimostra niente).
PROLOGO_MUT='set -eu
R=carddemo-parity/target/site/jacoco-aggregate/jacoco.xml
cambia() {
  h="$(md5sum "$1")"
  perl -0777 -pi -e "$2" "$1"
  [ "$h" != "$(md5sum "$1")" ] || { echo "SHIM: nessuna modifica a $1" >&2; exit 95; }
}'

# caso_shim <caso> <corpo della mutazione> [file da mettere in /menb-shim ...]; poi expect_marker.
SHIM_DIR=""
caso_shim() {
  local nome="$1" corpo="$2" f
  shift 2
  SHIM_DIR="${WORK}/shim-${nome}"
  limited "${SHORT_TIMEOUT}" mkdir -p "${SHIM_DIR}/bin" "${WORK}/dk-${nome}" </dev/null || { echo "ERRORE: mkdir degli shim fallito" >&2; exit 1; }
  scrivi "${SHIM_DIR}/bin/mvn" '#!/usr/bin/env bash
/usr/share/maven/bin/mvn "$@" || exit $?
bash /menb-shim/mut.sh || { echo "SHIM: alterazione fallita" >&2; exit 96; }
: >/menb-shim/mvn-eseguito || exit 98' x
  scrivi "${SHIM_DIR}/mut.sh" "${PROLOGO_MUT}
${corpo}"
  for f in "$@"; do
    limited "${SHORT_TIMEOUT}" cp "${f}" "${SHIM_DIR}/" </dev/null || { echo "ERRORE: copia di ${f} nello shim fallita" >&2; exit 1; }
  done
  scrivi "${WORK}/dk-${nome}/docker" "#!/usr/bin/env bash
$(docker_shim_body "${SHIM_DIR}")" x
  run_verify "${nome}" "${WORK}/dk-${nome}:${PATH}" || exit 1
}

# Lo shim deve aver registrato la mutazione; altrimenti il caso non dimostra nulla.
marker_ok() { # caso
  if [ ! -e "${SHIM_DIR}/mvn-eseguito" ]; then
    echo "ERRORE [$1]: lo shim non ha applicato la mutazione (manca mvn-eseguito)" >&2
    FAILED="${FAILED} $1"
    return 1
  fi
  return 0
}

# Caso con mutazione di un rapporto: lo shim lo altera, ./verify.sh deve fallire nel controllo
# dei rapporti dopo un Maven riuscito.
caso_rapporto() { # caso corpo bersaglio(JaCoCo|SpotBugs) messaggio... (ultimi: file da copiare dopo "--")
  local nome="$1" corpo="$2" bersaglio="$3" msgs=() files=()
  shift 3
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do msgs+=("$1"); shift; done
  [ "$#" -eq 0 ] || shift
  files=("$@")
  caso_shim "${nome}" "${corpo}" ${files[@]+"${files[@]}"}
  if marker_ok "${nome}"; then
    if [ "${bersaglio}" = JaCoCo ]; then
      expect "${nome}" ko "BUILD SUCCESS" "${msgs[@]}" "ERRORE: rapporto di copertura JaCoCo non valido" "== VERIFICA FALLITA"
    else
      expect "${nome}" ko "BUILD SUCCESS" "${msgs[@]}" "ERRORE: rapporti SpotBugs non validi" "== VERIFICA FALLITA"
    fi
  fi
}

# ---- base -----------------------------------------------------------------------------------

echo "== [base] ./verify.sh senza mutazioni (limite ${CASE_TIMEOUT}s)"
run_verify base || exit 1
expect base ok "BUILD SUCCESS" "== verifica completata"
if [ -n "${FAILED}" ]; then
  echo "ERRORE: la corsa di base non riesce: i casi negativi non sarebbero significativi" >&2
  exit 1
fi
missing_base="$(completezza "${RUN_LOG_FILE}")"
if [ -n "${missing_base}" ]; then
  echo "ERRORE: la corsa di base non e' completa:" >&2
  echo "${missing_base}" >&2
  exit 1
fi
echo "== [base] corsa completa: ogni controllo eseguito il numero atteso di volte"
for f in "${RAPPORTO_JACOCO}" carddemo-online/target/jacoco.exec carddemo-batch/target/spotbugsXml.xml; do
  [ -f "${ROOT}/${f}" ] || { echo "ERRORE: ${f} assente dopo la corsa di base" >&2; exit 1; }
done
limited "${SHORT_TIMEOUT}" cp "${ROOT}/${RAPPORTO_JACOCO}" "${WORK}/jacoco-base.xml" </dev/null || { echo "ERRORE: copia del rapporto di base fallita" >&2; exit 1; }
limited "${SHORT_TIMEOUT}" cp "${ROOT}/carddemo-online/target/jacoco.exec" "${WORK}/online-base.exec" </dev/null || { echo "ERRORE: copia del file di esecuzione di base fallita" >&2; exit 1; }
limited "${SHORT_TIMEOUT}" cp "${ROOT}/carddemo-batch/target/spotbugsXml.xml" "${WORK}/batch-spotbugs-base.xml" </dev/null || { echo "ERRORE: copia del rapporto SpotBugs di base fallita" >&2; exit 1; }

# ---- 1. rapporto aggregato JaCoCo -----------------------------------------------------------

caso_rapporto rapporto-assente 'rm -f "$R"; [ ! -e "$R" ]' JaCoCo "rapporto JaCoCo assente:"
caso_rapporto rapporto-troncato 'cambia "$R" '"'"'$_ = substr($_, 0, int(length($_) / 2))'"'" JaCoCo \
  "rapporto JaCoCo" "non e' XML ben formato e completo"
caso_rapporto rapporto-altra-corsa 'cp /menb-shim/jacoco-base.xml "$R"; cmp -s /menb-shim/jacoco-base.xml "$R"' JaCoCo \
  "il rapporto JaCoCo non e' della corsa corrente" -- "${WORK}/jacoco-base.xml"
caso_rapporto rapporto-senza-modulo 'cambia "$R" '"'"'s{<group name="carddemo-online">.*?</group>}{<group name="carddemo-online"/>}s'"'" JaCoCo \
  "il modulo carddemo-online ha 1 classi eseguibili compilate ma manca dal rapporto JaCoCo"
caso_rapporto rapporto-senza-classe 'cambia "$R" '"'"'s{<class name="[^"]*/batch/InstallationCheckJobConfig".*?</class>}{}s'"'" JaCoCo \
  "classe io.github.ltoscano.carddemo.batch.InstallationCheckJobConfig di carddemo-batch assente dal rapporto JaCoCo"

# aggregato mai prodotto: esecuzione di parity in skip
mut_dopo carddemo-parity/pom.xml '<artifactId>jacoco-maven-plugin</artifactId>' '        <configuration><skip>true</skip></configuration>'
run_verify rapporto-aggregato-skip || exit 1
expect rapporto-aggregato-skip ko "BUILD SUCCESS" "rapporto JaCoCo assente:" "ERRORE: rapporto di copertura JaCoCo non valido" "== VERIFICA FALLITA"
ripristina

# file di esecuzione di un modulo troncato (a 60 byte: dentro il primo blocco di dati)
caso_shim esecuzione-troncata 'cambia carddemo-online/target/jacoco.exec '"'"'$_ = substr($_, 0, 60)'"'"
if marker_ok esecuzione-troncata; then
  expect esecuzione-troncata ko "BUILD SUCCESS" "file di esecuzione JaCoCo di carddemo-online non leggibile o troncato" \
    "ERRORE: rapporto di copertura JaCoCo non valido" "== VERIFICA FALLITA"
fi

# ---- 2. agente JaCoCo spento ----------------------------------------------------------------

agente_spento() { # modulo
  mut_dopo "carddemo-$1/pom.xml" '<plugins>' '      <plugin><groupId>org.jacoco</groupId><artifactId>jacoco-maven-plugin</artifactId><configuration><skip>true</skip></configuration></plugin>'
  run_verify "agente-spento-$1" || exit 1
  expect "agente-spento-$1" ko "BUILD SUCCESS" "agente JaCoCo non attivo in carddemo-$1: file di esecuzione assente" \
    "ERRORE: rapporto di copertura JaCoCo non valido" "== VERIFICA FALLITA"
  ripristina
}
agente_spento online
agente_spento batch
agente_spento domain
agente_spento loader

# agente spento in online, ma un file di esecuzione sano di un'altra corsa al suo posto
mut_dopo carddemo-online/pom.xml '<plugins>' '      <plugin><groupId>org.jacoco</groupId><artifactId>jacoco-maven-plugin</artifactId><configuration><skip>true</skip></configuration></plugin>'
caso_shim agente-residuo-online 'cp /menb-shim/online-base.exec carddemo-online/target/jacoco.exec; cmp -s /menb-shim/online-base.exec carddemo-online/target/jacoco.exec' "${WORK}/online-base.exec"
if marker_ok agente-residuo-online; then
  expect agente-residuo-online ko "BUILD SUCCESS" "agente JaCoCo di carddemo-online: sessione 'verify-" "non della corsa corrente" \
    "ERRORE: rapporto di copertura JaCoCo non valido" "== VERIFICA FALLITA"
fi
ripristina

# ---- 3. difetti alla soglia di SpotBugs, nei quattro moduli ------------------------------------

difetto() { # modulo file-caso categoria
  aggiungi_classe "carddemo-$1" "$2" ProvaRegole
  run_verify "difetto-$1" || exit 1
  expect "difetto-$1" ko "spotbugs-maven-plugin:4.10.5.0:check (analisi-difetti) on project carddemo-$1: failed with 1 bugs" \
    "$3" "ProvaRegole" "ERRORE: mvn verify fallito" "== VERIFICA FALLITA"
  ripristina
}
difetto domain spotbugs-domain NP_ALWAYS_NULL
difetto loader spotbugs-loader EC_UNRELATED_TYPES
difetto online spotbugs-online RV_RETURN_VALUE_IGNORED
difetto batch spotbugs-batch ES_COMPARING_PARAMETER_STRING_WITH_EQ

# ---- 4. rapporti SpotBugs alterati ----------------------------------------------------------

caso_rapporto spotbugs-assente 'rm -f carddemo-batch/target/spotbugsXml.xml; [ ! -e carddemo-batch/target/spotbugsXml.xml ]' SpotBugs \
  "rapporto SpotBugs assente per carddemo-batch"
caso_rapporto spotbugs-troncato 'cambia carddemo-online/target/spotbugsXml.xml '"'"'$_ = substr($_, 0, int(length($_) / 2))'"'" SpotBugs \
  "rapporto SpotBugs di carddemo-online non leggibile o non e' XML ben formato e completo"
caso_rapporto spotbugs-altra-corsa 'cp /menb-shim/batch-spotbugs-base.xml carddemo-batch/target/spotbugsXml.xml; cmp -s /menb-shim/batch-spotbugs-base.xml carddemo-batch/target/spotbugsXml.xml' SpotBugs \
  "il rapporto SpotBugs di carddemo-batch non e' di questa corsa" -- "${WORK}/batch-spotbugs-base.xml"
caso_rapporto spotbugs-senza-classe 'cambia carddemo-batch/target/spotbugsXml.xml "s{<ClassStats[^>]*class=\x27io[.]github[.]ltoscano[.]carddemo[.]batch[.]InstallationCheckJobConfig\x27[^>]*></ClassStats>}{}"' SpotBugs \
  "classe io.github.ltoscano.carddemo.batch.InstallationCheckJobConfig di carddemo-batch non analizzata da SpotBugs"

# ---- 4b. file di esclusioni di SpotBugs: ammesso solo con il motivo di ogni esclusione ------------

ESCL_FILE="quality/regole/spotbugs-esclusioni.xml"
configura_esclusioni() {
  mut_dopo pom.xml '<xmlOutput>true</xmlOutput>' '                <excludeFilterFile>${project.parent.basedir}/quality/regole/spotbugs-esclusioni.xml</excludeFilterFile>'
  CREATED+=("${ROOT}/${ESCL_FILE}")
}
# senza motivo: Maven resta verde, e' verify.sh a respingere il file
configura_esclusioni
scrivi "${ROOT}/${ESCL_FILE}" '<FindBugsFilter>
  <Match><Class name="io.github.ltoscano.carddemo.domain.ProvaRegole"/></Match>
</FindBugsFilter>'
run_verify esclusione-senza-motivo || exit 1
expect esclusione-senza-motivo ko "BUILD SUCCESS" "esclusione SpotBugs senza motivo in ${ESCL_FILE}" "ERRORE: rapporti SpotBugs non validi" "== VERIFICA FALLITA"
ripristina
# con motivo: l'esclusione e' applicata (il difetto di prova non fa fallire nulla) e verify.sh la riconosce
configura_esclusioni
scrivi "${ROOT}/${ESCL_FILE}" '<FindBugsFilter>
  <!-- prova di regressione: difetto volutamente escluso -->
  <Match><Class name="io.github.ltoscano.carddemo.domain.ProvaRegole"/></Match>
</FindBugsFilter>'
aggiungi_classe carddemo-domain spotbugs-domain ProvaRegole
run_verify esclusione-con-motivo || exit 1
expect esclusione-con-motivo ok "SpotBugs esclusioni: 1 in ${ESCL_FILE}, ciascuna con il motivo" "== verifica completata"
ripristina

# ---- 5. cancelli rimossi --------------------------------------------------------------------

# SpotBugs in skip in un modulo di produzione senza codice (loader) e in uno con codice (batch):
# verify.sh non trova il rapporto del modulo.
for modulo in loader batch; do
  mut_dopo "carddemo-${modulo}/pom.xml" '<artifactId>spotbugs-maven-plugin</artifactId>' '        <configuration><skip>true</skip></configuration>'
  run_verify "cancello-spotbugs-skip-${modulo}" || exit 1
  expect "cancello-spotbugs-skip-${modulo}" ko "BUILD SUCCESS" "rapporto SpotBugs assente per carddemo-${modulo}" \
    "ERRORE: rapporti SpotBugs non validi" "== VERIFICA FALLITA"
  ripristina
done

# SpotBugs tolto dal POM padre (pluginManagement): i moduli lo dichiarano senza versione ne'
# esecuzioni, quindi Maven resta verde senza analizzare nulla.
mut_senza_plugin pom.xml spotbugs-maven-plugin
run_verify cancello-spotbugs-padre-rimosso || exit 1
expect cancello-spotbugs-padre-rimosso ko "BUILD SUCCESS" "rapporto SpotBugs assente per carddemo-" \
  "ERRORE: rapporti SpotBugs non validi" "== VERIFICA FALLITA"
ripristina

# Controllo dei rapporti tolto da verify.sh: su codice sano Maven e lo script restano verdi
# (codice 0); passa solo se la verifica di completezza della corsa di base se ne accorge.
cancello_verify() { # caso cercato descrizione-mancante
  mut_verify "$2" "true"
  run_verify "$1" || exit 1
  local mancanti
  mancanti="$(completezza "${RUN_LOG_FILE}")"
  if [ "${RUN_RC}" -ne 0 ]; then
    printf '== [%s] codice %s: ERRORE: verify.sh doveva restare verde\n' "$1" "${RUN_RC}"
    show_tail
    FAILED="${FAILED} $1"
  elif [ -z "${mancanti}" ]; then
    printf '== [%s] codice 0: NON RILEVATO: controllo tolto ma la corsa di base e'"'"' ancora completa\n' "$1"
    FAILED="${FAILED} $1"
  else
    case "${mancanti}" in
      *"$3"*)
        printf '== [%s] codice 0, %ss: rilevato dalla verifica di completezza: %s\n' "$1" "${RUN_SECONDS}" "${mancanti//$'\n'/; }"
        RESULTS+=("$1|0|rilevato dalla completezza|${mancanti//$'\n'/; }")
        ;;
      *)
        printf '== [%s] MOTIVO NON QUELLO ATTESO: mancano altri controlli: %s\n' "$1" "${mancanti//$'\n'/; }"
        FAILED="${FAILED} $1"
        ;;
    esac
  fi
  ripristina
}
cancello_verify cancello-controllo-jacoco-rimosso 'java quality/RapportiQualita.java jacoco' "rapporto aggregato verificato da verify.sh"
cancello_verify cancello-controllo-spotbugs-rimosso 'java quality/RapportiQualita.java spotbugs' "rapporti SpotBugs verificati da verify.sh"

# ---- 6. controprova lecita ------------------------------------------------------------------

aggiungi_classe carddemo-domain controprova-classe ProvaCopertura
aggiungi_classe carddemo-domain controprova-test ProvaCoperturaTest src/test
run_verify controprova-lecita || exit 1
mancanti="$(completezza "${RUN_LOG_FILE}")"
if [ -n "${mancanti}" ]; then
  printf '== [controprova-lecita] controlli mancanti: %s\n' "${mancanti//$'\n'/; }"
  FAILED="${FAILED} controprova-lecita"
else
  expect controprova-lecita ok "JaCoCo carddemo-domain: 1 di 1 classi eseguibili presenti nel rapporto aggregato" \
    "SpotBugs carddemo-domain: 2 classi analizzate, 0 difetti" "== verifica completata"
fi
ripristina

echo
echo "== riepilogo (caso | codice di uscita di ./verify.sh | esito | motivo atteso)"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r n c e m <<<"${r}"
  printf '%-40s %-4s %-28s %s\n' "${n}" "${c}" "${e}" "${m}"
done
if [ -n "${FAILED}" ]; then
  echo "ERRORE: casi non rilevati:${FAILED}" >&2
  exit 1
fi
