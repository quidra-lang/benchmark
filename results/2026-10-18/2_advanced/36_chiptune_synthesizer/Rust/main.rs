mod instruments;
mod mixer;
mod report;
mod sequencer;
mod song_parser;

use instruments::{envelope, frequency, oscillation, transpose};
use song_parser::{note_name, Cell, Effect, Instrument, Params, Song};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;

#[derive(Clone)]
pub struct Channel {
    instrument: Option<i64>,
    note: Option<i64>,
    frequency: i64,
    target: i64,
    portamento: i64,
    slide: i64,
    detune: i64,
    vibrato_speed: i64,
    vibrato_depth: i64,
    vibrato_position: i64,
    tremolo_speed: i64,
    tremolo_depth: i64,
    tremolo_position: i64,
    volume: i64,
    mode: i64,
    phase: i64,
    shift: i64,
    ticks: i64,
    release: Option<(i64, i64)>,
    envelope: i64,
    output_frequency: i64,
    output_volume: i64,
    amplitude: i64,
    increment: i64,
    effect: Option<Effect>,
    record: Option<usize>,
    retriggers: usize,
    cuts: usize,
    active: usize,
    audible: usize,
}

impl Channel {
    fn new() -> Self {
        Self {
            instrument: None, note: None, frequency: 0, target: 0, portamento: 0, slide: 0,
            detune: 0, vibrato_speed: 0, vibrato_depth: 0, vibrato_position: 0,
            tremolo_speed: 0, tremolo_depth: 0, tremolo_position: 0,
            volume: 15, mode: 0, phase: 0, shift: 1, ticks: 0, release: None, envelope: 0,
            output_frequency: 0, output_volume: 0, amplitude: 0, increment: 0, effect: None,
            record: None, retriggers: 0, cuts: 0, active: 0, audible: 0,
        }
    }

    fn approach(&mut self, step: i64) {
        self.frequency = if self.frequency < self.target { (self.frequency + step).min(self.target) } else { (self.frequency - step).max(self.target) };
    }

    fn output(&mut self, instrument: &Instrument, tick: i64, rate: i64) {
        let mut semitones = 0;
        if let Some(effect) = &self.effect {
            if effect.command == b'0' {
                semitones = match tick % 3 { 1 => effect.argument / 16, 2 => effect.argument % 16, _ => 0 };
            }
        }
        if !instrument.arpeggio.is_empty() { semitones += instrument.arpeggio[self.ticks as usize % instrument.arpeggio.len()]; }
        let mut value = transpose(self.frequency, semitones) + self.detune;
        if self.effect.as_ref().is_some_and(|e| e.command == b'4' || e.command == b'6') {
            value += oscillation(self.vibrato_position, self.vibrato_depth, 4);
        }
        if let Some((delay, speed, depth)) = instrument.vibrato {
            if self.ticks >= delay { value += oscillation(((self.ticks - delay) * speed) % 64, depth, 4); }
        }
        self.output_frequency = value.clamp(1000, 50 * rate);
        self.envelope = envelope(instrument, self.ticks, self.release);
        self.output_volume = if self.effect.as_ref().is_some_and(|e| e.command == b'7') {
            (self.volume + oscillation(self.tremolo_position, self.tremolo_depth, 255)).clamp(0, 15)
        } else { self.volume };
        self.amplitude = self.envelope * self.output_volume;
        self.increment = self.output_frequency * 65536 / (100 * rate);
    }
}

struct NoteRecord {
    channel: usize,
    position: usize,
    row: usize,
    instrument: i64,
    note: i64,
    start: usize,
    end: Option<usize>,
    reason: &'static str,
    release: Option<usize>,
}

struct RowRecord {
    position: usize,
    row: usize,
    start: usize,
    speed: i64,
    tempo: i64,
    notes: [Option<i64>; 4],
}

struct Playback<'a> {
    song: &'a Song,
    params: &'a Params,
    channels: Vec<Channel>,
    records: Vec<NoteRecord>,
    rows: Vec<RowRecord>,
    log: Vec<String>,
    warnings: Vec<String>,
    samples: Vec<i64>,
    lanes: Vec<Vec<i64>>,
    effects: BTreeMap<String, usize>,
    instrument_ticks: BTreeMap<i64, usize>,
    visits: BTreeMap<(usize, usize), (usize, usize)>,
    speed: i64,
    tempo: i64,
    ticks: usize,
    clipped: usize,
    end_reason: String,
    loop_start: Option<usize>,
}

