"""Explicit-trail DPLL with two watched literals and DLIS decisions."""

from collections import defaultdict


def run_round(variable_count, search_clauses):
    """Run one fresh DPLL search, returning a model, event trace and statistics."""
    clauses = [list(clause) for clause in search_clauses]
    assignment = [None] * (variable_count + 1)
    watches = defaultdict(list)
    trail = []
    queue_head = 0
    trace = []
    stats = {"decisions": 0, "propagations": 0,
             "conflicts": 0, "max_depth": 0}

    def value(literal):
        val = assignment[abs(literal)]
        return None if val is None else (val if literal > 0 else not val)

    def assign(literal, kind):
        assignment[abs(literal)] = literal > 0
        trail.append((literal, kind))
        trace.append({"decision": "D", "flip": "F", "propagation": "P"}[kind]
                     + str(literal))

    def conflict():
        stats["conflicts"] += 1
        trace.append("C")

    for index, clause in enumerate(clauses):
        if len(clause) >= 2:
            watches[clause[0]].append(index)
            watches[clause[1]].append(index)

    for clause in clauses:
        if not clause:
            conflict()
            return None, trace, stats
        if len(clause) == 1:
            literal = clause[0]
            truth = value(literal)
            if truth is False:
                conflict()
                return None, trace, stats
            if truth is None:
                assign(literal, "propagation")
                stats["propagations"] += 1

    while True:
        found_conflict = False
        while queue_head < len(trail):
            true_literal = trail[queue_head][0]
            queue_head += 1
            false_literal = -true_literal
            watch_list = watches[false_literal]
            index = 0
            while index < len(watch_list):
                clause_id = watch_list[index]
                clause = clauses[clause_id]
                if clause[0] == false_literal:
                    clause[0], clause[1] = clause[1], clause[0]
                other = clause[0]
                if value(other) is True:
                    index += 1
                    continue

                substitute = None
                for j in range(2, len(clause)):
                    if value(clause[j]) is not False:
                        substitute = j
                        break
                if substitute is not None:
                    clause[1], clause[substitute] = clause[substitute], clause[1]
                    # Removing this watch preserves the order of the remaining
                    # entries; the new watch is appended to its literal's list.
                    watch_list.pop(index)
                    watches[clause[1]].append(clause_id)
                    continue

                other_value = value(other)
                if other_value is False:
                    conflict()
                    found_conflict = True
                    break
                if other_value is None:
                    assign(other, "propagation")
                    stats["propagations"] += 1
                index += 1
            if found_conflict:
                break

        if found_conflict:
            # Remove propagations and exhausted flips to the nearest decision.
            while trail and trail[-1][1] != "decision":
                literal, _ = trail.pop()
                assignment[abs(literal)] = None
            if not trail:
                return None, trace, stats
            decision, _ = trail.pop()
            assignment[abs(decision)] = None
            assign(-decision, "flip")
            queue_head = len(trail) - 1
            continue

        counts = defaultdict(int)
        for clause in clauses:
            if any(value(literal) is True for literal in clause):
                continue
            for literal in clause:
                if value(literal) is None:
                    counts[literal] += 1
        if not counts:
            return [False if x is None else x for x in assignment], trace, stats

        best = max(
            counts, key=lambda literal:
            (counts[literal], -abs(literal), literal > 0)
        )
        assign(best, "decision")
        stats["decisions"] += 1
        depth = sum(kind in ("decision", "flip") for _, kind in trail)
        stats["max_depth"] = max(stats["max_depth"], depth)
