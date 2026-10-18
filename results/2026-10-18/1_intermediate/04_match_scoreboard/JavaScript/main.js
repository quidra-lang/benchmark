import { readFileSync } from "node:fs";


class Invalid extends Error {}

function fail(reason) {
    throw new Invalid(reason);
}

function pair(values, reverse = false) {
    return (reverse ? [...values].reverse() : values).join("-");
}

function lex(a, b) {
    return a < b ? -1 : a > b ? 1 : 0;
}

const darts = new Map();
for (let n = 1; n <= 20; n++) {
    darts.set("S" + n, { value: n, double: false });
    darts.set("D" + n, { value: 2 * n, double: true });
    darts.set("T" + n, { value: 3 * n, double: false });
}
darts.set("25", { value: 25, double: false });
darts.set("BULL", { value: 50, double: true });
darts.set("MISS", { value: 0, double: false });
const candidatesA = [];
const candidatesB = [];
for (const prefix of ["S", "T", "D"]) {
    for (let n = 20; n >= 1; n--) {
        candidatesA.push(prefix + n);
        if (prefix === "D") {
            candidatesB.push(prefix + n);
        }
    }
}
candidatesA.push("25", "BULL");
candidatesB.push("BULL");
const checkoutCache = new Map();

function checkout(score, maximum = 3) {
    const key = score + ":" + maximum;
    if (checkoutCache.has(key)) {
        return checkoutCache.get(key);
    }
    let result = null;
    if (maximum >= 1) {
        const last = candidatesB.find(dart => darts.get(dart).value === score);
        if (last) {
            result = [last];
        }
    }
    if (!result && maximum >= 2) {
        for (const first of candidatesA) {
            const last = candidatesB.find(dart => darts.get(first).value + darts.get(dart).value === score);
            if (last) {
                result = [first, last];
                break;
            }
        }
    }
    if (!result && maximum >= 3) {
        outer: for (const first of candidatesA) {
            for (const second of candidatesA) {
                const wanted = score - darts.get(first).value - darts.get(second).value;
                const last = candidatesB.find(dart => darts.get(dart).value === wanted);
                if (last) {
                    result = [first, second, last];
                    break outer;
                }
            }
        }
    }
    checkoutCache.set(key, result);
    return result;
}

const choices = {
    TENNIS: { SETS: ["3", "5"], DEUCE: ["AD", "NOAD"], FINAL: ["TB7", "TB10", "ADV", "SUPER"], FIRST: ["A", "B"] },
    TABLETENNIS: { GAMES: ["5", "7"], FIRST: ["A", "B"] },
    BADMINTON: { FIRST: ["A", "B"] }, VOLLEYBALL: { FIRST: ["A", "B"] },
    DARTS: { START: ["301", "501", "701"], SETS: ["1", "2", "3", "4", "5"], LEGS: ["1", "2", "3", "4", "5"], FIRST: ["A", "B"] },
    BOWLING: {}
};
const defaults = {
    TENNIS: { SETS: "3", DEUCE: "AD", FINAL: "TB7", FIRST: "A" },
    TABLETENNIS: { GAMES: "5", FIRST: "A" }, BADMINTON: { FIRST: "A" },
    VOLLEYBALL: { FIRST: "A" }, BOWLING: {},
    DARTS: { START: "501", SETS: "1", LEGS: "1", FIRST: "A" }
};

class Match {
    id;
    sport;
    names;
    options;
    initialLineups;
    first;
    state;
    initialState;
    history = [];

    constructor(args) {
        this.id = args[0];
        this.sport = args[1];
        this.names = this.sport === "BOWLING" ? [args[2]] : [args[2], args[3]];
        this.initialLineups = this.sport === "VOLLEYBALL" ?
            [args[4].split(",").map(Number), args[5].split(",").map(Number)] : [[], []];
        const optionStart = this.sport === "BOWLING" ? 3 : this.sport === "VOLLEYBALL" ? 6 : 4;
        this.options = { ...defaults[this.sport] };
        const seen = new Set();
        for (const option of args.slice(optionStart)) {
            const parts = option.split("=");
            if (parts.length !== 2 || !Object.hasOwn(choices[this.sport], parts[0]) ||
                !choices[this.sport][parts[0]].includes(parts[1]) || seen.has(parts[0])) {
                fail("invalid option");
            }
            seen.add(parts[0]);
            this.options[parts[0]] = parts[1];
        }
        this.first = this.options.FIRST === "B" ? 1 : 0;
        const start = Number(this.options.START ?? 501);
        this.state = {
            done: false, winner: -1, sets: [0, 0], legs: [0, 0], points: [0, 0], games: [0, 0],
            finished: [], gameServer: this.first, server: this.first,
            lineups: this.initialLineups.map(lineup => [...lineup]), subs: [0, 0], timeouts: [0, 0],
            rally: Array.from({ length: 2 }, () => ({
                points: 0, served: 0, serveWon: 0, run: 0, current: 0,
                holds: 0, serviceGames: 0, breaks: 0, opportunities: 0, conversions: 0
            })),
            frames: Array.from({ length: 10 }, () => []), marks: Array.from({ length: 10 }, () => []),
            frame: 0, standing: 10, remaining: [start, start], player: this.first, legNumber: 0,
            turn: [], turnStart: start, turnScore: 0,
            darts: Array.from({ length: 2 }, () => ({
                darts: 0, points: 0, busts: 0, high: 0, tons: 0, maximums: 0, attempts: 0, hits: 0
            }))
        };
        this.initialState = structuredClone(this.state);
    }

