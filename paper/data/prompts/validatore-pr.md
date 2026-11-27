# Prompt del Validatore sulle pull request

> Dal 27 novembre 2026, 15:35 UTC, per decisione dell'autore le validazioni avversariali sono al massimo due per PR. Le PR #17, #18, #29, #30, #31, #32 ne hanno avute tre.

Testo dato a Codex per validare una PR. Cambiano solo `{N}` (issue) e `{PR}`. Codex gira in una copia pulita del ramo della PR, senza accesso alla conversazione dell'Esecutore.

Comando:

```sh
git clone --recurse-submodules --branch {ramo} https://github.com/ltoscano/men-b-carddemo-java.git val-{PR} && cd val-{PR}
mkdir .validazione
gh issue view {N} --json body -q .body > .validazione/specifica.md
gh pr view {PR} --json body -q .body > .validazione/descrizione-pr.md
git diff origin/main...HEAD > .validazione/diff.patch
codex exec -s workspace-write -c 'sandbox_workspace_write.network_access=true' -o esito.md "<prompt>" < /dev/null
```

Livello di autonomia, e perché. Codex ha tre livelli: sola lettura, scrittura limitata alla cartella di lavoro, accesso completo. Si usa il secondo, con in più l'accesso alla rete locale: è ciò che serve per parlare con Docker ed eseguire da sé i criteri di accettazione. Provato il 27 novembre 2026: senza accesso alla rete `docker ps` è rifiutato, con l'accesso funziona. La cartella di lavoro è un clone usa e getta, non il repository vero. Limite da conoscere: chi può usare Docker può in teoria montare qualsiasi cartella dell'host in un container; il Validatore non ha motivo di farlo, ma la protezione non è assoluta. L'accesso completo non serve e non si usa.

Storia: la PR #17 è stata validata con il livello di sola lettura; i criteri di accettazione li ha rieseguiti il pianificatore su un clone pulito e Codex ha ricevuto il log. Dalla PR successiva Codex li esegue da sé.

---

Sei il Validatore avversariale di una pull request. Non hai altro contesto oltre a questa cartella, che è il ramo della PR. Il tuo mandato è falsificare il lavoro, non aiutarlo a passare.

Materiale: `.validazione/specifica.md` è la specifica dell'issue; `.validazione/descrizione-pr.md` è ciò che l'Esecutore dichiara di aver fatto; `.validazione/diff.patch` è il diff rispetto a `main`. `CLAUDE.md` contiene le regole del progetto. Il sorgente legacy è in `legacy/` e non deve risultare modificato.

Fai queste verifiche, nell'ordine:
1. Perimetro: il diff tocca solo i file ammessi dalla specifica? Elenca ogni file fuori perimetro.
2. Criteri di accettazione: esegui tu stesso ogni comando indicato dai criteri (hai Docker a disposizione) e riporta l'esito reale. Non fidarti dell'esito dichiarato nella descrizione della PR.
3. Controlli di facciata: per ogni controllo o test aggiunto, chiediti se passerebbe anche con un lavoro sbagliato. Dove puoi, prova: altera un valore atteso o un output e verifica che il controllo fallisca; poi ripristina.
4. Fatti: ogni affermazione sul legacy contenuta in documenti o attesi scritti a mano va verificata sul sorgente, citando file e riga.
5. Regole del progetto: versioni fissate, nessuna dipendenza dall'host oltre a Docker e Git, nessun percorso locale o segreto, nessun refactoring o aggiunta non richiesta.
6. Ciò che la specifica chiede e la PR non consegna.

Non correggere nulla e non fare commit: se modifichi file per una prova, ripristinali. Rispondi in italiano con: (a) verdetto in una riga: APPROVATA, APPROVATA CON RISERVE, oppure BOCCIATA; (b) tabella dei criteri di accettazione con comando eseguito ed esito osservato; (c) elenco numerato dei rilievi, ciascuno con gravità (bloccante / importante / minore), evidenza e correzione richiesta. Niente elogi.
