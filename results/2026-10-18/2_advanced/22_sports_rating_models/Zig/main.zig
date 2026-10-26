const std = @import("std");
const s = @import("season.zig");
const r = @import("report.zig");
const elo = @import("elo.zig");
const linear = @import("linear_models.zig");
const iterative = @import("iterative_models.zig");
const evaluation = @import("evaluation.zig");
const Fraction = r.Fraction;
const Comparison = r.Comparison;
const comparison_names = [_][]const u8{ "standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag" };
const prediction_names = [_][]const u8{ "base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble" };
const link_names = [_][]const u8{ "colley", "massey", "od", "winpct" };
const link_predictions = [_]usize{ 2, 3, 5, 6 };

const Record = struct {
    played: usize = 0,
    won: usize = 0,
    drawn: usize = 0,
    lost: usize = 0,
    scored: i64 = 0,
    conceded: i64 = 0,
    points: i64 = 0,

    fn add(self: *Record, scored: i64, conceded: i64, settings: s.Settings) void {
        self.played += 1;
        self.scored += scored;
        self.conceded += conceded;
        if (scored > conceded) {
            self.won += 1;
            self.points += settings.win_points;
        } else if (scored == conceded) {
            self.drawn += 1;
            self.points += settings.draw_points;
        } else self.lost += 1;
    }
    fn winPercentage(self: Record) Fraction { return Fraction.init(2 * r.n(self.won) + r.n(self.drawn), 2 * r.n(self.played)); }
};
const Standings = struct {
    records: [30]Record = @splat(.{}),
    h2h_points: [30]i64 = @splat(0),
    h2h_difference: [30]i64 = @splat(0),
    order: [30]usize = @splat(0),
    positions: [30]usize = @splat(0),

    fn before(self: *const Standings, first: usize, second: usize) bool {
        const a = self.records[first];
        const b = self.records[second];
        if (a.points != b.points) return a.points > b.points;
        if (self.h2h_points[first] != self.h2h_points[second]) return self.h2h_points[first] > self.h2h_points[second];
        if (self.h2h_difference[first] != self.h2h_difference[second]) return self.h2h_difference[first] > self.h2h_difference[second];
        if (a.scored - a.conceded != b.scored - b.conceded) return a.scored - a.conceded > b.scored - b.conceded;
        if (a.scored != b.scored) return a.scored > b.scored;
        return first < second;
    }
};

fn makeStandings(season: *const s.Season, count: usize) Standings {
    var result: Standings = .{};
    for (season.matches[0..count]) |match| {
        result.records[match.home].add(match.home_score, match.away_score, season.settings);
        result.records[match.away].add(match.away_score, match.home_score, season.settings);
    }
    for (season.matches[0..count]) |match| {
        if (result.records[match.home].points != result.records[match.away].points) continue;
        result.h2h_difference[match.home] += match.margin;
        result.h2h_difference[match.away] -= match.margin;
        if (match.margin > 0) result.h2h_points[match.home] += season.settings.win_points else if (match.margin < 0) result.h2h_points[match.away] += season.settings.win_points else {
            result.h2h_points[match.home] += season.settings.draw_points;
            result.h2h_points[match.away] += season.settings.draw_points;
        }
    }
    for (0..season.teams.len) |team| {
        var position = team;
        while (position > 0 and result.before(team, result.order[position - 1])) : (position -= 1) result.order[position] = result.order[position - 1];
        result.order[position] = team;
    }
    for (result.order[0..season.teams.len], 0..) |team, i| result.positions[team] = i + 1;
    return result;
}

const ModelFit = struct {
    elo_run: elo.Run = .{},
    colley: [30]f64 = @splat(0),
    massey: [30]f64 = @splat(0),
    strengths: [30]f64 = @splat(0),
    offense: [30]f64 = @splat(0),
    defense: [30]f64 = @splat(0),
    od: [30]f64 = @splat(0),
    home_advantage: f64 = 0,
    home_factor: f64 = 0,
    win_percentages: [30]Fraction = @splat(.{}),

    fn feature(self: *const ModelFit, model: usize, match: s.Match) f64 {
        const home = match.home;
        const away = match.away;
        return switch (model) {
            0 => self.colley[home] - self.colley[away],
            1 => self.massey[home] - self.massey[away],
            2 => @log(self.od[home]) - @log(self.od[away]),
            else => self.win_percentages[home].real() - self.win_percentages[away].real(),
        };
    }
};

fn makeFit(season: *const s.Season, count: usize) ModelFit {
    const n = season.teams.len;
    const matches = season.matches[0..count];
    const settings = season.settings;
    var fit: ModelFit = .{};
    fit.elo_run = elo.run(n, matches, settings.elo_k, settings.elo_home, settings.elo_initial);
    fit.colley = linear.colley(n, matches);
    const massey = linear.massey(n, matches);
    fit.massey = massey.ratings;
    fit.home_advantage = massey.advantage;
    const bt = iterative.bradleyTerry(n, matches, settings.bt_iterations);
    fit.strengths = bt.strengths;
    fit.home_factor = bt.theta;
    const od = iterative.offenseDefense(n, matches, settings.od_iterations);
    fit.offense = od.offense;
    fit.defense = od.defense;
    fit.od = od.ratings;
    const table = makeStandings(season, count);
    for (0..n) |i| fit.win_percentages[i] = table.records[i].winPercentage();
    return fit;
}

