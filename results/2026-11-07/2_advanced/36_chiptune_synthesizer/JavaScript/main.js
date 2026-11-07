'use strict';

const fs = require('node:fs');
const { readSong, noteName } = require('./song_parser');
const { frequency, transpose, oscillation, envelope } = require('./instruments');
const { samplesPerTick, nextRow, reachableRows } = require('./sequencer');
const { generate, fadeOut } = require('./mixer');
const { hex1, hex2, adler32, statistics, hexDump } = require('./report');
const EFFECTS = ['0', '1', '2', '3', '4', '5', '6', '7', 'A', 'B', 'C', 'D', 'E1', 'E2', 'E9', 'EA', 'EB', 'EC', 'ED', 'EE', 'F', 'P', 'Q', 'R', 'V'];
const KEY_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const KEY_WEIGHTS = [[64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29], [64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32]];
const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
const pad = (value, width) => String(value).padStart(width, ' ');
const address = (position, row) => hex2(position) + ':' + hex2(row);

function newChannel() {
    return { instrument: null, note: null, base: 0, target: 0, portamento: 0, slide: 0, detune: 0,
        vibratoSpeed: 0, vibratoDepth: 0, vibratoPosition: 0, tremoloSpeed: 0, tremoloDepth: 0, tremoloPosition: 0,
        volume: 15, mode: 0, phase: 0, register: 1, age: 0, keyedOff: false, offAge: 0, offEnvelope: 0,
        envelope: 0, outputFrequency: 0, outputVolume: 0, amplitude: 0, increment: 0, effect: null, cell: null,
        sounding: false, activeRecord: null, counters: { notes: 0, retriggers: 0, cuts: 0, active: 0, audible: 0 } };
}

function keyOff(channel) {
    channel.offAge = channel.age;
    channel.offEnvelope = channel.envelope;
    channel.keyedOff = true;
}

function computeOutput(channel, tick, rate) {
    channel.sounding = channel.note !== null;
    if (!channel.sounding) return;
    const effect = channel.effect;
    const instrument = channel.instrument;
    let semitones = 0;
    if (effect?.name === '0') semitones = tick % 3 === 1 ? effect.x : tick % 3 === 2 ? effect.y : 0;
    if (instrument.arpeggio) semitones += instrument.arpeggio[channel.age % instrument.arpeggio.length];
    let output = transpose(channel.base, semitones) + channel.detune;
    if (effect?.name === '4' || effect?.name === '6') output += oscillation(channel.vibratoPosition, channel.vibratoDepth, 4);
    if (instrument.vibrato) {
        const [delay, speed, depth] = instrument.vibrato;
        if (channel.age >= delay) output += oscillation((channel.age - delay) * speed % 64, depth, 4);
    }
    channel.outputFrequency = clamp(output, 1000, 50 * rate);
    channel.envelope = envelope(channel);
    channel.outputVolume = effect?.name === '7'
        ? clamp(channel.volume + oscillation(channel.tremoloPosition, channel.tremoloDepth, 255), 0, 15) : channel.volume;
    channel.amplitude = channel.envelope * channel.outputVolume;
    channel.increment = Math.floor(channel.outputFrequency * 65536 / (100 * rate));
}

function approach(channel, step) {
    channel.base = channel.base < channel.target ? Math.min(channel.base + step, channel.target) : Math.max(channel.base - step, channel.target);
}

class Player {
    constructor(song, settings) {
        this.song = song;
        this.settings = settings;
        this.channels = Array.from({ length: 4 }, newChannel);
        this.samples = [];
        this.lanes = Array.from({ length: 4 }, () => []);
        this.records = [];
        this.warnings = [];
        this.rows = [];
        this.log = [];
        this.visits = new Map();
        this.effectCounts = new Map();
        this.instrumentTicks = new Map([...song.instruments.keys()].map(number => [number, 0]));
        this.speed = song.speed;
        this.tempo = song.tempo;
        this.position = 0;
        this.row = 0;
        this.ticks = 0;
        this.clipped = 0;
        this.ending = null;
    }

    warn(channel, message) { this.warnings.push(`warning ${address(this.position, this.row)} ch${channel + 1} ${message}`); }

