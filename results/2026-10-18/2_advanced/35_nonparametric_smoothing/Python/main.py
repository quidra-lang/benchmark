"""Compare nonparametric smoothers and write the seven specified result files."""

from bisect import bisect_right
from math import floor, sqrt
from pathlib import Path

from dataset import hundredths, read_dataset
from kernels import KernelFit
from loess import LoessFit
from selection import choose_candidate, cross_validation_score, generalized_score, ordered_sum
from spline import SplineFit


class LinearFit:
    def __init__(self, points):
        self.x = [x / 100 for x, _ in points]
        y = [value / 100 for _, value in points]
        n = len(points)
        self.xbar = ordered_sum(self.x) / n
        ybar = ordered_sum(y) / n
        self.sxx = ordered_sum((x - self.xbar) * (x - self.xbar) for x in self.x)
        sxy = ordered_sum((x - self.xbar) * (value - ybar)
                          for x, value in zip(self.x, y))
        self.slope = sxy / self.sxx
        self.intercept = ybar - self.slope * self.xbar
        self.fitted = [self.intercept + self.slope * x for x in self.x]
        self.leverage = [1 / n + (x - self.xbar) * (x - self.xbar) / self.sxx
                         for x in self.x]
        self.edf = 2.0

    def estimate(self, position):
        return self.intercept + self.slope * (position / 100)

    def weights(self, position):
        return [1 / len(self.x) + (position / 100 - self.xbar)
                * (x - self.xbar) / self.sxx for x in self.x]


class RunningFit:
    def __init__(self, points, width, use_median):
        self.positions = [point[0] for point in points]
        n = len(points)
        half = (width - 1) // 2
        self.windows = []
        self.fitted = []
        diagonal = []
        for i in range(n):
            radius = min(half, i, n - 1 - i)
            left, right = i - radius, i + radius + 1
            values = [point[1] for point in points[left:right]]
            self.windows.append((left, right))
            value = (sorted(values)[radius] / 100 if use_median
                     else sum(values) / (100 * len(values)))
            self.fitted.append(value)
            diagonal.append(1 / len(values))
        self.leverage = None if use_median else diagonal
        self.edf = None if use_median else ordered_sum(diagonal)

    def nearest(self, position):
        return min(range(len(self.positions)),
                   key=lambda i: (abs(self.positions[i] - position), i))

    def estimate(self, position):
        return self.fitted[self.nearest(position)]

    def weights(self, position):
        left, right = self.windows[self.nearest(position)]
        return [1 / (right - left) if left <= i < right else 0.0
                for i in range(len(self.positions))]


class IsotonicFit:
    def __init__(self, points, mode):
        self.positions = [point[0] for point in points]
        self.mode = mode
        if mode == "auto":
            increasing = self.fit_direction(points, "increasing")
            decreasing = self.fit_direction(points, "decreasing")
            observed = [y / 100 for _, y in points]
            self.rss_increasing = residual_square(observed, increasing[0])
            self.rss_decreasing = residual_square(observed, decreasing[0])
            self.direction = ("increasing" if self.rss_increasing <= self.rss_decreasing
                              else "decreasing")
            self.fitted, self.blocks = (increasing if self.direction == "increasing"
                                        else decreasing)
        else:
            self.direction = mode
            self.fitted, self.blocks = self.fit_direction(points, mode)
        self.leverage = None
        self.edf = float(len(self.blocks))

    @staticmethod
    def fit_direction(points, direction):
        blocks = []
        for i, (_, value) in enumerate(points):
            blocks.append((i, i, value, 1))
            while len(blocks) >= 2:
                left, right = blocks[-2:]
                a, b = left[2] * right[3], right[2] * left[3]
                violates = a > b if direction == "increasing" else a < b
                if not violates:
                    break
                blocks[-2:] = [(left[0], right[1], left[2] + right[2], left[3] + right[3])]
        fitted = [0.0] * len(points)
        for start, stop, total, count in blocks:
            value = total / (100 * count)
            fitted[start:stop + 1] = [value] * count
        return fitted, blocks

    def estimate(self, position):
        index = max(0, bisect_right(self.positions, position) - 1)
        return self.fitted[index]


def residual_square(observed, fitted):
    return ordered_sum((y - estimate) * (y - estimate)
                       for y, estimate in zip(observed, fitted))


