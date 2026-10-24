'use strict';

const {notation} = require('./pddl_parser');
const {mask} = require('./search');

function subtype(type, expected, parents) {
  for (let current = type; current !== null; current = parents.get(current)) if (current === expected) return true;
  return false;
}

function classifyPredicates(domain) {
  const fluent = new Set();
  for (const action of domain.actions) for (const literal of action.effects) fluent.add(literal.atom.predicate);
  domain.fluent = fluent;
  domain.static = new Set(domain.predicates.filter(predicate => !fluent.has(predicate.name)).map(predicate => predicate.name));
}

function substitute(atom, assignment) {
  return {predicate: atom.predicate, terms: atom.terms.map(term => assignment.get(term))};
}

function ground(domain, problem) {
  const objectsByType = new Map(domain.types.map(type =>
    [type, problem.objects.filter(object => subtype(object.type, type, domain.parents))]));
  const initialAtoms = new Set(problem.init.map(notation));
  const registry = new Map();
  const register = atom => {
    const key = notation(atom);
    registry.set(key, atom);
    return key;
  };
  for (const atom of problem.init) register(atom);
  const candidates = [];
  const schemas = [];
  for (const source of domain.actions) {
    const choices = source.parameters.map(parameter => objectsByType.get(parameter.type));
    let assignments = 1;
    for (const choice of choices) assignments *= choice.length;
    const counts = {source, assignments, candidates: 0, reachable: 0};
    schemas.push(counts);
    const assigned = [];
    function enumerate(index) {
      if (index < choices.length) {
        for (const object of choices[index]) {
          assigned.push(object.name);
          enumerate(index + 1);
          assigned.pop();
        }
        return;
      }
      const assignment = new Map(source.parameters.map((parameter, number) => [parameter.name, assigned[number]]));
      const conditions = source.conditions.map(literal => ({negative: literal.negative, atom: substitute(literal.atom, assignment)}));
      for (const literal of conditions) {
        const atom = literal.atom;
        if (atom.predicate !== '=' && !domain.static.has(atom.predicate)) continue;
        const truth = atom.predicate === '=' ? atom.terms[0] === atom.terms[1] : initialAtoms.has(notation(atom));
        if (truth === literal.negative) return;
      }
      const pre = new Set();
      const neg = new Set();
      for (const literal of conditions) {
        if (domain.fluent.has(literal.atom.predicate)) (literal.negative ? neg : pre).add(register(literal.atom));
      }
      const add = new Set(source.adds.map(atom => register(substitute(atom, assignment))));
      const del = new Set(source.deletes.map(atom => register(substitute(atom, assignment))));
      for (const key of add) del.delete(key);
      candidates.push({source, arguments: assigned.slice(), cost: source.cost, pre, neg, add, del, counts, reachable: false});
      counts.candidates++;
    }
    enumerate(0);
  }
  const reachable = new Set(problem.init.filter(atom => domain.fluent.has(atom.predicate)).map(notation));
  let changed = true;
  while (changed) {
    changed = false;
    for (const candidate of candidates) {
      if (candidate.reachable || ![...candidate.pre].every(key => reachable.has(key))) continue;
      candidate.reachable = true;
      candidate.counts.reachable++;
      for (const key of candidate.add) reachable.add(key);
      changed = true;
    }
  }
  const facts = [...reachable].map(key => ({...registry.get(key), notation: key}));
  facts.sort((a, b) => {
    const predicate = domain.predicateTable.get(a.predicate).number - domain.predicateTable.get(b.predicate).number;
    if (predicate !== 0) return predicate;
    for (let index = 0; index < a.terms.length; index++) {
      const difference = problem.objectNumbers.get(a.terms[index]) - problem.objectNumbers.get(b.terms[index]);
      if (difference !== 0) return difference;
    }
    return 0;
  });
  const factNumbers = new Map(facts.map((fact, number) => [fact.notation, number]));
  const actions = [];
  for (const candidate of candidates) {
    if (!candidate.reachable) continue;
    const action = {number: actions.length, name: candidate.source.name, source: candidate.source,
      arguments: candidate.arguments, cost: candidate.cost,
      notation: notation({predicate: candidate.source.name, terms: candidate.arguments})};
    for (const field of ['pre', 'neg', 'add', 'del']) {
      const numbers = [...candidate[field]].filter(key => factNumbers.has(key)).map(key => factNumbers.get(key)).sort((a, b) => a - b);
      action[field + 'Facts'] = numbers;
      action[field] = mask(numbers);
    }
    actions.push(action);
  }
  const initialFacts = problem.init.filter(atom => domain.fluent.has(atom.predicate)).map(atom => factNumbers.get(notation(atom)));
  const goals = new Set();
  const unreachable = [];
  for (const atom of problem.goals) {
    const key = notation(atom);
    if (factNumbers.has(key)) goals.add(factNumbers.get(key));
    else if (!domain.static.has(atom.predicate) || !initialAtoms.has(key)) unreachable.push(atom);
  }
  const goalFacts = [...goals].sort((a, b) => a - b);
  return {facts, factNumbers, actions, schemas, candidateCount: candidates.length, objectsByType, unreachable,
    initial: mask(initialFacts), goal: mask(goalFacts), goalFacts,
    staticCount: problem.init.filter(atom => domain.static.has(atom.predicate)).length,
    actionTable: new Map(actions.map(action => [action.notation, action]))};
}

module.exports = {subtype, classifyPredicates, substitute, ground};
