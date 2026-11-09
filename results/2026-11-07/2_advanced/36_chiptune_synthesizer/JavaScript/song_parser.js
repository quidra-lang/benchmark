'use strict';

const fs = require('node:fs');
const PITCHES = ['C-', 'C#', 'D-', 'D#', 'E-', 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-'];
const noteNumber = text => 12 * Number(text[2]) + PITCHES.indexOf(text.slice(0, 2));
const noteName = number => PITCHES[number % 12] + Math.floor(number / 12);
const readLines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);

function parseCell(text) {
    const [note, instrument, volume, effectText] = text.split(' ');
    let effect = null;
    if (effectText !== '...') {
        const command = effectText[0];
        effect = { text: effectText, command, name: command === 'E' ? effectText.slice(0, 2) : command,
            argument: parseInt(command === 'E' ? effectText[2] : effectText.slice(1), 16),
            x: parseInt(effectText[1], 16), y: parseInt(effectText[2], 16) };
    }
    return { note: note === '...' ? null : note === 'OFF' ? 'OFF' : noteNumber(note),
        instrument: instrument === '..' ? null : parseInt(instrument, 16), volume: volume === '.' ? null : parseInt(volume, 16), effect };
}

function readSong() {
    const lines = readLines('song.txt').filter(line => line !== '' && !line.startsWith('#'));
    const value = index => Number(lines[index].split(' ')[1]);
    const song = { title: lines[0].slice(6), rate: value(1), speed: value(2), tempo: value(3), gain: value(4),
        instruments: new Map(), patterns: new Map(), order: [] };
    for (let i = 5; i < lines.length; i++) {
        const words = lines[i].split(' ');
        if (words[0] === 'ORDER') song.order = words.slice(1).map(value => parseInt(value, 16));
        else if (words[0] === 'INSTRUMENT') {
            const instrument = { number: parseInt(words[1], 16), name: words[2], vibrato: null, arpeggio: null, sweep: 0, mode: 0 };
            while (lines[++i] !== 'END') {
                const [name, ...attributes] = lines[i].split(' ');
                if (name === 'WAVE') {
                    instrument.wave = attributes[0];
                    if (instrument.wave === 'PULSE') instrument.mode = [12, 25, 50, 75].indexOf(Number(attributes[1]));
                    if (instrument.wave === 'NOISE') instrument.mode = Number(attributes[1] === 'SHORT');
                    if (instrument.wave === 'TABLE') instrument.table = [...attributes[1]].map(value => parseInt(value, 16));
                } else if (name === 'ENVELOPE') instrument.envelope = attributes.map(Number);
                else if (name === 'VIBRATO') instrument.vibrato = attributes.map(Number);
                else if (name === 'ARPEGGIO') instrument.arpeggio = attributes.map(Number);
                else instrument.sweep = Number(attributes[0]);
            }
            song.instruments.set(instrument.number, instrument);
        } else {
            const number = parseInt(words[1], 16);
            const rows = Array.from({ length: 64 }, () => Array.from({ length: 4 }, () => parseCell('... .. . ...')));
            while (lines[++i] !== 'END') rows[parseInt(lines[i].slice(0, 2), 16)] = lines[i].slice(3).split(' | ').map(parseCell);
            song.patterns.set(number, rows);
        }
    }
    const params = readLines('params.txt').map(line => line.split(' '));
    const settings = { maximum: Number(params[0][1]), loops: Number(params[1][1]), fade: Number(params[2][1]),
        mute: params[3].slice(1).map(Number), window: params[4].slice(1).map(Number), roll: params[5].slice(1).map(Number),
        preview: { note: noteNumber(params[6][1]), ticks: Number(params[6][2]), release: Number(params[6][3]) },
        traces: new Set(params.slice(7).map(words => parseInt(words[1], 16) + ',' + parseInt(words[2], 16))) };
    return { song, settings };
}

module.exports = { readSong, parseCell, noteNumber, noteName };
