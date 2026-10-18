import { readFileSync } from "node:fs";

type Tier = {limit: number | null; unit: bigint; flat: bigint};
type Plan = {name: string; price: bigint; cycle: string; length: number; trial: number; setup: bigint; perSeat: boolean; mode: string | null; tiers: Tier[]};
type Customer = {name: string; region: string; method: string; balance: bigint; log: {day: number; description: string; change: bigint; balance: bigint}[]};
type Coupon = {name: string; kind: string; value: bigint; applications: number | null; maximum: number | null; redeemed: number};
type Subscription = {id: number; customer: Customer; plan: Plan; seats: number; state: string; start: number; end: number; trialEnd: number | null; pauseStart: number | null; pending: {plan: Plan; seats: number} | null; cancelEnd: boolean; cancelOn: number | null; canceledOn: number | null; coupon: Coupon | null; left: number | null; usage: number};
type Item = {description: string; amount: bigint};
type Quote = {subtotal: bigint; discount: bigint; tax: bigint; total: bigint; credit: bigint; due: bigint};
type Invoice = Quote & {id: number; sub: Subscription; day: number; kind: string; items: Item[]; paid: bigint; refunded: bigint; outstanding: bigint; attempts: number; retries: number[]};
type EventRow = {day: number; id: number; from: string; to: string};
const LENGTH: Record<string, number> = {WEEKLY: 7, MONTHLY: 30, YEARLY: 360};
const cents = (s: string): bigint => BigInt(s.replace(".", ""));
const min = (a: bigint, b: bigint): bigint => a < b ? a : b;
const fee = (p: Plan, seats: number): bigint => p.price * BigInt(p.perSeat ? seats : 1);
const period = (s: Subscription): string => s.start + "-" + s.end;
const sum = (v: bigint[]): bigint => v.reduce((a, b) => a + b, 0n);
function money(v: bigint): string {
  const a = v < 0n ? -v : v;
  return (v < 0n ? "-" : "") + a / 100n + "." + String(a % 100n).padStart(2, "0");
}
const percent = (v: bigint): string => money(v) + "%";
class CommandError extends Error {}

class Billing {
  day = 1;
  plans = new Map<string, Plan>();
  taxes = new Map<string, bigint>();
  customers = new Map<string, Customer>();
  coupons = new Map<string, Coupon>();
  subs: Subscription[] = [];
  invoices: Invoice[] = [];
  events: EventRow[] = [];
  output: string[] = [];

  emit(indent: number, ...parts: (string | number)[]): void {
    this.output.push(" ".repeat(indent) + parts.join(" "));
  }

  plan(name: string): Plan {
    const p = this.plans.get(name);
    if (!p) throw new CommandError("unknown plan " + name);
    return p;
  }

  customer(name: string): Customer {
    const c = this.customers.get(name);
    if (!c) throw new CommandError("unknown customer " + name);
    return c;
  }

  coupon(name: string): Coupon {
    const c = this.coupons.get(name);
    if (!c) throw new CommandError("unknown coupon " + name);
    if (c.maximum !== null && c.redeemed === c.maximum) throw new CommandError("coupon exhausted " + name);
    return c;
  }

  sub(text: string): Subscription {
    const id = Number(text);
    if (id < 1 || id > this.subs.length) throw new CommandError("unknown sub " + text);
    return this.subs[id - 1];
  }

  invoice(text: string): Invoice {
    const id = Number(text);
    if (id < 1 || id > this.invoices.length) throw new CommandError("unknown invoice " + text);
    return this.invoices[id - 1];
  }

  state(s: Subscription, allowed: string[]): void {
    if (!allowed.includes(s.state)) throw new CommandError("invalid state " + s.id + " " + s.state);
  }

  balance(c: Customer, description: string, change: bigint): void {
    if (change === 0n) return;
    c.balance += change;
    c.log.push({day: this.day, description, change, balance: c.balance});
  }

  subInvoices(s: Subscription): Invoice[] {
    return this.invoices.filter(i => i.sub === s);
  }