const Appearance = struct { match: *const s.Match, opponent: usize, scored: i64, conceded: i64, home: bool, letter: u8 };
const Streak = struct { length: usize = 0, first: usize = 0, last: usize = 0 };

fn longestStreak(items: []const Appearance, unbeaten: bool) Streak {
    var best: Streak = .{};
    var start: usize = 0;
    var length: usize = 0;
    for (items, 0..) |item, i| {
        if (item.letter == 'L' or (!unbeaten and item.letter != 'W')) { length = 0; continue; }
        if (length == 0) start = i;
        length += 1;
        if (length > best.length) best = .{ .length = length, .first = items[start].match.round, .last = item.match.round };
    }
    return best;
}

const Prediction = struct {
    match: *const s.Match = undefined,
    probabilities: [8]f64 = @splat(0),
    losses: [8]f64 = @splat(0),
    briers: [8]f64 = @splat(0),
    scores: [8]i64 = @splat(0),
    margin_error: f64 = 0,
};
const ValidationRound = struct {
    number: usize = 0,
    training: usize = 0,
    start: usize = 0,
    count: usize = 0,
    base: f64 = 0,
    home_factor: f64 = 0,
    links: [4]evaluation.Link = @splat(.{}),
};
const Projection = struct {
    current: Standings = .{},
    ratings: [30]f64 = @splat(0),
    opponent_strength: [30]f64 = @splat(0),
    total_points: [30]i64 = @splat(0),
    titles: [30]i64 = @splat(0),
    tops: [30]i64 = @splat(0),
    bottoms: [30]i64 = @splat(0),
    order: [30]usize = @splat(0),
    ranks: [30]usize = @splat(0),
};

fn pointsOrder(points: []const i64, positions: []const usize) [30]usize {
    var order: [30]usize = @splat(0);
    for (0..points.len) |team| {
        var position = team;
        while (position > 0) {
            const previous = order[position - 1];
            if (points[team] < points[previous] or (points[team] == points[previous] and positions[team] > positions[previous])) break;
            order[position] = previous;
            position -= 1;
        }
        order[position] = team;
    }
    return order;
}

