import { readFileSync } from "node:fs";


class CommandError extends Error {}
const sum = (v) => v.reduce((a, b) => a + b, 0);
const lex = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const halfUp = (n, d) => Math.floor((2 * n + d) / (2 * d));
const halfAway = (n, d) => n < 0 ? -halfUp(-n, d) : halfUp(n, d);
const decimal = (n, sign = "-") => (n < 0 ? sign : "") + Math.floor(Math.abs(n) / 10) + "." + Math.abs(n) % 10;
const indexText = (n) => n === null ? "none" : decimal(n, "+");
const hcpText = (n) => n === null ? "none" : n < 0 ? "+" + -n : String(n);
const hundredths = (n) => Math.floor(n / 100) + "." + String(n % 100).padStart(2, "0");
const averageText = (total, count) => count ? hundredths(Math.floor(total * 100 / count)) : "-";
const status = (n) => n === 0 ? "AS" : Math.abs(n) + (n > 0 ? " UP" : " DN");

function allocation(h, si) {
  const q = Math.floor(Math.abs(h) / 18);
  const r = Math.abs(h) % 18;
  return si.map(i => h >= 0 ? q + Number(i <= r) : -q - Number(i >= 19 - r));
}

function handicap(index, c, t) {
  return halfUp(index * t.slope + 113 * (t.rating - 10 * c.par), 1130);
}

function ranked(ids, values, larger = false) {
  const keys = {};
  for (const id of ids) {
    const v = values[id];
    keys[id] = [sum(v), sum(v.slice(9)), sum(v.slice(12)), sum(v.slice(15)), v[17]];
  }
  return [...ids].sort((a, b) => {
    for (let i = 0; i < 5; i++) {
      const difference = keys[a][i] - keys[b][i];
      if (difference) return larger ? -difference : difference;
    }
    return lex(a, b);
  });
}

class Player {
  id;
  name;
  index;
  rounds = [];
  records = [];
  calculation = null;

  constructor(id, name, index) {
    this.id = id;
    this.name = name;
    this.index = index;
  }

  low(day) {
    const records = this.records.filter(([d]) => d >= day - 365 && d < day);
    records.sort((a, b) => a[1] - b[1] || a[0] - b[0]);
    return records.length ? records[0] : null;
  }

  eligible() {
    const rows = [];
    let reduction = 0;
    for (let i = this.rounds.length - 1; i >= Math.max(0, this.rounds.length - 20); i--) {
      const round = this.rounds[i];
      reduction += round.exceptional;
      rows.push({number: i + 1, round, adjusted: round.diff - reduction});
    }
    return rows.reverse();
  }

  counting(rows) {
    const n = rows.length;
    if (n < 3) return {selected: [], adjustment: 0};
    const k = n <= 5 ? 1 : n <= 8 ? 2 : n <= 11 ? 3 : n <= 14 ? 4 : n <= 16 ? 5 : n <= 18 ? 6 : n === 19 ? 7 : 8;
    const adjustment = n === 3 ? -20 : n === 4 || n === 6 ? -10 : 0;
    const selected = [...rows].sort((a, b) => a.adjusted - b.adjusted || b.number - a.number).slice(0, k);
    return {selected, adjustment};
  }

  update(day) {
    const {selected, adjustment} = this.counting(this.eligible());
    if (!selected.length) {
      this.calculation = null;
      return;
    }
    const average = halfAway(sum(selected.map(r => r.adjusted)), selected.length);
    let candidate = average + adjustment;
    const record = this.low(day);
    const low = record === null ? null : record[1];
    let soft = false;
    let hard = false;
    let maximum = false;
    if (low !== null) {
      if (candidate - low > 30) {
        candidate = low + 30 + Math.floor((candidate - low - 30) / 2);
        soft = true;
      }
      if (candidate - low > 50) {
        candidate = low + 50;
        hard = true;
      }
    }
    if (candidate > 540) {
      candidate = 540;
      maximum = true;
    }
    this.index = candidate;
    this.calculation = {k: selected.length, average, adjustment, low, hard, soft, maximum};
  }
}