def methods_in_order(settings):
    return (["linear", "running_mean", "running_median"]
            + ["nw_" + name for name in settings["KERNELS"]]
            + ["ll_" + name for name in settings["KERNELS"]]
            + ["loess" + degree for degree in settings["LOESS_DEGREES"]]
            + ["spline", "isotonic"])


def parameters_for(method, settings):
    if method.startswith("running_"):
        return settings["WINDOWS"]
    if method.startswith(("nw_", "ll_")):
        return settings["BANDWIDTHS"]
    if method.startswith("loess"):
        return settings["SPANS"]
    if method == "spline":
        return settings["LAMBDAS"]
    return []


def fit_model(method, parameter, points, settings, direction,
              robust=True, diagnostics=True):
    if method == "linear":
        return LinearFit(points)
    if method.startswith("running_"):
        return RunningFit(points, int(parameter), method == "running_median")
    if method == "isotonic":
        return IsotonicFit(points, direction)
    positions = [x for x, _ in points]
    values = [y / 100 for _, y in points]
    if method.startswith(("nw_", "ll_")):
        return KernelFit(positions, values, hundredths(parameter), method[3:],
                         method.startswith("ll_"), diagnostics)
    if method.startswith("loess"):
        iterations = settings["ROBUST_ITERATIONS"] if robust else 0
        return LoessFit(positions, values, hundredths(parameter), int(method[5:]),
                        iterations, diagnostics)
    return SplineFit(positions, values, float(parameter), diagnostics)


def validation_predictions(method, parameter, points, settings, direction, folds):
    predictions = [None] * len(points)
    for group in range(folds):
        training = [point for i, point in enumerate(points) if i % folds != group]
        model = fit_model(method, parameter, training, settings, direction,
                          robust=False, diagnostics=False)
        for i in range(group, len(points), folds):
            predictions[i] = model.estimate(points[i][0])
    return predictions


def select_models(points, settings, methods, isotonic_mode):
    observed = [y / 100 for _, y in points]
    entries = {}
    for method in methods:
        candidates = []
        for parameter in parameters_for(method, settings):
            candidate = fit_model(method, parameter, points, settings, isotonic_mode,
                                  robust=False)
            if method == "spline":
                score = generalized_score(observed, candidate.fitted, candidate.edf)
            else:
                predicted = validation_predictions(method, parameter, points, settings,
                                                   isotonic_mode, len(points))
                score = cross_validation_score(observed, predicted)
            candidates.append({"parameter": parameter, "score": score,
                               "edf": candidate.edf, "selected": False})
        if candidates:
            best = choose_candidate(candidates)
            candidates[best]["selected"] = True
            parameter = candidates[best]["parameter"]
        else:
            parameter = "-" if method == "linear" else isotonic_mode
        model = fit_model(method, parameter, points, settings, isotonic_mode)
        direction = model.direction if method == "isotonic" else isotonic_mode
        if method == "isotonic":
            parameter = direction
        if candidates and method != "spline":
            loo = candidates[best]["score"]
        else:
            predicted = validation_predictions(method, parameter, points, settings,
                                               direction, len(points))
            loo = cross_validation_score(observed, predicted)
        kfold = validation_predictions(method, parameter, points, settings,
                                       direction, settings["CV_FOLDS"])
        entries[method] = {"model": model, "parameter": parameter, "loo": loo,
                           "kfold": cross_validation_score(observed, kfold),
                           "candidates": candidates,
                           "gcv": candidates[best]["score"] if method == "spline" else None}
    return entries


def quantiles(residuals):
    ordered = sorted(residuals)
    result = []
    for k in range(5):
        index, remainder = divmod((len(ordered) - 1) * k, 4)
        value = ordered[index]
        if remainder:
            value += remainder / 4 * (ordered[index + 1] - ordered[index])
        result.append(value)
    return result


def residual_runs(residuals):
    signs = [1 if value > 0 else -1 for value in residuals if value != 0]
    positive = signs.count(1)
    negative = signs.count(-1)
    count = positive + negative
    runs = 1 + sum(a != b for a, b in zip(signs, signs[1:]))
    product = 2 * positive * negative
    mean = 1 + product / count
    variance = product * (product - count) / (count * count * (count - 1))
    return runs, positive, negative, (runs - mean) / sqrt(variance)


def turning_count(grid_values):
    values = [value for value in grid_values if value is not None]
    differences = [b - a for a, b in zip(values, values[1:]) if b != a]
    return sum((a > 0) != (b > 0) for a, b in zip(differences, differences[1:]))


