import { readFileSync } from "node:fs";

type Policy =
    "FIFO" | "LRU" | "LFU" | "NRU" | "AGING" | "CLOCK" | "ECLOCK" | "WSCLOCK" | "RANDOM" | "OPT";
type Operation = "R" | "W";
interface Settings {
    page: number;
    frames: number;
    tlb: number;
    sets: number;
    policy: Policy;
    scope: "GLOBAL" | "LOCAL";
    asid: "ON" | "OFF";
    tick: number;
    tau: number;
    seed: number;
}
interface Page {
    pid: number;
    number: number;
    frame: number;
    slot: number;
    ro: boolean;
    locked: boolean;
    r: number;
    m: number;
    load: number;
    last: number;
    uses: number;
    age: number;
    seen: boolean;
}
interface ProcessState {
    pid: number;
    pages: Page[];
    exited: boolean;
    accesses: number;
    faults: number;
    writebacks: number;
    segfaults: number;
    protfaults: number;
    peak: number;
    hand: number;
    references: number[];
}
type Access = { kind: "access"; pid: number; op: Operation; address: number };
type ReplayEvent =
    | Access
    | { kind: "exit"; pid: number }
    | { kind: "clean" }
    | { kind: "lock"; pid: number; first: number; last: number; locked: boolean };
type Command = Access | { kind: "command"; fields: string[] };
const policies: Policy[] = [
    "FIFO",
    "LRU",
    "LFU",
    "NRU",
    "AGING",
    "CLOCK",
    "ECLOCK",
    "WSCLOCK",
    "RANDOM",
    "OPT",
];
const defaults: Settings = {
    page: 256,
    frames: 4,
    tlb: 4,
    sets: 1,
    policy: "FIFO",
    scope: "GLOBAL",
    asid: "OFF",
    tick: 0,
    tau: 8,
    seed: 1,
};
const keys = Object.keys(defaults) as (keyof Settings)[];
const output: string[] = [];
const emit = (line: string): void => {
    output.push(line);
};
const hex = (value: number): string => "0x" + value.toString(16).toUpperCase();
function decimal(numerator: number, denominator: number): string {
    const scaled = denominator === 0 ? 0 : Math.floor((100 * numerator) / denominator);
    return `${Math.floor(scaled / 100)}.${String(scaled % 100).padStart(2, "0")}`;
}
const ratio = (x: number, y: number): string => decimal(100 * x, y) + "%";

function parseSettings(fields: string[]): Settings {
    const settings = { ...defaults };
    const seen = new Set<string>();
    for (const pair of fields) {
        const [key, value] = pair.split("=");
        if (!keys.includes(key as keyof Settings)) throw new Error(`unknown key ${key}`);
        if (seen.has(key)) throw new Error(`duplicate key ${key}`);
        seen.add(key);
        const n = Number(value);
        let valid = false;
        switch (key) {
            case "page":
                valid = n >= 16 && n <= 4096 && (n & (n - 1)) === 0;
                break;
            case "frames":
                valid = n >= 1 && n <= 16;
                break;
            case "tlb":
            case "sets":
                valid = n >= 1 && n <= 8;
                break;
            case "policy":
                valid = policies.includes(value as Policy);
                break;
            case "scope":
                valid = value === "GLOBAL" || value === "LOCAL";
                break;
            case "asid":
                valid = value === "ON" || value === "OFF";
                break;
            case "tick":
                valid = n >= 0 && n <= 1000;
                break;
            case "tau":
                valid = n >= 1 && n <= 1000;
                break;
            case "seed":
                valid = n >= 1 && n <= 2147483646;
                break;
        }
        if (!valid) throw new Error(`invalid ${key}`);
        switch (key) {
            case "policy":
                settings.policy = value as Policy;
                break;
            case "scope":
                settings.scope = value as Settings["scope"];
                break;
            case "asid":
                settings.asid = value as Settings["asid"];
                break;
            default:
                settings[key as Exclude<keyof Settings, "policy" | "scope" | "asid">] = n;
        }
    }
    if (settings.tlb % settings.sets !== 0) throw new Error("invalid sets");
    return settings;
}