  changeState(s: Subscription, to: string): void {
    const from = s.state;
    this.emit(2, "day", this.day, "sub", s.id, from, "->", to);
    this.events.push({day: this.day, id: s.id, from, to});
    if (from === "PAST_DUE") {
      for (const i of this.subInvoices(s)) i.retries = [];
    }
    s.state = to;
  }

  usageItem(s: Subscription, close = false): Item[] {
    if (s.plan.mode === null || s.usage === 0) return [];
    const p = s.plan;
    const units = s.usage;
    let charge = 0n;
    let lower = 0;
    for (let k = 0; k < p.tiers.length; k++) {
      const tier = p.tiers[k];
      const last = k === p.tiers.length - 1;
      if (p.mode === "VOLUME") {
        if (last || tier.limit === null || tier.limit >= units) {
          charge = BigInt(units) * tier.unit + tier.flat;
          break;
        }
      } else if (lower < units) {
        const upper = last || tier.limit === null ? units : Math.min(units, tier.limit);
        charge += BigInt(upper - lower) * tier.unit + tier.flat;
      }
      if (tier.limit !== null) lower = tier.limit;
    }
    if (close) s.usage = 0;
    return [{description: "usage " + p.name + " " + units + " units", amount: charge}];
  }

  chargeItem(p: Plan, seats: number, start: number): Item {
    return {description: "charge " + p.name + " seats " + seats + " " + start + "-" + (start + p.length), amount: fee(p, seats)};
  }

  opening(s: Subscription, start: number): Item[] {
    const items = [this.chargeItem(s.plan, s.seats, start)];
    if (s.plan.setup > 0n) items.push({description: "setup " + s.plan.name, amount: s.plan.setup});
    return items;
  }

  quote(s: Subscription, items: Item[]): Quote {
    const subtotal = sum(items.map(i => i.amount));
    let discount = 0n;
    if (s.coupon !== null && (s.left === null || s.left > 0) && subtotal > 0n) {
      discount = s.coupon.kind === "PERCENT" ? subtotal * s.coupon.value / 10000n : min(s.coupon.value, subtotal);
    }
    const tax = (subtotal - discount) * (this.taxes.get(s.customer.region) ?? 0n) / 10000n;
    const total = subtotal - discount + tax;
    const credit = min(s.customer.balance, total);
    return {subtotal, discount, tax, total, credit, due: total - credit};
  }

  issue(s: Subscription, kind: string, items: Item[]): void {
    const q = this.quote(s, items);
    if (s.coupon !== null && (s.left === null || s.left > 0) && q.subtotal > 0n && s.left !== null) s.left--;
    const i: Invoice = {...q, id: this.invoices.length + 1, sub: s, day: this.day, kind, items,
      paid: 0n, refunded: 0n, outstanding: q.due, attempts: 0, retries: []};
    this.invoices.push(i);
    this.balance(s.customer, "applied invoice " + i.id, -q.credit);
    let result = "PAID";
    if (q.due > 0n) {
      if (s.state === "UNPAID") result = "OPEN";
      else {
        i.attempts = 1;
        if (s.customer.method === "OK") {
          i.paid = q.due;
          i.outstanding = 0n;
        } else result = "FAILED";
      }
    }
    this.emit(2, "day", this.day, "invoice", i.id, "sub", s.id, kind,
      "total", money(q.total), "credit", money(q.credit), "due", money(q.due), result);
    if (result === "FAILED") {
      if (s.state === "ACTIVE") this.changeState(s, "PAST_DUE");
      if (s.state === "PAST_DUE") i.retries = [this.day + 3, this.day + 5, this.day + 7];
    }
  }

  complete(i: Invoice): void {
    i.retries = [];
    const s = i.sub;
    if (["PAST_DUE", "UNPAID"].includes(s.state) && this.subInvoices(s).every(i => i.outstanding === 0n)) {
      s.cancelOn = null;
      this.changeState(s, "ACTIVE");
    }
  }

  cancel(s: Subscription): void {
    this.changeState(s, "CANCELED");
    s.canceledOn = this.day;
    s.pending = null;
    s.cancelEnd = false;
    s.cancelOn = null;
    const items = this.usageItem(s, true);
    if (items.length) this.issue(s, "final", items);
  }

