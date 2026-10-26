#include "ratings.hpp"
#include <filesystem>

static const Lines ratingModels{"elo", "colley", "massey", "bt", "od", "winpct"};
static const Lines comparisonModels{"standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag"};
static const Lines predictionModels{"base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble"};
static const Lines linkModels{"colley", "massey", "od", "winpct"};
static std::string join(const Lines& values, const std::string& separator) { std::string result; for (std::size_t i = 0; i < values.size(); ++i) { if (i) result += separator; result += values[i]; } return result; }
static void paragraph(Lines& target, const Lines& source) { if (!target.empty()) target.push_back(""); target.insert(target.end(), source.begin(), source.end()); }
static double mean(const Values& values) { double sum = 0; for (double value : values) sum += value; return sum / values.size(); }
static Integers ranks(const Fractions& values) { Integers result; for (Fraction value : values) { int rank = 1; for (Fraction other : values) rank += other > value; result.push_back(rank); } return result; }
static Fractions rounded(const Values& values, int places) { Fractions result; for (double value : values) result.emplace_back(decimalValue(value, places)); return result; }
struct Record {
    int played = 0, won = 0, drawn = 0, lost = 0, scored = 0, conceded = 0;
    Integer points = 0;
    void add(int first, int second, const Settings& s) { ++played; scored += first; conceded += second; if (first > second) { ++won; points += s.winPoints; } else if (first == second) { ++drawn; points += s.drawPoints; } else ++lost; }
    int difference() const { return scored - conceded; }
    Fraction percentage() const { return {2 * won + drawn, 2 * played}; }
};
static std::vector<Record> records(int count, const Matches& matches, const Settings& s) { std::vector<Record> result(count); for (const Match& match : matches) { result[match.home].add(match.homeScore, match.awayScore, s); result[match.away].add(match.awayScore, match.homeScore, s); } return result; }
struct Standings {
    std::vector<Record> record;
    std::vector<Integer> headPoints;
    Integers headDifference, order, positions;
    Standings(const std::vector<Team>& teams, const Matches& matches, const Settings& s) : record(records(static_cast<int>(teams.size()), matches, s)), headPoints(teams.size()), headDifference(teams.size()), positions(teams.size()) {
        std::map<Integer, Integers> groups;
        for (int i = 0; i < static_cast<int>(teams.size()); ++i) { groups[record[i].points].push_back(i); order.push_back(i); }
        for (const std::pair<const Integer, Integers>& group : groups) {
            std::set<int> members(group.second.begin(), group.second.end()); Matches inner;
            for (const Match& match : matches) if (members.count(match.home) && members.count(match.away)) inner.push_back(match);
            std::vector<Record> table = records(static_cast<int>(teams.size()), inner, s);
            for (int team : group.second) { headPoints[team] = table[team].points; headDifference[team] = table[team].difference(); }
        }
        std::sort(order.begin(), order.end(), [&](int a, int b) { return std::make_tuple(-record[a].points, -headPoints[a], -headDifference[a], -record[a].difference(), -record[a].scored, teams[a].id) < std::make_tuple(-record[b].points, -headPoints[b], -headDifference[b], -record[b].difference(), -record[b].scored, teams[b].id); });
        for (int i = 0; i < static_cast<int>(order.size()); ++i) positions[order[i]] = i + 1;
    }
};
struct Appearance { int match, opponent, scored, conceded; bool home; char letter; };
using Appearances = std::vector<Appearance>;
static std::string recordText(const Appearances& appearances) { int won = 0, drawn = 0, lost = 0; for (const Appearance& item : appearances) { won += item.letter == 'W'; drawn += item.letter == 'D'; lost += item.letter == 'L'; } return text(won, '-', drawn, '-', lost); }
struct Streak { int length = 0, first = 0, last = 0; };
static Streak longestStreak(const Appearances& appearances, const Matches& matches, bool unbeaten) {
    Streak best; int length = 0, start = 0;
    for (int index = 0; index < static_cast<int>(appearances.size()); ++index) { char letter = appearances[index].letter; if (letter != 'W' && !(unbeaten && letter == 'D')) { length = 0; continue; } if (!length) start = index; ++length; if (length > best.length) best = {length, matches[appearances[start].match].round, matches[appearances[index].match].round}; }
    return best;
}
struct Fit {
    EloRun elo;
    Values colley, massey, strengths;
    double homeAdvantage, homeFactor;
    OffenseDefense od;
    Fractions percentages;
    Fit(int count, const Matches& matches, const Settings& s) : elo(runElo(count, matches, s.eloK, s.eloHome, s.eloInitial)), colley(colleyRatings(count, matches)), od(offenseDefense(count, matches, s.odIterations)) {
        std::pair<Values, double> m = masseyRatings(count, matches), b = bradleyTerry(count, matches, s.btIterations);
        massey = std::move(m.first); homeAdvantage = m.second; strengths = std::move(b.first); homeFactor = b.second;
        for (const Record& record : records(count, matches, s)) percentages.push_back(record.percentage());
    }
    double feature(int model, const Match& match) const { if (model == 0) return colley[match.home] - colley[match.away]; if (model == 1) return massey[match.home] - massey[match.away]; if (model == 2) return std::log(od.ratings[match.home]) - std::log(od.ratings[match.away]); return percentages[match.home].real() - percentages[match.away].real(); }
};
struct Prediction { Match match; std::array<double, 8> probabilities, losses, briers; std::array<Fraction, 8> scores; double error; };
struct ValidationRound {
    int round, trainingCount;
    Fit fit;
    double base;
    std::array<std::pair<double, double>, 4> links;
    std::vector<Prediction> predictions;
    ValidationRound(int round, int count, const Matches& matches, const Settings& s) : round(round), trainingCount(0), fit(count, matchesBefore(matches, round), s) {
        Matches training = matchesBefore(matches, round); trainingCount = static_cast<int>(training.size()); Values results;
        for (const Match& match : training) results.push_back(match.result());
        base = mean(results);
        for (int model = 0; model < 4; ++model) { Values features; for (const Match& match : training) features.push_back(fit.feature(model, match)); links[model] = fitLink(features, results, s.linkIterations); }
        for (const Match& match : matches) if (match.round == round) {
            Prediction prediction; prediction.match = match; prediction.probabilities[0] = base;
            prediction.probabilities[1] = expectedScore(fit.elo.ratings[match.home], fit.elo.ratings[match.away], s.eloHome);
            const int locations[]{2, 3, 5, 6};
            for (int model = 0; model < 4; ++model) prediction.probabilities[locations[model]] = sigma(links[model].first + links[model].second * fit.feature(model, match));
            double home = fit.homeFactor * fit.strengths[match.home]; prediction.probabilities[4] = home / (home + fit.strengths[match.away]);
            double ensemble = 0; for (int model = 1; model <= 6; ++model) ensemble += prediction.probabilities[model]; prediction.probabilities[7] = ensemble / 6;
            for (int model = 0; model < 8; ++model) { double p = prediction.probabilities[model]; prediction.losses[model] = logLoss(p, match.result()); prediction.briers[model] = brierScore(p, match.result()); prediction.scores[model] = correctness(p, match.doubledResult()); }
            prediction.error = match.margin() - (fit.massey[match.home] - fit.massey[match.away] + fit.homeAdvantage); predictions.push_back(prediction);
        }
    }
};
struct Projection {
    Standings current;
    Values ratings;
    Matches remaining;
    std::vector<Integer> totalPoints;
    Integers titles, tops, bottoms, order, positions;
    Projection(const Season& season) : current(season.teams, matchesBefore(season.matches, season.settings.holdoutRound), season.settings), ratings(runElo(static_cast<int>(season.teams.size()), matchesBefore(season.matches, season.settings.holdoutRound), season.settings.eloK, season.settings.eloHome, season.settings.eloInitial).ratings), totalPoints(season.teams.size()), titles(season.teams.size()), tops(season.teams.size()), bottoms(season.teams.size()), positions(season.teams.size()) {
        const Settings& s = season.settings; int count = static_cast<int>(season.teams.size());
        for (const Match& match : season.matches) if (match.round >= s.holdoutRound) remaining.push_back(match);
        Values probabilities; for (const Match& match : remaining) probabilities.push_back(expectedScore(ratings[match.home], ratings[match.away], s.eloHome));
        Integer state = s.seed;
        for (int simulation = 0; simulation < s.simulations; ++simulation) {
            std::vector<Integer> points; for (const Record& record : current.record) points.push_back(record.points);
            for (std::size_t i = 0; i < remaining.size(); ++i) { state = 48271 * state % 2147483647; double uniform = static_cast<double>(state) / 2147483647; points[uniform < probabilities[i] ? remaining[i].home : remaining[i].away] += s.winPoints; }
            Integers places(count); std::iota(places.begin(), places.end(), 0);
            std::sort(places.begin(), places.end(), [&](int a, int b) { return points[a] != points[b] ? points[a] > points[b] : current.positions[a] < current.positions[b]; });
            for (int i = 0; i < count; ++i) { int team = places[i], place = i + 1; totalPoints[team] += points[team]; titles[team] += place == 1; tops[team] += place <= s.top; bottoms[team] += place >= count - s.bottom + 1; }
        }
        order.resize(count); std::iota(order.begin(), order.end(), 0);
        std::sort(order.begin(), order.end(), [&](int a, int b) { return totalPoints[a] != totalPoints[b] ? totalPoints[a] > totalPoints[b] : current.positions[a] < current.positions[b]; });
        for (int i = 0; i < count; ++i) positions[order[i]] = i + 1;
    }
    double opponentStrength(int team) const { Values values; for (const Match& match : remaining) { if (match.home == team) values.push_back(ratings[match.away]); else if (match.away == team) values.push_back(ratings[match.home]); } return mean(values); }
};
class Analysis {
    const Season& season;
    const Settings& s;
    int count, finalRound;
    Standings final;
    Fit fit;
    Projection projection;
    std::vector<Appearances> appearances;
    std::vector<Streak> winStreaks, unbeatenStreaks;
    std::vector<Standings> tables;
    Fractions sos, sos2, rpi;
    Values pythag, luck;
    std::array<Fractions, 9> comparisons;
    std::array<Integers, 6> modelRanks;
    std::vector<ValidationRound> validation;
    std::vector<Prediction> predictions;
    std::array<double, 8> losses{}, briers{}, skills{};
    std::array<Fraction, 8> accuracies;
    Integers lossRanking, brierRanking, accuracyRanking;
    const std::string& code(int team) const { return season.teams[team].id; }
    Fraction opponentAverage(int team, const Fractions& values) const { Fraction sum; for (const Appearance& item : appearances[team]) sum = sum + values[item.opponent]; return sum / static_cast<Integer>(appearances[team].size()); }
    Lines standingsLines() const {
        Lines lines{"pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck"};
        for (int team : final.order) {
            const Record& record = final.record[team]; const Appearances& items = appearances[team]; Appearances home, away, close; std::string form; int streak = 0;
            for (const Appearance& item : items) { (item.home ? home : away).push_back(item); if (std::abs(item.scored - item.conceded) <= s.closeMargin) close.push_back(item); }
            for (int i = static_cast<int>(items.size()) - s.formLength; i < static_cast<int>(items.size()); ++i) form += items[i].letter;
            for (int i = static_cast<int>(items.size()) - 1; i >= 0 && items[i].letter == items.back().letter; --i) ++streak;
            add(lines, final.positions[team], ',', code(team), ',', season.teams[team].name, ',', record.played, ',', record.won, ',', record.drawn, ',', record.lost, ',', record.scored, ',', record.conceded, ',', record.difference(), ',', record.points, ',', recordText(home), ',', recordText(away), ',', form, ',', items.back().letter, streak, ',', recordText(close), ',', winStreaks[team].length, ',', unbeatenStreaks[team].length, ',', fractionText(fit.percentages[team]), ',', fixed(sos[team]), ',', fixed(sos2[team]), ',', fixed(rpi[team]), ',', fixed(pythag[team]), ',', fixed(luck[team]));
        }
        return lines;
    }
    Lines ratingsLines() const {
        Lines lines{"team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank"}; Integers totals(count), order(count); std::iota(order.begin(), order.end(), 0);
        for (int team = 0; team < count; ++team) for (const Integers& rank : modelRanks) totals[team] += rank[team];
        std::sort(order.begin(), order.end(), [&](int a, int b) { return totals[a] != totals[b] ? totals[a] < totals[b] : code(a) < code(b); });
        for (int team : order) {
            int best = count, worst = 0; for (const Integers& rank : modelRanks) { best = std::min(best, rank[team]); worst = std::max(worst, rank[team]); }
            add(lines, code(team), ',', fixed(fit.elo.ratings[team], 2), ',', modelRanks[0][team], ',', fixed(fit.colley[team]), ',', modelRanks[1][team], ',', fixed(fit.massey[team]), ',', modelRanks[2][team], ',', fixed(fit.strengths[team]), ',', modelRanks[3][team], ',', fixed(fit.od.offense[team], 2), ',', fixed(fit.od.defense[team]), ',', fixed(fit.od.ratings[team], 2), ',', modelRanks[4][team], ',', fixed(fit.percentages[team]), ',', modelRanks[5][team], ',', totals[team], ',', best, ',', worst);
        }
        return lines;
    }
    Lines historyLines() const {
        Lines lines{"round,team,elo,change,elo_rank,points,position"}; Values previous(count, s.eloInitial);
        for (int round = 0; round < finalRound; ++round) { const Values& values = fit.elo.rounds[round]; Integers rank = ranks(rounded(values, 2)); for (int team = 0; team < count; ++team) add(lines, round + 1, ',', code(team), ',', fixed(values[team], 2), ',', fixed(values[team] - previous[team], 2), ',', rank[team], ',', tables[round].record[team].points, ',', tables[round].positions[team]); previous = values; }
        return lines;
    }
    Lines seasonLines() const {
        int home = 0, draws = 0, away = 0, doubled = 0;
        for (const Match& match : season.matches) { home += match.doubledResult() == 2; draws += match.doubledResult() == 1; away += match.doubledResult() == 0; doubled += match.doubledResult(); }
        Lines lines{text("season teams ", count, " matches ", season.matches.size(), " rounds ", finalRound), text("home won ", home, " drawn ", draws, " lost ", away, " rate ", fractionWithReal({doubled, 2 * static_cast<Integer>(season.matches.size())})), text("massey_home_advantage ", fixed(fit.homeAdvantage)), text("bt_home_factor ", fixed(fit.homeFactor))};
        Integers upsets; for (int i = 0; i < static_cast<int>(season.matches.size()); ++i) if (season.matches[i].margin()) upsets.push_back(i);
        Values winnerExpected(season.matches.size()); for (int i : upsets) winnerExpected[i] = season.matches[i].margin() > 0 ? fit.elo.expected[i] : 1 - fit.elo.expected[i];
        std::stable_sort(upsets.begin(), upsets.end(), [&](int a, int b) { return decimalValue(winnerExpected[a], 4) < decimalValue(winnerExpected[b], 4); });
        Lines part{text("upsets top ", s.upsets)};
        for (std::size_t k = 0; k < upsets.size() && static_cast<Integer>(k) < s.upsets; ++k) { int i = upsets[k]; const Match& match = season.matches[i]; bool won = match.margin() > 0; add(part, "round ", match.round, ' ', code(won ? match.home : match.away), " beat ", code(won ? match.away : match.home), ' ', won ? match.homeScore : match.awayScore, '-', won ? match.awayScore : match.homeScore, ' ', won ? "home" : "away", " expected ", fixed(winnerExpected[i]), " gain ", fixed(std::abs(fit.elo.changes[i]), 2)); }
        paragraph(lines, part); part = {"tiebreaks"};
        for (int begin = 0; begin < count;) { int end = begin + 1; while (end < count && final.record[final.order[end]].points == final.record[final.order[begin]].points) ++end; if (end - begin > 1) { Lines ids, points, differences; for (int i = begin; i < end; ++i) { int team = final.order[i]; ids.push_back(code(team)); points.push_back(text(final.headPoints[team])); differences.push_back(text(final.headDifference[team])); } add(part, "points ", final.record[final.order[begin]].points, " order ", join(ids, " "), " h2h_points ", join(points, " "), " h2h_diff ", join(differences, " ")); } begin = end; }
        if (part.size() == 1) part.push_back("none"); paragraph(lines, part); part = {"leaders"}; int previous = -1, changes = 0;
        for (int round = 0; round < finalRound; ++round) { int leader = tables[round].order.front(); if (leader != previous) { ++changes; add(part, "round ", round + 1, ' ', code(leader), " points ", tables[round].record[leader].points); } previous = leader; }
        add(part, "lead_changes ", changes - 1); paragraph(lines, part); part.clear();
        for (int kind = 0; kind < 2; ++kind) { const std::vector<Streak>& streaks = kind ? unbeatenStreaks : winStreaks; int longest = 0; for (const Streak& streak : streaks) longest = std::max(longest, streak.length); for (int team = 0; team < count; ++team) if (streaks[team].length == longest) add(part, kind ? "longest_unbeaten_streak " : "longest_win_streak ", code(team), " length ", longest, " rounds ", streaks[team].first, '-', streaks[team].last); }
        paragraph(lines, part); part = {text("crosstable top ", s.top)}; Lines ids; for (int k = 0; k < s.top; ++k) ids.push_back(code(final.order[k])); part.push_back("team " + join(ids, " "));
        for (int a = 0; a < s.top; ++a) { Lines row{code(final.order[a])}; for (int b = 0; b < s.top; ++b) { if (a == b) row.push_back("-"); else { Appearances meetings; for (const Appearance& item : appearances[final.order[a]]) if (item.opponent == final.order[b]) meetings.push_back(item); row.push_back(recordText(meetings)); } } part.push_back(join(row, " ")); }
        paragraph(lines, part); part = {"trajectories"};
        for (int team = 0; team < count; ++team) { int peak = 0, low = 0, best = 0, worst = 0; for (int round = 1; round < finalRound; ++round) { Integer value = decimalValue(fit.elo.rounds[round][team], 2); if (value > decimalValue(fit.elo.rounds[peak][team], 2)) peak = round; if (value < decimalValue(fit.elo.rounds[low][team], 2)) low = round; if (tables[round].positions[team] < tables[best].positions[team]) best = round; if (tables[round].positions[team] > tables[worst].positions[team]) worst = round; } add(part, code(team), " elo_peak ", fixed(fit.elo.rounds[peak][team], 2), " round ", peak + 1, " elo_low ", fixed(fit.elo.rounds[low][team], 2), " round ", low + 1, " best_position ", tables[best].positions[team], " round ", best + 1, " worst_position ", tables[worst].positions[team], " round ", worst + 1); }
        paragraph(lines, part);
        for (int kind = 0; kind < 2; ++kind) { part = {kind ? "spearman" : "kendall", "model " + join(comparisonModels, " ")}; for (int a = 0; a < 9; ++a) { Lines row{comparisonModels[a]}; for (int b = 0; b < 9; ++b) row.push_back(fractionText(kind ? spearmanRho(comparisons[a], comparisons[b]) : kendallTau(comparisons[a], comparisons[b]))); part.push_back(join(row, " ")); } paragraph(lines, part); }
        int mostA = 0, mostB = 1, leastA = 0, leastB = 1; Fraction most = kendallTau(comparisons[0], comparisons[1]), least = most;
        for (int a = 0; a < 9; ++a) for (int b = a + 1; b < 9; ++b) { Fraction value = kendallTau(comparisons[a], comparisons[b]); if (value > most) { most = value; mostA = a; mostB = b; } if (value < least) { least = value; leastA = a; leastB = b; } }
        paragraph(lines, {text("most_similar ", comparisonModels[mostA], ' ', comparisonModels[mostB], " tau ", fractionWithReal(most)), text("least_similar ", comparisonModels[leastA], ' ', comparisonModels[leastB], " tau ", fractionWithReal(least))}); return lines;
    }
    Fraction projectionTau() const { Fractions first, second; for (int team = 0; team < count; ++team) { first.emplace_back(-projection.positions[team]); second.emplace_back(-final.positions[team]); } return kendallTau(first, second); }
    Lines predictionLines() const {
        Lines lines{"round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble"};
        for (const Prediction& prediction : predictions) { const Match& match = prediction.match; Lines row{text(match.round), code(match.home), code(match.away), text(match.homeScore), text(match.awayScore), match.doubledResult() == 2 ? "H" : match.doubledResult() == 1 ? "D" : "A"}; for (double probability : prediction.probabilities) row.push_back(fixed(probability)); lines.push_back(join(row, ",")); }
        return lines;
    }
    Lines evaluationLines() const {
        Lines lines{text("holdout rounds ", s.holdoutRound, '-', finalRound, " matches ", predictions.size())}, part{"links"};
        for (const ValidationRound& round : validation) { std::string line = text("round ", round.round, " train ", round.trainingCount, " base ", fixed(round.base), " bt_home ", fixed(round.fit.homeFactor)); for (int model = 0; model < 4; ++model) line += text(' ', linkModels[model], ' ', fixed(round.links[model].first), ' ', fixed(round.links[model].second)); part.push_back(line); }
        paragraph(lines, part); part = {"scores", "model log_loss brier skill accuracy"};
        for (int model = 0; model < 8; ++model) add(part, predictionModels[model], ' ', fixed(losses[model]), ' ', fixed(briers[model]), ' ', fixed(skills[model]), ' ', fractionWithReal(accuracies[model]));
        const std::array<Integers, 3> rankings{lossRanking, brierRanking, accuracyRanking}; const Lines labels{"ranking_log_loss", "ranking_brier", "ranking_accuracy"};
        for (int kind = 0; kind < 3; ++kind) { Lines names; for (int model : rankings[kind]) names.push_back(predictionModels[model]); part.push_back(labels[kind] + ' ' + join(names, " ")); }
        paragraph(lines, part); int reference = lossRanking.front(); part = {"paired_log_loss reference " + predictionModels[reference]};
        for (int model = 0; model < 8; ++model) if (model != reference) { Values deltas; for (const Prediction& prediction : predictions) deltas.push_back(prediction.losses[model] - prediction.losses[reference]); double average = mean(deltas), sum = 0; for (double delta : deltas) sum += (delta - average) * (delta - average); double deviation = std::sqrt(sum / (deltas.size() - 1)), statistic = average / (deviation / std::sqrt(static_cast<double>(deltas.size()))); add(part, predictionModels[model], " mean_diff ", fixed(average), " sd ", fixed(deviation), " t ", fixed(statistic, 2)); }
        paragraph(lines, part); Values absolute, squares, errors;
        for (const Prediction& prediction : predictions) { absolute.push_back(std::abs(prediction.error)); squares.push_back(prediction.error * prediction.error); errors.push_back(prediction.error); }
        paragraph(lines, {text("massey_margin mae ", fixed(mean(absolute)), " rmse ", fixed(std::sqrt(mean(squares))), " bias ", fixed(mean(errors)))});
        part = {"round_log_loss", "round " + join(predictionModels, " ")};
        for (const ValidationRound& round : validation) { Lines row{text(round.round)}; for (int model = 0; model < 8; ++model) { Values values; for (const Prediction& prediction : round.predictions) values.push_back(prediction.losses[model]); row.push_back(fixed(mean(values))); } part.push_back(join(row, " ")); }
        paragraph(lines, part); part = {text("calibration bins ", s.bins)};
        for (int model = 0; model < 8; ++model) for (int bin = 0; bin < s.bins; ++bin) {
            Values probabilities; int doubled = 0;
            for (const Prediction& prediction : predictions) if (std::min(static_cast<int>(std::floor(s.bins * prediction.probabilities[model])), s.bins - 1) == bin) { probabilities.push_back(prediction.probabilities[model]); doubled += prediction.match.doubledResult(); }
            add(part, predictionModels[model], " bin ", bin + 1, " count ", probabilities.size(), " predicted ", probabilities.empty() ? "-" : fixed(mean(probabilities)), " observed ", probabilities.empty() ? "-" : fractionText({doubled, 2 * static_cast<Integer>(probabilities.size())}));
        }
        paragraph(lines, part); Lines header{"k"}; for (Integer home : s.gridHome) header.push_back(text('h', home)); part = {"elo_grid", join(header, " ")}; bool haveBest = false; Integer bestK = 0, bestHome = 0; double bestLoss = 0;
        for (Integer coefficient : s.gridK) {
            Lines row{text(coefficient)};
            for (Integer home : s.gridHome) {
                EloRun run = runElo(count, season.matches, coefficient, home, s.eloInitial); Values values;
                for (std::size_t i = 0; i < season.matches.size(); ++i) if (season.matches[i].round >= s.holdoutRound) values.push_back(logLoss(run.expected[i], season.matches[i].result()));
                double loss = mean(values); row.push_back(fixed(loss));
                if (!haveBest || decimalValue(loss, 4) < decimalValue(bestLoss, 4)) { haveBest = true; bestK = coefficient; bestHome = home; bestLoss = loss; }
            }
            part.push_back(join(row, " "));
        }
        add(part, "best k ", bestK, " home ", bestHome, " log_loss ", fixed(bestLoss)); paragraph(lines, part);
        paragraph(lines, {text("projection simulations ", s.simulations, " kendall ", fractionWithReal(projectionTau()))}); return lines;
    }
    Lines projectionLines() const {
        Lines lines{"projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position"};
        for (int team : projection.order) add(lines, projection.positions[team], ',', code(team), ',', projection.current.record[team].points, ',', projection.current.positions[team], ',', fixed(projection.opponentStrength(team), 2), ',', fixed(Fraction(projection.totalPoints[team], s.simulations)), ',', fixed(Fraction(projection.titles[team], s.simulations)), ',', fixed(Fraction(projection.tops[team], s.simulations)), ',', fixed(Fraction(projection.bottoms[team], s.simulations)), ',', final.record[team].points, ',', final.positions[team]);
        return lines;
    }
public:
    explicit Analysis(const Season& season) : season(season), s(season.settings), count(static_cast<int>(season.teams.size())), finalRound(season.matches.back().round), final(season.teams, season.matches, s), fit(count, season.matches, s), projection(season), appearances(count), sos(count), sos2(count), rpi(count), pythag(count), luck(count) {
        for (int i = 0; i < static_cast<int>(season.matches.size()); ++i) {
            const Match& match = season.matches[i];
            appearances[match.home].push_back({i, match.away, match.homeScore, match.awayScore, true, match.margin() > 0 ? 'W' : match.margin() == 0 ? 'D' : 'L'});
            appearances[match.away].push_back({i, match.home, match.awayScore, match.homeScore, false, match.margin() < 0 ? 'W' : match.margin() == 0 ? 'D' : 'L'});
        }
        for (int round = 1; round <= finalRound; ++round) tables.emplace_back(season.teams, matchesBefore(season.matches, round + 1), s);
        for (int team = 0; team < count; ++team) { winStreaks.push_back(longestStreak(appearances[team], season.matches, false)); unbeatenStreaks.push_back(longestStreak(appearances[team], season.matches, true)); sos[team] = opponentAverage(team, fit.percentages); }
        for (int team = 0; team < count; ++team) sos2[team] = opponentAverage(team, sos);
        for (int team = 0; team < count; ++team) { rpi[team] = (fit.percentages[team] + sos[team] * 2 + sos2[team]) / 4; const Record& record = final.record[team]; pythag[team] = 1 / (1 + std::pow(static_cast<double>(record.conceded) / record.scored, s.exponent)); luck[team] = fit.percentages[team].real() - pythag[team]; comparisons[0].emplace_back(-final.positions[team]); }
        comparisons[1] = rounded(fit.elo.ratings, 2); comparisons[2] = rounded(fit.colley, 4); comparisons[3] = rounded(fit.massey, 4); comparisons[4] = rounded(fit.strengths, 4); comparisons[5] = rounded(fit.od.ratings, 2); comparisons[6] = fit.percentages; comparisons[7] = rpi; comparisons[8] = rounded(pythag, 4);
        for (int model = 0; model < 6; ++model) modelRanks[model] = ranks(comparisons[model + 1]);
        for (int round = s.holdoutRound; round <= finalRound; ++round) { validation.emplace_back(round, count, season.matches, s); predictions.insert(predictions.end(), validation.back().predictions.begin(), validation.back().predictions.end()); }
        for (int model = 0; model < 8; ++model) { double loss = 0, brier = 0; Fraction correct; for (const Prediction& prediction : predictions) { loss += prediction.losses[model]; brier += prediction.briers[model]; correct = correct + prediction.scores[model]; } losses[model] = loss / predictions.size(); briers[model] = brier / predictions.size(); accuracies[model] = correct / static_cast<Integer>(predictions.size()); }
        for (int model = 0; model < 8; ++model) { skills[model] = 1 - briers[model] / briers[0]; lossRanking.push_back(model); brierRanking.push_back(model); accuracyRanking.push_back(model); }
        std::stable_sort(lossRanking.begin(), lossRanking.end(), [&](int a, int b) { return decimalValue(losses[a], 4) < decimalValue(losses[b], 4); });
        std::stable_sort(brierRanking.begin(), brierRanking.end(), [&](int a, int b) { return decimalValue(briers[a], 4) < decimalValue(briers[b], 4); });
        std::stable_sort(accuracyRanking.begin(), accuracyRanking.end(), [&](int a, int b) { return accuracies[a] > accuracies[b]; });
    }
    void write() const { std::filesystem::create_directories("output"); writeLines("standings.csv", standingsLines()); writeLines("ratings.csv", ratingsLines()); writeLines("history.csv", historyLines()); writeLines("season.txt", seasonLines()); writeLines("predictions.csv", predictionLines()); writeLines("evaluation.txt", evaluationLines()); writeLines("projection.csv", projectionLines()); }
};
int main() { Season season = readSeason(); Analysis analysis(season); analysis.write(); }
