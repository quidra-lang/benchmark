import { readFileSync } from "node:fs";

const MODES = ["FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY"];
const COUNTERS = ["allocs", "frees", "reallocs", "moves", "failures", "collected"];
const UNIT = 8;
const HEADER = 8;
const MIN_BLOCK = 16;
const MIN_BUDDY_BLOCK = 32;
const MAX_HEAP = 65536;
const UNINITIALIZED = -1;
const RANDOM_MULTIPLIER = 48271;
const RANDOM_MODULUS = 2147483647;

type Placement = {rank: [number, number]; index: number; place: number};
type Reallocated = "kept" | "shrunk" | "grown";

class CommandError extends Error {}

function powerOfTwo(value: number): boolean {
  return value > 0 && (Math.log2(value) % 1) === 0;
}

function sizeClass(size: number): number {
  return Math.floor(Math.log2(size));
}

function fragmentationPercent(free: number, largest: number): number {
  return free > 0 ? Math.floor((free - largest) * 100 / free) : 0;
}

function nextRandom(state: number): number {
  return RANDOM_MULTIPLIER * state % RANDOM_MODULUS;
}

class Block {
  start: number;
  size: number;
  used = false;
  owner: string | null = null;
  requested = 0;
  contents: number[] = [];
  stamp = 0;

  constructor(start: number, size: number) {
    this.start = start;
    this.size = size;
    this.used = false;
    this.owner = null;
    this.requested = 0;
    this.contents = [];
    this.stamp = 0;
  }

  end(): number { return this.start + this.size; }
  payload(): number { return this.start + HEADER; }
  area(): string { return `${this.start}+${this.size}`; }

  mapUnits(): string {
    const count = this.size / UNIT - 1;
    if (!this.used) return "F" + ".".repeat(count);
    let units = "H";
    for (let unit = 0; unit < count; ++unit) {
      units += UNIT * unit < this.requested ? "#" : "-";
    }
    return units;
  }
}

class Heap {
  mode: string;
  size: number;
  rover = 0;
  registrations = 0;
  blocks: Block[] = [];

  constructor(mode: string, size: number) {
    this.mode = mode;
    this.size = size;
    this.rover = 0;
    this.registrations = 0;
    this.blocks = [this.register(new Block(0, size))];
  }

  register(block: Block): Block {
    block.stamp = ++this.registrations;
    return block;
  }

  isBuddy(): boolean { return this.mode === "BUDDY"; }

  requiredLength(request: number): number {
    const length = Math.ceil(request / UNIT) * UNIT + HEADER;
    if (!this.isBuddy()) return length;
    let power = MIN_BUDDY_BLOCK;
    while (power < length) power *= 2;
    return power;
  }

  locate(address: number): number {
    let index = 0;
    while (this.blocks[index].end() <= address) ++index;
    return index;
  }

  usedBlocks(): Block[] { return this.blocks.filter(block => block.used); }
  freeBlocks(): Block[] { return this.blocks.filter(block => !block.used); }
  usedTotal(): number { return this.usedBlocks().reduce((sum, block) => sum + block.size, 0); }

  fragmentation(): number {
    const sizes = this.freeBlocks().map(block => block.size);
    const total = sizes.reduce((sum, size) => sum + size, 0);
    return fragmentationPercent(total, sizes.length ? Math.max(...sizes) : 0);
  }

  placement(block: Block, alignment: number): number {
    let place = Math.ceil((block.start + HEADER) / alignment) * alignment - HEADER;
    if (place > block.start && place - block.start < MIN_BLOCK) place += alignment;
    return place;
  }

  rank(index: number, roverIndex: number): [number, number] {
    const block = this.blocks[index];
    switch (this.mode) {
      case "NEXT": return [(index - roverIndex + this.blocks.length) % this.blocks.length, 0];
      case "BEST":
      case "BUDDY": return [block.size, block.start];
      case "WORST": return [-block.size, block.start];
      case "SEGFIT": return [sizeClass(block.size), -block.stamp];
      default: return [block.start, 0];
    }
  }

  choose(length: number, alignment: number): Placement | null {
    const roverIndex = this.locate(this.rover);
    let chosen: Placement | null = null;
    for (let index = 0; index < this.blocks.length; ++index) {
      const block = this.blocks[index];
      if (block.used) continue;
      const place = this.placement(block, alignment);
      if (place + length > block.end()) continue;
      const rank = this.rank(index, roverIndex);
      if (chosen === null || rank[0] < chosen.rank[0] ||
          (rank[0] === chosen.rank[0] && rank[1] < chosen.rank[1])) {
        chosen = { rank, index, place };
      }
    }
    return chosen;
  }

