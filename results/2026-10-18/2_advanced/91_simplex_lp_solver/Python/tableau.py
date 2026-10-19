"""An exact tableau with unchanged row and column numbering."""

from rational import Fraction


class Tableau:
    def __init__(self, row_names, column_names, matrix, rhs, initial):
        self.row_names = row_names
        self.column_names = column_names
        self.values = [row.copy() for row in matrix]
        self.rhs = rhs.copy()
        self.basic = initial.copy()

    def pivot(self, row, column):
        divisor = self.values[row][column]
        self.values[row] = [value / divisor for value in self.values[row]]
        self.rhs[row] /= divisor
        for other in range(len(self.values)):
            if other == row:
                continue
            factor = self.values[other][column]
            self.values[other] = [value - factor * pivot_value
                                  for value, pivot_value in zip(self.values[other], self.values[row])]
            self.rhs[other] -= factor * self.rhs[row]
        self.basic[row] = column

    def reduced(self, costs):
        return [cost - sum((costs[basic] * row[column]
                            for basic, row in zip(self.basic, self.values)), Fraction(0))
                for column, cost in enumerate(costs)]

    def phase_value(self, costs):
        return sum((costs[basic] * value for basic, value in zip(self.basic, self.rhs)), Fraction(0))

    def display(self, heading, costs, objective):
        lines = [f"TABLEAU {heading}", "COLUMNS " + " ".join(self.column_names)]
        for name, basic, row, rhs in zip(self.row_names, self.basic, self.values, self.rhs):
            coefficients = " ".join(map(str, row))
            lines.append(f"ROW {name} {self.column_names[basic]} {coefficients} | {rhs}")
        reduced = " ".join(map(str, self.reduced(costs)))
        lines.append(f"COST {reduced} | {objective(self.phase_value(costs))}")
        return lines
