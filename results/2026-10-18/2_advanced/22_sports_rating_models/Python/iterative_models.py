from fractions import Fraction


def bradley_terry(team_count, matches, iterations):
    wins = [Fraction(0)] * team_count
    home_wins = Fraction(0)
    for match in matches:
        wins[match.home] += match.y
        wins[match.away] += 1 - match.y
        home_wins += match.y
    strengths = [1.0] * team_count
    theta = 1.0
    for _ in range(iterations):
        zeta = [0.0] * team_count
        for match in matches:
            q = theta * strengths[match.home] + strengths[match.away]
            zeta[match.home] += theta / q
            zeta[match.away] += 1 / q
        for team in range(team_count):
            strengths[team] = wins[team] / zeta[team]
        strength_sum = 0.0
        for strength in strengths:
            strength_sum += strength
        for team in range(team_count):
            strengths[team] = strengths[team] * team_count / strength_sum
        denominator = 0.0
        for match in matches:
            home = strengths[match.home]
            denominator += home / (theta * home + strengths[match.away])
        theta = home_wins / denominator
    return strengths, theta


def offense_defense(team_count, matches, iterations):
    points = [[0] * team_count for _ in range(team_count)]
    for match in matches:
        points[match.home][match.away] += match.away_score
        points[match.away][match.home] += match.home_score
    offense = [0.0] * team_count
    defense = [1.0] * team_count
    for _ in range(iterations):
        for j in range(team_count):
            total = 0.0
            for i in range(team_count):
                total += points[i][j] / defense[i]
            offense[j] = total
        for i in range(team_count):
            total = 0.0
            for j in range(team_count):
                total += points[i][j] / offense[j]
            defense[i] = total
    ratings = [offense[team] / defense[team] for team in range(team_count)]
    return offense, defense, ratings
