const fs = require('node:fs');

function packingOrder(courses) {
  return [...courses].sort((first, second) => second.students.length - first.students.length
    || (first.id < second.id ? -1 : first.id > second.id ? 1 : 0));
}

function readRooms(errors) {
  const rooms = new Map();
  const lines = fs.readFileSync('input/rooms.csv', 'ascii').slice(0, -1).split('\n').slice(1);
  lines.forEach((line, index) => {
    const [id, value] = line.split(',');
    const capacity = Number(value);
    let message = null;
    if (rooms.has(id)) message = `duplicate room ${id}`;
    else if (capacity < 1) message = `bad capacity ${capacity}`;
    if (message !== null) errors.push(`rooms.csv line ${index + 2}: ${message}`);
    else rooms.set(id, { id, capacity });
  });
  return [...rooms.values()].sort((first, second) => first.capacity - second.capacity
    || (first.id < second.id ? -1 : first.id > second.id ? 1 : 0));
}

function pack(courses, rooms) {
  const order = packingOrder(courses);
  const spaces = rooms.map(room => ({ room, remaining: room.capacity, duration: null, placements: [] }));
  const placements = new Map();
  for (const course of order) {
    const space = spaces.find(candidate => candidate.remaining >= course.students.length
      && (candidate.duration === null || candidate.duration === course.duration));
    if (space === undefined) return null;
    const first = space.room.capacity - space.remaining + 1;
    const placement = { course, room: space.room, first, last: first + course.students.length - 1 };
    space.remaining -= course.students.length;
    space.duration = course.duration;
    space.placements.push(placement);
    placements.set(course, placement);
  }
  return { order, rooms: spaces, placements };
}

module.exports = { readRooms, packingOrder, pack };
