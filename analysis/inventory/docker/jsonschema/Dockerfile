# Validatore JSON Schema (libreria jsonschema, MIT) per graph.json: strumento esistente, nessun validatore scritto in proprio.
# Immagine propria dell'issue #2 (nome menb-inventory-*); non tocca le immagini condivise menb-analysis-*.
FROM python:3.12-slim-trixie@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b
RUN pip install --no-cache-dir jsonschema==4.23.0
RUN useradd -m -u 10001 tool
USER tool
ENTRYPOINT ["python", "-I", "-c", "import json,sys,jsonschema; s=json.load(open(sys.argv[1])); g=json.load(open(sys.argv[2])); jsonschema.Draft202012Validator.check_schema(s); errs=sorted(jsonschema.Draft202012Validator(s).iter_errors(g), key=lambda e: list(map(str,e.absolute_path))); [print('SCHEMA:', '/'.join(map(str,e.absolute_path)), e.message[:200]) for e in errs[:20]]; print('schema valido' if not errs else f'{len(errs)} errori di schema'); sys.exit(1 if errs else 0)"]
