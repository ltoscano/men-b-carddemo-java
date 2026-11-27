#!/usr/bin/env bash
# Regressioni dei controlli di #26 (confini tra moduli, database incorporati, tipi in virgola
# mobile, accessi tra classi). Per ogni caso applica una mutazione al working tree, esegue
# Maven in un container (stessa immagine di ./verify.sh), controlla che il fallimento sia
# quello atteso (codice di uscita e messaggio del controllo giusto; non errori di
# compilazione, di download o scadenza del limite), e ripristina. Si esegue a richiesta;
# non fa parte di ./verify.sh ne' della CI obbligatoria.
#
# Casi:
#   base                          nessuna mutazione: Maven riesce e il log mostra ogni controllo
#                                 eseguito (conteggio delle esecuzioni, nessun salto)
#   archi-*                       archi interni vietati, dichiarati e non usati (enforcer)
#   db-*                          H2, HSQLDB, Derby diretti e uno transitivo (enforcer)
#   archunit-*                    online usa batch (fallisce) e online usa domain (passa)
#   tipi-*                        tipi in virgola mobile, letterali e var (Checkstyle)
#   cancello-*                    un controllo disattivato o rimosso: la corsa di base non
#                                 riconosce piu' tutti i controlli e deve fallire
# Il working tree deve essere pulito all'avvio e lo e' alla fine (altrimenti l'esito e' 1).
# Variabili opzionali: MENB_BUILD_CACHE_VOLUME, MENB_REGOLE_TIMEOUT (secondi per caso,
# predefinito 900), MENB_REGOLE_SHORT_TIMEOUT (altri comandi esterni, predefinito 60).
set -euo pipefail

