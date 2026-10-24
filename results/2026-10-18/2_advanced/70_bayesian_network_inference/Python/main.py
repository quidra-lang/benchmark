"""Learn a discrete Bayesian network and answer exact, sampled and structural queries."""

from collections import Counter, deque
from math import log
from pathlib import Path

from elimination import execute, interaction_graph, make_plan, traceback
from factors import Factor, assignments, cpt_factor, entry_count
from learning import count_samples, family_score, learn, log_likelihood, parameter_count, parent_row, total
from network_io import read_inputs
from sampling import Minstd, weighted_sample


def real(value):
    text = format(value, ".4f")
    return "0.0000" if text == "-0.0000" else text


def yes(value):
    return "yes" if value else "no"


def write_blocks(path, blocks):
    text = "\n\n".join("\n".join(block) for block in blocks)
    Path(path).write_text(text + ("\n" if text else ""), encoding="ascii", newline="\n")


class NetworkAnalysis:
    def __init__(self, network, samples, params):
        self.names, self.states = network.names, network.states
        self.parents, self.expert = network.parents, network.expert
        self.samples, self.params = samples, params
        self.sizes = [len(states) for states in self.states]
        self.variables = list(range(len(self.names)))
        self.children = [[child for child in self.variables if variable in self.parents[child]]
                         for variable in self.variables]
        self.topological, selected = [], set()
        while len(selected) < len(self.variables):
            variable = min(item for item in self.variables if item not in selected
                           and all(parent in selected for parent in self.parents[item]))
            self.topological.append(variable)
            selected.add(variable)
        self.depths = [0] * len(self.variables)
        for variable in self.topological:
            self.depths[variable] = max((self.depths[parent] + 1 for parent in self.parents[variable]), default=0)
        self.ancestors = [self.closure(self.parents[variable], self.parents) for variable in self.variables]
        self.descendants = [self.closure(self.children[variable], self.children) for variable in self.variables]
        self.spouses, self.blankets = [], []
        for variable in self.variables:
            immediate = set(self.parents[variable]) | set(self.children[variable])
            spouses = {parent for child in self.children[variable] for parent in self.parents[child]}
            spouses -= immediate | {variable}
            self.spouses.append(sorted(spouses))
            self.blankets.append(sorted(immediate | spouses))
        self.counts = [count_samples(variable, self.parents[variable], samples, self.sizes) for variable in self.variables]
        self.learned = [learn(counts, params["alpha"]) for counts in self.counts]
        self.cpts = [self.expert[variable] if params["sources"][variable] == "GIVEN" else self.learned[variable]
                     for variable in self.variables]
        self.likelihoods = [log_likelihood(counts, cpt) for counts, cpt in zip(self.counts, self.cpts)]
        self.parameters = [parameter_count(counts) for counts in self.counts]
        self.factors = [cpt_factor(variable, self.parents[variable], self.cpts[variable], self.sizes)
                        for variable in self.variables]
        self.random = Minstd(params["seed"])
        self.family_scores = {}

    def closure(self, initial, links):
        reached, pending = set(initial), list(initial)
        while pending:
            for neighbor in links[pending.pop()]:
                if neighbor not in reached:
                    reached.add(neighbor)
                    pending.append(neighbor)
        return reached

    def sequence(self, variables):
        return " ".join(self.names[variable] for variable in variables) or "-"

    def assignment_text(self, assignment, variables=None):
        if variables is None:
            variables = sorted(assignment)
        return " ".join(f"{self.names[variable]}={self.states[variable][assignment[variable]]}"
                        for variable in variables) or "-"

    def evidence(self, fields):
        result = {}
        for field in fields:
            variable_name, state_name = field.split("=")
            variable = self.names.index(variable_name)
            result[variable] = self.states[variable].index(state_name)
        return result

    def query_parts(self, fields):
        if "|" not in fields:
            return [self.names.index(name) for name in fields], {}
        separator = fields.index("|")
        return [self.names.index(name) for name in fields[:separator]], self.evidence(fields[separator + 1:])

    def plans(self, initial, eliminate):
        return {method: make_plan(initial, eliminate, method, self.params["order"], self.sizes)
                for method in ("MINFILL", "GIVEN")}

    def sum_result(self, initial, plan, query):
        factor, _ = execute(initial, plan, self.sizes)
        evidence_probability = total(factor.values)
        distribution = Factor(factor.variables, [value / evidence_probability for value in factor.values], self.sizes)
        marginals = {variable: [0.0] * self.sizes[variable] for variable in query}
        for assignment, probability in zip(assignments(distribution.variables, self.sizes), distribution.values):
            for variable in query:
                marginals[variable][assignment[variable]] += probability
        return distribution, evidence_probability, marginals

    def posterior(self, query, evidence):
        relevant = self.closure(set(query) | set(evidence), self.parents)
        eliminate = sorted(relevant - set(query) - set(evidence))
        initial = [self.factors[variable].reduced(evidence) for variable in sorted(relevant)]
        plans = self.plans(initial, eliminate)
        distribution, probability, marginals = self.sum_result(initial, plans[self.params["method"]], query)
        return {"relevant": sorted(relevant), "eliminate": eliminate, "initial": initial, "plans": plans,
                "distribution": distribution, "probability": probability, "marginals": marginals}

    def joint(self, assignment, variables):
        probability = 1.0
        for variable in variables:
            row = parent_row(self.parents[variable], assignment, self.sizes)
            probability *= self.cpts[variable][row][assignment[variable]]
        return probability

    def query_enumeration(self, result, query, evidence):
        free = sorted(set(result["relevant"]) - set(evidence))
        count = entry_count(free, self.sizes)
        if count > self.params["limit"]:
            return count, "skipped"
        query = sorted(query)
        values = [0.0] * entry_count(query, self.sizes)
        for assignment in assignments(free, self.sizes):
            assignment.update(evidence)
            probability = self.joint(assignment, result["relevant"])
            values[parent_row(query, assignment, self.sizes)] += probability
        evidence_probability = total(values)
        agreed = abs(log(evidence_probability) - log(result["probability"])) <= 1e-9
        for value, posterior in zip(values, result["distribution"].values):
            agreed = agreed and abs(value / evidence_probability - posterior) <= 1e-9
        return count, "agree" if agreed else "disagree"

    def elimination_lines(self, result, agreement, enumeration):
        pruned = sorted(set(self.variables) - set(result["relevant"]))
        lines = ["relevant " + self.sequence(result["relevant"]), "pruned " + self.sequence(pruned),
                 "eliminate " + self.sequence(result["eliminate"])]
        for method in ("MINFILL", "GIVEN"):
            plan = result["plans"][method]
            lines.append("order " + method.lower())
            for step in plan.steps:
                lines.append(f"step {self.names[step.variable]} fill {step.fill} "
                             f"scope {self.sequence(step.scope)} entries {step.size}")
            lines.append(f"cost max {plan.maximum} total {plan.total}")
        lines.extend(["used " + self.params["method"].lower(), "orders_agree " + yes(agreement),
                      f"enumeration {enumeration[0]} {enumeration[1]}"])
        return lines

    def marginal_lines(self, prefix, query, marginals):
        return [prefix + " " + self.names[variable] + " " + " ".join(
                f"{state} {real(probability)}" for state, probability in zip(self.states[variable], marginals[variable]))
                for variable in query]

    def answer_query(self, query, evidence):
        result = self.posterior(query, evidence)
        lines = ["log_evidence " + real(log(result["probability"]))]
        if evidence:
            conflict = total(log(self.posterior([], {variable: state})["probability"])
                             for variable, state in evidence.items()) - log(result["probability"])
            lines.append("conflict " + real(conflict))
        distribution = result["distribution"]
        if len(query) >= 2:
            for assignment, probability in zip(assignments(distribution.variables, self.sizes), distribution.values):
                lines.append("joint " + self.assignment_text(assignment) + " " + real(probability))
        lines.extend(self.marginal_lines("marginal", query, result["marginals"]))
        for variable, state in evidence.items():
            reduced = {other: value for other, value in evidence.items() if other != variable}
            without = self.posterior(query, reduced)["marginals"]
            shift = max(abs(left - right) for item in query
                        for left, right in zip(result["marginals"][item], without[item]))
            lines.append(f"drop {self.names[variable]}={self.states[variable][state]} shift {real(shift)}")
        first, first_z, _ = self.sum_result(result["initial"], result["plans"]["MINFILL"], query)
        second, second_z, _ = self.sum_result(result["initial"], result["plans"]["GIVEN"], query)
        agreement = abs(log(first_z) - log(second_z)) <= 1e-9
        agreement = agreement and all(abs(left - right) <= 1e-9 for left, right in zip(first.values, second.values))
        enumeration = self.query_enumeration(result, query, evidence)
        return lines, self.elimination_lines(result, agreement, enumeration)

    def mpe_enumeration(self, eliminate, evidence, assignment, maximum):
        count = entry_count(eliminate, self.sizes)
        if count > self.params["limit"]:
            return count, "skipped"
        best_probability, best_assignment = -1.0, None
        for candidate in assignments(eliminate, self.sizes):
            candidate.update(evidence)
            probability = self.joint(candidate, self.variables)
            if probability > best_probability:
                best_probability, best_assignment = probability, candidate
        agreement = best_assignment == assignment and abs(log(best_probability) - log(maximum)) <= 1e-9
        return count, "agree" if agreement else "disagree"

    def answer_mpe(self, evidence):
        initial = [factor.reduced(evidence) for factor in self.factors]
        eliminate = sorted(set(self.variables) - set(evidence))
        plans = self.plans(initial, eliminate)
        outcomes = {}
        for method, plan in plans.items():
            factor, products = execute(initial, plan, self.sizes, maximize=True)
            outcomes[method] = factor.values[0], traceback(products, self.sizes) | evidence
        maximum, assignment = outcomes[self.params["method"]]
        evidence_probability = self.posterior([], evidence)["probability"] if evidence else 1.0
        lines = ["assignment " + self.assignment_text(assignment), "log_joint " + real(log(maximum)),
                 "log_evidence " + real(log(evidence_probability)), "posterior " + real(maximum / evidence_probability)]
        for variable in eliminate:
            plan = make_plan(initial, [item for item in eliminate if item != variable],
                             self.params["method"], self.params["order"], self.sizes)
            factor, _ = execute(initial, plan, self.sizes, maximize=True)
            alternatives = [state for state in range(self.sizes[variable]) if state != assignment[variable]]
            alternative = max(alternatives, key=lambda state: factor.values[state])
            margin = log(maximum) - log(factor.values[alternative])
            lines.append(f"margin {self.names[variable]} {self.states[variable][alternative]} {real(margin)}")
        first, second = outcomes["MINFILL"], outcomes["GIVEN"]
        agreement = first[1] == second[1] and abs(log(first[0]) - log(second[0])) <= 1e-9
        result = {"relevant": self.variables, "eliminate": eliminate, "plans": plans}
        enumeration = self.mpe_enumeration(eliminate, evidence, assignment, maximum)
        return lines, self.elimination_lines(result, agreement, enumeration)

    def answer_sample(self, number, query, evidence, counts):
        exact = self.posterior(query, evidence)["marginals"]
        lines = self.marginal_lines("exact", query, exact)
        csv_lines = []
        weight, squared_weight = 0.0, 0.0
        weights = {variable: [0.0] * self.sizes[variable] for variable in query}
        checkpoints = set(counts)
        for index in range(1, counts[-1] + 1):
            sample, current = weighted_sample(self.topological, self.parents, self.cpts,
                                               self.sizes, evidence, self.random)
            weight += current
            squared_weight += current * current
            for variable in query:
                weights[variable][sample[variable]] += current
            if index not in checkpoints:
                continue
            maximum_error = 0.0
            for variable in query:
                for state, value in enumerate(weights[variable]):
                    estimate = value / weight
                    probability = exact[variable][state]
                    error = abs(estimate - probability)
                    maximum_error = max(maximum_error, error)
                    csv_lines.append(f"{number},{index},{self.names[variable]},{self.states[variable][state]},"
                                     f"{real(estimate)},{real(probability)},{real(error)}")
            effective = weight * weight / squared_weight
            lines.append(f"after {index} weight {real(weight)} ess {real(effective)} max_error {real(maximum_error)}")
        return lines, csv_lines

    def answer_predict(self, variable):
        size = self.sizes[variable]
        confusion = [[0] * size for _ in range(size)]
        likelihood = 0.0
        for sample in self.samples:
            assignment, values = sample[:], []
            for state in range(size):
                assignment[variable] = state
                row = parent_row(self.parents[variable], assignment, self.sizes)
                probability = self.cpts[variable][row][state]
                for child in self.children[variable]:
                    row = parent_row(self.parents[child], assignment, self.sizes)
                    probability *= self.cpts[child][row][assignment[child]]
                values.append(probability)
            denominator = total(values)
            probabilities = [value / denominator for value in values]
            predicted = max(range(size), key=lambda state: probabilities[state])
            actual = sample[variable]
            confusion[actual][predicted] += 1
            likelihood += log(probabilities[actual])
        correct = sum(confusion[state][state] for state in range(size))
        count = len(self.samples)
        lines = ["blanket " + self.sequence(self.blankets[variable]),
                 f"accuracy {correct}/{count} {real(correct / count)}",
                 "log_loss " + real(-likelihood / count), "predicted " + " ".join(self.states[variable])]
        for name, row in zip(self.states[variable], confusion):
            lines.append("actual " + name + " " + " ".join(map(str, row)))
        return lines

    def reachable(self, x, z):
        x, z = set(x), set(z)
        ancestors = self.closure(z, self.parents)
        pending = deque((variable, "up") for variable in sorted(x))
        visited = set(pending)
        while pending:
            variable, direction = pending.popleft()
            following = []
            if direction == "up" and variable not in z:
                following.extend((parent, "up") for parent in self.parents[variable])
                following.extend((child, "down") for child in self.children[variable])
            elif direction == "down":
                if variable not in z:
                    following.extend((child, "down") for child in self.children[variable])
                if variable in ancestors:
                    following.extend((parent, "up") for parent in self.parents[variable])
            for position in following:
                if position not in visited:
                    visited.add(position)
                    pending.append(position)
        return sorted({variable for variable, _ in visited} - x - z)

    def mutual_information(self, x, y, z):
        scope = sorted(set(x) | set(y) | set(z))
        xz, yz, z = sorted(set(x) | set(z)), sorted(set(y) | set(z)), sorted(z)
        counts = Counter(tuple(sample[variable] for variable in scope) for sample in self.samples)
        count_xz = Counter(tuple(sample[variable] for variable in xz) for sample in self.samples)
        count_yz = Counter(tuple(sample[variable] for variable in yz) for sample in self.samples)
        count_z = Counter(tuple(sample[variable] for variable in z) for sample in self.samples)
        information, count = 0.0, len(self.samples)
        for states in sorted(counts):
            assignment = dict(zip(scope, states))
            observed = counts[states]
            n_xz = count_xz[tuple(assignment[variable] for variable in xz)]
            n_yz = count_yz[tuple(assignment[variable] for variable in yz)]
            n_z = count_z[tuple(assignment[variable] for variable in z)]
            argument = float(observed * n_z) / float(n_xz * n_yz)
            information += (observed / count) * log(argument)
        degrees = (entry_count(x, self.sizes) - 1) * (entry_count(y, self.sizes) - 1) * entry_count(z, self.sizes)
        return information, 2 * count * information, degrees

    def answer_dsep(self, groups):
        x, y = groups[:2]
        z = groups[2] if len(groups) == 3 else []
        reachable = self.reachable(x, z)
        information, statistic, degrees = self.mutual_information(x, y, z)
        return ["result " + ("separated" if set(reachable).isdisjoint(y) else "connected"),
                "reachable " + self.sequence(reachable),
                f"data cmi {real(information)} g2 {real(statistic)} df {degrees}"]

    def answer_blanket(self, variable):
        blanket = self.blankets[variable]
        rest = sorted(set(self.variables) - set(blanket) - {variable})
        separated = set(self.reachable([variable], blanket)).isdisjoint(rest)
        return ["parents " + self.sequence(self.parents[variable]), "children " + self.sequence(self.children[variable]),
                "spouses " + self.sequence(self.spouses[variable]), "blanket " + self.sequence(blanket),
                "rest " + self.sequence(rest), "rest_separated " + yes(separated)]

    def path(self, start, finish, ignored=None):
        previous, pending = {start: None}, deque([start])
        while pending:
            variable = pending.popleft()
            for child in self.children[variable]:
                if (variable, child) == ignored or child in previous:
                    continue
                previous[child] = variable
                if child == finish:
                    result, current = [], child
                    while current is not None:
                        result.append(current)
                        current = previous[current]
                    return result[::-1]
                pending.append(child)
        return None

    def score(self, variable, parents):
        key = variable, tuple(sorted(parents))
        if key not in self.family_scores:
            self.family_scores[key] = family_score(variable, key[1], self.samples,
                                                    self.sizes, self.params["alpha"])
        return self.family_scores[key]

    def answer_edge(self, operation, x, y):
        exists = x in self.parents[y]
        if operation == "ADD" and exists:
            return ["result exists"]
        if operation != "ADD" and not exists:
            return ["result missing"]
        cycle = None
        if operation == "ADD":
            path = self.path(y, x)
            if path is not None:
                cycle = [x] + path
        elif operation == "REVERSE":
            path = self.path(x, y, (x, y))
            if path is not None:
                cycle = [y] + path
        if cycle is not None:
            return ["result cycle " + " -> ".join(self.names[variable] for variable in cycle)]
        before_y = self.score(y, self.parents[y])
        parents_y = set(self.parents[y]) | {x} if operation == "ADD" else set(self.parents[y]) - {x}
        after_y = self.score(y, parents_y)
        change = after_y - before_y
        lines = ["result ok", f"family {self.names[y]} before {real(before_y)} after {real(after_y)}"]
        if operation == "REVERSE":
            before_x = self.score(x, self.parents[x])
            after_x = self.score(x, set(self.parents[x]) | {y})
            change = (after_y - before_y) + (after_x - before_x)
            lines.append(f"family {self.names[x]} before {real(before_x)} after {real(after_x)}")
        lines.append(f"delta {real(change)} " + ("improves" if change > 0 else "worsens"))
        return lines

    def cpt_blocks(self):
        blocks, count = [], len(self.samples)
        for variable in self.variables:
            source = self.params["sources"][variable]
            parents, cpt, counts = self.parents[variable], self.cpts[variable], self.counts[variable]
            lines = [f"variable {self.names[variable]} source {source}", "states " + " ".join(self.states[variable]),
                     "parents " + self.sequence(parents)]
            for row, assignment in enumerate(assignments(parents, self.sizes)):
                combination = self.assignment_text(assignment, parents)
                lines.append("row " + combination + " counts " + " ".join(map(str, counts[row]))
                             + " probs " + " ".join(real(value) for value in cpt[row]))
            likelihood, parameters = self.likelihoods[variable], self.parameters[variable]
            bic = likelihood - parameters * log(count) / 2
            lines.append(f"loglik {real(likelihood)} parameters {parameters} bic {real(bic)}")
            marginal = self.posterior([variable], {})["marginals"][variable]
            frequencies = [sum(row[state] for row in counts) / count for state in range(self.sizes[variable])]
            lines.append("marginal model " + " ".join(map(real, marginal)) + " data " + " ".join(map(real, frequencies)))
            if source == "LEARNED":
                difference = "-"
                if variable in self.expert:
                    maximum = max(abs(left - right) for learned, given in zip(self.learned[variable], self.expert[variable])
                                  for left, right in zip(learned, given))
                    difference = real(maximum)
                lines.append("given_difference " + difference)
            blocks.append(lines)
        likelihood, parameters = total(self.likelihoods), sum(self.parameters)
        bic = likelihood - parameters * log(count) / 2
        blocks.append([f"network samples {count} pseudocount {real(self.params['alpha'])} loglik {real(likelihood)} "
                       f"parameters {parameters} bic {real(bic)}"])
        return blocks

    def structure_summary(self):
        plans = self.plans(self.factors, self.variables)
        widths = {method: max(len(step.scope) for step in plan.steps) - 1 for method, plan in plans.items()}
        graph = interaction_graph(self.factors)
        moral_edges = sum(len(neighbors) for neighbors in graph.values()) // 2
        lines = [f"variables {len(self.variables)} edges {sum(len(parents) for parents in self.parents)}",
                 "topological_order " + self.sequence(self.topological),
                 "roots " + self.sequence([variable for variable in self.variables if not self.parents[variable]]),
                 "leaves " + self.sequence([variable for variable in self.variables if not self.children[variable]]),
                 f"moral_edges {moral_edges} width minfill {widths['MINFILL']} given {widths['GIVEN']}"]
        for variable in self.variables:
            lines.append(f"variable {self.names[variable]} states {self.sizes[variable]} parents {len(self.parents[variable])} "
                         f"children {len(self.children[variable])} depth {self.depths[variable]} "
                         f"ancestors {len(self.ancestors[variable])} descendants {len(self.descendants[variable])} "
                         f"blanket {len(self.blankets[variable])}")
        return lines

    def process_queries(self, queries):
        answers, elimination, structure = [], [], [self.structure_summary()]
        sampling = ["query,samples,variable,state,estimate,exact,abs_error"]
        for number, line in enumerate(queries, 1):
            kind, *fields = line.split()
            heading = f"query {number} {line}"
            if kind == "QUERY":
                query, evidence = self.query_parts(fields)
                answer, steps = self.answer_query(query, evidence)
                answers.append([heading] + answer)
                elimination.append([heading] + steps)
            elif kind == "MPE":
                answer, steps = self.answer_mpe(self.evidence(fields))
                answers.append([heading] + answer)
                elimination.append([heading] + steps)
            elif kind == "SAMPLE":
                separator = max(index for index, field in enumerate(fields) if field == "COUNTS")
                query, evidence = self.query_parts(fields[:separator])
                counts = list(map(int, fields[separator + 1:]))
                answer, rows = self.answer_sample(number, query, evidence, counts)
                answers.append([heading] + answer)
                sampling.extend(rows)
            elif kind == "PREDICT":
                answers.append([heading] + self.answer_predict(self.names.index(fields[0])))
            elif kind == "DSEP":
                groups = [[]]
                for field in fields:
                    if field == "|":
                        groups.append([])
                    else:
                        groups[-1].append(self.names.index(field))
                structure.append([heading] + self.answer_dsep(groups))
            elif kind == "BLANKET":
                structure.append([heading] + self.answer_blanket(self.names.index(fields[0])))
            else:
                operation, x, y = fields
                structure.append([heading] + self.answer_edge(operation, self.names.index(x), self.names.index(y)))
        return answers, elimination, structure, sampling


def main():
    network, samples, queries, params = read_inputs()
    analysis = NetworkAnalysis(network, samples, params)
    cpts = analysis.cpt_blocks()
    answers, elimination, structure, sampling = analysis.process_queries(queries)
    output = Path("output")
    output.mkdir(exist_ok=True)
    write_blocks(output / "cpts.txt", cpts)
    write_blocks(output / "structure.txt", structure)
    write_blocks(output / "answers.txt", answers)
    write_blocks(output / "elimination.txt", elimination)
    write_blocks(output / "sampling.csv", [sampling])


if __name__ == "__main__":
    main()
