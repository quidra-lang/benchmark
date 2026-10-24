const fs = require('node:fs');

function csvLines(path) {
  return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n').slice(1);
}

function readEnrolment(errors) {
  const courses = new Map();
  csvLines('input/courses.csv').forEach((line, index) => {
    const [id, duration, name] = line.split(',');
    if (courses.has(id)) {
      errors.push(`courses.csv line ${index + 2}: duplicate course ${id}`);
    } else {
      courses.set(id, { id, duration: Number(duration), name, students: [] });
    }
  });
  const students = new Map();
  let accepted = 0;
  csvLines('input/enrolments.csv').forEach((line, index) => {
    const [student, id] = line.split(',');
    const course = courses.get(id);
    let message = null;
    if (course === undefined) message = `unknown course ${id}`;
    else if (students.get(student)?.includes(course)) message = `duplicate enrolment ${student} ${id}`;
    if (message !== null) {
      errors.push(`enrolments.csv line ${index + 2}: ${message}`);
      return;
    }
    if (!students.has(student)) students.set(student, []);
    students.get(student).push(course);
    course.students.push(student);
    accepted += 1;
  });
  for (const course of courses.values()) course.students.sort();
  for (const roster of students.values()) {
    roster.sort((first, second) => first.id < second.id ? -1 : first.id > second.id ? 1 : 0);
  }
  return { courses, students, enrolmentCount: accepted };
}

module.exports = { readEnrolment };
