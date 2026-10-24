const { byId } = require('./conflict_graph');

function saturation(course, assignment) {
  const slots = new Set();
  for (const neighbour of course.neighbours.keys()) {
    if (assignment.has(neighbour)) slots.add(assignment.get(neighbour));
  }
  return slots.size;
}

function attempt(courses, fixed, limit, candidateSlots) {
  const assignment = new Map(fixed);
  const order = [];
  let backtracks = 0;
  let deadCourse = null;
  let aborted = false;
  function search() {
    let chosen = null;
    let chosenSaturation = -1;
    for (const course of courses) {
      if (assignment.has(course)) continue;
      const value = saturation(course, assignment);
      if (chosen === null || value > chosenSaturation
          || (value === chosenSaturation && (course.neighbours.size > chosen.neighbours.size
            || (course.neighbours.size === chosen.neighbours.size && byId(course, chosen) < 0)))) {
        chosen = course;
        chosenSaturation = value;
      }
    }
    if (chosen === null) return true;
    const slots = candidateSlots(chosen, assignment);
    for (const slot of slots) {
      assignment.set(chosen, slot);
      order.push({ course: chosen, slot, saturation: chosenSaturation });
      if (search()) return true;
      order.pop();
      assignment.delete(chosen);
      if (aborted) return false;
    }
    backtracks += 1;
    deadCourse = chosen;
    if (backtracks > limit) aborted = true;
    return false;
  }
  const success = search();
  return { success, assignment, order, backtracks, deadCourse };
}

function greedyNumbering(courses) {
  const assigned = new Map();
  let maximum = 0;
  for (const course of courses) {
    const used = new Set();
    for (const neighbour of course.neighbours.keys()) {
      if (assigned.has(neighbour)) used.add(assigned.get(neighbour));
    }
    let number = 1;
    while (used.has(number)) number += 1;
    assigned.set(course, number);
    maximum = Math.max(maximum, number);
  }
  return maximum;
}

module.exports = { attempt, greedyNumbering };
