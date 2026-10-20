'use strict';

const {bit, numbers, contains, applicable} = require('./search');
const names = ['goalcount', 'hmax', 'hadd', 'ff', 'lmcount'];

function aggregate(values, mode) {
  let result = 0;
  for (const value of values) {
    if (value === Infinity) return Infinity;
    result = mode === 'max' ? Math.max(result, value) : result + value;
  }
  return result;
}

class Engine {
  constructor(problem) {
    this.problem = problem;
    this.achievers = Array.from({length: problem.facts.length}, () => []);
    for (const action of problem.actions) for (const fact of action.addFacts) this.achievers[fact].push(action);
    this.cache = new Map();
  }

  record(state) {
    if (!this.cache.has(state)) this.cache.set(state, {});
    return this.cache.get(state);
  }

  costs(state, mode) {
    const record = this.record(state);
    const key = mode === 'max' ? 'cmax' : 'cadd';
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

  relaxedPlan(state) {
    const record = this.record(state);
    if (record.relaxed !== undefined) return record.relaxed;
    const costs = this.costs(state, 'sum');
    if (this.problem.goalFacts.some(fact => costs[fact] === Infinity)) {
      record.relaxed = {value: Infinity, plan: [], helpful: []};
      return record.relaxed;
    }
    const best = this.problem.facts.map((_, fact) => {
      let chosen = null;
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
    const selected = new Set();
    const pending = this.problem.goalFacts.filter(fact => (state & bit(fact)) === 0n);
    while (pending.length > 0) {
      const action = best[pending.pop()];
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

  levels(state) {
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

  landmarks(state) {
    const record = this.record(state);
    if (record.landmarks !== undefined) return record.landmarks;
    const levels = this.levels(state);
    if (this.problem.goalFacts.some(fact => levels.facts[fact] === Infinity)) {
      record.landmarks = {value: Infinity, facts: []};
      return record.landmarks;
    }
    const landmarks = new Set(this.problem.goalFacts.filter(fact => (state & bit(fact)) === 0n));
    const verified = new Map();
    const verify = fact => {
      if (verified.has(fact)) return verified.get(fact);
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

  value(state, name) {
    if (name === 'none') return 0;
    const record = this.record(state);
    if (record[name] !== undefined) return record[name];
    let value;
    if (name === 'goalcount') value = this.problem.goalFacts.filter(fact => (state & bit(fact)) === 0n).length;
    else if (name === 'hmax') value = aggregate(this.problem.goalFacts.map(fact => this.costs(state, 'max')[fact]), 'max');
    else if (name === 'hadd') value = aggregate(this.problem.goalFacts.map(fact => this.costs(state, 'sum')[fact]), 'sum');
    else if (name === 'ff') value = this.relaxedPlan(state).value;
    else value = this.landmarks(state).value;
    record[name] = value;
    return value;
  }

  all(state) {
    return Object.fromEntries(names.map(name => [name, this.value(state, name)]));
  }
}

module.exports = {Engine, names};