class GolfRound {
  course;
  tee;
  day;
  scores;
  previousIndex;
  previousRecords;
  previousCalculation;
  hcp;
  adjusted;
  ags;
  diff;
  exceptional;

  constructor(p, c, t, day, scores) {
    this.course = c;
    this.tee = t;
    this.day = day;
    this.scores = scores;
    this.previousIndex = p.index;
    this.previousRecords = p.records.length;
    this.previousCalculation = p.calculation;
    this.hcp = p.index === null ? null : handicap(p.index, c, t);
    const strokes = allocation(this.hcp ?? 0, c.si);
    this.adjusted = scores.map((score, h) => {
      const limit = this.hcp === null ? c.pars[h] + 5 : c.pars[h] + 2 + strokes[h];
      return score === "-" ? c.pars[h] + strokes[h] : score === "X" ? limit : Math.min(score, limit);
    });
    this.ags = sum(this.adjusted);
    this.diff = halfAway(113 * (10 * this.ags - t.rating), t.slope);
    this.exceptional = p.index !== null && p.index - this.diff >= 70 ? p.index - this.diff >= 100 ? 20 : 10 : 0;
  }

  nets(strokes) {
    return this.scores.map((s, h) => typeof s === "number" ? s - strokes[h] : null);
  }

  points(nets) {
    return nets.map((n, h) => n === null ? 0 : Math.max(0, this.course.pars[h] + 2 - n));
  }

  complete() {
    return this.scores.every(s => typeof s === "number");
  }
}

class GolfScorer {
  courses = new Map();
  players = new Map();
  events = new Map();
  output = [];

  emit(...parts) {
    this.output.push(parts.join(" "));
  }

  player(id) {
    const p = this.players.get(id);
    if (!p) throw new CommandError("unknown player");
    return p;
  }

  course(id) {
    const c = this.courses.get(id);
    if (!c) throw new CommandError("unknown course");
    return c;
  }

  tee(cid, tid) {
    const c = this.course(cid);
    const t = c.tees.get(tid);
    if (!t) throw new CommandError("unknown tee");
    return [c, t];
  }

  eventData(e) {
    const rounds = {};
    const hcp = {};
    const nets = {};
    const points = {};
    for (const p of e.players) {
      const r = p.rounds.find(r => r.course === e.course && r.tee === e.tee && r.day === e.day);
      if (!r) throw new CommandError("missing round");
      if (r.hcp === null) throw new CommandError("no index");
      rounds[p.id] = r;
      hcp[p.id] = halfUp(r.hcp * e.allowance, 100);
    }
    const minimum = ["MATCH", "NASSAU", "FOURBALL"].includes(e.form) ? Math.min(...Object.values(hcp)) : 0;
    for (const p of e.players) {
      nets[p.id] = rounds[p.id].nets(allocation(hcp[p.id] - minimum, e.course.si));
      points[p.id] = rounds[p.id].points(nets[p.id]);
    }
    return {rounds, hcp, nets, points};
  }

  eventRanking(e, d) {
    const ids = e.players.map(p => p.id);
    if (e.form === "STROKE") {
      const complete = ids.filter(id => d.rounds[id].complete());
      const values = {};
      for (const id of complete) values[id] = d.nets[id];
      return {order: ranked(complete, values), values};
    }
    if (e.form === "STABLEFORD") return {order: ranked(ids, d.points, true), values: d.points};
    const values = {};
    for (const id of ids) values[id] = d.nets[id].map((n, h) => n === null || n > e.course.pars[h] ? -1 : n < e.course.pars[h] ? 1 : 0);
    return {order: ranked(ids, values, true), values};
  }

  individual(e, d) {
    const {order, values} = this.eventRanking(e, d);
    for (let rank = 0; rank < order.length; rank++) {
      const id = order[rank];
      if (e.form === "STROKE") this.emit(rank + 1, id, "net", sum(values[id]), "gross", sum(d.rounds[id].scores), "hcp", hcpText(d.hcp[id]));
      else if (e.form === "STABLEFORD") this.emit(rank + 1, id, "points", sum(values[id]), "hcp", hcpText(d.hcp[id]));
      else this.emit(rank + 1, id, status(sum(values[id])), "hcp", hcpText(d.hcp[id]));
    }
    if (e.form === "STROKE") {
      for (const id of e.players.map(p => p.id).filter(id => !d.rounds[id].complete()).sort()) this.emit("NR", id, "hcp", hcpText(d.hcp[id]));
      if (order.length) {
        const gross = {};
        for (const id of order) gross[id] = d.rounds[id].scores;
        const winner = ranked(order, gross)[0];
        this.emit("gross", winner, sum(gross[winner]));
      }
    }
  }

