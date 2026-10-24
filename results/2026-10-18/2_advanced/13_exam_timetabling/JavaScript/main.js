const fs = require('node:fs');
const { readEnrolment } = require('./enrolment');
const { byId, degreeOrder, buildGraph, components, greedyClique, reachable, kempeChain } = require('./conflict_graph');
const { attempt, greedyNumbering } = require('./coloring');
const { readRooms, packingOrder, pack } = require('./rooms');
const { floorRatio, ceilRatio, percentage, tableLine, writeReports } = require('./report');

function readLines(path) {
  return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
}

function total(values, valueOf = value => value) {
  let result = 0;
  for (const value of values) result += valueOf(value);
  return result;
}

function slotName(data, slot) {
  return data.slots[slot - 1].name;
}

function unavailableStudent(data, course, slot) {
  return course.students.find(student => data.unavailable.get(student)?.has(slot));
}

function suitable(data, course, slot) {
  return data.slots[slot - 1].minutes >= course.duration
    && unavailableStudent(data, course, slot) === undefined;
}

function coursesAt(assignment, slot) {
  return [...assignment.keys()].filter(course => assignment.get(course) === slot);
}

function outside(data, day, period) {
  return day < 1 || day > data.days || period < 1 || period > data.periods.length;
}

function validateDirective(data, tokens) {
  const [kind, ...fields] = tokens;
  if (kind === 'closed') {
    const [day, period] = fields.map(Number);
    if (outside(data, day, period)) return `slot ${day} ${period} outside calendar`;
    const slot = (day - 1) * data.periods.length + period;
    if (data.closed.has(slot)) return `duplicate closed ${slotName(data, slot)}`;
    data.closed.add(slot);
  } else if (kind === 'unavailable') {
    const [student, dayText, periodText] = fields;
    const day = Number(dayText);
    const period = Number(periodText);
    if (!data.students.has(student)) return `unknown student ${student}`;
    if (outside(data, day, period)) return `slot ${day} ${period} outside calendar`;
    const slot = (day - 1) * data.periods.length + period;
    if (data.unavailable.get(student)?.has(slot)) return `duplicate unavailable ${student} ${slotName(data, slot)}`;
    if (!data.unavailable.has(student)) data.unavailable.set(student, new Set());
    data.unavailable.get(student).add(slot);
  } else if (kind === 'fixed') {
    const [id, dayText, periodText] = fields;
    const course = data.courses.get(id);
    const day = Number(dayText);
    const period = Number(periodText);
    if (course === undefined) return `unknown course ${id}`;
    if (!course.schedulable) return `course ${id} not schedulable`;
    if (outside(data, day, period)) return `slot ${day} ${period} outside calendar`;
    const slot = (day - 1) * data.periods.length + period;
    if (data.closed.has(slot)) return `slot ${slotName(data, slot)} closed`;
    if (!suitable(data, course, slot)) return `slot ${slotName(data, slot)} unsuitable for ${id}`;
    if (data.fixed.has(course)) return `duplicate fixed ${id}`;
    const neighbours = [...course.neighbours.keys()].filter(neighbour => data.fixed.get(neighbour) === slot).sort(byId);
    if (neighbours.length > 0) return `conflict ${id} ${neighbours[0].id}`;
    if (pack([...coursesAt(data.fixed, slot), course], data.rooms) === null) return `rooms full ${slotName(data, slot)}`;
    data.fixed.set(course, slot);
  } else if (kind === 'after') {
    const [firstId, secondId] = fields;
    const first = data.courses.get(firstId);
    const second = data.courses.get(secondId);
    if (first === undefined) return `unknown course ${firstId}`;
    if (second === undefined) return `unknown course ${secondId}`;
    if (!first.schedulable) return `course ${firstId} not schedulable`;
    if (!second.schedulable) return `course ${secondId} not schedulable`;
    if (first === second) return `bad order ${firstId} ${secondId}`;
    if (data.arrows.get(first)?.has(second)) return `duplicate order ${firstId} ${secondId}`;
    if (reachable(data.arrows, second, first)) return `cycle ${firstId} ${secondId}`;
    if (data.fixed.has(first) && data.fixed.has(second) && data.fixed.get(first) <= data.fixed.get(second)) {
      return `fixed order ${firstId} ${secondId}`;
    }
    data.orders.push([first, second]);
    if (!data.arrows.has(first)) data.arrows.set(first, new Set());
    data.arrows.get(first).add(second);
  }
  return null;
}

