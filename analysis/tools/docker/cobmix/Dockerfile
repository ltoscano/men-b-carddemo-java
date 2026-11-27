# cobmix 0.1.2 da PyPI (ultima versione disponibile; riserva per la capacita' "grafi COPY e CALL").
# La 0.1.0 indicata dal README e' stata provata prima su COBIL00C e COACTUPC con lo stesso esito (nessuna riga negli archi).
FROM python:3.12-slim-trixie@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b
RUN pip install --no-cache-dir cobmix==0.1.2
RUN useradd -m -u 10001 tool
USER tool
ENTRYPOINT ["cobmix"]
