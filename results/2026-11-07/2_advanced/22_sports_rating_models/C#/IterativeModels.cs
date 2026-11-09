using System;
using System.Collections.Generic;
using System.Linq;

sealed record BradleyTerry(double[] Strengths, double HomeFactor);
sealed record OffenseDefense(double[] Offense, double[] Defense, double[] Ratings);
static class IterativeModels {
    public static BradleyTerry FitBradleyTerry(int count, List<Match> matches, long iterations) {
        int[] winsTwice = new int[count];
        int homeWinsTwice = 0;
        foreach (Match match in matches) { winsTwice[match.Home] += match.ResultTwice; winsTwice[match.Away] += 2 - match.ResultTwice; homeWinsTwice += match.ResultTwice; }
        double[] strengths = new double[count]; Array.Fill(strengths, 1);
        double theta = 1;
        for (long iteration = 0; iteration < iterations; iteration++) {
            double[] zeta = new double[count];
            foreach (Match match in matches) {
                double q = theta * strengths[match.Home] + strengths[match.Away];
                zeta[match.Home] += theta / q; zeta[match.Away] += 1 / q;
            }
            for (int i = 0; i < count; i++) strengths[i] = winsTwice[i] / 2.0 / zeta[i];
            double total = 0;
            foreach (double strength in strengths) total += strength;
            for (int i = 0; i < count; i++) strengths[i] = strengths[i] * count / total;
            double denominator = 0;
            foreach (Match match in matches) { double home = strengths[match.Home]; denominator += home / (theta * home + strengths[match.Away]); }
            theta = homeWinsTwice / 2.0 / denominator;
        }
        return new BradleyTerry(strengths, theta);
    }
    public static OffenseDefense FitOffenseDefense(int count, List<Match> matches, long iterations) {
        int[][] points = Enumerable.Range(0, count).Select(_ => new int[count]).ToArray();
        foreach (Match match in matches) { points[match.Home][match.Away] += match.AwayScore; points[match.Away][match.Home] += match.HomeScore; }
        double[] offense = new double[count], defense = new double[count]; Array.Fill(defense, 1);
        for (long iteration = 0; iteration < iterations; iteration++) {
            for (int j = 0; j < count; j++) { double total = 0; for (int i = 0; i < count; i++) total += points[i][j] / defense[i]; offense[j] = total; }
            for (int i = 0; i < count; i++) { double total = 0; for (int j = 0; j < count; j++) total += points[i][j] / offense[j]; defense[i] = total; }
        }
        double[] ratings = new double[count];
        for (int i = 0; i < count; i++) ratings[i] = offense[i] / defense[i];
        return new OffenseDefense(offense, defense, ratings);
    }
}
