import java.util.*;

final class Cox {
    record Risk(int events, double s0, double[] s1) {}
    static final class Evaluation {
        double likelihood;
        double[] score, theta, risks;
        double[][] information;
        SortedMap<Integer, Risk> times = new TreeMap<>();
        Evaluation(int n, int p) {
            score = new double[p];
            theta = new double[n];
            risks = new double[n];
            information = Numerics.zeros(p);
        }
    }
    static Evaluation evaluate(List<Dataset.Subject> subjects, double[][] x, double[] beta) {
        int n = subjects.size(), p = beta.length;
        Evaluation result = new Evaluation(n, p);
        for (int i = 0; i < n; i++) {
            for (int c = 0; c < p; c++)
                result.theta[i] += beta[c] * x[i][c];
            result.risks[i] = Math.exp(result.theta[i]);
        }
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < n; i++)
            order.add(i);
        order.sort((a, b)
                       -> subjects.get(a).time() != subjects.get(b).time()
                              ? Integer.compare(subjects.get(b).time(), subjects.get(a).time())
                              : Integer.compare(subjects.get(a).id(), subjects.get(b).id()));
        double s0 = 0;
        double[] s1 = new double[p];
        double[][] s2 = Numerics.zeros(p);
        int position = 0;
        while (position < n) {
            int end = position, time = subjects.get(order.get(position)).time();
            while (end < n && subjects.get(order.get(end)).time() == time)
                end++;
            for (int j = position; j < end; j++) {
                int i = order.get(j);
                double r = result.risks[i];
                s0 += r;
                for (int c = 0; c < p; c++) {
                    s1[c] += r * x[i][c];
                    for (int d = 0; d < p; d++)
                        s2[c][d] += r * x[i][c] * x[i][d];
                }
            }
            int events = 0;
            double theta = 0;
            double[] eventX = new double[p];
            for (int j = position; j < end; j++) {
                int i = order.get(j);
                if (subjects.get(i).event() == 1) {
                    events++;
                    theta += result.theta[i];
                    for (int c = 0; c < p; c++)
                        eventX[c] += x[i][c];
                }
            }
            if (events > 0) {
                result.likelihood += theta - events * Math.log(s0);
                for (int c = 0; c < p; c++) {
                    result.score[c] += eventX[c] - events * s1[c] / s0;
                    for (int d = 0; d < p; d++)
                        result.information[c][d] += events * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0));
                }
                result.times.put(time, new Risk(events, s0, s1.clone()));
            }
            position = end;
        }
        return result;
    }
    record Iteration(int number, double likelihood, double[] beta) {}
    static final class Fit {
        double[] beta;
        Evaluation initial, finalEvaluation;
        List<Iteration> iterations = new ArrayList<>();
    }
    static Fit fit(List<Dataset.Subject> subjects, double[][] x) {
        Fit result = new Fit();
        result.beta = new double[x[0].length];
        result.initial = evaluate(subjects, x, result.beta);
        for (int iteration = 1; iteration <= 25; iteration++) {
            Evaluation before = iteration == 1 ? result.initial : evaluate(subjects, x, result.beta);
            double[] delta = Numerics.solve(before.information, before.score);
            for (int c = 0; c < result.beta.length; c++)
                result.beta[c] += delta[c];
            result.iterations.add(new Iteration(iteration, before.likelihood, result.beta.clone()));
        }
        result.finalEvaluation = evaluate(subjects, x, result.beta);
        return result;
    }
}
