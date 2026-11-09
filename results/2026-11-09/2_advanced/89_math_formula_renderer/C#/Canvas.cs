sealed record Description(List<string> Lines, Dictionary<string, int> Kinds, int Depth);
static class Canvas
{
    public static void Paint(Box box, int x, int y, char[,] grid)
    {
        foreach (Ink ink in box.Strings) for (int i = 0; i < ink.Text.Length; i++) if (ink.Text[i] != ' ') grid[y + ink.Y, x + ink.X + i] = ink.Text[i];
        foreach (Child child in box.Children) Paint(child.Node, x + child.X, y + child.Y, grid);
    }
    public static Description Describe(List<Child> roots)
    {
        List<string> lines = new();
        Dictionary<string, int> kinds = new(StringComparer.Ordinal);
        int depth = 0;
        void Visit(Box box, int x, int y, int level, string role)
        {
            lines.Add(new string(' ', level * 2) + role + box.Description + $" x={x} y={y} w={box.Width} h={box.Height} b={box.Baseline}");
            string kind = box.Description.Split(' ')[0];
            kinds[kind] = kinds.GetValueOrDefault(kind) + 1;
            depth = Math.Max(depth, level + 1);
            foreach (Child child in box.Children) Visit(child.Node, x + child.X, y + child.Y, level + 1, child.Role);
        }
        foreach (Child root in roots) Visit(root.Node, root.X, root.Y, 0, "");
        return new Description(lines, kinds, depth);
    }
    public static List<string> Lines(char[,] grid)
    {
        List<string> lines = new();
        for (int y = 0; y < grid.GetLength(0); y++)
        {
            char[] row = new char[grid.GetLength(1)];
            for (int x = 0; x < row.Length; x++) row[x] = grid[y, x];
            lines.Add(new string(row).TrimEnd(' '));
        }
        return lines;
    }
}