IMAGE="maven:3.9.16-eclipse-temurin-21"
CACHE_VOLUME="${MENB_BUILD_CACHE_VOLUME:-menb-build-m2}"
CASE_TIMEOUT="${MENB_REGOLE_TIMEOUT:-900}"
SHORT_TIMEOUT="${MENB_REGOLE_SHORT_TIMEOUT:-60}"
case "${BASH_SOURCE[0]}" in
  */*) ROOT_DIR="${BASH_SOURCE[0]%/*}/.." ;;
  *) ROOT_DIR=".." ;;
esac
ROOT="$(cd "${ROOT_DIR}" && pwd)" || { echo "ERRORE: radice non raggiungibile" >&2; exit 1; }
[ -f "${ROOT}/pom.xml" ] || { echo "ERRORE: ${ROOT}/pom.xml non trovato" >&2; exit 1; }
[ -f "${ROOT}/quality/limite.sh" ] || { echo "ERRORE: quality/limite.sh non trovato" >&2; exit 1; }
# shellcheck source=quality/limite.sh
. "${ROOT}/quality/limite.sh" || { echo "ERRORE: caricamento di quality/limite.sh fallito" >&2; exit 1; }
check_seconds MENB_REGOLE_TIMEOUT "${CASE_TIMEOUT}" || exit 1
check_seconds MENB_REGOLE_SHORT_TIMEOUT "${SHORT_TIMEOUT}" || exit 1

CASI="${ROOT}/quality/regole/casi"
PKG_DIR="io/github/ltoscano/carddemo"
RUN_ID="regole-$$-${RANDOM}${RANDOM}"
RUN_LABEL="menb.regole.run=${RUN_ID}"
TMP_BASE="${TMPDIR:-/tmp}"
WORK="${TMP_BASE%/}/issue26-${RUN_ID}"
WORK_CREATED=0
SAVED=()      # file salvati: indice -> percorso originale (copia in ${WORK}/bak/<indice>)
CREATED=()    # file creati dai casi, da rimuovere
RESULTS=()
FAILED=0
CASE_N=0

CLEANUP_ARMED=0
RESTORE_FAILED=0

ripristina() {
  local i f
  for ((i = ${#SAVED[@]} - 1; i >= 0; i--)); do
    f="${SAVED[i]}"
    if ! cp -p "${WORK}/bak/${i}" "${f}"; then
      echo "ERRORE: ripristino di ${f} fallito" >&2
      RESTORE_FAILED=1
    fi
  done
  SAVED=()
  for f in ${CREATED[@]+"${CREATED[@]}"}; do
    if ! rm -f "${f}"; then
      echo "ERRORE: rimozione di ${f} fallita" >&2
      RESTORE_FAILED=1
    fi
  done
  CREATED=()
}

# Container di questa corsa: rimossi per etichetta, poi verificato che non ne resti nessuno.
cleanup_containers() {
  local ids id rc=0
  limited_out "${WORK}/ps.out" "${SHORT_TIMEOUT}" docker ps -a -q --no-trunc --filter "label=${RUN_LABEL}" </dev/null || { echo "ERRORE: elenco dei container fallito" >&2; return 1; }
  ids="${LIMITED_OUT}"
  while IFS= read -r id; do
    [ -n "${id}" ] || continue
    [[ "${id}" =~ ^[0-9a-f]{64}$ ]] || { echo "ERRORE: risposta inattesa di Docker: '${id}'" >&2; return 1; }
    limited "${SHORT_TIMEOUT}" docker rm -f -v "${id}" </dev/null >/dev/null || { echo "ERRORE: rimozione del container ${id} fallita" >&2; rc=1; }
  done <<EOF
${ids}
EOF
  limited_out "${WORK}/ps2.out" "${SHORT_TIMEOUT}" docker ps -a -q --no-trunc --filter "label=${RUN_LABEL}" </dev/null || { echo "ERRORE: nuovo elenco dei container fallito" >&2; return 1; }
  if [ -n "${LIMITED_OUT}" ]; then
    echo "ERRORE: container della corsa ancora presenti: ${LIMITED_OUT}" >&2
    rc=1
  fi
  return "${rc}"
}

on_exit() {
  local rc=$?
  trap - EXIT HUP INT TERM
  stop_limited
  if [ "${CLEANUP_ARMED}" -eq 1 ]; then
    echo "== ripristino e pulizia della corsa ${RUN_ID}"
    ripristina
    cleanup_containers || [ "${rc}" -ne 0 ] || rc=1
    [ "${RESTORE_FAILED}" -eq 0 ] || [ "${rc}" -ne 0 ] || rc=1
    if limited_out "${WORK}/status.out" "${SHORT_TIMEOUT}" git -C "${ROOT}" status --porcelain </dev/null; then
      if [ -n "${LIMITED_OUT}" ]; then
        echo "ERRORE: working tree non pulito alla fine:" >&2
        echo "${LIMITED_OUT}" >&2
        [ "${rc}" -ne 0 ] || rc=1
      else
        echo "== working tree pulito"
      fi
    else
      echo "ERRORE: git status fallito" >&2
      [ "${rc}" -ne 0 ] || rc=1
    fi
  fi
  if [ "${WORK_CREATED}" -eq 1 ] && ! limited "${SHORT_TIMEOUT}" rm -rf "${WORK}" </dev/null; then
    echo "ERRORE: cancellazione di ${WORK} fallita" >&2
    [ "${rc}" -ne 0 ] || rc=1
  fi
  if [ "${rc}" -eq 0 ]; then echo "== regressioni completate"; else echo "== REGRESSIONI FALLITE (codice ${rc})" >&2; fi
  exit "${rc}"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

limited "${SHORT_TIMEOUT}" mkdir -m 700 "${WORK}" </dev/null || { echo "ERRORE: creazione di ${WORK} fallita" >&2; exit 1; }
WORK_CREATED=1
limited "${SHORT_TIMEOUT}" mkdir "${WORK}/bak" </dev/null || { echo "ERRORE: creazione di ${WORK}/bak fallita" >&2; exit 1; }
limited_out "${WORK}/id-u.out" "${SHORT_TIMEOUT}" id -u </dev/null || { echo "ERRORE: id -u fallito" >&2; exit 1; }
HOST_UID="${LIMITED_OUT}"
limited_out "${WORK}/id-g.out" "${SHORT_TIMEOUT}" id -g </dev/null || { echo "ERRORE: id -g fallito" >&2; exit 1; }
HOST_GID="${LIMITED_OUT}"
for value in "${HOST_UID}" "${HOST_GID}"; do
  case "${value}" in '' | *[!0-9]*) echo "ERRORE: utente dell'host non numerico: '${value}'" >&2; exit 1 ;; esac
done
limited_out "${WORK}/status0.out" "${SHORT_TIMEOUT}" git -C "${ROOT}" status --porcelain </dev/null || { echo "ERRORE: git status fallito" >&2; exit 1; }
[ -z "${LIMITED_OUT}" ] || { echo "ERRORE: working tree non pulito all'avvio, nessuna mutazione applicata:" >&2; echo "${LIMITED_OUT}" >&2; exit 1; }
CLEANUP_ARMED=1

# ---- mutazioni -------------------------------------------------------------------------

salva() { # file
  local n="${#SAVED[@]}"
  cp -p "$1" "${WORK}/bak/${n}" || { echo "ERRORE: copia di $1 fallita" >&2; exit 1; }
  SAVED+=("$1")
}

# Sostituisce $1 con l'output del programma awk $2 (con argomenti ulteriori). Esito controllato.
awk_su() { # file programma [-v var=valore ...]
  local file="$1" prog="$2" out="${WORK}/awk.tmp"
  shift 2
  awk "$@" "${prog}" "${file}" > "${out}" || { echo "ERRORE: awk su ${file} fallito" >&2; exit 1; }
  cp "${out}" "${file}" || { echo "ERRORE: scrittura di ${file} fallita" >&2; exit 1; }
}

pom_di() { echo "${ROOT}/$1/pom.xml"; }

mut_inserisci() { # modulo-o-. frammento ancora(regex awk)
  local pom
  pom="$(pom_di "$1")"
  salva "${pom}"
  awk_su "${pom}" '$0 ~ ancora && !fatto { while ((getline l < frag) > 0) print l; close(frag); fatto = 1 } { print }' -v "frag=${CASI}/pom/$2.xml" -v "ancora=$3"
  grep -q 'PROVA-REGOLE-26' "${pom}" || { echo "ERRORE: mutazione non applicata a ${pom}" >&2; exit 1; }
}
mut_dip() { mut_inserisci "$1" "$2" '</dependencies>'; }
mut_repo() {
  local pom
  pom="$(pom_di "$1")"
  salva "${pom}"
  awk_su "${pom}" '{ print } /<\/parent>/ && !fatto { while ((getline l < frag) > 0) print l; close(frag); fatto = 1 }' -v "frag=${CASI}/pom/repository-locale.xml"
  grep -q 'PROVA-REGOLE-26' "${pom}" || { echo "ERRORE: mutazione non applicata a ${pom}" >&2; exit 1; }
}

mut_senza_blocco() { # modulo-o-. tag artifactId   (rimuove il blocco <tag> con quell'artifactId)
  local pom before after
  pom="$(pom_di "$1")"
  salva "${pom}"
  before="$(grep -c "<artifactId>$3</artifactId>" "${pom}")" || before=0
  awk_su "${pom}" '$0 ~ "^[ \t]*<" tag ">" { buf = $0; dentro = 1; next }
    dentro { buf = buf "\n" $0; if ($0 ~ "</" tag ">") { dentro = 0; if (buf !~ "<artifactId>" art "</artifactId>") print buf }; next }
    { print }' -v "tag=$2" -v "art=$3"
  after="$(grep -c "<artifactId>$3</artifactId>" "${pom}")" || after=0
  [ "${after}" -lt "${before}" ] || { echo "ERRORE: blocco $3 non rimosso da ${pom}" >&2; exit 1; }
}

mut_skip() { # modulo-o-. ancora-letterale testo-letterale  (dopo la prima riga con l'ancora)
  local pom
  pom="$(pom_di "$1")"
  salva "${pom}"
  awk_su "${pom}" '{ print } index($0, ancora) && !fatto { print testo; fatto = 1 }' -v "ancora=$2" -v "testo=$3"
  grep -qF -- "$3" "${pom}" || { echo "ERRORE: mutazione non applicata a ${pom}" >&2; exit 1; }
}

mut_java() { # modulo file-caso nome-classe-destinazione
  local pkg dest
  pkg="${1#carddemo-}"
  dest="${ROOT}/$1/src/main/java/${PKG_DIR}/${pkg}/$3.java"
  [ ! -e "${dest}" ] || { echo "ERRORE: ${dest} esiste gia'" >&2; exit 1; }
  sed "s/class ProvaRegole/class $3/" "${CASI}/java/$2.java" > "${dest}" || { echo "ERRORE: copia del caso $2 fallita" >&2; exit 1; }
  CREATED+=("${dest}")
  grep -q 'PROVA-REGOLE-26' "${dest}" || { echo "ERRORE: caso $2 non applicato" >&2; exit 1; }
}

mut_senza_file() { # percorso relativo
  salva "${ROOT}/$1"
  rm -f "${ROOT}/$1" || { echo "ERRORE: rimozione di $1 fallita" >&2; exit 1; }
  [ ! -e "${ROOT}/$1" ] || { echo "ERRORE: $1 ancora presente" >&2; exit 1; }
}

# ---- esecuzione ------------------------------------------------------------------------

# mvn_run <log> <argomenti di mvn...>: ripulisce i target/, esegue Maven nel container sotto
# limite di tempo, restituisce i target/ all'utente dell'host. Codice: quello di Maven, 124 se
# scaduto, 97 se il chown fallisce.
mvn_run() {
  local log="$1" rc=0
  shift
  CASE_N=$((CASE_N + 1))
  limited "${CASE_TIMEOUT}" docker run --rm -i \
    --name "menb-regole-${RUN_ID}-${CASE_N}" --label "${RUN_LABEL}" \
    -v "${CACHE_VOLUME}:/root/.m2" -v "${ROOT}:/workspace" -w /workspace \
    -e HOST_UID="${HOST_UID}" -e HOST_GID="${HOST_GID}" \
    "${IMAGE}" bash -c 'rm -rf carddemo-*/target || exit 98