    closeRecord(channel, reason) {
        if (channel.activeRecord === null) return;
        channel.activeRecord.length = this.samples.length - channel.activeRecord.start;
        channel.activeRecord.reason = reason;
        channel.activeRecord = null;
    }

    noteOn(channel, index, note) {
        this.closeRecord(channel, 'next');
        channel.note = note;
        channel.base = channel.target = frequency(note);
        channel.phase = channel.age = channel.vibratoPosition = channel.tremoloPosition = 0;
        channel.keyedOff = false;
        const record = { serial: this.records.length + 1, channel: index, position: this.position, row: this.row,
            instrument: channel.instrument.number, note, start: this.samples.length, release: null };
        this.records.push(record);
        channel.activeRecord = record;
        channel.counters.notes++;
    }

    cellContent(channel, index, portamento) {
        const cell = channel.cell;
        if (cell.instrument !== null) {
            const instrument = this.song.instruments.get(cell.instrument);
            if (!instrument) this.warn(index, 'undefined instrument ' + hex2(cell.instrument));
            else { channel.instrument = instrument; channel.volume = 15; channel.mode = instrument.mode; }
        }
        if (cell.volume !== null) channel.volume = cell.volume;
        if (cell.note === 'OFF') {
            if (channel.note !== null && !channel.keyedOff) {
                keyOff(channel);
                channel.activeRecord.release = this.samples.length - channel.activeRecord.start;
            } else this.warn(index, 'key off without note');
        } else if (cell.note !== null) {
            if (channel.instrument === null) this.warn(index, 'note without instrument');
            else if (portamento && channel.note !== null) { channel.target = frequency(cell.note); channel.note = cell.note; }
            else {
                if (portamento) this.warn(index, 'portamento without note');
                this.noteOn(channel, index, cell.note);
            }
        }
    }

    tickZero(channel, index) {
        const effect = channel.effect;
        if (effect === null) return;
        const { name, argument, x, y } = effect;
        if (name === '3') { if (argument > 0) channel.portamento = argument; }
        else if (name === '4') {
            if (x > 0) channel.vibratoSpeed = x;
            if (y > 0) channel.vibratoDepth = y;
        } else if (name === '7') {
            if (x > 0) channel.tremoloSpeed = x;
            if (y > 0) channel.tremoloDepth = y;
        } else if (name === 'C') channel.volume = Math.min(argument, 15);
        else if (name === 'E1') channel.base = clamp(channel.base + 10 * argument, 1000, 50 * this.song.rate);
        else if (name === 'E2') channel.base = clamp(channel.base - 10 * argument, 1000, 50 * this.song.rate);
        else if (name === 'EA') channel.volume = Math.min(channel.volume + argument, 15);
        else if (name === 'EB') channel.volume = Math.max(channel.volume - argument, 0);
        else if (name === 'EE') this.delay = argument;
        else if (name === 'F') {
            if (argument >= 1 && argument <= 31) this.speed = argument;
            else if (argument >= 32) this.tempo = argument;
        } else if (name === 'P') channel.detune = argument - 128;
        else if (name === 'Q' || name === 'R') {
            if (channel.note === null) this.warn(index, 'slide without note');
            else {
                channel.note = name === 'Q' ? Math.min(channel.note + y, 95) : Math.max(channel.note - y, 12);
                channel.target = frequency(channel.note);
                channel.slide = 2 * x + 1;
            }
        } else if (name === 'V') {
            const wave = channel.instrument?.wave;
            if ((wave === 'PULSE' && argument <= 3) || (wave === 'NOISE' && argument <= 1)) channel.mode = argument;
            else this.warn(index, 'invalid mode ' + hex2(argument));
        }
    }

    startRow(cells) {
        this.delay = 0;
        for (let index = 0; index < 4; index++) {
            const channel = this.channels[index];
            channel.cell = cells[index];
            channel.effect = cells[index].effect;
            channel.slide = 0;
            const effect = channel.effect;
            if (effect) this.effectCounts.set(effect.name, (this.effectCounts.get(effect.name) ?? 0) + 1);
            if (!(effect?.name === 'ED' && effect.argument >= 1)) this.cellContent(channel, index, effect?.name === '3' || effect?.name === '5');
            this.tickZero(channel, index);
        }
        const ticks = this.speed * (1 + this.delay);
        for (let index = 0; index < 4; index++) {
            const effect = this.channels[index].effect;
            if (effect?.name === 'EC' && effect.argument >= ticks) this.warn(index, 'cut beyond row');
            if (effect?.name === 'ED' && effect.argument >= ticks) this.warn(index, 'delay beyond row');
        }
        return ticks;
    }

