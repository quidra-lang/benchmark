import math
import os

from dataset import load_dataset
from eigen import POWER_ITERATIONS, jacobi, power_iteration
from matrix import column, dot, gauss_jordan, max_difference, orient, sequential_sum
from pca import (
    column_means, component_scores, correlation_matrix, covariance_matrix, hotelling_t2,
    residuals, standard_deviations, standardize,
)
from plot import (
    biplot_cell, circle_cell, diagnostic_cell, framed, new_grid, rounded_position, scree_line,
    shaft_cells, shaft_character,
)


INPUT_DIRECTORY = "input"
OUTPUT_DIRECTORY = "output"
STRATEGIES = ("listwise", "mean")
SCALINGS = ("covariance", "correlation")
CRITERIA = ("kaiser", "broken_stick", "parallel", "cumulative")
MINSTD_MULTIPLIER = 48271
MINSTD_MODULUS = 2147483647
EIGENVALUE_TOLERANCE = 1e-8
VECTOR_TOLERANCE = 0.000001
ARROW_SHRINK = 0.9
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
NEIGHBORS = ((-1, 0), (1, 0), (0, -1), (0, 1))


def real_text(value, digits=4):
    text = f"{value:.{digits}f}"
    if float(text) == 0:
        return text.lstrip("-")
    return text


def reals(values):
    return [real_text(value) for value in values]


def component_names(prefix, count):
    return [f"{prefix}{k}" for k in range(1, count + 1)]


def join_sections(sections):
    lines = []
    for section in sections:
        if lines:
            lines.append("")
        lines.extend(section)
    return lines


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIRECTORY, name), "w") as file:
        file.write("".join(line + "\n" for line in lines))


def has_missing(row):
    return any(value is None for value in row)


def top_indices(values, count):
    return sorted(range(len(values)), key=lambda i: (-values[i], i))[:count]


def largest_index(values):
    return max(range(len(values)), key=lambda i: values[i])


def smallest_index(values):
    return min(range(len(values)), key=lambda i: values[i])


def congruence(first, second):
    return dot(first, second) / math.sqrt(dot(first, first) * dot(second, second))


def explained_ratios(eigenvalues):
    total = sequential_sum(eigenvalues)
    return [value / total for value in eigenvalues]


def cumulative_ratios(ratios):
    cumulative = []
    running = 0.0
    for ratio in ratios:
        running += ratio
        cumulative.append(running)
    return cumulative


def first_crossing(ratios, thresholds):
    for k, (ratio, threshold) in enumerate(zip(ratios, thresholds)):
        if ratio <= threshold:
            return k
    return len(ratios)


def cumulative_count(cumulative, target):
    for k, value in enumerate(cumulative, 1):
        if value >= target:
            return k
    return len(cumulative)


def flag_text(t2, spe, settings):
    flag = ""
    if t2 > settings.t2_limit:
        flag += "T"
    if spe > settings.spe_limit:
        flag += "Q"
    return flag or "-"


def density_character(count):
    if count == 1:
        return "."
    if count <= 3:
        return "o"
    return "@"


def draw_axes(grid, center):
    row, col = center
    grid[row] = ["-"] * len(grid[row])
    for cells in grid:
        cells[col] = "|"
    grid[row][col] = "+"


def draw_points(grid, cells):
    counts = [[0] * len(line) for line in grid]
    for row, col in cells:
        counts[row][col] += 1
    for row, line in enumerate(counts):
        for col, count in enumerate(line):
            if count > 0:
                grid[row][col] = density_character(count)


def mark_cells(grid, cells, character):
    for row, col in cells:
        grid[row][col] = character


def inside_circle(row, col, center, radius):
    horizontal = col - center[1]
    vertical = 2 * (row - center[0])
    return horizontal * horizontal + vertical * vertical <= radius * radius


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def uniform(self):
        self.state = MINSTD_MULTIPLIER * self.state % MINSTD_MODULUS
        return self.state / MINSTD_MODULUS


class VariableSummary:
    def __init__(self, observed_values, total_rows):
        self.observed = len(observed_values)
        self.missing = total_rows - self.observed
        self.mean = sequential_sum(observed_values) / self.observed
        squares = sequential_sum((x - self.mean) * (x - self.mean) for x in observed_values)
        self.sd = math.sqrt(squares / (self.observed - 1))
        self.minimum = min(observed_values)
        self.maximum = max(observed_values)


