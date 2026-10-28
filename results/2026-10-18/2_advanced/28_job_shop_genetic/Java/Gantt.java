import java.util.*;

record Interval(int start, int end, char mark) {}
final class Gantt {
    static int[] scale(int makespan, int width) {
        for (int magnitude = 1;; magnitude *= 10)
            for (int step : new int[] {1, 2, 5}) {
                int scale = magnitude * step, columns = (makespan + scale - 1) / scale;
                if (columns <= width)
                    return new int[] {scale, columns};
            }
    }
    static String time(int scale, int columns) {
        StringBuilder row = new StringBuilder("time");
        for (int c = 0; c < columns; c += 10) {
            while (row.length() < 6 + c)
                row.append(' ');
            row.append(c * scale);
        }
        return row.toString();
    }
    static String rule(int columns) {
        StringBuilder row = new StringBuilder("      ");
        for (int c = 0; c < columns; c++)
            row.append(c % 10 == 0 ? '+' : '-');
        return row.toString();
    }
    static String frame(String label, String marks) {
        return label + " ".repeat(4 - label.length()) + " |" + marks + "|";
    }
    static String row(String label, List<Interval> intervals, int scale, int columns) {
        List<Interval> ordered = new ArrayList<>(intervals);
        ordered.sort(Comparator.comparingInt(Interval::start));
        StringBuilder marks = new StringBuilder();
        for (int c = 0; c < columns; c++) {
            int widest = 0;
            char mark = '.';
            for (Interval interval : ordered) {
                int overlap =
                    Math.min(interval.end(), (c + 1) * scale) - Math.max(interval.start(), c * scale);
                if (overlap > widest) {
                    widest = overlap;
                    mark = interval.mark();
                }
            }
            marks.append(mark);
        }
        return frame(label, marks.toString());
    }
    static String busy(List<List<Interval>> machines, int scale, int columns) {
        StringBuilder marks = new StringBuilder();
        for (int c = 0; c < columns; c++) {
            int count = 0;
            for (List<Interval> intervals : machines) {
                boolean found = false;
                for (Interval interval : intervals)
                    if (interval.start() <= c * scale && c * scale < interval.end())
                        found = true;
                if (found)
                    count++;
            }
            marks.append(count == 10 ? 'X' : (char)('0' + count));
        }
        return frame("busy", marks.toString());
    }
}
