#!/usr/bin/env bash
# Verifica di build e test: unico prerequisito sull'host e' Docker.
#  1. elimina gli output precedenti (fallisce se la cancellazione fallisce);
#  2. lancia mvn -B verify in un'immagine Maven ufficiale (JDK 21, versione fissata), con
#     accesso al Docker dell'host per i test di integrazione (Testcontainers);
#  3. controlla che il rapporto del test dei vettori del codec (#54) e quello del test di
#     integrazione PostgreSQL siano XML completi, di questa corsa, con i casi attesi eseguiti e
#     riusciti, nessuno saltato (quality/RapportoSurefire.java); lo stesso per i test della
#     tabella dei conti (#59: AccountSchemaTest, AccountContrattoTest, AccountMigrazioneTest)
#     e del caricamento dei conti (#60: TracciatoContoTest, CaricamentoContiTest,
#     CaricamentoContiCasiTest, CaricatoreApplicazioneTest), con tutti i casi elencati per nome;
#  4. controlla i rapporti di copertura (JaCoCo: rapporto aggregato e prova dell'agente in ogni
#     modulo che esegue test) e di analisi statica (SpotBugs: un rapporto per ogni modulo di
#     produzione) con quality/RapportiQualita.java; i plugin li producono dentro mvn verify;
#  5. controlla che online e batch abbiano esattamente un jar eseguibile (*-exec.jar);
#  6. alla fine, riuscita o no, anche se interrotta, rimuove il container di build e i
#     container avviati dai test di questa corsa (etichetta menb.verify.run) e verifica che
#     non ne resti nessuno.
# Ogni comando esterno sull'host ha un limite di tempo (quality/limite.sh).
# Non avvia alcun processo applicativo: l'avvio reale dello stack e' compito di ./smoke.sh.
# Variabili opzionali: MENB_BUILD_CACHE_VOLUME (volume Docker con la cache Maven),
# MENB_VERIFY_TIMEOUT (secondi, limite dell'intero container di build; predefinito 1800),
# MENB_VERIFY_SHORT_TIMEOUT (secondi, limite di ogni altro comando esterno; predefinito 60).
set -euo pipefail

