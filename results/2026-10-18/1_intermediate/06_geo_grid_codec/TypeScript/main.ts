import { readFileSync } from "node:fs";

type Cell = { system: string; p: number; x: bigint; y: bigint; w: bigint; h: bigint };
type Fraction = { n: bigint; d: bigint };

class Invalid extends Error {}

function invalid(): never {
    throw new Invalid();
}

const sequences: Record<string, number[]> = {
    GEOHASH: [1, 2, 3, 4, 5, 6, 7, 8, 9], MAIDENHEAD: [2, 4, 6, 8],
    PLUSCODE: [2, 4, 6, 8, 10, 11], GARS: [5, 6, 7], GEOREF: [2, 4, 8, 10, 12],
    MESH: [4, 6, 8, 9, 10, 11]
};
const dimensions: Record<string, number[][]> = {
    MAIDENHEAD: [[18, 18], [180, 180], [4320, 4320], [43200, 43200]],
    PLUSCODE: [[18, 9], [360, 180], [7200, 3600], [144000, 72000], [2880000, 1440000], [11520000, 7200000]],
    GARS: [[720, 360], [1440, 720], [4320, 2160]],
    GEOREF: [[24, 12], [360, 180], [21600, 10800], [216000, 108000], [2160000, 1080000]],
    MESH: [[360, 270], [2880, 2160], [28800, 21600], [57600, 43200], [115200, 86400], [230400, 172800]]
};
const l24 = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const geohash = "0123456789bcdefghjkmnpqrstuvwxyz";
const plus = "23456789CFGHJMPQRVWX";
const maiden = ["ABCDEFGHIJKLMNOPQR", "0123456789", "abcdefghijklmnopqrstuvwx", "0123456789"];
const national = "ABCDEFGHJKLMNOPQRSTUVWXYZ";
const bands = "CDEFGHJKLMNPQRSTUVWX";
const mgrsColumns = ["ABCDEFGH", "JKLMNPQR", "STUVWXYZ"];
const mgrsRows = "ABCDEFGHJKLMNPQRSTUV";

function floor(a: bigint, b: bigint): bigint {
    const q = a / b;
    return a < 0n && a % b !== 0n ? q - 1n : q;
}

function mod(a: bigint, b: bigint): bigint {
    return (a % b + b) % b;
}

function integer(text: string, low: number, high: number): number {
    if (!/^-?[0-9]{1,9}$/.test(text)) {
        invalid();
    }
    const value = Number(text);
    if (value < low || value > high) {
        invalid();
    }
    return value;
}

function coordinate(text: string, latitude: boolean): bigint {
    if (!/^-?[0-9]{1,3}(?:\.[0-9]{1,6})?$/.test(text)) {
        invalid();
    }
    const negative = text.startsWith("-");
    const [whole, fraction = ""] = (negative ? text.slice(1) : text).split(".");
    let value = BigInt(whole) * 1000000n + BigInt(fraction.padEnd(6, "0"));
    if (negative) {
        value = -value;
    }
    if (latitude ? value < -90000000n || value > 90000000n : value < -180000000n || value >= 180000000n) {
        invalid();
    }
    return value;
}

function systemName(value: string): string {
    if (!Object.hasOwn(sequences, value)) {
        invalid();
    }
    return value;
}

function precision(system: string, text: string): number {
    const value = integer(text, 1, 12);
    if (!sequences[system].includes(value)) {
        invalid();
    }
    return value;
}

function grid(system: string, p: number, x: bigint = 0n, y: bigint = 0n): Cell {
    let w: bigint;
    let h: bigint;
    if (system === "GEOHASH") {
        w = 1n << BigInt(Math.floor((5 * p + 1) / 2));
        h = 1n << BigInt(Math.floor(5 * p / 2));
    } else {
        const size = dimensions[system][sequences[system].indexOf(p)];
        w = BigInt(size[0]);
        h = BigInt(size[1]);
    }
    return { system, p, x, y, w, h };
}

