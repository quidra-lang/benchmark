import java.util.*;

final class GroupTests {
    static final List<String> WEIGHTS = List.of("logrank", "gehan_wilcoxon", "tarone_ware");
    static final class Result {
        List<String> groups;
        int[] events;
        double[] observed, expected;
        double[][] covariance;
        double chi2, pvalue;
        int degrees;
        Result(List<String> groups) {
            this.groups = groups;
            int n = groups.size();
            events = new int[n];
            observed = new double[n];
            expected = new double[n];
            covariance = Numerics.zeros(n);
        }
    }
    static void finish(Result result) {
        int n = result.groups.size() - 1;
        double[][] matrix = Numerics.zeros(n);
        double[] u = new double[n];
        for (int i = 0; i < n; i++) {
            u[i] = result.observed[i] - result.expected[i];
            for (int j = 0; j < n; j++)
                matrix[i][j] = result.covariance[i][j];
        }
        double[] solved = Numerics.solve(matrix, u);
        result.chi2 = 0;
        for (int i = 0; i < n; i++)
            result.chi2 += u[i] * solved[i];
        result.degrees = n;
        result.pvalue = Numerics.pvalue(result.chi2, n);
    }
    static Result weighted(List<Dataset.Subject> subjects, List<String> groups, int weight,
                           int totalSubjects) {
        Result result = new Result(groups);
        for (int time : Estimators.eventTimes(subjects, false)) {
            int n = 0, d = 0;
            int[] risk = new int[groups.size()], events = new int[groups.size()];
            for (Dataset.Subject s : subjects) {
                int g = groups.indexOf(s.group());
                if (s.time() >= time) {
                    risk[g]++;
                    n++;
                }
                if (s.time() == time && s.event() == 1) {
                    events[g]++;
                    d++;
                }
            }
            double nu = weight == 0 ? 1 : (double)n / totalSubjects;
            if (weight == 2)
                nu = Math.sqrt(nu);
            for (int h = 0; h < groups.size(); h++) {
                result.events[h] += events[h];
                result.observed[h] += nu * events[h];
                result.expected[h] += nu * ((double)(d * risk[h]) / n);
                if (n >= 2)
                    for (int l = 0; l < groups.size(); l++) {
                        int m = h == l ? risk[h] * (n - risk[h]) : -(risk[h] * risk[l]);
                        result.covariance[h][l] += nu * nu * ((double)(d * (n - d)) / ((n - 1) * n * n)) * m;
                    }
            }
        }
        finish(result);
        return result;
    }
    static Result combined(List<Result> strata, List<String> groups) {
        Result result = new Result(groups);
        for (Result s : strata)
            for (int h = 0; h < groups.size(); h++) {
                result.events[h] += s.events[h];
                result.observed[h] += s.observed[h];
                result.expected[h] += s.expected[h];
                for (int l = 0; l < groups.size(); l++)
                    result.covariance[h][l] += s.covariance[h][l];
            }
        finish(result);
        return result;
    }
}
