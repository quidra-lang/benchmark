import { readFileSync } from "node:fs";

type Policy = {name: string; args: bigint[]; text: string};
type Initial = {inventory: bigint; quantity: bigint; shipping: number; orders: number; holding: bigint; backlog: bigint; policy: Policy};
type RecordRow = Record<string, bigint>;
type Stage = {inventory: bigint; backlog: bigint; shipping: bigint[]; orders: bigint[]; policy: Policy; expected: bigint; holding: bigint; backlogRate: bigint; lot: bigint; capacity: bigint | null; records: RecordRow[]};
type State = {week: number; demands: bigint[]; stages: Stage[]; plantBacklog: bigint; plantCapacity: bigint | null; plantRecords: RecordRow[]; visibility: string};
const NAMES = ["RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY"];
const PARAMETERS: Record<string, number> = {FIXED: 1, PASS: 0, BASESTOCK: 1, MINMAX: 2, MOVAVG: 2, SMOOTH: 2, STERMAN: 4};
const MODES: Record<string, string> = {ORDERS: "order", INV: "inventory", BACK: "backlog"};
const sum = (v: bigint[]): bigint => v.reduce((a, b) => a + b, 0n);
const min = (...v: bigint[]): bigint => v.reduce((a, b) => a < b ? a : b);
const max = (...v: bigint[]): bigint => v.reduce((a, b) => a > b ? a : b);
const abs = (v: bigint): bigint => v < 0n ? -v : v;
const compare = (a: bigint, b: bigint): number => a < b ? -1 : a > b ? 1 : 0;
const floorDiv = (n: bigint, d: bigint): bigint => n < 0n ? -((-n + d - 1n) / d) : n / d;
const money = (v: bigint): string => v / 100n + "." + String(v % 100n).padStart(2, "0");
const variation = (v: bigint[]): bigint => BigInt(v.length) * sum(v.map(x => x * x)) - sum(v) ** 2n;
function decimal(p: bigint, q: number | bigint, places: number): string {
  const scale = 10n ** BigInt(places);
  const value = p * scale / BigInt(q);
  return value / scale + "." + String(value % scale).padStart(places, "0");
}
class CommandError extends Error {}

function parsePolicy(tokens: string[]): Policy {
  const name = tokens[0];
  if (!Object.hasOwn(PARAMETERS, name)) throw new CommandError("unknown policy " + name);
  const count = PARAMETERS[name];
  if (tokens.length - 1 !== count) throw new CommandError(name + " needs " + count + " parameters");
  const a = tokens.slice(1).map((t, i) => BigInt(name === "STERMAN" && i < 3 ? t.replace(".", "") : t));
  let valid = true;
  if (name === "FIXED") valid = a[0] >= 0n && a[0] <= 1000n;
  else if (name === "BASESTOCK") valid = a[0] >= 0n && a[0] <= 10000n;
  else if (name === "MINMAX") valid = a[0] >= 0n && a[0] < a[1] && a[1] <= 10000n;
  else if (name === "MOVAVG") valid = a[0] >= 1n && a[0] <= 52n && a[1] >= 0n && a[1] <= 10000n;
  else if (name === "SMOOTH") valid = a[0] >= 1n && a[0] <= 10n && a[1] >= 0n && a[1] <= 10000n;
  else if (name === "STERMAN") valid = a.slice(0, 3).every(v => v >= 0n && v <= 100n) && a[3] >= 0n && a[3] <= 10000n;
  if (!valid) throw new CommandError("invalid parameter for " + name);
  return {name, args: a, text: tokens.join(" ")};
}

class Simulation {
  initials: Initial[];
  week = 0;
  demands: bigint[];
  stages: Stage[];
  plantBacklog = 0n;
  plantCapacity: bigint | null = null;
  plantRecords: RecordRow[] = [];
  visibility = "OFF";

  constructor(initials: Initial[], demands: bigint[]) {
    this.initials = initials;
    this.demands = [...demands];
    this.stages = initials.map(i => ({inventory: i.inventory, backlog: 0n,
      shipping: Array(i.shipping).fill(i.quantity), orders: Array(i.orders).fill(i.quantity),
      policy: i.policy, expected: 100n * i.quantity, holding: i.holding, backlogRate: i.backlog,
      lot: 1n, capacity: null, records: []}));
  }

