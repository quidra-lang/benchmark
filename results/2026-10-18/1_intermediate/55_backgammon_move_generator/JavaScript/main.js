import { readFileSync, writeFileSync } from "node:fs";

const output = [];
const emit = (s) => {
    output.push(s);
};
const opposite = (c) => (c === "W" ? "B" : "W");
const clone = (x) => structuredClone(x);
const colors = ["W", "B"];
const empty = () => Array(26).fill(0);
function initial() {
    const position = { W: empty(), B: empty() };
    for (const c of colors)
        for (const [point, n] of [
            [24, 2],
            [13, 5],
            [8, 3],
            [6, 5],
        ])
            position[c][point] = n;
    return {
        position,
        side: "W",
        cube: 1,
        owner: "center",
        pending: false,
        over: false,
        score: { W: 0, B: 0 },
    };
}
const keyPosition = (p) => p.W.join(",") + "/" + p.B.join(",");
const pairOrder = (a, b) => b[0] - a[0] || b[1] - a[1];
function notation(pairs, hits) {
    let key = pairs.map((p) => [p[0], p[1]]).sort(pairOrder);
    while (true) {
        const a = key.findIndex(
            (p) => p[1] > 0 && !hits.includes(p[1]) && key.some((q) => q[0] === p[1]),
        );
        if (a < 0) break;
        const b = key.findIndex((p) => p[0] === key[a][1]);
        const pair = [key[a][0], key[b][1]];
        key = key
            .filter((_, i) => i !== a && i !== b)
            .concat([pair])
            .sort(pairOrder);
    }
    const elements = [],
        marked = [];
    for (let i = 0; i < key.length;) {
        const [s, t] = key[i];
        let j = i + 1;
        while (j < key.length && key[j][0] === s && key[j][1] === t) j++;
        const star = hits.includes(t) && !marked.includes(t);
        if (star) marked.push(t);
        elements.push(
            `${s === 25 ? "bar" : s}/${t === 0 ? "off" : t}${star ? "*" : ""}${j - i > 1 ? "(" + (j - i) + ")" : ""}`,
        );
        i = j;
    }
    return { key, notation: elements.length ? elements.join(" ") : "none" };
}
function canonical(a, b) {
    for (let i = 0; i < Math.min(a.key.length, b.key.length); i++) {
        const d = pairOrder(a.key[i], b.key[i]);
        if (d) return d;
    }
    return b.key.length - a.key.length;
}
function generate(position, side, d1, d2) {
    const possible = [];
    const opponent = opposite(side);
    function visit(p, dice, pairs, hits, used) {
        const n = notation(pairs, hits);
        possible.push({ position: p, pairs, hits, dice: used, key: n.key, notation: n.notation });
        for (let i = 0; i < dice.length; i++) {
            if (i && dice[i] === dice[i - 1]) continue;
            const d = dice[i],
                own = p[side],
                other = p[opponent];
            for (let s = own[25] ? 25 : 24; s >= (own[25] ? 25 : 1); s--) {
                if (!own[s]) continue;
                let t = s - d;
                if (t > 0) {
                    if (other[25 - t] >= 2) continue;
                } else {
                    if (own.slice(7, 26).some((n) => n > 0)) continue;
                    if (t < 0 && own.slice(s + 1, 7).some((n) => n > 0)) continue;
                    t = 0;
                }
                const next = clone(p),
                    hit = t > 0 && other[25 - t] === 1;
                next[side][s]--;
                next[side][t]++;
                if (hit) {
                    next[opponent][25 - t]--;
                    next[opponent][25]++;
                }
                visit(
                    next,
                    dice.filter((_, j) => i !== j),
                    pairs.concat([[s, t]]),
                    hit && !hits.includes(t) ? hits.concat(t) : hits,
                    used.concat(d),
                );
            }
        }
    }
    visit(
        clone(position),
        d1 === d2 ? [d1, d1, d1, d1] : [d1, d2].sort((a, b) => a - b),
        [],
        [],
        [],
    );
    let maximum = 0;
    for (const p of possible) maximum = Math.max(maximum, p.pairs.length);
    let candidates = possible.filter((p) => p.pairs.length === maximum);
    if (maximum === 1 && d1 !== d2 && candidates.some((p) => p.dice[0] === Math.max(d1, d2)))
        candidates = candidates.filter((p) => p.dice[0] === Math.max(d1, d2));
    const unique = new Map();
    for (const p of candidates)
        if (!unique.has(keyPosition(p.position))) unique.set(keyPosition(p.position), p);
    return { possible, legal: Array.from(unique.values()).sort(canonical), maximum };
}
const pips = (p, side) => p[side].reduce((n, count, point) => n + point * count, 0);
function evaluate(p, side) {
    const own = p[side],
        other = p[opposite(side)],
        P = pips(p, opposite(side)) - pips(p, side);
    let S = 0,
        H = 0,
        R = 0,
        A = 0,
        run = 0;
    for (let point = 1; point <= 24; point++) {
        if (own[point] >= 2) {
            run++;
            R = Math.max(R, run);
            if (point <= 6) H++;
            if (point >= 19) A++;
        } else run = 0;
        if (own[point] !== 1) continue;
        const distances = new Set();
        for (let q = 0; q < point; q++)
            if (other[q === 0 ? 25 : 25 - q] > 0) distances.add(point - q);
        for (let a = 1; a <= 6; a++)
            for (let b = 1; b <= 6; b++) {
                if (
                    distances.has(a) ||
                    distances.has(b) ||
                    distances.has(a + b) ||
                    (a === b && (distances.has(3 * a) || distances.has(4 * a)))
                )
                    S++;
            }
    }
    const G = other[25] - own[25];
    return [2 * P - S + 4 * H + 3 * R + 3 * A + 6 * G, P, S, H, R, A, G];
}
function ranked(plays, side) {
    return plays
        .map((play) => ({ play, evaluation: evaluate(play.position, side)[0] }))
        .sort((a, b) => b.evaluation - a.evaluation || canonical(a.play, b.play));
}
function contact(p) {
    let maxW = p.W[25] ? 25 : 0,
        minB = p.B[25] ? 0 : 25;
    for (let n = 1; n <= 24; n++) {
        if (p.W[n]) maxW = Math.max(maxW, n);
        if (p.B[n]) minB = Math.min(minB, 25 - n);
    }
    return maxW > minB;
}
const keith = (p, c) =>
    pips(p, c) +
    2 * Math.max(p[c][1] - 1, 0) +
    Math.max(p[c][2] - 1, 0) +
    Math.max(p[c][3] - 3, 0) +
    [4, 5, 6].filter((n) => p[c][n] === 0).length;
