'use strict';

const fs = require('node:fs');
const { splitTime } = require('./day_rules');
const two = value => String(value).padStart(2, '0');

function localTime(value) {
    const t = splitTime(value);
    return `${String(t.year).padStart(4, '0')}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}:${two(t.second)}`;
}

const utc = value => localTime(value) + 'Z';

function offset(value) {
    const absolute = Math.abs(value);
    return (value < 0 ? '-' : '+') + two(Math.floor(absolute / 3600)) + ':' + two(Math.floor(absolute % 3600 / 60))
        + (absolute % 60 === 0 ? '' : ':' + two(absolute % 60));
}

function duration(value) {
    const absolute = Math.abs(value);
    return (value < 0 ? '-' : '') + Math.floor(absolute / 3600) + ':' + two(Math.floor(absolute % 3600 / 60)) + ':' + two(absolute % 60);
}

function clock(value) {
    return Math.floor(value / 3600) + ':' + two(Math.floor(value % 3600 / 60)) + (value % 60 === 0 ? '' : ':' + two(value % 60));
}

const state = period => `${offset(period.offset)} ${period.dst ? 'DST' : 'STD'} ${period.abbreviation}`;
const change = transition => `${utc(transition.time)} ${state(transition.before)} -> ${state(transition.after)}`;

function writeLines(name, lines) {
    fs.writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

function writeBlocks(name, blocks) {
    fs.writeFileSync('output/' + name, blocks.length ? blocks.map(lines => lines.join('\n')).join('\n\n') + '\n' : '', 'ascii');
}

module.exports = { localTime, utc, offset, duration, clock, state, change, writeLines, writeBlocks };