impl<'a> Playback<'a> {
    fn new(song: &'a Song, params: &'a Params) -> Self {
        Self {
            song, params, channels: (0..4).map(|_| Channel::new()).collect(), records: Vec::new(), rows: Vec::new(),
            log: Vec::new(), warnings: Vec::new(), samples: Vec::new(), lanes: vec![Vec::new(); 4], effects: BTreeMap::new(),
            instrument_ticks: BTreeMap::new(), visits: BTreeMap::new(), speed: song.speed, tempo: song.tempo,
            ticks: 0, clipped: 0, end_reason: String::new(), loop_start: None,
        }
    }

    fn warn(&mut self, position: usize, row: usize, channel: usize, message: String) {
        self.warnings.push(format!("warning {position:02X}:{row:02X} ch{} {message}", channel + 1));
    }

    fn end_record(&mut self, channel: usize, reason: &'static str) {
        if let Some(index) = self.channels[channel].record.take() {
            self.records[index].end = Some(self.samples.len());
            self.records[index].reason = reason;
        }
    }

    fn content(&mut self, channel: usize, cell: &Cell, portamento: bool, position: usize, row: usize) {
        if let Some(number) = cell.instrument {
            if let Some(instrument) = self.song.instruments.get(&number) {
                self.channels[channel].instrument = Some(number);
                self.channels[channel].volume = 15;
                self.channels[channel].mode = instrument.mode;
            } else { self.warn(position, row, channel, format!("undefined instrument {number:02X}")); }
        }
        if let Some(volume) = cell.volume { self.channels[channel].volume = volume; }
        if cell.note == Some(-1) {
            if self.channels[channel].note.is_some() && self.channels[channel].release.is_none() {
                let c = &mut self.channels[channel];
                c.release = Some((c.ticks, c.envelope));
                if let Some(index) = c.record { self.records[index].release = Some(self.samples.len() - self.records[index].start); }
            } else { self.warn(position, row, channel, "key off without note".into()); }
        } else if let Some(note) = cell.note {
            if self.channels[channel].instrument.is_none() {
                self.warn(position, row, channel, "note without instrument".into());
            } else if portamento && self.channels[channel].note.is_some() {
                self.channels[channel].target = frequency(note);
                self.channels[channel].note = Some(note);
            } else {
                if portamento { self.warn(position, row, channel, "portamento without note".into()); }
                self.end_record(channel, "next");
                let c = &mut self.channels[channel];
                c.frequency = frequency(note);
                c.target = c.frequency;
                c.phase = 0;
                c.ticks = 0;
                c.vibrato_position = 0;
                c.tremolo_position = 0;
                c.release = None;
                c.note = Some(note);
                c.record = Some(self.records.len());
                self.records.push(NoteRecord { channel, position, row, instrument: c.instrument.unwrap(), note, start: self.samples.len(), end: None, reason: "end", release: None });
            }
        }
    }

    fn effect_start(&mut self, channel: usize, effect: &Effect, position: usize, row: usize, delay: &mut i64) {
        let argument = effect.argument;
        let (x, y) = (argument / 16, argument % 16);
        let mut warning = None;
        let c = &mut self.channels[channel];
        match effect.command {
            b'3' if argument > 0 => c.portamento = argument,
            b'4' => { if x > 0 { c.vibrato_speed = x; } if y > 0 { c.vibrato_depth = y; } }
            b'7' => { if x > 0 { c.tremolo_speed = x; } if y > 0 { c.tremolo_depth = y; } }
            b'C' => c.volume = argument.min(15),
            b'E' => match effect.subcommand {
                b'1' => c.frequency = (c.frequency + 10 * argument).clamp(1000, 50 * self.song.rate),
                b'2' => c.frequency = (c.frequency - 10 * argument).clamp(1000, 50 * self.song.rate),
                b'A' => c.volume = (c.volume + argument).min(15),
                b'B' => c.volume = (c.volume - argument).max(0),
                b'E' => *delay = argument,
                _ => (),
            },
            b'F' if (1..=31).contains(&argument) => self.speed = argument,
            b'F' if argument >= 32 => self.tempo = argument,
            b'P' => c.detune = argument - 128,
            b'Q' | b'R' => {
                if let Some(note) = c.note {
                    let note = if effect.command == b'Q' { (note + y).min(95) } else { (note - y).max(12) };
                    c.note = Some(note);
                    c.target = frequency(note);
                    c.slide = 2 * x + 1;
                } else { warning = Some("slide without note".into()); }
            }
            b'V' => {
                let valid = c.instrument.is_some_and(|number| {
                    let waveform = self.song.instruments[&number].waveform.as_str();
                    (waveform == "PULSE" && argument <= 3) || (waveform == "NOISE" && argument <= 1)
                });
                if valid { c.mode = argument; } else { warning = Some(format!("invalid mode {argument:02X}")); }
            }
            _ => (),
        }
        if let Some(warning) = warning { self.warn(position, row, channel, warning); }
    }

