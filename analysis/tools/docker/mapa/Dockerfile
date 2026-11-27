# mapa (parser JCL, MIT): compilato dai sorgenti al commit fissato (nessun JCLParser.jar precompilato).
# Il Makefile del progetto prevede due passate: la prima ("make all") segnala errori per riferimenti
# incrociati tra classi, che "make mine" risolve. Le librerie ANTLR 4.13.2 e commons-cli 1.4 sono
# quelle incluse nel repository di mapa (stessa versione indicata dal suo README).
FROM eclipse-temurin:21-jdk@sha256:8ad118b146aa92da815b576441acd6b42b38236797ad0b6edc8c200b85bb0734 AS build
ADD --checksum=sha256:7ce2b8e2153d73a36d971e15a3c99edcbe30558172d95a38df962e8cb99bfecc \
    https://github.com/cschneid-the-elder/mapa/archive/d05705af310730c3e9aa848e824755e652618512.tar.gz /tmp/mapa.tgz
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends make \
 && mkdir /src && tar -xzf /tmp/mapa.tgz -C /src --strip-components=1
WORKDIR /src/jcl
RUN make init \
 && (make all >/tmp/all1.log 2>&1 || true) \
 && (make all >/tmp/all2.log 2>&1 || true) \
 && make mine >/tmp/mine.log 2>&1 \
 && test -f class/Demo01.class

FROM eclipse-temurin:21-jre@sha256:d77e090ae1f6970c047b443c6f0a6c1358b0426d44432bb5a7753408cd43de0d
COPY --from=build /src/jcl/class /opt/mapa/class
COPY --from=build /src/jcl/antlr-4.13.2-complete.jar /src/jcl/commons-cli-1.4.jar /opt/mapa/
RUN useradd -m -u 10001 tool
USER tool
ENTRYPOINT ["java", "-cp", "/opt/mapa/class:/opt/mapa/antlr-4.13.2-complete.jar:/opt/mapa/commons-cli-1.4.jar", "Demo01"]
