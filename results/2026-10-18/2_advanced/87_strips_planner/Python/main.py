"""Validate, ground, solve, analyze, and repair the specified STRIPS problems."""

from collections import Counter
from itertools import combinations
from pathlib import Path
from types import SimpleNamespace

from graphplan import PlanningGraph
from grounding import ground, predicate_classes, substitute, subtype
from heuristics import Heuristics, NAMES
from pddl_parser import read_domain, read_problems
from search import applicable, apply, result, run


def notation(atom):
    return "(" + " ".join((atom[0], *atom[1])) + ")"


def action_text(action):
    return notation((action.source.name, action.arguments))


def number_list(numbers):
    return ",".join(map(str, sorted(numbers))) or "-"


def headed(heading, items):
    return heading + " " + (" ".join(items) or "-")


def value_text(value):
    return "inf" if value is None else str(value)


def heuristic_text(values):
    return " ".join(name + "=" + value_text(values[name]) for name in NAMES)


def read_settings(text):
    settings = {"runs": []}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split(" ")
        if fields[0] == "run":
            settings["runs"].append(tuple(fields[1:]))
        elif fields[0] == "repair":
            settings["repair"] = tuple(fields[1:])
        else:
            settings[fields[0]] = int(fields[1])
    return settings


def read_candidates(text):
    candidates = []
    current = None
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        if line.startswith("plan "):
            _, problem, label = line.split(" ")
            current = SimpleNamespace(number=len(candidates) + 1, problem=problem, label=label, steps=[])
        elif line == "end":
            candidates.append(current)
            current = None
        else:
            fields = line[1:-1].split(" ")
            current.steps.append((fields[0], tuple(fields[1:])))
    return candidates


def argument_error(domain, arguments, expected, table, noun):
    if len(arguments) != len(expected):
        return f"expected {len(expected)} arguments, got {len(arguments)}"
    for position, (argument, kind) in enumerate(zip(arguments, expected), 1):
        if argument not in table:
            return f"unknown {noun} {argument}"
        if not subtype(domain.parents, table[argument], kind):
            return f"argument {position} ({argument}) is not of type {kind}"
    return None


def validate_domain(domain):
    kept, diagnostics = [], []
    for action in domain.actions:
        error = None
        for _, kind in action.parameters:
            if kind not in domain.parents:
                error = "unknown type " + kind
                break
        if error is None:
            parameters = dict(action.parameters)
            for _, atom in action.condition + action.effects:
                if atom.predicate != "=" and atom.predicate not in domain.predicates:
                    error = "unknown predicate " + atom.predicate
                else:
                    expected = ("object", "object") if atom.predicate == "=" else domain.predicates[atom.predicate]
                    error = argument_error(domain, atom.terms, expected, parameters, "variable")
                if error is not None:
                    error = notation(atom) + ": " + error
                    break
        if error is None:
            kept.append(action)
        else:
            diagnostics.append(f"error: action {action.name}: {error}")
    domain.actions = kept
    domain.by_name = {action.name: action for action in kept}
    used = {atom.predicate for action in kept for _, atom in action.condition + action.effects}
    for predicate in domain.predicates:
        if predicate not in used:
            diagnostics.append(f"warning: predicate {predicate} is not used by any action")
    domain.fluent, domain.static = predicate_classes(domain)
    domain.diagnostics = diagnostics


def validate_problem(domain, problem):
    diagnostics = []
    for side, attribute in (("init", "initial"), ("goal", "goals")):
        kept, seen = [], set()
        for atom in getattr(problem, attribute):
            if atom.predicate not in domain.predicates:
                error = "unknown predicate " + atom.predicate
            else:
                error = argument_error(domain, atom.terms, domain.predicates[atom.predicate], problem.objects, "object")
            if error is None and atom in seen:
                error = "duplicate"
            if error is None:
                kept.append(atom)
                seen.add(atom)
            else:
                diagnostics.append(f"warning: {side} {notation(atom)}: {error}")
        setattr(problem, attribute, kept)
    problem.diagnostics = diagnostics


