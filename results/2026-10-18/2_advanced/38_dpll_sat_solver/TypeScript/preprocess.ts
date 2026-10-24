import type { Formula } from './cnf_io.ts';

interface Clause {
  number: number;
  literals: number[];
}
export function preprocess(formula: Formula, usePure: boolean) {
  const fixed: (boolean | null)[] = Array(formula.variables + 1).fill(null);
  const statistics = {
    tautologies: 0,
    duplicateLiterals: 0,
    unitFixed: 0,
    unitRemoved: 0,
    subsumed: 0,
    pureFixed: 0,
    pureRemoved: 0,
  };
  const records: Record<'tautology' | 'unit' | 'subsumed' | 'pure', number[]> = {
    tautology: [],
    unit: [],
    subsumed: [],
    pure: [],
  };
  let working: Clause[] = [];
  let emptyClause: number | null = null;
  formula.clauses.forEach((literals, i) => {
    const unique = new Set(literals);
    if (literals.some((literal) => unique.has(-literal))) {
      statistics.tautologies++;
      records.tautology.push(i + 1);
    } else {
      statistics.duplicateLiterals += literals.length - unique.size;
      working.push({ number: i + 1, literals: [...unique] });
    }
  });
  for (;;) {
    const empty = working.find((clause) => clause.literals.length === 0);
    if (empty !== undefined) {
      emptyClause = empty.number;
      break;
    }
    const unit = working.find((clause) => clause.literals.length === 1);
    if (unit === undefined) break;
    const literal = unit.literals[0];
    fixed[Math.abs(literal)] = literal > 0;
    statistics.unitFixed++;
    const remaining: Clause[] = [];
    for (const clause of working) {
      if (clause.literals.includes(literal)) {
        statistics.unitRemoved++;
        records.unit.push(clause.number);
      } else {
        remaining.push({
          number: clause.number,
          literals: clause.literals.filter((value) => value !== -literal),
        });
      }
    }
    working = remaining;
  }
  if (emptyClause === null) {
    const sets = working.map((clause) => new Set(clause.literals));
    const removed = working.map((clause, i) =>
      working.some(
        (candidate, j) =>
          j !== i &&
          (candidate.literals.length < clause.literals.length || j < i) &&
          candidate.literals.every((literal) => sets[i].has(literal)),
      ),
    );
    working = working.filter((clause, i) => {
      if (!removed[i]) return true;
      statistics.subsumed++;
      records.subsumed.push(clause.number);
      return false;
    });
    if (usePure) {
      for (;;) {
        const present = new Set(working.flatMap((clause) => clause.literals));
        const pure = new Set([...present].filter((literal) => !present.has(-literal)));
        if (pure.size === 0) break;
        for (const literal of pure) fixed[Math.abs(literal)] = literal > 0;
        statistics.pureFixed += pure.size;
        working = working.filter((clause) => {
          if (!clause.literals.some((literal) => pure.has(literal))) return true;
          statistics.pureRemoved++;
          records.pure.push(clause.number);
          return false;
        });
      }
    }
  }
  const active: number[] = [];
  const fixedLiterals: number[] = [];
  for (let x = 1; x <= formula.variables; x++) {
    if (fixed[x] === null) active.push(x);
    else fixedLiterals.push(fixed[x] ? x : -x);
  }
  for (const numbers of Object.values(records)) numbers.sort((a, b) => a - b);
  const removed =
    statistics.tautologies + statistics.unitRemoved + statistics.subsumed + statistics.pureRemoved;
  return {
    pure: usePure,
    fixed,
    fixedLiterals,
    active,
    clauses: working.map((clause) => clause.literals),
    statistics,
    records,
    removed,
    emptyClause,
  };
}