mvn -B "$@" </dev/null; rc=$?
for d in carddemo-*/target; do [ -e "$d" ] && { chown -R "${HOST_UID}:${HOST_GID}" "$d" || exit 97; }; done
exit "$rc"' _ "$@" </dev/null >"${log}" 2>&1 || rc=$?
  return "${rc}"
}

ESEC_BASE=(verify -Dtest=ArchitetturaTest -Dsurefire.failIfNoSpecifiedTests=false)

# Controlla che la corsa di base mostri ogni controllo eseguito, con il numero atteso di volte.
# Stampa i controlli mancanti; restituisce 0 solo se ci sono tutti.
controlla_base() { # log
  local log="$1" ok=0 n
  conta() { # descrizione atteso testo
    n="$(grep -cF -- "$3" "${log}")" || n=0
    if [ "${n}" -ne "$2" ]; then
      echo "   controllo mancante o saltato: $1 (attese $2 occorrenze di '$3', trovate ${n})"
      ok=1
    fi
  }
  conta "enforcer database incorporati (padre + 5 moduli)" 6 "enforcer:3.6.3:enforce (database-incorporati)"
  conta "enforcer archi interni (4 moduli)" 4 "enforcer:3.6.3:enforce (archi-interni)"
  conta "regole enforcer riuscite" 10 "BannedDependencies passed"
  conta "checkstyle tipi vietati (4 moduli)" 4 "checkstyle:3.6.0:check (tipi-vietati)"
  conta "checkstyle senza violazioni" 4 "You have 0 Checkstyle violations"
  conta "test ArchUnit eseguiti" 1 "Running io.github.ltoscano.carddemo.parity.ArchitetturaTest"
  conta "test ArchUnit riusciti" 1 "Tests run: 2, Failures: 0, Errors: 0, Skipped: 0, Time elapsed"
  return "${ok}"
}

