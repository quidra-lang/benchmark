use std::collections::{BTreeMap, BTreeSet};
use std::fs;

const PITCHES: [&str; 12] = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"];

pub fn note_number(text: &str) -> i64 {
    PITCHES.iter().position(|&p| p == &text[..2]).unwrap() as i64 + 12 * i64::from(text.as_bytes()[2] - b'0')
}

pub fn note_name(note: i64) -> String { format!("{}{}", PITCHES[(note % 12) as usize], note / 12) }

fn hex(text: &str) -> i64 { i64::from_str_radix(text, 16).unwrap() }

#[derive(Clone)]
pub struct Effect {
    pub text: String,
    pub command: u8,
    pub subcommand: u8,
    pub argument: i64,
}

impl Effect {
    pub fn name(&self) -> String {
        if self.command == b'E' { format!("E{}", self.subcommand as char) } else { (self.command as char).to_string() }
    }

    pub fn is(&self, name: &str) -> bool { self.name() == name }
}

#[derive(Clone, Default)]
pub struct Cell {
    pub note: Option<i64>,
    pub instrument: Option<i64>,
    pub volume: Option<i64>,
    pub effect: Option<Effect>,
}

impl Cell {
    fn parse(text: &str) -> Self {
        let parts: Vec<_> = text.split(' ').collect();
        let note = match parts[0] { "..." => None, "OFF" => Some(-1), name => Some(note_number(name)) };
        let instrument = (parts[1] != "..").then(|| hex(parts[1]));
        let volume = (parts[2] != ".").then(|| hex(parts[2]));
        let effect = if parts[3] == "..." { None } else {
            let text = parts[3];
            let command = text.as_bytes()[0];
            Some(Effect {
                text: text.into(), command, subcommand: text.as_bytes()[1],
                argument: hex(if command == b'E' { &text[2..] } else { &text[1..] }),
            })
        };
        Self { note, instrument, volume, effect }
    }

    pub fn empty(&self) -> bool { self.note.is_none() && self.instrument.is_none() && self.volume.is_none() && self.effect.is_none() }
}

pub struct Instrument {
    pub name: String,
    pub waveform: String,
    pub mode: i64,
    pub table: Vec<i64>,
    pub envelope: [i64; 4],
    pub vibrato: Option<(i64, i64, i64)>,
    pub arpeggio: Vec<i64>,
    pub sweep: i64,
}

pub struct Song {
    pub title: String,
    pub rate: i64,
    pub speed: i64,
    pub tempo: i64,
    pub gain: i64,
    pub instruments: BTreeMap<i64, Instrument>,
    pub patterns: BTreeMap<i64, Vec<[Cell; 4]>>,
    pub order: Vec<i64>,
}

pub struct Params {
    pub max_samples: usize,
    pub loops: usize,
    pub fade: usize,
    pub mute: [bool; 4],
    pub window: [usize; 5],
    pub roll: [usize; 2],
    pub preview: [i64; 3],
    pub traces: BTreeSet<(usize, usize)>,
}

pub fn read_song() -> Song {
    let input = fs::read_to_string("input/song.txt").unwrap();
    let lines: Vec<_> = input.lines().filter(|line| !line.is_empty() && !line.starts_with('#')).collect();
    let scalar = |i: usize| lines[i].split(' ').nth(1).unwrap().parse().unwrap();
    let mut song = Song { title: lines[0][6..].into(), rate: scalar(1), speed: scalar(2), tempo: scalar(3), gain: scalar(4), instruments: BTreeMap::new(), patterns: BTreeMap::new(), order: Vec::new() };
    let mut i = 5;
    while i < lines.len() {
        let words: Vec<_> = lines[i].split(' ').collect();
        match words[0] {
            "INSTRUMENT" => {
                let number = hex(words[1]);
                let mut instrument = Instrument { name: words[2].into(), waveform: String::new(), mode: 0, table: Vec::new(), envelope: [0; 4], vibrato: None, arpeggio: Vec::new(), sweep: 0 };
                i += 1;
                while lines[i] != "END" {
                    let words: Vec<_> = lines[i].split(' ').collect();
                    let numbers: Vec<i64> = if words[0] == "WAVE" { Vec::new() } else { words[1..].iter().map(|s| s.parse().unwrap()).collect() };
                    match words[0] {
                        "WAVE" => {
                            instrument.waveform = words[1].into();
                            match words[1] {
                                "PULSE" => instrument.mode = ["12", "25", "50", "75"].iter().position(|&d| d == words[2]).unwrap() as i64,
                                "NOISE" => instrument.mode = i64::from(words[2] == "SHORT"),
                                "TABLE" => instrument.table = words[2].chars().map(|c| i64::from(c.to_digit(16).unwrap())).collect(),
                                _ => (),
                            }
                        }
                        "ENVELOPE" => instrument.envelope.copy_from_slice(&numbers),
                        "VIBRATO" => instrument.vibrato = Some((numbers[0], numbers[1], numbers[2])),
                        "ARPEGGIO" => instrument.arpeggio = numbers,
                        "SWEEP" => instrument.sweep = numbers[0],
                        _ => unreachable!(),
                    }
                    i += 1;
                }
                song.instruments.insert(number, instrument);
            }
            "PATTERN" => {
                let number = hex(words[1]);
                let mut pattern: Vec<[Cell; 4]> = (0..64).map(|_| std::array::from_fn(|_| Cell::default())).collect();
                i += 1;
                while lines[i] != "END" {
                    let row = hex(&lines[i][..2]) as usize;
                    let cells: Vec<_> = lines[i][3..].split(" | ").map(Cell::parse).collect();
                    pattern[row] = cells.try_into().ok().unwrap();
                    i += 1;
                }
                song.patterns.insert(number, pattern);
            }
            "ORDER" => song.order = words[1..].iter().map(|p| hex(p)).collect(),
            _ => unreachable!(),
        }
        i += 1;
    }
    song
}

pub fn read_params() -> Params {
    let text = fs::read_to_string("input/params.txt").unwrap();
    let lines: Vec<Vec<_>> = text.lines().map(|line| line.split(' ').collect()).collect();
    let values = |i: usize| lines[i][1..].iter().map(|s| s.parse::<usize>().unwrap()).collect::<Vec<_>>();
    Params {
        max_samples: values(0)[0], loops: values(1)[0], fade: values(2)[0],
        mute: std::array::from_fn(|i| values(3)[i] == 1),
        window: values(4).try_into().ok().unwrap(), roll: values(5).try_into().ok().unwrap(),
        preview: [note_number(lines[6][1]), lines[6][2].parse().unwrap(), lines[6][3].parse().unwrap()],
        traces: lines[7..].iter().map(|words| (hex(words[1]) as usize, hex(words[2]) as usize)).collect(),
    }
}
