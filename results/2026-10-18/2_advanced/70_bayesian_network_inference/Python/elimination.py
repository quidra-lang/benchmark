"""Interaction graphs, ordered elimination plans and max-product traceback."""

from collections import namedtuple
from itertools import combinations

from factors import entry_count, multiply


Step = namedtuple("Step", "variable fill scope size")
Plan = namedtuple("Plan", "steps maximum total")


def interaction_graph(factors):
    graph = {}
    for factor in factors:
        for variable in factor.variables:
            graph.setdefault(variable, set())
        for left, right in combinations(factor.variables, 2):
            graph[left].add(right)
            graph[right].add(left)
    return graph


def make_plan(factors, eliminate, method, given_order, sizes):
    graph = interaction_graph(factors)
    remaining, steps = set(eliminate), []
    order = {variable: rank for rank, variable in enumerate(given_order)}
    while remaining:
        fills = {variable: sum(right not in graph[left] for left, right in combinations(sorted(graph[variable]), 2))
                 for variable in remaining}
        if method == "MINFILL":
            variable = min(remaining, key=lambda item: (fills[item], len(graph[item]), item))
        else:
            variable = min(remaining, key=lambda item: order[item])
        neighbors = graph[variable]
        scope = tuple(sorted(neighbors | {variable}))
        steps.append(Step(variable, fills[variable], scope, entry_count(scope, sizes)))
        for left, right in combinations(sorted(neighbors), 2):
            graph[left].add(right)
            graph[right].add(left)
        for neighbor in neighbors:
            graph[neighbor].remove(variable)
        del graph[variable]
        remaining.remove(variable)
    return Plan(steps, max((step.size for step in steps), default=0), sum(step.size for step in steps))


def execute(initial, plan, sizes, maximize=False):
    factors, products = list(initial), []
    for step in plan.steps:
        selected = [factor for factor in factors if step.variable in factor.variables]
        factors = [factor for factor in factors if step.variable not in factor.variables]
        product = multiply(selected, sizes)
        factors.append(product.eliminate(step.variable, maximize))
        if maximize:
            products.append((step.variable, product))
    return multiply(factors, sizes), products


def traceback(products, sizes):
    assignment = {}
    for variable, product in reversed(products):
        state = max(range(sizes[variable]), key=lambda value: product.value(assignment | {variable: value}))
        assignment[variable] = state
    return assignment
