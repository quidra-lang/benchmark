import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    record Warning(int column, String message) {}
    static final class Formula {
        int number;
        String line, tagString;
        List<Parser.Node> nodes = List.of();
        Lexer.Token tag, label;
        Lexer.FormulaError error;
        List<Warning> warnings = new ArrayList<>();
        Formula(int number, String line) {
            this.number = number;
            this.line = line;
            try {
                List<Lexer.Token> tokens = Lexer.tokenize(line);
                Parser.checkBraces(tokens);
                Parser parser = new Parser(tokens);
                nodes = parser.parse();
                tag = parser.tag;
                label = parser.label;
            } catch (Lexer.FormulaError error) {
                this.error = error;
            }
        }
    }
    static Map<String, String> referenceTable(List<Formula> formulas) {
        int counter = 0;
        for (Formula formula : formulas)
            if (formula.error == null) {
                if (formula.tag != null)
                    formula.tagString = "(" + formula.tag.value() + ")";
                else if (formula.label != null)
                    formula.tagString = "(" + (++counter) + ")";
            }
        Map<String, String> references = new HashMap<>();
        for (Formula formula : formulas)
            if (formula.error == null && formula.label != null) {
                Lexer.Token label = formula.label;
                if (references.containsKey(label.value()))
                    formula.warnings.add(
                        new Warning(label.column(), "duplicate label \"" + label.value() + "\""));
                else
                    references.put(label.value(), formula.tagString);
            }
        return references;
    }
    static List<Parser.Node> children(Parser.Node node) {
        return switch (node) {
            case Parser.Atom ignored -> List.of();
            case Parser.Row row -> row.children();
            case Parser.Binary binary -> List.of(binary.first(), binary.second());
            case Parser.Radical radical ->
                radical.index() == null ? List.of(radical.body())
                                        : List.of(radical.index(), radical.body());
            case Parser.Script script -> {
                List<Parser.Node> children = new ArrayList<>();
                children.add(script.base());
                if (script.sub() != null)
                    children.add(script.sub());
                if (script.sup() != null)
                    children.add(script.sup());
                yield children;
            }
            case Parser.Delimited delimited -> List.of(delimited.body());
            case Parser.Matrix matrix -> {
                List<Parser.Node> children = new ArrayList<>();
                for (List<Parser.Node> row : matrix.rows())
                    children.addAll(row);
                yield children;
            }
            case Parser.Accent accent -> List.of(accent.body());
        };
    }
    static void warnings(Parser.Node node, Formula formula, Map<String, String> references) {
        if (node instanceof Parser.Atom atom) {
            if (atom.kind().equals("identifier") && Lexer.COMMAND_NAMES.contains(atom.value()))
                formula.warnings.add(new Warning(
                    atom.column(), atom.value() + " is a command name; write \\" + atom.value()));
            else if (atom.kind().equals("reference") && !references.containsKey(atom.value()))
                formula.warnings.add(
                    new Warning(atom.column(), "undefined reference \"" + atom.value() + "\""));
        } else if (node instanceof Parser.Delimited delimited && !delimited.left().equals(".") &&
                   !delimited.right().equals(".") &&
                   !delimited.right().equals(
                       Map.of("(", ")", "[", "]", "|", "|", "\\{", "\\}").get(delimited.left())))
            formula.warnings.add(new Warning(delimited.column(), "\\left" + delimited.left() +
                                                                     " closed by \\right" +
                                                                     delimited.right()));
        for (Parser.Node child : children(node))
            warnings(child, formula, references);
    }
    static int center(Boxes.Box box, int width) { return (width - box.width) / 2; }
    static void drawDelimiter(Boxes.Box box, String delimiter, int x, int height) {
        List<String> glyph = Boxes.delimiterGlyph(delimiter, height);
        for (int y = 0; y < glyph.size(); y++)
            box.draw(glyph.get(y), x, y);
    }
    static String delimiterString(String delimiter) {
        return delimiter.equals(".") ? "" : delimiter.substring(delimiter.length() - 1);
    }
    static final class Typesetter {
        Map<String, Integer> params;
        Map<String, String> references;
        Typesetter(Map<String, Integer> params, Map<String, String> references) {
            this.params = params;
            this.references = references;
        }
        Boxes.Box typeset(Parser.Node node, boolean normal) {
            return switch (node) {
                case Parser.Atom atom -> atom(atom, normal);
                case Parser.Row row -> {
                    List<Boxes.Box> boxes = new ArrayList<>();
                    for (Parser.Node child : row.children())
                        boxes.add(typeset(child, normal));
                    yield Layout.row(boxes, Layout.spacing(row.children(), normal, params).gaps(),
                                     "row");
                }
                case Parser.Binary binary -> binary(binary, normal);
                case Parser.Script script -> script(script, normal);
                case Parser.Radical radical ->
                    radical(typeset(radical.body(), normal),
                            radical.index() == null ? null : typeset(radical.index(), false));
                case Parser.Delimited delimited ->
                    delimit(typeset(delimited.body(), normal), delimited.left(), delimited.right());
                case Parser.Matrix matrix -> matrix(matrix, normal);
                case Parser.Accent accent -> accent(accent, normal);
            };
        }
        Boxes.Box atom(Parser.Atom atom, boolean normal) {
            String description = (atom.kind().equals("text")        ? "text"
                                  : atom.kind().equals("reference") ? "eqref"
                                                                    : "atom") +
                                 " \"" + atom.value() + "\"",
                   display = atom.kind().equals("reference")
                                 ? references.getOrDefault(atom.value(), "(??)")
                                 : Boxes.display(atom);
            if (normal && atom.kind().equals("command") &&
                Boxes.LARGE_GLYPHS.containsKey(atom.value())) {
                List<String> glyph = Boxes.LARGE_GLYPHS.get(atom.value());
                Boxes.Box box = new Boxes.Box(glyph.getFirst().length(), 3, 1, description);
                for (int y = 0; y < 3; y++)
                    box.draw(glyph.get(y), 0, y);
                return box;
            }
            Boxes.Box box = new Boxes.Box(display.length(), 1, 0, description);
            box.draw(display);
            return box;
        }
        Boxes.Box script(Parser.Script script, boolean normal) {
            Boxes.Box base = typeset(script.base(), normal),
                      sub = script.sub() == null ? null : typeset(script.sub(), false),
                      sup = script.sup() == null ? null : typeset(script.sup(), false);
            int sw = sub == null ? 0 : sub.width, sh = sub == null ? 0 : sub.height,
                pw = sup == null ? 0 : sup.width, ph = sup == null ? 0 : sup.height;
            boolean stacked =
                normal &&
                (script.base() instanceof Parser.Atom atom && atom.kind().equals("command") &&
                     Set.of("\\sum", "\\prod", "\\lim", "\\max", "\\min").contains(atom.value()) ||
                 script.base() instanceof Parser.Accent accent &&
                     Set.of("overbrace", "underbrace").contains(accent.name()));
            if (stacked) {
                int width = Math.max(base.width, Math.max(sw, pw));
                Boxes.Box box =
                    new Boxes.Box(width, ph + base.height + sh, ph + base.baseline, "limits");
                box.add(base, center(base, width), ph, "base: ");
                if (sub != null)
                    box.add(sub, center(sub, width), ph + base.height, "sub: ");
                if (sup != null)
                    box.add(sup, center(sup, width), 0, "sup: ");
                return box;
            }
            int pt = (base.baseline == 0 ? -1 : 0) - ph + 1,
                st = base.descent() == 0 ? base.height : base.height - 1,
                top = sup == null ? 0 : Math.min(0, pt),
                bottom = sub == null ? base.height - 1 : Math.max(base.height - 1, st + sh - 1);
            Boxes.Box box = new Boxes.Box(base.width + Math.max(sw, pw), bottom - top + 1,
                                          base.baseline - top, "scripts");
            box.add(base, 0, -top, "base: ");
            if (sub != null)
                box.add(sub, base.width, st - top, "sub: ");
            if (sup != null)
                box.add(sup, base.width, pt - top, "sup: ");
            return box;
        }
        Boxes.Box binary(Parser.Binary node, boolean normal) {
            String kind = node.kind();
            if (kind.equals("overset") || kind.equals("underset")) {
                Boxes.Box placed = typeset(node.first(), false), base =
                                                                     typeset(node.second(), normal);
                int width = Math.max(placed.width, base.width);
                boolean over = kind.equals("overset");
                Boxes.Box box =
                    new Boxes.Box(width, placed.height + base.height,
                                  over ? placed.height + base.baseline : base.baseline, kind);
                if (over) {
                    box.add(placed, center(placed, width), 0, "over: ");
                    box.add(base, center(base, width), placed.height, "base: ");
                } else {
                    box.add(base, center(base, width), 0, "base: ");
                    box.add(placed, center(placed, width), base.height, "under: ");
                }
                return box;
            }
            Boxes.Box first = typeset(node.first(), normal), second =
                                                                 typeset(node.second(), normal);
            if (kind.equals("frac")) {
                if (normal) {
                    int width = Math.max(first.width, second.width) + 2;
                    Boxes.Box box = new Boxes.Box(width, first.height + 1 + second.height,
                                                  first.height, "frac");
                    box.add(first, center(first, width), 0, "num: ");
                    box.add(second, center(second, width), first.height + 1, "den: ");
                    box.draw("-".repeat(width), 0, first.height);
                    return box;
                }
                if (node.first() instanceof Parser.Row ||
                    node.first() instanceof Parser.Binary binary && binary.kind().equals("frac"))
                    first = delimit(first, "(", ")");
                if (node.second() instanceof Parser.Row ||
                    node.second() instanceof Parser.Binary binary && binary.kind().equals("frac"))
                    second = delimit(second, "(", ")");
                Boxes.Box slash = new Boxes.Box(1, 1, 0, "atom \"/\"");
                slash.draw("/");
                return Layout.row(List.of(first, slash, second), List.of(0, 0), "slash",
                                  List.of("num: ", "", "den: "));
            }
            int width = Math.max(first.width, second.width), height =
                                                                 first.height + 1 + second.height;
            Boxes.Box box = new Boxes.Box(width + 2, height, first.height, "binom");
            box.add(first, center(first, width) + 1, 0, "upper: ");
            box.add(second, center(second, width) + 1, first.height + 1, "lower: ");
            drawDelimiter(box, "(", 0, height);
            drawDelimiter(box, ")", width + 1, height);
            return box;
        }
        Boxes.Box radical(Boxes.Box body, Boxes.Box index) {
            int k = body.height, e = index == null ? 0 : Math.max(0, index.width - 1),
                top = index == null ? 0 : Math.max(0, index.height - k);
            Boxes.Box box = new Boxes.Box(e + k + 1 + body.width, k + 1 + top,
                                          body.baseline + 1 + top, index == null ? "sqrt" : "root");
            box.draw("_".repeat(body.width), e + k + 1, top);
            box.draw("\\", e, k + top);
            for (int row = 1; row <= k; row++)
                box.draw("/", e + k - row + 1, row + top);
            if (index != null) {
                box.add(index, 0, k - index.height + top, "index: ");
                box.add(body, e + k + 1, 1 + top, "body: ");
            } else
                box.add(body, e + k + 1, 1);
            return box;
        }
        Boxes.Box delimit(Boxes.Box body, String left, String right) {
            int lw = left.equals(".") ? 0 : 1, rw = right.equals(".") ? 0 : 1;
            Boxes.Box box = new Boxes.Box(lw + body.width + rw, body.height, body.baseline,
                                          "delim " + left + " " + right);
            box.add(body, lw, 0);
            drawDelimiter(box, left, 0, body.height);
            drawDelimiter(box, right, lw + body.width, body.height);
            return box;
        }
        Boxes.Box matrix(Parser.Matrix matrix, boolean normal) {
            List<List<Boxes.Box>> cells = new ArrayList<>();
            for (List<Parser.Node> row : matrix.rows()) {
                List<Boxes.Box> converted = new ArrayList<>();
                for (Parser.Node cell : row)
                    converted.add(typeset(cell, normal));
                cells.add(converted);
            }
            int rows = cells.size(), cols = cells.getFirst().size(), cg = params.get("col_gap"),
                rg = params.get("row_gap");
            int[] widths = new int[cols], ascents = new int[rows], descents = new int[rows];
            for (int i = 0; i < rows; i++)
                for (int j = 0; j < cols; j++) {
                    Boxes.Box cell = cells.get(i).get(j);
                    widths[j] = Math.max(widths[j], cell.width);
                    ascents[i] = Math.max(ascents[i], cell.baseline);
                    descents[i] = Math.max(descents[i], cell.descent());
                }
            int bodyWidth = Arrays.stream(widths).sum() + cg * (cols - 1),
                bodyHeight = Arrays.stream(ascents).sum() + Arrays.stream(descents).sum() + rows +
                             rg * (rows - 1);
            String env = matrix.environment();
            int shift = env.equals("matrix") ? 0 : 2, extra = env.equals("matrix")  ? 0
                                                              : env.equals("cases") ? 2
                                                                                    : 4;
            Boxes.Box box = new Boxes.Box(bodyWidth + extra, bodyHeight, (bodyHeight - 1) / 2,
                                          env + " rows=" + rows + " cols=" + cols);
            int y = 0;
            for (int i = 0; i < rows; i++) {
                int x = shift;
                for (int j = 0; j < cols; j++) {
                    Boxes.Box cell = cells.get(i).get(j);
                    int offset = env.equals("cases") ? 0 : center(cell, widths[j]);
                    box.add(cell, x + offset, y + ascents[i] - cell.baseline,
                            "cell " + (i + 1) + "," + (j + 1) + ": ");
                    x += widths[j] + cg;
                }
                y += ascents[i] + descents[i] + 1 + rg;
            }
            if (env.equals("cases"))
                drawDelimiter(box, "\\{", 0, bodyHeight);
            else if (!env.equals("matrix")) {
                String left = env.equals("pmatrix")   ? "("
                              : env.equals("bmatrix") ? "["
                                                      : "|",
                       right = env.equals("pmatrix")   ? ")"
                               : env.equals("bmatrix") ? "]"
                                                       : "|";
                drawDelimiter(box, left, 0, bodyHeight);
                drawDelimiter(box, right, bodyWidth + 3, bodyHeight);
            }
            return box;
        }
        Boxes.Box accent(Parser.Accent accent, boolean normal) {
            Boxes.Box body = typeset(accent.body(), normal);
            String name = accent.name();
            int width = body.width;
            if (Set.of("hat", "dot", "tilde").contains(name))
                width = Math.max(width, 1);
            else if (name.equals("vec"))
                width = Math.max(width, 2);
            else if (Set.of("overbrace", "underbrace").contains(name))
                width += 2;
            Boxes.Box box =
                new Boxes.Box(width, body.height + 1,
                              name.equals("underbrace") ? body.baseline : body.baseline + 1, name);
            if (name.equals("underbrace")) {
                box.add(body, 1, 0);
                box.draw("\\"
                             + "-".repeat(body.width) + "/",
                         0, body.height);
            } else if (name.equals("overbrace")) {
                box.add(body, 1, 1);
                box.draw("/"
                         + "-".repeat(body.width) + "\\");
            } else {
                box.add(body, 0, 1);
                if (name.equals("overline"))
                    box.draw("_".repeat(width));
                else if (name.equals("vec"))
                    box.draw("-".repeat(width - 1) + ">");
                else
                    box.draw(name.equals("hat")   ? "^"
                             : name.equals("dot") ? "."
                                                  : "~",
                             (width - 1) / 2, 0);
            }
            return box;
        }
    }
    record Line(int start, int end, int indent, int width) {}
    record Overfull(int number, int width) {}
    record Placement(List<Canvas.Root> roots, int lineCount, int width, int height,
                     List<Overfull> overfull) {}
    static List<Line> buildLines(Set<Integer> breaks, List<Layout.Types> types,
                                 List<Boxes.Box> boxes, int[] starts, Map<String, Integer> params) {
        List<Line> result = new ArrayList<>();
        int position = 0;
        Integer alignment = null;
        int relationWidth = 0;
        while (position < boxes.size()) {
            int indent = position == 0       ? 0
                         : alignment == null ? params.get("indent")
                         : types.get(position).left().equals("relation")
                             ? alignment
                             : alignment + relationWidth + params.get("rel_space");
            List<Integer> ends = new ArrayList<>();
            for (int end : breaks)
                if (end > position)
                    ends.add(end);
            ends.sort(Integer::compare);
            ends.add(boxes.size());
            Line chosen = null;
            for (int end : ends) {
                int width = starts[end - 1] + boxes.get(end - 1).width - starts[position];
                if (chosen == null || indent + width <= params.get("width"))
                    chosen = new Line(position, end, indent, width);
            }
            result.add(chosen);
            if (position == 0)
                for (int index = 0; index < chosen.end(); index++)
                    if (types.get(index).left().equals("relation")) {
                        alignment = starts[index];
                        relationWidth = boxes.get(index).width;
                        break;
                    }
            position = chosen.end();
        }
        return result;
    }
    static Placement placeFormula(Formula formula, Typesetter typesetter,
                                  Map<String, Integer> params) {
        List<Parser.Node> nodes = formula.nodes;
        Layout.Spacing spacing = Layout.spacing(nodes, true, params);
        List<Boxes.Box> boxes = new ArrayList<>();
        for (Parser.Node node : nodes)
            boxes.add(typesetter.typeset(node, true));
        int[] starts = new int[nodes.size()];
        int x = 0;
        for (int i = 0; i < boxes.size(); i++) {
            starts[i] = x;
            x += boxes.get(i).width;
            if (i < spacing.gaps().size())
                x += spacing.gaps().get(i);
        }
        Set<Integer> relations = new TreeSet<>(), plus = new TreeSet<>(),
                     punctuation = new TreeSet<>();
        for (int i = 1; i < nodes.size(); i++) {
            if (spacing.types().get(i).left().equals("relation"))
                relations.add(i);
            if (nodes.get(i) instanceof Parser.Atom atom && atom.kind().equals("symbol") &&
                Set.of("+", "-").contains(atom.value()) &&
                spacing.types().get(i).left().equals("binary"))
                plus.add(i);
            if (spacing.types().get(i - 1).right().equals("punctuation"))
                punctuation.add(i);
        }
        Set<Integer> breaks = new TreeSet<>(relations);
        List<Line> plan = List.of();
        for (int stage = 0; stage < 3; stage++) {
            if (stage == 1)
                breaks.addAll(plus);
            if (stage == 2)
                breaks.addAll(punctuation);
            plan = buildLines(breaks, spacing.types(), boxes, starts, params);
            boolean fits = true;
            for (Line line : plan)
                if (line.indent() + line.width() > params.get("width"))
                    fits = false;
            if (fits)
                break;
        }
        List<Canvas.Root> roots = new ArrayList<>();
        List<Overfull> overfull = new ArrayList<>();
        int width = 0, height = 0;
        for (int i = 0; i < plan.size(); i++) {
            Line part = plan.get(i);
            Boxes.Box line =
                Layout.row(boxes.subList(part.start(), part.end()),
                           spacing.gaps().subList(part.start(), part.end() - 1), "line " + (i + 1));
            roots.add(new Canvas.Root(line, part.indent(), height));
            height += line.height;
            width = Math.max(width, part.indent() + line.width);
            if (part.indent() + part.width() > params.get("width"))
                overfull.add(new Overfull(i + 1, part.indent() + part.width()));
        }
        if (formula.tagString != null) {
            String tag = formula.tagString;
            int tx = params.get("width") - tag.length();
            Canvas.Root last = roots.getLast();
            int ty;
            if (tx >= last.x() + last.box().width + 2)
                ty = last.y() + last.box().baseline;
            else {
                ty = height;
                height++;
            }
            Boxes.Box tagBox = new Boxes.Box(tag.length(), 1, 0, "tag \"" + tag + "\"");
            tagBox.draw(tag);
            roots.add(new Canvas.Root(tagBox, tx, ty));
            width = Math.max(width, tx + tagBox.width);
        }
        return new Placement(roots, plan.size(), width, height, overfull);
    }
    static String tree(Parser.Node node) {
        if (node instanceof Parser.Atom atom)
            return switch (atom.kind()) {
                case "symbol" -> "'" + atom.value() + "'";
                case "text" -> "\"" + atom.value() + "\"";
                case "reference" -> "(eqref \"" + atom.value() + "\")";
                default -> atom.value();
            };
        if (node instanceof Parser.Matrix matrix) {
            StringJoiner rows = new StringJoiner(" ");
            for (List<Parser.Node> row : matrix.rows()) {
                StringJoiner cells = new StringJoiner(" ");
                for (Parser.Node cell : row)
                    cells.add(tree(cell));
                rows.add("[" + cells + "]");
            }
            return "(" + matrix.environment() + " " + rows + ")";
        }
        if (node instanceof Parser.Delimited delimited) {
            String left = delimited.left().length() == 1 ? "'" + delimited.left() + "'"
                                                         : delimited.left(),
                   right = delimited.right().length() == 1 ? "'" + delimited.right() + "'"
                                                           : delimited.right();
            return "(delim " + left + " " + right + " " + tree(delimited.body()) + ")";
        }
        String name = switch (node) {
            case Parser.Row ignored -> "row";
            case Parser.Binary binary -> binary.kind();
            case Parser.Radical radical -> radical.index() == null ? "sqrt" : "root";
            case Parser.Script script ->
                script.sub() == null ? "sup" : script.sup() == null ? "sub" : "subsup";
            case Parser.Accent accent -> accent.name();
            default -> throw new IllegalStateException();
        };
        StringBuilder result = new StringBuilder("(" + name);
        for (Parser.Node child : children(node))
            result.append(" ").append(tree(child));
        return result.append(")").toString();
    }
    static final class LinearNotation {
        Map<String, Integer> params;
        Map<String, String> references;
        LinearNotation(Map<String, Integer> params, Map<String, String> references) {
            this.params = params;
            this.references = references;
        }
        String row(List<Parser.Node> nodes, boolean normal) {
            List<Integer> gaps = Layout.spacing(nodes, normal, params).gaps();
            StringBuilder result = new StringBuilder();
            for (int i = 0; i < nodes.size(); i++) {
                if (i > 0)
                    result.append(" ".repeat(gaps.get(i - 1)));
                result.append(node(nodes.get(i), normal));
            }
            return result.toString();
        }
        String parenthesize(Parser.Node node, boolean normal, boolean script) {
            String value = node(node, normal);
            return node instanceof Parser.Row ||
                    node instanceof Parser.Binary binary && binary.kind().equals("frac") ||
                    script && node instanceof Parser.Script
                ? "(" + value + ")"
                : value;
        }
        String node(Parser.Node node, boolean normal) {
            return switch (node) {
                case Parser.Atom atom ->
                    atom.kind().equals("reference") ? references.getOrDefault(atom.value(), "(??)")
                                                    : Boxes.display(atom);
                case Parser.Row row -> row(row.children(), normal);
                case Parser.Script script -> {
                    String value = parenthesize(script.base(), normal, true);
                    if (script.sub() != null)
                        value += "_" + parenthesize(script.sub(), false, false);
                    if (script.sup() != null)
                        value += "^" + parenthesize(script.sup(), false, false);
                    yield value;
                }
                case Parser.Delimited delimited ->
                    delimiterString(delimited.left()) + node(delimited.body(), normal) +
                        delimiterString(delimited.right());
                case Parser.Matrix matrix -> {
                    StringJoiner rows = new StringJoiner("; ");
                    for (List<Parser.Node> row : matrix.rows()) {
                        StringJoiner cells = new StringJoiner(", ");
                        for (Parser.Node cell : row)
                            cells.add(node(cell, normal));
                        rows.add(cells.toString());
                    }
                    yield matrix.environment() + "[" + rows + "]";
                }
                case Parser.Radical radical ->
                    radical.index() == null ? "sqrt(" + node(radical.body(), normal) + ")"
                                            : "root(" + node(radical.index(), false) + ", " +
                                                  node(radical.body(), normal) + ")";
                case Parser.Binary binary ->
                    binary.kind().equals("frac")
                        ? parenthesize(binary.first(), normal, false) + "/" +
                              parenthesize(binary.second(), normal, false)
                        : binary.kind() + "(" +
                              node(binary.first(), binary.kind().equals("binom") && normal) + ", " +
                              node(binary.second(), normal) + ")";
                case Parser.Accent accent ->
                    accent.name() + "(" + node(accent.body(), normal) + ")";
            };
        }
    }
    static List<String> diagnostic(Formula formula, int column, String message, boolean warning) {
        return List.of("formula " + formula.number + ", column " + column + ": " +
                           (warning ? "warning: " : "") + message,
                       "  " + formula.line, " ".repeat(column + 1) + "^");
    }
    static final class Reports {
        Map<String, Integer> params;
        Map<String, String> references;
        List<Formula> formulas;
        Typesetter typesetter;
        LinearNotation linear;
        List<String> rendered = new ArrayList<>(), boxes = new ArrayList<>(),
                     trees = new ArrayList<>(), errors = new ArrayList<>();
        Map<String, Integer> kinds = new TreeMap<>();
        int totalBoxes, maxDepth, validCount, errorCount, warningCount, overfullCount;
        Reports(Map<String, Integer> params, List<Formula> formulas,
                Map<String, String> references) {
            this.params = params;
            this.formulas = formulas;
            this.references = references;
            typesetter = new Typesetter(params, references);
            linear = new LinearNotation(params, references);
        }
        void recordError(Formula formula) {
            errorCount++;
            rendered.add("(error)");
            boxes.add("formula " + formula.number + ": error");
            trees.add("formula " + formula.number + ": error");
            errors.addAll(
                diagnostic(formula, formula.error.column, formula.error.getMessage(), false));
        }
        void recordValid(Formula formula) {
            validCount++;
            for (Parser.Node node : formula.nodes)
                warnings(node, formula, references);
            formula.warnings.sort(Comparator.comparingInt(Warning::column));
            Placement placed = placeFormula(formula, typesetter, params);
            rendered.addAll(Canvas.draw(placed.roots(), placed.width(), placed.height()));
            List<Canvas.Entry> entries = Canvas.entries(placed.roots());
            int depth = 0;
            for (Canvas.Entry entry : entries)
                depth = Math.max(depth, entry.level() + 1);
            totalBoxes += entries.size();
            maxDepth = Math.max(maxDepth, depth);
            boxes.add("formula " + formula.number + ": lines=" + placed.lineCount() +
                      " width=" + placed.width() + " height=" + placed.height() +
                      " boxes=" + entries.size() + " depth=" + depth);
            for (Canvas.Entry entry : entries) {
                boxes.add(entry.line());
                kinds.merge(entry.kind(), 1, Integer::sum);
            }
            StringJoiner notation = new StringJoiner(" ");
            for (Parser.Node node : formula.nodes)
                notation.add(tree(node));
            trees.add("formula " + formula.number + ": " + notation);
            String linearText = Canvas.trim(linear.row(formula.nodes, true));
            trees.add("  linear:" + (linearText.isEmpty() ? "" : " " + linearText));
            if (formula.tagString != null)
                trees.add("  tag: " + formula.tagString);
            warningCount += formula.warnings.size();
            for (Warning warning : formula.warnings)
                errors.addAll(diagnostic(formula, warning.column(), warning.message(), true));
            overfullCount += placed.overfull().size();
            for (Overfull overfull : placed.overfull())
                errors.add("formula " + formula.number + ": line " + overfull.number() +
                           " is overfull (width " + overfull.width() + " > " + params.get("width") +
                           ")");
        }
        void build() {
            for (Formula formula : formulas) {
                if (!rendered.isEmpty())
                    rendered.add("");
                rendered.add("formula " + formula.number);
                if (formula.error == null)
                    recordValid(formula);
                else
                    recordError(formula);
            }
            boxes.add("summary: boxes=" + totalBoxes + " max_depth=" + maxDepth);
            for (var entry : kinds.entrySet())
                boxes.add("  " + entry.getKey() + ": " + entry.getValue());
            errors.add("formulas=" + formulas.size() + " rendered=" + validCount + " errors=" +
                       errorCount + " warnings=" + warningCount + " overfull=" + overfullCount);
        }
        void write() throws Exception {
            Files.createDirectories(Path.of("output"));
            writeLines("rendered.txt", rendered);
            writeLines("boxes.txt", boxes);
            writeLines("trees.txt", trees);
            writeLines("errors.txt", errors);
        }
    }
    static void writeLines(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception {
        Map<String, Integer> params = new HashMap<>();
        for (String line :
             Files.readAllLines(Path.of("input", "params.txt"), StandardCharsets.US_ASCII)) {
            String[] fields = line.split(" ");
            params.put(fields[0], Integer.parseInt(fields[1]));
        }
        List<Formula> formulas = new ArrayList<>();
        for (String line :
             Files.readAllLines(Path.of("input", "formulas.txt"), StandardCharsets.US_ASCII))
            formulas.add(new Formula(formulas.size() + 1, line));
        Map<String, String> references = referenceTable(formulas);
        Reports reports = new Reports(params, formulas, references);
        reports.build();
        reports.write();
    }
}