  advance(target: number): void {
    while (this.day < target) {
      this.day++;
      for (const s of this.subs) {
        if (["PAUSED", "CANCELED"].includes(s.state)) continue;
        for (const i of this.subInvoices(s)) {
          if (i.retries[0] !== this.day) continue;
          i.retries.shift();
          i.attempts++;
          if (s.customer.method === "OK") {
            i.paid += i.outstanding;
            i.outstanding = 0n;
            this.emit(2, "day", this.day, "retry", i.attempts - 1, "invoice", i.id, "PAID");
            this.complete(i);
          } else {
            this.emit(2, "day", this.day, "retry", i.attempts - 1, "invoice", i.id, "FAILED");
            if (!i.retries.length) {
              this.changeState(s, "UNPAID");
              s.cancelOn = this.day + 14;
            }
          }
        }
        if (s.state === "UNPAID" && s.cancelOn === this.day) this.cancel(s);
        if (s.state === "TRIALING" && s.trialEnd === this.day) {
          if (s.cancelEnd) this.cancel(s);
          else {
            this.changeState(s, "ACTIVE");
            s.start = this.day;
            s.end = this.day + s.plan.length;
            this.issue(s, "first", this.opening(s, this.day));
          }
        }
        if (["ACTIVE", "PAST_DUE", "UNPAID"].includes(s.state) && s.end === this.day) {
          if (s.cancelEnd) this.cancel(s);
          else {
            const items = this.usageItem(s, true);
            if (s.pending) {
              this.emit(2, "day", this.day, "sub", s.id, s.plan.name, "seats", s.seats,
                "->", s.pending.plan.name, "seats", s.pending.seats);
              s.plan = s.pending.plan;
              s.seats = s.pending.seats;
              s.pending = null;
            }
            s.start = this.day;
            s.end = this.day + s.plan.length;
            items.push(this.chargeItem(s.plan, s.seats, this.day));
            this.issue(s, "renewal", items);
          }
        }
      }
    }
  }

  totals(q: Quote): void {
    this.emit(2, "subtotal", money(q.subtotal), "discount", money(q.discount), "tax", money(q.tax), "total", money(q.total));
  }

  showSub(s: Subscription): void {
    this.emit(0, "SUB", s.id, s.customer.name, s.plan.name, "seats", s.seats, s.state);
    if (s.state === "TRIALING") this.emit(2, "trial", "until", s.trialEnd!);
    if (["ACTIVE", "PAST_DUE", "UNPAID", "PAUSED"].includes(s.state)) this.emit(2, "period", period(s));
    if (s.state === "PAUSED") this.emit(2, "paused", "since", s.pauseStart!);
    if (s.pending) this.emit(2, "pending", s.pending.plan.name, "seats", s.pending.seats);
    if (s.cancelEnd) this.emit(2, "cancel", "at", "end");
    if (s.cancelOn !== null) this.emit(2, "cancel", "on", s.cancelOn);
    if (s.state === "CANCELED") this.emit(2, "canceled", "on", s.canceledOn!);
    if (s.coupon && (s.left === null || s.left > 0)) this.emit(2, "coupon", s.coupon.name, ...(s.left === null ? ["forever"] : ["left", s.left]));
    if (s.plan.mode !== null && s.state !== "CANCELED") this.emit(2, "usage", s.usage);
    const open = this.subInvoices(s).filter(i => i.outstanding > 0n);
    if (open.length) this.emit(2, "open", ...open.map(i => i.id));
  }

  preview(s: Subscription): void {
    this.state(s, ["TRIALING", "ACTIVE", "PAST_DUE", "UNPAID"]);
    const day = s.state === "TRIALING" ? s.trialEnd! : s.end;
    let kind: string;
    let items: Item[];
    if (s.cancelEnd) {
      kind = "final";
      items = s.state === "TRIALING" ? [] : this.usageItem(s);
    } else if (s.state === "TRIALING") {
      kind = "first";
      items = this.opening(s, day);
    } else {
      kind = "renewal";
      items = this.usageItem(s);
      const p = s.pending?.plan ?? s.plan;
      const seats = s.pending?.seats ?? s.seats;
      items.push(this.chargeItem(p, seats, day));
    }
    this.emit(0, "PREVIEW", "sub", s.id, "day", day, kind);
    for (const item of items) this.emit(2, item.description, money(item.amount));
    if (!items.length) this.emit(2, "(none)");
    else {
      const q = this.quote(s, items);
      this.totals(q);
      this.emit(2, "credit", money(q.credit), "due", money(q.due));
    }
  }