  allocate(length: number, alignment: number): Block | null {
    const choice = this.choose(length, alignment);
    if (choice === null) return null;
    const { index, place } = choice;
    const block = this.isBuddy() ? this.halve(index, length) : this.carve(index, place, length);
    block.used = true;
    if (this.mode === "NEXT") this.rover = block.end() === this.size ? 0 : block.end();
    return block;
  }

  carve(index: number, place: number, length: number): Block {
    const selected = this.blocks[index];
    const parts: Block[] = [];
    if (place > selected.start) parts.push(this.register(new Block(selected.start, place - selected.start)));
    const block = new Block(place, selected.end() - place);
    parts.push(block);
    if (block.size - length >= MIN_BLOCK) {
      parts.push(this.register(new Block(place + length, block.size - length)));
      block.size = length;
    }
    this.blocks.splice(index, 1, ...parts);
    return block;
  }

  halve(index: number, length: number): Block {
    const block = this.blocks[index];
    while (block.size > length) {
      block.size /= 2;
      this.blocks.splice(index + 1, 0, this.register(new Block(block.end(), block.size)));
    }
    return block;
  }

  mergeNext(index: number): void {
    this.blocks[index].size += this.blocks.splice(index + 1, 1)[0].size;
  }

  buddyIndex(index: number): number {
    const block = this.blocks[index];
    return block.start % (2 * block.size) === 0 ? index + 1 : index - 1;
  }

  coalesce(index: number): [Block, number] {
    let merges = 0;
    if (this.isBuddy()) {
      while (this.blocks[index].size < this.size) {
        const partner = this.buddyIndex(index);
        const other = this.blocks[partner];
        if (other.used || other.size !== this.blocks[index].size) break;
        index = Math.min(index, partner);
        this.mergeNext(index);
        ++merges;
      }
    } else {
      if (index + 1 < this.blocks.length && !this.blocks[index + 1].used) {
        this.mergeNext(index);
        ++merges;
      }
      if (index > 0 && !this.blocks[index - 1].used) {
        --index;
        this.mergeNext(index);
        ++merges;
      }
    }
    return [this.register(this.blocks[index]), merges];
  }

  release(block: Block): [Block, number] {
    block.used = false;
    block.owner = null;
    block.requested = 0;
    block.contents = [];
    return this.coalesce(this.blocks.indexOf(block));
  }

  shrink(index: number, length: number): "kept" | "shrunk" {
    const block = this.blocks[index];
    if (this.isBuddy()) {
      if (length === block.size) return "kept";
      this.halve(index, length);
      return "shrunk";
    }
    if (block.size - length < MIN_BLOCK) return "kept";
    this.blocks.splice(index + 1, 0, new Block(block.start + length, block.size - length));
    block.size = length;
    this.coalesce(index + 1);
    return "shrunk";
  }

  growIntoNext(index: number, length: number): "grown" | null {
    const block = this.blocks[index];
    if (index + 1 === this.blocks.length || this.blocks[index + 1].used) return null;
    const total = block.size + this.blocks[index + 1].size;
    if (total < length) return null;
    this.blocks.splice(index + 1, 1);
    if (total - length >= MIN_BLOCK) {
      block.size = length;
      this.blocks.splice(index + 1, 0, this.register(new Block(block.end(), total - length)));
    } else block.size = total;
    return "grown";
  }

  growBuddy(index: number, length: number): "grown" | null {
    const block = this.blocks[index];
    let size = block.size, last = index;
    while (size < length) {
      ++last;
      if (block.start % (2 * size) !== 0 || last === this.blocks.length) return null;
      const partner = this.blocks[last];
      if (partner.used || partner.size !== size) return null;
      size *= 2;
    }
    this.blocks.splice(index + 1, last - index);
    block.size = length;
    return "grown";
  }

  resize(block: Block, length: number): Reallocated | null {
    const index = this.blocks.indexOf(block);
    if (length <= block.size) return this.shrink(index, length);
    return this.isBuddy() ? this.growBuddy(index, length) : this.growIntoNext(index, length);
  }

  extend(amount: number): Block {
    this.blocks.push(new Block(this.size, amount));
    this.size += amount;
    return this.coalesce(this.blocks.length - 1)[0];
  }