class Simulation {
    processes = new Map<number, ProcessState>();
    frames: (Page | null)[];
    tlb: Page[][];
    slots = new Map<number, Page>();
    time = 0;
    faults = 0;
    zero = 0;
    swapin = 0;
    tlbhits = 0;
    writebacks = 0;
    switches = 0;
    hand = 0;
    random: number;
    previous: number | null = null;
    fixed = false;
    trace = false;
    events: ReplayEvent[] = [];
    faultHistory: number[] = [];
    cursor = 0;
    futurePositions = new Map<string, number[]>();

    constructor(
        public settings: Settings,
        public future: Access[],
    ) {
        this.frames = Array.from({ length: settings.frames }, () => null);
        this.tlb = Array.from({ length: settings.sets }, () => []);
        this.random = settings.seed;
        future.forEach((access, position) => {
            const key = `${access.pid}:${Math.floor(access.address / settings.page)}`;
            const positions = this.futurePositions.get(key) ?? [];
            positions.push(position);
            this.futurePositions.set(key, positions);
        });
    }
    sortedProcesses(): ProcessState[] {
        return [...this.processes.values()].sort((a, b) => a.pid - b.pid);
    }
    process(pid: number): ProcessState {
        const process = this.processes.get(pid);
        if (!process) throw new Error(`unknown process ${pid}`);
        if (process.exited) throw new Error(`process ${pid} exited`);
        return process;
    }
    declare(pid: number, count: number): void {
        if (this.fixed) throw new Error("processes are fixed");
        if (this.processes.has(pid)) throw new Error(`duplicate process ${pid}`);
        if (count < 1 || count > 256) throw new Error("invalid page count");
        if (
            this.processes.size >= 8 ||
            (this.settings.scope === "LOCAL" && this.processes.size >= this.settings.frames)
        ) {
            throw new Error("too many processes");
        }
        const pages: Page[] = Array.from({ length: count }, (_, number) => ({
            pid,
            number,
            frame: -1,
            slot: -1,
            ro: false,
            locked: false,
            r: 0,
            m: 0,
            load: 0,
            last: 0,
            uses: 0,
            age: 0,
            seen: false,
        }));
        this.processes.set(pid, {
            pid,
            pages,
            exited: false,
            accesses: 0,
            faults: 0,
            writebacks: 0,
            segfaults: 0,
            protfaults: 0,
            peak: 0,
            hand: 0,
            references: [],
        });
    }
    resident(process: ProcessState): number {
        return process.pages.reduce((count, page) => count + Number(page.frame >= 0), 0);
    }
    quota(process: ProcessState): number {
        const n = this.processes.size;
        const rank = this.sortedProcesses().findIndex((p) => p.pid === process.pid);
        return Math.floor(this.settings.frames / n) + Number(rank < this.settings.frames % n);
    }
    removeTlb(page: Page): void {
        const set = page.number % this.settings.sets;
        this.tlb[set] = this.tlb[set].filter((entry) => entry !== page);
    }
    writeback(page: Page): void {
        this.writebacks++;
        this.processes.get(page.pid)!.writebacks++;
        page.m = 0;
        if (page.slot < 0) {
            let slot = 0;
            while (this.slots.has(slot)) slot++;
            page.slot = slot;
            this.slots.set(slot, page);
        }
    }
    clean(record = true): number {
        let written = 0;
        for (const page of this.frames) {
            if (page && page.m) {
                this.writeback(page);
                written++;
            }
        }
        if (record) this.events.push({ kind: "clean" });
        return written;
    }
    exit(pid: number, record = true): string {
        const process = this.process(pid);
        let freed = 0;
        let slots = 0;
        for (const page of process.pages) {
            if (page.frame >= 0) {
                this.frames[page.frame] = null;
                page.frame = -1;
                this.removeTlb(page);
                freed++;
            }
            if (page.slot >= 0) {
                this.slots.delete(page.slot);
                page.slot = -1;
                slots++;
            }
        }
        process.exited = true;
        if (record) this.events.push({ kind: "exit", pid });
        return `EXIT P${pid} freed=${freed} slots=${slots}`;
    }
    attributes(
        pid: number,
        first: number,
        last: number,
        kind: string,
        value: string,
        record = true,
    ): void {
        const process = this.process(pid);
        if (first > last || last >= process.pages.length) throw new Error("invalid page range");
        for (let i = first; i <= last; i++) {
            if (kind === "PROTECT") process.pages[i].ro = value === "RO";
            else process.pages[i].locked = kind === "LOCK";
        }
        if (record && kind !== "PROTECT") {
            this.events.push({ kind: "lock", pid, first, last, locked: kind === "LOCK" });
        }
    }
    choose(process: ProcessState): number {
        let candidates = this.frames.flatMap((page, frame) =>
            page && (this.settings.scope === "GLOBAL" || page.pid === process.pid) ? [frame] : [],
        );
        const unlocked = candidates.filter((frame) => !this.frames[frame]!.locked);
        if (unlocked.length) candidates = unlocked;
        const pageAt = (frame: number): Page => this.frames[frame]!;
        const policy = this.settings.policy;
        if (policy === "RANDOM") {
            this.random = (48271 * this.random) % 2147483647;
            return candidates[this.random % candidates.length];
        }
        if (policy === "OPT") {
            let chosen = candidates[0];
            let farthest = -1;
            for (const frame of candidates) {
                const page = pageAt(frame);
                const positions = this.futurePositions.get(`${page.pid}:${page.number}`) ?? [];
                let lo = 0,
                    hi = positions.length;
                while (lo < hi) {
                    const middle = Math.floor((lo + hi) / 2);
                    if (positions[middle] <= this.cursor) lo = middle + 1;
                    else hi = middle;
                }
                const position = positions[lo] ?? Infinity;
                if (position > farthest) {
                    farthest = position;
                    chosen = frame;
                }
            }
            return chosen;
        }
        if (policy === "CLOCK" || policy === "ECLOCK" || policy === "WSCLOCK") {
            const hand = this.settings.scope === "GLOBAL" ? this.hand : process.hand;
            const order = [...candidates].sort(
                (a, b) =>
                    ((a - hand + this.settings.frames) % this.settings.frames) -
                    ((b - hand + this.settings.frames) % this.settings.frames),
            );
            let chosen: number | undefined;
            if (policy === "CLOCK") {
                while (chosen === undefined) {
                    for (const frame of order) {
                        if (!pageAt(frame).r) {
                            chosen = frame;
                            break;
                        }
                        pageAt(frame).r = 0;
                    }
                }
            } else if (policy === "ECLOCK") {
                while (chosen === undefined) {
                    chosen = order.find((frame) => !pageAt(frame).r && !pageAt(frame).m);
                    if (chosen !== undefined) break;
                    for (const frame of order) {
                        const page = pageAt(frame);
                        if (!page.r && page.m) {
                            chosen = frame;
                            break;
                        }
                        page.r = 0;
                    }
                }
            } else {
                for (const frame of order) {
                    const page = pageAt(frame);
                    if (page.r) {
                        page.r = 0;
                        page.last = this.time;
                    } else if (this.time - page.last > this.settings.tau) {
                        if (!page.m) {
                            chosen = frame;
                            break;
                        }
                        this.writeback(page);
                    }
                }
                if (chosen === undefined)
                    chosen = order.find((frame) => !pageAt(frame).m) ?? order[0];
            }
            const next = (chosen + 1) % this.settings.frames;
            if (this.settings.scope === "GLOBAL") this.hand = next;
            else process.hand = next;
            return chosen;
        }
        const score = (frame: number): number[] => {
            const page = pageAt(frame);
            switch (policy) {
                case "FIFO":
                    return [page.load];
                case "LRU":
                    return [page.last];
                case "LFU":
                    return [page.uses, page.load];
                case "NRU":
                    return [2 * page.r + page.m, frame];
                case "AGING":
                    return [page.age, page.load];
                default:
                    throw new Error("unreachable policy");
            }
        };
        candidates.sort((a, b) => {
            const left = score(a),
                right = score(b);
            for (let i = 0; i < left.length; i++)
                if (left[i] !== right[i]) return left[i] - right[i];
            return a - b;
        });
        return candidates[0];
    }
    access(access: Access, record = true): void {
        this.fixed = true;
        const { pid, op, address } = access;
        const process = this.process(pid);
        if (address >= process.pages.length * this.settings.page) {
            process.segfaults++;
            emit(`SEGFAULT P${pid} ${hex(address)}`);
            return;
        }
        const page = process.pages[Math.floor(address / this.settings.page)];
        if (op === "W" && page.ro) {
            process.protfaults++;
            emit(`PROTFAULT P${pid} ${hex(address)}`);
            return;
        }
        this.time++;
        process.accesses++;
        const switched = this.previous !== null && this.previous !== pid;
        if (switched) {
            this.switches++;
            if (this.settings.asid === "OFF") this.tlb = this.tlb.map(() => []);
        }
        this.previous = pid;
        let result: string;
        const set = this.tlb[page.number % this.settings.sets];
        const hit = set.indexOf(page);
        let fault = 0;
        if (hit >= 0) {
            this.tlbhits++;
            set.splice(hit, 1);
            set.unshift(page);
            result = "TLBHIT";
        } else {
            result = "HIT";
            if (page.frame < 0) {
                fault = 1;
                this.faults++;
                process.faults++;
                if (page.slot >= 0) {
                    this.swapin++;
                    result = "FAULT SWAPIN";
                } else {
                    this.zero++;
                    result = "FAULT ZERO";
                }
                let frame = -1;
                if (
                    this.settings.scope === "GLOBAL" ||
                    this.resident(process) < this.quota(process)
                ) {
                    frame = this.frames.indexOf(null);
                }
                if (frame < 0) {
                    frame = this.choose(process);
                    const victim = this.frames[frame]!;
                    result += ` evict=P${victim.pid}:${victim.number}`;
                    if (victim.m) {
                        this.writeback(victim);
                        result += " writeback";
                    }
                    victim.frame = -1;
                    this.removeTlb(victim);
                }
                this.frames[frame] = page;
                page.frame = frame;
                page.load = this.time;
                page.uses = page.m = page.age = 0;
                process.peak = Math.max(process.peak, this.resident(process));
            }
            const target = this.tlb[page.number % this.settings.sets];
            if (target.length === this.settings.tlb / this.settings.sets) target.pop();
            target.unshift(page);
        }
        page.r = 1;
        if (op === "W") page.m = 1;
        page.last = this.time;
        page.uses++;
        page.seen = true;
        process.references.push(page.number);
        this.faultHistory.push(fault);
        if (record) this.events.push(access);
        const tick = this.settings.tick > 0 && this.time % this.settings.tick === 0;
        if (tick) {
            for (const resident of this.frames) {
                if (resident) {
                    resident.age = Math.floor(resident.age / 2) + 128 * resident.r;
                    resident.r = 0;
                }
            }
        }
        if (this.trace) {
            const physical = page.frame * this.settings.page + (address % this.settings.page);
            emit(
                `t=${this.time} P${pid} ${op} ${hex(address)} page=${page.number} frame=${page.frame} phys=${hex(physical)} ${result}${switched ? " switch" : ""}`,
            );
            if (tick) emit(`t=${this.time} tick`);
        }
    }
    replay(policy: Policy, frames: number): Simulation {
        const future = this.events.filter((event): event is Access => event.kind === "access");
        const run = new Simulation({ ...this.settings, policy, frames }, future);
        for (const process of this.sortedProcesses())
            run.declare(process.pid, process.pages.length);
        for (const event of this.events) {
            switch (event.kind) {
                case "access":
                    run.access(event, false);
                    run.cursor++;
                    break;
                case "exit":
                    run.exit(event.pid, false);
                    break;
                case "clean":
                    run.clean(false);
                    break;
                case "lock":
                    run.attributes(
                        event.pid,
                        event.first,
                        event.last,
                        event.locked ? "LOCK" : "UNLOCK",
                        "",
                        false,
                    );
                    break;
            }
        }
        return run;
    }
    summary(): void {
        const processes = this.sortedProcesses();
        const segfaults = processes.reduce((sum, p) => sum + p.segfaults, 0);
        const protfaults = processes.reduce((sum, p) => sum + p.protfaults, 0);
        emit(
            `SUMMARY policy=${this.settings.policy} scope=${this.settings.scope} time=${this.time}`,
        );
        emit(
            `total faults=${this.faults} zero=${this.zero} swapin=${this.swapin} faultrate=${ratio(this.faults, this.time)} tlbhits=${this.tlbhits} tlbrate=${ratio(this.tlbhits, this.time)} writebacks=${this.writebacks} switches=${this.switches} segfaults=${segfaults} protfaults=${protfaults}`,
        );
        for (const p of processes) {
            emit(
                `P${p.pid} accesses=${p.accesses} faults=${p.faults} writebacks=${p.writebacks} segfaults=${p.segfaults} protfaults=${p.protfaults} resident=${this.resident(p)} peak=${p.peak}${this.settings.scope === "LOCAL" ? ` quota=${this.quota(p)}` : ""}${p.exited ? " exited" : ""}`,
            );
        }
    }
    command(fields: string[]): void {
        const [cmd, ...args] = fields;
        const pid = Number(args[0]);
        switch (cmd) {
            case "PROCESS":
                this.declare(pid, Number(args[1]));
                break;
            case "EXIT":
                emit(this.exit(pid));
                break;
            case "PROTECT":
            case "LOCK":
            case "UNLOCK":
                this.attributes(pid, Number(args[1]), Number(args[2]), cmd, args[3]);
                break;
            case "TRACE":
                this.trace = args[0] === "ON";
                break;
            case "SUMMARY":
                this.summary();
                break;
            case "FRAMES": {
                emit(
                    `FRAMES used=${this.frames.filter((page) => page !== null).length}/${this.settings.frames}`,
                );
                this.frames.forEach((page, frame) => {
                    if (!page) emit(`${frame} free`);
                    else
                        emit(
                            `${frame} P${page.pid}:${page.number} R=${page.r} M=${page.m} load=${page.load} last=${page.last} uses=${page.uses} age=${page.age}${page.locked ? " locked" : ""}`,
                        );
                });
                if (["CLOCK", "ECLOCK", "WSCLOCK"].includes(this.settings.policy)) {
                    if (this.settings.scope === "GLOBAL") emit(`hand=${this.hand}`);
                    else
                        emit(
                            "hand" +
                                this.sortedProcesses()
                                    .map((p) => ` P${p.pid}=${p.hand}`)
                                    .join(""),
                        );
                }
                break;
            }
            case "PAGETABLE": {
                const p = this.process(pid);
                emit(`PAGETABLE P${pid} pages=${p.pages.length} resident=${this.resident(p)}`);
                for (const page of p.pages) {
                    if (!page.seen) continue;
                    const state =
                        page.frame >= 0
                            ? `frame=${page.frame} R=${page.r} M=${page.m}`
                            : page.slot >= 0
                              ? `swap=${page.slot}`
                              : "zero";
                    emit(
                        `${page.number} ${state}${page.ro ? " RO" : ""}${page.locked ? " locked" : ""}`,
                    );
                }
                break;
            }
            case "TLB":
                emit(
                    `TLB used=${this.tlb.reduce((sum, set) => sum + set.length, 0)}/${this.settings.tlb} sets=${this.settings.sets}`,
                );
                this.tlb.forEach((set, i) =>
                    emit(
                        `set ${i}:` + set.map((p) => ` P${p.pid}:${p.number}->${p.frame}`).join(""),
                    ),
                );
                break;
            case "SWAP":
                emit(`SWAP used=${this.slots.size}`);
                for (const [slot, page] of [...this.slots].sort((a, b) => a[0] - b[0]))
                    emit(`${slot} P${page.pid}:${page.number}`);
                break;
            case "CLEAN":
                emit(`CLEAN written=${this.clean()}`);
                break;
            case "COMPARE": {
                emit(`COMPARE accesses=${this.time} frames=${this.settings.frames}`);
                const runs = policies.map((policy) => this.replay(policy, this.settings.frames));
                runs.forEach((run) =>
                    emit(
                        `${run.settings.policy} faults=${run.faults} writebacks=${run.writebacks} tlbhits=${run.tlbhits}`,
                    ),
                );
                const ranking = [...runs].sort(
                    (a, b) =>
                        a.faults - b.faults ||
                        a.writebacks - b.writebacks ||
                        policies.indexOf(a.settings.policy) - policies.indexOf(b.settings.policy),
                );
                emit("ranking " + ranking.map((run) => run.settings.policy).join(" "));
                break;
            }
            case "CURVE": {
                const policy = args[0] as Policy;
                if (!policies.includes(policy)) throw new Error("unknown policy");
                const lo = Number(args[1]),
                    hi = Number(args[2]);
                if (
                    lo < 1 ||
                    lo > hi ||
                    hi > 16 ||
                    (this.settings.scope === "LOCAL" && lo < this.processes.size)
                ) {
                    throw new Error("invalid frame range");
                }
                emit(`CURVE ${policy} frames=${lo}..${hi}`);
                let previous = Infinity;
                for (let frames = lo; frames <= hi; frames++) {
                    const run = this.replay(policy, frames);
                    emit(
                        `F=${frames} faults=${run.faults}${run.faults > previous ? " ANOMALY" : ""}`,
                    );
                    previous = run.faults;
                }
                break;
            }
            case "EAT": {
                if (!this.time) {
                    emit("EAT accesses=0");
                    break;
                }
                const [a, b, c] = args.map(Number);
                const total =
                    a * this.time +
                    b * (2 * this.time - this.tlbhits) +
                    c * (this.swapin + this.writebacks);
                emit(
                    `EAT accesses=${this.time} total=${total} average=${decimal(total, this.time)}`,
                );
                break;
            }
            case "TIMELINE": {
                const width = Number(args[0]);
                if (width < 1) throw new Error("invalid window");
                const counts: number[] = [];
                for (let i = 0; i < this.time; i += width)
                    counts.push(this.faultHistory.slice(i, i + width).reduce((a, b) => a + b, 0));
                emit(`TIMELINE window=${width}` + counts.map((count) => ` ${count}`).join(""));
                break;
            }
            case "WSET":
            case "HOT": {
                const p = this.process(pid);
                const count = Number(args[1]);
                if (count < 1) throw new Error(cmd === "WSET" ? "invalid window" : "invalid count");
                if (cmd === "WSET") {
                    const pages = [...new Set(p.references.slice(-count))].sort((a, b) => a - b);
                    emit(
                        `WSET P${pid} window=${count} size=${pages.length}` +
                            pages.map((page) => ` ${page}`).join(""),
                    );
                } else {
                    const counts = new Map<number, number>();
                    for (const page of p.references) counts.set(page, (counts.get(page) ?? 0) + 1);
                    const pages = [...counts]
                        .sort((a, b) => b[1] - a[1] || a[0] - b[0])
                        .slice(0, count);
                    emit(`HOT P${pid}` + pages.map(([page, uses]) => ` ${page}:${uses}`).join(""));
                }
                break;
            }
        }
    }
}