def diagnostics(method, model, observed, grid_values, linear_rss):
    residuals = [y - fit for y, fit in zip(observed, model.fitted)]
    count = len(observed)
    rss = ordered_sum(value * value for value in residuals)
    mean = ordered_sum(observed) / count
    tss = ordered_sum((y - mean) * (y - mean) for y in observed)
    edf = model.edf
    df = None if edf is None else count - edf
    rse = None if edf is None else sqrt(rss / df)
    nonlinear = None
    if method != "linear" and edf is not None and edf > 2:
        nonlinear = ((linear_rss - rss) / (edf - 2)) / (rss / df)
    residual_mean = ordered_sum(residuals) / count
    centered = [value - residual_mean for value in residuals]
    denominator = ordered_sum(value * value for value in centered)
    acf = [ordered_sum(centered[i] * centered[i + lag] for i in range(count - lag))
           / denominator for lag in range(1, 6)]
    dw = ordered_sum((b - a) * (b - a) for a, b in zip(residuals, residuals[1:])) / rss
    largest = max(range(count), key=lambda i: (abs(residuals[i]), -i))
    return {"residuals": residuals, "rss": rss, "edf": edf, "df": df,
            "rse": rse, "r2": 1 - rss / tss, "f_nonlinear": nonlinear,
            "acf": acf, "dw": dw, "runs": residual_runs(residuals),
            "largest": largest, "quantiles": quantiles(residuals),
            "turning": turning_count(grid_values)}


def agreements(entries, methods, ranking, grid):
    best = entries[ranking[0]]["grid_values"]
    result = {}
    for method in methods:
        if method == ranking[0]:
            continue
        own = entries[method]["grid_values"]
        pairs = [(i, abs(value - target)) for i, (value, target) in enumerate(zip(own, best))
                 if value is not None and target is not None]
        maximum = max(pairs, key=lambda pair: (pair[1], -pair[0]))
        result[method] = (len(pairs), sqrt(ordered_sum(d * d for _, d in pairs) / len(pairs)),
                          maximum[1], grid[maximum[0]])
    return result


def spline_slopes(values, grid):
    slopes = [(i, (values[i + 1] - values[i - 1]) / ((grid[i + 1] - grid[i - 1]) / 100))
              for i in range(1, len(grid) - 1)]
    maximum = max(slopes, key=lambda pair: (pair[1], -pair[0]))
    minimum = min(slopes, key=lambda pair: (pair[1], pair[0]))
    return maximum[1], grid[maximum[0]], minimum[1], grid[minimum[0]]


def outliers_and_influence(entries, ranking, threshold):
    method = next(name for name in ranking if entries[name]["model"].leverage is not None)
    model = entries[method]["model"]
    stats = entries[method]["diagnostics"]
    standardized = {}
    cooks = {}
    for i, leverage in enumerate(model.leverage):
        if leverage < 1:
            value = stats["residuals"][i] / (stats["rse"] * sqrt(1 - leverage))
            standardized[i] = value
            cooks[i] = value * value * leverage / ((1 - leverage) * model.edf)
    outliers = sorted((i for i in standardized if abs(standardized[i]) > threshold),
                      key=lambda i: (-abs(standardized[i]), i))
    influential = sorted(cooks, key=lambda i: (-cooks[i], i))[:3]
    return {"method": method, "standardized": standardized, "cooks": cooks,
            "outliers": outliers, "influential": influential}


def variability_bands(model, rse, grid, z):
    rows = []
    for position in grid:
        value = model.estimate(position)
        if value is None:
            rows.append((None, None, None, None))
            continue
        weights = model.weights(position)
        se = rse * sqrt(ordered_sum(weight * weight for weight in weights))
        rows.append((value, se, value - z * se, value + z * se))
    return rows


def band_summary(entry, positions, bands, z):
    errors = [row[1] for row in bands if row[0] is not None]
    rse = entry["diagnostics"]["rse"]
    covered = 0
    for position, residual in zip(positions, entry["diagnostics"]["residuals"]):
        weights = entry["model"].weights(position)
        se = rse * sqrt(ordered_sum(value * value for value in weights))
        covered += abs(residual) <= z * sqrt(rse * rse + se * se)
    return ordered_sum(errors) / len(errors), covered


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def index(self, count):
        self.state = (48271 * self.state) % 2147483647
        return self.state % count


