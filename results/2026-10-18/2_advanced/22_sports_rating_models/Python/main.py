import os
from fractions import Fraction
from math import floor, log, sqrt

from elo import expected_score, run_elo
from evaluation import (
    brier_score, correctness, fit_link, kendall_tau, log_loss, sigma, spearman_rho,
)
from iterative_models import bradley_terry, offense_defense
from linear_models import colley_ratings, massey_ratings
from report import decimal_value, fixed, fraction_text, fraction_with_real, write_lines
from season import load_season, matches_before


RATING_MODELS = ("elo", "colley", "massey", "bt", "od", "winpct")
COMPARISON_MODELS = (
    "standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag",
)
LINK_MODELS = ("colley", "massey", "od", "winpct")
PREDICTION_MODELS = ("base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble")
ENSEMBLE_MODELS = ("elo", "colley", "massey", "bt", "od", "winpct")
RANDOM_MULTIPLIER = 48271
RANDOM_MODULUS = 2147483647
STANDINGS_HEADER = (
    "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,"
    "close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck"
)
RATINGS_HEADER = (
    "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,"
    "od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank"
)
HISTORY_HEADER = "round,team,elo,change,elo_rank,points,position"
PREDICTIONS_HEADER = "round,home,away,home_score,away_score,result," + ",".join(PREDICTION_MODELS)
PROJECTION_HEADER = (
    "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,"
    "bottom,final_points,final_position"
)


def sequential_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def mean(values):
    return sequential_sum(values) / len(values)


def result_letter(scored, conceded):
    if scored > conceded:
        return "W"
    if scored == conceded:
        return "D"
    return "L"


def result_code(y):
    if y == 1:
        return "H"
    if y == 0:
        return "A"
    return "D"


def record_text(appearances):
    letters = [appearance.letter for appearance in appearances]
    return f"{letters.count('W')}-{letters.count('D')}-{letters.count('L')}"


def competition_ranks(values):
    return [1 + sum(1 for other in values if other > value) for value in values]


def csv_line(fields):
    return ",".join(str(field) for field in fields)


def join_parts(parts):
    lines = []
    for part in parts:
        if lines:
            lines.append("")
        lines.extend(part)
    return lines


class Appearance:
    def __init__(self, match, team):
        self.match = match
        self.home = match.home == team
        if self.home:
            self.opponent = match.away
            self.scored = match.home_score
            self.conceded = match.away_score
        else:
            self.opponent = match.home
            self.scored = match.away_score
            self.conceded = match.home_score
        self.letter = result_letter(self.scored, self.conceded)


def appearances_of(team, matches):
    return [Appearance(match, team) for match in matches if team in (match.home, match.away)]


class Record:
    def __init__(self):
        self.played = 0
        self.won = 0
        self.drawn = 0
        self.lost = 0
        self.scored = 0
        self.conceded = 0
        self.points = 0

    def add(self, scored, conceded, settings):
        self.played += 1
        self.scored += scored
        self.conceded += conceded
        if scored > conceded:
            self.won += 1
            self.points += settings.win_points
        elif scored == conceded:
            self.drawn += 1
            self.points += settings.draw_points
        else:
            self.lost += 1

    def difference(self):
        return self.scored - self.conceded

    def win_percentage(self):
        return Fraction(2 * self.won + self.drawn, 2 * self.played)


def team_records(team_count, matches, settings):
    records = [Record() for _ in range(team_count)]
    for match in matches:
        records[match.home].add(match.home_score, match.away_score, settings)
        records[match.away].add(match.away_score, match.home_score, settings)
    return records


class Standings:
    def __init__(self, teams, matches, settings):
        team_count = len(teams)
        self.teams = teams
        self.records = team_records(team_count, matches, settings)
        self.h2h_points = [0] * team_count
        self.h2h_difference = [0] * team_count
        groups = {}
        for team in range(team_count):
            groups.setdefault(self.records[team].points, set()).add(team)
        for members in groups.values():
            inner = [match for match in matches if match.home in members and match.away in members]
            inner_records = team_records(team_count, inner, settings)
            for team in members:
                self.h2h_points[team] = inner_records[team].points
                self.h2h_difference[team] = inner_records[team].difference()
        self.order = sorted(range(team_count), key=self.sort_key)
        self.positions = [0] * team_count
        for position, team in enumerate(self.order, 1):
            self.positions[team] = position

    def sort_key(self, team):
        record = self.records[team]
        return (
            -record.points, -self.h2h_points[team], -self.h2h_difference[team],
            -record.difference(), -record.scored, self.teams[team].code,
        )

    def tied_groups(self):
        groups = []
        for team in self.order:
            if groups and self.records[groups[-1][0]].points == self.records[team].points:
                groups[-1].append(team)
            else:
                groups.append([team])
        return [group for group in groups if len(group) > 1]