const lines = readFileSync(0, "utf8").trimEnd().split(/\r?\n/);
const commands: Command[] = [];
for (const line of lines.slice(1, Number(lines[0]) + 1)) {
    const fields = line.split(" ");
    if (/^\d/.test(line)) {
        commands.push({
            kind: "access",
            pid: Number(fields[0]),
            op: fields[1] as Operation,
            address: Number(fields[2]),
        });
    } else if (fields[0] === "LOOP") {
        const pid = Number(fields[1]),
            op = fields[2] as Operation;
        const start = Number(fields[3]),
            interval = Number(fields[4]);
        for (let repeat = 0; repeat < Number(fields[6]); repeat++) {
            for (let i = 0; i < Number(fields[5]); i++)
                commands.push({ kind: "access", pid, op, address: start + i * interval });
        }
    } else if (fields[0] === "RAND") {
        const pid = Number(fields[1]),
            lo = Number(fields[2]),
            hi = Number(fields[3]);
        let random = Number(fields[5]);
        for (let i = 0; i < Number(fields[4]); i++) {
            random = (48271 * random) % 2147483647;
            const address = lo + (random % (hi - lo));
            random = (48271 * random) % 2147483647;
            const op: Operation = random % 100 < Number(fields[6]) ? "W" : "R";
            commands.push({ kind: "access", pid, op, address });
        }
    } else commands.push({ kind: "command", fields });
}
let simulation: Simulation | null = null;
for (let i = 0; i < commands.length; i++) {
    const command = commands[i];
    try {
        if (command.kind === "command" && command.fields[0] === "SYSTEM") {
            simulation = null;
            const settings = parseSettings(command.fields.slice(1));
            const future: Access[] = [];
            for (let j = i + 1; j < commands.length; j++) {
                const next = commands[j];
                if (next.kind === "command" && next.fields[0] === "SYSTEM") break;
                if (next.kind === "access") future.push(next);
            }
            simulation = new Simulation(settings, future);
            emit("SYSTEM " + keys.map((key) => `${key}=${settings[key]}`).join(" "));
        } else if (!simulation) emit("ERROR no system");
        else if (command.kind === "access") {
            try {
                simulation.access(command);
            } finally {
                simulation.cursor++;
            }
        } else simulation.command(command.fields);
    } catch (error: unknown) {
        if (!(error instanceof Error)) throw error;
        emit("ERROR " + error.message);
    }
}
process.stdout.write(output.length ? output.join("\n") + "\n" : "");