def bootstrap_intervals(entry, grid, count, trim, generator):
    model = entry["model"]
    residuals = entry["diagnostics"]["residuals"]
    mean = ordered_sum(residuals) / len(residuals)
    centered = [value - mean for value in residuals]
    estimates = [[] for _ in grid]
    for _ in range(count):
        response = [value + centered[generator.index(len(centered))] for value in model.fitted]
        fit = model.fit_values(response)
        for position, values in zip(grid, estimates):
            values.append(model.evaluate_fit(fit, position))
    result = []
    for position, values in zip(grid, estimates):
        average = ordered_sum(values) / count
        se = sqrt(ordered_sum((value - average) * (value - average) for value in values)
                  / (count - 1))
        ordered = sorted(values)
        result.append((model.estimate(position), se, ordered[trim], ordered[count - trim - 1]))
    return result


def analyze_series(points, settings, methods, mode, generator):
    positions = [point[0] for point in points]
    values = [point[1] / 100 for point in points]
    count = settings["GRID_POINTS"]
    grid = [positions[0] + k * (positions[-1] - positions[0]) // (count - 1)
            for k in range(count)]
    entries = select_models(points, settings, methods, mode)
    linear_rss = residual_square(values, entries["linear"]["model"].fitted)
    for method, entry in entries.items():
        entry["grid_values"] = [entry["model"].estimate(position) for position in grid]
        entry["diagnostics"] = diagnostics(method, entry["model"], values,
                                            entry["grid_values"], linear_rss)
    ranking = sorted(methods, key=lambda method: (entries[method]["loo"], methods.index(method)))
    outlier_data = outliers_and_influence(entries, ranking, settings["OUTLIER_THRESHOLD"])
    bands = {}
    summaries = {}
    for method in settings["BAND_METHODS"]:
        entry = entries[method]
        bands[method] = variability_bands(entry["model"], entry["diagnostics"]["rse"],
                                         grid, settings["BAND_Z"])
        summaries[method] = band_summary(entry, positions, bands[method], settings["BAND_Z"])
    repetitions, trim, _ = settings["BOOTSTRAP"]
    bands["spline_bootstrap"] = bootstrap_intervals(entries["spline"], grid,
                                                  repetitions, trim, generator)
    return {"points": points, "grid": grid, "entries": entries, "ranking": ranking,
            "agreement": agreements(entries, methods, ranking, grid),
            "slope": spline_slopes(entries["spline"]["grid_values"], grid),
            "outlier": outlier_data, "bands": bands, "band_summary": summaries}


def real(value, places=4):
    if value is None:
        return "NA"
    result = f"{value:.{places}f}"
    zero = f"{0:.{places}f}"
    return zero if result == "-" + zero else result


def position_text(value):
    whole, fraction = divmod(abs(value), 100)
    return ("-" if value < 0 else "") + f"{whole}.{fraction:02d}"


def real_list(values):
    return " ".join(real(value) for value in values)


def write_lines(name, lines):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")


def join_blocks(blocks):
    lines = []
    for block in blocks:
        if lines:
            lines.append("")
        lines.extend(block)
    return lines


def selection_lines(analyses, methods):
    lines = ["series,method,parameter,score,edf,selected"]
    for name, analysis in analyses.items():
        for method in methods:
            for candidate in analysis["entries"][method]["candidates"]:
                lines.append(",".join((name, method, candidate["parameter"],
                                       real(candidate["score"]), real(candidate["edf"]),
                                       "1" if candidate["selected"] else "0")))
    return lines


def fit_lines(analyses, methods):
    lines = ["series,x," + ",".join(methods)]
    for name, analysis in analyses.items():
        for i, position in enumerate(analysis["grid"]):
            values = [real(analysis["entries"][method]["grid_values"][i]) for method in methods]
            lines.append(",".join([name, position_text(position)] + values))
    return lines


def prediction_lines(analyses, tests, methods):
    lines = ["series,x," + ",".join(methods)]
    for name, position in tests:
        values = [real(analyses[name]["entries"][method]["model"].estimate(position))
                  for method in methods]
        lines.append(",".join([name, position_text(position)] + values))
    return lines


def band_lines(analyses, settings):
    lines = ["series,method,x,fit,se,lower,upper"]
    for name, analysis in analyses.items():
        for method in settings["BAND_METHODS"] + ["spline_bootstrap"]:
            for position, values in zip(analysis["grid"], analysis["bands"][method]):
                lines.append(",".join([name, method, position_text(position)]
                                       + [real(value) for value in values]))
    return lines


