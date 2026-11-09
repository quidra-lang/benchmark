'use strict';

function phase(tableau, costs, candidates, objective) {
  const lines = [];
  let iterations = 0;
  while (true) {
    const reduced = tableau.reduced(costs);
    const entering = candidates.find(column => reduced.costs[column].n < 0n);
    if (entering === undefined) return {status: 'optimal', iterations, lines, entering: null};
    let leaving = null;
    let ratio = null;
    for (let row = 0; row < tableau.T.length; row++) {
      if (tableau.T[row][entering].n <= 0n) continue;
      const proposed = tableau.beta[row].divide(tableau.T[row][entering]);
      if (leaving === null || proposed.compare(ratio) < 0 ||
          (proposed.compare(ratio) === 0 && tableau.basis[row] < tableau.basis[leaving])) {
        leaving = row;
        ratio = proposed;
      }
    }
    if (leaving === null) return {status: 'unbounded', iterations, lines, entering};
    const enteringName = tableau.form.columns[entering].name;
    const leavingName = tableau.form.columns[tableau.basis[leaving]].name;
    const rowName = tableau.form.rows[leaving].name;
    tableau.pivot(leaving, entering);
    iterations++;
    const value = objective(tableau.reduced(costs).value);
    lines.push(`PIVOT ${iterations} enter ${enteringName} reduced ${reduced.costs[entering]} ` +
      `leave ${leavingName} row ${rowName} ratio ${ratio} objective ${value}`);
  }
}

module.exports = {phase};
