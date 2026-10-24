import { readFileSync } from "node:fs";


const RATE_SETTINGS = ["STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED", "UIRATE", "MATCH", "MATCHMAX", "GARNCAP"];
const INITIAL = {
  STATE: 500n, SUPP: 2200n, SSRATE: 620n, MEDRATE: 145n, ADDMED: 90n,
  UIRATE: 270n, MATCH: 5000n, MATCHMAX: 600n, GARNCAP: 2500n,
  SSBASE: 16860000n, ADDBASE: 20000000n, UIBASE: 700000n,
  RETIRECAP: 2300000n, ALLOWANCE: 15000n, NIGHT: 100n
};
const FIELDS = ["R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
  "sales", "commission", "earnings", "bonus", "gross", "retirement", "health", "federal",
  "supplemental", "state", "social", "medicare", "garnishment", "net", "employer_social",
  "employer_medicare", "unemployment", "match", "employer", "W", "Y", "F", "J"];
const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const cents = (s) => BigInt(s.replace(".", ""));
const money = (v) => v / 100n + "." + String(v % 100n).padStart(2, "0");
const rateText = (v) => money(v) + "%";
const duration = (v) => BigInt(v) / 60n + ":" + String(BigInt(v) % 60n).padStart(2, "0");
const clock = (v) => String(Math.floor(v / 60)).padStart(2, "0") + ":" + String(v % 60).padStart(2, "0");
const weekday = (d) => WEEKDAYS[(d - 1) % 7];
const periodOf = (d) => Math.floor((d - 1) / 14) + 1;
const compare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const min = (...values) => values.reduce((a, b) => a < b ? a : b);
const max = (a, b) => a > b ? a : b;
const emptyTotals = () => Object.fromEntries(FIELDS.map(f => [f, 0n]));
class CommandError extends Error {}

function sumStubs(stubs) {
  return Object.fromEntries(FIELDS.map(field => [field, stubs.reduce((total, stub) => total + stub[field], 0n)]));
}

function progressive(table, amount) {
  const pairs = [...table].sort((a, b) => compare(a[0], b[0]));
  let numerator = 0n;
  for (let i = 0; i < pairs.length; i++) {
    const [lower, rate] = pairs[i];
    if (lower >= amount) break;
    const upper = i + 1 < pairs.length ? pairs[i + 1][0] : amount;
    numerator += rate * (min(amount, upper) - lower);
  }
  return numerator / 10000n;
}

class Employee {
  id;
  department;
  kind;
  base;
  active = true;
  retirement = 0n;
  health = 0n;
  allowances = 0;
  extra = 0n;
  garnishments = [];
  bonus = 0n;
  ptoBalance = 0;
  shifts = new Map();
  pto = new Map();
  leave = new Set();
  sales = new Map();
  stubs = new Map();
  ytd = emptyTotals();
  periods = 0;

  constructor(id, department, kind, base) {
    this.id = id;
    this.department = department;
    this.kind = kind;
    this.base = base;
  }

  garnishmentBalance() {
    return this.garnishments.reduce((v, order) => v + order.balance, 0n);
  }
}

class Payroll {
  settings = {...INITIAL};
  brackets = new Map();
  tiers = new Map();
  holidays = new Set();
  employees = new Map();
  closed = 0;
  output = [];

  emit(indent, ...parts) {
    this.output.push(" ".repeat(indent) + parts.join(" "));
  }

  employee(text, active = false, kind = null) {
    const e = this.employees.get(Number(text));
    if (!e) throw new CommandError("unknown employee " + text);
    if (active && !e.active) throw new CommandError("terminated employee " + text);
    if (kind !== null && e.kind !== kind) throw new CommandError("not " + kind.toLowerCase() + " " + text);
    return e;
  }

  dayCheck(text) {
    const day = Number(text);
    if (day < 1 || day > 364) throw new CommandError("invalid day " + text);
    const period = periodOf(day);
    if (period <= this.closed) throw new CommandError("period closed " + period);
    return day;
  }

  periodCheck(text) {
    const p = Number(text);
    if (p < 1 || p > 26) throw new CommandError("invalid period " + text);
    return p;
  }

  rateCheck(text) {
    const value = cents(text);
    if (value > 10000n) throw new CommandError("invalid rate " + text);
    return value;
  }