function readInput() {
  const errors = [];
  const data = { ...readEnrolment(errors), rooms: readRooms(errors), errors };
  data.courseList = [...data.courses.values()].sort(byId);
  data.largestRoom = data.rooms.at(-1).capacity;
  for (const course of data.courseList) {
    course.empty = course.students.length === 0;
    course.oversized = course.students.length > data.largestRoom;
    course.schedulable = !course.empty && !course.oversized;
  }
  data.schedulable = data.courseList.filter(course => course.schedulable);
  data.graph = buildGraph(data.courses, data.students);
  const calendar = readLines('input/calendar.txt').map(line => line.split(' '));
  data.days = Number(calendar[0][1]);
  data.periods = calendar[1].slice(1).map(Number);
  data.limit = Number(calendar[2][1]);
  data.weights = calendar[3].slice(1).map(Number);
  [data.frontCount, data.deadline] = calendar[4].slice(1).map(Number);
  data.ratio = Number(calendar[5][1]);
  data.slots = [];
  for (let day = 1; day <= data.days; day += 1) {
    data.periods.forEach((minutes, index) => {
      data.slots.push({ number: data.slots.length + 1, day, period: index + 1, minutes, name: `D${day}P${index + 1}` });
    });
  }
  data.frontOrder = packingOrder(data.schedulable).slice(0, data.frontCount);
  data.closed = new Set();
  data.unavailable = new Map();
  data.fixed = new Map();
  data.orders = [];
  data.arrows = new Map();
  for (let index = 6; index < calendar.length; index += 1) {
    const message = validateDirective(data, calendar[index]);
    if (message !== null) errors.push(`calendar.txt line ${index + 1}: ${message}`);
  }
  data.open = data.slots.filter(slot => !data.closed.has(slot.number)).map(slot => slot.number);
  data.fixedSlots = new Set(data.fixed.values());
  data.queries = readLines('input/queries.txt');
  return data;
}

function orderConflicts(data, course, slot, assignment) {
  const others = [];
  for (const [after, before] of data.orders) {
    if (after === course && assignment.has(before) && slot <= assignment.get(before)) others.push(before);
    if (before === course && assignment.has(after) && assignment.get(after) <= slot) others.push(after);
  }
  return others;
}

function ordersSatisfied(data, assignment) {
  return data.orders.every(([after, before]) => !assignment.has(after) || !assignment.has(before)
    || assignment.get(after) > assignment.get(before));
}

function candidateSlots(data, course, assignment) {
  return data.open.filter(slot => {
    if (!suitable(data, course, slot)) return false;
    for (const neighbour of course.neighbours.keys()) if (assignment.get(neighbour) === slot) return false;
    if (orderConflicts(data, course, slot, assignment).length > 0) return false;
    return pack([...coursesAt(assignment, slot), course], data.rooms) !== null;
  });
}

function relation(data, first, second) {
  const low = Math.min(first, second);
  const high = Math.max(first, second);
  if (data.slots[low - 1].day === data.slots[high - 1].day) {
    if (high - low === 1) return 0;
    if (high - low >= 2) return 1;
  } else if (high - low === 1) return 2;
  return -1;
}

function penalty(data, assignment) {
  const counts = [0, 0, 0, 0];
  for (const edge of data.graph.edges) {
    if (!assignment.has(edge.first) || !assignment.has(edge.second)) continue;
    const kind = relation(data, assignment.get(edge.first), assignment.get(edge.second));
    if (kind >= 0) counts[kind] += edge.shared;
  }
  for (const course of data.frontOrder) {
    if (assignment.has(course) && assignment.get(course) > data.deadline) counts[3] += 1;
  }
  let value = 0;
  for (let index = 0; index < counts.length; index += 1) value += counts[index] * data.weights[index];
  return { counts, value };
}

function buildTimetable(data) {
  const state = { excluded: new Set(), attempts: [], insertions: [], reasons: new Map() };
  while (true) {
    const courses = data.schedulable.filter(course => !data.fixed.has(course) && !state.excluded.has(course));
    const result = attempt(courses, data.fixed, data.limit, (course, assignment) => candidateSlots(data, course, assignment));
    state.attempts.push({ courses: courses.length, backtracks: result.backtracks,
      success: result.success, deadCourse: result.deadCourse });
    if (result.success) {
      state.assignment = result.assignment;
      state.assignmentOrder = result.order;
      break;
    }
    state.excluded.add(result.deadCourse);
  }
  return state;
}

