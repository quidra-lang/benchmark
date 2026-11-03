import { readFileSync } from "node:fs";


const TYPES = ["SINGLE", "DOUBLE", "SUITE"];
const WEEKDAYS = ["SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"];
const DATES = [];
const DAYS = new Map();
for (let year = 2000; year <= 2099; year++) {
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  for (let month = 1; month <= 12; month++) {
    for (let day = 1; day <= lengths[month - 1]; day++) {
      const text = year + "-" + String(month).padStart(2, "0") + "-" + String(day).padStart(2, "0");
      DAYS.set(text, DATES.length);
      DATES.push(text);
    }
  }
}
const lex = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const dateText = (day) => DATES[day];
const dateWeek = (day) => dateText(day) + " " + WEEKDAYS[day % 7];
const cents = (s) => BigInt(s.replace(".", ""));
const money = (v) => v / 100n + "." + String(v % 100n).padStart(2, "0");
const lodging = (x) => x.nights.reduce((v, n) => v + n.rate, 0n);
const extras = (x) => x.extras.reduce((v, e) => v + e.amount, 0n);
const byArrival = (a, b) => a.start - b.start || lex(a.id, b.id);
class CommandError extends Error {}

class Hotel {
  today = DAYS.get("2026-01-01");
  rooms = new Map();
  seasons = [];
  reservations = new Map();
  queue = [];
  used = new Set();
  output = [];

  emit(indent, ...parts) {
    this.output.push(" ".repeat(indent) + parts.join(" "));
  }

  date(text) {
    const day = DAYS.get(text);
    if (day === undefined) throw new CommandError("invalid date " + text);
    return day;
  }

  room(text) {
    const r = this.rooms.get(Number(text));
    if (!r) throw new CommandError("unknown room " + text);
    return r;
  }

  reservation(id) {
    const x = this.reservations.get(id);
    if (!x) throw new CommandError("unknown reservation " + id);
    return x;
  }

  status(x, allowed) {
    if (!allowed.includes(x.status)) throw new CommandError("invalid status " + x.id + " " + x.status);
  }

  type(kind) {
    if (!TYPES.includes(kind)) throw new CommandError("invalid type " + kind);
  }

  unused(id) {
    if (this.used.has(id)) throw new CommandError("duplicate reservation " + id);
  }

  stay(a, b) {
    const start = this.date(a);
    const end = this.date(b);
    if (start < this.today) throw new CommandError("past date " + a);
    if (end <= start) throw new CommandError("invalid range " + a + " " + b);
    if (end - start > 30) throw new CommandError("too long " + (end - start));
    return [start, end];
  }

  period(a, b, future = false, limited = true) {
    const start = this.date(a);
    const end = this.date(b);
    if (future && start < this.today) throw new CommandError("past date " + a);
    if (end < start) throw new CommandError("invalid range " + a + " " + b);
    if (limited && end - start + 1 > 31) throw new CommandError("too long " + (end - start + 1));
    return [start, end];
  }

  sortedRooms() {
    return [...this.rooms.values()].sort((a, b) => a.number - b.number);
  }

  rate(r, day) {
    const percent = this.seasons.findLast(season => season.start <= day && day <= season.end)?.percent ?? 100n;
    return r.base * percent / 100n;
  }

  price(r, start, end) {
    const nights = [];
    for (let day = start; day < end; day++) nights.push({day, room: r.number, rate: this.rate(r, day)});
    return nights;
  }

  free(r, day, except = null) {
    const night = r.occupied.get(day);
    return !r.blocks.has(day) && (!night || night.owner === except);
  }

  unavailable(r, start, end, except = null) {
    for (let day = start; day < end; day++) {
      if (!this.free(r, day, except)) return day;
    }
    return null;
  }

  findRoom(kind, start, end, except = null) {
    return this.sortedRooms().find(r => r.kind === kind && this.unavailable(r, start, end, except) === null) ?? null;
  }

  inHouse(room) {
    return [...this.reservations.values()].find(x => x.status === "inhouse" && x.room === room);
  }

