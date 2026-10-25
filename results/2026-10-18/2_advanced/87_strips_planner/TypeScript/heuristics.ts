import {bit,numbers,contains,applicable} from './search.ts';
import type {
  GroundedModel,GroundedAction,HeuristicRecord,HeuristicRelaxation,
  HeuristicLevels,Landmarks
} from './types.ts';
export const names = ['goalcount', 'hmax', 'hadd', 'ff', 'lmcount'];

function aggregate(values:number[],mode:string):number {
  let result = 0;
  for (const value of values) {
    if (value === Infinity) return Infinity;
    result = mode === 'max' ? Math.max(result, value) : result + value;
  }
  return result;
}

export class Engine {
  problem:GroundedModel;
  achievers:GroundedAction[][];
  cache:Map<bigint,HeuristicRecord>;
  constructor(problem:GroundedModel) {
    this.problem = problem;
    this.achievers = Array.from({length: problem.facts.length}, ():GroundedAction[] => []);
    for (const action of problem.actions) for (const fact of action.addFacts) this.achievers[fact].push(action);
    this.cache = new Map<bigint,HeuristicRecord>();
  }

  record(state:bigint):HeuristicRecord {
    if (!this.cache.has(state)) this.cache.set(state, {});
    return this.cache.get(state)!;
  }

  costs(state:bigint,mode:'max'|'sum'):number[] {
    const record = this.record(state);
    const key: 'cmax'|'cadd' = mode === 'max' ? 'cmax' : 'cadd';
    if (record[key] !== undefined) return record[key];
    const costs = this.problem.facts.map((_, fact) => (state & bit(fact)) !== 0n ? 0 : Infinity);
    let changed = true;
    while (changed) {
      changed = false;
      for (const action of this.problem.actions) {
        const value = action.cost + aggregate(action.preFacts.map(fact => costs[fact]), mode);
        for (const fact of action.addFacts) {
          if (value < costs[fact]) {
            costs[fact] = value;
            changed = true;
          }
        }
      }
    }
    record[key] = costs;
    return costs;
  }

  relaxedPlan(state:bigint):HeuristicRelaxation {
    const record = this.record(state);
    if (record.relaxed !== undefined) return record.relaxed;
    const costs = this.costs(state, 'sum');
    if (this.problem.goalFacts.some(fact => costs[fact] === Infinity)) {
      record.relaxed = {value: Infinity, plan: [], helpful: []};
      return record.relaxed;
    }
    const best = this.problem.facts.map((_, fact) => {
      let chosen: GroundedAction | null = null;
      let minimum = Infinity;
      for (const action of this.achievers[fact]) {
        const value = action.cost + aggregate(action.preFacts.map(pre => costs[pre]), 'sum');
        if (value < minimum) {
          chosen = action;
          minimum = value;
        }
      }
      return chosen;
    });
    const selected = new Set<number>();
    const pending = this.problem.goalFacts.filter(fact => (state & bit(fact)) === 0n);
    while (pending.length > 0) {
      const action = best[pending.pop()!]!;
      if (selected.has(action.number)) continue;
      selected.add(action.number);
      for (const fact of action.preFacts) if ((state & bit(fact)) === 0n) pending.push(fact);
    }
    const plan = [...selected].sort((a, b) => a - b).map(number => this.problem.actions[number]);
    let value = 0;
    for (const action of plan) value += action.cost;
    record.relaxed = {value, plan, helpful: plan.filter(action => applicable(state, action))};
    return record.relaxed;
  }

  levels(state:bigint):HeuristicLevels {
    const facts = this.problem.facts.map((_, fact) => (state & bit(fact)) !== 0n ? 0 : Infinity);
    const actions = this.problem.actions.map(() => Infinity);
    for (let level = 0; ; level++) {
      let changed = false;
      for (const action of this.problem.actions) {
        if (actions[action.number] !== Infinity || !action.preFacts.every(fact => facts[fact] <= level)) continue;
        actions[action.number] = level;
        for (const fact of action.addFacts) if (facts[fact] === Infinity) {
          facts[fact] = level + 1;
          changed = true;
        }
      }
      if (!changed) break;
    }
    return {facts, actions};
  }

  landmarks(state:bigint):Landmarks {
    const record = this.record(state);
    if (record.landmarks !== undefined) return record.landmarks;
    const levels = this.levels(state);
    if (this.problem.goalFacts.some(fact => levels.facts[fact] === Infinity)) {
      record.landmarks = {value: Infinity, facts: []};
      return record.landmarks;
    }
    const landmarks = new Set<number>(this.problem.goalFacts.filter(fact => (state & bit(fact)) === 0n));
    const verified = new Map<number,boolean>();
    const verify = (fact:number):boolean => {
      if (verified.has(fact)) return verified.get(fact)!;
      let reachable = state;
      let previous;
      do {
        previous = reachable;
        for (const action of this.problem.actions) {
          if ((action.add & bit(fact)) === 0n && contains(reachable, action.pre)) reachable |= action.add;
        }
      } while (reachable !== previous);
      const passes = !contains(reachable, this.problem.goal);
      verified.set(fact, passes);
      return passes;
    };
    for (const fact of landmarks) {
      const achievers = this.achievers[fact].filter(action => levels.actions[action.number] === levels.facts[fact] - 1);
      let common = achievers[0].pre;
      for (const action of achievers.slice(1)) common &= action.pre;
      for (const candidate of numbers(common & ~state)) {
        if (!landmarks.has(candidate) && verify(candidate)) landmarks.add(candidate);
      }
    }
    record.landmarks = {value: landmarks.size, facts: [...landmarks].sort((a, b) => a - b)};
    return record.landmarks;
  }

  value(state:bigint,name:string):number {
    if (name === 'none') return 0;
    const record = this.record(state);
    const key = name as 'goalcount'|'hmax'|'hadd'|'ff'|'lmcount';
    if (record[key] !== undefined) return record[key]!;
    let value:number;
    if (name === 'goalcount') value = this.problem.goalFacts.filter(fact => (state & bit(fact)) === 0n).length;
    else if (name === 'hmax') value = aggregate(this.problem.goalFacts.map(fact => this.costs(state, 'max')[fact]), 'max');
    else if (name === 'hadd') value = aggregate(this.problem.goalFacts.map(fact => this.costs(state, 'sum')[fact]), 'sum');
    else if (name === 'ff') value = this.relaxedPlan(state).value;
    else value = this.landmarks(state).value;
    record[key] = value;
    return value;
  }

  all(state:bigint):Record<string,number> {
    return Object.fromEntries(names.map(name => [name, this.value(state, name)]));
  }
}

