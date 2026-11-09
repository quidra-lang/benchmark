import java.util.*;

final class Plot {
    static List<String> draw(List<List<Dataset.Subject>> groups, List<List<Estimators.Row>> tables, int width,
                             int height, int horizon) {
        int[][] occupied = new int[height][width];
        for (int g = 0; g < groups.size(); g++) {
            int maximum = 0;
            for (Dataset.Subject s : groups.get(g))
                maximum = Math.max(maximum, s.time());
            int previous = -1;
            for (int col = 0; col < width; col++) {
                int time = col * (horizon / width);
                if (time > maximum)
                    break;
                double survival = Estimators.at(tables.get(g), time).survival;
                int band = Math.min(height - 1, (int)Math.floor(survival * height));
                occupied[height - 1 - band][col] |= 1 << g;
                if (previous - 1 > band)
                    for (int q = band + 1; q < previous; q++)
                        occupied[height - 1 - q][col] |= 1 << g;
                previous = band;
            }
        }
        String border = "   +"
                        + "-".repeat(width) + "+";
        List<String> output = new ArrayList<>();
        output.add(border);
        for (int row = 0; row < height; row++) {
            int q = height - 1 - row;
            StringBuilder line = new StringBuilder(Main.pad(Integer.toString(100 * q / height), 3) + "|");
            for (int value : occupied[row])
                line.append(value == 0 ? ' '
                            : Integer.bitCount(value) == 1
                                ? (char)('A' + Integer.numberOfTrailingZeros(value))
                                : '*');
            output.add(line + "|");
        }
        output.add(border);
        return output;
    }
}
