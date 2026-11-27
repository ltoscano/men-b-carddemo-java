# Immagine dell'oracle: GnuCOBOL 3.2 con il runtime libcob e il gestore dei file indicizzati fissati.
#
# - Base: Debian trixie-slim fissata per digest (la stessa di analysis/tools/docker/gnucobol, cosi' il
#   compilatore e' lo stesso con cui #1 ha verificato che gli 11 programmi compilano).
# - GnuCOBOL: pacchetti Debian gnucobol3 / libcob4t64 / libcob4-dev alla versione 3.2-3 (cobc 3.2.0).
# - Backend dei file indicizzati (ISAM): Berkeley DB, quello con cui Debian compila libcob
#   ("indexed file handler : BDB" in `cobc --info`), fissato alla versione libdb5.3t64 5.3.28+dfsg2-9.
#   I file sequenziali usano il gestore interno di libcob.
# - gcc e libc6-dev servono a cobc per produrre eseguibili e moduli.
# Le versioni effettive (cobc --info, pacchetti, configurazione di runtime) sono registrate a ogni build
# in oracle/build/out/ambiente.txt e verificate da oracle/build/check.sh.
FROM debian:trixie-slim@sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      gnucobol3=3.2-3 libcob4t64=3.2-3 libcob4-dev=3.2-3 libdb5.3t64=5.3.28+dfsg2-9 \
      gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*
# Nessuna variabile di runtime di libcob e' impostata nell'immagine: valgono i default di
# /usr/share/gnucobol/config/runtime.cfg. Gli script impostano solo COB_LIBRARY_PATH (dove cercare i
# moduli richiamati con CALL) e, per ogni file, la variabile DD_<nome> (vedi oracle/README.md).
RUN useradd -m -u 10001 oracle
USER oracle
WORKDIR /tmp
