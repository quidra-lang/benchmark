import java.util.*;
final class Layout {
    record Types(String left, String right) {}
    record Spacing(List<Types> types, List<Integer> gaps) {}
    static final List<String> TYPES =
        List.of("ordinary", "operator", "binary", "relation", "open", "close", "punctuation");
    static final String[] SPACING = {"01BR000", "11-R000", "BB--B--", "RR-0R00",
                                     "00-0000", "01BR000", "PP-PPPP"};
    static Types types(Parser.Node node) {
        return switch (node) {
            case Parser.Atom atom -> new Types(Boxes.atomType(atom), Boxes.atomType(atom));
            case Parser.Delimited ignored -> new Types("open", "close");
            case Parser.Script script -> types(script.base());
            case Parser.Binary binary when binary.kind().equals("overset") ||
                binary.kind().equals("underset") ->
                types(binary.second());
            default -> new Types("ordinary", "ordinary");
        };
    }
    static List<Types> converted(List<Parser.Node> nodes) {
        List<Types> result = new ArrayList<>();
        for (Parser.Node node : nodes)
            result.add(types(node));
        for (int i = 0; i < result.size(); i++) {
            Types current = result.get(i);
            if (current.left().equals("binary") &&
                (i == 0 || Set.of("binary", "operator", "relation", "open", "punctuation")
                               .contains(result.get(i - 1).right()))) {
                current = new Types("ordinary", "ordinary");
                result.set(i, current);
            }
            if (Set.of("relation", "close", "punctuation").contains(current.left()) && i > 0 &&
                result.get(i - 1).right().equals("binary"))
                result.set(i - 1, new Types("ordinary", "ordinary"));
        }
        if (!result.isEmpty() && result.getLast().right().equals("binary"))
            result.set(result.size() - 1, new Types("ordinary", "ordinary"));
        return result;
    }
    static boolean word(Parser.Node node) {
        if (node instanceof Parser.Script script)
            return word(script.base());
        return node instanceof Parser.Atom atom && atom.kind().equals("command") &&
            (Lexer.GREEK.contains(atom.value().substring(1)) || atom.value().equals("\\infty"));
    }
    static boolean alphanumeric(Parser.Node node) {
        if (node instanceof Parser.Atom atom &&
                (atom.kind().equals("identifier") || atom.kind().equals("number")) ||
            word(node))
            return true;
        if (node instanceof Parser.Script script)
            return alphanumeric(script.base());
        return node instanceof Parser.Accent accent &&
            Set.of("overline", "hat", "vec", "dot", "tilde").contains(accent.name()) &&
            alphanumeric(accent.body());
    }
    static Spacing spacing(List<Parser.Node> nodes, boolean normal, Map<String, Integer> params) {
        List<Types> types = converted(nodes);
        List<Integer> gaps = new ArrayList<>();
        for (int i = 0; i + 1 < nodes.size(); i++) {
            Parser.Node first = nodes.get(i), second = nodes.get(i + 1);
            if (alphanumeric(first) && alphanumeric(second) && (word(first) || word(second)))
                gaps.add(1);
            else {
                char entry = SPACING[TYPES.indexOf(types.get(i).right())].charAt(
                    TYPES.indexOf(types.get(i + 1).left()));
                int gap = switch (entry) {
                    case 'B' -> normal ? params.get("bin_space") : 0;
                    case 'R' -> normal ? params.get("rel_space") : 0;
                    case 'P' -> normal ? params.get("punct_space") : 0;
                    case '1' -> 1;
                    default -> 0;
                };
                gaps.add(gap);
            }
        }
        return new Spacing(types, gaps);
    }
    static Boxes.Box row(List<Boxes.Box> children, List<Integer> gaps, String description,
                         List<String> roles) {
        int ascent = 0, descent = 0, width = 0;
        for (Boxes.Box box : children) {
            ascent = Math.max(ascent, box.baseline);
            descent = Math.max(descent, box.descent());
            width += box.width;
        }
        for (int gap : gaps)
            width += gap;
        Boxes.Box result = new Boxes.Box(width, ascent + descent + 1, ascent, description);
        int x = 0;
        for (int i = 0; i < children.size(); i++) {
            Boxes.Box child = children.get(i);
            result.add(child, x, ascent - child.baseline, roles == null ? "" : roles.get(i));
            x += child.width;
            if (i < gaps.size())
                x += gaps.get(i);
        }
        return result;
    }
    static Boxes.Box row(List<Boxes.Box> children, List<Integer> gaps, String description) {
        return row(children, gaps, description, null);
    }
}
