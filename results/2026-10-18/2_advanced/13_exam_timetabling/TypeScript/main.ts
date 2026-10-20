import { readFileSync } from 'node:fs';
import { readEnrolment, type Course, type Enrolment } from './enrolment.ts';
import { byId, degreeOrder, buildGraph, components, greedyClique, reachable, kempeChain, type Graph, type Arrows } from './conflict_graph.ts';
import { attempt, greedyNumbering, type Assignment, type AssignmentEntry } from './coloring.ts';
import { readRooms, packingOrder, pack, type Room, type Packing, type Placement, type RoomSpace } from './rooms.ts';
import { floorRatio, ceilRatio, percentage, tableLine, writeReports } from './report.ts';

interface Slot { number: number; day: number; period: number; minutes: number; name: string }
interface Data extends Enrolment {
  rooms: Room[]; errors: string[]; courseList: Course[]; largestRoom: number; schedulable: Course[]; graph: Graph;
  days: number; periods: number[]; limit: number; weights: number[]; deadline: number; ratio: number;
  slots: Slot[]; frontOrder: Course[]; closed: Set<number>; unavailable: Map<string,Set<number>>;
  fixed: Assignment; orders: [Course,Course][]; arrows: Arrows; open: number[]; fixedSlots: Set<number>; queries: string[];
}
interface Score { counts: [number,number,number,number]; value: number }
interface AttemptLog { courses: number; backtracks: number; success: boolean; deadCourse: Course | null }
interface Insertion { course: Course; slot: number; increase: number }
interface Exchange { h: number; t: number; before: number; after: number }
interface Round { pairs: number; fixed: number; invalid: number; worse: number; applied: number; exchanges: Exchange[] }
interface Move { course: Course; before: number; after: number }
interface Swap extends Exchange { course: Course; moves: Move[] }
interface Pass { candidates: number; fixed: number; invalid: number; rooms: number; worse: number; applied: number; swaps: Swap[] }
class Schedule {
  assignment: Assignment = new Map();
  assignmentOrder: AssignmentEntry[] = [];
  excluded = new Set<Course>();
  attempts: AttemptLog[] = [];
  insertions: Insertion[] = [];
  reasons = new Map<Course,string[]>();
  unscheduled: Course[] = [];
  initial: Score = {counts:[0,0,0,0],value:0};
  exchanged: Score = this.initial;
  final: Score = this.initial;
  rounds: Round[] = [];
  passes: Pass[] = [];
}
interface SlotInfo { packing: Packing; used: RoomSpace[]; invigilators: number; students: number; capacity: number }
interface RoomTotals { slots: number; exams: number; seated: number }
interface Seating { slotInfo: Map<number,SlotInfo>; placements: Map<Course,Placement>; roomTotals: Map<Room,RoomTotals>; invigilators: number }
type Relation = -1 | 0 | 1 | 2;
interface StudentPair { first: Course; second: Course; kind: 0 | 1 | 2 }
interface StudentInfo { id: string; assigned: Course[]; unassigned: Course[]; counts: number[]; pairs: StudentPair[]; penalty: number }
interface Analysis {
  contributions: Map<Course,number>; dayCounts: number[][]; late: Course[]; studentInfo: Map<string,StudentInfo>;
  histogram: Map<number,number>; gaps: Map<number,number>; dayloads: Map<number,number>;
}
const readLines = (path: string) => readFileSync(path,'ascii').split('\n').slice(0,-1);
function total<T>(values: Iterable<T>,valueOf: (value: T) => number): number { let sum = 0; for (const value of values) sum += valueOf(value); return sum; }
const sum = (values: Iterable<number>) => total(values,v => v);
const slotName = (d: Data,s: number) => d.slots[s-1].name;
const coursesAt = (a: Assignment,s: number) => [...a.keys()].filter(c => a.get(c) === s);
const unavailableStudent = (d: Data,c: Course,s: number) => c.students.find(id => d.unavailable.get(id)?.has(s));
const suitable = (d: Data,c: Course,s: number) => d.slots[s-1].minutes >= c.duration && unavailableStudent(d,c,s) === undefined;
const outside = (d: Data,day: number,period: number) => day < 1 || day > d.days || period < 1 || period > d.periods.length;

