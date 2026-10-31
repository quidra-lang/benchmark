import java.util.*;

final class Factorization {
    static final class Generator {
        long state;
        Generator(int seed) {
            state = seed;
        }
        long draw() {
            state = 48271 * state % 2147483647;
            return state;
        }
        double factor() {
            return ((draw() % 2001) - 1000) / 10000.0;
        }
    }
    record Log(String method, int epoch, double rmse) {}
    static final class Model {
        double mean;
        double[][] users, items;
        double[] userBias, itemBias;
        List<Log> log = new ArrayList<>();
        double predict(int u, int i) {
            return ((mean + userBias[u]) + itemBias[i]) + dot(users[u], items[i]);
        }
    }
    static double dot(double[] a, double[] b) {
        double sum = 0;
        for (int f = 0; f < a.length; f++)
            sum += a[f] * b[f];
        return sum;
    }
    static double rmse(Ratings.Data data, Model model) {
        double sum = 0;
        for (Ratings.Rating row : data.training) {
            double e = row.rating() - model.predict(row.user(), row.item());
            sum += e * e;
        }
        return Math.sqrt(sum / data.training.size());
    }
    static Model svd(Ratings.Data d) {
        int factors = d.settings.integer("FACTORS");
        Generator random = new Generator(d.settings.integer("SEED"));
        Model m = new Model();
        m.mean = d.mean;
        m.users = new double[d.users.size()][factors];
        m.items = new double[d.items.size()][factors];
        m.userBias = new double[d.users.size()];
        m.itemBias = new double[d.items.size()];
        for (double[] row : m.users)
            for (int f = 0; f < factors; f++)
                row[f] = random.factor();
        for (double[] row : m.items)
            for (int f = 0; f < factors; f++)
                row[f] = random.factor();
        int[] order = new int[d.training.size()];
        for (int t = 0; t < order.length; t++)
            order[t] = t;
        double rate = d.settings.number("LEARNING_RATE"), regularization =
                                                              d.settings.number("REGULARIZATION");
        for (int epoch = 1; epoch <= d.settings.integer("EPOCHS"); epoch++) {
            for (int t = order.length - 1; t >= 1; t--) {
                int other = (int)(random.draw() % (t + 1)), temporary = order[t];
                order[t] = order[other];
                order[other] = temporary;
            }
            for (int position : order) {
                Ratings.Rating row = d.training.get(position);
                int u = row.user(), i = row.item();
                double e = row.rating() - m.predict(u, i);
                m.userBias[u] += rate * (e - regularization * m.userBias[u]);
                m.itemBias[i] += rate * (e - regularization * m.itemBias[i]);
                for (int f = 0; f < factors; f++) {
                    double a = m.users[u][f], b = m.items[i][f];
                    m.users[u][f] = a + rate * (e * b - regularization * a);
                    m.items[i][f] = b + rate * (e * a - regularization * b);
                }
            }
            m.log.add(new Log("SVD", epoch, rmse(d, m)));
        }
        return m;
    }
    static double[] solve(double[][] a, double[] w) {
        int n = w.length;
        double[][] l = new double[n][n];
        for (int row = 0; row < n; row++)
            for (int col = 0; col <= row; col++) {
                double sum = 0;
                for (int t = 0; t < col; t++)
                    sum += l[row][t] * l[col][t];
                double s = a[row][col] - sum;
                l[row][col] = row == col ? Math.sqrt(s) : s / l[col][col];
            }
        double[] z = new double[n], x = new double[n];
        for (int row = 0; row < n; row++) {
            double sum = 0;
            for (int t = 0; t < row; t++)
                sum += l[row][t] * z[t];
            z[row] = (w[row] - sum) / l[row][row];
        }
        for (int row = n - 1; row >= 0; row--) {
            double sum = 0;
            for (int t = row + 1; t < n; t++)
                sum += l[t][row] * x[t];
            x[row] = (z[row] - sum) / l[row][row];
        }
        return x;
    }
    static double[] vector(List<Integer> indices, double[][] vectors, double[] residuals, int factors,
                           double regularization) {
        double[][] a = new double[factors][factors];
        double[] w = new double[factors];
        for (int index : indices)
            for (int row = 0; row < factors; row++) {
                w[row] += residuals[index] * vectors[index][row];
                for (int col = 0; col < factors; col++)
                    a[row][col] += vectors[index][row] * vectors[index][col];
            }
        for (int row = 0; row < factors; row++)
            a[row][row] += regularization * indices.size();
        return solve(a, w);
    }
    static Model als(Ratings.Data d, double[] userBias, double[] itemBias) {
        int factors = d.settings.integer("FACTORS");
        Generator random = new Generator(d.settings.integer("SEED"));
        Model m = new Model();
        m.mean = d.mean;
        m.userBias = userBias;
        m.itemBias = itemBias;
        m.users = new double[d.users.size()][factors];
        m.items = new double[d.items.size()][factors];
        for (double[] row : m.items)
            for (int f = 0; f < factors; f++)
                row[f] = random.factor();
        double[][] residuals = new double[d.users.size()][d.items.size()];
        for (Ratings.Rating row : d.training)
            residuals[row.user()][row.item()] =
                row.rating() - ((d.mean + userBias[row.user()]) + itemBias[row.item()]);
        for (int iteration = 1; iteration <= d.settings.integer("ALS_ITERATIONS"); iteration++) {
            for (int u = 0; u < d.users.size(); u++)
                m.users[u] =
                    vector(d.byUser.get(u), m.items, residuals[u], factors, d.settings.number("ALS_REG"));
            for (int i = 0; i < d.items.size(); i++) {
                double[] column = new double[d.users.size()];
                for (int u = 0; u < column.length; u++)
                    column[u] = residuals[u][i];
                m.items[i] = vector(d.byItem.get(i), m.users, column, factors, d.settings.number("ALS_REG"));
            }
            m.log.add(new Log("ALS", iteration, rmse(d, m)));
        }
        return m;
    }
}
