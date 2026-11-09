import java.util.*;
final class Boxes {
    record Child(Box box, int x, int y, String role) {}
    record Drawn(String text, int x, int y) {}
    static final class Box {
        int width, height, baseline;
        String description;
        List<Child> children = new ArrayList<>();
        List<Drawn> strings = new ArrayList<>();
        Box(int width, int height, int baseline, String description) {
            this.width = width;
            this.height = height;
            this.baseline = baseline;
            this.description = description;
        }
        int descent() { return height - 1 - baseline; }
        void add(Box child, int x, int y) { add(child, x, y, ""); }
        void add(Box child, int x, int y, String role) {
            children.add(new Child(child, x, y, role));
        }
        void draw(String text, int x, int y) { strings.add(new Drawn(text, x, y)); }
        void draw(String text) { draw(text, 0, 0); }
    }
    static final Map<String, List<String>> LARGE_GLYPHS =
        Map.of("\\sum", List.of("\\--", " > ", "/--"), "\\prod", List.of("___", "| |", "| |"),
               "\\int", List.of(" /", " |", "/ "));
    static String display(Parser.Atom atom) {
        return atom.kind().equals("command") ? Lexer.SYMBOL_COMMANDS.get(atom.value()).display()
                                             : atom.value();
    }
    static String atomType(Parser.Atom atom) {
        if (atom.kind().equals("command"))
            return Lexer.SYMBOL_COMMANDS.get(atom.value()).type();
        if (!atom.kind().equals("symbol"))
            return "ordinary";
        return switch (atom.value()) {
            case "+", "-", "*" -> "binary";
            case "=", "<", ">", ":" -> "relation";
            case "(", "[" -> "open";
            case ")", "]", "!" -> "close";
            case ",", ";" -> "punctuation";
            default -> "ordinary";
        };
    }
    static List<String> delimiterGlyph(String delimiter, int height) {
        List<String> result = new ArrayList<>();
        if (delimiter.equals("."))
            return result;
        String c = delimiter.substring(delimiter.length() - 1);
        if (height == 1)
            return List.of(c);
        if (Set.of("[", "]", "|").contains(delimiter))
            return Collections.nCopies(height, delimiter);
        boolean left = delimiter.equals("(") || delimiter.equals("\\{");
        result.add(left ? "/" : "\\");
        for (int i = 1; i < height - 1; i++)
            result.add("|");
        result.add(left ? "\\" : "/");
        if ((delimiter.equals("\\{") || delimiter.equals("\\}")) && height >= 3)
            result.set((height - 1) / 2, left ? "<" : ">");
        return result;
    }
}
