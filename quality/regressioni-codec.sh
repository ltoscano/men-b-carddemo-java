#!/usr/bin/env bash
# Regressioni del codec dei campi (#54): prove negative del test dei vettori, dei controlli
# esaustivi, dell'ispezione del bytecode e del controllo del rapporto in ./verify.sh.
# Corsa di base verde di ./verify.sh, poi una mutazione isolata per caso, con ripristino anche su
# interruzione; ogni caso deve far fallire ./verify.sh per il motivo dichiarato (codice di uscita
# diverso da 0 e da 124, messaggi attesi presenti, nessun marcatore di un fallimento per un'altra
# ragione: compilazione, download, limite di tempo). Modello: quality/regressioni-copertura.sh.
#
# Le mutazioni del file dei vettori NON toccano analysis/ nel working tree: uno shim di docker
# aggiunge al solo "docker run" di ./verify.sh un montaggio che sostituisce il file con una vista
# temporanea (o la cartella con una vuota). Lo shim registra di essere intervenuto; senza il
# marcatore il caso fallisce.
#
# Casi:
#   segno-scambiato            due righe della tabella del segno scambiate (A e B)
#   binario-ordine             ordine dei byte del binario invertito in lettura
#   packed-segno               codice di segno D del COMP-3 letto come positivo
#   scala-spostata             valore DISPLAY con la scala spostata di uno
#   non-valido-zero            un DISPLAY non valido convertito in zero
#   oltre-picture-valore       un binario oltre la PICTURE riceve il valore intero
#   zero-negativo-normalizzato la ricodifica conservativa riscrive '}' come '{'
#   vettori-irraggiungibili    cartella dei vettori vuota nel container: il test fallisce, non salta
#   vettore-tolto              un vettore tolto dalla vista senza aggiornare il numero atteso
#   segno-iniziale             '+' iniziale accettato in un DISPLAY senza segno (lo vedono gli esaustivi)
#   offset-zero                lettura sempre dall'offset zero
#   scala-sbagliata            binario valido con valore uguale e scala diversa
#   passaggio-double           una conversione che passa per Math.pow (double), invisibile alle regole sul testo
#   vettori-saltati            proprieta' menb.verify.run tolta da mvn in verify.sh: test saltato, il controllo
#                              del rapporto fallisce
#   rapporto-residuo           dopo il vero Maven il rapporto e' sostituito da quello sano della corsa di base
#   rapporto-assente           dopo il vero Maven il rapporto e' cancellato
#
# Uso: ./quality/regressioni-codec.sh [<caso> ...] (la corsa di base gira sempre);
# ./quality/regressioni-codec.sh --lista stampa i casi. Prerequisiti: bash, git, Docker, perl.
# Variabili opzionali: MENB_CODEC_TIMEOUT (secondi per ogni ./verify.sh, predefinito 1800),
# MENB_CODEC_SHORT_TIMEOUT (altri comandi, predefinito 60), MENB_CODEC_LOGS (cartella esistente in
# cui conservare il log di ogni caso). Esce con 0 solo se tutti i casi danno l'esito atteso e alla
# fine git status e' pulito.
set -euo pipefail

case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) SCRIPT_DIR="." ;;
esac
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)" || { echo "ERRORE: radice del repository non raggiungibile" >&2; exit 1; }
[ -f "${ROOT}/verify.sh" ] || { echo "ERRORE: ${ROOT}/verify.sh non trovato" >&2; exit 1; }
# shellcheck source=quality/limite.sh
. "${ROOT}/quality/limite.sh" || { echo "ERRORE: caricamento di quality/limite.sh fallito" >&2; exit 1; }
CASE_TIMEOUT="${MENB_CODEC_TIMEOUT:-1800}"
SHORT_TIMEOUT="${MENB_CODEC_SHORT_TIMEOUT:-60}"
check_seconds MENB_CODEC_TIMEOUT "${CASE_TIMEOUT}" || exit 1
check_seconds MENB_CODEC_SHORT_TIMEOUT "${SHORT_TIMEOUT}" || exit 1

