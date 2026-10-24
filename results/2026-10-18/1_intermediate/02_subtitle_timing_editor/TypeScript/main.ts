import { readFileSync } from "node:fs";

type Cue = { index: number; start: number; end: number; text: string[] };
type Token = { kind: string; text: string; digit: number };
type RecordEntry = { name: string; cues: Cue[] };

class Invalid extends Error {}

function bad(): never {
    throw new Invalid("bad arguments");
}

function floorRatio(a: bigint, b: bigint): bigint {
    if (b < 0n) {
        a = -a;
        b = -b;
    }
    const q = a / b;
    return a < 0n && a % b !== 0n ? q - 1n : q;
}

function rounded(a: bigint, b: bigint): number {
    if (b < 0n) {
        a = -a;
        b = -b;
    }
    return Number(floorRatio(2n * a + b, 2n * b));
}

function quotient(a: number, b: number): number {
    return Number(floorRatio(BigInt(a), BigInt(b)));
}

function pad(value: number, width: number): string {
    return String(value).padStart(width, "0");
}

function srt(time: number): string {
    return pad(quotient(time, 3600000), 2) + ":" + pad(quotient(time, 60000) % 60, 2) +
        ":" + pad(quotient(time, 1000) % 60, 2) + "," + pad(time % 1000, 3);
}

function ass(time: number): string {
    const c = quotient(time + 5, 10);
    return quotient(c, 360000) + ":" + pad(quotient(c, 6000) % 60, 2) +
        ":" + pad(quotient(c, 100) % 60, 2) + "." + pad(c % 100, 2);
}

function decimal(value: number): string {
    return quotient(value, 100) + "." + pad(value % 100, 2);
}

function parseTime(value: string): number {
    if (!/^\d{2}:[0-5]\d:[0-5]\d,\d{3}$/.test(value)) {
        bad();
    }
    return Number(value.slice(0, 2)) * 3600000 + Number(value.slice(3, 5)) * 60000 +
        Number(value.slice(6, 8)) * 1000 + Number(value.slice(9));
}

function integer(value: string, minimum: number = 0, maximum: number = 999999999): number {
    if (!/^\d{1,9}$/.test(value)) {
        bad();
    }
    const result = Number(value);
    if (result < minimum || result > maximum) {
        bad();
    }
    return result;
}

function signed(value: string): number {
    if (!/^-?\d{1,9}$/.test(value)) {
        bad();
    }
    return Number(value);
}

function fps(value: string): number[] {
    const parts = value.split("/");
    if (parts.length > 2) {
        bad();
    }
    return [integer(parts[0], 1, 100000), parts.length === 2 ? integer(parts[1], 1, 100000) : 1];
}

function textLines(value: string): string[] {
    const parts = value.split("|");
    if (parts.some(part => part.length === 0)) {
        bad();
    }
    return parts;
}

function chars(cue: Cue): number {
    return cue.text.reduce((sum, line) => sum + line.length, 0);
}

function dialogue(cue: Cue): boolean {
    return cue.text.some(line => line.startsWith("- "));
}

function words(lines: string[]): string[] {
    return lines.join(" ").split(" ").filter(Boolean);
}

function wrap(lines: string[], width: number): string[] {
    const result: string[] = [];
    for (const word of words(lines)) {
        if (result.length && result[result.length - 1].length + 1 + word.length <= width) {
            result[result.length - 1] += " " + word;
        } else {
            result.push(word);
        }
    }
    return result;
}

function markup(line: string): Token[] {
    const result: Token[] = [];
    const formats = ["<i>", "</i>", "<b>", "</b>", "<u>", "</u>"];
    let p = 0;
    while (p < line.length) {
        const format = formats.find(tag => line.startsWith(tag, p));
        if (format) {
            result.push({ kind: "format", text: format, digit: 0 });
            p += format.length;
            continue;
        }
        let font = "";
        if (line.startsWith("</font>", p)) {
            font = "</font>";
        } else if (line.startsWith("<font", p) && [" ", ">"].includes(line[p + 5])) {
            const end = line.indexOf(">", p + 5);
            if (end >= 0) {
                font = line.slice(p, end + 1);
            }
        }
        if (font) {
            result.push({ kind: "font", text: font, digit: 0 });
            p += font.length;
            continue;
        }
        const position = /^\{\\an([1-9])\}/.exec(line.slice(p));
        if (position) {
            result.push({ kind: "position", text: position[0], digit: Number(position[1]) });
            p += position[0].length;
        } else {
            result.push({ kind: "char", text: line[p], digit: 0 });
            p++;
        }
    }
    return result;
}

