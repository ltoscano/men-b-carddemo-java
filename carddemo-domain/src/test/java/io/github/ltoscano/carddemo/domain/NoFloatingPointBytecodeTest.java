package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.io.InputStream;
import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.springframework.asm.ClassReader;
import org.springframework.asm.ClassVisitor;
import org.springframework.asm.FieldVisitor;
import org.springframework.asm.Handle;
import org.springframework.asm.Label;
import org.springframework.asm.MethodVisitor;
import org.springframework.asm.Opcodes;
import org.springframework.asm.SpringAsmInfo;

/**
 * No floating point in the compiled codec. The source rules of #26 read the text and do not see
 * the implicit types of expressions ({@code BigDecimal.valueOf(Math.pow(10, scale))} passes them),
 * so here every compiled production class of the package is inspected with ASM (the copy shipped
 * in spring-core): no float/double instruction, constant, field, signature, local variable, call or
 * type ({@code java.lang.Double}, {@code java.lang.Float}).
 */
class NoFloatingPointBytecodeTest {

    /** Opcodes that load, store, compute, convert, compare or return float or double values. */
    private static final Set<Integer> FLOATING_OPCODES = Set.of(
            Opcodes.FCONST_0, Opcodes.FCONST_1, Opcodes.FCONST_2, Opcodes.DCONST_0, Opcodes.DCONST_1,
            Opcodes.FLOAD, Opcodes.DLOAD, Opcodes.FALOAD, Opcodes.DALOAD, Opcodes.FSTORE, Opcodes.DSTORE,
            Opcodes.FASTORE, Opcodes.DASTORE, Opcodes.FADD, Opcodes.DADD, Opcodes.FSUB, Opcodes.DSUB,
            Opcodes.FMUL, Opcodes.DMUL, Opcodes.FDIV, Opcodes.DDIV, Opcodes.FREM, Opcodes.DREM, Opcodes.FNEG,
            Opcodes.DNEG, Opcodes.I2F, Opcodes.I2D, Opcodes.L2F, Opcodes.L2D, Opcodes.F2I, Opcodes.F2L,
            Opcodes.F2D, Opcodes.D2I, Opcodes.D2L, Opcodes.D2F, Opcodes.FCMPL, Opcodes.FCMPG, Opcodes.DCMPL,
            Opcodes.DCMPG, Opcodes.FRETURN, Opcodes.DRETURN);
    private static final Set<String> FLOATING_TYPES = Set.of("java/lang/Double", "java/lang/Float");
    private static final Set<String> CODEC_CLASSES = Set.of("DecodeStatus", "DecodedField", "FieldCategory",
            "FieldEncodingException", "FieldPicture", "GnuCobolFieldCodec", "IncompleteFieldException");

    /** True if a type or method descriptor mentions float or double (outside class names). */
    static boolean floatingDescriptor(String desc) {
        if (desc == null) {
            return false;
        }
        for (int i = 0; i < desc.length(); i++) {
            char c = desc.charAt(i);
            if (c == 'L') {
                int end = desc.indexOf(';', i);
                String name = desc.substring(i + 1, end);
                if (FLOATING_TYPES.contains(name)) {
                    return true;
                }
                i = end;
            } else if (c == 'F' || c == 'D') {
                return true;
            }
        }
        return false;
    }