  trim(): number {
    let released = 0;
    if (this.isBuddy()) {
      while (!this.blocks.at(-1)!.used && this.blocks.at(-1)!.size * 2 === this.size) {
        released += this.blocks.pop()!.size;
        this.size /= 2;
      }
    } else if (this.blocks.length >= 2 && !this.blocks.at(-1)!.used) {
      const last = this.blocks.pop()!;
      released = last.size;
      this.size = last.start;
    }
    if (this.rover >= this.size) this.rover = 0;
    return released;
  }

  compact(): [[Block, number][], number] {
    const moved: [Block, number][] = [];
    let address = 0;
    const packed = this.usedBlocks();
    for (const block of packed) {
      if (block.start !== address) {
        moved.push([block, block.payload()]);
        block.start = address;
      }
      address += block.size;
    }
    if (address < this.size) packed.push(this.register(new Block(address, this.size - address)));
    this.blocks = packed;
    this.rover = 0;
    return [moved, address];
  }
}

function runExperiment(mode: string, size: number, seed: number, operations: number, maxRequest: number): string {
  const heap = new Heap(mode, size);
  let state = seed, used = 0, peak = 0, successes = 0, failures = 0;
  const live: Block[] = [];
  for (let operation = 0; operation < operations; ++operation) {
    state = nextRandom(state);
    const allocating = live.length === 0 || state % 3 !== 0;
    state = nextRandom(state);
    if (allocating) {
      const size = 1 + state % maxRequest;
      const block = heap.allocate(heap.requiredLength(size), UNIT);
      if (block === null) ++failures;
      else {
        ++successes;
        live.push(block);
        used += block.size;
      }
    } else {
      const block = live.splice(state % live.length, 1)[0];
      used -= block.size;
      heap.release(block);
    }
    peak = Math.max(peak, used);
  }
  return `BENCH ${mode} ok=${successes} fail=${failures} peak=${peak} used=${used} ` +
         `frag=${heap.fragmentation()} blocks=${heap.blocks.length}`;
}

class Allocator {
  output: string[] = [];
  heap: Heap | null = null;
  allocations = new Map<string, Block>();
  freed = new Set<string>();
  roots = new Set<string>();
  references = new Map<string, Set<string>>();
  histories = new Map<string, string[]>();
  counters: Record<string, number> = {};
  peak = 0;
  handlers: Record<string, (args: string[]) => void>;

  constructor() {
    this.output = [];
    this.reset(null);
    this.handlers = {
      HEAP: this.createHeap, MALLOC: this.malloc, CALLOC: this.calloc,
      MEMALIGN: this.memalign, REALLOC: this.realloc, FREE: this.free,
      FILL: this.fill, COPY: this.copy, READ: this.read,
      ROOT: this.root, UNROOT: this.unroot, LINK: this.link, UNLINK: this.unlink,
      GC: this.collect, SBRK: this.sbrk, TRIM: this.trim, COMPACT: this.compact,
      WHO: this.who, DUMP: this.dump, MAP: this.showMap, FREELIST: this.freelist,
      TREE: this.tree, STATS: this.stats, LEAKS: this.leaks,
      HISTORY: this.history, BENCH: this.bench
    };
  }

  reset(heap: Heap | null): void {
    this.heap = heap;
    this.allocations = new Map<string, Block>();
    this.freed = new Set<string>();
    this.roots = new Set<string>();
    this.references = new Map<string, Set<string>>();
    this.histories = new Map<string, string[]>();
    this.counters = Object.fromEntries(COUNTERS.map(name => [name, 0]));
    this.peak = 0;
  }

  emit(...parts: (string | number | null)[]): void { this.output.push(parts.map(String).join(" ")); }

  record(name: string, line: string): void {
    this.emit(line);
    if (!this.histories.has(name)) this.histories.set(name, []);
    this.histories.get(name)!.push(line);
  }

  outOfMemory(name: string): CommandError {
    ++this.counters.failures;
    return new CommandError(`OUT OF MEMORY ${name}`);
  }

  requireLive(name: string): Block {
    if (this.allocations.has(name)) return this.allocations.get(name)!;
    if (this.freed.has(name)) throw new CommandError(`USE AFTER FREE ${name}`);
    throw new CommandError(`UNKNOWN ID ${name}`);
  }

  requireRange(name: string, offset: number, length: number): Block {
    const block = this.requireLive(name);
    if (offset + length > block.requested) throw new CommandError(`OUT OF BOUNDS ${name}`);
    return block;
  }

  requireFreeList(): void {
    if (this.heap!.isBuddy()) throw new CommandError("UNSUPPORTED IN BUDDY MODE");
  }

