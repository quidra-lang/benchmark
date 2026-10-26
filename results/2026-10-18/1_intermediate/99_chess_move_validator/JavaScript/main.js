const fs = require("fs");
const FILES = "abcdefgh",
    RANKS = "12345678",
    INITIAL = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
const ROOK = [
        [0, 1],
        [0, -1],
        [-1, 0],
        [1, 0],
    ],
    BISHOP = [
        [1, 1],
        [-1, 1],
        [1, -1],
        [-1, -1],
    ],
    KING = [...ROOK, ...BISHOP],
    KNIGHT = [
        [1, 2],
        [2, 1],
        [2, -1],
        [1, -2],
        [-1, -2],
        [-2, -1],
        [-2, 1],
        [-1, 2],
    ];
const RULES = {
    K: [4, 7, 6, 5, [5, 6]],
    Q: [4, 0, 2, 3, [1, 2, 3]],
    k: [60, 63, 62, 61, [61, 62]],
    q: [60, 56, 58, 59, [57, 58, 59]],
};
const fail = (reason) => {
    throw new Error(reason);
};
const emit = (text) => console.log(text);
const opposite = (c) => (c === "w" ? "b" : "w");
const color = (p) => (p === p.toUpperCase() ? "w" : "b");
const colored = (p, c) => (c === "w" ? p : p.toLowerCase());
const step = (c) => (c === "w" ? 8 : -8);
const square = (s) =>
    s.length === 2 && FILES.includes(s[0]) && RANKS.includes(s[1])
        ? FILES.indexOf(s[0]) + 8 * RANKS.indexOf(s[1])
        : -1;