function cube(s, prohibited = false) {
    if (s.owner === opposite(s.side) || s.cube === 64 || prohibited) return "unavailable";
    if (contact(s.position)) {
        const e = evaluate(s.position, s.side)[0];
        return e < 60 ? "no double" : e <= 100 ? "double take" : "double drop";
    }
    const v = 8 * keith(s.position, s.side) - 7 * keith(s.position, opposite(s.side)),
        limit = s.owner === "center" ? 28 : 21;
    return v > limit ? "no double" : v >= 14 ? "double take" : "double drop";
}
function end(s, winner, kind) {
    const points = s.cube * (kind === "backgammon" ? 3 : kind === "gammon" ? 2 : 1);
    s.over = true;
    s.pending = false;
    s.score[winner] += points;
    return { winner, kind, points };
}
function move(s, p) {
    const c = s.side,
        other = opposite(c);
    s.position = clone(p.position);
    if (s.position[c][0] === 15) {
        const kind =
            s.position[other][0] > 0
                ? "single"
                : s.position[other][25] > 0 || s.position[other].slice(19, 25).some((n) => n > 0)
                  ? "backgammon"
                  : "gammon";
        return end(s, c, kind);
    }
    s.side = other;
    return undefined;
}
const resultLine = (r) => `result ${r.winner} ${r.kind} ${r.points}`;
let state = initial(),
    history = [],
    redo = [];
