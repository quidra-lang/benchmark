sealed record LineStep(bool Row, int Index, int Gain, bool Contradiction)
{
    public string Label => Propagation.Label(Row,Index);
    public string Text => Label + (Contradiction ? "!" : "+" + Gain);
}
sealed class Propagation
{
    public List<LineStep> Steps = [];
    public LineStep? Conflict;
    public string Record => string.Join(' ',Steps.Select(s => s.Text));
    public static string Label(bool row, int index) => (row ? "R" : "C") + (index + 1);
    public static char[] Cells(char[][] grid, bool row, int index) => row ? (char[])grid[index].Clone() : grid.Select(cells => cells[index]).ToArray();
    public static int Determined(char[][] grid) => grid.Sum(row => row.Count(c => c != LineSolver.Unknown));
    public static char[][] Copy(char[][] grid) => grid.Select(row => (char[])row.Clone()).ToArray();
    public static Propagation Run(char[][] grid, List<int[]> rows, List<int[]> columns, bool precise, bool[] rowMarks, bool[] columnMarks)
    {
        Propagation result = new();
        while (true)
        {
            int index = Array.IndexOf(rowMarks,true); bool row = index >= 0;
            if (row) rowMarks[index] = false; else { index = Array.IndexOf(columnMarks,true); if (index < 0) return result; columnMarks[index] = false; }
            char[] cells = Cells(grid,row,index); char[]? solved = LineSolver.Solve(cells,row ? rows[index] : columns[index],precise);
            if (solved is null) { LineStep step = new(row,index,0,true); result.Steps.Add(step); result.Conflict = step; return result; }
            int gain = 0;
            for (int i = 0; i < cells.Length; i++) if (cells[i] == LineSolver.Unknown && solved[i] != LineSolver.Unknown)
            {
                gain++; if (row) { grid[index][i] = solved[i]; columnMarks[i] = true; } else { grid[i][index] = solved[i]; rowMarks[i] = true; }
            }
            result.Steps.Add(new(row,index,gain,false));
        }
    }
}