  snapshot(): State {
    return structuredClone({week: this.week, demands: this.demands, stages: this.stages,
      plantBacklog: this.plantBacklog, plantCapacity: this.plantCapacity, plantRecords: this.plantRecords, visibility: this.visibility});
  }

  static restore(initials: Initial[], state: State): Simulation {
    return Object.assign(new Simulation(initials, []), structuredClone(state));
  }

  signal(index: number, week: number, current: bigint[] | null = null): bigint {
    if (this.visibility === "ON") return this.demands[week - 1];
    if (current !== null && week === this.week + 1) return current[index];
    return this.stages[index].records[week - 1].incoming;
  }

  setPolicy(index: number, policy: Policy): void {
    const s = this.stages[index];
    s.policy = policy;
    if (policy.name === "STERMAN") s.expected = 100n * (this.week ? this.signal(index, this.week) : this.initials[index].quantity);
  }

  positions(): {supply: bigint[]; positions: bigint[]} {
    const supply = this.stages.map((s, i) => sum(s.orders) + (i < 3 ? this.stages[i + 1].backlog : this.plantBacklog) + sum(s.shipping));
    return {supply, positions: this.stages.map((s, i) => s.inventory + supply[i] - s.backlog)};
  }

  policyOrder(index: number, incoming: bigint[], line: bigint, position: bigint): bigint {
    const s = this.stages[index];
    const {name, args: a} = s.policy;
    const week = this.week + 1;
    const signal = this.signal(index, week, incoming);
    if (name === "FIXED") return a[0];
    if (name === "PASS") return incoming[index];
    if (name === "BASESTOCK") return max(0n, a[0] - position);
    if (name === "MINMAX") return position <= a[0] ? a[1] - position : 0n;
    if (name === "MOVAVG") {
      const count = Math.min(Number(a[0]), week);
      const signals = Array.from({length: count}, (_, j) => this.signal(index, week - count + j + 1, incoming));
      const forecast = sum(signals) / BigInt(count);
      const delay = this.initials[index].shipping + this.initials[index].orders;
      return max(0n, a[1] + forecast * BigInt(delay) - position);
    }
    if (name === "SMOOTH") return max(0n, signal + floorDiv(a[1] - position, a[0]));
    const [theta, alpha, beta, target] = a;
    s.expected = (100n * theta * signal + (100n - theta) * s.expected) / 100n;
    const net = s.inventory - s.backlog;
    return max(0n, floorDiv(100n * s.expected + alpha * (100n * (target - net) - beta * line), 10000n));
  }

  step(): RecordRow[] {
    const received = this.stages.map(s => {
      const q = s.shipping.shift()!;
      s.inventory += q;
      return q;
    });
    const incoming = [this.demands[this.week], ...this.stages.slice(0, 3).map(s => s.orders.shift()!)];
    const plantIncoming = this.stages[3].orders.shift()!;
    const records: RecordRow[] = [];
    this.stages.forEach((s, i) => {
      const before = s.backlog;
      const requested = before + incoming[i];
      const shipped = min(s.inventory, requested, s.capacity ?? requested);
      s.inventory -= shipped;
      s.backlog = requested - shipped;
      if (i > 0) this.stages[i - 1].shipping.push(shipped);
      records.push({received: received[i], incoming: incoming[i], shipped, before,
        ontime: min(max(0n, shipped - before), incoming[i]), inventory: s.inventory, backlog: s.backlog});
    });
    const requested = this.plantBacklog + plantIncoming;
    const produced = min(requested, this.plantCapacity ?? requested);
    this.plantBacklog = requested - produced;
    this.stages[3].shipping.push(produced);
    const {supply, positions} = this.positions();
    const orders = this.stages.map((_, i) => this.policyOrder(i, incoming, supply[i], positions[i]));
    this.stages.forEach((s, i) => {
      const quantity = (orders[i] + s.lot - 1n) / s.lot * s.lot;
      s.orders.push(quantity);
      const r = records[i];
      r.order = quantity;
      r.holding = s.holding * s.inventory;
      r.backlog_cost = s.backlogRate * s.backlog;
      r.cost = r.holding + r.backlog_cost;
      s.records.push(r);
    });
    this.plantRecords.push({incoming: plantIncoming, produced, backlog: this.plantBacklog});
    this.week++;
    return records;
  }

  costs(): bigint[] {
    return this.stages.map(s => sum(s.records.map(r => r.cost)));
  }
}