def validation_result(status, messages, correct):
    return SimpleNamespace(status=status, messages=messages, correct=correct)


def validate_steps(domain, problem, steps):
    world, cost = set(problem.initial), 0
    for position, (name, arguments) in enumerate(steps, 1):
        heading = f"step {position} {notation((name, arguments))}: "
        if name not in domain.by_name:
            return validation_result("invalid", [heading + "unknown action " + name], position - 1)
        schema = domain.by_name[name]
        expected = [kind for _, kind in schema.parameters]
        error = argument_error(domain, arguments, expected, problem.objects, "object")
        if error is not None:
            return validation_result("invalid", [heading + error], position - 1)
        assignment = dict(zip((name for name, _ in schema.parameters), arguments))
        for sign, atom in schema.condition:
            bound = substitute(atom, assignment)
            truth = bound.terms[0] == bound.terms[1] if bound.predicate == "=" else bound in world
            if truth != sign:
                literal = notation(bound) if sign else "(not " + notation(bound) + ")"
                return validation_result("invalid", [heading + "precondition " + literal + " is false"], position - 1)
        deletes = {substitute(atom, assignment) for sign, atom in schema.effects if not sign}
        adds = {substitute(atom, assignment) for sign, atom in schema.effects if sign}
        world.difference_update(deletes)
        world.update(adds)
        cost += schema.cost
    missing = ["unsatisfied goal " + notation(atom) for atom in problem.goals if atom not in world]
    if missing:
        return validation_result("goal not reached", missing, len(steps))
    return validation_result("valid", [f"length={len(steps)} cost={cost}"], len(steps))


def verdict(validation):
    separator = " " if validation.status == "valid" else ": "
    return validation.status + separator + validation.messages[0]


def plan_steps(problem, plan):
    return [(problem.actions[number].source.name, problem.actions[number].arguments) for number in plan]


def plan_cost(problem, plan):
    return sum(problem.actions[number].cost for number in plan)


def interferes(first, second):
    return (bool(first.delete & (second.pre | second.add))
            or bool(second.delete & (first.pre | first.add))
            or bool(first.add & second.neg) or bool(second.add & first.neg))


def parallelize(problem, plan):
    assigned, layers = [], []
    for position, number in enumerate(plan):
        action, layer = problem.actions[number], 1
        for earlier in range(position):
            previous = problem.actions[plan[earlier]]
            if previous.add & action.pre or previous.delete & action.neg or interferes(previous, action):
                layer = max(layer, assigned[earlier] + 1)
        assigned.append(layer)
        while len(layers) < layer:
            layers.append([])
        layers[layer - 1].append(number)
    return layers


def validate_parallel(problem, layers):
    state = problem.initial
    for position, layer in enumerate(layers, 1):
        actions = [problem.actions[number] for number in layer]
        if any(not applicable(action, state) for action in actions):
            return "invalid at layer " + str(position)
        if any(interferes(first, second) for first, second in combinations(actions, 2)):
            return "invalid at layer " + str(position)
        deletes = frozenset(fact for action in actions for fact in action.delete)
        adds = frozenset(fact for action in actions for fact in action.add)
        state = (state - deletes) | adds
    return "valid" if problem.goal <= state else "goal not reached"


def improve(problem, plan):
    sequence, position = list(plan), 0
    while position < len(sequence):
        state = problem.initial
        for number in sequence[:position]:
            state = apply(problem.actions[number], state)
        applied = []
        for number in sequence[position + 1:]:
            action = problem.actions[number]
            if applicable(action, state):
                state = apply(action, state)
                applied.append(number)
        if problem.goal <= state:
            sequence = sequence[:position] + applied
        else:
            position += 1
    return tuple(sequence)


def reached_landmarks(problem, plan, landmarks):
    state, reached = problem.initial, set()
    for number in plan:
        state = apply(problem.actions[number], state)
        reached.update(state & landmarks)
    return reached


