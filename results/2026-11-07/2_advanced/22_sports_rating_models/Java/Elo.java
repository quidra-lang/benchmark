import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

final class EloRun {
    final double[] ratings;
    final List<Double> expected = new ArrayList<>(), changes = new ArrayList<>();
    final List<double[]> roundRatings = new ArrayList<>();
    EloRun(int count, double initial) { ratings = new double[count]; Arrays.fill(ratings, initial); }
}
final class Elo {
    static double expected(double home, double away, double advantage) { return 1 / (1 + Math.pow(10, (away - home - advantage) / 400)); }
    static double multiplier(Match match, double home, double away, double advantage) {
        int goals = Math.abs(match.margin()); if (goals == 0) return 1;
        double difference = match.margin() > 0 ? home + advantage - away : away - home - advantage;
        return Math.log(goals + 1) * 2.2 / (0.001 * difference + 2.2);
    }
    static EloRun run(int count, List<Match> matches, double k, double advantage, double initial) {
        EloRun run = new EloRun(count, initial);
        for (int i = 0; i < matches.size(); i++) {
            Match match = matches.get(i); double home = run.ratings[match.home()], away = run.ratings[match.away()];
            double expected = expected(home, away, advantage), weight = multiplier(match, home, away, advantage), change = k * weight * (match.result() - expected);
            run.ratings[match.home()] = home + change; run.ratings[match.away()] = away - change; run.expected.add(expected); run.changes.add(change);
            if (i + 1 == matches.size() || matches.get(i + 1).round() != match.round()) run.roundRatings.add(run.ratings.clone());
        }
        return run;
    }
}