T0="${SECONDS}"
LISTA=""
SEL=("$@")
USATI=()
if [ "${#SEL[@]}" -eq 1 ] && [ "${SEL[0]}" = "--lista" ]; then
  LISTA=1
  SEL=()
fi
case "${SEL[*]-}" in
  *--*) echo "ERRORE: opzione sconosciuta in '${SEL[*]}' (solo --lista, da sola, oppure nomi di casi)" >&2; exit 1 ;;
esac
selezionato() {
  local n="$1" r
  if [ -n "${LISTA}" ]; then
    echo "${n}"
    return 1
  fi
  [ "${#SEL[@]}" -ne 0 ] || return 0
  for r in "${SEL[@]}"; do
    if [ "${r}" = "${n}" ]; then
      USATI+=("${n}")
      return 0
    fi
  done
  return 1
}

PKG="carddemo-domain/src/main/java/io/github/ltoscano/carddemo/domain"
CODEC="${PKG}/GnuCobolFieldCodec.java"
VETTORI_IN_CONTAINER="/workspace/analysis/data-codec/vettori"
REPORT="carddemo-domain/target/surefire-reports/TEST-io.github.ltoscano.carddemo.domain.OracleGnuCobolVectorsTest.xml"
FALLITO_VETTORI="<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.OracleGnuCobolVectorsTest"
REAL_DOCKER="$(command -v docker)" || { echo "ERRORE: docker non trovato sul PATH" >&2; exit 1; }
case "${REAL_DOCKER}" in
  /*) ;;
  *) echo "ERRORE: percorso di docker non assoluto: '${REAL_DOCKER}'" >&2; exit 1 ;;
esac

TMP_BASE="${TMPDIR:-/tmp}"
WORK="${TMP_BASE%/}/menb-codec-$$-${RANDOM}${RANDOM}"
limited "${SHORT_TIMEOUT}" mkdir -m 700 "${WORK}" </dev/null || { echo "ERRORE: creazione di ${WORK} fallita" >&2; exit 1; }
LOG_DIR="${MENB_CODEC_LOGS:-${WORK}}"
RESULTS=()
SAVED=()
RESTORE_FAILED=0
FAILED=""
CLEANUP_ARMED=0

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
  return 0
}

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
    [ -n "${LISTA}" ] || echo "== REGRESSIONI RIUSCITE: tutti i casi rilevati"
  else
    echo "== REGRESSIONI FALLITE (codice ${rc})" >&2
  fi
  exit "${rc}"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[ -d "${LOG_DIR}" ] || { echo "ERRORE: MENB_CODEC_LOGS non e' una cartella esistente: '${LOG_DIR}'" >&2; exit 1; }
limited "${SHORT_TIMEOUT}" mkdir "${WORK}/bak" </dev/null || { echo "ERRORE: creazione di ${WORK}/bak fallita" >&2; exit 1; }
if [ -z "${LISTA}" ]; then
  if ! git_clean; then
    echo "ERRORE: l'albero di lavoro non e' pulito o git non risponde (vedi sopra): impossibile garantire il ripristino" >&2
    exit 1
  fi
  CLEANUP_ARMED=1
fi

# ---- mutazioni -------------------------------------------------------------------------------

salva() { # file
  local n="${#SAVED[@]}"
  limited "${SHORT_TIMEOUT}" cp -p "$1" "${WORK}/bak/${n}" </dev/null || { echo "ERRORE: copia di $1 fallita" >&2; exit 1; }
  SAVED+=("$1")
}

# muta <file-relativo> <cercato> <sostituto>: sostituisce la prima occorrenza letterale; fallisce se
# il testo non c'e' o se il file non cambia (una mutazione che non altera nulla non dimostra niente).
muta() {
  local f="${ROOT}/$1"
  [ -f "${f}" ] || { echo "ERRORE: $1 non trovato" >&2; exit 1; }
  grep -qF -- "$2" "${f}" || { echo "ERRORE: '$2' non trovato in $1: mutazione non applicabile" >&2; exit 1; }
  salva "${f}"
  CERCATO="$2" SOSTITUTO="$3" perl -0777 -pi -e 'my $c = $ENV{CERCATO}; my $s = $ENV{SOSTITUTO}; my $i = index($_, $c); substr($_, $i, length($c)) = $s if $i >= 0;' "${f}" \
    || { echo "ERRORE: perl su $1 fallito" >&2; exit 1; }
  if cmp -s "${f}" "${WORK}/bak/$((${#SAVED[@]} - 1))"; then
    echo "ERRORE: mutazione di $1 non applicata" >&2
    exit 1
  fi
}

# ---- esecuzione di ./verify.sh --------------------------------------------------------------

RUN_RC=0
RUN_SECONDS=0
RUN_LOG=""
run_verify() { # caso [PATH alternativo]
  local name="$1" started log
  log="${LOG_DIR}/${name}.log"
  started="${SECONDS}"
  RUN_RC=0
  limited "${CASE_TIMEOUT}" env PATH="${2:-${PATH}}" "${ROOT}/verify.sh" </dev/null >"${log}" 2>&1 || RUN_RC=$?
  RUN_SECONDS=$((SECONDS - started))
  if ! RUN_LOG="$(<"${log}")"; then
    echo "ERRORE [${name}]: lettura del log ${log} fallita" >&2
    exit 1
  fi
}

MOTIVI_ERRATI=("COMPILATION ERROR" "Could not resolve" "Could not transfer" "Non-resolvable" "Cannot access" "Unknown host" "superato il limite" "SHIM:")

# expect <caso> <ko|ok> <messaggio atteso>...
expect() {
  local name="$1" want="$2" msg missing="" wrong="" m verdict
  shift 2
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
  verdict="rilevato"
  if [ "${RUN_RC}" -eq 124 ]; then
    verdict="NON RILEVATO: superato il limite di ${CASE_TIMEOUT}s"
  elif [ "${want}" = ok ] && [ "${RUN_RC}" -ne 0 ]; then
    verdict="NON RIUSCITO: codice ${RUN_RC}, atteso 0"
  elif [ "${want}" = ko ] && [ "${RUN_RC}" -eq 0 ]; then
    verdict="NON RILEVATO: codice 0"
  elif [ -n "${missing}" ]; then
    verdict="MOTIVO NON QUELLO ATTESO: messaggi assenti:${missing}"
  elif [ -n "${wrong}" ]; then
    verdict="MOTIVO ERRATO: marcatori di un altro fallimento:${wrong}"
  elif [ "${want}" = ok ]; then
    verdict="riuscito"
  fi
  printf '== [%s] codice %s, %ss: %s\n' "${name}" "${RUN_RC}" "${RUN_SECONDS}" "${verdict}"
  RESULTS+=("${name}|${RUN_RC}|${verdict}|$*")
  case "${verdict}" in
    rilevato | riuscito) ;;
    *)
      printf '%s\n' "${RUN_LOG}" | tail -n 25 | sed 's/^/     | /'
      FAILED="${FAILED} ${name}"
      ;;
  esac
  return 0
}

# caso_java <caso> <file> <cercato> <sostituto> <messaggio atteso>...: mutazione del sorgente.
caso_java() {
  selezionato "$1" || return 0
  local name="$1" file="$2" cercato="$3" sostituto="$4"
  shift 4
  muta "${file}" "${cercato}" "${sostituto}"
  run_verify "${name}"
  expect "${name}" ko "$@" "ERRORE: mvn verify fallito" "== VERIFICA FALLITA"
  ripristina
}

# ---- shim di docker -------------------------------------------------------------------------
# shim <caso> <argomento di docker run>...: scrive ${WORK}/dk-<caso>/docker, che inoltra al vero
# docker e, nel solo "docker run", aggiunge gli argomenti dati e crea il marcatore "applicato".
SHIM_DIR=""
shim() {
  local name="$1" a
  shift
  SHIM_DIR="${WORK}/dk-${name}"
  limited "${SHORT_TIMEOUT}" mkdir -p "${SHIM_DIR}" </dev/null || { echo "ERRORE: mkdir di ${SHIM_DIR} fallito" >&2; exit 1; }
  {
    printf '#!/usr/bin/env bash\nreal=%q\nmarker=%q\n' "${REAL_DOCKER}" "${SHIM_DIR}/applicato"
    printf 'if [ "${1:-}" = run ]; then\n  shift\n  : >"${marker}" || exit 97\n  exec "${real}" run'
    for a in "$@"; do printf ' %q' "${a}"; done
    printf ' "$@"\nfi\nexec "${real}" "$@"\n'
  } >"${SHIM_DIR}/docker" || { echo "ERRORE: scrittura dello shim fallita" >&2; exit 1; }
  limited "${SHORT_TIMEOUT}" chmod +x "${SHIM_DIR}/docker" </dev/null || { echo "ERRORE: chmod dello shim fallito" >&2; exit 1; }
}

marker_ok() { # caso file-marcatore
  if [ ! -e "$2" ]; then
    echo "ERRORE [$1]: lo shim non ha applicato la mutazione (manca ${2##*/})" >&2
    FAILED="${FAILED} $1"
    return 1
  fi
  return 0
}

