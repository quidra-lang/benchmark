import os
from fractions import Fraction


class Team:
    def __init__(self, index, code, name):
        self.index = index
        self.code = code
        self.name = name


class Match:
    def __init__(self, round_number, home, away, home_score, away_score):
        self.round = round_number
        self.home = home
        self.away = away
        self.home_score = home_score
        self.away_score = away_score
        self.margin = home_score - away_score
        self.y = match_result(home_score, away_score)


class Settings:
    def __init__(self, values):
        self.win_points = int(values["WIN_POINTS"][0])
        self.draw_points = int(values["DRAW_POINTS"][0])
        self.form_length = int(values["FORM_LENGTH"][0])
        self.close_margin = int(values["CLOSE_MARGIN"][0])
        self.pythagorean_exponent = float(values["PYTHAGOREAN_EXPONENT"][0])
        self.elo_k = int(values["ELO_K"][0])
        self.elo_home = int(values["ELO_HOME"][0])
        self.elo_initial = int(values["ELO_INITIAL"][0])
        self.grid_k = [int(value) for value in values["ELO_GRID_K"]]
        self.grid_home = [int(value) for value in values["ELO_GRID_HOME"]]
        self.bt_iterations = int(values["BT_ITERATIONS"][0])
        self.od_iterations = int(values["OD_ITERATIONS"][0])
        self.link_iterations = int(values["LINK_ITERATIONS"][0])
        self.holdout_round = int(values["HOLDOUT_ROUND"][0])
        self.upsets = int(values["UPSETS"][0])
        self.calibration_bins = int(values["CALIBRATION_BINS"][0])
        self.simulations = int(values["SIMULATIONS"][0])
        self.seed = int(values["SIM_SEED"][0])
        self.top_positions = int(values["TOP_POSITIONS"][0])
        self.bottom_positions = int(values["BOTTOM_POSITIONS"][0])


def match_result(home_score, away_score):
    if home_score > away_score:
        return Fraction(1)
    if home_score == away_score:
        return Fraction(1, 2)
    return Fraction(0)


def matches_before(matches, round_number):
    return [match for match in matches if match.round < round_number]


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def read_teams(path):
    teams = []
    for line in read_lines(path)[1:]:
        code, name = line.split(",")
        teams.append(Team(len(teams), code, name))
    return teams


def read_matches(path, teams):
    indices = {team.code: team.index for team in teams}
    matches = []
    for line in read_lines(path)[1:]:
        round_text, home, away, home_score, away_score = line.split(",")
        matches.append(
            Match(int(round_text), indices[home], indices[away], int(home_score), int(away_score))
        )
    matches.sort(key=lambda match: match.round)
    return matches


def read_settings(path):
    values = {}
    for line in read_lines(path):
        keyword, *arguments = line.split(" ")
        values[keyword] = arguments
    return Settings(values)


def load_season(folder):
    teams = read_teams(os.path.join(folder, "teams.csv"))
    matches = read_matches(os.path.join(folder, "matches.csv"), teams)
    settings = read_settings(os.path.join(folder, "params.txt"))
    return teams, matches, settings
