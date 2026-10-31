const fs = require('node:fs');

const faces = 'URFDLB';
const colors = 'WRGYOB';
const letters = 'UDFBLRMESudfblrxyz';
const cornerNames = ['URF', 'UFL', 'ULB', 'UBR', 'DFR', 'DLF', 'DBL', 'DRB'];
const edgeNames = ['UR', 'UF', 'UL', 'UB', 'DR', 'DF', 'DL', 'DB', 'FR', 'FL', 'BL', 'BR'];
const cornerStickers = ['U9 R1 F3', 'U7 F1 L3', 'U1 L1 B3', 'U3 B1 R3', 'D3 F9 R7', 'D1 L9 F7', 'D7 B9 L7', 'D9 R9 B7'];
const edgeStickers = ['U6 R2', 'U8 F2', 'U4 L2', 'U2 B2', 'D6 R8', 'D2 F8', 'D4 L8', 'D8 B8', 'F6 R4', 'F4 L6', 'B6 L4', 'B4 R6'];
const identity = () => Array.from({ length: 54 }, (_, index) => index);
const solvedState = () => [...colors].flatMap(color => Array(9).fill(color));
const axis = (letter) => 'RLMrlx'.includes(letter) ? 'x' : 'UDEudy'.includes(letter) ? 'y' : 'z';
const moveText = (move) => move.letter + (move.amount === 2 ? '2' : move.amount === 3 ? "'" : '');
const sequenceText = (moves) => String(moves.length) + (moves.length === 0 ? '' : ' ' + moves.map(moveText).join(' '));
const inverse = (moves) => [...moves].reverse().map(move => ({ letter: move.letter, amount: 4 - move.amount }));
const sticker = (face, row, column) => faces.indexOf(face) * 9 + (row - 1) * 3 + column - 1;
const indices = (text) => text.split(' ').map(word => faces.indexOf(word[0]) * 9 + Number(word.slice(1)) - 1);
const cornerIndices = cornerStickers.map(indices);
const edgeIndices = edgeStickers.map(indices);
const centerIndices = [...faces].map((_, face) => [face * 9 + 4]);

