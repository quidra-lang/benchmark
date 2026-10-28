import java.util.*;

final class Evaluation {
    static String real(double value, int digits) {
        String s = String.format(Locale.ROOT, "%." + digits + "f", value);
        return s.startsWith("-") && Double.parseDouble(s) == 0 ? s.substring(1) : s;
    }
    static String ratio(int a, int b) {
        if (b == 0)
            return "-";
        int q = (20000 * a + b) / (2 * b);
        return q / 10000 + "." + String.format(Locale.ROOT, "%04d", q % 10000);
    }
    static int prediction(double[] scores) {
        int selected = 0;
        for (int k = 1; k < scores.length; k++)
            if (scores[k] > scores[selected])
                selected = k;
        return selected;
    }
    static int second(double[] scores, int first) {
        int selected = -1;
        for (int k = 0; k < scores.length; k++)
            if (k != first && (selected < 0 || scores[k] > scores[selected]))
                selected = k;
        return selected;
    }
    static int[][] confusion(List<Dataset.Image> images, List<Network.Pass> passes, int classes) {
        int[][] counts = new int[classes][classes];
        for (int i = 0; i < images.size(); i++)
            counts[images.get(i).label()][prediction(passes.get(i).scores())]++;
        return counts;
    }
    static List<String> confusionLines(int[][] counts) {
        List<String> lines = new ArrayList<>();
        int classes = counts.length;
        for (int k = 0; k < classes; k++) {
            List<String> values = new ArrayList<>();
            for (int value : counts[k])
                values.add(Integer.toString(value));
            lines.add(k + ": " + String.join(" ", values));
        }
        for (int k = 0; k < classes; k++) {
            int support = 0, predicted = 0;
            for (int j = 0; j < classes; j++) {
                support += counts[k][j];
                predicted += counts[j][k];
            }
            lines.add("class " + k + " support " + support + " predicted " + predicted + " precision " +
                      ratio(counts[k][k], predicted) + " recall " + ratio(counts[k][k], support) + " f1 " +
                      ratio(2 * counts[k][k], support + predicted));
        }
        return lines;
    }
    static List<String> maps(int[][] levels, int width, int height) {
        List<String> lines = new ArrayList<>();
        for (int r = 0; r < height; r++) {
            List<String> cells = new ArrayList<>();
            for (int[] level : levels) {
                StringBuilder row = new StringBuilder();
                for (int c = 0; c < width; c++)
                    row.append(level[r * width + c]);
                cells.add(row.toString());
            }
            lines.add(String.join(" ", cells));
        }
        return lines;
    }
    static List<String> image(Dataset.Image image, int width, int height) {
        List<String> lines = new ArrayList<>();
        for (int r = 0; r < height; r++) {
            StringBuilder row = new StringBuilder();
            for (int c = 0; c < width; c++)
                row.append(image.pixels().charAt(r * width + c) == '1' ? '#' : '.');
            lines.add(row.toString());
        }
        return lines;
    }
}
