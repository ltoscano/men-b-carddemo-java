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
 * so here every compiled production class of the module (all of {@code target/classes}, every
 * package) is inspected with ASM (the copy shipped in spring-core): no float/double instruction,
 * constant, field, signature, local variable, call or type ({@code java.lang.Double},
 * {@code java.lang.Float}), and no lossy numeric conversion of {@code BigInteger},
 * {@code BigDecimal} or {@code Number} ({@code longValue}, {@code intValue}, {@code shortValue},
 * {@code byteValue}, {@code doubleValue}, {@code floatValue}, {@code BigDecimal.toBigInteger});
 * the {@code ...ValueExact} and {@code toBigIntegerExact} forms are allowed.
 */
class NoFloatingPointBytecodeTest {

    /** Owners whose numeric conversions are checked. */
    private static final Set<String> NUMBER_TYPES = Set.of("java/math/BigInteger", "java/math/BigDecimal", "java/lang/Number");
    /** Conversions that silently drop digits, sign or fraction. */
    private static final Set<String> LOSSY_CONVERSIONS = Set.of(
            "longValue", "intValue", "shortValue", "byteValue", "doubleValue", "floatValue", "toBigInteger");

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
                        } else if (value instanceof Handle h) {
                            checkMethod(out, where + ": costante metodo ", h.getOwner(), h.getName(), h.getDesc());
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
                        checkMethod(out, where + ": chiamata ", owner, name, mdesc);
                    }

                    @Override
                    public void visitInvokeDynamicInsn(String name, String idesc, Handle bsm, Object... args) {
                        if (floatingDescriptor(idesc)) {
                            out.add(where + ": invokedynamic " + name + idesc);
                        }
                        // method references and lambdas: the target method is a bootstrap argument
                        for (Object a : args) {
                            if (a instanceof Handle h) {
                                checkMethod(out, where + ": riferimento a metodo ", h.getOwner(), h.getName(), h.getDesc());
                            }
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

    /** A call (or method reference) to a floating-point type or signature, or a lossy conversion. */
    private static void checkMethod(List<String> out, String prefix, String owner, String name, String desc) {
        if (FLOATING_TYPES.contains(owner) || floatingDescriptor(desc)) {
            out.add(prefix + owner + "." + name + desc);
        } else if (NUMBER_TYPES.contains(owner) && LOSSY_CONVERSIONS.contains(name)) {
            out.add(prefix + "con perdita " + owner + "." + name + desc);
        }
    }

    /** Root of the compiled production classes of the module ({@code target/classes}). */
    private static Path productionRoot() throws URISyntaxException {
        return Path.of(GnuCobolFieldCodec.class.getProtectionDomain().getCodeSource().getLocation().toURI());
    }

    @Test
    void nessunaVirgolaMobileNeConversioniConPerditaNelleClassiDelModulo() throws IOException, URISyntaxException {
        Path root = productionRoot();
        List<Path> classes;
        try (Stream<Path> s = Files.walk(root)) {
            classes = s.filter(f -> f.toString().endsWith(".class")).sorted().toList();
        }
        Set<String> seen = new TreeSet<>();
        List<String> found = new ArrayList<>();
        for (Path c : classes) {
            String file = root.relativize(c).toString().replace('\\', '/');
            seen.add(file.substring(0, file.length() - ".class".length()).replaceAll("\\$.*", ""));
            try (InputStream in = Files.newInputStream(c)) {
                found.addAll(findings(in));
            }
        }
        Set<String> codec = new TreeSet<>();
        for (String n : CODEC_CLASSES) {
            codec.add(GnuCobolFieldCodec.class.getPackageName().replace('.', '/') + "/" + n);
        }
        assertTrue(seen.containsAll(codec), "classi del codec ispezionate: " + seen);
        assertEquals(List.of(), found, "virgola mobile o conversioni con perdita nelle classi compilate di " + root);
    }

    /** Negative proofs of the inspection itself. */
    @Test
    void lIspezioneVedeVirgolaMobileEConversioniConPerdita() throws IOException {
        assertTrue(findingsOf("ThroughDouble").stream().anyMatch(s -> s.contains("java/lang/Math.pow(DD)D")), "Math.pow");
        List<String> lossy = findingsOf("Lossy");
        for (String m : List.of("java/math/BigInteger.longValue()J", "java/math/BigInteger.intValue()I",
                "java/math/BigDecimal.toBigInteger()Ljava/math/BigInteger;", "java/math/BigDecimal.shortValue()S",
                "java/lang/Number.byteValue()B", "java/math/BigInteger.longValue")) {
            assertTrue(lossy.stream().anyMatch(s -> s.contains(m)), m + " non visto: " + lossy);
        }
        assertEquals(List.of(), findingsOf("Exact"), "le forme esatte sono ammesse");
        assertTrue(floatingDescriptor("(I)D") && floatingDescriptor("Ljava/lang/Double;") && !floatingDescriptor("Ljava/lang/DFoo;"));
    }

    private static List<String> findingsOf(String nested) throws IOException {
        try (InputStream in = NoFloatingPointBytecodeTest.class.getResourceAsStream("NoFloatingPointBytecodeTest$" + nested + ".class")) {
            return findings(in);
        }
    }

    /** Example the source rules cannot see: no double written in the text. */
    static final class ThroughDouble {
        static java.math.BigDecimal power(int scale) {
            return java.math.BigDecimal.valueOf(Math.pow(10, scale));
        }
    }

    /** Lossy conversions: 18446744073709551617 becomes 1 through longValue. */
    static final class Lossy {
        static java.math.BigInteger viaLong(java.math.BigInteger x) {
            return java.math.BigInteger.valueOf(x.longValue());
        }

        static int small(java.math.BigInteger x, java.math.BigDecimal d, Number n) {
            return x.intValue() + d.toBigInteger().intValue() + d.shortValue() + n.byteValue();
        }

        static java.util.function.Function<java.math.BigInteger, Long> reference() {
            return java.math.BigInteger::longValue;
        }
    }

    /** The exact forms are allowed. */
    static final class Exact {
        static long exact(java.math.BigInteger x, java.math.BigDecimal d) {
            return x.longValueExact() + d.intValueExact() + d.toBigIntegerExact().shortValueExact();
        }
    }
}
