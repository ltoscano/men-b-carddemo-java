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
#   conversione-longvalue      BigInteger.valueOf(x.longValue()) nella codifica (conversione con perdita)
#   restringimento-l2i         BigInteger.valueOf((int) x.longValueExact()): chiamata esatta, poi L2I
#   conversione-sottoclasse    longValue() ereditato da una sottoclasse di BigInteger del modulo
#   picture-p                  la PICTURE normalizzata togliendo le P (forma che la colla non ammette)
#   picture-quattro-cifre      conteggi della PICTURE limitati a quattro cifre (la colla non ha limite)
#   double-pacchetto-fratello  Math.pow in una classe di un altro pacchetto del modulo, chiamata dal codec
#   vettore-ripetuto           il primo vettore verificato 375 volte: Maven verde, rapporto respinto
#   vettore-altri-dati         ogni caso verifica i dati del primo vettore: Maven verde, rapporto respinto
#   lettore-salta              il lettore salta le righe con colonne sbagliate, e la vista ne ha una
#   lettore-salta-rapporto     il lettore salta le righe che iniziano con '!', e la vista ne ha una:
#                              Maven verde, rapporto respinto (376 vettori nel file)
#   vettori-saltati           proprieta' menb.verify.run tolta da mvn in verify.sh: test saltato, il controllo
#                              del rapporto fallisce
#   rapporto-residuo           dopo il vero Maven il rapporto e' sostituito da quello sano della corsa di base
#   rapporto-assente           dopo il vero Maven il rapporto e' cancellato
#
# Uso: ./quality/regressioni-codec.sh [<caso> ...] (la corsa di base gira sempre);
# ./quality/regressioni-codec.sh --lista stampa i casi. Prerequisiti: bash, git, Docker (le
# mutazioni e le viste si fanno con un programma Java nell'immagine Maven di verify.sh, a versione fissata).
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
PICTURE="${PKG}/FieldPicture.java"
VECTORS_TEST="carddemo-domain/src/test/java/io/github/ltoscano/carddemo/domain/OracleGnuCobolVectorsTest.java"
READER="carddemo-domain/src/test/java/io/github/ltoscano/carddemo/domain/VectorFile.java"
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
CREATED=()
CREATED_DIRS=()
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
  for f in ${CREATED[@]+"${CREATED[@]}"}; do
    if ! limited "${SHORT_TIMEOUT}" rm -f "${f}" </dev/null; then
      echo "ERRORE: rimozione di ${f} fallita" >&2
      RESTORE_FAILED=1
    fi
  done
  CREATED=()
  for ((i = ${#CREATED_DIRS[@]} - 1; i >= 0; i--)); do
    f="${CREATED_DIRS[i]}"
    if ! limited "${SHORT_TIMEOUT}" rmdir "${f}" </dev/null; then
      echo "ERRORE: rimozione della cartella ${f} fallita" >&2
      RESTORE_FAILED=1
    fi
  done
  CREATED_DIRS=()
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
  limited_out "${WORK}/id-u.out" "${SHORT_TIMEOUT}" id -u </dev/null || { echo "ERRORE: id -u fallito" >&2; exit 1; }
  uid="${LIMITED_OUT}"
  limited_out "${WORK}/id-g.out" "${SHORT_TIMEOUT}" id -g </dev/null || { echo "ERRORE: id -g fallito" >&2; exit 1; }
  case "${uid}:${LIMITED_OUT}" in
    *[!0-9:]* | :* | *:) echo "ERRORE: utente dell'host non numerico: '${uid}:${LIMITED_OUT}'" >&2; exit 1 ;;
  esac
  HOST_IDS="${uid}:${LIMITED_OUT}"
fi

# ---- mutazioni -------------------------------------------------------------------------------

salva() { # file
  local n="${#SAVED[@]}"
  limited "${SHORT_TIMEOUT}" cp -p "$1" "${WORK}/bak/${n}" </dev/null || { echo "ERRORE: copia di $1 fallita" >&2; exit 1; }
  SAVED+=("$1")
}

# Le mutazioni e le viste si fanno con un piccolo programma Java eseguito nell'immagine Maven di
# verify.sh (versione fissata), non con strumenti dell'host: sull'host servono solo Docker e Git
# (oltre a bash e ai comandi di base gia' usati dagli altri script). Il programma esce con 0 solo
# se ha fatto esattamente cio' che si chiede; ogni altro codice e' un errore dello script.
#   sostituisci <file> <cercato> <sostituto>   prima occorrenza letterale; 3 se assente, 4 se il file non cambia
#   crea <file> <testo>                        file nuovo; 3 se esiste gia'
#   togli-riga <origine> <vista> <prefisso>    la vista e' l'origine senza la prima riga con quel prefisso; 3 se assente
#   aggiungi-riga <origine> <vista> <riga>     la vista e' l'origine con una riga in fondo
MUTA_IMAGE="maven:3.9.16-eclipse-temurin-21"
MUTA_SRC='import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public class Muta {
    public static void main(String[] a) throws Exception {
        switch (a[0]) {
            case "sostituisci" -> {
                Path f = Path.of(a[1]);
                String t = Files.readString(f, StandardCharsets.UTF_8);
                int i = t.indexOf(a[2]);
                if (i < 0) {
                    System.err.println("MUTA: testo non trovato in " + f);
                    System.exit(3);
                }
                String n = t.substring(0, i) + a[3] + t.substring(i + a[2].length());
                if (n.equals(t)) {
                    System.err.println("MUTA: " + f + " non cambia");
                    System.exit(4);
                }
                Files.writeString(f, n, StandardCharsets.UTF_8);
            }
            case "crea" -> {
                Path f = Path.of(a[1]);
                if (Files.exists(f)) {
                    System.err.println("MUTA: " + f + " esiste gia");
                    System.exit(3);
                }
                Files.writeString(f, a[2], StandardCharsets.UTF_8);
            }
            case "togli-riga" -> {
                String[] r = Files.readString(Path.of(a[1]), StandardCharsets.UTF_8).split("\n", -1);
                StringBuilder b = new StringBuilder();
                boolean tolta = false;
                for (int i = 0; i < r.length; i++) {
                    if (!tolta && r[i].startsWith(a[3])) {
                        tolta = true;
                        continue;
                    }
                    b.append(r[i]).append(i < r.length - 1 ? "\n" : "");
                }
                if (!tolta) {
                    System.err.println("MUTA: nessuna riga che inizia con il prefisso dato");
                    System.exit(3);
                }
                Files.writeString(Path.of(a[2]), b.toString(), StandardCharsets.UTF_8);
            }
            case "aggiungi-riga" -> {
                String t = Files.readString(Path.of(a[1]), StandardCharsets.UTF_8);
                Files.writeString(Path.of(a[2]), t + a[3] + "\n", StandardCharsets.UTF_8);
            }
            default -> {
                System.err.println("MUTA: comando sconosciuto " + a[0]);
                System.exit(2);
            }
        }
    }
}'
HOST_IDS=""
MUTA_N=0
# muta_java <comando> <argomenti...>: i percorsi sono gia' quelli del container (/w = repository,
# /m = cartella di lavoro). Limite di tempo; container con nome proprio, rimosso anche se il limite scade.
MUTA_RC=0
# muta_run: come muta_java ma non termina lo script; lascia l'esito in MUTA_RC (0 solo se riuscito).
muta_run() {
  local name
  MUTA_RC=0
  MUTA_N=$((MUTA_N + 1))
  name="menb-codec-muta-$$-${MUTA_N}"
  limited "${SHORT_TIMEOUT}" docker run --rm --name "${name}" --user "${HOST_IDS}" -e HOME=/tmp \
    -v "${ROOT}:/w" -v "${WORK}:/m" -w /w --entrypoint java "${MUTA_IMAGE}" /m/Muta.java "$@" </dev/null || MUTA_RC=$?
  if [ "${MUTA_RC}" -ne 0 ]; then
    limited "${SHORT_TIMEOUT}" docker rm -f "${name}" </dev/null >/dev/null 2>&1 || true
    case "${MUTA_RC}" in
      124) echo "ERRORE: programma di mutazione ($1) oltre il limite di ${SHORT_TIMEOUT}s" >&2 ;;
      3) echo "ERRORE: programma di mutazione ($1): bersaglio assente o gia' presente, mutazione non applicabile" >&2 ;;
      4) echo "ERRORE: programma di mutazione ($1): il file non cambia, mutazione non applicata" >&2 ;;
      *) echo "ERRORE: programma di mutazione ($1) fallito con codice ${MUTA_RC}" >&2 ;;
    esac
  fi
  return 0
}

