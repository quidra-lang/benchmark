import { readFileSync } from "node:fs";

type Server = {name: string; parties: number; sales: number; tips: number};
type Table = {number: number; seats: number; check: Check | null};
type Check = {party: string; size: number; table: Table; server: Server; seated: number; lines: Line[]; paid: number; discount: number; closed: boolean};
type MenuItem = {name: string; station: string; prep: number; price: number; course: string; stock: number | null};
type Line = {id: number; check: Check; seat: number; item: string; quantity: number; station: string; prep: number; price: number; course: string; state: string; reason: string | null; fire: number; ready: number; started: boolean};
type Station = {name: string; capacity: number; up: boolean; queue: Line[]; cooking: Line[]; tickets: number[]; remakes: number};
type Amounts = {subtotal: number; discount: number; service: number; tax: number; total: number; due: number};
type Waiting = {party: string; size: number; joined: number};
const STATIONS = ["GRILL", "FRY", "COLD", "BAR"];
const COURSES = ["DRINK", "STARTER", "MAIN", "DESSERT"];
const cents = (s: string): number => Number(s.replace(".", ""));
const money = (v: number): string => Math.floor(v / 100) + "." + String(v % 100).padStart(2, "0");
const clock = (t: number): string => String(Math.floor((660 + t) / 60)).padStart(2, "0") + ":" + String((660 + t) % 60).padStart(2, "0");
const rounded = (v: number, rate: number): number => Math.floor((v * rate + 50) / 100);
const amount = (l: Line): number => l.reason === null ? l.price * l.quantity : 0;
const active = (c: Check): Line[] => c.lines.filter(l => l.state !== "VOID");
const lex = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
class CommandError extends Error {}

class Restaurant {
  now = 0;
  tables = new Map<number, Table>();
  servers: Server[] = [];
  waiting: Waiting[] = [];
  menu = new Map<string, MenuItem>();
  lines: Line[] = [];
  stations = new Map<string, Station>(STATIONS.map(name => [name, {name, capacity: name === "BAR" ? 2 : 1, up: true, queue: [], cooking: [], tickets: [], remakes: 0}]));
  happyRate = 0;
  happyEnd = 0;
  covers = 0;
  parties = 0;
  turns = 0;
  stay = 0;
  sales: Record<string, number> = Object.fromEntries(COURSES.map(c => [c, 0]));
  totals: Record<string, number> = {subtotal: 0, discount: 0, service: 0, tax: 0, total: 0};
  payments: Record<string, number> = {CASH: 0, CARD: 0};
  tips = 0;
  comps = 0;
  compAmount = 0;
  voids = 0;
  served = new Map<string, number>();
  output: string[] = [];

  emit(...parts: (string | number)[]): void {
    this.output.push(parts.join(" "));
  }

  table(text: string): Table {
    const t = this.tables.get(Number(text));
    if (!t) throw new CommandError("unknown table " + text);
    return t;
  }

  check(text: string): Check {
    const t = this.table(text);
    if (!t.check) throw new CommandError("table " + text + " is free");
    return t.check;
  }

  unlocked(c: Check): void {
    if (c.paid > 0) throw new CommandError("check for table " + c.table.number + " is locked");
  }

  line(text: string): Line {
    const n = Number(text);
    if (n < 1 || n > this.lines.length) throw new CommandError("unknown line " + text);
    return this.lines[n - 1];
  }

  modifiable(l: Line): void {
    if (l.state === "VOID") throw new CommandError("#" + l.id + " is void");
    if (l.check.closed) throw new CommandError("#" + l.id + " is on a closed check");
    this.unlocked(l.check);
  }

  unserved(c: Check): void {
    const count = active(c).filter(l => l.state !== "SERVED").length;
    if (count) throw new CommandError("table " + c.table.number + " has " + count + " unserved items");
  }

  station(name: string): Station {
    const s = this.stations.get(name);
    if (!s) throw new CommandError("unknown station " + name);
    return s;
  }

  course(name: string): void {
    if (!COURSES.includes(name)) throw new CommandError("unknown course " + name);
  }

  item(name: string): MenuItem {
    const i = this.menu.get(name);
    if (!i) throw new CommandError("unknown item " + name);
    return i;
  }