    fn row_start(&mut self, cells: &[Cell; 4], position: usize, row: usize) -> i64 {
        let mut delay = 0;
        for (channel, cell) in cells.iter().enumerate() {
            self.channels[channel].effect = cell.effect.clone();
            self.channels[channel].slide = 0;
            if let Some(effect) = &cell.effect { *self.effects.entry(effect.name()).or_default() += 1; }
            let delayed = cell.effect.as_ref().is_some_and(|e| e.is("ED") && e.argument >= 1);
            let portamento = cell.effect.as_ref().is_some_and(|e| e.command == b'3' || e.command == b'5');
            if !delayed { self.content(channel, cell, portamento, position, row); }
            if let Some(effect) = &cell.effect { self.effect_start(channel, effect, position, row, &mut delay); }
        }
        let ticks = self.speed * (1 + delay);
        for (channel, cell) in cells.iter().enumerate() {
            if let Some(effect) = &cell.effect {
                if effect.is("EC") && effect.argument >= ticks { self.warn(position, row, channel, "cut beyond row".into()); }
                if effect.is("ED") && effect.argument >= ticks { self.warn(position, row, channel, "delay beyond row".into()); }
            }
        }
        ticks
    }

    fn tick(&mut self, cells: &[Cell; 4], tick: i64, position: usize, row: usize) {
        for (channel, cell) in cells.iter().enumerate() {
            let c = &mut self.channels[channel];
            if c.note.is_some() && c.ticks >= 1 {
                let sweep = self.song.instruments[&c.instrument.unwrap()].sweep;
                if sweep != 0 { c.frequency = (c.frequency + 10 * sweep).clamp(1000, 50 * self.song.rate); }
            }
            if tick >= 1 {
                if let Some(effect) = c.effect.clone() {
                    let (x, y) = (effect.argument / 16, effect.argument % 16);
                    match effect.command {
                        b'1' => c.frequency = (c.frequency + 10 * effect.argument).clamp(1000, 50 * self.song.rate),
                        b'2' => c.frequency = (c.frequency - 10 * effect.argument).clamp(1000, 50 * self.song.rate),
                        b'3' => c.approach(10 * c.portamento),
                        b'5' => { c.approach(10 * c.portamento); c.volume = (c.volume + x - y).clamp(0, 15); }
                        b'6' | b'A' => c.volume = (c.volume + x - y).clamp(0, 15),
                        b'Q' | b'R' if c.slide != 0 => c.approach(10 * c.slide),
                        _ => (),
                    }
                }
            }
            let effect = self.channels[channel].effect.clone();
            if let Some(effect) = &effect {
                if effect.is("ED") && effect.argument >= 1 && tick == effect.argument { self.content(channel, cell, false, position, row); }
                if effect.is("E9") && effect.argument >= 1 && tick >= 1 && tick % effect.argument == 0 && self.channels[channel].note.is_some() {
                    let c = &mut self.channels[channel];
                    c.phase = 0;
                    c.ticks = 0;
                    c.release = None;
                    c.retriggers += 1;
                }
                if effect.is("EC") && tick == effect.argument && self.channels[channel].note.is_some() {
                    self.end_record(channel, "cut");
                    self.channels[channel].note = None;
                    self.channels[channel].cuts += 1;
                }
            }
            let c = &mut self.channels[channel];
            if c.note.is_some() {
                let number = c.instrument.unwrap();
                c.output(&self.song.instruments[&number], tick, self.song.rate);
                c.active += 1;
                if c.amplitude > 0 { c.audible += 1; }
                *self.instrument_ticks.entry(number).or_default() += 1;
            }
        }
    }