# caso_vista <caso> <file vista> <messaggio atteso>...: la vista sostituisce oracle-gnucobol.tsv.
caso_vista() {
  local name="$1" vista="$2"
  shift 2
  shim "${name}" -v "${vista}:${VETTORI_IN_CONTAINER}/oracle-gnucobol.tsv:ro"
  run_verify "${name}" "${SHIM_DIR}:${PATH}"
  marker_ok "${name}" "${SHIM_DIR}/applicato" || return 0
  expect "${name}" ko "$@" "ERRORE: mvn verify fallito" "== VERIFICA FALLITA"
}

# caso_rapporto <caso> <comandi bash della mutazione> <messaggio atteso>...: dopo il vero "mvn
# verify", dentro il container, uno script altera il rapporto del test dei vettori.
caso_rapporto() {
  local name="$1" corpo="$2" dir
  shift 2
  dir="${WORK}/mvn-${name}"
  limited "${SHORT_TIMEOUT}" mkdir -p "${dir}/bin" </dev/null || { echo "ERRORE: mkdir di ${dir} fallito" >&2; exit 1; }
  printf '%s\n' '#!/usr/bin/env bash' \
    '/usr/share/maven/bin/mvn "$@" || exit $?' \
    'case " $* " in *" verify "*) ;; *) exit 0 ;; esac' \
    'bash /menb-shim/mut.sh || { echo "SHIM: alterazione fallita" >&2; exit 96; }' \
    ': >/menb-shim/mvn-eseguito || exit 98' >"${dir}/bin/mvn" || { echo "ERRORE: scrittura di mvn fallita" >&2; exit 1; }
  printf 'set -eu\nR=%q\n%s\n' "${REPORT}" "${corpo}" >"${dir}/mut.sh" || { echo "ERRORE: scrittura di mut.sh fallita" >&2; exit 1; }
  limited "${SHORT_TIMEOUT}" chmod +x "${dir}/bin/mvn" </dev/null || { echo "ERRORE: chmod di mvn fallito" >&2; exit 1; }
  if [ -f "${WORK}/rapporto-base.xml" ]; then
    limited "${SHORT_TIMEOUT}" cp "${WORK}/rapporto-base.xml" "${dir}/base.xml" </dev/null || { echo "ERRORE: copia del rapporto di base fallita" >&2; exit 1; }
  fi
  shim "${name}" -v "${dir}:/menb-shim" \
    -e PATH=/menb-shim/bin:/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  run_verify "${name}" "${SHIM_DIR}:${PATH}"
  marker_ok "${name}" "${SHIM_DIR}/applicato" || return 0
  marker_ok "${name}" "${dir}/mvn-eseguito" || return 0
  expect "${name}" ko "BUILD SUCCESS" "$@" "ERRORE: rapporto del test dei vettori" "== VERIFICA FALLITA"
}

