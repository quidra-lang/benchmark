import { readFileSync } from "node:fs";


const TYPES = ["MOTORCYCLE", "CAR", "ECAR", "VAN", "BUS"];
const KINDS = ["MOTO", "COMPACT", "LARGE", "EV"];
const PREF = {
  MOTORCYCLE: ["MOTO", "COMPACT", "LARGE"],
  CAR: ["COMPACT", "LARGE"],
  ECAR: ["EV", "COMPACT", "LARGE"],
  VAN: ["LARGE"]
};
const FIELDS = ["entries", "exits", "refused", "stay", "parking", "night", "lost", "charge", "total"];
const dateOf = (t) => Math.floor(t / 1440) + 1;
const duration = (m) => Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0");
const stamp = (t) => dateOf(t) + "-" + String(Math.floor(t % 1440 / 60)).padStart(2, "0") + ":" + String(t % 60).padStart(2, "0");
const emptyTotals = () => Object.fromEntries(FIELDS.map(f => [f, 0]));
const emptyTypes = () => Object.fromEntries(TYPES.map(k => [k, emptyTotals()]));
const sumTotals = (rows) => Object.fromEntries(FIELDS.map(f => [f, rows.reduce((a, r) => a + r[f], 0)]));
const free = (s) => !s.closed && s.vehicle === null;
const location = (v) => v.spots[0].code + (v.kind === "BUS" ? ".." + v.spots[2].number : "");
const order = (a, b) => a.spots[0].level - b.spots[0].level || a.spots[0].number - b.spots[0].number;
class CommandError extends Error {}

class Garage {
  now = 0;
  levels = [];
  spots = [];
  spotCodes = new Map();
  vehicles = new Map();
  queue = [];
  passes = new Map();
  history = new Map();
  rates = {MOTORCYCLE: [100, 800], CAR: [200, 1600], ECAR: [200, 1600], VAN: [300, 2400], BUS: [600, 4800]};
  fees = {NIGHT: 300, LOST: 2000, KWH: 30};
  totals = emptyTypes();
  daily = new Map();
  peak = 0;
  peakTime = null;
  output = [];

  emit(...parts) {
    this.output.push(parts.join(" "));
  }

  vehicle(plate) {
    const v = this.vehicles.get(plate);
    if (!v) throw new CommandError(plate + " is not parked");
    return v;
  }

  spot(code) {
    const s = this.spotCodes.get(code);
    if (!s) throw new CommandError("unknown spot " + code);
    return s;
  }

  unpaid(v) {
    if (v.payment !== null) throw new CommandError(v.plate + " has already paid");
  }

  hasPass(plate, time = this.now) {
    return this.passes.has(plate) && dateOf(time) <= this.passes.get(plate);
  }

  dayTotals(day) {
    if (!this.daily.has(day)) this.daily.set(day, emptyTypes());
    return this.daily.get(day);
  }

  count(kind, field, day) {
    this.totals[kind][field]++;
    this.dayTotals(day)[kind][field]++;
  }

  assignment(kind) {
    if (kind === "BUS") {
      for (const level of this.levels) {
        for (let i = 0; i + 2 < level.length; i++) {
          const triple = level.slice(i, i + 3);
          if (triple.every(s => s.kind === "LARGE" && free(s))) return triple;
        }
      }
    } else {
      for (const preferred of PREF[kind]) {
        const s = this.spots.find(s => s.kind === preferred && free(s));
        if (s) return [s];
      }
    }
    return null;
  }

  park(plate, kind, spots) {
    const v = {plate, kind, spots, entered: this.now, energy: 0, chargeCost: 0, validation: 0, payment: null};
    this.vehicles.set(plate, v);
    for (const s of spots) s.vehicle = v;
    this.count(kind, "entries", dateOf(this.now));
    if (this.vehicles.size > this.peak) {
      this.peak = this.vehicles.size;
      this.peakTime = this.now;
    }
    return v;
  }

  giveUp() {
    const remaining = [];
    for (const w of this.queue) {
      const deadline = w.joined + 30;
      if (deadline <= this.now) {
        this.emit("GIVEUP", w.plate, w.kind, stamp(deadline));
        this.count(w.kind, "refused", dateOf(deadline));
      } else {
        remaining.push(w);
      }
    }
    this.queue = remaining;
  }

