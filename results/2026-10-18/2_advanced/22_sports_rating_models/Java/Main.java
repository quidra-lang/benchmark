import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class Appearance {
    final Match match;
    final boolean home;
    final int opponent, scored, conceded;
    final String letter;
    Appearance(Match match, int team) {
        this.match = match; home = match.home() == team; opponent = home ? match.away() : match.home(); scored = home ? match.homeScore() : match.awayScore(); conceded = home ? match.awayScore() : match.homeScore(); letter = scored > conceded ? "W" : scored == conceded ? "D" : "L";
    }
}
final class TeamRecord {
    int played, won, drawn, lost, scored, conceded;
    long points;
    void add(int scored, int conceded, Settings settings) {
        played++; this.scored += scored; this.conceded += conceded;
        if (scored > conceded) { won++; points += settings.winPoints; } else if (scored == conceded) { drawn++; points += settings.drawPoints; } else lost++;
    }
    int difference() { return scored - conceded; }
    Fraction percentage() { return new Fraction(2 * won + drawn, 2 * played); }
}
final class Standings {
    final TeamRecord[] records;
    final long[] headPoints;
    final int[] headDifference, positions;
    final List<Integer> order;
    Standings(List<Team> teams, List<Match> matches, Settings settings) {
        int count = teams.size(); records = Main.records(count, matches, settings); headPoints = new long[count]; headDifference = new int[count]; positions = new int[count];
        for (Match match : matches) if (records[match.home()].points == records[match.away()].points) {
            int home = match.home(), away = match.away();
            if (match.margin() > 0) headPoints[home] += settings.winPoints; else if (match.margin() < 0) headPoints[away] += settings.winPoints; else { headPoints[home] += settings.drawPoints; headPoints[away] += settings.drawPoints; }
            headDifference[home] += match.margin(); headDifference[away] -= match.margin();
        }
        order = Main.indices(count);
        order.sort((a, b) -> {
            int comparison = Long.compare(records[b].points, records[a].points);
            if (comparison == 0) comparison = Long.compare(headPoints[b], headPoints[a]);
            if (comparison == 0) comparison = Integer.compare(headDifference[b], headDifference[a]);
            if (comparison == 0) comparison = Integer.compare(records[b].difference(), records[a].difference());
            if (comparison == 0) comparison = Integer.compare(records[b].scored, records[a].scored);
            return comparison == 0 ? teams.get(a).code().compareTo(teams.get(b).code()) : comparison;
        });
        for (int i = 0; i < count; i++) positions[order.get(i)] = i + 1;
    }
    List<List<Integer>> tiedGroups() {
        List<List<Integer>> groups = new ArrayList<>();
        for (int team : order) { if (groups.isEmpty() || records[groups.getLast().getFirst()].points != records[team].points) groups.add(new ArrayList<>()); groups.getLast().add(team); }
        return groups.stream().filter(group -> group.size() > 1).toList();
    }
}
record Streak(int length, int first, int last) {}
final class ModelFit {
    final EloRun elo;
    final double[] colley, massey, strengths, offense, defense, od;
    final double homeAdvantage, homeFactor;
    final Fraction[] percentages;
    ModelFit(int count, List<Match> matches, Settings settings) {
        elo = Elo.run(count, matches, settings.eloK, settings.eloHome, settings.eloInitial); colley = LinearModels.colley(count, matches);
        Massey fitted = LinearModels.massey(count, matches); massey = fitted.ratings(); homeAdvantage = fitted.homeAdvantage();
        BradleyTerry bt = IterativeModels.bradleyTerry(count, matches, settings.btIterations); strengths = bt.strengths(); homeFactor = bt.homeFactor();
        OffenseDefense result = IterativeModels.offenseDefense(count, matches, settings.odIterations); offense = result.offense(); defense = result.defense(); od = result.ratings();
        TeamRecord[] records = Main.records(count, matches, settings); percentages = new Fraction[count]; for (int i = 0; i < count; i++) percentages[i] = records[i].percentage();
    }
    double feature(String model, Match match) {
        int home = match.home(), away = match.away();
        return switch (model) { case "colley" -> colley[home] - colley[away]; case "massey" -> massey[home] - massey[away]; case "od" -> Math.log(od[home]) - Math.log(od[away]); default -> percentages[home].real() - percentages[away].real(); };
    }
    double btProbability(Match match) { double home = homeFactor * strengths[match.home()]; return home / (home + strengths[match.away()]); }
    double margin(Match match) { return massey[match.home()] - massey[match.away()] + homeAdvantage; }
}
final class Prediction {
    final Match match;
    final double[] probabilities, losses = new double[8], briers = new double[8];
    final int[] scoresTwice = new int[8];
    final double marginError;
    Prediction(Match match, double[] probabilities, double marginError) {
        this.match = match; this.probabilities = probabilities; this.marginError = marginError;
        for (int i = 0; i < 8; i++) { losses[i] = Evaluation.logLoss(probabilities[i], match.resultTwice()); briers[i] = Evaluation.brier(probabilities[i], match.resultTwice()); scoresTwice[i] = Evaluation.correctnessTwice(probabilities[i], match.resultTwice()); }
    }
}
final class ValidationRound {
    final int number;
    final List<Match> training;
    final ModelFit fit;
    final double base;
    final Map<String, Link> links = new LinkedHashMap<>();
    final List<Prediction> predictions = new ArrayList<>();
    ValidationRound(int number, int count, List<Match> matches, Settings settings) {
        this.number = number; training = Season.before(matches, number); fit = new ModelFit(count, training, settings);
        int resultsTwice = 0; for (Match match : training) resultsTwice += match.resultTwice(); base = new Fraction(resultsTwice, 2 * training.size()).real();
        for (String model : Main.LINK_MODELS) { double[] features = new double[training.size()]; for (int i = 0; i < features.length; i++) features[i] = fit.feature(model, training.get(i)); links.put(model, Evaluation.fitLink(features, training, settings.linkIterations)); }
        for (Match match : matches) if (match.round() == number) predictions.add(predict(match, settings));
    }
    Prediction predict(Match match, Settings settings) {
        double[] probabilities = new double[8]; probabilities[0] = base; probabilities[1] = Elo.expected(fit.elo.ratings[match.home()], fit.elo.ratings[match.away()], settings.eloHome);
        for (String model : Main.LINK_MODELS) { Link link = links.get(model); probabilities[Main.PREDICTION_MODELS.indexOf(model)] = Evaluation.sigma(link.alpha() + link.beta() * fit.feature(model, match)); }
        probabilities[4] = fit.btProbability(match); double ensemble = 0; for (int i = 1; i <= 6; i++) ensemble += probabilities[i]; probabilities[7] = ensemble / 6;
        return new Prediction(match, probabilities, match.margin() - fit.margin(match));
    }
}
final class ModelScores {
    final double[] losses = new double[8], briers = new double[8], skills = new double[8];
    final Fraction[] accuracies = new Fraction[8];
    final List<Integer> lossRanking, brierRanking, accuracyRanking;
    ModelScores(List<Prediction> predictions) {
        for (int i = 0; i < 8; i++) {
            double loss = 0, brier = 0; int score = 0;
            for (Prediction prediction : predictions) { loss += prediction.losses[i]; brier += prediction.briers[i]; score += prediction.scoresTwice[i]; }
            losses[i] = loss / predictions.size(); briers[i] = brier / predictions.size(); accuracies[i] = new Fraction(score, 2 * predictions.size());
        }
        for (int i = 0; i < 8; i++) skills[i] = 1 - briers[i] / briers[0];
        lossRanking = Main.indices(8); brierRanking = Main.indices(8); accuracyRanking = Main.indices(8);
        lossRanking.sort((a, b) -> { int result = Report.comparison(losses[a], 4).compareTo(Report.comparison(losses[b], 4)); return result == 0 ? Integer.compare(a, b) : result; });
        brierRanking.sort((a, b) -> { int result = Report.comparison(briers[a], 4).compareTo(Report.comparison(briers[b], 4)); return result == 0 ? Integer.compare(a, b) : result; });
        accuracyRanking.sort((a, b) -> { int result = accuracies[b].compareTo(accuracies[a]); return result == 0 ? Integer.compare(a, b) : result; });
    }
}
final class Projection {
    final Standings current;
    final double[] ratings;
    final List<Match> remaining;
    final long[] totalPoints;
    final int[] titles, tops, bottoms, ranks;
    final List<Integer> order;
    Projection(List<Team> teams, List<Match> matches, Settings settings) {
        int count = teams.size(); List<Match> currentMatches = Season.before(matches, settings.holdoutRound); current = new Standings(teams, currentMatches, settings);
        ratings = Elo.run(count, currentMatches, settings.eloK, settings.eloHome, settings.eloInitial).ratings; remaining = matches.stream().filter(match -> match.round() >= settings.holdoutRound).toList();
        totalPoints = new long[count]; titles = new int[count]; tops = new int[count]; bottoms = new int[count]; ranks = new int[count];
        double[] probabilities = new double[remaining.size()]; for (int i = 0; i < probabilities.length; i++) { Match match = remaining.get(i); probabilities[i] = Elo.expected(ratings[match.home()], ratings[match.away()], settings.eloHome); }
        long state = settings.seed;
        for (int simulation = 0; simulation < settings.simulations; simulation++) {
            long[] points = new long[count]; for (int i = 0; i < count; i++) points[i] = current.records[i].points;
            for (int i = 0; i < remaining.size(); i++) { Match match = remaining.get(i); state = 48271 * state % 2147483647; double uniform = (double) state / 2147483647; points[uniform < probabilities[i] ? match.home() : match.away()] += settings.winPoints; }
            List<Integer> simulated = ordered(points);
            for (int i = 0; i < count; i++) { int team = simulated.get(i), place = i + 1; totalPoints[team] += points[team]; if (place == 1) titles[team]++; if (place <= settings.topPositions) tops[team]++; if (place >= count - settings.bottomPositions + 1) bottoms[team]++; }
        }
        order = ordered(totalPoints); for (int i = 0; i < count; i++) ranks[order.get(i)] = i + 1;
    }
    List<Integer> ordered(long[] points) { List<Integer> order = Main.indices(points.length); order.sort((a, b) -> { int result = Long.compare(points[b], points[a]); return result == 0 ? Integer.compare(current.positions[a], current.positions[b]) : result; }); return order; }
    double opponentStrength(int team) { double total = 0; int count = 0; for (Match match : remaining) { if (match.home() == team) { total += ratings[match.away()]; count++; } else if (match.away() == team) { total += ratings[match.home()]; count++; } } return total / count; }
}
record Upset(Match match, double expected, double gain, int index) {}
record Similarity(String first, String second, Fraction tau) {}
final class LeagueAnalysis {
    final List<Team> teams;
    final List<Match> matches;
    final Settings settings;
    final int count, finalRound;
    final List<List<Appearance>> appearances = new ArrayList<>();
    final Standings finalTable;
    final ModelFit fit;
    final List<Standings> roundTables = new ArrayList<>();
    final List<Streak> wins = new ArrayList<>(), unbeaten = new ArrayList<>();
    final Fraction[] sos, sos2, rpi;
    final double[] pythag, luck;
    final Map<String, Fraction[]> comparison = new LinkedHashMap<>();
    final Map<String, int[]> ranks = new LinkedHashMap<>();
    final List<ValidationRound> rounds = new ArrayList<>();
    final List<Prediction> predictions = new ArrayList<>();
    final ModelScores scores;
    final Projection projection;
    LeagueAnalysis(SeasonData season) {
        teams = season.teams(); matches = season.matches(); settings = season.settings(); count = teams.size(); finalRound = matches.getLast().round();
        for (int i = 0; i < count; i++) { List<Appearance> items = new ArrayList<>(); for (Match match : matches) if (match.home() == i || match.away() == i) items.add(new Appearance(match, i)); appearances.add(items); wins.add(Main.longest(items, "W")); unbeaten.add(Main.longest(items, "WD")); }
        finalTable = new Standings(teams, matches, settings); fit = new ModelFit(count, matches, settings);
        for (int round = 1; round <= finalRound; round++) roundTables.add(new Standings(teams, Season.before(matches, round + 1), settings));
        sos = new Fraction[count]; sos2 = new Fraction[count]; rpi = new Fraction[count]; pythag = new double[count]; luck = new double[count];
        for (int i = 0; i < count; i++) sos[i] = opponentAverage(i, fit.percentages);
        for (int i = 0; i < count; i++) sos2[i] = opponentAverage(i, sos);
        for (int i = 0; i < count; i++) { rpi[i] = fit.percentages[i].add(sos[i].multiply(2)).add(sos2[i]).divide(4); TeamRecord record = finalTable.records[i]; pythag[i] = 1 / (1 + Math.pow((double) record.conceded / record.scored, settings.pythagoreanExponent)); luck[i] = fit.percentages[i].real() - pythag[i]; }
        Fraction[] standingValues = new Fraction[count]; for (int i = 0; i < count; i++) standingValues[i] = new Fraction(-finalTable.positions[i]); comparison.put("standings", standingValues);
        comparison.put("elo", rounded(fit.elo.ratings, 2)); comparison.put("colley", rounded(fit.colley, 4)); comparison.put("massey", rounded(fit.massey, 4)); comparison.put("bt", rounded(fit.strengths, 4)); comparison.put("od", rounded(fit.od, 2)); comparison.put("winpct", fit.percentages); comparison.put("rpi", rpi); comparison.put("pythag", rounded(pythag, 4));
        for (String model : Main.RATING_MODELS) ranks.put(model, Main.ranks(comparison.get(model)));
        for (int round = settings.holdoutRound; round <= finalRound; round++) { ValidationRound validation = new ValidationRound(round, count, matches, settings); rounds.add(validation); predictions.addAll(validation.predictions); }
        scores = new ModelScores(predictions); projection = new Projection(teams, matches, settings);
    }
    Fraction opponentAverage(int team, Fraction[] values) { Fraction total = new Fraction(0); for (Appearance appearance : appearances.get(team)) total = total.add(values[appearance.opponent]); return total.divide(appearances.get(team).size()); }
    static Fraction[] rounded(double[] values, int places) { Fraction[] result = new Fraction[values.length]; for (int i = 0; i < values.length; i++) result[i] = Report.comparison(values[i], places); return result; }
    String code(int team) { return teams.get(team).code(); }
    List<String> standingsLines() {
        List<String> lines = new ArrayList<>(List.of(Main.STANDINGS_HEADER));
        for (int team : finalTable.order) {
            TeamRecord record = finalTable.records[team]; List<Appearance> items = appearances.get(team);
            List<Appearance> home = items.stream().filter(item -> item.home).toList(), away = items.stream().filter(item -> !item.home).toList(), close = items.stream().filter(item -> Math.abs((long) item.scored - item.conceded) <= settings.closeMargin).toList();
            String form = String.join("", items.subList(Math.max(0, items.size() - settings.formLength), items.size()).stream().map(item -> item.letter).toList());
            lines.add(Main.csv(finalTable.positions[team], code(team), teams.get(team).name(), record.played, record.won, record.drawn, record.lost, record.scored, record.conceded, record.difference(), record.points, Main.recordText(home), Main.recordText(away), form, Main.currentStreak(items), Main.recordText(close), wins.get(team).length(), unbeaten.get(team).length(), fit.percentages[team], Report.fixed(sos[team]), Report.fixed(sos2[team]), Report.fixed(rpi[team]), Report.fixed(pythag[team]), Report.fixed(luck[team])));
        }
        return lines;
    }
    List<String> ratingsLines() {
        int[] totals = new int[count]; for (String model : Main.RATING_MODELS) for (int i = 0; i < count; i++) totals[i] += ranks.get(model)[i];
        List<Integer> order = Main.indices(count); order.sort(Comparator.<Integer>comparingInt(team -> totals[team]).thenComparing(this::code));
        List<String> lines = new ArrayList<>(List.of(Main.RATINGS_HEADER));
        for (int team : order) {
            int best = Integer.MAX_VALUE, worst = 0; for (String model : Main.RATING_MODELS) { best = Math.min(best, ranks.get(model)[team]); worst = Math.max(worst, ranks.get(model)[team]); }
            lines.add(Main.csv(code(team), Report.fixed(fit.elo.ratings[team], 2), ranks.get("elo")[team], Report.fixed(fit.colley[team]), ranks.get("colley")[team], Report.fixed(fit.massey[team]), ranks.get("massey")[team], Report.fixed(fit.strengths[team]), ranks.get("bt")[team], Report.fixed(fit.offense[team], 2), Report.fixed(fit.defense[team]), Report.fixed(fit.od[team], 2), ranks.get("od")[team], Report.fixed(fit.percentages[team]), ranks.get("winpct")[team], totals[team], best, worst));
        }
        return lines;
    }
    List<String> historyLines() {
        List<String> lines = new ArrayList<>(List.of(Main.HISTORY_HEADER)); double[] previous = new double[count]; Arrays.fill(previous, settings.eloInitial);
        for (int r = 0; r < roundTables.size(); r++) {
            Standings table = roundTables.get(r); double[] ratings = fit.elo.roundRatings.get(r); int[] ranks = Main.ranks(rounded(ratings, 2));
            for (int team = 0; team < count; team++) lines.add(Main.csv(r + 1, code(team), Report.fixed(ratings[team], 2), Report.fixed(ratings[team] - previous[team], 2), ranks[team], table.records[team].points, table.positions[team]));
            previous = ratings;
        }
        return lines;
    }
    List<String> summaryLines() {
        int home = 0, drawn = 0, away = 0, resultsTwice = 0;
        for (Match match : matches) { resultsTwice += match.resultTwice(); if (match.resultTwice() == 2) home++; else if (match.resultTwice() == 1) drawn++; else away++; }
        Fraction rate = new Fraction(resultsTwice, 2 * matches.size());
        return List.of("season teams " + count + " matches " + matches.size() + " rounds " + finalRound, "home won " + home + " drawn " + drawn + " lost " + away + " rate " + Report.fractionWithReal(rate), "massey_home_advantage " + Report.fixed(fit.homeAdvantage), "bt_home_factor " + Report.fixed(fit.homeFactor));
    }
    List<String> upsetLines() {
        List<Upset> candidates = new ArrayList<>();
        for (int i = 0; i < matches.size(); i++) { Match match = matches.get(i); if (match.margin() != 0) candidates.add(new Upset(match, match.margin() > 0 ? fit.elo.expected.get(i) : 1 - fit.elo.expected.get(i), Math.abs(fit.elo.changes.get(i)), i)); }
        candidates.sort(Comparator.<Upset, Fraction>comparing(item -> Report.comparison(item.expected(), 4)).thenComparingInt(Upset::index));
        List<String> lines = new ArrayList<>(List.of("upsets top " + settings.upsets));
        for (Upset item : candidates.subList(0, (int) Math.min(settings.upsets, candidates.size()))) {
            Match match = item.match(); boolean home = match.margin() > 0; int winner = home ? match.home() : match.away(), loser = home ? match.away() : match.home();
            String score = home ? match.homeScore() + "-" + match.awayScore() : match.awayScore() + "-" + match.homeScore();
            lines.add("round " + match.round() + " " + code(winner) + " beat " + code(loser) + " " + score + " " + (home ? "home" : "away") + " expected " + Report.fixed(item.expected()) + " gain " + Report.fixed(item.gain(), 2));
        }
        return lines;
    }
    List<String> tiebreakLines() {
        List<String> lines = new ArrayList<>(List.of("tiebreaks"));
        for (List<Integer> group : finalTable.tiedGroups()) lines.add("points " + finalTable.records[group.getFirst()].points + " order " + String.join(" ", group.stream().map(this::code).toList()) + " h2h_points " + String.join(" ", group.stream().map(team -> "" + finalTable.headPoints[team]).toList()) + " h2h_diff " + String.join(" ", group.stream().map(team -> "" + finalTable.headDifference[team]).toList()));
        if (lines.size() == 1) lines.add("none"); return lines;
    }
    List<String> leaderLines() {
        List<String> lines = new ArrayList<>(List.of("leaders")); int previous = -1, recorded = 0;
        for (int r = 0; r < roundTables.size(); r++) { Standings table = roundTables.get(r); int leader = table.order.getFirst(); if (leader != previous) { lines.add("round " + (r + 1) + " " + code(leader) + " points " + table.records[leader].points); recorded++; } previous = leader; }
        lines.add("lead_changes " + (recorded - 1)); return lines;
    }
    List<String> streakLines() {
        List<String> lines = new ArrayList<>();
        for (int category = 0; category < 2; category++) {
            List<Streak> streaks = category == 0 ? wins : unbeaten; String label = category == 0 ? "longest_win_streak" : "longest_unbeaten_streak"; int longest = 0;
            for (Streak streak : streaks) longest = Math.max(longest, streak.length());
            for (int team = 0; team < count; team++) { Streak streak = streaks.get(team); if (streak.length() == longest) lines.add(label + " " + code(team) + " length " + streak.length() + " rounds " + streak.first() + "-" + streak.last()); }
        }
        return lines;
    }
    List<String> crosstableLines() {
        List<Integer> top = finalTable.order.subList(0, settings.topPositions); List<String> lines = new ArrayList<>(List.of("crosstable top " + settings.topPositions, "team " + String.join(" ", top.stream().map(this::code).toList())));
        for (int first : top) { List<String> entries = new ArrayList<>(); for (int second : top) entries.add(first == second ? "-" : Main.recordText(appearances.get(first).stream().filter(item -> item.opponent == second).toList())); lines.add(code(first) + " " + String.join(" ", entries)); }
        return lines;
    }
    List<String> trajectoryLines() {
        List<String> lines = new ArrayList<>(List.of("trajectories"));
        for (int team = 0; team < count; team++) {
            int peak = 0, low = 0, best = 0, worst = 0;
            for (int r = 1; r < finalRound; r++) {
                Fraction value = Report.comparison(fit.elo.roundRatings.get(r)[team], 2);
                if (value.compareTo(Report.comparison(fit.elo.roundRatings.get(peak)[team], 2)) > 0) peak = r;
                if (value.compareTo(Report.comparison(fit.elo.roundRatings.get(low)[team], 2)) < 0) low = r;
                if (roundTables.get(r).positions[team] < roundTables.get(best).positions[team]) best = r;
                if (roundTables.get(r).positions[team] > roundTables.get(worst).positions[team]) worst = r;
            }
            lines.add(code(team) + " elo_peak " + Report.fixed(fit.elo.roundRatings.get(peak)[team], 2) + " round " + (peak + 1) + " elo_low " + Report.fixed(fit.elo.roundRatings.get(low)[team], 2) + " round " + (low + 1) + " best_position " + roundTables.get(best).positions[team] + " round " + (best + 1) + " worst_position " + roundTables.get(worst).positions[team] + " round " + (worst + 1));
        }
        return lines;
    }
    List<String> correlationLines(boolean spearman) {
        List<String> lines = new ArrayList<>(List.of(spearman ? "spearman" : "kendall", "model " + String.join(" ", Main.COMPARISON_MODELS)));
        for (String first : Main.COMPARISON_MODELS) { List<String> values = new ArrayList<>(); for (String second : Main.COMPARISON_MODELS) values.add((spearman ? Evaluation.spearman(comparison.get(first), comparison.get(second)) : Evaluation.kendall(comparison.get(first), comparison.get(second))).toString()); lines.add(first + " " + String.join(" ", values)); }
        return lines;
    }
    List<String> similarityLines() {
        Similarity most = null, least = null;
        for (int i = 0; i < Main.COMPARISON_MODELS.size(); i++) for (int j = i + 1; j < Main.COMPARISON_MODELS.size(); j++) {
            String a = Main.COMPARISON_MODELS.get(i), b = Main.COMPARISON_MODELS.get(j); Similarity pair = new Similarity(a, b, Evaluation.kendall(comparison.get(a), comparison.get(b)));
            if (most == null || pair.tau().compareTo(most.tau()) > 0) most = pair; if (least == null || pair.tau().compareTo(least.tau()) < 0) least = pair;
        }
        return List.of("most_similar " + most.first() + " " + most.second() + " tau " + Report.fractionWithReal(most.tau()), "least_similar " + least.first() + " " + least.second() + " tau " + Report.fractionWithReal(least.tau()));
    }
    List<String> seasonLines() { return Main.parts(List.of(summaryLines(), upsetLines(), tiebreakLines(), leaderLines(), streakLines(), crosstableLines(), trajectoryLines(), correlationLines(false), correlationLines(true), similarityLines())); }
    List<String> predictionLines() {
        List<String> lines = new ArrayList<>(List.of(Main.PREDICTIONS_HEADER));
        for (Prediction prediction : predictions) {
            Match match = prediction.match; List<String> fields = new ArrayList<>(List.of("" + match.round(), code(match.home()), code(match.away()), "" + match.homeScore(), "" + match.awayScore(), match.resultTwice() == 2 ? "H" : match.resultTwice() == 1 ? "D" : "A"));
            for (double probability : prediction.probabilities) fields.add(Report.fixed(probability)); lines.add(String.join(",", fields));
        }
        return lines;
    }
    List<String> linkLines() {
        List<String> lines = new ArrayList<>(List.of("links"));
        for (ValidationRound validation : rounds) {
            StringBuilder line = new StringBuilder("round " + validation.number + " train " + validation.training.size() + " base " + Report.fixed(validation.base) + " bt_home " + Report.fixed(validation.fit.homeFactor));
            for (String model : Main.LINK_MODELS) { Link link = validation.links.get(model); line.append(" ").append(model).append(" ").append(Report.fixed(link.alpha())).append(" ").append(Report.fixed(link.beta())); }
            lines.add(line.toString());
        }
        return lines;
    }
    List<String> scoreLines() {
        List<String> lines = new ArrayList<>(List.of("scores", "model log_loss brier skill accuracy"));
        for (int i = 0; i < 8; i++) lines.add(Main.PREDICTION_MODELS.get(i) + " " + Report.fixed(scores.losses[i]) + " " + Report.fixed(scores.briers[i]) + " " + Report.fixed(scores.skills[i]) + " " + Report.fractionWithReal(scores.accuracies[i]));
        lines.add("ranking_log_loss " + Main.modelNames(scores.lossRanking)); lines.add("ranking_brier " + Main.modelNames(scores.brierRanking)); lines.add("ranking_accuracy " + Main.modelNames(scores.accuracyRanking)); return lines;
    }
    List<String> pairedLines() {
        int reference = scores.lossRanking.getFirst(), size = predictions.size(); List<String> lines = new ArrayList<>(List.of("paired_log_loss reference " + Main.PREDICTION_MODELS.get(reference)));
        for (int i = 0; i < 8; i++) {
            if (i == reference) continue;
            double[] deltas = new double[size]; double total = 0;
            for (int j = 0; j < size; j++) { Prediction prediction = predictions.get(j); deltas[j] = prediction.losses[i] - prediction.losses[reference]; total += deltas[j]; }
            double mean = total / size, squares = 0; for (double delta : deltas) squares += (delta - mean) * (delta - mean);
            double spread = Math.sqrt(squares / (size - 1)), t = mean / (spread / Math.sqrt(size));
            lines.add(Main.PREDICTION_MODELS.get(i) + " mean_diff " + Report.fixed(mean) + " sd " + Report.fixed(spread) + " t " + Report.fixed(t, 2));
        }
        return lines;
    }
    List<String> marginLines() {
        double absolute = 0, squares = 0, total = 0;
        for (Prediction prediction : predictions) { double error = prediction.marginError; absolute += Math.abs(error); squares += error * error; total += error; }
        int size = predictions.size(); return List.of("massey_margin mae " + Report.fixed(absolute / size) + " rmse " + Report.fixed(Math.sqrt(squares / size)) + " bias " + Report.fixed(total / size));
    }
    List<String> roundLossLines() {
        List<String> lines = new ArrayList<>(List.of("round_log_loss", "round " + String.join(" ", Main.PREDICTION_MODELS)));
        for (ValidationRound validation : rounds) { List<String> values = new ArrayList<>(); for (int i = 0; i < 8; i++) { double total = 0; for (Prediction prediction : validation.predictions) total += prediction.losses[i]; values.add(Report.fixed(total / validation.predictions.size())); } lines.add(validation.number + " " + String.join(" ", values)); }
        return lines;
    }
    List<String> calibrationLines() {
        int bins = settings.calibrationBins; List<String> lines = new ArrayList<>(List.of("calibration bins " + bins));
        for (int i = 0; i < 8; i++) {
            List<List<Prediction>> members = new ArrayList<>(); for (int k = 0; k < bins; k++) members.add(new ArrayList<>());
            for (Prediction prediction : predictions) members.get(Math.min((int) Math.floor(bins * prediction.probabilities[i]), bins - 1)).add(prediction);
            for (int k = 0; k < bins; k++) {
                List<Prediction> group = members.get(k); String prefix = Main.PREDICTION_MODELS.get(i) + " bin " + (k + 1) + " count " + group.size();
                if (group.isEmpty()) lines.add(prefix + " predicted - observed -");
                else { double total = 0; int observedTwice = 0; for (Prediction prediction : group) { total += prediction.probabilities[i]; observedTwice += prediction.match.resultTwice(); } lines.add(prefix + " predicted " + Report.fixed(total / group.size()) + " observed " + new Fraction(observedTwice, 2 * group.size())); }
            }
        }
        return lines;
    }
    List<String> gridLines() {
        List<String> lines = new ArrayList<>(List.of("elo_grid", "k " + String.join(" ", settings.gridHome.stream().map(home -> "h" + home).toList()))); Fraction bestRounded = null; long bestK = 0, bestHome = 0; double bestLoss = 0;
        for (long k : settings.gridK) {
            List<String> row = new ArrayList<>(List.of("" + k));
            for (long home : settings.gridHome) {
                EloRun run = Elo.run(count, matches, k, home, settings.eloInitial); double total = 0; int size = 0;
                for (int i = 0; i < matches.size(); i++) if (matches.get(i).round() >= settings.holdoutRound) { total += Evaluation.logLoss(run.expected.get(i), matches.get(i).resultTwice()); size++; }
                double loss = total / size; row.add(Report.fixed(loss)); Fraction rounded = Report.comparison(loss, 4);
                if (bestRounded == null || rounded.compareTo(bestRounded) < 0) { bestRounded = rounded; bestK = k; bestHome = home; bestLoss = loss; }
            }
            lines.add(String.join(" ", row));
        }
        lines.add("best k " + bestK + " home " + bestHome + " log_loss " + Report.fixed(bestLoss)); return lines;
    }
    Fraction projectionTau() {
        Fraction[] projected = new Fraction[count], actual = new Fraction[count]; for (int i = 0; i < count; i++) { projected[i] = new Fraction(-projection.ranks[i]); actual[i] = new Fraction(-finalTable.positions[i]); }
        return Evaluation.kendall(projected, actual);
    }
    List<String> evaluationLines() { return Main.parts(List.of(List.of("holdout rounds " + settings.holdoutRound + "-" + finalRound + " matches " + predictions.size()), linkLines(), scoreLines(), pairedLines(), marginLines(), roundLossLines(), calibrationLines(), gridLines(), List.of("projection simulations " + settings.simulations + " kendall " + Report.fractionWithReal(projectionTau())))); }
    List<String> projectionLines() {
        List<String> lines = new ArrayList<>(List.of(Main.PROJECTION_HEADER));
        for (int team : projection.order) lines.add(Main.csv(projection.ranks[team], code(team), projection.current.records[team].points, projection.current.positions[team], Report.fixed(projection.opponentStrength(team), 2), Report.fixed(new Fraction(projection.totalPoints[team], settings.simulations)), Report.fixed(new Fraction(projection.titles[team], settings.simulations)), Report.fixed(new Fraction(projection.tops[team], settings.simulations)), Report.fixed(new Fraction(projection.bottoms[team], settings.simulations)), finalTable.records[team].points, finalTable.positions[team]));
        return lines;
    }
}
public class Main {
    static final List<String> RATING_MODELS = List.of("elo", "colley", "massey", "bt", "od", "winpct"), COMPARISON_MODELS = List.of("standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag"), LINK_MODELS = List.of("colley", "massey", "od", "winpct"), PREDICTION_MODELS = List.of("base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble");
    static final String STANDINGS_HEADER = "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck", RATINGS_HEADER = "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank", HISTORY_HEADER = "round,team,elo,change,elo_rank,points,position", PREDICTIONS_HEADER = "round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble", PROJECTION_HEADER = "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position";
    static List<Integer> indices(int count) { List<Integer> indices = new ArrayList<>(); for (int i = 0; i < count; i++) indices.add(i); return indices; }
    static TeamRecord[] records(int count, List<Match> matches, Settings settings) { TeamRecord[] records = new TeamRecord[count]; for (int i = 0; i < count; i++) records[i] = new TeamRecord(); for (Match match : matches) { records[match.home()].add(match.homeScore(), match.awayScore(), settings); records[match.away()].add(match.awayScore(), match.homeScore(), settings); } return records; }
    static Streak longest(List<Appearance> items, String allowed) {
        Streak best = new Streak(0, 0, 0); int start = 0, length = 0;
        for (int i = 0; i < items.size(); i++) { Appearance item = items.get(i); if (!allowed.contains(item.letter)) { length = 0; continue; } if (length == 0) start = i; length++; if (length > best.length()) best = new Streak(length, items.get(start).match.round(), item.match.round()); }
        return best;
    }
    static String currentStreak(List<Appearance> items) { String letter = items.getLast().letter; int count = 0; for (int i = items.size() - 1; i >= 0 && items.get(i).letter.equals(letter); i--) count++; return letter + count; }
    static String recordText(List<Appearance> items) { int won = 0, drawn = 0, lost = 0; for (Appearance item : items) { if (item.letter.equals("W")) won++; else if (item.letter.equals("D")) drawn++; else lost++; } return won + "-" + drawn + "-" + lost; }
    static int[] ranks(Fraction[] values) { int[] ranks = new int[values.length]; for (int i = 0; i < values.length; i++) { ranks[i] = 1; for (Fraction value : values) if (value.compareTo(values[i]) > 0) ranks[i]++; } return ranks; }
    static String csv(Object... fields) { return String.join(",", Arrays.stream(fields).map(Object::toString).toList()); }
    static String modelNames(List<Integer> ranking) { return String.join(" ", ranking.stream().map(PREDICTION_MODELS::get).toList()); }
    static List<String> parts(List<List<String>> parts) { List<String> lines = new ArrayList<>(); for (List<String> part : parts) { if (!lines.isEmpty()) lines.add(""); lines.addAll(part); } return lines; }
    public static void main(String[] args) throws Exception {
        LeagueAnalysis analysis = new LeagueAnalysis(Season.load()); Map<String, List<String>> files = new LinkedHashMap<>();
        files.put("standings.csv", analysis.standingsLines()); files.put("ratings.csv", analysis.ratingsLines()); files.put("history.csv", analysis.historyLines()); files.put("season.txt", analysis.seasonLines()); files.put("predictions.csv", analysis.predictionLines()); files.put("evaluation.txt", analysis.evaluationLines()); files.put("projection.csv", analysis.projectionLines());
        Files.createDirectories(Path.of("output")); for (var entry : files.entrySet()) Report.write(entry.getKey(), entry.getValue());
    }
}
