import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.stream.IntStream;

public class Main {
    public static void main(String[] args) {
        String[] names = {"Tanaka", "Suzuki", "Yamada", "Ito", "Kato", "Mori"};
        int[][] scores = {{78, 85, 94}, {88, 74, 82}, {65, 90, 71}, {80, 79, 85}, {92, 88, 95}, {70, 62, 78}};
        int[] totals = Arrays.stream(scores).mapToInt(row -> Arrays.stream(row).sum()).toArray();
        List<Integer> order = IntStream.range(0, names.length).boxed()
                .sorted(Comparator.<Integer>comparingInt(i -> totals[i]).reversed().thenComparing(i -> names[i]))
                .toList();
        int rank = 0, previous = -1;
        for (int position = 0; position < order.size(); position++) {
            int i = order.get(position);
            if (totals[i] != previous) {
                rank = position + 1;
            }
            previous = totals[i];
            System.out.printf(Locale.ROOT, "%d. %s total=%d average=%.2f%n",
                    rank, names[i], totals[i], totals[i] / 3.0);
        }
    }
}