function validateDirective(d: Data,[kind,...fields]: string[]): string | null {
  if (kind === 'closed') {
    const [day,period] = fields.map(Number);
    if (outside(d,day,period)) return `slot ${day} ${period} outside calendar`;
    const s = (day-1)*d.periods.length+period;
    if (d.closed.has(s)) return `duplicate closed ${slotName(d,s)}`;
    d.closed.add(s);
  } else if (kind === 'unavailable') {
    const [student,dayText,periodText] = fields, day = Number(dayText), period = Number(periodText);
    if (!d.students.has(student)) return `unknown student ${student}`;
    if (outside(d,day,period)) return `slot ${day} ${period} outside calendar`;
    const s = (day-1)*d.periods.length+period, slots = d.unavailable.get(student) ?? new Set<number>();
    if (slots.has(s)) return `duplicate unavailable ${student} ${slotName(d,s)}`;
    slots.add(s); d.unavailable.set(student,slots);
  } else if (kind === 'fixed') {
    const [id,dayText,periodText] = fields, course = d.courses.get(id), day = Number(dayText), period = Number(periodText);
    if (course === undefined) return `unknown course ${id}`;
    if (!course.schedulable) return `course ${id} not schedulable`;
    if (outside(d,day,period)) return `slot ${day} ${period} outside calendar`;
    const s = (day-1)*d.periods.length+period;
    if (d.closed.has(s)) return `slot ${slotName(d,s)} closed`;
    if (!suitable(d,course,s)) return `slot ${slotName(d,s)} unsuitable for ${id}`;
    if (d.fixed.has(course)) return `duplicate fixed ${id}`;
    const neighbours = [...course.neighbours.keys()].filter(n => d.fixed.get(n) === s).sort(byId);
    if (neighbours.length) return `conflict ${id} ${neighbours[0].id}`;
    if (pack([...coursesAt(d.fixed,s),course],d.rooms) === null) return `rooms full ${slotName(d,s)}`;
    d.fixed.set(course,s);
  } else if (kind === 'after') {
    const [aId,bId] = fields, a = d.courses.get(aId), b = d.courses.get(bId);
    if (a === undefined) return `unknown course ${aId}`;
    if (b === undefined) return `unknown course ${bId}`;
    if (!a.schedulable) return `course ${aId} not schedulable`;
    if (!b.schedulable) return `course ${bId} not schedulable`;
    if (a === b) return `bad order ${aId} ${bId}`;
    if (d.arrows.get(a)?.has(b)) return `duplicate order ${aId} ${bId}`;
    if (reachable(d.arrows,b,a)) return `cycle ${aId} ${bId}`;
    if (d.fixed.has(a) && d.fixed.has(b) && d.fixed.get(a)! <= d.fixed.get(b)!) return `fixed order ${aId} ${bId}`;
    d.orders.push([a,b]); const arrows = d.arrows.get(a) ?? new Set<Course>(); arrows.add(b); d.arrows.set(a,arrows);
  }
  return null;
}
function readInput(): Data {
  const errors: string[] = [], enrolment = readEnrolment(errors), rooms = readRooms(errors);
  const courseList = [...enrolment.courses.values()].sort(byId), largestRoom = rooms[rooms.length-1].capacity;
  for (const c of courseList) { c.empty = c.students.length === 0; c.oversized = c.students.length > largestRoom; c.schedulable = !c.empty && !c.oversized; }
  const schedulable = courseList.filter(c => c.schedulable), graph = buildGraph(enrolment.courses,enrolment.students);
  const calendar = readLines('input/calendar.txt').map(line => line.split(' ')), days = Number(calendar[0][1]), periods = calendar[1].slice(1).map(Number);
  const slots: Slot[] = [];
  for (let day = 1; day <= days; day++) periods.forEach((minutes,i) => slots.push({number:slots.length+1,day,period:i+1,minutes,name:`D${day}P${i+1}`}));
  const d: Data = {...enrolment,rooms,errors,courseList,largestRoom,schedulable,graph,days,periods,slots,
    limit:Number(calendar[2][1]),weights:calendar[3].slice(1).map(Number),deadline:Number(calendar[4][2]),ratio:Number(calendar[5][1]),
    frontOrder:packingOrder(schedulable).slice(0,Number(calendar[4][1])),closed:new Set(),unavailable:new Map(),fixed:new Map(),orders:[],arrows:new Map(),open:[],fixedSlots:new Set(),queries:readLines('input/queries.txt')};
  for (let i = 6; i < calendar.length; i++) { const message = validateDirective(d,calendar[i]); if (message !== null) errors.push(`calendar.txt line ${i+1}: ${message}`); }
  d.open = slots.filter(s => !d.closed.has(s.number)).map(s => s.number); d.fixedSlots = new Set(d.fixed.values()); return d;
}
function orderConflicts(d: Data,c: Course,s: number,a: Assignment): Course[] {
  const others: Course[] = [];
  for (const [after,before] of d.orders) { if (after === c && a.has(before) && s <= a.get(before)!) others.push(before); if (before === c && a.has(after) && a.get(after)! <= s) others.push(after); }
  return others;
}
function ordersSatisfied(d: Data,a: Assignment): boolean { return d.orders.every(([after,before]) => !a.has(after) || !a.has(before) || a.get(after)! > a.get(before)!); }
function candidateSlots(d: Data,c: Course,a: Assignment): number[] {
  return d.open.filter(s => {
    if (!suitable(d,c,s)) return false;
    for (const n of c.neighbours.keys()) if (a.get(n) === s) return false;
    return orderConflicts(d,c,s,a).length === 0 && pack([...coursesAt(a,s),c],d.rooms) !== null;
  });
}
function relation(d: Data,x: number,y: number): Relation {
  const low = Math.min(x,y), high = Math.max(x,y);
  if (d.slots[low-1].day === d.slots[high-1].day) { if (high-low === 1) return 0; if (high-low >= 2) return 1; }
  else if (high-low === 1) return 2;
  return -1;
}
function penalty(d: Data,a: Assignment): Score {
  const counts: Score['counts'] = [0,0,0,0];
  for (const {first,second,shared} of d.graph.edges) { if (!a.has(first) || !a.has(second)) continue; const kind = relation(d,a.get(first)!,a.get(second)!); if (kind !== -1) counts[kind] += shared; }
  for (const c of d.frontOrder) if (a.has(c) && a.get(c)! > d.deadline) counts[3]++;
  return {counts,value:counts.reduce((value,n,i) => value+n*d.weights[i],0)};
}
function buildTimetable(d: Data): Schedule {
  const state = new Schedule();
  while (true) {
    const courses = d.schedulable.filter(c => !d.fixed.has(c) && !state.excluded.has(c));
    const result = attempt(courses,d.fixed,d.limit,(c,a) => candidateSlots(d,c,a));
    state.attempts.push({courses:courses.length,backtracks:result.backtracks,success:result.success,deadCourse:result.deadCourse});
    if (result.success) { state.assignment = result.assignment; state.assignmentOrder = result.order; return state; }
    state.excluded.add(result.deadCourse!);
  }
}
function insertionReason(d: Data,c: Course,s: number,a: Assignment): string {
  if (d.closed.has(s)) return 'closed';
  if (d.slots[s-1].minutes < c.duration) return 'too_short';
  const student = unavailableStudent(d,c,s); if (student !== undefined) return `unavailable ${student}`;
  const neighbours = [...c.neighbours.keys()].filter(n => a.get(n) === s).sort((x,y) => c.neighbours.get(y)!-c.neighbours.get(x)! || byId(x,y));
  if (neighbours.length) return `conflict ${neighbours[0].id} shared ${c.neighbours.get(neighbours[0])}`;
  const orders = orderConflicts(d,c,s,a).sort(byId); return orders.length ? `order ${orders[0].id}` : 'rooms';
}
function insertExcluded(d: Data,state: Schedule): void {
  for (const c of [...state.excluded].sort(byId)) {
    const slots = candidateSlots(d,c,state.assignment);
    if (!slots.length) { state.reasons.set(c,d.slots.map(s => insertionReason(d,c,s.number,state.assignment))); continue; }
    const before = penalty(d,state.assignment).value; let chosen = slots[0], best = Infinity;
    for (const s of slots) { const trial = new Map(state.assignment); trial.set(c,s); const value = penalty(d,trial).value; if (value < best) { best = value; chosen = s; } }
    state.assignment.set(c,chosen); state.insertions.push({course:c,slot:chosen,increase:best-before});
  }
  state.unscheduled = d.courseList.filter(c => c.oversized || (state.excluded.has(c) && !state.assignment.has(c)));
  state.initial = penalty(d,state.assignment);
}
function exchangeSlots(d: Data,state: Schedule): void {
  let current = state.initial;
  while (true) {
    const round: Round = {pairs:0,fixed:0,invalid:0,worse:0,applied:0,exchanges:[]};
    for (let i = 0; i < d.open.length; i++) for (let j = i+1; j < d.open.length; j++) {
      const h = d.open[i], t = d.open[j]; round.pairs++;
      if (d.fixedSlots.has(h) || d.fixedSlots.has(t)) { round.fixed++; continue; }
      const trial = new Map(state.assignment), changed: Course[] = [];
      for (const [c,s] of state.assignment) if (s === h || s === t) { trial.set(c,s === h ? t : h); changed.push(c); }
      if (changed.some(c => !suitable(d,c,trial.get(c)!)) || !ordersSatisfied(d,trial)) { round.invalid++; continue; }
      const next = penalty(d,trial); if (next.value >= current.value) { round.worse++; continue; }
      round.applied++; round.exchanges.push({h,t,before:current.value,after:next.value}); state.assignment = trial; current = next;
    }
    state.rounds.push(round); if (!round.applied) break;
  }
  state.exchanged = current;
}
function swapKempeChains(d: Data,state: Schedule): void {
  let current = state.exchanged;
  while (true) {
    const pass: Pass = {candidates:0,fixed:0,invalid:0,rooms:0,worse:0,applied:0,swaps:[]};
    const courses = [...state.assignment.keys()].filter(c => !d.fixed.has(c)).sort(byId);
    for (const c of courses) {
      const h = state.assignment.get(c)!;
      for (const t of d.open) {
        if (t === h) continue; pass.candidates++;
        const chain = kempeChain(c,h,t,state.assignment);
        if (chain.some(member => d.fixed.has(member))) { pass.fixed++; continue; }
        const trial = new Map(state.assignment), moves = chain.map(course => { const before = state.assignment.get(course)!, after = before === h ? t : h; trial.set(course,after); return {course,before,after}; });
        if (chain.some(member => !suitable(d,member,trial.get(member)!)) || !ordersSatisfied(d,trial)) { pass.invalid++; continue; }
        if (pack(coursesAt(trial,h),d.rooms) === null || pack(coursesAt(trial,t),d.rooms) === null) { pass.rooms++; continue; }
        const next = penalty(d,trial); if (next.value >= current.value) { pass.worse++; continue; }
        pass.applied++; pass.swaps.push({course:c,h,t,moves,before:current.value,after:next.value}); state.assignment = trial; current = next; break;
      }
    }
    state.passes.push(pass); if (!pass.applied) break;
  }
  state.final = current;
}
function assignRooms(d: Data,state: Schedule): Seating {
  const seating: Seating = {slotInfo:new Map(),placements:new Map(),roomTotals:new Map(d.rooms.map(r => [r,{slots:0,exams:0,seated:0}])),invigilators:0};
  for (const s of d.open) {
    const packing = pack(coursesAt(state.assignment,s),d.rooms)!, used = packing.rooms.filter(space => space.placements.length > 0);
    let invigilators = 0;
    for (const space of used) { const seated = space.room.capacity-space.remaining, counts = seating.roomTotals.get(space.room)!; invigilators += ceilRatio(seated,d.ratio); counts.slots++; counts.exams += space.placements.length; counts.seated += seated; }
    for (const [course,placement] of packing.placements) seating.placements.set(course,placement);
    seating.slotInfo.set(s,{packing,used,invigilators,students:total(packing.order,c => c.students.length),capacity:total(used,space => space.room.capacity)});
    seating.invigilators += invigilators;
  }
  return seating;
}
function increment(counts: Map<number,number>,key: number): void { counts.set(key,(counts.get(key) ?? 0)+1); }
function analyseFinal(d: Data,state: Schedule): Analysis {
  const a: Analysis = {contributions:new Map([...state.assignment.keys()].map(c => [c,0])),dayCounts:Array.from({length:d.days},() => [0,0,0]),late:[],studentInfo:new Map(),histogram:new Map(),gaps:new Map(),dayloads:new Map()};
  for (const {first,second,shared} of d.graph.edges) {
    if (!state.assignment.has(first) || !state.assignment.has(second)) continue;
    const x = state.assignment.get(first)!, y = state.assignment.get(second)!, kind = relation(d,x,y); if (kind === -1) continue;
    const value = d.weights[kind]*shared;
    a.contributions.set(first,a.contributions.get(first)!+value); a.contributions.set(second,a.contributions.get(second)!+value); a.dayCounts[d.slots[Math.min(x,y)-1].day-1][kind] += shared;
  }
  a.late = d.frontOrder.filter(c => state.assignment.has(c) && state.assignment.get(c)! > d.deadline);
  for (const c of a.late) a.contributions.set(c,a.contributions.get(c)!+d.weights[3]);
  for (const [id,roster] of d.students) {
    const assigned = roster.filter(c => state.assignment.has(c)).sort((x,y) => state.assignment.get(x)!-state.assignment.get(y)!);
    const unassigned = roster.filter(c => !state.assignment.has(c)), counts = [0,0,0], pairs: StudentPair[] = [], daily = Array<number>(d.days).fill(0);
    for (let i = 0; i < assigned.length; i++) {
      const first = assigned[i], firstSlot = state.assignment.get(first)!; daily[d.slots[firstSlot-1].day-1]++;
      if (i > 0) increment(a.gaps,firstSlot-state.assignment.get(assigned[i-1])!);
      for (let j = i+1; j < assigned.length; j++) { const second = assigned[j], kind = relation(d,firstSlot,state.assignment.get(second)!); if (kind !== -1) { counts[kind]++; pairs.push({first,second,kind}); } }
    }
    const value = counts[0]*d.weights[0]+counts[1]*d.weights[1]+counts[2]*d.weights[2];
    a.studentInfo.set(id,{id,assigned,unassigned,counts,pairs,penalty:value}); increment(a.histogram,value); if (assigned.length) increment(a.dayloads,Math.max(...daily));
  }
  return a;
}

