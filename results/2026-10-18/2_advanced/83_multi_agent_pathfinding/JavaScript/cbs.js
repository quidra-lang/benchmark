'use strict';

function position(path, time) {
  return path[Math.min(time, path.length - 1)];
}

function costs(paths) {
  let soc = 0;
  let makespan = 0;
  for (const path of paths) {
    soc += path.length - 1;
    makespan = Math.max(makespan, path.length - 1);
  }
  return {soc, makespan};
}

function conflicts(paths) {
  const result = [];
  const maximum = costs(paths).makespan;
  for (let time = 1; time <= maximum; time++) {
    for (let a = 0; a < paths.length; a++) {
      const from = position(paths[a], time - 1);
      const to = position(paths[a], time);
      for (let b = a + 1; b < paths.length; b++) {
        if (to === position(paths[b], time)) result.push({kind: 'vertex', time, a, b, u: to, v: to});
        else if (to === position(paths[b], time - 1) && from === position(paths[b], time)) {
          result.push({kind: 'edge', time, a, b, u: from, v: to});
        }
      }
    }
  }
  return result;
}

function constraints(conflict) {
  const {kind, time, a, b, u, v} = conflict;
  return [{agent: a, kind, time, u, v},
    {agent: b, kind, time, u: kind === 'vertex' ? u : v, v: kind === 'vertex' ? v : u}];
}

class Node {
  constructor(paths, prohibitions, costFunction, number, parent = null) {
    this.paths = paths;
    this.prohibitions = prohibitions;
    this.number = number;
    this.parent = parent;
    this.depth = parent === null ? 0 : parent.depth + 1;
    const total = costs(paths);
    this.cost = costFunction === 'SOC' ? total.soc : total.makespan;
    this.conflicts = conflicts(paths);
  }
}

function compareNodes(a, b) {
  return a.cost - b.cost || a.conflicts.length - b.conflicts.length || a.number - b.number;
}

module.exports = {position, costs, conflicts, constraints, Node, compareNodes};
