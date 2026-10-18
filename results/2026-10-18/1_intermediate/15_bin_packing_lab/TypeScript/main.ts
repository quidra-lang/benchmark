import { readFileSync } from "node:fs";

type Item = {id: number; size: number};
type Bin = {load: number; items: Item[]; cls: number | null};
type Step = {item: Item; bin: number; inspected: number; fresh: boolean; closed: number | null; cls: number | null};
type Packing = {bins: Bin[]; steps: Step[]; inspections: number; closes: number};
type Rectangle = {id: number; w: number; h: number};
type Placement = Rectangle & {x: number; y: number; rotated: boolean};
type FreeRect = {x: number; y: number; w: number; h: number};
type Sheet = {free: FreeRect[]; placements: Placement[]};
type Shelf = {y: number; h: number; used: number; placements: Placement[]};
type BoundRow = {alpha: number; j1: number; j2: number; j3: number; bound: number};
const METHODS = ["NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST", "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD"];
const total = (items: Item[]): number => items.reduce((v, i) => v + i.size, 0);
const descending = (items: Item[]): Item[] => [...items].sort((a, b) => b.size - a.size || a.id - b.id);
const notation = (i: Item): string => i.id + ":" + i.size;
const letter = (id: number): string => String.fromCharCode(64 + id);
const ceil = (a: number, b: number): number => Math.floor((a + b - 1) / b);
const copyBins = (bins: Bin[]): Bin[] => bins.map(b => ({load: b.load, items: [...b.items], cls: b.cls}));
class CommandError extends Error {}

function pack(items: Item[], capacity: number, method: string, k = 0): Packing {
  const bins: Bin[] = [];
  const steps: Step[] = [];
  const current = new Map<number, number>();
  let active: number[] = [];
  let inspections = 0;
  let closes = 0;
  const order = ["FFD", "BFD", "WFD"].includes(method) ? descending(items) : items;
  for (const item of order) {
    const before = inspections;
    let destination = -1;
    let closed: number | null = null;
    let cls: number | null = null;
    if (method === "NEXTFIT") {
      if (bins.length) {
        inspections++;
        if (bins[bins.length - 1].load + item.size <= capacity) destination = bins.length - 1;
      }
    } else if (method === "HARMONIC") {
      cls = Math.min(Math.floor(capacity / item.size), k);
      const index = current.get(cls);
      if (index !== undefined) {
        inspections++;
        if (bins[index].load + item.size <= capacity) destination = index;
      }
    } else if (["FIRSTFIT", "FFD", "KBOUNDED"].includes(method)) {
      const candidates = method === "KBOUNDED" ? active : bins.map((_, i) => i);
      for (const index of candidates) {
        inspections++;
        if (bins[index].load + item.size <= capacity) {
          destination = index;
          break;
        }
      }
    } else {
      inspections += bins.length;
      const candidates = bins.map((_, i) => i).filter(i => bins[i].load + item.size <= capacity);
      const largest = method === "BESTFIT" || method === "BFD";
      candidates.sort((a, b) => (largest ? bins[b].load - bins[a].load : bins[a].load - bins[b].load) || a - b);
      if (candidates.length) destination = candidates[method === "ALMOSTWORST" && candidates.length > 1 ? 1 : 0];
    }
    const fresh = destination < 0;
    if (fresh) {
      if (method === "KBOUNDED" && active.length === k) {
        const index = [...active].sort((a, b) => bins[b].load - bins[a].load || a - b)[0];
        active = active.filter(i => i !== index);
        closed = index + 1;
        closes++;
      }
      destination = bins.length;
      bins.push({load: 0, items: [], cls});
      if (method === "HARMONIC") current.set(cls!, destination);
      if (method === "KBOUNDED") active.push(destination);
    }
    bins[destination].items.push(item);
    bins[destination].load += item.size;
    steps.push({item, bin: destination + 1, inspected: inspections - before, fresh, closed, cls});
  }
  return {bins, steps, inspections, closes};
}

