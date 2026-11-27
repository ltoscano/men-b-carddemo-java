APPROVATA

Validato lo SHA `afdb94f`.

| Rilievo del giro 1 | Stato | Comando/prova | Esito |
|---|---|---|---|
| 1. Cifre alternative del segno | **Chiuso** | `./analysis/run.sh data-codec --check` nella copia privata mutata; `python /e/audit.py` in container | Scambio 0/1 respinto con uscita **1**: `1234.50` atteso, `1234.51` ottenuto, in entrambi i profili. Tutte le **180 rimozioni individuali** sono rilevate: 30 byte × 3 varianti × 2 profili. |
| 2. Campi incompleti | **Chiuso** | `python /e/audit.py` in container | **610 rifiuti** con `CampoIncompleto`: 61 varianti, entrambi i profili, cinque ingressi errati. Nessun risultato o valore restituito. |
| 3. Riempimento packed z/OS | **Chiuso** | Decodifica di `10 00 00 01 23 45 6C`; verifica dei 16 riempimenti | z/OS: **`non-valido`, valore assente**, byte conservati. Oracle: riempimenti 0–9 validi e ignorati nel valore; A–F non validi, coerentemente con le osservazioni. |
| 4. Dettaglio delle prove negative | **Chiuso** | `./analysis/run.sh data-codec --check` e controllo del log | Riportate individualmente **187 prove della colla**, comprese le 139 per variante, e **60 altre prove negative**, con nome e diagnosi. |

La nuova fonte [IBM APAR PI96135](https://www.ibm.com/support/pages/apar/PI96135) sostiene esplicitamente il requisito dei quattro bit iniziali nulli per la validità del packed a precisione pari.

Sul diff di correzione:

- I casi esaustivi confrontano stato e valore con `attesa_esaustiva`, usando tabelle separate dalla decodifica della colla. Sul codec la scala proviene da `geometria`; i vettori fissi verificano anche quella. Non viene usato il risultato della decodifica come atteso.
- Ho confrontato indipendentemente tutte le **218 righe di decodifica nuove o modificate**. La trascrizione z/OS coincide con [ICU IBM 037](https://raw.githubusercontent.com/unicode-org/icu/main/icu4c/source/data/mappings/ibm-37_P100-1995.ucm) su **256/256 byte**, compresi `5F AD B0 BA BB BD`.
- Una riga spezzata e un valore numerico esadecimale troncato sono respinti dal parser. Il troncamento dell’ultimo campo passa il parser, ma il confronto integrale con il golden lo rileva: **uscita 1** riprodotta.
- L’atteso `F0 F0 F0 F5` per `MOVE` di −5 in `9(4)` è sostenuto dal [Language Reference IBM 6.4, “Elementary move rules”, pagina 404](https://publibfp.dhe.ibm.com/epubs/pdf/igy6lr40.pdf): verso un ricevente numerico senza segno si usa il valore assoluto.
- I tre casi numerici senza atteso `MOVE` sono dichiarati separatamente. Gli attesi di **rifiuto della colla sono presenti**; non sono casi di validità indeterminata.

**Rilievi nuovi: nessuno.** Non ho riprodotto nuovi falsi verdi né regole di codifica errate accettate come giuste.

| Comando richiesto | Esito |
|---|---:|
| `./analysis/run.sh data-codec --check` | **0** |
| `./analysis/run.sh --all --check` | **0** |
| `./oracle/run.sh --all --check` | **0** |

Il diff comprende **26 file, tutti ammessi**. `oracle/` e `legacy/` sono identici a `origin/main`; il submodule è pulito. Stato finale invariato: soltanto `?? .validazione/`, già presente inizialmente. Nessuna correzione o commit. Risorse Docker `menb-val47b-` rimosse; nessun residuo.

Evidenze: [audit indipendente](file locale del Validatore, non conservato), [controesempio mutato](file locale del Validatore, non conservato), [controllo completo delle analisi](file locale del Validatore, non conservato), [controllo oracle](file locale del Validatore, non conservato).