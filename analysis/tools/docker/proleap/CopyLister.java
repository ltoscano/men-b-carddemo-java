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

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import org.antlr.v4.runtime.CharStreams;
import org.antlr.v4.runtime.CommonTokenStream;
import org.antlr.v4.runtime.tree.ParseTreeWalker;

/**
 * Colla minima (nessun parser scritto qui): usa le classi di ProLeap per normalizzare le righe
 * COBOL a formato fisso e il parser del suo preprocessore per elencare le istruzioni COPY con
 * numero di riga e clausole REPLACING. Uso: CopyLister FILE.cbl
 */
public class CopyLister {
    /** Toglie i delimitatori pseudo-testo ==...== dal testo di una clausola. */
    static String strip(String t) {
        return t.startsWith("==") && t.endsWith("==") && t.length() >= 4 ? t.substring(2, t.length() - 2) : t;
    }

    public static void main(String[] args) throws Exception {
        String code = Files.readString(Path.of(args[0]), StandardCharsets.ISO_8859_1);
        CobolParserParams params = new CobolParserParamsImpl();
        params.setFormat(CobolSourceFormatEnum.FIXED);
        params.setCharset(StandardCharsets.ISO_8859_1);

        List<CobolLine> lines = new CobolLineReaderImpl().processLines(code, params);
        lines = new CobolLineIndicatorProcessorImpl().processLines(lines);
        lines = new CobolInlineCommentEntriesNormalizerImpl().processLines(lines);
        lines = new CobolCommentEntriesMarkerImpl().processLines(lines);
        String text = new CobolLineWriterImpl().serialize(lines);

        CobolPreprocessorLexer lexer = new CobolPreprocessorLexer(CharStreams.fromString(text));
        CommonTokenStream tokens = new CommonTokenStream(lexer);
        CobolPreprocessorParser parser = new CobolPreprocessorParser(tokens);
        CobolPreprocessorParser.StartRuleContext start = parser.startRule();

        System.out.println("riga\tcopybook\tsostituzioni");
        new ParseTreeWalker().walk(new CobolPreprocessorBaseListener() {
            @Override
            public void enterCopyStatement(CobolPreprocessorParser.CopyStatementContext ctx) {
                String name = ctx.copySource().getText().replace("'", "").replace("\"", "");
                StringBuilder repl = new StringBuilder();
                for (CobolPreprocessorParser.ReplacingPhraseContext rp : ctx.replacingPhrase()) {
                    for (CobolPreprocessorParser.ReplaceClauseContext rc : rp.replaceClause()) {
                        if (repl.length() > 0) repl.append(';');
                        repl.append(strip(rc.replaceable().getText())).append('=').append(strip(rc.replacement().getText()));
                    }
                }
                System.out.println(ctx.getStart().getLine() + "\t" + name + "\t" + repl);
            }
        }, start);
    }
}