function bounds(items: Item[], capacity: number): {l1: number; l2: number; rows: BoundRow[]} {
  const thresholds = [...new Set([0, ...items.filter(i => 2 * i.size <= capacity).map(i => i.size)])].sort((a, b) => a - b);
  const rows = thresholds.map(alpha => {
    const j1 = items.filter(i => i.size > capacity - alpha);
    const j2 = items.filter(i => 2 * i.size > capacity && i.size <= capacity - alpha);
    const j3 = items.filter(i => 2 * i.size <= capacity && i.size >= alpha);
    const extra = total(j3) - (j2.length * capacity - total(j2));
    return {alpha, j1: j1.length, j2: j2.length, j3: j3.length, bound: j1.length + j2.length + (extra > 0 ? ceil(extra, capacity) : 0)};
  });
  return {l1: ceil(total(items), capacity), l2: Math.max(...rows.map(r => r.bound)), rows};
}

class Lab {
  capacity: number | null = null;
  items: Item[] = [];
  output: string[] = [];

  emit(...parts: (string | number)[]): void {
    this.output.push(parts.join(" "));
  }

  binLine(bin: Bin, number: number, capacity: number, harmonic = false, over = false): void {
    this.emit("BIN", number, "load=" + bin.load + "/" + capacity, "items=" + bin.items.map(notation).join(" "),
      ...(harmonic ? ["class=" + bin.cls] : []), ...(over ? ["OVER"] : []));
  }

  header(method: string, k: number, result: Packing): string {
    const parameter = ["HARMONIC", "KBOUNDED"].includes(method) ? " k=" + k : "";
    return method + parameter + " bins=" + result.bins.length + " inspections=" + result.inspections +
      " waste=" + (result.bins.length * this.capacity! - total(this.items)) + (method === "KBOUNDED" ? " closes=" + result.closes : "");
  }

  reduce(method: string, k: number): void {
    const capacity = this.capacity!;
    const bins = pack(this.items, capacity, method, k).bins;
    const before = bins.length;
    const eliminations: string[] = [];
    while (true) {
      let succeeded = false;
      const order = bins.map((_, i) => i).sort((a, b) => bins[a].load - bins[b].load || a - b);
      for (const source of order) {
        const loads = bins.map(b => b.load);
        const moves: {item: Item; destination: number}[] = [];
        let possible = true;
        for (const item of descending(bins[source].items)) {
          const candidates = bins.map((_, i) => i).filter(i => i !== source && loads[i] + item.size <= capacity);
          candidates.sort((a, b) => loads[b] - loads[a] || a - b);
          if (!candidates.length) {
            possible = false;
            break;
          }
          const destination = candidates[0];
          loads[destination] += item.size;
          moves.push({item, destination});
        }
        if (!possible) continue;
        eliminations.push("ELIMINATE bin=" + (source + 1) + " load=" + bins[source].load +
          " moves=" + moves.map(m => notation(m.item) + "->" + (m.destination + 1)).join(" "));
        for (const m of moves) {
          bins[m.destination].items.push(m.item);
          bins[m.destination].load += m.item.size;
        }
        bins.splice(source, 1);
        succeeded = true;
        break;
      }
      if (!succeeded) break;
    }
    this.emit("REDUCE", method, ...(["HARMONIC", "KBOUNDED"].includes(method) ? ["k=" + k] : []),
      "before=" + before, "after=" + bins.length, "eliminated=" + (before - bins.length));
    for (const line of eliminations) this.emit(line);
    bins.forEach((b, i) => this.binLine(b, i + 1, capacity, method === "HARMONIC"));
  }

