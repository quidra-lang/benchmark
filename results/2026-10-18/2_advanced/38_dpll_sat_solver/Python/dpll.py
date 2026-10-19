"""Iterative DPLL with two watched literals, DLIS and chronological flips."""

from collections import Counter, defaultdict


def search(variable_count, source_clauses):
    """Run one round; never recurse and never mutate the supplied clauses."""
    clauses = [list(clause) for clause in source_clauses]
    values = [None] * (variable_count + 1)
    trail = []
    propagation_position = 0
    watched = defaultdict(list)
    trace = []
    decisions = 0
    propagations = 0
    conflicts = 0
    max_depth = 0

    def state(literal):
        value = values[abs(literal)]
        if value is None:
            return None
        return value if literal > 0 else not value

    def assign(literal, kind):
        values[abs(literal)] = literal > 0
        trail.append((literal, kind))
        trace.append({"decision": "D", "flip": "F",
                      "propagation": "P"}[kind] + str(literal))

    def stats():
        return {
            "decisions": decisions,
            "propagations": propagations,
            "conflicts": conflicts,
            "max_depth": max_depth,
            "trace": trace,
        }

    for i, clause in enumerate(clauses):
        if len(clause) >= 2:
            watched[clause[0]].append(i)
            watched[clause[1]].append(i)

    for clause in clauses:
        if not clause:
            conflicts += 1
            trace.append("C")
            return None, stats()
        if len(clause) != 1:
            continue
        literal = clause[0]
        if state(literal) is False:
            conflicts += 1
            trace.append("C")
            return None, stats()
        if state(literal) is None:
            assign(literal, "propagation")
            propagations += 1

    while True:
        contradiction = False
        while propagation_position < len(trail) and not contradiction:
            literal, _ = trail[propagation_position]
            propagation_position += 1
            false_literal = -literal
            queue = watched[false_literal]
            position = 0
            while position < len(queue):
                index = queue[position]
                clause = clauses[index]
                if clause[0] == false_literal:
                    clause[0], clause[1] = clause[1], clause[0]
                other = clause[0]
                if state(other) is True:
                    position += 1
                    continue
                replacement = next(
                    (j for j in range(2, len(clause))
                     if state(clause[j]) is not False),
                    None,
                )
                if replacement is not None:
                    clause[1], clause[replacement] = (
                        clause[replacement], clause[1]
                    )
                    queue.pop(position)
                    watched[clause[1]].append(index)
                    continue
                if state(other) is False:
                    conflicts += 1
                    trace.append("C")
                    contradiction = True
                    break
                if state(other) is None:
                    assign(other, "propagation")
                    propagations += 1
                position += 1

        if contradiction:
            while trail and trail[-1][1] != "decision":
                literal, kind = trail.pop()
                values[abs(literal)] = None
            if not trail:
                return None, stats()
            last_decision, _ = trail.pop()
            values[abs(last_decision)] = None
            assign(-last_decision, "flip")
            propagation_position = len(trail) - 1
            continue

        occurrences = Counter()
        for clause in clauses:
            if any(state(lit) is True for lit in clause):
                continue
            for literal in clause:
                if state(literal) is None:
                    occurrences[literal] += 1
        if not occurrences:
            model = [False] * (variable_count + 1)
            for variable in range(1, variable_count + 1):
                model[variable] = bool(values[variable])
            return model, stats()

        chosen = min(
            occurrences, key=lambda lit: (
                -occurrences[lit], abs(lit), lit < 0
            )
        )
        assign(chosen, "decision")
        decisions += 1
        depth = sum(kind in ("decision", "flip") for _, kind in trail)
        if depth > max_depth:
            max_depth = depth
