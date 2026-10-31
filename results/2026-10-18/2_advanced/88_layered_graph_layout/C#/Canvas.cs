readonly record struct Cell(int Row, int Column);
sealed class Canvas
{
    readonly int main;
    readonly string direction;
    readonly bool vertical;
    readonly byte[,] lines;
    readonly char[,] arrows;
    readonly char[,] boxes;
    readonly bool[,] highlighted;
    public int Rows {
        get;
    }
    public int Columns {
        get;
    }
    public Canvas(int main, int secondary, string direction)
    {
        this.main = main;
        this.direction = direction;
        vertical = direction is "TB" or "BT";
        Rows = vertical ? main : secondary;
        Columns = vertical ? secondary : main;
        lines = new byte[Rows, Columns];
        arrows = new char[Rows, Columns];
        boxes = new char[Rows, Columns];
        highlighted = new bool[Rows, Columns];
    }
    public Cell Map(int m, int secondary)
    {
        int mapped = direction is "BT" or "RL" ? main - 1 - m : m;
        return vertical ? new Cell(mapped, secondary) : new Cell(secondary, mapped);
    }
    public void Line(int m, int c, bool mainLine)
    {
        Cell p = Map(m, c);
        lines[p.Row, p.Column] |= (byte)(mainLine == vertical ? 1 : 2);
    }
    public void Corner(int m, int c) {
        Cell p = Map(m, c);
        lines[p.Row, p.Column] |= 4;
    }
    public void Arrow(int m, int c, bool reversed)
    {
        Cell p = Map(m, c);
        arrows[p.Row, p.Column] = (direction, reversed) switch {
            ("TB", false) or ("BT", true) => 'v', ("TB", true) or ("BT", false) => '^', ("LR", false) or ("RL", true) => '>', _ => '<'
        };
    }
    public void Highlight(int row, int column) => highlighted[row, column] = true;
    public void Label(int row, int column, string text) {
        for (int i = 0; i < text.Length; i++) boxes[row, column + i] = text[i];
    }
    public int Crossings()
    {
        int count = 0;
        for (int r = 0; r < Rows; r++) for (int c = 0; c < Columns; c++) if ((lines[r, c] & 3) == 3) count++;
        return count;
    }
    public List<string> Report()
    {
        List<string> result = new() {
            "    " + string.Concat(Enumerable.Range(0, Columns).Select(c => (c % 10).ToString(CultureInfo.InvariantCulture)))
        };
        for (int row = 0; row < Rows; row++)
        {
            StringBuilder text = new(row.ToString(CultureInfo.InvariantCulture).PadLeft(3) + " ");
            for (int column = 0; column < Columns; column++)
            {
                char c = boxes[row, column] != '\0' ? boxes[row, column] : arrows[row, column] != '\0' ? arrows[row, column] : highlighted[row, column] ? '#' : lines[row, column] switch {
                    0 => ' ', 1 => '|', 2 => '-', _ => '+'
                };
                text.Append(c);
            }
            result.Add(text.ToString().TrimEnd(' '));
        }
        return result;
    }
}
