# cb2xml 1.01.08 (LGPL-2.1) dal jar della release GitHub, verificato con SHA-256.
FROM eclipse-temurin:21-jre@sha256:d77e090ae1f6970c047b443c6f0a6c1358b0426d44432bb5a7753408cd43de0d
ARG CB2XML_VERSION=1.01.08
ARG CB2XML_SHA256=4d4fce7a9f590d2bbcd138a4eee4cfcafb40b4dcbe76d1f2f39b7085db5c81b2
RUN mkdir -p /opt/cb2xml
ADD --chmod=0644 --checksum=sha256:4d4fce7a9f590d2bbcd138a4eee4cfcafb40b4dcbe76d1f2f39b7085db5c81b2 \
    https://github.com/bmTas/cb2xml/releases/download/1.01.08/cb2xml.jar /opt/cb2xml/cb2xml.jar
RUN useradd -m -u 10001 tool
USER tool
ENTRYPOINT ["java", "-cp", "/opt/cb2xml/cb2xml.jar", "net.sf.cb2xml.Cb2Xml"]
