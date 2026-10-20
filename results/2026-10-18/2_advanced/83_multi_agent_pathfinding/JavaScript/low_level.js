'use strict';

class Heap {
  constructor(compare) {
    this.compare = compare;
    this.items = [];
  }

  get size() {
    return this.items.length;
  }

  push(value) {
    let index = this.items.length;
    this.items.push(value);
    while (index > 0) {
      const parent = Math.floor((index - 1) / 2);
      if (this.compare(this.items[parent], value) <= 0) break;
      this.items[index] = this.items[parent];
      index = parent;
    }
    this.items[index] = value;
  }

  pop() {
    const first = this.items[0];
    const last = this.items.pop();
    if (this.items.length === 0) return first;
    let index = 0;
    while (2 * index + 1 < this.items.length) {
      let child = 2 * index + 1;
      if (child + 1 < this.items.length && this.compare(this.items[child + 1], this.items[child]) < 0) child++;
      if (this.compare(last, this.items[child]) <= 0) break;
      this.items[index] = this.items[child];
      index = child;
    }
    this.items[index] = last;
    return first;
  }
}

class Prohibitions {
  constructor(size, entries = []) {
    this.size = size;
    this.entries = entries;
    this.states = new Set();
    this.moves = new Set();
    this.permanent = new Map();
    this.latest = new Map();
    for (const entry of entries) {
      if (entry.kind === 'vertex') this.addState(entry.v, entry.time);
      else this.addMove(entry.u, entry.v, entry.time);
    }
  }

  addState(cell, time) {
    this.states.add(time * this.size + cell);
    if (!this.latest.has(cell) || this.latest.get(cell) < time) this.latest.set(cell, time);
  }

  addMove(from, to, time) {
    this.moves.add((time * this.size + from) * this.size + to);
  }

  permits(from, to, time) {
    return !this.states.has(time * this.size + to) &&
      (!this.permanent.has(to) || this.permanent.get(to) > time) &&
      (from === to || !this.moves.has((time * this.size + from) * this.size + to));
  }

  arrival(goal) {
    return this.latest.has(goal) ? this.latest.get(goal) + 1 : 0;
  }

  withConstraint(constraint) {
    return new Prohibitions(this.size, this.entries.concat(constraint));
  }

  reserve(path, startTime = 0, permanent = false) {
    for (let index = 0; index < path.length; index++) {
      this.addState(path[index], startTime + index);
      if (index > 0 && path[index] !== path[index - 1]) {
        this.addMove(path[index], path[index - 1], startTime + index);
      }
    }
    if (permanent) {
      const goal = path.at(-1);
      const time = startTime + path.length - 1;
      if (!this.permanent.has(goal) || time < this.permanent.get(goal)) this.permanent.set(goal, time);
    }
  }
}

class BudgetExceeded extends Error {}

function counter(limit = null) {
  return {limit, searches: 0, expansions: 0};
}

function search(grid, agent, prohibitions, budget, start, startTime, maximum, window = false) {
  budget.searches++;
  const before = budget.expansions;
  const arrival = prohibitions.arrival(agent.goal);
  const open = new Heap((a, b) => a.f - b.f || b.g - a.g || a.number - b.number);
  const generated = new Set([startTime * grid.size + start]);
  let number = 0;
  open.push({cell: start, time: startTime, g: 0, f: agent.distance[start], number: number++, parent: null});
  while (open.size > 0) {
    const state = open.pop();
    budget.expansions++;
    if (budget.limit !== null && budget.expansions > budget.limit) throw new BudgetExceeded();
    if ((state.cell === agent.goal && state.time >= arrival) || (window && state.time === maximum)) {
      const path = [];
      for (let current = state; current !== null; current = current.parent) path.push(current.cell);
      path.reverse();
      return {path, expansions: budget.expansions - before};
    }
    if (state.time === maximum) continue;
    const time = state.time + 1;
    const g = time - startTime;
    for (const cell of grid.neighbors[state.cell]) {
      const key = time * grid.size + cell;
      if (agent.distance[cell] < 0 || !prohibitions.permits(state.cell, cell, time) || generated.has(key)) continue;
      generated.add(key);
      open.push({cell, time, g, f: g + agent.distance[cell], number: number++, parent: state});
    }
  }
  return {path: null, expansions: budget.expansions - before};
}

function plan(grid, agent, prohibitions, budget, horizon) {
  return search(grid, agent, prohibitions, budget, agent.start, 0, horizon);
}

module.exports = {Heap, Prohibitions, BudgetExceeded, counter, search, plan};
