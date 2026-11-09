using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Cox {
    public record Risk(int events, double s0, double[] s1) {
    }
    public sealed class Evaluation {
        public double likelihood;
        public double[] score, theta, risks;
        public double[][] information;
        public SortedDictionary<int, Risk> times = new();
        public Evaluation(int n, int p) {
            score = new double[p];
            theta = new double[n];
            risks = new double[n];
            information = Numerics.Zeros(p);
        }
    }
    public static Evaluation Evaluate(List<Dataset.Subject> subjects, double[][] x, double[] beta) {
        int n = subjects.Count, p = beta.Length;
        Evaluation result = new Evaluation(n, p);
        for (int i = 0; i < n; i++) {
            for (int c = 0; c < p; c++)
                result.theta[i] += beta[c] * x[i][c];
            result.risks[i] = Math.Exp(result.theta[i]);
        }
        List<int> order = new();
        for (int i = 0; i < n; i++)
            order.Add(i);
        order.Sort((a, b) => subjects[a].time != subjects[b].time
                                 ? subjects[b].time.CompareTo(subjects[a].time)
                                 : subjects[a].id.CompareTo(subjects[b].id));
        double s0 = 0;
        double[] s1 = new double[p];
        double[][] s2 = Numerics.Zeros(p);
        int position = 0;
        while (position < n) {
            int end = position, time = subjects[order[position]].time;
            while (end < n && subjects[order[end]].time == time)
                end++;
            for (int j = position; j < end; j++) {
                int i = order[j];
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
                int i = order[j];
                if (subjects[i].eventFlag == 1) {
                    events++;
                    theta += result.theta[i];
                    for (int c = 0; c < p; c++)
                        eventX[c] += x[i][c];
                }
            }
            if (events > 0) {
                result.likelihood += theta - events * Math.Log(s0);
                for (int c = 0; c < p; c++) {
                    result.score[c] += eventX[c] - events * s1[c] / s0;
                    for (int d = 0; d < p; d++)
                        result.information[c][d] += events * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0));
                }
                result.times[time] = new Risk(events, s0, s1.ToArray());
            }
            position = end;
        }
        return result;
    }
    public record Iteration(int number, double likelihood, double[] beta) {
    }
    public sealed class Fit {
        public double[] beta;
        public Evaluation initial, finalEvaluation;
        public List<Iteration> iterations = new();
    }
    public static Fit Fit(List<Dataset.Subject> subjects, double[][] x) {
        Fit result = new Fit();
        result.beta = new double[x[0].Length];
        result.initial = Evaluate(subjects, x, result.beta);
        for (int iteration = 1; iteration <= 25; iteration++) {
            Evaluation before = iteration == 1 ? result.initial : Evaluate(subjects, x, result.beta);
            double[] delta = Numerics.Solve(before.information, before.score);
            for (int c = 0; c < result.beta.Length; c++)
                result.beta[c] += delta[c];
            result.iterations.Add(new Iteration(iteration, before.likelihood, result.beta.ToArray()));
        }
        result.finalEvaluation = Evaluate(subjects, x, result.beta);
        return result;
    }
}
