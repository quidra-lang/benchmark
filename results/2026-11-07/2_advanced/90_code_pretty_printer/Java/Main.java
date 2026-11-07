import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    record Profile(int width, int indent, String braceStyle, boolean spaceAroundOperators,
                   boolean spaceAfterKeyword, boolean indentCaseLabels, boolean addBraces,
                   int maxBlankLines, boolean removeParens, int commentColumn) {}
    static final class Source {
        String header, name, profile;
        List<String> lines = new ArrayList<>();
        Source(String header) {
            this.header = header;
            String[] fields = header.split(" ");
            name = fields[1];
            profile = fields[2];
        }
    }
    static Map<String, Profile> profiles() throws Exception {
        Map<String, Profile> result = new LinkedHashMap<>();
        String name = null;
        Map<String, String> fields = new HashMap<>();
        List<String> lines = new ArrayList<>(
            Files.readAllLines(Path.of("input", "style.txt"), StandardCharsets.US_ASCII));
        lines.add("[end]");
        for (String line : lines) {
            if (line.isEmpty())
                continue;
            if (line.startsWith("[")) {
                if (name != null)
                    result.put(name, new Profile(Integer.parseInt(fields.get("width")),
                                                 Integer.parseInt(fields.get("indent")),
                                                 fields.get("brace_style"),
                                                 fields.get("space_around_operators").equals("yes"),
                                                 fields.get("space_after_keyword").equals("yes"),
                                                 fields.get("indent_case_labels").equals("yes"),
                                                 fields.get("add_braces").equals("yes"),
                                                 Integer.parseInt(fields.get("max_blank_lines")),
                                                 fields.get("remove_parens").equals("yes"),
                                                 Integer.parseInt(fields.get("comment_column"))));
                name = line.substring(1, line.length() - 1);
                fields = new HashMap<>();
            } else {
                String[] pair = line.split("=", 2);
                fields.put(pair[0], pair[1]);
            }
        }
        return result;
    }
    static List<Source> sources() throws Exception {
        List<Source> sources = new ArrayList<>();
        for (String line :
             Files.readAllLines(Path.of("input", "sources.txt"), StandardCharsets.US_ASCII))
            if (line.startsWith("=== "))
                sources.add(new Source(line));
            else
                sources.getLast().lines.add(line);
        return sources;
    }
    static void attachComments(Lexer.Lexed lexed) {
        List<Lexer.Entry> items = lexed.items();
        Lexer.Token previous = null;
        int nextIndex = 0;
        for (int i = 0; i < items.size(); i++) {
            Lexer.Entry entry = items.get(i);
            if (entry instanceof Lexer.Token token) {
                previous = token;
                nextIndex = token.index + 1;
                continue;
            }
            Lexer.Comment comment = (Lexer.Comment)entry;
            Lexer.Token next =
                nextIndex < lexed.tokens().size() - 1 ? lexed.tokens().get(nextIndex) : null;
            Lexer.Entry following = i + 1 < items.size() ? items.get(i + 1) : null;
            comment.ownLine = comment.kind.equals("line_comment") || following == null ||
                              following.line > comment.line;
            if (previous != null && previous.line == comment.line &&
                (next == null || next.line > comment.line))
                previous.trailing.add(comment);
            else
                (next == null ? lexed.tokens().getLast() : next).leading.add(comment);
        }
        for (Lexer.Token token : lexed.tokens())
            token.originalTrailing = !token.trailing.isEmpty();
    }
    static void checkComments(List<Lexer.Token> tokens) {
        for (Lexer.Token token : tokens)
            for (Lexer.Comment comment : token.leading)
                if (token.trailingComma || comment.ownLine && !token.allowed)
                    throw new Lexer.SourceError(comment.line, comment.column,
                                                "comment not allowed here");
    }
    static Doc t(String value) { return DocBuilder.text(value); }
    static Doc c(Doc... parts) { return DocBuilder.concat(parts); }
    static Doc c(List<Doc> parts) { return DocBuilder.concat(parts); }
    static Doc group(Doc child) { return new DocBuilder.Group(child); }
    static Doc nest(int amount, Doc child) { return new DocBuilder.Nest(amount, child); }
    static Doc align(Doc child) { return new DocBuilder.Align(child); }
    static final Doc LINE = DocBuilder.Break.LINE, SOFTLINE = DocBuilder.Break.SOFTLINE,
                     HARDLINE = DocBuilder.Break.HARDLINE,
                     BREAK_PARENT = DocBuilder.Break.BREAK_PARENT;
    record CommentSplit(List<Lexer.Comment> own, List<Lexer.Comment> inline) {}
    static final class DocumentFormatter {
        Profile profile;
        List<Lexer.Token> tokens;
        int indent, maxBlank;
        String separator, keywordGap;
        Doc operatorBreak;
        boolean kr;
        Doc firstFunctionDoc;
        String firstFunctionName;
        DocumentFormatter(Profile profile, List<Lexer.Token> tokens) {
            this.profile = profile;
            this.tokens = tokens;
            indent = profile.indent();
            maxBlank = profile.maxBlankLines();
            separator = profile.spaceAroundOperators() ? " " : "";
            operatorBreak = profile.spaceAroundOperators() ? LINE : SOFTLINE;
            keywordGap = profile.spaceAfterKeyword() ? " " : "";
            kr = profile.braceStyle().equals("kr");
        }
        Doc sep(int blank) {
            List<Doc> result = new ArrayList<>();
            result.add(HARDLINE);
            for (int i = 0; i < Math.min(blank, maxBlank); i++)
                result.add(HARDLINE);
            return c(result);
        }
        int preBlank(Lexer.Token token) {
            return token.leading.isEmpty() ? token.blank : token.leading.getFirst().blank;
        }
        Doc comments(List<Lexer.Comment> comments, Lexer.Entry following) {
            List<Doc> result = new ArrayList<>();
            for (int i = 0; i < comments.size(); i++) {
                Lexer.Comment comment = comments.get(i);
                result.add(t(comment.text));
                Lexer.Entry next = i + 1 < comments.size() ? comments.get(i + 1) : following;
                if (next != null)
                    result.add(comment.ownLine ? sep(next.blank) : t(" "));
            }
            return c(result);
        }
        Doc token(Lexer.Token token) { return token(token, token.leading); }
        Doc token(Lexer.Token token, List<Lexer.Comment> leading) {
            return c(comments(leading, token), t(token.text), suffix(token));
        }
        Doc suffix(Lexer.Token token) {
            if (token.trailing.isEmpty())
                return null;
            StringJoiner text = new StringJoiner(" ");
            for (Lexer.Comment comment : token.trailing)
                text.add(comment.text);
            return new DocBuilder.Suffix(text.toString());
        }
        CommentSplit splitComments(Lexer.Token close) {
            int last = -1;
            for (int i = 0; i < close.leading.size(); i++)
                if (close.leading.get(i).ownLine)
                    last = i;
            return new CommentSplit(close.leading.subList(0, last + 1),
                                    close.leading.subList(last + 1, close.leading.size()));
        }
        Doc closingComments(List<Lexer.Comment> comments, boolean preceding) {
            return comments.isEmpty()
                ? null
                : c(preceding ? sep(comments.getFirst().blank) : null, comments(comments, null));
        }
        Doc wholeFile(List<Parser.Item> items, Lexer.Token end) {
            List<Doc> pieces = new ArrayList<>();
            for (int i = 0; i < items.size(); i++) {
                Parser.Item item = items.get(i);
                if (i > 0)
                    pieces.add(sep(preBlank(item.first())));
                Doc document = item(item);
                if (firstFunctionDoc == null && item instanceof Parser.Function function) {
                    firstFunctionDoc = document;
                    firstFunctionName = function.name().text;
                }
                pieces.add(document);
            }
            if (!end.leading.isEmpty()) {
                if (!items.isEmpty())
                    pieces.add(sep(end.leading.getFirst().blank));
                pieces.add(comments(end.leading, null));
            }
            return c(pieces);
        }
        Doc item(Parser.Item item) {
            if (item instanceof Parser.Function function)
                return c(token(function.type()), t(" "), token(function.name()),
                         list(function.parameters()), HARDLINE, block(function.body()));
            return variable((Parser.Variable)item);
        }
        Doc parameter(Parser.Parameter parameter) {
            List<Doc> parts =
                new ArrayList<>(List.of(token(parameter.type()), t(" "), token(parameter.name())));
            for (Parser.Bracket bracket : parameter.brackets()) {
                parts.add(token(bracket.left()));
                parts.add(token(bracket.right()));
            }
            return c(parts);
        }
        Doc variable(Parser.Variable variable) {
            List<Doc> parts =
                new ArrayList<>(List.of(token(variable.type()), t(" "), token(variable.name())));
            for (Parser.Bracket bracket : variable.dimensions()) {
                parts.add(token(bracket.left()));
                if (bracket.expression() != null)
                    parts.add(expr(bracket.expression(), 0));
                parts.add(token(bracket.right()));
            }
            if (variable.equals() != null) {
                parts.add(t(separator));
                parts.add(token(variable.equals()));
                parts.add(t(separator));
                parts.add(initializer(variable.initializer()));
            }
            if (variable.semi() != null)
                parts.add(token(variable.semi()));
            return c(parts);
        }
        Doc initializer(Parser.Node node) {
            return node instanceof Parser.ListNode list ? list(list) : expr((Parser.Expr)node, 0);
        }
        Doc list(Parser.ListNode list) {
            if (list.elements().isEmpty())
                return c(token(list.left()), token(list.right()));
            boolean forced = false;
            for (int i = list.left().index; i < list.right().index; i++)
                if (tokens.get(i).originalTrailing)
                    forced = true;
            List<Doc> elements = new ArrayList<>();
            for (Parser.Node element : list.elements())
                elements.add(element instanceof Parser.Parameter parameter ? parameter(parameter)
                                                                           : initializer(element));
            List<Doc> inner = new ArrayList<>();
            inner.add(SOFTLINE);
            inner.add(elements.getFirst());
            for (int i = 0; i < list.commas().size(); i++) {
                inner.add(token(list.commas().get(i)));
                inner.add(LINE);
                inner.add(elements.get(i + 1));
            }
            if (list.kind() == Parser.ListKind.INITIALIZERS) {
                inner.add(new DocBuilder.IfBreak(",", ""));
                if (list.trailing() != null)
                    inner.add(suffix(list.trailing()));
            }
            return group(c(forced ? BREAK_PARENT : null, token(list.left()), nest(indent, c(inner)),
                           SOFTLINE, token(list.right())));
        }
        Doc block(Parser.Block block) {
            CommentSplit split = splitComments(block.right());
            if (block.statements().isEmpty() && split.own().isEmpty())
                return c(token(block.left()), token(block.right(), split.inline()));
            List<Doc> inner = new ArrayList<>();
            inner.add(HARDLINE);
            for (int i = 0; i < block.statements().size(); i++) {
                Parser.Statement statement = block.statements().get(i);
                if (i > 0)
                    inner.add(sep(preBlank(statement.first())));
                inner.add(statement(statement));
            }
            inner.add(closingComments(split.own(), !block.statements().isEmpty()));
            return c(token(block.left()), nest(indent, c(inner)), HARDLINE,
                     token(block.right(), split.inline()));
        }
        Doc body(Parser.Statement statement) {
            if (statement instanceof Parser.Block block)
                return c(kr ? t(" ") : HARDLINE, block(block));
            if (profile.addBraces())
                return c(kr ? t(" ") : HARDLINE, t("{"),
                         nest(indent, c(HARDLINE, statement(statement))), HARDLINE, t("}"));
            return nest(indent, c(HARDLINE, statement(statement)));
        }
        Doc simple(Parser.Simple simple) {
            return simple.operator() == null
                ? expr(simple.left(), 0)
                : c(expr(simple.left(), 0), t(separator), token(simple.operator()), t(separator),
                    expr(simple.right(), 0));
        }
        Doc ifStatement(Parser.If statement) {
            List<Doc> parts = new ArrayList<>(List.of(
                token(statement.keyword()), t(keywordGap), token(statement.left()),
                expr(statement.test(), 0), token(statement.right()), body(statement.body())));
            if (statement.elseToken() != null) {
                parts.add(kr && (statement.body() instanceof Parser.Block || profile.addBraces())
                              ? t(" ")
                              : HARDLINE);
                parts.add(token(statement.elseToken()));
                if (statement.alternative() instanceof Parser.If alternative) {
                    parts.add(t(" "));
                    parts.add(ifStatement(alternative));
                } else
                    parts.add(body(statement.alternative()));
            }
            return c(parts);
        }
        Doc forStatement(Parser.For statement) {
            List<Doc> contents = new ArrayList<>();
            if (statement.initial() != null)
                contents.add(statement.initial() instanceof Parser.Variable variable
                                 ? variable(variable)
                                 : simple((Parser.Simple)statement.initial()));
            contents.add(token(statement.firstSemi()));
            if (statement.condition() != null) {
                contents.add(LINE);
                contents.add(expr(statement.condition(), 0));
            }
            contents.add(token(statement.secondSemi()));
            if (statement.update() != null) {
                contents.add(LINE);
                contents.add(simple(statement.update()));
            }
            return c(token(statement.keyword()), t(keywordGap), token(statement.left()),
                     group(align(c(contents))), token(statement.right()), body(statement.body()));
        }
        Doc clause(Parser.Clause clause) {
            List<Doc> contents = new ArrayList<>();
            contents.add(token(clause.label()));
            if (clause.value() != null) {
                contents.add(t(" "));
                contents.add(expr(clause.value(), 0));
            }
            contents.add(token(clause.colon()));
            if (!clause.statements().isEmpty()) {
                List<Doc> inner = new ArrayList<>();
                inner.add(HARDLINE);
                for (int i = 0; i < clause.statements().size(); i++) {
                    Parser.Statement statement = clause.statements().get(i);
                    if (i > 0)
                        inner.add(sep(preBlank(statement.first())));
                    inner.add(statement(statement));
                }
                contents.add(nest(indent, c(inner)));
            }
            return c(contents);
        }
        Doc switchStatement(Parser.Switch statement) {
            CommentSplit split = splitComments(statement.closing());
            Doc header = c(token(statement.keyword()), t(keywordGap), token(statement.left()),
                           expr(statement.test(), 0), token(statement.right()),
                           kr ? t(" ") : HARDLINE, token(statement.opening()));
            if (statement.clauses().isEmpty() && split.own().isEmpty())
                return c(header, token(statement.closing(), split.inline()));
            List<Doc> inner = new ArrayList<>();
            inner.add(HARDLINE);
            for (int i = 0; i < statement.clauses().size(); i++) {
                Parser.Clause clause = statement.clauses().get(i);
                if (i > 0)
                    inner.add(sep(preBlank(clause.first())));
                inner.add(clause(clause));
            }
            inner.add(closingComments(split.own(), !statement.clauses().isEmpty()));
            return c(header, nest(profile.indentCaseLabels() ? indent : 0, c(inner)), HARDLINE,
                     token(statement.closing(), split.inline()));
        }
        Doc statement(Parser.Statement statement) {
            return switch (statement) {
                case Parser.Block block -> block(block);
                case Parser.Variable variable -> variable(variable);
                case Parser.SimpleStatement simple ->
                    c(simple(simple.value()), token(simple.semi()));
                case Parser.Return returned ->
                    c(token(returned.keyword()),
                      returned.expression() == null ? null
                                                    : c(t(" "), expr(returned.expression(), 0)),
                      token(returned.semi()));
                case Parser.Flow flow -> c(token(flow.keyword()), token(flow.semi()));
                case Parser.If conditional -> ifStatement(conditional);
                case Parser.While loop ->
                    c(token(loop.keyword()), t(keywordGap), token(loop.left()),
                      expr(loop.test(), 0), token(loop.right()), body(loop.body()));
                case Parser.For loop -> forStatement(loop);
                case Parser.Switch selection -> switchStatement(selection);
            };
        }
        Lexer.Token last(Parser.Expr expression) {
            return switch (expression) {
                case Parser.Primary primary -> primary.token();
                case Parser.Paren paren -> paren.right();
                case Parser.Unary unary -> last(unary.operand());
                case Parser.Binary binary -> last(binary.right());
                case Parser.Conditional conditional -> last(conditional.no());
                case Parser.Call call -> call.arguments().right();
                case Parser.Index index -> index.right();
                case Parser.Member member -> member.name();
            };
        }
        Parser.Expr opened(Parser.Expr expression, int minimum) {
            while (profile.removeParens() && expression instanceof Parser.Paren paren) {
                Parser.Expr inner = paren.inner();
                if (inner.level() < minimum || !paren.left().leading.isEmpty() ||
                    !paren.right().leading.isEmpty())
                    break;
                Lexer.Token first = inner.first(), last = last(inner);
                first.trailing.addAll(0, paren.left().trailing);
                paren.left().trailing.clear();
                last.trailing.addAll(paren.right().trailing);
                paren.right().trailing.clear();
                expression = inner;
            }
            return expression;
        }
        Doc binary(Parser.Binary expression) {
            int precedence = expression.level();
            List<Lexer.Token> operators = new ArrayList<>();
            List<Parser.Expr> operands = new ArrayList<>();
            Parser.Expr current = expression;
            while (current instanceof Parser.Binary binary && binary.level() == precedence) {
                operators.add(binary.operator());
                operands.add(binary.right());
                current = opened(binary.left(), precedence);
            }
            Collections.reverse(operators);
            Collections.reverse(operands);
            List<Doc> contents = new ArrayList<>();
            for (int i = 0; i < operators.size(); i++) {
                contents.add(operatorBreak);
                contents.add(token(operators.get(i)));
                contents.add(t(separator));
                contents.add(expr(operands.get(i), precedence + 1));
            }
            return group(c(expr(current, precedence), nest(indent, c(contents))));
        }
        Doc conditional(Parser.Conditional expression) {
            List<Doc> contents = new ArrayList<>();
            Parser.Conditional current = expression;
            while (true) {
                contents.add(operatorBreak);
                contents.add(token(current.question()));
                contents.add(t(separator));
                contents.add(expr(current.yes(), 0));
                contents.add(operatorBreak);
                contents.add(token(current.colon()));
                contents.add(t(separator));
                Parser.Expr following = opened(current.no(), 0);
                if (following instanceof Parser.Conditional next) {
                    contents.add(expr(next.test(), 1));
                    current = next;
                } else {
                    contents.add(expr(following, 0));
                    break;
                }
            }
            return group(c(expr(expression.test(), 1), nest(indent, c(contents))));
        }
        static boolean isPostfix(Parser.Expr expression) {
            return expression instanceof Parser.Call || expression instanceof Parser.Index ||
                expression instanceof Parser.Member;
        }
        Doc postfixPiece(Parser.Expr expression) {
            return switch (expression) {
                case Parser.Call call -> list(call.arguments());
                case Parser.Index index ->
                    c(token(index.left()), expr(index.index(), 0), token(index.right()));
                case Parser.Member member -> c(token(member.dot()), token(member.name()));
                default -> throw new IllegalStateException();
            };
        }
        Doc postfix(Parser.Expr expression) {
            List<Parser.Expr> operations = new ArrayList<>();
            Parser.Expr current = expression;
            while (isPostfix(current)) {
                operations.add(current);
                Parser.Expr target = switch (current) {
                    case Parser.Call call -> call.target();
                    case Parser.Index index -> index.target();
                    case Parser.Member member -> member.target();
                    default -> throw new IllegalStateException();
                };
                current = opened(target, 8);
            }
            Collections.reverse(operations);
            List<List<Parser.Expr>> segments = new ArrayList<>();
            segments.add(new ArrayList<>());
            for (Parser.Expr operation : operations) {
                if (operation instanceof Parser.Member)
                    segments.add(new ArrayList<>());
                segments.getLast().add(operation);
            }
            List<Integer> calls = new ArrayList<>();
            for (int i = 1; i < segments.size(); i++)
                if (segments.get(i).stream().anyMatch(part -> part instanceof Parser.Call))
                    calls.add(i);
            Doc head = expr(current, 8);
            List<Doc> parts = new ArrayList<>();
            parts.add(head);
            if (calls.size() < 2) {
                for (Parser.Expr operation : operations)
                    parts.add(postfixPiece(operation));
                return c(parts);
            }
            int split = calls.getFirst();
            for (int i = 0; i < split; i++)
                for (Parser.Expr operation : segments.get(i))
                    parts.add(postfixPiece(operation));
            List<Doc> following = new ArrayList<>();
            for (int i = split; i < segments.size(); i++) {
                following.add(SOFTLINE);
                for (Parser.Expr operation : segments.get(i))
                    following.add(postfixPiece(operation));
            }
            parts.add(nest(indent, c(following)));
            return group(c(parts));
        }
        Doc expr(Parser.Expr expression, int minimum) {
            expression = opened(expression, minimum);
            return switch (expression) {
                case Parser.Primary primary -> token(primary.token());
                case Parser.Paren paren ->
                    c(token(paren.left()), expr(paren.inner(), 0), token(paren.right()));
                case Parser.Unary unary -> c(token(unary.operator()), expr(unary.operand(), 8));
                case Parser.Binary binary -> binary(binary);
                case Parser.Conditional conditional -> conditional(conditional);
                case Parser.Call call -> postfix(call);
                case Parser.Index index -> postfix(index);
                case Parser.Member member -> postfix(member);
            };
        }
    }
    record Rendered(List<String> lines, int comments, Doc document, Doc firstFunctionDoc,
                    String firstFunctionName) {}
    static Rendered renderOnce(List<String> lines, Profile profile) {
        Lexer.Lexed lexed = Lexer.analyze(lines);
        attachComments(lexed);
        List<Parser.Item> syntax = new Parser(lexed.tokens()).parse();
        checkComments(lexed.tokens());
        Lexer.Token end = lexed.tokens().getLast();
        if (syntax.isEmpty() && end.leading.isEmpty())
            return new Rendered(List.of(), lexed.comments().size(), null, null, null);
        DocumentFormatter builder = new DocumentFormatter(profile, lexed.tokens());
        Doc document = builder.wholeFile(syntax, end);
        List<String> formatted = Printer.layout(document, profile.width(), profile.commentColumn());
        return new Rendered(formatted, lexed.comments().size(), document, builder.firstFunctionDoc,
                            builder.firstFunctionName);
    }
    static int firstDiffering(List<String> a, List<String> b) {
        for (int i = 0; i < Math.min(a.size(), b.size()); i++)
            if (!a.get(i).equals(b.get(i)))
                return i + 1;
        return Math.min(a.size(), b.size()) + 1;
    }
    static final class Result {
        Source source;
        Profile profile;
        List<String> original, formatted, diagnostics = new ArrayList<>();
        Lexer.SourceError error;
        Rendered first;
        String idempotency;
        Result(Source source, Profile profile) {
            this.source = source;
            this.profile = profile;
            original = source.lines.stream().map(Lexer::trim).toList();
            try {
                first = renderOnce(source.lines, profile);
            } catch (Lexer.SourceError error) {
                this.error = error;
                formatted = original;
                idempotency = source.name + ": skipped (syntax error)";
                diagnostics.add(source.name + ":" + error.line + ":" + error.column +
                                ": error: " + error.getMessage());
                return;
            }
            formatted = first.lines();
            try {
                Rendered second = renderOnce(formatted, profile);
                idempotency = source.name + (formatted.equals(second.lines())
                                                 ? ": stable"
                                                 : ": unstable at line " +
                                                       firstDiffering(formatted, second.lines()));
            } catch (Lexer.SourceError error) {
                idempotency = source.name + ": unstable (second pass: " + error.line + ":" +
                              error.column + ": " + error.getMessage() + ")";
            }
            for (int i = 0; i < formatted.size(); i++)
                if (formatted.get(i).length() > profile.width())
                    diagnostics.add(source.name + ":" + (i + 1) + ": warning: line too long (" +
                                    formatted.get(i).length() + " > " + profile.width() + ")");
        }
        List<String> treeLines() {
            List<String> lines = new ArrayList<>();
            lines.add("=== " + source.name);
            if (error != null) {
                lines.add("syntax error");
                return lines;
            }
            List<DocBuilder.Group> groups = DocBuilder.groups(first.document());
            int longest = 0, broken = 0, forced = 0;
            for (String line : formatted)
                longest = Math.max(longest, line.length());
            for (DocBuilder.Group group : groups) {
                if (!group.mode.equals("flat"))
                    broken++;
                if (group.mode.equals("forced"))
                    forced++;
            }
            lines.add("metrics lines=" + formatted.size() + " longest=" + longest +
                      " comments=" + first.comments() + " groups=" + groups.size() +
                      " broken=" + broken + " forced=" + forced);
            if (first.firstFunctionDoc() == null)
                lines.add("no function");
            else {
                lines.add("function " + first.firstFunctionName());
                lines.addAll(Report.tree(first.firstFunctionDoc()));
            }
            return lines;
        }
        List<String> changeLines() {
            List<String> lines = new ArrayList<>();
            lines.add("=== " + source.name);
            if (error != null)
                lines.add("skipped (syntax error)");
            else
                lines.addAll(Report.diff(original, formatted));
            return lines;
        }
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name),
                          lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception {
        Map<String, Profile> profiles = profiles();
        List<Result> results = new ArrayList<>();
        for (Source source : sources())
            results.add(new Result(source, profiles.get(source.profile)));
        List<String> formatted = new ArrayList<>(), idempotency = new ArrayList<>(),
                     diagnostics = new ArrayList<>(), trees = new ArrayList<>(),
                     changes = new ArrayList<>();
        for (Result result : results) {
            formatted.add(result.source.header);
            formatted.addAll(result.formatted);
            idempotency.add(result.idempotency);
            diagnostics.addAll(result.diagnostics);
            trees.addAll(result.treeLines());
            changes.addAll(result.changeLines());
        }
        if (diagnostics.isEmpty())
            diagnostics.add("no diagnostics");
        Files.createDirectories(Path.of("output"));
        write("formatted.txt", formatted);
        write("idempotency.txt", idempotency);
        write("diagnostics.txt", diagnostics);
        write("doc_tree.txt", trees);
        write("changes.txt", changes);
    }
}