# ---- base -----------------------------------------------------------------------------------

if [ -z "${LISTA}" ]; then
  echo "== [base] ./verify.sh senza mutazioni (limite ${CASE_TIMEOUT}s)"
  run_verify base
  expect base ok "BUILD SUCCESS" \
    "io.github.ltoscano.carddemo.domain.OracleGnuCobolVectorsTest: eseguiti e riusciti oracleGnuCobolVectors=375 beyondPictureObservations=10" \
    "Tests run: 385, Failures: 0, Errors: 0, Skipped: 0, Time elapsed" \
    "Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: " \
    "== verifica completata"
  if [ -n "${FAILED}" ]; then
    echo "ERRORE: la corsa di base non riesce: i casi negativi non sarebbero significativi" >&2
    exit 1
  fi
  [ -f "${ROOT}/${REPORT}" ] || { echo "ERRORE: ${REPORT} assente dopo la corsa di base" >&2; exit 1; }
  limited "${SHORT_TIMEOUT}" cp "${ROOT}/${REPORT}" "${WORK}/rapporto-base.xml" </dev/null || { echo "ERRORE: copia del rapporto di base fallita" >&2; exit 1; }
fi

# ---- mutazioni del codec --------------------------------------------------------------------

caso_java segno-scambiato "${CODEC}" "0x7B, 0x41, 0x42," "0x7B, 0x42, 0x41," "${FALLITO_VETTORI}"
caso_java binario-ordine "${CODEC}" \
  "BigInteger n = picture.signed() ? new BigInteger(bytes) : new BigInteger(1, bytes);" \
  "byte[] inv = new byte[bytes.length]; for (int k = 0; k < bytes.length; k++) { inv[k] = bytes[bytes.length - 1 - k]; } BigInteger n = picture.signed() ? new BigInteger(inv) : new BigInteger(1, inv);" \
  "${FALLITO_VETTORI}"
