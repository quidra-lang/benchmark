static class LineSolver
{
    public const char Unknown = '?', Filled = '#', Empty = '.';
    static bool[,] FitTable(char[] cells, int[] clue)
    {
        int n = cells.Length, k = clue.Length; int[] empties = new int[n + 1]; for (int i = 0; i < n; i++) empties[i + 1] = empties[i] + (cells[i] == Empty ? 1 : 0);
        bool[,] table = new bool[n + 1,k + 1]; table[0,0] = true;
        for (int end = 1; end <= n; end++) for (int count = 0; count <= k; count++)
        {
            bool fits = cells[end - 1] != Filled && table[end - 1,count];
            if (!fits && count > 0) { int start = end - clue[count - 1]; if (start >= 0 && empties[end] == empties[start]) fits = start == 0 ? count == 1 : cells[start - 1] != Filled && table[start - 1,count - 1]; } table[end,count] = fits;
        }
        return table;
    }
    sealed class Placements
    {
        readonly char[] cells;
        readonly int[] clue;
        readonly bool[,] before, after;
        public Placements(char[] cells, int[] clue) { this.cells = cells; this.clue = clue; before = FitTable(cells,clue); after = FitTable(cells.Reverse().ToArray(),clue.Reverse().ToArray()); }
        public bool Consistent => before[cells.Length,clue.Length];
        public List<int> Starts(int block)
        {
            List<int> starts = []; int n = cells.Length;
            for (int start = 0; start + clue[block] <= n; start++)
            {
                int end = start + clue[block], rest = clue.Length - block - 1; if (cells.Skip(start).Take(clue[block]).Contains(Empty)) continue;
                bool left = start == 0 ? block == 0 : cells[start - 1] != Filled && before[start - 1,block];
                bool right = end == n ? rest == 0 : cells[end] != Filled && after[n - end - 1,rest]; if (left && right) starts.Add(start);
            }
            return starts;
        }
        public bool CanBeEmpty(int index) => cells[index] != Filled && Enumerable.Range(0,clue.Length + 1).Any(k => before[index,k] && after[cells.Length - index - 1,clue.Length - k]);
    }
    public static bool HasPlacement(char[] cells, int[] clue) => new Placements(cells,clue).Consistent;
    public static char[]? Solve(char[] cells, int[] clue, bool precise)
    {
        Placements placements = new(cells,clue); if (!placements.Consistent) return null; char[] solved = (char[])cells.Clone(); bool[] covered = new bool[cells.Length];
        for (int block = 0; block < clue.Length; block++)
        {
            List<int> starts = placements.Starts(block); int length = clue[block];
            if (precise) { foreach (int start in starts) for (int i = start; i < start + length; i++) covered[i] = true; }
            else { for (int i = starts[^1]; i < starts[0] + length; i++) if (solved[i] == Unknown) solved[i] = Filled; for (int i = starts[0]; i < starts[^1] + length; i++) covered[i] = true; }
        }
        for (int i = 0; i < cells.Length; i++) if (solved[i] == Unknown) { if (!covered[i]) solved[i] = Empty; else if (precise && !placements.CanBeEmpty(i)) solved[i] = Filled; } return solved;
    }
}
