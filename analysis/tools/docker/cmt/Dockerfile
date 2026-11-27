# cobol-migration-toolkit 0.8.0 (Apache-2.0), installato dall'archivio del tag v0.8.0 (commit 2e2a9e0fadf9a19a4fc6f974d9f684bc03b4e7d6).
FROM python:3.12-slim-trixie@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b
RUN pip install --no-cache-dir "https://github.com/makedirectory/cobol-migration-toolkit/archive/2e2a9e0fadf9a19a4fc6f974d9f684bc03b4e7d6.tar.gz"
RUN useradd -m -u 10001 tool
USER tool
ENTRYPOINT ["cobol-migrate"]
