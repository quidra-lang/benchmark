'use strict';

function preprocess(formula, usePure) {
    const fixed = Array(formula.variables + 1).fill(null);
    const statistics = { tautologies: 0, duplicateLiterals: 0, unitFixed: 0, unitRemoved: 0,
        subsumed: 0, pureFixed: 0, pureRemoved: 0 };
    const records = { tautology: [], unit: [], subsumed: [], pure: [] };
    let working = [];
    let emptyClause = null;
    formula.clauses.forEach((literals, index) => {
        const unique = new Set(literals);
        if (literals.some(literal => unique.has(-literal))) {
            statistics.tautologies++;
            records.tautology.push(index + 1);
        } else {
            statistics.duplicateLiterals += literals.length - unique.size;
            working.push({ number: index + 1, literals: [...unique] });
        }
    });

    while (true) {
        const empty = working.find(clause => clause.literals.length === 0);
        if (empty !== undefined) {
            emptyClause = empty.number;
            break;
        }
        const unit = working.find(clause => clause.literals.length === 1);
        if (unit === undefined) break;
        const literal = unit.literals[0];
        fixed[Math.abs(literal)] = literal > 0;
        statistics.unitFixed++;
        const remaining = [];
        for (const clause of working) {
            if (clause.literals.includes(literal)) {
                statistics.unitRemoved++;
                records.unit.push(clause.number);
            } else {
                remaining.push({ number: clause.number, literals: clause.literals.filter(value => value !== -literal) });
            }
        }
        working = remaining;
    }

    if (emptyClause === null) {
        const sets = working.map(clause => new Set(clause.literals));
        const removed = working.map((clause, index) => working.some((candidate, other) => {
            if (other === index || candidate.literals.length > clause.literals.length) return false;
            if (candidate.literals.length === clause.literals.length && other > index) return false;
            return candidate.literals.every(literal => sets[index].has(literal));
        }));
        working = working.filter((clause, index) => {
            if (!removed[index]) return true;
            statistics.subsumed++;
            records.subsumed.push(clause.number);
            return false;
        });

        if (usePure) {
            while (true) {
                const present = new Set();
                for (const clause of working) for (const literal of clause.literals) present.add(literal);
                const pure = new Set([...present].filter(literal => !present.has(-literal)));
                if (pure.size === 0) break;
                for (const literal of pure) fixed[Math.abs(literal)] = literal > 0;
                statistics.pureFixed += pure.size;
                working = working.filter(clause => {
                    if (!clause.literals.some(literal => pure.has(literal))) return true;
                    statistics.pureRemoved++;
                    records.pure.push(clause.number);
                    return false;
                });
            }
        }
    }
    const active = [];
    const fixedLiterals = [];
    for (let variable = 1; variable <= formula.variables; variable++) {
        if (fixed[variable] === null) active.push(variable);
        else fixedLiterals.push(fixed[variable] ? variable : -variable);
    }
    for (const numbers of Object.values(records)) numbers.sort((first, second) => first - second);
    const removed = statistics.tautologies + statistics.unitRemoved + statistics.subsumed + statistics.pureRemoved;
    return { pure: usePure, fixed, fixedLiterals, active, clauses: working.map(clause => clause.literals),
        statistics, records, removed, emptyClause };
}

module.exports = { preprocess };
