"""Deterministic SGD and ALS, with the specified Cholesky solver."""

from math import sqrt

from evaluation import training_rmse


class RandomGenerator:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = (48271 * self.state) % 2147483647
        return self.state

    def factor(self):
        return ((self.draw() % 2001) - 1000) / 10000


def dot(left, right):
    total = 0.0
    for first, second in zip(left, right):
        total += first * second
    return total


class FactorModel:
    def __init__(self, mean, users, items, user_bias, item_bias):
        self.mean = mean
        self.users = users
        self.items = items
        self.user_bias = user_bias
        self.item_bias = item_bias

    def predict(self, user, item):
        baseline = (self.mean + self.user_bias[user]) + self.item_bias[item]
        return baseline + dot(self.users[user], self.items[item])


def train_svd(data):
    params = data.params
    random = RandomGenerator(params["seed"])
    factors = params["factors"]
    users = {user: [random.factor() for _ in range(factors)] for user in data.users}
    items = {item: [random.factor() for _ in range(factors)] for item in data.items}
    user_bias = dict.fromkeys(data.users, 0.0)
    item_bias = dict.fromkeys(data.items, 0.0)
    model = FactorModel(data.mean, users, items, user_bias, item_bias)
    order = list(range(len(data.training)))
    rate = params["learning_rate"]
    regularization = params["regularization"]
    log = []
    for epoch in range(1, params["epochs"] + 1):
        for position in range(len(order) - 1, 0, -1):
            other = random.draw() % (position + 1)
            order[position], order[other] = order[other], order[position]
        for position in order:
            user, item, rating, timestamp = data.training[position]
            error = rating - model.predict(user, item)
            user_bias[user] += rate * (error - regularization * user_bias[user])
            item_bias[item] += rate * (error - regularization * item_bias[item])
            for factor in range(factors):
                a = users[user][factor]
                b = items[item][factor]
                users[user][factor] = a + rate * (error * b - regularization * a)
                items[item][factor] = b + rate * (error * a - regularization * b)
        log.append(("SVD", epoch, training_rmse(data.training, model.predict)))
    return model, log


def cholesky_solve(matrix, target):
    size = len(target)
    lower = [[0.0] * size for _ in range(size)]
    for row in range(size):
        for column in range(row + 1):
            total = 0.0
            for index in range(column):
                total += lower[row][index] * lower[column][index]
            remainder = matrix[row][column] - total
            if row == column:
                lower[row][column] = sqrt(remainder)
            else:
                lower[row][column] = remainder / lower[column][column]
    intermediate = [0.0] * size
    for row in range(size):
        total = 0.0
        for index in range(row):
            total += lower[row][index] * intermediate[index]
        intermediate[row] = (target[row] - total) / lower[row][row]
    solution = [0.0] * size
    for row in range(size - 1, -1, -1):
        total = 0.0
        for index in range(row + 1, size):
            total += lower[index][row] * solution[index]
        solution[row] = (intermediate[row] - total) / lower[row][row]
    return solution


def fit_vector(observations, factors, regularization):
    matrix = [[0.0] * factors for _ in range(factors)]
    target = [0.0] * factors
    for vector, residual in observations:
        for row in range(factors):
            target[row] += residual * vector[row]
            for column in range(factors):
                matrix[row][column] += vector[row] * vector[column]
    for row in range(factors):
        matrix[row][row] += regularization * len(observations)
    return cholesky_solve(matrix, target)


def train_als(data, user_bias, item_bias):
    params = data.params
    factors = params["factors"]
    random = RandomGenerator(params["seed"])
    items = {item: [random.factor() for _ in range(factors)] for item in data.items}
    users = {}
    residuals = {
        (user, item): rating - ((data.mean + user_bias[user]) + item_bias[item])
        for user, item, rating, timestamp in data.training
    }
    model = FactorModel(data.mean, users, items, user_bias, item_bias)
    log = []
    for iteration in range(1, params["als_iterations"] + 1):
        for user in data.users:
            observations = [
                (items[item], residuals[user, item]) for item in data.by_user[user]
            ]
            users[user] = fit_vector(observations, factors, params["als_reg"])
        for item in data.items:
            observations = [
                (users[user], residuals[user, item]) for user in data.by_item[item]
            ]
            items[item] = fit_vector(observations, factors, params["als_reg"])
        log.append(("ALS", iteration, training_rmse(data.training, model.predict)))
    return model, log