  reachable(): Set<string> {
    const found = new Set(this.roots);
    const pending: string[] = [...this.roots];
    while (pending.length > 0) {
      const name = pending.pop()!;
      for (const target of this.references.get(name) ?? []) {
        if (found.has(target)) continue;
        found.add(target);
        pending.push(target);
      }
    }
    return found;
  }

  createHeap(args: string[]): void {
    const size = Number(args[0]), mode = args[1];
    if (size % UNIT !== 0 || size < 32 || size > MAX_HEAP ||
        (mode === "BUDDY" && !powerOfTwo(size))) throw new CommandError("BAD HEAP SIZE");
    this.reset(new Heap(mode, size));
    this.emit(`HEAP size=${size} mode=${mode}`);
  }

  allocateId(word: string, name: string, request: number, alignment: number, fill: number): void {
    if (request === 0) throw new CommandError("BAD SIZE");
    if (this.allocations.has(name)) throw new CommandError(`DUPLICATE ID ${name}`);
    const block = this.heap!.allocate(this.heap!.requiredLength(request), alignment);
    if (block === null) throw this.outOfMemory(name);
    block.owner = name;
    block.requested = request;
    block.contents = Array(request).fill(fill);
    this.allocations.set(name, block);
    this.freed.delete(name);
    ++this.counters.allocs;
    this.record(name, `${word} ${name} addr=${block.payload()} block=${block.size}`);
  }

  malloc(args: string[]): void { this.allocateId("MALLOC", args[0], Number(args[1]), UNIT, UNINITIALIZED); }
  calloc(args: string[]): void { this.allocateId("CALLOC", args[0], Number(args[1]) * Number(args[2]), UNIT, 0); }

  memalign(args: string[]): void {
    const [name, alignment, request] = [args[0], Number(args[1]), Number(args[2])];
    this.requireFreeList();
    if (!powerOfTwo(alignment) || alignment < UNIT || alignment > 4096)
      throw new CommandError("BAD ALIGNMENT");
    this.allocateId("MEMALIGN", name, request, alignment, UNINITIALIZED);
  }

  releaseId(name: string): string {
    const block = this.allocations.get(name)!;
    this.allocations.delete(name);
    this.freed.add(name);
    this.roots.delete(name);
    this.references.delete(name);
    for (const targets of this.references.values()) targets.delete(name);
    const size = block.size;
    const [result, merges] = this.heap!.release(block);
    return `block=${size} merges=${merges} free=${result.area()}`;
  }

  freeId(name: string): void {
    if (this.freed.has(name)) throw new CommandError(`DOUBLE FREE ${name}`);
    if (!this.allocations.has(name)) throw new CommandError(`UNKNOWN ID ${name}`);
    const details = this.releaseId(name);
    ++this.counters.frees;
    this.record(name, `FREE ${name} ${details}`);
  }

  free(args: string[]): void { this.freeId(args[0]); }

  realloc(args: string[]): void {
    const name = args[0], request = Number(args[1]);
    if (request === 0) return this.freeId(name);
    if (this.freed.has(name)) throw new CommandError(`USE AFTER FREE ${name}`);
    if (!this.allocations.has(name)) {
      this.allocateId("MALLOC", name, request, UNIT, UNINITIALIZED);
      return;
    }
    let block = this.allocations.get(name)!;
    const length = this.heap!.requiredLength(request);
    const contents = block.contents.slice(0, request);
    while (contents.length < request) contents.push(UNINITIALIZED);
    const original = block.payload();
    let kind: string | null = this.heap!.resize(block, length);
    if (kind === null) {
      const moved = this.heap!.allocate(length, UNIT);
      if (moved === null) throw this.outOfMemory(name);
      moved.owner = name;
      this.allocations.set(name, moved);
      this.heap!.release(block);
      ++this.counters.moves;
      block = moved;
      kind = `moved from=${original}`;
    }
    block.requested = request;
    block.contents = contents;
    ++this.counters.reallocs;
    this.record(name, `REALLOC ${name} addr=${block.payload()} block=${block.size} ${kind}`);
  }

  fill(args: string[]): void {
    const [name, start, count, value] = [args[0], Number(args[1]), Number(args[2]), Number(args[3])];
    const block = this.requireRange(name, start, count);
    block.contents.fill(value, start, start + count);
    this.emit(`FILL ${name} ${start}+${count} = ${value}`);
  }