muta_java() {
  muta_run "$@"
  [ "${MUTA_RC}" -eq 0 ] || exit 1
}

# muta <file-relativo> <cercato> <sostituto>: sostituisce la prima occorrenza letterale; fallisce se
# il testo non c'e' o se il file non cambia (una mutazione che non altera nulla non dimostra niente).
muta() {
  [ -f "${ROOT}/$1" ] || { echo "ERRORE: $1 non trovato" >&2; exit 1; }
  salva "${ROOT}/$1"
  muta_java sostituisci "/w/$1" "$2" "$3"
}

# crea <file-relativo> <testo>: file nuovo (con la sua cartella, se manca), rimosso al ripristino.
# Il file (e la cartella) devono mancare prima: un file o una cartella che esistevano gia' non sono
# mai registrati, quindi il ripristino non li tocca. Si registra solo cio' che questa chiamata ha
# creato davvero, anche se il programma di mutazione fallisce dopo aver scritto il file.
crea() {
  local d="${ROOT}/${1%/*}" f="${ROOT}/$1"
  if [ -e "${f}" ] || [ -L "${f}" ]; then
    echo "ERRORE: ${f} esiste gia': non si crea e non si registra per la rimozione" >&2
    exit 1
  fi
  if [ ! -d "${d}" ]; then
    limited "${SHORT_TIMEOUT}" mkdir "${d}" </dev/null || { echo "ERRORE: creazione di ${d} fallita" >&2; exit 1; }
    CREATED_DIRS+=("${d}")
  fi
  muta_run crea "/w/$1" "$2"
  if [ -e "${f}" ]; then
    CREATED+=("${f}")
  fi
  [ "${MUTA_RC}" -eq 0 ] || exit 1
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

# Ultime 25 righe del log, solo con bash (nessun comando esterno senza limite).
show_tail() {
  local lines=() line i start
  while IFS= read -r line; do lines+=("${line}"); done <<EOF
${RUN_LOG}
EOF
  start=$(( ${#lines[@]} > 25 ? ${#lines[@]} - 25 : 0 ))
  for ((i = start; i < ${#lines[@]}; i++)); do printf '     | %s\n' "${lines[i]}"; done
  return 0
}

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
      show_tail
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
  printf '%s\n' "${MUTA_SRC}" >"${WORK}/Muta.java" || { echo "ERRORE: scrittura del programma di mutazione fallita" >&2; exit 1; }
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
caso_java conversione-longvalue "${CODEC}" \
  "BigInteger n = scaled.unscaledValue();" \
  "BigInteger n = BigInteger.valueOf(scaled.unscaledValue().longValue());" \
  "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.NoFloatingPointBytecodeTest" "con perdita java/math/BigInteger.longValue()J"
caso_java restringimento-l2i "${CODEC}" \
  "BigInteger n = scaled.unscaledValue();" \
  "BigInteger n = BigInteger.valueOf((int) scaled.unscaledValue().longValueExact());" \
  "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.NoFloatingPointBytecodeTest" \
  "GnuCobolFieldCodec.unscaled(Lio/github/ltoscano/carddemo/domain/FieldPicture;Ljava/math/BigDecimal;)Ljava/math/BigInteger;: restringimento L2I"

# longValue() ereditato da una sottoclasse di BigInteger del modulo: l'owner nel bytecode e' la sottoclasse
if selezionato conversione-sottoclasse; then
  crea "carddemo-domain/src/main/java/io/github/ltoscano/carddemo/precision/Wide.java" 'package io.github.ltoscano.carddemo.precision;

/** Prova negativa di regressioni-codec.sh: sottoclasse di BigInteger, longValue() ereditato. */
public final class Wide extends java.math.BigInteger {
    private static final long serialVersionUID = 1L;

    /** @param v cifre decimali */
    public Wide(String v) {
        super(v);
    }
}
'
  muta "${CODEC}" "BigInteger n = scaled.unscaledValue();" \
    "BigInteger n = BigInteger.valueOf(new io.github.ltoscano.carddemo.precision.Wide(scaled.unscaledValue().toString()).longValue());"
  run_verify conversione-sottoclasse
  expect conversione-sottoclasse ko "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.NoFloatingPointBytecodeTest" \
    "con perdita io/github/ltoscano/carddemo/precision/Wide.longValue()J" \
    "ERRORE: mvn verify fallito" "== VERIFICA FALLITA"
  ripristina
fi

caso_java picture-p "${PICTURE}" \
  "Matcher m = NUMERIC.matcher(picture);" \
  "Matcher m = NUMERIC.matcher(picture.replace(\"P\", \"\"));" \
  "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.GnuCobolFieldCodecTest" "P9(4)"
caso_java picture-quattro-cifre "${PICTURE}" \
  'Pattern.compile("X\\(([1-9][0-9]*)\\)");' \
  'Pattern.compile("X\\(([1-9][0-9]{0,3})\\)");' \
  "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.GnuCobolFieldCodecTest" "confiniDeiConteggiPerOgniCategoria"

# double in una classe di un pacchetto fratello dello stesso modulo, chiamata dal codec
if selezionato double-pacchetto-fratello; then
  crea "carddemo-domain/src/main/java/io/github/ltoscano/carddemo/precision/Scale.java" 'package io.github.ltoscano.carddemo.precision;

/** Prova negativa di regressioni-codec.sh: passa per double. */
public final class Scale {
    private Scale() {
    }

    /** @return 1, calcolato in virgola mobile */
    public static java.math.BigDecimal one() {
        return java.math.BigDecimal.valueOf(Math.pow(10, 0));
    }
}
'
  muta "${CODEC}" "BigInteger n = scaled.unscaledValue();" \
    "BigInteger n = scaled.multiply(io.github.ltoscano.carddemo.precision.Scale.one()).setScale(picture.scale()).unscaledValue();"
  run_verify double-pacchetto-fratello
  expect double-pacchetto-fratello ko "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.NoFloatingPointBytecodeTest" \
    "io/github/ltoscano/carddemo/precision/Scale.one()Ljava/math/BigDecimal;: chiamata java/lang/Math.pow(DD)D" \
    "ERRORE: mvn verify fallito" "== VERIFICA FALLITA"
  ripristina
fi

# lo stesso vettore verificato 375 volte: Maven verde, il controllo del rapporto lo respinge
caso_rapporto_java() { # caso file cercato sostituto messaggio...
  selezionato "$1" || return 0
  local name="$1" file="$2" cercato="$3" sostituto="$4"
  shift 4
  muta "${file}" "${cercato}" "${sostituto}"
  run_verify "${name}"
  expect "${name}" ko "BUILD SUCCESS" "$@" "ERRORE: rapporto del test dei vettori non valido" "== VERIFICA FALLITA"
  ripristina
}
caso_rapporto_java vettore-ripetuto "${VECTORS_TEST}" \
  "return rows.stream().map(r -> dynamicTest(name(r), () -> check(r)));" \
  "return java.util.Collections.nCopies(rows.size(), rows.get(0)).stream().map(r -> dynamicTest(name(r), () -> check(r)));" \
  "testcase oracleGnuCobolVectors()[2]: vettore verificato [oracle-gnucobol.tsv:20:"
# il mutante della validazione 2 nella forma che resta esprimibile: ogni caso, con il nome e
# l'indice della sua riga, verifica i dati del primo vettore. Row non si costruisce piu' da testo e
# colonne separati; il marcatore lo scrive check() per la riga che ha appena verificato.
caso_rapporto_java vettore-altri-dati "${VECTORS_TEST}" \
  "dynamicTest(name(r), () -> check(r))" \
  "dynamicTest(name(r), () -> check(rows.get(0)))" \
  "testcase oracleGnuCobolVectors()[2]: vettore verificato [oracle-gnucobol.tsv:20:"

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
  muta_java togli-riga "/w/analysis/data-codec/vettori/oracle-gnucobol.tsv" /m/vista-vettore-tolto.tsv "$(printf 'comp\t9(3)\tdecodifica\t')"
  caso_vista vettore-tolto "${WORK}/vista-vettore-tolto.tsv" "${FALLITO_VETTORI}" "vettori nel file ==> expected: <375> but was: <374>"
fi

# lettore che salta in silenzio le righe con le colonne sbagliate, e una tale riga nella vista: lo
# vede il test diretto della grammatica (VectorFileTest)
if selezionato lettore-salta; then
  muta "${READER}" "if (fields == null) {" "if (fields == null) { continue; } if (false) {"
  muta_java aggiungi-riga "/w/analysis/data-codec/vettori/oracle-gnucobol.tsv" /m/vista-lettore-salta.tsv "riga incomprensibile"
  caso_vista lettore-salta "${WORK}/vista-lettore-salta.tsv" "<<< FAILURE! -- in io.github.ltoscano.carddemo.domain.VectorFileTest" \
    "righeSconosciuteRifiutateNonSaltate"
  ripristina
fi

# lettore che salta in silenzio solo le righe che iniziano con '!' (il test diretto non lo vede),
# e una tale riga nella vista: Maven verde, il controllo del rapporto conta 376 vettori nel file
if selezionato lettore-salta-rapporto; then
  muta "${READER}" 'if (blank(line) || line.startsWith("#")) {' 'if (blank(line) || line.startsWith("#") || line.startsWith("!")) {'
  muta_java aggiungi-riga "/w/analysis/data-codec/vettori/oracle-gnucobol.tsv" /m/vista-lettore-salta-rapporto.tsv "!riga incomprensibile"
  shim lettore-salta-rapporto -v "${WORK}/vista-lettore-salta-rapporto.tsv:${VETTORI_IN_CONTAINER}/oracle-gnucobol.tsv:ro"
  run_verify lettore-salta-rapporto "${SHIM_DIR}:${PATH}"
  if marker_ok lettore-salta-rapporto "${SHIM_DIR}/applicato"; then
    expect lettore-salta-rapporto ko "BUILD SUCCESS" "oracle-gnucobol.tsv: 376 vettori nel file, attesi 375" \
      "ERRORE: rapporto del test dei vettori non valido" "== VERIFICA FALLITA"
  fi
  ripristina
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
    'cp /menb-shim/base.xml "$R"
cmp -s /menb-shim/base.xml "$R" || { echo "SHIM: copia del rapporto di base non riuscita" >&2; exit 95; }' \
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
