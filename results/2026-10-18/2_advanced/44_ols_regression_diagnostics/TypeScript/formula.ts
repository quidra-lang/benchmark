import { numberValue, type DataRow } from './dataframe.ts';

export type Factor = { name: string; column: string; kind: 'numeric' } | { name: string; column: string; kind: 'categorical' } | { name: string; column: string; kind: 'power'; power: number };
export interface Term { name: string; factors: Factor[] }
export interface Model { formula: string; response: string; weight?: string; terms: Term[] }
export interface Component { name: string; factor: Factor; level?: string }
export interface DesignColumn { name: string; term?: number; components: Component[] }
export function parseFormula(line: string): Model {
  const [formula, weight] = line.split(' weights='), [response, rhs] = formula.split(' ~ '), terms: Term[] = [];
  const factor = (name: string): Factor => {
    if (name.startsWith('C(')) return { name, column: name.slice(2, -1), kind: 'categorical' };
    if (name.startsWith('I(')) { const [column, power] = name.slice(2, -1).split('^'); return { name, column, kind: 'power', power: +power }; }
    return { name, column: name, kind: 'numeric' };
  };
  const seen = new Set<string>();
  const append = (factors: Factor[]) => {
    const key = factors.map(f => f.name).sort().join('|');
    if (!seen.has(key)) { seen.add(key); terms.push({ name: factors.map(f => f.name).join(':'), factors }); }
  };
  for (const expression of rhs.split(' + ')) {
    if (!expression.includes('*')) append(expression.split(':').map(factor));
    else {
      const factors = expression.split('*').map(factor);
      const subsets = (size: number, start: number, chosen: Factor[]): void => {
        if (chosen.length === size) { append(chosen); return; }
        for (let i = start; i < factors.length; i++) subsets(size, i + 1, [...chosen, factors[i]]);
      };
      for (let size = 1; size <= factors.length; size++) subsets(size, 0, []);
    }
  }
  return { formula, response, weight, terms };
}
export const contained = (a: Term, b: Term) => a.factors.length < b.factors.length && a.factors.every(f => b.factors.some(g => f.name === g.name));
export const factorColumns = (model: Model) => [...new Set(model.terms.flatMap(term => term.factors.map(f => f.column)))];
export function variables(model: Model): string[] { return [...new Set([...factorColumns(model), model.response, ...(model.weight ? [model.weight] : [])])]; }
export function findLevels(model: Model, rows: DataRow[]): Map<string, string[]> {
  const levels = new Map<string, string[]>();
  for (const term of model.terms) for (const factor of term.factors) if (factor.kind === 'categorical' && !levels.has(factor.column)) {
    levels.set(factor.column, [...new Set(rows.map(row => row.values[factor.column]).filter((value): value is string => typeof value === 'string'))].sort());
  }
  return levels;
}
export function designColumns(model: Model, levels: Map<string, string[]>): DesignColumn[] {
  const columns: DesignColumn[] = [{ name: '(Intercept)', components: [] }];
  model.terms.forEach((term, t) => {
    let tuples: Component[][] = [[]];
    for (const factor of term.factors) {
      const components: Component[] = factor.kind === 'categorical' ? levels.get(factor.column)!.slice(1).map(level => ({ name: factor.name + level, factor, level })) : [{ name: factor.name, factor }];
      tuples = components.flatMap(component => tuples.map(tuple => [...tuple, component]));
    }
    for (const components of tuples) columns.push({ name: components.map(c => c.name).join(':'), term: t, components });
  });
  return columns;
}
export function columnValue(column: DesignColumn, row: DataRow): number {
  const componentValue = (component: Component): number => {
    const factor = component.factor;
    if (factor.kind === 'categorical') return row.values[factor.column] === component.level ? 1 : 0;
    const value = numberValue(row, factor.column);
    return factor.kind === 'numeric' ? value : factor.power === 2 ? value * value : value * value * value;
  };
  if (!column.components.length) return 1;
  let value = componentValue(column.components[0]);
  for (const component of column.components.slice(1)) value = value * componentValue(component);
  return value;
}
export function predictable(model: Model, levels: Map<string, string[]>, row: DataRow): boolean {
  return factorColumns(model).every(column => {
    const value = row.values[column];
    return value !== null && value !== undefined && (!levels.has(column) || (typeof value === 'string' && levels.get(column)!.includes(value)));
  });
}
export const formulaText = (model: Model, terms: number[]) => model.response + ' ~ ' + (terms.map(t => model.terms[t].name).join(' + ') || '1');
