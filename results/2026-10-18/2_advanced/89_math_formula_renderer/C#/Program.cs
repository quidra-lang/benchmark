sealed record Line(int Start, int End, int Indent, int Width);
sealed record Composition(List<Child> Placed, int Width, int Height, int Lines, List<(int Line, int Width)> Overfull);
sealed class Record
{
    public string Text {
        get;
    }
    public Formula? Formula {
        get;
    }
    public FormulaError? Error {
        get;
    }
    public string? Tag {
        get;
        set;
    }
    public List<(int Column, string Message)> Warnings {
        get;
    } = new();
    public Record(string text)
    {
        Text = text;
        try {
            Formula = Parser.Parse(Lexer.Lex(text), text.Length + 1);
        }
        catch (FormulaError error) {
            Error = error;
        }
    }
}
static class Program
{
    static string Display(string kind, string value, Dictionary<string, string> references) => kind == "command" ? Lexer.Symbol(value[1..])!.Value.Text : kind == "eqref" ? references.GetValueOrDefault(value, "(??)") : value;
    static Box Typeset(Node node, bool script, Params p, Dictionary<string, string> references)
    {
        switch (node)
        {
            case AtomNode atom:
            {
                string description = (atom.Kind == "text" ? "text" : atom.Kind == "eqref" ? "eqref" : "atom") + $" \"{atom.Value}\"";
                if (!script && atom.Kind == "command" && atom.Value is "\\sum" or "\\prod" or "\\int")
                {
                    string[] glyph = Boxes.Large(atom.Value[1..]);
                    Box result = new(glyph[0].Length, 3, 1, description);
                    for (int y = 0; y < glyph.Length; y++) result.String(0, y, glyph[y]);
                    return result;
                }
                return Box.Text(Display(atom.Kind, atom.Value, references), description);
            }
            case RowNode row:
            return Layout.Row(row.Elements.Select(n => Typeset(n, script, p, references)).ToList(), Layout.Space(row.Elements, script, p).Gaps, "row");
            case ScriptNode scripts:
            {
                Box b = Typeset(scripts.Base, script, p, references);
                Box? s = scripts.Sub is null ? null : Typeset(scripts.Sub, true, p, references), u = scripts.Sup is null ? null : Typeset(scripts.Sup, true, p, references);
                int sw = s?.Width ?? 0, sh = s?.Height ?? 0, uw = u?.Width ?? 0, uh = u?.Height ?? 0;
                bool stacked = !script && (scripts.Base is AtomNode {
                    Kind: "command", Value: "\\sum" or "\\prod" or "\\lim" or "\\max" or "\\min"
                } || scripts.Base is AccentNode {
                    Name: "overbrace" or "underbrace"
                });
                if (stacked)
                {
                    int width = Math.Max(b.Width, Math.Max(sw, uw));
                    Box result = new(width, uh + b.Height + sh, uh + b.Baseline, "limits");
                    result.Child(b, (width - b.Width) / 2, uh, "base: ");
                    if (s is not null) result.Child(s, (width - sw) / 2, uh + b.Height, "sub: ");
                    if (u is not null) result.Child(u, (width - uw) / 2, 0, "sup: ");
                    return result;
                }
                else
                {
                    int tp = (b.Baseline == 0 ? -1 : 0) - uh + 1, ts = b.Height - 1 - b.Baseline == 0 ? b.Height : b.Height - 1;
                    int top = u is null ? 0 : Math.Min(0, tp), bottom = s is null ? b.Height - 1 : Math.Max(b.Height - 1, ts + sh - 1), shift = -top;
                    Box result = new(b.Width + Math.Max(sw, uw), bottom - top + 1, b.Baseline + shift, "scripts");
                    result.Child(b, 0, shift, "base: ");
                    if (s is not null) result.Child(s, b.Width, ts + shift, "sub: ");
                    if (u is not null) result.Child(u, b.Width, tp + shift, "sup: ");
                    return result;
                }
            }
            case BinaryNode binary:
            {
                if (binary.Name == "frac" && script)
                {
                    Box Part(Node child)
                    {
                        bool wrap = child is RowNode or BinaryNode {
                            Name: "frac"
                        };
                        return Typeset(wrap ? new DelimitedNode("(", ")", child, 0) : child, true, p, references);
                    }
                    return Layout.Row(new() {
                        Part(binary.First), Box.Text("/", "atom \"/\""), Part(binary.Second)
                    }, new() {
                        0, 0
                    }, "slash", new() {
                        "num: ", "", "den: "
                    });
                }
                Box a = Typeset(binary.First, binary.Name is "overset" or "underset" || script, p, references), b = Typeset(binary.Second, script, p, references);
                int width = Math.Max(a.Width, b.Width);
                switch (binary.Name)
                {
                    case "frac":
                    {
                        Box result = new(width + 2, a.Height + 1 + b.Height, a.Height, "frac");
                        result.String(0, a.Height, new string('-', width + 2));
                        result.Child(a, (width + 2 - a.Width) / 2, 0, "num: ");
                        result.Child(b, (width + 2 - b.Width) / 2, a.Height + 1, "den: ");
                        return result;
                    }
                    case "binom":
                    {
                        Box result = new(width + 2, a.Height + 1 + b.Height, a.Height, "binom");
                        result.Delimiter("(", 0);
                        result.Delimiter(")", width + 1);
                        result.Child(a, 1 + (width - a.Width) / 2, 0, "upper: ");
                        result.Child(b, 1 + (width - b.Width) / 2, a.Height + 1, "lower: ");
                        return result;
                    }
                    case "overset":
                    {
                        Box result = new(width, a.Height + b.Height, a.Height + b.Baseline, "overset");
                        result.Child(a, (width - a.Width) / 2, 0, "over: ");
                        result.Child(b, (width - b.Width) / 2, a.Height, "base: ");
                        return result;
                    }
                    default:
                    {
                        Box result = new(width, a.Height + b.Height, b.Baseline, "underset");
                        result.Child(b, (width - b.Width) / 2, 0, "base: ");
                        result.Child(a, (width - a.Width) / 2, b.Height, "under: ");
                        return result;
                    }
                }
            }
            case RootNode root:
            {
                Box body = Typeset(root.Body, script, p, references);
                Box? index = root.Index is null ? null : Typeset(root.Index, true, p, references);
                int k = body.Height, extra = Math.Max(0, (index?.Width ?? 0) - 1), top = Math.Max(0, (index?.Height ?? 0) - k);
                Box result = new(extra + k + 1 + body.Width, k + 1 + top, body.Baseline + 1 + top, index is null ? "sqrt" : "root");
                result.String(extra + k + 1, top, new string('_', body.Width));
                result.String(extra, k + top, "\\");
                for (int r = 1; r <= k; r++) result.String(extra + k - r + 1, r + top, "/");
                if (index is not null) {
                    result.Child(index, 0, k + top - index.Height, "index: ");
                    result.Child(body, extra + k + 1, 1 + top, "body: ");
                }
                else result.Child(body, extra + k + 1, 1 + top);
                return result;
            }
            case DelimitedNode delimited:
            {
                Box body = Typeset(delimited.Body, script, p, references);
                int wl = delimited.Left == "." ? 0 : 1, wr = delimited.Right == "." ? 0 : 1;
                Box result = new(wl + body.Width + wr, body.Height, body.Baseline, $"delim {delimited.Left} {delimited.Right}");
                result.Delimiter(delimited.Left, 0);
                result.Delimiter(delimited.Right, wl + body.Width);
                result.Child(body, wl, 0);
                return result;
            }
            case MatrixNode matrix:
            {
                List<List<Box>> cells = matrix.Rows.Select(row => row.Select(n => Typeset(n, script, p, references)).ToList()).ToList();
                int columns = matrix.Rows[0].Count;
                int[] widths = Enumerable.Range(0, columns).Select(j => cells.Max(row => row[j].Width)).ToArray(), ascents = cells.Select(row => row.Max(b => b.Baseline)).ToArray(), descents = cells.Select(row => row.Max(b => b.Height - 1 - b.Baseline)).ToArray();
                int[] heights = ascents.Zip(descents, (a, d) => a + d + 1).ToArray();
                int bodyWidth = widths.Sum() + p.ColGap * (columns - 1), bodyHeight = heights.Sum() + p.RowGap * (cells.Count - 1), shift = matrix.Name == "matrix" ? 0 : 2;
                int width = bodyWidth + (matrix.Name == "matrix" ? 0 : matrix.Name == "cases" ? 2 : 4);
                Box result = new(width, bodyHeight, (bodyHeight - 1) / 2, $"{matrix.Name} rows={cells.Count} cols={columns}");
                switch (matrix.Name)
                {
                    case "pmatrix": result.Delimiter("(", 0);
                    result.Delimiter(")", bodyWidth + 3);
                    break;
                    case "bmatrix": result.Delimiter("[", 0);
                    result.Delimiter("]", bodyWidth + 3);
                    break;
                    case "vmatrix": result.Delimiter("|", 0);
                    result.Delimiter("|", bodyWidth + 3);
                    break;
                    case "cases": result.Delimiter("\\{", 0);
                    break;
                }
                int y = 0;
                for (int i = 0; i < cells.Count; i++)
                {
                    int x = shift;
                    for (int j = 0; j < cells[i].Count; j++)
                    {
                        Box box = cells[i][j];
                        int offset = matrix.Name == "cases" ? 0 : (widths[j] - box.Width) / 2;
                        result.Child(box, x + offset, y + ascents[i] - box.Baseline, $"cell {i + 1},{j + 1}: ");
                        x += widths[j] + p.ColGap;
                    }
                    y += heights[i] + p.RowGap;
                }
                return result;
            }
            case AccentNode accent:
            {
                Box body = Typeset(accent.Body, script, p, references);
                int width = accent.Name switch {
                    "hat" or "dot" or "tilde" => Math.Max(body.Width, 1), "vec" => Math.Max(body.Width, 2), "overbrace" or "underbrace" => body.Width + 2, _ => body.Width
                };
                Box result = new(width, body.Height + 1, accent.Name == "underbrace" ? body.Baseline : body.Baseline + 1, accent.Name);
                switch (accent.Name)
                {
                    case "overline": result.String(0, 0, new string('_', width));
                    break;
                    case "hat": case "dot": case "tilde": result.String((width - 1) / 2, 0, accent.Name == "hat" ? "^" : accent.Name == "dot" ? "." : "~");
                    break;
                    case "vec": result.String(0, 0, new string('-', width - 1) + ">");
                    break;
                    case "overbrace": result.String(0, 0, "/" + new string('-', body.Width) + "\\");
                    break;
                    default: result.String(0, body.Height, "\\" + new string('-', body.Width) + "/");
                    break;
                }
                result.Child(body, accent.Name is "overbrace" or "underbrace" ? 1 : 0, accent.Name == "underbrace" ? 0 : 1);
                return result;
            }
            default: throw new InvalidOperationException();
        }
    }
    static string Tree(Node node) => node switch
    {
        AtomNode a => a.Kind switch {
            "symbol" => $"'{a.Value}'", "text" => $"\"{a.Value}\"", "eqref" => $"(eqref \"{a.Value}\")", _ => a.Value
        },
        RowNode r => "(row" + string.Concat(r.Elements.Select(n => " " + Tree(n))) + ")",
        BinaryNode b => $"({b.Name} {Tree(b.First)} {Tree(b.Second)})",
        RootNode r => r.Index is null ? $"(sqrt {Tree(r.Body)})" : $"(root {Tree(r.Index)} {Tree(r.Body)})",
        ScriptNode s => s.Sub is not null && s.Sup is not null ? $"(subsup {Tree(s.Base)} {Tree(s.Sub)} {Tree(s.Sup)})" : s.Sub is not null ? $"(sub {Tree(s.Base)} {Tree(s.Sub)})" : $"(sup {Tree(s.Base)} {Tree(s.Sup!)})",
        DelimitedNode d => $"(delim {(d.Left.Length == 1 ? "'" + d.Left + "'" : d.Left)} {(d.Right.Length == 1 ? "'" + d.Right + "'" : d.Right)} {Tree(d.Body)})",
        MatrixNode m => "(" + m.Name + string.Concat(m.Rows.Select(row => " [" + string.Join(" ", row.Select(Tree)) + "]")) + ")",
        AccentNode a => $"({a.Name} {Tree(a.Body)})", _ => throw new InvalidOperationException()
    };
    static string Linear(Node node, bool script, Params p, Dictionary<string, string> references)
    {
        string Child(Node child) => Linear(child, script, p, references);
        string Parenthesize(Node child, bool style, bool basis = false)
        {
            string text = Linear(child, style, p, references);
            return child is RowNode or BinaryNode {
                Name: "frac"
            } || basis && child is ScriptNode ? "(" + text + ")" : text;
        }
        string Delimiter(string text) => text == "." ? "" : text == "\\{" ? "{" : text == "\\}" ? "}" : text;
        switch (node)
        {
            case AtomNode a: return Display(a.Kind, a.Value, references);
            case RowNode row:
            List<int> gaps = Layout.Space(row.Elements, script, p).Gaps;
            return string.Concat(row.Elements.Select((n, i) => (i > 0 ? new string(' ', gaps[i - 1]) : "") + Child(n)));
            case BinaryNode b:
            if (b.Name == "frac") return Parenthesize(b.First, script) + "/" + Parenthesize(b.Second, script);
            if (b.Name == "binom") return $"binom({Child(b.First)}, {Child(b.Second)})";
            return $"{b.Name}({Linear(b.First, true, p, references)}, {Child(b.Second)})";
            case RootNode r: return r.Index is null ? $"sqrt({Child(r.Body)})" : $"root({Linear(r.Index, true, p, references)}, {Child(r.Body)})";
            case ScriptNode s: return Parenthesize(s.Base, script, true) + (s.Sub is null ? "" : "_" + Parenthesize(s.Sub, true)) + (s.Sup is null ? "" : "^" + Parenthesize(s.Sup, true));
            case DelimitedNode d: return Delimiter(d.Left) + Child(d.Body) + Delimiter(d.Right);
            case MatrixNode m: return m.Name + "[" + string.Join("; ", m.Rows.Select(row => string.Join(", ", row.Select(Child)))) + "]";
            case AccentNode a: return $"{a.Name}({Child(a.Body)})";
            default: throw new InvalidOperationException();
        }
    }
    static void Warnings(Node node, Dictionary<string, string> references, List<(int Column, string Message)> output)
    {
        switch (node)
        {
            case AtomNode a:
            if (a.Kind == "identifier" && Lexer.CommandName(a.Value)) output.Add((a.Column, $"{a.Value} is a command name; write \\{a.Value}"));
            if (a.Kind == "eqref" && !references.ContainsKey(a.Value)) output.Add((a.Column, $"undefined reference \"{a.Value}\""));
            break;
            case RowNode r: foreach (Node child in r.Elements) Warnings(child, references, output);
            break;
            case BinaryNode b: Warnings(b.First, references, output);
            Warnings(b.Second, references, output);
            break;
            case RootNode r: if (r.Index is not null) Warnings(r.Index, references, output);
            Warnings(r.Body, references, output);
            break;
            case ScriptNode s: Warnings(s.Base, references, output);
            if (s.Sub is not null) Warnings(s.Sub, references, output);
            if (s.Sup is not null) Warnings(s.Sup, references, output);
            break;
            case DelimitedNode d:
            if (d.Left != "." && d.Right != "." && !new[] {
                ("(", ")"), ("[", "]"), ("|", "|"), ("\\{", "\\}")
            }.Contains((d.Left, d.Right))) output.Add((d.Column, $"\\left{d.Left} closed by \\right{d.Right}"));
            Warnings(d.Body, references, output);
            break;
            case MatrixNode m: foreach (Node child in m.Rows.SelectMany(row => row)) Warnings(child, references, output);
            break;
            case AccentNode a: Warnings(a.Body, references, output);
            break;
        }
    }
    static List<Line> BuildLines(List<Node> nodes, List<Box> boxes, List<(int Left, int Right)> types, List<int> gaps, Params p, int stage)
    {
        List<int> breaks = new();
        for (int i = 1; i < nodes.Count; i++)
        {
            bool binary = stage >= 1 && types[i].Left == 2 && nodes[i] is AtomNode {
                Kind: "symbol", Value: "+" or "-"
            };
            if (types[i].Left == 3 || binary || stage >= 2 && types[i - 1].Right == 6) breaks.Add(i);
        }
        breaks.Add(nodes.Count);
        List<Line> lines = new();
        int start = 0;
        (int Column, int Width)? alignment = null;
        while (start < nodes.Count)
        {
            int indent = start == 0 ? 0 : alignment is {
            } a ? types[start].Left == 3 ? a.Column : a.Column + a.Width + p.Rel : p.Indent;
            int Width(int endIndex) => boxes.Skip(start).Take(endIndex - start).Sum(b => b.Width) + gaps.Skip(start).Take(endIndex - start - 1).Sum();
            int[] candidates = breaks.Where(b => b > start).ToArray(), fitting = candidates.Where(candidateEnd => indent + Width(candidateEnd) <= p.Width).ToArray();
            int end = fitting.Length > 0 ? fitting[^1] : candidates[0];
            if (start == 0)
            {
                int[] relation = Enumerable.Range(start, end - start).Where(i => types[i].Left == 3).Take(1).ToArray();
                if (relation.Length > 0) {
                    int r = relation[0];
                    alignment = (boxes.Take(r).Sum(b => b.Width) + gaps.Take(r).Sum(), boxes[r].Width);
                }
            }
            lines.Add(new Line(start, end, indent, Width(end)));
            start = end;
        }
        return lines;
    }
    static Composition Compose(List<Node> elements, string? tag, Params p, Dictionary<string, string> references)
    {
        Spacing spacing = Layout.Space(elements, false, p);
        List<Box> boxes = elements.Select(n => Typeset(n, false, p, references)).ToList();
        List<Line> lines = new();
        for (int stage = 0; stage < 3; stage++) {
            lines = BuildLines(elements, boxes, spacing.Types, spacing.Gaps, p, stage);
            if (lines.All(l => l.Indent + l.Width <= p.Width)) break;
        }
        List<Child> placed = new();
        List<(int Line, int Width)> overfull = new();
        int width = 0, y = 0;
        for (int k = 0; k < lines.Count; k++)
        {
            Line line = lines[k];
            if (line.Indent + line.Width > p.Width) overfull.Add((k + 1, line.Indent + line.Width));
            Box box = Layout.Row(boxes.GetRange(line.Start, line.End - line.Start), spacing.Gaps.Skip(line.Start).Take(line.End - line.Start - 1).ToList(), $"line {k + 1}");
            width = Math.Max(width, line.Indent + box.Width);
            placed.Add(new Child("", line.Indent, y, box));
            y += box.Height;
        }
        if (tag is not null)
        {
            int x = p.Width - tag.Length;
            Child last = placed[^1];
            int tagY;
            if (x >= last.X + last.Node.Width + 2) tagY = last.Y + last.Node.Baseline;
            else {
                tagY = y;
                y++;
            }
            Box box = Box.Text(tag, $"tag \"{tag}\"");
            width = Math.Max(width, x + box.Width);
            placed.Add(new Child("", x, tagY, box));
        }
        return new Composition(placed, width, y, lines.Count, overfull);
    }
    static Params ReadParams()
    {
        Dictionary<string, int> values = File.ReadLines("input/params.txt").Select(l => l.Split(' ')).ToDictionary(a => a[0], a => int.Parse(a[1], CultureInfo.InvariantCulture), StringComparer.Ordinal);
        return new Params(values["width"], values["indent"], values["rel_space"], values["bin_space"], values["punct_space"], values["col_gap"], values["row_gap"]);
    }
    static void Diagnostic(int number, string text, int column, string message, List<string> output) => output.AddRange(new[] {
        $"formula {number}, column {column}: {message}", "  " + text, new string(' ', column + 1) + "^"
    });
    static void Write(string name, List<string> lines)
    {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", new UTF8Encoding(false));
    }
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        Params parameters = ReadParams();
        List<Record> records = File.ReadLines("input/formulas.txt").Select(l => new Record(l)).ToList();
        int counter = 0;
        Dictionary<string, string> references = new(StringComparer.Ordinal);
        foreach (Record record in records) if (record.Formula is {
        } formula)
        {
            if (formula.Tag is {
            } tag) record.Tag = "(" + tag.Value + ")";
            else if (formula.Label is not null) {
                counter++;
                record.Tag = $"({counter})";
            }
        }
        foreach (Record record in records) if (record.Formula?.Label is {
        } label)
        {
            if (references.ContainsKey(label.Value)) record.Warnings.Add((label.Column, $"duplicate label \"{label.Value}\""));
            else references[label.Value] = record.Tag!;
        }
        List<string> rendered = new(), boxes = new(), trees = new(), errors = new();
        SortedDictionary<string, int> kinds = new(StringComparer.Ordinal);
        int valid = 0, totalBoxes = 0, maxDepth = 0, warningCount = 0, overfullCount = 0;
        for (int i = 0; i < records.Count; i++)
        {
            Record record = records[i];
            int number = i + 1;
            if (i > 0) rendered.Add("");
            rendered.Add($"formula {number}");
            if (record.Error is {
            } error)
            {
                rendered.Add("(error)");
                boxes.Add($"formula {number}: error");
                trees.Add($"formula {number}: error");
                Diagnostic(number, record.Text, error.Column, error.Reason, errors);
                continue;
            }
            Formula formula = record.Formula!;
            valid++;
            foreach (Node node in formula.Elements) Warnings(node, references, record.Warnings);
            record.Warnings.Sort((a, b) => a.Column.CompareTo(b.Column));
            warningCount += record.Warnings.Count;
            foreach (var (column, message) in record.Warnings) Diagnostic(number, record.Text, column, "warning: " + message, errors);
            Composition composition = Compose(formula.Elements, record.Tag, parameters, references);
            overfullCount += composition.Overfull.Count;
            foreach (var (line, width) in composition.Overfull) errors.Add($"formula {number}: line {line} is overfull (width {width} > {parameters.Width})");
            char[,] grid = new char[composition.Height, composition.Width];
            for (int y = 0; y < composition.Height; y++) for (int x = 0; x < composition.Width; x++) grid[y, x] = ' ';
            foreach (Child placed in composition.Placed) Canvas.Paint(placed.Node, placed.X, placed.Y, grid);
            Description description = Canvas.Describe(composition.Placed);
            foreach (var (kind, count) in description.Kinds) kinds[kind] = kinds.GetValueOrDefault(kind) + count;
            totalBoxes += description.Lines.Count;
            maxDepth = Math.Max(maxDepth, description.Depth);
            boxes.Add($"formula {number}: lines={composition.Lines} width={composition.Width} height={composition.Height} boxes={description.Lines.Count} depth={description.Depth}");
            boxes.AddRange(description.Lines);
            rendered.AddRange(Canvas.Lines(grid));
            trees.Add($"formula {number}: " + string.Join(" ", formula.Elements.Select(Tree)));
            string text = Linear(new RowNode(formula.Elements), false, parameters, references).TrimEnd(' ');
            trees.Add(text.Length == 0 ? "  linear:" : "  linear: " + text);
            if (record.Tag is {
            } tag) trees.Add("  tag: " + tag);
        }
        boxes.Add($"summary: boxes={totalBoxes} max_depth={maxDepth}");
        foreach (var (kind, count) in kinds) boxes.Add($"  {kind}: {count}");
        errors.Add($"formulas={records.Count} rendered={valid} errors={records.Count - valid} warnings={warningCount} overfull={overfullCount}");
        Write("rendered.txt", rendered);
        Write("boxes.txt", boxes);
        Write("trees.txt", trees);
        Write("errors.txt", errors);
    }
}
