using System.Collections.Generic;
using System.Linq;

sealed class Grid {
    public readonly List<string> Rows;
    public readonly int Height, Width;
    public readonly char[] Cells;
    public Grid(List<string> rows) {
        Rows = rows;
        Height = rows.Count;
        Width = rows[0].Length;
        Cells = string.Concat(rows).ToCharArray();
    }
    public int Size => Height * Width;
    public int Cell(int row, int column) => row * Width + column;
    public string Location(int cell) => (cell / Width + 1) + "," + (cell % Width + 1);
    public bool Open(int row, int column) => row >= 0 && row < Height && column >= 0 && column < Width && Rows[row][column] != '#';
    public bool Given(int cell) => Cells[cell] != '#' && Cells[cell] != '.';
    public List<int> Whites() => Enumerable.Range(0, Size).Where(cell => Cells[cell] != '#').ToList();
    public int Asymmetric(string symmetry) {
        for (int row = 0; row < Height; row++) for (int column = 0; column < Width; column++) {
            int otherRow = symmetry == "rot180" ? Height - 1 - row : row;
            if (Open(row, column) != Open(otherRow, Width - 1 - column)) return Cell(row, column);
        }
        return -1;
    }
    public int Components() {
        bool[] seen = new bool[Size];
        int count = 0;
        int[] dr = [-1, 1, 0, 0], dc = [0, 0, -1, 1];
        foreach (int start in Whites()) {
            if (seen[start]) continue;
            count++;
            seen[start] = true;
            Stack<int> stack = new();
            stack.Push(start);
            while (stack.Count > 0) {
                int point = stack.Pop(), row = point / Width, column = point % Width;
                for (int i = 0; i < 4; i++) if (Open(row + dr[i], column + dc[i])) {
                    int neighbor = Cell(row + dr[i], column + dc[i]);
                    if (!seen[neighbor]) { seen[neighbor] = true; stack.Push(neighbor); }
                }
            }
        }
        return count;
    }
}