  playMatch(names, holes, first, last) {
    let lead = 0;
    let remaining = last - first;
    const statuses = [];
    for (let h = first; h < last; h++) {
      lead += holes[h];
      statuses.push(status(lead));
      remaining = last - h - 1;
      if (Math.abs(lead) > remaining || remaining === 0) break;
    }
    const result = lead === 0 ? "AS" : names[lead > 0 ? 0 : 1] + " " + Math.abs(lead) + (remaining ? "&" + remaining : " UP");
    return {statuses, result};
  }

  matches(e, d) {
    const ids = e.players.map(p => p.id);
    const sides = e.form === "FOURBALL" ? [ids.slice(0, 2), ids.slice(2)] : [[ids[0]], [ids[1]]];
    const names = sides.map(side => side.join("+"));
    const holes = [];
    for (let h = 0; h < 18; h++) {
      const scores = sides.map(side => {
        const values = side.map(id => d.nets[id][h]).filter((n) => n !== null);
        return values.length ? Math.min(...values) : null;
      });
      const [a, b] = scores;
      holes.push(a === null ? b === null ? 0 : -1 : b === null || a < b ? 1 : a > b ? -1 : 0);
    }
    const minimum = Math.min(...Object.values(d.hcp));
    const parts = ["strokes"];
    for (const id of ids) parts.push(id, d.hcp[id] - minimum);
    this.emit(...parts);
    if (e.form === "NASSAU") {
      for (const [label, first, last] of [["front", 0, 9], ["back", 9, 18], ["total", 0, 18]]) {
        this.emit(label, this.playMatch(names, holes, first, last).result);
      }
    } else {
      const match = this.playMatch(names, holes, 0, 18);
      this.emit("status", match.statuses.join(", "));
      this.emit("result", match.result);
    }
  }

  betterball(e, d) {
    const teams = {};
    const values = {};
    for (let i = 0; i < e.players.length; i += 2) {
      const a = e.players[i].id;
      const b = e.players[i + 1].id;
      teams[a] = b;
      values[a] = d.points[a].map((v, h) => Math.max(v, d.points[b][h]));
    }
    const order = ranked(Object.keys(teams), values, true);
    for (let i = 0; i < order.length; i++) {
      const a = order[i];
      const b = teams[a];
      this.emit(i + 1, a + "+" + b, "points", sum(values[a]), "hcp", hcpText(d.hcp[a]), hcpText(d.hcp[b]));
    }
  }

  skins(e, d) {
    const ids = e.players.map(p => p.id);
    const totals = Object.fromEntries(ids.map(id => [id, 0]));
    let carry = 0;
    let winners = [];
    for (let h = 0; h < 18; h++) {
      carry++;
      const available = ids.filter(id => d.nets[id][h] !== null);
      const best = available.length ? Math.min(...available.map(id => d.nets[id][h])) : null;
      winners = available.filter(id => d.nets[id][h] === best);
      if (winners.length === 1) {
        this.emit("hole", h + 1, winners[0], carry);
        totals[winners[0]] += 100 * carry;
        carry = 0;
      }
    }
    if (carry) {
      const sharing = (winners.length ? winners : ids).slice().sort();
      const share = Math.floor(carry * 100 / sharing.length);
      for (const id of sharing) totals[id] += share;
      this.emit("carry", carry, ...sharing);
    }
    for (const id of [...ids].sort((a, b) => totals[b] - totals[a] || lex(a, b))) this.emit(id, hundredths(totals[id]));
  }

  cardTotal(label, r, strokes, nets, points, first, last) {
    const scores = r.scores.slice(first, last);
    const complete = scores.every(s => typeof s === "number");
    this.emit(label, sum(r.course.pars.slice(first, last)), complete ? sum(scores) : "-",
      sum(r.adjusted.slice(first, last)), sum(strokes.slice(first, last)),
      complete ? sum(nets.slice(first, last)) : "-", sum(points.slice(first, last)));
  }