  load(server: Server): number {
    return [...this.tables.values()].filter(t => t.check?.server === server).length;
  }

  select(size: number): Table | null {
    return [...this.tables.values()].filter(t => t.check === null && t.seats >= size).sort((a, b) => a.seats - b.seats || a.number - b.number)[0] ?? null;
  }

  seat(party: string, size: number, table: Table): Check {
    let server = this.servers[0];
    for (const candidate of this.servers) {
      if (this.load(candidate) < this.load(server)) server = candidate;
    }
    const c: Check = {party, size, table, server, seated: this.now, lines: [], paid: 0, discount: 0, closed: false};
    table.check = c;
    server.parties++;
    this.covers += size;
    this.parties++;
    return c;
  }

  processWaiting(): void {
    const remaining: Waiting[] = [];
    for (const w of this.waiting) {
      const t = this.select(w.size);
      if (t) {
        const c = this.seat(w.party, w.size, t);
        this.emit("SEATED", w.party, w.size, "table", t.number, "server", c.server.name, "waited", this.now - w.joined);
      } else remaining.push(w);
    }
    this.waiting = remaining;
  }

  amounts(c: Check): Amounts {
    const subtotal = active(c).reduce((v, l) => v + amount(l), 0);
    const discount = rounded(subtotal, c.discount);
    const after = subtotal - discount;
    const service = c.size >= 6 ? rounded(after, 18) : 0;
    const tax = rounded(after, 8);
    const total = after + service + tax;
    return {subtotal, discount, service, tax, total, due: total - c.paid};
  }

  close(c: Check): void {
    const a = this.amounts(c);
    this.turns++;
    this.stay += this.now - c.seated;
    for (const l of active(c)) this.sales[l.course] += amount(l);
    for (const key of ["subtotal", "discount", "service", "tax", "total"]) this.totals[key] += a[key as keyof Amounts];
    c.server.sales += a.total;
    c.closed = true;
    c.table.check = null;
    this.emit("FREE", "table", c.table.number, c.party, "stayed", this.now - c.seated);
    this.processWaiting();
  }

  start(s: Station, time: number): void {
    while (s.up && s.queue.length && s.cooking.length < s.capacity) {
      const l = s.queue.shift()!;
      l.state = "COOKING";
      l.ready = time + l.prep;
      l.started = true;
      s.cooking.push(l);
    }
  }

  tick(minutes: number): void {
    const end = this.now + minutes;
    this.emit("TICK", clock(end));
    while (true) {
      const cooking = [...this.stations.values()].flatMap(s => s.cooking);
      if (!cooking.length) break;
      const time = Math.min(...cooking.map(l => l.ready));
      if (time > end) break;
      for (const name of STATIONS) {
        const s = this.stations.get(name)!;
        const finished = s.cooking.filter(l => l.ready === time).sort((a, b) => a.id - b.id);
        s.cooking = s.cooking.filter(l => l.ready !== time);
        for (const l of finished) {
          l.state = "READY";
          s.tickets.push(time - l.fire);
          this.emit("READY", clock(time), name, "#" + l.id, l.item, "x" + l.quantity, "table", l.check.table.number, "seat", l.seat);
        }
      }
      for (const s of this.stations.values()) this.start(s, time);
    }
    this.now = end;
  }

  seats(c: Check): Map<number, number> {
    const groups = Map.groupBy(active(c), l => l.seat);
    return new Map([...groups].sort((a, b) => a[0] - b[0]).map(([seat, lines]) =>
      [seat, lines.reduce((subtotal, line) => subtotal + amount(line), 0)]));
  }

  allocate(values: Map<number, number>, rate: number): Map<number, number> {
    const result = new Map([...values].map(([seat, v]): [number, number] => [seat, Math.floor(v * rate / 100)]));
    const total = [...values.values()].reduce((a, b) => a + b, 0);
    const left = rounded(total, rate) - [...result.values()].reduce((a, b) => a + b, 0);
    const order = [...values.keys()].sort((a, b) => values.get(b)! * rate % 100 - values.get(a)! * rate % 100 || a - b);
    for (const seat of order.slice(0, left)) result.set(seat, result.get(seat)! + 1);
    return result;
  }