  release(x) {
    for (const n of x.nights) this.rooms.get(n.room).occupied.delete(n.day);
  }

  occupy(x) {
    for (const n of x.nights) this.rooms.get(n.room).occupied.set(n.day, {owner: x.id, rate: n.rate});
  }

  create(id, guest, r, start, end, indent = 0) {
    const x = {id, guest, room: r.number, start, end, nights: this.price(r, start, end),
      status: "booked", extras: [], deposit: 0n, paid: 0n, posting: null, fee: 0n, penalty: null, bill: null};
    this.reservations.set(id, x);
    this.used.add(id);
    this.occupy(x);
    this.emit(indent, "BOOK", id, guest, "room", r.number, r.kind, dateText(start), "->", dateText(end),
      "nights", end - start, "total", money(lodging(x)));
  }

  guestPaid(guest) {
    return [...this.reservations.values()].filter(x => x.guest === guest).reduce((v, x) => v + x.paid, 0n);
  }

  tier(guest) {
    const points = this.guestPaid(guest) / 100n;
    return points >= 2000n ? {points, name: "GOLD", percent: 10n} :
      points >= 500n ? {points, name: "SILVER", percent: 5n} : {points, name: "BRONZE", percent: 0n};
  }

  bill(x) {
    const l = lodging(x);
    const discount = l * this.tier(x.guest).percent / 100n;
    const penalty = x.penalty?.rate ?? 0n;
    const e = extras(x);
    const subtotal = l - discount + penalty + e;
    const tax = subtotal / 10n;
    return {lodging: l, discount, penalty, extras: e, tax, total: subtotal + tax};
  }

  deposit(x, amount) {
    return "deposit " + money(x.deposit) + (amount >= x.deposit ? " due " + money(amount - x.deposit) : " refund " + money(x.deposit - amount));
  }

  checkout(x, day, indent = 0) {
    if (day < x.end) {
      x.penalty = x.nights.find(n => n.day === day);
      for (const n of x.nights.filter(n => n.day >= day)) this.rooms.get(n.room).occupied.delete(n.day);
      x.nights = x.nights.filter(n => n.day < day);
      x.end = day;
    }
    const b = this.bill(x);
    x.bill = b;
    x.paid = b.total;
    x.status = "checkedout";
    x.posting = day;
    this.rooms.get(x.room).clean = false;
    this.emit(indent, "CHECKOUT", x.id, "nights", x.nights.length, "lodging", money(b.lodging),
      "discount", money(b.discount), "penalty", money(b.penalty), "extras", money(b.extras),
      "tax", money(b.tax), "total", money(b.total), this.deposit(x, b.total));
  }

  processQueue() {
    const remaining = [];
    for (const w of this.queue) {
      if (w.start < this.today) {
        this.emit(2, "WAITLIST", w.id, "expired");
      } else {
        const r = this.findRoom(w.kind, w.start, w.end);
        if (r) this.create(w.id, w.guest, r, w.start, w.end, 2);
        else remaining.push(w);
      }
    }
    this.queue = remaining;
  }

  metrics(day) {
    let available = 0;
    let occupied = 0;
    let revenue = 0n;
    for (const r of this.rooms.values()) {
      if (!r.blocks.has(day)) available++;
      const night = r.occupied.get(day);
      if (night) {
        occupied++;
        revenue += night.rate;
      }
    }
    return {available, occupied, revenue};
  }

  metricsText(m) {
    return "sold " + m.occupied + "/" + m.available + " rate " + (m.available ? Math.floor(m.occupied * 100 / m.available) + "%" : "n/a") +
      " revenue " + money(m.revenue) + " adr " + (m.occupied ? money(m.revenue / BigInt(m.occupied)) : "n/a") +
      " revpar " + (m.available ? money(m.revenue / BigInt(m.available)) : "n/a");
  }

