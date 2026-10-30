sealed record Child(string Role, int X, int Y, Box Node);
sealed record Ink(int X, int Y, string Text);
sealed class Box(int width, int height, int baseline, string description)
{
    public int Width {
        get;
    } = width;
    public int Height {
        get;
    } = height;
    public int Baseline {
        get;
    } = baseline;
    public string Description {
        get;
    } = description;
    public List<Child> Children {
        get;
    } = new();
    public List<Ink> Strings {
        get;
    } = new();
    public void Child(Box node, int x, int y, string role = "") => Children.Add(new Child(role, x, y, node));
    public void String(int x, int y, string text) => Strings.Add(new Ink(x, y, text));
    public void Delimiter(string text, int x)
    {
        List<string> glyph = Boxes.Delimiter(text, Height);
        for (int y = 0; y < glyph.Count; y++) String(x, y, glyph[y]);
    }
    public static Box Text(string display, string description)
    {
        Box node = new(display.Length, 1, 0, description);
        node.String(0, 0, display);
        return node;
    }
}
static class Boxes
{
    public static List<string> Delimiter(string text, int height)
    {
        if (text == ".") return new();
        string plain = text == "\\{" ? "{" : text == "\\}" ? "}" : text;
        if (height == 1) return new() {
            plain
        };
        List<string> glyph = Enumerable.Repeat(plain, height).ToList();
        if (text is "(" or "\\{")
        {
            glyph = Enumerable.Repeat("|", height).ToList();
            glyph[0] = "/";
            glyph[^1] = "\\";
            if (text == "\\{" && height >= 3) glyph[(height - 1) / 2] = "<";
        }
        else if (text is ")" or "\\}")
        {
            glyph = Enumerable.Repeat("|", height).ToList();
            glyph[0] = "\\";
            glyph[^1] = "/";
            if (text == "\\}" && height >= 3) glyph[(height - 1) / 2] = ">";
        }
        return glyph;
    }
    public static string[] Large(string name) => name == "sum" ? ["\\--", " > ", "/--"] : name == "prod" ? ["___", "| |", "| |"] : [" /", " |", "/ "];
    public static int AtomType(string kind, string value)
    {
        if (kind == "command") return Lexer.Symbol(value[1..])!.Value.Type;
        if (kind != "symbol") return 0;
        return value switch {
            "+" or "-" or "*" => 2, "=" or "<" or ">" or ":" => 3, "(" or "[" => 4, ")" or "]" or "!" => 5, "," or ";" => 6, _ => 0
        };
    }
}