  processQueue() {
    const remaining = [];
    for (const w of this.queue) {
      const spots = this.assignment(w.kind);
      if (spots === null) {
        remaining.push(w);
      } else {
        const v = this.park(w.plate, w.kind, spots);
        this.emit("ADMIT", w.plate, w.kind, location(v), "waited", duration(this.now - w.joined));
      }
    }
    this.queue = remaining;
  }

  interval(v, start, end, grace) {
    const stay = end - start;
    if (this.hasPass(v.plate, end) || stay <= grace) return [0, 0];
    const [rate, cap] = this.rates[v.kind];
    let parking = 0;
    for (let offset = 0; offset < stay; offset += 1440) {
      const billable = Math.min(stay - offset, 1440) - (offset === 0 ? grace : 0);
      parking += Math.min(Math.floor((billable + 29) / 30) * rate, cap);
    }
    return [parking, (dateOf(end) - dateOf(start)) * this.fees.NIGHT];
  }

  charges(v, lost = false) {
    let parking;
    let night;
    let due;
    const lostFee = lost ? this.fees.LOST : 0;
    if (v.payment === null) {
      [parking, night] = this.interval(v, v.entered, this.now, 15 + v.validation);
      due = parking + night + lostFee + v.chargeCost;
    } else {
      const [paidTime, paidParking, paidNight] = v.payment;
      const [additional, extraNight] = this.interval(v, paidTime, this.now, 15);
      parking = paidParking + additional;
      night = paidNight + extraNight;
      due = additional + extraNight;
    }
    return {parking, night, lost: lostFee, charge: v.chargeCost, total: parking + night + lostFee + v.chargeCost, due};
  }

  feeLine(label, v, c) {
    this.emit(label, v.plate, location(v), "stay", duration(this.now - v.entered),
      "parking", c.parking, "night", c.night, "lost", c.lost, "charge", c.charge, "total", c.total, "due", c.due);
  }

  annotation(v) {
    const parts = [];
    if (this.hasPass(v.plate)) parts.push("PASS");
    if (v.validation) parts.push("VAL", v.validation);
    if (v.energy) parts.push("KWH", v.energy);
    if (v.payment !== null) parts.push("PAID");
    return parts.length ? " " + parts.join(" ") : "";
  }

  moveVehicle(v, s) {
    const old = location(v);
    v.spots[0].vehicle = null;
    v.spots = [s];
    s.vehicle = v;
    this.emit("MOVE", v.plate, old, "->", s.code);
  }

  revenueLine(label, t) {
    const parts = [label, "exits", t.exits];
    for (const f of ["parking", "night", "lost", "charge", "total"]) parts.push(f, t[f]);
    this.emit(...parts);
  }

  dailyLine(prefix, t) {
    this.emit(...prefix, "entries", t.entries, "exits", t.exits, "refused", t.refused, "revenue", t.total);
  }

  statsLine(label, t) {
    const q = t.exits ? Math.floor(t.stay * 10 / t.exits) : 0;
    this.emit(label, "entries", t.entries, "exits", t.exits, "refused", t.refused, "avg_stay", Math.floor(q / 10) + "." + q % 10);
  }