caso_java packed-segno "${CODEC}" "negative = true;" "negative = false;" "${FALLITO_VETTORI}"
caso_java scala-spostata "${CODEC}" \
  "return DecodedField.validNumber(new BigDecimal(negative ? n.negate() : n, picture.scale()), bytes);" \
  "return DecodedField.validNumber(new BigDecimal(negative ? n.negate() : n, picture.scale() + 1), bytes);" \
  "${FALLITO_VETTORI}" "valore e scala"
caso_java non-valido-zero "${CODEC}" \
  "return DecodedField.withoutValue(DecodeStatus.INVALID, bytes);" \
  "return DecodedField.validNumber(BigDecimal.ZERO.setScale(picture.scale()), bytes);" \
  "${FALLITO_VETTORI}" "stato ==> expected: <INVALID> but was: <VALID>"
caso_java oltre-picture-valore "${CODEC}" \
  "return DecodedField.withoutValue(DecodeStatus.BEYOND_PICTURE, bytes);" \
  "return DecodedField.validNumber(new BigDecimal(n, picture.scale()), bytes);" \
  "${FALLITO_VETTORI}" "expected: <BEYOND_PICTURE> but was: <VALID>"
caso_java zero-negativo-normalizzato "${CODEC}" \
  "        return field.originalBytes();" \
  "        byte[] b = field.originalBytes(); if (b.length > 0 && b[b.length - 1] == 0x7D && field.number().isPresent()) { b[b.length - 1] = 0x7B; } return b;" \
  "${FALLITO_VETTORI}" "ricodifica conservativa"
caso_java segno-iniziale "${CODEC}" \
  "            int digit = asciiDigit(bytes[i] & BYTE_MASK);" \
  "            if (i == 0 && !picture.signed() && bytes[i] == 0x2B) { continue; }
            int digit = asciiDigit(bytes[i] & BYTE_MASK);" \
  "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.DisplayExhaustiveTest" "casi esaustivi diversi dalla regola"
caso_java offset-zero "${CODEC}" \
  "Arrays.copyOfRange(record, offset, offset + picture.length())" \
  "Arrays.copyOfRange(record, 0, picture.length())" \
  "${FALLITO_VETTORI}"
caso_java scala-sbagliata "${CODEC}" \
  "return DecodedField.validNumber(new BigDecimal(n, picture.scale()), bytes);" \
  "return DecodedField.validNumber(new BigDecimal(n, picture.scale()).setScale(picture.scale() + 1), bytes);" \
  "${FALLITO_VETTORI}" "valore e scala"