    fn play(&mut self) {
        let (mut position, mut row) = (0, 0);
        'playback: loop {
            let start = self.samples.len();
            let visit = self.visits.entry((position, row)).or_insert((0, start));
            visit.0 += 1;
            let cells = self.song.patterns[&self.song.order[position]][row].clone();
            let tick_count = self.row_start(&cells, position, row);
            let samples_per_tick = sequencer::samples_per_tick(self.song.rate, self.tempo);
            for tick in 0..tick_count {
                self.tick(&cells, tick, position, row);
                if tick == 0 {
                    self.rows.push(RowRecord { position, row, start, speed: self.speed, tempo: self.tempo, notes: std::array::from_fn(|c| self.channels[c].note) });
                    let channel_states = self.channels.iter().map(channel_text).collect::<Vec<_>>().join(" | ");
                    self.log.push(format!("{position:02X} {:02X} {row:02X} {start:7} {:2} {:3} | {}", self.song.order[position], self.speed, self.tempo, channel_states));
                }
                if self.params.traces.contains(&(position, row)) {
                    let channels = self.channels.iter().map(|channel| {
                        if channel.note.is_some() { format!("{:7} {:5} {:X}{:X}", channel.output_frequency, channel.increment, channel.envelope, channel.output_volume) }
                        else { "      -     - --".into() }
                    }).collect::<Vec<_>>().join(" | ");
                    self.log.push(format!("  tick {tick:3} {:7} | {channels}", self.samples.len()));
                }
                let count = samples_per_tick.min(self.params.max_samples - self.samples.len());
                self.clipped += mixer::tick(&mut self.channels, &self.song.instruments, count, self.song.gain, &self.params.mute, &mut self.lanes, &mut self.samples);
                self.ticks += 1;
                for channel in &mut self.channels {
                    if channel.note.is_some() { channel.ticks += 1; }
                    if let Some(effect) = &channel.effect {
                        if effect.command == b'4' || effect.command == b'6' { channel.vibrato_position = (channel.vibrato_position + channel.vibrato_speed) % 64; }
                        if effect.command == b'7' { channel.tremolo_position = (channel.tremolo_position + channel.tremolo_speed) % 64; }
                    }
                }
                if self.samples.len() == self.params.max_samples {
                    self.end_reason = "limit".into();
                    break 'playback;
                }
            }
            let (next, stop) = sequencer::next_row(self.song, position, row, &cells);
            if stop {
                self.end_reason = format!("stop order={position:02X} row={row:02X}");
                break;
            }
            let Some((next_position, next_row)) = next else { self.end_reason = "finished".into(); break; };
            if self.visits.get(&(next_position, next_row)).is_some_and(|&(count, _)| count >= self.params.loops) {
                self.loop_start = Some(self.visits[&(next_position, next_row)].1);
                self.end_reason = format!("loop order={next_position:02X} row={next_row:02X}");
                break;
            }
            position = next_position;
            row = next_row;
        }
        for channel in 0..4 { self.end_record(channel, "end"); }
        if self.end_reason == "limit" || self.loop_start.is_some() { mixer::fade(&mut self.samples, self.params.fade); }
    }
}

fn channel_text(channel: &Channel) -> String {
    let effect = channel.effect.as_ref().map_or("...", |effect| effect.text.as_str());
    if let Some(note) = channel.note {
        format!("{} {:02X} {:7} {:X} {:X} {}", note_name(note), channel.instrument.unwrap(), channel.output_frequency, channel.envelope, channel.output_volume, effect)
    } else { format!("--- --       - - {:X} {}", channel.volume, effect) }
}

fn note_lines(playback: &Playback<'_>) -> Vec<String> {
    playback.records.iter().enumerate().map(|(index, record)| {
        let end = record.end.unwrap();
        let lane = &playback.lanes[record.channel][record.start..end];
        let peak = lane.iter().map(|value| value.abs()).max().unwrap_or(0);
        let cycles = lane.windows(2).filter(|pair| pair[0] < 0 && pair[1] >= 0).count();
        let release = record.release.map_or_else(|| "-".into(), |value| value.to_string());
        format!("{:4} ch={} at={:02X}:{:02X} ins={:02X} note={} start={} length={} release={} end={} peak={} cycles={}", index + 1, record.channel + 1, record.position, record.row, record.instrument, note_name(record.note), record.start, end - record.start, release, record.reason, peak, cycles)
    }).collect()
}