def method_diagnostic_lines(method, entry, points):
    stats = entry["diagnostics"]
    first = f"method {method} parameter {entry['parameter']} loo {real(entry['loo'])}"
    if method == "spline":
        first += " gcv " + real(entry["gcv"])
    runs, positive, negative, z = stats["runs"]
    largest = stats["largest"]
    lines = [first,
             f"  rss {real(stats['rss'])} edf {real(stats['edf'])} df {real(stats['df'])} "
             f"rse {real(stats['rse'])} r2 {real(stats['r2'])} f_nonlinear {real(stats['f_nonlinear'])}",
             f"  acf {real_list(stats['acf'])} dw {real(stats['dw'])}",
             f"  runs {runs} positive {positive} negative {negative} z {real(z)}",
             f"  max_residual {real(stats['residuals'][largest])} "
             f"at {position_text(points[largest][0])} turning {stats['turning']}",
             "  quantiles " + real_list(stats["quantiles"])]
    if method.startswith("loess"):
        model = entry["model"]
        for iteration, scale, zero_count, change in model.records:
            lines.append(f"  robust {iteration} scale {real(scale)} "
                         f"zero_weight {zero_count} max_change {real(change)}")
        zero_points = [position_text(points[i][0]) for i, weight in enumerate(model.rho)
                       if weight == 0]
        lines.append("  zero_weight_points " + (" ".join(zero_points) if zero_points else "none"))
    return lines


def comparison_diagnostic_lines(analysis, methods):
    entries = analysis["entries"]
    ranking = analysis["ranking"]
    lines = ["ranking"]
    for rank, method in enumerate(ranking, 1):
        lines.append(f"  {rank} {method} {real(entries[method]['loo'])} "
                     f"kfold {real(entries[method]['kfold'])}")
    lines.append("agreement with " + ranking[0])
    for method in methods:
        if method == ranking[0]:
            continue
        count, rms, maximum, position = analysis["agreement"][method]
        lines.append(f"  {method} points {count} rms {real(rms)} "
                     f"max {real(maximum)} at {position_text(position)}")
    maximum, at_max, minimum, at_min = analysis["slope"]
    lines.append(f"slope spline max {real(maximum)} at {position_text(at_max)} "
                 f"min {real(minimum)} at {position_text(at_min)}")
    return lines


def outlier_diagnostic_lines(analysis, settings):
    data = analysis["outlier"]
    entry = analysis["entries"][data["method"]]
    model = entry["model"]
    residuals = entry["diagnostics"]["residuals"]
    points = analysis["points"]
    lines = [f"outliers method {data['method']} threshold {real(settings['OUTLIER_THRESHOLD'], 2)}"]
    for i in data["outliers"]:
        lines.append(f"  x {position_text(points[i][0])} y {position_text(points[i][1])} "
                     f"fit {real(model.fitted[i])} residual {real(residuals[i])} "
                     f"standardized {real(data['standardized'][i])}")
    if not data["outliers"]:
        lines.append("  none")
    lines.append("influence method " + data["method"])
    for i in data["influential"]:
        lines.append(f"  x {position_text(points[i][0])} lev {real(model.leverage[i])} "
                     f"cook {real(data['cooks'][i])}")
    lines.append("bands")
    for method in settings["BAND_METHODS"]:
        mean_se, covered = analysis["band_summary"][method]
        lines.append(f"  {method} mean_se {real(mean_se)} coverage {covered} of {len(points)}")
    return lines


def diagnostics_block(name, analysis, methods, settings):
    points = analysis["points"]
    low, high = min(y for _, y in points), max(y for _, y in points)
    lines = [f"series {name} n {len(points)} x {position_text(points[0][0])} "
             f"{position_text(points[-1][0])} y {position_text(low)} {position_text(high)}"]
    for method in methods:
        lines.extend(method_diagnostic_lines(method, analysis["entries"][method], points))
    lines.extend(comparison_diagnostic_lines(analysis, methods))
    lines.extend(outlier_diagnostic_lines(analysis, settings))
    return lines


def isotonic_block(name, analysis):
    entry = analysis["entries"]["isotonic"]
    model = entry["model"]
    first = f"series {name} direction {model.direction} mode {model.mode}"
    if model.mode == "auto":
        first += (f" rss_increasing {real(model.rss_increasing)} "
                  f"rss_decreasing {real(model.rss_decreasing)}")
    lines = [first, f"blocks {len(model.blocks)} rss {real(entry['diagnostics']['rss'])} "
                    f"loo {real(entry['loo'])}"]
    for number, (start, stop, total, count) in enumerate(model.blocks, 1):
        lines.append(f"block {number} x {position_text(model.positions[start])} "
                     f"{position_text(model.positions[stop])} count {count} "
                     f"value {real(total / (100 * count))}")
    return lines