  exact(limit: number): void {
    if (limit === 0) throw new CommandError("BAD PARAMETER");
    if (this.items.length > 20) throw new CommandError("TOO MANY ITEMS");
    const capacity = this.capacity!;
    const lower = bounds(this.items, capacity).l2;
    let best = copyBins(pack(this.items, capacity, "FFD").bins);
    this.emit("EXACT", "ffd=" + best.length, "L2=" + lower);
    const order = descending(this.items);
    const remaining = Array(order.length + 1).fill(0) as number[];
    for (let i = order.length - 1; i >= 0; i--) remaining[i] = remaining[i + 1] + order[i].size;
    const bins: Bin[] = [];
    let nodes = 0;
    let status = best.length === lower ? "bound" : "complete";
    let stopped = status === "bound";
    const visit = (index: number, used: number): void => {
      if (nodes === limit) {
        status = "limit";
        stopped = true;
        return;
      }
      nodes++;
      const free = bins.length * capacity - used;
      const extra = remaining[index] - free;
      const bound = bins.length + (extra > 0 ? ceil(extra, capacity) : 0);
      if (bound >= best.length) return;
      if (index === order.length) {
        best = copyBins(bins);
        this.emit("IMPROVE", "bins=" + best.length, "nodes=" + nodes);
        if (best.length === lower) {
          status = "bound";
          stopped = true;
        }
        return;
      }
      const item = order[index];
      const seen = new Set<number>();
      for (const bin of bins) {
        if (seen.has(bin.load)) continue;
        seen.add(bin.load);
        if (bin.load + item.size > capacity) continue;
        bin.load += item.size;
        bin.items.push(item);
        visit(index + 1, used + item.size);
        bin.items.pop();
        bin.load -= item.size;
        if (stopped) return;
      }
      if (bins.length + 1 < best.length) {
        bins.push({load: item.size, items: [item], cls: null});
        visit(index + 1, used + item.size);
        bins.pop();
      }
    };
    if (!stopped) visit(0, 0);
    this.emit("RESULT", "bins=" + best.length, "nodes=" + nodes, "status=" + status);
    best.forEach((b, i) => this.binLine(b, i + 1, capacity));
  }

  cover(): void {
    const capacity = this.capacity!;
    this.emit("COVER", "total=" + total(this.items), "upper=" + Math.floor(total(this.items) / capacity));
    for (const method of ["DNF", "BIGSMALL"]) {
      const remaining = method === "DNF" ? [...this.items] : descending(this.items);
      const bins: Bin[] = [];
      while (remaining.length) {
        const first = remaining.shift()!;
        const bin = {load: first.size, items: [first], cls: null};
        while (bin.load < capacity && remaining.length) {
          const item = method === "DNF" ? remaining.shift()! : remaining.pop()!;
          bin.items.push(item);
          bin.load += item.size;
        }
        bins.push(bin);
      }
      const covered = bins.filter(b => b.load >= capacity);
      const rest = bins.find(b => b.load < capacity);
      this.emit(method, "covered=" + covered.length, "rest=" + (rest?.load ?? 0));
      covered.forEach((b, i) => this.binLine(b, i + 1, capacity));
      if (rest) this.emit("REST", "items=" + rest.items.map(notation).join(" "));
    }
  }

  machines(bins: Bin[], count: number): void {
    for (let i = 0; i < count; i++) {
      const bin = bins[i];
      this.emit("MACHINE", i + 1, "load=" + (bin?.load ?? 0), "items=" + (bin ? bin.items.map(notation).join(" ") : "-"));
    }
  }

  multifit(count: number): void {
    if (count === 0) throw new CommandError("BAD PARAMETER");
    const size = total(this.items);
    const largest = Math.max(...this.items.map(i => i.size));
    let lo = Math.max(ceil(size, count), largest);
    let hi = Math.max(ceil(2 * size, count), largest);
    this.emit("MULTIFIT", "m=" + count, "lower=" + lo, "upper=" + hi);
    while (lo < hi) {
      const mid = Math.floor((lo + hi) / 2);
      const bins = pack(this.items, mid, "FFD").bins;
      const ok = bins.length <= count;
      this.emit("TRY", "cap=" + mid, "bins=" + bins.length, ok ? "ok" : "fail");
      if (ok) hi = mid;
      else lo = mid + 1;
    }
    const bins = pack(this.items, hi, "FFD").bins;
    this.emit("RESULT", "cap=" + hi, "makespan=" + Math.max(...bins.map(b => b.load)));
    this.machines(bins, count);
    const lpt: Bin[] = Array.from({length: count}, () => ({load: 0, items: [], cls: null}));
    for (const item of descending(this.items)) {
      let chosen = 0;
      for (let i = 1; i < count; i++) {
        if (lpt[i].load < lpt[chosen].load) chosen = i;
      }
      lpt[chosen].items.push(item);
      lpt[chosen].load += item.size;
    }
    this.emit("LPT", "makespan=" + Math.max(...lpt.map(b => b.load)));
    for (let i = 0; i < count; i++) {
      const b = lpt[i];
      this.emit("MACHINE", i + 1, "load=" + b.load, "items=" + (b.items.length ? b.items.map(notation).join(" ") : "-"));
    }
  }