    tickEffect(channel) {
        const effect = channel.effect;
        if (!effect) return;
        const { name, argument, x, y } = effect;
        if (name === '1') channel.base = clamp(channel.base + 10 * argument, 1000, 50 * this.song.rate);
        else if (name === '2') channel.base = clamp(channel.base - 10 * argument, 1000, 50 * this.song.rate);
        else if (name === '3' || name === '5') approach(channel, 10 * channel.portamento);
        else if ((name === 'Q' || name === 'R') && channel.slide !== 0) approach(channel, 10 * channel.slide);
        if (name === '5' || name === '6' || name === 'A') channel.volume = clamp(channel.volume + x - y, 0, 15);
    }

    processTick(tick) {
        for (let index = 0; index < 4; index++) {
            const channel = this.channels[index];
            if (channel.note !== null && channel.age >= 1 && channel.instrument.sweep !== 0)
                channel.base = clamp(channel.base + 10 * channel.instrument.sweep, 1000, 50 * this.song.rate);
            if (tick >= 1) this.tickEffect(channel);
            const effect = channel.effect;
            if (effect?.name === 'ED' && effect.argument >= 1 && tick === effect.argument) this.cellContent(channel, index, false);
            if (effect?.name === 'E9' && effect.argument >= 1 && tick >= 1 && tick % effect.argument === 0 && channel.note !== null) {
                channel.phase = channel.age = 0;
                channel.keyedOff = false;
                channel.counters.retriggers++;
            }
            if (effect?.name === 'EC' && tick === effect.argument && channel.note !== null) {
                this.closeRecord(channel, 'cut');
                channel.note = null;
                channel.counters.cuts++;
            }
            computeOutput(channel, tick, this.song.rate);
            if (channel.sounding) {
                channel.counters.active++;
                if (channel.amplitude > 0) channel.counters.audible++;
                const number = channel.instrument.number;
                this.instrumentTicks.set(number, this.instrumentTicks.get(number) + 1);
            }
        }
    }

    rowLine(record) {
        const channels = this.channels.map(channel => {
            const effect = channel.effect?.text ?? '...';
            return channel.note === null ? `--- --       - - ${hex1(channel.volume)} ${effect}`
                : `${noteName(channel.note)} ${hex2(channel.instrument.number)} ${pad(channel.outputFrequency, 7)} ${hex1(channel.envelope)} ${hex1(channel.outputVolume)} ${effect}`;
        });
        return `${hex2(record.position)} ${hex2(record.pattern)} ${hex2(record.row)} ${pad(record.start, 7)} ${pad(record.speed, 2)} ${pad(record.tempo, 3)} | ${channels.join(' | ')}`;
    }

    tickLine(tick) {
        const channels = this.channels.map(channel => channel.sounding
            ? `${pad(channel.outputFrequency, 7)} ${pad(channel.increment, 5)} ${hex1(channel.envelope)}${hex1(channel.outputVolume)}`
            : '      -     - --');
        return `  tick ${pad(tick, 3)} ${pad(this.samples.length, 7)} | ${channels.join(' | ')}`;
    }