function digits(value: bigint, radices: number[]): number[] {
    const result = new Array<number>(radices.length);
    for (let i = radices.length - 1; i >= 0; i--) {
        result[i] = Number(value % BigInt(radices[i]));
        value /= BigInt(radices[i]);
    }
    return result;
}

function character(set: string, value: string): number {
    const index = set.indexOf(value);
    if (value.length !== 1 || index < 0) {
        invalid();
    }
    return index;
}

function encode(cell: Cell): string | null {
    let { x, y } = cell;
    const p = cell.p;
    if (cell.system === "GEOHASH") {
        const a = Math.floor((5 * p + 1) / 2);
        const b = Math.floor(5 * p / 2);
        const xs = x.toString(2).padStart(a, "0");
        const ys = y.toString(2).padStart(b, "0");
        let bits = "";
        for (let i = 0; i < 5 * p; i++) {
            bits += i % 2 === 0 ? xs[Math.floor(i / 2)] : ys[Math.floor(i / 2)];
        }
        let code = "";
        for (let i = 0; i < bits.length; i += 5) {
            code += geohash[parseInt(bits.slice(i, i + 5), 2)];
        }
        return code;
    }
    if (cell.system === "MAIDENHEAD") {
        const count = p / 2;
        const radices = [18, 10, 24, 10].slice(0, count);
        const xs = digits(x, radices);
        const ys = digits(y, radices);
        return xs.map((value, i) => maiden[i][value] + maiden[i][ys[i]]).join("");
    }
    if (cell.system === "PLUSCODE") {
        let tail = "";
        if (p === 11) {
            tail = plus[Number(4n * (y % 5n) + x % 4n)];
            x /= 4n;
            y /= 5n;
        }
        const count = Math.min(p, 10) / 2;
        const xs = digits(x, [18, ...new Array(count - 1).fill(20)]);
        const ys = digits(y, [9, ...new Array(count - 1).fill(20)]);
        const code = xs.map((value, i) => plus[ys[i]] + plus[value]).join("") + tail;
        return p >= 8 ? code.slice(0, 8) + "+" + code.slice(8) : code + "0".repeat(8 - p) + "+";
    }
    if (cell.system === "GARS") {
        let suffix = "";
        if (p === 7) {
            suffix = String(1n + x % 3n + 3n * (2n - y % 3n));
            x /= 3n;
            y /= 3n;
        }
        if (p >= 6) {
            suffix = String(1n + x % 2n + 2n * (1n - y % 2n)) + suffix;
            x /= 2n;
            y /= 2n;
        }
        return String(x + 1n).padStart(3, "0") + l24[Number(y / 24n)] + l24[Number(y % 24n)] + suffix;
    }
    if (cell.system === "GEOREF") {
        let tail = "";
        if (p >= 8) {
            const m = (p - 4) / 2;
            const radix = BigInt(6 * 10 ** (m - 1));
            tail = String(x % radix).padStart(m, "0") + String(y % radix).padStart(m, "0");
            x /= radix;
            y /= radix;
        }
        if (p === 2) {
            return l24[Number(x)] + l24[Number(y)];
        }
        return l24[Number(x / 15n)] + l24[Number(y / 15n)] + l24[Number(x % 15n)] + l24[Number(y % 15n)] + tail;
    }
    const index = sequences.MESH.indexOf(p);
    const scale = BigInt([1, 8, 80, 160, 320, 640][index]);
    const u = x - 280n * scale;
    const v = y - 135n * scale;
    if (u < 0n || u >= 80n * scale || v < 0n || v >= 100n * scale) {
        return null;
    }
    const xs = digits(u, [80, 8, 10, 2, 2, 2].slice(0, index + 1));
    const ys = digits(v, [100, 8, 10, 2, 2, 2].slice(0, index + 1));
    let code = String(ys[0]).padStart(2, "0") + String(xs[0]).padStart(2, "0");
    for (let i = 1; i < xs.length; i++) {
        code += i <= 2 ? String(ys[i]) + xs[i] : String(1 + xs[i] + 2 * ys[i]);
    }
    return code;
}