  copy(args: string[]): void {
    const targetName = args[0], targetOffset = Number(args[1]);
    const sourceName = args[2], sourceOffset = Number(args[3]), count = Number(args[4]);
    const target = this.requireRange(targetName, targetOffset, count);
    const source = this.requireRange(sourceName, sourceOffset, count);
    const values = source.contents.slice(sourceOffset, sourceOffset + count);
    target.contents.splice(targetOffset, count, ...values);
    this.emit(`COPY ${targetName} ${targetOffset}+${count} from ${sourceName} ${sourceOffset}`);
  }

  read(args: string[]): void {
    const name = args[0], start = Number(args[1]), count = Number(args[2]);
    const block = this.requireRange(name, start, count);
    const values = block.contents.slice(start, start + count)
      .map(v => v === UNINITIALIZED ? "?" : String(v)).join(" ");
    this.emit(`READ ${name} ${start}+${count} = ${values}`);
  }

  root(args: string[]): void {
    const name = args[0];
    this.requireLive(name);
    this.roots.add(name);
    this.emit("ROOT", name);
  }

  unroot(args: string[]): void {
    const name = args[0];
    this.requireLive(name);
    if (!this.roots.has(name)) throw new CommandError(`NOT ROOT ${name}`);
    this.roots.delete(name);
    this.emit("UNROOT", name);
  }

  link(args: string[]): void {
    const [source, target] = args;
    this.requireLive(source);
    this.requireLive(target);
    if (!this.references.has(source)) this.references.set(source, new Set());
    this.references.get(source)!.add(target);
    this.emit("LINK", source, target);
  }

  unlink(args: string[]): void {
    const [source, target] = args;
    this.requireLive(source);
    this.requireLive(target);
    if (!(this.references.get(source)?.has(target)))
      throw new CommandError(`NO LINK ${source} ${target}`);
    this.references.get(source)!.delete(target);
    this.emit("UNLINK", source, target);
  }

  collect(): void {
    const found = this.reachable();
    const garbage = [...this.allocations.entries()].filter(([name]) => !found.has(name))
      .map(([, block]) => block).sort((a, b) => a.start - b.start);
    this.emit(`GC collected=${garbage.length} bytes=${garbage.reduce((sum, block) => sum + block.size, 0)}`);
    for (const block of garbage) {
      const name = block.owner!;
      this.record(name, `COLLECT ${name} ${this.releaseId(name)}`);
    }
    this.counters.collected += garbage.length;
  }

  sbrk(args: string[]): void {
    const amount = Number(args[0]);
    const heap = this.heap!;
    const valid = heap.isBuddy()
      ? amount === heap.size && 2 * heap.size <= MAX_HEAP
      : amount % UNIT === 0 && amount >= MIN_BLOCK && heap.size + amount <= MAX_HEAP;
    if (!valid) throw new CommandError("BAD SBRK SIZE");
    const result = heap.extend(amount);
    this.emit(`SBRK heap=${heap.size} free=${result.area()}`);
  }

  trim(): void {
    const released = this.heap!.trim();
    this.emit(`TRIM heap=${this.heap!.size} released=${released}`);
  }

  compact(): void {
    this.requireFreeList();
    const [moved, used] = this.heap!.compact();
    this.counters.moves += moved.length;
    const free = used < this.heap!.size ? `${used}+${this.heap!.size - used}` : "none";
    this.emit(`COMPACT moved=${moved.length} free=${free}`);
    for (const [block, from] of moved)
      this.record(block.owner!, `MOVE ${block.owner} ${from} -> ${block.payload()}`);
  }

  who(args: string[]): void {
    const address = Number(args[0]);
    if (address >= this.heap!.size) return this.emit("WHO", address, "outside");
    const block = this.heap!.blocks[this.heap!.locate(address)];
    if (!block.used) return this.emit("WHO", address, "free", block.area());
    if (address < block.payload()) return this.emit("WHO", address, "header", block.owner);
    const offset = address - block.payload();
    this.emit("WHO", address, offset < block.requested ? "data" : "slack", `${block.owner}+${offset}`);
  }

  dump(): void {
    const heap = this.heap!;
    this.emit(`DUMP mode=${heap.mode} heap=${heap.size} blocks=${heap.blocks.length}` +
      (heap.mode === "NEXT" ? ` rover=${heap.rover}` : ""));
    for (const block of heap.blocks) {
      if (block.used) this.emit(block.start, block.size, "USED", block.owner!, `req=${block.requested}`);
      else this.emit(block.start, block.size, "FREE");
    }
  }