class AnalysisData:
    def __init__(self, table, strategy, observed_means):
        self.ids = []
        self.values = []
        for row_id, row in zip(table.ids, table.rows):
            if strategy == "listwise" and has_missing(row):
                continue
            self.ids.append(row_id)
            self.values.append([
                mean if value is None else value for value, mean in zip(row, observed_means)
            ])


class Decomposition:
    def __init__(self, data, scaling):
        self.data = data
        self.means = column_means(data.values)
        self.covariance = covariance_matrix(data.values, self.means)
        self.deviations = standard_deviations(self.covariance)
        self.correlation = correlation_matrix(self.covariance, self.deviations)
        if scaling == "covariance":
            self.matrix = self.covariance
            self.scales = [1.0] * len(self.means)
        else:
            self.matrix = self.correlation
            self.scales = self.deviations
        self.eigen = jacobi(self.matrix)


class Adequacy:
    def __init__(self, correlation, rows):
        size = len(correlation)
        inverse, self.determinant = gauss_jordan(correlation)
        partial = [
            [0.0 if j == k else -inverse[j][k] / math.sqrt(inverse[j][j] * inverse[k][k])
             for k in range(size)]
            for j in range(size)
        ]
        self.correlation_squares = [
            sequential_sum(correlation[j][k] * correlation[j][k] for k in range(size) if k != j)
            for j in range(size)
        ]
        self.partial_squares = [
            sequential_sum(partial[j][k] * partial[j][k] for k in range(size) if k != j)
            for j in range(size)
        ]
        self.msa = [
            rr / (rr + pp) for rr, pp in zip(self.correlation_squares, self.partial_squares)
        ]
        total_rr = sequential_sum(self.correlation_squares)
        total_pp = sequential_sum(self.partial_squares)
        self.kmo = total_rr / (total_rr + total_pp)
        self.bartlett = -(rows - 1 - (2 * size + 5) / 6) * math.log(self.determinant)
        self.freedom = size * (size - 1) // 2


def parallel_analysis(rows, size, iterations, seed):
    generator = Minstd(seed)
    totals = [0.0] * size
    for _ in range(iterations):
        values = [[generator.uniform() for _ in range(size)] for _ in range(rows)]
        covariance = covariance_matrix(values, column_means(values))
        correlation = correlation_matrix(covariance, standard_deviations(covariance))
        ratios = explained_ratios(jacobi(correlation).values)
        for k in range(size):
            totals[k] += ratios[k]
    return [total / iterations for total in totals]


class VarianceTable:
    def __init__(self, eigenvalues, rows, parallel, target):
        size = len(eigenvalues)
        self.eigenvalues = eigenvalues
        self.total = sequential_sum(eigenvalues)
        self.average = self.total / size
        self.ratios = explained_ratios(eigenvalues)
        self.cumulative = cumulative_ratios(self.ratios)
        self.broken_stick = [
            sequential_sum(1 / i for i in range(k, size + 1)) / size for k in range(1, size + 1)
        ]
        self.parallel = parallel
        self.errors = [value * math.sqrt(2 / rows) for value in eigenvalues]
        self.separated = [self.is_separated(k) for k in range(size)]
        self.retention = {
            "kaiser": sum(1 for value in eigenvalues if value > self.average),
            "broken_stick": first_crossing(self.ratios, self.broken_stick),
            "parallel": first_crossing(self.ratios, parallel),
            "cumulative": cumulative_count(self.cumulative, target),
        }

    def is_separated(self, k):
        neighbors = [h for h in (k - 1, k + 1) if 0 <= h < len(self.eigenvalues)]
        return all(
            abs(self.eigenvalues[k] - self.eigenvalues[h]) > self.errors[k] for h in neighbors
        )


def varimax_criterion(g):
    count = len(g)
    total = 0.0
    for k in range(len(g[0])):
        q4 = sequential_sum((row[k] * row[k]) * (row[k] * row[k]) for row in g)
        q2 = sequential_sum(row[k] * row[k] for row in g)
        total += q4 / count - (q2 / count) * (q2 / count)
    return total