IMAGE="maven:3.9.16-eclipse-temurin-21"
# Plugin che produce i POM effettivi letti dai controlli di copertura e analisi statica (ultima
# stabile su Maven Central al 27 nov 2026; non gestita da Spring Boot).
HELP_PLUGIN_VERSION="3.6.0"
CACHE_VOLUME="${MENB_BUILD_CACHE_VOLUME:-menb-build-m2}"
VERIFY_TIMEOUT="${MENB_VERIFY_TIMEOUT:-1800}"
SHORT_TIMEOUT="${MENB_VERIFY_SHORT_TIMEOUT:-60}"
# Socket del daemon Docker: la sorgente di un montaggio e' risolta dal daemon, quindi e' il
# suo socket (su Docker Desktop il percorso e' gestito in modo speciale e porta alla VM).
DOCKER_SOCKET="/var/run/docker.sock"
RUN_LABEL_KEY="menb.verify.run"
# Cartella dello script senza comandi esterni (niente dirname), con esito controllato.
case "${BASH_SOURCE[0]}" in
  */*) ROOT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) ROOT_DIR="." ;;
esac
ROOT="$(cd "${ROOT_DIR}" && pwd)" || { echo "ERRORE: cartella dello script non raggiungibile" >&2; exit 1; }
[ -f "${ROOT}/pom.xml" ] || { echo "ERRORE: ${ROOT}/pom.xml non trovato" >&2; exit 1; }
[ -f "${ROOT}/quality/limite.sh" ] || { echo "ERRORE: ${ROOT}/quality/limite.sh non trovato" >&2; exit 1; }
[ -f "${ROOT}/quality/RapportoSurefire.java" ] || { echo "ERRORE: ${ROOT}/quality/RapportoSurefire.java non trovato" >&2; exit 1; }
[ -f "${ROOT}/quality/RapportiQualita.java" ] || { echo "ERRORE: ${ROOT}/quality/RapportiQualita.java non trovato" >&2; exit 1; }
# shellcheck source=quality/limite.sh
. "${ROOT}/quality/limite.sh" || { echo "ERRORE: caricamento di quality/limite.sh fallito" >&2; exit 1; }
check_seconds MENB_VERIFY_TIMEOUT "${VERIFY_TIMEOUT}" || exit 1
check_seconds MENB_VERIFY_SHORT_TIMEOUT "${SHORT_TIMEOUT}" || exit 1

# Identificativo di questa corsa: nome del container di build, etichetta dei container
# avviati dai test, proprieta' registrata nel rapporto dei test. Unico per corsa, quindi i
# residui di altre corse (o di altri) non contano.
RUN_ID="verify-$$-${RANDOM}${RANDOM}"
BUILD_CONTAINER="menb-build-${RUN_ID}"
RUN_LABEL="${RUN_LABEL_KEY}=${RUN_ID}"
# Cartella privata per l'output dei comandi sotto limite (vedi limited_out in limite.sh).
TMP_BASE="${TMPDIR:-/tmp}"
WORK="${TMP_BASE%/}/menb-${RUN_ID}"
WORK_CREATED=0

# Controlla che ogni riga di $1 sia un identificativo completo di container (formato di Docker).
valid_ids() {
  local line
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    [[ "${line}" =~ ^[0-9a-f]{64}$ ]] || return 1
  done <<EOF
$1
EOF
  return 0
}

# Acquisisce in LISTED gli id grezzi dei container (anche arrestati) che soddisfano il filtro
# $1. Va chiamata nella shell corrente. Restituisce 1, lasciando LISTED a "<ignoto>", se
# l'elenco non si ottiene o non ha il formato atteso: l'assenza non e' provata.
LISTED="<ignoto>"
list_containers() {
  LISTED="<ignoto>"
  if ! limited_out "${WORK}/docker-ps.out" "${SHORT_TIMEOUT}" docker ps -a -q --no-trunc --filter "$1" </dev/null; then
    echo "ERRORE: elenco dei container con il filtro $1 fallito" >&2
    return 1
  fi
  if ! valid_ids "${LIMITED_OUT}"; then
    echo "ERRORE: risposta inattesa di Docker nell'elenco dei container ($1): '${LIMITED_OUT}'" >&2
    return 1
  fi
  LISTED="${LIMITED_OUT}"
  return 0
}

# Rimuove i container dell'ultima acquisizione. Riporta gli esiti; decide la nuova acquisizione.
remove_listed() {
  local id
  while IFS= read -r id; do
    [ -n "${id}" ] || continue
    printf '  container %s\n' "${id}" >&2
    limited "${SHORT_TIMEOUT}" docker rm -f -v "${id}" </dev/null >/dev/null || echo "ERRORE: rimozione del container ${id} fallita" >&2
  done <<EOF
${LISTED}
EOF
  return 0
}

# Prima il container di build (se e' ancora vivo potrebbe avviare altri container di test),
# poi i container con l'etichetta della corsa. Restituisce 0 solo se gli elenchi si ottengono
# e sono vuoti; se trova qualcosa lo rimuove e restituisce comunque 1.
cleanup_run() {
  local rc=0 filter what
  for filter in "name=^${BUILD_CONTAINER}\$" "label=${RUN_LABEL}"; do
    case "${filter}" in
      name=*) what="container di build ${BUILD_CONTAINER}" ;;
      *) what="container di test con l'etichetta ${RUN_LABEL}" ;;
    esac
    if ! list_containers "${filter}"; then
      echo "ERRORE: impossibile verificare l'assenza di ${what}" >&2
      rc=1
      continue
    fi
    [ -n "${LISTED}" ] || continue
    rc=1
    echo "ERRORE: ${what} ancora presenti, rimozione:" >&2
    remove_listed
    if ! list_containers "${filter}"; then
      echo "ERRORE: impossibile verificare la rimozione di ${what}" >&2
    elif [ -n "${LISTED}" ]; then
      echo "ERRORE: ${what} ancora presenti dopo la rimozione, da rimuovere a mano" >&2
    else
      echo "   rimozione riuscita" >&2
    fi
  done
  if [ "${rc}" -eq 0 ]; then
    echo "== nessun container di test (${RUN_LABEL}) ne' di build rimasto"
  fi
  return "${rc}"
}

CLEANUP_ARMED=0
on_exit() {
  local rc=$?
  trap - EXIT HUP INT TERM
  # Interrotta durante un comando sotto limite: lo si ferma prima della pulizia.
  stop_limited
  if [ "${CLEANUP_ARMED}" -eq 1 ]; then
    echo "== pulizia dei container della corsa ${RUN_ID}"
    if ! cleanup_run; then
      [ "${rc}" -ne 0 ] || rc=1
    fi
  fi
  if [ "${WORK_CREATED}" -eq 1 ] && ! limited "${SHORT_TIMEOUT}" rm -rf "${WORK}" </dev/null; then
    echo "ERRORE: cancellazione di ${WORK} fallita" >&2
    [ "${rc}" -ne 0 ] || rc=1
  fi
  if [ "${rc}" -eq 0 ]; then
    echo "== verifica completata"
  else
    echo "== VERIFICA FALLITA (codice ${rc})" >&2
  fi
  exit "${rc}"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# mkdir fallisce se la cartella esiste gia': nessun output di altre corse viene riusato.
limited "${SHORT_TIMEOUT}" mkdir -m 700 "${WORK}" </dev/null || { echo "ERRORE: creazione di ${WORK} fallita" >&2; exit 1; }
WORK_CREATED=1

# Utente dell'host a cui restituire le cartelle target/: esito di id controllato e valore
# numerico, altrimenti chown riceverebbe un utente vuoto e non cambierebbe nulla.
limited_out "${WORK}/id-u.out" "${SHORT_TIMEOUT}" id -u </dev/null || { echo "ERRORE: id -u fallito" >&2; exit 1; }
HOST_UID="${LIMITED_OUT}"
limited_out "${WORK}/id-g.out" "${SHORT_TIMEOUT}" id -g </dev/null || { echo "ERRORE: id -g fallito" >&2; exit 1; }
HOST_GID="${LIMITED_OUT}"
for value in "${HOST_UID}" "${HOST_GID}"; do
  case "${value}" in
    '' | *[!0-9]*) echo "ERRORE: utente dell'host non numerico: '${HOST_UID}:${HOST_GID}'" >&2; exit 1 ;;
  esac
done

# Il contenitore gira come root: a fine corsa restituisce all'utente dell'host solo le
# cartelle target/ generate (non .git, ne' i sorgenti, ne' legacy/).
# Accesso a Docker dai test: socket del daemon montato; le porte dei container avviati dai
# test (fratelli, non figli) si raggiungono da host.docker.internal, che punta all'host sia su
# Docker Desktop sia su Linux (host-gateway). Ryuk e' disattivato: la pulizia la fa questo
# script, per etichetta, in on_exit.
CLEANUP_ARMED=1
rc=0
limited "${VERIFY_TIMEOUT}" docker run --rm -i \
  --name "${BUILD_CONTAINER}" \
  -v "${CACHE_VOLUME}:/root/.m2" \
  -v "${ROOT}:/workspace" \
  -v "${DOCKER_SOCKET}:${DOCKER_SOCKET}" \
  --add-host "host.docker.internal:host-gateway" \
  -w /workspace \
  -e HOST_UID="${HOST_UID}" -e HOST_GID="${HOST_GID}" \
  -e TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal \
  -e TESTCONTAINERS_RYUK_DISABLED=true \
  -e MENB_VERIFY_RUN_ID="${RUN_ID}" \
  -e HELP_PLUGIN_VERSION="${HELP_PLUGIN_VERSION}" \
  "${IMAGE}" bash -s <<'CONTAINER' || rc=$?
set -uo pipefail
shopt -s nullglob

cleanup() {
  local rc=$?
  for d in carddemo-*/target; do
    if ! chown -R "${HOST_UID}:${HOST_GID}" "${d}"; then
      echo "ERRORE: chown di ${d} fallito" >&2
      [ "${rc}" -eq 0 ] && rc=1
    fi
  done
  exit "${rc}"
}
trap cleanup EXIT

