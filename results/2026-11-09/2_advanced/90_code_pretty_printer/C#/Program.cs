using System;
using System.IO;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;
using static Docs;
sealed class Profile {
    public Dictionary<string, string> Values {
        get;
    } = new();
    public bool Yes(string key) => Values[key] == "yes";
    public int Number(string key) => int.Parse(Values[key], CultureInfo.InvariantCulture);
    public bool Kr => Values["brace_style"] == "kr";
}
sealed class Construction(List<Token> tokens, Profile profile) {
    public List<Token> Tokens {
        get;
    } = tokens;
    readonly bool[] originalTrailing = tokens.Select(t => t.Trailing.Count != 0).ToArray();
    readonly DocBuilder docs = new();
    Document Space() => Text(profile.Yes("space_around_operators") ? " " : "");
    Document KeywordSpace() => Text(profile.Yes("space_after_keyword") ? " " : "");
    Document OperatorLine() => profile.Yes("space_around_operators") ? Line() : Softline();
    public Document Separator(int blank) => Concat(Enumerable.Range(0, 1 + Math.Min(blank, profile.Number("max_blank_lines"))).Select(_ => Hardline()));
    public int Preblank(int token) => Tokens[token].Leading.FirstOrDefault()?.Blank ?? Tokens[token].Blank;
    public Document Comments(IReadOnlyList<Comment> comments, int? next) {
        List<Document> parts = new();
        for (int i = 0; i < comments.Count; i++) {
            Comment comment = comments[i];
            parts.Add(Text(comment.Text));
            int? blank = i + 1 < comments.Count ? comments[i + 1].Blank : next;
            if (blank.HasValue) parts.Add(comment.Own ? Separator(blank.Value) : Text(" "));
        }
        return Concat(parts);
    }
    Document Trailing(int token) => Tokens[token].Trailing.Count == 0 ? Text("") : Suffix(string.Join(" ", Tokens[token].Trailing.Select(c => c.Text)));
    Document TokenWith(int token, IReadOnlyList<Comment> leading) => Concat(Comments(leading, Tokens[token].Blank), Text(Tokens[token].Text), Trailing(token));
    Document T(int token) => TokenWith(token, Tokens[token].Leading);
    Document Group(Document child) => docs.Group(child);
    int Level(SyntaxNode node) => node.Kind switch {
        "conditional" => 0, "binary" => Parser.Precedence(Tokens[node.Tokens[0]].Text), "unary" => 7, _ => 8
    };
    SyntaxNode Open(SyntaxNode node, int required) {
        SyntaxNode current = node;
        while (profile.Yes("remove_parens") && current.Kind == "paren" && Level(current.Children[0]) >= required && Tokens[current.Tokens[0]].Leading.Count == 0 && Tokens[current.Tokens[1]].Leading.Count == 0) {
            SyntaxNode child = current.Children[0];
            Token left = Tokens[current.Tokens[0]], right = Tokens[current.Tokens[1]];
            List<Comment> first = new(left.Trailing), last = new(right.Trailing);
            left.Trailing.Clear();
            right.Trailing.Clear();
            Tokens[child.Start].Trailing.InsertRange(0, first);
            Tokens[child.End].Trailing.AddRange(last);
            current = child;
        }
        return current;
    }
    Document List(SyntaxNode node) {
        int left = node.Tokens[0], right = node.Tokens[^1];
        if (node.Children.Count == 0) return Concat(T(left), T(right));
        bool forced = Enumerable.Range(node.Start, node.End - node.Start).Any(i => originalTrailing[i]);
        List<Document> inside = new() {
            Softline()
        };
        for (int i = 0; i < node.Children.Count; i++) {
            SyntaxNode child = node.Children[i];
            if (i > 0) inside.AddRange(new[] {
                T(node.Tokens[i]), Line()
            });
            inside.Add(node.Kind == "params" ? Parameter(child) : node.Kind == "initlist" ? Initializer(child) : Expression(child, 0));
        }
        if (node.Kind == "initlist") {
            inside.Add(IfBreak(",", ""));
            if (node.Trailing is int tail) inside.Add(Trailing(tail));
        }
        return Group(Concat(forced ? BreakParent() : Text(""), T(left), Nest(profile.Number("indent"), Concat(inside)), Softline(), T(right)));
    }
    Document Parameter(SyntaxNode node) {
        List<Document> parts = new() {
            T(node.Tokens[0]), Text(" "), T(node.Tokens[1])
        };
        foreach (SyntaxNode dimension in node.Children) parts.AddRange(new[] {
            T(dimension.Tokens[0]), T(dimension.Tokens[1])
        });
        return Concat(parts);
    }
    public Document Declaration(SyntaxNode node) {
        List<Document> parts = new() {
            T(node.Tokens[0]), Text(" "), T(node.Tokens[1])
        };
        SyntaxNode? initial = null;
        foreach (SyntaxNode child in node.Children) {
            if (child.Kind == "dimension") {
                parts.Add(T(child.Tokens[0]));
                if (child.Children.Count > 0) parts.Add(Expression(child.Children[0], 0));
                parts.Add(T(child.Tokens[1]));
            } else initial = child;
        }
        foreach (int t in node.Tokens.Skip(2)) {
            if (Tokens[t].Text == "=") parts.AddRange(new[] {
                Space(), T(t), Space(), Initializer(initial!)
            });
            else parts.Add(T(t));
        }
        return Concat(parts);
    }
    Document Initializer(SyntaxNode node) => node.Kind == "initlist" ? List(node) : Expression(node, 0);
    (List<Comment> H, List<Comment> G) Closing(int token) {
        List<Comment> comments = Tokens[token].Leading;
        int split = comments.FindLastIndex(c => c.Own) + 1;
        return (comments.Take(split).ToList(), comments.Skip(split).ToList());
    }
    Document Block(SyntaxNode node) {
        int close = node.Tokens[1];
        var (h, g) = Closing(close);
        if (node.Children.Count == 0 && h.Count == 0) return Concat(T(node.Tokens[0]), TokenWith(close, g));
        List<Document> inside = new() {
            Hardline()
        };
        for (int i = 0; i < node.Children.Count; i++) {
            SyntaxNode child = node.Children[i];
            if (i > 0) inside.Add(Separator(Preblank(child.Start)));
            inside.Add(Statement(child));
        }
        if (h.Count > 0) {
            if (node.Children.Count > 0) inside.Add(Separator(h[0].Blank));
            inside.Add(Comments(h, null));
        }
        return Concat(T(node.Tokens[0]), Nest(profile.Number("indent"), Concat(inside)), Hardline(), TokenWith(close, g));
    }
    Document Body(SyntaxNode node) {
        Document separator = profile.Kr ? Text(" ") : Hardline();
        if (node.Kind == "block") return Concat(separator, Block(node));
        Document document = Statement(node);
        if (profile.Yes("add_braces")) return Concat(separator, Text("{"), Nest(profile.Number("indent"), Concat(Hardline(), document)), Hardline(), Text("}"));
        return Nest(profile.Number("indent"), Concat(Hardline(), document));
    }
    Document Simple(SyntaxNode node) => node.Kind == "assign" ? Concat(Expression(node.Children[0], 0), Space(), T(node.Tokens[0]), Space(), Expression(node.Children[1], 0)) : Expression(node.Children[0], 0);
    Document Clause(SyntaxNode node) {
        List<Document> parts = new() {
            T(node.Tokens[0])
        };
        int first = node.Kind == "case" ? 1 : 0;
        if (first == 1) parts.AddRange(new[] {
            Text(" "), Expression(node.Children[0], 0)
        });
        parts.Add(T(node.Tokens[1]));
        if (node.Children.Count > first) {
            List<Document> statements = new() {
                Hardline()
            };
            for (int i = first; i < node.Children.Count; i++) {
                SyntaxNode child = node.Children[i];
                if (i > first) statements.Add(Separator(Preblank(child.Start)));
                statements.Add(Statement(child));
            }
            parts.Add(Nest(profile.Number("indent"), Concat(statements)));
        }
        return Concat(parts);
    }
    Document Statement(SyntaxNode node) {
        switch (node.Kind) {
            case "block": return Block(node);
            case "decl": return Declaration(node);
            case "statement": return Concat(Simple(node.Children[0]), T(node.Tokens[0]));
            case "break": case "continue": return Concat(node.Tokens.Select(T));
            case "return": {
                List<Document> parts = new() {
                    T(node.Tokens[0])
                };
                if (node.Children.Count > 0) parts.AddRange(new[] {
                    Text(" "), Expression(node.Children[0], 0)
                });
                parts.Add(T(node.Tokens[1]));
                return Concat(parts);
            }
            case "while": case "if": {
                Document condition = Expression(node.Children[0], 0), body = Body(node.Children[1]);
                List<Document> parts = new() {
                    T(node.Tokens[0]), KeywordSpace(), T(node.Tokens[1]), condition, T(node.Tokens[2]), body
                };
                if (node.Kind == "if" && node.Children.Count == 3) {
                    parts.Add(profile.Kr && (node.Children[1].Kind == "block" || profile.Yes("add_braces")) ? Text(" ") : Hardline());
                    parts.Add(T(node.Tokens[3]));
                    if (node.Children[2].Kind == "if") parts.AddRange(new[] {
                        Text(" "), Statement(node.Children[2])
                    });
                    else parts.Add(Body(node.Children[2]));
                }
                return Concat(parts);
            }
            case "for": {
                List<Document> inner = new();
                SyntaxNode initial = node.Children[0];
                if (initial.Kind != "empty") inner.Add(initial.Kind == "decl" ? Declaration(initial) : Simple(initial));
                inner.Add(T(node.Tokens[2]));
                if (node.Children[1].Kind != "empty") inner.AddRange(new[] {
                    Line(), Expression(node.Children[1], 0)
                });
                inner.Add(T(node.Tokens[3]));
                if (node.Children[2].Kind != "empty") inner.AddRange(new[] {
                    Line(), Simple(node.Children[2])
                });
                Document group = Group(Align(Concat(inner))), body = Body(node.Children[3]);
                return Concat(T(node.Tokens[0]), KeywordSpace(), T(node.Tokens[1]), group, T(node.Tokens[4]), body);
            }
            case "switch": {
                int close = node.Tokens[4];
                var (h, g) = Closing(close);
                Document condition = Expression(node.Children[0], 0);
                List<Document> parts = new() {
                    T(node.Tokens[0]), KeywordSpace(), T(node.Tokens[1]), condition, T(node.Tokens[2]), profile.Kr ? Text(" ") : Hardline(), T(node.Tokens[3])
                };
                if (node.Children.Count > 1 || h.Count > 0) {
                    List<Document> inside = new() {
                        Hardline()
                    };
                    for (int i = 1; i < node.Children.Count; i++) {
                        SyntaxNode child = node.Children[i];
                        if (i > 1) inside.Add(Separator(Preblank(child.Start)));
                        inside.Add(Clause(child));
                    }
                    if (h.Count > 0) {
                        if (node.Children.Count > 1) inside.Add(Separator(h[0].Blank));
                        inside.Add(Comments(h, null));
                    }
                    parts.AddRange(new[] {
                        Nest(profile.Yes("indent_case_labels") ? profile.Number("indent") : 0, Concat(inside)), Hardline()
                    });
                }
                parts.Add(TokenWith(close, g));
                return Concat(parts);
            }
            default: throw new InvalidOperationException();
        }
    }
    public Document Function(SyntaxNode node) {
        Document parameters = List(node.Children[0]), block = Block(node.Children[1]);
        return Concat(T(node.Tokens[0]), Text(" "), T(node.Tokens[1]), parameters, Hardline(), block);
    }
    Document Postfix(SyntaxNode node) => node.Kind switch {
        "call" => List(node.Children[1]), "index" => Concat(T(node.Tokens[0]), Expression(node.Children[1], 0), T(node.Tokens[1])), "member" => Concat(T(node.Tokens[0]), T(node.Tokens[1])), _ => throw new InvalidOperationException()
    };
    Document Expression(SyntaxNode original, int required) {
        SyntaxNode node = Open(original, required);
        switch (node.Kind) {
            case "atom": return T(node.Tokens[0]);
            case "paren": return Concat(T(node.Tokens[0]), Expression(node.Children[0], 0), T(node.Tokens[1]));
            case "unary": return Concat(T(node.Tokens[0]), Expression(node.Children[0], 8));
            case "binary": {
                int p = Level(node);
                SyntaxNode current = node;
                List<(int Op, SyntaxNode Right)> entries = new();
                while (current.Kind == "binary" && Level(current) == p) {
                    entries.Add((current.Tokens[0], current.Children[1]));
                    current = Open(current.Children[0], p);
                }
                Document head = Expression(current, p);
                List<Document> rest = new();
                foreach (var (op, right) in entries.AsEnumerable().Reverse()) rest.AddRange(new[] {
                    OperatorLine(), T(op), Space(), Expression(right, p + 1)
                });
                return Group(Concat(head, Nest(profile.Number("indent"), Concat(rest))));
            }
            case "conditional": {
                Document head = Expression(node.Children[0], 1);
                SyntaxNode current = node;
                List<Document> rest = new();
                while (true) {
                    rest.AddRange(new[] {
                        OperatorLine(), T(current.Tokens[0]), Space(), Expression(current.Children[1], 0), OperatorLine(), T(current.Tokens[1]), Space()
                    });
                    SyntaxNode next = Open(current.Children[2], 0);
                    if (next.Kind == "conditional") {
                        rest.Add(Expression(next.Children[0], 1));
                        current = next;
                    } else {
                        rest.Add(Expression(next, 0));
                        break;
                    }
                }
                return Group(Concat(head, Nest(profile.Number("indent"), Concat(rest))));
            }
            case "call": case "index": case "member": {
                SyntaxNode current = node;
                List<SyntaxNode> operations = new();
                while (current.Kind is "call" or "index" or "member") {
                    operations.Add(current);
                    current = Open(current.Children[0], 8);
                }
                List<List<SyntaxNode>> segments = new() {
                    new()
                };
                foreach (SyntaxNode operation in operations.AsEnumerable().Reverse()) {
                    if (operation.Kind == "member") segments.Add(new());
                    segments[^1].Add(operation);
                }
                List<int> calls = Enumerable.Range(1, segments.Count - 1).Where(i => segments[i].Any(op => op.Kind == "call")).ToList();
                List<Document> parts = new() {
                    Expression(current, 8)
                };
                if (calls.Count < 2) {
                    foreach (SyntaxNode operation in segments.SelectMany(segment => segment)) parts.Add(Postfix(operation));
                    return Concat(parts);
                }
                int first = calls[0];
                foreach (SyntaxNode operation in segments.Take(first).SelectMany(segment => segment)) parts.Add(Postfix(operation));
                List<Document> rest = new();
                foreach (List<SyntaxNode> segment in segments.Skip(first)) {
                    rest.Add(Softline());
                    foreach (SyntaxNode operation in segment) rest.Add(Postfix(operation));
                }
                parts.Add(Nest(profile.Number("indent"), Concat(rest)));
                return Group(Concat(parts));
            }
            default: throw new InvalidOperationException();
        }
    }
}
sealed record Formatted(List<string> Lines, (string Name, Document Document)? FirstFunction, Dictionary<int, string> Modes, int Comments);
sealed record Source(string Header, string Name, string Profile) {
    public List<string> Lines {
        get;
    } = new();
}
static class Program {
    static (List<Token> Tokens, int Comments) Attach(Lexed lexed) {
        List<Token> tokens = lexed.Tokens;
        for (int k = 0; k < lexed.Order.Count; k++) {
            Occurrence entry = lexed.Order[k];
            if (entry.IsToken) continue;
            Comment comment = lexed.Comments[entry.Index];
            int? previous = lexed.Order.Take(k).Where(o => o.IsToken).Select(o => (int?)o.Index).LastOrDefault();
            int? next = lexed.Order.Skip(k + 1).Where(o => o.IsToken).Select(o => (int?)o.Index).FirstOrDefault();
            int? nextLine = null;
            if (k + 1 < lexed.Order.Count) {
                Occurrence following = lexed.Order[k + 1];
                nextLine = following.IsToken ? tokens[following.Index].Line : lexed.Comments[following.Index].Line;
            }
            comment.Own = comment.LineComment || !nextLine.HasValue || nextLine.Value > comment.Line;
            bool trailing = previous.HasValue && tokens[previous.Value].Line == comment.Line && (next == null || tokens[next.Value].Line > comment.Line);
            if (trailing) tokens[previous!.Value].Trailing.Add(comment);
            else tokens[next ?? tokens.Count - 1].Leading.Add(comment);
        }
        return (tokens, lexed.Comments.Count);
    }
    static void CheckComments(List<SyntaxNode> items, List<Token> tokens) {
        HashSet<int> allowed = new() {
            tokens.Count - 1
        }, tails = new();
        void Walk(SyntaxNode node) {
            switch (node.Kind) {
                case "block": allowed.Add(node.Tokens[1]);
                foreach (SyntaxNode child in node.Children) allowed.Add(child.Start);
                break;
                case "switch": allowed.Add(node.Tokens[4]);
                foreach (SyntaxNode clause in node.Children.Skip(1)) {
                    allowed.Add(clause.Tokens[0]);
                    foreach (SyntaxNode statement in clause.Children.Skip(clause.Kind == "case" ? 1 : 0)) allowed.Add(statement.Start);
                } break;
                case "if": if (node.Children[1].Kind != "block") allowed.Add(node.Children[1].Start);
                if (node.Children.Count == 3 && node.Children[2].Kind is not ("block" or "if")) allowed.Add(node.Children[2].Start);
                break;
                case "while": if (node.Children[1].Kind != "block") allowed.Add(node.Children[1].Start);
                break;
                case "for": if (node.Children[3].Kind != "block") allowed.Add(node.Children[3].Start);
                break;
                case "params": case "args": case "initlist": foreach (SyntaxNode child in node.Children) allowed.Add(child.Start);
                if (node.Trailing is int tail) tails.Add(tail);
                break;
            }
            foreach (SyntaxNode child in node.Children) Walk(child);
        }
        foreach (SyntaxNode item in items) {
            allowed.Add(item.Start);
            Walk(item);
        }
        for (int i = 0; i < tokens.Count; i++) foreach (Comment comment in tokens[i].Leading) if (comment.Own && !allowed.Contains(i) || tails.Contains(i)) throw new SourceError(comment.Line, comment.Column, "comment not allowed here");
    }
    static Formatted FormatSource(IReadOnlyList<string> lines, Profile profile) {
        var (tokens, commentCount) = Attach(Lexer.Lex(lines));
        List<SyntaxNode> items = Parser.Parse(tokens);
        CheckComments(items, tokens);
        bool empty = items.Count == 0 && tokens[^1].Leading.Count == 0;
        Construction builder = new(tokens, profile);
        List<Document> parts = new();
        (string Name, Document Document)? firstFunction = null;
        for (int i = 0; i < items.Count; i++) {
            SyntaxNode node = items[i];
            if (i > 0) parts.Add(builder.Separator(builder.Preblank(node.Start)));
            Document document = node.Kind == "function" ? builder.Function(node) : builder.Declaration(node);
            if (node.Kind == "function" && firstFunction == null) firstFunction = (builder.Tokens[node.Tokens[1]].Text, document);
            parts.Add(document);
        }
        List<Comment> closing = builder.Tokens[^1].Leading;
        if (closing.Count > 0) {
            if (items.Count > 0) parts.Add(builder.Separator(closing[0].Blank));
            parts.Add(builder.Comments(closing, null));
        }
        if (empty) return new(new(), firstFunction, new(), commentCount);
        Printed printed = Printer.Print(Concat(parts), profile.Number("width"), profile.Number("comment_column"));
        return new(printed.Lines, firstFunction, printed.Modes, commentCount);
    }
    static (Dictionary<string, Profile> Profiles, List<Source> Sources) Inputs() {
        Dictionary<string, Profile> profiles = new();
        string current = "";
        foreach (string line in File.ReadAllLines("input/style.txt")) {
            if (line.Length == 0) continue;
            if (line.StartsWith('[')) {
                current = line[1..^1];
                profiles[current] = new();
            } else {
                string[] pair = line.Split('=', 2);
                profiles[current].Values[pair[0]] = pair[1];
            }
        }
        List<Source> sources = new();
        foreach (string line in File.ReadAllLines("input/sources.txt")) {
            if (line.StartsWith("=== ", StringComparison.Ordinal)) {
                string[] parts = line.Split(' ');
                sources.Add(new(line, parts[1], parts[2]));
            } else sources[^1].Lines.Add(line);
        } return (profiles, sources);
    }
    static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n");
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        var (profiles, sources) = Inputs();
        List<string> formatted = new(), idempotency = new(), diagnostics = new(), docTree = new(), changes = new();
        foreach (Source source in sources) {
            Profile profile = profiles[source.Profile];
            List<string> original = source.Lines.Select(Lexer.Trim).ToList();
            formatted.Add(source.Header);
            docTree.Add("=== " + source.Name);
            changes.Add("=== " + source.Name);
            try {
                Formatted first = FormatSource(source.Lines, profile);
                formatted.AddRange(first.Lines);
                try {
                    Formatted second = FormatSource(first.Lines, profile);
                    if (first.Lines.SequenceEqual(second.Lines)) idempotency.Add(source.Name + ": stable");
                    else {
                        int index = 0;
                        while (index < Math.Min(first.Lines.Count, second.Lines.Count) && first.Lines[index] == second.Lines[index]) index++;
                        idempotency.Add($"{source.Name}: unstable at line {index + 1}");
                    }
                }
                catch (SourceError error) {
                    idempotency.Add($"{source.Name}: unstable (second pass: {error.Line}:{error.Column}: {error.Reason})");
                }
                int width = profile.Number("width");
                for (int i = 0; i < first.Lines.Count; i++) if (first.Lines[i].Length > width) diagnostics.Add($"{source.Name}:{i + 1}: warning: line too long ({first.Lines[i].Length} > {width})");
                int longest = first.Lines.Select(line => line.Length).DefaultIfEmpty(0).Max(), broken = first.Modes.Values.Count(mode => mode != "flat"), forced = first.Modes.Values.Count(mode => mode == "forced");
                docTree.Add($"metrics lines={first.Lines.Count} longest={longest} comments={first.Comments} groups={first.Modes.Count} broken={broken} forced={forced}");
                if (first.FirstFunction is {
                } function) {
                    docTree.Add("function " + function.Name);
                    Report.Tree(function.Document, 0, first.Modes, docTree);
                } else docTree.Add("no function");
                changes.AddRange(Report.Diff(original, first.Lines));
            } catch (SourceError error) {
                formatted.AddRange(original);
                idempotency.Add(source.Name + ": skipped (syntax error)");
                diagnostics.Add($"{source.Name}:{error.Line}:{error.Column}: error: {error.Reason}");
                docTree.Add("syntax error");
                changes.Add("skipped (syntax error)");
            }
        }
        if (diagnostics.Count == 0) diagnostics.Add("no diagnostics");
        Write("formatted.txt", formatted);
        Write("idempotency.txt", idempotency);
        Write("diagnostics.txt", diagnostics);
        Write("doc_tree.txt", docTree);
        Write("changes.txt", changes);
    }
}