function listing(cue: Cue, position: number): string {
    return position + " " + cue.index + " " + srt(cue.start) + " " + srt(cue.end) + " " + cue.text.join("|");
}

const arities: Record<string, number[]> = {
    LIST: [0], VALIDATE: [0], SEARCH: [1], AT: [1], GAPS: [1], STATS: [0],
    PRINT: [0], TOVTT: [0], TOASS: [0], FRAMES: [1], SHIFT: [1], SHIFTFROM: [2],
    SCALE: [2], SYNC: [4], SNAP: [1], FIXOVERLAP: [1], EXTEND: [1], TIME: [3],
    SORT: [0], RENUMBER: [0], MERGE: [1], SPLIT: [1], INSERT: [4], DELETE: [1, 2],
    TEXT: [2], BALANCE: [0], STRIP: [0], CLEANHI: [0], REPLACE: [1], UNDO: [0]
};
const modifying = new Set([
    "SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP", "FIXOVERLAP", "EXTEND", "TIME",
    "SORT", "RENUMBER", "MERGE", "SPLIT", "INSERT", "DELETE", "TEXT", "BALANCE",
    "STRIP", "CLEANHI", "REPLACE"
]);

class Editor {
    cues: Cue[] = [];
    history: RecordEntry[] = [];

    load(lines: string[]): string[] {
        const blocks: string[][] = [];
        let current: string[] = [];
        for (const line of [...lines, ""]) {
            if (line) {
                current.push(line);
            } else if (current.length) {
                blocks.push(current);
                current = [];
            }
        }
        const output: string[] = [];
        for (let i = 0; i < blocks.length; i++) {
            const block = blocks[i];
            let reason = "";
            let start = 0;
            let end = 0;
            if (!/^\d{1,6}$/.test(block[0])) {
                reason = "index";
            } else if (block.length < 2 || !/^\d{2}:[0-5]\d:[0-5]\d,\d{3} --> \d{2}:[0-5]\d:[0-5]\d,\d{3}$/.test(block[1])) {
                reason = "time";
            } else {
                start = parseTime(block[1].slice(0, 12));
                end = parseTime(block[1].slice(17));
                if (block.length < 3) {
                    reason = "no text";
                }
            }
            if (reason) {
                output.push("BAD CUE " + (i + 1) + ": " + reason);
            } else {
                this.cues.push({ index: Number(block[0]), start, end, text: block.slice(2) });
            }
        }
        output.push("LOAD cues=" + this.cues.length + " bad=" + (blocks.length - this.cues.length));
        return output;
    }

    execute(line: string): string[] {
        const name = line.split(" ", 1)[0];
        if (!Object.hasOwn(arities, name)) {
            throw new Invalid("unknown command");
        }
        const fixed: Record<string, number> = { SEARCH: 0, INSERT: 3, TEXT: 1, REPLACE: 0 };
        let args: string[];
        if (Object.hasOwn(fixed, name)) {
            args = [];
            let p = name.length + 1;
            if (line.length <= name.length) {
                bad();
            }
            for (let i = 0; i < fixed[name]; i++) {
                const next = line.indexOf(" ", p);
                if (next < 0) {
                    bad();
                }
                args.push(line.slice(p, next));
                p = next + 1;
            }
            args.push(line.slice(p));
        } else {
            args = line.split(" ").slice(1);
        }
        if (!arities[name].includes(args.length)) {
            bad();
        }
        const values: number[] = [];
        let texts: string[] = [];
        let rate = [1, 1];
        let old = "";
        let replacement = "";
        const positions: number[] = [];
        const position = (value: string): number => {
            const p = integer(value, 1);
            positions.push(p);
            return p;
        };
        switch (name) {
            case "AT":
                values.push(parseTime(args[0]));
                break;
            case "GAPS": case "FIXOVERLAP": case "MERGE":
                values.push(integer(args[0], 0, 60000));
                break;
            case "EXTEND":
                values.push(integer(args[0], 1, 60000));
                break;
            case "SPLIT":
                values.push(integer(args[0], 10, 80));
                break;
            case "SHIFT":
                values.push(signed(args[0]));
                break;
            case "SHIFTFROM":
                values.push(position(args[0]), signed(args[1]));
                break;
            case "SCALE":
                values.push(integer(args[0], 1, 100000), integer(args[1], 1, 100000));
                break;
            case "SYNC":
                values.push(position(args[0]), parseTime(args[1]), position(args[2]), parseTime(args[3]));
                break;
            case "TIME": case "INSERT":
                values.push(position(args[0]), parseTime(args[1]), parseTime(args[2]));
                if (name === "INSERT") {
                    texts = textLines(args[3]);
                }
                break;
            case "DELETE":
                values.push(...args.map(position));
                if (values.length === 2 && values[1] < values[0]) {
                    bad();
                }
                break;
            case "TEXT":
                values.push(position(args[0]));
                texts = textLines(args[1]);
                break;
            case "FRAMES": case "SNAP":
                rate = fps(args[0]);
                break;
            case "REPLACE": {
                const parts = args[0].split("|");
                if (parts.length !== 2 || parts.some(part => !part)) {
                    bad();
                }
                [old, replacement] = parts;
                break;
            }
        }
        for (const p of positions) {
            if (p > this.cues.length + (name === "INSERT" ? 1 : 0)) {
                throw new Invalid("no cue " + p);
            }
        }
        if (name === "SYNC" && this.cues[values[0] - 1].start === this.cues[values[2] - 1].start) {
            throw new Invalid("sync points coincide");
        }
        if (name === "UNDO") {
            const record = this.history.pop();
            if (!record) {
                throw new Invalid("nothing to undo");
            }
            this.cues = record.cues;
            return ["UNDO command=" + record.name];
        }
        if (modifying.has(name)) {
            this.history.push({ name, cues: structuredClone(this.cues) });
        }
        return this.process(name, args, values, texts, rate, old, replacement);
    }

