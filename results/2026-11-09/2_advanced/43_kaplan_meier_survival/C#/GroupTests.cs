using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class GroupTests {
    public static readonly List<string> WEIGHTS = ["logrank", "gehan_wilcoxon", "tarone_ware"];
    public sealed class Result {
        public List<string> groups;
        public int[] events;
        public double[] observed, expected;
        public double[][] covariance;
        public double chi2, pvalue;
        public int degrees;
        public Result(List<string> groups) {
            this.groups = groups;
            int n = groups.Count;
            events = new int[n];
            observed = new double[n];
            expected = new double[n];
            covariance = Numerics.Zeros(n);
        }
    }
    public static void Finish(Result result) {
        int n = result.groups.Count - 1;
        double[][] matrix = Numerics.Zeros(n);
        double[] u = new double[n];
        for (int i = 0; i < n; i++) {
            u[i] = result.observed[i] - result.expected[i];
            for (int j = 0; j < n; j++)
                matrix[i][j] = result.covariance[i][j];
        }
        double[] solved = Numerics.Solve(matrix, u);
        result.chi2 = 0;
        for (int i = 0; i < n; i++)
            result.chi2 += u[i] * solved[i];
        result.degrees = n;
        result.pvalue = Numerics.Pvalue(result.chi2, n);
    }
    public static Result Weighted(List<Dataset.Subject> subjects, List<string> groups, int weight,
                                  int totalSubjects) {
        Result result = new Result(groups);
        foreach (int time in Estimators.EventTimes(subjects, false)) {
            int n = 0, d = 0;
            int[] risk = new int[groups.Count], events = new int[groups.Count];
            foreach (Dataset.Subject s in subjects) {
                int g = groups.IndexOf(s.group);
                if (s.time >= time) {
                    risk[g]++;
                    n++;
                }
                if (s.time == time && s.eventFlag == 1) {
                    events[g]++;
                    d++;
                }
            }
            double nu = weight == 0 ? 1 : (double)n / totalSubjects;
            if (weight == 2)
                nu = Math.Sqrt(nu);
            for (int h = 0; h < groups.Count; h++) {
                result.events[h] += events[h];
                result.observed[h] += nu * events[h];
                result.expected[h] += nu * ((double)(d * risk[h]) / n);
                if (n >= 2)
                    for (int l = 0; l < groups.Count; l++) {
                        int m = h == l ? risk[h] * (n - risk[h]) : -(risk[h] * risk[l]);
                        result.covariance[h][l] += nu * nu * ((double)(d * (n - d)) / ((n - 1) * n * n)) * m;
                    }
            }
        }
        Finish(result);
        return result;
    }
    public static Result Combined(List<Result> strata, List<string> groups) {
        Result result = new Result(groups);
        foreach (Result s in strata)
            for (int h = 0; h < groups.Count; h++) {
                result.events[h] += s.events[h];
                result.observed[h] += s.observed[h];
                result.expected[h] += s.expected[h];
                for (int l = 0; l < groups.Count; l++)
                    result.covariance[h][l] += s.covariance[h][l];
            }
        Finish(result);
        return result;
    }
}
