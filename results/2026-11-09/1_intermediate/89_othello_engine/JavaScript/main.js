const fs = require("fs");
const WEIGHTS = [
    100, -20, 10, 5, 5, 10, -20, 100, -20, -50, -2, -2, -2, -2, -50, -20, 10, -2, -1, -1, -1, -1,
    -2, 10, 5, -2, -1, -1, -1, -1, -2, 5, 5, -2, -1, -1, -1, -1, -2, 5, 10, -2, -1, -1, -1, -1, -2,
    10, -20, -50, -2, -2, -2, -2, -50, -20, 100, -20, 10, 5, 5, 10, -20, 100,
];
const TRANSFORMS = ["rot90", "rot180", "rot270", "mirror", "flip", "diag", "anti"];
const ZERO = [
    "NEW",
    "DUMP",
    "SHOW",
    "SCORE",
    "LEGAL",
    "HISTORY",
    "SHEET",
    "STATS",
    "EVAL",
    "STABLE",
    "SOLVE",
];
const NUMERIC = ["UNDO", "REDO", "HINT", "PV", "AI", "ANALYZE", "RANDOM", "PERFT", "DIVIDE"];
const ACTIVE = [
    "FLIPS",
    "MOVE",
    "PLAY",
    "HINT",
    "PV",
    "AI",
    "SOLVE",
    "AUTOPLAY",
    "RANDOM",
    "MC",
    "DIVIDE",
];
const COMMANDS = [
    ...ZERO,
    ...NUMERIC,
    "LOAD",
    "TRANSFORM",
    "AUTOPLAY",
    "MC",
    "FLIPS",
    "MOVE",
    "PLAY",
    "RECORD",
];
const other = (s) => (s === "B" ? "W" : "B");
const name = (p) => "abcdefgh"[p % 8] + (Math.floor(p / 8) + 1);
const square = (s) => (Number(s[1]) - 1) * 8 + s.charCodeAt(0) - 97;
const inside = (r, c) => r >= 0 && r < 8 && c >= 0 && c < 8;
function initial() {
    const b = Array(64).fill(".");
    b[27] = "W";
    b[36] = "W";
    b[28] = "B";
    b[35] = "B";
    return b.join("");
}
function flips(b, s, p) {
    if (b[p] !== ".") return [];
    const out = [],
        r = Math.floor(p / 8),
        c = p % 8;
    for (let dr = -1; dr <= 1; dr++)
        for (let dc = -1; dc <= 1; dc++) {
            if (!dr && !dc) continue;
            let y = r + dr,
                x = c + dc;
            const line = [];
            while (inside(y, x) && b[8 * y + x] === other(s)) {
                line.push(8 * y + x);
                y += dr;
                x += dc;
            }
            if (line.length && inside(y, x) && b[8 * y + x] === s) out.push(...line);
        }
    return out.sort((a, b) => a - b);
}
const legal = (b, s) =>
    Array.from(
        {
            length: 64,
        },
        (_, i) => i,
    ).filter((p) => b[p] === "." && flips(b, s, p).length);
function place(b, s, p) {
    const a = b.split("");
    for (const q of flips(b, s, p)) a[q] = s;
    a[p] = s;
    return a.join("");
}
const count = (b, s) => b.split("").filter((x) => x === s).length;
const terminal = (b) => !legal(b, "B").length && !legal(b, "W").length;
function gameOver(b) {
    const x = count(b, "B"),
        y = count(b, "W");
    return `game over B ${x} W ${y} ${x > y ? "winner B" : x < y ? "winner W" : "draw"}`;
}
function evaluate(b, s) {
    let w = 0;
    for (let i = 0; i < 64; i++) w += b[i] === s ? WEIGHTS[i] : b[i] === other(s) ? -WEIGHTS[i] : 0;
    const own = legal(b, s).length,
        enemy = legal(b, other(s)).length;
    return [w + 10 * (own - enemy), w, own, enemy];
}
const searchCache = new Map(),
    perftCache = new Map();
