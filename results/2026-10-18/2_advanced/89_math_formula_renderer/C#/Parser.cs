abstract record Node;
sealed record AtomNode(string Kind, string Value, int Column) : Node;
sealed record RowNode(List<Node> Elements) : Node;
sealed record BinaryNode(string Name, Node First, Node Second) : Node;
sealed record RootNode(Node? Index, Node Body) : Node;
sealed record ScriptNode(Node Base, Node? Sub, Node? Sup) : Node;
sealed record DelimitedNode(string Left, string Right, Node Body, int Column) : Node;
sealed record MatrixNode(string Name, List<List<Node>> Rows) : Node;
sealed record AccentNode(string Name, Node Body) : Node;
sealed record Formula(List<Node> Elements, (string Value, int Column)? Tag, (string Value, int Column)? Label);
sealed class Parser(List<Token> tokens, int end)
{
    readonly Token eof = new("eof", "", end);
    int index;
    (string Value, int Column)? tag, label;
    Token Peek => index < tokens.Count ? tokens[index] : eof;
    Token Take() {
        Token token = Peek;
        if (index < tokens.Count) index++;
        return token;
    }
    FormulaError Unexpected() => new(Peek.Column, Peek.Kind switch {
        "right" => "unexpected \\right", "end" => "unexpected \\end", "&" => "misplaced &", "newline" => "misplaced \\\\", _ => "unexpected end of input"
    });
    static Node Empty() => new RowNode(new());
    static Node Collapse(List<Node> nodes) => nodes.Count == 1 ? nodes[0] : new RowNode(nodes);
    List<Node> ElementList(bool top = false, bool rootIndex = false)
    {
        List<Node> result = new();
        while (true)
        {
            Token token = Peek;
            if (token.Kind is "}" or "&" or "newline" or "right" or "end" or "eof" || rootIndex && token.Kind == "symbol" && token.Value == "]") return result;
            if (token.Kind is "tag" or "label")
            {
                if (!top) throw new FormulaError(token.Column, "misplaced \\" + token.Kind);
                if ((token.Kind == "tag" ? tag : label) is not null) throw new FormulaError(token.Column, "duplicate \\" + token.Kind);
                if (token.Kind == "tag") tag = (token.Value, token.Column);
                else label = (token.Value, token.Column);
                Take();
                continue;
            }
            result.Add(Element());
        }
    }
    Node Element()
    {
        Node basis = Peek.Kind is "^" or "_" ? Empty() : Nucleus();
        Node? sub = null, sup = null;
        while (Peek.Kind is "^" or "_")
        {
            Token token = Take();
            if ((token.Kind == "^" ? sup : sub) is not null) throw new FormulaError(token.Column, token.Kind == "^" ? "double superscript" : "double subscript");
            Node value = Argument(token.Kind);
            if (token.Kind == "^") sup = value;
            else sub = value;
        }
        return sub is not null || sup is not null ? new ScriptNode(basis, sub, sup) : basis;
    }
    Node Argument(string name)
    {
        if (Peek.Kind is "identifier" or "number" or "symbol" or "command" or "text" or "eqref" or "{" or "frac" or "binom" or "overset" or "underset" or "sqrt" or "accent") return Nucleus();
        throw new FormulaError(Peek.Column, "missing argument for " + name);
    }
    string Delimiter()
    {
        Token token = Take();
        if (token.Kind == "symbol" && token.Value is "(" or ")" or "[" or "]" or "|" or "." || token.Kind == "command" && token.Value is "\\{" or "\\}") return token.Value;
        throw new FormulaError(token.Column, "invalid delimiter");
    }
    Node Nucleus()
    {
        Token token = Take();
        switch (token.Kind)
        {
            case "identifier": case "number": case "symbol": case "command": case "text": case "eqref": return new AtomNode(token.Kind, token.Value, token.Column);
            case "{":
            List<Node> nodes = ElementList();
            if (Peek.Kind != "}") throw Unexpected();
            Take();
            return Collapse(nodes);
            case "frac": case "binom": case "overset": case "underset":
            string name = "\\" + token.Kind;
            Node first = Argument(name), second = Argument(name);
            return new BinaryNode(token.Kind, first, second);
            case "sqrt":
            Node? rootIndex = null;
            if (Peek.Kind == "symbol" && Peek.Value == "[")
            {
                int column = Take().Column;
                List<Node> elements = ElementList(false, true);
                if (Peek.Kind != "symbol" || Peek.Value != "]") throw new FormulaError(column, "missing ]");
                Take();
                rootIndex = Collapse(elements);
            }
            return new RootNode(rootIndex, Argument("\\sqrt"));
            case "accent": return new AccentNode(token.Value, Argument("\\" + token.Value));
            case "left":
            string left = Delimiter();
            List<Node> body = ElementList();
            if (Peek.Kind != "right") throw new FormulaError(token.Column, "missing \\right");
            int rightColumn = Take().Column;
            return new DelimitedNode(left, Delimiter(), Collapse(body), rightColumn);
            case "begin":
            List<List<Node>> rows = new() {
                new()
            };
            while (true)
            {
                rows[^1].Add(Collapse(ElementList()));
                Token closing = Take();
                if (closing.Kind == "&") continue;
                if (closing.Kind == "newline") {
                    rows.Add(new());
                    continue;
                }
                if (closing.Kind == "end") {
                    if (closing.Value != token.Value) throw new FormulaError(closing.Column, "mismatched \\end");
                    break;
                }
                throw new FormulaError(token.Column, "missing \\end");
            }
            if (rows.Count > 1 && rows[^1].Count == 1 && rows[^1][0] is RowNode {
                Elements.Count: 0
            }) rows.RemoveAt(rows.Count - 1);
            int width = rows.Max(r => r.Count);
            foreach (List<Node> row in rows) while (row.Count < width) row.Add(Empty());
            return new MatrixNode(token.Value, rows);
            default: throw new InvalidOperationException();
        }
    }
    public static Formula Parse(List<Token> tokens, int end)
    {
        Stack<int> braces = new();
        foreach (Token token in tokens)
        {
            if (token.Kind == "{") braces.Push(token.Column);
            else if (token.Kind == "}") {
                if (!braces.TryPop(out _)) throw new FormulaError(token.Column, "unmatched }");
            }
        }
        if (braces.Count > 0) throw new FormulaError(braces.Peek(), "unclosed {");
        Parser parser = new(tokens, end);
        List<Node> elements = parser.ElementList(true);
        if (parser.Peek.Kind != "eof") throw parser.Unexpected();
        return new Formula(elements, parser.tag, parser.label);
    }
}