function timetableReport(d: Data,state: Schedule,seating: Seating): string[] {
  const empty = d.courseList.filter(c => c.empty).length;
  const lines = [`TIMETABLE days ${d.days} periods ${d.periods.length} open ${d.open.length} courses ${d.courses.size} scheduled ${state.assignment.size} unscheduled ${state.unscheduled.length} empty ${empty}`];
  lines.push(tableLine('DAY',[...d.periods.map((_,i) => `P${i+1}`),'TOTAL'],4,10));
  for (let day = 1; day <= d.days; day++) {
    const columns: string[] = []; let exams = 0, students = 0;
    for (const slot of d.slots.filter(s => s.day === day)) {
      if (d.closed.has(slot.number)) columns.push('closed');
      else { const info = seating.slotInfo.get(slot.number)!; columns.push(`${info.packing.order.length}/${info.students}`); exams += info.packing.order.length; students += info.students; }
    }
    columns.push(`${exams}/${students}`); lines.push(tableLine(`D${day}`,columns,4,10));
  }
  for (const slot of d.slots) {
    const heading = `SLOT ${slot.number} ${slot.name} minutes ${slot.minutes}`;
    if (d.closed.has(slot.number)) { lines.push(heading+' closed'); continue; }
    const info = seating.slotInfo.get(slot.number)!;
    lines.push(`${heading} exams ${info.packing.order.length} students ${info.students} rooms ${info.used.length} seats ${info.capacity} invigilators ${info.invigilators}`);
    for (const course of info.packing.order) {
      const p = info.packing.placements.get(course)!, fixed = d.fixed.has(course) ? ' fixed' : '';
      lines.push(`  ${course.id} ${course.duration}min students ${course.students.length} room ${p.room.id} seats ${p.first}-${p.last}${fixed} ${course.name}`);
    }
  }
  for (const room of d.rooms) {
    const c = seating.roomTotals.get(room)!;
    lines.push(`ROOM ${room.id} capacity ${room.capacity} slots ${c.slots} exams ${c.exams} seated ${c.seated} utilization ${percentage(c.seated,room.capacity*d.open.length)}`);
  }
  lines.push(`INVIGILATORS total ${seating.invigilators} ratio ${d.ratio}`); return lines;
}
function roomsReport(d: Data,seating: Seating): string[] {
  const lines = ['slot,room,course,students,first_seat,last_seat'];
  for (const s of d.open) for (const space of seating.slotInfo.get(s)!.packing.rooms) for (const p of space.placements) lines.push(`${slotName(d,s)},${space.room.id},${p.course.id},${p.course.students.length},${p.first},${p.last}`);
  return lines;
}
function breakdown(score: Score): string {
  const [back,same,overnight,late] = score.counts;
  return `back_to_back ${back} same_day ${same} overnight ${overnight} front_load ${late} penalty ${score.value}`;
}
function penaltyReport(d: Data,state: Schedule,a: Analysis): string[] {
  const [back,same,overnight,front] = d.weights;
  const lines = [`WEIGHTS back_to_back ${back} same_day ${same} overnight ${overnight} front_load ${front}`,`FRONT_LOAD courses ${d.frontOrder.length} last_slot ${slotName(d,d.deadline)}`,`INITIAL ${breakdown(state.initial)}`];
  let serial = 0;
  state.rounds.forEach((r,i) => {
    lines.push(`ROUND ${i+1} pairs ${r.pairs} fixed ${r.fixed} invalid ${r.invalid} worse ${r.worse} applied ${r.applied}`);
    for (const e of r.exchanges) lines.push(`EXCHANGE ${++serial} ${slotName(d,e.h)} ${slotName(d,e.t)} penalty ${e.before} -> ${e.after}`);
  });
  lines.push(`EXCHANGED ${breakdown(state.exchanged)}`); serial = 0;
  state.passes.forEach((p,i) => {
    lines.push(`PASS ${i+1} candidates ${p.candidates} fixed ${p.fixed} invalid ${p.invalid} rooms ${p.rooms} worse ${p.worse} applied ${p.applied}`);
    for (const swap of p.swaps) {
      lines.push(`SWAP ${++serial} ${swap.course.id} ${slotName(d,swap.h)} ${slotName(d,swap.t)} chain ${swap.moves.length} penalty ${swap.before} -> ${swap.after}`);
      for (const move of swap.moves) lines.push(`  MOVE ${move.course.id} ${slotName(d,move.before)} -> ${slotName(d,move.after)}`);
    }
  });
  lines.push(`FINAL ${breakdown(state.final)}`,`SAVED ${state.initial.value-state.final.value}`);
  a.dayCounts.forEach((c,i) => lines.push(`DAY D${i+1} back_to_back ${c[0]} same_day ${c[1]} overnight ${c[2]}`));
  for (const course of a.late) lines.push(`LATE ${course.id} ${slotName(d,state.assignment.get(course)!)} students ${course.students.length}`);
  const contributions = [...state.assignment.keys()].sort((x,y) => a.contributions.get(y)!-a.contributions.get(x)! || byId(x,y)).slice(0,10);
  for (const course of contributions) if (a.contributions.get(course)! > 0) lines.push(`COURSE ${course.id} ${slotName(d,state.assignment.get(course)!)} penalty ${a.contributions.get(course)}`);
  const distributions: [string,Map<number,number>][] = [['HISTOGRAM',a.histogram],['GAP',a.gaps],['DAYLOAD',a.dayloads]];
  for (const [label,counts] of distributions) for (const [value,count] of [...counts].sort((x,y) => x[0]-y[0])) lines.push(`${label} ${value} ${count}`);
  const worst = [...a.studentInfo.values()].sort((x,y) => y.penalty-x.penalty || byId(x,y)).slice(0,5);
  for (const student of worst) if (student.penalty > 0) lines.push(`WORST ${student.id} penalty ${student.penalty} back_to_back ${student.counts[0]} same_day ${student.counts[1]} overnight ${student.counts[2]}`);
  return lines;
}
function studentReport(d: Data,state: Schedule,seating: Seating,a: Analysis): string[] {
  const lines: string[] = [], classes = ['BACK_TO_BACK','SAME_DAY','OVERNIGHT'];
  for (const id of d.queries) {
    const roster = d.students.get(id);
    if (roster === undefined) { lines.push(`STUDENT ${id} not found`); continue; }
    const info = a.studentInfo.get(id)!;
    lines.push(`STUDENT ${id} exams ${roster.length} scheduled ${info.assigned.length} penalty ${info.penalty}`);
    for (const course of info.assigned) {
      const p = seating.placements.get(course)!, seat = p.first+course.students.indexOf(id);
      lines.push(`  ${slotName(d,state.assignment.get(course)!)} ${course.id} room ${p.room.id} seat ${seat} ${course.name}`);
    }
    for (const course of info.unassigned) lines.push(`  UNSCHEDULED ${course.id} ${course.name}`);
    for (const p of info.pairs) lines.push(`  ${classes[p.kind]} ${slotName(d,state.assignment.get(p.first)!)} ${p.first.id} ${slotName(d,state.assignment.get(p.second)!)} ${p.second.id}`);
    for (const s of [...(d.unavailable.get(id) ?? [])].sort((x,y) => x-y)) lines.push(`  UNAVAILABLE ${slotName(d,s)}`);
  }
  return lines;
}
function courseReport(d: Data,state: Schedule,a: Analysis): string[] {
  const lines = ['course,status,slot,students,minutes,degree,penalty'];
  for (const c of d.courseList) {
    const assigned = state.assignment.has(c), status = d.fixed.has(c) ? 'fixed' : assigned ? 'scheduled' : c.oversized ? 'too_large' : c.empty ? 'empty' : 'no_slot';
    const slot = assigned ? slotName(d,state.assignment.get(c)!) : '-';
    lines.push(`${c.id},${status},${slot},${c.students.length},${c.duration},${c.neighbours.size},${a.contributions.get(c) ?? 0}`);
  }
  return lines;
}
function processingReport(d: Data,state: Schedule,seating: Seating): string[] {
  const lines = [`INPUT courses ${d.courses.size} enrolments ${d.enrolmentCount} rooms ${d.rooms.length} students ${d.students.size} errors ${d.errors.length}`];
  for (const error of d.errors) lines.push(`ERROR ${error}`);
  const {vertices,edges} = d.graph, density = vertices.length < 2 ? 0 : floorRatio(2000*edges.length,vertices.length*(vertices.length-1));
  lines.push(`GRAPH courses ${vertices.length} edges ${edges.length} shared ${total(edges,e => e.shared)} density ${density}`);
  for (const course of [...vertices].sort(degreeOrder).slice(0,5)) lines.push(`DEGREE ${course.id} neighbours ${course.neighbours.size} shared ${sum(course.neighbours.values())} students ${course.students.length}`);
  const groups = components(vertices); lines.push(`COMPONENTS ${groups.length}`);
  groups.forEach((group,i) => lines.push(`COMPONENT ${i+1} size ${group.length} first ${group[0].id}`));
  const clique = greedyClique(d.schedulable); lines.push(['CLIQUE','size',clique.length,...clique.map(c => c.id)].join(' '));
  let maximumLoad = 0, maximumStudents = 0;
  for (const roster of d.students.values()) { if (roster.length > maximumLoad) { maximumLoad = roster.length; maximumStudents = 1; } else if (roster.length === maximumLoad) maximumStudents++; }
  lines.push(`LOAD max_exams ${maximumLoad} students ${maximumStudents}`);
  const demand = total(d.schedulable,c => c.students.length), capacity = total(d.rooms,r => r.capacity);
  lines.push(`SEATS demand ${demand} capacity ${capacity} min_slots ${ceilRatio(demand,capacity)}`);
  lines.push(`HEURISTIC largest_degree slots ${greedyNumbering([...d.schedulable].sort(degreeOrder))}`,`HEURISTIC largest_enrolment slots ${greedyNumbering(packingOrder(d.schedulable))}`);
  const table = packingOrder(vertices).slice(0,8); lines.push(tableLine('MATRIX',table.map(c => c.id),9,9));
  for (const course of table) lines.push(tableLine(course.id,table.map(other => other === course ? '-' : course.neighbours.get(other) ?? 0),9,9));
  for (const course of d.courseList) if (course.empty) lines.push(`EMPTY ${course.id}`);
  for (const course of d.courseList) if (course.oversized) lines.push(`TOO_LARGE ${course.id} students ${course.students.length} largest_room ${d.largestRoom}`);
  for (const s of [...d.closed].sort((x,y) => x-y)) lines.push(`CLOSED ${slotName(d,s)}`);
  for (const c of [...d.fixed.keys()].sort(byId)) lines.push(`FIXED ${c.id} ${slotName(d,d.fixed.get(c)!)}`);
  for (const [after,before] of d.orders) lines.push(`AFTER ${after.id} ${before.id}`);
  state.attempts.forEach((result,i) => lines.push(`ATTEMPT ${i+1} courses ${result.courses} backtracks ${result.backtracks} ${result.success ? 'success' : `failed ${result.deadCourse!.id}`}`));
  state.assignmentOrder.forEach((entry,i) => lines.push(`ORDER ${i+1} ${entry.course.id} ${slotName(d,entry.slot)} saturation ${entry.saturation} degree ${entry.course.neighbours.size}`));
  for (const insertion of state.insertions) lines.push(`INSERTED ${insertion.course.id} ${slotName(d,insertion.slot)} penalty ${insertion.increase}`);
  for (const course of state.unscheduled) {
    lines.push(`UNSCHEDULED ${course.id} reason ${course.oversized ? 'too_large' : 'no_slot'} students ${course.students.length}`);
    if (!course.oversized) state.reasons.get(course)!.forEach((message,i) => lines.push(`  ${slotName(d,i+1)} ${message}`));
  }
  const slotsUsed = [...seating.slotInfo.values()].filter(info => info.packing.order.length > 0).length;
  lines.push(`SUMMARY scheduled ${state.assignment.size} unscheduled ${state.unscheduled.length} slots_used ${slotsUsed} penalty ${state.final.value}`); return lines;
}
function main(): void {
  const data = readInput(), state = buildTimetable(data);
  insertExcluded(data,state); exchangeSlots(data,state); swapKempeChains(data,state);
  const seating = assignRooms(data,state), analysis = analyseFinal(data,state);
  writeReports({'timetable.txt':timetableReport(data,state,seating),'rooms.csv':roomsReport(data,seating),
    'penalties.txt':penaltyReport(data,state,analysis),'student_schedules.txt':studentReport(data,state,seating,analysis),
    'course_status.csv':courseReport(data,state,analysis),'report.txt':processingReport(data,state,seating)});
}
main();
