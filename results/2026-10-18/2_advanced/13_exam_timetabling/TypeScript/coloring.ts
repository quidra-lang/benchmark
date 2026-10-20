import type { Course } from './enrolment.ts';
import { byId } from './conflict_graph.ts';

export type Assignment = Map<Course,number>;
export interface AssignmentEntry { course: Course; slot: number; saturation: number }
export interface AttemptResult { success: boolean; assignment: Assignment; order: AssignmentEntry[]; backtracks: number; deadCourse: Course | null }
function saturation(course: Course,assignment: Assignment): number {
  const slots = new Set<number>();
  for (const n of course.neighbours.keys()) { const slot = assignment.get(n); if (slot !== undefined) slots.add(slot); }
  return slots.size;
}
export function attempt(courses: Course[],fixed: Assignment,limit: number,candidates: (c: Course,a: Assignment) => number[]): AttemptResult {
  const assignment = new Map(fixed), order: AssignmentEntry[] = [];
  let backtracks = 0, deadCourse: Course | null = null, aborted = false;
  function search(): boolean {
    let chosen: Course | null = null, chosenSaturation = -1;
    for (const course of courses) {
      if (assignment.has(course)) continue;
      const value = saturation(course,assignment);
      if (chosen === null || value > chosenSaturation || (value === chosenSaturation && (course.neighbours.size > chosen.neighbours.size || (course.neighbours.size === chosen.neighbours.size && byId(course,chosen) < 0)))) { chosen = course; chosenSaturation = value; }
    }
    if (chosen === null) return true;
    for (const slot of candidates(chosen,assignment)) {
      assignment.set(chosen,slot); order.push({course:chosen,slot,saturation:chosenSaturation});
      if (search()) return true;
      order.pop(); assignment.delete(chosen); if (aborted) return false;
    }
    backtracks++; deadCourse = chosen; if (backtracks > limit) aborted = true; return false;
  }
  const success = search(); return {success,assignment,order,backtracks,deadCourse};
}
export function greedyNumbering(courses: Course[]): number {
  const assigned: Assignment = new Map(); let maximum = 0;
  for (const course of courses) {
    const used = new Set<number>();
    for (const n of course.neighbours.keys()) { const number = assigned.get(n); if (number !== undefined) used.add(number); }
    let number = 1; while (used.has(number)) number++; assigned.set(course,number); maximum = Math.max(maximum,number);
  }
  return maximum;
}