  cutstock(capacity: number, tokens: string[]): void {
    if (capacity === 0) throw new CommandError("BAD CAPACITY");
    const pieces = tokens.map(t => t.split(":").map(Number));
    const seen = new Set<number>();
    for (let i = 0; i < pieces.length; i++) {
      const [length, demand] = pieces[i];
      if (length === 0 || length > capacity || demand === 0) throw new CommandError("BAD PIECE " + (i + 1));
      if (seen.has(length)) throw new CommandError("DUPLICATE PIECE " + (i + 1));
      seen.add(length);
    }
    pieces.sort((a, b) => b[0] - a[0]);
    const patterns: number[][] = [];
    const enumerate = (index: number, rest: number, prefix: number[]): void => {
      const maximum = Math.floor(rest / pieces[index][0]);
      if (index === pieces.length - 1) {
        patterns.push([...prefix, maximum]);
        return;
      }
      for (let count = maximum; count >= 0; count--) enumerate(index + 1, rest - count * pieces[index][0], [...prefix, count]);
    };
    enumerate(0, capacity, []);
    const remaining = pieces.map(p => p[1]);
    const used = patterns.map(() => 0);
    while (remaining.some(d => d > 0)) {
      let chosen = 0;
      let best = -1;
      for (let p = 0; p < patterns.length; p++) {
        const useful = patterns[p].reduce((v, a, i) => v + Math.min(a, remaining[i]), 0);
        if (useful > best) {
          best = useful;
          chosen = p;
        }
      }
      used[chosen]++;
      for (let i = 0; i < pieces.length; i++) remaining[i] = Math.max(0, remaining[i] - patterns[chosen][i]);
    }
    const trims = patterns.map(p => capacity - p.reduce((v, a, i) => v + a * pieces[i][0], 0));
    const cut = pieces.map((_, i) => patterns.reduce((v, p, j) => v + p[i] * used[j], 0));
    const bars = used.reduce((a, b) => a + b, 0);
    const size = pieces.reduce((v, p) => v + p[0] * p[1], 0);
    this.emit("CUTSTOCK", "L=" + capacity, "pieces=" + pieces.length, "patterns=" + patterns.length);
    patterns.forEach((p, i) => this.emit("PATTERN", i + 1, p.flatMap((a, j) => a > 0 ? [a + "x" + pieces[j][0]] : []).join("+"), "rest=" + trims[i]));
    used.forEach((n, i) => {
      if (n) this.emit("USE", i + 1, "bars=" + n);
    });
    pieces.forEach((p, i) => this.emit("PIECE", p[0], "demand=" + p[1], "cut=" + cut[i]));
    this.emit("TOTAL", "bars=" + bars, "trim=" + used.reduce((v, n, i) => v + n * trims[i], 0),
      "surplus=" + cut.reduce((v, n, i) => v + n - pieces[i][1], 0), "waste=" + (bars * capacity - size));
    const items: Item[] = [];
    for (const [length, demand] of pieces) {
      for (let i = 0; i < demand; i++) items.push({id: items.length + 1, size: length});
    }
    const ffd = pack(items, capacity, "FIRSTFIT").bins.length;
    this.emit("FFD", "bars=" + ffd, "waste=" + (ffd * capacity - size));
    this.emit("LOWER", "bars=" + ceil(size, capacity));
  }

