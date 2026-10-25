static class Clues
{
    public static bool IsLine(string text) => text.Length > 0 && text.All(c => c == ' ' || c >= '0' && c <= '9');
    public static int[]? Parse(string text)
    {
        if (text == "0") return []; string[] tokens = text.Split(' ');
        if (tokens.Any(t => t.Length is < 1 or > 2 || t[0] == '0' || t.Any(c => c < '0' || c > '9'))) return null; return tokens.Select(int.Parse).ToArray();
    }
    public static int[] Run(IEnumerable<char> cells)
    {
        List<int> clue = []; int run = 0; foreach (char state in cells) { if (state == LineSolver.Filled) run++; else if (run > 0) { clue.Add(run); run = 0; } } if (run > 0) clue.Add(run); return clue.ToArray();
    }
    public static string Text(int[] clue, char separator = ' ') => clue.Length == 0 ? "0" : string.Join(separator,clue);
    public static int Span(int[] clue) => clue.Sum() + clue.Length - 1;
    public static bool Equal(List<int[]> a, List<int[]> b) => a.Count == b.Count && a.Zip(b).All(pair => pair.First.SequenceEqual(pair.Second));
}