function compose(first, second) {
    return first.map(destination => second[destination]);
}
function inversePermutation(permutation) {
    const result = identity();
    permutation.forEach((destination, source) => result[destination] = source);
    return result;
}
function applyPermutation(state, permutation) {
    const result = [...state];
    permutation.forEach((destination, source) => result[destination] = state[source]);
    return result;
}
function buildMoves() {
    const quarter = new Map();
    for (const letter of 'URFDLBMES') {
        const permutation = identity();
        const put = (from, i, j, to, row, column) => {
            permutation[sticker(from, i, j)] = sticker(to, row, column);
        };
        if (faces.includes(letter)) for (let i = 1; i <= 3; i++) for (let j = 1; j <= 3; j++) put(letter, i, j, letter, j, 4 - i);
        for (let n = 1; n <= 3; n++) {
            switch (letter) {
                case 'U': put('F', 1, n, 'L', 1, n); put('L', 1, n, 'B', 1, n); put('B', 1, n, 'R', 1, n); put('R', 1, n, 'F', 1, n); break;
                case 'R': put('F', n, 3, 'U', n, 3); put('U', n, 3, 'B', 4 - n, 1); put('B', n, 1, 'D', 4 - n, 3); put('D', n, 3, 'F', n, 3); break;
                case 'F': put('U', 3, n, 'R', n, 1); put('R', n, 1, 'D', 1, 4 - n); put('D', 1, n, 'L', n, 3); put('L', n, 3, 'U', 3, 4 - n); break;
                case 'D': put('F', 3, n, 'R', 3, n); put('R', 3, n, 'B', 3, n); put('B', 3, n, 'L', 3, n); put('L', 3, n, 'F', 3, n); break;
                case 'L': put('U', n, 1, 'F', n, 1); put('F', n, 1, 'D', n, 1); put('D', n, 1, 'B', 4 - n, 3); put('B', n, 3, 'U', 4 - n, 1); break;
                case 'B': put('U', 1, n, 'L', 4 - n, 1); put('L', n, 1, 'D', 3, n); put('D', 3, n, 'R', 4 - n, 3); put('R', n, 3, 'U', 1, n); break;
                case 'M': put('U', n, 2, 'F', n, 2); put('F', n, 2, 'D', n, 2); put('D', n, 2, 'B', 4 - n, 2); put('B', n, 2, 'U', 4 - n, 2); break;
                case 'E': put('F', 2, n, 'R', 2, n); put('R', 2, n, 'B', 2, n); put('B', 2, n, 'L', 2, n); put('L', 2, n, 'F', 2, n); break;
                case 'S': put('U', 2, n, 'R', n, 2); put('R', n, 2, 'D', 2, 4 - n); put('D', 2, n, 'L', n, 2); put('L', n, 2, 'U', 2, 4 - n); break;
            }
        }
        quarter.set(letter, permutation);
    }
    const definitions = { r: "R M'", l: 'L M', u: "U E'", d: 'D E', f: 'F S', b: "B S'", x: "R M' L'", y: "U E' D'", z: "F S B'" };
    for (const [letter, definition] of Object.entries(definitions)) {
        let permutation = identity();
        for (const word of definition.split(' ')) {
            const base = quarter.get(word[0]);
            permutation = compose(permutation, word.endsWith("'") ? inversePermutation(base) : base);
        }
        quarter.set(letter, permutation);
    }
    const result = new Map();
    for (const letter of letters) {
        let permutation = identity();
        for (let amount = 1; amount <= 3; amount++) {
            permutation = compose(permutation, quarter.get(letter));
            result.set(moveText({ letter, amount }), permutation);
        }
    }
    return result;
}
const movePermutations = buildMoves();
function effect(moves) {
    return moves.reduce((permutation, move) => compose(permutation, movePermutations.get(moveText(move))), identity());
}
function basicSequence(text) {
    return text === '' ? [] : text.split(' ').map(word => ({ letter: word[0], amount: word.endsWith('2') ? 2 : word.endsWith("'") ? 3 : 1 }));
}
const rotations = ['', 'y', 'y2', "y'", 'x', 'x y', 'x y2', "x y'", 'x2', 'x2 y', 'x2 y2', "x2 y'", "x'", "x' y", "x' y2", "x' y'", 'z', 'z y', 'z y2', "z y'", "z'", "z' y", "z' y2", "z' y'"].map(basicSequence);
const rotationEffects = rotations.map(effect);
function normalize(state) {
    for (let index = 0; index < rotations.length; index++) {
        const rotated = applyPermutation(state, rotationEffects[index]);
        if ([...colors].every((color, face) => rotated[face * 9 + 4] === color)) return { state: rotated, rotation: index };
    }
    return null;
}
function identify(state, names, positions) {
    const pieces = [];
    const orientations = [];
    for (const position of positions) {
        const current = position.map(index => state[index]);
        let found = -1;
        let twist = 0;
        for (let piece = 0; piece < names.length && found < 0; piece++) {
            const expected = [...names[piece]].map(face => colors[faces.indexOf(face)]);
            for (let orientation = 0; orientation < current.length; orientation++) {
                if (expected.every((color, index) => current[(orientation + index) % current.length] === color)) {
                    found = piece;
                    twist = orientation;
                    break;
                }
            }
        }
        pieces.push(found);
        orientations.push(twist);
    }
    return { pieces, orientations };
}
function cycles(state, names, positions) {
    const identified = identify(state, names, positions);
    const destination = [];
    identified.pieces.forEach((piece, position) => destination[piece] = position);
    const seen = new Set();
    const result = [];
    for (let start = 0; start < names.length; start++) {
        if (seen.has(start)) continue;
        const cycle = [];
        let current = start;
        let orientation = 0;
        do {
            seen.add(current);
            cycle.push(names[current]);
            current = destination[current];
            orientation += identified.orientations[current];
        } while (current !== start);
        const remainder = orientation % positions[0].length;
        const mark = remainder === 0 ? '' : remainder === 1 ? '+' : '-';
        if (cycle.length > 1 || mark !== '') result.push('(' + cycle.join(' ') + ')' + mark);
    }
    return result.length === 0 ? 'none' : result.join(' ');
}
function parity(pieces) {
    let count = 0;
    for (let i = 0; i < pieces.length; i++) for (let j = i + 1; j < pieces.length; j++) if (pieces[i] > pieces[j]) count++;
    return count % 2;
}
function invalidState(text) {
    if (text.length !== 54) return `length ${text.length}`;
    const state = [...text];
    const bad = state.findIndex(color => !colors.includes(color));
    if (bad >= 0) return `char ${bad + 1}`;
    for (const color of colors) {
        const count = state.filter(value => value === color).length;
        if (count !== 9) return `count ${color} ${count}`;
    }
    const normalized = normalize(state);
    if (normalized === null) return 'centers';
    const corners = identify(state, cornerNames, cornerIndices);
    const edges = identify(state, edgeNames, edgeIndices);
    if (corners.pieces.includes(-1)) return `corner ${cornerNames[corners.pieces.indexOf(-1)]}`;
    if (edges.pieces.includes(-1)) return `edge ${edgeNames[edges.pieces.indexOf(-1)]}`;
    for (let piece = 0; piece < 8; piece++) if (!corners.pieces.includes(piece)) return `missing ${cornerNames[piece]}`;
    for (let piece = 0; piece < 12; piece++) if (!edges.pieces.includes(piece)) return `missing ${edgeNames[piece]}`;
    const normalizedCorners = identify(normalized.state, cornerNames, cornerIndices);
    const normalizedEdges = identify(normalized.state, edgeNames, edgeIndices);
    if (normalizedCorners.orientations.reduce((a, b) => a + b, 0) % 3 !== 0) return 'twist';
    if (normalizedEdges.orientations.reduce((a, b) => a + b, 0) % 2 !== 0) return 'flip';
    return parity(normalizedCorners.pieces) === parity(normalizedEdges.pieces) ? null : 'parity';
}
function mismatch(state) {
    return state.filter((color, index) => color !== state[Math.floor(index / 9) * 9 + 4]).length;
}
function simplify(moves) {
    let current = moves;
    while (true) {
        const result = [];
        for (let start = 0; start < current.length;) {
            let end = start;
            const sums = new Map();
            while (end < current.length && axis(current[end].letter) === axis(current[start].letter)) {
                const move = current[end++];
                sums.set(move.letter, (sums.get(move.letter) ?? 0) + move.amount);
            }
            for (const [letter, sum] of sums) if (sum % 4 !== 0) result.push({ letter, amount: sum % 4 });
            start = end;
        }
        if (sequenceText(result) === sequenceText(current)) return result;
        current = result;
    }
}
function matchingMove(permutation, outerOnly = false) {
    for (const letter of outerOnly ? faces : letters) for (let amount = 1; amount <= 3; amount++) {
        const candidate = movePermutations.get(moveText({ letter, amount }));
        if (candidate.every((destination, index) => destination === permutation[index])) return { letter, amount };
    }
    throw new Error('move effect unavailable');
}
function conjugate(move, rotation, outerOnly = false) {
    return matchingMove(compose(compose(rotation, movePermutations.get(moveText(move))), inversePermutation(rotation)), outerOnly);
}
function unrotate(moves) {
    const replacements = { M: "R L' x'", E: "U D' y'", S: "F' B z", r: 'L x', l: "R x'", u: 'D y', d: "U y'", f: 'B z', b: "F z'" };
    const result = [];
    let rotation = identity();
    for (const move of moves) {
        const expanded = replacements[move.letter] === undefined ? [move] : basicSequence(replacements[move.letter]).map(part => ({ letter: part.letter, amount: part.amount * move.amount % 4 }));
        for (const part of expanded) {
            if ('xyz'.includes(part.letter)) rotation = compose(rotation, movePermutations.get(moveText(part)));
            else result.push(conjugate(part, rotation, true));
        }
    }
    const index = rotationEffects.findIndex(candidate => candidate.every((destination, i) => destination === rotation[i]));
    return [...result, ...rotations[index]];
}
function gcd(a, b) {
    while (b !== 0) [a, b] = [b, a % b];
    return a;
}
function order(permutation) {
    const seen = new Set();
    let result = 1;
    for (let start = 0; start < 54; start++) {
        if (seen.has(start)) continue;
        let current = start;
        let length = 0;
        do { seen.add(current); current = permutation[current]; length++; } while (current !== start);
        result = result / gcd(result, length) * length;
    }
    return result;
}

