import { readFileSync } from "node:fs";


const DAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];
const POINTS = {A: 4, B: 3, C: 2, D: 1, F: 0};
const lex = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const time = (m) => String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0");
const overlap = (a, b) => a.day === b.day && a.start < b.end && b.start < a.end;
const weekly = (c) => c.slots.reduce((v, s) => v + s.end - s.start, 0);
const earned = (s) => s.grades.filter(r => r.grade !== "F").reduce((v, r) => v + r.credits, 0);
const passed = (s, code) => s.grades.find(r => r.code === code && ["A", "B", "C"].includes(r.grade));
const rate = (k, m) => m ? Math.floor(k * 100 / m) + "%" : "n/a";
class CommandError extends Error {}

function gpa(s) {
  if (!s.grades.length) return "n/a";
  const p = s.grades.reduce((v, r) => v + POINTS[r.grade] * r.credits, 0);
  const c = s.grades.reduce((v, r) => v + r.credits, 0);
  const v = Math.floor((200 * p + c) / (2 * c));
  return Math.floor(v / 100) + "." + String(v % 100).padStart(2, "0");
}

function combine(kind, children) {
  const flat = children.flatMap(c => c.kind === kind ? c.children : [c]);
  return flat.length === 1 ? flat[0] : {kind, word: "", children: flat};
}

function canonical(node) {
  if (node === null) return "-";
  if (node.kind === "leaf") return node.word;
  return node.children.map(c => node.kind === "and" && c.kind === "or" ? "(" + canonical(c) + ")" : canonical(c)).join(node.kind === "and" ? "&" : "|");
}

function contains(node, code) {
  return node !== null && (node.kind === "leaf" ? node.word === code : node.children.some(c => contains(c, code)));
}

function satisfied(node, s) {
  if (node === null) return true;
  if (node.kind === "leaf") return /^Y[1-9]$/.test(node.word) ? s.year >= Number(node.word[1]) : passed(s, node.word) !== undefined;
  return node.kind === "and" ? node.children.every(c => satisfied(c, s)) : node.children.some(c => satisfied(c, s));
}

function prerequisite(code, text) {
  if (text === "-") return null;
  const tokens = text.match(/[A-Z0-9]+|[&|()]/g) ?? [];
  const invalid = () => { throw new CommandError("invalid prereq " + code); };
  for (const t of tokens) {
    if (!["&", "|", "(", ")"].includes(t) && !/^(?:[A-Z]{2,4}[0-9]{3}|Y[1-9])$/.test(t)) invalid();
  }
  let position = 0;
  const factor = () => {
    const token = tokens[position++];
    if (token === "(") {
      const node = expression();
      if (tokens[position++] !== ")") invalid();
      return node;
    }
    if (token === undefined || ["&", "|", ")"].includes(token)) return invalid();
    return {kind: "leaf", word: token, children: []};
  };
  const term = () => {
    const nodes = [factor()];
    while (tokens[position] === "&") {
      position++;
      nodes.push(factor());
    }
    return combine("and", nodes);
  };
  const expression = () => {
    const nodes = [term()];
    while (tokens[position] === "|") {
      position++;
      nodes.push(term());
    }
    return combine("or", nodes);
  };
  const node = expression();
  if (position !== tokens.length) invalid();
  if (contains(node, code)) throw new CommandError("self prereq " + code);
  return node;
}

function slots(text) {
  if (text === "-") return [];
  const result = text.split(",").map(raw => {
    const day = raw.slice(0, 2);
    const sh = Number(raw.slice(2, 4));
    const sm = Number(raw.slice(4, 6));
    const eh = Number(raw.slice(7, 9));
    const em = Number(raw.slice(9, 11));
    const start = sh * 60 + sm;
    const end = eh * 60 + em;
    if (!DAYS.includes(day) || sh > 23 || sm > 59 || eh > 23 || em > 59 || start >= end) throw new CommandError("invalid slot " + raw);
    return {day, start, end, raw};
  });
  for (let i = 0; i < result.length; i++) {
    for (let j = i + 1; j < result.length; j++) {
      if (overlap(result[i], result[j])) throw new CommandError("overlapping slots " + result[i].raw + " " + result[j].raw);
    }
  }
  return result;
}