class Streak:
    def __init__(self, length, first, last):
        self.length = length
        self.first = first
        self.last = last


def longest_streak(appearances, letters):
    best = Streak(0, 0, 0)
    start = 0
    length = 0
    for index, appearance in enumerate(appearances):
        if appearance.letter not in letters:
            length = 0
            continue
        if length == 0:
            start = index
        length += 1
        if length > best.length:
            best = Streak(length, appearances[start].match.round, appearance.match.round)
    return best


def current_streak(appearances):
    last = appearances[-1].letter
    count = 0
    for appearance in reversed(appearances):
        if appearance.letter != last:
            break
        count += 1
    return f"{last}{count}"


class ModelFit:
    def __init__(self, team_count, matches, settings):
        self.elo = run_elo(
            team_count, matches, settings.elo_k, settings.elo_home, settings.elo_initial
        )
        self.colley = colley_ratings(team_count, matches)
        self.massey, self.home_advantage = massey_ratings(team_count, matches)
        self.strengths, self.home_factor = bradley_terry(
            team_count, matches, settings.bt_iterations
        )
        self.offense, self.defense, self.od = offense_defense(
            team_count, matches, settings.od_iterations
        )
        records = team_records(team_count, matches, settings)
        self.win_percentages = [record.win_percentage() for record in records]

    def feature(self, model, match):
        home, away = match.home, match.away
        if model == "colley":
            return self.colley[home] - self.colley[away]
        if model == "massey":
            return self.massey[home] - self.massey[away]
        if model == "od":
            return log(self.od[home]) - log(self.od[away])
        return float(self.win_percentages[home]) - float(self.win_percentages[away])

    def bt_probability(self, match):
        home = self.home_factor * self.strengths[match.home]
        return home / (home + self.strengths[match.away])

    def predicted_margin(self, match):
        return self.massey[match.home] - self.massey[match.away] + self.home_advantage


class Prediction:
    def __init__(self, match, probabilities, margin_error):
        self.match = match
        self.probabilities = probabilities
        self.losses = [log_loss(p, match.y) for p in probabilities]
        self.briers = [brier_score(p, match.y) for p in probabilities]
        self.scores = [correctness(p, match.y) for p in probabilities]
        self.margin_error = margin_error


class ValidationRound:
    def __init__(self, number, team_count, matches, settings):
        self.number = number
        self.training = matches_before(matches, number)
        self.fit = ModelFit(team_count, self.training, settings)
        results = [match.y for match in self.training]
        self.base = float(sum(results) / len(results))
        self.links = {}
        for model in LINK_MODELS:
            features = [self.fit.feature(model, match) for match in self.training]
            self.links[model] = fit_link(features, results, settings.link_iterations)
        self.predictions = [
            self.predict(match, settings) for match in matches if match.round == number
        ]

    def predict(self, match, settings):
        ratings = self.fit.elo.ratings
        probabilities = {"base": self.base}
        probabilities["elo"] = expected_score(
            ratings[match.home], ratings[match.away], settings.elo_home
        )
        for model in LINK_MODELS:
            alpha, beta = self.links[model]
            probabilities[model] = sigma(alpha + beta * self.fit.feature(model, match))
        probabilities["bt"] = self.fit.bt_probability(match)
        ensemble = sequential_sum(probabilities[model] for model in ENSEMBLE_MODELS)
        probabilities["ensemble"] = ensemble / len(ENSEMBLE_MODELS)
        error = match.margin - self.fit.predicted_margin(match)
        return Prediction(match, [probabilities[model] for model in PREDICTION_MODELS], error)