  drawing(width: number, height: number, placements: Placement[]): void {
    const cells: string[][] = Array.from({length: height}, () => Array(width).fill("."));
    for (const p of placements) {
      for (let y = p.y; y < p.y + p.h; y++) {
        for (let x = p.x; x < p.x + p.w; x++) cells[y][x] = letter(p.id);
      }
    }
    for (let y = height - 1; y >= 0; y--) this.emit(cells[y].join(""));
  }

  rectangles(tokens: string[]): Rectangle[] {
    return tokens.map((t, i) => {
      const [w, h] = t.split("x").map(Number);
      return {id: i + 1, w, h};
    });
  }

  shelf(width: number, tokens: string[]): void {
    if (width === 0) throw new CommandError("BAD CAPACITY");
    const rectangles = this.rectangles(tokens);
    for (const r of rectangles) {
      if (r.w === 0 || r.h === 0 || r.w > width) throw new CommandError("BAD RECT " + r.id);
    }
    const order = [...rectangles].sort((a, b) => b.h - a.h || b.w - a.w || a.id - b.id);
    const area = rectangles.reduce((v, r) => v + r.w * r.h, 0);
    this.emit("SHELF", "W=" + width, "rects=" + rectangles.length, "area=" + area);
    for (const method of ["NFDH", "FFDH", "BFDH"]) {
      const shelves: Shelf[] = [];
      for (const r of order) {
        let candidates = shelves.map((_, i) => i).filter(i => shelves[i].used + r.w <= width);
        if (method === "NFDH") candidates = candidates.filter(i => i === shelves.length - 1);
        if (method === "BFDH") candidates.sort((a, b) => shelves[b].used - shelves[a].used || a - b);
        let index = candidates[0];
        if (index === undefined) {
          index = shelves.length;
          const last = shelves[shelves.length - 1];
          shelves.push({y: last ? last.y + last.h : 0, h: r.h, used: 0, placements: []});
        }
        const shelf = shelves[index];
        shelf.placements.push({...r, x: shelf.used, y: shelf.y, rotated: false});
        shelf.used += r.w;
      }
      const last = shelves[shelves.length - 1];
      const height = last.y + last.h;
      this.emit(method, "height=" + height, "shelves=" + shelves.length, "util=" + Math.floor(area * 100 / (width * height)));
      shelves.forEach((s, i) => this.emit("LEVEL", i + 1, "y=" + s.y, "h=" + s.h, "used=" + s.used,
        "items=" + s.placements.map(p => letter(p.id) + "@" + p.x).join(" ")));
      this.drawing(width, height, shelves.flatMap(s => s.placements));
    }
    const heights = Array(width).fill(0) as number[];
    const placements: Placement[] = [];
    for (const r of order) {
      let x = 0;
      let y = Infinity;
      for (let candidate = 0; candidate + r.w <= width; candidate++) {
        const level = Math.max(...heights.slice(candidate, candidate + r.w));
        if (level < y) {
          x = candidate;
          y = level;
        }
      }
      placements.push({...r, x, y, rotated: false});
      for (let column = x; column < x + r.w; column++) heights[column] = y + r.h;
    }
    const height = Math.max(...heights);
    this.emit("SKYLINE", "height=" + height, "util=" + Math.floor(area * 100 / (width * height)));
    for (const p of placements) this.emit("PLACE", letter(p.id), "x=" + p.x, "y=" + p.y, "w=" + p.w, "h=" + p.h);
    this.drawing(width, height, placements);
  }