function insertionReason(data, course, slot, assignment) {
  if (data.closed.has(slot)) return 'closed';
  if (data.slots[slot - 1].minutes < course.duration) return 'too_short';
  const student = unavailableStudent(data, course, slot);
  if (student !== undefined) return `unavailable ${student}`;
  const neighbours = [...course.neighbours.keys()].filter(neighbour => assignment.get(neighbour) === slot);
  neighbours.sort((first, second) => course.neighbours.get(second) - course.neighbours.get(first) || byId(first, second));
  if (neighbours.length > 0) return `conflict ${neighbours[0].id} shared ${course.neighbours.get(neighbours[0])}`;
  const orders = orderConflicts(data, course, slot, assignment).sort(byId);
  if (orders.length > 0) return `order ${orders[0].id}`;
  return 'rooms';
}

function insertExcluded(data, state) {
  for (const course of [...state.excluded].sort(byId)) {
    const slots = candidateSlots(data, course, state.assignment);
    if (slots.length === 0) {
      state.reasons.set(course, data.slots.map(slot => insertionReason(data, course, slot.number, state.assignment)));
      continue;
    }
    const before = penalty(data, state.assignment).value;
    let chosen = null;
    let best = null;
    for (const slot of slots) {
      const trial = new Map(state.assignment);
      trial.set(course, slot);
      const value = penalty(data, trial).value;
      if (best === null || value < best) {
        best = value;
        chosen = slot;
      }
    }
    state.assignment.set(course, chosen);
    state.insertions.push({ course, slot: chosen, increase: best - before });
  }
  state.unscheduled = data.courseList.filter(course => course.oversized
    || (state.excluded.has(course) && !state.assignment.has(course)));
  state.initial = penalty(data, state.assignment);
}

function exchangeSlots(data, state) {
  state.rounds = [];
  let current = state.initial;
  while (true) {
    const round = { pairs: 0, fixed: 0, invalid: 0, worse: 0, applied: 0, exchanges: [] };
    for (let i = 0; i < data.open.length; i += 1) {
      const h = data.open[i];
      for (let j = i + 1; j < data.open.length; j += 1) {
        const t = data.open[j];
        round.pairs += 1;
        if (data.fixedSlots.has(h) || data.fixedSlots.has(t)) {
          round.fixed += 1;
          continue;
        }
        const trial = new Map(state.assignment);
        const changed = [];
        for (const [course, slot] of state.assignment) {
          if (slot === h || slot === t) {
            trial.set(course, slot === h ? t : h);
            changed.push(course);
          }
        }
        if (changed.some(course => !suitable(data, course, trial.get(course))) || !ordersSatisfied(data, trial)) {
          round.invalid += 1;
          continue;
        }
        const next = penalty(data, trial);
        if (next.value >= current.value) {
          round.worse += 1;
          continue;
        }
        round.applied += 1;
        round.exchanges.push({ h, t, before: current.value, after: next.value });
        state.assignment = trial;
        current = next;
      }
    }
    state.rounds.push(round);
    if (round.applied === 0) break;
  }
  state.exchanged = current;
}

function swapKempeChains(data, state) {
  state.passes = [];
  let current = state.exchanged;
  while (true) {
    const pass = { candidates: 0, fixed: 0, invalid: 0, rooms: 0, worse: 0, applied: 0, swaps: [] };
    const courses = [...state.assignment.keys()].filter(course => !data.fixed.has(course)).sort(byId);
    for (const course of courses) {
      const h = state.assignment.get(course);
      for (const t of data.open) {
        if (t === h) continue;
        pass.candidates += 1;
        const chain = kempeChain(course, h, t, state.assignment);
        if (chain.some(member => data.fixed.has(member))) {
          pass.fixed += 1;
          continue;
        }
        const trial = new Map(state.assignment);
        const moves = chain.map(member => {
          const before = state.assignment.get(member);
          const after = before === h ? t : h;
          trial.set(member, after);
          return { course: member, before, after };
        });
        if (chain.some(member => !suitable(data, member, trial.get(member))) || !ordersSatisfied(data, trial)) {
          pass.invalid += 1;
          continue;
        }
        if (pack(coursesAt(trial, h), data.rooms) === null || pack(coursesAt(trial, t), data.rooms) === null) {
          pass.rooms += 1;
          continue;
        }
        const next = penalty(data, trial);
        if (next.value >= current.value) {
          pass.worse += 1;
          continue;
        }
        pass.applied += 1;
        pass.swaps.push({ course, h, t, moves, before: current.value, after: next.value });
        state.assignment = trial;
        current = next;
        break;
      }
    }
    state.passes.push(pass);
    if (pass.applied === 0) break;
  }
  state.final = current;
}

