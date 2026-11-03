"""Evaluate RBAC and attribute policies, explain decisions and analyze coverage."""

import operator
from collections import Counter, defaultdict, namedtuple
from pathlib import Path

from analysis import blocker, conflict_winner, day_notation, points
from combining import ID, IP, NA, combine
from policy_parser import read_policies
from rbac import RBAC


DEFINITE = ("PERMIT", "DENY")
Request = namedtuple("Request", "identifier user roles action resource environment explain")
OPERATORS = {"+": operator.add, "-": operator.sub, "*": operator.mul,
             "==": operator.eq, "!=": operator.ne, "<": operator.lt,
             "<=": operator.le, ">": operator.gt, ">=": operator.ge}


class Error:
    def __init__(self, reason):
        self.reason = reason


def input_value(text):
    if text in ("true", "false"):
        return text == "true"
    if text.startswith("["):
        return tuple(text[1:-1].split(",")) if text != "[]" else ()
    if text.lstrip("-").isdigit():
        return int(text)
    return text


def attributes(fields):
    return {name: input_value(value) for name, value in (field.split("=", 1) for field in fields)}


def value_notation(value):
    if type(value) is bool:
        return "true" if value else "false"
    if type(value) is int:
        return str(value)
    if type(value) is str:
        return '"' + value + '"'
    return "[" + ",".join(value_notation(item) for item in value) + "]"


def read_attributes():
    subjects, resources, domains, reference = {}, {}, [], {}
    for line in Path("input/attributes.txt").read_text(encoding="ascii").splitlines():
        kind, *fields = line.split()
        if kind == "SUBJECT":
            subjects[fields[0]] = attributes(fields[1:])
        elif kind == "RESOURCE":
            resources[fields[0]] = fields[1], attributes(fields[2:])
        elif kind == "DOMAIN":
            domains.append((fields[0], [input_value(value) for value in fields[1:]]))
        else:
            reference = attributes(fields)
    return subjects, resources, domains, reference


def read_requests():
    requests = []
    for line in Path("input/requests.txt").read_text(encoding="ascii").splitlines():
        fields = line.split()
        explain = fields[-1] == "EXPLAIN"
        if explain:
            fields.pop()
        requests.append(Request(*fields[:5], attributes(fields[5:]), explain))
    return requests


def first_error(values):
    return next((value for value in values if isinstance(value, Error)), None)


def boolean_result(values, veto, name):
    checked = [value if type(value) is bool or isinstance(value, Error) else Error("type " + name)
               for value in values]
    if any(value is veto for value in checked):
        return veto
    error = first_error(checked)
    return error if error is not None else not veto


def operation(name, values):
    error = first_error(values)
    if error is not None:
        return error
    kinds = [type(value) for value in values]
    if name in ("+", "-", "*", "<", "<=", ">", ">="):
        if all(kind is int for kind in kinds):
            if len(values) == 1:
                return -values[0]
            return OPERATORS[name](*values)
    elif name in ("==", "!="):
        if kinds[0] is kinds[1] and kinds[0] in (int, str, bool):
            return OPERATORS[name](*values)
    elif name == "in":
        if kinds == [str, tuple]:
            return values[0] in values[1]
    elif name == "not":
        if kinds == [bool]:
            return not values[0]
    elif name in ("starts_with", "^="):
        if kinds == [str, str]:
            return values[0].startswith(values[1])
    elif name == "size":
        if kinds == [tuple]:
            return len(values[0])
    return Error("type " + name)


def expression(tree, values, current=None):
    name, *arguments = tree
    if name == "literal":
        return arguments[0]
    if name == "attribute":
        reference = arguments[0]
        return values[reference] if reference in values else Error("missing " + reference)
    if name == "it":
        return current
    if name == "present":
        return arguments[0][1] in values
    if name in ("any_of", "all_of"):
        bag = expression(arguments[0], values, current)
        if isinstance(bag, Error):
            return bag
        if type(bag) is not tuple:
            return Error("type " + name)
        predicates = [expression(arguments[1], values, item) for item in bag]
        return boolean_result(predicates, name == "any_of", name)
    operands = [expression(argument, values, current) for argument in arguments]
    if name in ("and", "or"):
        return boolean_result(operands, name == "or", name)
    return operation(name, operands)


