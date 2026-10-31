function strongComponents(adjacency) {
  const indices = Array(adjacency.length).fill(-1);
  const low = Array(adjacency.length).fill(0);
  const active = Array(adjacency.length).fill(false);
  const stack = [];
  const frames = [];
  const groups = [];
  let serial = 0;
  function enter(node, parent) {
    indices[node] = serial;
    low[node] = serial;
    serial += 1;
    active[node] = true;
    stack.push(node);
    frames.push({ node, parent, next: 0 });
  }
  for (let start = 0; start < adjacency.length; start += 1) {
    if (indices[start] !== -1) continue;
    enter(start, -1);
    while (frames.length > 0) {
      const frame = frames.at(-1);
      const node = frame.node;
      if (frame.next < adjacency[node].length) {
        const next = adjacency[node][frame.next];
        frame.next += 1;
        if (indices[next] === -1) enter(next, node);
        else if (active[next]) low[node] = Math.min(low[node], indices[next]);
      } else {
        frames.pop();
        if (low[node] === indices[node]) {
          const group = [];
          while (true) {
            const member = stack.pop();
            active[member] = false;
            group.push(member);
            if (member === node) break;
          }
          groups.push(group.sort((first, second) => first - second));
        }
        if (frame.parent !== -1) low[frame.parent] = Math.min(low[frame.parent], low[node]);
      }
    }
  }
  groups.sort((first, second) => first[0] - second[0]);
  const component = Array(adjacency.length);
  groups.forEach((group, index) => {
    for (const node of group) component[node] = index;
  });
  return { groups, component };
}

function reachable(starts, adjacency) {
  const seen = new Set(starts);
  const pending = [...seen];
  for (let head = 0; head < pending.length; head += 1) {
    for (const next of adjacency[pending[head]]) {
      if (!seen.has(next)) {
        seen.add(next);
        pending.push(next);
      }
    }
  }
  return seen;
}

function distances(starts, adjacency) {
  const result = Array(adjacency.length).fill(-1);
  const pending = [];
  for (const start of starts) {
    if (result[start] === -1) {
      result[start] = 0;
      pending.push(start);
    }
  }
  for (let head = 0; head < pending.length; head += 1) {
    const node = pending[head];
    for (const next of adjacency[node]) {
      if (result[next] === -1) {
        result[next] = result[node] + 1;
        pending.push(next);
      }
    }
  }
  return result;
}

function weakComponents(adjacency, nodes = adjacency.map((_, index) => index)) {
  const unseen = new Set(nodes);
  const groups = [];
  for (const start of nodes) {
    if (!unseen.delete(start)) continue;
    const group = [];
    const pending = [start];
    while (pending.length > 0) {
      const node = pending.pop();
      group.push(node);
      for (const next of adjacency[node]) if (unseen.delete(next)) pending.push(next);
    }
    groups.push(group.sort((first, second) => first - second));
  }
  return groups;
}

module.exports = { strongComponents, reachable, distances, weakComponents };
