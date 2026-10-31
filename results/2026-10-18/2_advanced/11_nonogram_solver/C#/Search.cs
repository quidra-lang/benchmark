sealed record Guess(int Number, int Depth, int Row, int Column, char Value, int Solves, int Known, string Result);
sealed class Search
{
    public List<Guess> Guesses = [];
    public List<char[][]> Solutions = [];
    public int Backtracks, MaxDepth, LineSolves;
    public static (int Row, int Column) GuessCell(char[][] grid)
    {
        int h = grid.Length, w = grid[0].Length; int[] rows = new int[h], columns = new int[w];
        for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) if (grid[r][c] == LineSolver.Unknown) { rows[r]++; columns[c]++; }
        (int Row, int Column) best = (-1,-1); int score = int.MaxValue;
        for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) if (grid[r][c] == LineSolver.Unknown && rows[r] + columns[c] < score) { best = (r,c); score = rows[r] + columns[c]; } return best;
    }
    public static Search Run(char[][] grid, List<int[]> rows, List<int[]> columns)
    {
        Search result = new(); int h = rows.Count, w = columns.Count;
        bool Visit(char[][] parent, int depth)
        {
            var cell = GuessCell(parent);
            foreach (char value in new[] { LineSolver.Filled,LineSolver.Empty })
            {
                char[][] child = Propagation.Copy(parent); child[cell.Row][cell.Column] = value; bool[] rowMarks = new bool[h], columnMarks = new bool[w]; rowMarks[cell.Row] = true; columnMarks[cell.Column] = true;
                Propagation propagation = Propagation.Run(child,rows,columns,true,rowMarks,columnMarks); int known = Propagation.Determined(child); string outcome = "open";
                if (propagation.Conflict is not null) { outcome = "contradiction at=" + propagation.Conflict.Label; result.Backtracks++; }
                else if (known == h * w) { result.Solutions.Add(child); outcome = "solution" + result.Solutions.Count; }
                result.LineSolves += propagation.Steps.Count; result.MaxDepth = Math.Max(result.MaxDepth,depth); result.Guesses.Add(new(result.Guesses.Count + 1,depth,cell.Row,cell.Column,value,propagation.Steps.Count,known,outcome));
                if (outcome == "open") { if (Visit(child,depth + 1)) return true; } else if (result.Solutions.Count == 2) return true;
            }
            return false;
        }
        Visit(grid,1); return result;
    }
}