  amountCheck(text) {
    const value = cents(text);
    if (value === 0n) throw new CommandError("invalid amount");
    return value;
  }

  timeCheck(text) {
    const [hour, minute] = text.split(":").map(Number);
    if (hour > 23 || minute > 59) throw new CommandError("invalid time " + text);
    return hour * 60 + minute;
  }

  daily(e, day) {
    const shifts = e.shifts.get(day) ?? [];
    const worked = shifts.reduce((v, [s, t]) => v + t - s, 0);
    const night = shifts.reduce((v, [s, t]) => v + Math.max(0, Math.min(t, 360) - s) + Math.max(0, t - Math.max(s, 1320)), 0);
    const pto = e.pto.get(day) ?? 0;
    if (day % 7 === 0 || this.holidays.has(day)) return [worked, 0, 0, worked, night, pto];
    return [worked, Math.min(worked, 480), Math.min(Math.max(worked - 480, 0), 240), Math.max(worked - 720, 0), night, pto];
  }

  weekly(e, week) {
    const values = [0, 0, 0, 0, 0];
    for (let day = 7 * week - 6; day <= 7 * week; day++) {
      const daily = this.daily(e, day);
      for (let i = 0; i < 5; i++) values[i] += daily[i + 1];
    }
    const overtime = Math.max(0, values[0] - 2400);
    values[0] -= overtime;
    values[1] += overtime;
    return {values, overtime};
  }

  breakdown(e, p) {
    const a = this.weekly(e, 2 * p - 1).values;
    const b = this.weekly(e, 2 * p).values;
    return a.map((v, i) => v + b[i]);
  }

  calculate(e, p) {
    const s = emptyTotals();
    const c = this.settings;
    const ytd = e.ytd;
    if (e.kind === "HOURLY") {
      const values = this.breakdown(e, p);
      for (let i = 0; i < 5; i++) s[["R", "O", "D", "N", "P"][i]] = BigInt(values[i]);
      const weighted = 2n * (s.R + s.P) + 3n * s.O + 4n * s.D;
      s.earnings = (weighted * e.base + 2n * s.N * c.NIGHT) / 120n;
    } else if (e.kind === "SALARIED") {
      if (e.active) {
        s.salary = e.base / 26n;
        s.leave = BigInt([...e.leave].filter(d => periodOf(d) === p && !this.holidays.has(d)).length);
        s.deduction = s.leave * (e.base / 260n);
        s.earnings = s.salary - s.deduction;
      }
    } else {
      s.sales = e.sales.get(p) ?? 0n;
      s.commission = progressive(this.tiers, s.sales);
      s.earnings = s.commission + (e.active ? e.base : 0n);
    }
    s.bonus = e.bonus;
    const gross = s.earnings + s.bonus;
    if (gross === 0n) return null;
    s.gross = gross;
    let remaining = gross;
    const deduct = (field, value) => {
      s[field] = min(value, remaining);
      remaining -= s[field];
    };
    const retirementRoom = max(0n, c.RETIRECAP - ytd.retirement);
    deduct("retirement", min(gross * e.retirement / 10000n, retirementRoom));
    deduct("health", e.health);
    s.W = remaining;
    const baseTaxable = max(0n, s.earnings - s.retirement - s.health);
    const allowanceTaxable = max(0n, baseTaxable - BigInt(e.allowances) * c.ALLOWANCE);
    deduct("federal", progressive(this.brackets, allowanceTaxable) + e.extra);
    deduct("supplemental", (s.W - baseTaxable) * c.SUPP / 10000n);
    deduct("state", s.W * c.STATE / 10000n);
    s.F = gross - s.health;
    s.Y = min(s.F, max(0n, c.SSBASE - ytd.Y));
    const additional = max(0n, min(s.F, ytd.F + s.F - c.ADDBASE));
    deduct("social", s.Y * c.SSRATE / 10000n);
    deduct("medicare", s.F * c.MEDRATE / 10000n + additional * c.ADDMED / 10000n);
    const disposable = remaining;
    const cap = disposable * c.GARNCAP / 10000n;
    const balances = [];
    let garnishment = 0n;
    for (const order of e.garnishments) {
      const taken = min(disposable * order.rate / 10000n, order.balance, cap - garnishment);
      garnishment += taken;
      balances.push(order.balance - taken);
    }
    s.garnishment = garnishment;
    s.garnishment_balance = balances.reduce((v, b) => v + b, 0n);
    s.net = remaining - garnishment;
    s.employer_social = s.Y * c.SSRATE / 10000n;
    s.employer_medicare = s.F * c.MEDRATE / 10000n;
    s.J = min(s.F, max(0n, c.UIBASE - ytd.J));
    s.unemployment = s.J * c.UIRATE / 10000n;
    s.match = min(s.retirement, gross * c.MATCHMAX / 10000n) * c.MATCH / 10000n;
    s.employer = s.employer_social + s.employer_medicare + s.unemployment + s.match;
    if (e.kind === "HOURLY") s.accrued = min(BigInt(960 - e.ptoBalance), (s.R + s.O + s.D) / 20n);
    s.pto_balance = BigInt(e.ptoBalance) + s.accrued;
    return {values: s, balances};
  }