  guillotine(width: number, height: number, mode: string, rule: string, tokens: string[]): void {
    if (width === 0 || height === 0) throw new CommandError("BAD CAPACITY");
    const rectangles = this.rectangles(tokens);
    const fits = (r: Rectangle, f: FreeRect): boolean => (r.w <= f.w && r.h <= f.h) || (mode === "ROTATE" && r.h <= f.w && r.w <= f.h);
    for (const r of rectangles) {
      if (r.w === 0 || r.h === 0 || !fits(r, {x: 0, y: 0, w: width, h: height})) throw new CommandError("BAD RECT " + r.id);
    }
    const sheets: Sheet[] = [];
    let rotatedCount = 0;
    for (const r of [...rectangles].sort((a, b) => b.w * b.h - a.w * a.h || a.id - b.id)) {
      let chosenSheet = -1;
      let chosenFree = -1;
      let bestArea = Infinity;
      for (let i = 0; i < sheets.length; i++) {
        for (let j = 0; j < sheets[i].free.length; j++) {
          const f = sheets[i].free[j];
          if (!fits(r, f)) continue;
          if (chosenSheet < 0 || (rule === "BEST" && f.w * f.h < bestArea)) {
            chosenSheet = i;
            chosenFree = j;
            bestArea = f.w * f.h;
          }
        }
      }
      if (chosenSheet < 0) {
        chosenSheet = sheets.length;
        chosenFree = 0;
        sheets.push({free: [{x: 0, y: 0, w: width, h: height}], placements: []});
      }
      const sheet = sheets[chosenSheet];
      const [f] = sheet.free.splice(chosenFree, 1);
      const rotated = !(r.w <= f.w && r.h <= f.h);
      const w = rotated ? r.h : r.w;
      const h = rotated ? r.w : r.h;
      if (rotated) rotatedCount++;
      sheet.placements.push({id: r.id, w, h, x: f.x, y: f.y, rotated});
      const rw = f.w - w;
      const rh = f.h - h;
      const top = {x: f.x, y: f.y + h, w: rw <= rh ? f.w : w, h: rh};
      const right = {x: f.x + w, y: f.y, w: rw, h: rw <= rh ? h : f.h};
      for (const free of [top, right]) {
        if (free.w > 0 && free.h > 0) sheet.free.push(free);
      }
    }
    const area = rectangles.reduce((v, r) => v + r.w * r.h, 0);
    this.emit("GUILLOTINE", "W=" + width, "H=" + height, "mode=" + mode, "rule=" + rule, "rects=" + rectangles.length,
      "sheets=" + sheets.length, "rotated=" + rotatedCount, "util=" + Math.floor(area * 100 / (sheets.length * width * height)));
    sheets.forEach((sheet, i) => {
      this.emit("SHEET", i + 1, "placed=" + sheet.placements.length, "area=" + sheet.placements.reduce((v, p) => v + p.w * p.h, 0));
      for (const p of sheet.placements) this.emit("PLACE", letter(p.id), "x=" + p.x, "y=" + p.y, "w=" + p.w, "h=" + p.h, ...(p.rotated ? ["rotated"] : []));
      this.emit("FREE", ...(sheet.free.length ? sheet.free.map(f => f.x + "," + f.y + "," + f.w + "x" + f.h) : ["none"]));
      this.drawing(width, height, sheet.placements);
    });
  }

