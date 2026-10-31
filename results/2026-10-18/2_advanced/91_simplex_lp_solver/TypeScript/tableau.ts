import { zero } from './rational.ts';
import type { Rational } from './rational.ts';
import type { StandardForm } from './types.ts';

export class Tableau {
  form: StandardForm;
  T: Rational[][];
  beta: Rational[];
  basis: number[];
  constructor(form: StandardForm) {
    this.form = form;
    this.T = form.rows.map(row => row.values.slice());
    this.beta = form.rows.map(row => row.rhs);
    this.basis = form.rows.map(row => row.initial);
  }

  reduced(costs: Rational[]): {costs: Rational[]; value: Rational} {
    const reduced = costs.slice();
    let value = zero;
    for (let row = 0; row < this.T.length; row++) {
      const basicCost = costs[this.basis[row]];
      value = value.add(basicCost.multiply(this.beta[row]));
      for (let column = 0; column < reduced.length; column++) {
        reduced[column] = reduced[column].subtract(basicCost.multiply(this.T[row][column]));
      }
    }
    return {costs: reduced, value};
  }

  pivot(row: number, column: number): void {
    const divisor = this.T[row][column];
    this.T[row] = this.T[row].map(value => value.divide(divisor));
    this.beta[row] = this.beta[row].divide(divisor);
    for (let other = 0; other < this.T.length; other++) {
      if (other === row) continue;
      const factor = this.T[other][column];
      this.T[other] = this.T[other].map((value, index) => value.subtract(factor.multiply(this.T[row][index])));
      this.beta[other] = this.beta[other].subtract(factor.multiply(this.beta[row]));
    }
    this.basis[row] = column;
  }

  solution(): Rational[] {
    const values = this.form.columns.map(() => zero);
    for (let row = 0; row < this.basis.length; row++) values[this.basis[row]] = this.beta[row];
    return values;
  }

  display(heading: string, costs: Rational[], objective: (value: Rational) => Rational): string[] {
    const columns = this.form.columns;
    const lines = [`TABLEAU ${heading}`, 'COLUMNS ' + columns.map(column => column.name).join(' ')];
    for (let row = 0; row < this.T.length; row++) {
      lines.push(`ROW ${this.form.rows[row].name} ${columns[this.basis[row]].name} ${this.T[row].join(' ')} | ${this.beta[row]}`);
    }
    const reduced = this.reduced(costs);
    lines.push(`COST ${reduced.costs.join(' ')} | ${objective(reduced.value)}`);
    return lines;
  }
}

