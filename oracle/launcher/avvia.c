/*
 * Avviatore dell'oracle: e' il main() di ogni eseguibile (collegato insieme al programma COBOL).
 * Fa la parte che su z/OS fa il sistema per un passo `EXEC PGM=<programma>,PARM='<testo>'`:
 * costruisce l'area del PARM e chiama il programma passandogliela come primo (e unico) argomento.
 *
 * Area del PARM (come su z/OS):
 *   byte 0-1  lunghezza del testo, intero binario senza segno di 2 byte in ordine big-endian
 *             (lo stesso ordine che i programmi compilati con -std=ibm, binary-byteorder big-endian,
 *             si aspettano per un campo PIC S9(04) COMP: vedi oracle/cobc.opts e oracle/README.md);
 *   byte 2-   il testo, lungo quanto indicato (al massimo 100 caratteri, il limite del PARM del JCL).
 * Oltre la lunghezza l'area e' riempita con X'00' (su z/OS quel contenuto non e' definito).
 *
 * Uso:  <eseguibile> [PARM]     senza argomento la lunghezza e' 0, come un passo senza PARM=.
 * Il codice di uscita e' il RETURN-CODE del programma (o quello di STOP RUN / dello stub CEE3ABD).
 *
 * Compilazione (oracle/build/compile.sh): cobc -c <opzioni> <programma>.cbl, poi
 *   cobc -x -A -DMENB_ENTRY=<programma> -o <programma> avvia.c <programma>.o
 * MENB_ORDINE_INVERTITO esiste solo per la prova negativa di oracle/avviatore/check.sh: scrive la
 * lunghezza in ordine little-endian e il controllo deve accorgersene. Non si usa mai nella build.
 */
#include <stdio.h>
#include <string.h>
#include <libcob.h>

#ifndef MENB_ENTRY
#error "MENB_ENTRY (nome del programma da avviare) non definito"
#endif

/* Punto d'ingresso C generato da cobc per il programma (PROGRAM-ID). I programmi senza USING ignorano
   l'argomento, come su z/OS ignorano l'area del PARM. */
extern int MENB_ENTRY (unsigned char *);

#define MENB_PARM_MAX 100

int
main (int argc, char **argv)
{
	static unsigned char area[2 + MENB_PARM_MAX];
	size_t len = 0;
	int ret;

	if (argc > 2) {
		fprintf (stderr, "avvia: uso: %s [PARM]\n", argv[0]);
		return 2;
	}
	if (argc == 2) {
		len = strlen (argv[1]);
	}
	if (len > MENB_PARM_MAX) {
		fprintf (stderr, "avvia: PARM di %lu caratteri, il massimo e' %d\n",
			 (unsigned long)len, MENB_PARM_MAX);
		return 2;
	}
	memset (area, 0x00, sizeof (area));
#ifdef MENB_ORDINE_INVERTITO
	area[0] = (unsigned char)(len & 0xFF);
	area[1] = (unsigned char)((len >> 8) & 0xFF);
#else
	area[0] = (unsigned char)((len >> 8) & 0xFF);
	area[1] = (unsigned char)(len & 0xFF);
#endif
	if (len > 0) {
		memcpy (area + 2, argv[1], len);
	}

	cob_init (0, NULL);
	/* Chiamata diretta al programma collegato in questo eseguibile (niente ricerca per nome nei moduli),
	   con il numero di argomenti impostato come fa cobc per una CALL statica con un argomento. */
	cob_get_global_ptr ()->cob_call_params = 1;
	ret = MENB_ENTRY (area);
	cob_stop_run (ret);
}