  command(cmd: string, a: string[]): void {
    if (cmd === "ITEMS" || cmd === "RANDOM") {
      let capacity: number;
      let sizes: number[];
      if (cmd === "ITEMS") {
        capacity = Number(a[0]);
        if (capacity === 0) throw new CommandError("BAD CAPACITY");
        sizes = a.slice(1).map(Number);
        const bad = sizes.findIndex(s => s === 0 || s > capacity);
        if (bad >= 0) throw new CommandError("BAD ITEM " + (bad + 1));
      } else {
        const count = Number(a[0]);
        if (count === 0 || count > 40) throw new CommandError("BAD COUNT");
        capacity = Number(a[1]);
        if (capacity === 0) throw new CommandError("BAD CAPACITY");
        let seed = Number(a[2]);
        if (seed === 0 || seed >= 2147483647) throw new CommandError("BAD SEED");
        sizes = [];
        for (let i = 0; i < count; i++) {
          seed = 48271 * seed % 2147483647;
          sizes.push(seed % capacity + 1);
        }
      }
      this.capacity = capacity;
      this.items = sizes.map((size, i) => ({id: i + 1, size}));
      this.emit(cmd, "count=" + sizes.length, "capacity=" + capacity, "total=" + total(this.items));
      if (cmd === "RANDOM") this.emit("SIZES", ...sizes);
      return;
    }
    if (cmd === "CUTSTOCK") {
      this.cutstock(Number(a[0]), a.slice(1));
      return;
    }
    if (cmd === "SHELF") {
      this.shelf(Number(a[0]), a.slice(1));
      return;
    }
    if (cmd === "GUILLOTINE") {
      this.guillotine(Number(a[0]), Number(a[1]), a[2], a[3], a.slice(4));
      return;
    }
    if (this.capacity === null) throw new CommandError("NO ITEMS");
    const capacity = this.capacity;
    if (METHODS.includes(cmd) || cmd === "TRACE" || cmd === "REDUCE") {
      const method = cmd === "TRACE" || cmd === "REDUCE" ? a[0] : cmd;
      const k = Number(a[cmd === "TRACE" || cmd === "REDUCE" ? 1 : 0] ?? 0);
      if (["HARMONIC", "KBOUNDED"].includes(method) && k === 0) throw new CommandError("BAD PARAMETER");
      if (cmd === "REDUCE") {
        this.reduce(method, k);
        return;
      }
      const result = pack(this.items, capacity, method, k);
      this.emit((cmd === "TRACE" ? "TRACE " : "") + this.header(method, k, result));
      if (cmd === "TRACE") {
        result.steps.forEach((s, i) => this.emit("STEP", i + 1, "item=" + notation(s.item), "bin=" + s.bin, "inspected=" + s.inspected,
          ...(s.fresh ? ["new"] : []), ...(s.closed === null ? [] : ["closed=" + s.closed]), ...(s.cls === null ? [] : ["class=" + s.cls])));
      } else result.bins.forEach((b, i) => this.binLine(b, i + 1, capacity, method === "HARMONIC"));
    } else if (cmd === "BOUNDS") {
      const b = bounds(this.items, capacity);
      this.emit("BOUNDS", "total=" + total(this.items), "L1=" + b.l1, "L2=" + b.l2);
      for (const r of b.rows) this.emit("ALPHA", r.alpha, "j1=" + r.j1, "j2=" + r.j2, "j3=" + r.j3, "bound=" + r.bound);
    } else if (cmd === "COMPARE") {
      const k = Number(a[0]);
      if (k === 0) throw new CommandError("BAD PARAMETER");
      const b = bounds(this.items, capacity);
      this.emit("COMPARE", "k=" + k, "L1=" + b.l1, "L2=" + b.l2);
      const rows = METHODS.map(method => ({method, result: pack(this.items, capacity, method, k)}));
      rows.sort((a, b) => a.result.bins.length - b.result.bins.length || (a.method < b.method ? -1 : a.method > b.method ? 1 : 0));
      for (const r of rows) this.emit(r.method, "bins=" + r.result.bins.length, "gap=" + (r.result.bins.length - b.l2),
        "waste=" + (r.result.bins.length * capacity - total(this.items)), "inspections=" + r.result.inspections);
    } else if (cmd === "EXACT") {
      this.exact(Number(a[0]));
    } else if (cmd === "CHECK") {
      const labels = a.map(Number);
      if (labels.length !== this.items.length || labels.some(n => n === 0)) throw new CommandError("BAD ASSIGNMENT");
      const bins = new Map<number, Bin>();
      this.items.forEach((item, i) => {
        if (!bins.has(labels[i])) bins.set(labels[i], {load: 0, items: [], cls: null});
        const bin = bins.get(labels[i])!;
        bin.load += item.size;
        bin.items.push(item);
      });
      const over = [...bins.values()].filter(b => b.load > capacity).length;
      this.emit("CHECK", "bins=" + bins.size, "over=" + over, "L2=" + bounds(this.items, capacity).l2, "status=" + (over ? "invalid" : "valid"));
      for (const label of [...bins.keys()].sort((a, b) => a - b)) this.binLine(bins.get(label)!, label, capacity, false, bins.get(label)!.load > capacity);
    } else if (cmd === "COVER") {
      this.cover();
    } else if (cmd === "MULTIFIT") {
      this.multifit(Number(a[0]));
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
const lab = new Lab();
for (let i = 1; i <= Number(lines[0]); i++) lab.execute(lines[i]);
process.stdout.write(lab.output.join("\n") + "\n");
