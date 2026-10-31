import { readFileSync } from "node:fs";

type CardEntry = {day: number; kind: string; warehouse: string; quantity: number; value: bigint};
type Item = {code: string; level: number; name: string; lastCost: bigint | null; card: CardEntry[]};
type Lot = {number: number; item: string; day: number; initialQuantity: number; initialCost: bigint; warehouse: string; kind: string; removed: number};
type StockLot = {lot: Lot; quantity: number; cost: bigint};
type Part = {lot: Lot; quantity: number; cost: bigint};
type Order = {number: number; warehouse: string; item: string; day: number; price: bigint; ordered: number; shipped: number; backorder: number; cancelled: number; returned: number; revenue: bigint; cogs: bigint; issues: Part[]};
type Total = {quantity: number; value: bigint};
type Sales = {quantity: number; revenue: bigint; cogs: bigint};
const CATEGORIES = ["received", "returned", "adjusted-in", "adjusted-out", "shipped", "written-down", "expired", "recalled"];
const lex = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
const compare = (a: bigint, b: bigint): number => a < b ? -1 : a > b ? 1 : 0;
const cents = (s: string): bigint => BigInt(s.replace(".", ""));
const value = (s: StockLot): bigint => BigInt(s.quantity) * s.cost;
const sumQuantity = (stocks: StockLot[]): number => stocks.reduce((q, s) => q + s.quantity, 0);
const sumValue = (stocks: StockLot[]): bigint => stocks.reduce((v, s) => v + value(s), 0n);
const signedQuantity = (q: number): string => q > 0 ? "+" + q : String(q);

function money(v: bigint): string {
  const sign = v < 0n ? "-" : "";
  const magnitude = v < 0n ? -v : v;
  return sign + magnitude / 100n + "." + String(magnitude % 100n).padStart(2, "0");
}

function signedMoney(v: bigint): string {
  return (v > 0n ? "+" : "") + money(v);
}

function margin(profit: bigint, revenue: bigint): string {
  if (revenue === 0n) return "n/a";
  const magnitude = profit < 0n ? -profit : profit;
  const q = magnitude * 1000n / revenue;
  return (profit < 0n && q > 0n ? "-" : "") + q / 10n + "." + q % 10n + "%";
}

class CommandError extends Error {}

class Inventory {
  day = 1;
  stock = new Map<string, Map<string, Map<number, StockLot>>>();
  items = new Map<string, Item>();
  lots: Lot[] = [];
  orders: Order[] = [];
  totals = new Map<string, Total>(CATEGORIES.map(c => [c, {quantity: 0, value: 0n}]));
  output: string[] = [];

  emit(indent: number, ...parts: (string | number)[]): void {
    this.output.push(" ".repeat(indent) + parts.join(" "));
  }

  warehouse(code: string): string {
    if (!this.stock.has(code)) throw new CommandError("unknown warehouse " + code);
    return code;
  }

  item(code: string): Item {
    const item = this.items.get(code);
    if (!item) throw new CommandError("unknown item " + code);
    return item;
  }

  pair(w: string, code: string): Item {
    this.warehouse(w);
    return this.item(code);
  }

  order(text: string): Order {
    const number = Number(text);
    if (number < 1 || number > this.orders.length) throw new CommandError("unknown order " + text);
    return this.orders[number - 1];
  }

  lot(text: string): Lot {
    const number = Number(text);
    if (number < 1 || number > this.lots.length) throw new CommandError("unknown lot " + text);
    return this.lots[number - 1];
  }

  requireQuantity(q: number): void {
    if (q === 0) throw new CommandError("invalid quantity");
  }

  holdings(w: string, code: string): Map<number, StockLot> {
    return this.stock.get(w)!.get(code) ?? new Map();
  }

  stocks(w: string, code: string): StockLot[] {
    return [...this.holdings(w, code).values()];
  }

  quantity(w: string, code: string): number {
    return sumQuantity(this.stocks(w, code));
  }

  allStocks(): StockLot[] {
    return [...this.stock.values()].flatMap(pairs => [...pairs.values()].flatMap(lots => [...lots.values()]));
  }

  totalQuantity(code: string): number {
    return [...this.stock.keys()].reduce((q, w) => q + this.quantity(w, code), 0);
  }

  backorder(code: string): number {
    return this.orders.filter(o => o.item === code).reduce((q, o) => q + o.backorder, 0);
  }

