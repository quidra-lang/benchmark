sealed record Params(int Width, int Indent, int Rel, int Binary, int Punctuation, int ColGap, int RowGap);
sealed record Spacing(List<(int Left, int Right)> Types, List<int> Gaps);
static class Layout
{
    public static (int Left, int Right) Types(Node node) => node switch
    {
        AtomNode a => (Boxes.AtomType(a.Kind, a.Value), Boxes.AtomType(a.Kind, a.Value)),
        DelimitedNode => (4, 5), ScriptNode s => Types(s.Base),
        BinaryNode {
            Name: "overset" or "underset"
        } b => Types(b.Second), _ => (0, 0)
    };
    public static bool Word(Node node) => node switch
    {
        AtomNode a => a.Kind == "command" && (Lexer.Greek.Contains(a.Value[1..]) || a.Value == "\\infty"),
        ScriptNode s => Word(s.Base), _ => false
    };
    public static bool Alphanumeric(Node node)
    {
        if (Word(node)) return true;
        return node switch
        {
            AtomNode a => a.Kind is "identifier" or "number", ScriptNode s => Alphanumeric(s.Base),
            AccentNode a => a.Name is "overline" or "hat" or "vec" or "dot" or "tilde" && Alphanumeric(a.Body), _ => false
        };
    }
    public static Spacing Space(List<Node> nodes, bool script, Params p)
    {
        List<(int Left, int Right)> types = nodes.Select(Types).ToList();
        for (int i = 0; i < types.Count; i++)
        {
            if (types[i].Left == 2 && (i == 0 || new[] {
                1, 2, 3, 4, 6
            }.Contains(types[i - 1].Right))) types[i] = (0, 0);
            if (types[i].Left is 3 or 5 or 6 && i > 0 && types[i - 1].Right == 2) types[i - 1] = (0, 0);
        }
        if (types.Count > 0 && types[^1].Right == 2) types[^1] = (0, 0);
        int[][] table = [[0,1,2,3,0,0,0],[1,1,0,3,0,0,0],[2,2,0,0,2,0,0],[3,3,0,0,3,0,0],[0,0,0,0,0,0,0],[0,1,2,3,0,0,0],[4,4,0,4,4,4,4]];
        List<int> gaps = new();
        for (int i = 0; i < nodes.Count - 1; i++)
        {
            int gap = Alphanumeric(nodes[i]) && Alphanumeric(nodes[i + 1]) && (Word(nodes[i]) || Word(nodes[i + 1])) ? 1 : table[types[i].Right][types[i + 1].Left] switch {
                0 => 0, 1 => 1, 2 => script ? 0 : p.Binary, 3 => script ? 0 : p.Rel, _ => script ? 0 : p.Punctuation
            };
            gaps.Add(gap);
        }
        return new Spacing(types, gaps);
    }
    public static Box Row(List<Box> elements, List<int> gaps, string description, List<string>? roles = null)
    {
        int ascent = elements.Select(b => b.Baseline).DefaultIfEmpty(0).Max(), descent = elements.Select(b => b.Height - 1 - b.Baseline).DefaultIfEmpty(0).Max();
        Box result = new(elements.Sum(b => b.Width) + gaps.Sum(), ascent + descent + 1, ascent, description);
        int x = 0;
        for (int i = 0; i < elements.Count; i++)
        {
            Box box = elements[i];
            result.Child(box, x, ascent - box.Baseline, roles is not null && i < roles.Count ? roles[i] : "");
            x += box.Width + (i < gaps.Count ? gaps[i] : 0);
        }
        return result;
    }
}