def rotate_pair(g, a, b):
    count = len(g)
    phi = [row[a] * row[a] - row[b] * row[b] for row in g]
    psi = [2 * row[a] * row[b] for row in g]
    sa = sequential_sum(phi)
    sb = sequential_sum(psi)
    sc = sequential_sum(f * f - p * p for f, p in zip(phi, psi))
    sd = sequential_sum(2 * f * p for f, p in zip(phi, psi))
    numerator = sd - 2 * sa * sb / count
    denominator = sc - (sa * sa - sb * sb) / count
    omega = math.sqrt(numerator * numerator + denominator * denominator)
    if omega == 0:
        return
    cos4 = denominator / omega
    sin4 = numerator / omega
    cos2 = math.sqrt((1 + cos4) / 2)
    sin2 = 1.0 if cos2 == 0 else sin4 / (2 * cos2)
    cos1 = math.sqrt((1 + cos2) / 2)
    sin1 = sin2 / (2 * cos1)
    for row in g:
        first, second = row[a], row[b]
        row[a] = cos1 * first + sin1 * second
        row[b] = -sin1 * first + cos1 * second


class Varimax:
    def __init__(self, loadings, components, cycles):
        size = len(loadings)
        etas = [
            math.sqrt(sequential_sum(row[k] * row[k] for k in range(components)))
            for row in loadings
        ]
        g = [[row[k] / eta for k in range(components)] for row, eta in zip(loadings, etas)]
        self.criteria = [varimax_criterion(g)]
        for _ in range(cycles):
            for a in range(components - 1):
                for b in range(a + 1, components):
                    rotate_pair(g, a, b)
            self.criteria.append(varimax_criterion(g))
        columns = [orient([g[j][k] * etas[j] for j in range(size)]) for k in range(components)]
        squares = [dot(values, values) for values in columns]
        order = sorted(range(components), key=lambda k: (-squares[k], k))
        self.columns = [columns[k] for k in order]
        self.squares = [squares[k] for k in order]
        self.closest = []
        self.congruences = []
        for rotated in self.columns:
            values = [abs(congruence(rotated, column(loadings, k))) for k in range(components)]
            best = largest_index(values)
            self.closest.append(best)
            self.congruences.append(values[best])


class Observation:
    def __init__(self, row_id, z, eigen, components, settings):
        self.id = row_id
        self.z = z
        self.scores = component_scores(z, eigen.vectors)
        self.t2 = hotelling_t2(self.scores, eigen.values, components)
        self.residuals = residuals(z, self.scores, eigen.vectors, components)
        self.spe = dot(self.residuals, self.residuals)
        self.flag = flag_text(self.t2, self.spe, settings)


class Sensitivity:
    def __init__(self, strategy, scaling, fit, reference, components):
        self.strategy = strategy
        self.scaling = scaling
        self.rows = len(fit.data.ids)
        self.sweeps = fit.eigen.sweeps
        self.eigenvalues = fit.eigen.values[:components]
        self.cumulative = cumulative_ratios(explained_ratios(fit.eigen.values))[components - 1]
        self.agreement = [
            abs(dot(fit.eigen.vectors[k], reference[k])) for k in range(components)
        ]