record() { # nome esito codice durata motivo
  RESULTS+=("$1|$2|$3|$4|$5")
  if [ "$2" != "OK" ]; then FAILED=1; fi
  printf '== caso %-34s %-8s codice %s, %ss\n' "$1" "$2" "$3" "$4"
}

# Marcatori che indicano un fallimento per la ragione sbagliata.
motivi_errati() { # log -> stampa il primo trovato
  local m
  for m in "COMPILATION ERROR" "Could not resolve" "Could not transfer" "Non-resolvable" "Cannot access" "Unknown host"; do
    if grep -qF -- "${m}" "$1"; then echo "${m}"; return 0; fi
  done
  return 1
}

# atteso_fallimento <nome> <motivo atteso (testo)> <marcatori...> -- <argomenti mvn>
atteso_fallimento() {
  local nome="$1" motivo="$2" log="${WORK}/$1.log" start="${SECONDS}" rc=0 m errato mancanti="" markers=()
  shift 2
  while [ "$1" != "--" ]; do markers+=("$1"); shift; done
  shift
  mvn_run "${log}" "$@" || rc=$?
  if [ "${rc}" -eq 0 ]; then
    record "${nome}" "NON-RILEVATO" "${rc}" "$((SECONDS - start))" "la mutazione non ha fatto fallire Maven"
  elif [ "${rc}" -eq 124 ] || [ "${rc}" -eq 97 ] || [ "${rc}" -eq 98 ]; then
    record "${nome}" "ERRORE" "${rc}" "$((SECONDS - start))" "limite di tempo o errore del contenitore"
  else
    for m in "${markers[@]}"; do
      grep -qF -- "${m}" "${log}" || mancanti="${mancanti} '${m}'"
    done
    if errato="$(motivi_errati "${log}")"; then
      record "${nome}" "MOTIVO" "${rc}" "$((SECONDS - start))" "fallito per un altro motivo: ${errato}"
    elif [ -n "${mancanti}" ]; then
      record "${nome}" "MOTIVO" "${rc}" "$((SECONDS - start))" "marcatori assenti dal log:${mancanti}"
    else
      record "${nome}" "OK" "${rc}" "$((SECONDS - start))" "${motivo}"
    fi
  fi
  ripristina
}