function apply(p, d1, d2) {
    const before = clone(state),
        record = `${state.side} ${d1}-${d2} ${p.notation}`,
        result = move(state, p);
    history.push({ record, before, after: clone(state) });
    redo = [];
    if (result) emit(resultLine(result));
}
function parsePlay(words) {
    if (words.length === 1 && words[0] === "none") return [];
    const pairs = [];
    for (const element of words) {
        const match = /^(.*?)(?:\(([234])\))?$/.exec(element);
        const points = match[1].split("/"),
            repeat = match[2] ? Number(match[2]) : 1;
        if (points.length < 2 || !/^(bar|[1-9]|1[0-9]|2[0-4])$/.test(points[0])) return undefined;
        const nums = [points[0] === "bar" ? 25 : Number(points[0])];
        for (let i = 1; i < points.length; i++) {
            if (!/^(off|(?:[1-9]|1[0-9]|2[0-4])\*?)$/.test(points[i])) return undefined;
            nums.push(points[i] === "off" ? 0 : Number(points[i].replace("*", "")));
            if (nums[i] >= nums[i - 1]) return undefined;
        }
        for (let i = 1; i < nums.length; i++)
            for (let k = 0; k < repeat; k++) pairs.push([nums[i - 1], nums[i]]);
    }
    return pairs;
}
function proposed(pairs) {
    const p = clone(state.position),
        own = p[state.side],
        other = p[opposite(state.side)];
    for (const [s, t] of pairs) {
        own[s]--;
        own[t]++;
    }
    for (const t of new Set(pairs.map((pair) => pair[1])))
        if (t > 0 && state.position[opposite(state.side)][25 - t] === 1) {
            other[25 - t]--;
            other[25]++;
        }
    return p;
}
function selfPlay(start, random, strategies, opening, report, prohibited) {
    const s = clone(start);
    let openingDice;
    if (opening) {
        let w = 0,
            b = 0;
        while (w === b) {
            w = (random() % 6) + 1;
            b = (random() % 6) + 1;
        }
        s.side = w > b ? "W" : "B";
        openingDice = [w, b];
    }
    const first = s.side;
    let t = 1,
        turns = 0;
    while (true) {
        const x = s.side,
            y = opposite(x);
        let dice;
        if (openingDice) {
            dice = openingDice;
            openingDice = undefined;
        } else {
            const decision = cube(s, prohibited(s));
            if (decision === "double take" || decision === "double drop") {
                if (report) {
                    emit(`${t} ${x} doubles ${s.cube * 2}`);
                    emit(`${t} ${y} ${decision === "double take" ? "takes" : "drops"}`);
                }
                if (decision === "double drop") {
                    const result = end(s, x, "drop");
                    if (report) emit(resultLine(result));
                    return { result, turns, first };
                }
                s.cube *= 2;
                s.owner = y;
            }
            dice = [(random() % 6) + 1, (random() % 6) + 1];
        }
        const legal = generate(s.position, x, dice[0], dice[1]).legal,
            strategy = strategies[x === "W" ? 0 : 1];
        const play =
            strategy === "FIRST"
                ? legal[0]
                : strategy === "RANDOM"
                  ? legal[random() % legal.length]
                  : ranked(legal, x)[0].play;
        if (report) emit(`${t} ${x} ${dice[0]}-${dice[1]} ${play.notation}`);
        turns++;
        const result = move(s, play);
        if (result) {
            if (report) emit(resultLine(result));
            return { result, turns, first };
        }
        t++;
    }
}
function execute(words) {
    const [cmd, ...a] = words,
        n = a.map(Number);
    const noArgs = [
        "NEW",
        "SHOW",
        "BOARD",
        "PIPS",
        "RACE",
        "EVAL",
        "SHOTS",
        "CUBE",
        "DOUBLE",
        "TAKE",
        "DROP",
        "SCORE",
        "HISTORY",
    ];
    const known = noArgs.concat([
        "POS",
        "MOVES",
        "PLAY",
        "AUTO",
        "HINT",
        "RESIGN",
        "UNDO",
        "REDO",
        "GAME",
        "MATCH",
        "STATS",
    ]);
    const error = (s) => emit("ERROR " + s);
    if (!known.includes(cmd)) {
        error("unknown command");
        return;
    }
    const inRange = (i, low, high) =>
        /^(0|[1-9][0-9]*)$/.test(a[i] ?? "") && n[i] >= low && n[i] <= high;
    if (cmd === "POS") {
        const points = (a[0] ?? "").split(",").map(Number),
            wb = n[1],
            bb = n[2];
        const white = points.reduce((s, p) => s + Math.max(p, 0), wb),
            black = points.reduce((s, p) => s + Math.max(-p, 0), bb);
        if (
            a.length !== 4 ||
            points.length !== 24 ||
            !inRange(1, 0, 15) ||
            !inRange(2, 0, 15) ||
            !["W", "B"].includes(a[3]) ||
            white < 1 ||
            white > 15 ||
            black < 1 ||
            black > 15
        ) {
            error("bad position");
            return;
        }
        const score = state.score;
        state = initial();
        state.score = score;
        state.position = { W: empty(), B: empty() };
        state.side = a[3];
        points.forEach((p, i) => {
            if (p > 0) state.position.W[i + 1] = p;
            if (p < 0) state.position.B[24 - i] = -p;
        });
        state.position.W[25] = wb;
        state.position.B[25] = bb;
        state.position.W[0] = 15 - white;
        state.position.B[0] = 15 - black;
        history = [];
        redo = [];
        emit("OK");
        return;
    }
    let valid = true;
    if (noArgs.includes(cmd)) valid = a.length === 0;
    if (["MOVES", "AUTO"].includes(cmd))
        valid = a.length === 2 && inRange(0, 1, 6) && inRange(1, 1, 6);
    if (cmd === "PLAY") valid = a.length >= 3 && inRange(0, 1, 6) && inRange(1, 1, 6);
    if (cmd === "HINT")
        valid = a.length === 3 && inRange(0, 1, 6) && inRange(1, 1, 6) && inRange(2, 1, 1000);
    if (cmd === "RESIGN")
        valid = a.length === 1 && ["single", "gammon", "backgammon"].includes(a[0]);
    if (["UNDO", "REDO"].includes(cmd)) valid = a.length === 1 && inRange(0, 1, 1000);
    if (cmd === "GAME")
        valid =
            a.length === 3 &&
            inRange(0, 1, 2147483646) &&
            a.slice(1).every((s) => ["BEST", "FIRST", "RANDOM"].includes(s));
    if (cmd === "MATCH") valid = a.length === 2 && inRange(0, 1, 15) && inRange(1, 1, 2147483646);
    if (cmd === "STATS") valid = a.length === 2 && inRange(0, 1, 50) && inRange(1, 1, 2147483646);
    if (!valid) {
        error("bad arguments");
        return;
    }
    const noOver = [
        "RACE",
        "MOVES",
        "PLAY",
        "AUTO",
        "HINT",
        "EVAL",
        "SHOTS",
        "CUBE",
        "DOUBLE",
        "TAKE",
        "DROP",
        "RESIGN",
        "GAME",
    ];
    const noPending = ["PLAY", "AUTO", "CUBE", "DOUBLE", "RESIGN", "GAME"];
    if (state.over && noOver.includes(cmd)) {
        error("game over");
        return;
    }
    if (state.pending && noPending.includes(cmd)) {
        error("double pending");
        return;
    }
    switch (cmd) {
        case "NEW": {
            const score = state.score;
            state = initial();
            state.score = score;
            history = [];
            redo = [];
            emit("OK");
            break;
        }
        case "SHOW":
            emit(
                "POS " +
                    Array.from(
                        { length: 24 },
                        (_, i) => state.position.W[i + 1] - state.position.B[24 - i],
                    ).join(",") +
                    ` ${state.position.W[25]} ${state.position.B[25]} ${state.side}`,
            );
            break;
        case "BOARD": {
            const top = Array.from({ length: 12 }, (_, i) => 13 + i),
                bottom = Array.from({ length: 12 }, (_, i) => 12 - i);
            const row = (fields) =>
                emit(
                    fields
                        .slice(0, 6)
                        .map((s) => s.padStart(3))
                        .join("") +
                        " |" +
                        fields
                            .slice(6)
                            .map((s) => s.padStart(3))
                            .join(""),
                );
            const cells = (points, r) =>
                points.map((p) => {
                    const w = state.position.W[p],
                        b = state.position.B[25 - p],
                        count = w || b;
                    return r === 5 && count > 5
                        ? String(count)
                        : count >= r
                          ? w
                              ? "W"
                              : "B"
                          : ".";
                });
            row(top.map(String));
            for (let r = 1; r <= 5; r++) row(cells(top, r));
            emit(
                `bar W${state.position.W[25]} B${state.position.B[25]} | off W${state.position.W[0]} B${state.position.B[0]} | cube ${state.cube} ${state.owner} | ${state.over ? "game over" : state.side + (state.pending ? " doubles" : " to move")}`,
            );
            for (let r = 5; r >= 1; r--) row(cells(bottom, r));
            row(bottom.map(String));
            break;
        }
        case "PIPS":
            emit(`pips W ${pips(state.position, "W")} B ${pips(state.position, "B")}`);
            break;
        case "RACE":
            emit(
                contact(state.position)
                    ? "contact"
                    : `race W ${keith(state.position, "W")} B ${keith(state.position, "B")}`,
            );
            break;
        case "MOVES": {
            const legal = generate(state.position, state.side, n[0], n[1]).legal;
            legal.forEach((p) => emit(p.notation));
            emit("total " + legal.length);
            break;
        }
        case "PLAY": {
            const pairs = parsePlay(a.slice(2));
            if (!pairs) {
                emit("ILLEGAL syntax");
                break;
            }
            const final = proposed(pairs),
                own = final[state.side],
                other = state.position[opposite(state.side)];
            if (own.some((x) => x < 0)) {
                emit("ILLEGAL no checker");
                break;
            }
            if (own[25] > 0 && pairs.some((p) => p[0] !== 25)) {
                emit("ILLEGAL bar");
                break;
            }
            if (pairs.some((p) => p[1] > 0 && other[25 - p[1]] >= 2)) {
                emit("ILLEGAL blocked");
                break;
            }
            if (pairs.some((p) => p[1] === 0) && own.slice(7, 26).some((x) => x > 0)) {
                emit("ILLEGAL bear-off");
                break;
            }
            const all = generate(state.position, state.side, n[0], n[1]),
                key = keyPosition(final),
                legal = all.legal.find((p) => keyPosition(p.position) === key);
            if (legal) {
                emit("OK " + legal.notation);
                apply(legal, n[0], n[1]);
            } else {
                const same = all.possible.filter((p) => keyPosition(p.position) === key);
                emit(
                    "ILLEGAL " +
                        (same.length
                            ? same.some((p) => p.pairs.length < all.maximum)
                                ? "too few dice"
                                : "larger die required"
                            : "impossible"),
                );
            }
            break;
        }
        case "AUTO":
        case "HINT": {
            const choices = ranked(
                generate(state.position, state.side, n[0], n[1]).legal,
                state.side,
            );
            if (cmd === "HINT")
                choices.slice(0, n[2]).forEach((p) => emit(p.evaluation + " " + p.play.notation));
            else {
                emit(`OK ${choices[0].play.notation} eval ${choices[0].evaluation}`);
                apply(choices[0].play, n[0], n[1]);
            }
            break;
        }
        case "EVAL": {
            const e = evaluate(state.position, state.side);
            emit(
                `eval ${e[0]} pips ${e[1]} blots ${e[2]} home ${e[3]} prime ${e[4]} anchors ${e[5]} bar ${e[6]}`,
            );
            break;
        }
        case "SHOTS": {
            const blots = [],
                weights = new Map(),
                rolls = [];
            for (let p = 24; p >= 1; p--)
                if (state.position[state.side][p] === 1) {
                    blots.push(p);
                    weights.set(p, 0);
                }
            let total = 0;
            for (let a = 6; a >= 1; a--)
                for (let b = a; b >= 1; b--) {
                    const plays = generate(state.position, opposite(state.side), a, b).legal;
                    const hits = blots.filter((p) =>
                            plays.some((play) => play.hits.includes(25 - p)),
                        ),
                        weight = a === b ? 1 : 2;
                    if (hits.length) {
                        total += weight;
                        rolls.push(`${a}-${b}`);
                    }
                    for (const p of hits) weights.set(p, weights.get(p) + weight);
                }
            emit(`shots ${total}/36${rolls.length ? " " + rolls.join(" ") : ""}`);
            blots.forEach((p) => emit(`blot ${p} ${weights.get(p)}/36`));
            break;
        }
        case "CUBE":
            emit("cube " + cube(state));
            break;
        case "DOUBLE":
            if (state.owner === opposite(state.side) || state.cube === 64)
                error("cube unavailable");
            else {
                state.pending = true;
                redo = [];
                emit("OK double " + state.cube * 2);
            }
            break;
        case "TAKE":
            if (!state.pending) error("no double");
            else {
                state.pending = false;
                state.cube *= 2;
                state.owner = opposite(state.side);
                redo = [];
                emit(`OK take ${state.cube} ${state.owner}`);
            }
            break;
        case "DROP":
            if (!state.pending) error("no double");
            else {
                const r = end(state, state.side, "drop");
                redo = [];
                emit("OK drop");
                emit(resultLine(r));
            }
            break;
        case "RESIGN": {
            const r = end(state, opposite(state.side), a[0]);
            redo = [];
            emit("OK resign");
            emit(resultLine(r));
            break;
        }
        case "SCORE":
            emit(`score W ${state.score.W} B ${state.score.B}`);
            break;
        case "HISTORY":
            emit("history " + history.length);
            history.forEach((e, i) => emit(`${i + 1} ${e.record}`));
            break;
        case "UNDO":
            if (n[0] > history.length) error("cannot undo");
            else {
                const entries = history.splice(history.length - n[0]);
                state = clone(entries[0].before);
                redo = entries.concat(redo);
                emit("OK");
            }
            break;
        case "REDO":
            if (n[0] > redo.length) error("cannot redo");
            else {
                const entries = redo.splice(0, n[0]);
                history = history.concat(entries);
                state = clone(entries[entries.length - 1].after);
                emit("OK");
            }
            break;
        case "GAME":
        case "MATCH":
        case "STATS": {
            let seed = cmd === "GAME" ? n[0] : n[1];
            const random = () => {
                seed = (48271 * seed) % 2147483647;
                return seed;
            };
            if (cmd === "GAME") {
                selfPlay(state, random, a.slice(1), false, true, () => false);
                break;
            }
            const scores = { W: 0, B: 0 },
                counts = new Map();
            for (const kind of ["single", "gammon", "backgammon", "drop"])
                counts.set(kind, { W: 0, B: 0 });
            let game = 0,
                turns = 0,
                crawfordUsed = false;
            while (cmd === "MATCH" ? scores.W < n[0] && scores.B < n[0] : game < n[0]) {
                game++;
                const crawford =
                    cmd === "MATCH" && !crawfordUsed && Math.max(scores.W, scores.B) === n[0] - 1;
                if (crawford) crawfordUsed = true;
                const played = selfPlay(
                    initial(),
                    random,
                    ["BEST", "BEST"],
                    true,
                    false,
                    (s) => cmd === "MATCH" && (crawford || scores[s.side] + s.cube >= n[0]),
                );
                const r = played.result;
                scores[r.winner] += r.points;
                counts.get(r.kind)[r.winner]++;
                turns += played.turns;
                if (cmd === "MATCH")
                    emit(
                        `game ${game}${crawford ? " crawford" : ""} start ${played.first} turns ${played.turns} ${resultLine(r)} score ${scores.W}-${scores.B}`,
                    );
            }
            if (cmd === "MATCH")
                emit(`match ${scores.W >= n[0] ? "W" : "B"} ${scores.W}-${scores.B}`);
            else {
                for (const [kind, c] of counts) emit(`${kind} W ${c.W} B ${c.B}`);
                emit(`points W ${scores.W} B ${scores.B}`);
                emit("turns " + turns);
            }
            break;
        }
    }
}
const lines = readFileSync(0, "utf8").trimEnd().split("\n");
for (let i = 1; i <= Number(lines[0]); i++) {
    execute(lines[i].trimEnd().split(" "));
    writeFileSync(1, output.join("\n") + "\n");
    output.length = 0;
}
