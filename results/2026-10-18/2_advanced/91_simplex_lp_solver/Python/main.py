"""Exact two-phase LP solving, sensitivity analysis, and integer model reports."""

from pathlib import Path
from types import SimpleNamespace

import branch_bound
from lp_parser import read_models, read_settings
from rational import Fraction, approximate, ceil, endpoint, floor
from simplex import run_phase
from tableau import Tableau


def coefficients(terms, variables):
    values = dict.fromkeys(variables, Fraction(0))
    for name, coefficient in terms:
        values[name] += coefficient
    return [values[name] for name in variables]


def dot(left, right):
    return sum((a * b for a, b in zip(left, right)), Fraction(0))


def content_check(parsed):
    if parsed.error is not None:
        return parsed
    variables = []
    expressions = [parsed.objective] + [row.terms for row in parsed.constraints]
    for terms in expressions:
        for name, coefficient in terms:
            if name not in variables:
                variables.append(name)
    model = SimpleNamespace(
        name=parsed.name, error=None, direction=parsed.direction,
        variables=variables, constraints=parsed.constraints,
        costs=coefficients(parsed.objective, variables),
        matrix=[coefficients(row.terms, variables) for row in parsed.constraints],
        rhs=[row.rhs for row in parsed.constraints],
        comparisons=[row.comparison for row in parsed.constraints],
        lower=[Fraction(0) for _ in variables], upper=[None for _ in variables],
        integer=[False for _ in variables],
    )
    seen = set()
    for row in parsed.constraints:
        if row.name in seen:
            model.error = (row.line, f"duplicate constraint {row.name}")
            return model
        seen.add(row.name)
    positions = {name: j for j, name in enumerate(variables)}
    for line, name, kind, lower, upper in parsed.bounds:
        if name not in positions:
            model.error = (line, f"unknown variable {name}")
            return model
        j = positions[name]
        if kind in {"lower", "both"}:
            model.lower[j] = lower
        if kind in {"upper", "both"}:
            model.upper[j] = upper
        low, high = model.lower[j], model.upper[j]
        if low is not None and high is not None and low > high:
            model.error = (line, f"inconsistent bounds {name}")
            return model
    for line, names in parsed.integers:
        for name in names:
            if name not in positions:
                model.error = (line, f"unknown variable {name}")
                return model
            j = positions[name]
            model.integer[j] = True
            if model.lower[j] is not None:
                model.lower[j] = Fraction(ceil(model.lower[j]))
            if model.upper[j] is not None:
                model.upper[j] = Fraction(floor(model.upper[j]))
            low, high = model.lower[j], model.upper[j]
            if low is not None and high is not None and low > high:
                model.error = (line, f"inconsistent bounds {name}")
                return model
    for line, names in parsed.binaries:
        for name in names:
            if name not in positions:
                model.error = (line, f"unknown variable {name}")
                return model
            j = positions[name]
            model.integer[j] = True
            model.lower[j] = Fraction(0)
            model.upper[j] = Fraction(1)
    return model


