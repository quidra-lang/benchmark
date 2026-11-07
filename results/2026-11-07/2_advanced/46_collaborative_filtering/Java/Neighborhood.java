import java.util.*;

final class Neighborhood {
    static final class Model {
        double[][] users, items;
        int[][] userCommon, common, differences;
        int userPairs, userUsable, itemPairs, itemUsable, slopePairs;
    }
    static Model compute(Ratings.Data d) {
        int users = d.users.size(), items = d.items.size();
        int shrinkage = d.settings.integer("SHRINKAGE");
        double threshold = d.settings.number("MIN_SIMILARITY");
        Model m = new Model();
        m.users = new double[users][users];
        m.items = new double[items][items];
        for (double[] row : m.users)
            Arrays.fill(row, Double.NaN);
        for (double[] row : m.items)
            Arrays.fill(row, Double.NaN);
        m.userCommon = new int[users][users];
        m.common = new int[items][items];
        m.differences = new int[items][items];
        for (int u = 0; u < users; u++)
            for (int v = u + 1; v < users; v++) {
                long n = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
                for (int i = 0; i < items; i++)
                    if (d.ratings[u][i] > 0 && d.ratings[v][i] > 0) {
                        long x = d.ratings[u][i], y = d.ratings[v][i];
                        n++;
                        sx += x;
                        sy += y;
                        sxx += x * x;
                        syy += y * y;
                        sxy += x * y;
                    }
                m.userCommon[u][v] = m.userCommon[v][u] = (int)n;
                if (n < 2)
                    continue;
                long num = n * sxy - sx * sy, dx = n * sxx - sx * sx, dy = n * syy - sy * sy;
                if (dx == 0 || dy == 0)
                    continue;
                long a = (num * n) * (num * n), b = dx * dy * (n + shrinkage) * (n + shrinkage);
                double sim = Long.signum(num) * Math.sqrt((double)a / b);
                m.users[u][v] = m.users[v][u] = sim;
                m.userPairs++;
                if (sim > threshold)
                    m.userUsable++;
            }
        for (int i = 0; i < items; i++)
            for (int j = i + 1; j < items; j++) {
                int n = 0, difference = 0;
                double num = 0, ni = 0, nj = 0;
                for (int u = 0; u < users; u++)
                    if (d.ratings[u][i] > 0 && d.ratings[u][j] > 0) {
                        n++;
                        difference += d.ratings[u][i] - d.ratings[u][j];
                        double x = d.ratings[u][i] - d.userMeans[u], y = d.ratings[u][j] - d.userMeans[u];
                        num += x * y;
                        ni += x * x;
                        nj += y * y;
                    }
                m.common[i][j] = m.common[j][i] = n;
                m.differences[i][j] = difference;
                m.differences[j][i] = -difference;
                if (n > 0)
                    m.slopePairs++;
                if (n < 2 || ni == 0 || nj == 0)
                    continue;
                double sim = num / Math.sqrt(ni * nj) * n / (n + shrinkage);
                m.items[i][j] = m.items[j][i] = sim;
                m.itemPairs++;
                if (sim > threshold)
                    m.itemUsable++;
            }
        return m;
    }
    static List<Integer> select(double[] similarities, List<Integer> candidates, int limit) {
        List<Integer> result = new ArrayList<>(candidates);
        result.sort((a, b) -> {
            int comparison = Double.compare(similarities[b], similarities[a]);
            return comparison != 0 ? comparison : Integer.compare(a, b);
        });
        return new ArrayList<>(result.subList(0, Math.min(limit, result.size())));
    }
}