fn roll_lines(playback: &Playback<'_>) -> Vec<String> {
    let [start, count] = playback.params.roll;
    let rows: Vec<_> = playback.rows.iter().skip(start).take(count).collect();
    let pitches: BTreeSet<_> = rows.iter().flat_map(|row| row.notes.iter().flatten().copied()).collect();
    let mut lines = vec![format!("ROLL start={start} rows={} pitches={}", rows.len(), pitches.len())];
    for pitch in pitches.into_iter().rev() {
        let marks: String = rows.iter().map(|row| {
            let channels: Vec<_> = row.notes.iter().enumerate().filter(|(_, note)| **note == Some(pitch)).map(|(i, _)| i).collect();
            match channels.len() { 0 => ' ', 1 => (b'1' + channels[0] as u8) as char, _ => '*' }
        }).collect();
        lines.push(format!("{} |{}|", note_name(pitch), marks));
    }
    let axis: String = (0..rows.len()).map(|i| if i % 16 == 0 { '+' } else { '-' }).collect();
    lines.push(format!("    +{axis}+"));
    lines
}

fn range(records: &[&NoteRecord]) -> String {
    let minimum = records.iter().map(|record| record.note).min();
    let maximum = records.iter().map(|record| record.note).max();
    match (minimum, maximum) { (Some(a), Some(b)) => format!("{}..{}", note_name(a), note_name(b)), _ => "none".into() }
}

fn hex_list(values: impl IntoIterator<Item = i64>) -> String {
    let values: Vec<_> = values.into_iter().map(|value| format!("{value:02X}")).collect();
    if values.is_empty() { "none".into() } else { values.join(" ") }
}

