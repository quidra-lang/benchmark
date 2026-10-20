interface Frame { node: number; parent: number; next: number }
export interface Components { groups: number[][]; component: number[] }

export function strongComponents(adjacency: number[][]): Components {
  const indices: number[] = Array(adjacency.length).fill(-1), low: number[] = Array(adjacency.length).fill(0);
  const active: boolean[] = Array(adjacency.length).fill(false), stack: number[] = [], frames: Frame[] = [], groups: number[][] = [];
  let serial = 0;
  function enter(node: number, parent: number) {
    indices[node] = serial; low[node] = serial; serial++;
    active[node] = true; stack.push(node); frames.push({ node, parent, next: 0 });
  }
  for (let start = 0; start < adjacency.length; start++) {
    if (indices[start] !== -1) continue;
    enter(start, -1);
    while (frames.length > 0) {
      const frame = frames.at(-1)!, node = frame.node;
      if (frame.next < adjacency[node].length) {
        const next = adjacency[node][frame.next++];
        if (indices[next] === -1) enter(next, node);
        else if (active[next]) low[node] = Math.min(low[node], indices[next]);
      } else {
        frames.pop();
        if (low[node] === indices[node]) {
          const group: number[] = [];
          while (true) {
            const member = stack.pop()!;
            active[member] = false; group.push(member);
            if (member === node) break;
          }
          groups.push(group.sort((first, second) => first - second));
        }
        if (frame.parent !== -1) low[frame.parent] = Math.min(low[frame.parent], low[node]);
      }
    }
  }
  groups.sort((first, second) => first[0] - second[0]);
  const component: number[] = Array(adjacency.length);
  groups.forEach((group, index) => { for (const node of group) component[node] = index; });
  return { groups, component };
}
export function reachable(starts: number[], adjacency: number[][]): Set<number> {
  const seen = new Set(starts), pending = [...seen];
  for (let head = 0; head < pending.length; head++) for (const next of adjacency[pending[head]]) {
    if (!seen.has(next)) { seen.add(next); pending.push(next); }
  }
  return seen;
}
export function distances(starts: number[], adjacency: number[][]): number[] {
  const result: number[] = Array(adjacency.length).fill(-1), pending: number[] = [];
  for (const start of starts) if (result[start] === -1) { result[start] = 0; pending.push(start); }
  for (let head = 0; head < pending.length; head++) {
    const node = pending[head];
    for (const next of adjacency[node]) if (result[next] === -1) { result[next] = result[node] + 1; pending.push(next); }
  }
  return result;
}
export function weakComponents(adjacency: number[][], nodes = adjacency.map((_, index) => index)): number[][] {
  const unseen = new Set(nodes), groups: number[][] = [];
  for (const start of nodes) {
    if (!unseen.delete(start)) continue;
    const group: number[] = [], pending = [start];
    while (pending.length > 0) {
      const node = pending.pop()!;
      group.push(node);
      for (const next of adjacency[node]) if (unseen.delete(next)) pending.push(next);
    }
    groups.push(group.sort((first, second) => first - second));
  }
  return groups;
}
