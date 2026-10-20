import { readFileSync } from 'node:fs';

const channelTypes = ['NOTE_OFF', 'NOTE_ON', 'POLY_PRESSURE', 'CONTROL', 'PROGRAM', 'CHANNEL_PRESSURE', 'PITCH_BEND'];
const textTypes = ['TEXT_EVENT', 'COPYRIGHT', 'TRACK_NAME', 'INSTRUMENT_NAME', 'LYRIC', 'MARKER', 'CUE_POINT'];
const metaTypes = new Map([[0, 'SEQUENCE_NUMBER'], [32, 'CHANNEL_PREFIX'], [47, 'END_OF_TRACK'], [81, 'TEMPO'], [84, 'SMPTE_OFFSET'], [88, 'TIME_SIGNATURE'], [89, 'KEY_SIGNATURE'], [127, 'SEQUENCER_SPECIFIC']]);
textTypes.forEach((t, i) => metaTypes.set(i + 1, t));
const noteNames = Array.from({ length: 128 }, (_, n) => ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][n % 12] + (Math.floor(n / 12) - 1));
const keys = [ ['Cb', 'Gb', 'Db', 'Ab', 'Eb', 'Bb', 'F', 'C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#'], ['Ab', 'Eb', 'Bb', 'F', 'C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#', 'G#', 'D#', 'A#'] ];
const output = [];
const emit = (s) => { output.push(s); };
const hex = (n, width = 2) => n.toString(16).toUpperCase().padStart(width, '0');
const be = (n, size) => Array.from({ length: size }, (_, i) => Math.floor(n / 256 ** (size - 1 - i)) % 256);
const integer = (a, low, high) => /^-?(0|[1-9][0-9]*)$/.test(a) && Number(a) >= low && Number(a) <= high;
const value = (e) => e.data.reduce((v, n) => v * 256 + n, 0);
const event = (tick, type, data = [], ch = 0, meta = -1) => ({ tick, type, data, ch, meta });
const globalEvents = (s) => s.tracks.flatMap((track, t) => track.map((event, i) => ({ event, track: t, order: i }))).sort((a, b) => a.event.tick - b.event.tick || a.track - b.track || a.order - b.order);
const count = (s) => s.tracks.reduce((n, t) => n + t.length, 0);
const length = (s) => s.tracks.reduce((n, t) => Math.max(n, t[t.length - 1].tick), 0);
const description = (s) => `format ${s.format} tracks ${s.tracks.length} division ${s.division} events ${count(s)}`;
const isOn = (e) => e.type === 'NOTE_ON' && e.data[1] > 0;
const isOff = (e) => e.type === 'NOTE_OFF' || (e.type === 'NOTE_ON' && e.data[1] === 0);
function fields(e) {
    const d = e.data;
    if (channelTypes.includes(e.type)) {
        if (['NOTE_ON', 'NOTE_OFF', 'POLY_PRESSURE'].includes(e.type)) return `${e.ch} ${noteNames[d[0]]} ${d[1]}`;
        if (e.type === 'PITCH_BEND') return `${e.ch} ${d[0] + 128 * d[1] - 8192}`;
        return e.ch + ' ' + d.join(' ');
    }
    if (textTypes.includes(e.type)) return '"' + d.map(n => String.fromCharCode(n)).join('') + '"';
    switch (e.type) {
        case 'SEQUENCE_NUMBER': case 'TEMPO': return String(value(e));
        case 'CHANNEL_PREFIX': return String(d[0] + 1);
        case 'END_OF_TRACK': return '';
        case 'SMPTE_OFFSET': return d.join(' ');
        case 'TIME_SIGNATURE': return `${d[0]}/${2 ** d[1]} ${d[2]} ${d[3]}`;
        case 'KEY_SIGNATURE': {
            const sf = d[0] > 127 ? d[0] - 256 : d[0];
            return keys[d[1]][sf + 7] + (d[1] ? ' minor' : ' major');
        }
        default: return (e.type === 'META' ? hex(e.meta) + ' ' : '') + d.length + (d.length ? ' ' + d.map(n => hex(n)).join('') : '');
    }
}
const line = (e, track) => `${e.tick} ${track} ${e.type}${fields(e) ? ' ' + fields(e) : ''}`;
function parseHex(bytes) {
    let pos = 0;
    const fail = (reason, at) => { throw new Error(`byte ${at}: ${reason}`); };
    const readBE = (start, n) => bytes.slice(start, start + n).reduce((v, b) => 256 * v + b, 0);
    function chunk(id) {
        const p = pos;
        if (bytes.length - p < 8) fail('truncated chunk', p);
        if (bytes.slice(p, p + 4).map(n => String.fromCharCode(n)).join('') !== id) fail('bad chunk id', p);
        const size = readBE(p + 4, 4), end = p + 8 + size;
        if (end > bytes.length) fail('truncated chunk', p);
        pos = p + 8;
        return { start: pos, end, size };
    }
    const header = chunk('MThd');
    if (header.size !== 6) fail('bad header length', 4);
    const format = readBE(8, 2), tracks = readBE(10, 2), division = readBE(12, 2);
    if (format > 2) fail('bad format', 8);
    if (!tracks || (format === 0 && tracks !== 1)) fail('bad track count', 10);
    if (division >= 32768) fail('smpte timing not supported', 12);
    if (!division) fail('bad division', 12);
    pos = 14;
    const song = { format, division, tracks: [] };
    for (let t = 0; t < tracks; t++) {
        if (pos === bytes.length) fail('missing track', bytes.length);
        const trackChunk = chunk('MTrk'), track = [];
        let tick = 0, running = 0, eventStart = pos;
        function byte() {
            if (pos >= trackChunk.end) fail('truncated event', eventStart);
            return bytes[pos++];
        }
        function vlq() {
            const start = pos;
            let result = 0;
            for (let i = 0; i < 4; i++) {
                const b = byte(); result = result * 128 + b % 128;
                if (b < 128) return result;
            }
            return fail('variable-length value too long', start);
        }
        while (pos < trackChunk.end) {
            eventStart = pos;
            if (track.length && track[track.length - 1].type === 'END_OF_TRACK') fail('event after end of track', pos);
            tick += vlq();
            const statusPos = pos;
            let status = byte();
            if (status < 128) {
                if (!running) fail('data byte without running status', statusPos);
                pos--; status = running;
            }
            if (status < 240) {
                running = status;
                const high = Math.floor(status / 16), n = high === 12 || high === 13 ? 1 : 2, data = [];
                for (let i = 0; i < n; i++) {
                    const at = pos, b = byte();
                    if (b >= 128) fail('bad data byte', at);
                    data.push(b);
                }
                track.push(event(tick, channelTypes[high - 8], data, status % 16 + 1));
            } else if (status === 240 || status === 247 || status === 255) {
                running = 0;
                const meta = status === 255 ? byte() : -1, n = vlq();
                if (pos + n > trackChunk.end) fail('truncated event', eventStart);
                const data = bytes.slice(pos, pos + n); pos += n;
                if (status === 255) {
                    const sizes = new Map([[0, 2], [32, 1], [47, 0], [81, 3], [84, 5], [88, 4], [89, 2]]);
                    if (sizes.has(meta) && sizes.get(meta) !== n) fail('bad meta length', statusPos);
                    const sf = data[0] >= 128 ? data[0] - 256 : data[0];
                    if ((meta === 81 && data.every(x => x === 0)) || (meta === 32 && data[0] > 15) || (meta === 88 && (data[0] === 0 || data[1] > 6)) || (meta === 89 && (sf < -7 || sf > 7 || data[1] > 1))) fail('bad meta data', statusPos);
                }
                track.push(event(tick, status === 240 ? 'SYSEX' : status === 247 ? 'SYSEX_ESCAPE' : metaTypes.get(meta) ?? 'META', data, 0, meta));
            } else fail('unknown status byte', statusPos);
        }
        if (!track.length || track[track.length - 1].type !== 'END_OF_TRACK') fail('missing end of track', trackChunk.end);
        song.tracks.push(track);
    }
    if (pos !== bytes.length) fail('extra data', pos);
    return song;
}
function parseText(lines) {
    const fail = (reason, n) => { throw new Error(`line ${n}: ${reason}`); };
    const header = lines[0].split(' ');
    if (header.length !== 4 || header[0] !== 'HEADER' || !integer(header[1], 0, 2) || !integer(header[2], 1, 65535) || !integer(header[3], 1, 32767) || (header[1] === '0' && header[2] !== '1')) fail('bad header', 1);
    const song = { format: Number(header[1]), division: Number(header[3]), tracks: [[]] };
    const ntracks = Number(header[2]);
    let current = 0;
    for (let i = 1; i < lines.length; i++) {
        const words = lines[i].split(' '), tick = Number(words[0]), t = Number(words[1]), type = words[2], f = words.slice(3);
        if (!channelTypes.includes(type) && !textTypes.includes(type) && !Array.from(metaTypes.values()).includes(type) && !['SYSEX', 'SYSEX_ESCAPE', 'META'].includes(type)) fail('unknown event type', i + 1);
        const e = event(tick, type);
        let valid = false;
        const nums = (ranges) => f.length === ranges.length && f.every((s, j) => integer(s, ranges[j][0], ranges[j][1]));
        if (channelTypes.includes(type)) {
            e.ch = Number(f[0]);
            if (['NOTE_ON', 'NOTE_OFF', 'POLY_PRESSURE'].includes(type)) {
                valid = f.length === 3 && integer(f[0], 1, 16) && noteNames.includes(f[1]) && integer(f[2], 0, 127);
                e.data = [noteNames.indexOf(f[1]), Number(f[2])];
            } else if (type === 'PITCH_BEND') {
                valid = nums([[1, 16], [-8192, 8191]]);
                const n = Number(f[1]) + 8192; e.data = [n % 128, Math.floor(n / 128)];
            } else {
                valid = nums(type === 'CONTROL' ? [[1, 16], [0, 127], [0, 127]] : [[1, 16], [0, 127]]);
                e.data = f.slice(1).map(Number);
            }
        } else if (textTypes.includes(type)) {
            const text = f.join(' ');
            valid = /^"[^\"]*"$/.test(text); e.data = text.slice(1, -1).split('').map(c => c.charCodeAt(0));
        } else switch (type) {
            case 'SEQUENCE_NUMBER': valid = nums([[0, 65535]]); e.data = be(Number(f[0]), 2); break;
            case 'CHANNEL_PREFIX': valid = nums([[1, 16]]); e.data = [Number(f[0]) - 1]; break;
            case 'END_OF_TRACK': valid = !f.length; break;
            case 'TEMPO': valid = nums([[1, 16777215]]); e.data = be(Number(f[0]), 3); break;
            case 'SMPTE_OFFSET': valid = nums(Array.from({ length: 5 }, () => [0, 255])); e.data = f.map(Number); break;
            case 'TIME_SIGNATURE': {
                const signature = (f[0] ?? '').split('/');
                valid = f.length === 3 && signature.length === 2 && integer(signature[0], 1, 255) && [1, 2, 4, 8, 16, 32, 64].includes(Number(signature[1])) && integer(f[1], 0, 255) && integer(f[2], 0, 255);
                e.data = [Number(signature[0]), Math.log2(Number(signature[1])), Number(f[1]), Number(f[2])]; break;
            }
            case 'KEY_SIGNATURE': {
                const minor = f[1] === 'minor' ? 1 : 0, index = keys[minor].indexOf(f[0]);
                valid = f.length === 2 && ['major', 'minor'].includes(f[1]) && index >= 0;
                e.data = [(index - 7 + 256) % 256, minor]; break;
            }
            default: {
                const offset = type === 'META' ? 1 : 0, n = Number(f[offset]), data = f[offset + 1] ?? '';
                valid = integer(f[offset], 0, 1000000) && f.length === offset + 1 + (n ? 1 : 0) && data.length === 2 * n && /^[0-9A-F]*$/.test(data);
                if (offset) {
                    valid = valid && /^[0-9A-F]{2}$/.test(f[0]) && !metaTypes.has(parseInt(f[0], 16));
                    e.meta = parseInt(f[0], 16);
                }
                e.data = [];
                for (let j = 0; j < data.length; j += 2) e.data.push(parseInt(data.slice(j, j + 2), 16));
            }
        }
        if (!valid) fail('bad value', i + 1);
        if (t >= ntracks) fail('bad track', i + 1);
        const track = song.tracks[current], ended = track.length > 0 && track[track.length - 1].type === 'END_OF_TRACK';
        if (t < current) fail('out of order', i + 1);
        if (t > current && (!ended || t > current + 1)) fail('missing end of track', i + 1);
        if (t === current && ended) fail('event after end of track', i + 1);
        if (t === current + 1) { current++; song.tracks.push([]); }
        const dest = song.tracks[current];
        if (dest.length && tick < dest[dest.length - 1].tick) fail('out of order', i + 1);
        dest.push(e);
    }
    const last = song.tracks[current];
    if (current + 1 < ntracks || !last.length || last[last.length - 1].type !== 'END_OF_TRACK') fail('missing end of track', lines.length + 1);
    return song;
}
function pairing(s) {
    const queues = new Map(), notes = [], unmatched = [];
    const all = globalEvents(s), index = new Map();
    all.forEach((l, i) => index.set(l.event, i));
    for (const l of all) {
        const e = l.event, key = `${e.ch}/${e.data[0]}`;
        if (isOn(e)) { const q = queues.get(key) ?? []; q.push(l); queues.set(key, q); }
        else if (isOff(e)) {
            const q = queues.get(key);
            if (q?.length) notes.push({ on: q.shift(), off: l }); else unmatched.push(l);
        }
    }
    for (const q of queues.values()) for (const l of q) unmatched.push(l);
    notes.sort((a, b) => a.on.event.tick - b.on.event.tick || a.on.event.ch - b.on.event.ch || a.on.event.data[0] - b.on.event.data[0] || index.get(a.on.event) - index.get(b.on.event));
    unmatched.sort((a, b) => index.get(a.event) - index.get(b.event));
    return { notes, unmatched };
}
function timing(s, tick) {
    let total = 0, last = 0, tempo = 500000, start = 0, bar = 1, nn = 4, beat = s.division;
    for (const l of globalEvents(s)) {
        const e = l.event;
        if (e.tick > tick) break;
        if (e.type === 'TEMPO') { total += (e.tick - last) * tempo; last = e.tick; tempo = value(e); }
        if (e.type === 'TIME_SIGNATURE') {
            bar += Math.ceil((e.tick - start) / (nn * beat)); start = e.tick; nn = e.data[0]; beat = Math.floor(s.division * 4 / 2 ** e.data[1]);
        }
    }
    const micros = Math.floor((total + (tick - last) * tempo) / s.division), x = tick - start;
    return { time: `${Math.floor(micros / 1000)}.${String(micros % 1000).padStart(3, '0')}`, bar: `${bar + Math.floor(x / (nn * beat))}:${Math.floor((x % (nn * beat)) / beat) + 1}:${x % beat}` };
}
let running = true, noteoffZero = false;
function encode(s) {
    function vlq(n) {
        const bytes = [n % 128]; n = Math.floor(n / 128);
        while (n) { bytes.unshift(n % 128 + 128); n = Math.floor(n / 128); }
        return bytes;
    }
    const bytes = [77, 84, 104, 100, 0, 0, 0, 6].concat(be(s.format, 2), be(s.tracks.length, 2), be(s.division, 2));
    for (const track of s.tracks) {
        let data = [], previousTick = 0, status = 0;
        for (const e of track) {
            data = data.concat(vlq(e.tick - previousTick)); previousTick = e.tick;
            if (channelTypes.includes(e.type)) {
                const zero = noteoffZero && e.type === 'NOTE_OFF';
                const next = (zero ? 144 : 128 + channelTypes.indexOf(e.type) * 16) + e.ch - 1;
                if (!running || status !== next) data.push(next);
                status = next; data = data.concat(zero ? [e.data[0], 0] : e.data);
            } else {
                status = 0;
                if (e.type === 'SYSEX' || e.type === 'SYSEX_ESCAPE') data.push(e.type === 'SYSEX' ? 240 : 247);
                else {
                    const meta = e.type === 'META' ? e.meta : Array.from(metaTypes).find(([, t]) => t === e.type)[0];
                    data.push(255, meta);
                }
                data = data.concat(vlq(e.data.length), e.data);
            }
        }
        for (const n of [77, 84, 114, 107].concat(be(data.length, 4), data)) bytes.push(n);
    }
    return bytes;
}
const songs = new Map();
function command(words) {
    const [cmd, name, ...args] = words;
    const known = ['DECODE', 'ENCODE', 'TIMING', 'NOTES', 'STATS', 'ROLL', 'TRANSPOSE', 'QUANTIZE', 'VELOCITY', 'TEMPO', 'FILTER', 'MERGE', 'SPLIT', 'COPY', 'LIST', 'RUNNING', 'NOTEOFF'];
    const fail = (reason) => { throw new Error(reason); };
    if (!known.includes(cmd)) fail('unknown command');
    if (cmd === 'LIST') {
        const sorted = Array.from(songs.keys()).sort();
        sorted.forEach(n => emit(n + ' ' + description(songs.get(n))));
        if (!sorted.length) emit('no songs'); return;
    }
    if (cmd === 'RUNNING' || cmd === 'NOTEOFF') {
        if (!(cmd === 'RUNNING' ? ['ON', 'OFF'] : ['ZERO', 'KEEP']).includes(name)) fail('bad argument');
        if (cmd === 'RUNNING') { running = name === 'ON'; emit('running ' + name.toLowerCase()); }
        else { noteoffZero = name === 'ZERO'; emit('noteoff ' + name.toLowerCase()); }
        return;
    }
    const song = songs.get(name);
    if (!song) fail('no song ' + name);
    const s = song, a = args.map(Number);
    const range = (i, lo, hi) => a[i] >= lo && a[i] <= hi;
    if ((cmd === 'TRANSPOSE' && (!range(0, -127, 127) || (args.length === 2 && !range(1, 1, 16)))) ||
        (cmd === 'QUANTIZE' && (!range(0, 1, 1000000) || !range(1, 0, 100))) ||
        (cmd === 'VELOCITY' && (!range(0, 0, 1000) || !range(1, -127, 127))) ||
        (cmd === 'TEMPO' && (!range(0, 1, 1000) || !range(1, 1, 1000))) ||
        (cmd === 'FILTER' && a.some(n => n < 1 || n > 16)) ||
        (cmd === 'ROLL' && (!range(0, 0, 10000000) || !range(1, 1, 10000000) || !range(2, 1, 10000000) || a[1] <= a[0] || Math.ceil((a[1] - a[0]) / a[2]) > 64))) fail('bad argument');
    if (['TIMING', 'STATS'].includes(cmd) && s.format === 2) fail('format 2 not supported');
    switch (cmd) {
        case 'COPY': songs.set(args[0], structuredClone(s)); emit(`copied ${name} to ${args[0]}`); break;
        case 'DECODE':
            emit(`HEADER ${s.format} ${s.tracks.length} ${s.division}`);
            s.tracks.forEach((t, i) => t.forEach(e => emit(line(e, i)))); break;
        case 'ENCODE': {
            const bytes = encode(s);
            for (let i = 0; i < bytes.length; i += 16) emit(hex(i, 4) + ': ' + bytes.slice(i, i + 16).map(n => hex(n)).join(' '));
            emit(bytes.length + ' bytes'); break;
        }
        case 'TIMING':
            for (const l of globalEvents(s)) { const t = timing(s, l.event.tick); emit(`${l.event.tick} ${l.track} ${l.event.type} ${t.time} ${t.bar}`); }
            { const t = timing(s, length(s)); emit(`end ${length(s)} ${t.time} ${t.bar}`); } break;
        case 'NOTES': {
            const p = pairing(s); emit(`notes ${p.notes.length} unmatched ${p.unmatched.length}`);
            for (const n of p.notes) emit(`${n.on.event.tick} ${n.off.event.tick - n.on.event.tick} ${n.on.event.ch} ${noteNames[n.on.event.data[0]]} ${n.on.event.data[1]}`);
            for (const l of p.unmatched) emit(`unmatched ${isOn(l.event) ? 'on' : 'off'} ${l.event.tick} ${l.track} ${l.event.ch} ${noteNames[l.event.data[0]]}`);
            break;
        }
        case 'TRANSPOSE': {
            let kept = 0; const dropped = [];
            s.tracks = s.tracks.map((track, t) => track.filter(e => {
                if (!['NOTE_ON', 'NOTE_OFF', 'POLY_PRESSURE'].includes(e.type) || (args.length === 2 && e.ch !== a[1])) return true;
                const n = e.data[0] + a[0];
                if (n < 0 || n > 127) { dropped.push(`dropped ${e.tick} ${t} ${e.type} ${e.ch} ${noteNames[e.data[0]]}`); return false; }
                e.data[0] = n; kept++; return true;
            }));
            emit(`transposed ${kept} dropped ${dropped.length}`); dropped.forEach(emit); break;
        }
        case 'QUANTIZE': {
            const p = pairing(s); let moved = 0;
            const targets = p.notes.slice();
            for (const l of p.unmatched) if (isOn(l.event)) targets.push({ on: l });
            for (const n of targets) {
                const t = n.on.event.tick, lower = Math.floor(t / a[0]) * a[0], g = t - lower <= lower + a[0] - t ? lower : lower + a[0];
                const delta = Math.floor((2 * (g - t) * a[1] + 100) / 200);
                n.on.event.tick += delta; if (n.off) n.off.event.tick += delta; if (delta) moved++;
            }
            s.tracks = s.tracks.map(t => {
                const end = t[t.length - 1], others = t.slice(0, -1).sort((a, b) => a.tick - b.tick);
                end.tick = others.reduce((n, e) => Math.max(n, e.tick), end.tick); return others.concat(end);
            });
            emit(`quantized ${targets.length} moved ${moved}`); break;
        }
        case 'VELOCITY': {
            let converted = 0, clamped = 0;
            for (const l of globalEvents(s)) if (isOn(l.event)) {
                const v = Math.floor((l.event.data[1] * a[0] + 50) / 100) + a[1]; converted++;
                if (v < 1 || v > 127) clamped++; l.event.data[1] = Math.max(1, Math.min(127, v));
            }
            emit(`velocity ${converted} clamped ${clamped}`); break;
        }
        case 'TEMPO': {
            const tempos = globalEvents(s).filter(l => l.event.type === 'TEMPO'), convert = (n) => Math.floor((2 * n * a[1] + a[0]) / (2 * a[0]));
            const values = tempos.map(l => convert(value(l.event))), insert = !tempos.some(l => l.event.tick === 0), initial = convert(500000);
            if (values.some(n => n < 1 || n > 16777215) || (insert && (initial < 1 || initial > 16777215))) fail('tempo out of range');
            tempos.forEach((l, i) => { l.event.data = be(values[i], 3); }); emit('scaled ' + tempos.length);
            if (insert) { s.tracks[0].unshift(event(0, 'TEMPO', be(initial, 3))); emit('inserted 0 0 TEMPO ' + initial); }
            break;
        }
        case 'FILTER': {
            const before = count(s); s.tracks = s.tracks.map(t => t.filter(e => !channelTypes.includes(e.type) || a.includes(e.ch)));
            emit('removed ' + (before - count(s))); break;
        }
        case 'MERGE': {
            if (s.format !== 1) fail('not format 1');
            const n = s.tracks.length, end = length(s), events = globalEvents(s).filter(l => l.event.type !== 'END_OF_TRACK').map(l => l.event);
            s.tracks = [events.concat(event(end, 'END_OF_TRACK'))]; s.format = 0; emit(`merged ${n} tracks events ${count(s)}`); break;
        }
        case 'SPLIT': {
            if (s.format !== 0) fail('not format 0');
            const end = length(s), events = s.tracks[0].slice(0, -1), channels = Array.from(new Set(events.filter(e => channelTypes.includes(e.type)).map(e => e.ch))).sort((a, b) => a - b);
            s.tracks = [events.filter(e => !channelTypes.includes(e.type))].concat(channels.map(ch => events.filter(e => channelTypes.includes(e.type) && e.ch === ch)));
            s.tracks.forEach(t => t.push(event(end, 'END_OF_TRACK'))); s.format = 1; emit(`split tracks ${s.tracks.length} events ${count(s)}`); break;
        }
        case 'STATS': {
            const p = pairing(s); emit(description(s)); emit(`notes ${p.notes.length} unmatched ${p.unmatched.length}`);
            const rangeText = (notes) => {
                let lo = 127, hi = 0;
                for (const n of notes) { lo = Math.min(lo, n.on.event.data[0]); hi = Math.max(hi, n.on.event.data[0]); }
                return `${noteNames[lo]} ${noteNames[hi]}`;
            };
            for (let ch = 1; ch <= 16; ch++) {
                const notes = p.notes.filter(n => n.on.event.ch === ch);
                if (notes.length) emit(`channel ${ch} notes ${notes.length} range ${rangeText(notes)}`);
            }
            emit('range ' + (p.notes.length ? rangeText(p.notes) : 'none'));
            emit(`length ${length(s)} ticks ${timing(s, length(s)).time} ms`);
            const changes = new Map();
            for (const n of p.notes) if (n.off.event.tick > n.on.event.tick) {
                changes.set(n.on.event.tick, (changes.get(n.on.event.tick) ?? 0) + 1);
                changes.set(n.off.event.tick, (changes.get(n.off.event.tick) ?? 0) - 1);
            }
            let active = 0, maximum = 0, at = 0;
            for (const tick of Array.from(changes.keys()).sort((a, b) => a - b)) {
                active += changes.get(tick); if (active > maximum) { maximum = active; at = tick; }
            }
            emit(maximum ? `polyphony ${maximum} at ${at}` : 'polyphony 0'); break;
        }
        case 'ROLL': {
            const notes = pairing(s).notes; let rows = 0;
            for (let pitch = 127; pitch >= 0; pitch--) {
                let cells = '';
                for (let tick = a[0]; tick < a[1]; tick += a[2]) {
                    const ns = notes.filter(n => n.on.event.data[0] === pitch);
                    cells += ns.some(n => n.on.event.tick >= tick && n.on.event.tick < tick + a[2]) ? '#' : ns.some(n => n.on.event.tick <= tick && tick < n.off.event.tick) ? '=' : '.';
                }
                if (/[^.]/.test(cells)) { emit(noteNames[pitch].padEnd(4) + ' ' + cells); rows++; }
            }
            if (!rows) emit('empty'); break;
        }
    }
}
const input = readFileSync(0, 'utf8').trimEnd().split('\n');
let cursor = 1;
for (let n = 0; n < Number(input[0]); n++) {
    const words = input[cursor++].split(' '), cmd = words[0];
    try {
        if (cmd === 'HEX' || cmd === 'TEXT') {
            const data = input.slice(cursor, cursor + Number(words[2])); cursor += Number(words[2]);
            const song = cmd === 'HEX' ? parseHex(data.join(' ').split(' ').map(s => parseInt(s, 16))) : parseText(data);
            songs.set(words[1], song); emit(`loaded ${words[1]} ${description(song)}`);
        } else command(words);
    } catch (error) { emit('error: ' + (error instanceof Error ? error.message : String(error))); }
}
process.stdout.write(output.join('\n') + '\n');