echo "== [1/7] pulizia degli output precedenti e mvn -B verify"
rm -rf carddemo-*/target || { echo "ERRORE: cancellazione dei target/ precedenti fallita" >&2; exit 1; }
residui=(carddemo-*/target)
if [ "${#residui[@]}" -ne 0 ]; then
  echo "ERRORE: output precedenti ancora presenti dopo la cancellazione: ${residui[*]}" >&2
  exit 1
fi
# Identificativo della corsa: deve esserci, perche' il rapporto dei test va legato a questa build.
case "${MENB_VERIFY_RUN_ID:-}" in
  verify-[0-9]*-[0-9]*) ;;
  *) echo "ERRORE: identificativo della corsa non valido: '${MENB_VERIFY_RUN_ID:-}'" >&2; exit 1 ;;
esac
# Inizio della corsa (secondi dall'epoca): un rapporto SpotBugs prodotto prima non e' di questa corsa.
RUN_START="$(date +%s)" || { echo "ERRORE: date fallito" >&2; exit 1; }
case "${RUN_START}" in
  '' | *[!0-9]*) echo "ERRORE: ora di inizio non numerica: '${RUN_START}'" >&2; exit 1 ;;
esac
# -Dmenb.verify.run arriva come proprieta' di sistema ai test e surefire la registra nel rapporto.
mvn -B verify "-Dmenb.verify.run=${MENB_VERIFY_RUN_ID}" </dev/null || { echo "ERRORE: mvn verify fallito" >&2; exit 1; }