function assignRooms(data, state) {
  state.slotInfo = new Map();
  state.placements = new Map();
  state.roomTotals = new Map(data.rooms.map(room => [room, { slots: 0, exams: 0, seated: 0 }]));
  state.invigilators = 0;
  for (const slot of data.open) {
    const packing = pack(coursesAt(state.assignment, slot), data.rooms);
    const used = packing.rooms.filter(space => space.placements.length > 0);
    let invigilators = 0;
    for (const space of used) {
      const seated = space.room.capacity - space.remaining;
      invigilators += ceilRatio(seated, data.ratio);
      const counts = state.roomTotals.get(space.room);
      counts.slots += 1;
      counts.exams += space.placements.length;
      counts.seated += seated;
    }
    for (const [course, placement] of packing.placements) state.placements.set(course, placement);
    state.slotInfo.set(slot, { packing, used, invigilators,
      students: total(packing.order, course => course.students.length), capacity: total(used, space => space.room.capacity) });
    state.invigilators += invigilators;
  }
}

function increment(counts, key) {
  counts.set(key, (counts.get(key) ?? 0) + 1);
}

function analyseFinal(data, state) {
  state.contributions = new Map([...state.assignment.keys()].map(course => [course, 0]));
  state.dayCounts = Array.from({ length: data.days }, () => [0, 0, 0]);
  for (const { first, second, shared } of data.graph.edges) {
    if (!state.assignment.has(first) || !state.assignment.has(second)) continue;
    const x = state.assignment.get(first);
    const y = state.assignment.get(second);
    const kind = relation(data, x, y);
    if (kind < 0) continue;
    const value = data.weights[kind] * shared;
    state.contributions.set(first, state.contributions.get(first) + value);
    state.contributions.set(second, state.contributions.get(second) + value);
    state.dayCounts[data.slots[Math.min(x, y) - 1].day - 1][kind] += shared;
  }
  state.late = data.frontOrder.filter(course => state.assignment.has(course) && state.assignment.get(course) > data.deadline);
  for (const course of state.late) state.contributions.set(course, state.contributions.get(course) + data.weights[3]);
  state.studentInfo = new Map();
  state.histogram = new Map();
  state.gaps = new Map();
  state.dayloads = new Map();
  for (const [id, roster] of data.students) {
    const assigned = roster.filter(course => state.assignment.has(course))
      .sort((first, second) => state.assignment.get(first) - state.assignment.get(second));
    const unassigned = roster.filter(course => !state.assignment.has(course));
    const counts = [0, 0, 0];
    const pairs = [];
    const daily = Array(data.days).fill(0);
    for (let i = 0; i < assigned.length; i += 1) {
      const first = assigned[i];
      const firstSlot = state.assignment.get(first);
      daily[data.slots[firstSlot - 1].day - 1] += 1;
      if (i > 0) increment(state.gaps, firstSlot - state.assignment.get(assigned[i - 1]));
      for (let j = i + 1; j < assigned.length; j += 1) {
        const second = assigned[j];
        const kind = relation(data, firstSlot, state.assignment.get(second));
        if (kind >= 0) {
          counts[kind] += 1;
          pairs.push({ first, second, kind });
        }
      }
    }
    const value = counts[0] * data.weights[0] + counts[1] * data.weights[1] + counts[2] * data.weights[2];
    state.studentInfo.set(id, { id, assigned, unassigned, counts, pairs, penalty: value });
    increment(state.histogram, value);
    if (assigned.length > 0) increment(state.dayloads, Math.max(...daily));
  }
}