def standard_form(model, lower, upper):
    column_names = []
    owners = []
    directions = []
    mappings = []
    for j, name in enumerate(model.variables):
        first = len(column_names)
        if lower[j] is not None:
            kind, offset = "shift", lower[j]
            columns, signs, names = [first], [1], [name]
        elif upper[j] is not None:
            kind, offset = "reflect", upper[j]
            columns, signs, names = [first], [-1], [name + "'"]
        else:
            kind, offset = "split", Fraction(0)
            columns, signs, names = [first, first + 1], [1, -1], [name + "+", name + "-"]
        column_names.extend(names)
        owners.extend([j] * len(columns))
        directions.extend(signs)
        mappings.append(SimpleNamespace(kind=kind, offset=offset, columns=columns,
                                        directions=signs, upper_row=None))
    offsets = [mapping.offset for mapping in mappings]
    row_names = [row.name for row in model.constraints]
    matrix = [[directions[k] * row[j] for k, j in enumerate(owners)]
              for row in model.matrix]
    rhs = [value - dot(row, offsets) for row, value in zip(model.matrix, model.rhs)]
    comparisons = model.comparisons.copy()
    for j, mapping in enumerate(mappings):
        if mapping.kind != "shift" or upper[j] is None:
            continue
        mapping.upper_row = len(row_names)
        row_names.append(model.variables[j] + ".ub")
        row = [Fraction(0) for _ in column_names]
        row[mapping.columns[0]] = Fraction(1)
        matrix.append(row)
        rhs.append(upper[j] - lower[j])
        comparisons.append("<=")
    signs = [1 for _ in row_names]
    for i in range(len(row_names)):
        if rhs[i] < 0:
            matrix[i] = [-value for value in matrix[i]]
            rhs[i] = -rhs[i]
            signs[i] = -1
            comparisons[i] = {"<=": ">=", ">=": "<=", "=": "="}[comparisons[i]]
    slack = [None for _ in row_names]
    artificial = set()
    initial = [None for _ in row_names]
    for i, comparison in enumerate(comparisons):
        if comparison == "=":
            continue
        slack[i] = len(column_names)
        column_names.append("s:" + row_names[i])
        for t, row in enumerate(matrix):
            row.append(Fraction((1 if comparison == "<=" else -1) if t == i else 0))
        if comparison == "<=":
            initial[i] = slack[i]
    for i, comparison in enumerate(comparisons):
        if comparison == "<=":
            continue
        column = len(column_names)
        artificial.add(column)
        initial[i] = column
        column_names.append("a:" + row_names[i])
        for t, row in enumerate(matrix):
            row.append(Fraction(1 if t == i else 0))
    direction = 1 if model.direction == "minimize" else -1
    phase2 = [direction * directions[k] * model.costs[j] for k, j in enumerate(owners)]
    phase2.extend(Fraction(0) for _ in range(len(column_names) - len(phase2)))
    phase1 = [Fraction(1 if k in artificial else 0) for k in range(len(column_names))]
    return SimpleNamespace(
        column_names=column_names, row_names=row_names, mappings=mappings,
        matrix=matrix, rhs=rhs, signs=signs, slack=slack, artificial=artificial,
        initial=initial, phase1=phase1, phase2=phase2,
        constant=dot(model.costs, offsets), direction=direction,
    )


def tableau_solution(form, tableau):
    values = [Fraction(0) for _ in form.column_names]
    for basic, rhs in zip(tableau.basic, tableau.rhs):
        values[basic] = rhs
    solution = []
    for mapping in form.mappings:
        value = mapping.offset
        for column, direction in zip(mapping.columns, mapping.directions):
            value += direction * values[column]
        solution.append(value)
    return solution


def farkas_multipliers(result):
    form = result.form
    reduced = result.tableau.reduced(form.phase1)
    return [form.signs[i] * (form.phase1[column] - reduced[column])
            for i, column in enumerate(form.initial)]


def unbounded_ray(model, result):
    tableau, form = result.tableau, result.form
    column = result.unbounded
    delta = [Fraction(0) for _ in form.column_names]
    delta[column] = Fraction(1)
    for row, basic in enumerate(tableau.basic):
        delta[basic] = -tableau.values[row][column]
    ray = []
    for mapping in form.mappings:
        value = sum((direction * delta[k] for k, direction in
                     zip(mapping.columns, mapping.directions)), Fraction(0))
        ray.append(value)
    return ray, dot(model.costs, ray)


def mapping_lines(model, form, lower, upper):
    lines = []
    for j, mapping in enumerate(form.mappings):
        name = model.variables[j]
        if mapping.kind == "split":
            lines.append(f"MAP {name} split")
        elif mapping.kind == "reflect":
            lines.append(f"MAP {name} reflect {upper[j]}")
        else:
            text = f"MAP {name} shift {lower[j]}"
            if upper[j] is not None:
                text += f" upper {upper[j]}"
            lines.append(text)
    for name, sign in zip(form.row_names, form.signs):
        if sign == -1:
            lines.append(f"FLIP {name}")
    return lines