    rallySport() {
        return ["TENNIS", "TABLETENNIS", "BADMINTON", "VOLLEYBALL"].includes(this.sport);
    }

    finalSet(s) {
        const target = Math.floor(Number(this.options.SETS) / 2);
        return s.sets[0] === target && s.sets[1] === target;
    }

    tennisKind(s) {
        if (this.finalSet(s) && this.options.FINAL === "SUPER") {
            return "super";
        }
        if (s.games[0] === 6 && s.games[1] === 6 && !(this.finalSet(s) && this.options.FINAL === "ADV")) {
            return "tie";
        }
        return "normal";
    }

    server(s) {
        if (this.sport === "TENNIS") {
            if (this.tennisKind(s) === "normal") {
                return s.gameServer;
            }
            const k = s.points[0] + s.points[1] + 1;
            return s.gameServer ^ (Math.floor(k / 2) % 2);
        }
        if (this.sport === "TABLETENNIS") {
            const first = this.first ^ (s.finished.length % 2);
            const t = s.points[0] + s.points[1];
            return first ^ (t < 20 ? Math.floor(t / 2) % 2 : t % 2);
        }
        return s.server;
    }

    normalGameWins(points, winner) {
        return points[winner] >= 4 && (this.options.DEUCE === "NOAD" || points[winner] - points[1 - winner] >= 2);
    }

    finishRallyUnit(s, winner, record, target) {
        s.finished.push(record);
        s.sets[winner]++;
        if (s.sets[winner] === target) {
            s.done = true;
            s.winner = winner;
        } else {
            s.points = [0, 0];
            s.games = [0, 0];
            if (this.sport === "VOLLEYBALL") {
                s.lineups = this.initialLineups.map(lineup => [...lineup]);
                s.subs = [0, 0];
                s.timeouts = [0, 0];
                s.server = this.first ^ (s.finished.length % 2);
            }
        }
    }

    point(s, winner) {
        const server = this.server(s);
        s.rally[winner].points++;
        s.rally[server].served++;
        if (winner === server) {
            s.rally[server].serveWon++;
        }
        s.rally[winner].current++;
        s.rally[winner].run = Math.max(s.rally[winner].run, s.rally[winner].current);
        s.rally[1 - winner].current = 0;
        if (this.sport === "TENNIS") {
            const kind = this.tennisKind(s);
            if (kind === "normal") {
                const receiver = 1 - server;
                const hypothetical = [...s.points];
                hypothetical[receiver]++;
                if (this.normalGameWins(hypothetical, receiver)) {
                    s.rally[receiver].opportunities++;
                    if (winner === receiver) {
                        s.rally[receiver].conversions++;
                    }
                }
            }
            s.points[winner]++;
            const targetSets = Math.floor(Number(this.options.SETS) / 2) + 1;
            if (kind === "normal" && this.normalGameWins(s.points, winner)) {
                s.rally[server].serviceGames++;
                if (winner === server) {
                    s.rally[server].holds++;
                } else {
                    s.rally[winner].breaks++;
                }
                s.games[winner]++;
                s.points = [0, 0];
                s.gameServer ^= 1;
                if (s.games[winner] >= 6 && s.games[winner] - s.games[1 - winner] >= 2) {
                    this.finishRallyUnit(s, winner, { values: [...s.games], tie: -1, super: false }, targetSets);
                }
            } else if (kind !== "normal") {
                const target = kind === "super" || (this.finalSet(s) && this.options.FINAL === "TB10") ? 10 : 7;
                if (s.points[winner] >= target && s.points[winner] - s.points[1 - winner] >= 2) {
                    const record = kind === "super" ?
                        { values: [...s.points], tie: -1, super: true } :
                        { values: s.games.map((value, i) => value + (i === winner ? 1 : 0)), tie: s.points[1 - winner], super: false };
                    s.gameServer ^= 1;
                    this.finishRallyUnit(s, winner, record, targetSets);
                }
            }
        } else {
            s.points[winner]++;
            if (this.sport === "BADMINTON") {
                s.server = winner;
            } else if (this.sport === "VOLLEYBALL" && winner !== s.server) {
                s.server = winner;
                const player = s.lineups[winner].shift();
                s.lineups[winner].push(player);
            }
            const target = this.sport === "TABLETENNIS" ? 11 : this.sport === "BADMINTON" ? 21 :
                s.finished.length === 4 ? 15 : 25;
            const won = (s.points[winner] >= target && s.points[winner] - s.points[1 - winner] >= 2) ||
                (this.sport === "BADMINTON" && s.points[winner] === 30);
            if (won) {
                const needed = this.sport === "TABLETENNIS" ? Math.floor(Number(this.options.GAMES) / 2) + 1 :
                    this.sport === "BADMINTON" ? 2 : 3;
                this.finishRallyUnit(s, winner, { values: [...s.points], tie: -1, super: false }, needed);
            }
        }
    }