fn stats(playback: &Playback<'_>) -> Vec<String> {
    let song = playback.song;
    let n = playback.samples.len();
    let (peak, rms, crossings) = report::statistics(&playback.samples, 128);
    let mut lines = vec![format!("title={}", song.title), format!("rate={}", song.rate), format!("samples={n}"), format!("duration_ms={}", n as i64 * 1000 / song.rate), format!("end={}", playback.end_reason),
        format!("loop_start={}", playback.loop_start.map_or_else(|| "-".into(), |v| v.to_string())),
        format!("loop_length={}", playback.loop_start.map_or_else(|| "-".into(), |v| (n - v).to_string())),
        format!("rows={}", playback.rows.len()), format!("ticks={}", playback.ticks), format!("clipped={}", playback.clipped),
        format!("peak={peak}"), format!("min={}", playback.samples.iter().min().unwrap()), format!("max={}", playback.samples.iter().max().unwrap()),
        format!("rms={rms}"), format!("zero_crossings={crossings}"), format!("adler32={:08X}", report::adler(&playback.samples))];
    let mut path = Vec::new();
    for row in &playback.rows { if path.last() != Some(&row.position) { path.push(row.position); } }
    lines.push(format!("path {}", path.iter().map(|position| format!("{position:02X}")).collect::<Vec<_>>().join(" ")));
    let mut timing = None;
    for row in &playback.rows {
        if timing != Some((row.speed, row.tempo)) {
            lines.push(format!("timing sample={} order={:02X} row={:02X} speed={} tempo={}", row.start, row.position, row.row, row.speed, row.tempo));
            timing = Some((row.speed, row.tempo));
        }
    }
    for (index, channel) in playback.channels.iter().enumerate() {
        let (peak, rms, _) = report::statistics(&playback.lanes[index], 0);
        let notes = playback.records.iter().filter(|record| record.channel == index).count();
        lines.push(format!("channel {} notes={} retriggers={} cuts={} active={} audible={} peak={} rms={}", index + 1, notes, channel.retriggers, channel.cuts, channel.active, channel.audible, peak, rms));
    }
    for (&number, instrument) in &song.instruments {
        let records: Vec<_> = playback.records.iter().filter(|record| record.instrument == number).collect();
        let average = if records.is_empty() { "-".into() } else { (records.iter().map(|record| record.end.unwrap() - record.start).sum::<usize>() / records.len()).to_string() };
        lines.push(format!("instrument {number:02X} {} {} notes={} ticks={} range={} average={}", instrument.name, instrument.waveform, records.len(), playback.instrument_ticks.get(&number).unwrap_or(&0), range(&records), average));
    }
    for (&number, pattern) in &song.patterns {
        let rows = pattern.iter().filter(|row| row.iter().any(|cell| !cell.empty())).count();
        let notes = pattern.iter().flatten().filter(|cell| cell.note.is_some()).count();
        lines.push(format!("pattern {number:02X} rows={rows} notes={notes} orders={}", song.order.iter().filter(|&&p| p == number).count()));
    }
    let reachable = sequencer::reachable(song);
    for (position, &pattern) in song.order.iter().enumerate() {
        let rows: Vec<_> = playback.rows.iter().filter(|row| row.position == position).collect();
        let first = rows.first().map_or_else(|| "-".into(), |row| row.start.to_string());
        let dead = song.patterns[&pattern].iter().enumerate().filter(|(row, cells)| !reachable.contains(&(position, *row)) && cells.iter().any(|cell| cell.note.is_some())).count();
        lines.push(format!("order {position:02X} pattern={pattern:02X} rows={} first={} dead={}", rows.len(), first, dead));
    }
    let mut notes: BTreeMap<i64, usize> = BTreeMap::new();
    for record in &playback.records { *notes.entry(record.note).or_default() += 1; }
    lines.extend(notes.iter().map(|(&note, count)| format!("note {} count={count}", note_name(note))));
    let effect_order = ["0", "1", "2", "3", "4", "5", "6", "7", "A", "B", "C", "D", "E1", "E2", "E9", "EA", "EB", "EC", "ED", "EE", "F", "P", "Q", "R", "V"];
    let effects: Vec<_> = effect_order.iter().filter_map(|&effect| playback.effects.get(effect).map(|count| format!("{effect}={count}"))).collect();
    lines.push(format!("effects {}", if effects.is_empty() { "none".into() } else { effects.join(" ") }));
    lines.push(format!("unused_instruments={}", hex_list(song.instruments.keys().copied().filter(|&number| !playback.records.iter().any(|record| record.instrument == number)))));
    lines.push(format!("unused_patterns={}", hex_list(song.patterns.keys().copied().filter(|number| !song.order.contains(number)))));
    lines.push(format!("unreached_orders={}", hex_list((0..song.order.len()).filter(|&p| !playback.rows.iter().any(|row| row.position == p)).map(|p| p as i64))));
    let mut durations = [0_i64; 12];
    for record in &playback.records {
        if song.instruments[&record.instrument].waveform != "NOISE" { durations[(record.note % 12) as usize] += (record.end.unwrap() - record.start) as i64; }
    }
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    lines.push(format!("pitch_classes {}", names.iter().zip(durations).map(|(name, duration)| format!("{name}={duration}")).collect::<Vec<_>>().join(" ")));
    let weights = [[64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29], [64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32]];
    let mut keys: Vec<_> = (0..24).map(|index| {
        let score: i64 = (0..12).map(|j| weights[index / 12][(j + 12 - index % 12) % 12] * durations[j]).sum();
        (index, score)
    }).collect();
    keys.sort_by_key(|&(index, score)| (-score, index));
    let key_name = |index: usize| format!("{} {}", names[index % 12], if index < 12 { "major" } else { "minor" });
    lines.push(format!("key={} score={} runner_up={} score={}", key_name(keys[0].0), keys[0].1, key_name(keys[1].0), keys[1].1));
    for channel in 0..4 {
        let records: Vec<_> = playback.records.iter().filter(|record| record.channel == channel).collect();
        let usage = song.instruments.keys().map(|number| format!("{number:02X}={}", records.iter().filter(|record| record.instrument == *number).count())).collect::<Vec<_>>().join(" ");
        lines.push(format!("usage ch{} range={} {}", channel + 1, range(&records), usage));
    }
    lines.extend(playback.warnings.clone());
    lines
}

fn plot(values: &[i64], width: usize, height: usize, low: i64, high: i64, middle: i64) -> Vec<String> {
    let row = |value| (2 * (high - value) * (height - 1) as i64 + (high - low)) / (2 * (high - low));
    let ranges: Vec<_> = (0..width).map(|column| {
        let part = &values[column * values.len() / width..(column + 1) * values.len() / width];
        (row(*part.iter().max().unwrap()), row(*part.iter().min().unwrap()))
    }).collect();
    (0..height).map(|r| {
        let label = if r == 0 { high.to_string() } else if r as i64 == row(middle) { middle.to_string() } else if r == height - 1 { low.to_string() } else { String::new() };
        let marks: String = ranges.iter().map(|&(top, bottom)| if top <= r as i64 && r as i64 <= bottom { '#' } else if r as i64 == row(middle) { '-' } else { ' ' }).collect();
        format!("{label:>5} |{marks}|")
    }).collect()
}

