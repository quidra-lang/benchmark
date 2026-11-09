import {notation} from './pddl_parser.ts';
import {mask} from './search.ts';
import type {
  Domain, Problem, Atom, Literal, CandidateGrounded, SchemaStats,
  GroundedFact, GroundedModel, GroundedAction, ProblemObject
} from './types.ts';

export function subtype(type:string,expected:string,parents:Map<string,string|null>):boolean {
  for (let current = type; current !== null; current = parents.get(current)!) if (current === expected) return true;
  return false;
}

export function classifyPredicates(domain:Domain):void {
  const fluent = new Set<string>();
  for (const action of domain.actions) for (const literal of action.effects) fluent.add(literal.atom.predicate);
  domain.fluent = fluent;
  domain.static = new Set(domain.predicates.filter(predicate => !fluent.has(predicate.name)).map(predicate => predicate.name));
}

export function substitute(atom:Atom,assignment:Map<string,string>):Atom {
  return {predicate: atom.predicate, terms: atom.terms.map(term => assignment.get(term)!)};
}

export function ground(domain:Domain,problem:Problem):GroundedModel {
  const objectsByType = new Map<string,ProblemObject[]>(domain.types.map(type =>
    [type, problem.objects.filter(object => subtype(object.type, type, domain.parents))]));
  const initialAtoms = new Set<string>(problem.init.map(notation));
  const registry = new Map<string,Atom>();
  const register = (atom:Atom):string => {
    const key = notation(atom);
    registry.set(key, atom);
    return key;
  };
  for (const atom of problem.init) register(atom);
  const candidates:CandidateGrounded[] = [];
  const schemas:SchemaStats[] = [];
  for (const source of domain.actions) {
    const choices = source.parameters.map(parameter => objectsByType.get(parameter.type)!);
    let assignments = 1;
    for (const choice of choices) assignments *= choice.length;
    const counts = {source, assignments, candidates: 0, reachable: 0};
    schemas.push(counts);
    const assigned:string[] = [];
    function enumerate(index:number):void {
      if (index < choices.length) {
        for (const object of choices[index]) {
          assigned.push(object.name);
          enumerate(index + 1);
          assigned.pop();
        }
        return;
      }
      const assignment = new Map<string,string>(source.parameters.map((parameter, number) => [parameter.name, assigned[number]]));
      const conditions = source.conditions.map(literal => ({negative: literal.negative, atom: substitute(literal.atom, assignment)}));
      for (const literal of conditions) {
        const atom = literal.atom;
        if (atom.predicate !== '=' && !domain.static.has(atom.predicate)) continue;
        const truth = atom.predicate === '=' ? atom.terms[0] === atom.terms[1] : initialAtoms.has(notation(atom));
        if (truth === literal.negative) return;
      }
      const pre = new Set<string>();
      const neg = new Set<string>();
      for (const literal of conditions) {
        if (domain.fluent.has(literal.atom.predicate)) (literal.negative ? neg : pre).add(register(literal.atom));
      }
      const add = new Set<string>(source.adds.map(atom => register(substitute(atom, assignment))));
      const del = new Set<string>(source.deletes.map(atom => register(substitute(atom, assignment))));
      for (const key of add) del.delete(key);
      candidates.push({source, arguments: assigned.slice(), cost: source.cost, pre, neg, add, del, counts, reachable: false});
      counts.candidates++;
    }
    enumerate(0);
  }
  const reachable = new Set<string>(problem.init.filter(atom => domain.fluent.has(atom.predicate)).map(notation));
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
  const facts = [...reachable].map(key => ({...registry.get(key)!, notation: key}));
  facts.sort((a, b) => {
    const predicate = domain.predicateTable.get(a.predicate)!.number - domain.predicateTable.get(b.predicate)!.number;
    if (predicate !== 0) return predicate;
    for (let index = 0; index < a.terms.length; index++) {
      const difference = problem.objectNumbers.get(a.terms[index])! - problem.objectNumbers.get(b.terms[index])!;
      if (difference !== 0) return difference;
    }
    return 0;
  });
  const factNumbers = new Map<string,number>(facts.map((fact, number) => [fact.notation, number]));
  const actions:GroundedAction[] = [];
  for (const candidate of candidates) {
    if (!candidate.reachable) continue;
    const factIds = (keys:Set<string>):number[] => [...keys].filter(key => factNumbers.has(key))
      .map(key => factNumbers.get(key)!).sort((a,b)=>a-b);
    const preFacts=factIds(candidate.pre), negFacts=factIds(candidate.neg);
    const addFacts=factIds(candidate.add), delFacts=factIds(candidate.del);
    const action:GroundedAction = {number:actions.length,name:candidate.source.name,source:candidate.source,
      arguments:candidate.arguments,cost:candidate.cost,
      notation:notation({predicate:candidate.source.name,terms:candidate.arguments}),
      preFacts,negFacts,addFacts,delFacts,
      pre:mask(preFacts),neg:mask(negFacts),add:mask(addFacts),del:mask(delFacts)};
    actions.push(action);
  }
  const initialFacts = problem.init.filter(atom => domain.fluent.has(atom.predicate)).map(atom => factNumbers.get(notation(atom))!);
  const goals = new Set<number>();
  const unreachable:Atom[] = [];
  for (const atom of problem.goals) {
    const key = notation(atom);
    if (factNumbers.has(key)) goals.add(factNumbers.get(key)!);
    else if (!domain.static.has(atom.predicate) || !initialAtoms.has(key)) unreachable.push(atom);
  }
  const goalFacts = [...goals].sort((a, b) => a - b);
  return {facts, factNumbers, actions, schemas, candidateCount: candidates.length, objectsByType, unreachable,
    initial: mask(initialFacts), goal: mask(goalFacts), goalFacts,
    staticCount: problem.init.filter(atom => domain.static.has(atom.predicate)).length,
    actionTable: new Map(actions.map(action => [action.notation, action]))};
}