const Analysis = struct {
    season: *const s.Season,
    final: Standings = .{},
    round_tables: [40]Standings = @splat(.{}),
    appearances: [30][40]Appearance = undefined,
    appearance_count: [30]usize = @splat(0),
    wins: [30]Streak = @splat(.{}),
    unbeaten: [30]Streak = @splat(.{}),
    fit: ModelFit = .{},
    sos: [30]Fraction = @splat(.{}),
    sos2: [30]Fraction = @splat(.{}),
    rpi: [30]Fraction = @splat(.{}),
    pythag: [30]f64 = @splat(0),
    luck: [30]f64 = @splat(0),
    comparison: [9][30]Comparison = @splat(@splat(.{})),
    ranks: [6][30]usize = @splat(@splat(0)),
    totals: [30]usize = @splat(0),
    rounds: [40]ValidationRound = @splat(.{}),
    round_count: usize = 0,
    predictions: [600]Prediction = @splat(.{}),
    prediction_count: usize = 0,
    losses: [8]f64 = @splat(0),
    briers: [8]f64 = @splat(0),
    skills: [8]f64 = @splat(0),
    accuracies: [8]Fraction = @splat(.{}),
    rankings: [3][8]usize = @splat(@splat(0)),
    projection: Projection = .{},

    fn initialize(self: *Analysis) void {
        const season = self.season;
        self.final = makeStandings(season, season.matches.len);
        self.fit = makeFit(season, season.matches.len);
        for (0..season.rounds) |round| self.round_tables[round] = makeStandings(season, season.before(round + 2));
        for (0..season.teams.len) |team| {
            for (season.matches) |*match| {
                if (match.home != team and match.away != team) continue;
                const home = match.home == team;
                const scored = if (home) match.home_score else match.away_score;
                const conceded = if (home) match.away_score else match.home_score;
                const i = self.appearance_count[team];
                self.appearances[team][i] = .{ .match = match, .opponent = if (home) match.away else match.home, .scored = scored, .conceded = conceded, .home = home, .letter = if (scored > conceded) 'W' else if (scored == conceded) 'D' else 'L' };
                self.appearance_count[team] += 1;
            }
            const items = self.appearances[team][0..self.appearance_count[team]];
            self.wins[team] = longestStreak(items, false);
            self.unbeaten[team] = longestStreak(items, true);
        }
        self.indicators();
        self.validate();
        self.project();
    }

    fn opponentAverage(self: *const Analysis, team: usize, values: []const Fraction) Fraction {
        var total: Fraction = .{};
        for (self.appearances[team][0..self.appearance_count[team]]) |item| total = total.add(values[item.opponent]);
        return total.divide(r.n(self.appearance_count[team]));
    }

    fn indicators(self: *Analysis) void {
        const n = self.season.teams.len;
        for (0..n) |team| self.sos[team] = self.opponentAverage(team, self.fit.win_percentages[0..n]);
        for (0..n) |team| self.sos2[team] = self.opponentAverage(team, self.sos[0..n]);
        for (0..n) |team| {
            const weighted = self.fit.win_percentages[team].add(Fraction.init(2, 1).multiply(self.sos[team]));
            self.rpi[team] = weighted.add(self.sos2[team]).divide(4);
            const record = self.final.records[team];
            self.pythag[team] = 1 / (1 + std.math.pow(f64, r.f(record.conceded) / r.f(record.scored), self.season.settings.exponent));
            self.luck[team] = self.fit.win_percentages[team].real() - self.pythag[team];
            const values = [_]f64{ -r.f(self.final.positions[team]), r.decimalValue(self.fit.elo_run.ratings[team], 2), r.decimalValue(self.fit.colley[team], 4), r.decimalValue(self.fit.massey[team], 4), r.decimalValue(self.fit.strengths[team], 4), r.decimalValue(self.fit.od[team], 2), 0, 0, r.decimalValue(self.pythag[team], 4) };
            for (values, 0..) |value, model| self.comparison[model][team].value = value;
            self.comparison[6][team] = .{ .exact = true, .fraction = self.fit.win_percentages[team] };
            self.comparison[7][team] = .{ .exact = true, .fraction = self.rpi[team] };
        }
        for (0..6) |model| {
            for (0..n) |team| {
                var rank: usize = 1;
                for (0..n) |other| rank += @intFromBool(self.comparison[model + 1][other].compare(self.comparison[model + 1][team]) == .gt);
                self.ranks[model][team] = rank;
                self.totals[team] += rank;
            }
        }
    }

    fn validate(self: *Analysis) void {
        const season = self.season;
        for (season.settings.holdout_round..season.rounds + 1) |number| {
            const round = &self.rounds[self.round_count];
            self.round_count += 1;
            round.number = number;
            round.training = season.before(number);
            const fit = makeFit(season, round.training);
            round.home_factor = fit.home_factor;
            var result_sum: i64 = 0;
            for (season.matches[0..round.training]) |match| result_sum += match.y2;
            round.base = r.f(result_sum) / r.f(2 * round.training);
            for (0..4) |model| {
                var features: [600]f64 = undefined;
                for (season.matches[0..round.training], 0..) |match, i| features[i] = fit.feature(model, match);
                round.links[model] = evaluation.fitLink(features[0..round.training], season.matches[0..round.training], season.settings.link_iterations);
            }
            round.start = self.prediction_count;
            for (season.matches[round.training..season.before(number + 1)]) |*match| {
                const prediction = &self.predictions[self.prediction_count];
                self.prediction_count += 1;
                prediction.match = match;
                prediction.probabilities[0] = round.base;
                prediction.probabilities[1] = elo.expectedScore(fit.elo_run.ratings[match.home], fit.elo_run.ratings[match.away], r.f(season.settings.elo_home));
                for (0..4) |model| {
                    const link = round.links[model];
                    prediction.probabilities[link_predictions[model]] = evaluation.sigma(link.alpha + link.beta * fit.feature(model, match.*));
                }
                const home = fit.home_factor * fit.strengths[match.home];
                prediction.probabilities[4] = home / (home + fit.strengths[match.away]);
                var total: f64 = 0;
                for (prediction.probabilities[1..7]) |probability| total += probability;
                prediction.probabilities[7] = total / 6;
                prediction.margin_error = r.f(match.margin) - (fit.massey[match.home] - fit.massey[match.away] + fit.home_advantage);
                for (0..8) |model| {
                    const probability = prediction.probabilities[model];
                    prediction.losses[model] = evaluation.logLoss(probability, match.y2);
                    prediction.briers[model] = evaluation.brierScore(probability, match.y2);
                    prediction.scores[model] = evaluation.correctness(probability, match.y2);
                }
            }
            round.count = self.prediction_count - round.start;
        }
        for (0..8) |model| {
            var correct: i64 = 0;
            for (self.predictions[0..self.prediction_count]) |prediction| {
                self.losses[model] += prediction.losses[model];
                self.briers[model] += prediction.briers[model];
                correct += prediction.scores[model];
            }
            self.losses[model] /= r.f(self.prediction_count);
            self.briers[model] /= r.f(self.prediction_count);
            self.accuracies[model] = Fraction.init(correct, 2 * r.n(self.prediction_count));
        }
        for (0..8) |model| self.skills[model] = 1 - self.briers[model] / self.briers[0];
        for (0..3) |kind| {
            for (0..8) |model| {
                var position = model;
                while (position > 0) {
                    const previous = self.rankings[kind][position - 1];
                    const before = if (kind == 2) self.accuracies[model].compare(self.accuracies[previous]) == .gt else if (kind == 0) r.decimalValue(self.losses[model], 4) < r.decimalValue(self.losses[previous], 4) else r.decimalValue(self.briers[model], 4) < r.decimalValue(self.briers[previous], 4);
                    if (!before) break;
                    self.rankings[kind][position] = previous;
                    position -= 1;
                }
                self.rankings[kind][position] = model;
            }
        }
    }

    fn project(self: *Analysis) void {
        const season = self.season;
        const n = season.teams.len;
        const settings = season.settings;
        const projection = &self.projection;
        const current_count = season.before(settings.holdout_round);
        projection.current = makeStandings(season, current_count);
        const run = elo.run(n, season.matches[0..current_count], settings.elo_k, settings.elo_home, settings.elo_initial);
        projection.ratings = run.ratings;
        var probabilities: [600]f64 = undefined;
        for (season.matches[current_count..], current_count..) |match, i| probabilities[i] = elo.expectedScore(run.ratings[match.home], run.ratings[match.away], r.f(settings.elo_home));
        var random = settings.seed;
        for (0..settings.simulations) |_| {
            var points: [30]i64 = @splat(0);
            for (0..n) |team| points[team] = projection.current.records[team].points;
            for (season.matches[current_count..], current_count..) |match, i| {
                random = @mod(48271 * random, 2147483647);
                const uniform = r.f(random) / 2147483647;
                points[if (uniform < probabilities[i]) match.home else match.away] += settings.win_points;
            }
            const order = pointsOrder(points[0..n], projection.current.positions[0..n]);
            for (order[0..n], 1..) |team, place| {
                projection.total_points[team] += points[team];
                projection.titles[team] += @intFromBool(place == 1);
                projection.tops[team] += @intFromBool(place <= settings.top_positions);
                projection.bottoms[team] += @intFromBool(place >= n - settings.bottom_positions + 1);
            }
        }
        projection.order = pointsOrder(projection.total_points[0..n], projection.current.positions[0..n]);
        for (projection.order[0..n], 1..) |team, rank| projection.ranks[team] = rank;
        for (0..n) |team| {
            var count: usize = 0;
            var total: f64 = 0;
            for (season.matches[current_count..]) |match| {
                if (match.home == team) { total += run.ratings[match.away]; count += 1; } else if (match.away == team) { total += run.ratings[match.home]; count += 1; }
            }
            projection.opponent_strength[team] = total / r.f(count);
        }
    }

    fn recordText(self: *const Analysis, team: usize, category: enum { home, away, close, opponent }, opponent: usize) []const u8 {
        var won: usize = 0;
        var drawn: usize = 0;
        var lost: usize = 0;
        for (self.appearances[team][0..self.appearance_count[team]]) |item| {
            const include = switch (category) {
                .home => item.home,
                .away => !item.home,
                .close => @as(i64, @intCast(@abs(item.scored - item.conceded))) <= self.season.settings.close_margin,
                .opponent => item.opponent == opponent,
            };
            if (!include) continue;
            won += @intFromBool(item.letter == 'W');
            drawn += @intFromBool(item.letter == 'D');
            lost += @intFromBool(item.letter == 'L');
        }
        return r.fmt("{d}-{d}-{d}", .{ won, drawn, lost });
    }

    fn standingsLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck");
        for (self.final.order[0..self.season.teams.len], 1..) |team, position| {
            const count = self.appearance_count[team];
            const items = self.appearances[team][0..count];
            const record = self.final.records[team];
            var form: r.Text = .{};
            for (items[count - self.season.settings.form_length ..]) |item| form.add("{c}", .{item.letter});
            var streak: usize = 0;
            var i = count;
            while (i > 0 and items[i - 1].letter == items[count - 1].letter) : (i -= 1) streak += 1;
            lines.add("{d},{s},{s},{d},{d},{d},{d},{d},{d},{d},{d},{s},{s},{s},{c}{d},{s},{d},{d},{s},{s},{s},{s},{s},{s}", .{ position, self.season.teams[team].code, self.season.teams[team].name, record.played, record.won, record.drawn, record.lost, record.scored, record.conceded, record.scored - record.conceded, record.points, self.recordText(team, .home, 0), self.recordText(team, .away, 0), form.value(), items[count - 1].letter, streak, self.recordText(team, .close, 0), self.wins[team].length, self.unbeaten[team].length, self.fit.win_percentages[team].text(), self.sos[team].fixed(4), self.sos2[team].fixed(4), self.rpi[team].fixed(4), r.fixed(self.pythag[team], 4), r.fixed(self.luck[team], 4) });
        }
        return lines;
    }

    fn ratingsLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank");
        var order: [30]usize = @splat(0);
        for (0..self.season.teams.len) |team| {
            var position = team;
            while (position > 0 and self.totals[team] < self.totals[order[position - 1]]) : (position -= 1) order[position] = order[position - 1];
            order[position] = team;
        }
        const fit = &self.fit;
        for (order[0..self.season.teams.len]) |team| {
            var best: usize = 31;
            var worst: usize = 0;
            for (0..6) |model| { best = @min(best, self.ranks[model][team]); worst = @max(worst, self.ranks[model][team]); }
            lines.add("{s},{s},{d},{s},{d},{s},{d},{s},{d},{s},{s},{s},{d},{s},{d},{d},{d},{d}", .{ self.season.teams[team].code, r.fixed(fit.elo_run.ratings[team], 2), self.ranks[0][team], r.fixed(fit.colley[team], 4), self.ranks[1][team], r.fixed(fit.massey[team], 4), self.ranks[2][team], r.fixed(fit.strengths[team], 4), self.ranks[3][team], r.fixed(fit.offense[team], 2), r.fixed(fit.defense[team], 4), r.fixed(fit.od[team], 2), self.ranks[4][team], fit.win_percentages[team].fixed(4), self.ranks[5][team], self.totals[team], best, worst });
        }
        return lines;
    }

    fn historyLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("round,team,elo,change,elo_rank,points,position");
        for (0..self.season.rounds) |round| {
            const ratings = self.fit.elo_run.round_ratings[round];
            for (0..self.season.teams.len) |team| {
                var rank: usize = 1;
                for (ratings[0..self.season.teams.len]) |other| rank += @intFromBool(r.decimalValue(other, 2) > r.decimalValue(ratings[team], 2));
                const previous = if (round > 0) self.fit.elo_run.round_ratings[round - 1][team] else r.f(self.season.settings.elo_initial);
                const table = &self.round_tables[round];
                lines.add("{d},{s},{s},{s},{d},{d},{d}", .{ round + 1, self.season.teams[team].code, r.fixed(ratings[team], 2), r.fixed(ratings[team] - previous, 2), rank, table.records[team].points, table.positions[team] });
            }
        }
        return lines;
    }

    fn summaryLines(self: *const Analysis) r.Lines {
        var won: usize = 0;
        var drawn: usize = 0;
        var lost: usize = 0;
        var result_sum: i64 = 0;
        for (self.season.matches) |match| {
            won += @intFromBool(match.y2 == 2);
            drawn += @intFromBool(match.y2 == 1);
            lost += @intFromBool(match.y2 == 0);
            result_sum += match.y2;
        }
        var lines: r.Lines = .{};
        lines.add("season teams {d} matches {d} rounds {d}", .{ self.season.teams.len, self.season.matches.len, self.season.rounds });
        lines.add("home won {d} drawn {d} lost {d} rate {s}", .{ won, drawn, lost, Fraction.init(result_sum, 2 * r.n(self.season.matches.len)).withReal() });
        lines.add("massey_home_advantage {s}", .{r.fixed(self.fit.home_advantage, 4)});
        lines.add("bt_home_factor {s}", .{r.fixed(self.fit.home_factor, 4)});
        return lines;
    }

    fn winningExpected(self: *const Analysis, index: usize) f64 {
        return if (self.season.matches[index].margin > 0) self.fit.elo_run.expected[index] else 1 - self.fit.elo_run.expected[index];
    }

    fn upsetLines(self: *const Analysis) r.Lines {
        var order: [600]usize = undefined;
        var count: usize = 0;
        for (self.season.matches, 0..) |match, i| {
            if (match.margin == 0) continue;
            var position = count;
            count += 1;
            while (position > 0 and r.decimalValue(self.winningExpected(i), 4) < r.decimalValue(self.winningExpected(order[position - 1]), 4)) : (position -= 1) order[position] = order[position - 1];
            order[position] = i;
        }
        var lines: r.Lines = .{};
        lines.add("upsets top {d}", .{self.season.settings.upsets});
        for (order[0..@min(count, self.season.settings.upsets)]) |index| {
            const match = self.season.matches[index];
            const home = match.margin > 0;
            lines.add("round {d} {s} beat {s} {d}-{d} {s} expected {s} gain {s}", .{ match.round, self.season.teams[if (home) match.home else match.away].code, self.season.teams[if (home) match.away else match.home].code, if (home) match.home_score else match.away_score, if (home) match.away_score else match.home_score, if (home) "home" else "away", r.fixed(self.winningExpected(index), 4), r.fixed(@abs(self.fit.elo_run.changes[index]), 2) });
        }
        return lines;
    }

    fn tiebreakLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("tiebreaks");
        var start: usize = 0;
        while (start < self.season.teams.len) {
            var end = start + 1;
            const points = self.final.records[self.final.order[start]].points;
            while (end < self.season.teams.len and self.final.records[self.final.order[end]].points == points) end += 1;
            if (end - start > 1) {
                var line: r.Text = .{};
                line.add("points {d} order", .{points});
                for (self.final.order[start..end]) |team| line.add(" {s}", .{self.season.teams[team].code});
                line.write(" h2h_points");
                for (self.final.order[start..end]) |team| line.add(" {d}", .{self.final.h2h_points[team]});
                line.write(" h2h_diff");
                for (self.final.order[start..end]) |team| line.add(" {d}", .{self.final.h2h_difference[team]});
                lines.write(line.value());
            }
            start = end;
        }
        if (lines.data.items.len == 1) lines.write("none");
        return lines;
    }

    fn leaderLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("leaders");
        var previous: ?usize = null;
        var recorded: usize = 0;
        for (self.round_tables[0..self.season.rounds], 1..) |*table, number| {
            const leader = table.order[0];
            if (previous == null or leader != previous.?) {
                lines.add("round {d} {s} points {d}", .{ number, self.season.teams[leader].code, table.records[leader].points });
                recorded += 1;
            }
            previous = leader;
        }
        lines.add("lead_changes {d}", .{recorded - 1});
        return lines;
    }

    fn streakLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        for (0..2) |kind| {
            const streaks = if (kind == 0) &self.wins else &self.unbeaten;
            var longest: usize = 0;
            for (streaks[0..self.season.teams.len]) |streak| longest = @max(longest, streak.length);
            for (streaks[0..self.season.teams.len], 0..) |streak, team| {
                if (streak.length == longest) lines.add("{s} {s} length {d} rounds {d}-{d}", .{ if (kind == 0) "longest_win_streak" else "longest_unbeaten_streak", self.season.teams[team].code, longest, streak.first, streak.last });
            }
        }
        return lines;
    }

    fn crosstableLines(self: *const Analysis) r.Lines {
        const top = self.final.order[0..self.season.settings.top_positions];
        var lines: r.Lines = .{};
        lines.add("crosstable top {d}", .{top.len});
        var header: r.Text = .{};
        header.write("team");
        for (top) |team| header.add(" {s}", .{self.season.teams[team].code});
        lines.write(header.value());
        for (top) |first| {
            var row: r.Text = .{};
            row.write(self.season.teams[first].code);
            for (top) |second| row.add(" {s}", .{if (first == second) "-" else self.recordText(first, .opponent, second)});
            lines.write(row.value());
        }
        return lines;
    }

    fn trajectoryLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("trajectories");
        for (0..self.season.teams.len) |team| {
            var peak: usize = 0;
            var low: usize = 0;
            var best: usize = 0;
            var worst: usize = 0;
            for (1..self.season.rounds) |round| {
                const value = r.decimalValue(self.fit.elo_run.round_ratings[round][team], 2);
                if (value > r.decimalValue(self.fit.elo_run.round_ratings[peak][team], 2)) peak = round;
                if (value < r.decimalValue(self.fit.elo_run.round_ratings[low][team], 2)) low = round;
                const position = self.round_tables[round].positions[team];
                if (position < self.round_tables[best].positions[team]) best = round;
                if (position > self.round_tables[worst].positions[team]) worst = round;
            }
            lines.add("{s} elo_peak {s} round {d} elo_low {s} round {d} best_position {d} round {d} worst_position {d} round {d}", .{ self.season.teams[team].code, r.fixed(self.fit.elo_run.round_ratings[peak][team], 2), peak + 1, r.fixed(self.fit.elo_run.round_ratings[low][team], 2), low + 1, self.round_tables[best].positions[team], best + 1, self.round_tables[worst].positions[team], worst + 1 });
        }
        return lines;
    }

    fn correlationLines(self: *const Analysis, spearman: bool) r.Lines {
        const n = self.season.teams.len;
        var lines: r.Lines = .{};
        lines.write(if (spearman) "spearman" else "kendall");
        lines.write("model standings elo colley massey bt od winpct rpi pythag");
        for (comparison_names, 0..) |name, first| {
            var line: r.Text = .{};
            line.write(name);
            for (0..9) |second| {
                const value = if (spearman) evaluation.spearmanRho(self.comparison[first][0..n], self.comparison[second][0..n]) else evaluation.kendallTau(self.comparison[first][0..n], self.comparison[second][0..n]);
                line.add(" {s}", .{value.text()});
            }
            lines.write(line.value());
        }
        return lines;
    }

    fn similarityLines(self: *const Analysis) r.Lines {
        const n = self.season.teams.len;
        var most_first: usize = 0;
        var most_second: usize = 1;
        var least_first: usize = 0;
        var least_second: usize = 1;
        var most = evaluation.kendallTau(self.comparison[0][0..n], self.comparison[1][0..n]);
        var least = most;
        for (0..9) |first| {
            for (first + 1..9) |second| {
                const tau = evaluation.kendallTau(self.comparison[first][0..n], self.comparison[second][0..n]);
                if (tau.compare(most) == .gt) { most = tau; most_first = first; most_second = second; }
                if (tau.compare(least) == .lt) { least = tau; least_first = first; least_second = second; }
            }
        }
        var lines: r.Lines = .{};
        lines.add("most_similar {s} {s} tau {s}", .{ comparison_names[most_first], comparison_names[most_second], most.withReal() });
        lines.add("least_similar {s} {s} tau {s}", .{ comparison_names[least_first], comparison_names[least_second], least.withReal() });
        return lines;
    }

    fn seasonLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.paragraph(self.summaryLines());
        lines.paragraph(self.upsetLines());
        lines.paragraph(self.tiebreakLines());
        lines.paragraph(self.leaderLines());
        lines.paragraph(self.streakLines());
        lines.paragraph(self.crosstableLines());
        lines.paragraph(self.trajectoryLines());
        lines.paragraph(self.correlationLines(false));
        lines.paragraph(self.correlationLines(true));
        lines.paragraph(self.similarityLines());
        return lines;
    }

    fn predictionLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble");
        for (self.predictions[0..self.prediction_count]) |*prediction| {
            const match = prediction.match;
            var line: r.Text = .{};
            line.add("{d},{s},{s},{d},{d},{c}", .{ match.round, self.season.teams[match.home].code, self.season.teams[match.away].code, match.home_score, match.away_score, @as(u8, if (match.y2 == 2) 'H' else if (match.y2 == 0) 'A' else 'D') });
            for (prediction.probabilities) |probability| line.add(",{s}", .{r.fixed(probability, 4)});
            lines.write(line.value());
        }
        return lines;
    }

    fn linkLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("links");
        for (self.rounds[0..self.round_count]) |round| {
            var line: r.Text = .{};
            line.add("round {d} train {d} base {s} bt_home {s}", .{ round.number, round.training, r.fixed(round.base, 4), r.fixed(round.home_factor, 4) });
            for (link_names, round.links) |name, link| line.add(" {s} {s} {s}", .{ name, r.fixed(link.alpha, 4), r.fixed(link.beta, 4) });
            lines.write(line.value());
        }
        return lines;
    }

    fn scoreLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("scores");
        lines.write("model log_loss brier skill accuracy");
        for (prediction_names, 0..) |name, model| lines.add("{s} {s} {s} {s} {s}", .{ name, r.fixed(self.losses[model], 4), r.fixed(self.briers[model], 4), r.fixed(self.skills[model], 4), self.accuracies[model].withReal() });
        const labels = [_][]const u8{ "ranking_log_loss", "ranking_brier", "ranking_accuracy" };
        for (labels, self.rankings) |label, ranking| {
            var line: r.Text = .{};
            line.write(label);
            for (ranking) |model| line.add(" {s}", .{prediction_names[model]});
            lines.write(line.value());
        }
        return lines;
    }

    fn pairedLines(self: *const Analysis) r.Lines {
        const reference = self.rankings[0][0];
        const count = self.prediction_count;
        var lines: r.Lines = .{};
        lines.add("paired_log_loss reference {s}", .{prediction_names[reference]});
        for (prediction_names, 0..) |name, model| {
            if (model == reference) continue;
            var deltas: [600]f64 = undefined;
            var total: f64 = 0;
            for (self.predictions[0..count], 0..) |*prediction, i| {
                deltas[i] = prediction.losses[model] - prediction.losses[reference];
                total += deltas[i];
            }
            const average = total / r.f(count);
            var squares: f64 = 0;
            for (deltas[0..count]) |delta| { const difference = delta - average; squares += difference * difference; }
            const spread = @sqrt(squares / r.f(count - 1));
            const t = average / (spread / @sqrt(r.f(count)));
            lines.add("{s} mean_diff {s} sd {s} t {s}", .{ name, r.fixed(average, 4), r.fixed(spread, 4), r.fixed(t, 2) });
        }
        return lines;
    }

    fn marginLines(self: *const Analysis) r.Lines {
        var absolute: f64 = 0;
        var squares: f64 = 0;
        var sum: f64 = 0;
        for (self.predictions[0..self.prediction_count]) |prediction| {
            absolute += @abs(prediction.margin_error);
            squares += prediction.margin_error * prediction.margin_error;
            sum += prediction.margin_error;
        }
        const count = r.f(self.prediction_count);
        var lines: r.Lines = .{};
        lines.add("massey_margin mae {s} rmse {s} bias {s}", .{ r.fixed(absolute / count, 4), r.fixed(@sqrt(squares / count), 4), r.fixed(sum / count, 4) });
        return lines;
    }

    fn roundLossLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("round_log_loss");
        lines.write("round base elo colley massey bt od winpct ensemble");
        for (self.rounds[0..self.round_count]) |round| {
            var line: r.Text = .{};
            line.add("{d}", .{round.number});
            for (0..8) |model| {
                var total: f64 = 0;
                for (self.predictions[round.start .. round.start + round.count]) |prediction| total += prediction.losses[model];
                line.add(" {s}", .{r.fixed(total / r.f(round.count), 4)});
            }
            lines.write(line.value());
        }
        return lines;
    }

    fn calibrationLines(self: *const Analysis) r.Lines {
        const bins = self.season.settings.calibration_bins;
        var lines: r.Lines = .{};
        lines.add("calibration bins {d}", .{bins});
        for (prediction_names, 0..) |name, model| {
            var counts: [10]usize = @splat(0);
            var observed: [10]i64 = @splat(0);
            var totals: [10]f64 = @splat(0);
            for (self.predictions[0..self.prediction_count]) |prediction| {
                const bin = @min(@as(usize, @intFromFloat(@floor(r.f(bins) * prediction.probabilities[model]))), bins - 1);
                counts[bin] += 1;
                totals[bin] += prediction.probabilities[model];
                observed[bin] += prediction.match.y2;
            }
            for (0..bins) |bin| {
                if (counts[bin] == 0) {
                    lines.add("{s} bin {d} count 0 predicted - observed -", .{ name, bin + 1 });
                } else lines.add("{s} bin {d} count {d} predicted {s} observed {s}", .{ name, bin + 1, counts[bin], r.fixed(totals[bin] / r.f(counts[bin]), 4), Fraction.init(observed[bin], 2 * r.n(counts[bin])).text() });
            }
        }
        return lines;
    }

    fn gridLines(self: *const Analysis) r.Lines {
        const season = self.season;
        const settings = season.settings;
        var lines: r.Lines = .{};
        lines.write("elo_grid");
        var header: r.Text = .{};
        header.write("k");
        for (settings.grid_home) |home| header.add(" h{d}", .{home});
        lines.write(header.value());
        var best_loss: ?f64 = null;
        var best_k: i64 = 0;
        var best_home: i64 = 0;
        const start = season.before(settings.holdout_round);
        for (settings.grid_k) |k| {
            var row: r.Text = .{};
            row.add("{d}", .{k});
            for (settings.grid_home) |home| {
                const run = elo.run(season.teams.len, season.matches, k, home, settings.elo_initial);
                var total: f64 = 0;
                for (season.matches[start..], start..) |match, i| total += evaluation.logLoss(run.expected[i], match.y2);
                const loss = total / r.f(self.prediction_count);
                row.add(" {s}", .{r.fixed(loss, 4)});
                if (best_loss == null or r.decimalValue(loss, 4) < r.decimalValue(best_loss.?, 4)) { best_loss = loss; best_k = k; best_home = home; }
            }
            lines.write(row.value());
        }
        lines.add("best k {d} home {d} log_loss {s}", .{ best_k, best_home, r.fixed(best_loss.?, 4) });
        return lines;
    }

    fn projectionTau(self: *const Analysis) Fraction {
        const n = self.season.teams.len;
        var projected: [30]Comparison = undefined;
        var final: [30]Comparison = undefined;
        for (0..n) |team| {
            projected[team] = .{ .value = -r.f(self.projection.ranks[team]) };
            final[team] = .{ .value = -r.f(self.final.positions[team]) };
        }
        return evaluation.kendallTau(projected[0..n], final[0..n]);
    }

    fn evaluationLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        var holdout: r.Lines = .{};
        var projection: r.Lines = .{};
        holdout.add("holdout rounds {d}-{d} matches {d}", .{ self.season.settings.holdout_round, self.season.rounds, self.prediction_count });
        lines.paragraph(holdout);
        lines.paragraph(self.linkLines());
        lines.paragraph(self.scoreLines());
        lines.paragraph(self.pairedLines());
        lines.paragraph(self.marginLines());
        lines.paragraph(self.roundLossLines());
        lines.paragraph(self.calibrationLines());
        lines.paragraph(self.gridLines());
        projection.add("projection simulations {d} kendall {s}", .{ self.season.settings.simulations, self.projectionTau().withReal() });
        lines.paragraph(projection);
        return lines;
    }

    fn projectionLines(self: *const Analysis) r.Lines {
        var lines: r.Lines = .{};
        lines.write("projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position");
        const projection = &self.projection;
        const simulations = r.n(self.season.settings.simulations);
        for (projection.order[0..self.season.teams.len], 1..) |team, rank| {
            lines.add("{d},{s},{d},{d},{s},{s},{s},{s},{s},{d},{d}", .{ rank, self.season.teams[team].code, projection.current.records[team].points, projection.current.positions[team], r.fixed(projection.opponent_strength[team], 2), Fraction.init(projection.total_points[team], simulations).fixed(4), Fraction.init(projection.titles[team], simulations).fixed(4), Fraction.init(projection.tops[team], simulations).fixed(4), Fraction.init(projection.bottoms[team], simulations).fixed(4), self.final.records[team].points, self.final.positions[team] });
        }
        return lines;
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    r.allocator = arena.allocator();
    const season = try s.load(init.io);
    const analysis = &r.alloc(Analysis, 1)[0];
    analysis.* = .{ .season = &season };
    analysis.initialize();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    try r.writeLines(init.io, "standings.csv", analysis.standingsLines());
    try r.writeLines(init.io, "ratings.csv", analysis.ratingsLines());
    try r.writeLines(init.io, "history.csv", analysis.historyLines());
    try r.writeLines(init.io, "season.txt", analysis.seasonLines());
    try r.writeLines(init.io, "predictions.csv", analysis.predictionLines());
    try r.writeLines(init.io, "evaluation.txt", analysis.evaluationLines());
    try r.writeLines(init.io, "projection.csv", analysis.projectionLines());
}
