'use strict';

const fs = require('node:fs');

class InputError extends Error {}

function wellFormedNumber(text) {
    return /^(?:0|[1-9][0-9]{0,5})$/.test(text);
}

function readDimacs(filename) {
    const lines = fs.readFileSync(filename, 'ascii').split('\n');
    const clauses = [];
    let header = null;
    let pending = [];
    for (let index = 0; index < lines.length; index++) {
        const line = lines[index];
        if (line.startsWith('c') || line.trim() === '') continue;
        const tokens = line.trim().split(/ +/);
        const number = index + 1;
        if (tokens[0] === 'p') {
            if (header !== null) throw new InputError(`duplicate header at line ${number}`);
            if (tokens.length !== 4 || tokens[1] !== 'cnf'
                || !wellFormedNumber(tokens[2]) || !wellFormedNumber(tokens[3])) {
                throw new InputError(`bad header at line ${number}`);
            }
            header = { variables: Number(tokens[2]), count: Number(tokens[3]) };
            continue;
        }
        if (header === null) throw new InputError('missing header');
        for (const token of tokens) {
            if (!/^(?:0|-?[1-9][0-9]{0,5})$/.test(token)) {
                throw new InputError(`bad token ${token} at line ${number}`);
            }
            const literal = Number(token);
            if (Math.abs(literal) > header.variables) {
                throw new InputError(`literal out of range ${token} at line ${number}`);
            }
            if (literal === 0) {
                clauses.push(pending);
                pending = [];
            } else pending.push(literal);
        }
    }
    if (header === null) throw new InputError('missing header');
    if (pending.length > 0) throw new InputError('unterminated clause');
    if (clauses.length !== header.count) {
        throw new InputError(`clause count mismatch header=${header.count} found=${clauses.length}`);
    }
    return { variables: header.variables, clauses };
}

function modelLines(model) {
    const tokens = [];
    for (let variable = 1; variable < model.length; variable++) tokens.push(model[variable] ? variable : -variable);
    tokens.push(0);
    const lines = [];
    for (let index = 0; index < tokens.length; index += 10) lines.push('v ' + tokens.slice(index, index + 10).join(' '));
    return lines;
}

module.exports = { InputError, wellFormedNumber, readDimacs, modelLines };