class SequenceParser {
    constructor(line, position, macros) {
        this.line = line;
        this.position = position;
        this.macros = macros;
    }
    current() { return this.line[this.position] ?? ''; }
    spaces() { while (this.current() === ' ') this.position++; }
    syntax() { throw new Error(`syntax at ${Math.min(this.position, this.line.length) + 1}`); }
    power(moves) {
        let count = 1;
        if (/^[1-9]$/.test(this.current())) {
            count = Number(this.current()); this.position++;
            if (/^[0-9]$/.test(this.current())) { count = count * 10 + Number(this.current()); this.position++; }
        }
        const invert = this.current() === "'";
        if (invert) this.position++;
        const result = [];
        for (let i = 0; i < count; i++) result.push(...moves);
        return invert ? inverse(result) : result;
    }
    sequence() {
        const result = [];
        while (true) {
            this.spaces();
            const char = this.current();
            if (char !== '' && letters.includes(char)) {
                this.position++;
                let amount = 1;
                if (this.current() === '2') { amount = 2; this.position++; }
                else if (this.current() === "'") { amount = 3; this.position++; }
                result.push({ letter: char, amount });
            } else if (char === '(') {
                this.position++;
                const group = this.sequence(); this.spaces();
                if (this.current() !== ')') this.syntax();
                this.position++; result.push(...this.power(group));
            } else if (char === '[') {
                this.position++;
                const left = this.sequence(); this.spaces();
                const separator = this.current();
                if (separator !== ',' && separator !== ':') this.syntax();
                this.position++;
                const right = this.sequence(); this.spaces();
                if (this.current() !== ']') this.syntax();
                this.position++;
                const group = [...left, ...right, ...inverse(left), ...(separator === ',' ? inverse(right) : [])];
                result.push(...this.power(group));
            } else if (char === '{') {
                this.position++;
                const start = this.position;
                while (/^[a-z]$/.test(this.current())) this.position++;
                const name = this.line.slice(start, this.position);
                if (name === '' || this.current() !== '}') this.syntax();
                const macro = this.macros.get(name);
                if (macro === undefined) throw new Error(`undefined ${name}`);
                this.position++; result.push(...this.power(macro));
            } else return result;
        }
    }
    parse() {
        const result = this.sequence(); this.spaces();
        if (this.current() !== '') this.syntax();
        if (result.length > 500) throw new Error('too long');
        return result;
    }
}

