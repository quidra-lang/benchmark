from math import sqrt


class LocalFit:
    def __init__(self, estimate, zeta, members, scaled, bases):
        self.estimate = estimate
        self.zeta = zeta
        self.members = members
        self.scaled = scaled
        self.bases = bases

    def zeta0(self):
        return self.zeta[0]

    def weights(self, count):
        weights = [0.0] * count
        for j, v, basis in zip(self.members, self.scaled, self.bases):
            combination = 0.0
            for k in range(len(basis)):
                combination += self.zeta[k] * basis[k]
            weights[j] = v * combination
        return weights


class RobustRound:
    def __init__(self, scale, zero_count, max_change):
        self.scale = scale
        self.zero_count = zero_count
        self.max_change = max_change


class LoessFit:
    def __init__(self, fitted, rho, leverages, rounds):
        self.fitted = fitted
        self.rho = rho
        self.leverages = leverages
        self.rounds = rounds


def median(values):
    ordered = sorted(values)
    m = len(ordered)
    if m % 2 == 1:
        return ordered[m // 2]
    return (ordered[m // 2 - 1] + ordered[m // 2]) / 2


def neighbourhood(points, span, position):
    q = span * points.n // 100
    order = sorted(range(points.n), key=lambda j: (abs(points.X[j] - position), j))
    members = sorted(order[:q])
    extent = max(abs(points.X[j] - position) for j in members)
    return members, extent


def tricube(distance, extent):
    a = distance / extent
    s = 1 - a * a * a
    return s * s * s


def cholesky(matrix):
    size = len(matrix)
    lower = [[0.0] * size for _ in range(size)]
    for row in range(size):
        for column in range(row + 1):
            sigma = matrix[row][column]
            for i in range(column):
                sigma -= lower[row][i] * lower[column][i]
            if column == row:
                lower[row][row] = sqrt(sigma)
            else:
                lower[row][column] = sigma / lower[column][column]
    return lower


def solve(lower, right):
    size = len(lower)
    eta = [0.0] * size
    for k in range(size):
        value = right[k]
        for i in range(k):
            value -= lower[k][i] * eta[i]
        eta[k] = value / lower[k][k]
    solution = [0.0] * size
    for k in range(size - 1, -1, -1):
        value = eta[k]
        for i in range(k + 1, size):
            value -= lower[i][k] * solution[i]
        solution[k] = value / lower[k][k]
    return solution


def local_fit(points, rho, degree, span, position):
    members, extent = neighbourhood(points, span, position)
    x0 = position / 100
    size = degree + 1
    matrix = [[0.0] * size for _ in range(size)]
    right = [0.0] * size
    scaled = []
    bases = []
    for j in members:
        v = tricube(abs(points.X[j] - position), extent) * rho[j]
        d = points.x[j] - x0
        basis = [1.0, d] if degree == 1 else [1.0, d, d * d]
        for row in range(size):
            for column in range(row + 1):
                matrix[row][column] += v * basis[row] * basis[column]
            right[row] += v * basis[row] * points.y[j]
        scaled.append(v)
        bases.append(basis)
    lower = cholesky(matrix)
    beta = solve(lower, right)
    unit = [1.0] + [0.0] * degree
    zeta = solve(lower, unit)
    return LocalFit(beta[0], zeta, members, scaled, bases)


def fit_all(points, rho, degree, span):
    return [local_fit(points, rho, degree, span, position) for position in points.X]


def robustness_weights(residuals, scale):
    rho = []
    for e in residuals:
        u = e / (6 * scale)
        if abs(u) < 1:
            nu = 1 - u * u
            rho.append(nu * nu)
        else:
            rho.append(0.0)
    return rho


def robust_fit(points, degree, span, iterations):
    rho = [1.0] * points.n
    fits = fit_all(points, rho, degree, span)
    fitted = [fit.estimate for fit in fits]
    rounds = []
    for _ in range(iterations):
        residuals = [y - value for y, value in zip(points.y, fitted)]
        scale = median([abs(e) for e in residuals])
        rho = robustness_weights(residuals, scale)
        fits = fit_all(points, rho, degree, span)
        updated = [fit.estimate for fit in fits]
        change = max(abs(new - old) for new, old in zip(updated, fitted))
        rounds.append(RobustRound(scale, rho.count(0.0), change))
        fitted = updated
    leverages = [weight * fit.zeta0() for weight, fit in zip(rho, fits)]
    return LoessFit(fitted, rho, leverages, rounds)
