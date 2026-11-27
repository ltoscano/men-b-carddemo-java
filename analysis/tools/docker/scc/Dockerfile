# scc 4.1.0 (MIT) da binario ufficiale di GitHub Releases, verificato con SHA-256.
FROM debian:trixie-slim@sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0
ARG SCC_VERSION=4.1.0
ARG SCC_SHA256_ARM64=6e0d2a1f8d3540ba7df185477dec40bb7340f1b214bfd303147de5cad2bd7b8b
ARG SCC_SHA256_AMD64=c7328436d3027f4357d3d7853f7dc3ac2bbcb4ca08f1adad91a27c593884079b
ARG TARGETARCH
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl \
 && case "$TARGETARCH" in \
      arm64) A=arm64;  S=$SCC_SHA256_ARM64 ;; \
      amd64) A=x86_64; S=$SCC_SHA256_AMD64 ;; \
      *) echo "architettura non supportata: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/scc.tgz "https://github.com/boyter/scc/releases/download/v${SCC_VERSION}/scc_Linux_${A}.tar.gz" \
 && echo "$S  /tmp/scc.tgz" | sha256sum -c - \
 && tar -xzf /tmp/scc.tgz -C /usr/local/bin scc \
 && rm /tmp/scc.tgz \
 && apt-get purge -y -qq curl && apt-get autoremove -y -qq && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 10001 tool
USER tool
ENTRYPOINT ["scc"]
