"""Depth-first integer search, preserving the specified node order."""

from dataclasses import dataclass
from types import SimpleNamespace

from rational import Fraction, ceil, floor


@dataclass
class Node:
    lower: list
    upper: list
    depth: int
    parent: object
    branch: str
    parent_value: object


def search(model, limit, solve):
    stack = [Node(model.lower.copy(), model.upper.copy(), 0, None, "root", None)]
    solves = []
    lines = []
    incumbent = None
    objective = None
    incumbents = pruned = infeasible = 0
    status = None
    while stack:
        if len(solves) == limit:
            status = "NODE_LIMIT"
            break
        node = stack.pop()
        number = len(solves) + 1
        result = solve(node.lower, node.upper, number)
        solves.append(result)
        if result.status == "INFEASIBLE":
            outcome = "infeasible"
            infeasible += 1
        elif result.status == "UNBOUNDED":
            outcome = "unbounded"
            status = "UNBOUNDED"
        elif objective is not None and ((model.direction == "maximize" and result.objective <= objective)
                                        or (model.direction == "minimize" and result.objective >= objective)):
            outcome = "pruned"
            pruned += 1
        else:
            fractional = next((j for j, integer in enumerate(model.integer)
                               if integer and result.solution[j].denominator != 1), None)
            if fractional is None:
                incumbent = result.solution.copy()
                objective = result.objective
                outcome = "incumbent"
                incumbents += 1
            else:
                value = result.solution[fractional]
                name = model.variables[fractional]
                down, up = floor(value), ceil(value)
                lower = node.lower.copy()
                lower[fractional] = Fraction(up)
                upper = node.upper.copy()
                upper[fractional] = Fraction(down)
                stack.append(Node(lower, node.upper.copy(), node.depth + 1, number,
                                  f"{name}>={up}", result.objective))
                stack.append(Node(node.lower.copy(), upper, node.depth + 1, number,
                                  f"{name}<={down}", result.objective))
                outcome = f"branch {name} {value}"
        parent = "-" if node.parent is None else str(node.parent)
        lp = str(result.objective) if result.status == "OPTIMAL" else result.status.lower()
        lines.append(f"NODE {number} depth {node.depth} parent {parent} branch {node.branch} "
                     f"lp {lp} pivots {result.pivots} action {outcome}")
        if status == "UNBOUNDED":
            break
    if status is None:
        status = "OPTIMAL" if incumbent is not None else "INFEASIBLE"
    if status == "NODE_LIMIT":
        for node in reversed(stack):
            lines.append(f"OPEN parent {node.parent} branch {node.branch} bound {node.parent_value}")
        bounds = [node.parent_value for node in stack]
        if objective is not None:
            bounds.append(objective)
        bound = max(bounds) if model.direction == "maximize" else min(bounds)
    else:
        bound = objective
    shown_objective = "-" if objective is None else str(objective)
    shown_bound = "-" if bound is None else str(bound)
    lines.append(f"RESULT {status} objective {shown_objective} nodes {len(solves)} "
                 f"incumbents {incumbents} pruned {pruned} infeasible {infeasible} "
                 f"open {len(stack)} bound {shown_bound}")
    return SimpleNamespace(status=status, objective=objective, solution=incumbent,
                           solves=solves, root=solves[0], lines=lines, nodes=len(solves))