  requireStock(w: string, code: string, q: number): void {
    const held = this.quantity(w, code);
    if (held < q) throw new CommandError("insufficient stock " + w + " " + code + " " + held);
  }

  cardEntry(code: string, kind: string, warehouse: string, quantity: number, value: bigint): void {
    this.items.get(code)!.card.push({day: this.day, kind, warehouse, quantity, value});
  }

  accumulate(category: string, quantity: number, value: bigint): void {
    const total = this.totals.get(category)!;
    total.quantity += quantity;
    total.value += value;
  }

  addStock(w: string, lot: Lot, quantity: number, cost: bigint): void {
    const pairs = this.stock.get(w)!;
    if (!pairs.has(lot.item)) pairs.set(lot.item, new Map());
    const holdings = pairs.get(lot.item)!;
    const existing = holdings.get(lot.number);
    if (existing) existing.quantity += quantity;
    else holdings.set(lot.number, {lot, quantity, cost});
  }

  createLot(w: string, item: string, day: number, quantity: number, cost: bigint, kind: string): Lot {
    const lot = {number: this.lots.length + 1, item, day, initialQuantity: quantity, initialCost: cost, warehouse: w, kind, removed: 0};
    this.lots.push(lot);
    this.addStock(w, lot, quantity, cost);
    return lot;
  }

  fifo(w: string, code: string): StockLot[] {
    return this.stocks(w, code).sort((a, b) => a.lot.day - b.lot.day || a.lot.number - b.lot.number);
  }

  issue(w: string, code: string, q: number): {parts: Part[]; cost: bigint} {
    const parts: Part[] = [];
    let cost = 0n;
    for (const s of this.fifo(w, code)) {
      if (q === 0) break;
      const taken = Math.min(q, s.quantity);
      parts.push({lot: s.lot, quantity: taken, cost: s.cost});
      cost += BigInt(taken) * s.cost;
      s.quantity -= taken;
      q -= taken;
      if (s.quantity === 0) this.holdings(w, code).delete(s.lot.number);
    }
    return {parts, cost};
  }

  fulfil(o: Order, q: number, kind: string): bigint {
    if (q === 0) return 0n;
    const {parts, cost} = this.issue(o.warehouse, o.item, q);
    o.shipped += q;
    o.backorder -= q;
    o.revenue += BigInt(q) * o.price;
    o.cogs += cost;
    o.issues.push(...parts);
    this.accumulate("shipped", q, cost);
    this.cardEntry(o.item, kind, o.warehouse, -q, -cost);
    return cost;
  }

  allocate(w: string, code: string): void {
    let available = this.quantity(w, code);
    for (const o of this.orders) {
      if (available === 0) break;
      if (o.warehouse !== w || o.item !== code || o.backorder === 0) continue;
      const q = Math.min(available, o.backorder);
      const cost = this.fulfil(o, q, "fill");
      const revenue = BigInt(q) * o.price;
      available -= q;
      this.emit(2, "FILL", "order", o.number, "qty", q, "revenue", money(revenue),
        "cogs", money(cost), "profit", money(revenue - cost), "backorder", o.backorder);
    }
  }

  removeParts(parts: Part[]): void {
    for (const p of parts) p.lot.removed += p.quantity;
  }

  sales(): Map<string, Sales> {
    const rows = new Map<string, Sales>();
    for (const o of this.orders) {
      if (!rows.has(o.item)) rows.set(o.item, {quantity: 0, revenue: 0n, cogs: 0n});
      const row = rows.get(o.item)!;
      row.quantity += o.shipped - o.returned;
      row.revenue += o.revenue;
      row.cogs += o.cogs;
    }
    return rows;
  }

  marginLine(label: string, row: Sales): void {
    this.emit(2, label, "sold", row.quantity, "revenue", money(row.revenue), "cogs", money(row.cogs),
      "profit", money(row.revenue - row.cogs), "margin", margin(row.revenue - row.cogs, row.revenue));
  }

  agingLine(label: string, buckets: (number | bigint)[], monetary = false): void {
    const parts: (string | number)[] = [label];
    for (let i = 0; i < 4; i++) parts.push(["0-30", "31-60", "61-90", "91+"][i], monetary ? money(buckets[i] as bigint) : Number(buckets[i]));
    this.emit(2, ...parts);
  }