    standing(s) {
        return s.frame === 9 && s.standing === 0 ? 10 : s.standing;
    }

    roll(s, pins) {
        const standing = this.standing(s);
        if (pins > standing) {
            fail("too many pins");
        }
        const frame = s.frames[s.frame];
        const freshRack = frame.length === 0 || (s.frame === 9 && s.standing === 0);
        const mark = freshRack && pins === 10 ? "X" : pins === standing ? "/" : pins === 0 ? "-" : String(pins);
        frame.push(pins);
        s.marks[s.frame].push(mark);
        s.standing = standing - pins;
        if (s.frame < 9) {
            if (pins === 10 && frame.length === 1 || frame.length === 2) {
                s.frame++;
                s.standing = 10;
            }
        } else if (frame.length === 3 || (frame.length === 2 && frame[0] !== 10 && frame[0] + frame[1] < 10)) {
            s.done = true;
        }
    }

    frameScores(s) {
        return s.frames.map((frame, i) => {
            if (i === 9) {
                return s.done ? frame.reduce((a, b) => a + b, 0) : null;
            }
            const later = s.frames.slice(i + 1).flat();
            if (frame[0] === 10) {
                return later.length >= 2 ? 10 + later[0] + later[1] : null;
            }
            if (frame.length < 2) {
                return null;
            }
            if (frame[0] + frame[1] === 10) {
                return later.length ? 10 + later[0] : null;
            }
            return frame[0] + frame[1];
        });
    }

    maximum(s) {
        const hypothetical = structuredClone(s);
        while (!hypothetical.done) {
            this.roll(hypothetical, this.standing(hypothetical));
        }
        return this.frameScores(hypothetical).reduce((sum, value) => sum + (value ?? 0), 0);
    }

    completedTurn(s, player) {
        const stats = s.darts[player];
        stats.high = Math.max(stats.high, s.turnScore);
        if (s.turnScore >= 100) {
            stats.tons++;
        }
        if (s.turnScore === 180) {
            stats.maximums++;
        }
    }

    nextTurn(s) {
        s.player = 1 - s.player;
        s.turn = [];
        s.turnScore = 0;
        s.turnStart = s.remaining[s.player];
    }

    throwDart(s, notation) {
        const dart = darts.get(notation);
        if (!dart) {
            fail("invalid dart");
        }
        const player = s.player;
        const stats = s.darts[player];
        const before = s.remaining[player];
        stats.darts++;
        if (before === 50 || before <= 40 && before % 2 === 0) {
            stats.attempts++;
        }
        s.turn.push(notation);
        s.turnScore += dart.value;
        stats.points += dart.value;
        const remaining = before - dart.value;
        if (remaining < 0 || remaining === 1 || remaining === 0 && !dart.double) {
            stats.busts++;
            stats.points -= s.turnScore;
            s.remaining[player] = s.turnStart;
            this.nextTurn(s);
        } else {
            s.remaining[player] = remaining;
            if (remaining === 0) {
                stats.hits++;
                this.completedTurn(s, player);
                s.legs[player]++;
                if (s.legs[player] === Number(this.options.LEGS)) {
                    s.sets[player]++;
                    s.finished.push({ values: [...s.legs], tie: -1, super: false });
                    if (s.sets[player] === Number(this.options.SETS)) {
                        s.done = true;
                        s.winner = player;
                        return;
                    }
                    s.legs = [0, 0];
                }
                s.legNumber++;
                const start = Number(this.options.START);
                s.remaining = [start, start];
                s.player = this.first ^ (s.legNumber % 2);
                s.turn = [];
                s.turnScore = 0;
                s.turnStart = start;
            } else if (s.turn.length === 3) {
                this.completedTurn(s, player);
                this.nextTurn(s);
            }
        }
    }

