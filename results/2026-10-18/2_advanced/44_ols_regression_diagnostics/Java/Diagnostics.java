final class Diagnostics {
    static final class Result {
        double[] standardized, studentized, cooks, dffits;
        String[] flags;
        double[][] dfbetas;
        double dw, bp, bpP, jb, jbP, skewness, kurtosis;
        int bpDegrees;
    }
    static Result compute(double[][] x, double[] y, double[] w, QrSolver.Fit fit, double sigma, int degrees,
                          Dataframe.Settings settings) {
        int n = y.length, r = fit.rank;
        Result result = new Result();
        result.standardized = new double[n];
        result.studentized = new double[n];
        result.cooks = new double[n];
        result.dffits = new double[n];
        result.flags = new String[n];
        result.dfbetas = new double[n][r];
        for (int i = 0; i < n; i++) {
            double h = fit.leverage[i], z = fit.epsilon[i] / (sigma * Math.sqrt(1 - h));
            result.standardized[i] = z;
            result.studentized[i] = z * Math.sqrt((degrees - 1) / (degrees - z * z));
            result.cooks[i] = z * z * h / (r * (1 - h));
            result.dffits[i] = result.studentized[i] * Math.sqrt(h / (1 - h));
            String flags = "";
            if (h > settings.number("LEVERAGE") * r / n)
                flags += "H";
            if (Math.abs(result.studentized[i]) > settings.number("STUDENTIZED"))
                flags += "O";
            if (result.cooks[i] > settings.number("COOK") / n)
                flags += "C";
            if (Math.abs(result.dffits[i]) > settings.number("DFFITS") * Math.sqrt((double)r / n))
                flags += "F";
            result.flags[i] = flags.isEmpty() ? "-" : flags;
            double deleted = sigma * Math.sqrt((degrees - z * z) / (degrees - 1));
            for (int k = 0; k < r; k++)
                result.dfbetas[i][k] =
                    fit.g[i][k] * fit.epsilon[i] / (1 - h) / (deleted * Math.sqrt(fit.variance[k]));
        }
        double dw = 0;
        for (int i = 1; i < n; i++) {
            double difference = fit.epsilon[i] - fit.epsilon[i - 1];
            dw += difference * difference;
        }
        result.dw = dw / fit.rss;
        double[][] accepted = new double[n][r];
        double[] squares = new double[n], ones = new double[n];
        double sum = 0;
        for (int i = 0; i < n; i++) {
            for (int k = 0; k < r; k++)
                accepted[i][k] = x[i][fit.accepted[k]];
            squares[i] = fit.epsilon[i] * fit.epsilon[i];
            sum += squares[i];
            ones[i] = 1;
        }
        QrSolver.Fit auxiliary = QrSolver.fit(accepted, squares, ones, settings.number("RANK_TOL"));
        double mean = sum / n, total = 0;
        for (double value : squares)
            total += (value - mean) * (value - mean);
        result.bp = n * (1 - auxiliary.rss / total);
        result.bpDegrees = auxiliary.rank - 1;
        result.bpP = Inference.pchi(result.bp, result.bpDegrees);
        sum = 0;
        for (double value : fit.epsilon)
            sum += value;
        mean = sum / n;
        double m2 = 0, m3 = 0, m4 = 0;
        for (double value : fit.epsilon) {
            double delta = value - mean;
            m2 += delta * delta;
            m3 += delta * delta * delta;
            m4 += delta * delta * delta * delta;
        }
        m2 /= n;
        m3 /= n;
        m4 /= n;
        result.skewness = m3 / (m2 * Math.sqrt(m2));
        result.kurtosis = m4 / (m2 * m2);
        result.jb =
            n / 6.0 * (result.skewness * result.skewness + (result.kurtosis - 3) * (result.kurtosis - 3) / 4);
        result.jbP = Inference.pchi(result.jb, 2);
        return result;
    }
}
