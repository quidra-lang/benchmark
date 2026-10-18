import os


INPUT_DIR = "input"
POINTS_FILE = "points.csv"
PARAMS_FILE = "params.txt"


class Point:
    def __init__(self, point_id, x, y):
        self.id = point_id
        self.x = x
        self.y = y


class Params:
    def __init__(self, values):
        self.eps_list = [int(value) for value in values["EPS"]]
        self.min_pts = int(values["MIN_PTS"][0])
        self.max_eps = int(values["OPTICS_MAX_EPS"][0])
        self.extract_eps = [int(value) for value in values["EXTRACT_EPS"]]
        self.xi_text = values["XI"][0]
        numerator, denominator = self.xi_text.split("/")
        self.xi_u = int(numerator)
        self.xi_v = int(denominator)
        self.xi_min_size = int(values["XI_MIN_SIZE"][0])
        self.map_width, self.map_height = (int(value) for value in values["MAP_SIZE"])
        self.kdist_width, self.kdist_height = (int(value) for value in values["KDIST_PLOT"])
        self.plot_width = int(values["PLOT_WIDTH"][0])


def read_lines(name):
    with open(os.path.join(INPUT_DIR, name)) as file:
        return file.read().splitlines()


def read_points():
    points = []
    for line in read_lines(POINTS_FILE)[1:]:
        point_id, x, y = (int(field) for field in line.split(","))
        points.append(Point(point_id, x, y))
    points.sort(key=lambda point: point.id)
    return points


def read_params():
    values = {}
    for line in read_lines(PARAMS_FILE):
        keyword, *fields = line.split(" ")
        values[keyword] = fields
    return Params(values)
