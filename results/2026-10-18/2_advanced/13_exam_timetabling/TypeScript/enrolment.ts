import { readFileSync } from 'node:fs';

export interface Course {
  id: string; duration: number; name: string; students: string[];
  neighbours: Map<Course,number>; empty: boolean; oversized: boolean; schedulable: boolean;
}
export interface Enrolment { courses: Map<string,Course>; students: Map<string,Course[]>; enrolmentCount: number }
function csvLines(path: string): string[] { return readFileSync(path,'ascii').split('\n').slice(1,-1); }
export function readEnrolment(errors: string[]): Enrolment {
  const courses = new Map<string,Course>(), students = new Map<string,Course[]>();
  csvLines('input/courses.csv').forEach((line,i) => {
    const [id,duration,name] = line.split(',');
    if (courses.has(id)) errors.push(`courses.csv line ${i+2}: duplicate course ${id}`);
    else courses.set(id,{id,duration:Number(duration),name,students:[],neighbours:new Map(),empty:false,oversized:false,schedulable:false});
  });
  let accepted = 0;
  csvLines('input/enrolments.csv').forEach((line,i) => {
    const [student,id] = line.split(','), course = courses.get(id);
    if (course === undefined) { errors.push(`enrolments.csv line ${i+2}: unknown course ${id}`); return; }
    const roster = students.get(student) ?? [];
    if (roster.includes(course)) { errors.push(`enrolments.csv line ${i+2}: duplicate enrolment ${student} ${id}`); return; }
    roster.push(course); students.set(student,roster); course.students.push(student); accepted++;
  });
  for (const course of courses.values()) course.students.sort();
  for (const roster of students.values()) roster.sort((a,b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  return {courses,students,enrolmentCount:accepted};
}