function search(b, s, d) {
    const key = b + s + ":" + d;
    if (searchCache.has(key)) return searchCache.get(key);
    const moves = legal(b, s),
        o = other(s);
    let v;
    if (!moves.length && !legal(b, o).length) v = (d < 0 ? 1 : 1000) * (count(b, s) - count(b, o));
    else if (d === 0) v = evaluate(b, s)[0];
    else if (!moves.length) v = -search(b, o, d < 0 ? -1 : d - 1);
    else {
        v = -1000000;
        for (const p of moves) v = Math.max(v, -search(place(b, s, p), o, d < 0 ? -1 : d - 1));
    }
    if (searchCache.size > 300000) searchCache.clear();
    searchCache.set(key, v);
    return v;
}
const ranked = (b, s, d) =>
    legal(b, s)
        .map((p) => [-search(place(b, s, p), other(s), d < 0 ? -1 : d - 1), p])
        .sort((a, b) => b[0] - a[0] || a[1] - b[1]);
function variation(b, s, d) {
    const steps = [];
    while (!terminal(b) && d !== 0) {
        const ms = ranked(b, s, d);
        if (ms.length) {
            steps.push(name(ms[0][1]));
            b = place(b, s, ms[0][1]);
        } else steps.push("pass");
        s = other(s);
        if (d > 0) d--;
    }
    return {
        steps,
        board: b,
    };
}
function perft(b, s, d) {
    if (!d) return 1;
    const key = b + s + d;
    if (perftCache.has(key)) return perftCache.get(key);
    const ms = legal(b, s),
        o = other(s);
    const n = ms.length
        ? ms.reduce((t, p) => t + perft(place(b, s, p), o, d - 1), 0)
        : legal(b, o).length
          ? perft(b, o, d - 1)
          : 1;
    if (perftCache.size > 200000) perftCache.clear();
    perftCache.set(key, n);
    return n;
}
function stable(b) {
    const set = new Set(),
        axes = [
            [0, 1],
            [1, 0],
            [1, 1],
            [1, -1],
        ];
    while (true) {
        const found = [];
        for (let p = 0; p < 64; p++) {
            if (b[p] === "." || set.has(p)) continue;
            const row = Math.floor(p / 8),
                col = p % 8;
            let ok = true;
            for (const [dr, dc] of axes) {
                let full = true,
                    anchor = false;
                for (const sign of [-1, 1]) {
                    let r = row + dr * sign,
                        c = col + dc * sign;
                    if (!inside(r, c) || (set.has(8 * r + c) && b[8 * r + c] === b[p]))
                        anchor = true;
                    while (inside(r, c)) {
                        if (b[8 * r + c] === ".") full = false;
                        r += dr * sign;
                        c += dc * sign;
                    }
                }
                if (!full && !anchor) {
                    ok = false;
                    break;
                }
            }
            if (ok) found.push(p);
        }
        if (!found.length) break;
        for (const p of found) set.add(p);
    }
    return ["B", "W"].map((s) => [...set].filter((p) => b[p] === s).length);
}
function transform(p, op) {
    const r = Math.floor(p / 8),
        c = p % 8;
    switch (op) {
        case "rot90":
            return 8 * c + 7 - r;
        case "rot180":
            return 63 - p;
        case "rot270":
            return 8 * (7 - c) + r;
        case "mirror":
            return 8 * r + 7 - c;
        case "flip":
            return 8 * (7 - r) + c;
        case "diag":
            return 8 * c + r;
        default:
            return 8 * (7 - c) + 7 - r;
    }
}
function transformBoard(b, op) {
    const a = Array(64).fill(".");
    for (let p = 0; p < 64; p++) a[transform(p, op)] = b[p];
    return a.join("");
}
class Random {
    constructor(seed) {
        this.value = seed;
    }
    draw() {
        this.value = (this.value * 48271) % 2147483647;
        return this.value;
    }
}
function randomGame(b, s, rng) {
    while (true) {
        const ms = legal(b, s);
        if (ms.length) b = place(b, s, ms[rng.draw() % ms.length]);
        else if (!legal(b, other(s)).length) return b;
        s = other(s);
    }
}
const average = (f, n) => {
    const v = Math.floor((100 * f) / n);
    return Math.floor(v / 100) + "." + String(v % 100).padStart(2, "0");
};
class Othello {
    constructor() {
        this.reset();
        this.output = [];
    }
    reset() {
        this.board = initial();
        this.side = "B";
        this.over = false;
        this.history = [];
        this.redo = [];
    }
    emit(...xs) {
        this.output.push(xs.join(" "));
    }
    snapshot() {
        return {
            board: this.board,
            side: this.side,
            over: this.over,
        };
    }
    restore(p) {
        this.board = p.board;
        this.side = p.side;
        this.over = p.over;
    }
    status() {
        return this.over ? gameOver(this.board) : this.side + " to move";
    }
    adjust(quiet = false) {
        if (legal(this.board, this.side).length) return false;
        if (legal(this.board, other(this.side)).length) {
            if (!quiet) this.emit(this.side, "passes");
            this.side = other(this.side);
            return true;
        }
        this.over = true;
        if (!quiet) this.emit(gameOver(this.board));
        return false;
    }
    move(p, quiet = false, value = null) {
        const before = this.snapshot(),
            s = this.side,
            k = flips(this.board, s, p).length;
        this.board = place(this.board, s, p);
        if (!quiet) this.emit(s, name(p), "flips", k, ...(value === null ? [] : ["value", value]));
        this.side = other(s);
        const passed = this.adjust(quiet);
        this.history.push({
            side: s,
            square: p,
            count: k,
            passed,
            before,
            after: this.snapshot(),
        });
        this.redo = [];
        return passed;
    }
    reason(p) {
        return this.over
            ? "game over"
            : this.board[p] !== "."
              ? "occupied"
              : !flips(this.board, this.side, p).length
                ? "no flips"
                : "";
    }
    record(text) {
        const e = new Othello(),
            ps = text.match(/../g).map(square);
        let passes = 0;
        for (let i = 0; i < ps.length; i++) {
            const why = e.reason(ps[i]);
            if (why) {
                this.emit("ILLEGAL move", i + 1, name(ps[i]), why);
                return;
            }
            if (e.move(ps[i], true)) passes++;
        }
        this.restore(e.snapshot());
        this.history = e.history;
        this.redo = [];
        const op = {
            f5: "",
            e6: "diag",
            d3: "anti",
            c4: "rot180",
        }[name(ps[0])];
        this.emit("record", ps.length, "moves", passes, "passes");
        this.emit("normal", ps.map((p) => name(op ? transform(p, op) : p)).join(""));
        this.emit(this.status());
    }
    sheet() {
        const fields = (this.history.length ? this.history[0].before.board : this.board).split("");
        this.history.forEach((r, i) => (fields[r.square] = String(i + 1)));
        this.emit(" " + [..."abcdefgh"].map((c) => c.padStart(3)).join(""));
        for (let r = 0; r < 8; r++)
            this.emit(
                String(r + 1) +
                    fields
                        .slice(8 * r, 8 * r + 8)
                        .map((x) => x.padStart(3))
                        .join(""),
            );
    }
    stats() {
        const all = this.history,
            total = all.reduce((s, r) => s + r.count, 0);
        if (!all.length) this.emit("moves 0");
        else
            this.emit(
                "moves",
                all.length,
                "flips",
                total,
                "avg",
                average(total, all.length),
                "passes",
                all.filter((r) => r.passed).length,
            );
        for (const side of ["B", "W"]) {
            const rows = all.filter((r) => r.side === side);
            if (!rows.length) {
                this.emit(side, "moves 0");
                continue;
            }
            const sum = rows.reduce((s, r) => s + r.count, 0),
                max = Math.max(...rows.map((r) => r.count));
            this.emit(
                side,
                "moves",
                rows.length,
                "flips",
                sum,
                "avg",
                average(sum, rows.length),
                "max",
                max,
                name(rows.find((r) => r.count === max).square),
                "corners",
                rows.filter((r) => [0, 7, 56, 63].includes(r.square)).length,
            );
        }
    }
    auto(black, white, seed = 0) {
        const rng = seed ? new Random(seed) : null,
            ps = [];
        let passes = 0;
        while (!this.over) {
            const ms = legal(this.board, this.side),
                p = rng
                    ? ms[rng.draw() % ms.length]
                    : ranked(this.board, this.side, this.side === "B" ? black : white)[0][1];
            ps.push(name(p));
            if (this.move(p, true)) passes++;
        }
        this.emit(rng ? "random" : "autoplay", ps.length, "moves", passes, "passes");
        this.emit("moves", ps.join(""));
        this.emit(gameOver(this.board));
    }
    monteCarlo(k, seed) {
        const rng = new Random(seed);
        let best = -1,
            bp = -1;
        for (const p of legal(this.board, this.side)) {
            let w = 0,
                d = 0,
                l = 0;
            const start = place(this.board, this.side, p);
            for (let i = 0; i < k; i++) {
                const end = randomGame(start, other(this.side), rng),
                    diff = count(end, this.side) - count(end, other(this.side));
                if (diff > 0) w++;
                else if (diff < 0) l++;
                else d++;
            }
            this.emit(name(p), w, d, l);
            if (2 * w + d > best) {
                best = 2 * w + d;
                bp = p;
            }
        }
        this.emit("best", name(bp), best);
    }
    execute(text) {
        const [cmd, ...a] = text.split(" ");
        let error = "";
        if (!COMMANDS.includes(cmd)) error = "unknown command";
        else if (cmd === "LOAD") {
            if (a.length !== 2 || !/^[.BW]{64}$/.test(a[0]) || !["B", "W"].includes(a[1]))
                error = "bad board";
        } else if (["MOVE", "FLIPS"].includes(cmd)) {
            if (a.length !== 1) error = "bad arguments";
            else if (!/^[a-h][1-8]$/.test(a[0])) error = "bad square";
        } else if (["PLAY", "RECORD"].includes(cmd)) {
            if (a.length !== 1) error = "bad arguments";
            else if (a[0].length > 120 || !/^([a-h][1-8])+$/.test(a[0])) error = "bad record";
        } else if (ZERO.includes(cmd)) {
            if (a.length) error = "bad arguments";
        } else if (cmd === "TRANSFORM") {
            if (a.length !== 1 || !TRANSFORMS.includes(a[0])) error = "bad arguments";
        } else {
            const n = a.map(Number),
                expected = ["AUTOPLAY", "MC"].includes(cmd) ? 2 : 1;
            if (a.length !== expected || a.some((x) => !/^[0-9]+$/.test(x)))
                error = "bad arguments";
            else {
                let ok;
                if (cmd === "AUTOPLAY") ok = n.every((v) => v >= 1 && v <= 4);
                else if (["HINT", "PV", "AI", "ANALYZE"].includes(cmd)) ok = n[0] >= 1 && n[0] <= 4;
                else if (["PERFT", "DIVIDE"].includes(cmd)) ok = n[0] >= 1 && n[0] <= 8;
                else if (cmd === "MC")
                    ok = n[0] >= 1 && n[0] <= 100 && n[1] >= 1 && n[1] <= 2147483646;
                else if (cmd === "RANDOM") ok = n[0] >= 1 && n[0] <= 2147483646;
                else ok = n[0] >= 1;
                if (!ok) error = "bad arguments";
            }
        }
        if (error) {
            this.emit("ERROR", error);
            return;
        }
        if (ACTIVE.includes(cmd) && this.over) {
            this.emit("ERROR game over");
            return;
        }
        const n = Number(a[0]);
        switch (cmd) {
            case "NEW":
                this.reset();
                this.emit("OK");
                break;
            case "LOAD":
                this.board = a[0];
                this.side = a[1];
                this.over = false;
                this.history = [];
                this.redo = [];
                this.emit("OK");
                this.adjust();
                break;
            case "DUMP":
                this.emit("board", this.board, this.side);
                break;
            case "SHOW": {
                this.emit("  a b c d e f g h");
                const ms = this.over ? [] : legal(this.board, this.side);
                for (let r = 0; r < 8; r++)
                    this.emit(
                        r + 1,
                        ...Array.from(
                            {
                                length: 8,
                            },
                            (_, c) => (ms.includes(8 * r + c) ? "*" : this.board[8 * r + c]),
                        ),
                    );
                this.emit(this.status());
                break;
            }
            case "SCORE":
                this.emit(
                    "score B",
                    count(this.board, "B"),
                    "W",
                    count(this.board, "W"),
                    "empty",
                    count(this.board, "."),
                );
                break;
            case "LEGAL": {
                const ms = this.over ? [] : legal(this.board, this.side);
                this.emit("legal", ms.length, ...ms.map(name));
                break;
            }
            case "MOVE":
            case "FLIPS": {
                const p = square(a[0]),
                    why = this.reason(p);
                if (why) this.emit("ILLEGAL", why);
                else if (cmd === "MOVE") this.move(p);
                else {
                    const f = flips(this.board, this.side, p);
                    this.emit("flips", a[0], f.length, ...f.map(name));
                }
                break;
            }
            case "PLAY": {
                for (let i = 0; i < a[0].length; i += 2) {
                    const p = square(a[0].slice(i, i + 2)),
                        why = this.reason(p);
                    if (why) {
                        this.emit("ILLEGAL move", i / 2 + 1, name(p), why);
                        break;
                    }
                    this.move(p);
                }
                break;
            }
            case "RECORD":
                this.record(a[0]);
                break;
            case "UNDO":
                if (n > this.history.length) this.emit("ERROR cannot undo");
                else {
                    const removed = this.history.splice(this.history.length - n);
                    this.restore(removed[0].before);
                    this.redo = [...removed, ...this.redo];
                    this.emit(this.status());
                }
                break;
            case "REDO":
                if (n > this.redo.length) this.emit("ERROR cannot redo");
                else {
                    const added = this.redo.splice(0, n);
                    this.history.push(...added);
                    this.restore(added.at(-1).after);
                    this.emit(this.status());
                }
                break;
            case "HISTORY":
                this.emit("history", this.history.length);
                this.history.forEach((r, i) =>
                    this.emit(
                        i + 1,
                        r.side,
                        name(r.square),
                        r.count,
                        ...(r.passed ? ["pass"] : []),
                    ),
                );
                break;
            case "SHEET":
                this.sheet();
                break;
            case "STATS":
                this.stats();
                break;
            case "TRANSFORM": {
                const op = a[0];
                this.board = transformBoard(this.board, op);
                for (const r of [...this.history, ...this.redo]) {
                    r.square = transform(r.square, op);
                    r.before = {
                        ...r.before,
                        board: transformBoard(r.before.board, op),
                    };
                    r.after = {
                        ...r.after,
                        board: transformBoard(r.after.board, op),
                    };
                }
                this.emit("OK");
                break;
            }
            case "EVAL": {
                const [v, w, x, y] = evaluate(this.board, this.side);
                this.emit("eval", v, "weights", w, "mobility", x, y);
                break;
            }
            case "STABLE": {
                const [b, w] = stable(this.board);
                this.emit("stable B", b, "W", w);
                break;
            }
            case "HINT":
                for (const [v, p] of ranked(this.board, this.side, n)) this.emit(name(p), v);
                break;
            case "PV": {
                const v = search(this.board, this.side, n),
                    pv = variation(this.board, this.side, n);
                this.emit("pv", v, ...pv.steps);
                break;
            }
            case "AI": {
                const [v, p] = ranked(this.board, this.side, n)[0];
                this.move(p, false, v);
                break;
            }
            case "ANALYZE": {
                const loss = {
                    B: 0,
                    W: 0,
                };
                this.history.forEach((r, i) => {
                    const rankedMoves = ranked(r.before.board, r.side, n),
                        [best, bp] = rankedMoves[0],
                        v = rankedMoves.find((x) => x[1] === r.square)[0];
                    loss[r.side] += best - v;
                    this.emit(i + 1, r.side, name(r.square), v, "best", name(bp), best);
                });
                this.emit("loss B", loss.B, "W", loss.W);
                break;
            }
            case "SOLVE":
                if (count(this.board, ".") >= 9) this.emit("ERROR too many empties");
                else {
                    for (const [v, p] of ranked(this.board, this.side, -1)) this.emit(name(p), v);
                    const pv = variation(this.board, this.side, -1);
                    this.emit("line", ...pv.steps);
                    this.emit("final B", count(pv.board, "B"), "W", count(pv.board, "W"));
                }
                break;
            case "AUTOPLAY":
                this.auto(n, Number(a[1]));
                break;
            case "RANDOM":
                this.auto(0, 0, n);
                break;
            case "MC":
                this.monteCarlo(n, Number(a[1]));
                break;
            case "PERFT":
                this.emit("perft", n, perft(this.board, this.side, n));
                break;
            case "DIVIDE": {
                let total = 0;
                for (const p of legal(this.board, this.side)) {
                    const v = perft(place(this.board, this.side, p), other(this.side), n - 1);
                    this.emit(name(p), v);
                    total += v;
                }
                this.emit("total", total);
                break;
            }
        }
    }
}
const input = fs.readFileSync(0, "utf8").trimEnd().split("\n"),
    engine = new Othello();
for (const line of input.slice(1, Number(input[0]) + 1)) engine.execute(line);
process.stdout.write(engine.output.join("\n") + "\n");