ENF="Failed to execute goal org.apache.maven.plugins:maven-enforcer-plugin:3.6.3:enforce"
CHK="Failed to execute goal org.apache.maven.plugins:maven-checkstyle-plugin:3.6.0:check (tipi-vietati)"
G="io.github.ltoscano.carddemo"

echo "== corsa ${RUN_ID}: immagine ${IMAGE}"

# ---- base ----
start="${SECONDS}"
rc=0
mvn_run "${WORK}/base.log" "${ESEC_BASE[@]}" || rc=$?
if [ "${rc}" -ne 0 ]; then
  record base ERRORE "${rc}" "$((SECONDS - start))" "la corsa di base deve riuscire"
  tail -30 "${WORK}/base.log" >&2 || true
  echo "ERRORE: senza corsa di base verde i casi negativi non dimostrano nulla" >&2
  exit 1
fi
if mancanti="$(controlla_base "${WORK}/base.log")"; then
  record base OK 0 "$((SECONDS - start))" "tutti i controlli eseguiti, nessuna violazione"
else
  echo "${mancanti}" >&2
  record base ERRORE 0 "$((SECONDS - start))" "controlli mancanti nel log di base"
  exit 1
fi

# ---- archi interni (enforcer) ----
mut_senza_blocco carddemo-loader dependency carddemo-domain
mut_dip carddemo-domain domain-loader
atteso_fallimento archi-domain-loader "enforcer" "${ENF} (archi-interni)" "ARCO-INTERNO-VIETATO" "Found Banned Dependency: ${G}:carddemo-loader:jar" "@ carddemo-domain" -- validate