function decode(system: string, code: string): Cell {
    let p = code.length;
    let x = 0n;
    let y = 0n;
    if (system === "GEOHASH") {
        if (p < 1 || p > 9) {
            invalid();
        }
        const bits = code.split("").map(c => character(geohash, c).toString(2).padStart(5, "0")).join("");
        for (let i = 0; i < bits.length; i++) {
            if (i % 2 === 0) {
                x = 2n * x + BigInt(bits[i]);
            } else {
                y = 2n * y + BigInt(bits[i]);
            }
        }
    } else if (system === "MAIDENHEAD") {
        if (!sequences[system].includes(p)) {
            invalid();
        }
        for (let i = 0; i < p / 2; i++) {
            const radix = BigInt(maiden[i].length);
            x = x * radix + BigInt(character(maiden[i], code[2 * i]));
            y = y * radix + BigInt(character(maiden[i], code[2 * i + 1]));
        }
    } else if (system === "PLUSCODE") {
        const parts = code.split("+");
        if (parts.length !== 2 || parts[0].length !== 8) {
            invalid();
        }
        const zero = parts[0].indexOf("0");
        let raw = "";
        if (zero >= 0) {
            if (![2, 4, 6].includes(zero) || parts[0].slice(zero) !== "0".repeat(8 - zero) || parts[1] !== "") {
                invalid();
            }
            raw = parts[0].slice(0, zero);
        } else {
            if (![0, 2, 3].includes(parts[1].length)) {
                invalid();
            }
            raw = parts[0] + parts[1];
        }
        const values = raw.split("").map(c => character(plus, c));
        if (values[0] > 8 || values[1] > 17) {
            invalid();
        }
        p = values.length;
        for (let i = 0; i < Math.min(p, 10); i += 2) {
            y = y * BigInt(i === 0 ? 9 : 20) + BigInt(values[i]);
            x = x * BigInt(i === 0 ? 18 : 20) + BigInt(values[i + 1]);
        }
        if (p === 11) {
            x = 4n * x + BigInt(values[10] % 4);
            y = 5n * y + BigInt(Math.floor(values[10] / 4));
        }
    } else if (system === "GARS") {
        if (!/^[0-9]{3}[A-Z]{2}[1-4]?[1-9]?$/.test(code) || p < 5 || p > 7) {
            invalid();
        }
        const band = Number(code.slice(0, 3));
        if (band < 1 || band > 720) {
            invalid();
        }
        x = BigInt(band - 1);
        y = BigInt(24 * character(l24.slice(0, 15), code[3]) + character(l24, code[4]));
        if (p >= 6) {
            const q = Number(code[5]) - 1;
            if (q < 0 || q > 3) {
                invalid();
            }
            x = 2n * x + BigInt(q % 2);
            y = 2n * y + BigInt(1 - Math.floor(q / 2));
        }
        if (p === 7) {
            const k = Number(code[6]) - 1;
            x = 3n * x + BigInt(k % 3);
            y = 3n * y + BigInt(2 - Math.floor(k / 3));
        }
    } else if (system === "GEOREF") {
        if (!sequences[system].includes(p)) {
            invalid();
        }
        x = BigInt(character(l24, code[0]));
        y = BigInt(character(l24.slice(0, 12), code[1]));
        if (p >= 4) {
            x = 15n * x + BigInt(character(l24.slice(0, 15), code[2]));
            y = 15n * y + BigInt(character(l24.slice(0, 15), code[3]));
        }
        if (p >= 8) {
            const m = (p - 4) / 2;
            const tail = code.slice(4);
            if (!/^[0-9]+$/.test(tail)) {
                invalid();
            }
            const radix = 6 * 10 ** (m - 1);
            const e = Number(tail.slice(0, m));
            const n = Number(tail.slice(m));
            if (e >= radix || n >= radix) {
                invalid();
            }
            x = x * BigInt(radix) + BigInt(e);
            y = y * BigInt(radix) + BigInt(n);
        }
    } else {
        if (!sequences.MESH.includes(p) || !/^[0-9]+$/.test(code) || Number(code.slice(2, 4)) > 79) {
            invalid();
        }
        let u = BigInt(code.slice(2, 4));
        let v = BigInt(code.slice(0, 2));
        if (p >= 6) {
            if (Number(code[4]) > 7 || Number(code[5]) > 7) {
                invalid();
            }
            v = 8n * v + BigInt(code[4]);
            u = 8n * u + BigInt(code[5]);
        }
        if (p >= 8) {
            v = 10n * v + BigInt(code[6]);
            u = 10n * u + BigInt(code[7]);
        }
        for (let i = 8; i < p; i++) {
            const q = Number(code[i]) - 1;
            if (q < 0 || q > 3) {
                invalid();
            }
            u = 2n * u + BigInt(q % 2);
            v = 2n * v + BigInt(Math.floor(q / 2));
        }
        const scale = BigInt([1, 8, 80, 160, 320, 640][sequences.MESH.indexOf(p)]);
        x = 280n * scale + u;
        y = 135n * scale + v;
    }
    return grid(system, p, x, y);
}