def target_group(results, conjunction):
    if conjunction:
        if any(result == "NO_MATCH" for result, _ in results):
            return "NO_MATCH", None
        if all(result == "MATCH" for result, _ in results):
            return "MATCH", None
    else:
        if any(result == "MATCH" for result, _ in results):
            return "MATCH", None
    for result, reason in results:
        if result == "INDETERMINATE":
            return result, reason
    return "NO_MATCH", None


def match_clause(clause, values):
    reference, mandatory, name, literal = clause
    if reference not in values:
        return ("INDETERMINATE", "missing " + reference) if mandatory else ("NO_MATCH", None)
    source = values[reference]
    items = source if type(source) is tuple else (source,)
    comparison = expression(literal, values)
    results = [operation(name, [item, comparison]) for item in items]
    if any(result is True for result in results):
        return "MATCH", None
    error = first_error(results)
    return ("INDETERMINATE", error.reason) if error is not None else ("NO_MATCH", None)


def decision_notation(decision, reason):
    return decision + " (" + reason + ")" if decision.startswith("INDETERMINATE") else decision


def final_notation(result):
    text = decision_notation(result.decision, result.reason)
    if result.decision in DEFINITE:
        text += " by " + result.decisive.identifier
    return text


class Evaluation:
    def __init__(self, element, target):
        self.element, self.target = element, target
        self.decision, self.reason, self.decisive = NA, None, None
        self.condition = None
        self.children, self.obligations, self.advice = [], [], []


class Evaluator:
    def __init__(self, values, coverage=None):
        self.values, self.coverage = values, coverage

    def target(self, element):
        lines = []
        for line in element.targets:
            alternatives = []
            for alternative in line:
                clauses = [match_clause(clause, self.values) for clause in alternative]
                alternatives.append(target_group(clauses, True))
            lines.append(target_group(alternatives, False))
        return target_group(lines, True)

    def attachments(self, result, supporters):
        for supporter in supporters:
            result.obligations.extend(supporter.obligations)
            result.advice.extend(supporter.advice)
        effect = result.decision
        for obligatory, definitions in ((True, result.element.obligations), (False, result.element.advice)):
            for required_effect, identifier, arguments in definitions:
                if required_effect != effect:
                    continue
                evaluated = [(name, expression(tree, self.values)) for name, tree in arguments]
                error = first_error([value for _, value in evaluated])
                if error is not None:
                    if obligatory:
                        result.decision = ID if effect == "DENY" else IP
                        result.reason = "obligation " + identifier + ": " + error.reason
                        result.decisive = None
                        result.obligations, result.advice = [], []
                        return
                    continue
                item = identifier + "".join(" " + name + "=" + value_notation(value) for name, value in evaluated)
                destination = result.obligations if obligatory else result.advice
                destination.append((identifier, item))

    def rule(self, element, obligations=True):
        result = Evaluation(element, self.target(element))
        target, reason = result.target
        indeterminate = ID if element.behavior == "DENY" else IP
        if target == "INDETERMINATE":
            result.decision, result.reason = indeterminate, reason
        elif target == "MATCH":
            condition = True if element.condition is None else expression(element.condition, self.values)
            if type(condition) is not bool and not isinstance(condition, Error):
                condition = Error("type condition")
            result.condition = condition
            if isinstance(condition, Error):
                result.decision, result.reason = indeterminate, condition.reason
            elif condition:
                result.decision, result.decisive = element.behavior, element
                if obligations:
                    self.attachments(result, [])
        if self.coverage is not None:
            self.coverage[element.identifier] = {"PERMIT": "P", "DENY": "D", NA: "-"}.get(result.decision, "I")
        return result

    def evaluate(self, element):
        if element.kind == "rule":
            return self.rule(element)
        result = Evaluation(element, self.target(element))
        target, reason = result.target
        if target == "NO_MATCH":
            return result
        result.decision, result.reason, result.children = combine(element.behavior, element.children,
                                                                 self.evaluate, self.target)
        if target == "INDETERMINATE":
            if result.decision in DEFINITE:
                result.decision = ID if result.decision == "DENY" else IP
            if result.decision.startswith("INDETERMINATE"):
                result.reason = reason
        if result.decision in DEFINITE:
            supporters = [state[1] for state in result.children
                          if state is not None and state[0] == "evaluated" and state[1].decision == result.decision]
            result.decisive = supporters[0].decisive if supporters else element
            self.attachments(result, supporters)
        return result