const name = (s) => FILES[s % 8] + RANKS[Math.floor(s / 8)];
const number = (s, lo, hi) => (/^(0|[1-9][0-9]*)$/.test(s) && +s >= lo && +s <= hi ? +s : -1);
const shift = (s, dx, dy) => {
    const x = (s % 8) + dx,
        y = Math.floor(s / 8) + dy;
    return x >= 0 && x < 8 && y >= 0 && y < 8 ? 8 * y + x : -1;
};
function targets(board, s) {
    const piece = board[s],
        kind = piece.toUpperCase();
    if ("PNK".includes(kind)) {
        const moves =
            kind === "P"
                ? [
                      [-1, color(piece) === "w" ? 1 : -1],
                      [1, color(piece) === "w" ? 1 : -1],
                  ]
                : kind === "N"
                  ? KNIGHT
                  : KING;
        return moves.map(([dx, dy]) => shift(s, dx, dy)).filter((t) => t >= 0);
    }
    const directions = kind === "Q" ? KING : kind === "R" ? ROOK : BISHOP,
        result = [];
    for (const [dx, dy] of directions)
        for (let t = shift(s, dx, dy); t >= 0; t = shift(t, dx, dy)) {
            result.push(t);
            if (board[t] !== ".") break;
        }
    return result;
}
function attackers(board, t, c) {
    const result = [];
    for (let s = 0; s < 64; s++)
        if (board[s] !== "." && color(board[s]) === c && targets(board, s).includes(t))
            result.push(s);
    return result;
}
class Position {
    constructor(board, side, rights, ep, half, full) {
        this.board = board;
        this.side = side;
        this.rights = rights;
        this.ep = ep;
        this.half = half;
        this.full = full;
        this.cached = null;
    }
    check(c = this.side) {
        return attackers(this.board, this.board.indexOf(colored("K", c)), opposite(c)).length > 0;
    }
    castle(m) {
        return this.board[m.s].toUpperCase() === "K" && Math.abs(m.t - m.s) === 2;
    }
    enpassant(m) {
        return (
            this.board[m.s].toUpperCase() === "P" && m.s % 8 !== m.t % 8 && this.board[m.t] === "."
        );
    }
    capture(m) {
        return this.board[m.t] !== "." || this.enpassant(m);
    }
    captured(m) {
        return this.board[m.t] !== "."
            ? this.board[m.t].toLowerCase()
            : this.enpassant(m)
              ? "p"
              : "-";
    }
    play(m) {
        const b = [...this.board],
            piece = b[m.s],
            kind = piece.toUpperCase();
        if (this.enpassant(m)) b[m.t - step(this.side)] = ".";
        if (this.castle(m)) {
            const r = RULES[colored(m.t > m.s ? "K" : "Q", this.side)];
            b[r[3]] = b[r[1]];
            b[r[1]] = ".";
        }
        b[m.t] = m.p ? colored(m.p, this.side) : piece;
        b[m.s] = ".";
        const rights = [...this.rights]
            .filter(
                (r) =>
                    (kind !== "K" || color(r) !== this.side) && ![m.s, m.t].includes(RULES[r][1]),
            )
            .join("");
        return new Position(
            b,
            opposite(this.side),
            rights,
            kind === "P" && Math.abs(m.t - m.s) === 16 ? (m.s + m.t) / 2 : -1,
            kind === "P" || this.capture(m) ? 0 : this.half + 1,
            this.full + (this.side === "b" ? 1 : 0),
        );
    }
    pseudo() {
        const result = [];
        for (let s = 0; s < 64; s++) {
            const p = this.board[s];
            if (p === "." || color(p) !== this.side) continue;
            const pawn = p.toUpperCase() === "P";
            let a = [];
            if (pawn) {
                const d = step(this.side),
                    rank = Math.floor(s / 8);
                if (this.board[s + d] === ".") {
                    a.push(s + d);
                    if (rank === (this.side === "w" ? 1 : 6) && this.board[s + 2 * d] === ".")
                        a.push(s + 2 * d);
                }
                a.push(
                    ...targets(this.board, s).filter(
                        (t) =>
                            (this.board[t] !== "." && color(this.board[t]) !== this.side) ||
                            t === this.ep,
                    ),
                );
            } else
                a = targets(this.board, s).filter(
                    (t) => this.board[t] === "." || color(this.board[t]) !== this.side,
                );
            for (const t of a)
                for (const promotion of pawn && Math.floor(t / 8) === (this.side === "w" ? 7 : 0)
                    ? "QRBN"
                    : [""])
                    result.push({ s, t, p: promotion });
        }
        return result;
    }
    castlingMove(kingside) {
        const r = RULES[colored(kingside ? "K" : "Q", this.side)];
        return { s: r[0], t: r[2], p: "" };
    }
    castlingProblem(kingside) {
        const right = colored(kingside ? "K" : "Q", this.side),
            r = RULES[right];
        if (!this.rights.includes(right)) return "no castling right";
        if (r[4].some((s) => this.board[s] !== ".")) return "path blocked";
        if (this.check()) return "in check";
        if (attackers(this.board, r[3], opposite(this.side)).length) return "through check";
        if (this.play(this.castlingMove(kingside)).check(this.side)) return "into check";
        return "";
    }
    legal() {
        if (this.cached !== null) return this.cached;
        const a = this.pseudo().filter((m) => !this.play(m).check(this.side));
        for (const k of [true, false]) if (!this.castlingProblem(k)) a.push(this.castlingMove(k));
        this.cached = a;
        return a;
    }
    mark(m) {
        const q = this.play(m);
        return q.check() ? (q.legal().length ? "+" : "#") : "";
    }
    disambiguation(m) {
        const others = this.legal().filter(
            (x) =>
                !this.castle(x) &&
                x.t === m.t &&
                x.s !== m.s &&
                this.board[x.s] === this.board[m.s],
        );
        if (!others.length) return "";
        if (others.every((x) => x.s % 8 !== m.s % 8)) return FILES[m.s % 8];
        if (others.every((x) => Math.floor(x.s / 8) !== Math.floor(m.s / 8)))
            return RANKS[Math.floor(m.s / 8)];
        return name(m.s);
    }
    san(m) {
        const kind = this.board[m.s].toUpperCase();
        let text;
        if (this.castle(m)) text = m.t > m.s ? "O-O" : "O-O-O";
        else if (kind === "P")
            text =
                (this.capture(m) ? FILES[m.s % 8] + "x" : "") + name(m.t) + (m.p ? "=" + m.p : "");
        else text = kind + this.disambiguation(m) + (this.capture(m) ? "x" : "") + name(m.t);
        return text + this.mark(m);
    }
    key() {
        return (
            this.board.join("") +
            " " +
            this.side +
            " " +
            this.rights +
            " " +
            (this.ep >= 0 && this.legal().some((m) => this.enpassant(m)) ? this.ep : -1)
        );
    }
    state() {
        return this.check()
            ? this.legal().length
                ? "check"
                : "checkmate"
            : this.legal().length
              ? "normal"
              : "stalemate";
    }
    insufficient() {
        const a = [];
        for (let s = 0; s < 64; s++)
            if (this.board[s] !== "." && this.board[s].toUpperCase() !== "K") a.push(s);
        if (a.some((s) => "PRQ".includes(this.board[s].toUpperCase()))) return false;
        return (
            a.length <= 1 ||
            (a.every((s) => this.board[s].toUpperCase() === "B") &&
                new Set(a.map((s) => ((s % 8) + Math.floor(s / 8)) % 2)).size === 1)
        );
    }
    pins() {
        const king = this.board.indexOf(colored("K", this.side)),
            found = [];
        for (const [dx, dy] of KING) {
            let first = -1;
            for (let t = shift(king, dx, dy); t >= 0; t = shift(t, dx, dy)) {
                const p = this.board[t];
                if (p === ".") continue;
                if (first < 0) {
                    if (color(p) !== this.side) break;
                    first = t;
                } else {
                    if (
                        color(p) !== this.side &&
                        ("Q" + (dx === 0 || dy === 0 ? "R" : "B")).includes(p.toUpperCase())
                    )
                        found.push([first, t]);
                    break;
                }
            }
        }
        return found.sort((a, b) => a[0] - b[0]);
    }
    fen() {
        const rows = [];
        for (let r = 7; r >= 0; r--) {
            let text = "",
                empty = 0;
            for (let f = 0; f < 8; f++) {
                const p = this.board[r * 8 + f];
                if (p === ".") empty++;
                else {
                    if (empty) text += empty;
                    empty = 0;
                    text += p;
                }
            }
            if (empty) text += empty;
            rows.push(text);
        }
        return [
            rows.join("/"),
            this.side,
            this.rights || "-",
            this.ep < 0 ? "-" : name(this.ep),
            this.half,
            this.full,
        ].join(" ");
    }
}
function parseFen(a) {
    if (a.length !== 6) fail("fields");
    const ranks = a[0].split("/"),
        board = Array(64).fill(".");
    if (ranks.length !== 8) fail("placement");
    for (let i = 0; i < 8; i++) {
        let f = 0,
            digit = false;
        for (const c of ranks[i]) {
            if ("12345678".includes(c)) {
                if (digit) fail("placement");
                f += +c;
                digit = true;
            } else {
                if (!"KQRBNPkqrbnp".includes(c) || f >= 8) fail("placement");
                board[(7 - i) * 8 + f++] = c;
                digit = false;
            }
        }
        if (f !== 8) fail("placement");
    }
    if (board.filter((p) => p === "K").length !== 1 || board.filter((p) => p === "k").length !== 1)
        fail("kings");
    if ([...board.slice(0, 8), ...board.slice(56)].some((p) => p === "P" || p === "p"))
        fail("pawns");
    const side = a[1];
    if (!["w", "b"].includes(side)) fail("side");
    if (a[2] !== "-" && !/^(?=.+)K?Q?k?q?$/.test(a[2])) fail("castling");
    const rights = a[2] === "-" ? "" : a[2];
    for (const r of rights)
        if (
            board[RULES[r][0]] !== colored("K", color(r)) ||
            board[RULES[r][1]] !== colored("R", color(r))
        )
            fail("castling");
    let ep = -1;
    if (a[3] !== "-") {
        ep = square(a[3]);
        const d = step(side);
        if (
            ep < 0 ||
            Math.floor(ep / 8) !== (side === "w" ? 5 : 2) ||
            board[ep] !== "." ||
            board[ep + d] !== "." ||
            board[ep - d] !== colored("P", opposite(side))
        )
            fail("en passant");
    }
    const half = number(a[4], 0, 999),
        full = number(a[5], 1, 999);
    if (half < 0 || full < 0 || (ep >= 0 && half !== 0)) fail("clocks");
    const p = new Position(board, side, rights, ep, half, full);
    if (p.check(opposite(side))) fail("check");
    return p;
}
function readSan(pos, text) {
    const mark = /[+#]$/.test(text) ? text.at(-1) : "";
    let body = mark ? text.slice(0, -1) : text;
    const castling = body === "O-O" || body === "O-O-O";
    let p = "",
        target = -1,
        capture = false,
        kind = "P",
        file = "",
        rank = "";
    if (!castling) {
        if (body.length >= 2 && body.at(-2) === "=") {
            p = body.at(-1);
            if (!"QRBN".includes(p)) fail("syntax");
            body = body.slice(0, -2);
        }
        target = square(body.slice(-2));
        if (target < 0) fail("syntax");
        body = body.slice(0, -2);
        capture = body.endsWith("x");
        if (capture) body = body.slice(0, -1);
        if (body && "KQRBN".includes(body[0])) {
            kind = body[0];
            const hints = /^([a-h]?)([1-8]?)$/.exec(body.slice(1));
            if (!hints || p) fail("syntax");
            file = hints[1];
            rank = hints[2];
        } else {
            if (!(capture ? /^[a-h]$/ : /^$/).test(body)) fail("syntax");
            file = body;
        }
    }
    const legal = pos.legal();
    if (!legal.length) fail("game over");
    let move;
    if (castling) {
        const kingside = body === "O-O",
            problem = pos.castlingProblem(kingside);
        if (problem) fail(problem);
        move = pos.castlingMove(kingside);
    } else {
        const matches = (m) =>
            pos.board[m.s].toUpperCase() === kind &&
            m.t === target &&
            !pos.castle(m) &&
            (!file || FILES[m.s % 8] === file) &&
            (!rank || RANKS[Math.floor(m.s / 8)] === rank) &&
            (kind !== "P" || (m.s % 8 !== m.t % 8) === capture);
        const candidates = legal.filter(matches);
        if (!candidates.length)
            fail(pos.pseudo().some(matches) ? "leaves king in check" : "no such move");
        if (new Set(candidates.map((m) => m.s)).size > 1) fail("ambiguous");
        move = candidates[0];
        if (pos.capture(move) !== capture) fail("capture mark");
        if (move.p && !p) fail("missing promotion");
        if (p && !move.p) fail("invalid promotion");
        if (kind !== "P" && file + rank !== pos.disambiguation(move)) fail("disambiguation");
        move = { ...move, p };
    }
    if (pos.mark(move) !== mark) fail("check mark");
    return move;
}
function readUci(pos, text) {
    if (!/^[a-h][1-8][a-h][1-8][qrbn]?$/.test(text)) fail("syntax");
    const s = square(text.slice(0, 2)),
        t = square(text.slice(2, 4)),
        p = text.slice(4).toUpperCase(),
        legal = pos.legal();
    if (!legal.length) fail("game over");
    if (pos.board[s] === "." || color(pos.board[s]) !== pos.side) fail("no piece");
    const found = legal.find((m) => m.s === s && m.t === t);
    if (!found)
        fail(
            pos.pseudo().some((m) => m.s === s && m.t === t)
                ? "leaves king in check"
                : "no such move",
        );
    if (found.p && !p) fail("missing promotion");
    if (p && !found.p) fail("invalid promotion");
    return { s, t, p };
}
function perft(p, d, stats = null) {
    if (!d) return 1;
    let total = 0;
    for (const m of p.legal()) {
        const q = p.play(m);
        total += perft(q, d - 1, stats);
        if (d === 1 && stats) {
            stats[0]++;
            stats[1] += +p.capture(m);
            stats[2] += +p.enpassant(m);
            stats[3] += +p.castle(m);
            stats[4] += +(m.p !== "");
            if (q.check()) {
                stats[5]++;
                if (!q.legal().length) stats[6]++;
            }
        }
    }
    return total;
}
class Game {
    constructor(start = parseFen(INITIAL.split(" ")), loaded = false) {
        this.positions = [start];
        this.records = [];
        this.loaded = loaded;
    }
    current() {
        return this.positions.at(-1);
    }
    play(m) {
        const p = this.current();
        this.records.push({
            san: p.san(m),
            uci: name(m.s) + name(m.t) + m.p.toLowerCase(),
            captured: p.captured(m),
        });
        this.positions.push(p.play(m));
    }
    repetition() {
        const key = this.current().key();
        return this.positions.filter((p) => p.key() === key).length;
    }
    draws() {
        const p = this.current(),
            a = [];
        if (p.half >= 100) a.push("fifty");
        if (this.repetition() >= 3) a.push("threefold");
        if (p.insufficient()) a.push("insufficient");
        return a;
    }
    result() {
        const p = this.current(),
            state = p.state();
        return state === "checkmate"
            ? p.side === "b"
                ? "1-0"
                : "0-1"
            : state === "stalemate" || this.draws().length
              ? "1/2-1/2"
              : "*";
    }
}
let game = new Game();
function execute(line) {
    const [cmd, ...a] = line.split(" "),
        commands =
            "NEW LOAD FEN BOARD MOVE UCI LEGAL STATUS UNDO PERFT DIVIDE ATTACKS PINS HISTORY PGN".split(
                " ",
            );
    if (!commands.includes(cmd)) {
        emit("ERROR unknown command");
        return;
    }
    let n = -1;
    const noargs = ["NEW", "FEN", "BOARD", "STATUS", "PINS", "HISTORY", "PGN"];
    let bad =
        (noargs.includes(cmd) && a.length !== 0) ||
        (["MOVE", "UCI"].includes(cmd) && a.length === 0);
    if (cmd === "LEGAL") bad = a.length > 1 || (a.length === 1 && square(a[0]) < 0);
    if (cmd === "ATTACKS") bad = a.length !== 1 || square(a[0]) < 0;
    if (["UNDO", "PERFT", "DIVIDE"].includes(cmd)) {
        n = a.length === 1 ? number(a[0], 1, cmd === "UNDO" ? 9999 : 3) : -1;
        bad = n < 0;
    }
    if (bad) {
        emit("ERROR bad arguments");
        return;
    }
    const p = game.current();
    if (cmd === "NEW") {
        game = new Game();
        emit("OK");
    } else if (cmd === "LOAD") {
        try {
            const q = parseFen(a);
            game = new Game(q, true);
            emit("OK");
        } catch (e) {
            emit(`ERROR bad fen (${e.message})`);
        }
    } else if (cmd === "FEN") emit(p.fen());
    else if (cmd === "BOARD") {
        for (let r = 7; r >= 0; r--) emit([r + 1, ...p.board.slice(8 * r, 8 * r + 8)].join(" "));
        emit("  a b c d e f g h");
    } else if (cmd === "MOVE" || cmd === "UCI") {
        const played = [];
        let error = "";
        for (let i = 0; i < a.length; i++) {
            try {
                const m =
                    cmd === "MOVE" ? readSan(game.current(), a[i]) : readUci(game.current(), a[i]);
                game.play(m);
                played.push(game.records.at(-1).san);
            } catch (e) {
                error = `ILLEGAL move ${i + 1}: ${a[i]} (${e.message})`;
                break;
            }
        }
        if (cmd === "UCI" && played.length) emit("san " + played.join(" "));
        if (error) emit(error);
        else if (cmd === "MOVE") emit("OK");
    } else if (cmd === "LEGAL") {
        const from = a.length ? square(a[0]) : -1,
            list = p
                .legal()
                .filter((m) => from < 0 || m.s === from)
                .map((m) => p.san(m))
                .sort();
        emit(["legal", list.length, ...list].join(" "));
    } else if (cmd === "STATUS")
        emit(
            [
                "status",
                p.side === "w" ? "white" : "black",
                p.state(),
                "rep",
                game.repetition(),
                ...game.draws(),
            ].join(" "),
        );
    else if (cmd === "UNDO") {
        if (n > game.records.length) emit("ERROR cannot undo");
        else {
            game.records.splice(-n);
            game.positions.splice(-n);
            emit("OK");
        }
    } else if (cmd === "PERFT") {
        const stats = Array(7).fill(0);
        perft(p, n, stats);
        emit(
            [
                "perft",
                n,
                ...["nodes", "captures", "ep", "castles", "promotions", "checks", "mates"].flatMap(
                    (f, i) => [f, stats[i]],
                ),
            ].join(" "),
        );
    } else if (cmd === "DIVIDE") {
        const rows = p
            .legal()
            .map((m) => [p.san(m), perft(p.play(m), n - 1)])
            .sort((x, y) => (x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : 0));
        for (const row of rows) emit(row.join(" "));
        emit("total " + rows.reduce((s, r) => s + r[1], 0));
    } else if (cmd === "ATTACKS") {
        const t = square(a[0]),
            w = attackers(p.board, t, "w"),
            b = attackers(p.board, t, "b");
        emit(
            [
                "attacks",
                a[0],
                "white",
                w.length,
                ...w.map(name),
                "black",
                b.length,
                ...b.map(name),
            ].join(" "),
        );
    } else if (cmd === "PINS") {
        const pins = p.pins();
        emit(["pins", pins.length, ...pins.map(([s, t]) => name(s) + "-" + name(t))].join(" "));
    } else if (cmd === "HISTORY") {
        emit("history " + game.records.length);
        game.records.forEach((r, i) => emit(`${i + 1} ${r.uci} ${r.san} ${r.captured}`));
    } else if (cmd === "PGN") {
        const result = game.result();
        emit(`[Result "${result}"]`);
        if (game.loaded) {
            emit('[SetUp "1"]');
            emit(`[FEN "${game.positions[0].fen()}"]`);
        }
        const words = [];
        game.records.forEach((r, i) => {
            const q = game.positions[i];
            if (q.side === "w") words.push(q.full + ".");
            else if (!i) words.push(q.full + "...");
            words.push(r.san);
        });
        words.push(result);
        emit(words.join(" "));
    }
}
const lines = fs.readFileSync(0, "utf8").trimEnd().split(/\r?\n/);
for (const line of lines.slice(1, 1 + Number(lines[0]))) execute(line);