  command(cmd: string, a: string[]): void {
    switch (cmd) {
      case "PLAN": {
        if (this.plans.has(a[0])) throw new CommandError("duplicate plan " + a[0]);
        const p: Plan = {name: a[0], price: cents(a[1]), cycle: a[2], length: LENGTH[a[2]],
          trial: 0, setup: 0n, perSeat: false, mode: null, tiers: []};
        for (let i = 3; i < a.length; i++) {
          if (a[i] === "TRIAL") p.trial = Number(a[++i]);
          else if (a[i] === "SETUP") p.setup = cents(a[++i]);
          else if (a[i] === "PERSEAT") p.perSeat = true;
          else p.mode = a[i];
        }
        this.plans.set(p.name, p);
        const parts: (string | number)[] = ["PLAN", p.name, p.cycle, money(p.price)];
        if (p.trial) parts.push("trial", p.trial);
        if (p.setup > 0n) parts.push("setup", money(p.setup));
        if (p.perSeat) parts.push("perseat");
        if (p.mode) parts.push(p.mode.toLowerCase());
        this.emit(0, ...parts);
        break;
      }
      case "TIER": {
        const p = this.plan(a[0]);
        if (p.mode === null) throw new CommandError("not metered " + a[0]);
        const limit = a[1] === "INF" ? null : Number(a[1]);
        const last = p.tiers[p.tiers.length - 1];
        if (last && (last.limit === null || (limit !== null && limit <= last.limit))) throw new CommandError("tier order " + a[0]);
        p.tiers.push({limit, unit: cents(a[2]), flat: cents(a[3])});
        this.emit(0, "TIER", p.name, p.tiers.length, "upto", a[1], "unit", money(cents(a[2])), "flat", money(cents(a[3])));
        break;
      }
      case "TAX":
        this.taxes.set(a[0], BigInt(a[1]));
        this.emit(0, "TAX", a[0], percent(BigInt(a[1])));
        break;
      case "CUSTOMER":
        if (this.customers.has(a[0])) throw new CommandError("duplicate customer " + a[0]);
        this.customers.set(a[0], {name: a[0], region: a[1], method: "OK", balance: 0n, log: []});
        this.emit(0, "CUSTOMER", a[0], "region", a[1]);
        break;
      case "COUPON": {
        if (this.coupons.has(a[0])) throw new CommandError("duplicate coupon " + a[0]);
        const applications = a[3] === "FOREVER" ? null : a[3] === "ONCE" ? 1 : Number(a[4]);
        const maxIndex = a.indexOf("MAX");
        const maximum = maxIndex < 0 ? null : Number(a[maxIndex + 1]);
        const value = a[1] === "PERCENT" ? BigInt(a[2]) : cents(a[2]);
        this.coupons.set(a[0], {name: a[0], kind: a[1], value, applications, maximum, redeemed: 0});
        this.emit(0, "COUPON", a[0], a[1].toLowerCase(), a[1] === "PERCENT" ? percent(value) : money(value),
          a[3].toLowerCase(), ...(a[3] === "REPEATING" ? [applications!] : []), ...(maximum === null ? [] : ["max", maximum]));
        break;
      }
      case "PAYMETHOD": {
        const c = this.customer(a[0]);
        c.method = a[1];
        this.emit(0, "PAYMETHOD", c.name, c.method);
        break;
      }
      case "CREDIT": {
        const c = this.customer(a[0]);
        const amount = cents(a[1]);
        if (amount === 0n) throw new CommandError("invalid amount");
        this.balance(c, "grant", amount);
        this.emit(0, "CREDIT", c.name, "amount", money(amount), "balance", money(c.balance));
        break;
      }
      case "DAY": {
        const day = Number(a[0]);
        if (day <= this.day) throw new CommandError("invalid day " + a[0]);
        this.emit(0, "DAY", day);
        this.advance(day);
        break;
      }
      case "SUBSCRIBE": {
        const c = this.customer(a[0]);
        const p = this.plan(a[1]);
        const seatIndex = a.indexOf("SEATS");
        if (seatIndex >= 0 && !p.perSeat) throw new CommandError("not per-seat " + p.name);
        const seats = seatIndex < 0 ? 1 : Number(a[seatIndex + 1]);
        if (seats === 0) throw new CommandError("invalid seats");
        const couponIndex = a.indexOf("COUPON");
        const coupon = couponIndex < 0 ? null : this.coupon(a[couponIndex + 1]);
        if (coupon) coupon.redeemed++;
        const s: Subscription = {id: this.subs.length + 1, customer: c, plan: p, seats, state: "NONE",
          start: 0, end: 0, trialEnd: null, pauseStart: null, pending: null, cancelEnd: false,
          cancelOn: null, canceledOn: null, coupon, left: coupon?.applications ?? null, usage: 0};
        this.subs.push(s);
        this.emit(0, "SUBSCRIBE", "sub", s.id, c.name, p.name, "seats", seats, ...(coupon ? ["coupon", coupon.name] : []));
        if (p.trial) {
          s.trialEnd = this.day + p.trial;
          this.changeState(s, "TRIALING");
        } else {
          this.changeState(s, "ACTIVE");
          s.start = this.day;
          s.end = this.day + p.length;
          this.issue(s, "first", this.opening(s, this.day));
        }
        break;
      }
      case "CHANGE": {
        const s = this.sub(a[0]);
        this.state(s, ["ACTIVE", "TRIALING"]);
        let p = s.plan;
        let seats = s.seats;
        if (a[1] === "PLAN") {
          p = this.plan(a[2]);
          if (!p.perSeat) seats = 1;
        } else {
          if (!p.perSeat) throw new CommandError("not per-seat " + p.name);
          seats = Number(a[2]);
          if (seats === 0) throw new CommandError("invalid seats");
        }
        if (p === s.plan && seats === s.seats) throw new CommandError("no change " + s.id);
        s.pending = null;
        const old = s.plan;
        const oldSeats = s.seats;
        const oldFee = fee(old, oldSeats);
        const newFee = fee(p, seats);
        const head: (string | number)[] = ["CHANGE", "sub", s.id, old.name, "seats", oldSeats, "->", p.name, "seats", seats];
        if (s.state === "TRIALING") {
          s.plan = p;
          s.seats = seats;
          this.emit(0, ...head, "now");
        } else if (newFee * BigInt(old.length) > oldFee * BigInt(p.length)) {
          this.emit(0, ...head, "now");
          const days = s.end - this.day;
          const items = this.usageItem(s, true);
          items.push({description: "unused " + old.name + " seats " + oldSeats + " " + days + " days", amount: -(oldFee * BigInt(days) / BigInt(old.length))});
          items.push({description: "remaining " + p.name + " seats " + seats + " " + days + " days", amount: newFee * BigInt(days) / BigInt(p.length)});
          s.plan = p;
          s.seats = seats;
          this.issue(s, "upgrade", items);
        } else {
          s.pending = {plan: p, seats};
          this.emit(0, ...head, "at", s.end);
        }
        break;
      }
      case "PAUSE": {
        const s = this.sub(a[0]);
        this.state(s, ["ACTIVE"]);
        this.emit(0, "PAUSE", "sub", s.id);
        s.pauseStart = this.day;
        this.changeState(s, "PAUSED");
        break;
      }
      case "RESUME": {
        const s = this.sub(a[0]);
        this.state(s, ["PAUSED"]);
        const shift = this.day - s.pauseStart!;
        s.end += shift;
        this.emit(0, "RESUME", "sub", s.id, "shift", shift, "period", period(s));
        s.pauseStart = null;
        this.changeState(s, "ACTIVE");
        break;
      }
      case "CANCEL": {
        const s = this.sub(a[0]);
        if (a[1] === "NOW") {
          this.state(s, ["TRIALING", "ACTIVE", "PAST_DUE", "UNPAID", "PAUSED"]);
          const remaining = s.state === "ACTIVE" ? s.end - this.day : s.state === "PAUSED" ? s.end - s.pauseStart! : 0;
          const refund = fee(s.plan, s.seats) * BigInt(remaining) / BigInt(s.plan.length);
          this.balance(s.customer, "cancel sub " + s.id, refund);
          this.emit(0, "CANCEL", "sub", s.id, "now", "credit", money(refund));
          this.cancel(s);
        } else {
          this.state(s, ["ACTIVE", "TRIALING"]);
          if (s.cancelEnd) throw new CommandError("already canceling " + s.id);
          s.cancelEnd = true;
          this.emit(0, "CANCEL", "sub", s.id, "end", s.state === "TRIALING" ? s.trialEnd! : s.end);
        }
        break;
      }
      case "USAGE": {
        const s = this.sub(a[0]);
        this.state(s, ["ACTIVE", "PAST_DUE"]);
        if (s.plan.mode === null) throw new CommandError("not metered " + s.plan.name);
        const units = Number(a[1]);
        if (units === 0) throw new CommandError("invalid units");
        s.usage += units;
        this.emit(0, "USAGE", "sub", s.id, "units", units, "total", s.usage);
        break;
      }
      case "APPLY": {
        const s = this.sub(a[0]);
        this.state(s, ["TRIALING", "ACTIVE", "PAST_DUE", "UNPAID", "PAUSED"]);
        const coupon = this.coupon(a[1]);
        coupon.redeemed++;
        s.coupon = coupon;
        s.left = coupon.applications;
        this.emit(0, "APPLY", "sub", s.id, "coupon", coupon.name);
        break;
      }
      case "PAY": {
        const i = this.invoice(a[0]);
        if (i.outstanding === 0n) throw new CommandError("already paid " + a[0]);
        this.emit(0, "PAY", "invoice", i.id, "amount", money(i.outstanding));
        i.paid += i.outstanding;
        i.outstanding = 0n;
        this.complete(i);
        break;
      }
      case "REFUND": {
        const i = this.invoice(a[0]);
        const amount = cents(a[1]);
        if (amount === 0n) throw new CommandError("invalid amount");
        if (amount > i.total - i.refunded) throw new CommandError("refund exceeds " + a[0] + " " + money(i.total - i.refunded));
        const applied = min(amount, i.outstanding);
        i.refunded += amount;
        i.outstanding -= applied;
        this.balance(i.sub.customer, "refund invoice " + i.id, amount - applied);
        this.emit(0, "REFUND", "invoice", i.id, "amount", money(amount), "applied", money(applied), "balance", money(i.sub.customer.balance));
        if (applied > 0n && i.outstanding === 0n) this.complete(i);
        break;
      }
      case "INVOICE": {
        const i = this.invoice(a[0]);
        this.emit(0, "INVOICE", i.id, "sub", i.sub.id, i.sub.customer.name, "day", i.day, i.kind, i.outstanding > 0n ? "OPEN" : "PAID");
        for (const item of i.items) this.emit(2, item.description, money(item.amount));
        this.totals(i);
        this.emit(2, "credit", money(i.credit), "due", money(i.due), "paid", money(i.paid), "refunded", money(i.refunded), "outstanding", money(i.outstanding));
        break;
      }
      case "SUB":
        this.showSub(this.sub(a[0]));
        break;
      case "PREVIEW":
        this.preview(this.sub(a[0]));
        break;
      case "STATEMENT":
      case "LEDGER": {
        const c = this.customer(a[0]);
        if (cmd === "LEDGER") {
          this.emit(0, "LEDGER", c.name, "balance", money(c.balance));
          for (const row of c.log) this.emit(2, "day", row.day, row.description, (row.change > 0n ? "+" : "") + money(row.change), "balance", money(row.balance));
          if (!c.log.length) this.emit(2, "(none)");
        } else {
          this.emit(0, "STATEMENT", c.name, "region", c.region, "tax", percent(this.taxes.get(c.region) ?? 0n), "method", c.method, "balance", money(c.balance));
          for (const s of this.subs.filter(s => s.customer === c)) this.emit(2, "sub", s.id, s.plan.name, s.state);
          const invoices = this.invoices.filter(i => i.sub.customer === c);
          for (const i of invoices) this.emit(2, "invoice", i.id, "day", i.day, "sub", i.sub.id, i.kind, "total", money(i.total), "outstanding", money(i.outstanding));
          this.emit(2, "outstanding", money(sum(invoices.map(i => i.outstanding))));
        }
        break;
      }
      case "MRR": {
        const rows = new Map<string, {count: number; value: bigint}>();
        for (const s of this.subs) {
          if (!["ACTIVE", "PAST_DUE"].includes(s.state)) continue;
          const amount = fee(s.plan, s.seats);
          const mrr = s.plan.cycle === "MONTHLY" ? amount : s.plan.cycle === "YEARLY" ? amount / 12n : amount * 30n / 7n;
          if (!rows.has(s.plan.name)) rows.set(s.plan.name, {count: 0, value: 0n});
          const row = rows.get(s.plan.name)!;
          row.count++;
          row.value += mrr;
        }
        this.emit(0, "MRR");
        for (const name of [...rows.keys()].sort()) {
          const row = rows.get(name)!;
          this.emit(2, name, "subs", row.count, "mrr", money(row.value));
        }
        this.emit(2, "total", "subs", [...rows.values()].reduce((n, r) => n + r.count, 0), "mrr", money(sum([...rows.values()].map(r => r.value))));
        break;
      }
      case "AGING": {
        const rows = new Map<string, bigint[]>();
        const total = [0n, 0n, 0n];
        for (const i of this.invoices) {
          if (i.outstanding === 0n) continue;
          if (!rows.has(i.sub.customer.name)) rows.set(i.sub.customer.name, [0n, 0n, 0n]);
          const age = this.day - i.day;
          const bucket = age <= 30 ? 0 : age <= 60 ? 1 : 2;
          rows.get(i.sub.customer.name)![bucket] += i.outstanding;
          total[bucket] += i.outstanding;
        }
        this.emit(0, "AGING", "day", this.day);
        for (const name of [...rows.keys()].sort()) {
          const row = rows.get(name)!;
          this.emit(2, name, "0-30", money(row[0]), "31-60", money(row[1]), "61+", money(row[2]), "sum", money(sum(row)));
        }
        this.emit(2, "total", "0-30", money(total[0]), "31-60", money(total[1]), "61+", money(total[2]), "sum", money(sum(total)));
        break;
      }
      case "DUNNING": {
        this.emit(0, "DUNNING");
        const invoices = this.invoices.filter(i => i.retries.length > 0);
        for (const i of invoices) this.emit(2, "invoice", i.id, "sub", i.sub.id, i.sub.customer.name,
          "outstanding", money(i.outstanding), "attempts", i.attempts, "next", i.retries[0]);
        if (!invoices.length) this.emit(2, "(none)");
        break;
      }
      case "REVENUE": {
        const total = (field: keyof Quote | "paid" | "refunded" | "outstanding"): string => money(sum(this.invoices.map(i => i[field])));
        this.emit(0, "REVENUE");
        this.emit(2, "invoices", this.invoices.length, "subtotal", total("subtotal"), "discount", total("discount"), "tax", total("tax"), "total", total("total"));
        this.emit(2, "credit", total("credit"), "paid", total("paid"), "refunded", total("refunded"), "outstanding", total("outstanding"),
          "balances", money(sum([...this.customers.values()].map(c => c.balance))));
        break;
      }
      case "EVENTS": {
        const s = a.length ? this.sub(a[0]) : null;
        this.emit(0, "EVENTS", ...(s ? ["sub", s.id] : []));
        const events = this.events.filter(e => s === null || e.id === s.id);
        for (const e of events) this.emit(2, "day", e.day, "sub", e.id, e.from, "->", e.to);
        if (!events.length) this.emit(2, "(none)");
        break;
      }
    }
  }

  execute(line: string): void {
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
const billing = new Billing();
for (let i = 1; i <= Number(lines[0]); i++) billing.execute(lines[i]);
process.stdout.write(billing.output.join("\n") + "\n");