def transform_negatives(problem):
    negative = sorted({fact for action in problem.actions for fact in action.neg})
    complements = {fact: len(problem.facts) + index for index, fact in enumerate(negative)}
    actions = []
    for action in problem.actions:
        pre = action.pre | frozenset(complements[fact] for fact in action.neg)
        add = action.add | frozenset(complements[fact] for fact in action.delete if fact in complements)
        delete = action.delete | frozenset(complements[fact] for fact in action.add if fact in complements)
        actions.append(SimpleNamespace(number=action.number, pre=pre, add=add, delete=delete))
    initial = problem.initial | frozenset(complements[fact] for fact in negative if fact not in problem.initial)
    return actions, initial, len(negative)


class Planner:
    def __init__(self):
        self.domain = read_domain(Path("input/domain.txt").read_text(encoding="ascii"))
        self.sources = read_problems(Path("input/problems.txt").read_text(encoding="ascii"))
        self.settings = read_settings(Path("input/params.txt").read_text(encoding="ascii"))
        self.candidates = read_candidates(Path("input/candidates.txt").read_text(encoding="ascii"))
        validate_domain(self.domain)
        self.tags = [" ".join(pair) for pair in self.settings["runs"]] + ["graphplan"]
        self.totals = [Counter() for _ in self.tags]
        self.grounding_lines, self.plan_lines, self.graph_lines, self.validation_lines = [], [], [], []
        self.comparison_lines = ["problem,algorithm,heuristic,length,cost,expanded,generated"]
        self.problems, self.evaluators, self.summaries = {}, {}, {}
        self.validated_plans, self.valid_plans, self.valid_candidates = 0, 0, 0

    def domain_report(self):
        domain, lines = self.domain, self.grounding_lines
        lines.append(f"== domain {domain.name} ==")
        lines.extend(domain.diagnostics)
        for kind in domain.type_order:
            chain, current = [], kind
            while current is not None:
                chain.append(current)
                current = domain.parents[current]
            lines.append("type " + " < ".join(chain))
        for predicate, arguments in domain.predicates.items():
            kind = "fluent" if predicate in domain.fluent else "static"
            lines.append(f"predicate {predicate}/{len(arguments)} {kind}")
        for action in domain.actions:
            adds = sum(sign for sign, _ in action.effects)
            deletes = sum(not sign for sign, _ in action.effects)
            lines.append(f"action {action.name}/{len(action.parameters)} cost={action.cost} "
                         f"pre={len(action.condition)} add={adds} del={deletes}")

    def grounding_report(self, problem):
        lines = self.grounding_lines
        lines.extend(["", f"== problem {problem.name} =="])
        lines.extend(problem.source.diagnostics)
        lines.append("objects: " + str(len(problem.source.objects)))
        for kind in self.domain.type_order:
            lines.append(headed("  " + kind + ":", problem.objects_by_type[kind]))
        lines.append("static facts: " + str(problem.static_count))
        for action in self.domain.actions:
            assignments, candidates, reachable = problem.statistics[action.name]
            lines.append(f"schema {action.name}: assignments={assignments} candidates={candidates} reachable={reachable}")
        lines.append(f"candidates: {problem.candidate_count} reachable: {len(problem.actions)}")
        lines.append(f"facts: {len(problem.facts)} init: {len(problem.initial)} goals: {len(problem.goal)}")
        lines.extend("unreachable goal: " + notation(atom) for atom in problem.unreachable)
        counts = Counter(atom.predicate for atom in problem.facts)
        lines.append(headed("facts by predicate:", [f"{name}={counts[name]}" for name in self.domain.predicates
                                                   if name in self.domain.fluent]))
        lines.append("facts:")
        lines.extend(f"  {number} {notation(atom)}" for number, atom in enumerate(problem.facts))
        lines.append("actions:")
        for action in problem.actions:
            lines.append(f"  {action.number} {action_text(action)} cost={action.cost} pre={number_list(action.pre)} "
                         f"neg={number_list(action.neg)} add={number_list(action.add)} del={number_list(action.delete)}")

    def initial_report(self, problem, evaluator):
        values = evaluator.values(problem.initial)
        landmarks = evaluator.landmarks(problem.initial) or frozenset()
        relaxed = evaluator.relaxed_plan(problem.initial) or ()
        lines = self.plan_lines
        lines.append("initial h: " + heuristic_text(values))
        lines.append("landmarks: " + str(len(landmarks)))
        lines.extend("  " + notation(problem.facts[number]) for number in sorted(landmarks))
        lines.append(f"relaxed plan: length={len(relaxed)} cost={value_text(values['ff'])}")
        lines.extend("  " + action_text(problem.actions[number]) for number in relaxed)
        lines.append(headed("helpful:", [action_text(problem.actions[number]) for number in evaluator.helpful(problem.initial)]))
        return landmarks

    def plan_report(self, problem, tag, plan, landmarks, earlier):
        lines, cost = self.plan_lines, plan_cost(problem, plan)
        first = earlier.setdefault(plan, tag)
        suffix = " (same as " + first + ")" if first != tag else ""
        lines.append(f"plan: length={len(plan)} cost={cost}" + suffix)
        lines.extend(f"  {position} {action_text(problem.actions[number])}" for position, number in enumerate(plan, 1))
        counts = Counter(problem.actions[number].source.name for number in plan)
        lines.append(headed("schemas:", [f"{action.name}={counts[action.name]}" for action in self.domain.actions
                                         if counts[action.name]]))
        layers = parallelize(problem, plan)
        lines.append("parallel: layers=" + str(len(layers)))
        for position, layer in enumerate(layers, 1):
            lines.append(headed(f"  {position}:", [action_text(problem.actions[number]) for number in layer]))
        improved = improve(problem, plan)
        removed = len(plan) - len(improved)
        lines.append(f"improved: length={len(improved)} cost={plan_cost(problem, improved)} removed={removed}")
        if removed:
            lines.extend(f"  {position} {action_text(problem.actions[number])}" for position, number in enumerate(improved, 1))
        reached = reached_landmarks(problem, plan, landmarks)
        lines.append(f"landmarks reached: {len(reached)}/{len(landmarks)}")
        lines.extend("  missed " + notation(problem.facts[number]) for number in sorted(landmarks - reached))
        checked = validate_steps(self.domain, problem.source, plan_steps(problem, plan))
        checked_improved = validate_steps(self.domain, problem.source, plan_steps(problem, improved))
        self.validation_lines.append(tag + ": " + verdict(checked))
        self.validation_lines.append("  parallel: " + validate_parallel(problem, layers))
        self.validation_lines.append("  improved: " + verdict(checked_improved))
        self.validated_plans += 1
        self.valid_plans += checked.status == "valid"

    def search_result_report(self, problem, tag, outcome, landmarks, earlier):
        self.plan_lines.append("-- " + tag + " --")
        if problem.unreachable:
            self.plan_lines.append("result: FAIL (unreachable goal)")
            return
        state = "solved" if outcome.status == "solved" else "FAIL (" + outcome.status + ")"
        self.plan_lines.append(f"result: {state} expanded={outcome.expanded} generated={outcome.generated}")
        if outcome.status == "solved":
            self.plan_report(problem, tag, outcome.plan, landmarks, earlier)

    def graph_report(self, problem, outcome, complements):
        lines = self.graph_lines
        if problem.unreachable:
            lines.append("result: FAIL (unreachable goal)")
            return
        lines.append("complementary facts: " + str(complements))
        lines.extend(outcome.lines)
        counts = f" searched={outcome.expanded} memo_hits={outcome.memo_hits} tried={outcome.generated}"
        if outcome.status == "solved":
            lines.append(f"result: solved levels={len(outcome.layers)} length={len(outcome.plan)} "
                         f"cost={plan_cost(problem, outcome.plan)}" + counts)
            for position, layer in enumerate(outcome.layers, 1):
                lines.append(headed(f"layer {position}:", [action_text(problem.actions[number]) for number in layer]))
        else:
            lines.append("result: FAIL (" + outcome.status + ")" + counts)

    def profile_report(self, problem, evaluator, tag, plan):
        lines, state = self.plan_lines, problem.initial
        remaining, overestimates = plan_cost(problem, plan), Counter()
        lines.append("-- profile (" + tag + ") --")
        for position in range(len(plan) + 1):
            values = evaluator.values(state)
            lines.append(f"  {position}: h*={remaining} " + heuristic_text(values))
            for name, value in values.items():
                if value is None or value > remaining:
                    overestimates[name] += 1
            if position < len(plan):
                action = problem.actions[plan[position]]
                state = apply(action, state)
                remaining -= action.cost
        lines.append("overestimates: " + " ".join(f"{name}={overestimates[name]}" for name in NAMES))
        lines.append("-- causal links (" + tag + ") --")
        suppliers = {}
        for position, number in enumerate(plan, 1):
            action = problem.actions[number]
            links = [notation(problem.facts[fact]) + "<-" + str(suppliers.get(fact, 0)) for fact in sorted(action.pre)]
            lines.append(headed(f"  {position} {action_text(action)}:", links))
            for fact in action.add:
                suppliers[fact] = position
        goal_links = [notation(problem.facts[fact]) + "<-" + str(suppliers.get(fact, 0)) for fact in sorted(problem.goal)]
        lines.append(headed("  goal:", goal_links))

    def summarize_problem(self, problem, outcomes, proof):
        solved = [outcome for outcome in outcomes if outcome.status == "solved"]
        best = min((plan_cost(problem, outcome.plan) for outcome in solved), default=None)
        if proof is not None:
            optimal = str(plan_cost(problem, outcomes[proof].plan))
        elif any(outcome.status in ("unreachable goal", "dead end", "exhausted", "unreachable") for outcome in outcomes):
            optimal = "none"
        else:
            optimal = "unknown"
        self.summaries[problem.name] = SimpleNamespace(solved=len(solved), best=best, optimal=optimal)
        pairs = self.settings["runs"] + [("graphplan", "none")]
        for index, (outcome, (algorithm, heuristic)) in enumerate(zip(outcomes, pairs)):
            totals = self.totals[index]
            totals["expanded"] += outcome.expanded
            totals["generated"] += outcome.generated
            length, cost = "-", "-"
            if outcome.status == "solved":
                length, cost = str(len(outcome.plan)), str(plan_cost(problem, outcome.plan))
                totals["solved"] += 1
                totals["best"] += int(cost) == best
            self.comparison_lines.append(f"{problem.name},{algorithm},{heuristic},{length},{cost},"
                                         f"{outcome.expanded},{outcome.generated}")

    def solve_problem(self, source):
        validate_problem(self.domain, source)
        problem = ground(self.domain, source)
        self.problems[problem.name] = problem
        self.grounding_report(problem)
        for lines in (self.plan_lines, self.graph_lines, self.validation_lines):
            lines.append(f"== problem {problem.name} ==")
        outcomes, earlier, proof = [], {}, None
        if problem.unreachable:
            self.plan_lines.append("initial h: unreachable goal")
            evaluator, landmarks = None, frozenset()
        else:
            evaluator = Heuristics(problem)
            self.evaluators[problem.name] = evaluator
            landmarks = self.initial_report(problem, evaluator)
        for index, (algorithm, heuristic) in enumerate(self.settings["runs"]):
            if problem.unreachable:
                outcome = result("unreachable goal")
            else:
                outcome = run(problem, problem.initial, algorithm, heuristic, self.settings["budget"],
                              self.settings["weight"], evaluator)
            outcomes.append(outcome)
            self.search_result_report(problem, self.tags[index], outcome, landmarks, earlier)
            if proof is None and (algorithm, heuristic) in (("ucs", "none"), ("astar", "hmax")) and outcome.status == "solved":
                proof = index
        complements = 0
        if problem.unreachable:
            graph = result("unreachable goal")
        else:
            actions, initial, complements = transform_negatives(problem)
            graph = PlanningGraph(actions, initial, problem.goal, self.settings["graphplan"]).run()
        outcomes.append(graph)
        self.search_result_report(problem, "graphplan", graph, landmarks, earlier)
        self.graph_report(problem, graph, complements)
        if proof is not None:
            self.profile_report(problem, evaluator, self.tags[proof], outcomes[proof].plan)
        self.summarize_problem(problem, outcomes, proof)
        for lines in (self.plan_lines, self.graph_lines, self.validation_lines):
            lines.append("")

    def summary_report(self):
        self.plan_lines.append("== summary ==")
        for name, summary in self.summaries.items():
            best = "-" if summary.best is None else str(summary.best)
            self.plan_lines.append(f"{name}: solved={summary.solved}/{len(self.tags)} best={best} optimal={summary.optimal}")
        for tag, totals in zip(self.tags, self.totals):
            self.plan_lines.append(f"{tag}: solved={totals['solved']} best={totals['best']} "
                                   f"expanded={totals['expanded']} generated={totals['generated']}")

    def mapped_steps(self, problem, steps):
        return tuple(problem.action_numbers[step] for step in steps)

    def repair_candidate(self, problem, candidate, checked):
        if problem.unreachable:
            self.validation_lines.append("  repair: FAIL (unreachable goal)")
            return
        prefix = self.mapped_steps(problem, candidate.steps[:checked.correct])
        state = problem.initial
        for number in prefix:
            state = apply(problem.actions[number], state)
        algorithm, heuristic = self.settings["repair"]
        outcome = run(problem, state, algorithm, heuristic, self.settings["budget"],
                      self.settings["weight"], self.evaluators[problem.name])
        if outcome.status != "solved":
            self.validation_lines.append("  repair: FAIL (" + outcome.status + ")")
            return
        repaired = prefix + outcome.plan
        validation = validate_steps(self.domain, problem.source, plan_steps(problem, repaired))
        self.validation_lines.append(f"  repair: kept={len(prefix)} added={len(outcome.plan)} " + verdict(validation))
        self.validation_lines.extend(f"    {position} {action_text(problem.actions[number])}"
                                     for position, number in enumerate(repaired, 1))

    def candidate_report(self):
        lines = self.validation_lines
        lines.append("== candidates ==")
        for candidate in self.candidates:
            problem = self.problems[candidate.problem]
            checked = validate_steps(self.domain, problem.source, candidate.steps)
            heading = f"candidate {candidate.number} {candidate.problem} {candidate.label}: "
            if checked.status == "valid":
                self.valid_candidates += 1
                lines.append(heading + verdict(checked))
                mapped = self.mapped_steps(problem, candidate.steps)
                improved = improve(problem, mapped)
                best = self.summaries[problem.name].best
                best_text = "-" if best is None else str(best)
                lines.append(f"  improved: length={len(improved)} cost={plan_cost(problem, improved)} "
                             f"removed={len(mapped) - len(improved)} best known={best_text}")
            else:
                lines.append(heading + checked.status)
                lines.extend("  " + message for message in checked.messages)
                self.repair_candidate(problem, candidate, checked)
        lines.extend(["", "== summary ==", f"plans: {self.validated_plans} valid: {self.valid_plans}",
                      f"candidates: {len(self.candidates)} valid: {self.valid_candidates}"])

    def write_reports(self):
        directory = Path("output")
        directory.mkdir(exist_ok=True)
        reports = (("grounding.txt", self.grounding_lines), ("plans.txt", self.plan_lines),
                   ("graphplan.txt", self.graph_lines), ("validation.txt", self.validation_lines),
                   ("comparison.csv", self.comparison_lines))
        for name, lines in reports:
            (directory / name).write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")

    def run(self):
        self.domain_report()
        for source in self.sources:
            self.solve_problem(source)
        self.summary_report()
        self.candidate_report()
        self.write_reports()


def main():
    Planner().run()


if __name__ == "__main__":
    main()