  hoursParts(values) {
    return values.flatMap((v, i) => [["reg", "ot", "dbl", "night", "pto"][i], duration(v)]);
  }

  stubBlock(e, s, indent) {
    if (e.kind === "HOURLY") {
      this.emit(indent, "hours", ...this.hoursParts(["R", "O", "D", "N", "P"].map(f => s[f])));
      this.emit(indent, "pto", "accrued", duration(s.accrued), "balance", duration(s.pto_balance));
    } else if (e.kind === "SALARIED") {
      this.emit(indent, "salary", money(s.salary), "leave", s.leave, "deduction", money(s.deduction));
    } else {
      this.emit(indent, "sales", money(s.sales), "commission", money(s.commission));
    }
    for (const f of ["earnings", "bonus", "gross", "retirement", "health", "federal", "supplemental", "state", "social", "medicare"]) {
      this.emit(indent, f === "social" ? "social-security" : f, money(s[f]));
    }
    this.emit(indent, "garnishment", money(s.garnishment), "balance", money(s.garnishment_balance));
    this.emit(indent, "net", money(s.net));
    this.emit(indent, "employer", "social-security", money(s.employer_social), "medicare", money(s.employer_medicare),
      "unemployment", money(s.unemployment), "match", money(s.match));
  }

  printStub(e, p, s, department) {
    this.emit(2, "STUB", e.id, department, e.kind, "period", p);
    this.stubBlock(e, s, 4);
  }

  showHours(e, p) {
    this.emit(0, "HOURS", e.id, "period", p);
    let found = false;
    for (let day = 14 * p - 13; day <= 14 * p; day++) {
      const shifts = [...(e.shifts.get(day) ?? [])].sort((a, b) => a[0] - b[0]);
      if (!shifts.length && !e.pto.has(day)) continue;
      const [worked, ...values] = this.daily(e, day);
      this.emit(2, "day", day, weekday(day), ...(this.holidays.has(day) ? ["holiday"] : []),
        ...shifts.map(([s, t]) => clock(s) + "-" + clock(t)), "total", duration(worked), ...this.hoursParts(values));
      found = true;
    }
    if (!found) this.emit(2, "(none)");
    for (const week of [2 * p - 1, 2 * p]) {
      const {values, overtime} = this.weekly(e, week);
      this.emit(2, "week", week, ...this.hoursParts(values), "weekly-ot", duration(overtime));
    }
    this.emit(2, "total", ...this.hoursParts(this.breakdown(e, p)));
  }

  run(p) {
    this.closed = p;
    this.emit(0, "RUN", p, "days", (14 * p - 13) + "-" + 14 * p);
    let paid = 0;
    let skipped = 0;
    const stubs = [];
    for (const e of [...this.employees.values()].sort((a, b) => a.id - b.id)) {
      const calculated = this.calculate(e, p);
      if (calculated === null) {
        if (e.active) skipped++;
        continue;
      }
      const {values: s, balances} = calculated;
      this.printStub(e, p, s, e.department);
      e.bonus = 0n;
      e.ptoBalance = Number(s.pto_balance);
      for (let i = 0; i < balances.length; i++) e.garnishments[i].balance = balances[i];
      for (const field of FIELDS) e.ytd[field] += s[field];
      e.periods++;
      e.stubs.set(p, {values: s, department: e.department});
      stubs.push(s);
      paid++;
    }
    const t = sumStubs(stubs);
    this.emit(2, "TOTAL", "paid", paid, "skipped", skipped, "gross", money(t.gross),
      "deductions", money(t.gross - t.net), "net", money(t.net), "employer", money(t.employer));
  }

