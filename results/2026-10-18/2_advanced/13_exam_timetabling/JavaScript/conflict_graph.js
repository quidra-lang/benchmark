function byId(first, second) {
  return first.id < second.id ? -1 : first.id > second.id ? 1 : 0;
}

function degreeOrder(first, second) {
  return second.neighbours.size - first.neighbours.size || byId(first, second);
}

function buildGraph(courses, students) {
  for (const course of courses.values()) course.neighbours = new Map();
  for (const roster of students.values()) {
    for (let i = 0; i < roster.length; i += 1) {
      for (let j = i + 1; j < roster.length; j += 1) {
        const first = roster[i];
        const second = roster[j];
        first.neighbours.set(second, (first.neighbours.get(second) ?? 0) + 1);
        second.neighbours.set(first, (second.neighbours.get(first) ?? 0) + 1);
      }
    }
  }
  const vertices = [...courses.values()].filter(course => course.students.length > 0).sort(byId);
  const edges = [];
  for (const first of vertices) {
    for (const [second, shared] of first.neighbours) {
      if (first.id < second.id) edges.push({ first, second, shared });
    }
  }
  return { vertices, edges };
}

function components(vertices) {
  const unseen = new Set(vertices);
  const groups = [];
  for (const first of vertices) {
    if (!unseen.delete(first)) continue;
    const group = [];
    const pending = [first];
    while (pending.length > 0) {
      const course = pending.pop();
      group.push(course);
      for (const neighbour of course.neighbours.keys()) {
        if (unseen.delete(neighbour)) pending.push(neighbour);
      }
    }
    groups.push(group.sort(byId));
  }
  return groups.sort((first, second) => second.length - first.length || byId(first[0], second[0]));
}

function greedyClique(courses) {
  let candidates = [...courses].sort(degreeOrder);
  const result = [];
  while (candidates.length > 0) {
    const course = candidates[0];
    result.push(course);
    candidates = candidates.filter(candidate => course.neighbours.has(candidate));
  }
  return result;
}

function reachable(arrows, from, target) {
  const pending = [from];
  const seen = new Set();
  while (pending.length > 0) {
    const course = pending.pop();
    if (course === target) return true;
    if (seen.has(course)) continue;
    seen.add(course);
    for (const next of arrows.get(course) ?? []) pending.push(next);
  }
  return false;
}

function kempeChain(first, h, t, assignment) {
  const seen = new Set([first]);
  const pending = [first];
  while (pending.length > 0) {
    const course = pending.pop();
    for (const neighbour of course.neighbours.keys()) {
      const slot = assignment.get(neighbour);
      if ((slot === h || slot === t) && !seen.has(neighbour)) {
        seen.add(neighbour);
        pending.push(neighbour);
      }
    }
  }
  return [...seen].sort(byId);
}

module.exports = { byId, degreeOrder, buildGraph, components, greedyClique, reachable, kempeChain };