mut_dip carddemo-loader loader-online
atteso_fallimento archi-loader-online "enforcer" "${ENF} (archi-interni)" "ARCO-INTERNO-VIETATO" "Found Banned Dependency: ${G}:carddemo-online:jar" "@ carddemo-loader" -- validate

mut_dip carddemo-online online-batch
atteso_fallimento archi-online-batch "enforcer" "${ENF} (archi-interni)" "ARCO-INTERNO-VIETATO" "Found Banned Dependency: ${G}:carddemo-batch:jar" "@ carddemo-online" -- validate

mut_dip carddemo-batch batch-online
atteso_fallimento archi-batch-online "enforcer" "${ENF} (archi-interni)" "ARCO-INTERNO-VIETATO" "Found Banned Dependency: ${G}:carddemo-online:jar" "@ carddemo-batch" -- validate

mut_dip carddemo-batch batch-loader-test
atteso_fallimento archi-batch-loader-test "enforcer, ambito test" "${ENF} (archi-interni)" "ARCO-INTERNO-VIETATO" "Found Banned Dependency: ${G}:carddemo-loader:jar" "@ carddemo-batch" -- validate

mut_dip carddemo-online online-loader-optional
atteso_fallimento archi-online-loader-optional "enforcer, optional" "${ENF} (archi-interni)" "ARCO-INTERNO-VIETATO" "Found Banned Dependency: ${G}:carddemo-loader:jar" "@ carddemo-online" -- validate

# ---- database incorporati (enforcer) ----
mut_dip carddemo-loader h2
atteso_fallimento db-h2 "enforcer" "${ENF} (database-incorporati)" "DATABASE-INCORPORATO-VIETATO" "Found Banned Dependency: com.h2database:h2" "@ carddemo-loader" -- validate

mut_dip carddemo-online hsqldb
atteso_fallimento db-hsqldb "enforcer" "${ENF} (database-incorporati)" "DATABASE-INCORPORATO-VIETATO" "Found Banned Dependency: org.hsqldb:hsqldb" "@ carddemo-online" -- validate

mut_dip carddemo-batch derby
atteso_fallimento db-derby "enforcer" "${ENF} (database-incorporati)" "DATABASE-INCORPORATO-VIETATO" "Found Banned Dependency: org.apache.derby:derby" "@ carddemo-batch" -- validate

mut_repo carddemo-domain
mut_dip carddemo-domain transitiva
atteso_fallimento db-hsqldb-transitivo "enforcer, via prova-transitiva" "${ENF} (database-incorporati)" "DATABASE-INCORPORATO-VIETATO" "Found Banned Dependency: org.hsqldb:hsqldb" "prova-transitiva" "@ carddemo-domain" -- validate

# ---- ArchUnit ----
mut_dip carddemo-online online-batch
mut_java carddemo-online archunit-online-usa-batch ProvaRegole
atteso_fallimento archunit-online-usa-batch "ArchUnit" "ArchitetturaTest" "Architecture Violation" "ProvaRegole" "online" -- verify -Denforcer.skip=true -Dtest=ArchitetturaTest -Dsurefire.failIfNoSpecifiedTests=false

# controprova lecita: online usa domain, deve passare e la classe deve essere compilata
mut_java carddemo-domain archunit-dominio ProvaDominio
mut_java carddemo-online archunit-online-usa-domain ProvaRegole
start="${SECONDS}"
rc=0
mvn_run "${WORK}/archunit-online-usa-domain.log" "${ESEC_BASE[@]}" || rc=$?
if [ "${rc}" -eq 0 ] \
   && [ -f "${ROOT}/carddemo-online/target/classes/${PKG_DIR}/online/ProvaRegole.class" ] \
   && grep -qF "Tests run: 2, Failures: 0, Errors: 0, Skipped: 0, Time elapsed" "${WORK}/archunit-online-usa-domain.log"; then
  record archunit-online-usa-domain OK "${rc}" "$((SECONDS - start))" "controprova lecita: online usa domain, classe compilata e analizzata"