def solve_lp(model, lower, upper, number, level):
    form = standard_form(model, lower, upper)
    tableau = Tableau(form.row_names, form.column_names, form.matrix, form.rhs, form.initial)
    lines = []

    def emit(required, text):
        if level >= required:
            lines.append(text)

    def display(heading, costs, objective):
        if level >= 2:
            lines.extend(tableau.display(heading, costs, objective))

    def phase2_value(value):
        return form.constant + form.direction * value

    emit(0, f"SOLVE node {number} rows {len(form.row_names)} columns {len(form.column_names)} "
            f"artificials {len(form.artificial)}")
    for line in mapping_lines(model, form, lower, upper):
        emit(1, line)
    phase1_count = phase2_count = drives = redundant = 0
    infeasibility = Fraction(0)
    status = "OPTIMAL"
    unbounded = None
    if form.artificial:
        emit(1, "PHASE 1")
        display("phase 1 start", form.phase1, lambda value: value)
        phase = run_phase(tableau, form.phase1, range(len(form.column_names)), lambda value: value)
        phase1_count = phase.iterations
        for line in phase.lines:
            emit(1, line)
        infeasibility = tableau.phase_value(form.phase1)
        emit(1, f"PHASE 1 END objective {infeasibility} iterations {phase1_count}")
        if infeasibility > 0:
            status = "INFEASIBLE"
            display("final", form.phase1, lambda value: value)
        else:
            for row, basic in enumerate(tableau.basic):
                if basic not in form.artificial:
                    continue
                entering = next((k for k, value in enumerate(tableau.values[row])
                                 if k not in form.artificial and value != 0), None)
                if entering is None:
                    redundant += 1
                    emit(1, f"REDUNDANT row {form.row_names[row]}")
                else:
                    leaving = form.column_names[basic]
                    tableau.pivot(row, entering)
                    drives += 1
                    emit(1, f"DRIVE row {form.row_names[row]} enter {form.column_names[entering]} "
                            f"leave {leaving}")
    if status != "INFEASIBLE":
        emit(1, "PHASE 2")
        display("phase 2 start", form.phase2, phase2_value)
        candidates = [k for k in range(len(form.column_names)) if k not in form.artificial]
        phase = run_phase(tableau, form.phase2, candidates, phase2_value)
        phase2_count = phase.iterations
        for line in phase.lines:
            emit(1, line)
        unbounded = phase.unbounded
        if unbounded is not None:
            status = "UNBOUNDED"
            emit(1, f"UNBOUNDED enter {form.column_names[unbounded]}")
        value = phase2_value(tableau.phase_value(form.phase2))
        emit(1, f"PHASE 2 END objective {value} iterations {phase2_count}")
        display("final", form.phase2, phase2_value)
    objective = phase2_value(tableau.phase_value(form.phase2)) if status == "OPTIMAL" else None
    shown = "-" if objective is None else str(objective)
    emit(0, f"RESULT {status} objective {shown} phase1 {phase1_count} phase2 {phase2_count} "
            f"drives {drives} redundant {redundant}")
    return SimpleNamespace(
        status=status, objective=objective, solution=tableau_solution(form, tableau),
        form=form, tableau=tableau, unbounded=unbounded, infeasibility=infeasibility,
        phase1=phase1_count, phase2=phase2_count, drives=drives, redundant=redundant,
        pivots=phase1_count + phase2_count + drives, lines=lines,
    )


def statistics_line(model):
    matrix = [value for row in model.matrix for value in row if value]
    objective = [value for value in model.costs if value]
    rhs = [value for value in model.rhs if value]
    bounds = [value for value in model.lower + model.upper if value is not None and value]
    parts = [f"STATS nonzeros {len(matrix)}"]
    for name, values in (("matrix", matrix), ("objective", objective), ("rhs", rhs), ("bounds", bounds)):
        if values:
            magnitudes = [abs(value) for value in values]
            parts.append(f"{name} {min(magnitudes)} {max(magnitudes)}")
        else:
            parts.append(f"{name} - -")
    return " ".join(parts)


def range_endpoints(origin, coefficients, numerators):
    lower = [value / coefficient for value, coefficient in zip(numerators, coefficients)
             if coefficient > 0]
    upper = [value / coefficient for value, coefficient in zip(numerators, coefficients)
             if coefficient < 0]
    return (origin + max(lower) if lower else None,
            origin + min(upper) if upper else None)


def objective_range(model, result, variable, reduced, nonbasic):
    form, tableau = result.form, result.tableau
    h = [Fraction(0) for _ in form.column_names]
    mapping = form.mappings[variable]
    for column, direction in zip(mapping.columns, mapping.directions):
        h[column] = Fraction(form.direction * direction)
    eta = []
    for column in nonbasic:
        change = h[column]
        for row, basic in enumerate(tableau.basic):
            change -= h[basic] * tableau.values[row][column]
        eta.append(change)
    numerators = [-reduced[column] for column in nonbasic]
    return range_endpoints(model.costs[variable], eta, numerators)


def rhs_range(model, result, constraint):
    form, tableau = result.form, result.tableau
    initial = form.initial[constraint]
    rho = [form.signs[constraint] * row[initial] for row in tableau.values]
    if any(value != 0 and basic in form.artificial for value, basic in zip(rho, tableau.basic)):
        return model.rhs[constraint], model.rhs[constraint]
    return range_endpoints(model.rhs[constraint], rho, [-value for value in tableau.rhs])


