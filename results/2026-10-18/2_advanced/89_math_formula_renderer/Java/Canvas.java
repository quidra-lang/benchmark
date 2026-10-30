import java.util.*;
final class Canvas {
    record Root(Boxes.Box box, int x, int y) {}
    record Entry(Boxes.Box box, int x, int y, int level, String role) {
        String line() {
            return "  ".repeat(level) + role + box.description + " x=" + x + " y=" + y +
                " w=" + box.width + " h=" + box.height + " b=" + box.baseline;
        }
        String kind() { return box.description.split(" ", 2)[0]; }
    }
    static void walk(Boxes.Box box, int x, int y, int level, String role, List<Entry> entries) {
        entries.add(new Entry(box, x, y, level, role));
        for (Boxes.Child child : box.children)
            walk(child.box(), x + child.x(), y + child.y(), level + 1, child.role(), entries);
    }
    static List<Entry> entries(List<Root> roots) {
        List<Entry> entries = new ArrayList<>();
        for (Root root : roots)
            walk(root.box(), root.x(), root.y(), 0, "", entries);
        return entries;
    }
    static String trim(String text) {
        int end = text.length();
        while (end > 0 && text.charAt(end - 1) == ' ')
            end--;
        return text.substring(0, end);
    }
    static List<String> draw(List<Root> roots, int width, int height) {
        char[][] grid = new char[height][width];
        for (char[] row : grid)
            Arrays.fill(row, ' ');
        for (Entry entry : entries(roots))
            for (Boxes.Drawn drawn : entry.box().strings)
                for (int i = 0; i < drawn.text().length(); i++)
                    if (drawn.text().charAt(i) != ' ')
                        grid[entry.y() + drawn.y()][entry.x() + drawn.x() + i] =
                            drawn.text().charAt(i);
        List<String> lines = new ArrayList<>();
        for (char[] row : grid)
            lines.add(trim(new String(row)));
        return lines;
    }
}