class ModelScores:
    def __init__(self, predictions):
        count = len(predictions)
        indices = range(len(PREDICTION_MODELS))
        self.losses = [mean([item.losses[k] for item in predictions]) for k in indices]
        self.briers = [mean([item.briers[k] for item in predictions]) for k in indices]
        self.skills = [1 - brier / self.briers[0] for brier in self.briers]
        self.accuracies = [sum(item.scores[k] for item in predictions) / count for k in indices]
        self.loss_ranking = sorted(indices, key=lambda k: decimal_value(self.losses[k], 4))
        self.brier_ranking = sorted(indices, key=lambda k: decimal_value(self.briers[k], 4))
        self.accuracy_ranking = sorted(indices, key=lambda k: -self.accuracies[k])


class RandomSequence:
    def __init__(self, seed):
        self.state = seed

    def next_uniform(self):
        self.state = RANDOM_MULTIPLIER * self.state % RANDOM_MODULUS
        return self.state / RANDOM_MODULUS


class Projection:
    def __init__(self, teams, matches, settings):
        team_count = len(teams)
        current_matches = matches_before(matches, settings.holdout_round)
        self.current = Standings(teams, current_matches, settings)
        self.ratings = run_elo(
            team_count, current_matches, settings.elo_k, settings.elo_home,
            settings.elo_initial,
        ).ratings
        self.remaining = [match for match in matches if match.round >= settings.holdout_round]
        self.total_points = [0] * team_count
        self.titles = [0] * team_count
        self.tops = [0] * team_count
        self.bottoms = [0] * team_count
        self.simulate(settings)
        self.order = sorted(
            range(team_count), key=lambda team: self.rank_key(team, self.total_points)
        )
        self.ranks = [0] * team_count
        for rank, team in enumerate(self.order, 1):
            self.ranks[team] = rank

    def rank_key(self, team, points):
        return -points[team], self.current.positions[team]

    def simulate(self, settings):
        team_count = len(self.total_points)
        probabilities = [
            expected_score(self.ratings[match.home], self.ratings[match.away], settings.elo_home)
            for match in self.remaining
        ]
        generator = RandomSequence(settings.seed)
        bottom_place = team_count - settings.bottom_positions + 1
        for _ in range(settings.simulations):
            points = [record.points for record in self.current.records]
            for match, probability in zip(self.remaining, probabilities):
                if generator.next_uniform() < probability:
                    points[match.home] += settings.win_points
                else:
                    points[match.away] += settings.win_points
            order = sorted(range(team_count), key=lambda team: self.rank_key(team, points))
            for place, team in enumerate(order, 1):
                self.total_points[team] += points[team]
                if place == 1:
                    self.titles[team] += 1
                if place <= settings.top_positions:
                    self.tops[team] += 1
                if place >= bottom_place:
                    self.bottoms[team] += 1

    def opponent_strength(self, team):
        ratings = []
        for match in self.remaining:
            if match.home == team:
                ratings.append(self.ratings[match.away])
            elif match.away == team:
                ratings.append(self.ratings[match.home])
        return mean(ratings)


