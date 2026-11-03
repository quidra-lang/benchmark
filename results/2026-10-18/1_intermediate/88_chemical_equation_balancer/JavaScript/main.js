const fs = require("fs");
const symbols =
    "H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe".split(
        " ",
    );
const weights = [
    1008, 4003, 6941, 9012, 10811, 12011, 14007, 15999, 18998, 20180, 22990, 24305, 26982, 28086,
    30974, 32065, 35453, 39948, 39098, 40078, 44956, 47867, 50942, 51996, 54938, 55845, 58933,
    58693, 63546, 65380, 69723, 72630, 74922, 78971, 79904, 83798, 85468, 87620, 88906, 91224,
    92906, 95950, 98000, 101070, 102906, 106420, 107868, 112414, 114818, 118710, 121760, 127600,
    126904, 131293,
];
const W = Object.fromEntries(symbols.map((s, i) => [s, weights[i]]));
const valence = {
    H: 1,
    F: 1,
    Cl: 1,
    Br: 1,
    I: 1,
    O: 2,
    S: 2,
    Se: 2,
    B: 3,
    N: 3,
    P: 3,
    As: 3,
    C: 4,
    Si: 4,
    Ge: 4,
};
const metals = { Li: 1, Na: 1, K: 1, Rb: 1, Be: 2, Mg: 2, Ca: 2, Sr: 2, Al: 3 };
const heats = new Map();
const gcd = (a, b) => {
    a = Math.abs(a);
    b = Math.abs(b);
    while (b) [a, b] = [b, a % b];
    return a;
};
const dec = (n, d) => `${Math.floor(n / 10 ** d)}.${String(n % 10 ** d).padStart(d, "0")}`;
const ent = (n) => (n < 0 ? "-" : "") + dec(Math.abs(n), 2);
const signed = (n) => (n > 0 ? "+" + n : String(n));
const fail = (s) => {
    throw new Error("error: " + s);
};
class Fraction {
    constructor(n, d = 1) {
        const g = gcd(n, d);
        this.n = (n / g) * (d < 0 ? -1 : 1);
        this.d = Math.abs(d) / g;
    }
    sub(b) {
        return new Fraction(this.n * b.d - b.n * this.d, this.d * b.d);
    }
    mul(b) {
        return new Fraction(this.n * b.n, this.d * b.d);
    }
    div(b) {
        return new Fraction(this.n * b.d, this.d * b.n);
    }
    neg() {
        return new Fraction(-this.n, this.d);
    }
    text() {
        return signed(this.n) + (this.d === 1 ? "" : "/" + this.d);
    }
}
const order = (c) => {
    const e = Object.keys(c).sort();
    return e.includes("C")
        ? ["C", ...(e.includes("H") ? ["H"] : []), ...e.filter((x) => x !== "C" && x !== "H")]
        : e;
};
const add = (a, b, k = 1) => {
    for (const e of Object.keys(b)) a[e] = (a[e] || 0) + b[e] * k;
    return a;
};
const scale = (c, k) => Object.fromEntries(Object.entries(c).map(([e, n]) => [e, n * k]));
const mass = (c) => Object.keys(c).reduce((s, e) => s + c[e] * W[e], 0);
const hill = (c, q = 0) =>
    order(c)
        .map((e) => e + (c[e] === 1 ? "" : c[e]))
        .join("") + (q ? "^" + (Math.abs(q) === 1 ? "" : Math.abs(q)) + (q > 0 ? "+" : "-") : "");