def variable_status(form, basic, variable):
    mapping = form.mappings[variable]
    if mapping.kind == "split":
        return "basic" if any(column in basic for column in mapping.columns) else "zero"
    if mapping.kind == "reflect":
        return "basic" if mapping.columns[0] in basic else "upper"
    if mapping.columns[0] not in basic:
        return "lower"
    if mapping.upper_row is not None and form.slack[mapping.upper_row] not in basic:
        return "upper"
    return "basic"


def sensitivity_lines(model, result):
    form, tableau = result.form, result.tableau
    reduced = tableau.reduced(form.phase2)
    basic = set(tableau.basic)
    nonbasic = [k for k in range(len(form.column_names)) if k not in basic and k not in form.artificial]
    dual = [-form.direction * form.signs[i] * reduced[form.initial[i]]
            for i in range(len(model.constraints))]
    variable_reduced = []
    for j, cost in enumerate(model.costs):
        variable_reduced.append(cost - dot(dual, [row[j] for row in model.matrix]))
    primal_degeneracy = sum(basis not in form.artificial and rhs == 0
                            for basis, rhs in zip(tableau.basic, tableau.rhs))
    dual_degeneracy = sum(reduced[column] == 0 for column in nonbasic)
    dual_objective = dot(dual, model.rhs) + dot(variable_reduced, result.solution)
    kind = "relaxation" if any(model.integer) else "lp"
    lines = [f"MODEL {model.name} {kind} objective {result.objective}"]
    lines.append("BASIS " + " ".join(form.column_names[column] for column in tableau.basic))
    lines.append(f"DEGENERACY primal {primal_degeneracy} dual {dual_degeneracy}")
    lines.append(f"DUAL objective {dual_objective}")
    for i, constraint in enumerate(model.constraints):
        lower, upper = rhs_range(model, result, i)
        lines.append(f"CONSTRAINT {constraint.name} price {dual[i]} rhs {model.rhs[i]} "
                     f"range {endpoint(lower, True)} {endpoint(upper, False)}")
    for j, name in enumerate(model.variables):
        lower, upper = objective_range(model, result, j, reduced, nonbasic)
        status = variable_status(form, basic, j)
        lines.append(f"VARIABLE {name} {status} value {result.solution[j]} reduced {variable_reduced[j]} "
                     f"cost {model.costs[j]} range {endpoint(lower, True)} {endpoint(upper, False)}")
    return lines


def solve_model(model, level, limit):
    def solve(lower, upper, number):
        return solve_lp(model, lower, upper, number, level)

    if any(model.integer):
        return branch_bound.search(model, limit, solve)
    result = solve(model.lower, model.upper, 1)
    solution = result.solution if result.status == "OPTIMAL" else None
    return SimpleNamespace(status=result.status, objective=result.objective,
                           solution=solution, solves=[result], root=result, nodes=1, lines=[])


def solution_lines(model, result):
    root = result.root
    integer_count = sum(model.integer)
    lines = [f"MODEL {model.name} {model.direction} variables {len(model.variables)} "
             f"constraints {len(model.constraints)} integers {integer_count}"]
    lines.append(statistics_line(model))
    lines.append(f"STATUS {result.status}")
    if result.solution is not None:
        lines.append(f"OBJECTIVE {result.objective} approx {approximate(result.objective)}")
    if integer_count and root.status == "OPTIMAL":
        lines.append(f"RELAXATION {root.objective} approx {approximate(root.objective)}")
    if root.status == "INFEASIBLE":
        lines.append(f"INFEASIBILITY {root.infeasibility}")
        for name, value in zip(root.form.row_names, farkas_multipliers(root)):
            lines.append(f"FARKAS {name} {value}")
    values = result.solution
    if result.status == "UNBOUNDED":
        values = root.solution
    if values is not None:
        for name, value in zip(model.variables, values):
            lines.append(f"VALUE {name} {value}")
    if result.status == "UNBOUNDED":
        ray, rate = unbounded_ray(model, root)
        for name, value in zip(model.variables, ray):
            lines.append(f"RAY {name} {value}")
        lines.append(f"RATE {rate}")
    if result.solution is not None:
        for i, constraint in enumerate(model.constraints):
            value = dot(model.matrix[i], result.solution)
            margin = model.rhs[i] - value if model.comparisons[i] == "<=" else value - model.rhs[i]
            lines.append(f"ROW {constraint.name} {value} {margin}")
    if integer_count:
        lines.append(f"NODES {result.nodes}")
    lines.append(f"PIVOTS {sum(lp.pivots for lp in result.solves)}")
    return lines