  occupancyText(rooms, day) {
    const blocked = rooms.filter(r => r.blocks.has(day)).length;
    const occupied = rooms.filter(r => r.occupied.has(day)).length;
    const available = rooms.length - blocked;
    return "rooms " + rooms.length + " blocked " + blocked + " occupied " + occupied +
      " rate " + (available ? Math.floor(occupied * 100 / available) + "%" : "n/a");
  }

  invoice(x) {
    this.emit(0, "INVOICE", x.id, x.guest, "room", x.room, this.rooms.get(x.room).kind, x.status);
    if (x.status === "cancelled" || x.status === "noshow") {
      this.emit(2, x.status === "cancelled" ? "cancellation" : "noshow", "fee", money(x.fee));
      this.emit(2, "total", money(x.fee));
      this.emit(2, this.deposit(x, x.fee));
      return;
    }
    for (const n of x.nights) this.emit(2, dateWeek(n.day), "room", n.room, money(n.rate));
    const b = x.status === "checkedout" ? x.bill : this.bill(x);
    this.emit(2, "lodging", money(b.lodging));
    this.emit(2, "discount", money(b.discount));
    if (x.penalty) this.emit(2, "penalty", dateWeek(x.penalty.day), money(b.penalty));
    for (const e of x.extras) this.emit(2, "extra", e.item, money(e.amount));
    this.emit(2, "tax", money(b.tax));
    this.emit(2, "total", money(b.total));
    this.emit(2, this.deposit(x, b.total));
  }