function formula(text, word = text) {
    let p = 0,
        seen = [];
    const number = () => {
        const start = p;
        while (/[0-9]/.test(text[p] || "!")) p++;
        if (p === start) return 1;
        if (text[start] === "0") throw 0;
        return Number(text.slice(start, p));
    };
    const sequence = () => {
        const result = {};
        let count = 0;
        while (p < text.length) {
            let item = {},
                ch = text[p];
            if (/[A-Z]/.test(ch)) {
                let e = text[p++];
                if (/[a-z]/.test(text[p] || "!")) e += text[p++];
                seen.push(e);
                item[e] = 1;
            } else if (ch === "(" || ch === "[") {
                p++;
                item = sequence();
                if (text[p++] !== (ch === "(" ? ")" : "]")) throw 0;
            } else break;
            add(result, item, number());
            count++;
        }
        if (!count) throw 0;
        return result;
    };
    let c,
        q = 0;
    try {
        c = sequence();
        while (text[p] === ".") {
            p++;
            const k = number();
            add(c, sequence(), k);
        }
        if (text[p] === "^") {
            p++;
            const k = number(),
                ch = text[p++];
            if (ch !== "+" && ch !== "-") throw 0;
            q = ch === "+" ? k : -k;
        }
        if (p !== text.length) throw 0;
    } catch {
        fail("invalid formula " + word);
    }
    for (const e of seen) if (!Object.hasOwn(W, e)) fail("unknown element " + e);
    return { c, q, m: mass(c) };
}
function species(word, coefficient = false) {
    const state = ["(s)", "(l)", "(g)", "(aq)"].find((s) => word.endsWith(s)) || "";
    let f = state ? word.slice(0, -state.length) : word,
        k = 1;
    if (coefficient && /^[0-9]/.test(f)) {
        const t = f.match(/^[0-9]+/)[0];
        if (t[0] === "0") fail("invalid formula " + word);
        k = Number(t);
        f = f.slice(t.length);
    }
    return { f, state, name: f + state, k, ...formula(f, word) };
}
function equation(a, check = false) {
    if (
        a.length % 2 === 0 ||
        a.filter((x, i) => i % 2 && x === "->").length !== 1 ||
        a.some((x, i) => (i % 2 ? !["+", "->"].includes(x) : ["+", "->"].includes(x)))
    )
        fail("malformed equation");
    const list = a.filter((_, i) => i % 2 === 0).map((x) => species(x, check)),
        r = (a.indexOf("->") + 1) / 2;
    return { list, r, sign: list.map((_, i) => (i < r ? 1 : -1)) };
}
function quantity(s) {
    if (!/^(0|[1-9][0-9]{0,3})(\.[0-9]{1,3})?$/.test(s)) fail("invalid quantity " + s);
    const [a, b = ""] = s.split("."),
        n = Number(a) * 1000 + Number(b.padEnd(3, "0"));
    if (!n) fail("invalid quantity " + s);
    return n;
}
function enthalpy(s) {
    if (!/^-?(0|[1-9][0-9]{0,4})(\.[0-9]{1,2})?$/.test(s)) fail("invalid enthalpy " + s);
    const [a, b = ""] = s.replace("-", "").split(".");
    return (s[0] === "-" ? -1 : 1) * (Number(a) * 100 + Number(b.padEnd(2, "0")));
}
function matrix(list, sign) {
    const all = {};
    for (const s of list) add(all, s.c);
    const labels = [...order(all), "charge"];
    return {
        labels,
        rows: labels.map((e) => list.map((s, i) => sign[i] * (e === "charge" ? s.q : s.c[e] || 0))),
    };
}
function nullspace(rows, n) {
    const a = rows.map((r) => r.map((x) => new Fraction(x))),
        piv = [],
        free = [];
    for (let j = 0; j < n; j++) {
        const r = piv.length,
            i = a.findIndex((row, k) => k >= r && row[j].n !== 0);
        if (i < 0) {
            free.push(j);
            continue;
        }
        [a[r], a[i]] = [a[i], a[r]];
        const t = a[r][j];
        a[r] = a[r].map((x) => x.div(t));
        for (let k = 0; k < a.length; k++)
            if (k !== r && a[k][j].n) {
                const f = a[k][j];
                a[k] = a[k].map((x, z) => x.sub(f.mul(a[r][z])));
            }
        piv.push(j);
    }
    const basis = free.map((f) => {
        const v = Array.from({ length: n }, () => new Fraction(0));
        v[f] = new Fraction(1);
        piv.forEach((j, i) => (v[j] = a[i][f].neg()));
        let l = 1;
        for (const x of v) l = (l / gcd(l, x.d)) * x.d;
        const b = v.map((x) => x.n * (l / x.d));
        const g = b.reduce(gcd, 0);
        return b.map((x) => x / g);
    });
    return { rank: piv.length, basis };
}
function coefficients(list, sign, k = list.length) {
    const { basis } = nullspace(matrix(list, sign).rows, list.length);
    if (basis.length > 1) throw new Error(`AMBIGUOUS (nullity ${basis.length})`);
    if (!basis.length) throw new Error("IMPOSSIBLE");
    const v = basis[0].map((x) => (basis[0][0] < 0 ? -x : x));
    if (v.slice(0, k).some((x) => x <= 0)) throw new Error("IMPOSSIBLE");
    return v;
}
const term = (s, k) => (k === 1 ? s : k + s);
const notation = (eq, v) =>
    eq.list
        .map((s, i) => term(s.name, v[i]))
        .slice(0, eq.r)
        .join(" + ") +
    " -> " +
    eq.list
        .map((s, i) => term(s.name, v[i]))
        .slice(eq.r)
        .join(" + ");
