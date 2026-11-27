# Estrattore dei blocchi EXEC CICS (issue #22): lo stesso ProLeap COBOL parser (MIT, commit d1bfe75) gia' adottato in #1 e usato
# in #2 per le COPY, compilato con gli stessi passi e le stesse basi per digest di analysis/tools/docker/proleap (la cache dei
# layer di Docker li condivide), piu' una colla Java minima (CicsLister.java) che usa la regola execCicsStatement del suo
# preprocessore. Immagine propria (nome menb-inventory-cics-*): l'immagine condivisa menb-analysis-proleap non si tocca.
FROM maven:3.9-eclipse-temurin-21@sha256:99e61abcff91a9b1333463bd8451fb18495d6eba9250ac66a338b518f8278320 AS build
ADD --checksum=sha256:9c37c3ade2ece0c84eabb46fdcefc7ba5c6e45ac94cb4a4bee9ef1d0085d2749 \
    https://github.com/uwol/proleap-cobol-parser/archive/d1bfe75bdd6d480f70c74c6345bcc02610ac30d3.tar.gz /tmp/proleap.tgz
RUN mkdir /src && tar -xzf /tmp/proleap.tgz -C /src --strip-components=1
WORKDIR /src
RUN mvn -q -B -DskipTests -Dmaven.javadoc.skip=true package dependency:copy-dependencies -DincludeScope=runtime
COPY CicsLister.java /glue/CicsLister.java
RUN javac -d /glue -cp "/src/target/classes:/src/target/dependency/*" /glue/CicsLister.java

FROM eclipse-temurin:21-jre@sha256:d77e090ae1f6970c047b443c6f0a6c1358b0426d44432bb5a7753408cd43de0d
COPY --from=build /src/target/classes /opt/proleap/classes
COPY --from=build /src/target/dependency /opt/proleap/lib
COPY --from=build /glue/*.class /opt/proleap/cics/
RUN useradd -m -u 10001 tool
USER tool
ENTRYPOINT ["java", "-cp", "/opt/proleap/cics:/opt/proleap/classes:/opt/proleap/lib/*", "CicsLister"]
