import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    static final Set<String> CONDITIONALS =
        Set.of("if", "ifdef", "ifndef", "elif", "elifdef", "elifndef", "else", "endif");
    static final class DirectiveError extends RuntimeException {
        DirectiveError(String message) { super(message); }
    }
    static final class Block {
        String kind;
        Definitions.Position position;
        boolean parent, chosen, active, elseSeen;
        Integer skipStart;
        Block(String kind, Definitions.Position position, boolean parent) {
            this.kind = kind;
            this.position = position;
            this.parent = parent;
        }
    }
    static final class Inclusion {
        IncludeManager.SourceFile source;
        int depth, offset;
        String displayFile;
        List<Block> stack = new ArrayList<>();
        List<Lexer.Token> segment = new ArrayList<>();
        Inclusion(IncludeManager.SourceFile source, int depth) {
            this.source = source;
            this.depth = depth;
            displayFile = source.path;
        }
        Definitions.Position position(int physical) {
            return new Definitions.Position(displayFile, physical + offset);
        }
        boolean skipping() { return !stack.isEmpty() && !stack.getLast().active; }
    }
    record Header(String rendering, String name, boolean quoted) {}
    record HeaderRead(Header header, int consumed) {}
    record Test(Long value, List<Lexer.Token> expanded) {}
    static boolean separatorNeeded(String left, String right) {
        return left.equals("/") && "/*".indexOf(right.charAt(0)) >= 0 ||
            Lexer.readToken(left + right, 0, false).end() != left.length();
    }
    static String outputRender(List<Lexer.Token> tokens) {
        StringBuilder result = new StringBuilder();
        String previous = null;
        for (Lexer.Token token : tokens) {
            if (previous != null && (token.space() || separatorNeeded(previous, token.spelling())))
                result.append(' ');
            result.append(token.spelling());
            previous = token.spelling();
        }
        return result.toString();
    }
    static String following(String heading, Collection<String> items) {
        return heading + (items.isEmpty() ? "" : " " + String.join(" ", items));
    }
    static HeaderRead headerSpecification(List<Lexer.Token> tokens, int position) {
        if (position >= tokens.size())
            return new HeaderRead(null, position);
        Lexer.Token token = tokens.get(position);
        if (token.kind().equals("string") || token.kind().equals("header")) {
            String text = token.spelling();
            return new HeaderRead(
                new Header(text, text.substring(1, text.length() - 1), text.startsWith("\"")),
                position + 1);
        }
        if (token.spelling().equals("<")) {
            int closing = position + 1;
            while (closing < tokens.size() && !tokens.get(closing).spelling().equals(">"))
                closing++;
            if (closing == tokens.size())
                throw new DirectiveError("missing terminating > character");
            String text = "<" + Lexer.render(tokens.subList(position + 1, closing)) + ">";
            return new HeaderRead(new Header(text, text.substring(1, text.length() - 1), false),
                                  closing + 1);
        }
        return new HeaderRead(null, position);
    }
    static boolean decimalToken(Lexer.Token token) {
        return token.kind().equals("number") && token.spelling().matches("[0-9]+");
    }
    static final class Preprocessor {
        Map<String, Definitions.Macro> macros = new TreeMap<>();
        Set<String> everDefined = new TreeSet<>(), poisoned = new HashSet<>();
        Map<String, List<Definitions.Macro>> saved = new HashMap<>();
        IncludeManager manager = new IncludeManager();
        Expander expander = new Expander(macros, this::diagnostic);
        List<String> output = new ArrayList<>(), history = new ArrayList<>(),
                     diagnostics = new ArrayList<>(), tree = new ArrayList<>(List.of("main.c")),
                     conditionalRecords = new ArrayList<>(), regions = new ArrayList<>();
        Map<String, Integer> diagnosticCounts = new HashMap<>(), conditionCounts = new HashMap<>();
        Definitions.Position previous;
        void diagnostic(Definitions.Position position, String kind, String message) {
            diagnostics.add(position + ": " + kind + ": " + message);
            diagnosticCounts.merge(kind, 1, Integer::sum);
        }
        void event(Definitions.Position position, String content) {
            history.add(position + ": " + content);
        }
        void poisonCheck(Inclusion context, List<Lexer.Token> tokens) {
            for (Lexer.Token token : tokens)
                if (token.kind().equals("identifier") && poisoned.contains(token.spelling()))
                    diagnostic(context.position(token.line()), "error",
                               "attempt to use poisoned \"" + token.spelling() + "\"");
        }
        void unusedCheck(Definitions.Macro macro) {
            if (macro.mainFile && macro.expanded == 0 && macro.tested == 0)
                diagnostic(macro.position, "warning", "macro \"" + macro.name + "\" is not used");
        }
        void define(List<Lexer.Token> tokens, Definitions.Position position, boolean mainFile) {
            Definitions.Macro macro;
            try {
                macro = Definitions.parse(tokens, position, mainFile);
            } catch (Definitions.DefinitionError error) {
                diagnostic(position, "error", error.getMessage());
                return;
            }
            Definitions.Macro previous = macros.get(macro.name);
            String operation;
            if (previous == null) {
                macros.put(macro.name, macro);
                everDefined.add(macro.name);
                operation = "define";
            } else if (previous.identical(macro))
                operation = "identical";
            else {
                unusedCheck(previous);
                diagnostic(position, "warning",
                           "\"" + macro.name + "\" redefined (previous definition at " +
                               previous.position + ")");
                macros.put(macro.name, macro);
                everDefined.add(macro.name);
                operation = "redefine";
            }
            event(position, operation + " " + macro.signature());
        }
        void undefine(List<Lexer.Token> tokens, Definitions.Position position) {
            String error = Definitions.checkName(tokens, "undef");
            if (error != null) {
                diagnostic(position, "error", error);
                return;
            }
            if (tokens.size() >= 2)
                diagnostic(position, "warning", "extra tokens at end of #undef directive");
            String name = tokens.getFirst().spelling();
            Definitions.Macro macro = macros.get(name);
            if (macro == null)
                event(position, "undef " + name + " (not defined)");
            else {
                unusedCheck(macro);
                macros.remove(name);
                event(position, "undef " + name);
            }
        }
        void processDefines() throws Exception {
            List<String> lines =
                Files.readAllLines(Path.of("input", "defines.txt"), StandardCharsets.US_ASCII);
            for (int i = 0; i < lines.size(); i++) {
                String line = lines.get(i);
                if (line.isEmpty())
                    continue;
                int equals = line.indexOf('=');
                String text = equals < 0
                                  ? line + " 1"
                                  : line.substring(0, equals) + " " + line.substring(equals + 1);
                define(Lexer.definition(text, i + 1),
                       new Definitions.Position("defines.txt", i + 1), false);
            }
        }
        void marker(String file, int line, Integer flag) {
            output.add("# " + line + " \"" + file + "\"" + (flag == null ? "" : " " + flag));
            previous = new Definitions.Position(file, line - 1);
        }
        void outputLine(Inclusion context, int physical, String text) {
            Definitions.Position position = context.position(physical);
            if (position.file().equals(previous.file()) && previous.line() < position.line() &&
                (long)position.line() <= (long)previous.line() + 8)
                for (int i = previous.line() + 1; i < position.line(); i++)
                    output.add("");
            else
                marker(position.file(), position.line(), null);
            output.add(text);
            previous = position;
            context.source.outputLines++;
        }
        void flush(Inclusion context) {
            List<Lexer.Token> segment = context.segment;
            context.segment = new ArrayList<>();
            if (segment.isEmpty())
                return;
            poisonCheck(context, segment);
            List<Lexer.Token> expanded = expander.expand(segment, context);
            int start = 0;
            while (start < expanded.size()) {
                int physical = expanded.get(start).line(), end = start + 1;
                while (end < expanded.size() && expanded.get(end).line() == physical)
                    end++;
                outputLine(context, physical, outputRender(expanded.subList(start, end)));
                start = end;
            }
        }
        boolean macroDefined(String name) {
            Definitions.Macro macro = macros.get(name);
            if (macro != null) {
                macro.tested++;
                return true;
            }
            return Definitions.BUILTINS.contains(name) || name.equals("__has_include");
        }
        List<Lexer.Token> replaceOperators(Inclusion context, List<Lexer.Token> operands) {
            List<Lexer.Token> replaced = new ArrayList<>();
            int position = 0;
            while (position < operands.size()) {
                Lexer.Token token = operands.get(position);
                int index;
                boolean value;
                if (token.kind().equals("identifier") && token.spelling().equals("defined")) {
                    index = position + 1;
                    boolean parenthesized =
                        index < operands.size() && operands.get(index).spelling().equals("(");
                    if (parenthesized)
                        index++;
                    if (index == operands.size() ||
                        !operands.get(index).kind().equals("identifier"))
                        throw new DirectiveError("operator \"defined\" requires an identifier");
                    String name = operands.get(index++).spelling();
                    if (parenthesized) {
                        if (index == operands.size() || !operands.get(index).spelling().equals(")"))
                            throw new DirectiveError("missing ')' after \"defined\"");
                        index++;
                    }
                    value = macroDefined(name);
                } else if (token.kind().equals("identifier") &&
                           token.spelling().equals("__has_include")) {
                    index = position + 1;
                    if (index == operands.size() || !operands.get(index).spelling().equals("("))
                        throw new DirectiveError("missing '(' after \"__has_include\"");
                    HeaderRead read = headerSpecification(operands, index + 1);
                    Header header = read.header();
                    index = read.consumed();
                    if (header == null || header.name().isEmpty())
                        throw new DirectiveError(
                            "operator \"__has_include\" requires a header-name");
                    if (index == operands.size() || !operands.get(index).spelling().equals(")"))
                        throw new DirectiveError("missing ')' after \"__has_include\" operand");
                    index++;
                    value = manager.search(header.name(), header.quoted()) != null;
                } else {
                    replaced.add(token);
                    position++;
                    continue;
                }
                replaced.add(
                    new Lexer.Token("number", value ? "1" : "0", token.line(), token.space()));
                position = index;
            }
            return replaced;
        }
        Test test(Inclusion context, Lexer.LogicalLine logical, String name,
                  List<Lexer.Token> operands) {
            Definitions.Position position = context.position(logical.tokens().getFirst().line());
            poisonCheck(context, operands);
            if (!name.equals("if") && !name.equals("elif")) {
                if (operands.isEmpty()) {
                    diagnostic(position, "error", "no macro name given in #" + name + " directive");
                    return new Test(null, null);
                }
                if (!operands.getFirst().kind().equals("identifier")) {
                    diagnostic(position, "error", "macro names must be identifiers");
                    return new Test(null, null);
                }
                if (operands.size() >= 2)
                    diagnostic(position, "warning",
                               "extra tokens at end of #" + name + " directive");
                boolean defined = macroDefined(operands.getFirst().spelling()),
                        value =
                            name.equals("ifndef") || name.equals("elifndef") ? !defined : defined;
                return new Test(value ? 1L : 0L, null);
            }
            List<Lexer.Token> replaced;
            try {
                replaced = replaceOperators(context, operands);
            } catch (DirectiveError error) {
                diagnostic(position, "error", error.getMessage());
                return new Test(null, null);
            }
            List<Lexer.Token> expanded = expander.expand(replaced, context);
            try {
                Expression.Node expression = Expression.parse(expanded, name);
                long value = Expression.evaluate(
                    expression, message -> diagnostic(position, "warning", message));
                return new Test(value, expanded);
            } catch (Expression.ExpressionError error) {
                diagnostic(position, "error", error.getMessage());
                return new Test(null, expanded);
            }
        }
        String testDescription(String name, Test test) {
            String description;
            if (test.value() == null)
                description = "not taken (error)";
            else {
                description = test.value() != 0 ? "taken" : "not taken";
                if (name.equals("if") || name.equals("elif"))
                    description += " (value " + test.value() + ")";
            }
            if (test.expanded() != null)
                description += " [" + outputRender(test.expanded()) + "]";
            return description;
        }
        void closeRegion(Inclusion context, Block block, int end) {
            Integer start = block.skipStart;
            if (start != null && end >= start) {
                Definitions.Position first = context.position(start), last = context.position(end);
                regions.add(first + "-" + last.line() + " lines=" + (end - start + 1));
                context.source.skippedLines += end - start + 1;
            }
            block.skipStart = null;
        }
        void conditionalRecord(Definitions.Position position, int depth, String name,
                               List<Lexer.Token> operands, String description) {
            String directive =
                "#" + name + (operands.isEmpty() ? "" : " " + Lexer.render(operands));
            conditionalRecords.add(position + ": "
                                   + "  ".repeat(depth) + directive + " => " + description);
            String[][] categories = {{"taken", "taken"},
                                     {"not taken", "not_taken"},
                                     {"skipped", "skipped"},
                                     {"not evaluated", "not_evaluated"},
                                     {"closes", "endif"}};
            for (String[] category : categories)
                if (description.startsWith(category[0])) {
                    conditionCounts.merge(category[1], 1, Integer::sum);
                    break;
                }
        }
        void conditional(Inclusion context, Lexer.LogicalLine logical, String name,
                         List<Lexer.Token> operands) {
            Definitions.Position position = context.position(logical.tokens().getFirst().line());
            if (IncludeManager.STARTS.contains(name)) {
                boolean parent = context.stack.isEmpty() || context.stack.getLast().active;
                Block block = new Block(name, position, parent);
                String description;
                if (parent) {
                    Test test = test(context, logical, name, operands);
                    if (test.value() != null && test.value() != 0)
                        block.chosen = block.active = true;
                    else
                        block.skipStart = logical.end() + 1;
                    description = testDescription(name, test);
                } else
                    description = "skipped";
                conditionalRecord(position, context.stack.size(), name, operands, description);
                context.stack.add(block);
                return;
            }
            if (context.stack.isEmpty()) {
                diagnostic(position, "error", "#" + name + " without #if");
                return;
            }
            Block block = context.stack.getLast();
            int depth = context.stack.size() - 1;
            closeRegion(context, block, logical.start() - 1);
            String description;
            if (name.equals("endif")) {
                context.stack.removeLast();
                if (block.parent && !operands.isEmpty())
                    diagnostic(position, "warning", "extra tokens at end of #endif directive");
                description = "closes #" + block.kind + " at line " + block.position.line();
            } else {
                if (block.elseSeen)
                    diagnostic(position, "error", "#" + name + " after #else");
                if (name.equals("else")) {
                    if (block.parent && !operands.isEmpty())
                        diagnostic(position, "warning", "extra tokens at end of #else directive");
                    block.elseSeen = true;
                    if (block.parent) {
                        block.active = !block.chosen;
                        block.chosen = true;
                        description = block.active ? "taken" : "not taken";
                    } else {
                        block.active = false;
                        description = "skipped";
                    }
                } else if (!block.parent) {
                    block.active = false;
                    description = "skipped";
                } else if (block.chosen) {
                    block.active = false;
                    description = "not evaluated";
                } else {
                    Test test = test(context, logical, name, operands);
                    block.active = test.value() != null && test.value() != 0;
                    if (block.active)
                        block.chosen = true;
                    description = testDescription(name, test);
                }
                if (block.parent && !block.active)
                    block.skipStart = logical.end() + 1;
            }
            conditionalRecord(position, depth, name, operands, description);
        }
        void include(Inclusion context, Lexer.LogicalLine logical, List<Lexer.Token> operands)
            throws Exception {
            Definitions.Position position = context.position(logical.tokens().getFirst().line());
            Header header;
            try {
                List<Lexer.Token> sequence = operands;
                HeaderRead read = headerSpecification(sequence, 0);
                if (read.header() == null && !sequence.isEmpty()) {
                    sequence = expander.expand(sequence, context);
                    read = headerSpecification(sequence, 0);
                }
                header = read.header();
                if (header == null)
                    throw new DirectiveError("#include expects \"FILENAME\" or <FILENAME>");
                if (read.consumed() < sequence.size())
                    diagnostic(position, "warning", "extra tokens at end of #include directive");
                if (header.name().isEmpty())
                    throw new DirectiveError("empty filename in #include");
            } catch (DirectiveError error) {
                diagnostic(position, "error", error.getMessage());
                return;
            }
            String prefix =
                       "  ".repeat(context.depth + 1) + logical.tokens().getFirst().line() + ": ",
                   path = manager.search(header.name(), header.quoted());
            if (path == null) {
                tree.add(prefix + header.rendering() + " [not found]");
                diagnostic(position, "error", "cannot find include file " + header.rendering());
                return;
            }
            IncludeManager.SourceFile previous = manager.files.get(path);
            if (previous != null && previous.once) {
                tree.add(prefix + path + " [skipped: pragma once]");
                previous.skipped++;
                return;
            }
            if (previous != null && previous.guard != null && macros.containsKey(previous.guard)) {
                tree.add(prefix + path + " [skipped: guard " + previous.guard + "]");
                previous.skipped++;
                return;
            }
            if (context.depth + 1 > 8) {
                tree.add(prefix + path + " [too deep]");
                diagnostic(position, "error", "#include nested too deeply");
                return;
            }
            tree.add(prefix + path);
            marker(path, 1, 1);
            processFile(path, context.depth + 1);
            Definitions.Position resumed = context.position(logical.end() + 1);
            marker(resumed.file(), resumed.line(), 2);
        }
        void lineDirective(Inclusion context, Lexer.LogicalLine logical,
                           List<Lexer.Token> operands) {
            Definitions.Position position = context.position(logical.tokens().getFirst().line());
            if (operands.isEmpty() || !decimalToken(operands.getFirst()))
                operands = expander.expand(operands, context);
            if ((operands.size() != 1 && operands.size() != 2) ||
                !decimalToken(operands.getFirst()) ||
                operands.size() == 2 && !operands.get(1).kind().equals("string")) {
                diagnostic(position, "error", "invalid #line directive");
                return;
            }
            long line = Long.parseLong(operands.getFirst().spelling());
            if (line < 1 || line > Integer.MAX_VALUE) {
                diagnostic(position, "error", "line number out of range");
                return;
            }
            context.offset = (int)line - (logical.end() + 1);
            if (operands.size() == 2) {
                String spelling = operands.get(1).spelling();
                context.displayFile = spelling.substring(1, spelling.length() - 1);
            }
        }
        void macroPragma(Definitions.Position position, List<Lexer.Token> operands,
                         String operation) {
            if (operands.size() != 4 || !operands.get(1).spelling().equals("(") ||
                !operands.get(2).kind().equals("string") ||
                !operands.get(3).spelling().equals(")")) {
                diagnostic(position, "error", "invalid #pragma " + operation + " directive");
                return;
            }
            String spelling = operands.get(2).spelling(),
                   name = spelling.substring(1, spelling.length() - 1);
            List<Definitions.Macro> stack =
                saved.computeIfAbsent(name, ignored -> new ArrayList<>());
            if (operation.equals("push_macro")) {
                stack.add(macros.get(name));
                event(position, "push " + name);
            } else if (stack.isEmpty())
                diagnostic(position, "warning", "no matching push_macro for \"" + name + "\"");
            else {
                Definitions.Macro macro = stack.removeLast();
                if (macro == null) {
                    macros.remove(name);
                    event(position, "pop " + name + " (undefined)");
                } else {
                    macros.put(name, macro);
                    event(position, "pop " + name);
                }
            }
        }
        void pragma(Inclusion context, Lexer.LogicalLine logical, List<Lexer.Token> operands) {
            Definitions.Position position = context.position(logical.tokens().getFirst().line());
            String name = !operands.isEmpty() && operands.getFirst().kind().equals("identifier")
                              ? operands.getFirst().spelling()
                              : null;
            if ("once".equals(name)) {
                if (operands.size() >= 2)
                    diagnostic(position, "warning",
                               "extra tokens at end of #pragma once directive");
                if (context.depth == 0)
                    diagnostic(position, "warning", "#pragma once in main file");
                context.source.once = true;
            } else if (operands.size() >= 2 && operands.get(0).spelling().equals("GCC") &&
                       operands.get(1).spelling().equals("poison")) {
                for (Lexer.Token token : operands.subList(2, operands.size()))
                    if (!token.kind().equals("identifier")) {
                        diagnostic(position, "error", "invalid #pragma GCC poison directive");
                        return;
                    }
                for (Lexer.Token token : operands.subList(2, operands.size())) {
                    if (macros.containsKey(token.spelling()))
                        diagnostic(position, "warning",
                                   "poisoning existing macro \"" + token.spelling() + "\"");
                    poisoned.add(token.spelling());
                }
            } else if ("push_macro".equals(name) || "pop_macro".equals(name))
                macroPragma(position, operands, name);
            else
                outputLine(context, logical.tokens().getFirst().line(),
                           "#pragma" + (operands.isEmpty() ? "" : " " + Lexer.render(operands)));
        }
        void directive(Inclusion context, Lexer.LogicalLine logical, String name,
                       List<Lexer.Token> operands) throws Exception {
            if (logical.tokens().size() == 1)
                return;
            boolean poisoning = "pragma".equals(name) && operands.size() >= 2 &&
                                operands.get(0).spelling().equals("GCC") &&
                                operands.get(1).spelling().equals("poison");
            if (!poisoning)
                poisonCheck(context, operands);
            Definitions.Position position = context.position(logical.tokens().getFirst().line());
            if ("define".equals(name))
                define(operands, position, context.depth == 0);
            else if ("undef".equals(name))
                undefine(operands, position);
            else if ("include".equals(name))
                include(context, logical, operands);
            else if ("line".equals(name))
                lineDirective(context, logical, operands);
            else if ("error".equals(name) || "warning".equals(name))
                diagnostic(position, name,
                           "#" + name + (operands.isEmpty() ? "" : " " + Lexer.render(operands)));
            else if ("pragma".equals(name))
                pragma(context, logical, operands);
            else
                diagnostic(position, "error",
                           "invalid preprocessing directive #" +
                               logical.tokens().get(1).spelling());
        }
        void processFile(String path, int depth) throws Exception {
            IncludeManager.SourceFile source = manager.load(path);
            source.entered++;
            Inclusion context = new Inclusion(source, depth);
            for (Lexer.LogicalLine logical : source.lines) {
                List<Lexer.Token> tokens = logical.tokens();
                boolean directive = !tokens.isEmpty() && tokens.getFirst().spelling().equals("#");
                String name = IncludeManager.directiveName(tokens);
                List<Lexer.Token> operands =
                    tokens.subList(Math.min(2, tokens.size()), tokens.size());
                if (directive && name != null && CONDITIONALS.contains(name)) {
                    flush(context);
                    conditional(context, logical, name, operands);
                } else if (context.skipping())
                    continue;
                else if (directive) {
                    flush(context);
                    directive(context, logical, name, operands);
                } else
                    context.segment.addAll(tokens);
            }
            flush(context);
            for (Block block : context.stack)
                closeRegion(context, block, source.physicalLines);
            for (Block block : context.stack)
                diagnostic(block.position, "error", "unterminated #" + block.kind);
        }
        List<String> includeReport() {
            List<String> lines = new ArrayList<>(tree);
            lines.add("");
            lines.add("== files ==");
            for (String path : new TreeSet<>(manager.files.keySet())) {
                IncludeManager.SourceFile source = manager.files.get(path);
                lines.add(path + " entered=" + source.entered + " skipped=" + source.skipped +
                          " lines=" + source.physicalLines + " output_lines=" + source.outputLines +
                          " skipped_lines=" + source.skippedLines +
                          " guard=" + (source.guard == null ? "-" : source.guard) +
                          " once=" + (source.once ? "yes" : "no"));
            }
            lines.add("");
            String current = "main.o:";
            boolean hasPath = false;
            for (String path : manager.files.keySet()) {
                if (current.length() + 1 + path.length() > 76 && hasPath) {
                    lines.add(current + " \\");
                    current = " ";
                    hasPath = false;
                }
                current += " " + path;
                hasPath = true;
            }
            lines.add(current);
            return lines;
        }
        Map<String, List<String>> references() {
            Map<String, List<String>> references = new TreeMap<>();
            for (var entry : macros.entrySet()) {
                Definitions.Macro macro = entry.getValue();
                Set<String> names = new TreeSet<>();
                for (Lexer.Token token : macro.replacement)
                    if (token.kind().equals("identifier") && macros.containsKey(token.spelling()) &&
                        (macro.parameters == null || !macro.parameters.contains(token.spelling())))
                        names.add(token.spelling());
                references.put(entry.getKey(), List.copyOf(names));
            }
            return references;
        }
        boolean recursive(String name, Map<String, List<String>> references) {
            Deque<String> pending = new ArrayDeque<>(references.get(name));
            Set<String> seen = new HashSet<>();
            while (!pending.isEmpty()) {
                String current = pending.pop();
                if (current.equals(name))
                    return true;
                if (seen.add(current))
                    pending.addAll(references.get(current));
            }
            return false;
        }
        List<String> macroReport() {
            List<String> lines = new ArrayList<>();
            lines.add("== history ==");
            lines.addAll(history);
            lines.add("");
            lines.add("== table ==");
            Map<String, List<String>> references = references();
            int objectLike = 0;
            for (var entry : macros.entrySet()) {
                Definitions.Macro macro = entry.getValue();
                if (macro.parameters == null)
                    objectLike++;
                lines.add(
                    "#define " + macro.signature() +
                    (macro.replacement.isEmpty() ? "" : " " + Lexer.render(macro.replacement)));
                lines.add("  at " + macro.position + " expanded=" + macro.expanded +
                          " tested=" + macro.tested +
                          " recursive=" + (recursive(macro.name, references) ? "yes" : "no"));
                lines.add(following("  refs:", references.get(macro.name)));
            }
            lines.add("");
            lines.add("macros=" + macros.size() + " object_like=" + objectLike +
                      " function_like=" + (macros.size() - objectLike));
            Set<String> undefined = new TreeSet<>(everDefined);
            undefined.removeAll(macros.keySet());
            lines.add(following("undefined:", undefined));
            lines.add(
                "builtins: __COUNTER__=" + expander.builtinCounts.getOrDefault("__COUNTER__", 0) +
                " __FILE__=" + expander.builtinCounts.getOrDefault("__FILE__", 0) +
                " __LINE__=" + expander.builtinCounts.getOrDefault("__LINE__", 0));
            return lines;
        }
        List<String> conditionalReport() {
            List<String> lines = new ArrayList<>(conditionalRecords);
            lines.add("");
            lines.add("== skipped regions ==");
            lines.addAll(regions);
            lines.add("");
            lines.add("directives=" + conditionalRecords.size() +
                      " taken=" + conditionCounts.getOrDefault("taken", 0) +
                      " not_taken=" + conditionCounts.getOrDefault("not_taken", 0) +
                      " skipped=" + conditionCounts.getOrDefault("skipped", 0) +
                      " not_evaluated=" + conditionCounts.getOrDefault("not_evaluated", 0) +
                      " endif=" + conditionCounts.getOrDefault("endif", 0) +
                      " regions=" + regions.size());
            return lines;
        }
        void writeReports() throws Exception {
            Files.createDirectories(Path.of("output"));
            List<String> diagnosticLines = new ArrayList<>(diagnostics);
            diagnosticLines.add("errors=" + diagnosticCounts.getOrDefault("error", 0) +
                                " warnings=" + diagnosticCounts.getOrDefault("warning", 0));
            write("preprocessed.txt", output);
            write("includes.txt", includeReport());
            write("macros.txt", macroReport());
            write("conditionals.txt", conditionalReport());
            write("diagnostics.txt", diagnosticLines);
        }
        void run() throws Exception {
            processDefines();
            marker("main.c", 1, null);
            processFile("main.c", 0);
            for (Definitions.Macro macro : macros.values())
                unusedCheck(macro);
            writeReports();
        }
    }
    static void write(String name, List<String> lines) throws Exception {
        StringBuilder text = new StringBuilder();
        for (String line : lines) {
            int end = line.length();
            while (end > 0 && line.charAt(end - 1) == ' ')
                end--;
            text.append(line, 0, end).append('\n');
        }
        Files.writeString(Path.of("output", name), text, StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception { new Preprocessor().run(); }
}
