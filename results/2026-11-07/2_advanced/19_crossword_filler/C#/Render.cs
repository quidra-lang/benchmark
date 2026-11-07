using System.Collections.Generic;

static class Render {
    public static string Decimal(int numerator, int denominator, int places) {
        int scale = 1;
        for (int i = 0; i < places; i++) scale *= 10;
        int rounded = (2 * numerator * scale + denominator) / (2 * denominator);
        return rounded / scale + "." + (rounded % scale).ToString().PadLeft(places, '0');
    }
    public static List<string> GridLines(Grid grid, char[] letters) {
        List<string> lines = new();
        for (int row = 0; row < grid.Height; row++) lines.Add(new string(letters, row * grid.Width, grid.Width));
        return lines;
    }
    public static List<string> NumberLines(Layout layout) {
        Grid grid = layout.Grid;
        List<string> lines = new();
        for (int row = 0; row < grid.Height; row++) {
            List<string> marks = new();
            for (int column = 0; column < grid.Width; column++) {
                int cell = grid.Cell(row, column);
                marks.Add(!grid.Open(row, column) ? "##" : layout.Numbers[cell] > 0 ? layout.Numbers[cell].ToString().PadLeft(2) : " .");
            }
            lines.Add(string.Join(" ", marks));
        }
        return lines;
    }
    public static string ListLine(Slot slot, string clue, string entry, string score, bool theme) => slot.Number + ". " + clue + " (" + slot.Length + ") " + entry + " " + score + (theme ? " theme" : "");
}
