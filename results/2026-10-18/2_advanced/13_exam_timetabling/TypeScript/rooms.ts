import { readFileSync } from 'node:fs';
import type { Course } from './enrolment.ts';

export interface Room { id: string; capacity: number }
export interface Placement { course: Course; room: Room; first: number; last: number }
export interface RoomSpace { room: Room; remaining: number; duration: number | null; placements: Placement[] }
export interface Packing { order: Course[]; rooms: RoomSpace[]; placements: Map<Course,Placement> }
export function packingOrder(courses: Iterable<Course>): Course[] {
  return [...courses].sort((a,b) => b.students.length-a.students.length || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}
export function readRooms(errors: string[]): Room[] {
  const rooms = new Map<string,Room>();
  readFileSync('input/rooms.csv','ascii').split('\n').slice(1,-1).forEach((line,i) => {
    const [id,value] = line.split(','), capacity = Number(value);
    if (rooms.has(id)) errors.push(`rooms.csv line ${i+2}: duplicate room ${id}`);
    else if (capacity < 1) errors.push(`rooms.csv line ${i+2}: bad capacity ${capacity}`);
    else rooms.set(id,{id,capacity});
  });
  return [...rooms.values()].sort((a,b) => a.capacity-b.capacity || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}
export function pack(courses: Iterable<Course>,rooms: Room[]): Packing | null {
  const order = packingOrder(courses), placements = new Map<Course,Placement>();
  const spaces: RoomSpace[] = rooms.map(room => ({room,remaining:room.capacity,duration:null,placements:[]}));
  for (const course of order) {
    const space = spaces.find(s => s.remaining >= course.students.length && (s.duration === null || s.duration === course.duration));
    if (space === undefined) return null;
    const first = space.room.capacity-space.remaining+1, placement = {course,room:space.room,first,last:first+course.students.length-1};
    space.remaining -= course.students.length; space.duration = course.duration; space.placements.push(placement); placements.set(course,placement);
  }
  return {order,rooms:spaces,placements};
}