  journal(p) {
    const stubs = [...this.employees.values()].filter(e => e.stubs.has(p)).map(e => e.stubs.get(p).values);
    const t = sumStubs(stubs);
    const rows = [
      ["debit", "wages", t.gross],
      ["debit", "employer-tax", t.employer_social + t.employer_medicare + t.unemployment],
      ["debit", "retirement-match", t.match],
      ["credit", "retirement", t.retirement + t.match],
      ["credit", "health", t.health],
      ["credit", "federal", t.federal + t.supplemental],
      ["credit", "state", t.state],
      ["credit", "fica", t.social + t.medicare + t.employer_social + t.employer_medicare],
      ["credit", "unemployment", t.unemployment],
      ["credit", "garnishment", t.garnishment],
      ["credit", "net-pay", t.net]
    ];
    this.emit(0, "JOURNAL", p, "stubs", stubs.length);
    for (const [side, label, value] of rows) this.emit(2, side, label, money(value));
    const debit = rows.filter(r => r[0] === "debit").reduce((v, r) => v + r[2], 0n);
    const credit = rows.filter(r => r[0] === "credit").reduce((v, r) => v + r[2], 0n);
    this.emit(2, "total", "debit", money(debit), "credit", money(credit));
  }

  reportLine(department, stubs) {
    const t = sumStubs(stubs);
    const taxes = t.federal + t.supplemental + t.state + t.social + t.medicare;
    this.emit(2, department, "stubs", stubs.length, "gross", money(t.gross), "pretax", money(t.retirement + t.health),
      "taxes", money(taxes), "garnishment", money(t.garnishment), "net", money(t.net), "employer", money(t.employer));
  }