function timetableReport(data, state) {
  const empty = data.courseList.filter(course => course.empty).length;
  const lines = [`TIMETABLE days ${data.days} periods ${data.periods.length} open ${data.open.length} courses ${data.courses.size} `
    + `scheduled ${state.assignment.size} unscheduled ${state.unscheduled.length} empty ${empty}`];
  lines.push(tableLine('DAY', [...data.periods.map((_, index) => `P${index + 1}`), 'TOTAL'], 4, 10));
  for (let day = 1; day <= data.days; day += 1) {
    const columns = [];
    let exams = 0;
    let students = 0;
    for (const slot of data.slots.filter(candidate => candidate.day === day)) {
      if (data.closed.has(slot.number)) columns.push('closed');
      else {
        const info = state.slotInfo.get(slot.number);
        columns.push(`${info.packing.order.length}/${info.students}`);
        exams += info.packing.order.length;
        students += info.students;
      }
    }
    columns.push(`${exams}/${students}`);
    lines.push(tableLine(`D${day}`, columns, 4, 10));
  }
  for (const slot of data.slots) {
    const heading = `SLOT ${slot.number} ${slot.name} minutes ${slot.minutes}`;
    if (data.closed.has(slot.number)) {
      lines.push(heading + ' closed');
      continue;
    }
    const info = state.slotInfo.get(slot.number);
    lines.push(`${heading} exams ${info.packing.order.length} students ${info.students} `
      + `rooms ${info.used.length} seats ${info.capacity} invigilators ${info.invigilators}`);
    for (const course of info.packing.order) {
      const placement = info.packing.placements.get(course);
      const fixed = data.fixed.has(course) ? ' fixed' : '';
      lines.push(`  ${course.id} ${course.duration}min students ${course.students.length} room ${placement.room.id} `
        + `seats ${placement.first}-${placement.last}${fixed} ${course.name}`);
    }
  }
  for (const room of data.rooms) {
    const counts = state.roomTotals.get(room);
    lines.push(`ROOM ${room.id} capacity ${room.capacity} slots ${counts.slots} exams ${counts.exams} seated ${counts.seated} `
      + `utilization ${percentage(counts.seated, room.capacity * data.open.length)}`);
  }
  lines.push(`INVIGILATORS total ${state.invigilators} ratio ${data.ratio}`);
  return lines;
}

function roomsReport(data, state) {
  const lines = ['slot,room,course,students,first_seat,last_seat'];
  for (const slot of data.open) {
    for (const space of state.slotInfo.get(slot).packing.rooms) {
      for (const placement of space.placements) {
        lines.push(`${slotName(data, slot)},${space.room.id},${placement.course.id},${placement.course.students.length},${placement.first},${placement.last}`);
      }
    }
  }
  return lines;
}

function breakdown(score) {
  const [back, same, overnight, late] = score.counts;
  return `back_to_back ${back} same_day ${same} overnight ${overnight} front_load ${late} penalty ${score.value}`;
}

function penaltyReport(data, state) {
  const [back, same, overnight, front] = data.weights;
  const lines = [`WEIGHTS back_to_back ${back} same_day ${same} overnight ${overnight} front_load ${front}`,
    `FRONT_LOAD courses ${data.frontOrder.length} last_slot ${slotName(data, data.deadline)}`,
    `INITIAL ${breakdown(state.initial)}`];
  let serial = 0;
  state.rounds.forEach((round, index) => {
    lines.push(`ROUND ${index + 1} pairs ${round.pairs} fixed ${round.fixed} invalid ${round.invalid} worse ${round.worse} applied ${round.applied}`);
    for (const exchange of round.exchanges) {
      serial += 1;
      lines.push(`EXCHANGE ${serial} ${slotName(data, exchange.h)} ${slotName(data, exchange.t)} penalty ${exchange.before} -> ${exchange.after}`);
    }
  });
  lines.push(`EXCHANGED ${breakdown(state.exchanged)}`);
  serial = 0;
  state.passes.forEach((pass, index) => {
    lines.push(`PASS ${index + 1} candidates ${pass.candidates} fixed ${pass.fixed} invalid ${pass.invalid} `
      + `rooms ${pass.rooms} worse ${pass.worse} applied ${pass.applied}`);
    for (const swap of pass.swaps) {
      serial += 1;
      lines.push(`SWAP ${serial} ${swap.course.id} ${slotName(data, swap.h)} ${slotName(data, swap.t)} `
        + `chain ${swap.moves.length} penalty ${swap.before} -> ${swap.after}`);
      for (const move of swap.moves) {
        lines.push(`  MOVE ${move.course.id} ${slotName(data, move.before)} -> ${slotName(data, move.after)}`);
      }
    }
  });
  lines.push(`FINAL ${breakdown(state.final)}`, `SAVED ${state.initial.value - state.final.value}`);
  state.dayCounts.forEach((counts, index) => {
    lines.push(`DAY D${index + 1} back_to_back ${counts[0]} same_day ${counts[1]} overnight ${counts[2]}`);
  });
  for (const course of state.late) {
    lines.push(`LATE ${course.id} ${slotName(data, state.assignment.get(course))} students ${course.students.length}`);
  }
  const contributions = [...state.assignment.keys()].sort((first, second) =>
    state.contributions.get(second) - state.contributions.get(first) || byId(first, second)).slice(0, 10);
  for (const course of contributions) {
    if (state.contributions.get(course) > 0) {
      lines.push(`COURSE ${course.id} ${slotName(data, state.assignment.get(course))} penalty ${state.contributions.get(course)}`);
    }
  }
  for (const [label, counts] of [['HISTOGRAM', state.histogram], ['GAP', state.gaps], ['DAYLOAD', state.dayloads]]) {
    for (const [value, count] of [...counts].sort((first, second) => first[0] - second[0])) lines.push(`${label} ${value} ${count}`);
  }
  const worst = [...state.studentInfo.values()].sort((first, second) => second.penalty - first.penalty || byId(first, second)).slice(0, 5);
  for (const student of worst) {
    if (student.penalty > 0) {
      lines.push(`WORST ${student.id} penalty ${student.penalty} back_to_back ${student.counts[0]} `
        + `same_day ${student.counts[1]} overnight ${student.counts[2]}`);
    }
  }
  return lines;
}

