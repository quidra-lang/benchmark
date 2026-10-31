"""Read the four inputs and organize the sparse rating tables by ID."""

import csv
from pathlib import Path


class Ratings:
    def __init__(self, training, test, titles, genre_text, params):
        self.training = training
        self.test = test
        self.titles = titles
        self.genre_text = genre_text
        self.genres = {item: text.split("|") for item, text in genre_text.items()}
        self.params = params
        users = {}
        items = {}
        for user, item, rating, timestamp in training:
            users.setdefault(user, {})[item] = rating
            items.setdefault(item, {})[user] = rating
        self.users = sorted(users)
        self.items = sorted(items)
        self.by_user = {user: dict(sorted(users[user].items())) for user in self.users}
        self.by_item = {item: dict(sorted(items[item].items())) for item in self.items}
        self.user_counts = {user: len(self.by_user[user]) for user in self.users}
        self.item_counts = {item: len(self.by_item[item]) for item in self.items}
        self.user_means = {
            user: sum(self.by_user[user].values()) / self.user_counts[user]
            for user in self.users
        }
        self.item_means = {
            item: sum(self.by_item[item].values()) / self.item_counts[item]
            for item in self.items
        }
        self.mean = sum(row[2] for row in training) / len(training)


def read_integer_csv(path):
    with path.open(encoding="ascii", newline="") as stream:
        rows = csv.reader(stream)
        next(rows)
        return [tuple(map(int, row)) for row in rows]


def read_params(path):
    real_keys = {
        "MIN_SIMILARITY", "BIAS_REG", "LEARNING_RATE", "REGULARIZATION", "ALS_REG"
    }
    list_keys = {
        "BIAS_REG", "CUTOFFS", "NEIGHBOR_GRID", "USER_GROUPS", "ITEM_GROUPS",
        "RECOMMEND_USERS", "SIMILAR_ITEMS"
    }
    params = {}
    with path.open(encoding="ascii") as stream:
        for line in stream:
            key, *values = line.split()
            convert = float if key in real_keys else int
            converted = [convert(value) for value in values]
            params[key.lower()] = converted if key in list_keys else converted[0]
    return params


def read_inputs(directory="input"):
    directory = Path(directory)
    training = read_integer_csv(directory / "ratings.csv")
    test = read_integer_csv(directory / "test.csv")
    titles = {}
    genre_text = {}
    with (directory / "items.csv").open(encoding="ascii", newline="") as stream:
        rows = csv.reader(stream)
        next(rows)
        for item, title, genres in rows:
            titles[int(item)] = title
            genre_text[int(item)] = genres
    return Ratings(training, test, titles, genre_text, read_params(directory / "params.txt"))
