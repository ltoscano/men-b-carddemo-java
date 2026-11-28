package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.io.InputStream;
import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
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
 * No floating point and no lossy numeric conversion in the compiled production code. The source
 * rules of #26 read the text and do not see the implicit types of expressions
 * ({@code BigDecimal.valueOf(Math.pow(10, scale))} passes them), so every compiled production class
 * of the module (all of {@code target/classes}, every package) is inspected with ASM (the copy
 * shipped in spring-core):
 * <ul>
 *   <li>no float/double instruction, constant, field, signature, local variable, call, method
 *       reference or type ({@code java.lang.Double}, {@code java.lang.Float});</li>
 *   <li>no lossy conversion method ({@code longValue()J}, {@code intValue()I}, {@code shortValue()S},
 *       {@code byteValue()B}, {@code doubleValue()D}, {@code floatValue()F},
 *       {@code toBigInteger()Ljava/math/BigInteger;}) called on any owner that is or extends
 *       {@code Number}, inherited methods included: the hierarchy is resolved through the classes of
 *       the module and then the JDK; an owner that cannot be resolved is reported (in doubt,
 *       report). The {@code ...ValueExact} and {@code toBigIntegerExact} forms are allowed;</li>
 *   <li>no primitive narrowing instruction ({@code L2I}, {@code I2B}, {@code I2C}, {@code I2S}; the
 *       float/double ones are already forbidden) except the ones listed, with their count, in
 *       {@link #ALLOWED_NARROWING}, each with the reason why it loses nothing.</li>
 * </ul>
 */
class NoFloatingPointBytecodeTest {

    /** Lossy conversions, by name and descriptor. */
    private static final Set<String> LOSSY_CONVERSIONS = Set.of(
            "longValue()J", "intValue()I", "shortValue()S", "byteValue()B", "doubleValue()D", "floatValue()F",
            "toBigInteger()Ljava/math/BigInteger;");

    /** Primitive narrowing instructions that are not floating point (those are forbidden outright). */
    private static final Map<Integer, String> NARROWING = Map.of(
            Opcodes.L2I, "L2I", Opcodes.I2B, "I2B", Opcodes.I2C, "I2C", Opcodes.I2S, "I2S");

    /**
     * The narrowing instructions of the codec, each with its exact count and the reason it loses
     * nothing. A new one, or a different count in the same method, fails the test.
     */
    static final Map<String, Integer> ALLOWED_NARROWING = Map.of(
            // out[i] = (byte) c, after the check c <= 0xFF: the byte is the ISO-8859-1 code of c
            "io/github/ltoscano/carddemo/domain/GnuCobolFieldCodec.encode(Lio/github/ltoscano/carddemo/domain/FieldPicture;"
                    + "Ljava/lang/String;)[B: restringimento I2B", 1,
            // chars[i] = (char) (bytes[i] & 0xFF): a value 0-255 always fits a char
            "io/github/ltoscano/carddemo/domain/GnuCobolFieldCodec.decodeAlphanumeric([B)"
                    + "Lio/github/ltoscano/carddemo/domain/DecodedField;: restringimento I2C", 1,
            // OVERPUNCH[i] == (byte) b, with b = last byte & 0xFF (0-255): compares the same bit pattern
            "io/github/ltoscano/carddemo/domain/GnuCobolFieldCodec.overpunchIndex(I)I: restringimento I2B", 1,
            // out[start + i] = (byte) digits.charAt(i): the characters of BigInteger.toString() of a
            // non-negative number are '0'-'9' (0x30-0x39)
            "io/github/ltoscano/carddemo/domain/GnuCobolFieldCodec.encodeDisplay(Lio/github/ltoscano/carddemo/domain/FieldPicture;"
                    + "Ljava/math/BigInteger;)[B: restringimento I2B", 1,
            // out[i] = (byte) ((hi << 4) | lo) with two nibbles 0-15: a value 0-255, the packed byte
            "io/github/ltoscano/carddemo/domain/GnuCobolFieldCodec.encodePacked(Lio/github/ltoscano/carddemo/domain/FieldPicture;"
                    + "Ljava/math/BigInteger;)[B: restringimento I2B", 1);

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

    /**
     * Whether an owner is or extends {@code Number}: through the given classes (internal name to
     * superclass), then through the JDK. Empty when the hierarchy cannot be resolved.
     */
    static java.util.Optional<Boolean> isNumber(String owner, Map<String, String> supers) {
        String c = owner;
        for (int guard = 0; c != null && guard < 64; guard++) {
            if ("java/lang/Number".equals(c)) {
                return java.util.Optional.of(true);
            }
            if (!supers.containsKey(c)) {
                if (c.startsWith("[")) {
                    return java.util.Optional.of(false);
                }
                try {
                    Class<?> k = Class.forName(c.replace('/', '.'), false, NoFloatingPointBytecodeTest.class.getClassLoader());
                    return java.util.Optional.of(Number.class.isAssignableFrom(k));
                } catch (ClassNotFoundException | LinkageError e) {
                    return java.util.Optional.empty();
                }
            }
            c = supers.get(c);
        }
        return java.util.Optional.empty();
    }

    /** Internal name to superclass of each class file. */
    static Map<String, String> supers(List<byte[]> classFiles) {
        Map<String, String> out = new HashMap<>();
        for (byte[] b : classFiles) {
            ClassReader r = new ClassReader(b);
            out.put(r.getClassName(), r.getSuperName());
        }
        return out;
    }

    /** Every forbidden or narrowing use found in one class file, as readable lines. */
    static List<String> findings(byte[] classFile, Map<String, String> supers) {
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
                        } else if (NARROWING.containsKey(opcode)) {
                            out.add(where + ": restringimento " + NARROWING.get(opcode));
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
                            checkMethod(out, supers, where + ": costante metodo ", h.getOwner(), h.getName(), h.getDesc());
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
                        checkMethod(out, supers, where + ": chiamata ", owner, name, mdesc);
                    }

                    @Override
                    public void visitInvokeDynamicInsn(String name, String idesc, Handle bsm, Object... args) {
                        if (floatingDescriptor(idesc)) {
                            out.add(where + ": invokedynamic " + name + idesc);
                        }
                        // method references and lambdas: the target method is a bootstrap argument
                        for (Object a : args) {
                            if (a instanceof Handle h) {
                                checkMethod(out, supers, where + ": riferimento a metodo ", h.getOwner(), h.getName(), h.getDesc());
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
    private static void checkMethod(List<String> out, Map<String, String> supers, String prefix, String owner,
            String name, String desc) {
        if (FLOATING_TYPES.contains(owner) || floatingDescriptor(desc)) {
            out.add(prefix + owner + "." + name + desc);
        } else if (LOSSY_CONVERSIONS.contains(name + desc)) {
            java.util.Optional<Boolean> number = isNumber(owner, supers);
            if (number.isEmpty()) {
                out.add(prefix + "gerarchia non risolta, possibile conversione con perdita " + owner + "." + name + desc);
            } else if (number.get()) {
                out.add(prefix + "con perdita " + owner + "." + name + desc);
            }
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
        List<byte[]> files = new ArrayList<>();
        for (Path c : classes) {
            String file = root.relativize(c).toString().replace('\\', '/');
            seen.add(file.substring(0, file.length() - ".class".length()).replaceAll("\\$.*", ""));
            files.add(Files.readAllBytes(c));
        }
        Map<String, String> supers = supers(files);
        List<String> forbidden = new ArrayList<>();
        Map<String, Integer> narrowing = new TreeMap<>();
        for (byte[] f : files) {
            for (String finding : findings(f, supers)) {
                if (finding.contains(": restringimento ")) {
                    narrowing.merge(finding, 1, Integer::sum);
                } else {
                    forbidden.add(finding);
                }
            }
        }
        Set<String> codec = new TreeSet<>();
        for (String n : CODEC_CLASSES) {
            codec.add(GnuCobolFieldCodec.class.getPackageName().replace('.', '/') + "/" + n);
        }
        assertTrue(seen.containsAll(codec), "classi del codec ispezionate: " + seen);
        assertEquals(List.of(), forbidden, "virgola mobile o conversioni con perdita nelle classi compilate di " + root);
        assertEquals(new TreeMap<>(ALLOWED_NARROWING), narrowing,
                "restringimenti primitivi diversi dall'elenco motivato ALLOWED_NARROWING");
    }

    /** Negative proofs of the inspection itself. */
    @Test
    void lIspezioneVedeVirgolaMobileConversioniConPerditaERestringimenti() throws IOException {
        assertTrue(findingsOf("ThroughDouble").stream().anyMatch(s -> s.contains("java/lang/Math.pow(DD)D")), "Math.pow");
        List<String> lossy = findingsOf("Lossy", "Wide");
        String wide = "io/github/ltoscano/carddemo/domain/NoFloatingPointBytecodeTest$Wide";
        for (String m : List.of("con perdita java/math/BigInteger.longValue()J", "con perdita java/math/BigInteger.intValue()I",
                "con perdita java/math/BigDecimal.toBigInteger()Ljava/math/BigInteger;",
                "con perdita java/math/BigDecimal.shortValue()S", "con perdita java/lang/Number.byteValue()B",
                "con perdita java/lang/Long.intValue()I", "riferimento a metodo con perdita java/math/BigInteger.longValue()J",
                "con perdita " + wide + ".longValue()J", "restringimento L2I", "restringimento I2S")) {
            assertTrue(lossy.stream().anyMatch(s -> s.contains(m)), m + " non visto: " + lossy);
        }
        assertTrue(findingsOf("Unresolved").stream().anyMatch(s -> s.contains("gerarchia non risolta")),
                "proprietario non risolvibile: nel dubbio si segnala");
        assertEquals(List.of(), findingsOf("Exact"), "le forme esatte sono ammesse");
        assertTrue(floatingDescriptor("(I)D") && floatingDescriptor("Ljava/lang/Double;") && !floatingDescriptor("Ljava/lang/DFoo;"));
        assertEquals(java.util.Optional.empty(), isNumber("io/github/ltoscano/Assente", Map.of()));
        assertEquals(java.util.Optional.of(true), isNumber("a/B", Map.of("a/B", "java/math/BigInteger")));
        assertEquals(java.util.Optional.of(false), isNumber("java/lang/String", Map.of()));
    }

    private static List<String> findingsOf(String... nested) throws IOException {
        List<byte[]> files = new ArrayList<>();
        for (String n : nested) {
            try (InputStream in = NoFloatingPointBytecodeTest.class.getResourceAsStream("NoFloatingPointBytecodeTest$" + n + ".class")) {
                files.add(in.readAllBytes());
            }
        }
        if ("Unresolved".equals(nested[0])) {
            // the bytecode of Unresolved calls longValue() on NoFloatingPointBytecodeTest$Wide; hide
            // its hierarchy by renaming the owner to a class that does not exist
            byte[] b = files.get(0);
            String from = "NoFloatingPointBytecodeTest$Wide";
            String to = "NoFloatingPointBytecodeTest$Xxxx";
            String s = new String(b, java.nio.charset.StandardCharsets.ISO_8859_1).replace(from, to);
            files.set(0, s.getBytes(java.nio.charset.StandardCharsets.ISO_8859_1));
        }
        return findings(files.get(0), supers(files));
    }

    /** Example the source rules cannot see: no double written in the text. */
    static final class ThroughDouble {
        static java.math.BigDecimal power(int scale) {
            return java.math.BigDecimal.valueOf(Math.pow(10, scale));
        }
    }

    /** A subclass of BigInteger: longValue() is inherited, the owner in the bytecode is Wide. */
    static final class Wide extends java.math.BigInteger {
        private static final long serialVersionUID = 1L;

        Wide(String v) {
            super(v);
        }
    }

    /** Lossy conversions: 18446744073709551617 becomes 1 through longValue, 4294967297 through (int). */
    static final class Lossy {
        static java.math.BigInteger viaLong(java.math.BigInteger x) {
            return java.math.BigInteger.valueOf(x.longValue());
        }

        static java.math.BigInteger viaSubclass(Wide w) {
            return java.math.BigInteger.valueOf(w.longValue());
        }

        static java.math.BigInteger viaNarrowing(java.math.BigInteger x) {
            return java.math.BigInteger.valueOf((int) x.longValueExact());
        }

        static short viaShort(int x) {
            return (short) x;
        }

        static long small(java.math.BigInteger x, java.math.BigDecimal d, Number n, Long l) {
            return x.intValue() + d.toBigInteger().intValueExact() + d.shortValue() + n.byteValue() + l.intValue();
        }

        static java.util.function.Function<java.math.BigInteger, Long> reference() {
            return java.math.BigInteger::longValue;
        }
    }

    /** Same call as Lossy.viaSubclass; its owner is renamed in the test to a class that does not exist. */
    static final class Unresolved {
        static long call(Wide w) {
            return w.longValue();
        }
    }

    /** The exact forms are allowed. */
    static final class Exact {
        static long exact(java.math.BigInteger x, java.math.BigDecimal d) {
            return x.longValueExact() + d.intValueExact() + d.toBigIntegerExact().shortValueExact();
        }
    }
}