const gas = (s, n, d) =>
    s.state === "(g)" ? " " + dec(Math.floor((n * 22414) / d), 3) + " L" : "";
function ratios(a) {
    const es = order(a);
    let f = es[0];
    for (const e of es) if (a[e] * W[f] < a[f] * W[e]) f = e;
    const out = es.map((e) => e + " " + dec(Math.floor((1000 * a[e] * W[f]) / (W[e] * a[f])), 3));
    for (let k = 1; k <= 12; k++) {
        const c = {};
        let ok = true;
        for (const e of es) {
            const n = k * a[e] * W[f],
                d = W[e] * a[f],
                i = Math.floor((2 * n + d) / (2 * d));
            c[e] = i;
            if (20 * Math.abs(n - i * d) > d) ok = false;
        }
        if (ok) return [...out, hill(c) + ` (k = ${k})`];
    }
    return [...out, "no simple ratio"];
}
function group(f, k) {
    const core = f.split("^")[0];
    if (k === 1) return core;
    let depth = 0,
        end = -1;
    if (core[0] === "[")
        for (let i = 0; i < core.length; i++) {
            if (core[i] === "[") depth++;
            if (core[i] === "]" && --depth === 0) {
                end = i;
                break;
            }
        }
    return (/^[A-Z][a-z]?$/.test(core) || end === core.length - 1 ? core : "(" + core + ")") + k;
}
function execute(line) {
    const [cmd, ...a] = line.split(" "),
        count = a.length;
    const counts = {
        ELEMENT: 1,
        PARSE: 1,
        MASS: 1,
        PERCENT: 1,
        EMPIRICAL: 1,
        DBE: 1,
        OXSTATE: 1,
        MOLES: 2,
        GRAMS: 2,
        MOLECULAR: 2,
        SALT: 2,
        HEAT: 2,
        COMBUST: 3,
        HEATS: 0,
        DERIVE: -2,
        BALANCE: -1,
        MATRIX: -1,
        CHECK: -1,
        DELTAH: -1,
        REDOX: -3,
        HALF: -3,
        STOICH: -4,
        LIMITING: -4,
        YIELD: -4,
    };
    if (!Object.hasOwn(counts, cmd)) fail("unknown command " + cmd);
    const expect = counts[cmd];
    if (
        (expect >= 0 && count !== expect) ||
        (expect === -1 && count < 1) ||
        (expect === -2 && (count < 2 || count % 2)) ||
        (expect === -3 && count < 2)
    )
        fail("wrong argument count for " + cmd);
    if (cmd === "ELEMENT") {
        if (!Object.hasOwn(W, a[0])) fail("unknown element " + a[0]);
        return [`${a[0]} (Z = ${symbols.indexOf(a[0]) + 1}) ${dec(W[a[0]], 3)} u`];
    }
    if (cmd === "HEATS")
        return heats.size
            ? [...heats.keys()].sort().map((s) => `${s} ${ent(heats.get(s))} kJ/mol`)
            : ["no enthalpies"];
    if (cmd === "HEAT") {
        species(a[0]);
        const h = enthalpy(a[1]);
        const out =
            `dHf(${a[0]}) = ${ent(h)} kJ/mol` +
            (heats.has(a[0]) ? ` (was ${ent(heats.get(a[0]))})` : "");
        heats.set(a[0], h);
        return [out];
    }
    if (cmd === "DERIVE") {
        const b = {};
        for (let i = 0; i < count; i += 2) {
            const e = a[i];
            if (!Object.hasOwn(W, e)) fail("unknown element " + e);
            if (Object.hasOwn(b, e)) fail("duplicate element " + e);
            const q = quantity(a[i + 1]);
            if (q > 100000) fail("invalid percentage " + a[i + 1]);
            b[e] = q;
        }
        const t = Object.values(b).reduce((x, y) => x + y, 0);
        if (Math.abs(t - 100000) > 1000) fail("percentages sum to " + dec(t, 3));
        return ratios(b);
    }
    if (cmd === "COMBUST") {
        const [s, p, r] = a.map(quantity),
            c = Math.floor((p * 12011) / 44009),
            h = Math.floor((r * 2016) / 18015),
            o = s - c - h;
        if (!c || !h || 100 * o < -s) fail("inconsistent masses");
        const b = { C: c, H: h };
        if (100 * o > s) b.O = o;
        return [...Object.keys(b).map((e) => `mass ${e} ${dec(b[e], 3)} g`), ...ratios(b)];
    }
    if (
        [
            "PARSE",
            "MASS",
            "PERCENT",
            "EMPIRICAL",
            "DBE",
            "OXSTATE",
            "MOLES",
            "GRAMS",
            "MOLECULAR",
            "SALT",
        ].includes(cmd)
    ) {
        const f = formula(a[0]),
            { c, q, m } = f,
            es = order(c);
        if (cmd === "PARSE")
            return [
                `${hill(c, q)} (${es.map((e) => e + " " + c[e]).join(", ")}; charge ${signed(q)})`,
            ];
        if (cmd === "MASS") return [`M(${a[0]}) = ${dec(m, 3)} g/mol`];
        if (cmd === "PERCENT")
            return es.map((e) => `${e} ${dec(Math.floor((10000 * c[e] * W[e]) / m), 2)}%`);
        if (cmd === "EMPIRICAL") {
            const g = Object.values(c).reduce(gcd, 0);
            return [
                `${hill(Object.fromEntries(Object.entries(c).map(([e, n]) => [e, n / g])))} (n = ${g})`,
            ];
        }
        if (cmd === "DBE") {
            if (q) fail("charged formula " + a[0]);
            let t = 2;
            for (const e of es) {
                if (!(e in valence)) fail("no valence for " + e);
                t += c[e] * (valence[e] - 2);
            }
            return [
                "DBE = " + (t < 0 ? "-" : "") + Math.floor(Math.abs(t) / 2) + "." + (t % 2 ? 5 : 0),
            ];
        }
        if (cmd === "OXSTATE") {
            const st = {};
            let last = "";
            const assign = (e, n) => {
                st[e] = new Fraction(n);
                last = e;
            };
            if (es.length === 1) st[es[0]] = new Fraction(q, c[es[0]]);
            else {
                if ("F" in c) assign("F", -1);
                for (const e of es) if (e in metals) assign(e, metals[e]);
                if ("H" in c) assign("H", es.every((e) => e === "H" || e in metals) ? -1 : 1);
                if ("O" in c) assign("O", -2);
                else if (!("F" in c))
                    for (const e of ["Cl", "Br", "I"])
                        if (e in c) {
                            assign(e, -1);
                            break;
                        }
                const u = es.filter((e) => !(e in st));
                if (u.length >= 2) return ["indeterminate: " + u.join(" ")];
                const s = Object.keys(st).reduce((t, e) => t + c[e] * st[e].n, 0);
                if (u.length) st[u[0]] = new Fraction(q - s, c[u[0]]);
                else if (s !== q) st[last] = new Fraction(q - s + c[last] * st[last].n, c[last]);
            }
            return [es.map((e) => e + " " + st[e].text()).join(", ")];
        }
        if (cmd === "SALT") {
            const b = formula(a[1]);
            if (q <= 0) fail("not a cation " + a[0]);
            if (b.q >= 0) fail("not an anion " + a[1]);
            for (const w of a) if (w.includes(".")) fail("hydrate ion " + w);
            const g = gcd(q, b.q),
                x = -b.q / g,
                y = q / g,
                z = add(scale(c, x), b.c, y);
            return [`${group(a[0], x)}${group(a[1], y)} (${hill(z)}, ${dec(mass(z), 3)} g/mol)`];
        }
        if (cmd === "MOLECULAR" && q) fail("charged formula " + a[0]);
        const n = quantity(a[1]);
        if (cmd === "MOLES")
            return [`${dec(n, 3)} g ${a[0]} = ${dec(Math.floor((n * 1000000) / m), 6)} mol`];
        if (cmd === "GRAMS")
            return [`${dec(n, 3)} mol ${a[0]} = ${dec(Math.floor((n * m) / 1000), 3)} g`];
        const k = Math.floor((2 * n + m) / (2 * m));
        return !k || 10 * Math.abs(n - k * m) > m
            ? [`no integer multiple (ratio ${dec(Math.floor((1000 * n) / m), 3)})`]
            : [`${hill(scale(c, k))} (n = ${k}, ${dec(k * m, 3)} g/mol)`];
    }
    if (cmd === "REDOX" || cmd === "HALF") {
        if (!["acidic", "basic"].includes(a[0])) fail("invalid medium " + a[0]);
        const eq = equation(a.slice(1));
        for (const s of eq.list)
            if (["H^+", "OH^-", "H2O"].includes(s.f)) fail("reserved species " + s.name);
        const aux = [species(a[0] === "acidic" ? "H^+" : "OH^-"), species("H2O")];
        if (cmd === "HALF")
            aux.push({ f: "e^-", name: "e^-", state: "", k: 1, c: {}, q: -1, m: 0 });
        const v = coefficients(
                [...eq.list, ...aux],
                [...eq.sign, ...aux.map(() => 1)],
                eq.list.length,
            ),
            left = [],
            right = [];
        eq.list.forEach((s, i) => (i < eq.r ? left : right).push(term(s.name, v[i])));
        aux.forEach((s, i) => {
            const n = v[eq.list.length + i];
            if (n) (n > 0 ? left : right).push(term(s.name, Math.abs(n)));
        });
        const out = [left.join(" + ") + " -> " + right.join(" + ")];
        if (cmd === "HALF")
            out.push(
                v.at(-1) > 0 ? "reduction" : v.at(-1) < 0 ? "oxidation" : "no electron transfer",
            );
        return out;
    }
    let words = a,
        rest = [];
    if (["STOICH", "LIMITING", "YIELD"].includes(cmd)) {
        if (a.filter((x) => x === ":").length !== 1) fail("invalid separator");
        const i = a.indexOf(":");
        words = a.slice(0, i);
        rest = a.slice(i + 1);
        if ((cmd === "STOICH" && rest.length !== 2) || (cmd === "YIELD" && rest.length !== 4))
            fail("wrong argument count for " + cmd);
    }
    const eq = equation(words, cmd === "CHECK"),
        list = eq.list,
        { r, sign } = eq;
    if (cmd === "MATRIX") {
        const { labels, rows } = matrix(list, sign),
            { rank, basis } = nullspace(rows, list.length);
        return [
            "columns: " + list.map((s) => s.name).join(" "),
            ...rows.map((row, i) => labels[i] + ": " + row.join(" ")),
            `rank ${rank}, nullity ${basis.length}`,
            ...basis.map((v) => "null: " + v.join(" ")),
        ];
    }
    if (cmd === "CHECK") {
        const { labels, rows } = matrix(list, sign),
            diff = [];
        rows.forEach((row, i) => {
            const l = row.slice(0, r).reduce((s, x, j) => s + x * list[j].k, 0),
                rr = -row.slice(r).reduce((s, x, j) => s + x * list[j + r].k, 0);
            if (l !== rr)
                diff.push(
                    labels[i] +
                        ": " +
                        (labels[i] === "charge" ? signed(l) : l) +
                        " != " +
                        (labels[i] === "charge" ? signed(rr) : rr),
                );
        });
        const g = list.map((s) => s.k).reduce(gcd, 0);
        return diff.length
            ? ["not balanced", ...diff]
            : [g === 1 ? "balanced" : `balanced, not in lowest terms (gcd ${g})`];
    }
    let target = -1,
        product = -1,
        qs = [];
    if (cmd === "DELTAH")
        for (const s of list) if (!heats.has(s.name)) fail("no enthalpy for " + s.name);
    if (cmd === "STOICH") {
        target = list.findIndex((s) => s.name === rest[0]);
        if (target < 0) fail("species " + rest[0] + " not in equation");
        qs = [quantity(rest[1])];
    }
    if (cmd === "LIMITING") {
        if (rest.length !== r) fail(`expected ${r} masses, got ${rest.length}`);
        qs = rest.map(quantity);
    }
    if (cmd === "YIELD") {
        target = list.findIndex((s, i) => i < r && s.name === rest[0]);
        if (target < 0) fail(rest[0] + " is not a reactant");
        product = list.findIndex((s, i) => i >= r && s.name === rest[2]);
        if (product < 0) fail(rest[2] + " is not a product");
        qs = [quantity(rest[1]), quantity(rest[3])];
    }
    const v = coefficients(list, sign),
        out = [notation(eq, v)];
    if (cmd === "BALANCE") return out;
    if (cmd === "DELTAH") {
        const h = list.reduce((t, s, i) => t - sign[i] * v[i] * heats.get(s.name), 0);
        return [
            ...out,
            `dH = ${ent(h)} kJ (${h < 0 ? "exothermic" : h > 0 ? "endothermic" : "thermoneutral"})`,
        ];
    }
    if (cmd === "STOICH") {
        const d = v[target] * list[target].m;
        return [
            ...out,
            ...list.map(
                (s, i) =>
                    `${s.name} ${dec(Math.floor((qs[0] * v[i] * 1000000) / d), 6)} mol ${dec(Math.floor((qs[0] * v[i] * s.m) / d), 3)} g` +
                    gas(s, qs[0] * v[i], d),
            ),
        ];
    }
    if (cmd === "YIELD") {
        const t = Math.floor((qs[0] * v[product] * list[product].m) / (v[target] * list[target].m));
        return [
            ...out,
            `theoretical ${dec(t, 3)} g`,
            `actual ${dec(qs[1], 3)} g`,
            t ? "yield " + dec(Math.floor((qs[1] * 10000) / t), 2) + "%" : "yield undefined",
        ];
    }
    let l = 0;
    for (let i = 1; i < r; i++) if (qs[i] * v[l] * list[l].m < qs[l] * v[i] * list[i].m) l = i;
    const d = v[l] * list[l].m;
    out.push(
        "limiting " + list[l].name,
        "extent " + dec(Math.floor((qs[l] * 1000000) / d), 6) + " mol",
    );
    for (let i = r; i < list.length; i++)
        out.push(
            `product ${list[i].name} ${dec(Math.floor((qs[l] * v[i] * list[i].m) / d), 3)} g` +
                gas(list[i], qs[l] * v[i], d),
        );
    for (let i = 0; i < r; i++)
        if (i !== l)
            out.push(
                `remaining ${list[i].name} ${dec(Math.floor((qs[i] * d - qs[l] * v[i] * list[i].m) / d), 3)} g`,
            );
    return out;
}
const input = fs.readFileSync(0, "utf8").trimEnd().split("\n"),
    out = [];
for (const line of input.slice(1, Number(input[0]) + 1)) {
    try {
        out.push(...execute(line));
    } catch (e) {
        out.push(e.message);
    }
}
process.stdout.write(out.join("\n") + "\n");