function studentReport(data, state) {
  const lines = [];
  const classes = ['BACK_TO_BACK', 'SAME_DAY', 'OVERNIGHT'];
  for (const id of data.queries) {
    if (!data.students.has(id)) {
      lines.push(`STUDENT ${id} not found`);
      continue;
    }
    const info = state.studentInfo.get(id);
    lines.push(`STUDENT ${id} exams ${data.students.get(id).length} scheduled ${info.assigned.length} penalty ${info.penalty}`);
    for (const course of info.assigned) {
      const placement = state.placements.get(course);
      const seat = placement.first + course.students.indexOf(id);
      lines.push(`  ${slotName(data, state.assignment.get(course))} ${course.id} room ${placement.room.id} seat ${seat} ${course.name}`);
    }
    for (const course of info.unassigned) lines.push(`  UNSCHEDULED ${course.id} ${course.name}`);
    for (const pair of info.pairs) {
      lines.push(`  ${classes[pair.kind]} ${slotName(data, state.assignment.get(pair.first))} ${pair.first.id} `
        + `${slotName(data, state.assignment.get(pair.second))} ${pair.second.id}`);
    }
    for (const slot of [...(data.unavailable.get(id) ?? [])].sort((first, second) => first - second)) {
      lines.push(`  UNAVAILABLE ${slotName(data, slot)}`);
    }
  }
  return lines;
}

function courseReport(data, state) {
  const lines = ['course,status,slot,students,minutes,degree,penalty'];
  for (const course of data.courseList) {
    const assigned = state.assignment.has(course);
    const status = data.fixed.has(course) ? 'fixed' : assigned ? 'scheduled'
      : course.oversized ? 'too_large' : course.empty ? 'empty' : 'no_slot';
    const slot = assigned ? slotName(data, state.assignment.get(course)) : '-';
    lines.push(`${course.id},${status},${slot},${course.students.length},${course.duration},${course.neighbours.size},${state.contributions.get(course) ?? 0}`);
  }
  return lines;
}