class Game {
  initials: Initial[];
  base: bigint[] = [];
  sim: Simulation;
  snapshots = new Map<string, State>();
  output: string[] = [];

  constructor(settings: string[][]) {
    this.initials = settings.map(a => ({inventory: BigInt(a[1]), quantity: BigInt(a[2]),
      shipping: Number(a[3]), orders: Number(a[4]), holding: BigInt(a[5]), backlog: BigInt(a[6]), policy: parsePolicy(a.slice(7))}));
    this.sim = new Simulation(this.initials, []);
  }

  emit(...parts: (string | number | bigint)[]): void {
    this.output.push(parts.join(" "));
  }

  stageIndex(text: string): number {
    const index = NAMES.indexOf(text);
    if (index < 0) throw new CommandError("unknown stage " + text);
    return index;
  }

  target(text: string): number[] {
    return text === "ALL" ? [0, 1, 2, 3] : [this.stageIndex(text)];
  }

  requireWeeks(): void {
    if (this.sim.week === 0) throw new CommandError("no weeks simulated");
  }

  range(a: string[], limit: number): number[] {
    if (!a.length) return [1, limit];
    const [first, last] = a.map(Number);
    if (first < 1 || first > last || last > limit) throw new CommandError("bad range " + a[0] + " " + a[1]);
    return [first, last];
  }

  mode(mode: string): void {
    if (!["ORDERS", "INV", "BACK", "NET"].includes(mode)) throw new CommandError("unknown mode " + mode);
  }

  values(index: number, mode: string): bigint[] {
    return this.sim.stages[index].records.map(r => mode === "NET" ? r.inventory - r.backlog : r[MODES[mode]]);
  }

  initialize(demands: bigint[] | null = null): void {
    if (demands !== null) this.base = [...demands];
    this.sim = new Simulation(this.initials, this.base);
  }

  trial(policies: Policy[]): Simulation {
    const current = this.sim;
    const trial = new Simulation(this.initials, current.demands);
    trial.visibility = current.visibility;
    trial.plantCapacity = current.plantCapacity;
    trial.stages.forEach((s, i) => {
      const old = current.stages[i];
      s.lot = old.lot;
      s.capacity = old.capacity;
      s.holding = old.holding;
      s.backlogRate = old.backlogRate;
      trial.setPolicy(i, policies[i]);
    });
    while (trial.week < trial.demands.length) trial.step();
    return trial;
  }

  demand(values: bigint[]): void {
    this.initialize(values);
    this.emit("DEMAND", "weeks", values.length, "total", sum(values), "min", min(...values), "max", max(...values));
  }

  generate(a: string[]): void {
    const weeks = Number(a[0]);
    const base = BigInt(a[1]);
    const spread = BigInt(a[2]);
    let seed = BigInt(a[3]);
    const changes: {kind: string; week: number; amount: bigint}[] = [];
    for (let i = 4; i < a.length; i += 3) {
      const week = Number(a[i + 1]);
      if (week < 1 || week > weeks) throw new CommandError("week " + a[i + 1] + " outside horizon");
      changes.push({kind: a[i], week, amount: BigInt(a[i + 2])});
    }
    const levels: bigint[] = [];
    for (let week = 1; week <= weeks; week++) {
      let level = base;
      for (const c of changes) {
        if ((c.kind === "STEP" && week >= c.week) || (c.kind === "PULSE" && week === c.week)) level += c.amount;
        else if (c.kind === "RAMP" && week >= c.week) level += c.amount * BigInt(week - c.week + 1);
      }
      if (level < 0n) throw new CommandError("negative level at week " + week);
      levels.push(level);
    }
    const values = levels.map(level => {
      seed = 48271n * seed % 2147483647n;
      return level + seed % spread;
    });
    this.demand(values);
  }

  status(): void {
    const s = this.sim;
    this.emit("STATUS", "week", s.week, "of", s.demands.length);
    const {supply, positions} = s.positions();
    s.stages.forEach((stage, i) => {
      this.emit(NAMES[i], "inv", stage.inventory, "back", stage.backlog,
        "transit", stage.shipping.join(","), "pending", stage.orders.join(","), "supply", supply[i],
        "position", positions[i], "policy", stage.policy.text, ...(stage.policy.name === "STERMAN" ? ["expect", money(stage.expected)] : []));
    });
    this.emit("PLANT", "back", s.plantBacklog);
  }