  bill(c: Check): void {
    this.emit("BILL", "table", c.table.number, c.party, "guests", c.size);
    for (const [seat, subtotal] of this.seats(c)) {
      this.emit("SEAT", seat, money(subtotal));
      for (const l of active(c).filter(l => l.seat === seat)) this.emit("#" + l.id, l.item, "x" + l.quantity, money(amount(l)), ...(l.reason === null ? [] : ["COMP", l.reason]));
    }
    const a = this.amounts(c);
    this.emit("SUBTOTAL", money(a.subtotal));
    if (c.discount) this.emit("DISCOUNT", c.discount + "%", money(a.discount));
    if (c.size >= 6) this.emit("SERVICE", money(a.service));
    this.emit("TAX", money(a.tax));
    this.emit("TOTAL", money(a.total));
    if (c.paid > 0) {
      this.emit("PAID", money(c.paid));
      this.emit("DUE", money(a.due));
    }
  }

  report(): void {
    this.emit("REPORT", clock(this.now));
    this.emit("COVERS", this.covers, "parties", this.parties);
    this.emit("TURNS", this.turns, "avg_stay", this.turns ? Math.floor(this.stay / this.turns) : "-");
    this.emit("SALES", ...COURSES.flatMap(c => [c, money(this.sales[c])]));
    this.emit("TOTALS", ...["subtotal", "discount", "service", "tax", "total"].flatMap(k => [k, money(this.totals[k])]));
    this.emit("PAYMENTS", "cash", money(this.payments.CASH), "card", money(this.payments.CARD), "tips", money(this.tips));
    this.emit("COMPS", this.comps, money(this.compAmount), "VOIDS", this.voids);
    const top = [...this.served].filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1] || lex(a[0], b[0])).slice(0, 3);
    top.forEach(([name, count], i) => this.emit("TOP", i + 1, name, count));
    for (const s of this.stations.values()) {
      this.emit(s.name, "tickets", s.tickets.length, "avg", s.tickets.length ? Math.floor(s.tickets.reduce((a, b) => a + b, 0) / s.tickets.length) : "-",
        "max", s.tickets.length ? Math.max(...s.tickets) : "-", "remakes", s.remakes);
    }
    for (const s of this.servers) this.emit("SERVER", s.name, "tables", this.load(s), "parties", s.parties, "sales", money(s.sales), "tips", money(s.tips));
  }

  command(cmd: string, a: string[]): void {
    switch (cmd) {
      case "TABLE": {
        const number = Number(a[0]);
        if (this.tables.has(number)) throw new CommandError("table " + a[0] + " already exists");
        this.tables.set(number, {number, seats: Number(a[1]), check: null});
        this.emit("TABLE", number, "seats", Number(a[1]));
        this.processWaiting();
        break;
      }
      case "STAFF":
        if (this.servers.some(s => s.name === a[0])) throw new CommandError(a[0] + " is already on duty");
        this.servers.push({name: a[0], parties: 0, sales: 0, tips: 0});
        this.emit("STAFF", a[0]);
        break;
      case "SEAT": {
        const seated = [...this.tables.values()].find(t => t.check?.party === a[0]);
        if (seated) throw new CommandError(a[0] + " is already seated at table " + seated.number);
        if (this.waiting.some(w => w.party === a[0])) throw new CommandError(a[0] + " is already waiting");
        const size = Number(a[1]);
        if (![...this.tables.values()].some(t => t.seats >= size)) throw new CommandError("no table for party of " + size);
        if (!this.servers.length) throw new CommandError("no server on duty");
        const t = this.select(size);
        if (t) {
          const c = this.seat(a[0], size, t);
          this.emit("SEAT", a[0], size, "table", t.number, "server", c.server.name);
        } else {
          this.waiting.push({party: a[0], size, joined: this.now});
          this.emit("WAIT", a[0], size, "position", this.waiting.length);
        }
        break;
      }
      case "CANCEL": {
        const i = this.waiting.findIndex(w => w.party === a[0]);
        if (i < 0) throw new CommandError(a[0] + " is not waiting");
        const [w] = this.waiting.splice(i, 1);
        this.emit("CANCEL", w.party, w.size, "waited", this.now - w.joined);
        break;
      }
      case "MOVE": {
        const source = this.table(a[0]);
        const destination = this.table(a[1]);
        if (!source.check) throw new CommandError("table " + a[0] + " is free");
        if (destination.check) throw new CommandError("table " + a[1] + " is occupied");
        const c = source.check;
        if (destination.seats < c.size) throw new CommandError("table " + a[1] + " is too small for " + c.party);
        source.check = null;
        destination.check = c;
        c.table = destination;
        this.emit("MOVE", c.party, "table", source.number, "->", destination.number);
        this.processWaiting();
        break;
      }
      case "MENU": {
        this.station(a[1]);
        this.course(a[4]);
        const old = this.menu.get(a[0]);
        this.menu.set(a[0], {name: a[0], station: a[1], prep: Number(a[2]), price: cents(a[3]), course: a[4], stock: old?.stock ?? null});
        this.emit("MENU", old ? "UPDATE" : "ADD", a[0], a[1], Number(a[2]), money(cents(a[3])), a[4]);
        break;
      }
      case "STOCK": {
        const item = this.item(a[0]);
        item.stock = Number(a[1]);
        this.emit("STOCK", item.name, item.stock);
        break;
      }
      case "HAPPY":
        this.happyRate = Number(a[0]);
        this.happyEnd = this.now + Number(a[1]);
        this.emit("HAPPY", this.happyRate + "%", "until", clock(this.happyEnd));
        break;
      case "ITEMS": {
        const items = [...this.menu.values()].sort((a, b) => COURSES.indexOf(a.course) - COURSES.indexOf(b.course) || lex(a.name, b.name));
        this.emit("ITEMS", items.length);
        for (const i of items) this.emit(i.course, i.name, i.station, i.prep, money(i.price), i.stock === null ? "-" : i.stock);
        break;
      }
      case "ORDER": {
        const c = this.check(a[0]);
        this.unlocked(c);
        const seat = Number(a[1]);
        if (seat > c.size) throw new CommandError("seat " + seat + " out of range for table " + a[0]);
        const item = this.item(a[2]);
        const quantity = Number(a[3]);
        if (item.stock !== null && item.stock < quantity) throw new CommandError("only " + item.stock + " " + item.name + " left");
        const happy = item.course === "DRINK" && this.now < this.happyEnd;
        const price = item.price - (happy ? rounded(item.price, this.happyRate) : 0);
        const l: Line = {id: this.lines.length + 1, check: c, seat, item: item.name, quantity, station: item.station,
          prep: item.prep, price, course: item.course, state: "ORDERED", reason: null, fire: 0, ready: 0, started: false};
        this.lines.push(l);
        c.lines.push(l);
        this.emit("ORDER", "#" + l.id, "table", c.table.number, "seat", seat, item.name, "x" + quantity, money(amount(l)), ...(happy ? ["HAPPY"] : []));
        if (item.stock !== null) {
          item.stock -= quantity;
          if (item.stock === 0) this.emit("SOLDOUT", item.name);
        }
        break;
      }
      case "FIRE": {
        const c = this.check(a[0]);
        this.course(a[1]);
        const lines = c.lines.filter(l => l.course === a[1] && l.state === "ORDERED");
        if (!lines.length) throw new CommandError("nothing to fire for " + a[1] + " at table " + a[0]);
        for (const earlier of ["STARTER", "MAIN", "DESSERT"].slice(0, ["STARTER", "MAIN", "DESSERT"].indexOf(a[1]))) {
          if (a[1] !== "DRINK" && c.lines.some(l => l.course === earlier && l.state === "ORDERED")) throw new CommandError("fire " + earlier + " first");
        }
        for (const l of lines) {
          l.state = "QUEUED";
          l.fire = this.now;
          this.stations.get(l.station)!.queue.push(l);
        }
        this.emit("FIRE", "table", c.table.number, a[1], ...lines.map(l => "#" + l.id));
        for (const s of this.stations.values()) this.start(s, this.now);
        break;
      }
      case "TICK":
        this.tick(Number(a[0]));
        break;
      case "SERVE": {
        const c = this.check(a[0]);
        const lines = c.lines.filter(l => l.state === "READY");
        if (!lines.length) throw new CommandError("nothing ready for table " + a[0]);
        for (const l of lines) {
          l.state = "SERVED";
          this.served.set(l.item, (this.served.get(l.item) ?? 0) + l.quantity);
        }
        this.emit("SERVE", "table", c.table.number, ...lines.map(l => "#" + l.id));
        break;
      }
      case "RUSH": {
        const l = this.line(a[0]);
        if (l.state !== "QUEUED") throw new CommandError("#" + l.id + " is not queued");
        const s = this.stations.get(l.station)!;
        s.queue = [l, ...s.queue.filter(x => x !== l)];
        this.emit("RUSH", "#" + l.id, l.station);
        break;
      }
      case "REMAKE": {
        const l = this.line(a[0]);
        if (l.check.closed) throw new CommandError("#" + l.id + " is on a closed check");
        if (!["READY", "SERVED"].includes(l.state)) throw new CommandError("#" + l.id + " is not ready or served");
        l.state = "QUEUED";
        l.fire = this.now;
        const s = this.stations.get(l.station)!;
        s.queue.unshift(l);
        s.remakes++;
        this.emit("REMAKE", "#" + l.id, l.item, l.station);
        this.start(s, this.now);
        break;
      }
      case "VOID": {
        const l = this.line(a[0]);
        if (l.state === "VOID") throw new CommandError("#" + l.id + " is already void");
        if (l.started) throw new CommandError("#" + l.id + " has already started");
        if (l.state === "QUEUED") {
          const s = this.stations.get(l.station)!;
          s.queue = s.queue.filter(x => x !== l);
        }
        l.state = "VOID";
        const item = this.menu.get(l.item)!;
        if (item.stock !== null) item.stock += l.quantity;
        this.voids++;
        this.emit("VOID", "#" + l.id, l.item, "x" + l.quantity);
        break;
      }
      case "STATION": {
        const s = this.station(a[0]);
        if (a[1] === "DOWN" && !s.up) throw new CommandError("station " + s.name + " is already down");
        if (a[1] === "UP" && s.up) throw new CommandError("station " + s.name + " is not down");
        s.up = a[1] === "UP";
        if (s.up) this.start(s, this.now);
        this.emit("STATION", s.name, a[1]);
        break;
      }
      case "COMP":
      case "TRANSFER": {
        const l = this.line(a[0]);
        this.modifiable(l);
        if (cmd === "COMP") {
          if (l.reason !== null) throw new CommandError("#" + l.id + " is already comped");
          const value = amount(l);
          this.emit("COMP", "#" + l.id, l.item, money(value), a[1]);
          this.comps++;
          this.compAmount += value;
          l.reason = a[1];
        } else {
          const seat = Number(a[1]);
          if (seat > l.check.size) throw new CommandError("seat " + seat + " out of range for table " + l.check.table.number);
          if (seat === l.seat) throw new CommandError("#" + l.id + " is already on seat " + seat);
          this.emit("TRANSFER", "#" + l.id, "seat", l.seat, "->", seat);
          l.seat = seat;
        }
        break;
      }
      case "DISCOUNT": {
        const c = this.check(a[0]);
        this.unlocked(c);
        c.discount = Number(a[1]);
        this.emit("DISCOUNT", "table", c.table.number, c.discount + "%");
        break;
      }
      case "BILL":
        this.bill(this.check(a[0]));
        break;
      case "SPLIT": {
        const c = this.check(a[0]);
        const amounts = this.amounts(c);
        if (amounts.due === 0) throw new CommandError("nothing to split for table " + a[0]);
        if (a[1] === "EVEN") {
          const count = Number(a[2]);
          if (count > c.size) throw new CommandError("cannot split table " + a[0] + " " + count + " ways");
          this.emit("SPLIT", "table", c.table.number, "EVEN", count, "due", money(amounts.due));
          const q = Math.floor(amounts.due / count);
          const r = amounts.due % count;
          for (let i = 1; i <= count; i++) this.emit("PAYER", i, money(q + Number(i <= r)));
        } else {
          if (c.paid > 0) throw new CommandError("table " + a[0] + " has payments");
          const values = this.seats(c);
          const discounts = this.allocate(values, c.discount);
          const after = new Map([...values].map(([seat, v]): [number, number] => [seat, v - discounts.get(seat)!]));
          const services = this.allocate(after, c.size >= 6 ? 18 : 0);
          const taxes = this.allocate(after, 8);
          this.emit("SPLIT", "table", c.table.number, "BYSEAT", "total", money(amounts.total));
          for (const [seat, subtotal] of values) this.emit("SEAT", seat, "subtotal", money(subtotal),
            "discount", money(discounts.get(seat)!), "service", money(services.get(seat)!),
            "tax", money(taxes.get(seat)!), "total", money(after.get(seat)! + services.get(seat)! + taxes.get(seat)!));
        }
        break;
      }
      case "PAY": {
        const c = this.check(a[0]);
        if (!["CASH", "CARD"].includes(a[1])) throw new CommandError("unknown method " + a[1]);
        this.unserved(c);
        const due = this.amounts(c).due;
        if (due === 0) throw new CommandError("nothing to pay for table " + a[0]);
        const value = cents(a[2]);
        const applied = Math.min(value, due);
        c.paid += applied;
        this.payments[a[1]] += applied;
        if (value < due) this.emit("PAY", "table", c.table.number, a[1], money(value), "remaining", money(due - value));
        else {
          this.emit("PAY", "table", c.table.number, a[1], money(value), a[1] === "CASH" ? "change" : "tip", money(value - due));
          if (a[1] === "CARD") {
            this.tips += value - due;
            c.server.tips += value - due;
          }
          this.close(c);
        }
        break;
      }
      case "CLOSE": {
        const c = this.check(a[0]);
        this.unserved(c);
        const due = this.amounts(c).due;
        if (due !== 0) throw new CommandError("table " + a[0] + " still owes " + money(due));
        this.close(c);
        break;
      }
      case "STATUS": {
        const c = this.check(a[0]);
        this.emit("STATUS", "table", c.table.number, c.party, "guests", c.size, "since", clock(c.seated));
        for (const l of c.lines) this.emit("#" + l.id, "seat", l.seat, l.item, "x" + l.quantity, l.course, l.state,
          ...(l.state === "COOKING" ? ["until", clock(l.ready)] : []), ...(l.reason === null ? [] : ["COMP", l.reason]));
        break;
      }
      case "KITCHEN":
        this.emit("KITCHEN", clock(this.now));
        for (const s of this.stations.values()) {
          const cooking = s.cooking.toSorted((a, b) => a.ready - b.ready || a.id - b.id).map(l => "#" + l.id + "@" + clock(l.ready));
          this.emit(s.name, s.up ? "up" : "down", "cooking", cooking.length ? cooking.join(" ") : "-",
            "queue", s.queue.length ? s.queue.map(l => "#" + l.id).join(" ") : "-");
        }
        break;
      case "FLOOR": {
        const tables = [...this.tables.values()].sort((a, b) => a.number - b.number);
        const free = tables.filter(t => t.check === null).length;
        this.emit("FLOOR", clock(this.now), "free", free, "seated", tables.length - free, "waiting", this.waiting.length);
        for (const t of tables) {
          const c = t.check;
          if (!c) this.emit("table", t.number, "seats", t.seats, "free");
          else this.emit("table", t.number, "seats", t.seats, c.party, "guests", c.size, "server", c.server.name,
            "since", clock(c.seated), "items", active(c).length, "total", money(this.amounts(c).total), ...(c.paid > 0 ? ["paid", money(c.paid)] : []));
        }
        this.waiting.forEach((w, i) => this.emit("WAITING", i + 1, w.party, w.size, "since", clock(w.joined)));
        break;
      }
      case "REPORT":
        this.report();
        break;
    }
  }

  execute(line: string): void {
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
const restaurant = new Restaurant();
for (let i = 1; i <= Number(lines[0]); i++) restaurant.execute(lines[i]);
process.stdout.write(restaurant.output.join("\n") + "\n");
