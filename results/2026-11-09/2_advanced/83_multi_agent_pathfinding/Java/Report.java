import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Report {
    static String cell(GridMap.Cell cell) { return cell.x() + "," + cell.y(); }
    static char name(int number) { return (char)('A' + number); }
    static String actions(List<GridMap.Cell> path) {
        StringBuilder result = new StringBuilder();
        for (int i = 1; i < path.size(); i++) {
            int dx = path.get(i).x() - path.get(i - 1).x(),
                dy = path.get(i).y() - path.get(i - 1).y();
            result.append(dx == 1 ? 'E' : dx == -1 ? 'W' : dy == 1 ? 'S' : dy == -1 ? 'N' : '.');
        }
        return result.toString();
    }
    static String conflict(Cbs.Conflict c) {
        String start = c.kind() + " t " + c.time() + " " + name(c.a()) + " " + name(c.b());
        return c.kind().equals("vertex") ? start + " at " + c.v()
                                         : start + " from " + c.u() + " to " + c.v();
    }
    static String fraction(int numerator, int denominator) {
        int a = numerator, b = denominator;
        while (b != 0) {
            int r = a % b;
            a = b;
            b = r;
        }
        return numerator / a + "/" + denominator / a;
    }
    static String csv(List<String> values) { return String.join(",", values); }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