  command(cmd: string, a: string[]): void {
    switch (cmd) {
      case "DAY": {
        const day = Number(a[0]);
        if (day <= this.day) throw new CommandError("invalid day " + a[0]);
        this.day = day;
        this.emit(0, "DAY", day);
        break;
      }
      case "WAREHOUSE": {
        if (this.stock.has(a[0])) throw new CommandError("duplicate warehouse " + a[0]);
        this.stock.set(a[0], new Map());
        this.emit(0, "WAREHOUSE", a[0]);
        break;
      }
      case "ITEM": {
        const item = this.items.get(a[0]);
        const action = item ? "updated" : "added";
        if (item) {
          item.level = Number(a[1]);
          item.name = a[2];
        } else {
          this.items.set(a[0], {code: a[0], level: Number(a[1]), name: a[2], lastCost: null, card: []});
        }
        this.emit(0, "ITEM", a[0], action, a[2], "level", Number(a[1]));
        break;
      }
      case "RECEIVE": {
        const [w, code] = a;
        const item = this.pair(w, code);
        const q = Number(a[2]);
        const cost = cents(a[3]);
        const day = Number(a[4]);
        this.requireQuantity(q);
        if (day > this.day) throw new CommandError("future day " + a[4]);
        const lot = this.createLot(w, code, day, q, cost, "receive");
        const amount = BigInt(q) * cost;
        item.lastCost = cost;
        this.accumulate("received", q, amount);
        this.cardEntry(code, "receive", w, q, amount);
        this.emit(0, "RECEIVE", w, code, "lot", lot.number, "qty", q, "cost", money(cost), "day", day, "value", money(amount));
        this.allocate(w, code);
        break;
      }
      case "SHIP": {
        const [w, code] = a;
        this.pair(w, code);
        const q = Number(a[2]);
        this.requireQuantity(q);
        const o: Order = {number: this.orders.length + 1, warehouse: w, item: code, day: this.day, price: cents(a[3]),
          ordered: q, shipped: 0, backorder: q, cancelled: 0, returned: 0, revenue: 0n, cogs: 0n, issues: []};
        this.orders.push(o);
        const filled = Math.min(q, this.quantity(w, code));
        const cost = this.fulfil(o, filled, "ship");
        this.emit(0, "SHIP", "order", o.number, w, code, "shipped", filled, "revenue", money(o.revenue),
          "cogs", money(cost), "profit", money(o.revenue - cost), "backorder", o.backorder);
        break;
      }
      case "CANCEL": {
        const o = this.order(a[0]);
        if (o.backorder === 0) throw new CommandError("no backorder " + a[0]);
        o.cancelled += o.backorder;
        o.backorder = 0;
        this.emit(0, "CANCEL", "order", o.number, "qty", o.cancelled);
        break;
      }
      case "TRANSFER": {
        const [source, destination, code] = a;
        this.warehouse(source);
        this.warehouse(destination);
        if (source === destination) throw new CommandError("same warehouse " + source);
        this.item(code);
        const q = Number(a[3]);
        this.requireQuantity(q);
        this.requireStock(source, code, q);
        const {parts, cost} = this.issue(source, code, q);
        for (const p of parts) this.addStock(destination, p.lot, p.quantity, p.cost);
        this.cardEntry(code, "transfer-out", source, -q, -cost);
        this.cardEntry(code, "transfer-in", destination, q, cost);
        this.emit(0, "TRANSFER", source, "->", destination, code, "qty", q, "value", money(cost), "lots", parts.length);
        this.allocate(destination, code);
        break;
      }
      case "ADJUST": {
        const [w, code, change] = a;
        this.pair(w, code);
        const q = Number(change.slice(1));
        this.requireQuantity(q);
        if (change[0] === "+") {
          const cost = cents(a[3]);
          const amount = BigInt(q) * cost;
          const lot = this.createLot(w, code, this.day, q, cost, "adjust");
          this.accumulate("adjusted-in", q, amount);
          this.cardEntry(code, "adjust", w, q, amount);
          this.emit(0, "ADJUST", w, code, "+" + q, "lot", lot.number, "value", money(amount));
          this.allocate(w, code);
        } else {
          this.requireStock(w, code, q);
          const {parts, cost} = this.issue(w, code, q);
          this.removeParts(parts);
          this.accumulate("adjusted-out", q, cost);
          this.cardEntry(code, "adjust", w, -q, -cost);
          this.emit(0, "ADJUST", w, code, "-" + q, "value", money(cost));
        }
        break;
      }
      case "RETURN": {
        const o = this.order(a[0]);
        const q = Number(a[1]);
        const cost = cents(a[2]);
        this.requireQuantity(q);
        const available = o.shipped - o.returned;
        if (q > available) throw new CommandError("return exceeds shipped " + a[0] + " " + available);
        const lot = this.createLot(o.warehouse, o.item, this.day, q, cost, "return");
        const amount = BigInt(q) * cost;
        const refund = BigInt(q) * o.price;
        o.returned += q;
        o.revenue -= refund;
        o.cogs -= amount;
        this.accumulate("returned", q, amount);
        this.cardEntry(o.item, "return", o.warehouse, q, amount);
        this.emit(0, "RETURN", "order", o.number, o.warehouse, o.item, "qty", q, "lot", lot.number, "refund", money(refund), "value", money(amount));
        this.allocate(o.warehouse, o.item);
        break;
      }
      case "COUNT": {
        const [w, code] = a;
        const item = this.pair(w, code);
        const actual = Number(a[2]);
        const held = this.quantity(w, code);
        if (actual === held) {
          this.emit(0, "COUNT", w, code, "qty", actual, "ok");
        } else if (actual < held) {
          const q = held - actual;
          const {parts, cost} = this.issue(w, code, q);
          this.removeParts(parts);
          this.accumulate("adjusted-out", q, cost);
          this.cardEntry(code, "count", w, -q, -cost);
          this.emit(0, "COUNT", w, code, "qty", held, "->", actual, "shortage", q, "value", money(cost));
        } else {
          const q = actual - held;
          const cost = item.lastCost ?? 0n;
          const amount = BigInt(q) * cost;
          const lot = this.createLot(w, code, this.day, q, cost, "count");
          this.accumulate("adjusted-in", q, amount);
          this.cardEntry(code, "count", w, q, amount);
          this.emit(0, "COUNT", w, code, "qty", held, "->", actual, "surplus", q, "lot", lot.number, "value", money(amount));
          this.allocate(w, code);
        }
        break;
      }
      case "MARKET": {
        this.item(a[0]);
        const price = cents(a[1]);
        let changed = 0;
        let q = 0;
        let loss = 0n;
        for (const w of [...this.stock.keys()].sort()) {
          let warehouseLoss = 0n;
          for (const s of this.stocks(w, a[0])) {
            if (s.cost <= price) continue;
            warehouseLoss += BigInt(s.quantity) * (s.cost - price);
            changed++;
            q += s.quantity;
            s.cost = price;
          }
          if (warehouseLoss > 0n) this.cardEntry(a[0], "writedown", w, 0, -warehouseLoss);
          loss += warehouseLoss;
        }
        this.accumulate("written-down", q, loss);
        this.emit(0, "MARKET", a[0], "price", money(price), "lots", changed, "qty", q, "loss", money(loss));
        break;
      }
      case "RECALL": {
        const lot = this.lot(a[0]);
        const held: {warehouse: string; stock: StockLot}[] = [];
        for (const w of [...this.stock.keys()].sort()) {
          const s = this.holdings(w, lot.item).get(lot.number);
          if (s) held.push({warehouse: w, stock: s});
        }
        if (!held.length) throw new CommandError("nothing to recall " + a[0]);
        const q = sumQuantity(held.map(r => r.stock));
        const amount = sumValue(held.map(r => r.stock));
        for (const r of held) {
          this.holdings(r.warehouse, lot.item).delete(lot.number);
          this.cardEntry(lot.item, "recall", r.warehouse, -r.stock.quantity, -value(r.stock));
        }
        lot.removed += q;
        this.accumulate("recalled", q, amount);
        this.emit(0, "RECALL", "lot", lot.number, lot.item, "qty", q, "value", money(amount));
        for (const r of held) this.emit(2, r.warehouse, "qty", r.stock.quantity, "value", money(value(r.stock)));
        break;
      }
      case "EXPIRE": {
        const days = Number(a[0]);
        this.emit(0, "EXPIRE", days);
        let totalQ = 0;
        let totalV = 0n;
        for (const code of [...this.items.keys()].sort()) {
          for (const w of [...this.stock.keys()].sort()) {
            const expired = this.stocks(w, code).filter(s => this.day - s.lot.day > days);
            if (!expired.length) continue;
            const q = sumQuantity(expired);
            const amount = sumValue(expired);
            for (const s of expired) {
              s.lot.removed += s.quantity;
              this.holdings(w, code).delete(s.lot.number);
            }
            this.accumulate("expired", q, amount);
            this.cardEntry(code, "expire", w, -q, -amount);
            totalQ += q;
            totalV += amount;
            this.emit(2, code, w, "lots", expired.length, "qty", q, "value", money(amount));
          }
        }
        this.emit(2, "total", "qty", totalQ, "value", money(totalV));
        break;
      }
      case "VALUE":
      case "AGING": {
        const warehouses = a.length ? [this.warehouse(a[0])] : [...this.stock.keys()].sort();
        if (cmd === "VALUE") this.emit(0, "VALUE", ...a);
        else this.emit(0, "AGING", ...a, "day", this.day);
        let totalQ = 0;
        let totalV = 0n;
        const bucketQ = [0, 0, 0, 0];
        const bucketV = [0n, 0n, 0n, 0n];
        for (const code of [...this.items.keys()].sort()) {
          const rows = warehouses.map(w => ({w, stocks: this.stocks(w, code)}));
          const stocks = rows.flatMap(r => r.stocks);
          const q = sumQuantity(stocks);
          const amount = sumValue(stocks);
          if (!q) continue;
          if (cmd === "VALUE") {
            this.emit(2, code, "qty", q, "value", money(amount), "avg", money(amount / BigInt(q)));
            if (!a.length) {
              for (const r of rows) {
                const quantity = sumQuantity(r.stocks);
                if (quantity) this.emit(4, r.w, "qty", quantity, "value", money(sumValue(r.stocks)));
              }
            }
          } else {
            const itemBuckets = [0, 0, 0, 0];
            for (const s of stocks) {
              const age = this.day - s.lot.day;
              const bucket = age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3;
              itemBuckets[bucket] += s.quantity;
              bucketQ[bucket] += s.quantity;
              bucketV[bucket] += value(s);
            }
            this.agingLine(code, itemBuckets);
          }
          totalQ += q;
          totalV += amount;
        }
        if (cmd === "VALUE") this.emit(2, "total", "qty", totalQ, "value", money(totalV));
        else {
          this.agingLine("total", bucketQ);
          this.agingLine("value", bucketV, true);
        }
        break;
      }
      case "LOTS": {
        const [w, code] = a;
        this.pair(w, code);
        this.emit(0, "LOTS", w, code);
        const stocks = this.fifo(w, code);
        const orders = this.orders.filter(o => o.warehouse === w && o.item === code && o.backorder > 0);
        for (const s of stocks) this.emit(2, "lot", s.lot.number, "day", s.lot.day, "qty", s.quantity, "cost", money(s.cost), "value", money(value(s)), "age", this.day - s.lot.day);
        for (const o of orders) this.emit(2, "backorder", "order", o.number, "qty", o.backorder);
        if (!stocks.length && !orders.length) this.emit(2, "(none)");
        break;
      }
      case "REORDER":
      case "ITEMS": {
        this.emit(0, cmd);
        let found = false;
        for (const code of [...this.items.keys()].sort()) {
          const item = this.items.get(code)!;
          const q = this.totalQuantity(code);
          const backorder = this.backorder(code);
          if (cmd === "REORDER") {
            if (q - backorder > item.level) continue;
            this.emit(2, code, item.name, "onhand", q, "backorder", backorder, "level", item.level);
          } else {
            this.emit(2, code, item.name, "level", item.level, "onhand", q, "backorder", backorder,
              "cost", item.lastCost === null ? "none" : money(item.lastCost));
          }
          found = true;
        }
        if (!found) this.emit(2, "(none)");
        break;
      }
      case "MARGIN":
      case "TOP": {
        const rows = this.sales();
        if (cmd === "MARGIN") {
          this.emit(0, "MARGIN");
          const total = {quantity: 0, revenue: 0n, cogs: 0n};
          for (const code of [...rows.keys()].sort()) {
            const row = rows.get(code)!;
            this.marginLine(code, row);
            total.quantity += row.quantity;
            total.revenue += row.revenue;
            total.cogs += row.cogs;
          }
          this.marginLine("total", total);
        } else {
          this.emit(0, "TOP", Number(a[0]));
          const ids = [...rows.keys()].sort((a, b) => {
            const x = rows.get(a)!;
            const y = rows.get(b)!;
            return compare(y.revenue - y.cogs, x.revenue - x.cogs) || compare(y.revenue, x.revenue) || lex(a, b);
          });
          for (let i = 0; i < Math.min(ids.length, Number(a[0])); i++) {
            const row = rows.get(ids[i])!;
            this.emit(2, i + 1, ids[i], "profit", money(row.revenue - row.cogs), "revenue", money(row.revenue), "margin", margin(row.revenue - row.cogs, row.revenue));
          }
          if (!ids.length) this.emit(2, "(none)");
        }
        break;
      }
      case "BACKORDERS": {
        this.emit(0, "BACKORDERS");
        const orders = this.orders.filter(o => o.backorder > 0);
        for (const o of orders) this.emit(2, "order", o.number, o.warehouse, o.item, "qty", o.backorder, "day", o.day, "price", money(o.price));
        if (!orders.length) this.emit(2, "(none)");
        break;
      }
      case "ORDER": {
        const o = this.order(a[0]);
        this.emit(0, "ORDER", o.number, o.warehouse, o.item, "day", o.day, "price", money(o.price));
        this.emit(2, "ordered", o.ordered, "shipped", o.shipped, "backorder", o.backorder, "cancelled", o.cancelled, "returned", o.returned);
        for (const p of o.issues) this.emit(2, "lot", p.lot.number, "qty", p.quantity, "cost", money(p.cost));
        this.emit(2, "revenue", money(o.revenue), "cogs", money(o.cogs), "profit", money(o.revenue - o.cogs));
        break;
      }
      case "TRACE": {
        const lot = this.lot(a[0]);
        this.emit(0, "TRACE", "lot", lot.number, lot.item, lot.kind, lot.warehouse, "day", lot.day, "qty", lot.initialQuantity, "cost", money(lot.initialCost));
        for (const w of [...this.stock.keys()].sort()) {
          const s = this.holdings(w, lot.item).get(lot.number);
          if (s) this.emit(2, "held", w, "qty", s.quantity, "cost", money(s.cost));
        }
        for (const o of this.orders) {
          const q = o.issues.filter(p => p.lot.number === lot.number).reduce((q, p) => q + p.quantity, 0);
          if (q) this.emit(2, "order", o.number, "qty", q);
        }
        if (lot.removed) this.emit(2, "removed", "qty", lot.removed);
        break;
      }
      case "CARD": {
        const item = this.item(a[0]);
        this.emit(0, "CARD", item.code, item.name);
        let q = 0;
        let amount = 0n;
        for (const e of item.card) {
          q += e.quantity;
          amount += e.value;
          this.emit(2, "day", e.day, e.kind, e.warehouse, signedQuantity(e.quantity), signedMoney(e.value), "balance", q, money(amount));
        }
        if (!item.card.length) this.emit(2, "(none)");
        break;
      }
      case "STATUS": {
        this.emit(0, "STATUS");
        for (const w of [...this.stock.keys()].sort()) {
          const pairs = this.stock.get(w)!;
          const stocks = [...pairs.values()].flatMap(lots => [...lots.values()]);
          const skus = [...pairs.values()].filter(lots => lots.size > 0).length;
          const backorder = this.orders.filter(o => o.warehouse === w).reduce((q, o) => q + o.backorder, 0);
          this.emit(2, w, "skus", skus, "qty", sumQuantity(stocks), "value", money(sumValue(stocks)), "backorder", backorder);
        }
        if (!this.stock.size) this.emit(2, "(none)");
        break;
      }
      case "SUMMARY": {
        this.emit(0, "SUMMARY");
        for (const category of CATEGORIES) {
          const total = this.totals.get(category)!;
          this.emit(2, category, "qty", total.quantity, "value", money(total.value));
        }
        const stocks = this.allStocks();
        this.emit(2, "on-hand", "qty", sumQuantity(stocks), "value", money(sumValue(stocks)));
        this.emit(2, "orders", this.orders.length, "open", this.orders.filter(o => o.backorder > 0).length,
          "backorder", this.orders.reduce((q, o) => q + o.backorder, 0));
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
const inventory = new Inventory();
for (let i = 1; i <= Number(lines[0]); i++) inventory.execute(lines[i]);
process.stdout.write(inventory.output.join("\n") + "\n");