class Reports:
    def __init__(self):
        self.iterations = []
        self.solutions = []
        self.sensitivity = []
        self.tree = []
        self.summary = ["model,status,objective,approx,relaxation,nodes,pivots"]
        self.statuses = dict.fromkeys(["OPTIMAL", "INFEASIBLE", "UNBOUNDED", "NODE_LIMIT", "ERROR"], 0)
        self.solves = 0
        self.phase1 = 0
        self.phase2 = 0
        self.drives = 0
        self.analyzed = 0
        self.integer_models = 0
        self.integer_nodes = 0
        self.limited_models = 0

    def add_error(self, model):
        line, message = model.error
        self.statuses["ERROR"] += 1
        self.iterations.append(f"MODEL {model.name} error")
        self.solutions.extend([f"MODEL {model.name}", f"STATUS ERROR line {line} {message}"])
        self.sensitivity.append(f"MODEL {model.name} skipped ERROR")
        self.summary.append(f"{model.name},ERROR,-,-,-,0,0")

    def add_valid(self, model, result, level, limit):
        self.statuses[result.status] += 1
        self.iterations.append(f"MODEL {model.name} level {level}")
        for lp in result.solves:
            self.iterations.extend(lp.lines)
            self.solves += 1
            self.phase1 += lp.phase1
            self.phase2 += lp.phase2
            self.drives += lp.drives
        self.solutions.extend(solution_lines(model, result))
        if result.root.status == "OPTIMAL":
            self.analyzed += 1
            self.sensitivity.extend(sensitivity_lines(model, result.root))
        else:
            self.sensitivity.append(f"MODEL {model.name} skipped {result.root.status}")
        if any(model.integer):
            self.integer_models += 1
            self.integer_nodes += result.nodes
            self.limited_models += result.status == "NODE_LIMIT"
            self.tree.append(f"MODEL {model.name} {model.direction} integers {sum(model.integer)} "
                             f"node_limit {limit}")
            self.tree.extend(result.lines)
        objective = "-" if result.objective is None else str(result.objective)
        approx = "-" if result.objective is None else approximate(result.objective)
        relaxation = "-" if result.root.objective is None else str(result.root.objective)
        pivots = sum(lp.pivots for lp in result.solves)
        self.summary.append(f"{model.name},{result.status},{objective},{approx},{relaxation},"
                            f"{len(result.solves)},{pivots}")

    def finish(self):
        models = sum(self.statuses.values())
        pivots = self.phase1 + self.phase2 + self.drives
        self.iterations.append(f"TOTAL solves {self.solves} phase1 {self.phase1} phase2 {self.phase2} "
                               f"drives {self.drives} pivots {pivots}")
        self.solutions.append(
            f"SUMMARY models {models} optimal {self.statuses['OPTIMAL']} "
            f"infeasible {self.statuses['INFEASIBLE']} unbounded {self.statuses['UNBOUNDED']} "
            f"node_limit {self.statuses['NODE_LIMIT']} error {self.statuses['ERROR']}"
        )
        self.sensitivity.append(f"SUMMARY analyzed {self.analyzed} skipped {models - self.analyzed}")
        self.tree.append(f"SUMMARY models {self.integer_models} nodes {self.integer_nodes} "
                         f"node_limit {self.limited_models}")
        output = Path("output")
        output.mkdir(exist_ok=True)
        reports = [("iterations.txt", self.iterations), ("solutions.txt", self.solutions),
                   ("sensitivity.txt", self.sensitivity), ("bnb_tree.txt", self.tree),
                   ("summary.csv", self.summary)]
        for name, lines in reports:
            (output / name).write_bytes(("\n".join(lines) + "\n").encode("ascii"))


def main():
    settings = read_settings()
    reports = Reports()
    for parsed in read_models():
        model = content_check(parsed)
        if model.error is not None:
            reports.add_error(model)
            continue
        level = settings.logs.get(model.name, settings.level)
        limit = settings.limits.get(model.name, settings.limit)
        result = solve_model(model, level, limit)
        reports.add_valid(model, result, level, limit)
    reports.finish()


if __name__ == "__main__":
    main()