class LeagueAnalysis:
    def __init__(self, teams, matches, settings):
        self.teams = teams
        self.matches = matches
        self.settings = settings
        self.team_count = len(teams)
        self.final_round = matches[-1].round
        self.appearances = [appearances_of(team.index, matches) for team in teams]
        self.final = Standings(teams, matches, settings)
        self.fit = ModelFit(self.team_count, matches, settings)
        self.round_tables = [
            Standings(teams, matches_before(matches, number + 1), settings)
            for number in range(1, self.final_round + 1)
        ]
        self.win_streaks = [longest_streak(items, ("W",)) for items in self.appearances]
        self.unbeaten_streaks = [longest_streak(items, ("W", "D")) for items in self.appearances]
        self.compute_indicators()
        self.comparison = self.comparison_values()
        self.ranks = {model: competition_ranks(self.comparison[model]) for model in RATING_MODELS}
        self.rounds = [
            ValidationRound(number, self.team_count, matches, settings)
            for number in range(settings.holdout_round, self.final_round + 1)
        ]
        self.predictions = [
            prediction for validation in self.rounds for prediction in validation.predictions
        ]
        self.scores = ModelScores(self.predictions)
        self.projection = Projection(teams, matches, settings)

    def opponent_average(self, team, values):
        total = Fraction(0)
        for appearance in self.appearances[team]:
            total += values[appearance.opponent]
        return total / len(self.appearances[team])

    def compute_indicators(self):
        indices = range(self.team_count)
        percentages = self.fit.win_percentages
        self.sos = [self.opponent_average(team, percentages) for team in indices]
        self.sos2 = [self.opponent_average(team, self.sos) for team in indices]
        self.rpi = [
            (percentages[team] + 2 * self.sos[team] + self.sos2[team]) / 4 for team in indices
        ]
        exponent = self.settings.pythagorean_exponent
        self.pythag = [
            1 / (1 + (record.conceded / record.scored) ** exponent)
            for record in self.final.records
        ]
        self.luck = [float(percentages[team]) - self.pythag[team] for team in indices]

    def comparison_values(self):
        fit = self.fit
        return {
            "standings": [-position for position in self.final.positions],
            "elo": [decimal_value(rating, 2) for rating in fit.elo.ratings],
            "colley": [decimal_value(rating, 4) for rating in fit.colley],
            "massey": [decimal_value(rating, 4) for rating in fit.massey],
            "bt": [decimal_value(rating, 4) for rating in fit.strengths],
            "od": [decimal_value(rating, 2) for rating in fit.od],
            "winpct": fit.win_percentages,
            "rpi": self.rpi,
            "pythag": [decimal_value(value, 4) for value in self.pythag],
        }

    def code(self, team):
        return self.teams[team].code

    def standings_lines(self):
        settings = self.settings
        lines = [STANDINGS_HEADER]
        for position, team in enumerate(self.final.order, 1):
            record = self.final.records[team]
            appearances = self.appearances[team]
            home = [item for item in appearances if item.home]
            away = [item for item in appearances if not item.home]
            close = [
                item for item in appearances
                if abs(item.scored - item.conceded) <= settings.close_margin
            ]
            form = "".join(item.letter for item in appearances[-settings.form_length:])
            lines.append(csv_line([
                position, self.code(team), self.teams[team].name, record.played, record.won,
                record.drawn, record.lost, record.scored, record.conceded, record.difference(),
                record.points, record_text(home), record_text(away), form,
                current_streak(appearances), record_text(close),
                self.win_streaks[team].length, self.unbeaten_streaks[team].length,
                fraction_text(self.fit.win_percentages[team]), fixed(self.sos[team]),
                fixed(self.sos2[team]), fixed(self.rpi[team]), fixed(self.pythag[team]),
                fixed(self.luck[team]),
            ]))
        return lines

    def ratings_lines(self):
        fit = self.fit
        totals = [
            sum(self.ranks[model][team] for model in RATING_MODELS)
            for team in range(self.team_count)
        ]
        order = sorted(range(self.team_count), key=lambda team: (totals[team], self.code(team)))
        lines = [RATINGS_HEADER]
        for team in order:
            ranks = {model: self.ranks[model][team] for model in RATING_MODELS}
            lines.append(csv_line([
                self.code(team), fixed(fit.elo.ratings[team], 2), ranks["elo"],
                fixed(fit.colley[team]), ranks["colley"], fixed(fit.massey[team]), ranks["massey"],
                fixed(fit.strengths[team]), ranks["bt"], fixed(fit.offense[team], 2),
                fixed(fit.defense[team]), fixed(fit.od[team], 2), ranks["od"],
                fixed(fit.win_percentages[team]), ranks["winpct"], totals[team],
                min(ranks.values()), max(ranks.values()),
            ]))
        return lines

    def history_lines(self):
        lines = [HISTORY_HEADER]
        previous = [float(self.settings.elo_initial)] * self.team_count
        for number, table in enumerate(self.round_tables, 1):
            ratings = self.fit.elo.round_ratings[number - 1]
            elo_ranks = competition_ranks([decimal_value(rating, 2) for rating in ratings])
            for team in range(self.team_count):
                lines.append(csv_line([
                    number, self.code(team), fixed(ratings[team], 2),
                    fixed(ratings[team] - previous[team], 2), elo_ranks[team],
                    table.records[team].points, table.positions[team],
                ]))
            previous = ratings
        return lines

    def summary_lines(self):
        results = [match.y for match in self.matches]
        rate = sum(results) / len(results)
        return [
            f"season teams {self.team_count} matches {len(self.matches)}"
            f" rounds {self.final_round}",
            f"home won {results.count(1)} drawn {results.count(Fraction(1, 2))}"
            f" lost {results.count(0)} rate {fraction_with_real(rate)}",
            f"massey_home_advantage {fixed(self.fit.home_advantage)}",
            f"bt_home_factor {fixed(self.fit.home_factor)}",
        ]

    def upset_lines(self):
        elo = self.fit.elo
        candidates = []
        for index, match in enumerate(self.matches):
            if match.margin > 0:
                candidates.append((match, elo.expected[index], abs(elo.changes[index])))
            elif match.margin < 0:
                candidates.append((match, 1 - elo.expected[index], abs(elo.changes[index])))
        candidates.sort(key=lambda candidate: decimal_value(candidate[1], 4))
        lines = [f"upsets top {self.settings.upsets}"]
        for match, expected, gain in candidates[:self.settings.upsets]:
            if match.margin > 0:
                winner, loser, side = match.home, match.away, "home"
                score = f"{match.home_score}-{match.away_score}"
            else:
                winner, loser, side = match.away, match.home, "away"
                score = f"{match.away_score}-{match.home_score}"
            lines.append(
                f"round {match.round} {self.code(winner)} beat {self.code(loser)} {score} {side}"
                f" expected {fixed(expected)} gain {fixed(gain, 2)}"
            )
        return lines

    def tiebreak_lines(self):
        lines = ["tiebreaks"]
        for group in self.final.tied_groups():
            points = self.final.records[group[0]].points
            order = " ".join(self.code(team) for team in group)
            h2h_points = " ".join(str(self.final.h2h_points[team]) for team in group)
            h2h_difference = " ".join(str(self.final.h2h_difference[team]) for team in group)
            lines.append(
                f"points {points} order {order} h2h_points {h2h_points} h2h_diff {h2h_difference}"
            )
        if len(lines) == 1:
            lines.append("none")
        return lines

    def leader_lines(self):
        lines = ["leaders"]
        previous = None
        recorded = 0
        for number, table in enumerate(self.round_tables, 1):
            leader = table.order[0]
            if leader != previous:
                lines.append(
                    f"round {number} {self.code(leader)} points {table.records[leader].points}"
                )
                recorded += 1
            previous = leader
        lines.append(f"lead_changes {recorded - 1}")
        return lines

    def streak_lines(self):
        lines = []
        labels = (
            ("longest_win_streak", self.win_streaks),
            ("longest_unbeaten_streak", self.unbeaten_streaks),
        )
        for label, streaks in labels:
            longest = max(streak.length for streak in streaks)
            for team, streak in enumerate(streaks):
                if streak.length == longest:
                    lines.append(
                        f"{label} {self.code(team)} length {streak.length}"
                        f" rounds {streak.first}-{streak.last}"
                    )
        return lines

    def crosstable_lines(self):
        top = self.final.order[:self.settings.top_positions]
        lines = [
            f"crosstable top {self.settings.top_positions}",
            "team " + " ".join(self.code(team) for team in top),
        ]
        for first in top:
            entries = []
            for second in top:
                if first == second:
                    entries.append("-")
                else:
                    meetings = [
                        item for item in self.appearances[first] if item.opponent == second
                    ]
                    entries.append(record_text(meetings))
            lines.append(self.code(first) + " " + " ".join(entries))
        return lines

    def trajectory_lines(self):
        lines = ["trajectories"]
        for team in range(self.team_count):
            ratings = [snapshot[team] for snapshot in self.fit.elo.round_ratings]
            rounded = [decimal_value(rating, 2) for rating in ratings]
            positions = [table.positions[team] for table in self.round_tables]
            peak = low = best = worst = 0
            for index in range(1, self.final_round):
                if rounded[index] > rounded[peak]:
                    peak = index
                if rounded[index] < rounded[low]:
                    low = index
                if positions[index] < positions[best]:
                    best = index
                if positions[index] > positions[worst]:
                    worst = index
            lines.append(
                f"{self.code(team)} elo_peak {fixed(ratings[peak], 2)} round {peak + 1}"
                f" elo_low {fixed(ratings[low], 2)} round {low + 1}"
                f" best_position {positions[best]} round {best + 1}"
                f" worst_position {positions[worst]} round {worst + 1}"
            )
        return lines

    def correlation_lines(self, title, measure):
        lines = [title, "model " + " ".join(COMPARISON_MODELS)]
        for first in COMPARISON_MODELS:
            values = [
                fraction_text(measure(self.comparison[first], self.comparison[second]))
                for second in COMPARISON_MODELS
            ]
            lines.append(first + " " + " ".join(values))
        return lines

    def similarity_lines(self):
        pairs = []
        for index, first in enumerate(COMPARISON_MODELS):
            for second in COMPARISON_MODELS[index + 1:]:
                tau = kendall_tau(self.comparison[first], self.comparison[second])
                pairs.append((first, second, tau))
        most = least = pairs[0]
        for pair in pairs[1:]:
            if pair[2] > most[2]:
                most = pair
            if pair[2] < least[2]:
                least = pair
        return [
            f"most_similar {most[0]} {most[1]} tau {fraction_with_real(most[2])}",
            f"least_similar {least[0]} {least[1]} tau {fraction_with_real(least[2])}",
        ]

    def season_lines(self):
        return join_parts([
            self.summary_lines(),
            self.upset_lines(),
            self.tiebreak_lines(),
            self.leader_lines(),
            self.streak_lines(),
            self.crosstable_lines(),
            self.trajectory_lines(),
            self.correlation_lines("kendall", kendall_tau),
            self.correlation_lines("spearman", spearman_rho),
            self.similarity_lines(),
        ])

    def prediction_lines(self):
        lines = [PREDICTIONS_HEADER]
        for prediction in self.predictions:
            match = prediction.match
            fields = [
                match.round, self.code(match.home), self.code(match.away), match.home_score,
                match.away_score, result_code(match.y),
            ]
            fields.extend(fixed(probability) for probability in prediction.probabilities)
            lines.append(csv_line(fields))
        return lines

    def link_lines(self):
        lines = ["links"]
        for validation in self.rounds:
            parts = [
                f"round {validation.number} train {len(validation.training)}"
                f" base {fixed(validation.base)} bt_home {fixed(validation.fit.home_factor)}"
            ]
            for model in LINK_MODELS:
                alpha, beta = validation.links[model]
                parts.append(f"{model} {fixed(alpha)} {fixed(beta)}")
            lines.append(" ".join(parts))
        return lines

    def score_lines(self):
        scores = self.scores
        lines = ["scores", "model log_loss brier skill accuracy"]
        for index, model in enumerate(PREDICTION_MODELS):
            lines.append(
                f"{model} {fixed(scores.losses[index])} {fixed(scores.briers[index])}"
                f" {fixed(scores.skills[index])} {fraction_with_real(scores.accuracies[index])}"
            )
        rankings = (
            ("ranking_log_loss", scores.loss_ranking),
            ("ranking_brier", scores.brier_ranking),
            ("ranking_accuracy", scores.accuracy_ranking),
        )
        for label, ranking in rankings:
            lines.append(label + " " + " ".join(PREDICTION_MODELS[index] for index in ranking))
        return lines

    def paired_lines(self):
        reference = self.scores.loss_ranking[0]
        count = len(self.predictions)
        lines = [f"paired_log_loss reference {PREDICTION_MODELS[reference]}"]
        for index, model in enumerate(PREDICTION_MODELS):
            if index == reference:
                continue
            deltas = [item.losses[index] - item.losses[reference] for item in self.predictions]
            average = mean(deltas)
            squares = sequential_sum((delta - average) * (delta - average) for delta in deltas)
            spread = sqrt(squares / (count - 1))
            t_value = average / (spread / sqrt(count))
            lines.append(
                f"{model} mean_diff {fixed(average)} sd {fixed(spread)} t {fixed(t_value, 2)}"
            )
        return lines

    def margin_lines(self):
        errors = [prediction.margin_error for prediction in self.predictions]
        absolute = mean([abs(error) for error in errors])
        root_squared = sqrt(mean([error * error for error in errors]))
        bias = mean(errors)
        return [
            f"massey_margin mae {fixed(absolute)} rmse {fixed(root_squared)} bias {fixed(bias)}"
        ]

    def round_loss_lines(self):
        lines = ["round_log_loss", "round " + " ".join(PREDICTION_MODELS)]
        for validation in self.rounds:
            losses = [
                fixed(mean([item.losses[index] for item in validation.predictions]))
                for index in range(len(PREDICTION_MODELS))
            ]
            lines.append(f"{validation.number} " + " ".join(losses))
        return lines

    def calibration_lines(self):
        bins = self.settings.calibration_bins
        lines = [f"calibration bins {bins}"]
        for index, model in enumerate(PREDICTION_MODELS):
            members = [[] for _ in range(bins)]
            for prediction in self.predictions:
                number = min(floor(bins * prediction.probabilities[index]) + 1, bins)
                members[number - 1].append(prediction)
            for number, group in enumerate(members, 1):
                if not group:
                    lines.append(f"{model} bin {number} count 0 predicted - observed -")
                    continue
                predicted = mean([item.probabilities[index] for item in group])
                observed = sum(item.match.y for item in group) / len(group)
                lines.append(
                    f"{model} bin {number} count {len(group)} predicted {fixed(predicted)}"
                    f" observed {fraction_text(observed)}"
                )
        return lines

    def grid_lines(self):
        settings = self.settings
        validation = [
            index for index, match in enumerate(self.matches)
            if match.round >= settings.holdout_round
        ]
        lines = ["elo_grid", "k " + " ".join(f"h{home}" for home in settings.grid_home)]
        best = None
        for k_factor in settings.grid_k:
            row = [str(k_factor)]
            for home in settings.grid_home:
                run = run_elo(
                    self.team_count, self.matches, k_factor, home, settings.elo_initial
                )
                loss = mean([
                    log_loss(run.expected[index], self.matches[index].y) for index in validation
                ])
                row.append(fixed(loss))
                if best is None or decimal_value(loss, 4) < decimal_value(best[2], 4):
                    best = (k_factor, home, loss)
            lines.append(" ".join(row))
        lines.append(f"best k {best[0]} home {best[1]} log_loss {fixed(best[2])}")
        return lines

    def projection_tau(self):
        projected = [-rank for rank in self.projection.ranks]
        final = [-position for position in self.final.positions]
        return kendall_tau(projected, final)

    def evaluation_lines(self):
        return join_parts([
            [
                f"holdout rounds {self.settings.holdout_round}-{self.final_round}"
                f" matches {len(self.predictions)}"
            ],
            self.link_lines(),
            self.score_lines(),
            self.paired_lines(),
            self.margin_lines(),
            self.round_loss_lines(),
            self.calibration_lines(),
            self.grid_lines(),
            [
                f"projection simulations {self.settings.simulations}"
                f" kendall {fraction_with_real(self.projection_tau())}"
            ],
        ])

    def projection_lines(self):
        projection = self.projection
        simulations = self.settings.simulations
        lines = [PROJECTION_HEADER]
        for rank, team in enumerate(projection.order, 1):
            lines.append(csv_line([
                rank, self.code(team), projection.current.records[team].points,
                projection.current.positions[team], fixed(projection.opponent_strength(team), 2),
                fixed(projection.total_points[team] / simulations),
                fixed(projection.titles[team] / simulations),
                fixed(projection.tops[team] / simulations),
                fixed(projection.bottoms[team] / simulations),
                self.final.records[team].points, self.final.positions[team],
            ]))
        return lines

    def output_files(self):
        return [
            ("standings.csv", self.standings_lines()),
            ("ratings.csv", self.ratings_lines()),
            ("history.csv", self.history_lines()),
            ("season.txt", self.season_lines()),
            ("predictions.csv", self.prediction_lines()),
            ("evaluation.txt", self.evaluation_lines()),
            ("projection.csv", self.projection_lines()),
        ]


def main():
    teams, matches, settings = load_season("input")
    analysis = LeagueAnalysis(teams, matches, settings)
    os.makedirs("output", exist_ok=True)
    for name, lines in analysis.output_files():
        write_lines(os.path.join("output", name), lines)


if __name__ == "__main__":
    main()