  fill(records: RecordRow[]): {ordered: bigint; ontime: bigint; text: string} {
    const ordered = sum(records.map(r => r.incoming));
    const ontime = sum(records.map(r => r.ontime));
    return {ordered, ontime, text: ordered === 0n ? "n/a" : decimal(ontime * 100n, ordered, 2) + "%"};
  }

  peaks(): void {
    const s = this.sim;
    this.emit("PEAKS", "weeks", "1-" + s.week);
    s.stages.forEach((stage, i) => {
      const inventories = stage.records.map(r => r.inventory);
      const backlogs = stage.records.map(r => r.backlog);
      const mi = max(...inventories);
      const mb = max(...backlogs);
      let run = 0;
      let longest = 0;
      let start = 0;
      let bestStart = 0;
      let bestEnd = 0;
      backlogs.forEach((backlog, j) => {
        if (backlog > 0n) {
          if (run === 0) start = j + 1;
          run++;
          if (run > longest) {
            longest = run;
            bestStart = start;
            bestEnd = j + 1;
          }
        } else run = 0;
      });
      this.emit(NAMES[i], "max_inv", mi, "week", mi ? inventories.indexOf(mi) + 1 : "-",
        "max_back", mb, "week", mb ? backlogs.indexOf(mb) + 1 : "-",
        "longest_stockout", longest ? longest + " weeks " + bestStart + "-" + bestEnd : 0);
    });
  }

  leadtime(index: number): void {
    const records = this.sim.stages[index].records;
    const initial = this.initials[index];
    const nominal = initial.shipping + initial.orders;
    let received = 0n;
    const cumulative = records.map(r => {
      received += r.received;
      return received - BigInt(nominal) * initial.quantity;
    });
    let ordered = 0n;
    let count = 0;
    const leads: number[] = [];
    records.forEach((r, t) => {
      ordered += r.order;
      if (r.order === 0n) return;
      count++;
      for (let u = t + 1; u < records.length; u++) {
        if (cumulative[u] >= ordered) {
          leads.push(u - t);
          break;
        }
      }
    });
    this.emit("LEADTIME", NAMES[index], "nominal", nominal, "orders", count, "completed", leads.length,
      "open", count - leads.length, "min", leads.length ? Math.min(...leads) : "-",
      "avg", leads.length ? decimal(BigInt(leads.reduce((a, b) => a + b, 0)), leads.length, 2) : "-", "max", leads.length ? Math.max(...leads) : "-");
  }

  plot(index: number, mode: string, first: number, last: number): void {
    const values = this.values(index, mode).slice(first - 1, last);
    const maximum = max(...values);
    if (mode === "NET") {
      this.emit("PLOT", NAMES[index], mode, first + "-" + last, "min", min(...values), "max", maximum);
      const scale = max(...values.map(abs));
      values.forEach((value, i) => {
        const length = scale === 0n ? 0 : Number(abs(value) * 25n / scale);
        const left = value < 0n ? " ".repeat(25 - length) + "-".repeat(length) : " ".repeat(25);
        const right = value > 0n ? "+".repeat(length) : "";
        this.emit(String(first + i).padStart(3, " ") + " " + left + "|" + right + " " + value);
      });
    } else {
      this.emit("PLOT", NAMES[index], mode, first + "-" + last, "max", maximum);
      values.forEach((value, i) => {
        const length = maximum === 0n ? 0 : Number(value * 50n / maximum);
        this.emit(String(first + i).padStart(3, " ") + " |" + "#".repeat(length) + " " + value);
      });
    }
  }