# Test dei vettori del codec (#54): con la proprieta' menb.verify.run e' obbligatorio, senza (build
# delle immagini) si salta. Qui si prova che in questa corsa non e' stato saltato: rapporto di
# questa corsa, con esattamente i casi attesi (375 vettori di oracle-gnucobol.tsv, 10 osservazioni
# di oracle-oltre-picture.tsv), ognuno con l'identificativo del vettore corrispondente letto qui dal
# file (riga e impronta del testo), zero saltati, falliti o in errore.
echo "== [2/7] controllo del rapporto del test dei vettori del codec"
report="carddemo-domain/target/surefire-reports/TEST-io.github.ltoscano.carddemo.domain.OracleGnuCobolVectorsTest.xml"
vettori="analysis/data-codec/vettori"
if [ ! -f "${report}" ]; then
  echo "ERRORE: rapporto del test dei vettori assente: ${report}" >&2
  exit 1
fi
if ! java quality/RapportoSurefire.java "${report}" "${MENB_VERIFY_RUN_ID}" \
    io.github.ltoscano.carddemo.domain.OracleGnuCobolVectorsTest \
    "oracleGnuCobolVectors=375@${vettori}/oracle-gnucobol.tsv" \
    "beyondPictureObservations=10@${vettori}/oracle-oltre-picture.tsv" </dev/null; then
  echo "ERRORE: rapporto del test dei vettori non valido: ${report}" >&2
  exit 1
fi

# Il rapporto di surefire deve essere un XML ben formato e completo, di questa corsa (proprieta'
# menb.verify.run), con il caso di test atteso eseguito e riuscito: lo legge il parser XML del
# JDK del container (quality/RapportoSurefire.java, lanciato come sorgente).
echo "== [3/7] controllo del rapporto del test di integrazione"
report="carddemo-parity/target/surefire-reports/TEST-io.github.ltoscano.carddemo.parity.PostgresIntegrazioneTest.xml"
if [ ! -f "${report}" ]; then
  echo "ERRORE: rapporto del test di integrazione assente: ${report}" >&2
  exit 1
fi
if ! java quality/RapportoSurefire.java "${report}" "${MENB_VERIFY_RUN_ID}" \
    io.github.ltoscano.carddemo.parity.PostgresIntegrazioneTest \
    avviaLImmagineDiComposeScriveRileggeEdElimina </dev/null; then
  echo "ERRORE: rapporto del test di integrazione non valido: ${report}" >&2
  exit 1
