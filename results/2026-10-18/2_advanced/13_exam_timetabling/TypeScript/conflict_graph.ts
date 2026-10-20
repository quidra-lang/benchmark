import type { Course } from './enrolment.ts';
import type { Assignment } from './coloring.ts';

export interface Edge { first: Course; second: Course; shared: number }
export interface Graph { vertices: Course[]; edges: Edge[] }
export type Arrows = Map<Course,Set<Course>>;
export const byId = (a: {id: string},b: {id: string}) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
export const degreeOrder = (a: Course,b: Course) => b.neighbours.size-a.neighbours.size || byId(a,b);
export function buildGraph(courses: Map<string,Course>,students: Map<string,Course[]>): Graph {
  for (const course of courses.values()) course.neighbours.clear();
  for (const roster of students.values()) for (let i = 0; i < roster.length; i++) for (let j = i+1; j < roster.length; j++) {
    const a = roster[i], b = roster[j]; a.neighbours.set(b,(a.neighbours.get(b) ?? 0)+1); b.neighbours.set(a,(b.neighbours.get(a) ?? 0)+1);
  }
  const vertices = [...courses.values()].filter(c => c.students.length > 0).sort(byId), edges: Edge[] = [];
  for (const a of vertices) for (const [b,shared] of a.neighbours) if (a.id < b.id) edges.push({first:a,second:b,shared});
  return {vertices,edges};
}
export function components(vertices: Course[]): Course[][] {
  const unseen = new Set(vertices), groups: Course[][] = [];
  for (const first of vertices) {
    if (!unseen.delete(first)) continue;
    const group: Course[] = [], pending = [first];
    while (pending.length) { const course = pending.pop()!; group.push(course); for (const n of course.neighbours.keys()) if (unseen.delete(n)) pending.push(n); }
    groups.push(group.sort(byId));
  }
  return groups.sort((a,b) => b.length-a.length || byId(a[0],b[0]));
}
export function greedyClique(courses: Course[]): Course[] {
  let candidates = [...courses].sort(degreeOrder);
  const result: Course[] = [];
  while (candidates.length) { const course = candidates[0]; result.push(course); candidates = candidates.filter(c => course.neighbours.has(c)); }
  return result;
}
export function reachable(arrows: Arrows,from: Course,target: Course): boolean {
  const pending = [from], seen = new Set<Course>();
  while (pending.length) { const course = pending.pop()!; if (course === target) return true; if (seen.has(course)) continue; seen.add(course); for (const next of arrows.get(course) ?? []) pending.push(next); }
  return false;
}
export function kempeChain(first: Course,h: number,t: number,assignment: Assignment): Course[] {
  const seen = new Set([first]), pending = [first];
  while (pending.length) for (const n of pending.pop()!.neighbours.keys()) {
    const slot = assignment.get(n); if ((slot === h || slot === t) && !seen.has(n)) { seen.add(n); pending.push(n); }
  }
  return [...seen].sort(byId);
}