  command(cmd, a) {
    switch (cmd) {
      case "COURSE": {
        if (this.courses.has(a[0])) throw new CommandError("duplicate course");
        const pars = a.slice(1, 19).map(Number);
        const si = a.slice(19).map(Number);
        if (pars.some(p => ![3, 4, 5].includes(p)) || [...si].sort((a, b) => a - b).some((v, i) => v !== i + 1)) throw new CommandError("invalid course");
        this.courses.set(a[0], {id: a[0], pars, si, par: sum(pars), tees: new Map()});
        break;
      }
      case "TEE": {
        const c = this.course(a[0]);
        if (c.tees.has(a[1])) throw new CommandError("duplicate tee");
        const rating = Number(a[2]);
        const slope = Number(a[3]);
        if (rating < 500 || rating > 900 || slope < 55 || slope > 155) throw new CommandError("invalid tee");
        c.tees.set(a[1], {id: a[1], rating, slope});
        break;
      }
      case "PLAYER": {
        if (this.players.has(a[0])) throw new CommandError("duplicate player");
        const index = a.length === 3 ? Number(a[2]) : null;
        if (index !== null && (index < -100 || index > 540)) throw new CommandError("invalid index");
        this.players.set(a[0], new Player(a[0], a[1], index));
        break;
      }
      case "ROUND": {
        const p = this.player(a[0]);
        const [c, t] = this.tee(a[1], a[2]);
        const day = Number(a[3]);
        if (p.rounds.length && day < p.rounds[p.rounds.length - 1].day) throw new CommandError("invalid day");
        const scores = a.slice(4).map(s => s === "-" || s === "X" ? s : Number(s));
        if (scores.filter(s => s === "-").length >= 5) throw new CommandError("too few holes");
        const r = new GolfRound(p, c, t, day, scores);
        p.rounds.push(r);
        p.update(day);
        if (p.index !== null) p.records.push([day, p.index]);
        const parts = ["round", p.id, p.rounds.length + ":", "ags", r.ags, "diff", decimal(r.diff)];
        if (r.exceptional) parts.push("exceptional", decimal(-r.exceptional));
        this.emit(...parts, "index", indexText(p.index));
        break;
      }
      case "REMOVE": {
        const p = this.player(a[0]);
        if (!p.rounds.length) throw new CommandError("no rounds");
        const number = p.rounds.length;
        const r = p.rounds.pop();
        p.index = r.previousIndex;
        p.records.length = r.previousRecords;
        p.calculation = r.previousCalculation;
        this.emit("removed", p.id, number + ":", "index", indexText(p.index));
        break;
      }
      case "INDEX": {
        const p = this.player(a[0]);
        const parts = ["index", p.id + ":", indexText(p.index), "rounds", p.rounds.length];
        const c = p.calculation;
        if (c) {
          parts.push("lowest", c.k, "average", decimal(c.average), "adjustment", decimal(c.adjustment));
          if (c.low !== null) parts.push("low", indexText(c.low));
          if (c.hard) parts.push("hard", "cap");
          else if (c.soft) parts.push("soft", "cap");
          if (c.maximum) parts.push("maximum");
        }
        this.emit(...parts);
        break;
      }
      case "HISTORY": {
        const p = this.player(a[0]);
        const rows = p.eligible();
        const counted = new Set(p.counting(rows).selected.map(r => r.number));
        this.emit("history", p.id + ":", "rounds", p.rounds.length);
        for (const row of rows) {
          const r = row.round;
          const parts = [row.number, "day", r.day, r.course.id, r.tee.id, "ags", r.ags, "diff", decimal(r.diff)];
          if (row.adjusted !== r.diff) parts.push("adjusted", decimal(row.adjusted));
          if (counted.has(row.number)) parts.push("*");
          this.emit(...parts);
        }
        break;
      }
      case "LOWINDEX": {
        const p = this.player(a[0]);
        const day = Number(a[1]);
        const low = p.low(day);
        this.emit("lowindex", p.id, day + ":", ...(low === null ? ["none"] : [indexText(low[1]), "day", low[0]]));
        break;
      }
      case "COURSEHCP": {
        const p = this.player(a[0]);
        const [c, t] = this.tee(a[1], a[2]);
        if (p.index === null) throw new CommandError("no index");
        const h = handicap(p.index, c, t);
        this.emit("coursehcp", p.id, c.id, t.id + ":", hcpText(h), "strokes", ...allocation(h, c.si));
        break;
      }
      case "HCPTABLE": {
        const [c, t] = this.tee(a[0], a[1]);
        const first = Number(a[2]);
        const last = Number(a[3]);
        if (first < -100 || first > last || last > 540) throw new CommandError("invalid index");
        this.emit("hcptable", c.id, t.id + ":", indexText(first), "to", indexText(last));
        let start = first;
        let h = handicap(first, c, t);
        for (let i = first + 1; i <= last; i++) {
          const next = handicap(i, c, t);
          if (next !== h) {
            this.emit(indexText(start), "to", indexText(i - 1) + ":", hcpText(h));
            start = i;
            h = next;
          }
        }
        this.emit(indexText(start), "to", indexText(last) + ":", hcpText(h));
        break;
      }
      case "CARD": {
        const p = this.player(a[0]);
        const number = Number(a[1]);
        if (number > p.rounds.length) throw new CommandError("unknown round");
        const r = p.rounds[number - 1];
        const c = r.course;
        const strokes = allocation(r.hcp ?? 0, c.si);
        const nets = r.nets(strokes);
        const points = r.points(nets);
        this.emit("card", p.id, number + ":", c.id, r.tee.id, "day", r.day, "handicap", hcpText(r.hcp));
        for (let h = 0; h < 18; h++) {
          this.emit(h + 1, c.pars[h], c.si[h], r.scores[h], r.adjusted[h], strokes[h], nets[h] ?? "-", points[h]);
          if (h === 8) this.cardTotal("OUT", r, strokes, nets, points, 0, 9);
          if (h === 17) {
            this.cardTotal("IN", r, strokes, nets, points, 9, 18);
            this.cardTotal("TOTAL", r, strokes, nets, points, 0, 18);
          }
        }
        this.emit("ags", r.ags, "diff", decimal(r.diff));
        break;
      }
      case "STATS": {
        const p = this.player(a[0]);
        const labels = ["eagles", "birdies", "pars", "bogeys", "doubles", "others", "pickups"];
        const counts = Array(7).fill(0);
        const parScores = {3: [], 4: [], 5: []};
        const totals = [];
        for (const r of p.rounds) {
          if (r.complete()) totals.push(sum(r.scores));
          for (let h = 0; h < 18; h++) {
            const score = r.scores[h];
            if (score === "X") counts[6]++;
            else if (typeof score === "number") {
              const relative = score - r.course.pars[h];
              counts[relative <= -2 ? 0 : relative === -1 ? 1 : relative === 0 ? 2 : relative === 1 ? 3 : relative === 2 ? 4 : 5]++;
              parScores[r.course.pars[h]].push(score);
            }
          }
        }
        const parts = ["stats", p.id + ":", "rounds", p.rounds.length, "best", totals.length ? Math.min(...totals) : "-", "average", averageText(sum(totals), totals.length)];
        for (let i = 0; i < labels.length; i++) parts.push(labels[i], counts[i]);
        for (const par of [3, 4, 5]) parts.push("par" + par, averageText(sum(parScores[par]), parScores[par].length));
        this.emit(...parts);
        break;
      }
      case "HOLESTATS": {
        const c = this.course(a[0]);
        const rounds = [...this.players.values()].flatMap(p => p.rounds).filter(r => r.course === c);
        const scores = Array.from({length: 18}, (_, h) => rounds.map(r => r.scores[h]).filter((s) => typeof s === "number"));
        const totals = scores.map(sum);
        const order = Array.from({length: 18}, (_, h) => h).sort((a, b) => {
          if (!scores[a].length || !scores[b].length) return Number(!scores[a].length) - Number(!scores[b].length) || a - b;
          return (totals[b] - c.pars[b] * scores[b].length) * scores[a].length - (totals[a] - c.pars[a] * scores[a].length) * scores[b].length || a - b;
        });
        this.emit("holestats", c.id + ":", "rounds", rounds.length);
        for (let h = 0; h < 18; h++) this.emit(h + 1, "par", c.pars[h], "si", c.si[h], "scores", scores[h].length, "avg", averageText(totals[h], scores[h].length), "rank", order.indexOf(h) + 1);
        break;
      }
      case "PLAYERS": {
        const players = [...this.players.values()].sort((a, b) => Number(a.index === null) - Number(b.index === null) || (a.index ?? 0) - (b.index ?? 0) || lex(a.id, b.id));
        this.emit("players", players.length);
        for (const p of players) this.emit(p.id, p.name, indexText(p.index), "rounds", p.rounds.length);
        break;
      }
      case "EVENT": {
        if (this.events.has(a[0])) throw new CommandError("duplicate event");
        const [c, t] = this.tee(a[2], a[3]);
        const allowance = Number(a[5]);
        if (allowance < 1 || allowance > 100) throw new CommandError("invalid allowance");
        const ids = a.slice(6);
        if (ids.some(id => !this.players.has(id))) throw new CommandError("unknown player");
        const n = ids.length;
        const valid = ["MATCH", "NASSAU"].includes(a[1]) ? n === 2 : a[1] === "FOURBALL" ? n === 4 : a[1] === "BETTERBALL" ? [4, 6, 8].includes(n) : n >= 2 && n <= 8;
        if (!valid || new Set(ids).size !== n) throw new CommandError("invalid players");
        this.events.set(a[0], {id: a[0], form: a[1], course: c, tee: t, day: Number(a[4]), allowance, players: ids.map(id => this.players.get(id))});
        break;
      }
      case "RESULTS": {
        const e = this.events.get(a[0]);
        if (!e) throw new CommandError("unknown event");
        const d = this.eventData(e);
        this.emit("results", e.id + ":", e.form, e.course.id, e.tee.id, "day", e.day, "allowance", e.allowance);
        if (["STROKE", "STABLEFORD", "PAR"].includes(e.form)) this.individual(e, d);
        else if (["MATCH", "NASSAU", "FOURBALL"].includes(e.form)) this.matches(e, d);
        else if (e.form === "BETTERBALL") this.betterball(e, d);
        else this.skins(e, d);
        break;
      }
      case "MERIT": {
        const totals = new Map();
        const awards = [10, 8, 6, 5, 4, 3, 2, 1];
        let counted = 0;
        for (const e of this.events.values()) {
          if (!["STROKE", "STABLEFORD", "PAR"].includes(e.form)) continue;
          let d;
          try {
            d = this.eventData(e);
          } catch (error) {
            if (!(error instanceof CommandError)) throw error;
            continue;
          }
          counted++;
          for (const p of e.players) {
            if (!totals.has(p.id)) totals.set(p.id, [0, 0, 0]);
            totals.get(p.id)[2]++;
          }
          const order = this.eventRanking(e, d).order;
          for (let rank = 0; rank < order.length; rank++) {
            const row = totals.get(order[rank]);
            row[0] += awards[rank];
            if (rank === 0) row[1]++;
          }
        }
        this.emit("merit:", "events", counted);
        const ids = [...totals.keys()].sort((a, b) => totals.get(b)[0] - totals.get(a)[0] || totals.get(b)[1] - totals.get(a)[1] || lex(a, b));
        for (let i = 0; i < ids.length; i++) {
          const [points, wins, played] = totals.get(ids[i]);
          this.emit(i + 1, ids[i], points, "wins", wins, "played", played);
        }
        break;
      }
    }
  }

  execute(line) {
    const [cmd, ...args] = line.split(" ");
    try {
      this.command(cmd, args);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.emit("ERROR", error.message);
    }
  }
}

const lines = readFileSync(0, "utf8").trimEnd().split("\n");
const scorer = new GolfScorer();
for (let i = 1; i <= Number(lines[0]); i++) scorer.execute(lines[i]);
if (scorer.output.length) process.stdout.write(scorer.output.join("\n") + "\n");
