import java.util.Arrays;
import java.util.List;

record BradleyTerry(double[] strengths, double homeFactor) {}
record OffenseDefense(double[] offense, double[] defense, double[] ratings) {}
final class IterativeModels {
    static BradleyTerry bradleyTerry(int count, List<Match> matches, long iterations) {
        int[] winsTwice = new int[count]; int homeWinsTwice = 0;
        for (Match match : matches) { winsTwice[match.home()] += match.resultTwice(); winsTwice[match.away()] += 2 - match.resultTwice(); homeWinsTwice += match.resultTwice(); }
        double[] strengths = new double[count]; Arrays.fill(strengths, 1); double theta = 1;
        for (long iteration = 0; iteration < iterations; iteration++) {
            double[] zeta = new double[count];
            for (Match match : matches) { double q = theta * strengths[match.home()] + strengths[match.away()]; zeta[match.home()] += theta / q; zeta[match.away()] += 1 / q; }
            for (int i = 0; i < count; i++) strengths[i] = winsTwice[i] / 2.0 / zeta[i];
            double total = 0; for (double strength : strengths) total += strength;
            for (int i = 0; i < count; i++) strengths[i] = strengths[i] * count / total;
            double denominator = 0; for (Match match : matches) { double home = strengths[match.home()]; denominator += home / (theta * home + strengths[match.away()]); }
            theta = homeWinsTwice / 2.0 / denominator;
        }
        return new BradleyTerry(strengths, theta);
    }
    static OffenseDefense offenseDefense(int count, List<Match> matches, long iterations) {
        int[][] points = new int[count][count]; for (Match match : matches) { points[match.home()][match.away()] += match.awayScore(); points[match.away()][match.home()] += match.homeScore(); }
        double[] offense = new double[count], defense = new double[count]; Arrays.fill(defense, 1);
        for (long iteration = 0; iteration < iterations; iteration++) {
            for (int j = 0; j < count; j++) { double total = 0; for (int i = 0; i < count; i++) total += points[i][j] / defense[i]; offense[j] = total; }
            for (int i = 0; i < count; i++) { double total = 0; for (int j = 0; j < count; j++) total += points[i][j] / offense[j]; defense[i] = total; }
        }
        double[] ratings = new double[count]; for (int i = 0; i < count; i++) ratings[i] = offense[i] / defense[i];
        return new OffenseDefense(offense, defense, ratings);
    }
}