fn axes(start: usize, length: usize, width: usize, rate: i64) -> Vec<String> {
    let marks: String = (0..width).map(|c| if c % 10 == 0 { '+' } else { '-' }).collect();
    let mut ticks = b"    ms".to_vec();
    for column in (0..width).step_by(10) {
        let value = ((start + column * length / width) as i64 * 1000 / rate).to_string();
        let offset = 7 + column;
        if ticks.len() < offset + value.len() { ticks.resize(offset + value.len(), b' '); }
        ticks[offset..offset + value.len()].copy_from_slice(value.as_bytes());
    }
    vec![format!("      +{marks}+"), String::from_utf8(ticks).unwrap()]
}

fn waveform_lines(playback: &Playback<'_>) -> Vec<String> {
    let [start, length, width, height, scope] = playback.params.window;
    let mut lines = vec![format!("MIX start={start} length={length} width={width} height={height}")];
    lines.extend(plot(&playback.samples[start..start + length], width, height, 0, 255, 128));
    lines.extend(axes(start, length, width, playback.song.rate));
    for channel in 0..4 {
        lines.push(format!("CHANNEL {}", channel + 1));
        lines.extend(plot(&playback.lanes[channel][start..start + length], width, scope, -3375, 3375, 0));
    }
    lines.extend(axes(start, length, width, playback.song.rate));
    lines
}

fn previews(song: &Song, params: &Params) -> Vec<String> {
    let [note, ticks, release] = params.preview;
    let samples_per_tick = sequencer::samples_per_tick(song.rate, song.tempo);
    let mut lines = Vec::new();
    for (&number, instrument) in &song.instruments {
        let mut channel = Channel::new();
        channel.instrument = Some(number);
        channel.mode = instrument.mode;
        channel.note = Some(note);
        channel.frequency = frequency(note);
        channel.target = channel.frequency;
        let mut channels = vec![channel];
        let mut samples = Vec::new();
        let mut lanes = vec![Vec::new()];
        let mut envelopes = String::new();
        let mut frequencies = Vec::new();
        for tick in 0..ticks {
            let c = &mut channels[0];
            c.ticks = tick;
            if tick == release { c.release = Some((tick, c.envelope)); }
            if tick >= 1 && instrument.sweep != 0 { c.frequency = (c.frequency + 10 * instrument.sweep).clamp(1000, 50 * song.rate); }
            c.output(instrument, tick, song.rate);
            envelopes.push_str(&format!("{:X}", c.envelope));
            frequencies.push(c.output_frequency.to_string());
            mixer::tick(&mut channels, &song.instruments, samples_per_tick, song.gain, &[false], &mut lanes, &mut samples);
        }
        let (peak, rms, _) = report::statistics(&samples, 128);
        lines.push(format!("instrument {number:02X} {} wave={} samples={} peak={} rms={} adler32={:08X}", instrument.name, instrument.waveform, samples.len(), peak, rms, report::adler(&samples)));
        lines.push(format!("  env {envelopes}"));
        lines.push(format!("  freq {}", frequencies.join(" ")));
    }
    lines
}

fn write(name: &str, lines: &[String]) {
    let content = if lines.is_empty() { String::new() } else { format!("{}\n", lines.join("\n")) };
    fs::write(format!("output/{name}"), content).unwrap();
}

fn main() {
    let song = song_parser::read_song();
    let params = song_parser::read_params();
    let mut playback = Playback::new(&song, &params);
    playback.play();
    fs::create_dir_all("output").unwrap();
    write("samples.txt", &report::hex_dump(&playback.samples));
    write("channel_log.txt", &playback.log);
    write("notes.txt", &note_lines(&playback));
    write("roll.txt", &roll_lines(&playback));
    write("stats.txt", &stats(&playback));
    write("waveform.txt", &waveform_lines(&playback));
    write("instruments.txt", &previews(&song, &params));
}
