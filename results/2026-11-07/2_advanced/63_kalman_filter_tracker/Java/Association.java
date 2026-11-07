import java.util.*;
final class Association {
    record Pair(int row, int column) {}
    static List<Pair> minimum(double[][] costs) {
        List<Pair> result = new ArrayList<>();
        if (costs.length == 0 || costs[0].length == 0)
            return result;
        boolean transpose = costs.length > costs[0].length;
        double[][] a = transpose ? Matrix.transpose(costs) : costs;
        int rows = a.length, columns = a[0].length;
        double[] u = new double[rows + 1], v = new double[columns + 1];
        int[] matched = new int[columns + 1], previous = new int[columns + 1];
        for (int row = 1; row <= rows; row++) {
            matched[0] = row;
            int column = 0;
            double[] distances = new double[columns + 1];
            Arrays.fill(distances, Double.POSITIVE_INFINITY);
            boolean[] used = new boolean[columns + 1];
            do {
                used[column] = true;
                int current = matched[column], following = 0;
                double delta = Double.POSITIVE_INFINITY;
                for (int candidate = 1; candidate <= columns; candidate++)
                    if (!used[candidate]) {
                        double reduced = a[current - 1][candidate - 1] - u[current] - v[candidate];
                        if (reduced < distances[candidate]) {
                            distances[candidate] = reduced;
                            previous[candidate] = column;
                        }
                        if (distances[candidate] < delta) {
                            delta = distances[candidate];
                            following = candidate;
                        }
                    }
                for (int candidate = 0; candidate <= columns; candidate++)
                    if (used[candidate]) {
                        u[matched[candidate]] += delta;
                        v[candidate] -= delta;
                    } else
                        distances[candidate] -= delta;
                column = following;
            } while (matched[column] != 0);
            while (column != 0) {
                int following = previous[column];
                matched[column] = matched[following];
                column = following;
            }
        }
        for (int c = 1; c <= columns; c++)
            if (matched[c] != 0)
                result.add(transpose ? new Pair(c - 1, matched[c] - 1) : new Pair(matched[c] - 1, c - 1));
        result.sort(Comparator.comparingInt(Pair::row).thenComparingInt(Pair::column));
        return result;
    }
    static List<Pair> optimal(double[][] costs, boolean[][] usable) {
        if (costs.length == 0 || costs[0].length == 0)
            return new ArrayList<>();
        double largest = 1;
        for (int r = 0; r < costs.length; r++)
            for (int c = 0; c < costs[0].length; c++)
                if (usable[r][c])
                    largest = Math.max(largest, costs[r][c]);
        double penalty = (Math.min(costs.length, costs[0].length) + 1) * (largest + 1);
        double[][] a = new double[costs.length][costs[0].length];
        for (int r = 0; r < a.length; r++)
            for (int c = 0; c < a[0].length; c++)
                a[r][c] = usable[r][c] ? costs[r][c] : penalty;
        List<Pair> result = new ArrayList<>();
        for (Pair p : minimum(a))
            if (usable[p.row()][p.column()])
                result.add(p);
        return result;
    }
}
