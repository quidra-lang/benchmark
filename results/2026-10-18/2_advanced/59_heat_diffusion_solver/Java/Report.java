import java.nio.file.*;
import java.util.*;

final class Report {
    record MapImage(int[] counts, List<String> lines) {}
    static String real(double value, int places) {
        String s = String.format(Locale.ROOT, "%." + places + "f", value);
        return s.equals("-0."
                        + "0".repeat(places))
            ? s.substring(1)
            : s;
    }
    static String time(int ms) {
        return ms / 1000 + "." + String.format(Locale.ROOT, "%03d", ms % 1000);
    }
    static List<String> field(Mesh m, double[] x) {
        List<String> lines = new ArrayList<>();
        for (int r = 0; r < m.height; r++) {
            List<String> values = new ArrayList<>();
            for (int c = 0; c < m.width; c++)
                values.add(real(x[m.cell(r, c)], 2));
            lines.add(String.join(" ", values));
        }
        return lines;
    }
    static MapImage isotherm(Mesh m, double[] x, double[] bands) {
        int hottest = 0;
        for (int p = 1; p < x.length; p++)
            if (x[p] > x[hottest])
                hottest = p;
        int[] counts = new int[bands.length + 1];
        char[] cells = new char[x.length];
        for (int p = 0; p < x.length; p++) {
            int digit = 0;
            for (double band : bands)
                if (band <= x[p])
                    digit++;
            counts[digit]++;
            cells[p] = p == hottest ? '*' : (char)('0' + digit);
        }
        List<String> lines = new ArrayList<>();
        for (int r = 0; r < m.height; r++)
            lines.add(new String(cells, r * m.width, m.width));
        return new MapImage(counts, lines);
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
}