class Registrar {
  courses = new Map();
  students = new Map();
  commandNumber = 0;
  output = [];

  emit(indent, ...parts) {
    this.output.push(" ".repeat(indent) + parts.join(" "));
  }

  student(id) {
    const s = this.students.get(id);
    if (!s) throw new CommandError("unknown student " + id);
    return s;
  }

  course(code) {
    const c = this.courses.get(code);
    if (!c) throw new CommandError("unknown course " + code);
    return c;
  }

  sortedCourses() {
    return [...this.courses.values()].sort((a, b) => lex(a.code, b.code));
  }

  taking(s, except = null) {
    return [...s.taking].filter(c => c !== except).sort().map(code => this.courses.get(code));
  }

  credits(s, except = null) {
    return this.taking(s, except).reduce((v, c) => v + c.credits, 0);
  }

  waitlists(s) {
    return this.sortedCourses().filter(c => c.waiting.includes(s.id));
  }

  conflict(s, c, except = null) {
    return this.taking(s, except).find(other => other.slots.some(a => c.slots.some(b => overlap(a, b))));
  }

  eligible(s, c, except = null) {
    if (!c.open) return {word: "course closed", extra: []};
    if (c.enrolled.has(s.id)) return {word: "already enrolled", extra: []};
    if (c.waiting.includes(s.id)) return {word: "already waitlisted", extra: []};
    const grade = passed(s, c.code);
    if (grade) return {word: "already completed", extra: [grade.grade]};
    if (!satisfied(c.prerequisite, s)) return {word: "prereq not met", extra: []};
    const conflicting = this.conflict(s, c, except);
    if (conflicting) return {word: "time conflict", extra: [conflicting.code]};
    const credits = this.credits(s, except) + c.credits;
    if (credits > s.limit) return {word: "credit limit", extra: [credits, s.limit]};
    return {word: "OK", extra: []};
  }

  judgment(s, c) {
    const result = this.eligible(s, c);
    if (result.word !== "OK") return result;
    if (c.enrolled.size < c.capacity) return {word: "enroll", extra: []};
    if (this.waitlists(s).length >= 3) return {word: "waitlist limit", extra: []};
    return {word: "waitlist", extra: [1 + c.waiting.filter(id => this.students.get(id).year >= s.year).length]};
  }

  reject(s, c, result) {
    throw new CommandError([result.word, s.id, c.code, ...result.extra].join(" "));
  }

  history(s, event) {
    s.history.push({command: this.commandNumber, event});
  }

  enroll(s, c) {
    c.enrolled.add(s.id);
    s.taking.add(c.code);
  }

  remove(s, c) {
    c.enrolled.delete(s.id);
    s.taking.delete(c.code);
  }

  promote() {
    for (const c of this.sortedCourses()) {
      if (!c.open) continue;
      while (c.enrolled.size < c.capacity) {
        const index = c.waiting.findIndex(id => {
          const s = this.students.get(id);
          return !this.conflict(s, c) && this.credits(s) + c.credits <= s.limit;
        });
        if (index < 0) break;
        const [id] = c.waiting.splice(index, 1);
        const s = this.students.get(id);
        this.enroll(s, c);
        this.history(s, "promote " + c.code);
        this.enrollmentLine("PROMOTE", s, c, 2);
      }
    }
  }

  enrollmentLine(label, s, c, indent = 0) {
    this.emit(indent, label, s.id, c.code, "enrolled", c.enrolled.size + "/" + c.capacity, "credits", this.credits(s) + "/" + s.limit);
  }

