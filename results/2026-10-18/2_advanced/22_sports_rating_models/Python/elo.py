from math import log


class EloRun:
    def __init__(self, ratings):
        self.ratings = ratings
        self.expected = []
        self.changes = []
        self.round_ratings = []


def expected_score(home_rating, away_rating, home_advantage):
    return 1 / (1 + 10 ** ((away_rating - home_rating - home_advantage) / 400))


def multiplier(match, home_rating, away_rating, home_advantage):
    goals = abs(match.margin)
    if goals == 0:
        return 1.0
    if match.margin > 0:
        difference = home_rating + home_advantage - away_rating
    else:
        difference = away_rating - home_rating - home_advantage
    return log(goals + 1) * 2.2 / (0.001 * difference + 2.2)


def run_elo(team_count, matches, k_factor, home_advantage, initial):
    run = EloRun([float(initial)] * team_count)
    ratings = run.ratings
    for position, match in enumerate(matches):
        home_rating = ratings[match.home]
        away_rating = ratings[match.away]
        expected = expected_score(home_rating, away_rating, home_advantage)
        weight = multiplier(match, home_rating, away_rating, home_advantage)
        change = k_factor * weight * (match.y - expected)
        ratings[match.home] = home_rating + change
        ratings[match.away] = away_rating - change
        run.expected.append(expected)
        run.changes.append(change)
        if position + 1 == len(matches) or matches[position + 1].round != match.round:
            run.round_ratings.append(list(ratings))
    return run