  command(cmd: string, a: string[]): void {
    const s = this.sim;
    switch (cmd) {
      case "DEMAND":
        this.demand(a.map(BigInt));
        break;
      case "GENERATE":
        this.generate(a);
        break;
      case "RUN": {
        if (s.week === s.demands.length) throw new CommandError("horizon reached at week " + s.demands.length);
        const first = s.week + 1;
        const count = Math.min(Number(a[0]), s.demands.length - s.week);
        let cost = 0n;
        for (let j = 0; j < count; j++) {
          s.step().forEach((r, i) => {
            cost += r.cost;
            if (r.before === 0n && r.backlog > 0n) this.emit("STOCKOUT", NAMES[i], "week", s.week, "backlog", r.backlog);
            else if (r.before > 0n && r.backlog === 0n) this.emit("RECOVER", NAMES[i], "week", s.week);
          });
        }
        this.emit("RUN", first + "-" + s.week, "demand", sum(s.demands.slice(first - 1, s.week)), "cost", money(cost));
        if (s.week === s.demands.length) this.emit("HORIZON", s.week);
        break;
      }
      case "RESET":
        this.initialize();
        this.emit("RESET", "week", 0);
        break;
      case "SAVE":
        this.snapshots.set(a[0], s.snapshot());
        this.emit("SAVE", a[0], "week", s.week);
        break;
      case "LOAD": {
        const state = this.snapshots.get(a[0]);
        if (!state) throw new CommandError("no snapshot " + a[0]);
        this.sim = Simulation.restore(this.initials, state);
        this.emit("LOAD", a[0], "week", this.sim.week);
        break;
      }
      case "SET": {
        const indices = this.target(a[0]);
        const policy = parsePolicy(a.slice(1));
        for (const i of indices) s.setPolicy(i, policy);
        this.emit("SET", a[0], policy.text);
        break;
      }
      case "BATCH": {
        const i = this.stageIndex(a[0]);
        const lot = BigInt(a[1]);
        if (lot < 1n || lot > 100n) throw new CommandError("invalid batch size " + a[1]);
        s.stages[i].lot = lot;
        this.emit("BATCH", a[0], lot);
        break;
      }
      case "CAPACITY": {
        const i = a[0] === "PLANT" ? null : this.stageIndex(a[0]);
        const capacity = a[1] === "OFF" ? null : BigInt(a[1]);
        if (capacity !== null && capacity > 10000n) throw new CommandError("invalid capacity " + a[1]);
        if (i === null) s.plantCapacity = capacity;
        else s.stages[i].capacity = capacity;
        this.emit("CAPACITY", a[0], a[1]);
        break;
      }
      case "COST": {
        const i = this.stageIndex(a[0]);
        const holding = BigInt(a[1]);
        const backlog = BigInt(a[2]);
        if (holding > 1000n || backlog > 1000n) throw new CommandError("invalid cost");
        s.stages[i].holding = holding;
        s.stages[i].backlogRate = backlog;
        this.emit("COST", a[0], "holding", holding, "backlog", backlog);
        break;
      }
      case "VISIBILITY":
        if (!["ON", "OFF"].includes(a[0])) throw new CommandError("unknown visibility " + a[0]);
        s.visibility = a[0];
        this.emit("VISIBILITY", a[0]);
        break;
      case "SHOCK": {
        const week = Number(a[0]);
        if (week < 1 || week > s.demands.length) throw new CommandError("week " + a[0] + " outside horizon");
        if (week <= s.week) throw new CommandError("week " + a[0] + " already simulated");
        const old = s.demands[week - 1];
        s.demands[week - 1] = BigInt(a[1]);
        this.emit("SHOCK", "week", week, old, "->", BigInt(a[1]));
        break;
      }
      case "STATUS":
        this.status();
        break;
      case "SETTINGS":
        this.emit("SETTINGS");
        s.stages.forEach((stage, i) => this.emit(NAMES[i], "holding", stage.holding, "backlog", stage.backlogRate,
          "batch", stage.lot, "capacity", stage.capacity === null ? "OFF" : stage.capacity, "delays", this.initials[i].shipping, this.initials[i].orders));
        this.emit("PLANT", "capacity", s.plantCapacity === null ? "OFF" : s.plantCapacity);
        this.emit("VISIBILITY", s.visibility);
        break;
      case "WEEK": {
        this.requireWeeks();
        const week = Number(a[0]);
        if (week < 1 || week > s.week) throw new CommandError("bad week " + a[0]);
        this.emit("WEEK", week, "demand", s.demands[week - 1]);
        s.stages.forEach((stage, i) => {
          const r = stage.records[week - 1];
          this.emit(NAMES[i], "recv", r.received, "in", r.incoming, "ship", r.shipped, "inv", r.inventory, "back", r.backlog, "order", r.order, "cost", money(r.cost));
        });
        const p = s.plantRecords[week - 1];
        this.emit("PLANT", "in", p.incoming, "made", p.produced, "back", p.backlog);
        break;
      }
      case "TABLE": {
        const i = this.stageIndex(a[0]);
        this.requireWeeks();
        const [first, last] = this.range(a.slice(1), s.week);
        this.emit("TABLE", a[0], first + "-" + last);
        const widths = [4, 6, 6, 6, 6, 6, 6, 9];
        this.emit(["week", "in", "ship", "recv", "inv", "back", "order", "cost"].map((v, j) => v.padStart(widths[j], " ")).join(" "));
        for (let week = first; week <= last; week++) {
          const r = s.stages[i].records[week - 1];
          const values = [week, r.incoming, r.shipped, r.received, r.inventory, r.backlog, r.order, money(r.cost)];
          this.emit(values.map((v, j) => String(v).padStart(widths[j], " ")).join(" "));
        }
        break;
      }
      case "CHAIN": {
        this.requireWeeks();
        const [first, last] = this.range(a, s.week);
        this.emit("CHAIN", first + "-" + last);
        this.emit("week".padStart(4, " ") + " " + "demand".padStart(6, " ") + " " + NAMES.map(n => n.padStart(11, " ")).join(" "));
        for (let week = first; week <= last; week++) this.emit(String(week).padStart(4, " ") + " " +
          String(s.demands[week - 1]).padStart(6, " ") + " " + s.stages.map(stage => String(stage.records[week - 1].order).padStart(11, " ")).join(" "));
        break;
      }
      case "DEMANDS": {
        const [first, last] = this.range(a, s.demands.length);
        const values = s.demands.slice(first - 1, last);
        this.emit("DEMANDS", first + "-" + last, "total", sum(values), "min", min(...values), "max", max(...values));
        this.emit(...values);
        break;
      }
      case "COSTS": {
        this.emit("COSTS", "week", s.week);
        let totalHolding = 0n;
        let totalBacklog = 0n;
        s.stages.forEach((stage, i) => {
          const holding = sum(stage.records.map(r => r.holding));
          const backlog = sum(stage.records.map(r => r.backlog_cost));
          totalHolding += holding;
          totalBacklog += backlog;
          this.emit(NAMES[i], "holding", money(holding), "backlog", money(backlog), "total", money(holding + backlog));
        });
        this.emit("TOTAL", "holding", money(totalHolding), "backlog", money(totalBacklog), "total", money(totalHolding + totalBacklog));
        break;
      }
      case "SUMMARY":
        this.requireWeeks();
        this.emit("SUMMARY", "weeks", "1-" + s.week);
        s.stages.forEach((stage, i) => {
          const orders = stage.records.map(r => r.order);
          this.emit(NAMES[i], "avg_inv", decimal(sum(stage.records.map(r => r.inventory)), s.week, 2),
            "avg_back", decimal(sum(stage.records.map(r => r.backlog)), s.week, 2), "orders", sum(orders),
            "min", min(...orders), "max", max(...orders), "zero_weeks", orders.filter(v => v === 0n).length);
        });
        break;
      case "BALANCE":
        this.emit("BALANCE", "week", s.week);
        s.stages.forEach((stage, i) => this.emit(NAMES[i], "start", this.initials[i].inventory,
          "received", sum(stage.records.map(r => r.received)), "shipped", sum(stage.records.map(r => r.shipped)), "end", stage.inventory, "owed", stage.backlog));
        this.emit("SYSTEM", "initial", sum(this.initials.map(i => i.inventory + i.quantity * BigInt(i.shipping))),
          "produced", sum(s.plantRecords.map(r => r.produced)), "delivered", sum(s.stages[0].records.map(r => r.shipped)),
          "stock", sum(s.stages.map(stage => stage.inventory)), "transit", sum(s.stages.map(stage => sum(stage.shipping))));
        break;
      case "FILLRATE":
        this.requireWeeks();
        this.emit("FILLRATE", "weeks", "1-" + s.week);
        s.stages.forEach((stage, i) => {
          const f = this.fill(stage.records);
          const stockouts = stage.records.filter(r => r.backlog > 0n).length;
          this.emit(NAMES[i], "fill", f.text, "ontime", f.ontime, "ordered", f.ordered, "stockout_weeks", stockouts,
            "service", decimal(BigInt((s.week - stockouts) * 100), s.week, 2) + "%");
        });
        break;
      case "BULLWHIP": {
        this.requireWeeks();
        const n = s.week;
        const demand = s.demands.slice(0, n);
        const dv = variation(demand);
        this.emit("BULLWHIP", "weeks", "1-" + n, "demand", "mean", decimal(sum(demand), n, 4), "var", decimal(dv, n * n, 4));
        let previous = dv;
        s.stages.forEach((stage, i) => {
          const values = stage.records.map(r => r.order);
          const v = variation(values);
          this.emit(NAMES[i], "mean", decimal(sum(values), n, 4), "var", decimal(v, n * n, 4),
            "ratio", dv === 0n ? "n/a" : decimal(v, dv, 4), "step", previous === 0n ? "n/a" : decimal(v, previous, 4));
          previous = v;
        });
        break;
      }
      case "PEAKS":
        this.requireWeeks();
        this.peaks();
        break;
      case "LEADTIME": {
        const i = this.stageIndex(a[0]);
        this.requireWeeks();
        this.leadtime(i);
        break;
      }
      case "PLOT":
      case "HISTOGRAM": {
        const i = this.stageIndex(a[0]);
        this.mode(a[1]);
        const width = cmd === "HISTOGRAM" ? BigInt(a[2]) : 1n;
        if (cmd === "HISTOGRAM" && (width < 1n || width > 100n)) throw new CommandError("invalid width " + a[2]);
        this.requireWeeks();
        if (cmd === "PLOT") {
          const [first, last] = this.range(a.slice(2), s.week);
          this.plot(i, a[1], first, last);
        } else {
          const bins = new Map<bigint, number>();
          for (const value of this.values(i, a[1])) {
            const bucket = floorDiv(value, width);
            bins.set(bucket, (bins.get(bucket) ?? 0) + 1);
          }
          this.emit("HISTOGRAM", a[0], a[1], "width", width, "weeks", "1-" + s.week);
          for (let bucket = min(...bins.keys()); bucket <= max(...bins.keys()); bucket++) {
            const count = bins.get(bucket) ?? 0;
            this.emit(bucket * width + ".." + (bucket * width + width - 1n), count, ...(count ? ["*".repeat(count)] : []));
          }
        }
        break;
      }
      case "COMPARE": {
        const policies: Policy[] = [];
        let start = 0;
        for (let end = 0; end <= a.length; end++) {
          if (end === a.length || a[end] === "/") {
            policies.push(parsePolicy(a.slice(start, end)));
            start = end + 1;
          }
        }
        const rows = policies.map((policy, index) => {
          const trial = this.trial([policy, policy, policy, policy]);
          const cost = sum(trial.costs());
          const fill = this.fill(trial.stages[0].records).text;
          const dv = variation(trial.demands);
          const fv = variation(trial.stages[3].records.map(r => r.order));
          return {policy, index, cost, fill, ratio: dv === 0n ? "n/a" : decimal(fv, dv, 4)};
        });
        rows.sort((a, b) => compare(a.cost, b.cost) || a.index - b.index);
        this.emit("COMPARE", policies.length, "weeks", s.demands.length);
        rows.forEach((r, i) => this.emit(i + 1, r.policy.text, "total", money(r.cost), "fill", r.fill, "bullwhip", r.ratio));
        break;
      }
      case "OPTIMIZE": {
        const indices = this.target(a[0]);
        const low = Number(a[1]);
        const high = Number(a[2]);
        if (low > high) throw new CommandError("bad range " + a[1] + " " + a[2]);
        if (high - low > 200) throw new CommandError("range too large");
        let best: {objective: bigint; target: number; total: bigint} | null = null;
        for (let target = low; target <= high; target++) {
          const policies = s.stages.map(stage => stage.policy);
          for (const i of indices) policies[i] = {name: "BASESTOCK", args: [BigInt(target)], text: "BASESTOCK " + target};
          const costs = this.trial(policies).costs();
          const objective = sum(indices.map(i => costs[i]));
          if (best === null || objective < best.objective) best = {objective, target, total: sum(costs)};
        }
        this.emit("OPTIMIZE", a[0], "BASESTOCK", best!.target, "cost", money(best!.objective), "total", money(best!.total));
        break;
      }
      default:
        throw new CommandError("unknown command " + cmd);
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
const game = new Game(lines.slice(0, 4).map(line => line.split(" ")));
for (const line of lines.slice(4)) {
  if (line === "END") break;
  game.execute(line);
}
if (game.output.length) process.stdout.write(game.output.join("\n") + "\n");
