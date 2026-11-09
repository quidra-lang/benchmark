static class Render
{
    public static char StateChar(char state) => state;
    public static string StateString(char[] cells) => new(cells.Select(StateChar).ToArray());
    public static List<string> GridDisplay(List<(string Name, char[][] Grid)> grids)
    {
        if (grids.Count == 0) return []; List<string> result = ["grid " + string.Join(' ',grids.Select(g => g.Name))];
        for (int r = 0; r < grids[0].Grid.Length; r++) result.Add(string.Join(" | ",grids.Select(g => StateString(g.Grid[r])))); return result;
    }
    public static List<string> AnswerSheet(List<int[]> rows, List<int[]> columns, char[][] grid)
    {
        List<string[]> tokens = columns.Select(c => Clues.Text(c).Split(' ')).ToList(); int width = tokens.SelectMany(c => c).Max(t => t.Length) + 1, depth = tokens.Max(c => c.Length), margin = rows.Max(c => Clues.Text(c).Length); List<string> result = [];
        for (int i = 0; i < depth; i++) { string text = new(' ',margin); foreach (string[] column in tokens) { int index = i - depth + column.Length; text += (index < 0 ? "" : column[index]).PadLeft(width); } result.Add(text.TrimEnd(' ')); }
        for (int r = 0; r < rows.Count; r++) result.Add(Clues.Text(rows[r]).PadLeft(margin) + string.Concat(grid[r].Select(c => new string(' ',width - 1) + StateChar(c)))); return result;
    }
}