  command(cmd, a) {
    const plate = a[0];
    switch (cmd) {
      case "LEVEL": {
        const counts = a.map(Number);
        const level = [];
        const index = this.levels.length + 1;
        for (let k = 0; k < KINDS.length; k++) {
          for (let j = 0; j < counts[k]; j++) {
            const number = level.length + 1;
            const s = {level: index, number, kind: KINDS[k], code: "L" + index + "-" + number, closed: false, vehicle: null};
            level.push(s);
            this.spots.push(s);
            this.spotCodes.set(s.code, s);
          }
        }
        this.levels.push(level);
        this.emit("LEVEL", index, "spots", level.length, "MOTO", counts[0], "COMPACT", counts[1], "LARGE", counts[2], "EV", counts[3]);
        this.processQueue();
        break;
      }
      case "CLOSE": {
        const s = this.spot(a[0]);
        if (s.closed) throw new CommandError("spot " + s.code + " is already closed");
        if (s.vehicle) throw new CommandError("spot " + s.code + " is occupied by " + s.vehicle.plate);
        s.closed = true;
        this.emit("CLOSE", s.code, s.kind);
        break;
      }
      case "OPEN": {
        const s = this.spot(a[0]);
        if (!s.closed) throw new CommandError("spot " + s.code + " is not closed");
        s.closed = false;
        this.emit("OPEN", s.code, s.kind);
        this.processQueue();
        break;
      }
      case "RATE": {
        if (!TYPES.includes(a[0])) throw new CommandError("unknown type " + a[0]);
        const rate = Number(a[1]);
        const cap = Number(a[2]);
        if (cap < rate) throw new CommandError("cap below rate for " + a[0]);
        this.rates[a[0]] = [rate, cap];
        this.emit("RATE", a[0], rate, cap);
        break;
      }
      case "FEE": {
        if (!(a[0] in this.fees)) throw new CommandError("unknown fee " + a[0]);
        this.fees[a[0]] = Number(a[1]);
        this.emit("FEE", a[0], Number(a[1]));
        break;
      }
      case "ENTER": {
        const kind = a[1];
        if (!TYPES.includes(kind)) throw new CommandError("unknown type " + kind);
        if (this.vehicles.has(plate)) throw new CommandError(plate + " is already parked at " + location(this.vehicles.get(plate)));
        if (this.queue.some(w => w.plate === plate)) throw new CommandError(plate + " is already waiting");
        const spots = this.assignment(kind);
        if (spots !== null) {
          const v = this.park(plate, kind, spots);
          this.emit("ENTER", plate, kind, location(v));
        } else if (this.queue.length < 3) {
          this.queue.push({plate, kind, joined: this.now});
          this.emit("WAIT", plate, kind, this.queue.length);
        } else {
          this.emit("FULL", plate, kind);
          this.count(kind, "refused", dateOf(this.now));
        }
        break;
      }
      case "LEAVE": {
        const i = this.queue.findIndex(w => w.plate === plate);
        if (i < 0) throw new CommandError(plate + " is not waiting");
        const [w] = this.queue.splice(i, 1);
        this.emit("LEAVE", plate, w.kind);
        break;
      }
      case "EXIT": {
        const v = this.vehicle(plate);
        const lost = a.length === 2;
        if (lost) this.unpaid(v);
        const c = this.charges(v, lost);
        this.feeLine("EXIT", v, c);
        if (!this.history.has(plate)) this.history.set(plate, []);
        this.history.get(plate).push({entered: v.entered, exited: this.now, location: location(v), kind: v.kind, total: c.total, lost});
        this.count(v.kind, "exits", dateOf(this.now));
        const daily = this.dayTotals(dateOf(this.now))[v.kind];
        for (const f of ["parking", "night", "lost", "charge", "total"]) {
          this.totals[v.kind][f] += c[f];
          daily[f] += c[f];
        }
        this.totals[v.kind].stay += this.now - v.entered;
        daily.stay += this.now - v.entered;
        for (const s of v.spots) s.vehicle = null;
        this.vehicles.delete(plate);
        this.processQueue();
        break;
      }
      case "PAY": {
        const v = this.vehicle(plate);
        this.unpaid(v);
        const c = this.charges(v);
        v.payment = [this.now, c.parking, c.night];
        this.emit("PAY", plate, "parking", c.parking, "night", c.night, "charge", c.charge, "total", c.total);
        break;
      }
      case "QUOTE": {
        const v = this.vehicle(plate);
        this.feeLine("QUOTE", v, this.charges(v));
        break;
      }
      case "CHARGE": {
        const v = this.vehicle(plate);
        const kwh = Number(a[1]);
        if (v.kind !== "ECAR") throw new CommandError(plate + " is not an electric car");
        if (v.spots[0].kind !== "EV") throw new CommandError(plate + " is not at a charger");
        this.unpaid(v);
        if (v.energy + kwh > 100) throw new CommandError("charge limit exceeded for " + plate);
        const cost = kwh * this.fees.KWH;
        v.energy += kwh;
        v.chargeCost += cost;
        this.emit("CHARGE", plate, "kwh", kwh, "cost", cost, "stay_kwh", v.energy, "stay_cost", v.chargeCost);
        break;
      }
      case "VALIDATE": {
        const v = this.vehicle(plate);
        this.unpaid(v);
        const minutes = Number(a[1]);
        if (v.validation + minutes > 180) throw new CommandError("validation limit exceeded for " + plate);
        v.validation += minutes;
        this.emit("VALIDATE", plate, minutes, "total", v.validation);
        break;
      }
      case "PASS": {
        const last = this.hasPass(plate) ? this.passes.get(plate) : dateOf(this.now) - 1;
        this.passes.set(plate, last + Number(a[1]));
        this.emit("PASS", plate, "until", this.passes.get(plate));
        break;
      }
      case "UNPASS": {
        if (!this.hasPass(plate)) throw new CommandError(plate + " has no pass");
        this.passes.delete(plate);
        this.emit("UNPASS", plate);
        break;
      }
      case "MOVE": {
        const v = this.vehicle(plate);
        if (v.kind === "BUS") throw new CommandError("bus " + plate + " cannot be moved");
        const s = this.spot(a[1]);
        if (s === v.spots[0]) throw new CommandError(plate + " is already at " + s.code);
        if (s.closed) throw new CommandError("spot " + s.code + " is closed");
        if (s.vehicle) throw new CommandError("spot " + s.code + " is occupied by " + s.vehicle.plate);
        if (!PREF[v.kind].includes(s.kind)) throw new CommandError(v.kind + " cannot use " + s.kind + " spot " + s.code);
        this.moveVehicle(v, s);
        this.processQueue();
        break;
      }
      case "REBALANCE": {
        const targets = [...this.vehicles.values()].filter(v => v.kind !== "BUS").sort(order);
        let moved = 0;
        for (const v of targets) {
          const rank = PREF[v.kind].indexOf(v.spots[0].kind);
          if (rank === 0) continue;
          const spots = this.assignment(v.kind);
          if (spots && PREF[v.kind].indexOf(spots[0].kind) < rank) {
            this.moveVehicle(v, spots[0]);
            moved++;
          }
        }
        this.emit("REBALANCE", moved);
        this.processQueue();
        break;
      }
      case "WHERE": {
        const v = this.vehicles.get(plate);
        const position = this.queue.findIndex(w => w.plate === plate);
        if (v) {
          this.emit("WHERE", plate, location(v), v.kind, stamp(v.entered), "stay", duration(this.now - v.entered) + this.annotation(v));
        } else if (position >= 0) {
          this.emit("WHERE", plate, "waiting", position + 1);
        } else {
          const records = this.history.get(plate);
          if (!records) throw new CommandError("unknown plate " + plate);
          this.emit("WHERE", plate, "gone", stamp(records[records.length - 1].exited));
        }
        break;
      }
      case "LIST":
      case "OVERSTAY": {
        const level = a.length ? Number(a[0]) : null;
        if (cmd === "LIST" && level !== null && level > this.levels.length) throw new CommandError("unknown level " + level);
        const targets = [...this.vehicles.values()].filter(v => cmd === "LIST" ? level === null || v.spots[0].level === level : this.now - v.entered >= level * 60);
        targets.sort(cmd === "LIST" ? order : (a, b) => a.entered - b.entered || order(a, b));
        if (cmd === "LIST") this.emit("LIST", targets.length);
        else this.emit("OVERSTAY", level, targets.length);
        for (const v of targets) {
          if (cmd === "LIST") this.emit(location(v), v.plate, v.kind, stamp(v.entered) + this.annotation(v));
          else this.emit(location(v), v.plate, v.kind, stamp(v.entered), "stay", duration(this.now - v.entered));
        }
        break;
      }
      case "MAP": {
        this.emit("MAP", this.levels.length);
        for (let i = 0; i < this.levels.length; i++) {
          const symbols = this.levels[i].map(s => s.closed ? "#" : s.vehicle ? s.kind[0] : s.kind[0].toLowerCase()).join("");
          this.emit("L" + (i + 1), ...symbols.match(/.{1,10}/g));
        }
        break;
      }
      case "OCCUPANCY": {
        this.emit("OCCUPANCY", "vehicles", this.vehicles.size, "waiting", this.queue.length);
        const allUsed = Object.fromEntries(KINDS.map(k => [k, 0]));
        const allAvailable = {...allUsed};
        let allClosed = 0;
        for (let i = 0; i < this.levels.length; i++) {
          const used = Object.fromEntries(KINDS.map(k => [k, 0]));
          const available = {...used};
          let closed = 0;
          for (const s of this.levels[i]) {
            if (s.closed) closed++;
            else available[s.kind]++;
            if (s.vehicle) used[s.kind]++;
          }
          const parts = ["L" + (i + 1)];
          for (const k of KINDS) {
            parts.push(k, used[k] + "/" + available[k]);
            allUsed[k] += used[k];
            allAvailable[k] += available[k];
          }
          this.emit(...parts, "closed", closed);
          allClosed += closed;
        }
        const parts = ["TOTAL"];
        for (const k of KINDS) parts.push(k, allUsed[k] + "/" + allAvailable[k]);
        const available = Object.values(allAvailable).reduce((a, b) => a + b, 0);
        const used = Object.values(allUsed).reduce((a, b) => a + b, 0);
        const q = available ? Math.floor(used * 1000 / available) : 0;
        this.emit(...parts, "closed", allClosed, "rate", Math.floor(q / 10) + "." + q % 10 + "%");
        break;
      }
      case "SIGN": {
        const parts = ["SIGN"];
        for (const kind of TYPES) {
          let count = 0;
          if (kind === "BUS") {
            for (const level of this.levels) {
              let run = 0;
              for (const s of level) {
                if (s.kind === "LARGE" && free(s)) run++;
                else {
                  count += Math.floor(run / 3);
                  run = 0;
                }
              }
              count += Math.floor(run / 3);
            }
          } else {
            count = this.spots.filter(s => free(s) && PREF[kind].includes(s.kind)).length;
          }
          parts.push(kind, count || "FULL");
        }
        this.emit(...parts);
        break;
      }
      case "RATES": {
        this.emit("RATES");
        for (const kind of TYPES) this.emit(kind, ...this.rates[kind]);
        this.emit("NIGHT", this.fees.NIGHT, "LOST", this.fees.LOST, "KWH", this.fees.KWH);
        break;
      }
      case "PASSES": {
        const plates = [...this.passes.keys()].filter(p => this.hasPass(p)).sort();
        this.emit("PASSES", plates.length);
        for (const p of plates) this.emit(p, "until", this.passes.get(p), ...(this.vehicles.has(p) ? ["IN"] : []));
        break;
      }
      case "HISTORY": {
        const records = this.history.get(plate);
        if (!records) throw new CommandError("no history for " + plate);
        this.emit("HISTORY", plate, "visits", records.length, "paid", records.reduce((a, r) => a + r.total, 0));
        for (const r of records) this.emit(stamp(r.entered), stamp(r.exited), r.location, r.kind, r.total, ...(r.lost ? ["LOST"] : []));
        break;
      }
      case "REVENUE": {
        this.emit("REVENUE");
        for (const kind of TYPES) this.revenueLine(kind, this.totals[kind]);
        this.revenueLine("TOTAL", sumTotals(Object.values(this.totals)));
        break;
      }
      case "DAILY": {
        const day = Number(a[0]);
        const totals = this.daily.get(day) ?? emptyTypes();
        this.dailyLine(["DAILY", day], sumTotals(Object.values(totals)));
        for (const kind of TYPES) this.dailyLine([kind], totals[kind]);
        break;
      }
      case "STATS": {
        this.emit("STATS", "parked", this.vehicles.size, "peak", this.peak, "at", this.peakTime === null ? "-" : stamp(this.peakTime));
        for (const kind of TYPES) this.statsLine(kind, this.totals[kind]);
        this.statsLine("ALL", sumTotals(Object.values(this.totals)));
        break;
      }
    }
  }

  execute(line) {
    const [day, clock, cmd, ...args] = line.split(" ");
    const [hour, minute] = clock.split(":").map(Number);
    this.now = (Number(day) - 1) * 1440 + hour * 60 + minute;
    this.giveUp();
    try {
      this.command(cmd, args);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.emit("ERROR", error.message);
    }
  }
}

const lines = readFileSync(0, "utf8").trimEnd().split("\n");
const garage = new Garage();
for (let i = 1; i <= Number(lines[0]); i++) garage.execute(lines[i]);
process.stdout.write(garage.output.join("\n") + "\n");