else
  record archunit-online-usa-domain ERRORE "${rc}" "$((SECONDS - start))" "la controprova lecita doveva passare"
fi
ripristina

# ---- tipi in virgola mobile e var (Checkstyle) ----
tipo() { # nome modulo file marcatore [classe]
  mut_java "$2" "$3" ProvaRegole
  atteso_fallimento "$1" "checkstyle" "${CHK}" "$4" "ProvaRegole.java" "@ $2" -- validate
}
tipo tipi-double-campo carddemo-domain campo-double FP-VIETATO
tipo tipi-double-parametro carddemo-loader parametro-double FP-VIETATO
tipo tipi-double-ritorno carddemo-online ritorno-double FP-VIETATO
tipo tipi-double-locale carddemo-batch locale-double FP-VIETATO
tipo tipi-double-qualificato carddemo-domain double-qualificato FP-VIETATO
tipo tipi-float-array carddemo-loader array-float FP-VIETATO
tipo tipi-lista-double carddemo-online lista-double FP-VIETATO
tipo tipi-cast-double carddemo-batch cast-double FP-VIETATO
tipo tipi-var carddemo-domain var-locale VAR-VIETATO
tipo tipi-letterale-decimale carddemo-loader letterale-decimale FP-VIETATO
tipo tipi-letterale-esponente carddemo-online letterale-esponente FP-VIETATO
tipo tipi-letterale-float carddemo-batch letterale-float FP-VIETATO

# ---- cancello disattivato: la corsa di base deve accorgersene ----
cancello() { # nome descrizione
  local nome="$1" start="${SECONDS}" rc=0 mancanti
  mvn_run "${WORK}/${nome}.log" "${ESEC_BASE[@]}" || rc=$?
  if [ "${rc}" -ne 0 ]; then
    record "${nome}" "ERRORE" "${rc}" "$((SECONDS - start))" "Maven doveva riuscire (e' il controllo di base a doversi accorgere)"
  elif mancanti="$(controlla_base "${WORK}/${nome}.log")"; then
    record "${nome}" "NON-RILEVATO" "${rc}" "$((SECONDS - start))" "controllo disattivato ma la corsa di base e' ancora completa"
  else
    record "${nome}" "OK" 1 "$((SECONDS - start))" "$2: ${mancanti//$'\n'/;}"
  fi
  ripristina
}
mut_skip . '<fail>true</fail>' '              <skip>true</skip>'
cancello cancello-skip-enforcer-database "enforcer database in skip"
mut_skip carddemo-domain '<fail>true</fail>' '              <skip>true</skip>'
cancello cancello-skip-enforcer-archi "enforcer archi in skip"
mut_skip carddemo-domain '<artifactId>maven-checkstyle-plugin</artifactId>' '        <configuration><skip>true</skip></configuration>'
cancello cancello-skip-checkstyle "checkstyle in skip"
mut_senza_blocco carddemo-loader plugin maven-checkstyle-plugin
cancello cancello-checkstyle-rimosso "checkstyle rimosso dal modulo"
mut_senza_blocco carddemo-batch plugin maven-enforcer-plugin
cancello cancello-enforcer-archi-rimosso "enforcer archi rimosso dal modulo"
mut_senza_file carddemo-parity/src/test/java/io/github/ltoscano/carddemo/parity/ArchitetturaTest.java
cancello cancello-archunit-rimosso "test ArchUnit rimosso"

echo
echo "== riepilogo"
printf '%-36s %-13s %-7s %-8s %s\n' caso esito codice secondi motivo
for r in "${RESULTS[@]}"; do
  IFS='|' read -r n e c d m <<<"${r}"
  printf '%-36s %-13s %-7s %-8s %s\n' "${n}" "${e}" "${c}" "${d}" "${m}"
done
[ "${FAILED}" -eq 0 ] || { echo "ERRORE: almeno un caso non ha dato l'esito atteso" >&2; exit 1; }
