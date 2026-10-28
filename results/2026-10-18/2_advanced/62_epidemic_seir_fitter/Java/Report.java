import java.util.*;

final class Report {
    static String f(double value, int places) {
        String s = String.format(Locale.ROOT, "%." + places + "f", value);
        return s.startsWith("-") && Double.parseDouble(s) == 0 ? s.substring(1) : s;
    }
    static List<String> plot(int[] observed, double[] fitted) {
        int n = observed.length, maximum = 0;
        for (int value : observed)
            maximum = Math.max(maximum, value);
        int width = Integer.toString(maximum).length();
        char[][] grid = new char[20][70];
        for (char[] row : grid)
            Arrays.fill(row, '.');
        for (int x = 0; x < 70; x++) {
            int day = x * (n - 1) / 69, oy = Math.min(19, 20 * observed[day] / maximum),
                fy = Math.min(19, (int)Math.floor(20 * fitted[day] / maximum));
            grid[oy][x] = 'o';
            grid[fy][x] = oy == fy ? '#' : '*';
        }
        List<String> lines =
            new ArrayList<>(List.of("plot observed o fitted * both # days 1 " + n + " max " + maximum));
        for (int y = 19; y >= 0; y--)
            lines.add(String.format(Locale.ROOT, "%" + width + "d", maximum * y / 20) + " |" +
                      new String(grid[y]));
        StringBuilder ticks = new StringBuilder();
        for (int x = 0; x < 70; x++)
            ticks.append(x % 10 == 0 ? '+' : '-');
        lines.add(" ".repeat(width + 1) + "+" + ticks);
        char[] labels = new char[70];
        Arrays.fill(labels, ' ');
        for (int x = 0; x <= 60; x += 10) {
            String label = Integer.toString(1 + x * (n - 1) / 69);
            for (int i = 0; i < label.length(); i++)
                labels[x + i] = label.charAt(i);
        }
        String line = " ".repeat(width + 2) + new String(labels);
        int end = line.length();
        while (end > 0 && line.charAt(end - 1) == ' ')
            end--;
        lines.add(line.substring(0, end));
        return lines;
    }
}
