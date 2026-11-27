import io.proleap.cobol.CobolPreprocessorBaseListener;
import io.proleap.cobol.CobolPreprocessorLexer;
import io.proleap.cobol.CobolPreprocessorParser;
import io.proleap.cobol.asg.params.CobolParserParams;
import io.proleap.cobol.asg.params.impl.CobolParserParamsImpl;
import io.proleap.cobol.preprocessor.CobolPreprocessor.CobolSourceFormatEnum;
import io.proleap.cobol.preprocessor.sub.CobolLine;
import io.proleap.cobol.preprocessor.sub.line.reader.impl.CobolLineReaderImpl;
import io.proleap.cobol.preprocessor.sub.line.rewriter.impl.CobolCommentEntriesMarkerImpl;
import io.proleap.cobol.preprocessor.sub.line.rewriter.impl.CobolInlineCommentEntriesNormalizerImpl;
import io.proleap.cobol.preprocessor.sub.line.rewriter.impl.CobolLineIndicatorProcessorImpl;
import io.proleap.cobol.preprocessor.sub.line.writer.impl.CobolLineWriterImpl;

import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import org.antlr.v4.runtime.BaseErrorListener;
import org.antlr.v4.runtime.CharStream;
import org.antlr.v4.runtime.CharStreams;
import org.antlr.v4.runtime.CommonTokenStream;
import org.antlr.v4.runtime.DefaultErrorStrategy;
import org.antlr.v4.runtime.Parser;
import org.antlr.v4.runtime.RecognitionException;
import org.antlr.v4.runtime.Recognizer;
import org.antlr.v4.runtime.Token;
import org.antlr.v4.runtime.misc.Interval;
import org.antlr.v4.runtime.tree.ParseTreeWalker;

/**
 * Colla minima (nessun parser scritto qui): usa le classi di ProLeap per normalizzare le righe COBOL a formato
 * fisso (colonne 8-72, indicatore in colonna 7, commenti) e il parser del suo preprocessore, che ha la regola
 * execCicsStatement : EXEC CICS charData END_EXEC DOT? . Per ogni blocco scrive riga e colonna di EXEC, riga di
 * END-EXEC e il testo originale tra CICS e END-EXEC (spazi compresi, preso dal flusso di caratteri, non dai token).
 *
 * Uso: CicsLister RADICE ELENCO CARTELLA-USCITA   (ELENCO: un percorso relativo a RADICE per riga)
 *      CicsLister --regole                       (nomi delle regole del preprocessore che riguardano CICS)
 * Per ogni file scrive CARTELLA-USCITA/<percorso con '/' sostituito da '_'>.tsv:
 *   intestazione "riga<TAB>riga_fine<TAB>colonna<TAB>testo", una riga per blocco, chiusura
 *   "#fine<TAB><n blocchi><TAB><errori di sintassi><TAB><riga del primo errore, 0 se nessuno><TAB><riprese dopo un errore>
 *   <TAB><blocchi EXEC CICS incompleti>".
 * Nel testo: '\' -> "\\", fine riga -> "\n", ritorno carrello -> "\r", TAB -> "\t".
 */
public class CicsLister {
    static String esc(String s) {
        StringBuilder b = new StringBuilder();
        for (char c : s.toCharArray()) {
            switch (c) {
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default: b.append(c);
            }
        }
        return b.toString();
    }

