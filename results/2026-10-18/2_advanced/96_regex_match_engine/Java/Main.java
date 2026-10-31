import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.math.BigInteger;
public final class Main {
    interface Searcher {
        int[] search(int start);
        int steps();
    }
    enum Op { CHAR, ANY, CLASS, SPLIT, JMP, SAVE, ASSERT, BACKREF, LOOK, MATCH }
    record Instruction(Op op, int x, int y, int value, BitSet characters, boolean negated,
                       String kind) {
        Instruction(Op op) { this(op, 0, 0, 0, null, false, null); }
        Instruction withTargets(int x, int y) {
            return new Instruction(op, x, y, value, characters, negated, kind);
        }
    }
    static boolean matchesCharacter(Instruction instruction, String text, int position,
                                    String flags) {
        return switch (instruction.op()) {
            case CHAR -> Charset.testChar(text, position, (char)instruction.value(), flags);
            case ANY -> Charset.testAny(text, position, flags);
            case CLASS ->
                Charset.testClass(text, position, instruction.characters(), instruction.negated(),
                                  flags);
            default -> false;
        };
    }
    sealed interface Node permits Literal, Any, CharacterClass, Assertion, Backreference, Group,
        Look, Sequence, Alternation, Repeat {}
    record Literal(char value) implements Node {}
    record Any() implements Node {}
    record CharacterClass(BitSet characters, boolean negated) implements Node {}
    record Assertion(String kind) implements Node {}
    static final class Backreference implements Node {
        int number, column;
        String name;
        Backreference(int number, String name, int column) {
            this.number = number;
            this.name = name;
            this.column = column;
        }
    }
    record Group(int number, Node child) implements Node {}
    record Look(boolean positive, Node child) implements Node {}
    record Sequence(List<Node> elements) implements Node {}
    record Alternation(List<Node> elements) implements Node {}
    enum Mode { GREEDY, LAZY, POSSESSIVE }
    record Repeat(Node child, int lower, Integer upper, Mode mode) implements Node {}
    static final class PatternError extends RuntimeException {
        int column;
        PatternError(String message, int column) {
            super(message);
            this.column = column;
        }
    }
    record ClassItem(Integer character, BitSet characters) {}
    static final class PatternParser {
        String text;
        int index, groups;
        Map<String, Integer> named = new LinkedHashMap<>();
        List<Backreference> backrefs = new ArrayList<>();
        PatternParser(String text) { this.text = text; }
        int peek() { return peek(0); }
        int peek(int offset) {
            return index + offset < text.length() ? text.charAt(index + offset) : -1;
        }
        int take() {
            int c = peek();
            if (c >= 0)
                index++;
            return c;
        }
        void error(String message) { error(message, index + 1); }
        void error(String message, int column) { throw new PatternError(message, column); }
        boolean digit(int c) { return c >= '0' && c <= '9'; }
        boolean letter(int c) { return c >= 0 && Charset.letter((char)c); }
        boolean quantifier(int c) { return c == '*' || c == '+' || c == '?' || c == '{'; }
        String digits() {
            int start = index;
            while (digit(peek()))
                take();
            return text.substring(start, index);
        }
        String name() {
            if (!letter(peek()) && peek() != '_')
                error("invalid group name");
            int start = index;
            while (letter(peek()) || digit(peek()) || peek() == '_')
                take();
            String name = text.substring(start, index);
            if (peek() != '>')
                error("invalid group name");
            take();
            return name;
        }
        Node parse() {
            Node root = alternation();
            if (peek() >= 0)
                error("unmatched )");
            for (Backreference reference : backrefs)
                if (reference.name != null) {
                    Integer number = named.get(reference.name);
                    if (number == null)
                        error("unknown group name", reference.column);
                    reference.number = number;
                } else if (reference.number > groups)
                    error("invalid group reference", reference.column);
            return root;
        }
        Node alternation() {
            List<Node> children = new ArrayList<>();
            children.add(concatenation());
            while (peek() == '|') {
                take();
                children.add(concatenation());
            }
            return children.size() == 1 ? children.getFirst() : new Alternation(children);
        }
        Node concatenation() {
            List<Node> children = new ArrayList<>();
            while (peek() >= 0 && peek() != '|' && peek() != ')')
                children.add(quantified());
            return children.size() == 1 ? children.getFirst() : new Sequence(children);
        }
        Node quantified() {
            if (quantifier(peek()))
                error("nothing to repeat");
            Node element = element();
            if (!quantifier(peek()))
                return element;
            if (element instanceof Assertion || element instanceof Look)
                error("nothing to repeat");
            int beginning = index + 1, character = take(), lower = 0;
            Integer upper = null;
            if (character == '*')
                lower = 0;
            else if (character == '+')
                lower = 1;
            else if (character == '?') {
                lower = 0;
                upper = 1;
            } else {
                String low = digits();
                if (low.isEmpty())
                    error("invalid quantifier", beginning);
                lower = Integer.parseInt(low);
                if (peek() == '}')
                    upper = lower;
                else if (peek() == ',') {
                    take();
                    if (peek() != '}') {
                        String high = digits();
                        if (high.isEmpty())
                            error("invalid quantifier", beginning);
                        upper = Integer.parseInt(high);
                    }
                } else
                    error("invalid quantifier", beginning);
                if (peek() != '}')
                    error("invalid quantifier", beginning);
                take();
                if (lower > 100 || upper != null && upper > 100)
                    error("quantifier too large", beginning);
                if (upper != null && lower > upper)
                    error("quantifier range out of order", beginning);
            }
            Mode mode = Mode.GREEDY;
            if (peek() == '?') {
                take();
                mode = Mode.LAZY;
            } else if (peek() == '+') {
                take();
                mode = Mode.POSSESSIVE;
            }
            if (quantifier(peek()))
                error("nested quantifier");
            return new Repeat(element, lower, upper, mode);
        }
        Node element() {
            int c = peek();
            if (c == '(')
                return group();
            if (c == '[')
                return characterClass();
            if (c == '\\')
                return escape();
            take();
            if (c == '.')
                return new Any();
            if (c == '^' || c == '$')
                return new Assertion(c == '^' ? "BOL" : "EOL");
            return new Literal((char)c);
        }
        Node group() {
            int column = index + 1;
            take();
            String kind = "capture", namedGroup = null;
            if (peek() == '?') {
                take();
                int special = peek();
                if (special != ':' && special != '=' && special != '!' && special != '<')
                    error("invalid group", column);
                take();
                kind = special == ':'   ? "noncapture"
                       : special == '=' ? "ahead"
                       : special == '!' ? "negative"
                                        : "capture";
                if (special == '<') {
                    int nameColumn = index + 1;
                    namedGroup = name();
                    if (named.containsKey(namedGroup))
                        error("duplicate group name", nameColumn);
                }
            }
            int number = 0;
            if (kind.equals("capture")) {
                number = ++groups;
                if (namedGroup != null)
                    named.put(namedGroup, number);
            }
            Node content = alternation();
            if (peek() != ')')
                error("missing )", column);
            take();
            if (kind.equals("noncapture"))
                return content;
            if (kind.equals("ahead") || kind.equals("negative"))
                return new Look(kind.equals("ahead"), content);
            return new Group(number, content);
        }
        ClassItem classItem() {
            int c = peek();
            if (c != '\\')
                return new ClassItem(take(), null);
            int column = index + 1;
            take();
            int special = peek();
            if (special < 0)
                error("trailing backslash", column);
            take();
            if ("dDwWsS".indexOf(special) >= 0)
                return new ClassItem(null, Charset.escapedSet((char)special));
            if (special == 'n' || special == 't')
                return new ClassItem(special == 'n' ? 10 : 9, null);
            if (letter(special) || digit(special))
                error("invalid escape", column);
            return new ClassItem(special, null);
        }
        Node characterClass() {
            int opening = index + 1;
            take();
            boolean negate = peek() == '^';
            if (negate)
                take();
            if (peek() == ']')
                error("empty class");
            BitSet values = new BitSet(128);
            while (true) {
                if (peek() < 0)
                    error("missing ]", opening);
                if (peek() == ']') {
                    take();
                    break;
                }
                ClassItem first = classItem();
                if (peek() == '-' && peek(1) >= 0 && peek(1) != ']') {
                    int column = index + 1;
                    take();
                    if (first.character() == null)
                        error("invalid range", column);
                    ClassItem last = classItem();
                    if (last.character() == null || first.character() > last.character())
                        error("invalid range", column);
                    values.set(first.character(), last.character() + 1);
                } else if (first.character() == null)
                    values.or(first.characters());
                else
                    values.set(first.character());
            }
            return new CharacterClass(values, negate);
        }
        Node escape() {
            int column = index + 1;
            take();
            int c = peek();
            if (c < 0)
                error("trailing backslash", column);
            take();
            if ("dDwWsS".indexOf(c) >= 0)
                return new CharacterClass(Charset.standard(Character.toLowerCase((char)c)),
                                          c >= 'A' && c <= 'Z');
            if (c == 'b' || c == 'B')
                return new Assertion(c == 'b' ? "WORD" : "NOTWORD");
            if (c == 'n' || c == 't')
                return new Literal(c == 'n' ? '\n' : '\t');
            if (c >= '1' && c <= '9') {
                Backreference reference =
                    new Backreference(Integer.parseInt((char)c + digits()), null, column);
                backrefs.add(reference);
                return reference;
            }
            if (c == 'k') {
                if (peek() != '<')
                    error("invalid escape", column);
                take();
                Backreference reference = new Backreference(-1, name(), column);
                backrefs.add(reference);
                return reference;
            }
            if (letter(c) || digit(c))
                error("invalid escape", column);
            return new Literal((char)c);
        }
    }
    static final class Compiler {
        List<Instruction> program = new ArrayList<>();
        int emit(Instruction instruction) {
            int address = program.size();
            program.add(instruction);
            return address;
        }
        int emit(Op op) { return emit(new Instruction(op)); }
        int value(Op op, int value) {
            return emit(new Instruction(op, 0, 0, value, null, false, null));
        }
        int kind(Op op, String kind) {
            return emit(new Instruction(op, 0, 0, 0, null, false, kind));
        }
        void patch(int index, int x, int y) {
            program.set(index, program.get(index).withTargets(x, y));
        }
        void compile(Node node) {
            switch (node) {
            case Literal literal -> value(Op.CHAR, literal.value());
            case Any ignored -> emit(Op.ANY);
            case CharacterClass characterClass ->
                emit(new Instruction(Op.CLASS, 0, 0, 0, characterClass.characters(),
                                     characterClass.negated(), null));
            case Assertion assertion -> kind(Op.ASSERT, assertion.kind());
            case Backreference reference -> value(Op.BACKREF, reference.number);
            case Group group -> {
                value(Op.SAVE, 2 * group.number());
                compile(group.child());
                value(Op.SAVE, 2 * group.number() + 1);
            }
            case Look look -> {
                int address = kind(Op.LOOK, look.positive() ? "AHEAD" : "NOT");
                compile(look.child());
                emit(Op.MATCH);
                patch(address, program.size(), 0);
            }
            case Sequence sequence -> {
                for (Node child : sequence.elements())
                    compile(child);
            }
            case Alternation alternation -> {
                List<Integer> endings = new ArrayList<>();
                for (int i = 0; i + 1 < alternation.elements().size(); i++) {
                    int split = emit(Op.SPLIT);
                    int continuation = program.size();
                    compile(alternation.elements().get(i));
                    int jump = emit(Op.JMP);
                    patch(split, continuation, program.size());
                    endings.add(jump);
                }
                compile(alternation.elements().getLast());
                for (int jump : endings)
                    patch(jump, program.size(), 0);
            }
            case Repeat repeat -> repeat(repeat);
            }
        }
        void split(int address, int continuation, int end, Mode mode) {
            patch(address, mode == Mode.LAZY ? end : continuation,
                  mode == Mode.LAZY ? continuation : end);
        }
        void repeat(Repeat repeat) {
            if (repeat.mode() == Mode.POSSESSIVE) {
                int address = kind(Op.LOOK, "ATOMIC");
                compile(new Repeat(repeat.child(), repeat.lower(), repeat.upper(), Mode.GREEDY));
                emit(Op.MATCH);
                patch(address, program.size(), 0);
                return;
            }
            if (repeat.upper() == null && repeat.lower() == 0) {
                int address = emit(Op.SPLIT), continuation = program.size();
                compile(repeat.child());
                int jump = emit(Op.JMP);
                patch(jump, address, 0);
                split(address, continuation, program.size(), repeat.mode());
                return;
            }
            if (repeat.upper() == null) {
                for (int i = 0; i < repeat.lower() - 1; i++)
                    compile(repeat.child());
                int beginning = program.size();
                compile(repeat.child());
                int address = emit(Op.SPLIT);
                split(address, beginning, program.size(), repeat.mode());
                return;
            }
            for (int i = 0; i < repeat.lower(); i++)
                compile(repeat.child());
            List<int[]> optional = new ArrayList<>();
            for (int i = 0; i < repeat.upper() - repeat.lower(); i++) {
                int address = emit(Op.SPLIT), continuation = program.size();
                compile(repeat.child());
                optional.add(new int[] {address, continuation});
            }
            int end = program.size();
            for (int[] pair : optional)
                split(pair[0], pair[1], end, repeat.mode());
        }
        List<Instruction> program(Node root) {
            value(Op.SAVE, 0);
            compile(root);
            value(Op.SAVE, 1);
            emit(Op.MATCH);
            return program;
        }
    }
    record LengthRange(BigInteger minimum, BigInteger maximum) {}
    record First(BitSet characters, boolean nullable) {}
    static LengthRange lengthRange(Node node) {
        if (node instanceof Literal || node instanceof Any || node instanceof CharacterClass)
            return new LengthRange(BigInteger.ONE, BigInteger.ONE);
        if (node instanceof Assertion || node instanceof Look)
            return new LengthRange(BigInteger.ZERO, BigInteger.ZERO);
        if (node instanceof Backreference)
            return new LengthRange(BigInteger.ZERO, null);
        if (node instanceof Group group)
            return lengthRange(group.child());
        if (node instanceof Repeat repeat) {
            LengthRange child = lengthRange(repeat.child());
            BigInteger maximum = child.maximum() != null && child.maximum().signum() == 0
                                     ? BigInteger.ZERO
                                 : child.maximum() == null || repeat.upper() == null
                                     ? null
                                     : child.maximum().multiply(BigInteger.valueOf(repeat.upper()));
            return new LengthRange(child.minimum().multiply(BigInteger.valueOf(repeat.lower())),
                                   maximum);
        }
        List<Node> children = node instanceof Sequence sequence ? sequence.elements()
                                                                : ((Alternation)node).elements();
        boolean concatenate = node instanceof Sequence;
        BigInteger minimum = concatenate ? BigInteger.ZERO : null, maximum = BigInteger.ZERO;
        for (Node child : children) {
            LengthRange range = lengthRange(child);
            minimum = concatenate       ? minimum.add(range.minimum())
                      : minimum == null ? range.minimum()
                                        : minimum.min(range.minimum());
            if (maximum != null)
                maximum = range.maximum() == null ? null
                          : concatenate           ? maximum.add(range.maximum())
                                                  : maximum.max(range.maximum());
        }
        return new LengthRange(minimum, maximum);
    }
    static First firstCharacters(Node node, String flags) {
        if (node instanceof Literal literal) {
            BitSet chars = Charset.fromCodes(literal.value());
            if (flags.indexOf('i') >= 0 && Charset.letter(literal.value()))
                chars.set(Charset.switched(literal.value()));
            return new First(chars, false);
        }
        if (node instanceof Any) {
            BitSet chars = (BitSet)Charset.ASCII.clone();
            if (flags.indexOf('s') < 0)
                chars.clear(10);
            return new First(chars, false);
        }
        if (node instanceof CharacterClass characterClass) {
            BitSet chars = new BitSet(128);
            for (int code = 0; code < 128; code++)
                if (Charset.testClass(String.valueOf((char)code), 0, characterClass.characters(),
                                      characterClass.negated(), flags))
                    chars.set(code);
            return new First(chars, false);
        }
        if (node instanceof Assertion || node instanceof Look)
            return new First(new BitSet(), true);
        if (node instanceof Backreference)
            return new First((BitSet)Charset.ASCII.clone(), true);
        if (node instanceof Group group)
            return firstCharacters(group.child(), flags);
        if (node instanceof Repeat repeat) {
            if (repeat.upper() != null && repeat.upper() == 0)
                return new First(new BitSet(), true);
            First child = firstCharacters(repeat.child(), flags);
            return new First(child.characters(), child.nullable() || repeat.lower() == 0);
        }
        BitSet chars = new BitSet(128);
        if (node instanceof Alternation alternation) {
            boolean nullable = false;
            for (Node child : alternation.elements()) {
                First first = firstCharacters(child, flags);
                chars.or(first.characters());
                nullable |= first.nullable();
            }
            return new First(chars, nullable);
        }
        for (Node child : ((Sequence)node).elements()) {
            First first = firstCharacters(child, flags);
            chars.or(first.characters());
            if (!first.nullable())
                return new First(chars, false);
        }
        return new First(chars, true);
    }
    static List<String> fields(String text, int maximum) {
        List<String> fields = new ArrayList<>();
        int start = 0;
        while (fields.size() + 1 < maximum) {
            int space = text.indexOf(' ', start);
            if (space < 0)
                break;
            fields.add(text.substring(start, space));
            start = space + 1;
        }
        fields.add(text.substring(start));
        return fields;
    }
    static String decodeQuoted(String text) {
        StringBuilder decoded = new StringBuilder();
        int position = 1;
        while (position < text.length() - 1) {
            char c = text.charAt(position++);
            if (c == '\\')
                c = switch (text.charAt(position++)) {
                    case 'n' -> '\n';
                    case 't' -> '\t';
                    case '\\' -> '\\';
                    default -> '"';
                };
            decoded.append(c);
        }
        return decoded.toString();
    }
    static final class PatternData {
        String name, flagsText, flags, text;
        Node root;
        List<Instruction> program;
        int groups;
        Map<String, Integer> named;
        boolean pike;
        PatternError error;
        PatternData(String line) {
            List<String> fields = fields(line, 3);
            name = fields.get(0);
            flagsText = fields.get(1);
            flags = flagsText.equals("-") ? "" : flagsText;
            text = fields.get(2);
            PatternParser parser = new PatternParser(text);
            try {
                root = parser.parse();
                program = new Compiler().program(root);
                groups = parser.groups;
                named = parser.named;
                pike = program.stream().allMatch(
                    instruction -> instruction.op() != Op.BACKREF && instruction.op() != Op.LOOK);
            } catch (PatternError error) {
                this.error = error;
            }
        }
    }
    record Command(int number, String line, String kind, String name, String subject, String mode,
                   String template) {}
    static Command command(String line, int number) {
        List<String> fields = fields(line, line.startsWith("REPLACE ") ? 5 : 3);
        if (fields.getFirst().equals("REPLACE"))
            return new Command(number, line, "REPLACE", fields.get(2), fields.get(3), fields.get(1),
                               decodeQuoted(fields.get(4)));
        if (fields.getFirst().equals("LIST"))
            return new Command(number, line, "LIST", fields.get(1), null, null, null);
        return new Command(number, line, fields.get(0), fields.get(1), fields.get(2), null, null);
    }
    sealed interface TemplatePart permits TemplateText, TemplateGroup {}
    record TemplateText(String text) implements TemplatePart {}
    record TemplateGroup(int group) implements TemplatePart {}
    static boolean decimal(String text) {
        if (text.isEmpty())
            return false;
        for (int i = 0; i < text.length(); i++)
            if (text.charAt(i) < '0' || text.charAt(i) > '9')
                return false;
        return true;
    }
    static List<TemplatePart> parseTemplate(String text, PatternData pattern) {
        List<TemplatePart> parts = new ArrayList<>();
        int position = 0;
        while (position < text.length()) {
            char c = text.charAt(position);
            if (c != '$') {
                parts.add(new TemplateText(String.valueOf(c)));
                position++;
                continue;
            }
            if (position + 1 >= text.length())
                return null;
            char next = text.charAt(position + 1);
            if (next == '$') {
                parts.add(new TemplateText("$"));
                position += 2;
                continue;
            }
            int group;
            if (next >= '0' && next <= '9') {
                group = next - '0';
                position += 2;
            } else if (next == '{') {
                int end = text.indexOf('}', position + 2);
                if (end < 0)
                    return null;
                String name = text.substring(position + 2, end);
                if (decimal(name))
                    group = Integer.parseInt(name);
                else if (pattern.named.containsKey(name))
                    group = pattern.named.get(name);
                else
                    return null;
                position = end + 1;
            } else
                return null;
            if (group > pattern.groups)
                return null;
            parts.add(new TemplateGroup(group));
        }
        return parts;
    }
    static String expandTemplate(List<TemplatePart> parts, int[] captures, String text) {
        StringBuilder result = new StringBuilder();
        for (TemplatePart part : parts)
            if (part instanceof TemplateText literal)
                result.append(literal.text());
            else {
                int group = ((TemplateGroup)part).group(), start = captures[2 * group],
                    end = captures[2 * group + 1];
                if (start >= 0 && end >= 0)
                    result.append(text, start, end);
            }
        return result.toString();
    }
    static List<int[]> scans(Searcher vm, String kind, int textLength) {
        List<int[]> found = new ArrayList<>();
        if (kind.equals("MATCH") || kind.equals("SEARCH") || kind.equals("REPLACE FIRST")) {
            int[] match = vm.search(0);
            if (match != null)
                found.add(match);
            return found;
        }
        int start = 0;
        while (start <= textLength) {
            int[] match = vm.search(start);
            if (match == null)
                break;
            found.add(match);
            start = match[1] > match[0] ? match[1] : match[1] + 1;
        }
        return found;
    }
    record Step(String engine, int count) {}
    static final class Evaluation {
        String status, engine, text;
        List<int[]> matches;
        List<TemplatePart> template;
        List<Step> steps = new ArrayList<>();
        Evaluation(String status) { this.status = status; }
    }
    static boolean sameMatches(List<int[]> first, List<int[]> second) {
        if (first.size() != second.size())
            return false;
        for (int i = 0; i < first.size(); i++)
            if (!Arrays.equals(first.get(i), second.get(i)))
                return false;
        return true;
    }
    static Evaluation execute(Command command, PatternData pattern, Map<String, String> subjects) {
        if (pattern.error != null)
            return new Evaluation("invalid pattern");
        if (command.kind().equals("LIST"))
            return new Evaluation("list");
        List<TemplatePart> template = null;
        if (command.kind().equals("REPLACE")) {
            template = parseTemplate(command.template(), pattern);
            if (template == null)
                return new Evaluation("invalid template");
        }
        String text = subjects.get(command.subject()), kind = command.kind().equals("REPLACE")
                                                                  ? "REPLACE " + command.mode()
                                                                  : command.kind();
        boolean full = command.kind().equals("MATCH"), aborted = false;
        BacktrackVm backtrack =
            new BacktrackVm(pattern.program, pattern.flags, pattern.groups, text, full);
        List<int[]> backtrackMatches = null;
        try {
            backtrackMatches = scans(backtrack, kind, text.length());
        } catch (BacktrackVm.TooManySteps error) {
            aborted = true;
        }
        Evaluation evaluation = new Evaluation("ok");
        evaluation.steps.add(new Step("backtrack", backtrack.steps()));
        if (pattern.pike) {
            PikeVm pike = new PikeVm(pattern.program, pattern.flags, pattern.groups, text, full);
            List<int[]> pikeMatches = scans(pike, kind, text.length());
            evaluation.steps.add(new Step("pike", pike.steps()));
            if (aborted) {
                evaluation.engine = "pike (backtrack: TOO_MANY_STEPS)";
                evaluation.matches = pikeMatches;
            } else if (!sameMatches(backtrackMatches, pikeMatches)) {
                evaluation.status = "MISMATCH";
                return evaluation;
            } else {
                evaluation.engine = "both";
                evaluation.matches = pikeMatches;
            }
        } else {
            if (aborted) {
                evaluation.status = "TOO_MANY_STEPS";
                return evaluation;
            }
            evaluation.engine = "backtrack";
            evaluation.matches = backtrackMatches;
        }
        evaluation.template = template;
        evaluation.text = text;
        return evaluation;
    }
    static List<String> matchLines(int[] captures, PatternData pattern, String text) {
        List<String> lines = new ArrayList<>();
        lines.add("match " + captures[0] + "-" + captures[1] + " " +
                  Formatter.quoted(text.substring(captures[0], captures[1])));
        for (int group = 1; group <= pattern.groups; group++) {
            int start = captures[2 * group], end = captures[2 * group + 1];
            lines.add(start < 0 || end < 0 ? "group " + group + " -"
                                           : "group " + group + " " + start + "-" + end + " " +
                                                 Formatter.quoted(text.substring(start, end)));
        }
        return lines;
    }
    static List<String> splitText(String text, List<int[]> matches) {
        List<String> pieces = new ArrayList<>();
        int previous = 0;
        for (int[] captures : matches) {
            pieces.add(text.substring(previous, captures[0]));
            previous = captures[1];
        }
        pieces.add(text.substring(previous));
        return pieces;
    }
    static String replacementText(String text, List<int[]> matches, List<TemplatePart> parts) {
        StringBuilder result = new StringBuilder();
        int previous = 0;
        for (int[] captures : matches) {
            result.append(text, previous, captures[0]);
            result.append(expandTemplate(parts, captures, text));
            previous = captures[1];
        }
        return result.append(text.substring(previous)).toString();
    }
    static List<String> renderResult(Command command, PatternData pattern, Evaluation evaluation) {
        List<String> lines = new ArrayList<>();
        lines.add("#" + command.number() + " " + command.line());
        if (evaluation.status.equals("list")) {
            lines.add("instructions " + pattern.program.size());
            return lines;
        }
        if (!evaluation.status.equals("ok")) {
            lines.add(evaluation.status);
            return lines;
        }
        String text = evaluation.text;
        List<int[]> matches = evaluation.matches;
        lines.add("engine " + evaluation.engine);
        switch (command.kind()) {
        case "MATCH", "SEARCH" -> {
            if (matches.isEmpty())
                lines.add("no match");
            else
                lines.addAll(matchLines(matches.getFirst(), pattern, text));
        }
        case "FINDALL" -> {
            lines.add("matches " + matches.size());
            for (int[] captures : matches)
                lines.addAll(matchLines(captures, pattern, text));
        }
        case "REPLACE" -> {
            lines.add("replacements " + matches.size());
            lines.add("result " +
                      Formatter.quoted(replacementText(text, matches, evaluation.template)));
        }
        case "SPLIT" -> {
            List<String> pieces = splitText(text, matches);
            lines.add("pieces " + pieces.size());
            lines.add("piece " + Formatter.quoted(pieces.getFirst()));
            for (int i = 0; i < matches.size(); i++) {
                int[] captures = matches.get(i);
                for (int group = 1; group <= pattern.groups; group++) {
                    int start = captures[2 * group], end = captures[2 * group + 1];
                    lines.add("group " + group + " " +
                              (start < 0 || end < 0
                                   ? "-"
                                   : Formatter.quoted(text.substring(start, end))));
                }
                lines.add("piece " + Formatter.quoted(pieces.get(i + 1)));
            }
        }
        }
        return lines;
    }
    static List<String> programListing(PatternData pattern) {
        LengthRange length = lengthRange(pattern.root);
        First first = firstCharacters(pattern.root, pattern.flags);
        List<Map.Entry<String, Integer>> named = new ArrayList<>(pattern.named.entrySet());
        named.sort(Map.Entry.comparingByValue());
        StringJoiner names = new StringJoiner(",");
        for (var entry : named)
            names.add(entry.getKey() + ":" + entry.getValue());
        List<String> lines = new ArrayList<>();
        lines.add("=== " + pattern.name);
        lines.add("flags=" + pattern.flagsText + " groups=" + pattern.groups +
                  " names=" + (named.isEmpty() ? "-" : names) + " length=" + length.minimum() +
                  ".." + (length.maximum() == null ? "inf" : length.maximum()) + " first=" +
                  (first.characters().isEmpty()
                       ? "-"
                       : Formatter.setNotation(first.characters(), false)) +
                  " pike=" + (pattern.pike ? "yes" : "no") + " size=" + pattern.program.size());
        for (int pc = 0; pc < pattern.program.size(); pc++)
            lines.add(pc + " " + Formatter.instruction(pattern.program.get(pc)));
        return lines;
    }
    static List<String> patternErrors(Map<String, PatternData> patterns) {
        List<String> lines = new ArrayList<>();
        for (PatternData pattern : patterns.values())
            if (pattern.error != null) {
                lines.add(pattern.name + ": " + pattern.error.getMessage() + " at column " +
                          pattern.error.column);
                lines.add("  " + pattern.text);
                lines.add(" ".repeat(pattern.error.column + 1) + "^");
            }
        return lines.isEmpty() ? List.of("no errors") : lines;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name),
                          lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception {
        Map<String, PatternData> patterns = new LinkedHashMap<>();
        for (String line :
             Files.readAllLines(Path.of("input", "patterns.txt"), StandardCharsets.US_ASCII)) {
            PatternData pattern = new PatternData(line);
            patterns.put(pattern.name, pattern);
        }
        Map<String, String> subjects = new HashMap<>();
        for (String line :
             Files.readAllLines(Path.of("input", "subjects.txt"), StandardCharsets.US_ASCII)) {
            List<String> fields = fields(line, 2);
            subjects.put(fields.get(0), decodeQuoted(fields.get(1)));
        }
        List<String> results = new ArrayList<>(), programs = new ArrayList<>(),
                     steps = new ArrayList<>(List.of("command,engine,steps"));
        int number = 0;
        for (String line :
             Files.readAllLines(Path.of("input", "commands.txt"), StandardCharsets.US_ASCII)) {
            Command command = command(line, ++number);
            PatternData pattern = patterns.get(command.name());
            Evaluation evaluation = execute(command, pattern, subjects);
            results.addAll(renderResult(command, pattern, evaluation));
            if (command.kind().equals("LIST") && pattern.error == null)
                programs.addAll(programListing(pattern));
            for (Step step : evaluation.steps)
                steps.add(command.number() + "," + step.engine() + "," + step.count());
        }
        if (programs.isEmpty())
            programs.add("no programs");
        Files.createDirectories(Path.of("output"));
        write("results.txt", results);
        write("programs.txt", programs);
        write("steps.csv", steps);
        write("errors.txt", patternErrors(patterns));
    }
}
