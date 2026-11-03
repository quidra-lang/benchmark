"""Canonical dense factors and sequential sum/product operations."""

from itertools import product as cartesian_product

from learning import parent_row, total


def entry_count(variables, sizes):
    result = 1
    for variable in variables:
        result *= sizes[variable]
    return result


def assignments(variables, sizes):
    variables = tuple(variables)
    for states in cartesian_product(*(range(sizes[variable]) for variable in variables)):
        yield dict(zip(variables, states))


class Factor:
    def __init__(self, variables, values, sizes):
        self.variables = tuple(variables)
        self.values = list(values)
        self.sizes = sizes

    def value(self, assignment):
        index = 0
        for variable in self.variables:
            index = index * self.sizes[variable] + assignment[variable]
        return self.values[index]

    def reduced(self, evidence):
        variables = tuple(variable for variable in self.variables if variable not in evidence)
        values = [self.value(assignment | evidence) for assignment in assignments(variables, self.sizes)]
        return Factor(variables, values, self.sizes)

    def multiplied(self, other):
        variables = tuple(sorted(set(self.variables) | set(other.variables)))
        values = [self.value(assignment) * other.value(assignment)
                  for assignment in assignments(variables, self.sizes)]
        return Factor(variables, values, self.sizes)

    def eliminate(self, variable, maximize=False):
        variables = tuple(item for item in self.variables if item != variable)
        values = []
        for assignment in assignments(variables, self.sizes):
            candidates = [self.value(assignment | {variable: state}) for state in range(self.sizes[variable])]
            values.append(max(candidates) if maximize else total(candidates))
        return Factor(variables, values, self.sizes)


def cpt_factor(variable, parents, cpt, sizes):
    variables = tuple(sorted([variable] + list(parents)))
    values = [cpt[parent_row(parents, assignment, sizes)][assignment[variable]]
              for assignment in assignments(variables, sizes)]
    return Factor(variables, values, sizes)


def multiply(factors, sizes):
    if not factors:
        return Factor((), [1.0], sizes)
    result = factors[0]
    for factor in factors[1:]:
        result = result.multiplied(factor)
    return result
