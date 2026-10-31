import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class Render {
    static String decimal(int numerator, int denominator, int places) {
        int scale = 1; for (int i = 0; i < places; i++) scale *= 10;
        int rounded = (2 * numerator * scale + denominator) / (2 * denominator);
        String fraction = Integer.toString(rounded % scale);
        return rounded / scale + "." + "0".repeat(places - fraction.length()) + fraction;
    }
    static List<String> gridLines(Grid grid, char[] letters) {
        List<String> lines = new ArrayList<>();
        for (int row = 0; row < grid.height; row++) lines.add(new String(letters, row * grid.width, grid.width));
        return lines;
    }
    static List<String> numberLines(Layout layout) {
        Grid grid = layout.grid; List<String> lines = new ArrayList<>();
        for (int row = 0; row < grid.height; row++) {
            List<String> marks = new ArrayList<>();
            for (int column = 0; column < grid.width; column++) { int cell = grid.cell(row, column); marks.add(!grid.open(row, column) ? "##" : layout.numbers[cell] > 0 ? String.format(Locale.ROOT, "%2d", layout.numbers[cell]) : " ."); }
            lines.add(String.join(" ", marks));
        }
        return lines;
    }
    static String listLine(Slot slot, String clue, String entry, String score, boolean theme) { return slot.number + ". " + clue + " (" + slot.length + ") " + entry + " " + score + (theme ? " theme" : ""); }
}