function point(system: string, p: number, lat: bigint, lon: bigint): Cell {
    const cell = grid(system, p);
    cell.x = (lon + 180000000n) * cell.w / 360000000n;
    cell.y = (lat + 90000000n) * cell.h / 180000000n;
    if (cell.y === cell.h) {
        cell.y--;
    }
    return cell;
}

function ancestor(cell: Cell, p: number): Cell {
    const parent = grid(cell.system, p);
    parent.x = cell.x * parent.w / cell.w;
    parent.y = cell.y * parent.h / cell.h;
    return parent;
}

function key(cell: Cell): string {
    return cell.p + ":" + cell.x + ":" + cell.y;
}

function coordinateText(value: bigint): string {
    const magnitude = value < 0n ? -value : value;
    return (value < 0n ? "-" : "") + magnitude / 1000000n + "." + String(magnitude % 1000000n).padStart(6, "0");
}

function center(cell: Cell, latitude: boolean): Fraction {
    const divisor = latitude ? cell.h : cell.w;
    const index = latitude ? cell.y : cell.x;
    const span = latitude ? 180000000n : 360000000n;
    return { n: -span * divisor + span * (2n * index + 1n), d: 2n * divisor };
}

function comparison(a: Fraction, b: Fraction): number {
    const difference = a.n * b.d - b.n * a.d;
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
}

function relate(a: Cell, b: Cell): string {
    const aw = { n: a.x, d: a.w };
    const ae = { n: a.x + 1n, d: a.w };
    const as = { n: a.y, d: a.h };
    const an = { n: a.y + 1n, d: a.h };
    const bw = { n: b.x, d: b.w };
    const be = { n: b.x + 1n, d: b.w };
    const bs = { n: b.y, d: b.h };
    const bn = { n: b.y + 1n, d: b.h };
    const inside = comparison(aw, bw) >= 0 && comparison(ae, be) <= 0 && comparison(as, bs) >= 0 && comparison(an, bn) <= 0;
    const contains = comparison(bw, aw) >= 0 && comparison(be, ae) <= 0 && comparison(bs, as) >= 0 && comparison(bn, an) <= 0;
    if (inside && contains) {
        return "EQUAL";
    }
    if (inside) {
        return "INSIDE";
    }
    if (contains) {
        return "CONTAINS";
    }
    const x = comparison(aw, be) < 0 && comparison(bw, ae) < 0;
    const y = comparison(as, bn) < 0 && comparison(bs, an) < 0;
    if (x && y) {
        return "OVERLAP";
    }
    const yTouch = comparison(as, bn) <= 0 && comparison(bs, an) <= 0;
    const xTouch = comparison(aw, be) <= 0 && comparison(bw, ae) <= 0;
    const wrapped = a.x + 1n === a.w && b.x === 0n || b.x + 1n === b.w && a.x === 0n;
    return yTouch && (xTouch || wrapped) ? "TOUCH" : "DISJOINT";
}

