"""One simplex phase with Bland's entering and leaving rules."""

from types import SimpleNamespace


def run_phase(tableau, costs, candidates, objective):
    iterations = 0
    lines = []
    candidates = sorted(candidates)
    while True:
        reduced = tableau.reduced(costs)
        entering = next((column for column in candidates if reduced[column] < 0), None)
        if entering is None:
            return SimpleNamespace(iterations=iterations, unbounded=None, lines=lines)
        ratios = [(tableau.rhs[row] / values[entering], tableau.basic[row], row)
                  for row, values in enumerate(tableau.values) if values[entering] > 0]
        if not ratios:
            return SimpleNamespace(iterations=iterations, unbounded=entering, lines=lines)
        ratio, leaving, row = min(ratios)
        before = reduced[entering]
        tableau.pivot(row, entering)
        iterations += 1
        value = objective(tableau.phase_value(costs))
        lines.append(f"PIVOT {iterations} enter {tableau.column_names[entering]} reduced {before} "
                     f"leave {tableau.column_names[leaving]} row {tableau.row_names[row]} "
                     f"ratio {ratio} objective {value}")
