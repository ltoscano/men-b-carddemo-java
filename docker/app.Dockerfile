# Immagine di un'applicazione CardDemo (online o batch), scelta con l'argomento MODULE.
# Build multi-stage: il jar si compila qui dentro (nessun jar costruito sull'host), poi
# solo il jar eseguibile passa nell'immagine finale, che gira come utente non-root.
# Immagini di base fissate per tag e digest (verificati su Docker Hub il 27 nov 2026).

FROM maven:3.9.16-eclipse-temurin-21@sha256:99e61abcff91a9b1333463bd8451fb18495d6eba9250ac66a338b518f8278320 AS build
ARG MODULE
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
WORKDIR /build
COPY pom.xml ./
COPY carddemo-domain carddemo-domain
COPY carddemo-loader carddemo-loader
COPY carddemo-online carddemo-online
COPY carddemo-batch carddemo-batch
COPY carddemo-parity carddemo-parity
# Stessa build di ./verify.sh, limitata al modulo e alle sue dipendenze, test compresi.
RUN --mount=type=cache,target=/root/.m2,id=menb-carddemo-m2,sharing=locked \
    case "${MODULE:-}" in online|batch) ;; *) echo "MODULE deve essere online o batch, non '${MODULE:-}'" >&2; exit 1;; esac; \
    mvn -B -pl "carddemo-${MODULE}" -am package </dev/null; \
    shopt -s nullglob; \
    jars=("carddemo-${MODULE}"/target/*-exec.jar); \
    if [ "${#jars[@]}" -ne 1 ]; then echo "attesi esattamente 1 jar eseguibile, trovati ${#jars[@]}" >&2; exit 1; fi; \
    cp "${jars[0]}" /build/app.jar

FROM eclipse-temurin:21.0.13.1_2-jre-alpine-3.24@sha256:5d7689f47d670aca766b9503a70bccc2d73b4eb9221ae8f714ae958313c4ce70
RUN addgroup -S -g 10001 carddemo && adduser -S -D -H -u 10001 -G carddemo carddemo
WORKDIR /app
# Il jar resta di proprieta' di root: l'utente dell'applicazione puo' leggerlo, non modificarlo.
COPY --from=build /build/app.jar /app/app.jar
USER 10001:10001
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
