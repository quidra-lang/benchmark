using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;

sealed class Appearance {
    public readonly Match Match;
    public readonly bool Home;
    public readonly int Opponent, Scored, Conceded;
    public readonly string Letter;
    public Appearance(Match match, int team) {
        Match = match; Home = match.Home == team; Opponent = Home ? match.Away : match.Home; Scored = Home ? match.HomeScore : match.AwayScore; Conceded = Home ? match.AwayScore : match.HomeScore;
        Letter = Scored > Conceded ? "W" : Scored == Conceded ? "D" : "L";
    }
}
sealed class TeamRecord {
    public int Played, Won, Drawn, Lost, Scored, Conceded;
    public long Points;
    public void Add(int scored, int conceded, Settings settings) {
        Played++; Scored += scored; Conceded += conceded;
        if (scored > conceded) { Won++; Points += settings.WinPoints; }
        else if (scored == conceded) { Drawn++; Points += settings.DrawPoints; }
        else Lost++;
    }
    public int Difference => Scored - Conceded;
    public Fraction Percentage() => new(2 * Won + Drawn, 2 * Played);
}
sealed class Standings {
    public readonly TeamRecord[] Records;
    public readonly long[] HeadPoints;
    public readonly int[] HeadDifference, Positions;
    public readonly List<int> Order;
    public Standings(List<Team> teams, List<Match> matches, Settings settings) {
        int count = teams.Count;
        Records = Program.Records(count, matches, settings); HeadPoints = new long[count]; HeadDifference = new int[count]; Positions = new int[count];
        foreach (Match match in matches) if (Records[match.Home].Points == Records[match.Away].Points) {
            int home = match.Home, away = match.Away;
            if (match.Margin > 0) HeadPoints[home] += settings.WinPoints;
            else if (match.Margin < 0) HeadPoints[away] += settings.WinPoints;
            else { HeadPoints[home] += settings.DrawPoints; HeadPoints[away] += settings.DrawPoints; }
            HeadDifference[home] += match.Margin; HeadDifference[away] -= match.Margin;
        }
        Order = Program.Indices(count).OrderByDescending(team => Records[team].Points).ThenByDescending(team => HeadPoints[team]).ThenByDescending(team => HeadDifference[team]).ThenByDescending(team => Records[team].Difference).ThenByDescending(team => Records[team].Scored).ThenBy(team => teams[team].Code, StringComparer.Ordinal).ToList();
        for (int i = 0; i < count; i++) Positions[Order[i]] = i + 1;
    }
    public List<List<int>> TiedGroups() {
        List<List<int>> groups = new();
        foreach (int team in Order) {
            if (groups.Count == 0 || Records[groups[^1][0]].Points != Records[team].Points) groups.Add(new());
            groups[^1].Add(team);
        }
        return groups.Where(group => group.Count > 1).ToList();
    }
}
sealed record Streak(int Length, int First, int Last);
sealed class ModelFit {
    public readonly EloRun EloResult;
    public readonly double[] Colley, Massey, Strengths, Offense, Defense, Od;
    public readonly double HomeAdvantage, HomeFactor;
    public readonly Fraction[] Percentages;
    public ModelFit(int count, List<Match> matches, Settings settings) {
        EloResult = Elo.Run(count, matches, settings.EloK, settings.EloHome, settings.EloInitial); Colley = LinearModels.Colley(count, matches);
        var fitted = LinearModels.FitMassey(count, matches); Massey = fitted.Ratings; HomeAdvantage = fitted.HomeAdvantage;
        var bt = IterativeModels.FitBradleyTerry(count, matches, settings.BtIterations); Strengths = bt.Strengths; HomeFactor = bt.HomeFactor;
        var result = IterativeModels.FitOffenseDefense(count, matches, settings.OdIterations); Offense = result.Offense; Defense = result.Defense; Od = result.Ratings;
        TeamRecord[] records = Program.Records(count, matches, settings); Percentages = records.Select(record => record.Percentage()).ToArray();
    }
    public double Feature(string model, Match match) {
        int home = match.Home, away = match.Away;
        return model switch { "colley" => Colley[home] - Colley[away], "massey" => Massey[home] - Massey[away], "od" => Math.Log(Od[home]) - Math.Log(Od[away]), _ => Percentages[home].Real - Percentages[away].Real };
    }
    public double BtProbability(Match match) { double home = HomeFactor * Strengths[match.Home]; return home / (home + Strengths[match.Away]); }
    public double Margin(Match match) => Massey[match.Home] - Massey[match.Away] + HomeAdvantage;
}
sealed class Prediction {
    public readonly Match Match;
    public readonly double[] Probabilities, Losses = new double[8], Briers = new double[8];
    public readonly int[] ScoresTwice = new int[8];
    public readonly double MarginError;
    public Prediction(Match match, double[] probabilities, double marginError) {
        Match = match; Probabilities = probabilities; MarginError = marginError;
        for (int i = 0; i < 8; i++) { Losses[i] = Evaluation.LogLoss(probabilities[i], match.ResultTwice); Briers[i] = Evaluation.Brier(probabilities[i], match.ResultTwice); ScoresTwice[i] = Evaluation.CorrectnessTwice(probabilities[i], match.ResultTwice); }
    }
}
sealed class ValidationRound {
    public readonly int Number;
    public readonly List<Match> Training;
    public readonly ModelFit Fit;
    public readonly double Base;
    public readonly Dictionary<string, Link> Links = new(StringComparer.Ordinal);
    public readonly List<Prediction> Predictions = new();
    public ValidationRound(int number, int count, List<Match> matches, Settings settings) {
        Number = number; Training = Season.Before(matches, number); Fit = new ModelFit(count, Training, settings);
        int resultsTwice = 0;
        foreach (Match match in Training) resultsTwice += match.ResultTwice;
        Base = new Fraction(resultsTwice, 2 * Training.Count).Real;
        foreach (string model in Program.LinkModels) {
            double[] features = Training.Select(match => Fit.Feature(model, match)).ToArray();
            Links.Add(model, Evaluation.FitLink(features, Training, settings.LinkIterations));
        }
        foreach (Match match in matches) if (match.Round == number) Predictions.Add(Predict(match, settings));
    }
    Prediction Predict(Match match, Settings settings) {
        double[] probabilities = new double[8];
        probabilities[0] = Base; probabilities[1] = Elo.Expected(Fit.EloResult.Ratings[match.Home], Fit.EloResult.Ratings[match.Away], settings.EloHome);
        foreach (string model in Program.LinkModels) { Link link = Links[model]; probabilities[Program.PredictionModels.IndexOf(model)] = Evaluation.Sigma(link.Alpha + link.Beta * Fit.Feature(model, match)); }
        probabilities[4] = Fit.BtProbability(match);
        double ensemble = 0;
        for (int i = 1; i <= 6; i++) ensemble += probabilities[i];
        probabilities[7] = ensemble / 6;
        return new Prediction(match, probabilities, match.Margin - Fit.Margin(match));
    }
}
sealed class ModelScores {
    public readonly double[] Losses = new double[8], Briers = new double[8], Skills = new double[8];
    public readonly Fraction[] Accuracies = new Fraction[8];
    public readonly List<int> LossRanking, BrierRanking, AccuracyRanking;
    public ModelScores(List<Prediction> predictions) {
        for (int i = 0; i < 8; i++) {
            double loss = 0, brier = 0;
            int score = 0;
            foreach (Prediction prediction in predictions) { loss += prediction.Losses[i]; brier += prediction.Briers[i]; score += prediction.ScoresTwice[i]; }
            Losses[i] = loss / predictions.Count; Briers[i] = brier / predictions.Count; Accuracies[i] = new Fraction(score, 2 * predictions.Count);
        }
        for (int i = 0; i < 8; i++) Skills[i] = 1 - Briers[i] / Briers[0];
        LossRanking = Program.Indices(8).OrderBy(i => Report.Comparison(Losses[i], 4)).ThenBy(i => i).ToList();
        BrierRanking = Program.Indices(8).OrderBy(i => Report.Comparison(Briers[i], 4)).ThenBy(i => i).ToList();
        AccuracyRanking = Program.Indices(8).OrderByDescending(i => Accuracies[i]).ThenBy(i => i).ToList();
    }
}
sealed class Projection {
    public readonly Standings Current;
    public readonly double[] Ratings;
    public readonly List<Match> Remaining;
    public readonly long[] TotalPoints;
    public readonly int[] Titles, Tops, Bottoms, Ranks;
    public readonly List<int> Order;
    public Projection(List<Team> teams, List<Match> matches, Settings settings) {
        int count = teams.Count;
        List<Match> currentMatches = Season.Before(matches, settings.HoldoutRound);
        Current = new Standings(teams, currentMatches, settings); Ratings = Elo.Run(count, currentMatches, settings.EloK, settings.EloHome, settings.EloInitial).Ratings;
        Remaining = matches.Where(match => match.Round >= settings.HoldoutRound).ToList();
        TotalPoints = new long[count]; Titles = new int[count]; Tops = new int[count]; Bottoms = new int[count]; Ranks = new int[count];
        double[] probabilities = Remaining.Select(match => Elo.Expected(Ratings[match.Home], Ratings[match.Away], settings.EloHome)).ToArray();
        long state = settings.Seed;
        for (int simulation = 0; simulation < settings.Simulations; simulation++) {
            long[] points = Current.Records.Select(record => record.Points).ToArray();
            for (int i = 0; i < Remaining.Count; i++) {
                Match match = Remaining[i]; state = 48271 * state % 2147483647;
                double uniform = (double)state / 2147483647;
                points[uniform < probabilities[i] ? match.Home : match.Away] += settings.WinPoints;
            }
            List<int> simulated = Ordered(points);
            for (int i = 0; i < count; i++) {
                int team = simulated[i], place = i + 1; TotalPoints[team] += points[team];
                if (place == 1) Titles[team]++;
                if (place <= settings.TopPositions) Tops[team]++;
                if (place >= count - settings.BottomPositions + 1) Bottoms[team]++;
            }
        }
        Order = Ordered(TotalPoints);
        for (int i = 0; i < count; i++) Ranks[Order[i]] = i + 1;
    }
    List<int> Ordered(long[] points) => Program.Indices(points.Length).OrderByDescending(team => points[team]).ThenBy(team => Current.Positions[team]).ToList();
    public double OpponentStrength(int team) {
        double total = 0; int count = 0;
        foreach (Match match in Remaining) {
            if (match.Home == team) { total += Ratings[match.Away]; count++; }
            else if (match.Away == team) { total += Ratings[match.Home]; count++; }
        }
        return total / count;
    }
}
sealed record Upset(Match Match, double Expected, double Gain, int Index);
sealed record Similarity(string First, string Second, Fraction Tau);
sealed class LeagueAnalysis {
    readonly List<Team> teams;
    readonly List<Match> matches;
    readonly Settings settings;
    readonly int count, finalRound;
    readonly List<List<Appearance>> appearances = new();
    readonly Standings finalTable;
    readonly ModelFit fit;
    readonly List<Standings> roundTables = new();
    readonly List<Streak> wins = new(), unbeaten = new();
    readonly Fraction[] sos, sos2, rpi;
    readonly double[] pythag, luck;
    readonly Dictionary<string, Fraction[]> comparison = new(StringComparer.Ordinal);
    readonly Dictionary<string, int[]> ranks = new(StringComparer.Ordinal);
    readonly List<ValidationRound> rounds = new();
    readonly List<Prediction> predictions = new();
    readonly ModelScores scores;
    readonly Projection projection;
    public LeagueAnalysis(SeasonData season) {
        teams = season.Teams; matches = season.Matches; settings = season.Settings; count = teams.Count; finalRound = matches[^1].Round;
        for (int i = 0; i < count; i++) {
            List<Appearance> items = matches.Where(match => match.Home == i || match.Away == i).Select(match => new Appearance(match, i)).ToList();
            appearances.Add(items); wins.Add(Program.Longest(items, "W")); unbeaten.Add(Program.Longest(items, "WD"));
        }
        finalTable = new Standings(teams, matches, settings); fit = new ModelFit(count, matches, settings);
        for (int round = 1; round <= finalRound; round++) roundTables.Add(new Standings(teams, Season.Before(matches, round + 1), settings));
        sos = new Fraction[count]; sos2 = new Fraction[count]; rpi = new Fraction[count]; pythag = new double[count]; luck = new double[count];
        for (int i = 0; i < count; i++) sos[i] = OpponentAverage(i, fit.Percentages);
        for (int i = 0; i < count; i++) sos2[i] = OpponentAverage(i, sos);
        for (int i = 0; i < count; i++) {
            rpi[i] = fit.Percentages[i].Add(sos[i].Multiply(2)).Add(sos2[i]).Divide(4);
            TeamRecord record = finalTable.Records[i]; pythag[i] = 1 / (1 + Math.Pow((double)record.Conceded / record.Scored, settings.PythagoreanExponent)); luck[i] = fit.Percentages[i].Real - pythag[i];
        }
        comparison.Add("standings", finalTable.Positions.Select(position => new Fraction(-position)).ToArray());
        comparison.Add("elo", Rounded(fit.EloResult.Ratings, 2)); comparison.Add("colley", Rounded(fit.Colley, 4)); comparison.Add("massey", Rounded(fit.Massey, 4)); comparison.Add("bt", Rounded(fit.Strengths, 4)); comparison.Add("od", Rounded(fit.Od, 2)); comparison.Add("winpct", fit.Percentages); comparison.Add("rpi", rpi); comparison.Add("pythag", Rounded(pythag, 4));
        foreach (string model in Program.RatingModels) ranks.Add(model, Program.Ranks(comparison[model]));
        for (int round = settings.HoldoutRound; round <= finalRound; round++) { ValidationRound validation = new(round, count, matches, settings); rounds.Add(validation); predictions.AddRange(validation.Predictions); }
        scores = new ModelScores(predictions); projection = new Projection(teams, matches, settings);
    }
    Fraction OpponentAverage(int team, Fraction[] values) {
        Fraction total = new(0);
        foreach (Appearance appearance in appearances[team]) total = total.Add(values[appearance.Opponent]);
        return total.Divide(appearances[team].Count);
    }
    static Fraction[] Rounded(double[] values, int places) => values.Select(value => Report.Comparison(value, places)).ToArray();
    string Code(int team) => teams[team].Code;
    List<string> StandingsLines() {
        List<string> lines = [Program.StandingsHeader];
        foreach (int team in finalTable.Order) {
            TeamRecord record = finalTable.Records[team]; List<Appearance> items = appearances[team];
            string form = string.Concat(items.TakeLast(settings.FormLength).Select(item => item.Letter));
            lines.Add(Program.Csv(finalTable.Positions[team], Code(team), teams[team].Name, record.Played, record.Won, record.Drawn, record.Lost, record.Scored, record.Conceded, record.Difference, record.Points,
                Program.RecordText(items.Where(item => item.Home)), Program.RecordText(items.Where(item => !item.Home)), form, Program.CurrentStreak(items), Program.RecordText(items.Where(item => Math.Abs((long)item.Scored - item.Conceded) <= settings.CloseMargin)),
                wins[team].Length, unbeaten[team].Length, fit.Percentages[team], Report.Fixed(sos[team]), Report.Fixed(sos2[team]), Report.Fixed(rpi[team]), Report.Fixed(pythag[team]), Report.Fixed(luck[team])));
        }
        return lines;
    }
    List<string> RatingsLines() {
        int[] totals = new int[count];
        foreach (string model in Program.RatingModels) for (int i = 0; i < count; i++) totals[i] += ranks[model][i];
        List<string> lines = [Program.RatingsHeader];
        foreach (int team in Program.Indices(count).OrderBy(team => totals[team]).ThenBy(Code, StringComparer.Ordinal)) {
            List<int> values = Program.RatingModels.Select(model => ranks[model][team]).ToList();
            lines.Add(Program.Csv(Code(team), Report.Fixed(fit.EloResult.Ratings[team], 2), ranks["elo"][team], Report.Fixed(fit.Colley[team]), ranks["colley"][team], Report.Fixed(fit.Massey[team]), ranks["massey"][team],
                Report.Fixed(fit.Strengths[team]), ranks["bt"][team], Report.Fixed(fit.Offense[team], 2), Report.Fixed(fit.Defense[team]), Report.Fixed(fit.Od[team], 2), ranks["od"][team], Report.Fixed(fit.Percentages[team]), ranks["winpct"][team], totals[team], values.Min(), values.Max()));
        }
        return lines;
    }
    List<string> HistoryLines() {
        List<string> lines = [Program.HistoryHeader];
        double[] previous = Enumerable.Repeat((double)settings.EloInitial, count).ToArray();
        for (int r = 0; r < roundTables.Count; r++) {
            Standings table = roundTables[r]; double[] ratings = fit.EloResult.RoundRatings[r]; int[] positions = Program.Ranks(Rounded(ratings, 2));
            for (int team = 0; team < count; team++) lines.Add(Program.Csv(r + 1, Code(team), Report.Fixed(ratings[team], 2), Report.Fixed(ratings[team] - previous[team], 2), positions[team], table.Records[team].Points, table.Positions[team]));
            previous = ratings;
        }
        return lines;
    }
    List<string> SummaryLines() {
        int home = 0, drawn = 0, away = 0, resultsTwice = 0;
        foreach (Match match in matches) { resultsTwice += match.ResultTwice; if (match.ResultTwice == 2) home++; else if (match.ResultTwice == 1) drawn++; else away++; }
        Fraction rate = new(resultsTwice, 2 * matches.Count);
        return ["season teams " + count + " matches " + matches.Count + " rounds " + finalRound, "home won " + home + " drawn " + drawn + " lost " + away + " rate " + Report.FractionWithReal(rate),
            "massey_home_advantage " + Report.Fixed(fit.HomeAdvantage), "bt_home_factor " + Report.Fixed(fit.HomeFactor)];
    }
    List<string> UpsetLines() {
        List<Upset> candidates = new();
        for (int i = 0; i < matches.Count; i++) {
            Match match = matches[i];
            if (match.Margin != 0) candidates.Add(new Upset(match, match.Margin > 0 ? fit.EloResult.Expected[i] : 1 - fit.EloResult.Expected[i], Math.Abs(fit.EloResult.Changes[i]), i));
        }
        List<string> lines = ["upsets top " + settings.Upsets];
        foreach (Upset item in candidates.OrderBy(item => Report.Comparison(item.Expected, 4)).ThenBy(item => item.Index).Take((int)Math.Min(settings.Upsets, candidates.Count))) {
            Match match = item.Match; bool home = match.Margin > 0;
            int winner = home ? match.Home : match.Away, loser = home ? match.Away : match.Home;
            string score = home ? match.HomeScore + "-" + match.AwayScore : match.AwayScore + "-" + match.HomeScore;
            lines.Add("round " + match.Round + " " + Code(winner) + " beat " + Code(loser) + " " + score + " " + (home ? "home" : "away") + " expected " + Report.Fixed(item.Expected) + " gain " + Report.Fixed(item.Gain, 2));
        }
        return lines;
    }
    List<string> TiebreakLines() {
        List<string> lines = ["tiebreaks"];
        foreach (List<int> group in finalTable.TiedGroups()) lines.Add("points " + finalTable.Records[group[0]].Points + " order " + string.Join(" ", group.Select(Code)) + " h2h_points " + string.Join(" ", group.Select(team => finalTable.HeadPoints[team])) + " h2h_diff " + string.Join(" ", group.Select(team => finalTable.HeadDifference[team])));
        if (lines.Count == 1) lines.Add("none");
        return lines;
    }
    List<string> LeaderLines() {
        List<string> lines = ["leaders"];
        int previous = -1, recorded = 0;
        for (int r = 0; r < roundTables.Count; r++) {
            Standings table = roundTables[r]; int leader = table.Order[0];
            if (leader != previous) { lines.Add("round " + (r + 1) + " " + Code(leader) + " points " + table.Records[leader].Points); recorded++; }
            previous = leader;
        }
        lines.Add("lead_changes " + (recorded - 1));
        return lines;
    }
    List<string> StreakLines() {
        List<string> lines = new();
        for (int category = 0; category < 2; category++) {
            List<Streak> streaks = category == 0 ? wins : unbeaten;
            string label = category == 0 ? "longest_win_streak" : "longest_unbeaten_streak";
            int longest = streaks.Max(streak => streak.Length);
            for (int team = 0; team < count; team++) {
                Streak streak = streaks[team];
                if (streak.Length == longest) lines.Add(label + " " + Code(team) + " length " + streak.Length + " rounds " + streak.First + "-" + streak.Last);
            }
        }
        return lines;
    }
    List<string> CrosstableLines() {
        List<int> top = finalTable.Order.Take(settings.TopPositions).ToList();
        List<string> lines = ["crosstable top " + settings.TopPositions, "team " + string.Join(" ", top.Select(Code))];
        foreach (int first in top) {
            List<string> entries = top.Select(second => first == second ? "-" : Program.RecordText(appearances[first].Where(item => item.Opponent == second))).ToList();
            lines.Add(Code(first) + " " + string.Join(" ", entries));
        }
        return lines;
    }
    List<string> TrajectoryLines() {
        List<string> lines = ["trajectories"];
        for (int team = 0; team < count; team++) {
            int peak = 0, low = 0, best = 0, worst = 0;
            for (int r = 1; r < finalRound; r++) {
                Fraction value = Report.Comparison(fit.EloResult.RoundRatings[r][team], 2);
                if (value.CompareTo(Report.Comparison(fit.EloResult.RoundRatings[peak][team], 2)) > 0) peak = r;
                if (value.CompareTo(Report.Comparison(fit.EloResult.RoundRatings[low][team], 2)) < 0) low = r;
                if (roundTables[r].Positions[team] < roundTables[best].Positions[team]) best = r;
                if (roundTables[r].Positions[team] > roundTables[worst].Positions[team]) worst = r;
            }
            lines.Add(Code(team) + " elo_peak " + Report.Fixed(fit.EloResult.RoundRatings[peak][team], 2) + " round " + (peak + 1) + " elo_low " + Report.Fixed(fit.EloResult.RoundRatings[low][team], 2) + " round " + (low + 1) + " best_position " + roundTables[best].Positions[team] + " round " + (best + 1) + " worst_position " + roundTables[worst].Positions[team] + " round " + (worst + 1));
        }
        return lines;
    }
    List<string> CorrelationLines(bool spearman) {
        List<string> lines = [spearman ? "spearman" : "kendall", "model " + string.Join(" ", Program.ComparisonModels)];
        foreach (string first in Program.ComparisonModels) {
            List<string> values = Program.ComparisonModels.Select(second => (spearman ? Evaluation.Spearman(comparison[first], comparison[second]) : Evaluation.Kendall(comparison[first], comparison[second])).ToString()).ToList();
            lines.Add(first + " " + string.Join(" ", values));
        }
        return lines;
    }
    List<string> SimilarityLines() {
        Similarity most = null, least = null;
        for (int i = 0; i < Program.ComparisonModels.Count; i++) for (int j = i + 1; j < Program.ComparisonModels.Count; j++) {
            string a = Program.ComparisonModels[i], b = Program.ComparisonModels[j]; Similarity pair = new(a, b, Evaluation.Kendall(comparison[a], comparison[b]));
            if (most == null || pair.Tau.CompareTo(most.Tau) > 0) most = pair;
            if (least == null || pair.Tau.CompareTo(least.Tau) < 0) least = pair;
        }
        return ["most_similar " + most.First + " " + most.Second + " tau " + Report.FractionWithReal(most.Tau), "least_similar " + least.First + " " + least.Second + " tau " + Report.FractionWithReal(least.Tau)];
    }
    List<string> SeasonLines() => Program.Parts([SummaryLines(), UpsetLines(), TiebreakLines(), LeaderLines(), StreakLines(), CrosstableLines(), TrajectoryLines(), CorrelationLines(false), CorrelationLines(true), SimilarityLines()]);
    List<string> PredictionLines() {
        List<string> lines = [Program.PredictionsHeader];
        foreach (Prediction prediction in predictions) {
            Match match = prediction.Match;
            List<string> fields = [match.Round.ToString(), Code(match.Home), Code(match.Away), match.HomeScore.ToString(), match.AwayScore.ToString(), match.ResultTwice == 2 ? "H" : match.ResultTwice == 1 ? "D" : "A"];
            fields.AddRange(prediction.Probabilities.Select(value => Report.Fixed(value)));
            lines.Add(string.Join(",", fields));
        }
        return lines;
    }
    List<string> LinkLines() {
        List<string> lines = ["links"];
        foreach (ValidationRound validation in rounds) {
            List<string> fields = ["round " + validation.Number + " train " + validation.Training.Count + " base " + Report.Fixed(validation.Base) + " bt_home " + Report.Fixed(validation.Fit.HomeFactor)];
            foreach (string model in Program.LinkModels) { Link link = validation.Links[model]; fields.Add(model + " " + Report.Fixed(link.Alpha) + " " + Report.Fixed(link.Beta)); }
            lines.Add(string.Join(" ", fields));
        }
        return lines;
    }
    List<string> ScoreLines() {
        List<string> lines = ["scores", "model log_loss brier skill accuracy"];
        for (int i = 0; i < 8; i++) lines.Add(Program.PredictionModels[i] + " " + Report.Fixed(scores.Losses[i]) + " " + Report.Fixed(scores.Briers[i]) + " " + Report.Fixed(scores.Skills[i]) + " " + Report.FractionWithReal(scores.Accuracies[i]));
        lines.Add("ranking_log_loss " + Program.ModelNames(scores.LossRanking)); lines.Add("ranking_brier " + Program.ModelNames(scores.BrierRanking)); lines.Add("ranking_accuracy " + Program.ModelNames(scores.AccuracyRanking));
        return lines;
    }
    List<string> PairedLines() {
        int reference = scores.LossRanking[0], size = predictions.Count;
        List<string> lines = ["paired_log_loss reference " + Program.PredictionModels[reference]];
        for (int i = 0; i < 8; i++) {
            if (i == reference) continue;
            double[] deltas = new double[size]; double total = 0;
            for (int j = 0; j < size; j++) { Prediction prediction = predictions[j]; deltas[j] = prediction.Losses[i] - prediction.Losses[reference]; total += deltas[j]; }
            double mean = total / size, squares = 0;
            foreach (double delta in deltas) squares += (delta - mean) * (delta - mean);
            double spread = Math.Sqrt(squares / (size - 1)), t = mean / (spread / Math.Sqrt(size));
            lines.Add(Program.PredictionModels[i] + " mean_diff " + Report.Fixed(mean) + " sd " + Report.Fixed(spread) + " t " + Report.Fixed(t, 2));
        }
        return lines;
    }
    List<string> MarginLines() {
        double absolute = 0, squares = 0, total = 0;
        foreach (Prediction prediction in predictions) { double error = prediction.MarginError; absolute += Math.Abs(error); squares += error * error; total += error; }
        int size = predictions.Count;
        return ["massey_margin mae " + Report.Fixed(absolute / size) + " rmse " + Report.Fixed(Math.Sqrt(squares / size)) + " bias " + Report.Fixed(total / size)];
    }
    List<string> RoundLossLines() {
        List<string> lines = ["round_log_loss", "round " + string.Join(" ", Program.PredictionModels)];
        foreach (ValidationRound validation in rounds) {
            List<string> values = new();
            for (int i = 0; i < 8; i++) { double total = 0; foreach (Prediction prediction in validation.Predictions) total += prediction.Losses[i]; values.Add(Report.Fixed(total / validation.Predictions.Count)); }
            lines.Add(validation.Number + " " + string.Join(" ", values));
        }
        return lines;
    }
    List<string> CalibrationLines() {
        int bins = settings.CalibrationBins;
        List<string> lines = ["calibration bins " + bins];
        for (int i = 0; i < 8; i++) {
            List<List<Prediction>> members = Enumerable.Range(0, bins).Select(_ => new List<Prediction>()).ToList();
            foreach (Prediction prediction in predictions) members[Math.Min((int)Math.Floor(bins * prediction.Probabilities[i]), bins - 1)].Add(prediction);
            for (int k = 0; k < bins; k++) {
                List<Prediction> group = members[k];
                string prefix = Program.PredictionModels[i] + " bin " + (k + 1) + " count " + group.Count;
                if (group.Count == 0) { lines.Add(prefix + " predicted - observed -"); continue; }
                double total = 0; int observedTwice = 0;
                foreach (Prediction prediction in group) { total += prediction.Probabilities[i]; observedTwice += prediction.Match.ResultTwice; }
                lines.Add(prefix + " predicted " + Report.Fixed(total / group.Count) + " observed " + new Fraction(observedTwice, 2 * group.Count));
            }
        }
        return lines;
    }
    List<string> GridLines() {
        List<string> lines = ["elo_grid", "k " + string.Join(" ", settings.GridHome.Select(home => "h" + home))];
        Fraction bestRounded = null; long bestK = 0, bestHome = 0; double bestLoss = 0;
        foreach (long k in settings.GridK) {
            List<string> row = [k.ToString()];
            foreach (long home in settings.GridHome) {
                EloRun run = Elo.Run(count, matches, k, home, settings.EloInitial);
                double total = 0; int size = 0;
                for (int i = 0; i < matches.Count; i++) if (matches[i].Round >= settings.HoldoutRound) { total += Evaluation.LogLoss(run.Expected[i], matches[i].ResultTwice); size++; }
                double loss = total / size; row.Add(Report.Fixed(loss)); Fraction rounded = Report.Comparison(loss, 4);
                if (bestRounded == null || rounded.CompareTo(bestRounded) < 0) { bestRounded = rounded; bestK = k; bestHome = home; bestLoss = loss; }
            }
            lines.Add(string.Join(" ", row));
        }
        lines.Add("best k " + bestK + " home " + bestHome + " log_loss " + Report.Fixed(bestLoss));
        return lines;
    }
    Fraction ProjectionTau() {
        Fraction[] projected = projection.Ranks.Select(rank => new Fraction(-rank)).ToArray(), actual = finalTable.Positions.Select(position => new Fraction(-position)).ToArray();
        return Evaluation.Kendall(projected, actual);
    }
    List<string> EvaluationLines() => Program.Parts([["holdout rounds " + settings.HoldoutRound + "-" + finalRound + " matches " + predictions.Count], LinkLines(), ScoreLines(), PairedLines(), MarginLines(), RoundLossLines(), CalibrationLines(), GridLines(), ["projection simulations " + settings.Simulations + " kendall " + Report.FractionWithReal(ProjectionTau())]]);
    List<string> ProjectionLines() {
        List<string> lines = [Program.ProjectionHeader];
        foreach (int team in projection.Order) lines.Add(Program.Csv(projection.Ranks[team], Code(team), projection.Current.Records[team].Points, projection.Current.Positions[team], Report.Fixed(projection.OpponentStrength(team), 2),
            Report.Fixed(new Fraction(projection.TotalPoints[team], settings.Simulations)), Report.Fixed(new Fraction(projection.Titles[team], settings.Simulations)), Report.Fixed(new Fraction(projection.Tops[team], settings.Simulations)), Report.Fixed(new Fraction(projection.Bottoms[team], settings.Simulations)), finalTable.Records[team].Points, finalTable.Positions[team]));
        return lines;
    }
    public Dictionary<string, List<string>> OutputFiles() => new() {
        ["standings.csv"] = StandingsLines(), ["ratings.csv"] = RatingsLines(), ["history.csv"] = HistoryLines(), ["season.txt"] = SeasonLines(), ["predictions.csv"] = PredictionLines(), ["evaluation.txt"] = EvaluationLines(), ["projection.csv"] = ProjectionLines()
    };
}
static class Program {
    public static readonly List<string> RatingModels = ["elo", "colley", "massey", "bt", "od", "winpct"], ComparisonModels = ["standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag"], LinkModels = ["colley", "massey", "od", "winpct"], PredictionModels = ["base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble"];
    public const string StandingsHeader = "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck";
    public const string RatingsHeader = "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank";
    public const string HistoryHeader = "round,team,elo,change,elo_rank,points,position";
    public const string PredictionsHeader = "round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble";
    public const string ProjectionHeader = "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position";
    public static List<int> Indices(int count) => Enumerable.Range(0, count).ToList();
    public static TeamRecord[] Records(int count, List<Match> matches, Settings settings) {
        TeamRecord[] records = Enumerable.Range(0, count).Select(_ => new TeamRecord()).ToArray();
        foreach (Match match in matches) { records[match.Home].Add(match.HomeScore, match.AwayScore, settings); records[match.Away].Add(match.AwayScore, match.HomeScore, settings); }
        return records;
    }
    public static Streak Longest(List<Appearance> items, string allowed) {
        Streak best = new(0, 0, 0); int start = 0, length = 0;
        for (int i = 0; i < items.Count; i++) {
            Appearance item = items[i];
            if (!allowed.Contains(item.Letter, StringComparison.Ordinal)) { length = 0; continue; }
            if (length == 0) start = i;
            length++;
            if (length > best.Length) best = new Streak(length, items[start].Match.Round, item.Match.Round);
        }
        return best;
    }
    public static string CurrentStreak(List<Appearance> items) {
        string letter = items[^1].Letter; int count = 0;
        for (int i = items.Count - 1; i >= 0 && items[i].Letter == letter; i--) count++;
        return letter + count;
    }
    public static string RecordText(IEnumerable<Appearance> items) {
        int won = 0, drawn = 0, lost = 0;
        foreach (Appearance item in items) { if (item.Letter == "W") won++; else if (item.Letter == "D") drawn++; else lost++; }
        return won + "-" + drawn + "-" + lost;
    }
    public static int[] Ranks(Fraction[] values) => values.Select(value => 1 + values.Count(other => other.CompareTo(value) > 0)).ToArray();
    public static string Csv(params object[] fields) => string.Join(",", fields.Select(field => field.ToString()));
    public static string ModelNames(List<int> ranking) => string.Join(" ", ranking.Select(index => PredictionModels[index]));
    public static List<string> Parts(List<List<string>> parts) {
        List<string> lines = new();
        foreach (List<string> part in parts) { if (lines.Count > 0) lines.Add(""); lines.AddRange(part); }
        return lines;
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        LeagueAnalysis analysis = new(Season.Load());
        Directory.CreateDirectory("output");
        foreach (var pair in analysis.OutputFiles()) Report.Write(pair.Key, pair.Value);
    }
}