    static List<String> list(Path file) throws Exception {
        String code = Files.readString(file, StandardCharsets.ISO_8859_1);
        CobolParserParams params = new CobolParserParamsImpl();
        params.setFormat(CobolSourceFormatEnum.FIXED);
        params.setCharset(StandardCharsets.ISO_8859_1);

        List<CobolLine> lines = new CobolLineReaderImpl().processLines(code, params);
        lines = new CobolLineIndicatorProcessorImpl().processLines(lines);
        lines = new CobolInlineCommentEntriesNormalizerImpl().processLines(lines);
        lines = new CobolCommentEntriesMarkerImpl().processLines(lines);
        String text = new CobolLineWriterImpl().serialize(lines);

        CharStream chars = CharStreams.fromString(text);
        CobolPreprocessorLexer lexer = new CobolPreprocessorLexer(chars);
        CommonTokenStream tokens = new CommonTokenStream(lexer);
        CobolPreprocessorParser parser = new CobolPreprocessorParser(tokens);
        final int[] errors = {0, 0};   // numero di errori, riga del primo
        parser.removeErrorListeners();
        parser.addErrorListener(new BaseErrorListener() {
            @Override
            public void syntaxError(Recognizer<?, ?> r, Object o, int line, int col, String msg, RecognitionException e) {
                if (errors[0]++ == 0) errors[1] = line;
            }
        });
        /*
         * Il preprocessore di ProLeap non conosce EXEC DLI (IMS): al primo errore la regola iniziale cattura l'eccezione,
         * il recupero standard consuma i token fino a EOF e i blocchi EXEC CICS successivi andrebbero persi. Qui il recupero
         * scarta un solo token e l'analisi riprende con una nuova invocazione della regola iniziale dal token successivo.
         * Gli errori sono contati e dichiarati nella chiusura della risposta; nessuna regola della grammatica cambia.
         */
        parser.setErrorHandler(new DefaultErrorStrategy() {
            @Override
            public void recover(Parser p, RecognitionException e) {
                if (p.getInputStream().LA(1) != Token.EOF) p.consume();
            }
        });

        List<String> rows = new ArrayList<>();
        final int[] incomplete = {0};
        CobolPreprocessorBaseListener listener = new CobolPreprocessorBaseListener() {
            @Override
            public void enterExecCicsStatement(CobolPreprocessorParser.ExecCicsStatementContext ctx) {
                if (ctx.exception != null || ctx.EXEC() == null || ctx.CICS() == null || ctx.END_EXEC() == null) {
                    incomplete[0]++;
                    return;
                }
                Token exec = ctx.EXEC().getSymbol();
                Token cics = ctx.CICS().getSymbol();
                Token end = ctx.END_EXEC().getSymbol();
                String body = chars.getText(Interval.of(cics.getStopIndex() + 1, end.getStartIndex() - 1));
                rows.add(exec.getLine() + "\t" + end.getLine() + "\t" + (exec.getCharPositionInLine() + 1) + "\t" + esc(body));
            }
        };
        int resumes = 0;
        while (true) {
            int before = tokens.index();
            CobolPreprocessorParser.StartRuleContext start = parser.startRule();
            new ParseTreeWalker().walk(listener, start);
            if (tokens.LA(1) == Token.EOF) break;
            resumes++;
            if (tokens.index() == before) tokens.consume();
        }
        rows.add("#fine\t" + rows.size() + "\t" + errors[0] + "\t" + errors[1] + "\t" + resumes + "\t" + incomplete[0]);
        return rows;
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 1 && args[0].equals("--regole")) {
            for (String r : CobolPreprocessorParser.ruleNames) {
                if (r.toLowerCase().contains("cics")) System.out.println("regola\t" + r);
            }
            for (String t : new String[] {"EXEC", "CICS", "END_EXEC"}) {
                int found = -1;
                for (int i = 0; i < CobolPreprocessorLexer.VOCABULARY.getMaxTokenType() + 1; i++) {
                    if (t.equals(CobolPreprocessorLexer.VOCABULARY.getSymbolicName(i))) found = i;
                }
                System.out.println("token\t" + t + "\t" + (found >= 0 ? "presente" : "assente"));
            }
            return;
        }
        Path root = Path.of(args[0]);
        Path out = Path.of(args[2]);
        int n = 0;
        for (String rel : Files.readAllLines(Path.of(args[1]), StandardCharsets.UTF_8)) {
            if (rel.isEmpty()) continue;
            List<String> rows = list(root.resolve(rel));
            try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out.resolve(rel.replace('/', '_') + ".tsv"), StandardCharsets.UTF_8))) {
                w.print("riga\triga_fine\tcolonna\ttesto\n");
                for (String r : rows) w.print(r + "\n");
            }
            n++;
        }
        System.out.println("file analizzati\t" + n);
    }
}