function compact(cells: Cell[]): string {
    const system = cells[0].system;
    const sequence = sequences[system];
    const selected = new Map<string, Cell>();
    cells.sort((a, b) => sequence.indexOf(a.p) - sequence.indexOf(b.p));
    for (const cell of cells) {
        const index = sequence.indexOf(cell.p);
        if (!sequence.slice(0, index).some(p => selected.has(key(ancestor(cell, p))))) {
            selected.set(key(cell), cell);
        }
    }
    while (true) {
        let merged = false;
        for (const cell of selected.values()) {
            const index = sequence.indexOf(cell.p);
            if (!index) {
                continue;
            }
            const parent = ancestor(cell, sequence[index - 1]);
            const rx = cell.w / parent.w;
            const ry = cell.h / parent.h;
            if (rx * ry > BigInt(selected.size)) {
                continue;
            }
            const children: Cell[] = [];
            for (let j = 0n; j < ry; j++) {
                for (let i = 0n; i < rx; i++) {
                    children.push(grid(system, cell.p, parent.x * rx + i, parent.y * ry + j));
                }
            }
            if (children.every(child => selected.has(key(child)))) {
                for (const child of children) {
                    selected.delete(key(child));
                }
                selected.set(key(parent), parent);
                merged = true;
                break;
            }
        }
        if (!merged) {
            break;
        }
    }
    const sorted = [...selected.values()].sort((a, b) =>
        sequence.indexOf(a.p) - sequence.indexOf(b.p) || (a.y === b.y ? 0 : a.y > b.y ? -1 : 1) ||
        (a.x === b.x ? 0 : a.x < b.x ? -1 : 1));
    return sorted.map(cell => encode(cell)!).join(" ");
}

function offsets(a: Cell, b: Cell): bigint[] {
    let dx = mod(b.x - a.x, a.w);
    if (2n * dx > a.w) {
        dx -= a.w;
    }
    return [dx, b.y - a.y];
}

function numericDigits(args: string[], offset: number): bigint[] {
    if (args.length === offset) {
        return [0n, 0n, 100000n];
    }
    const a = args[offset];
    const b = args[offset + 1];
    if (!/^[0-9]{1,5}$/.test(a) || !/^[0-9]{1,5}$/.test(b) || a.length !== b.length) {
        invalid();
    }
    const size = 10n ** BigInt(5 - a.length);
    return [BigInt(a) * size, BigInt(b) * size, size];
}

const arities: Record<string, number[]> = {
    ENCODE: [4], DECODE: [2], NEIGHBORS: [2], PARENT: [2], CHILDREN: [2], COMMON: [3],
    CONTAINS: [4], COVER: [6], CONVERT: [5], STEPS: [3], PATH: [3], RELATE: [4], SIZE: [2],
    SHORTEN: [3], RECOVER: [3], UTMZONE: [2], OSGB: [3], UNOSGB: [1, 3], MGRS: [5],
    UNMGRS: [2, 4], QUADKEY: [3], UNQUADKEY: [1]
};