fi

# Test della tabella dei conti (#59): obbligatori. Per ogni classe, rapporto di questa corsa con
# tutti i casi elencati qui per nome, eseguiti e riusciti, nessun caso saltato, fallito o in errore.
# Una classe esclusa o non trovata da surefire (rapporto assente), un caso rinominato o tolto (caso
# assente) o saltato fanno fallire la verifica.
echo "== [3/7] controllo dei rapporti dei test della tabella dei conti (#59)"
pretendi_casi() {
  local classe="io.github.ltoscano.carddemo.parity.$1" rapporto
  shift
  rapporto="carddemo-parity/target/surefire-reports/TEST-${classe}.xml"
  if [ ! -f "${rapporto}" ]; then
    echo "ERRORE: rapporto dei test della tabella dei conti assente: ${rapporto}" >&2
    return 1
  fi
  if ! java quality/RapportoSurefire.java "${rapporto}" "${MENB_VERIFY_RUN_ID}" "${classe}" "$@" </dev/null; then
    echo "ERRORE: rapporto dei test della tabella dei conti non valido: ${rapporto}" >&2
    return 1
  fi
  return 0
}
pretendi_casi AccountSchemaTest \
  colonneNomiOrdineTipiPrecisioneScalaCollazioneNotNullNessunPredefinito \
  vincoliChiavePrimariaCheckSullaChiaveELunghezzaDeiTesti \
  soloLIndiceDellaChiavePrimaria \
  oggettiDelloSchemaETrigger \
  massimoEMinimoDellaPictureSiRileggonoIdentici \
  unaCifraInteraInPiuERifiutata \
  chiaveNegativaRifiutata \
  chiaveDuplicataRifiutata \
  decimaliInPiuArrotondatiDalDatabase \
  testoPiuLungoOPiuCortoRifiutatoAncheConSoliSpazi \
  testoDiNCaratteriRilettoIdenticoSpaziCompresi \
  confrontiConParametroDiNCaratteri \
  ordinamentoDeiTestiPerCodiceDelCarattere \
  ordinePerChiaveNumericoCrescente || exit 1
pretendi_casi AccountContrattoTest \
  ogniCampoElementareDelContrattoHaLaSuaColonnaENessunaInPiu || exit 1
pretendi_casi AccountMigrazioneTest \
  migrazioneApplicataDueVolteNonCambiaNullaENonFallisce \
  migrazioneModificataDopoLApplicazioneFaFallireLAvvio \
  primoAvvioERiavvioBatchPoiOnlineSuDatabaseVuoto \
  primoAvvioERiavvioOnlinePoiBatchSuDatabaseVuoto || exit 1

# Test del caricamento dei conti (#60): obbligatori, con le stesse regole (rapporto di questa corsa,
# tutti i casi elencati per nome, eseguiti e riusciti, nessuno saltato, fallito o in errore).
echo "== [3/7] controllo dei rapporti dei test del caricamento dei conti (#60)"
pretendi_casi_caricamento() {
  local classe="io.github.ltoscano.carddemo.parity.$1" rapporto
  shift
  rapporto="carddemo-parity/target/surefire-reports/TEST-${classe}.xml"
  if [ ! -f "${rapporto}" ]; then
    echo "ERRORE: rapporto dei test del caricamento dei conti assente: ${rapporto}" >&2
    return 1
  fi
  if ! java quality/RapportoSurefire.java "${rapporto}" "${MENB_VERIFY_RUN_ID}" "${classe}" "$@" </dev/null; then
    echo "ERRORE: rapporto dei test del caricamento dei conti non valido: ${rapporto}" >&2
    return 1
  fi
  return 0
}
pretendi_casi_caricamento TracciatoContoTest \
  ilTracciatoDelCaricatoreCoincideRigaPerRigaConIlContratto || exit 1
pretendi_casi_caricamento CaricamentoContiTest \
  ilFileDiEsempioSiCaricaECorrispondeRecordPerRecord \
  caricamentoSuTabellaNonVuotaSiFermaSenzaCambiareNulla || exit 1