  schedule(s) {
    const taking = this.taking(s);
    this.emit(0, "SCHEDULE", s.id, "courses", taking.length, "credits", this.credits(s), "weekly", time(taking.reduce((v, c) => v + weekly(c), 0)));
    for (const day of DAYS) {
      const meetings = taking.flatMap(c => c.slots.filter(slot => slot.day === day).map(slot => ({code: c.code, slot})));
      meetings.sort((a, b) => a.slot.start - b.slot.start);
      if (meetings.length) this.emit(2, day, ...meetings.flatMap(m => [time(m.slot.start) + "-" + time(m.slot.end), m.code]));
    }
    const tba = taking.filter(c => !c.slots.length).map(c => c.code);
    if (tba.length) this.emit(2, "TBA", ...tba);
  }

  command(cmd, a) {
    switch (cmd) {
      case "COURSE": {
        if (this.courses.has(a[0])) throw new CommandError("duplicate course " + a[0]);
        const meetings = slots(a[3]);
        const tree = prerequisite(a[0], a[4]);
        const c = {code: a[0], credits: Number(a[1]), capacity: Number(a[2]), slots: meetings,
          prerequisite: tree, open: true, enrolled: new Set(), waiting: []};
        this.courses.set(c.code, c);
        this.emit(0, "COURSE", c.code, "credits", c.credits, "capacity", c.capacity, "meetings", meetings.length, "weekly", time(weekly(c)), "prereq", canonical(tree));
        break;
      }
      case "STUDENT": {
        if (this.students.has(a[0])) throw new CommandError("duplicate student " + a[0]);
        const grades = [];
        const seen = new Set();
        for (const token of a[3] === "-" ? [] : a[3].split(",")) {
          const [code, grade, credits] = token.split(":");
          if (!Object.hasOwn(POINTS, grade)) throw new CommandError("invalid grade " + a[0] + " " + code + " " + grade);
          if (seen.has(code)) throw new CommandError("duplicate record " + a[0] + " " + code);
          seen.add(code);
          grades.push({code, grade, credits: Number(credits)});
        }
        const s = {id: a[0], year: Number(a[1]), limit: Number(a[2]), grades, taking: new Set(), history: []};
        this.students.set(s.id, s);
        this.emit(0, "STUDENT", s.id, "year", s.year, "limit", s.limit, "records", grades.length, "earned", earned(s), "gpa", gpa(s));
        break;
      }
      case "ENROLL":
      case "CHECK": {
        const s = this.student(a[0]);
        const c = this.course(a[1]);
        const result = this.judgment(s, c);
        if (cmd === "CHECK") this.emit(0, "CHECK", s.id, c.code, result.word, ...result.extra);
        else if (result.word === "enroll") {
          this.enroll(s, c);
          this.history(s, "enroll " + c.code);
          this.enrollmentLine("ENROLL", s, c);
        } else if (result.word === "waitlist") {
          const position = Number(result.extra[0]);
          c.waiting.splice(position - 1, 0, s.id);
          this.history(s, "waitlist " + c.code + " " + position);
          this.emit(0, "ENROLL", s.id, c.code, "waitlist", position);
        } else this.reject(s, c, result);
        break;
      }
      case "OPTIONS": {
        const s = this.student(a[0]);
        this.emit(0, "OPTIONS", s.id, "courses", this.courses.size);
        for (const c of this.sortedCourses()) {
          const result = this.judgment(s, c);
          this.emit(2, c.code, result.word, ...result.extra);
        }
        break;
      }
      case "DROP": {
        const s = this.student(a[0]);
        const c = this.course(a[1]);
        const position = c.waiting.indexOf(s.id);
        if (c.enrolled.has(s.id)) {
          this.remove(s, c);
          this.history(s, "drop " + c.code);
          this.enrollmentLine("DROP", s, c);
        } else if (position >= 0) {
          c.waiting.splice(position, 1);
          this.history(s, "drop " + c.code + " waitlist");
          this.emit(0, "DROP", s.id, c.code, "waitlist", "removed");
        } else throw new CommandError("not registered " + s.id + " " + c.code);
        this.promote();
        break;
      }
      case "SWAP": {
        const s = this.student(a[0]);
        const old = this.course(a[1]);
        const next = this.course(a[2]);
        if (!old.enrolled.has(s.id)) throw new CommandError("not enrolled " + s.id + " " + old.code);
        if (old === next) throw new CommandError("same course " + old.code);
        const result = this.eligible(s, next, old.code);
        if (result.word !== "OK") this.reject(s, next, result);
        if (next.enrolled.size >= next.capacity) throw new CommandError("course full " + next.code);
        this.remove(s, old);
        this.enroll(s, next);
        this.history(s, "swap " + old.code + " " + next.code);
        this.emit(0, "SWAP", s.id, old.code, "->", next.code, "credits", this.credits(s) + "/" + s.limit);
        this.promote();
        break;
      }
      case "CLOSE":
      case "OPEN": {
        const c = this.course(a[0]);
        if (c.open === (cmd === "OPEN")) throw new CommandError("already " + cmd.toLowerCase() + (cmd === "CLOSE" ? "d " : " ") + c.code);
        c.open = cmd === "OPEN";
        this.emit(0, cmd, c.code, "enrolled", c.enrolled.size + "/" + c.capacity, "waitlist", c.waiting.length);
        if (cmd === "OPEN") this.promote();
        break;
      }
      case "CAPACITY": {
        const c = this.course(a[0]);
        const capacity = Number(a[1]);
        if (capacity < c.enrolled.size) throw new CommandError("capacity below enrollment " + c.code + " " + c.enrolled.size);
        const old = c.capacity;
        c.capacity = capacity;
        this.emit(0, "CAPACITY", c.code, old, "->", capacity);
        this.promote();
        break;
      }
      case "LIMIT": {
        const s = this.student(a[0]);
        const limit = Number(a[1]);
        const credits = this.credits(s);
        if (limit < credits) throw new CommandError("limit below enrolled " + s.id + " " + credits);
        const old = s.limit;
        s.limit = limit;
        this.emit(0, "LIMIT", s.id, old, "->", limit);
        this.promote();
        break;
      }
      case "PREREQ": {
        const c = this.course(a[0]);
        const tree = prerequisite(c.code, a[1]);
        c.prerequisite = tree;
        this.emit(0, "PREREQ", c.code, canonical(tree));
        c.waiting = c.waiting.filter(id => {
          const s = this.students.get(id);
          if (satisfied(tree, s)) return true;
          this.history(s, "unlist " + c.code);
          this.emit(2, "UNLIST", s.id, c.code);
          return false;
        });
        break;
      }
      case "CANCEL": {
        const c = this.course(a[0]);
        this.emit(0, "CANCEL", c.code, "enrolled", c.enrolled.size, "waitlist", c.waiting.length);
        for (const id of c.enrolled) {
          const s = this.students.get(id);
          s.taking.delete(c.code);
          this.history(s, "cancel " + c.code);
        }
        for (const id of c.waiting) this.history(this.students.get(id), "cancel " + c.code + " waitlist");
        this.courses.delete(c.code);
        this.promote();
        break;
      }
      case "ROSTER": {
        const c = this.course(a[0]);
        this.emit(0, "ROSTER", c.code, c.open ? "open" : "closed", "enrolled", c.enrolled.size + "/" + c.capacity, "waitlist", c.waiting.length);
        for (const id of [...c.enrolled].sort()) this.emit(2, "enrolled", id, "year", this.students.get(id).year);
        c.waiting.forEach((id, i) => this.emit(2, "waitlist", i + 1, id, "year", this.students.get(id).year));
        break;
      }
      case "SCHEDULE":
        this.schedule(this.student(a[0]));
        break;
      case "FREE": {
        const s = this.student(a[0]);
        if (!DAYS.includes(a[1])) throw new CommandError("invalid day " + a[1]);
        const meetings = this.taking(s).flatMap(c => c.slots).filter(t => t.day === a[1] && t.start < 1320 && t.end > 480).sort((a, b) => a.start - b.start);
        const ranges = [];
        let cursor = 480;
        for (const slot of meetings) {
          const start = Math.max(slot.start, 480);
          if (start > cursor) ranges.push([cursor, start]);
          cursor = Math.max(cursor, Math.min(slot.end, 1320));
        }
        if (cursor < 1320) ranges.push([cursor, 1320]);
        this.emit(0, "FREE", s.id, a[1], "total", time(ranges.reduce((v, [a, b]) => v + b - a, 0)),
          ...ranges.map(([a, b]) => time(a) + "-" + time(b)));
        break;
      }
      case "INFO": {
        const c = this.course(a[0]);
        this.emit(0, "INFO", c.code, c.open ? "open" : "closed", "credits", c.credits, "capacity", c.capacity, "prereq", canonical(c.prerequisite));
        for (const slot of c.slots.toSorted((a, b) => DAYS.indexOf(a.day) - DAYS.indexOf(b.day) || a.start - b.start)) this.emit(2, "meet", slot.day, time(slot.start) + "-" + time(slot.end));
        if (!c.slots.length) this.emit(2, "meet", "TBA");
        const required = this.sortedCourses().filter(other => contains(other.prerequisite, c.code)).map(other => other.code);
        this.emit(2, "required", "by", ...(required.length ? required : ["none"]));
        break;
      }
      case "AUDIT": {
        const s = this.student(a[0]);
        this.emit(0, "AUDIT", s.id, "year", s.year, "limit", s.limit);
        for (const r of s.grades.toSorted((a, b) => lex(a.code, b.code))) this.emit(2, "record", r.code, r.grade, r.credits);
        this.emit(2, "earned", earned(s), "gpa", gpa(s));
        for (const c of this.taking(s)) this.emit(2, "enrolled", c.code, c.credits);
        this.emit(2, "credits", this.credits(s), "remaining", s.limit - this.credits(s));
        for (const c of this.waitlists(s)) this.emit(2, "waitlist", c.code, c.waiting.indexOf(s.id) + 1);
        break;
      }
      case "HISTORY": {
        const s = this.student(a[0]);
        this.emit(0, "HISTORY", s.id, "events", s.history.length);
        for (const row of s.history) this.emit(2, row.command, row.event);
        break;
      }
      case "STUDENTS":
        this.emit(0, "STUDENTS", this.students.size);
        for (const s of [...this.students.values()].sort((a, b) => lex(a.id, b.id))) this.emit(2, s.id, "year", s.year,
          "credits", this.credits(s) + "/" + s.limit, "courses", s.taking.size, "waitlists", this.waitlists(s).length);
        break;
      case "REPORT": {
        const courses = this.sortedCourses();
        const enrolled = courses.reduce((v, c) => v + c.enrolled.size, 0);
        const capacity = courses.reduce((v, c) => v + c.capacity, 0);
        const waiting = courses.reduce((v, c) => v + c.waiting.length, 0);
        this.emit(0, "REPORT", "courses", courses.length, "enrolled", enrolled + "/" + capacity, "rate", rate(enrolled, capacity), "waitlisted", waiting);
        for (const c of courses) this.emit(2, c.code, c.open ? "open" : "closed", c.enrolled.size + "/" + c.capacity, rate(c.enrolled.size, c.capacity), "waitlist", c.waiting.length);
        const departments = Map.groupBy(courses, c => c.code.slice(0, -3));
        for (const department of [...departments.keys()].sort()) {
          const group = departments.get(department);
          const k = group.reduce((v, c) => v + c.enrolled.size, 0);
          const m = group.reduce((v, c) => v + c.capacity, 0);
          this.emit(2, "dept", department, "courses", group.length, "enrolled", k + "/" + m,
            "rate", rate(k, m), "waitlisted", group.reduce((v, c) => v + c.waiting.length, 0));
        }
        break;
      }
    }
  }

  execute(line) {
    this.commandNumber++;
    const [cmd, ...args] = line.split(" ");
    try {
      this.command(cmd, args);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.emit(0, "ERROR", error.message);
    }
  }
}

const lines = readFileSync(0, "utf8").trimEnd().split("\n");
const registrar = new Registrar();
for (let i = 1; i <= Number(lines[0]); i++) registrar.execute(lines[i]);
process.stdout.write(registrar.output.join("\n") + "\n");
