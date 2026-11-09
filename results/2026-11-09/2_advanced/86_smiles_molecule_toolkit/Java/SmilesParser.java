import java.util.*;
final class SmilesParser {
    record Organic(String symbol, boolean aromatic, int end) {}
    record AtomRead(Molecule.Atom atom, int end) {}
    record Pending(char symbol, int column) {}
    record Branch(int atom, int column) {}
    record OpenRing(int atom, Character symbol, int column) {}
    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static Organic organic(String text, int position) {
        if (position >= text.length())
            return null;
        String pair = text.substring(position, Math.min(position + 2, text.length()));
        if (pair.equals("Cl") || pair.equals("Br"))
            return new Organic(pair, false, position + 2);
        char c = text.charAt(position);
        if ("BCNOPSFI".indexOf(c) >= 0)
            return new Organic(Character.toString(c), false, position + 1);
        if ("bcnops".indexOf(c) >= 0)
            return new Organic(Character.toString(Character.toUpperCase(c)), true, position + 1);
        return null;
    }
    static Molecule.Atom bracket(String content, Map<String, Molecule.Element> elements,
                                 int column) {
        int p = 0;
        while (p < content.length() && digit(content.charAt(p)))
            p++;
        if (p >= 4 || p > 0 && content.charAt(0) == '0')
            throw new Molecule.AnalysisError("bad bracket atom", column);
        int mass = p == 0 ? 0 : Integer.parseInt(content.substring(0, p));
        if (p == content.length())
            throw new Molecule.AnalysisError("bad bracket atom", column);
        char c = content.charAt(p);
        String symbol;
        boolean aromatic;
        if ("bcnops".indexOf(c) >= 0) {
            symbol = Character.toString(Character.toUpperCase(c));
            aromatic = true;
            p++;
        } else if (c >= 'A' && c <= 'Z') {
            String pair = content.substring(p, Math.min(p + 2, content.length()));
            if (pair.length() == 2 && pair.charAt(1) >= 'a' && pair.charAt(1) <= 'z' &&
                elements.containsKey(pair)) {
                symbol = pair;
                p += 2;
            } else if (elements.containsKey(Character.toString(c))) {
                symbol = Character.toString(c);
                p++;
            } else
                throw new Molecule.AnalysisError("unknown element", column);
            aromatic = false;
        } else
            throw new Molecule.AnalysisError("bad bracket atom", column);
        if (content.startsWith("@@", p))
            p += 2;
        else if (content.startsWith("@", p))
            p++;
        int hydrogens = 0;
        if (p < content.length() && content.charAt(p) == 'H') {
            hydrogens = 1;
            p++;
            if (p < content.length() && digit(content.charAt(p)))
                hydrogens = content.charAt(p++) - '0';
        }
        int charge = 0;
        if (p < content.length() && (content.charAt(p) == '+' || content.charAt(p) == '-')) {
            charge = content.charAt(p++) == '+' ? 1 : -1;
            if (p < content.length() && content.charAt(p) >= '1' && content.charAt(p) <= '9')
                charge *= content.charAt(p++) - '0';
        }
        if (p != content.length())
            throw new Molecule.AnalysisError("bad bracket atom", column);
        return new Molecule.Atom(elements.get(symbol), aromatic, mass, charge, hydrogens, true,
                                 column);
    }
    static AtomRead atom(String text, int position, Map<String, Molecule.Element> elements) {
        if (text.charAt(position) == '[') {
            int end = text.indexOf(']', position + 1);
            if (end < 0)
                throw new Molecule.AnalysisError("unclosed bracket", position + 1);
            return new AtomRead(bracket(text.substring(position + 1, end), elements, position + 1),
                                end + 1);
        }
        Organic organic = organic(text, position);
        if (organic == null)
            throw new Molecule.AnalysisError("unexpected character", position + 1);
        return new AtomRead(new Molecule.Atom(elements.get(organic.symbol()), organic.aromatic(), 0,
                                              0, 0, false, position + 1),
                            organic.end());
    }
    static Molecule parse(String text, Map<String, Molecule.Element> elements, boolean pattern) {
        Molecule molecule = new Molecule(elements);
        String symbols = pattern ? "-=#:~" : "-/\\=#:";
        Integer current = null;
        Pending pending = null;
        List<Branch> branches = new ArrayList<>();
        Map<Integer, OpenRing> openRings = new HashMap<>();
        int position = 0;
        while (position < text.length()) {
            char c = text.charAt(position);
            int column = position + 1;
            if (symbols.indexOf(c) >= 0) {
                if (current == null || pending != null)
                    throw new Molecule.AnalysisError("misplaced bond", column);
                pending = new Pending(c, column);
                position++;
            } else if (c == '(') {
                if (current == null || pending != null || text.charAt(position - 1) == '(')
                    throw new Molecule.AnalysisError("misplaced branch", column);
                branches.add(new Branch(current, column));
                position++;
            } else if (c == ')') {
                if (branches.isEmpty())
                    throw new Molecule.AnalysisError("unmatched parenthesis", column);
                if (pending != null)
                    throw new Molecule.AnalysisError("dangling bond", pending.column());
                if (text.charAt(position - 1) == '(')
                    throw new Molecule.AnalysisError("empty branch", column);
                current = branches.removeLast().atom();
                position++;
            } else if (digit(c) || c == '%') {
                if (current == null)
                    throw new Molecule.AnalysisError("misplaced ring closure", column);
                int ring;
                if (c == '%') {
                    if (position + 2 >= text.length() || !digit(text.charAt(position + 1)) ||
                        !digit(text.charAt(position + 2)))
                        throw new Molecule.AnalysisError("bad ring number", column);
                    ring = Integer.parseInt(text.substring(position + 1, position + 3));
                    position += 3;
                } else {
                    ring = c - '0';
                    position++;
                }
                Character symbol = pending == null ? null : pending.symbol();
                pending = null;
                OpenRing opening = openRings.get(ring);
                if (opening == null) {
                    openRings.put(ring, new OpenRing(current, symbol, column));
                    continue;
                }
                if (opening.atom() == current)
                    throw new Molecule.AnalysisError("self bond", column);
                if (opening.symbol() != null && symbol != null &&
                    Molecule.bondType(opening.symbol()) != Molecule.bondType(symbol))
                    throw new Molecule.AnalysisError("ring bond mismatch", column);
                if (molecule.neighbors.get(opening.atom()).containsKey(current))
                    throw new Molecule.AnalysisError("duplicate bond", column);
                molecule.addBond(opening.atom(), current,
                                 symbol == null ? opening.symbol() : symbol);
                openRings.remove(ring);
            } else {
                AtomRead read =
                    pattern ? Search.patternAtom(text, position) : atom(text, position, elements);
                position = read.end();
                int next = molecule.addAtom(read.atom());
                if (current != null)
                    molecule.addBond(current, next, pending == null ? null : pending.symbol());
                current = next;
                pending = null;
            }
        }
        if (pending != null)
            throw new Molecule.AnalysisError("dangling bond", pending.column());
        if (!branches.isEmpty())
            throw new Molecule.AnalysisError("unmatched parenthesis", branches.getFirst().column());
        if (!openRings.isEmpty())
            throw new Molecule.AnalysisError(
                "unclosed ring",
                openRings.values().stream().mapToInt(OpenRing::column).min().orElseThrow());
        return molecule;
    }
}
