import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
import java.util.function.IntFunction;
final class Report {
    static String fixed(long value) {
        long n = Math.abs(value);
        return (value < 0 ? "-" : "") + (n / 10000) + "." + String.format(Locale.ROOT, "%04d", n % 10000);
    }
    static String average(long total, long count) {
        return fixed(DynamicProgramming.floor(total * 10000, count));
    }
    static String cell(Environment world, int x) {
        return (x / world.width) + "," + (x % world.width);
    }
    static List<String> grid(Environment world, boolean separated, IntFunction<String> content) {
        List<String> output = new ArrayList<>();
        for (int r = 0; r < world.height; r++) {
            List<String> row = new ArrayList<>();
            for (int c = 0; c < world.width; c++) {
                int x = r * world.width + c;
                row.add(world.cells[x] == '#' || world.terminal(x) ? Character.toString(world.cells[x])
                                                                   : content.apply(x));
            }
            output.add(String.join(separated ? " " : "", row));
        }
        return output;
    }
    static void qRows(List<String> output, String method, Environment world, long[][] values,
                      long[][] visits) {
        for (int x : world.states)
            for (int a = 0; a < 4; a++)
                output.add(method + "," + cell(world, x) + ","
                           + "NESW".charAt(a) + "," + fixed(values[x][a]) + "," +
                           (visits == null ? "-" : visits[x][a]));
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
