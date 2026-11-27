# Ambiente fissato dell'oracle (incluso con `. /oracle/ambiente.sh` DENTRO il container da
# oracle/build/compile.sh e da oracle/esegui.sh).
#
# Ogni invocazione di cobc e ogni esecuzione di un programma compilato parte da `env -i` seguito da
# queste e sole variabili: l'ambiente ereditato (dal container, da docker run -e, da uno script che fa
# export) non arriva mai al compilatore ne' al runtime. Restano quindi assenti tutte le variabili che
# GnuCOBOL 3.2 legge, tra cui COB_CONFIG_DIR, COB_COPY_DIR, COBCPY, COB_CC, COB_CFLAGS, COB_LDFLAGS,
# COB_LIBS, COB_RUNTIME_CONFIG, COB_PRE_LOAD, COB_FILE_PATH, COB_VARSEQ_FORMAT ... (elenco completo nel README),
# e le variabili di libc come TZ, LANG e LC_*: per queste vale LC_ALL=C.
# Nessun valore puo' contenere spazi (le liste sono separate da spazi).

# Compilatore: solo percorso dei comandi, cartella home e localizzazione C.
AMBIENTE_COBC="PATH=/usr/bin:/bin HOME=/tmp LC_ALL=C"

# Runtime dei programmi: come sopra, piu' la cartella dei moduli richiamati con CALL. Gli artefatti sono
# sempre montati in /oracle-bin. Le variabili DD_<nome> dei file si aggiungono una per una, per nome,
# solo quelle chieste esplicitamente a esegui.sh con --dd.
AMBIENTE_RUN="PATH=/usr/bin:/bin HOME=/tmp LC_ALL=C COB_LIBRARY_PATH=/oracle-bin"