    play() {
        while (this.ending === null) {
            const pattern = this.song.order[this.position];
            const cells = this.song.patterns.get(pattern)[this.row];
            const rowTicks = this.startRow(cells);
            const record = { position: this.position, pattern, row: this.row, start: this.samples.length, speed: this.speed, tempo: this.tempo };
            this.rows.push(record);
            const key = this.position + ',' + this.row;
            if (!this.visits.has(key)) this.visits.set(key, { count: 0, start: record.start });
            this.visits.get(key).count++;
            const perTick = samplesPerTick(this.song.rate, this.tempo);
            for (let tick = 0; tick < rowTicks; tick++) {
                this.processTick(tick);
                if (tick === 0) { record.notes = this.channels.map(channel => channel.note); this.log.push(this.rowLine(record)); }
                if (this.settings.traces.has(key)) this.log.push(this.tickLine(tick));
                const count = Math.min(perTick, this.settings.maximum - this.samples.length);
                this.clipped += generate(this.channels, count, this.song.gain, this.settings.mute, this.samples, this.lanes);
                this.ticks++;
                for (const channel of this.channels) {
                    if (channel.note !== null) channel.age++;
                    if (channel.effect?.name === '4' || channel.effect?.name === '6') channel.vibratoPosition = (channel.vibratoPosition + channel.vibratoSpeed) % 64;
                    if (channel.effect?.name === '7') channel.tremoloPosition = (channel.tremoloPosition + channel.tremoloSpeed) % 64;
                }
                if (this.samples.length === this.settings.maximum) { this.ending = { reason: 'limit' }; break; }
            }
            if (this.ending !== null) break;
            const next = nextRow(this.song, this.position, this.row);
            if (next.reason) this.ending = next;
            else {
                const visit = this.visits.get(next.position + ',' + next.row);
                if (visit && visit.count >= this.settings.loops) this.ending = { ...next, reason: 'loop', start: visit.start };
                else { this.position = next.position; this.row = next.row; }
            }
        }
        for (const channel of this.channels) this.closeRecord(channel, 'end');
        if ((this.ending.reason === 'limit' || this.ending.reason === 'loop') && this.settings.fade > 0) fadeOut(this.samples, this.settings.fade);
    }
}

function noteRange(records) {
    if (records.length === 0) return 'none';
    let low = 95;
    let high = 12;
    for (const record of records) { low = Math.min(low, record.note); high = Math.max(high, record.note); }
    return noteName(low) + '..' + noteName(high);
}

function noteLines(player) {
    return player.records.map(record => {
        const lane = player.lanes[record.channel];
        let peak = 0;
        let cycles = 0;
        for (let i = record.start; i < record.start + record.length; i++) {
            peak = Math.max(peak, Math.abs(lane[i]));
            if (i > record.start && lane[i - 1] < 0 && lane[i] >= 0) cycles++;
        }
        return `${pad(record.serial, 4)} ch=${record.channel + 1} at=${address(record.position, record.row)} ins=${hex2(record.instrument)} note=${noteName(record.note)} start=${record.start} length=${record.length} release=${record.release ?? '-'} end=${record.reason} peak=${peak} cycles=${cycles}`;
    });
}

function rollLines(player) {
    const [start, count] = player.settings.roll;
    const rows = player.rows.slice(start, start + count);
    const pitches = [...new Set(rows.flatMap(row => row.notes.filter(note => note !== null)))].sort((a, b) => b - a);
    const lines = [`ROLL start=${start} rows=${rows.length} pitches=${pitches.length}`];
    for (const pitch of pitches) {
        const columns = rows.map(row => {
            const channels = row.notes.map((note, index) => note === pitch ? String(index + 1) : '').filter(Boolean);
            return channels.length === 0 ? ' ' : channels.length === 1 ? channels[0] : '*';
        });
        lines.push(`${noteName(pitch)} |${columns.join('')}|`);
    }
    lines.push('    +' + rows.map((_, index) => index % 16 === 0 ? '+' : '-').join('') + '+');
    return lines;
}

