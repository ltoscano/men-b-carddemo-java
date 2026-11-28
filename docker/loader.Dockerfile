# Immagine del caricatore dei conti (issue #60). Stessa build multi-stage di app.Dockerfile, per
# il modulo carddemo-loader; in piu' l'immagine finale contiene il file dei conti che legge
# l'oracle, analysis/oracle-dati/out/ACCTFILE.rec (50 record di 300 byte, issue #53), copiato qui
# in modo esplicito: e' l'argomento predefinito del caricatore. Immagini di base fissate per tag e
# digest, le stesse di app.Dockerfile.

FROM maven:3.9.16-eclipse-temurin-21@sha256:99e61abcff91a9b1333463bd8451fb18495d6eba9250ac66a338b518f8278320 AS build
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
WORKDIR /build
COPY pom.xml ./
# Configurazione dei controlli di #26 (Checkstyle gira nella fase validate di mvn package).
COPY quality/regole quality/regole
COPY carddemo-domain carddemo-domain
COPY carddemo-loader carddemo-loader
COPY carddemo-online carddemo-online
COPY carddemo-batch carddemo-batch
COPY carddemo-parity carddemo-parity
# Stessa build di ./verify.sh, limitata al modulo e alle sue dipendenze, test compresi.
RUN --mount=type=cache,target=/root/.m2,id=menb-carddemo-m2,sharing=locked \
    mvn -B -pl carddemo-loader -am package </dev/null; \
    shopt -s nullglob; \
    jars=(carddemo-loader/target/*-exec.jar); \
    if [ "${#jars[@]}" -ne 1 ]; then echo "attesi esattamente 1 jar eseguibile, trovati ${#jars[@]}" >&2; exit 1; fi; \
    cp "${jars[0]}" /build/app.jar

FROM eclipse-temurin:21.0.13.1_2-jre-alpine-3.24@sha256:5d7689f47d670aca766b9503a70bccc2d73b4eb9221ae8f714ae958313c4ce70
RUN addgroup -S -g 10001 carddemo && adduser -S -D -H -u 10001 -G carddemo carddemo
WORKDIR /app
# Jar e file dei conti restano di proprieta' di root: l'utente dell'applicazione li legge, non li
# modifica.
COPY --from=build /build/app.jar /app/app.jar
COPY analysis/oracle-dati/out/ACCTFILE.rec /app/dati/ACCTFILE.rec
USER 10001:10001
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
CMD ["/app/dati/ACCTFILE.rec"]
