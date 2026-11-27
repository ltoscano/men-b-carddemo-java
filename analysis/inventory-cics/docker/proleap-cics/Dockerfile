# Estrattore dei blocchi EXEC CICS (issue #22): lo stesso ProLeap COBOL parser (MIT, commit d1bfe75) gia' adottato in #1 e
# usato in #2 per le COPY, preso dall'immagine condivisa menb-analysis-proleap:d1bfe75 (costruita da analysis/tools/docker/proleap,
# basi con digest fissato), piu' una colla Java minima (CicsLister.java) che usa la regola execCicsStatement del suo preprocessore.
# L'immagine condivisa e' solo letta: qui si costruisce un'immagine propria (nome menb-inventory-cics-*).
FROM maven:3.9-eclipse-temurin-21@sha256:99e61abcff91a9b1333463bd8451fb18495d6eba9250ac66a338b518f8278320 AS build
COPY --from=menb-analysis-proleap:d1bfe75 /opt/proleap /opt/proleap
COPY CicsLister.java /glue/CicsLister.java
RUN javac -d /glue -cp "/opt/proleap/classes:/opt/proleap/lib/*" /glue/CicsLister.java

FROM menb-analysis-proleap:d1bfe75
COPY --from=build /glue/*.class /opt/proleap/cics/
ENTRYPOINT ["java", "-cp", "/opt/proleap/cics:/opt/proleap/classes:/opt/proleap/lib/*", "CicsLister"]