caso_java passaggio-double "${CODEC}" \
  "BigInteger n = scaled.unscaledValue();" \
  "BigInteger n = scaled.multiply(BigDecimal.valueOf(Math.pow(10, 0))).setScale(picture.scale()).unscaledValue();" \
  "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.NoFloatingPointBytecodeTest" "java/lang/Math.pow(DD)D"

# ---- mutazioni del file dei vettori (vista temporanea) --------------------------------------

if selezionato vettori-irraggiungibili; then
  shim vettori-irraggiungibili --tmpfs "${VETTORI_IN_CONTAINER}"
  run_verify vettori-irraggiungibili "${SHIM_DIR}:${PATH}"
  if marker_ok vettori-irraggiungibili "${SHIM_DIR}/applicato"; then
    expect vettori-irraggiungibili ko "file dei vettori assente o non leggibile" "${FALLITO_VETTORI}" \
      "ERRORE: mvn verify fallito" "== VERIFICA FALLITA"
  fi
fi

if selezionato vettore-tolto; then
  originale="${ROOT}/analysis/data-codec/vettori/oracle-gnucobol.tsv"
  vista="${WORK}/vista-vettore-tolto.tsv"
  awk 'BEGIN { tolto = 0 } !tolto && /^comp\t9\(3\)\tdecodifica\t/ { tolto = 1; next } { print }' "${originale}" >"${vista}" \
    || { echo "ERRORE: awk sulla vista fallito" >&2; exit 1; }
  prima="$(wc -l <"${originale}")" || { echo "ERRORE: wc fallito" >&2; exit 1; }
  dopo="$(wc -l <"${vista}")" || { echo "ERRORE: wc fallito" >&2; exit 1; }
  [ "$((prima - dopo))" -eq 1 ] || { echo "ERRORE: la vista non ha esattamente una riga in meno (${prima} -> ${dopo})" >&2; exit 1; }
  caso_vista vettore-tolto "${vista}" "${FALLITO_VETTORI}" "vettori nel file ==> expected: <375> but was: <374>"
fi

# ---- controllo del rapporto in verify.sh ----------------------------------------------------

if selezionato vettori-saltati; then
  muta verify.sh 'mvn -B verify "-Dmenb.verify.run=${MENB_VERIFY_RUN_ID}" </dev/null' 'mvn -B verify </dev/null'
  run_verify vettori-saltati
  expect vettori-saltati ko "BUILD SUCCESS" "Tests run: 2, Failures: 0, Errors: 0, Skipped: 2" \
    "test saltato: skipped=2" "ERRORE: rapporto del test dei vettori non valido" "== VERIFICA FALLITA"
  ripristina
fi

if selezionato rapporto-residuo; then
  caso_rapporto rapporto-residuo \
    'cmp -s /menb-shim/base.xml "$R" && { echo "SHIM: rapporto gia uguale alla base" >&2; exit 95; }
cp /menb-shim/base.xml "$R"' \
    "il rapporto non e' della corsa corrente" "ERRORE: rapporto del test dei vettori non valido"
fi

if selezionato rapporto-assente; then
  caso_rapporto rapporto-assente 'rm "$R"; [ ! -e "$R" ]' "ERRORE: rapporto del test dei vettori assente"
fi

# ---- esito -----------------------------------------------------------------------------------

[ -z "${LISTA}" ] || exit 0
for richiesto in ${SEL[@]+"${SEL[@]}"}; do
  case " ${USATI[*]-} " in
    *" ${richiesto} "*) ;;
    *) echo "ERRORE: caso richiesto sconosciuto: '${richiesto}' (elenco: ./quality/regressioni-codec.sh --lista)" >&2; FAILED="${FAILED} ${richiesto}" ;;
  esac
done
echo
echo "== riepilogo (caso | codice di uscita di ./verify.sh | esito | motivo atteso)"
for r in ${RESULTS[@]+"${RESULTS[@]}"}; do
  IFS='|' read -r n c e m <<<"${r}"
  printf '%-28s %-4s %-12s %s\n' "${n}" "${c}" "${e}" "${m}"
done
echo "== durata totale: $((SECONDS - T0))s, ${#RESULTS[@]} corse"
if [ -n "${FAILED}" ]; then
  echo "ERRORE: casi non rilevati:${FAILED}" >&2
  exit 1
fi
