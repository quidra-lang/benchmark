import java.util.*;
final class Charset {
    static final BitSet ASCII = range(0, 127), DIGITS = range('0', '9'), WORD = wordSet(),
                        SPACE = fromCodes(9, 10, 11, 12, 13, 32);
    static BitSet range(int first, int last) {
        BitSet result = new BitSet(128);
        result.set(first, last + 1);
        return result;
    }
    static BitSet fromCodes(int... codes) {
        BitSet result = new BitSet(128);
        for (int code : codes)
            result.set(code);
        return result;
    }
    static BitSet wordSet() {
        BitSet result = range('0', '9');
        result.or(range('a', 'z'));
        result.or(range('A', 'Z'));
        result.set('_');
        return result;
    }
    static boolean letter(char c) { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'; }
    static char switched(char c) {
        return c >= 'a' && c <= 'z' ? (char)(c - 'a' + 'A')
        : c >= 'A' && c <= 'Z'      ? (char)(c - 'A' + 'a')
                                    : c;
    }
    static BitSet standard(char c) {
        return (BitSet)(switch (c) {
                   case 'd' -> DIGITS;
                   case 'w' -> WORD;
                   default -> SPACE;
               })
            .clone();
    }
    static BitSet escapedSet(char c) {
        BitSet result = standard(Character.toLowerCase(c));
        if (c >= 'A' && c <= 'Z')
            result.flip(0, 128);
        return result;
    }
    static boolean equal(char a, char b, String flags) {
        return a == b || flags.indexOf('i') >= 0 && letter(a) && switched(a) == b;
    }
    static boolean testChar(String text, int position, char expected, String flags) {
        return position < text.length() && equal(text.charAt(position), expected, flags);
    }
    static boolean testAny(String text, int position, String flags) {
        return position < text.length() &&
            (flags.indexOf('s') >= 0 || text.charAt(position) != '\n');
    }
    static boolean testClass(String text, int position, BitSet set, boolean negate, String flags) {
        if (position >= text.length())
            return false;
        char c = text.charAt(position);
        boolean present =
            set.get(c) || flags.indexOf('i') >= 0 && letter(c) && set.get(switched(c));
        return present != negate;
    }
    static boolean wordAt(String text, int position) {
        return position >= 0 && position < text.length() && WORD.get(text.charAt(position));
    }
    static boolean assertion(String kind, String text, int position, String flags) {
        if (kind.equals("BOL"))
            return position == 0 || flags.indexOf('m') >= 0 && text.charAt(position - 1) == '\n';
        if (kind.equals("EOL"))
            return position == text.length() ||
                flags.indexOf('m') >= 0 && text.charAt(position) == '\n';
        boolean edge = wordAt(text, position - 1) != wordAt(text, position);
        return kind.equals("WORD") ? edge : !edge;
    }
}