class PcaReport:
    def __init__(self, dataset):
        self.settings = dataset.settings
        self.data = dataset.data
        self.supplementary = dataset.supplementary
        self.names = self.data.names
        self.size = len(self.names)
        self.summaries = [
            VariableSummary(
                [row[j] for row in self.data.rows if row[j] is not None], len(self.data.rows)
            )
            for j in range(self.size)
        ]
        self.observed_means = [summary.mean for summary in self.summaries]
        self.incomplete = [
            row_id for row_id, row in zip(self.data.ids, self.data.rows) if has_missing(row)
        ]
        main_data = AnalysisData(self.data, self.settings.missing, self.observed_means)
        self.fit = Decomposition(main_data, self.settings.scaling)
        self.ids = main_data.ids
        self.rows = len(self.ids)
        self.eigenvalues = self.fit.eigen.values
        self.vectors = self.fit.eigen.vectors
        self.strongest = self.strongest_pairs()
        self.adequacy = Adequacy(self.fit.correlation, self.rows)
        self.power = power_iteration(self.fit.matrix, self.vectors)
        parallel = parallel_analysis(
            self.rows, self.size, self.settings.parallel_iterations, self.settings.seed
        )
        self.variance = VarianceTable(
            self.eigenvalues, self.rows, parallel, self.settings.cumulative_target
        )
        self.components = self.retained_components()
        self.compute_loadings()
        self.varimax = Varimax(self.loadings, self.components, self.settings.varimax_cycles)
        self.observations = [
            self.observation(row_id, values) for row_id, values in zip(self.ids, main_data.values)
        ]
        self.projections = [
            self.observation(row_id, values)
            for row_id, values in zip(self.supplementary.ids, self.supplementary.rows)
        ]
        self.sensitivity = [
            Sensitivity(
                strategy, scaling,
                Decomposition(AnalysisData(self.data, strategy, self.observed_means), scaling),
                self.vectors, self.components,
            )
            for strategy in STRATEGIES for scaling in SCALINGS
        ]

    def strongest_pairs(self):
        pairs = [(j, k) for j in range(self.size) for k in range(j + 1, self.size)]
        strengths = [abs(self.fit.correlation[j][k]) for j, k in pairs]
        return [pairs[i] for i in top_indices(strengths, self.settings.top_rows)]

    def retained_components(self):
        rule = self.settings.components
        if rule in CRITERIA:
            return max(self.variance.retention[rule], 1)
        return int(rule)

    def compute_loadings(self):
        self.loadings = [
            [vector[j] * math.sqrt(value) for value, vector in zip(self.eigenvalues, self.vectors)]
            for j in range(self.size)
        ]
        self.communalities = []
        self.circle = []
        for j, row in enumerate(self.loadings):
            diagonal = self.fit.matrix[j][j]
            squares = sequential_sum(row[k] * row[k] for k in range(self.components))
            self.communalities.append(squares / diagonal)
            self.circle.append([row[k] / math.sqrt(diagonal) for k in range(2)])

    def observation(self, row_id, values):
        z = standardize(values, self.fit.means, self.fit.scales)
        return Observation(row_id, z, self.fit.eigen, self.components, self.settings)

    def quality(self, observation):
        retained = observation.scores[:self.components]
        return dot(retained, retained) / dot(observation.z, observation.z)

    def t2_contributions(self, observation):
        contributions = []
        for j, value in enumerate(observation.z):
            weight = sequential_sum(
                observation.scores[k] / self.eigenvalues[k] * self.vectors[k][j]
                for k in range(self.components)
            )
            contributions.append(value * weight)
        return contributions

    def nearest_row(self, projection):
        distances = []
        for observation in self.observations:
            differences = [
                projection.scores[k] - observation.scores[k] for k in range(self.components)
            ]
            distances.append(dot(differences, differences))
        nearest = smallest_index(distances)
        return nearest, math.sqrt(distances[nearest])

    def summary_section(self):
        settings = self.settings
        if self.incomplete:
            incomplete = " ".join([str(len(self.incomplete))] + self.incomplete)
        else:
            incomplete = "0 -"
        return [
            f"pca rows {len(self.data.ids)} used {self.rows} variables {self.size}"
            f" missing {settings.missing} scaling {settings.scaling}",
            f"incomplete {incomplete}",
        ]

    def variable_section(self):
        lines = ["variable observed missing mean sd min max msa"]
        for name, summary, msa in zip(self.names, self.summaries, self.adequacy.msa):
            values = reals([summary.mean, summary.sd, summary.minimum, summary.maximum, msa])
            lines.append(" ".join([name, str(summary.observed), str(summary.missing)] + values))
        adequacy = self.adequacy
        lines.append(
            f"adequacy kmo {real_text(adequacy.kmo)}"
            f" determinant {real_text(adequacy.determinant, 6)}"
            f" bartlett {real_text(adequacy.bartlett)} df {adequacy.freedom}"
        )
        return lines

    def matrix_section(self):
        lines = [f"matrix {self.settings.scaling}"]
        for name, row in zip(self.names, self.fit.matrix):
            lines.append(" ".join([name] + reals(row)))
        pairs = [
            f"{self.names[j]}:{self.names[k]}:{real_text(self.fit.correlation[j][k])}"
            for j, k in self.strongest
        ]
        lines.append(" ".join(["strongest"] + pairs))
        return lines

    def eigenvalue_section(self):
        variance = self.variance
        lines = [
            f"jacobi sweeps {self.fit.eigen.sweeps}",
            f"eigenvalues total {real_text(variance.total)} average {real_text(variance.average)}",
            "k eigenvalue ratio cumulative broken_stick parallel se separated",
        ]
        for k in range(self.size):
            values = reals([
                self.eigenvalues[k], variance.ratios[k], variance.cumulative[k],
                variance.broken_stick[k], variance.parallel[k], variance.errors[k],
            ])
            separated = "yes" if variance.separated[k] else "no"
            lines.append(" ".join([str(k + 1)] + values + [separated]))
        counts = " ".join(f"{name} {variance.retention[name]}" for name in CRITERIA)
        lines.append(
            f"retention {counts} target {real_text(self.settings.cumulative_target)}"
        )
        lines.append(f"components {self.components} rule {self.settings.components}")
        return lines

    def eigenvector_section(self):
        lines = ["eigenvectors", " ".join(["variable"] + component_names("pc", self.size))]
        for j, name in enumerate(self.names):
            lines.append(" ".join([name] + reals(vector[j] for vector in self.vectors)))
        return lines

    def power_section(self):
        lines = [f"power_iteration iterations {POWER_ITERATIONS}", "k jacobi power agree_at match"]
        matches = 0
        for k, component in enumerate(self.power):
            match = (
                abs(component.value - self.eigenvalues[k])
                <= EIGENVALUE_TOLERANCE * self.eigenvalues[0]
                and max_difference(component.vector, self.vectors[k]) <= VECTOR_TOLERANCE
            )
            if match:
                matches += 1
            agreement = "-" if component.agreement is None else str(component.agreement)
            lines.append(
                f"{k + 1} {real_text(self.eigenvalues[k])} {real_text(component.value)}"
                f" {agreement} {'yes' if match else 'no'}"
            )
        lines.append(f"cross_check {matches}/{self.size}")
        return lines

    def score_section(self):
        lines = ["scores", "component sd min min_id max max_id contributors"]
        denominator = self.rows - 1
        for k in range(self.components):
            scores = [observation.scores[k] for observation in self.observations]
            sd = math.sqrt(sequential_sum(t * t for t in scores) / denominator)
            low = smallest_index(scores)
            high = largest_index(scores)
            contributions = [t * t / (denominator * self.eigenvalues[k]) for t in scores]
            parts = [
                f"pc{k + 1}", real_text(sd), real_text(scores[low]), self.ids[low],
                real_text(scores[high]), self.ids[high],
            ]
            for i in top_indices(contributions, self.settings.top_rows):
                parts.append(f"{self.ids[i]}:{real_text(contributions[i])}")
            lines.append(" ".join(parts))
        return lines

    def varimax_section(self):
        varimax = self.varimax
        lines = [f"varimax components {self.components} cycles {self.settings.varimax_cycles}"]
        for cycle, value in enumerate(varimax.criteria):
            lines.append(f"cycle {cycle} criterion {real_text(value, 6)}")
        for k in range(self.components):
            squares = varimax.squares[k]
            lines.append(
                f"rc{k + 1} ss {real_text(squares)}"
                f" ratio {real_text(squares / self.variance.total)}"
                f" closest pc{varimax.closest[k] + 1}"
                f" congruence {real_text(varimax.congruences[k])}"
            )
        return lines

    def sensitivity_section(self):
        lines = ["sensitivity", "missing scaling rows sweeps eigenvalues cumulative congruence"]
        for result in self.sensitivity:
            parts = [result.strategy, result.scaling, str(result.rows), str(result.sweeps)]
            parts += reals(result.eigenvalues)
            parts.append(real_text(result.cumulative))
            parts += reals(result.agreement)
            lines.append(" ".join(parts))
        return lines

    def eigen_file(self):
        return join_sections([
            self.summary_section(),
            self.variable_section(),
            self.matrix_section(),
            self.eigenvalue_section(),
            self.eigenvector_section(),
            self.power_section(),
            self.score_section(),
            self.varimax_section(),
            self.sensitivity_section(),
        ])

    def loadings_file(self):
        header = (
            ["variable"] + component_names("pc", self.components) + ["communality"]
            + component_names("rc", self.components)
        )
        lines = [",".join(header)]
        for j, name in enumerate(self.names):
            values = self.loadings[j][:self.components] + [self.communalities[j]]
            values += [rotated[j] for rotated in self.varimax.columns]
            lines.append(",".join([name] + reals(values)))
        return lines

    def scores_file(self):
        lines = [",".join(["id", "set"] + component_names("pc", self.components))]
        for observation in self.observations:
            scores = reals(observation.scores[:self.components])
            lines.append(",".join([observation.id, "data"] + scores))
        for projection in self.projections:
            scores = reals(projection.scores[:self.components])
            lines.append(",".join([projection.id, "supplementary"] + scores))
        return lines

    def diagnostics_section(self):
        settings = self.settings
        lines = [
            f"diagnostics components {self.components} t2_limit {real_text(settings.t2_limit)}"
            f" spe_limit {real_text(settings.spe_limit)}",
            "id t2 spe quality flag",
        ]
        for observation in self.observations:
            values = reals([observation.t2, observation.spe, self.quality(observation)])
            lines.append(" ".join([observation.id] + values + [observation.flag]))
        flags = [observation.flag for observation in self.observations]
        t2_count = sum(1 for flag in flags if "T" in flag)
        spe_count = sum(1 for flag in flags if "Q" in flag)
        both_count = sum(1 for flag in flags if flag == "TQ")
        any_count = sum(1 for flag in flags if flag != "-")
        lines.append(f"flagged t2 {t2_count} spe {spe_count} both {both_count} any {any_count}")
        return lines

    def top_section(self, label, values, contributions):
        lines = [f"top {label}", f"rank id {label} variable contribution"]
        for rank, i in enumerate(top_indices(values, self.settings.top_rows), 1):
            variable = largest_index(contributions[i])
            lines.append(
                f"{rank} {self.ids[i]} {real_text(values[i])} {self.names[variable]}"
                f" {real_text(contributions[i][variable])}"
            )
        return lines

    def reconstruction_section(self):
        lines = ["reconstruction", "k mean_spe max_spe max_id"]
        for count in range(1, self.size):
            errors = []
            for observation in self.observations:
                residual = residuals(observation.z, observation.scores, self.vectors, count)
                errors.append(dot(residual, residual))
            worst = largest_index(errors)
            mean = sequential_sum(errors) / self.rows
            lines.append(
                f"{count} {real_text(mean)} {real_text(errors[worst])} {self.ids[worst]}"
            )
        return lines

    def supplementary_section(self):
        header = ["id"] + component_names("pc", self.components)
        header += ["t2", "spe", "flag", "nearest", "distance"]
        lines = ["supplementary", " ".join(header)]
        for projection in self.projections:
            nearest, distance = self.nearest_row(projection)
            values = reals(projection.scores[:self.components] + [projection.t2, projection.spe])
            lines.append(" ".join(
                [projection.id] + values
                + [projection.flag, self.ids[nearest], real_text(distance)]
            ))
        return lines

    def outliers_file(self):
        observations = self.observations
        return join_sections([
            self.diagnostics_section(),
            self.top_section(
                "t2", [observation.t2 for observation in observations],
                [self.t2_contributions(observation) for observation in observations],
            ),
            self.top_section(
                "spe", [observation.spe for observation in observations],
                [[e * e for e in observation.residuals] for observation in observations],
            ),
            self.reconstruction_section(),
            self.supplementary_section(),
        ])

    def scree_section(self):
        width = self.settings.scree_width
        first = self.eigenvalues[0]
        kaiser = rounded_position(self.variance.average / first, width)
        lines = [f"scree width {width} kaiser_column {kaiser}"]
        for k, value in enumerate(self.eigenvalues):
            length = rounded_position(value / first, width)
            broken = rounded_position(self.variance.broken_stick[k] * self.variance.total / first, width)
            lines.append(f"{scree_line(length, kaiser, broken, width)} pc{k + 1} {real_text(value)}")
        return lines

    def biplot_section(self):
        width = self.settings.biplot_width
        height = self.settings.biplot_height
        points = self.observations + self.projections
        x_limit = max(abs(point.scores[0]) for point in points)
        y_limit = max(abs(point.scores[1]) for point in points)
        x_loading = max(abs(row[0]) for row in self.loadings)
        y_loading = max(abs(row[1]) for row in self.loadings)
        scale = ARROW_SHRINK * min(x_limit / x_loading, y_limit / y_loading)
        origin = biplot_cell(0.0, 0.0, x_limit, y_limit, width, height)
        tips = [
            biplot_cell(scale * row[0], scale * row[1], x_limit, y_limit, width, height)
            for row in self.loadings
        ]
        cells = [
            biplot_cell(point.scores[0], point.scores[1], x_limit, y_limit, width, height)
            for point in points
        ]
        data_cells = cells[:self.rows]
        grid = new_grid(height, width)
        draw_axes(grid, origin)
        for tip in tips:
            mark_cells(grid, shaft_cells(origin, tip), shaft_character(origin, tip))
        draw_points(grid, data_cells)
        flagged = [
            cell for cell, observation in zip(data_cells, self.observations)
            if observation.flag != "-"
        ]
        mark_cells(grid, flagged, "X")
        mark_cells(grid, cells[self.rows:], "*")
        for j, tip in enumerate(tips):
            mark_cells(grid, [tip], LETTERS[j])
        lines = [
            f"biplot pc1 pc2 width {width} height {height}",
            f"x {real_text(-x_limit)} {real_text(x_limit)} y {real_text(-y_limit)}"
            f" {real_text(y_limit)} arrow_scale {real_text(scale)}",
        ]
        lines += framed(grid)
        for j, name in enumerate(self.names):
            loading = self.loadings[j]
            lines.append(f"{LETTERS[j]} {name} {real_text(loading[0])} {real_text(loading[1])}")
        return lines

    def circle_section(self):
        radius = self.settings.circle_radius
        center = (radius // 2 + 1, radius + 1)
        grid = new_grid(radius + 3, 2 * radius + 3)
        draw_axes(grid, center)
        for row, line in enumerate(grid):
            for col in range(len(line)):
                if not inside_circle(row, col, center, radius):
                    continue
                if not all(
                    inside_circle(row + dr, col + dc, center, radius) for dr, dc in NEIGHBORS
                ):
                    line[col] = "."
        for j, (first, second) in enumerate(self.circle):
            mark_cells(grid, [circle_cell(first, second, radius)], LETTERS[j])
        lines = [f"circle radius {radius}"] + framed(grid)
        for j, name in enumerate(self.names):
            first, second = self.circle[j]
            values = reals([first, second, first * first + second * second])
            lines.append(" ".join([LETTERS[j], name] + values))
        return lines

    def diagnostic_section(self):
        settings = self.settings
        width = settings.diagnostic_width
        height = settings.diagnostic_height
        t2_max = 2 * settings.t2_limit
        spe_max = 2 * settings.spe_limit
        grid = new_grid(height, width)
        limit = diagnostic_cell(settings.t2_limit, settings.spe_limit, t2_max, spe_max, width, height)
        draw_axes(grid, limit)
        draw_points(grid, [
            diagnostic_cell(observation.t2, observation.spe, t2_max, spe_max, width, height)
            for observation in self.observations
        ])
        mark_cells(grid, [
            diagnostic_cell(projection.t2, projection.spe, t2_max, spe_max, width, height)
            for projection in self.projections
        ], "*")
        header = (
            f"diagnostic width {width} height {height}"
            f" t2_max {real_text(t2_max)} spe_max {real_text(spe_max)}"
        )
        return [header] + framed(grid)

    def plots_file(self):
        return join_sections([
            self.scree_section(),
            self.biplot_section(),
            self.circle_section(),
            self.diagnostic_section(),
        ])


def main():
    report = PcaReport(load_dataset(INPUT_DIRECTORY))
    os.makedirs(OUTPUT_DIRECTORY, exist_ok=True)
    write_lines("eigen.txt", report.eigen_file())
    write_lines("loadings.csv", report.loadings_file())
    write_lines("scores.csv", report.scores_file())
    write_lines("outliers.txt", report.outliers_file())
    write_lines("plots.txt", report.plots_file())


if __name__ == "__main__":
    main()
