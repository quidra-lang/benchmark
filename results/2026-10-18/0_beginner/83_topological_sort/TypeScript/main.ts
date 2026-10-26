function kahn(courses: string[], pairs: string[][]) {
  const graph = new Map<string, string[]>(courses.map(course => [course, []]));
  const indegree = new Map<string, number>(courses.map(course => [course, 0]));
  for (const [source, target] of pairs) {
    graph.get(source)!.push(target);
    indegree.set(target, indegree.get(target)! + 1);
  }
  const ready = courses.filter(course => indegree.get(course) === 0).sort();
  const order: string[] = [];
  while (ready.length > 0) {
    const course = ready.shift()!;
    order.push(course);
    for (const target of graph.get(course)!) {
      indegree.set(target, indegree.get(target)! - 1);
      if (indegree.get(target) === 0) ready.push(target);
    }
    ready.sort();
  }
  return {order, cycle: courses.filter(course => !order.includes(course)).sort()};
}

const courses1 = "physics algebra graphics programming statistics calculus databases algorithms".split(" ");
const pairs1 = [
  ["calculus", "physics"], ["algebra", "calculus"], ["programming", "algorithms"],
  ["algebra", "statistics"], ["algorithms", "databases"], ["statistics", "databases"],
  ["calculus", "graphics"], ["algorithms", "graphics"], ["physics", "graphics"]
];
const courses2 = "music ecology art geology biology chemistry".split(" ");
const pairs2 = [
  ["music", "art"], ["art", "ecology"], ["biology", "chemistry"],
  ["chemistry", "ecology"], ["ecology", "geology"], ["geology", "chemistry"]
];
const first = kahn(courses1, pairs1), second = kahn(courses2, pairs2);
console.log(`order: ${first.order.join(" -> ")}`);
console.log(`order: ${second.order.join(" -> ")}`);
console.log(`cycle: ${second.cycle.join(" ")}`);