function command(line: string): string {
    const [name, ...args] = line.split(" ");
    if (name === "COMPACT") {
        if (args.length < 2 || args.length > 101) {
            invalid();
        }
        const system = systemName(args[0]);
        return compact(args.slice(1).map(code => decode(system, code)));
    }
    if (!Object.hasOwn(arities, name) || !arities[name].includes(args.length)) {
        invalid();
    }
    if (name === "ENCODE" || name === "SIZE" || name === "COVER") {
        const system = systemName(args[0]);
        if (name === "ENCODE") {
            const lat = coordinate(args[1], true);
            const lon = coordinate(args[2], false);
            return encode(point(system, precision(system, args[3]), lat, lon)) ?? "OUT OF AREA";
        }
        const p = precision(system, args[1]);
        const cell = grid(system, p);
        if (name === "SIZE") {
            const scale = BigInt([1, 8, 80, 160, 320, 640][sequences.MESH.indexOf(p)] ?? 0);
            const count = system === "MESH" ? 8000n * scale * scale : cell.w * cell.h;
            return "w=" + coordinateText(360000000n / cell.w) + " h=" + coordinateText(180000000n / cell.h) + " cells=" + count;
        }
        const lat1 = coordinate(args[2], true);
        const lon1 = coordinate(args[3], false);
        const lat2 = coordinate(args[4], true);
        const lon2 = coordinate(args[5], false);
        if (lat1 > lat2) {
            invalid();
        }
        const a = point(system, p, lat1, lon1);
        const b = point(system, p, lat2, lon2);
        let columns = b.x - a.x + 1n;
        if (lon1 > lon2) {
            columns += cell.w;
            if (columns > cell.w) {
                columns = cell.w;
            }
        }
        if (columns * (b.y - a.y + 1n) > 100n) {
            return "TOO MANY";
        }
        const codes: string[] = [];
        for (let y = b.y; y >= a.y; y--) {
            for (let i = 0n; i < columns; i++) {
                codes.push(encode(grid(system, p, (a.x + i) % cell.w, y)) ?? "-");
            }
        }
        return codes.join(" ");
    }
    if (name === "SHORTEN" || name === "RECOVER") {
        const lat = coordinate(args[1], true);
        const lon = coordinate(args[2], false);
        if (name === "SHORTEN") {
            const cell = decode("PLUSCODE", args[0]);
            if (cell.p < 8) {
                invalid();
            }
            const cy = center(cell, true);
            const cx = center(cell, false);
            const dy = cy.n - lat * cy.d;
            const dx = cx.n - lon * cx.d;
            const close = (distance: bigint): boolean =>
                (dy < 0n ? -dy : dy) < distance * cy.d && (dx < 0n ? -dx : dx) < distance * cx.d;
            return close(15000n) ? args[0].slice(6) : close(300000n) ? args[0].slice(4) : args[0];
        }
        const parts = args[0].split("+");
        if (parts.length !== 2 || ![2, 4].includes(parts[0].length) || ![0, 2, 3].includes(parts[1].length)) {
            invalid();
        }
        for (const c of parts.join("")) {
            character(plus, c);
        }
        const removed = 8 - parts[0].length;
        const prefix = encode(point("PLUSCODE", 10, lat, lon))!.slice(0, removed);
        const cell = decode("PLUSCODE", prefix + args[0]);
        const cy = center(cell, true);
        const cx = center(cell, false);
        const distance = removed === 4 ? 1000000n : 50000n;
        const my = distance * cell.h / 180000000n;
        const mx = distance * cell.w / 360000000n;
        if ((lat + distance / 2n) * cy.d < cy.n && cy.n - distance * cy.d >= -90000000n * cy.d) {
            cell.y -= my;
        } else if ((lat - distance / 2n) * cy.d > cy.n && cy.n + distance * cy.d <= 90000000n * cy.d) {
            cell.y += my;
        }
        if ((lon + distance / 2n) * cx.d < cx.n) {
            cell.x = mod(cell.x - mx, cell.w);
        } else if ((lon - distance / 2n) * cx.d > cx.n) {
            cell.x = mod(cell.x + mx, cell.w);
        }
        return encode(cell)!;
    }
    if (name === "RELATE") {
        return relate(decode(systemName(args[0]), args[1]), decode(systemName(args[2]), args[3]));
    }
    if (["DECODE", "NEIGHBORS", "PARENT", "CHILDREN", "COMMON", "CONTAINS", "CONVERT", "STEPS", "PATH"].includes(name)) {
        const system = systemName(args[0]);
        const cell = decode(system, args[1]);
        const sequence = sequences[system];
        const index = sequence.indexOf(cell.p);
        if (name === "DECODE") {
            const south = -90000000n + 180000000n * cell.y / cell.h;
            const west = -180000000n + 360000000n * cell.x / cell.w;
            const north = -90000000n + 180000000n * (cell.y + 1n) / cell.h;
            const east = -180000000n + 360000000n * (cell.x + 1n) / cell.w;
            const cy = center(cell, true);
            const cx = center(cell, false);
            return "sw=" + coordinateText(south) + "," + coordinateText(west) + " ne=" + coordinateText(north) + "," +
                coordinateText(east) + " c=" + coordinateText(floor(cy.n, cy.d)) + "," + coordinateText(floor(cx.n, cx.d));
        }
        if (name === "NEIGHBORS") {
            return [[0, 1], [1, 1], [1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1]].map(([dx, dy]) => {
                const y = cell.y + BigInt(dy);
                return y < 0n || y >= cell.h ? "-" : encode(grid(system, cell.p, mod(cell.x + BigInt(dx), cell.w), y)) ?? "-";
            }).join(" ");
        }
        if (name === "PARENT") {
            return index ? encode(ancestor(cell, sequence[index - 1]))! : "NONE";
        }
        if (name === "CHILDREN") {
            if (index === sequence.length - 1) {
                return "NONE";
            }
            const child = grid(system, sequence[index + 1]);
            const rx = child.w / cell.w;
            const ry = child.h / cell.h;
            if (rx * ry > 100n) {
                return "TOO MANY";
            }
            const codes: string[] = [];
            for (let j = ry - 1n; j >= 0n; j--) {
                for (let i = 0n; i < rx; i++) {
                    codes.push(encode(grid(system, child.p, rx * cell.x + i, ry * cell.y + j)) ?? "-");
                }
            }
            return codes.join(" ");
        }
        if (name === "CONTAINS") {
            const lat = coordinate(args[2], true);
            const lon = coordinate(args[3], false);
            return key(cell) === key(point(system, cell.p, lat, lon)) ? "YES" : "NO";
        }
        if (name === "CONVERT") {
            if (args[2] !== "TO") {
                invalid();
            }
            const target = systemName(args[3]);
            const converted = grid(target, precision(target, args[4]));
            converted.x = (2n * cell.x + 1n) * converted.w / (2n * cell.w);
            converted.y = (2n * cell.y + 1n) * converted.h / (2n * cell.h);
            return encode(converted) ?? "OUT OF AREA";
        }
        const other = decode(system, args[2]);
        if (name === "COMMON") {
            const last = Math.min(index, sequence.indexOf(other.p));
            for (let i = last; i >= 0; i--) {
                const a = ancestor(cell, sequence[i]);
                const b = ancestor(other, sequence[i]);
                if (key(a) === key(b)) {
                    return encode(a)!;
                }
            }
            return "NONE";
        }
        if (cell.p !== other.p) {
            return "MISMATCH";
        }
        const [dx, dy] = offsets(cell, other);
        if (name === "STEPS") {
            return "dx=" + dx + " dy=" + dy;
        }
        const ax = dx < 0n ? -dx : dx;
        const ay = dy < 0n ? -dy : dy;
        const n = ax > ay ? ax : ay;
        if (n + 1n > 100n) {
            return "TOO MANY";
        }
        if (!n) {
            return encode(cell)!;
        }
        const codes: string[] = [];
        for (let i = 0n; i <= n; i++) {
            const x = mod(cell.x + floor(2n * i * dx + n, 2n * n), cell.w);
            const y = cell.y + floor(2n * i * dy + n, 2n * n);
            codes.push(encode(grid(system, cell.p, x, y)) ?? "-");
        }
        return codes.join(" ");
    }
    return otherCommand(name, args);
}