  showMap(): void {
    const heap = this.heap!;
    this.emit(`MAP heap=${heap.size}`);
    const allUnits = heap.blocks.map(block => block.mapUnits()).join("");
    for (let first = 0; first < allUnits.length; first += 64) {
      this.emit(String(first * UNIT).padStart(5, "0"), allUnits.slice(first, first + 64));
    }
  }

  freelist(): void {
    const free = this.heap!.freeBlocks();
    if (this.heap!.mode === "SEGFIT") free.sort((a, b) => b.stamp - a.stamp);
    this.emit(`FREELIST count=${free.length}`);
    const classes = [...new Set(free.map(block => sizeClass(block.size)))].sort((a, b) => a - b);
    for (const exponent of classes) {
      const areas = free.filter(block => sizeClass(block.size) === exponent).map(block => block.area());
      this.emit(`${2 ** exponent}-${2 ** (exponent + 1) - 1}:`, ...areas);
    }
  }

  treeNode(leaves: Map<number, Block>, start: number, size: number, depth: number): void {
    const label = " ".repeat(depth * 2) + `${start}+${size}`;
    const block = leaves.get(start);
    if (block && block.size === size) {
      this.emit(label, block.used ? "USED" : "FREE", ...(block.used ? [block.owner] : []));
      return;
    }
    this.emit(label, "split");
    const half = size / 2;
    this.treeNode(leaves, start, half, depth + 1);
    this.treeNode(leaves, start + half, half, depth + 1);
  }

  tree(): void {
    if (!this.heap!.isBuddy()) throw new CommandError("REQUIRES BUDDY MODE");
    this.emit(`TREE heap=${this.heap!.size}`);
    const leaves = new Map<number, Block>(this.heap!.blocks.map(block => [block.start, block]));
    this.treeNode(leaves, 0, this.heap!.size, 0);
  }

  stats(): void {
    const used = this.heap!.usedBlocks(), free = this.heap!.freeBlocks();
    const freeTotal = free.reduce((sum, block) => sum + block.size, 0);
    const largest = free.length ? Math.max(...free.map(block => block.size)) : 0;
    this.emit(`STATS used=${used.reduce((sum, block) => sum + block.size, 0)} used_blocks=${used.length}`,
      `free=${freeTotal} free_blocks=${free.length} largest=${largest}`,
      `frag=${fragmentationPercent(freeTotal, largest)}`,
      `requested=${used.reduce((sum, block) => sum + block.requested, 0)} peak=${this.peak}`);
    this.emit("OPS", ...COUNTERS.map(name => `${name}=${this.counters[name]}`));
  }

  leaks(): void {
    const found = this.reachable();
    const names = [...this.allocations.keys()].sort();
    const requested = names.reduce((sum, name) => sum + this.allocations.get(name)!.requested, 0);
    const lost = names.filter(name => !found.has(name)).length;
    this.emit(`LEAKS count=${names.length} requested=${requested} lost=${lost}`);
    for (const name of names) {
      const block = this.allocations.get(name)!;
      this.emit(`LEAK ${name} addr=${block.payload()} block=${block.size}`,
        `req=${block.requested} ${found.has(name) ? "reachable" : "lost"}`);
    }
  }

  history(args: string[]): void {
    const name = args[0], lines = this.histories.get(name) ?? [];
    this.emit(`HISTORY ${name} events=${lines.length}`);
    this.output.push(...lines);
  }

  bench(args: string[]): void {
    const [size, seed, operations, maxRequest] = args.map(Number);
    if (!powerOfTwo(size) || size < 32 || size > MAX_HEAP)
      throw new CommandError("BAD HEAP SIZE");
    this.emit(`BENCH heap=${size} seed=${seed} ops=${operations} maxreq=${maxRequest}`);
    for (const mode of MODES) this.emit(runExperiment(mode, size, seed, operations, maxRequest));
  }

  execute(line: string): void {
    const [command, ...args] = line.split(" ");
    try {
      if (this.heap === null && command !== "HEAP" && command !== "BENCH")
        throw new CommandError("NO HEAP");
      this.handlers[command].call(this, args);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.emit("ERROR", error.message);
    }
    if (this.heap !== null) this.peak = Math.max(this.peak, this.heap!.usedTotal());
  }
}

const lines = readFileSync(0, "utf8").trimEnd().split(/\r?\n/);
const allocator = new Allocator();
for (let i = 1, n = Number(lines[0]); i <= n; ++i) allocator.execute(lines[i]);
process.stdout.write(allocator.output.join("\n") + "\n");