def tree_lines(result, depth=0):
    element, target = result.element, result.target[0]
    prefix = " " * (2 + 2 * depth)
    line = prefix + f"{element.kind} {element.identifier} {element.behavior} target {target}"
    if element.kind == "rule" and target == "MATCH":
        condition = "INDETERMINATE" if isinstance(result.condition, Error) else "TRUE" if result.condition else "FALSE"
        line += " condition " + condition
    lines = [line + " -> " + decision_notation(result.decision, result.reason)]
    if element.kind != "rule" and target != "NO_MATCH":
        for child, state in zip(element.children, result.children):
            if state is not None and state[0] == "evaluated":
                lines.extend(tree_lines(state[1], depth + 1))
            elif state is None:
                lines.append(prefix + f"  {child.kind} {child.identifier} skipped")
            else:
                checked, reason = state[1]
                line = prefix + f"  {child.kind} {child.identifier} {child.behavior} target {checked}"
                lines.append(line + (" (" + reason + ")" if checked == "INDETERMINATE" else ""))
    return lines


def join_blocks(blocks):
    lines = []
    for block in blocks:
        if lines:
            lines.append("")
        lines.extend(block)
    return lines


class Engine:
    def __init__(self):
        self.rbac = RBAC()
        self.root, self.elements = read_policies()
        self.rules = [element for element in self.elements if element.kind == "rule"]
        self.subjects, self.resources, self.domains, self.reference = read_attributes()
        self.requests = read_requests()
        self.coverage = {rule.identifier: [] for rule in self.rules}
        self.grant_counts, self.decisions, self.decisive = Counter(), Counter(), Counter()
        self.obligations, self.advice = Counter(), Counter()
        self.refused = 0

    def check_request(self, request):
        if request.user not in self.subjects:
            return "unknown user " + request.user
        if request.resource not in self.resources:
            return "unknown resource " + request.resource
        day = request.environment.get("day")
        if type(day) is not int or not 1 <= day <= 365:
            return "bad day"
        return None

    def activate(self, user, specification, day):
        authorized = self.rbac.authorized(user, day)
        candidates = [] if specification == "-" else sorted(authorized) if specification == "*" else specification.split(",")
        active, seen, activations = [], set(), []
        for candidate in candidates:
            reason = None
            if candidate not in self.rbac.roles:
                reason = "unknown"
            elif candidate in seen:
                reason = "duplicate"
            elif candidate not in authorized:
                reason = "unauthorized"
            else:
                closure = self.rbac.closure(set(active) | {candidate})
                for name, cardinality, roles in self.rbac.dsd:
                    if len(roles & closure) >= cardinality:
                        reason = "dsd " + name
                        break
            seen.add(candidate)
            if reason is None:
                active.append(candidate)
            activations.append((candidate, reason))
        return activations, sorted(self.rbac.closure(active))

    def prepare(self, request):
        activations, roles = self.activate(request.user, request.roles, request.environment["day"])
        resource_type, resource_attributes = self.resources[request.resource]
        grant = next((role for role in roles if (request.action, resource_type) in self.rbac.permissions[role]), None)
        values = {"subject." + name: value for name, value in self.subjects[request.user].items()}
        values.update({"subject.id": request.user, "subject.role": tuple(roles), "subject.rbac": grant is not None})
        values.update({"resource." + name: value for name, value in resource_attributes.items()})
        values.update({"resource.id": request.resource, "resource.type": resource_type, "action.id": request.action})
        values.update({"environment." + name: value for name, value in request.environment.items()})
        return activations, roles, grant, values

    def trace(self, request, activations, roles, grant, result):
        resource_type = self.resources[request.resource][0]
        lines = ["request " + request.identifier,
                 f"  user {request.user} resource {request.resource} type {resource_type} "
                 f"action {request.action} day {request.environment['day']}"]
        for role, reason in activations:
            lines.append("  activate " + role + (" ok" if reason is None else " refused " + reason))
        lines.append("  roles " + (",".join(roles) if roles else "-"))
        lines.append("  rbac " + ("yes " + grant if grant is not None else "no"))
        lines.extend(tree_lines(result))
        lines.append("  decision " + final_notation(result))
        return lines

    def process_requests(self):
        lines, explanations = [], []
        for request in self.requests:
            coverage = {rule.identifier: "." for rule in self.rules}
            error = self.check_request(request)
            if error is not None:
                lines.append(request.identifier + " ERROR " + error)
                self.decisions["ERROR"] += 1
                if request.explain:
                    explanations.append(["request " + request.identifier, "  error " + error])
            else:
                activations, roles, grant, values = self.prepare(request)
                result = Evaluator(values, coverage).evaluate(self.root)
                lines.append(request.identifier + " " + final_notation(result))
                for role, reason in activations:
                    if reason is not None:
                        lines.append("  refused " + role + " " + reason)
                        self.refused += 1
                for identifier, item in result.obligations:
                    lines.append("  obligation " + item)
                    self.obligations[identifier] += 1
                for identifier, item in result.advice:
                    lines.append("  advice " + item)
                    self.advice[identifier] += 1
                if grant is not None:
                    self.grant_counts[grant, request.action, self.resources[request.resource][0]] += 1
                category = "INDETERMINATE" if result.decision.startswith("INDETERMINATE") else result.decision
                self.decisions[category] += 1
                if result.decision in DEFINITE:
                    self.decisive[result.decisive.identifier] += 1
                if request.explain:
                    explanations.append(self.trace(request, activations, roles, grant, result))
            for rule in self.rules:
                self.coverage[rule.identifier].append(coverage[rule.identifier])
        return lines, join_blocks(explanations)

    def permission_report(self):
        blocks = []
        users = sorted({user for user, _, _, _ in self.rbac.assignments})
        for user in users:
            assigned, authorized = defaultdict(set), defaultdict(set)
            for owner, role, first, last in self.rbac.assignments:
                if owner == user:
                    assigned[role].update(range(first, last + 1))
            for role, days in assigned.items():
                for inherited in self.rbac.closure([role]):
                    authorized[inherited].update(days)
            lines = ["user " + user]
            for role in sorted(assigned):
                lines.append("  assigned " + role + " " + day_notation(assigned[role]))
            for role in sorted(authorized):
                lines.append("  authorized " + role + " " + day_notation(authorized[role]))
            via = defaultdict(list)
            for role in sorted(authorized):
                for permission in self.rbac.permissions[role]:
                    via[permission].append(role)
            for action, resource_type in sorted(via):
                roles = via[action, resource_type]
                days = set()
                for role in roles:
                    days.update(authorized[role])
                effective = "-"
                if user in self.subjects:
                    resources = [identifier for identifier, (kind, _) in self.resources.items() if kind == resource_type]
                    permitted = 0
                    for resource in resources:
                        request = Request("", user, "*", action, resource, self.reference, False)
                        _, _, _, values = self.prepare(request)
                        if Evaluator(values).evaluate(self.root).decision == "PERMIT":
                            permitted += 1
                    effective = f"{permitted}/{len(resources)}"
                lines.append(f"  permission {action} {resource_type} {day_notation(days)} "
                             f"via {','.join(roles)} effective {effective}")
            blocks.append(lines)
        return join_blocks(blocks)

    def domain_analysis(self):
        counts, examples, conflict_counts = Counter(), {}, Counter()
        ancestors = {}
        shadowed = {rule.identifier for rule in self.rules if rule.parent.behavior == "first-applicable"}
        blockers = defaultdict(set)
        pairs = []
        for rule in self.rules:
            chain, parent = [], rule.parent
            while parent is not None:
                chain.append(parent.identifier)
                parent = parent.parent
            ancestors[rule.identifier] = chain
        for policy in self.elements:
            if policy.kind == "policy":
                for index, earlier in enumerate(policy.children):
                    for later in policy.children[index + 1:]:
                        if earlier.behavior != later.behavior:
                            pairs.append((policy, earlier, later))
        point_count = 0
        for values in points(self.domains):
            point_count += 1
            evaluator = Evaluator(values)
            targets = {element.identifier: evaluator.target(element)[0] for element in self.elements if element.kind != "rule"}
            standalone = {rule.identifier: evaluator.rule(rule, obligations=False).decision for rule in self.rules}
            applying = set()
            for rule in self.rules:
                identifier = rule.identifier
                if standalone[identifier] not in DEFINITE or not all(targets[parent] == "MATCH" for parent in ancestors[identifier]):
                    continue
                applying.add(identifier)
                counts[identifier] += 1
                if identifier not in examples:
                    examples[identifier] = " ".join(name + "=" + value_notation(values[name])
                                                    for name, candidates in self.domains if len(candidates) >= 2)
                if identifier in shadowed:
                    earlier = blocker(rule, standalone)
                    if earlier is None:
                        shadowed.remove(identifier)
                    else:
                        blockers[identifier].add(earlier)
            for policy, earlier, later in pairs:
                if earlier.identifier in applying and later.identifier in applying:
                    conflict_counts[policy.identifier, earlier.identifier, later.identifier] += 1
        lines = ["applicability " + str(point_count)]
        for rule in self.rules:
            identifier = rule.identifier
            lines.append(f"  {identifier} {counts[identifier]} {examples.get(identifier, '-')}")
        dead = [rule.identifier for rule in self.rules if not counts[rule.identifier]]
        lines.append("dead " + str(len(dead)))
        lines.extend("  " + identifier for identifier in dead)
        shadowed.difference_update(dead)
        lines.append("shadowed " + str(len(shadowed)))
        for rule in self.rules:
            if rule.identifier in shadowed:
                names = [earlier.identifier for earlier in self.rules if earlier.identifier in blockers[rule.identifier]]
                lines.append("  " + rule.identifier + " by " + ",".join(names))
        conflicts = [(policy, earlier, later) for policy, earlier, later in pairs
                     if conflict_counts[policy.identifier, earlier.identifier, later.identifier]]
        lines.append("conflicts " + str(len(conflicts)))
        for policy, earlier, later in conflicts:
            count = conflict_counts[policy.identifier, earlier.identifier, later.identifier]
            winner = conflict_winner(policy, earlier, later)
            lines.append(f"  {policy.identifier} {earlier.identifier} {later.identifier} {count} {winner}")
        return lines

    def analysis_report(self):
        lines = ["rbac " + str(len(self.rbac.diagnostics))]
        for number, keyword, message in self.rbac.diagnostics:
            lines.append(f"  line {number} {keyword} {message}")
        lines.append("grants " + str(len(self.rbac.grants)))
        for role, action, resource_type in sorted(self.rbac.grants):
            lines.append(f"  {role} {action} {resource_type} {self.grant_counts[role, action, resource_type]}")
        lines.extend(self.domain_analysis())
        lines.append("coverage " + str(len(self.requests)))
        uncovered = []
        for rule in self.rules:
            symbols = "".join(self.coverage[rule.identifier])
            count = symbols.count("P") + symbols.count("D")
            lines.append(f"  {rule.identifier} {symbols} {count}")
            if count == 0:
                uncovered.append(rule.identifier)
        lines.append("uncovered " + str(len(uncovered)))
        lines.extend("  " + identifier for identifier in uncovered)
        lines.append("summary")
        for name in ("PERMIT", "DENY", NA, "INDETERMINATE", "ERROR"):
            lines.append(f"  decision {name} {self.decisions[name]}")
        lines.append("  refused " + str(self.refused))
        for element in self.elements:
            count = self.decisive[element.identifier]
            if count:
                lines.append(f"  decisive {element.identifier} {count}")
        for kind, counts in (("obligation", self.obligations), ("advice", self.advice)):
            for identifier in sorted(counts):
                lines.append(f"  {kind} {identifier} {counts[identifier]}")
        return lines

    def run(self):
        decisions, traces = self.process_requests()
        reports = [("decisions.txt", decisions), ("traces.txt", traces),
                   ("permissions.txt", self.permission_report()), ("analysis.txt", self.analysis_report())]
        Path("output").mkdir(exist_ok=True)
        for name, lines in reports:
            with open("output/" + name, "w", encoding="ascii", newline="\n") as destination:
                for line in lines:
                    destination.write(line + "\n")


def main():
    Engine().run()


if __name__ == "__main__":
    main()