function otherCommand(name: string, args: string[]): string {
    if (name === "UTMZONE") {
        const lat = coordinate(args[0], true);
        const lon = coordinate(args[1], false);
        if (lat < -80000000n || lat >= 84000000n) {
            return "NONE";
        }
        const index = Number((lat + 80000000n) / 8000000n);
        const band = bands[Math.min(index, 19)];
        let zone = (lon + 180000000n) / 6000000n + 1n;
        if (band === "V" && lon >= 3000000n && lon < 12000000n) {
            zone = 32n;
        }
        if (band === "X" && lon >= 0n && lon < 42000000n) {
            zone = lon < 9000000n ? 31n : lon < 21000000n ? 33n : lon < 33000000n ? 35n : 37n;
        }
        return zone + band;
    }
    if (name === "QUADKEY") {
        const z = integer(args[2], 1, 23);
        const x = BigInt(integer(args[0], 0, 2 ** z - 1));
        const y = BigInt(integer(args[1], 0, 2 ** z - 1));
        let code = "";
        for (let i = z - 1; i >= 0; i--) {
            code += String((x >> BigInt(i) & 1n) + 2n * (y >> BigInt(i) & 1n));
        }
        return code;
    }
    if (name === "UNQUADKEY") {
        if (!/^[0-3]{1,23}$/.test(args[0])) {
            invalid();
        }
        let x = 0n;
        let y = 0n;
        for (const c of args[0]) {
            x = 2n * x + BigInt(Number(c) % 2);
            y = 2n * y + BigInt(Math.floor(Number(c) / 2));
        }
        return "x=" + x + " y=" + y + " z=" + args[0].length;
    }
    if (name === "UNOSGB" || name === "UNMGRS") {
        let e: bigint;
        let n: bigint;
        let offset: number;
        if (name === "UNOSGB") {
            if (args[0].length !== 2) {
                invalid();
            }
            const first = character(national, args[0][0]);
            const second = character(national, args[0][1]);
            e = BigInt(500000 * (first % 5 - 2) + 100000 * (second % 5));
            n = BigInt(500000 * (3 - Math.floor(first / 5)) + 100000 * (4 - Math.floor(second / 5)));
            if (e < 0n || e >= 700000n || n < 0n || n >= 1300000n) {
                invalid();
            }
            offset = 1;
        } else {
            if (!/^[1-9][0-9]?[C-HJ-NP-X]$/.test(args[0]) || args[1].length !== 2) {
                invalid();
            }
            const zone = Number(args[0].slice(0, -1));
            if (zone > 60) {
                invalid();
            }
            character(bands, args[0].slice(-1));
            const col = character(mgrsColumns[(zone - 1) % 3], args[1][0]);
            const row = character(mgrsRows, args[1][1]);
            e = BigInt(100000 * (col + 1));
            n = 100000n * mod(BigInt(row - (zone % 2 === 0 ? 5 : 0)), 20n);
            offset = 2;
        }
        const [east, north, size] = numericDigits(args, offset);
        return (name === "UNMGRS" ? args[0] + " " : "") + "sw=" + (e + east) + "," + (n + north) + " size=" + size;
    }
    let e: number;
    let n: number;
    let d: number;
    let text: string;
    if (name === "OSGB") {
        e = integer(args[0], 0, 699999);
        n = integer(args[1], 0, 1299999);
        d = integer(args[2], 0, 5);
        text = national[5 * (3 - Math.floor(n / 500000)) + 2 + Math.floor(e / 500000)] +
            national[5 * (4 - Math.floor(n / 100000) % 5) + Math.floor(e / 100000) % 5];
    } else {
        const zone = integer(args[0], 1, 60);
        character(bands, args[1]);
        e = integer(args[2], 100000, 899999);
        n = integer(args[3], 0, 9999999);
        d = integer(args[4], 0, 5);
        text = zone + args[1] + " " + mgrsColumns[(zone - 1) % 3][Math.floor(e / 100000) - 1] +
            mgrsRows[(Math.floor(n / 100000) + (zone % 2 === 0 ? 5 : 0)) % 20];
    }
    if (d) {
        text += " " + String(e % 100000).padStart(5, "0").slice(0, d) + " " +
            String(n % 100000).padStart(5, "0").slice(0, d);
    }
    return text;
}

const lines = readFileSync(0, "utf8").split("\n");
const output: string[] = [];
for (let i = 1; i <= Number(lines[0]); i++) {
    try {
        output.push(command(lines[i]));
    } catch (error) {
        if (!(error instanceof Invalid)) {
            throw error;
        }
        output.push("INVALID");
    }
}
process.stdout.write(output.join("\n") + "\n");