  command(cmd, a) {
    switch (cmd) {
      case "SET": {
        const name = a[0];
        if (!Object.hasOwn(this.settings, name)) throw new CommandError("unknown setting " + name);
        const value = RATE_SETTINGS.includes(name) ? this.rateCheck(a[1]) : cents(a[1]);
        const formatter = RATE_SETTINGS.includes(name) ? rateText : money;
        const old = this.settings[name];
        this.settings[name] = value;
        this.emit(0, "SET", name, formatter(old), "->", formatter(value));
        break;
      }
      case "BRACKET":
      case "TIER": {
        const rate = this.rateCheck(a[1]);
        const table = cmd === "BRACKET" ? this.brackets : this.tiers;
        const lower = cents(a[0]);
        const action = table.has(lower) ? "replaced" : "added";
        table.set(lower, rate);
        this.emit(0, cmd, money(lower), rateText(rate), action);
        break;
      }
      case "EMP": {
        const id = Number(a[0]);
        if (this.employees.has(id)) throw new CommandError("duplicate employee " + a[0]);
        const base = this.amountCheck(a[3]);
        this.employees.set(id, new Employee(id, a[1], a[2], base));
        this.emit(0, "EMP", id, a[1], a[2], money(base));
        break;
      }
      case "RATE":
      case "DEPT":
      case "BENEFIT":
      case "W4":
      case "GARNISH":
      case "TERM":
      case "BONUS": {
        const e = this.employee(a[0], true);
        if (cmd === "RATE") {
          const base = this.amountCheck(a[1]);
          const old = e.base;
          e.base = base;
          this.emit(0, "RATE", e.id, money(old), "->", money(base));
        } else if (cmd === "DEPT") {
          if (a[1] === e.department) throw new CommandError("same department " + a[1]);
          const old = e.department;
          e.department = a[1];
          this.emit(0, "DEPT", e.id, old, "->", a[1]);
        } else if (cmd === "BENEFIT") {
          const rate = this.rateCheck(a[1]);
          e.retirement = rate;
          e.health = cents(a[2]);
          this.emit(0, "BENEFIT", e.id, "retirement", rateText(rate), "health", money(e.health));
        } else if (cmd === "W4") {
          e.allowances = Number(a[1]);
          e.extra = cents(a[2]);
          this.emit(0, "W4", e.id, "allowances", e.allowances, "extra", money(e.extra));
        } else if (cmd === "GARNISH") {
          const rate = this.rateCheck(a[1]);
          const balance = this.amountCheck(a[2]);
          e.garnishments.push({rate, balance});
          this.emit(0, "GARNISH", e.id, "order", e.garnishments.length, rateText(rate), "balance", money(balance));
        } else if (cmd === "TERM") {
          e.active = false;
          this.emit(0, "TERM", e.id);
        } else {
          const amount = this.amountCheck(a[1]);
          e.bonus += amount;
          this.emit(0, "BONUS", e.id, money(amount), "pending", money(e.bonus));
        }
        break;
      }
      case "HOLIDAY": {
        const day = this.dayCheck(a[0]);
        if (this.holidays.has(day)) throw new CommandError("duplicate holiday " + a[0]);
        this.holidays.add(day);
        this.emit(0, "HOLIDAY", day, weekday(day));
        break;
      }
      case "TIME":
      case "UNTIME":
      case "PTO":
      case "LEAVE":
      case "SALES": {
        const kind = cmd === "LEAVE" ? "SALARIED" : cmd === "SALES" ? "COMMISSION" : "HOURLY";
        const e = this.employee(a[0], true, kind);
        const day = this.dayCheck(a[1]);
        if (cmd === "TIME") {
          const start = this.timeCheck(a[2]);
          const end = this.timeCheck(a[3]);
          if (start >= end) throw new CommandError("invalid shift " + a[2] + "-" + a[3]);
          const shifts = [...(e.shifts.get(day) ?? [])].sort((a, b) => a[0] - b[0]);
          for (const [s, t] of shifts) {
            if (start < t && s < end) throw new CommandError("overlapping shift " + clock(s) + "-" + clock(t));
          }
          if (shifts.reduce((v, [s, t]) => v + t - s, 0) + end - start > 960) throw new CommandError("daily limit " + a[0] + " " + a[1]);
          if (!e.shifts.has(day)) e.shifts.set(day, []);
          e.shifts.get(day).push([start, end]);
          this.emit(0, "TIME", e.id, "day", day, clock(start) + "-" + clock(end), duration(end - start));
        } else if (cmd === "UNTIME") {
          const start = this.timeCheck(a[2]);
          const shifts = e.shifts.get(day) ?? [];
          const i = shifts.findIndex(s => s[0] === start);
          if (i < 0) throw new CommandError("no shift " + a[0] + " " + a[1] + " " + a[2]);
          const [shift] = shifts.splice(i, 1);
          this.emit(0, "UNTIME", e.id, "day", day, clock(shift[0]) + "-" + clock(shift[1]));
        } else if (cmd === "PTO") {
          const [hour, minute] = a[2].split(":").map(Number);
          const length = hour * 60 + minute;
          if (minute > 59 || length < 1 || length > 480) throw new CommandError("invalid duration " + a[2]);
          if (e.pto.has(day)) throw new CommandError("duplicate pto " + a[0] + " " + a[1]);
          if (length > e.ptoBalance) throw new CommandError("insufficient pto " + a[0] + " " + duration(e.ptoBalance));
          e.pto.set(day, length);
          e.ptoBalance -= length;
          this.emit(0, "PTO", e.id, "day", day, duration(length), "balance", duration(e.ptoBalance));
        } else if (cmd === "LEAVE") {
          if ([0, 6].includes(day % 7) || this.holidays.has(day)) throw new CommandError("not workday " + a[1]);
          if (e.leave.has(day)) throw new CommandError("duplicate leave " + a[0] + " " + a[1]);
          e.leave.add(day);
          this.emit(0, "LEAVE", e.id, "day", day, weekday(day));
        } else {
          const amount = this.amountCheck(a[2]);
          const p = periodOf(day);
          e.sales.set(p, (e.sales.get(p) ?? 0n) + amount);
          this.emit(0, "SALES", e.id, "day", day, money(amount), "period", p, "total", money(e.sales.get(p)));
        }
        break;
      }
      case "HOURS": {
        const e = this.employee(a[0], false, "HOURLY");
        this.showHours(e, this.periodCheck(a[1]));
        break;
      }
      case "RUN": {
        const p = Number(a[0]);
        if (p !== this.closed + 1 || p > 26) throw new CommandError("invalid period " + a[0]);
        this.run(p);
        break;
      }
      case "PREVIEW": {
        const e = this.employee(a[0]);
        const p = this.closed + 1;
        const calculated = this.calculate(e, p);
        this.emit(0, "PREVIEW", e.id, "period", p);
        if (calculated === null) this.emit(2, "no pay");
        else this.printStub(e, p, calculated.values, e.department);
        break;
      }
      case "REPRINT": {
        const e = this.employee(a[0]);
        const p = this.periodCheck(a[1]);
        const saved = e.stubs.get(p);
        if (!saved) throw new CommandError("no stub " + a[0] + " " + a[1]);
        this.emit(0, "REPRINT", e.id, p);
        this.printStub(e, p, saved.values, saved.department);
        break;
      }
      case "YTD": {
        const e = this.employee(a[0]);
        this.emit(0, "YTD", e.id, e.department, e.kind, e.active ? "active" : "terminated", "periods", e.periods);
        const s = {...e.ytd, pto_balance: BigInt(e.ptoBalance), garnishment_balance: e.garnishmentBalance()};
        this.stubBlock(e, s, 2);
        this.emit(2, "wages", "federal", money(s.W), "social-security", money(s.Y), "medicare", money(s.F), "unemployment", money(s.J));
        this.emit(2, "retirement-room", money(max(0n, this.settings.RETIRECAP - s.retirement)), "pending-bonus", money(e.bonus));
        break;
      }
      case "JOURNAL": {
        const p = Number(a[0]);
        if (p < 1 || p > this.closed) throw new CommandError("no run " + a[0]);
        this.journal(p);
        break;
      }
      case "REPORT": {
        const saved = [...this.employees.values()].flatMap(e => [...e.stubs.values()]);
        const departments = Map.groupBy(saved, stub => stub.department);
        this.emit(0, "REPORT", "period", this.closed);
        for (const department of [...departments.keys()].sort()) {
          this.reportLine(department, departments.get(department).map(stub => stub.values));
        }
        this.reportLine("total", saved.map(stub => stub.values));
        break;
      }
      case "TOP": {
        const k = Number(a[0]);
        const employees = [...this.employees.values()].filter(e => e.periods > 0).sort((a, b) => compare(b.ytd.gross, a.ytd.gross) || a.id - b.id);
        this.emit(0, "TOP", k);
        for (let i = 0; i < Math.min(k, employees.length); i++) {
          const e = employees[i];
          this.emit(2, i + 1, e.id, e.department, "gross", money(e.ytd.gross), "net", money(e.ytd.net));
        }
        if (!employees.length) this.emit(2, "(none)");
        break;
      }
      case "EMPLOYEES": {
        this.emit(0, "EMPLOYEES");
        for (const e of [...this.employees.values()].sort((a, b) => a.id - b.id)) {
          this.emit(2, e.id, e.department, e.kind, money(e.base), e.active ? "active" : "terminated", "retirement", rateText(e.retirement),
            "health", money(e.health), "allowances", e.allowances, "extra", money(e.extra), "bonus", money(e.bonus));
          for (let i = 0; i < e.garnishments.length; i++) {
            const order = e.garnishments[i];
            this.emit(4, "garnish", i + 1, rateText(order.rate), "balance", money(order.balance));
          }
        }
        if (!this.employees.size) this.emit(2, "(none)");
        break;
      }
      case "CONFIG":
        this.emit(0, "CONFIG");
        for (const [name, value] of Object.entries(this.settings)) this.emit(2, name, RATE_SETTINGS.includes(name) ? rateText(value) : money(value));
        for (const [label, table] of [["bracket", this.brackets], ["tier", this.tiers]]) {
          for (const [lower, rate] of [...table].sort((a, b) => compare(a[0], b[0]))) this.emit(2, label, money(lower), rateText(rate));
        }
        break;
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
  }
}

const lines = readFileSync(0, "utf8").trimEnd().split("\n");
const payroll = new Payroll();
for (let i = 1; i <= Number(lines[0]); i++) payroll.execute(lines[i]);
process.stdout.write(payroll.output.join("\n") + "\n");
