using System;
using System.Collections.Generic;

sealed class EloRun {
    public readonly double[] Ratings;
    public readonly List<double> Expected = new(), Changes = new();
    public readonly List<double[]> RoundRatings = new();
    public EloRun(int count, double initial) { Ratings = new double[count]; Array.Fill(Ratings, initial); }
}
static class Elo {
    public static double Expected(double home, double away, double advantage) => 1 / (1 + Math.Pow(10, (away - home - advantage) / 400));
    static double Multiplier(Match match, double home, double away, double advantage) {
        int goals = Math.Abs(match.Margin);
        if (goals == 0) return 1;
        double difference = match.Margin > 0 ? home + advantage - away : away - home - advantage;
        return Math.Log(goals + 1) * 2.2 / (0.001 * difference + 2.2);
    }
    public static EloRun Run(int count, List<Match> matches, double k, double advantage, double initial) {
        EloRun run = new(count, initial);
        for (int i = 0; i < matches.Count; i++) {
            Match match = matches[i];
            double home = run.Ratings[match.Home], away = run.Ratings[match.Away];
            double expected = Expected(home, away, advantage), weight = Multiplier(match, home, away, advantage), change = k * weight * (match.Result - expected);
            run.Ratings[match.Home] = home + change; run.Ratings[match.Away] = away - change; run.Expected.Add(expected); run.Changes.Add(change);
            if (i + 1 == matches.Count || matches[i + 1].Round != match.Round) run.RoundRatings.Add((double[])run.Ratings.Clone());
        }
        return run;
    }
}