function processingReport(data, state) {
  const lines = [`INPUT courses ${data.courses.size} enrolments ${data.enrolmentCount} rooms ${data.rooms.length} `
    + `students ${data.students.size} errors ${data.errors.length}`];
  for (const error of data.errors) lines.push(`ERROR ${error}`);
  const { vertices, edges } = data.graph;
  const density = vertices.length < 2 ? 0 : floorRatio(2000 * edges.length, vertices.length * (vertices.length - 1));
  lines.push(`GRAPH courses ${vertices.length} edges ${edges.length} shared ${total(edges, edge => edge.shared)} density ${density}`);
  for (const course of [...vertices].sort(degreeOrder).slice(0, 5)) {
    lines.push(`DEGREE ${course.id} neighbours ${course.neighbours.size} shared ${total(course.neighbours.values())} students ${course.students.length}`);
  }
  const groups = components(vertices);
  lines.push(`COMPONENTS ${groups.length}`);
  groups.forEach((group, index) => lines.push(`COMPONENT ${index + 1} size ${group.length} first ${group[0].id}`));
  const clique = greedyClique(data.schedulable);
  lines.push(['CLIQUE', 'size', clique.length, ...clique.map(course => course.id)].join(' '));
  let maximumLoad = 0;
  let maximumStudents = 0;
  for (const roster of data.students.values()) {
    if (roster.length > maximumLoad) {
      maximumLoad = roster.length;
      maximumStudents = 1;
    } else if (roster.length === maximumLoad) maximumStudents += 1;
  }
  lines.push(`LOAD max_exams ${maximumLoad} students ${maximumStudents}`);
  const demand = total(data.schedulable, course => course.students.length);
  const capacity = total(data.rooms, room => room.capacity);
  lines.push(`SEATS demand ${demand} capacity ${capacity} min_slots ${ceilRatio(demand, capacity)}`);
  lines.push(`HEURISTIC largest_degree slots ${greedyNumbering([...data.schedulable].sort(degreeOrder))}`,
    `HEURISTIC largest_enrolment slots ${greedyNumbering(packingOrder(data.schedulable))}`);
  const table = packingOrder(vertices).slice(0, 8);
  lines.push(tableLine('MATRIX', table.map(course => course.id), 9, 9));
  for (const course of table) {
    lines.push(tableLine(course.id, table.map(other => other === course ? '-' : course.neighbours.get(other) ?? 0), 9, 9));
  }
  for (const course of data.courseList) if (course.empty) lines.push(`EMPTY ${course.id}`);
  for (const course of data.courseList) {
    if (course.oversized) lines.push(`TOO_LARGE ${course.id} students ${course.students.length} largest_room ${data.largestRoom}`);
  }
  for (const slot of [...data.closed].sort((first, second) => first - second)) lines.push(`CLOSED ${slotName(data, slot)}`);
  for (const course of [...data.fixed.keys()].sort(byId)) lines.push(`FIXED ${course.id} ${slotName(data, data.fixed.get(course))}`);
  for (const [after, before] of data.orders) lines.push(`AFTER ${after.id} ${before.id}`);
  state.attempts.forEach((result, index) => {
    const verdict = result.success ? 'success' : `failed ${result.deadCourse.id}`;
    lines.push(`ATTEMPT ${index + 1} courses ${result.courses} backtracks ${result.backtracks} ${verdict}`);
  });
  state.assignmentOrder.forEach((entry, index) => {
    lines.push(`ORDER ${index + 1} ${entry.course.id} ${slotName(data, entry.slot)} saturation ${entry.saturation} degree ${entry.course.neighbours.size}`);
  });
  for (const insertion of state.insertions) {
    lines.push(`INSERTED ${insertion.course.id} ${slotName(data, insertion.slot)} penalty ${insertion.increase}`);
  }
  for (const course of state.unscheduled) {
    const reason = course.oversized ? 'too_large' : 'no_slot';
    lines.push(`UNSCHEDULED ${course.id} reason ${reason} students ${course.students.length}`);
    if (!course.oversized) {
      state.reasons.get(course).forEach((message, index) => lines.push(`  ${slotName(data, index + 1)} ${message}`));
    }
  }
  const slotsUsed = [...state.slotInfo.values()].filter(info => info.packing.order.length > 0).length;
  lines.push(`SUMMARY scheduled ${state.assignment.size} unscheduled ${state.unscheduled.length} slots_used ${slotsUsed} penalty ${state.final.value}`);
  return lines;
}

function main() {
  const data = readInput();
  const state = buildTimetable(data);
  insertExcluded(data, state);
  exchangeSlots(data, state);
  swapKempeChains(data, state);
  assignRooms(data, state);
  analyseFinal(data, state);
  writeReports({
    'timetable.txt': timetableReport(data, state),
    'rooms.csv': roomsReport(data, state),
    'penalties.txt': penaltyReport(data, state),
    'student_schedules.txt': studentReport(data, state),
    'course_status.csv': courseReport(data, state),
    'report.txt': processingReport(data, state),
  });
}

if (require.main === module) main();
