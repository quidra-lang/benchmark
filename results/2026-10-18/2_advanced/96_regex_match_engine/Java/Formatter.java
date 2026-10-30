import java.util.*;
final class Formatter {
    static String display(char c) {
        return c >= 33 && c <= 126 && "\\]^-".indexOf(c) < 0
            ? String.valueOf(c)
            : String.format(Locale.ROOT, "\\x%02X", (int)c);
    }
    static String setNotation(BitSet codes, boolean negated) {
        StringBuilder result = new StringBuilder(negated ? "[^" : "[");
        int position = codes.nextSetBit(0);
        while (position >= 0) {
            int end = position;
            while (end + 1 < 128 && codes.get(end + 1))
                end++;
            String first = display((char)position), last = display((char)end);
            result.append(first);
            if (end - position + 1 == 2)
                result.append(last);
            else if (end - position + 1 >= 3)
                result.append('-').append(last);
            position = codes.nextSetBit(end + 1);
        }
        return result.append(']').toString();
    }
    static String instruction(Main.Instruction instruction) {
        return switch (instruction.op()) {
            case CHAR -> "CHAR " + display((char)instruction.value());
            case CLASS -> "CLASS " + setNotation(instruction.characters(), instruction.negated());
            case SPLIT -> "SPLIT " + instruction.x() + ", " + instruction.y();
            case JMP -> "JMP " + instruction.x();
            case SAVE -> "SAVE " + instruction.value();
            case ASSERT -> "ASSERT " + instruction.kind();
            case BACKREF -> "BACKREF " + instruction.value();
            case LOOK -> "LOOK " + instruction.kind() + " " + instruction.x();
            default -> instruction.op().name();
        };
    }
    static String quoted(String text) {
        return "\"" +
            text.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\t", "\\t") +
            "\"";
    }
}