class Cube {
    state = solvedState();
    history = [];
    redo = [];
    macros = new Map();
    saves = new Map();
    output = [];

    search(depth) {
        const visit = (state, remaining, previous) => {
            if (remaining === 0) return mismatch(state) === 0 ? [] : null;
            for (const face of faces) {
                if (face === previous || previous === 'D' && face === 'U' || previous === 'L' && face === 'R' || previous === 'B' && face === 'F') continue;
                for (const amount of [1, 2, 3]) {
                    const move = { letter: face, amount };
                    const tail = visit(applyPermutation(state, movePermutations.get(moveText(move))), remaining - 1, face);
                    if (tail !== null) return [move, ...tail];
                }
            }
            return null;
        };
        for (let limit = 0; limit <= depth; limit++) {
            const result = visit(this.state, limit, '');
            if (result !== null) return result;
        }
        return null;
    }
    apply(moves) {
        this.state = applyPermutation(this.state, effect(moves));
        this.history.push(...moves);
        this.redo = [];
    }
    execute(line) {
        const space = line.indexOf(' ');
        const command = space < 0 ? line : line.slice(0, space);
        const argument = space < 0 ? null : line.slice(space + 1);
        const noArguments = new Set(['RESET', 'SHOW', 'STATE', 'ISSOLVED', 'HISTORY', 'SOLUTION', 'ANALYZE', 'STAGE', 'MACROS']);
        const wordCommands = { CHECK: 1, LOAD: 1, UNDO: 1, REDO: 1, SEARCH: 1, WHERE: 1, SAVE: 1, RESTORE: 1, SCRAMBLE: 2 };
        const sequenceCommands = new Set(['APPLY', 'INVERT', 'SIMPLIFY', 'METRICS', 'ORDER', 'CYCLES', 'UNROTATE', 'UNTIL']);
        const headCommands = new Set(['DEFINE', 'MIRROR', 'ROTATE']);
        if (!noArguments.has(command) && !Object.hasOwn(wordCommands, command) && !sequenceCommands.has(command) && !headCommands.has(command)) throw new Error(`unknown command ${command}`);
        const words = argument === null ? [] : argument.split(' ');
        const numberWord = /^(?:0|[1-9][0-9]{0,9})$/;
        if (noArguments.has(command) && argument !== null || Object.hasOwn(wordCommands, command) && words.length !== wordCommands[command]) throw new Error('bad arguments');
        if (['UNDO', 'REDO', 'SEARCH', 'SCRAMBLE'].includes(command) && !words.every(word => numberWord.test(word))) throw new Error('bad arguments');
        if (['SAVE', 'RESTORE'].includes(command) && !/^[a-z]{1,8}$/.test(words[0])) throw new Error('bad arguments');
        if (headCommands.has(command) && (argument === null || command === 'DEFINE' && !/^[a-z]{1,8}$/.test(words[0]) || command === 'MIRROR' && !['LR', 'UD', 'FB'].includes(words[0]) || command === 'ROTATE' && !/^[xyz](?:2|')?$/.test(words[0]))) throw new Error('bad arguments');
        let moves = [];
        if (sequenceCommands.has(command)) moves = new SequenceParser(line, space < 0 ? line.length : space + 1, this.macros).parse();
        else if (headCommands.has(command)) moves = new SequenceParser(line, (space + 1) + words[0].length + 1, this.macros).parse();
        if (['UNDO', 'REDO'].includes(command) && Number(words[0]) < 1 || command === 'SEARCH' && Number(words[0]) > 4 || command === 'SCRAMBLE' && (Number(words[0]) < 1 || Number(words[0]) > 50 || Number(words[1]) < 1 || Number(words[1]) > 2147483646)) throw new Error('bad value');
        if (command === 'WHERE' && !cornerNames.includes(words[0]) && !edgeNames.includes(words[0])) throw new Error(`unknown piece ${words[0]}`);
        switch (command) {
            case 'RESET': this.state = solvedState(); this.history = []; this.redo = []; this.output.push('reset'); break;
            case 'STATE': this.output.push('state ' + this.state.join('')); break;
            case 'ISSOLVED': { const count = mismatch(this.state); this.output.push(count === 0 ? 'solved' : `unsolved ${count}`); break; }
            case 'HISTORY': this.output.push('history ' + sequenceText(this.history)); break;
            case 'SOLUTION': this.output.push('solution ' + sequenceText(simplify(inverse(this.history)))); break;
            case 'SHOW': {
                const row = (face, index) => this.state.slice(faces.indexOf(face) * 9 + index * 3, faces.indexOf(face) * 9 + index * 3 + 3).join(' ');
                for (let i = 0; i < 3; i++) this.output.push('      ' + row('U', i));
                for (let i = 0; i < 3; i++) this.output.push(['L', 'F', 'R', 'B'].map(face => row(face, i)).join(' '));
                for (let i = 0; i < 3; i++) this.output.push('      ' + row('D', i));
                break;
            }
            case 'MACROS': this.output.push(`macros ${this.macros.size}`); for (const name of [...this.macros.keys()].sort()) this.output.push(`macro ${name} ${sequenceText(this.macros.get(name))}`); break;
            case 'CHECK': case 'LOAD': {
                const reason = invalidState(words[0]);
                if (command === 'CHECK') this.output.push(reason === null ? 'valid' : 'invalid ' + reason);
                else { if (reason !== null) throw new Error('invalid ' + reason); this.state = [...words[0]]; this.history = []; this.redo = []; this.output.push('loaded'); }
                break;
            }
            case 'UNDO': case 'REDO': {
                const source = command === 'UNDO' ? this.history : this.redo;
                const target = command === 'UNDO' ? this.redo : this.history;
                if (source.length === 0) throw new Error(command === 'UNDO' ? 'nothing to undo' : 'nothing to redo');
                const count = Math.min(Number(words[0]), source.length);
                for (let i = 0; i < count; i++) { const move = source.pop(); this.state = applyPermutation(this.state, effect(command === 'UNDO' ? inverse([move]) : [move])); target.push(move); }
                this.output.push(`${command === 'UNDO' ? 'undone' : 'redone'} ${count}`); break;
            }
            case 'SAVE': this.saves.set(words[0], { state: [...this.state], history: [...this.history] }); this.output.push('saved ' + words[0]); break;
            case 'RESTORE': { const save = this.saves.get(words[0]); if (save === undefined) throw new Error('no save ' + words[0]); this.state = [...save.state]; this.history = [...save.history]; this.redo = []; this.output.push('restored ' + words[0]); break; }
            case 'SEARCH': { const solution = this.search(Number(words[0])); this.output.push(solution === null ? 'not found' : 'found ' + sequenceText(solution)); break; }
            case 'ANALYZE': case 'WHERE': case 'STAGE': {
                const normalized = normalize(this.state);
                const corners = identify(normalized.state, cornerNames, cornerIndices);
                const edges = identify(normalized.state, edgeNames, edgeIndices);
                if (command === 'ANALYZE') {
                    const rotation = rotations[normalized.rotation];
                    this.output.push('rotation ' + (rotation.length === 0 ? 'none' : rotation.map(moveText).join(' ')));
                    this.output.push('corners ' + cycles(normalized.state, cornerNames, cornerIndices));
                    this.output.push('edges ' + cycles(normalized.state, edgeNames, edgeIndices));
                } else if (command === 'WHERE') {
                    const corner = cornerNames.includes(words[0]);
                    const names = corner ? cornerNames : edgeNames;
                    const data = corner ? corners : edges;
                    const at = data.pieces.indexOf(names.indexOf(words[0]));
                    this.output.push(`${words[0]} at ${names[at]} ${corner ? 'twist' : 'flip'} ${data.orientations[at]}`);
                } else {
                    const correct = (data, index) => data.pieces[index] === index && data.orientations[index] === 0;
                    const cross = [4, 5, 6, 7].filter(index => correct(edges, index)).length;
                    const slots = [4, 5, 6, 7].filter(index => correct(corners, index) && correct(edges, index + 4)).length;
                    const top = normalized.state.slice(0, 9).filter(color => color === 'W').length;
                    const stage = mismatch(normalized.state) === 0 ? 'solved'
                        : cross === 4 && slots === 4 ? top === 9 ? 'oll' : 'f2l'
                        : cross === 4 ? 'cross' : 'none';
                    this.output.push(`stage ${stage} cross ${cross} slots ${slots} top ${top}`);
                }
                break;
            }
            case 'SCRAMBLE': {
                let random = Number(words[1]);
                const next = () => random = random * 48271 % 2147483647;
                const scramble = [];
                for (let i = 0; i < Number(words[0]); i++) {
                    const previous = scramble[i - 1]?.letter;
                    const before = scramble[i - 2]?.letter;
                    const usable = [...faces].filter(face => face !== previous
                        && !(before !== undefined && previous !== undefined
                            && axis(before) === axis(previous) && axis(face) === axis(previous)));
                    const letter = usable[next() % usable.length];
                    const amount = [1, 3, 2][next() % 3];
                    scramble.push({ letter, amount });
                }
                this.apply(scramble);
                this.output.push('scramble ' + scramble.map(moveText).join(' '));
                break;
            }
            case 'APPLY': this.apply(moves); this.output.push(`applied ${moves.length}`); break;
            case 'DEFINE': this.macros.set(words[0], [...moves]); this.output.push(`defined ${words[0]} ${moves.length}`); break;
            case 'INVERT': this.output.push('inverse ' + sequenceText(inverse(moves))); break;
            case 'SIMPLIFY': this.output.push('simplified ' + sequenceText(simplify(moves))); break;
            case 'UNROTATE': this.output.push('unrotated ' + sequenceText(unrotate(moves))); break;
            case 'ROTATE': { const rotation = effect(basicSequence(words[0])); this.output.push('rotated ' + sequenceText(moves.map(move => conjugate(move, rotation)))); break; }
            case 'MIRROR': {
                const mirrorAxis = words[0] === 'LR' ? 'x' : words[0] === 'UD' ? 'y' : 'z';
                const opposites = {
                    R: 'L', L: 'R', r: 'l', l: 'r', U: 'D', D: 'U', u: 'd', d: 'u',
                    F: 'B', B: 'F', f: 'b', b: 'f',
                };
                const mirrored = moves.map(move => axis(move.letter) !== mirrorAxis
                    ? { letter: move.letter, amount: 4 - move.amount }
                    : Object.hasOwn(opposites, move.letter)
                        ? { letter: opposites[move.letter], amount: 4 - move.amount } : move);
                this.output.push('mirror ' + sequenceText(mirrored));
                break;
            }
            case 'METRICS': {
                let htm = 0; let qtm = 0; let stm = 0;
                for (const move of moves) {
                    if ('xyz'.includes(move.letter)) continue;
                    const weight = 'MES'.includes(move.letter) ? 2 : 1;
                    htm += weight; qtm += weight * (move.amount === 2 ? 2 : 1); stm++;
                }
                this.output.push(`metrics htm ${htm} qtm ${qtm} stm ${stm} etm ${moves.length}`);
                break;
            }
            case 'ORDER': this.output.push(`order ${order(effect(moves))}`); break;
            case 'CYCLES': { const state = applyPermutation(solvedState(), effect(moves)); this.output.push('corners ' + cycles(state, cornerNames, cornerIndices), 'edges ' + cycles(state, edgeNames, edgeIndices), 'centers ' + cycles(state, [...faces], centerIndices)); break; }
            case 'UNTIL': { const permutation = effect(moves); let state = this.state; let found = 0; for (let i = 1; i <= order(permutation); i++) { state = applyPermutation(state, permutation); if (mismatch(state) === 0) { found = i; break; } } this.output.push(found === 0 ? 'until never' : `until ${found}`); break; }
        }
    }
    run(lines) {
        for (const line of lines.slice(1, Number(lines[0]) + 1)) {
            try { this.execute(line); } catch (error) { this.output.push(`error: ${(error).message}`); }
        }
    }
}
const cube = new Cube();
cube.run(fs.readFileSync(0, 'utf8').split('\n'));
process.stdout.write(cube.output.join('\n') + '\n');