function statsLines(player) {
    const { song, samples, rows, records, ending } = player;
    const instruments = [...song.instruments.values()].sort((a, b) => a.number - b.number);
    const patterns = [...song.patterns.keys()].sort((a, b) => a - b);
    const mix = statistics(samples);
    const end = ending.reason === 'stop' || ending.reason === 'loop'
        ? `${ending.reason} order=${hex2(ending.position)} row=${hex2(ending.row)}` : ending.reason;
    const lines = [`title=${song.title}`, `rate=${song.rate}`, `samples=${samples.length}`,
        `duration_ms=${Math.floor(samples.length * 1000 / song.rate)}`, `end=${end}`,
        `loop_start=${ending.reason === 'loop' ? ending.start : '-'}`,
        `loop_length=${ending.reason === 'loop' ? samples.length - ending.start : '-'}`,
        `rows=${rows.length}`, `ticks=${player.ticks}`, `clipped=${player.clipped}`,
        `peak=${mix.peak}`, `min=${mix.minimum}`, `max=${mix.maximum}`, `rms=${mix.rms}`,
        `zero_crossings=${mix.crossings}`, `adler32=${adler32(samples)}`];
    lines.push('path ' + rows.filter((row, index) => index === 0 || rows[index - 1].position !== row.position).map(row => hex2(row.position)).join(' '));
    rows.forEach((row, index) => {
        if (index === 0 || row.speed !== rows[index - 1].speed || row.tempo !== rows[index - 1].tempo)
            lines.push(`timing sample=${row.start} order=${hex2(row.position)} row=${hex2(row.row)} speed=${row.speed} tempo=${row.tempo}`);
    });
    player.channels.forEach((channel, index) => {
        const { notes, retriggers, cuts, active, audible } = channel.counters;
        const lane = statistics(player.lanes[index], 0);
        lines.push(`channel ${index + 1} notes=${notes} retriggers=${retriggers} cuts=${cuts} active=${active} audible=${audible} peak=${lane.peak} rms=${lane.rms}`);
    });
    for (const instrument of instruments) {
        const selected = records.filter(record => record.instrument === instrument.number);
        const average = selected.length ? Math.floor(selected.reduce((sum, record) => sum + record.length, 0) / selected.length) : '-';
        lines.push(`instrument ${hex2(instrument.number)} ${instrument.name} ${instrument.wave} notes=${selected.length} ticks=${player.instrumentTicks.get(instrument.number)} range=${noteRange(selected)} average=${average}`);
    }
    for (const pattern of patterns) {
        const contents = song.patterns.get(pattern);
        const populated = contents.filter(cells => cells.some(cell => cell.note !== null || cell.instrument !== null || cell.volume !== null || cell.effect !== null)).length;
        const notes = contents.reduce((sum, cells) => sum + cells.filter(cell => cell.note !== null).length, 0);
        lines.push(`pattern ${hex2(pattern)} rows=${populated} notes=${notes} orders=${song.order.filter(number => number === pattern).length}`);
    }
    const reachable = reachableRows(song);
    song.order.forEach((pattern, position) => {
        const played = rows.filter(row => row.position === position);
        const dead = song.patterns.get(pattern).filter((cells, row) => !reachable.has(position + ',' + row) && cells.some(cell => cell.note !== null)).length;
        lines.push(`order ${hex2(position)} pattern=${hex2(pattern)} rows=${played.length} first=${played[0]?.start ?? '-'} dead=${dead}`);
    });
    const notes = [...new Set(records.map(record => record.note))].sort((a, b) => a - b);
    for (const note of notes) lines.push(`note ${noteName(note)} count=${records.filter(record => record.note === note).length}`);
    const effects = EFFECTS.filter(name => player.effectCounts.has(name)).map(name => `${name}=${player.effectCounts.get(name)}`);
    lines.push('effects ' + (effects.length ? effects.join(' ') : 'none'));
    const numbers = values => values.length ? values.map(hex2).join(' ') : 'none';
    lines.push('unused_instruments=' + numbers(instruments.filter(instrument => !records.some(record => record.instrument === instrument.number)).map(instrument => instrument.number)));
    lines.push('unused_patterns=' + numbers(patterns.filter(pattern => !song.order.includes(pattern))));
    lines.push('unreached_orders=' + numbers(song.order.map((_, position) => position).filter(position => !rows.some(row => row.position === position))));
    const durations = Array(12).fill(0);
    for (const record of records) if (song.instruments.get(record.instrument).wave !== 'NOISE') durations[record.note % 12] += record.length;
    lines.push('pitch_classes ' + KEY_NAMES.map((name, index) => `${name}=${durations[index]}`).join(' '));
    const keys = KEY_WEIGHTS.flatMap((weights, mode) => KEY_NAMES.map((name, tonic) => ({
        name: name + (mode === 0 ? ' major' : ' minor'), order: mode * 12 + tonic,
        score: durations.reduce((sum, duration, pitch) => sum + weights[(pitch - tonic + 12) % 12] * duration, 0)
    }))).sort((a, b) => b.score - a.score || a.order - b.order);
    lines.push(`key=${keys[0].name} score=${keys[0].score} runner_up=${keys[1].name} score=${keys[1].score}`);
    player.channels.forEach((_, index) => {
        const selected = records.filter(record => record.channel === index);
        lines.push(`usage ch${index + 1} range=${noteRange(selected)}` + instruments.map(instrument =>
            ` ${hex2(instrument.number)}=${selected.filter(record => record.instrument === instrument.number).length}`).join(''));
    });
    lines.push(...player.warnings);
    return lines;
}