def framed(grid):
    border = "+" + "-" * len(grid[0]) + "+"
    return [border] + ["|" + "".join(row) + "|" for row in grid] + [border]


def histogram_lines(standardized):
    counts = [0] * 14
    for value in standardized.values():
        index = 0 if value < -3 else 13 if value >= 3 else 1 + floor((value + 3) / 0.5)
        counts[index] += 1
    lines = []
    for i, count in enumerate(counts):
        lower = "-inf" if i == 0 else real(-3 + 0.5 * (i - 1), 2)
        upper = "inf" if i == 13 else real(-3 + 0.5 * i, 2)
        lines.append(f"{lower} {upper} {count} |" + "#" * count)
    return lines


def plot_block(name, analysis, settings):
    points = analysis["points"]
    width, height = settings["PLOT_SIZE"]
    xa, xb = points[0][0], points[-1][0]
    ya, yb = min(y for _, y in points), max(y for _, y in points)
    columns = [min(width - 1, width * (x - xa) // (xb - xa)) for x, _ in points]
    grid = [[" "] * width for _ in range(height)]
    for column, (_, y) in zip(columns, points):
        row = min(height - 1, height * (yb - y) // (yb - ya))
        grid[row][column] = "."
    for number, method in enumerate(settings["PLOT_METHODS"], 1):
        model = analysis["entries"][method]["model"]
        for column in range(width):
            position = xa + (2 * column + 1) * (xb - xa) // (2 * width)
            value = model.estimate(position)
            if value is None:
                continue
            pi = height * (yb / 100 - value) / (yb / 100 - ya / 100)
            row = max(0, min(height - 1, floor(pi)))
            digit = str(number)
            grid[row][column] = digit if grid[row][column] in (" ", ".", digit) else "*"
    cells = "".join("".join(row) for row in grid)
    lines = [f"plot {name} size {width}x{height} x {position_text(xa)} {position_text(xb)} "
             f"y {position_text(ya)} {position_text(yb)}",
             "legend . data " + " ".join(f"{i} {method}" for i, method in
                                         enumerate(settings["PLOT_METHODS"], 1))]
    lines.extend(framed(grid))
    lines.append(f"cells data {cells.count('.')} curve {sum(c.isdigit() for c in cells)} "
                 f"overlap {cells.count('*')}")
    method = analysis["ranking"][0]
    residuals = analysis["entries"][method]["diagnostics"]["residuals"]
    limit = max(abs(value) for value in residuals)
    grid = [[" "] * width for _ in range(height)]
    grid[height // 2] = ["-"] * width
    for column, residual in zip(columns, residuals):
        row = max(0, min(height - 1, floor(height * ((limit - residual) / (2 * limit)))))
        grid[row][column] = "o"
    lines.extend(["", f"residuals {name} method {method} limit {real(limit)}"])
    lines.extend(framed(grid))
    lines.extend(["", f"histogram {name} method {analysis['outlier']['method']}"])
    lines.extend(histogram_lines(analysis["outlier"]["standardized"]))
    return lines


def main():
    series, tests, settings = read_dataset()
    methods = methods_in_order(settings)
    generator = Minstd(settings["BOOTSTRAP"][2])
    analyses = {}
    for (name, points), mode in zip(series.items(), settings["ISOTONIC"]):
        analyses[name] = analyze_series(points, settings, methods, mode, generator)
    write_lines("selection.csv", selection_lines(analyses, methods))
    write_lines("fits.csv", fit_lines(analyses, methods))
    write_lines("predictions.csv", prediction_lines(analyses, tests, methods))
    write_lines("bands.csv", band_lines(analyses, settings))
    write_lines("diagnostics.txt", join_blocks([
        diagnostics_block(name, analysis, methods, settings)
        for name, analysis in analyses.items()
    ]))
    write_lines("isotonic.txt", join_blocks([
        isotonic_block(name, analysis) for name, analysis in analyses.items()
    ]))
    write_lines("plots.txt", join_blocks([
        plot_block(name, analyses[name], settings) for name in settings["PLOT_SERIES"]
    ]))


if __name__ == "__main__":
    main()
