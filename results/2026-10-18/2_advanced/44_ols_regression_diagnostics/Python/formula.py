"""Expand formulas and construct consistently ordered model columns."""

from itertools import combinations, product


class Factor:
    def __init__(self, name):
        self.name = name
        self.power = 1
        self.categorical = name.startswith("C(")
        if self.categorical:
            self.column = name[2:-1]
        elif name.startswith("I("):
            self.column, power = name[2:-1].split("^")
            self.power = int(power)
        else:
            self.column = name

    def components(self, levels):
        if self.categorical:
            return [(self, self.name + level, level)
                    for level in levels[self.column][1:]]
        return [(self, self.name, None)]

    def value(self, row, level):
        value = row[self.column]
        if self.categorical:
            return 1.0 if value == level else 0.0
        if self.power == 2:
            return value * value
        if self.power == 3:
            return value * value * value
        return value


class Term:
    def __init__(self, factors):
        self.factors = tuple(factors)
        self.name = ":".join(factor.name for factor in factors)
        self.factor_names = frozenset(factor.name for factor in factors)

    def contained_in(self, other):
        return self.factor_names < other.factor_names


class Model:
    def __init__(self, line):
        self.original, separator, weight = line.partition(" weights=")
        self.weight = weight if separator else None
        self.response, expressions = self.original.split(" ~ ")
        self.terms = []
        seen = set()
        for expression in expressions.split(" + "):
            if "*" in expression:
                factors = [Factor(name) for name in expression.split("*")]
                expanded = [subset for size in range(1, len(factors) + 1)
                            for subset in combinations(factors, size)]
            else:
                expanded = [tuple(Factor(name)
                                  for name in expression.split(":"))]
            for factors in expanded:
                term = Term(factors)
                if term.factor_names not in seen:
                    seen.add(term.factor_names)
                    self.terms.append(term)
        self.factor_columns = list(dict.fromkeys(
            factor.column for term in self.terms for factor in term.factors
        ))
        self.categorical_columns = list(dict.fromkeys(
            factor.column for term in self.terms for factor in term.factors
            if factor.categorical
        ))
        self.variables = set(self.factor_columns)
        self.variables.add(self.response)
        if self.weight is not None:
            self.variables.add(self.weight)

    def format(self, term_indices):
        names = [self.terms[index].name for index in sorted(term_indices)]
        return self.response + " ~ " + (" + ".join(names) if names else "1")

    def removable(self, term_indices):
        return [index for index in term_indices
                if not any(self.terms[index].contained_in(self.terms[other])
                           for other in term_indices)]

    def candidates(self, term_indices):
        selected = set(term_indices)
        return [index for index, term in enumerate(self.terms)
                if index not in selected
                and all(other in selected
                        for other, smaller in enumerate(self.terms)
                        if smaller.contained_in(term))]

    def hierarchical(self, term_indices):
        selected = set(term_indices)
        return all(other in selected
                   for index in term_indices
                   for other, term in enumerate(self.terms)
                   if term.contained_in(self.terms[index]))


class DesignColumn:
    def __init__(self, term_index, components):
        self.term_index = term_index
        self.components = tuple(components)
        self.name = (":".join(component[1] for component in components)
                     if components else "(Intercept)")

    def value(self, row):
        if not self.components:
            return 1.0
        factor, _, level = self.components[0]
        value = factor.value(row, level)
        for factor, _, level in self.components[1:]:
            value = value * factor.value(row, level)
        return value


class Design:
    def __init__(self, model, data):
        self.model = model
        used = [(number, row) for number, row in enumerate(data.rows, 1)
                if all(row[column] is not None for column in model.variables)]
        self.row_numbers = [number for number, row in used]
        self.rows = [row for number, row in used]
        self.levels = {
            column: sorted({row[column] for row in self.rows})
            for column in model.categorical_columns
        }
        self.columns = [DesignColumn(None, ())]
        for index, term in enumerate(model.terms):
            components = [factor.components(self.levels)
                          for factor in term.factors]
            # itertools.product changes its last coordinate fastest.
            for choices in product(*reversed(components)):
                self.columns.append(DesignColumn(index, tuple(reversed(choices))))
        self.matrix = [self.values(row) for row in self.rows]
        self.response = [row[model.response] for row in self.rows]
        self.weights = ([row[model.weight] for row in self.rows]
                        if model.weight is not None else [1.0] * len(self.rows))

    def values(self, row):
        return [column.value(row) for column in self.columns]

    def subset_matrix(self, term_indices):
        selected = set(term_indices)
        indices = [j for j, column in enumerate(self.columns)
                   if column.term_index is None or column.term_index in selected]
        return [[row[j] for j in indices] for row in self.matrix]

    def predictable(self, row):
        for column in self.model.factor_columns:
            value = row[column]
            if value is None:
                return False
            if column in self.levels and value not in self.levels[column]:
                return False
        return True
