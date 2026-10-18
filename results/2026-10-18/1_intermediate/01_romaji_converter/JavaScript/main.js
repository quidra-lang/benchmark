import { readFileSync } from "node:fs";


class Invalid extends Error {}

const systems = ["HEPBURN", "TRADITIONAL", "KUNREI", "NIHON", "WAPURO"];
const baseRows = ["a", "ka", "sa", "ta", "na", "ha", "ma", "ya", "ra", "wa"];
const rowData = [
    ["a", "a i u e o"], ["ka", "ka ki ku ke ko"], ["sa", "sa si su se so"],
    ["ta", "ta ti tu te to"], ["na", "na ni nu ne no"], ["ha", "ha hi hu he ho"],
    ["ma", "ma mi mu me mo"], ["ya", "ya yu yo"], ["ra", "ra ri ru re ro"],
    ["wa", "wa wi we wo"], ["ga", "ga gi gu ge go"], ["za", "za zi zu ze zo"],
    ["da", "da di du de do"], ["ba", "ba bi bu be bo"], ["pa", "pa pi pu pe po"]
];
const contractedRows = ["ka", "sa", "ta", "na", "ha", "ma", "ra", "ga", "za", "da", "ba", "pa"];
const table = [];
const info = new Map();
for (const [row, ids] of rowData) {
    for (const id of ids.split(" ")) {
        const item = { id, row, dan: id.slice(-1), contracted: false };
        table.push(item);
        info.set(id, item);
    }
}
for (const row of contractedRows) {
    for (const dan of ["ya", "yu", "yo"]) {
        const id = row[0] + dan;
        const item = { id, row, dan, contracted: true };
        table.push(item);
        info.set(id, item);
    }
}

function fail(message) {
    throw new Invalid(message);
}

function at(column, message) {
    return fail("col " + column + ": " + message);
}

function spelling(system, id) {
    const hepburn = {
        si: "shi", ti: "chi", tu: "tsu", hu: "fu", zi: "ji", di: "ji",
        du: "zu", wi: "i", we: "e", wo: "o"
    };
    const kunrei = {
        di: "zi", du: "zu", wi: "i", we: "e", wo: "o",
        dya: "zya", dyu: "zyu", dyo: "zyo"
    };
    const wapuro = {
        si: "shi", ti: "chi", tu: "tsu", hu: "fu", zi: "ji"
    };
    if (system === "KUNREI") {
        return kunrei[id] ?? id;
    }
    if (system === "NIHON") {
        return id;
    }
    const replacements = system === "WAPURO" ? wapuro : hepburn;
    if (replacements[id] !== undefined) {
        return replacements[id];
    }
    if (id.startsWith("sy")) {
        return "sh" + id.slice(2);
    }
    if (id.startsWith("ty")) {
        return "ch" + id.slice(2);
    }
    if (id.startsWith("zy") || (system !== "WAPURO" && id.startsWith("dy"))) {
        return "j" + id.slice(2);
    }
    return id;
}

const lexicons = new Map();
for (const system of [...systems, "NORMALIZE"]) {
    const entries = new Map();
    const sources = system === "NORMALIZE" ? ["HEPBURN", "KUNREI", "NIHON", "WAPURO"] : [system];
    for (const item of table) {
        for (const source of sources) {
            const text = spelling(source, item.id);
            if (!entries.has(text)) {
                entries.set(text, item.id);
            }
        }
    }
    const list = Array.from(entries, ([text, id]) => ({ spelling: text, id }));
    list.sort((a, b) => b.spelling.length - a.spelling.length);
    lexicons.set(system, list);
}

function matchAt(text, position, system) {
    return lexicons.get(system).find(entry => text.startsWith(entry.spelling, position));
}

function casePattern(word) {
    if (!/[A-Z]/.test(word)) {
        return "LOWER";
    }
    if (/^[A-Z]/.test(word) && !/[A-Z]/.test(word.slice(1))) {
        return "TITLE";
    }
    const letters = word.replace(/[^A-Za-z]/g, "");
    if (letters.length >= 2 && !/[a-z]/.test(letters)) {
        return "UPPER";
    }
    return "";
}

