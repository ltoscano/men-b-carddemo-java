# GnuCOBOL 3.2 dal pacchetto Debian gnucobol3 (versione fissata); base fissata per digest.
FROM debian:trixie-slim@sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends gnucobol3=3.2-3 gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 10001 tool
USER tool
ENTRYPOINT ["cobc"]