function plot(values, low, high, middle, height, width) {
    const rowOf = value => Math.floor((2 * (high - value) * (height - 1) + high - low) / (2 * (high - low)));
    const middleRow = rowOf(middle);
    const columns = [];
    for (let column = 0; column < width; column++) {
        const start = Math.floor(column * values.length / width);
        const end = Math.floor((column + 1) * values.length / width);
        let bottom = values[start];
        let top = values[start];
        for (let i = start + 1; i < end; i++) { bottom = Math.min(bottom, values[i]); top = Math.max(top, values[i]); }
        columns.push([rowOf(top), rowOf(bottom)]);
    }
    return Array.from({ length: height }, (_, row) => {
        const label = row === 0 ? high : row === middleRow ? middle : row === height - 1 ? low : '';
        const cells = columns.map(([top, bottom]) => row >= top && row <= bottom ? '#' : row === middleRow ? '-' : ' ');
        return `${pad(label, 5)} |${cells.join('')}|`;
    });
}

function waveformLines(player) {
    const [start, length, width, height, scope] = player.settings.window;
    const axis = '      +' + Array.from({ length: width }, (_, column) => column % 10 === 0 ? '+' : '-').join('') + '+';
    let milliseconds = '    ms';
    for (let column = 0; column < width; column += 10) {
        const value = Math.floor((start + Math.floor(column * length / width)) * 1000 / player.song.rate);
        milliseconds = milliseconds.padEnd(7 + column, ' ') + value;
    }
    const lines = [`MIX start=${start} length=${length} width=${width} height=${height}`,
        ...plot(player.samples.slice(start, start + length), 0, 255, 128, height, width), axis, milliseconds];
    for (let index = 0; index < 4; index++) lines.push(`CHANNEL ${index + 1}`,
        ...plot(player.lanes[index].slice(start, start + length), -3375, 3375, 0, scope, width));
    lines.push(axis, milliseconds);
    return lines;
}

function previewLines(song, settings) {
    const lines = [];
    const instruments = [...song.instruments.values()].sort((a, b) => a.number - b.number);
    const perTick = samplesPerTick(song.rate, song.tempo);
    for (const instrument of instruments) {
        const channel = newChannel();
        channel.instrument = instrument;
        channel.mode = instrument.mode;
        channel.note = settings.preview.note;
        channel.base = channel.target = frequency(channel.note);
        const samples = [];
        const envelopes = [];
        const frequencies = [];
        for (let tick = 0; tick < settings.preview.ticks; tick++) {
            channel.age = tick;
            if (tick === settings.preview.release) keyOff(channel);
            if (tick >= 1 && instrument.sweep !== 0) channel.base = clamp(channel.base + 10 * instrument.sweep, 1000, 50 * song.rate);
            computeOutput(channel, tick, song.rate);
            envelopes.push(hex1(channel.envelope));
            frequencies.push(channel.outputFrequency);
            generate([channel], perTick, song.gain, [0], samples);
        }
        const stats = statistics(samples);
        lines.push(`instrument ${hex2(instrument.number)} ${instrument.name} wave=${instrument.wave} samples=${samples.length} peak=${stats.peak} rms=${stats.rms} adler32=${adler32(samples)}`,
            '  env ' + envelopes.join(''), '  freq ' + frequencies.join(' '));
    }
    return lines;
}

function main() {
    const { song, settings } = readSong();
    const player = new Player(song, settings);
    player.play();
    const outputs = new Map([
        ['samples.txt', hexDump(player.samples)], ['channel_log.txt', player.log], ['notes.txt', noteLines(player)],
        ['roll.txt', rollLines(player)], ['stats.txt', statsLines(player)], ['waveform.txt', waveformLines(player)],
        ['instruments.txt', previewLines(song, settings)]
    ]);
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of outputs) fs.writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

if (require.main === module) main();