function scanWords(text) {
    const words = [];
    for (const match of text.matchAll(/[A-Za-z'-]+/g)) {
        words.push({
            original: match[0], start: match.index,
            pattern: casePattern(match[0]), morae: []
        });
    }
    return words;
}

function parseWord(word, system) {
    const text = word.original.toLowerCase();
    const result = [];
    let position = 0;
    while (position < text.length) {
        const c = text[position];
        const c2 = text[position + 1] ?? "";
        const column = word.start + position + 1;
        let id = "";
        let length = 1;
        if (c === "-") {
            if (result.length === 0 || !info.has(result[result.length - 1].id)) {
                at(column, "misplaced long mark");
            }
            id = "-";
        } else if (c === "'") {
            at(column, "misplaced apostrophe");
        } else {
            const match = matchAt(text, position, system);
            if (match) {
                id = match.id;
                length = match.spelling.length;
            } else if ((system === "WAPURO" || system === "NORMALIZE") && text.startsWith("xtu", position)) {
                id = "Q";
                length = 3;
            } else if (c === "n") {
                id = "N";
                if (system === "NORMALIZE") {
                    const third = text[position + 2] ?? "";
                    if (c2 === "'" || (c2 === "n" && !/^[aiueoy']$/.test(third))) {
                        length = 2;
                    }
                } else if ((system === "WAPURO" && c2 === "n") || (system !== "WAPURO" && c2 === "'")) {
                    length = 2;
                }
            } else if ((system === "TRADITIONAL" || system === "NORMALIZE") && c === "m" && /^[bmp]$/.test(c2)) {
                id = "N";
            } else if (/^[a-z]$/.test(c) && !/[aiueon]/.test(c) && c2 === c && matchAt(text, position + 1, system)) {
                id = "Q";
            } else if (["HEPBURN", "TRADITIONAL", "NORMALIZE"].includes(system) && c === "t" &&
                       text.startsWith("ch", position + 1) && matchAt(text, position + 1, system)) {
                id = "Q";
            } else {
                at(column, "unknown syllable");
            }
        }
        result.push({ id, column });
        position += length;
    }
    return result;
}

function longData(morae) {
    const pairs = new Set();
    const elements = new Map();
    for (let i = 0; i < morae.length; i++) {
        if (morae[i].id === "-") {
            elements.set(i, morae[i - 1].id.slice(-1));
        }
    }
    let i = 0;
    while (i + 1 < morae.length) {
        const current = morae[i].id;
        const next = morae[i + 1].id;
        const vowel = current.slice(-1);
        if (info.has(current) && /^[aiueo]$/.test(next) &&
            (vowel === next || (vowel === "o" && next === "u") || (vowel === "e" && next === "i"))) {
            pairs.add(i + 1);
            if ((vowel === "o" && (next === "o" || next === "u")) || (vowel === "u" && next === "u")) {
                elements.set(i + 1, vowel);
            }
            i += 2;
        } else {
            i++;
        }
    }
    return { pairs, elements };
}

function writtenParts(morae, system, longMode) {
    const data = longData(morae);
    const parts = [];
    for (let i = 0; i < morae.length; i++) {
        const mora = morae[i];
        const next = morae[i + 1]?.id ?? "";
        const nextSpelling = info.has(next) ? spelling(system, next) : "";
        const first = nextSpelling[0] ?? "";
        let part = "";
        if (data.elements.has(i)) {
            const vowel = data.elements.get(i);
            if (longMode === "KEEP") {
                part = mora.id === "-" ? "-" : spelling(system, mora.id);
            } else if (longMode === "PASSPORT") {
                part = vowel === "o" && !/^[aiueo]$/.test(first) ? "h" : "";
            } else if (longMode === "HYPHEN") {
                part = "-";
            } else if (longMode === "DOUBLE") {
                part = vowel;
            }
        } else if (info.has(mora.id)) {
            part = spelling(system, mora.id);
        } else if (mora.id === "N") {
            if (system === "WAPURO") {
                part = next === "N" || /^[aiueoyn]$/.test(first) ? "nn" : "n";
            } else if (system === "TRADITIONAL" && /^[bmp]$/.test(first)) {
                part = "m";
            } else {
                part = /^[aiueoy]$/.test(first) ? "n'" : "n";
            }
        } else if (mora.id === "Q") {
            if (first && !/[aiueon]/.test(first)) {
                part = ["HEPBURN", "TRADITIONAL"].includes(system) && nextSpelling.startsWith("ch") ? "t" : first;
            } else if (system === "WAPURO") {
                part = "xtu";
            } else {
                at(mora.column, "small tsu cannot be written");
            }
        }
        parts.push(part);
    }
    return parts;
}

function writeWord(word, system, settings, canonical = false, morae = word.morae) {
    const value = writtenParts(morae, system, canonical ? "KEEP" : settings.LONG).join("");
    const pattern = canonical || settings.CASE === "KEEP" ? word.pattern : settings.CASE;
    if (pattern === "UPPER") {
        return value.toUpperCase();
    }
    if (pattern === "TITLE") {
        return value[0].toUpperCase() + value.slice(1);
    }
    return value;
}

function replaceWords(text, words, replacement) {
    let result = "";
    let position = 0;
    for (const word of words) {
        result += text.slice(position, word.start) + replacement(word);
        position = word.start + word.original.length;
    }
    return result + text.slice(position);
}

function devoice(id) {
    const letters = { g: "k", z: "s", d: "t", b: "h", p: "h" };
    return (letters[id[0]] ?? id[0]) + id.slice(1);
}

function elements(morae) {
    const result = [];
    for (const mora of morae) {
        if (mora.id === "-") {
            continue;
        }
        if (mora.id === "N" || mora.id === "Q") {
            result.push({ base: mora.id === "N" ? "N" : "tu", voice: 0, size: mora.id === "Q" ? 1 : 0 });
            continue;
        }
        const item = info.get(mora.id);
        const voice = ["ga", "za", "da", "ba"].includes(item.row) ? 1 : item.row === "pa" ? 2 : 0;
        const base = item.contracted ? devoice(item.row[0] + "i") : devoice(mora.id);
        result.push({ base, voice, size: 0 });
        if (item.contracted) {
            result.push({ base: item.dan, voice: 0, size: 1 });
        }
    }
    return result;
}

const orders = {
    GOJUON: "a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N".split(" "),
    IROHA: "i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N".split(" ")
};

function compareSequence(a, b) {
    for (let i = 0; i < Math.min(a.length, b.length); i++) {
        if (a[i] !== b[i]) {
            return a[i] - b[i];
        }
    }
    return a.length - b.length;
}

function sortedWords(words, order) {
    const ranks = new Map(orders[order].map((base, rank) => [base, rank]));
    const entries = words.map((word, index) => {
        const cols = elements(word.morae);
        const keys = [
            cols.map(item => ranks.get(item.base)),
            cols.map(item => item.voice),
            cols.map(item => item.size),
            word.morae.map(mora => mora.id === "-" ? 1 : 0)
        ];
        return { word, index, keys };
    });
    entries.sort((a, b) => {
        for (let i = 0; i < a.keys.length; i++) {
            const difference = compareSequence(a.keys[i], b.keys[i]);
            if (difference !== 0) {
                return difference;
            }
        }
        return a.index - b.index;
    });
    return entries.map(entry => entry.word);
}

function parsePattern(pattern, system) {
    if (!/^[a-z'?*-]+$/.test(pattern)) {
        fail("invalid pattern");
    }
    const result = [];
    try {
        for (const part of pattern.split(/([?*])/)) {
            if (part === "?" || part === "*") {
                result.push(part);
            } else if (part) {
                const word = { original: part, start: 0, pattern: "LOWER", morae: [] };
                result.push(...parseWord(word, system).map(mora => mora.id));
            }
        }
    } catch (error) {
        if (!(error instanceof Invalid)) {
            throw error;
        }
        fail("invalid pattern");
    }
    return result;
}

function matchesPattern(pattern, morae) {
    let previous = new Array(morae.length + 1).fill(false);
    previous[0] = true;
    for (const token of pattern) {
        const current = new Array(morae.length + 1).fill(false);
        if (token === "*") {
            current[0] = previous[0];
        }
        for (let j = 1; j <= morae.length; j++) {
            current[j] = token === "*" ? previous[j] || current[j - 1] :
                previous[j - 1] && (token === "?" || token === morae[j - 1].id);
        }
        previous = current;
    }
    return previous[morae.length];
}

function ids(morae) {
    return morae.map(mora => mora.id).join(",");
}

function counted(items, total) {
    return items.length + " of " + total + (items.length ? ": " + items.join(" ") : "");
}

const settings = { LONG: "KEEP", CASE: "KEEP", ORDER: "GOJUON" };
const argumentCounts = {
    SET: 2, TABLE: 2, CONVERT: 2, NORMALIZE: 0, REVERSE: 1, VALID: 1,
    DETECT: 0, DIFF: 2, SAME: 2, MORAE: 1, SYLLABLES: 1, ROW: 1,
    STATS: 1, SORT: 1, INDEX: 1, FIND: 2, HAIKU: 1, KAIBUN: 1, SHIRITORI: 1
};

function command(line) {
    const name = line.split(" ", 1)[0];
    if (!Object.hasOwn(argumentCounts, name)) {
        fail("unknown command " + name);
    }
    const count = argumentCounts[name];
    const args = [];
    let text = "";
    if (name === "SET" || name === "TABLE") {
        const parts = line.split(" ");
        if (parts.length < 3) {
            fail("missing argument");
        }
        if (parts.length > 3) {
            fail("too many arguments");
        }
        args.push(...parts.slice(1));
    } else {
        let position = 0;
        for (let i = 0; i <= count; i++) {
            const space = line.indexOf(" ", position);
            if (space < 0) {
                fail("missing argument");
            }
            if (i > 0) {
                args.push(line.slice(position, space));
            }
            position = space + 1;
        }
        text = line.slice(position);
    }
    const systemCount = ["NORMALIZE", "DETECT", "SET"].includes(name) ? 0 :
        ["CONVERT", "DIFF", "SAME"].includes(name) ? 2 : 1;
    for (const system of args.slice(0, systemCount)) {
        if (!systems.includes(system)) {
            fail("unknown system " + system);
        }
    }
    const system = name === "NORMALIZE" ? "NORMALIZE" : args[0];
    if (name === "SET") {
        const choices = {
            LONG: ["KEEP", "DROP", "PASSPORT", "HYPHEN", "DOUBLE"],
            CASE: ["KEEP", "LOWER", "UPPER", "TITLE"], ORDER: ["GOJUON", "IROHA"]
        };
        if (!Object.hasOwn(choices, args[0])) {
            fail("unknown option " + args[0]);
        }
        if (!choices[args[0]].includes(args[1])) {
            fail("unknown value " + args[1]);
        }
        settings[args[0]] = args[1];
        return args[0] + "=" + args[1];
    }
    if (name === "TABLE") {
        if (!rowData.some(([row]) => row === args[1])) {
            fail("unknown row " + args[1]);
        }
        return table.filter(item => item.row === args[1]).map(item => spelling(system, item.id)).join(" ");
    }
    const pattern = name === "FIND" ? parsePattern(args[1], system) : [];
    const allowSlash = name === "HAIKU" || name === "SAME";
    for (let i = 0; i < text.length; i++) {
        if (!/[A-Za-z0-9' .,! ?;:()"-]/.test(text[i]) && !(allowSlash && text[i] === "/")) {
            at(i + 1, "invalid character");
        }
    }
    const pieces = text.split("/");
    if (name === "SAME" && (pieces.length !== 2 || pieces.some(piece => scanWords(piece).length === 0))) {
        fail("expected two texts");
    }
    if (name === "HAIKU" && (![3, 5].includes(pieces.length) || pieces.some(piece => scanWords(piece).length === 0))) {
        fail("expected 3 or 5 lines");
    }
    const words = scanWords(text);
    if (words.length === 0) {
        fail("no words");
    }
    for (const word of words) {
        if (!word.pattern) {
            at(word.start + 1, "mixed case");
        }
    }
    if (name === "DETECT") {
        return systems.map(source => {
            let verdict = "canonical";
            try {
                for (const word of words) {
                    word.morae = parseWord(word, source);
                }
                if (words.some(word => word.original !== writeWord(word, source, settings, true))) {
                    verdict = "readable";
                }
            } catch (error) {
                if (!(error instanceof Invalid)) {
                    throw error;
                }
                verdict = "error";
            }
            return source + "=" + verdict;
        }).join(" ");
    }
    const slash = text.indexOf("/");
    for (const word of words) {
        const source = name === "SAME" && word.start > slash ? args[1] : system;
        word.morae = parseWord(word, source);
    }
    if (name === "CONVERT" || name === "NORMALIZE" || name === "REVERSE") {
        const target = name === "NORMALIZE" ? "HEPBURN" : name === "CONVERT" ? args[1] : system;
        return replaceWords(text, words, word => {
            let morae = word.morae;
            if (name === "REVERSE") {
                morae = morae.map((mora, i) => ({
                    id: mora.id === "-" ? word.morae[i - 1].id.slice(-1) : mora.id,
                    column: mora.column
                })).reverse();
            }
            return writeWord(word, target, settings, false, morae);
        });
    }
    if (name === "VALID") {
        for (const word of words) {
            const canonical = writeWord(word, system, settings, true);
            if (canonical !== word.original) {
                let i = 0;
                while (i < Math.min(canonical.length, word.original.length) && canonical[i] === word.original[i]) {
                    i++;
                }
                return "INVALID col " + (word.start + i + 1) + ": expected " + canonical;
            }
        }
        return "VALID";
    }
    if (name === "DIFF") {
        const differences = [];
        for (const word of words) {
            const a = writeWord(word, system, settings);
            const b = writeWord(word, args[1], settings);
            if (a !== b) {
                differences.push(a + ">" + b);
            }
        }
        return counted(differences, words.length);
    }
    if (name === "SAME") {
        const left = words.filter(word => word.start < slash);
        const right = words.filter(word => word.start > slash);
        for (let i = 0; i < Math.min(left.length, right.length); i++) {
            const loose = (word) => {
                const data = longData(word.morae);
                return ids(word.morae.filter((_, index) => !data.elements.has(index)));
            };
            if (loose(left[i]) !== loose(right[i])) {
                return "DIFFERENT at word " + (i + 1);
            }
        }
        if (left.length !== right.length) {
            return "DIFFERENT at word " + (Math.min(left.length, right.length) + 1);
        }
        return left.every((word, i) => ids(word.morae) === ids(right[i].morae)) ? "EXACT" : "LOOSE";
    }
    if (name === "MORAE") {
        const total = words.reduce((sum, word) => sum + word.morae.length, 0);
        return total + ": " + words.map(word => word.morae.map(mora =>
            info.has(mora.id) ? spelling(system, mora.id) : mora.id).join(".")).join(" ");
    }
    if (name === "SYLLABLES") {
        let total = 0;
        const displays = words.map(word => {
            const data = longData(word.morae);
            const parts = writtenParts(word.morae, system, "KEEP");
            const groups = [];
            for (let i = 0; i < word.morae.length; i++) {
                if (i === 0 || (info.has(word.morae[i].id) && !data.pairs.has(i))) {
                    groups.push(parts[i]);
                } else {
                    groups[groups.length - 1] += parts[i];
                }
            }
            total += groups.length;
            return groups.join(".");
        });
        return total + ": " + displays.join(" ");
    }
    if (name === "ROW") {
        return words.flatMap(word => word.morae.map(mora => {
            const item = info.get(mora.id);
            return item ? spelling(system, mora.id) + ": " + item.row + " " + item.dan : mora.id + ": special";
        })).join(", ");
    }
    if (name === "STATS") {
        const counts = new Map();
        const increment = (key) => {
            counts.set(key, (counts.get(key) ?? 0) + 1);
        };
        const all = words.flatMap(word => word.morae);
        for (const mora of all) {
            const item = info.get(mora.id);
            if (!item) {
                increment(mora.id === "-" ? "L" : mora.id);
            } else {
                increment(devoice(item.row));
                if (["ga", "za", "da", "ba"].includes(item.row)) {
                    increment("voiced");
                }
                if (item.row === "pa") {
                    increment("semivoiced");
                }
                if (item.contracted) {
                    increment("contracted");
                }
            }
        }
        const output = ["morae=" + all.length];
        for (const row of baseRows) {
            if (counts.has(row)) {
                output.push(row + "=" + counts.get(row));
            }
        }
        for (const key of ["voiced", "semivoiced", "contracted", "N", "Q", "L"]) {
            output.push(key + "=" + (counts.get(key) ?? 0));
        }
        return output.join(" ");
    }
    if (name === "SORT" || name === "INDEX") {
        const sorted = sortedWords(words, settings.ORDER);
        if (name === "SORT") {
            return sorted.map(word => word.original).join(" ");
        }
        const groups = [];
        for (const word of sorted) {
            const base = elements(word.morae)[0].base;
            const heading = settings.ORDER === "IROHA" || base === "N" ? base : info.get(base).row;
            if (groups.length === 0 || groups[groups.length - 1].heading !== heading) {
                groups.push({ heading, words: [] });
            }
            groups[groups.length - 1].words.push(word.original);
        }
        return groups.map(group => group.heading + ": " + group.words.join(" ")).join("; ");
    }
    if (name === "FIND") {
        return counted(words.filter(word => matchesPattern(pattern, word.morae)).map(word => word.original), words.length);
    }
    if (name === "HAIKU") {
        const counts = new Array(pieces.length).fill(0);
        for (const word of words) {
            const lineIndex = text.slice(0, word.start).split("/").length - 1;
            counts[lineIndex] += word.morae.length;
        }
        const expected = pieces.length === 3 ? [5, 7, 5] : [5, 7, 5, 7, 7];
        const verdict = counts.every((count, i) => count === expected[i]) ? "OK" : "NG";
        return verdict + (pieces.length === 3 ? " haiku " : " tanka ") + counts.join("-");
    }
    if (name === "KAIBUN") {
        const sequence = words.flatMap(word => elements(word.morae).map(item => item.base));
        const palindrome = sequence.every((base, i) => base === sequence[sequence.length - 1 - i]);
        return (palindrome ? "YES " : "NO ") + sequence.join(".");
    }
    const seen = new Set();
    let previousTail = "";
    for (let i = 0; i < words.length; i++) {
        const word = words[i];
        const sequence = elements(word.morae);
        const head = sequence[0].base;
        const tail = sequence[sequence.length - 1].base;
        const prefix = "NG " + (i + 1) + ": " + word.original;
        if (i > 0 && head !== previousTail) {
            return prefix + " must start with " + spelling(system, previousTail);
        }
        const key = ids(word.morae);
        if (seen.has(key)) {
            return prefix + " is repeated";
        }
        if (tail === "N") {
            return prefix + " ends with N";
        }
        seen.add(key);
        previousTail = tail;
    }
    return "OK " + words.length;
}

const lines = readFileSync(0, "utf8").split(/\r?\n/);
const count = Number(lines[0]);
const output = [];
for (let i = 1; i <= count; i++) {
    try {
        output.push(command(lines[i]));
    } catch (error) {
        if (!(error instanceof Invalid)) {
            throw error;
        }
        output.push("ERROR " + error.message);
    }
}
process.stdout.write(output.join("\n") + "\n");
