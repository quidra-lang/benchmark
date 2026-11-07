'use strict';

const fs = require('node:fs');

const FORMS = {
    ALLOC: ['p', 'd'], PUSH: ['r'], LOAD: ['i', 'f'], POP: ['n'],
    SET: ['i', 'f', 'r'], OVERWRITE: ['i', 'r'], CHECKPOINT: ['label'],
};
const COMMANDS = Object.keys(FORMS);
const NUMBER = /^(0|[1-9][0-9]{0,3})$/;
const LABEL = /^[a-z0-9_]{1,16}$/;

function readInputs() {
    const settings = { collectors: [] };
    const configuration = fs.readFileSync('input/config.txt', 'ascii').slice(0, -1).split('\n');
    for (const line of configuration) {
        const fields = line.split(' ');
        switch (fields[0]) {
            case 'HEAP': settings.heap = Number(fields[1]); break;
            case 'COLLECTOR': {
                const collector = { name: fields[1], type: fields[2] };
                if (collector.type === 'GENERATIONAL') {
                    collector.young = Number(fields[3]);
                    collector.age = Number(fields[4]);
                }
                settings.collectors.push(collector);
                break;
            }
            case 'MAPS': settings.maps = new Set(fields.slice(1)); break;
            case 'MMU': settings.windows = fields.slice(1).map(Number); break;
            case 'WIDTH': settings.width = Number(fields[1]); break;
        }
    }
    const lines = fs.readFileSync('input/mutator.txt', 'ascii').slice(0, -1).split('\n');
    return { settings, lines };
}

function parseCommand(text, line) {
    const tokens = text.split(' ');
    const op = tokens[0];
    if (!Object.hasOwn(FORMS, op) || tokens.length !== FORMS[op].length + 1) return { reason: 'syntax' };
    const command = { op, line };
    for (let index = 0; index < FORMS[op].length; index++) {
        const name = FORMS[op][index];
        const token = tokens[index + 1];
        if (name === 'label') {
            if (!LABEL.test(token)) return { reason: 'syntax' };
            command.label = token;
        } else if (name === 'r' && token === '-') command.r = null;
        else {
            if (!NUMBER.test(token)) return { reason: 'syntax' };
            command[name] = Number(token);
        }
    }
    if (op === 'ALLOC' && (command.p > 6 || command.d > 24)) return { reason: 'range' };
    if (op === 'POP' && command.n === 0) return { reason: 'range' };
    return command;
}

module.exports = { COMMANDS, readInputs, parseCommand };