    apply(name, args) {
        if (name === "POINT") {
            this.point(this.state, args[0] === "A" ? 0 : 1);
        } else if (name === "ROLL") {
            this.roll(this.state, Number(args[0]));
        } else if (name === "THROW") {
            this.throwDart(this.state, args[0]);
        } else {
            const side = args[0] === "A" ? 0 : 1;
            if (name === "SUB") {
                const lineup = this.state.lineups[side];
                const position = lineup.indexOf(Number(args[1]));
                if (position < 0) {
                    fail("player not on court");
                }
                if (lineup.includes(Number(args[2]))) {
                    fail("player already on court");
                }
                if (this.state.subs[side] >= 6) {
                    fail("no substitutions left");
                }
                lineup[position] = Number(args[2]);
                this.state.subs[side]++;
            } else {
                if (this.state.timeouts[side] >= 2) {
                    fail("no timeouts left");
                }
                this.state.timeouts[side]++;
            }
        }
    }

    event(name, args) {
        const allowed = name === "POINT" ? this.rallySport() : name === "ROLL" ? this.sport === "BOWLING" :
            name === "THROW" ? this.sport === "DARTS" : this.sport === "VOLLEYBALL";
        if (!allowed) {
            fail("wrong event");
        }
        const events = name === "POINT" ? args[0].split("").map(value => [value]) :
            name === "ROLL" || name === "THROW" ? args.map(value => [value]) : [args];
        for (const values of events) {
            if (this.state.done) {
                fail("match over");
            }
            this.apply(name, values);
            this.history.push({ name, args: values });
        }
    }

    scoreRecord(record, reverse = false) {
        const value = pair(record.values, reverse);
        return record.super ? "[" + value + "]" : value + (record.tie >= 0 ? "(" + record.tie + ")" : "");
    }

    situation(side) {
        const s = this.state;
        const next = structuredClone(s);
        const server = this.server(s);
        const normal = this.sport === "TENNIS" && this.tennisKind(s) === "normal";
        this.point(next, side);
        if (next.done) {
            return "match point";
        }
        if (next.finished.length > s.finished.length) {
            return ["TENNIS", "VOLLEYBALL"].includes(this.sport) ? "set point" : "game point";
        }
        if (normal && next.gameServer !== s.gameServer) {
            return side === server ? "game point" : "break point";
        }
        return "";
    }

    score() {
        const s = this.state;
        if (this.sport === "BOWLING") {
            const scores = this.frameScores(s);
            let total = 0;
            const items = [];
            for (let i = 0; i < 10; i++) {
                if (!s.frames[i].length) {
                    break;
                }
                let value = s.marks[i].join("");
                if (scores[i] !== null) {
                    total += scores[i];
                    value += "(" + total + ")";
                }
                items.push(value);
            }
            return this.id + ": " + this.names[0] + (items.length ? " " + items.join(" ") : "");
        }
        const server = this.sport === "DARTS" ? s.player : this.server(s);
        const names = this.names.map((name, i) => name + (!s.done && i === server ? "*" : ""));
        const items = s.finished.map(record => this.scoreRecord(record));
        if (this.sport === "DARTS") {
            items.splice(0, items.length, "sets", pair(s.sets), "legs", pair(s.legs), "score", pair(s.remaining));
            if (!s.done) {
                if (s.turn.length) {
                    items.push("turn", ...s.turn);
                }
                const finish = checkout(s.remaining[s.player], 3 - s.turn.length);
                if (finish) {
                    items.push("checkout", ...finish);
                }
            }
        } else if (!s.done) {
            if (this.sport === "TENNIS") {
                const kind = this.tennisKind(s);
                if (kind === "super") {
                    items.push("[" + pair(s.points) + "]");
                } else {
                    items.push(pair(s.games));
                    if (kind === "tie") {
                        items.push(pair(s.points));
                    } else if (this.options.DEUCE === "AD" && s.points.every(value => value >= 3)) {
                        items.push(s.points[0] === s.points[1] ? "40-40" : s.points[0] > s.points[1] ? "AD-40" : "40-AD");
                    } else {
                        items.push(s.points.map(value => ["0", "15", "30", "40"][value]).join("-"));
                    }
                }
            } else {
                items.push(pair(s.points));
                if (this.sport === "VOLLEYBALL") {
                    items.push("server", String(s.lineups[s.server][0]));
                }
            }
            for (let side = 0; side < 2; side++) {
                const situation = this.situation(side);
                if (situation) {
                    items.push("(" + situation + " " + this.names[side] + ")");
                }
            }
        }
        return this.id + ": " + names[0] + " vs " + names[1] + " " + items.join(" ");
    }

