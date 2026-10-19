"""Deterministic best-first and helpful-action enforced hill-climbing searches."""

import heapq
from collections import deque, namedtuple
from types import SimpleNamespace


Node = namedtuple("Node", "state g depth parent action")


def applicable(action, state):
    return action.pre <= state and not action.neg & state


def apply(action, state):
    return (state - action.delete) | action.add


def successors(problem, state):
    for action in problem.actions:
        if applicable(action, state):
            yield action, apply(action, state)


def result(status, expanded=0, generated=0, plan=()):
    return SimpleNamespace(status=status, expanded=expanded, generated=generated, plan=tuple(plan))


def reconstruct(node):
    plan = []
    while node.parent is not None:
        plan.append(node.action)
        node = node.parent
    return tuple(reversed(plan))


def priority(algorithm, node, heuristic, weight):
    if algorithm == "bfs":
        return node.depth
    if algorithm == "ucs":
        return node.g
    if algorithm == "gbfs":
        return heuristic
    return node.g + heuristic * (weight if algorithm == "wastar" else 1)


def best_first(problem, start, algorithm, heuristic, budget, weight, evaluator):
    initial_h = evaluator.value(heuristic, start)
    if initial_h is None:
        return result("dead end")
    first = Node(start, 0, 0, None, None)
    queue = [(priority(algorithm, first, initial_h, weight), initial_h, 0, first)]
    best = {start: 0}
    serial, expanded, generated = 1, 0, 0
    reopen = algorithm in ("ucs", "astar", "wastar")
    while queue:
        _, _, _, node = heapq.heappop(queue)
        if reopen and node.g > best[node.state]:
            continue
        if problem.goal <= node.state:
            return result("solved", expanded, generated, reconstruct(node))
        if expanded == budget:
            return result("budget", expanded, generated)
        expanded += 1
        for action, state in successors(problem, node.state):
            generated += 1
            cost = node.g + action.cost
            if state in best and (not reopen or best[state] <= cost):
                continue
            best[state] = cost
            value = evaluator.value(heuristic, state)
            if value is None:
                continue
            child = Node(state, cost, node.depth + 1, node, action.number)
            heapq.heappush(queue, (priority(algorithm, child, value, weight), value, serial, child))
            serial += 1
    return result("exhausted", expanded, generated)


def hill_climbing(problem, start, heuristic, budget, evaluator):
    current, plan = start, ()
    current_h = evaluator.value(heuristic, current)
    expanded, generated = 0, 0
    if current_h is None:
        return result("dead end")
    while not problem.goal <= current:
        queue, visited = deque([(current, ())]), {current}
        improved = False
        while queue and not improved:
            state, prefix = queue.popleft()
            if expanded == budget:
                return result("budget", expanded, generated)
            expanded += 1
            for number in evaluator.helpful(state):
                successor = apply(problem.actions[number], state)
                generated += 1
                if successor in visited:
                    continue
                visited.add(successor)
                value = evaluator.value(heuristic, successor)
                if value is None:
                    continue
                path = prefix + (number,)
                if value < current_h:
                    plan += path
                    current, current_h, improved = successor, value, True
                    break
                queue.append((successor, path))
        if not improved:
            return result("stuck", expanded, generated)
    return result("solved", expanded, generated, plan)


def run(problem, start, algorithm, heuristic, budget, weight, evaluator):
    if algorithm == "ehc":
        return hill_climbing(problem, start, heuristic, budget, evaluator)
    return best_first(problem, start, algorithm, heuristic, budget, weight, evaluator)