  command(cmd, a) {
    switch (cmd) {
      case "ROOM": {
        const number = Number(a[0]);
        if (this.rooms.has(number)) throw new CommandError("duplicate room " + a[0]);
        this.type(a[1]);
        const base = cents(a[2]);
        this.rooms.set(number, {number, kind: a[1], base, clean: true, blocks: new Set(), occupied: new Map()});
        this.emit(0, "ROOM", number, a[1], money(base));
        break;
      }
      case "RATE": {
        const r = this.room(a[0]);
        const old = r.base;
        r.base = cents(a[1]);
        this.emit(0, "RATE", r.number, money(old), "->", money(r.base));
        break;
      }
      case "SEASON": {
        const [start, end] = this.period(a[0], a[1], false, false);
        this.seasons.push({start, end, percent: BigInt(a[2])});
        this.emit(0, "SEASON", this.seasons.length, a[0], "->", a[1], a[2] + "%");
        break;
      }
      case "BLOCK":
      case "UNBLOCK": {
        const r = this.room(a[0]);
        const [start, end] = this.period(a[1], a[2], true);
        if (cmd === "BLOCK") {
          for (let day = start; day <= end; day++) {
            if (r.occupied.has(day)) throw new CommandError("room unavailable " + r.number + " " + dateText(day));
          }
        }
        const nights = new Set(Array.from({length: end - start + 1}, (_, i) => start + i));
        const previous = r.blocks.size;
        r.blocks = cmd === "BLOCK" ? r.blocks.union(nights) : r.blocks.difference(nights);
        const count = Math.abs(r.blocks.size - previous);
        this.emit(0, cmd, r.number, a[1], "->", a[2], cmd === "BLOCK" ? "added" : "removed", count);
        break;
      }
      case "CLEAN": {
        const r = this.room(a[0]);
        if (r.clean) throw new CommandError("already clean " + r.number);
        r.clean = true;
        this.emit(0, "CLEAN", r.number);
        break;
      }
      case "TODAY": {
        const day = this.date(a[0]);
        if (day < this.today) throw new CommandError("past date " + a[0]);
        this.emit(0, "TODAY", dateWeek(day));
        const checkouts = [...this.reservations.values()].filter(x => x.status === "inhouse" && x.end < day);
        checkouts.sort((a, b) => a.end - b.end || lex(a.id, b.id));
        for (const x of checkouts) this.checkout(x, x.end, 2);
        const noshows = [...this.reservations.values()].filter(x => x.status === "booked" && x.start < day).sort(byArrival);
        for (const x of noshows) {
          x.fee = x.nights[0].rate;
          x.paid = x.fee;
          x.status = "noshow";
          x.posting = x.start;
          this.release(x);
          this.emit(2, "NOSHOW", x.id, x.guest, "fee", money(x.fee), this.deposit(x, x.fee));
        }
        this.today = day;
        break;
      }
      case "BOOK":
      case "BOOKROOM":
      case "WAITLIST": {
        this.unused(a[0]);
        let specific = null;
        if (cmd === "BOOKROOM") specific = this.room(a[2]);
        else this.type(a[2]);
        const [start, end] = this.stay(a[3], a[4]);
        const r = specific ?? this.findRoom(a[2], start, end);
        if (specific) {
          const day = this.unavailable(specific, start, end);
          if (day !== null) throw new CommandError("room unavailable " + specific.number + " " + dateText(day));
        }
        if (r) {
          this.create(a[0], a[1], r, start, end);
        } else if (cmd === "WAITLIST") {
          this.queue.push({id: a[0], guest: a[1], kind: a[2], start, end});
          this.used.add(a[0]);
          this.emit(0, "WAITLIST", a[0], "queued", "position", this.queue.length);
        } else {
          throw new CommandError("no availability " + a[2] + " " + a[3] + " " + a[4]);
        }
        break;
      }
      case "MODIFY": {
        const x = this.reservation(a[0]);
        this.status(x, ["booked"]);
        const [start, end] = this.stay(a[1], a[2]);
        const old = this.rooms.get(x.room);
        const kept = this.unavailable(old, start, end, x.id) === null;
        const r = kept ? old : this.findRoom(old.kind, start, end, x.id);
        if (!r) throw new CommandError("no availability " + old.kind + " " + a[1] + " " + a[2]);
        this.release(x);
        x.room = r.number;
        x.start = start;
        x.end = end;
        x.nights = this.price(r, start, end);
        this.occupy(x);
        this.emit(0, "MODIFY", x.id, "room", r.number, kept ? "kept" : "reassigned", a[1], "->", a[2],
          "nights", end - start, "total", money(lodging(x)));
        break;
      }
      case "CANCEL": {
        const i = this.queue.findIndex(w => w.id === a[0]);
        if (i >= 0) {
          this.queue.splice(i, 1);
          this.emit(0, "CANCEL", a[0], "waitlist", "removed");
          break;
        }
        const x = this.reservation(a[0]);
        this.status(x, ["booked"]);
        const days = x.start - this.today;
        x.fee = days >= 7 ? 0n : days >= 1 ? x.nights[0].rate / 2n : x.nights[0].rate;
        x.paid = x.fee;
        x.status = "cancelled";
        x.posting = this.today;
        this.release(x);
        this.emit(0, "CANCEL", x.id, "days", days, "fee", money(x.fee), this.deposit(x, x.fee));
        break;
      }
      case "CHECKIN": {
        const x = this.reservation(a[0]);
        this.status(x, ["booked"]);
        if (x.start !== this.today) throw new CommandError("not arrival date " + x.id + " " + dateText(x.start));
        const occupant = this.inHouse(x.room);
        if (occupant) throw new CommandError("room occupied " + x.room + " " + occupant.id);
        if (!this.rooms.get(x.room).clean) throw new CommandError("room dirty " + x.room);
        x.status = "inhouse";
        this.emit(0, "CHECKIN", x.id, x.guest, "room", x.room, "until", dateText(x.end));
        break;
      }
      case "MOVE": {
        const x = this.reservation(a[0]);
        this.status(x, ["inhouse"]);
        const r = this.room(a[1]);
        if (r.number === x.room) throw new CommandError("same room " + r.number);
        const remaining = x.nights.filter(n => n.day >= this.today);
        if (!remaining.length) throw new CommandError("no remaining nights " + x.id);
        for (const n of remaining) {
          if (!this.free(r, n.day, x.id)) throw new CommandError("room unavailable " + r.number + " " + dateText(n.day));
        }
        const occupant = this.inHouse(r.number);
        if (occupant) throw new CommandError("room occupied " + r.number + " " + occupant.id);
        if (!r.clean) throw new CommandError("room dirty " + r.number);
        const old = x.room;
        for (const n of remaining) {
          this.rooms.get(n.room).occupied.delete(n.day);
          n.room = r.number;
          r.occupied.set(n.day, {owner: x.id, rate: n.rate});
        }
        this.emit(0, "MOVE", x.id, old, "->", r.number, "nights", remaining.length);
        this.rooms.get(old).clean = false;
        x.room = r.number;
        break;
      }
      case "EXTEND": {
        const x = this.reservation(a[0]);
        this.status(x, ["inhouse"]);
        const end = this.date(a[1]);
        if (end <= x.end) throw new CommandError("invalid range " + dateText(x.end) + " " + a[1]);
        if (end - x.start > 30) throw new CommandError("too long " + (end - x.start));
        const r = this.rooms.get(x.room);
        const unavailable = this.unavailable(r, x.end, end, x.id);
        if (unavailable !== null) throw new CommandError("room unavailable " + r.number + " " + dateText(unavailable));
        x.nights.push(...this.price(r, x.end, end));
        x.end = end;
        this.occupy(x);
        this.emit(0, "EXTEND", x.id, "until", a[1], "nights", x.nights.length, "total", money(lodging(x)));
        break;
      }
      case "CHARGE":
      case "PAY": {
        const x = this.reservation(a[0]);
        this.status(x, cmd === "CHARGE" ? ["inhouse"] : ["booked", "inhouse"]);
        const amount = cents(a[1]);
        if (amount === 0n) throw new CommandError("invalid amount");
        if (cmd === "CHARGE") {
          x.extras.push({item: a[2], amount});
          this.emit(0, "CHARGE", x.id, a[2], money(amount), "extras", money(extras(x)));
        } else {
          x.deposit += amount;
          this.emit(0, "PAY", x.id, money(amount), "deposit", money(x.deposit));
        }
        break;
      }
      case "CHECKOUT": {
        const x = this.reservation(a[0]);
        this.status(x, ["inhouse"]);
        this.checkout(x, this.today);
        break;
      }
      case "INVOICE":
        this.invoice(this.reservation(a[0]));
        break;
      case "AVAIL": {
        this.type(a[0]);
        const [start, end] = this.period(a[1], a[2]);
        this.emit(0, "AVAIL", a[0], a[1], "->", a[2]);
        for (let day = start; day <= end; day++) {
          const rooms = this.sortedRooms().filter(r => r.kind === a[0] && this.free(r, day));
          this.emit(2, dateWeek(day), "free", rooms.length, ...rooms.map(r => r.number));
        }
        break;
      }
      case "OCCUPANCY": {
        const day = this.date(a[0]);
        this.emit(0, "OCCUPANCY", dateWeek(day), this.occupancyText([...this.rooms.values()], day));
        for (const kind of TYPES) {
          const rooms = [...this.rooms.values()].filter(r => r.kind === kind);
          if (rooms.length) this.emit(2, kind, this.occupancyText(rooms, day));
        }
        break;
      }
      case "STATS": {
        const [start, end] = this.period(a[0], a[1]);
        this.emit(0, "STATS", a[0], "->", a[1]);
        const total = {available: 0, occupied: 0, revenue: 0n};
        for (let day = start; day <= end; day++) {
          const m = this.metrics(day);
          this.emit(2, dateWeek(day), this.metricsText(m));
          total.available += m.available;
          total.occupied += m.occupied;
          total.revenue += m.revenue;
        }
        this.emit(2, "total", this.metricsText(total));
        break;
      }
      case "ROOMS": {
        this.emit(0, "ROOMS", dateWeek(this.today), "rooms", this.rooms.size);
        for (const r of this.sortedRooms()) {
          const occupant = this.inHouse(r.number);
          const situation = occupant ? "occupied " + occupant.id : r.blocks.has(this.today) ? "blocked" : "vacant";
          const next = [...this.reservations.values()].filter(x => x.status === "booked" && x.room === r.number).sort(byArrival)[0];
          this.emit(2, r.number, r.kind, "base", money(r.base), "tonight", money(this.rate(r, this.today)), r.clean ? "clean" : "dirty", situation,
            ...(next ? ["next", next.id, dateText(next.start)] : []));
        }
        break;
      }
      case "LIST": {
        const targets = [...this.reservations.values()].filter(x => x.status === a[0]).sort(byArrival);
        this.emit(0, "LIST", a[0], targets.length);
        for (const x of targets) this.emit(2, x.id, x.guest, "room", x.room, dateText(x.start), "->", dateText(x.end));
        break;
      }
      case "QUEUE":
        this.emit(0, "QUEUE", this.queue.length);
        for (let i = 0; i < this.queue.length; i++) {
          const w = this.queue[i];
          this.emit(2, i + 1, w.id, w.guest, w.kind, dateText(w.start), "->", dateText(w.end));
        }
        break;
      case "SCHEDULE": {
        const day = this.date(a[0]);
        const arrivals = [...this.reservations.values()].filter(x => x.start === day && x.status !== "cancelled").sort((a, b) => lex(a.id, b.id));
        const departures = [...this.reservations.values()].filter(x => x.end === day && ["booked", "inhouse", "checkedout"].includes(x.status)).sort((a, b) => lex(a.id, b.id));
        this.emit(0, "SCHEDULE", dateWeek(day), "arrivals", arrivals.length, "departures", departures.length);
        for (const x of arrivals) this.emit(2, "arrival", x.id, x.guest, "room", x.room, x.status);
        for (const x of departures) this.emit(2, "departure", x.id, x.guest, "room", x.room, x.status);
        break;
      }
      case "GUEST": {
        const targets = [...this.reservations.values()].filter(x => x.guest === a[0]);
        if (!targets.length) throw new CommandError("unknown guest " + a[0]);
        this.emit(0, "GUEST", a[0]);
        for (const x of targets) this.emit(2, x.id, "room", x.room, this.rooms.get(x.room).kind, dateText(x.start), "->", dateText(x.end), x.status,
          ["booked", "inhouse"].includes(x.status) ? "deposit" : "paid", money(["booked", "inhouse"].includes(x.status) ? x.deposit : x.paid));
        const tier = this.tier(a[0]);
        this.emit(2, "total", "paid", money(this.guestPaid(a[0])), "points", String(tier.points), "tier", tier.name);
        break;
      }
      case "REVENUE": {
        const [start, end] = this.period(a[0], a[1], false, false);
        const targets = [...this.reservations.values()].filter(x => x.posting !== null && x.posting >= start && x.posting <= end);
        const totals = {lodging: 0n, discount: 0n, penalty: 0n, extras: 0n, tax: 0n, cancellation: 0n, noshow: 0n};
        let checkouts = 0;
        let cancellations = 0;
        let noshows = 0;
        for (const x of targets) {
          if (x.status === "checkedout") {
            checkouts++;
            for (const key of ["lodging", "discount", "penalty", "extras", "tax"]) totals[key] += x.bill[key];
          } else if (x.status === "cancelled") {
            cancellations++;
            totals.cancellation += x.fee;
          } else if (x.status === "noshow") {
            noshows++;
            totals.noshow += x.fee;
          }
        }
        this.emit(0, "REVENUE", a[0], "->", a[1]);
        for (const key of ["lodging", "discount", "penalty", "extras", "tax", "cancellation", "noshow"]) this.emit(2, key, money(totals[key]));
        const total = totals.lodging - totals.discount + totals.penalty + totals.extras + totals.tax + totals.cancellation + totals.noshow;
        this.emit(2, "total", money(total));
        this.emit(2, "checkouts", checkouts, "cancellations", cancellations, "noshows", noshows);
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
      this.emit(0, "ERROR", error.message);
    }
    this.processQueue();
  }
}

const lines = readFileSync(0, "utf8").trimEnd().split("\n");
const hotel = new Hotel();
for (let i = 1; i <= Number(lines[0]); i++) hotel.execute(lines[i]);
process.stdout.write(hotel.output.join("\n") + "\n");