pretendi_casi_caricamento CaricamentoContiCasiTest \
  zeroNegativoRifiutato \
  segnoAlternativoRifiutato \
  fillerNonVuotoRifiutato \
  campoNumericoConSpaziRifiutato \
  chiaveDuplicataRifiutata \
  fileTroncatoRifiutato \
  byteNulloInUnCampoDiTestoRifiutato \
  importoMassimoEMinimoDellaPictureAccettati \
  fileVuotoAccettatoZeroRighe \
  recordDistinguibiliCampoPerCampoAccettati \
  caratteriOltreAsciiAccettatiERicodificatiIdentici || exit 1
pretendi_casi_caricamento CaricatoreApplicazioneTest \
  ilCaricatoreMigraCaricaETerminaConZeroPoiRifiutaLaSecondaEsecuzione \
  fileRifiutatoTerminaConIlCodiceDiRifiutoEZeroRighe || exit 1

# POM effettivi del reattore (maven-help-plugin, versione fissata): la configurazione dei plugin di
# copertura e di analisi statica si legge da qui, come la vede Maven (ereditarieta', profili,
# proprieta' risolte), non cercando testo nei POM. Nome unico per corsa; esito controllato.
EFFECTIVE_POM="/tmp/menb-effective-pom-${MENB_VERIFY_RUN_ID}.xml"
echo "== [4/7] POM effettivi (maven-help-plugin ${HELP_PLUGIN_VERSION})"
mvn -B -q "org.apache.maven.plugins:maven-help-plugin:${HELP_PLUGIN_VERSION}:effective-pom" \
  "-Dmenb.verify.run=${MENB_VERIFY_RUN_ID}" "-Doutput=${EFFECTIVE_POM}" </dev/null \
  || { echo "ERRORE: generazione dei POM effettivi fallita" >&2; exit 1; }
[ -s "${EFFECTIVE_POM}" ] || { echo "ERRORE: POM effettivi assenti o vuoti: ${EFFECTIVE_POM}" >&2; exit 1; }

# Copertura: il rapporto aggregato di JaCoCo (carddemo-parity/target/site/jacoco-aggregate/jacoco.xml)
# deve essere di questa corsa e contenere ogni classe di produzione eseguibile compilata; ogni
# modulo che ha eseguito test deve avere la prova dell'agente (sessione di questa corsa nel suo
# target/jacoco.exec). Nessuna soglia di copertura.
echo "== [5/7] controllo del rapporto di copertura (JaCoCo)"
if ! java quality/RapportiQualita.java jacoco . "${MENB_VERIFY_RUN_ID}" "${EFFECTIVE_POM}" </dev/null; then
  echo "ERRORE: rapporto di copertura JaCoCo non valido" >&2
  exit 1
fi

# Analisi statica: ogni modulo con codice di produzione deve avere un rapporto SpotBugs di questa
# corsa, senza difetti ne' errori di analisi, con tutte le sue classi analizzate.
echo "== [6/7] controllo dei rapporti di analisi statica (SpotBugs)"
if ! java quality/RapportiQualita.java spotbugs . "${MENB_VERIFY_RUN_ID}" "${RUN_START}" "${EFFECTIVE_POM}" </dev/null; then
  echo "ERRORE: rapporti SpotBugs non validi" >&2
  exit 1
fi

# Dopo la pulizia puo' esistere solo l'eseguibile prodotto da questa build: ne serve uno.
echo "== [7/7] controllo dei jar eseguibili"
for module in carddemo-online carddemo-batch; do
  jars=("${module}"/target/*-exec.jar)
  if [ "${#jars[@]}" -ne 1 ]; then
    echo "ERRORE: attesi esattamente 1 jar eseguibile in ${module}/target, trovati ${#jars[@]}" >&2
    exit 1
  fi
  echo "${module}: ${jars[0]}"
done
echo "== build e controlli nel container completati"
CONTAINER
if [ "${rc}" -ne 0 ]; then
  echo "ERRORE: container di build terminato con codice ${rc}" >&2
  exit "${rc}"
fi