    /** Every use of floating point found in one class file, as readable lines. */
    static List<String> findings(InputStream classFile) throws IOException {
        List<String> out = new ArrayList<>();
        ClassReader reader = new ClassReader(classFile);
        String cls = reader.getClassName();
        int api = SpringAsmInfo.ASM_VERSION;
        reader.accept(new ClassVisitor(api) {
            @Override
            public FieldVisitor visitField(int access, String name, String desc, String sig, Object value) {
                if (floatingDescriptor(desc) || value instanceof Float || value instanceof Double) {
                    out.add(cls + "." + name + ": campo " + desc);
                }
                return null;
            }

            @Override
            public MethodVisitor visitMethod(int access, String name, String desc, String sig, String[] ex) {
                String where = cls + "." + name + desc;
                if (floatingDescriptor(desc)) {
                    out.add(where + ": firma");
                }
                return new MethodVisitor(api) {
                    @Override
                    public void visitInsn(int opcode) {
                        if (FLOATING_OPCODES.contains(opcode)) {
                            out.add(where + ": istruzione " + opcode);
                        }
                    }

                    @Override
                    public void visitVarInsn(int opcode, int var) {
                        visitInsn(opcode);
                    }

                    @Override
                    public void visitIntInsn(int opcode, int operand) {
                        if (opcode == Opcodes.NEWARRAY && (operand == Opcodes.T_FLOAT || operand == Opcodes.T_DOUBLE)) {
                            out.add(where + ": array in virgola mobile");
                        }
                    }

                    @Override
                    public void visitLdcInsn(Object value) {
                        if (value instanceof Float || value instanceof Double) {
                            out.add(where + ": costante " + value);
                        }
                    }

                    @Override
                    public void visitTypeInsn(int opcode, String type) {
                        // an internal name, or an array descriptor when it starts with '['
                        if (FLOATING_TYPES.contains(type) || type.startsWith("[") && floatingDescriptor(type)) {
                            out.add(where + ": tipo " + type);
                        }
                    }

                    @Override
                    public void visitFieldInsn(int opcode, String owner, String name, String fdesc) {
                        if (FLOATING_TYPES.contains(owner) || floatingDescriptor(fdesc)) {
                            out.add(where + ": campo " + owner + "." + name + " " + fdesc);
                        }
                    }

                    @Override
                    public void visitMethodInsn(int opcode, String owner, String name, String mdesc, boolean itf) {
                        if (FLOATING_TYPES.contains(owner) || floatingDescriptor(mdesc)) {
                            out.add(where + ": chiamata " + owner + "." + name + mdesc);
                        }
                    }

                    @Override
                    public void visitInvokeDynamicInsn(String name, String idesc, Handle bsm, Object... args) {
                        if (floatingDescriptor(idesc)) {
                            out.add(where + ": invokedynamic " + name + idesc);
                        }
                    }

                    @Override
                    public void visitLocalVariable(String name, String ldesc, String sig, Label start, Label end, int index) {
                        if (floatingDescriptor(ldesc)) {
                            out.add(where + ": variabile locale " + name + " " + ldesc);
                        }
                    }
                };
            }
        }, 0);
        return out;
    }

    private static Path packageDir(Class<?> anchor) throws URISyntaxException {
        Path root = Path.of(anchor.getProtectionDomain().getCodeSource().getLocation().toURI());
        return root.resolve(anchor.getPackageName().replace('.', '/'));
    }

    @Test
    void nessunaVirgolaMobileNelleClassiCompilateDelCodec() throws IOException, URISyntaxException {
        Path dir = packageDir(GnuCobolFieldCodec.class);
        List<Path> classes;
        try (Stream<Path> s = Files.walk(dir)) {
            classes = s.filter(f -> f.toString().endsWith(".class")).sorted().toList();
        }
        Set<String> seen = new TreeSet<>();
        List<String> found = new ArrayList<>();
        for (Path c : classes) {
            String file = dir.relativize(c).toString();
            seen.add(file.substring(0, file.length() - ".class".length()).replaceAll("\\$.*", ""));
            try (InputStream in = Files.newInputStream(c)) {
                found.addAll(findings(in));
            }
        }
        assertTrue(seen.containsAll(CODEC_CLASSES), "classi del codec ispezionate: " + seen);
        assertEquals(List.of(), found, "uso di virgola mobile nelle classi compilate di " + dir);
    }

    /** Negative proof of the inspection itself: a class that goes through double is caught. */
    @Test
    void lIspezioneVedeUnPassaggioPerDouble() throws IOException {
        try (InputStream in = NoFloatingPointBytecodeTest.class.getResourceAsStream("NoFloatingPointBytecodeTest$ThroughDouble.class")) {
            List<String> f = findings(in);
            assertFalse(f.isEmpty(), "l'ispezione non ha visto Math.pow");
            assertTrue(f.stream().anyMatch(s -> s.contains("java/lang/Math.pow(DD)D")), f.toString());
        }
        assertTrue(floatingDescriptor("(I)D") && floatingDescriptor("Ljava/lang/Double;") && !floatingDescriptor("Ljava/lang/DFoo;"));
    }

    /** Example the source rules cannot see: no double written in the text. */
    static final class ThroughDouble {
        static java.math.BigDecimal power(int scale) {
            return java.math.BigDecimal.valueOf(Math.pow(10, scale));
        }
    }
}