    process(name: string, args: string[], v: number[], texts: string[], rate: number[],
            old: string, replacement: string): string[] {
        const output: string[] = [];
        const n = this.cues.length;
        if (name === "LIST" || name === "AT") {
            this.cues.forEach((cue, i) => {
                if (name === "LIST" || (cue.start <= v[0] && v[0] < cue.end)) {
                    output.push(listing(cue, i + 1));
                }
            });
            if (name === "AT") {
                output.push("AT active=" + output.length);
            }
        } else if (name === "VALIDATE") {
            this.cues.forEach((cue, i) => {
                const p = i + 1;
                const prefix = "cue " + p + ": ";
                const d = cue.end - cue.start;
                if (cue.index !== p) {
                    output.push(prefix + "index " + cue.index + " (expected " + p + ")");
                }
                if (d <= 0) {
                    output.push(prefix + "end not after start");
                }
                if (i > 0 && cue.start < this.cues[i - 1].end) {
                    output.push(prefix + "overlaps previous by " + (this.cues[i - 1].end - cue.start) + " ms");
                }
                if (d >= 1 && d < 700) {
                    output.push(prefix + "too short (" + d + " ms)");
                } else if (d > 7000) {
                    output.push(prefix + "too long (" + d + " ms)");
                }
                cue.text.forEach((text, j) => {
                    if (text.length > 42) {
                        output.push(prefix + "line " + (j + 1) + " too long (" + text.length + " chars)");
                    }
                });
                if (cue.text.length >= 3) {
                    output.push(prefix + "too many lines (" + cue.text.length + ")");
                }
                const c = chars(cue);
                if (d >= 1 && c * 1000 > 21 * d) {
                    output.push(prefix + "too fast (" + decimal(quotient(c * 100000, d)) + " cps)");
                }
            });
            output.push("VALIDATE problems=" + output.length);
        } else if (name === "SEARCH") {
            this.cues.forEach((cue, i) => {
                const match = cue.text.find(text => text.includes(args[0]));
                if (match !== undefined) {
                    output.push((i + 1) + " " + srt(cue.start) + " " + match);
                }
            });
            output.push("SEARCH found=" + output.length);
        } else if (name === "GAPS") {
            for (let i = 0; i + 1 < n; i++) {
                const gap = this.cues[i + 1].start - this.cues[i].end;
                if (gap < v[0]) {
                    output.push((i + 1) + " " + (i + 2) + " " + gap);
                }
            }
            output.push("GAPS count=" + output.length);
        } else if (name === "STATS") {
            output.push("STATS cues=" + n);
            if (n) {
                const durations = this.cues.map(cue => Math.max(0, cue.end - cue.start));
                const total = durations.reduce((a, b) => a + b, 0);
                const c = this.cues.reduce((sum, cue, i) => sum + (durations[i] > 0 ? chars(cue) : 0), 0);
                output.push("duration total=" + srt(total) + " mean=" + srt(quotient(total, n)));
                output.push("speed " + (total ? decimal(quotient(c * 100000, total)) : "-"));
                const maximum = Math.max(...durations);
                output.push("longest cue=" + (durations.indexOf(maximum) + 1) + " duration=" + srt(maximum));
                if (n === 1) {
                    output.push("gap none");
                } else {
                    const gaps = this.cues.slice(1).map((cue, i) => cue.start - this.cues[i].end);
                    const maximumGap = Math.max(...gaps);
                    output.push("gap cue=" + (gaps.indexOf(maximumGap) + 1) + " ms=" + maximumGap);
                }
            }
        } else if (name === "PRINT") {
            for (const cue of this.cues) {
                output.push(String(cue.index), srt(cue.start) + " --> " + srt(cue.end), ...cue.text, "");
            }
        } else if (name === "TOVTT") {
            output.push("WEBVTT", "");
            const escapes: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;" };
            for (const cue of this.cues) {
                let digit = 0;
                const converted = cue.text.map(line => {
                    let result = "";
                    for (const token of markup(line)) {
                        if (token.kind === "position" && !digit) {
                            digit = token.digit;
                        }
                        if (token.kind === "format") {
                            result += token.text;
                        } else if (token.kind === "char") {
                            result += escapes[token.text] ?? token.text;
                        }
                    }
                    return result.trim();
                }).filter(Boolean);
                if (!converted.length) {
                    continue;
                }
                let settings = digit >= 7 ? " line:0" : digit >= 4 ? " line:50%" : "";
                if ([1, 4, 7].includes(digit)) {
                    settings += " align:start";
                } else if ([3, 6, 9].includes(digit)) {
                    settings += " align:end";
                }
                output.push(String(cue.index), srt(cue.start).replace(",", ".") + " --> " +
                    srt(cue.end).replace(",", ".") + settings, ...converted, "");
            }
        } else if (name === "TOASS") {
            output.push("[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text");
            const tags: Record<string, string> = {
                "<i>": "{\\i1}", "</i>": "{\\i0}", "<b>": "{\\b1}", "</b>": "{\\b0}",
                "<u>": "{\\u1}", "</u>": "{\\u0}"
            };
            for (const cue of this.cues) {
                const converted = cue.text.map(line => markup(line).map(token =>
                    token.kind === "format" ? tags[token.text] : token.kind === "font" ? "" : token.text).join(""));
                output.push("Dialogue: 0," + ass(cue.start) + "," + ass(cue.end) + ",Default,,0,0,0,," + converted.join("\\N"));
            }
        } else if (name === "FRAMES") {
            this.cues.forEach((cue, i) => {
                const frames = [cue.start, cue.end].map(t =>
                    floorRatio(BigInt(t) * BigInt(rate[0]), 1000n * BigInt(rate[1])));
                output.push((i + 1) + " " + frames[0] + " " + frames[1]);
            });
        } else if (["SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP"].includes(name)) {
            let clamped = 0;
            let changed = 0;
            const first = name === "SHIFTFROM" ? v[0] - 1 : 0;
            const shift = name === "SHIFTFROM" ? v[1] : v[0];
            const s1 = name === "SYNC" ? this.cues[v[0] - 1].start : 0;
            const s2 = name === "SYNC" ? this.cues[v[2] - 1].start : 0;
            for (let i = first; i < n; i++) {
                const cue = this.cues[i];
                let wasClamped = false;
                for (const key of ["start", "end"] as const) {
                    const t = cue[key];
                    let result = t;
                    if (name === "SHIFT" || name === "SHIFTFROM") {
                        result = t + shift;
                    } else if (name === "SCALE") {
                        result = rounded(BigInt(t) * BigInt(v[0]), BigInt(v[1]));
                    } else if (name === "SYNC") {
                        const den = BigInt(s2 - s1);
                        const num = BigInt(v[1]) * den + BigInt(t - s1) * BigInt(v[3] - v[1]);
                        result = rounded(num, den);
                    } else {
                        const frame = rounded(BigInt(t) * BigInt(rate[0]), 1000n * BigInt(rate[1]));
                        result = rounded(BigInt(frame) * 1000n * BigInt(rate[1]), BigInt(rate[0]));
                    }
                    if (result < 0) {
                        wasClamped = true;
                        result = 0;
                    }
                    if (result !== t) {
                        changed++;
                    }
                    cue[key] = result;
                }
                if (wasClamped) {
                    clamped++;
                }
            }
            if (name === "SNAP") {
                output.push("SNAP changed=" + changed);
            } else if (name === "SCALE") {
                output.push("SCALE cues=" + n);
            } else {
                output.push(name + " cues=" + (n - first) + " clamped=" + clamped);
            }
        } else if (name === "FIXOVERLAP") {
            let fixed = 0;
            let failed = 0;
            for (let i = 0; i + 1 < n; i++) {
                const cue = this.cues[i];
                const limit = this.cues[i + 1].start - v[0];
                if (cue.end > limit) {
                    if (limit > cue.start) {
                        cue.end = limit;
                        fixed++;
                    } else {
                        failed++;
                        output.push("cue " + (i + 1) + ": cannot fix");
                    }
                }
            }
            output.push("FIXOVERLAP fixed=" + fixed + " failed=" + failed);
        } else if (name === "EXTEND") {
            let extended = 0;
            for (let i = 0; i < n; i++) {
                const cue = this.cues[i];
                if (cue.end - cue.start < v[0]) {
                    const candidate = Math.min(cue.start + v[0], this.cues[i + 1]?.start ?? Infinity);
                    if (candidate > cue.end) {
                        cue.end = candidate;
                        extended++;
                    }
                }
            }
            output.push("EXTEND extended=" + extended + " short=" + this.cues.filter(cue => cue.end - cue.start < v[0]).length);
        } else if (name === "TIME") {
            this.cues[v[0] - 1].start = v[1];
            this.cues[v[0] - 1].end = v[2];
            output.push("TIME cue=" + v[0]);
        } else if (name === "SORT") {
            const sorted = this.cues.map((cue, i) => ({ cue, i }));
            sorted.sort((a, b) => a.cue.start - b.cue.start || a.cue.end - b.cue.end || a.i - b.i);
            output.push("SORT moved=" + sorted.filter((entry, i) => entry.i !== i).length);
            this.cues = sorted.map(entry => entry.cue);
        } else if (name === "RENUMBER") {
            let changed = 0;
            this.cues.forEach((cue, i) => {
                if (cue.index !== i + 1) {
                    cue.index = i + 1;
                    changed++;
                }
            });
            output.push("RENUMBER changed=" + changed);
        } else if (name === "MERGE") {
            const merged: Cue[] = [];
            let joins = 0;
            for (const cue of this.cues) {
                const previous = merged[merged.length - 1];
                const lines = previous ? wrap([...previous.text, ...cue.text], 42) : [];
                if (previous && cue.start - previous.end < v[0] && !dialogue(previous) && !dialogue(cue) && lines.length <= 2) {
                    previous.end = Math.max(previous.end, cue.end);
                    previous.text = lines;
                    joins++;
                } else {
                    merged.push(cue);
                }
            }
            this.cues = merged;
            output.push("MERGE merged=" + joins + " cues=" + merged.length);
        } else if (name === "SPLIT") {
            const result: Cue[] = [];
            let split = 0;
            for (const cue of this.cues) {
                const duration = cue.end - cue.start;
                if (duration <= 0 || dialogue(cue)) {
                    result.push(cue);
                    continue;
                }
                const lines = wrap(cue.text, v[0]);
                if (lines.length <= 2) {
                    cue.text = lines;
                    result.push(cue);
                    continue;
                }
                split++;
                const parts: string[][] = [];
                for (let i = 0; i < lines.length; i += 2) {
                    parts.push(lines.slice(i, i + 2));
                }
                const counts = parts.map(part => part.reduce((sum, line) => sum + line.length, 0));
                const total = counts.reduce((a, b) => a + b, 0);
                const times = counts.map(c => quotient(duration * c, total));
                const order = counts.map((c, i) => ({ i, remainder: BigInt(duration) * BigInt(c) % BigInt(total) }));
                order.sort((a, b) => a.remainder === b.remainder ? a.i - b.i : a.remainder > b.remainder ? -1 : 1);
                const remaining = duration - times.reduce((a, b) => a + b, 0);
                for (let i = 0; i < remaining; i++) {
                    times[order[i].i]++;
                }
                let start = cue.start;
                parts.forEach((text, i) => {
                    result.push({ index: cue.index, start, end: start + times[i], text });
                    start += times[i];
                });
            }
            this.cues = result;
            output.push("SPLIT split=" + split + " cues=" + result.length);
        } else if (name === "INSERT") {
            this.cues.splice(v[0] - 1, 0, { index: v[0], start: v[1], end: v[2], text: texts });
            output.push("INSERT cue=" + v[0] + " cues=" + this.cues.length);
        } else if (name === "DELETE") {
            const count = (v[1] ?? v[0]) - v[0] + 1;
            this.cues.splice(v[0] - 1, count);
            output.push("DELETE removed=" + count + " cues=" + this.cues.length);
        } else if (name === "TEXT") {
            this.cues[v[0] - 1].text = texts;
            output.push("TEXT cue=" + v[0] + " lines=" + texts.length);
        } else if (name === "BALANCE") {
            let changed = 0;
            let skipped = 0;
            let dialogues = 0;
            for (const cue of this.cues) {
                if (dialogue(cue)) {
                    dialogues++;
                    continue;
                }
                const all = words(cue.text);
                const joined = all.join(" ");
                let best: string[] | undefined = joined.length <= 42 ? [joined] : undefined;
                if (!best) {
                    for (let j = 1; j < all.length; j++) {
                        const candidate = [all.slice(0, j).join(" "), all.slice(j).join(" ")];
                        if (candidate.some(line => line.length > 42)) {
                            continue;
                        }
                        if (!best || Math.abs(candidate[0].length - candidate[1].length) < Math.abs(best[0].length - best[1].length) ||
                            (Math.abs(candidate[0].length - candidate[1].length) === Math.abs(best[0].length - best[1].length) &&
                             candidate[0].length < best[0].length)) {
                            best = candidate;
                        }
                    }
                }
                if (!best) {
                    skipped++;
                } else if (JSON.stringify(best) !== JSON.stringify(cue.text)) {
                    cue.text = best;
                    changed++;
                }
            }
            output.push("BALANCE changed=" + changed + " skipped=" + skipped + " dialogue=" + dialogues);
        } else if (name === "STRIP" || name === "CLEANHI") {
            let tags = 0;
            let segments = 0;
            let labels = 0;
            let deletedLines = 0;
            const result: Cue[] = [];
            for (const cue of this.cues) {
                const lines: string[] = [];
                for (const original of cue.text) {
                    let line = "";
                    if (name === "STRIP") {
                        for (const token of markup(original)) {
                            if (token.kind === "char") {
                                line += token.text;
                            } else {
                                tags++;
                            }
                        }
                        line = line.trim();
                    } else {
                        line = original.replace(/\[.*?\]|\(.*?\)/g, () => {
                            segments++;
                            return "";
                        });
                        line = line.replace(/ +/g, " ").trim();
                        const prefix = line.startsWith("- ") ? "- " : "";
                        const body = line.slice(prefix.length);
                        const colon = body.indexOf(":");
                        if (colon >= 0 && /^[A-Z][A-Z0-9 ]*$/.test(body.slice(0, colon))) {
                            labels++;
                            line = (prefix + body.slice(colon + 1)).replace(/ +/g, " ").trim();
                        }
                    }
                    if (!line || (name === "CLEANHI" && line === "-")) {
                        deletedLines++;
                    } else {
                        lines.push(line);
                    }
                }
                if (lines.length) {
                    cue.text = lines;
                    result.push(cue);
                }
            }
            this.cues = result;
            const suffix = " removed_lines=" + deletedLines + " removed_cues=" + (n - result.length);
            output.push(name === "STRIP" ? "STRIP tags=" + tags + suffix :
                "CLEANHI segments=" + segments + " labels=" + labels + suffix);
        } else if (name === "REPLACE") {
            let count = 0;
            let changed = 0;
            for (const cue of this.cues) {
                let matches = 0;
                cue.text = cue.text.map(line => {
                    const parts = line.split(old);
                    matches += parts.length - 1;
                    return parts.join(replacement);
                });
                count += matches;
                if (matches) {
                    changed++;
                }
            }
            output.push("REPLACE count=" + count + " cues=" + changed);
        }
        return output;
    }
}

const lines = readFileSync(0, "utf8").split("\n");
const terminator = lines.indexOf("###");
const editor = new Editor();
const output = editor.load(lines.slice(0, terminator));
const count = Number(lines[terminator + 1]);
for (let i = 0; i < count; i++) {
    try {
        output.push(...editor.execute(lines[terminator + 2 + i]));
    } catch (error) {
        if (!(error instanceof Invalid)) {
            throw error;
        }
        output.push("ERROR " + error.message);
    }
}
process.stdout.write(output.join("\n") + "\n");