    stats() {
        const s = this.state;
        if (this.sport === "BOWLING") {
            const marks = s.marks.flat();
            const open = s.frames.filter(frame => frame.length >= 2 && frame[0] !== 10 && frame[0] + frame[1] < 10).length;
            return [this.id + " " + this.names[0] + ": strikes " + marks.filter(mark => mark === "X").length +
                " spares " + marks.filter(mark => mark === "/").length + " open " + open + " max " + this.maximum(s)];
        }
        return this.names.map((name, i) => {
            let result = this.id + " " + name + ": ";
            if (this.sport === "DARTS") {
                const stats = s.darts[i];
                const average = stats.darts ? Math.floor(stats.points * 300 / stats.darts) : 0;
                result += "darts " + stats.darts + " average " + Math.floor(average / 100) + "." +
                    String(average % 100).padStart(2, "0") + " busts " + stats.busts + " high " + stats.high +
                    " tons " + stats.tons + " 180s " + stats.maximums + " doubles " + stats.hits + "/" + stats.attempts;
            } else {
                const stats = s.rally[i];
                result += "points " + stats.points + " serve " + stats.serveWon + "/" + stats.served + " run " + stats.run;
                if (this.sport === "TENNIS") {
                    result += " holds " + stats.holds + "/" + stats.serviceGames + " breaks " + stats.breaks +
                        " break points " + stats.conversions + "/" + stats.opportunities;
                } else if (this.sport === "VOLLEYBALL") {
                    result += " subs " + s.subs[i] + " timeouts " + s.timeouts[i] + " lineup " + s.lineups[i].join(",");
                }
            }
            return result;
        });
    }

    result() {
        const s = this.state;
        if (!s.done) {
            fail("match not finished");
        }
        if (this.sport === "BOWLING") {
            return this.id + ": " + this.names[0] + " " + this.frameScores(s).reduce((sum, value) => sum + (value ?? 0), 0);
        }
        return this.id + ": " + this.names[s.winner] + " def. " + this.names[1 - s.winner] + " " +
            s.finished.map(record => this.scoreRecord(record, s.winner === 1)).join(" ");
    }
}

const matches = new Map();

function command(line) {
    const [name, ...args] = line.split(" ");
    if (name === "MATCH") {
        if (matches.has(args[0])) {
            fail("duplicate match");
        }
        const match = new Match(args);
        matches.set(match.id, match);
        return [];
    }
    if (name === "CHECKOUT") {
        const answer = checkout(Number(args[0]));
        return ["checkout " + args[0] + ": " + (answer ? answer.join(" ") : "none")];
    }
    if (name === "STANDINGS") {
        const totals = new Map();
        for (const match of matches.values()) {
            if (!match.state.done || match.sport === "BOWLING") {
                continue;
            }
            match.names.forEach((person, i) => {
                if (!totals.has(person)) {
                    totals.set(person, [0, 0]);
                }
                totals.get(person)[i === match.state.winner ? 0 : 1]++;
            });
        }
        const ordered = [...totals].sort((a, b) => b[1][0] - a[1][0] || a[1][1] - b[1][1] || lex(a[0], b[0]));
        return ["standings: " + (ordered.length ? ordered.map(([person, values]) => person + " " + pair(values)).join(", ") : "none")];
    }
    const match = matches.get(args[0]);
    if (!match) {
        fail("unknown match");
    }
    if (name === "UNDO") {
        const previous = match.history.pop();
        if (!previous) {
            fail("nothing to undo");
        }
        match.state = structuredClone(match.initialState);
        for (const event of match.history) {
            match.apply(event.name, event.args);
        }
        return [];
    }
    if (name === "SCORE") {
        return [match.score()];
    }
    if (name === "STATS") {
        return match.stats();
    }
    if (name === "RESULT") {
        return [match.result()];
    }
    match.event(name, args.slice(1));
    return [];
}

const lines = readFileSync(0, "utf8").split("\n");
const output = [];
for (let i = 1; i <= Number(lines[0]); i++) {
    try {
        output.push(...command(lines[i]));
    } catch (error) {
        if (!(error instanceof Invalid)) {
            throw error;
        }
        output.push("ERROR " + error.message);
    }
}
if (output.length) {
    process.stdout.write(output.join("\n") + "\n");
}
