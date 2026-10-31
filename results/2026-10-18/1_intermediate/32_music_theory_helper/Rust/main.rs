use std::fmt::{self, Display};
use std::io::{self, BufRead, Write};

type Result<T> = std::result::Result<T, String>;
const NATURAL: [i32; 7] = [0, 2, 4, 5, 7, 9, 11];
const FIFTHS: [i32; 7] = [0, 2, 4, -1, 1, 3, 5];
const ACCIDENTALS: [&str; 5] = ["bb", "b", "", "#", "x"];
const SHARPS: [&str; 12] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const FLATS: [&str; 12] = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];
const UPPER: [&str; 7] = ["I", "II", "III", "IV", "V", "VI", "VII"];
const LOWER: [&str; 7] = ["i", "ii", "iii", "iv", "v", "vi", "vii"];

fn bad(kind: &str, word: &str) -> String { format!("ERROR BAD {kind} {word}") }
fn canonical(text: &str, low: i32, high: i32) -> Option<i32> {
    if text.is_empty() || (text.starts_with('0') && text.len() > 1) || !text.bytes().all(|c| c.is_ascii_digit()) { return None; }
    text.parse().ok().filter(|value| (low..=high).contains(value))
}
fn number(text: &str) -> Result<i32> { canonical(text, 0, 127).ok_or_else(|| bad("NUMBER", text)) }
fn frequency(text: &str, tuning: bool) -> Result<i32> {
    let mut parts = text.split('.');
    let first = parts.next().unwrap();
    if !(1..=5).contains(&first.len()) || !first.bytes().all(|c| c.is_ascii_digit()) { return Err(bad("FREQUENCY", text)); }
    let mut cents = first.parse::<i32>().unwrap() * 100;
    if let Some(second) = parts.next() {
        if !(1..=2).contains(&second.len()) || !second.bytes().all(|c| c.is_ascii_digit()) || parts.next().is_some() {
            return Err(bad("FREQUENCY", text));
        }
        cents += second.parse::<i32>().unwrap() * if second.len() == 1 { 10 } else { 1 };
    }
    if cents == 0 || (tuning && !(40000..=48000).contains(&cents)) { return Err(bad("FREQUENCY", text)); }
    Ok(cents)
}
fn frequency_text(cents: i32) -> String { format!("{}.{:02}", cents / 100, cents % 100) }
fn joined<T: Display>(values: &[T], separator: &str) -> String {
    values.iter().map(ToString::to_string).collect::<Vec<_>>().join(separator)
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct Pitch { letter: i32, alteration: i32 }
impl Pitch {
    fn prefix(text: &str) -> Option<(Self, &str)> {
        let bytes = text.as_bytes();
        let letter = b"CDEFGAB".iter().position(|c| Some(c) == bytes.first())? as i32;
        let (alteration, length) = match bytes.get(1) {
            Some(b'b') if bytes.get(2) == Some(&b'b') => (-2, 3),
            Some(b'b') => (-1, 2), Some(b'#') => (1, 2), Some(b'x') => (2, 2), _ => (0, 1),
        };
        Some((Self { letter, alteration }, &text[length..]))
    }
    fn parse(text: &str) -> Result<Self> {
        Self::prefix(text).filter(|(_, rest)| rest.is_empty()).map(|(pitch, _)| pitch).ok_or_else(|| bad("PITCH", text))
    }
    fn class(self) -> i32 { (NATURAL[self.letter as usize] + self.alteration).rem_euclid(12) }
    fn raise(self, tone: Tone) -> Result<Self> {
        let target = self.letter + tone.letters;
        let alteration = NATURAL[self.letter as usize] + self.alteration + tone.semitones
            - NATURAL[(target % 7) as usize] - 12 * (target / 7);
        if !(-2..=2).contains(&alteration) { return Err("ERROR CANNOT SPELL".into()); }
        Ok(Self { letter: target % 7, alteration })
    }
    fn fifths(value: i32) -> Self {
        Self { letter: [3, 0, 4, 1, 5, 2, 6][(value + 1).rem_euclid(7) as usize], alteration: (value + 1).div_euclid(7) }
    }
}
impl Display for Pitch {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}{}", b"CDEFGAB"[self.letter as usize] as char, ACCIDENTALS[(self.alteration + 2) as usize])
    }
}
#[derive(Clone, Copy)]
struct Note { pitch: Pitch, octave: i32 }
impl Note {
    fn parse(text: &str) -> Result<Self> {
        let (pitch, rest) = Pitch::prefix(text).ok_or_else(|| bad("NOTE", text))?;
        let octave = if rest == "-1" { -1 }
            else if rest.len() == 1 && rest.as_bytes()[0].is_ascii_digit() { i32::from(rest.as_bytes()[0] - b'0') }
            else { return Err(bad("NOTE", text)); };
        let note = Self { pitch, octave };
        if !note.valid() { return Err(bad("NOTE", text)); }
        Ok(note)
    }
    fn midi(self) -> i32 { 12 * (self.octave + 1) + NATURAL[self.pitch.letter as usize] + self.pitch.alteration }
    fn position(self) -> i32 { 7 * self.octave + self.pitch.letter }
    fn valid(self) -> bool { (-1..=9).contains(&self.octave) && (0..=127).contains(&self.midi()) }
    fn from_pitch(pitch: Pitch, value: i32) -> Self {
        Self { pitch, octave: (value - NATURAL[pitch.letter as usize] - pitch.alteration) / 12 - 1 }
    }
    fn spelling(value: i32, flat: bool) -> Self {
        Self { pitch: Pitch::parse((if flat { &FLATS } else { &SHARPS })[(value % 12) as usize]).unwrap(), octave: value / 12 - 1 }
    }
}
impl Display for Note {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { write!(f, "{}{}", self.pitch, self.octave) }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Quality { Perfect, Major, Minor, Augmented, Diminished, DoubleAugmented, DoubleDiminished }
const QUALITIES: [Quality; 7] = [Quality::Perfect, Quality::Major, Quality::Minor, Quality::Augmented,
    Quality::Diminished, Quality::DoubleAugmented, Quality::DoubleDiminished];
impl Quality {
    fn text(self) -> &'static str {
        match self { Self::Perfect => "P", Self::Major => "M", Self::Minor => "m", Self::Augmented => "A",
            Self::Diminished => "d", Self::DoubleAugmented => "AA", Self::DoubleDiminished => "dd" }
    }
    fn delta(self, perfect: bool) -> Option<i32> {
        match self {
            Self::Perfect if perfect => Some(0), Self::Major if !perfect => Some(0), Self::Minor if !perfect => Some(-1),
            Self::Augmented => Some(1), Self::DoubleAugmented => Some(2),
            Self::Diminished => Some(if perfect { -1 } else { -2 }),
            Self::DoubleDiminished => Some(if perfect { -2 } else { -3 }), _ => None,
        }
    }
    fn inverse(self) -> Self {
        match self { Self::Perfect => Self::Perfect, Self::Major => Self::Minor, Self::Minor => Self::Major,
            Self::Augmented => Self::Diminished, Self::Diminished => Self::Augmented,
            Self::DoubleAugmented => Self::DoubleDiminished, Self::DoubleDiminished => Self::DoubleAugmented }
    }
}
#[derive(Clone, Copy)]
struct Interval { quality: Quality, number: i32 }
impl Interval {
    fn perfect(number: i32) -> bool { matches!((number - 1) % 7, 0 | 3 | 4) }
    fn forbidden(self) -> bool { self.number == 1 && matches!(self.quality, Quality::Diminished | Quality::DoubleDiminished) }
    fn parse(text: &str) -> Result<Self> {
        for quality in QUALITIES {
            if let Some(number) = text.strip_prefix(quality.text()).and_then(|rest| canonical(rest, 1, 99)) {
                let interval = Self { quality, number };
                if quality.delta(Self::perfect(number)).is_some() && !interval.forbidden() { return Ok(interval); }
            }
        }
        Err(bad("INTERVAL", text))
    }
    fn simple(mut self) -> Self { while self.number > 8 { self.number -= 7; } self }
    fn tone(self) -> Tone {
        let letters = self.number - 1;
        Tone { letters, semitones: 12 * (letters / 7) + NATURAL[(letters % 7) as usize] + self.quality.delta(Self::perfect(self.number)).unwrap() }
    }
    fn class(self) -> &'static str {
        let simple = self.simple();
        if simple.quality == Quality::Perfect && matches!(simple.number, 1 | 5 | 8) { "perfect" }
        else if matches!(simple.quality, Quality::Major | Quality::Minor) && matches!(simple.number, 3 | 6) { "imperfect" }
        else { "dissonant" }
    }
}
impl Display for Interval {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { write!(f, "{}{}", self.quality.text(), self.number) }
}
struct IntervalResult { interval: Interval, down: bool, semitones: i32 }
fn between(a: Note, b: Note) -> Result<IntervalResult> {
    let mut distance = b.position() - a.position();
    let mut semitones = b.midi() - a.midi();
    let down = distance < 0 || (distance == 0 && semitones < 0);
    if down { distance = -distance; semitones = -semitones; }
    let difference = semitones - 12 * (distance / 7) - NATURAL[(distance % 7) as usize];
    let quality = QUALITIES.iter().copied().find(|q| q.delta(Interval::perfect(distance + 1)) == Some(difference))
        .ok_or_else(|| "ERROR UNNAMEABLE INTERVAL".to_string())?;
    Ok(IntervalResult { interval: Interval { quality, number: distance + 1 }, down, semitones })
}

#[derive(Clone, Copy)]
struct Tone { letters: i32, semitones: i32 }
const fn t(letters: i32, semitones: i32) -> Tone { Tone { letters, semitones } }
struct Scale { name: &'static str, tones: &'static [Tone] }
const SCALES: [Scale; 15] = [
    Scale { name: "major", tones: &[t(0,0),t(1,2),t(2,4),t(3,5),t(4,7),t(5,9),t(6,11)] },
    Scale { name: "natural_minor", tones: &[t(0,0),t(1,2),t(2,3),t(3,5),t(4,7),t(5,8),t(6,10)] },
    Scale { name: "harmonic_minor", tones: &[t(0,0),t(1,2),t(2,3),t(3,5),t(4,7),t(5,8),t(6,11)] },
    Scale { name: "melodic_minor", tones: &[t(0,0),t(1,2),t(2,3),t(3,5),t(4,7),t(5,9),t(6,11)] },
    Scale { name: "ionian", tones: &[t(0,0),t(1,2),t(2,4),t(3,5),t(4,7),t(5,9),t(6,11)] },
    Scale { name: "dorian", tones: &[t(0,0),t(1,2),t(2,3),t(3,5),t(4,7),t(5,9),t(6,10)] },
    Scale { name: "phrygian", tones: &[t(0,0),t(1,1),t(2,3),t(3,5),t(4,7),t(5,8),t(6,10)] },
    Scale { name: "lydian", tones: &[t(0,0),t(1,2),t(2,4),t(3,6),t(4,7),t(5,9),t(6,11)] },
    Scale { name: "mixolydian", tones: &[t(0,0),t(1,2),t(2,4),t(3,5),t(4,7),t(5,9),t(6,10)] },
    Scale { name: "aeolian", tones: &[t(0,0),t(1,2),t(2,3),t(3,5),t(4,7),t(5,8),t(6,10)] },
    Scale { name: "locrian", tones: &[t(0,0),t(1,1),t(2,3),t(3,5),t(4,6),t(5,8),t(6,10)] },
    Scale { name: "major_pentatonic", tones: &[t(0,0),t(1,2),t(2,4),t(4,7),t(5,9)] },
    Scale { name: "minor_pentatonic", tones: &[t(0,0),t(2,3),t(3,5),t(4,7),t(6,10)] },
    Scale { name: "blues", tones: &[t(0,0),t(2,3),t(3,5),t(3,6),t(4,7),t(6,10)] },
    Scale { name: "whole_tone", tones: &[t(0,0),t(1,2),t(2,4),t(3,6),t(4,8),t(5,10)] },
];
struct Chord { name: &'static str, suffix: &'static str, numeral_suffix: &'static str, lower: bool, tones: &'static [Tone] }
const CHORDS: [Chord; 16] = [
    Chord { name:"maj",suffix:"",numeral_suffix:"",lower:false,tones:&[t(0,0),t(2,4),t(4,7)] },
    Chord { name:"min",suffix:"m",numeral_suffix:"",lower:true,tones:&[t(0,0),t(2,3),t(4,7)] },
    Chord { name:"dim",suffix:"dim",numeral_suffix:"o",lower:true,tones:&[t(0,0),t(2,3),t(4,6)] },
    Chord { name:"aug",suffix:"aug",numeral_suffix:"+",lower:false,tones:&[t(0,0),t(2,4),t(4,8)] },
    Chord { name:"sus2",suffix:"sus2",numeral_suffix:"sus2",lower:false,tones:&[t(0,0),t(1,2),t(4,7)] },
    Chord { name:"sus4",suffix:"sus4",numeral_suffix:"sus4",lower:false,tones:&[t(0,0),t(3,5),t(4,7)] },
    Chord { name:"6",suffix:"6",numeral_suffix:"6",lower:false,tones:&[t(0,0),t(2,4),t(4,7),t(5,9)] },
    Chord { name:"m6",suffix:"m6",numeral_suffix:"6",lower:true,tones:&[t(0,0),t(2,3),t(4,7),t(5,9)] },
    Chord { name:"7",suffix:"7",numeral_suffix:"7",lower:false,tones:&[t(0,0),t(2,4),t(4,7),t(6,10)] },
    Chord { name:"maj7",suffix:"maj7",numeral_suffix:"maj7",lower:false,tones:&[t(0,0),t(2,4),t(4,7),t(6,11)] },
    Chord { name:"m7",suffix:"m7",numeral_suffix:"7",lower:true,tones:&[t(0,0),t(2,3),t(4,7),t(6,10)] },
    Chord { name:"mMaj7",suffix:"mMaj7",numeral_suffix:"maj7",lower:true,tones:&[t(0,0),t(2,3),t(4,7),t(6,11)] },
    Chord { name:"m7b5",suffix:"m7b5",numeral_suffix:"h7",lower:true,tones:&[t(0,0),t(2,3),t(4,6),t(6,10)] },
    Chord { name:"dim7",suffix:"dim7",numeral_suffix:"o7",lower:true,tones:&[t(0,0),t(2,3),t(4,6),t(6,9)] },
    Chord { name:"9",suffix:"9",numeral_suffix:"9",lower:false,tones:&[t(0,0),t(2,4),t(4,7),t(6,10),t(8,14)] },
    Chord { name:"add9",suffix:"add9",numeral_suffix:"add9",lower:false,tones:&[t(0,0),t(2,4),t(4,7),t(8,14)] },
];
struct Mode { name: &'static str, scale: usize, offset: i32 }
const MODES: [Mode; 9] = [
    Mode{name:"major",scale:0,offset:0}, Mode{name:"minor",scale:1,offset:-3}, Mode{name:"ionian",scale:4,offset:0},
    Mode{name:"dorian",scale:5,offset:-2}, Mode{name:"phrygian",scale:6,offset:-4}, Mode{name:"lydian",scale:7,offset:1},
    Mode{name:"mixolydian",scale:8,offset:-1}, Mode{name:"aeolian",scale:9,offset:-3}, Mode{name:"locrian",scale:10,offset:-5},
];
fn scale_index(text: &str) -> Result<usize> { SCALES.iter().position(|s| s.name == text).ok_or_else(|| bad("SCALE", text)) }
fn quality_index(text: &str) -> Result<usize> { CHORDS.iter().position(|c| c.name == text).ok_or_else(|| bad("QUALITY", text)) }
fn mode_index(text: &str) -> Result<usize> { MODES.iter().position(|m| m.name == text).ok_or_else(|| bad("MODE", text)) }
fn build(root: Pitch, tones: &[Tone]) -> Result<Vec<Pitch>> { tones.iter().map(|&tone| root.raise(tone)).collect() }
fn symbol(root: Pitch, quality: usize, bass: Option<Pitch>) -> String {
    format!("{root}{}{}", CHORDS[quality].suffix, bass.map_or(String::new(), |pitch| format!("/{pitch}")))
}
fn roman(degree: usize, quality: usize) -> String {
    let chord = &CHORDS[quality];
    format!("{}{}", (if chord.lower { &LOWER } else { &UPPER })[degree], chord.numeral_suffix)
}

#[derive(Clone, Copy)]
struct Key { tonic: Pitch, mode: usize, fifths: i32, scale: [Pitch; 7] }
impl Key {
    fn new(tonic: Pitch, mode: usize) -> Result<Self> {
        let fifths = FIFTHS[tonic.letter as usize] + 7 * tonic.alteration + MODES[mode].offset;
        if !(-7..=7).contains(&fifths) { return Err("ERROR THEORETICAL KEY".into()); }
        let notes = build(tonic, SCALES[MODES[mode].scale].tones)?;
        let scale = std::array::from_fn(|i| notes[i]);
        Ok(Self { tonic, mode, fifths, scale })
    }
    fn parse(words: &[&str]) -> Result<Self> {
        let tonic = Pitch::parse(words[0])?;
        let mode = mode_index(words[1])?;
        Self::new(tonic, mode)
    }
    fn degree(self, pitch: Pitch) -> usize { (pitch.letter - self.tonic.letter).rem_euclid(7) as usize }
    fn prefix(self, pitch: Pitch) -> String {
        let difference = pitch.alteration - self.scale[self.degree(pitch)].alteration;
        (if difference < 0 { "b" } else { "#" }).repeat(difference.unsigned_abs() as usize)
    }
    fn label(self, pitch: Pitch) -> String { format!("{}{}", self.prefix(pitch), self.degree(pitch) + 1) }
    fn set(self) -> u16 { self.scale.iter().fold(0, |mask, pitch| mask | 1u16 << pitch.class()) }
}
impl Display for Key {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { write!(f, "{} {}", self.tonic, MODES[self.mode].name) }
}
#[derive(Clone, Copy)]
struct Numeral { alteration: i32, degree: usize, quality: usize }
impl Numeral {
    fn parse(text: &str) -> Result<Self> {
        let (alteration, rest) = if let Some(rest) = text.strip_prefix('b') { (-1, rest) }
            else if let Some(rest) = text.strip_prefix('#') { (1, rest) } else { (0, text) };
        let end = rest.bytes().take_while(|&c| matches!(c, b'I' | b'V' | b'i' | b'v')).count();
        for degree in 0..7 {
            for (quality, chord) in CHORDS.iter().enumerate() {
                if &rest[..end] == (if chord.lower { &LOWER } else { &UPPER })[degree] && &rest[end..] == chord.numeral_suffix {
                    return Ok(Self { alteration, degree, quality });
                }
            }
        }
        Err(bad("NUMERAL", text))
    }
}
struct Symbol { root: Pitch, quality: usize }
impl Symbol {
    fn parse(text: &str) -> Result<Self> {
        if let Some((root, suffix)) = Pitch::prefix(text) {
            if let Some(quality) = CHORDS.iter().position(|chord| chord.suffix == suffix) { return Ok(Self { root, quality }); }
        }
        Err(bad("SYMBOL", text))
    }
}

const COMMANDS: [(&str, usize, usize); 24] = [
    ("MIDI",1,1),("NOTE",1,1),("FREQ",1,1),("TUNING",1,1),("PITCH",1,1),("INTERVAL",2,2),
    ("INVERT",1,1),("TRANSPOSE",3,3),("SCALE",2,2),("CHORD",2,3),("VOICE",2,3),
    ("IDENTIFY",2,15),("MELODY",2,15),("ENHARMONIC",1,1),("KEYSIG",2,2),("RELATIVE",2,2),
    ("CIRCLE",1,1),("DIATONIC",2,2),("PROGRESSION",3,15),("ANALYZE",3,15),("FINDKEY",1,15),
    ("DEGREE",3,3),("SPELL",3,3),("KEYDIST",4,4),
];
struct Calculator { tuning: i32 }
impl Calculator {
    fn execute(&mut self, line: &str) -> Result<Vec<String>> {
        let words: Vec<_> = line.split(' ').collect();
        let command = words[0];
        let &(_, minimum, maximum) = COMMANDS.iter().find(|c| c.0 == command)
            .ok_or_else(|| format!("ERROR UNKNOWN COMMAND {command}"))?;
        let a = &words[1..];
        if !(minimum..=maximum).contains(&a.len()) { return Err("ERROR ARGUMENT COUNT".into()); }
        Ok(match command {
            "MIDI" | "FREQ" | "ENHARMONIC" => {
                let note = Note::parse(a[0])?;
                let value = note.midi();
                let row = if command == "MIDI" { format!("MIDI {} {value}", a[0]) }
                else if command == "FREQ" {
                    let cents = (f64::from(self.tuning) * (f64::from(value - 69) / 12.0).exp2()).round() as i32;
                    format!("FREQ {} {}", a[0], frequency_text(cents))
                } else {
                    let mut notes = Vec::new();
                    for octave in -1..=9 {
                        for letter in 0..7 {
                            let alteration = value - 12 * (octave + 1) - NATURAL[letter as usize];
                            if (-2..=2).contains(&alteration) { notes.push(Note { pitch: Pitch { letter, alteration }, octave }); }
                        }
                    }
                    format!("ENHARMONIC {} {}", a[0], joined(&notes, " "))
                };
                vec![row]
            }
            "NOTE" => {
                let value = number(a[0])?;
                vec![format!("NOTE {value} {} {}", Note::spelling(value, false), Note::spelling(value, true))]
            }
            "TUNING" | "PITCH" => {
                let value = frequency(a[0], command == "TUNING")?;
                if command == "TUNING" {
                    self.tuning = value;
                    vec![format!("TUNING {}", frequency_text(value))]
                } else {
                    let x = 69.0 + 12.0 * (f64::from(value) / f64::from(self.tuning)).log2();
                    let nearest = x.round() as i32;
                    if !(0..=127).contains(&nearest) { return Err("ERROR OUT OF RANGE".into()); }
                    let cents = (100.0 * (x - f64::from(nearest))).round() as i32;
                    vec![format!("PITCH {} {} {cents:+}", frequency_text(value), Note::spelling(nearest, false))]
                }
            }
            "INTERVAL" => {
                let first = Note::parse(a[0])?;
                let second = Note::parse(a[1])?;
                let result = between(first, second)?;
                vec![format!("INTERVAL {} {} {} {} semitones={} simple={} class={}", a[0], a[1], result.interval,
                    if result.down { "down" } else { "up" }, result.semitones, result.interval.simple(), result.interval.class())]
            }
            "INVERT" => {
                let simple = Interval::parse(a[0])?.simple();
                let inverse = Interval { quality: simple.quality.inverse(), number: 9 - simple.number };
                if inverse.forbidden() { return Err("ERROR CANNOT INVERT".into()); }
                vec![format!("INVERT {} {simple} {inverse}", a[0])]
            }
            "TRANSPOSE" => {
                let note = Note::parse(a[0])?;
                let tone = Interval::parse(a[1])?.tone();
                let sign = match a[2] { "UP" => 1, "DOWN" => -1, _ => return Err(bad("DIRECTION", a[2])) };
                let target = note.position() + sign * tone.letters;
                let value = note.midi() + sign * tone.semitones;
                let letter = target.rem_euclid(7);
                let octave = target.div_euclid(7);
                let alteration = value - 12 * (octave + 1) - NATURAL[letter as usize];
                if !(-2..=2).contains(&alteration) { return Err("ERROR CANNOT SPELL".into()); }
                let result = Note { pitch: Pitch { letter, alteration }, octave };
                if !result.valid() { return Err("ERROR OUT OF RANGE".into()); }
                vec![format!("TRANSPOSE {} {} {} {result}", a[0], a[1], a[2])]
            }
            "SCALE" => {
                let root = Pitch::parse(a[0])?;
                let scale = &SCALES[scale_index(a[1])?];
                let pitches = build(root, scale.tones)?;
                let steps: Vec<_> = scale.tones.iter().enumerate().map(|(i, tone)|
                    scale.tones.get(i + 1).map_or(12, |next| next.semitones) - tone.semitones).collect();
                vec![format!("SCALE {} {} {} steps={}", a[0], a[1], joined(&pitches, " "), joined(&steps, ","))]
            }
            "CHORD" | "VOICE" => {
                let note = if command == "VOICE" { Some(Note::parse(a[0])?) } else { None };
                let root = if let Some(note) = note { note.pitch } else { Pitch::parse(a[0])? };
                let quality = quality_index(a[1])?;
                let chord = &CHORDS[quality];
                let inversion = if a.len() == 3 {
                    canonical(a[2], 0, chord.tones.len() as i32 - 1).ok_or_else(|| bad("INVERSION", a[2]))? as usize
                } else { 0 };
                let mut pitches = build(root, chord.tones)?;
                pitches.rotate_left(inversion);
                let name = symbol(root, quality, if inversion == 0 { None } else { Some(pitches[0]) });
                if let Some(note) = note {
                    let mut value = note.midi();
                    let mut notes = Vec::new();
                    for (i, &pitch) in pitches.iter().enumerate() {
                        if i > 0 || inversion > 0 {
                            let difference = (pitch.class() - value).rem_euclid(12);
                            value += if difference == 0 { 12 } else { difference };
                        }
                        let note = Note::from_pitch(pitch, value);
                        if !note.valid() { return Err("ERROR OUT OF RANGE".into()); }
                        notes.push(note);
                    }
                    let values: Vec<_> = notes.iter().map(|note| note.midi()).collect();
                    vec![format!("VOICE {name} {} midi={}", joined(&notes, " "), joined(&values, ","))]
                } else { vec![format!("CHORD {name} {}", joined(&pitches, " "))] }
            }
            "IDENTIFY" | "MELODY" => {
                let mut notes = a.iter().map(|text| Note::parse(text)).collect::<Result<Vec<_>>>()?;
                if command == "MELODY" {
                    let (mut low, mut high) = (0, 0);
                    for i in 1..notes.len() {
                        if notes[i].midi() < notes[low].midi() { low = i; }
                        if notes[i].midi() > notes[high].midi() { high = i; }
                    }
                    let range = between(notes[low], notes[high])?.interval;
                    let mut steps = Vec::new();
                    let mut leaps = 0;
                    for pair in notes.windows(2) {
                        let result = between(pair[0], pair[1])?;
                        steps.push(format!("{}{}", if result.down { '-' } else { '+' }, result.interval));
                        if (pair[1].midi() - pair[0].midi()).abs() >= 3 { leaps += 1; }
                    }
                    vec![format!("MELODY n={} low={} high={} range={range} leaps={leaps} steps={}", notes.len(), a[low], a[high], steps.join(","))]
                } else {
                    notes.sort_by_key(|note| note.midi());
                    let mut set = 0u16;
                    notes.retain(|note| {
                        let bit = 1u16 << note.pitch.class();
                        let unique = set & bit == 0;
                        set |= bit;
                        unique
                    });
                    let bass = notes[0].pitch;
                    for note in notes {
                        for (quality, chord) in CHORDS.iter().enumerate() {
                            let candidate = chord.tones.iter().fold(0u16, |mask, tone|
                                mask | 1u16 << (note.midi() + tone.semitones).rem_euclid(12));
                            if candidate != set { continue; }
                            let inversion = chord.tones.iter().position(|tone| (note.midi() + tone.semitones).rem_euclid(12) == bass.class()).unwrap();
                            let name = symbol(note.pitch, quality, if inversion == 0 { None } else { Some(bass) });
                            return Ok(vec![format!("IDENTIFY {name} root={} quality={} inversion={inversion}", note.pitch, chord.name)]);
                        }
                    }
                    vec!["IDENTIFY UNKNOWN".into()]
                }
            }
            "CIRCLE" => {
                let mode = mode_index(a[0])?;
                let pitches: Vec<_> = (-7..=7).map(|p| Pitch::fifths(p - MODES[mode].offset)).collect();
                vec![format!("CIRCLE {} {}", a[0], joined(&pitches, " "))]
            }
            "FINDKEY" => {
                let pitches = a.iter().map(|text| Pitch::parse(text)).collect::<Result<Vec<_>>>()?;
                let mut keys = Vec::new();
                for p in -7..=7 {
                    for mode in 0..2 {
                        let key = Key::new(Pitch::fifths(p - MODES[mode].offset), mode)?;
                        if pitches.iter().all(|pitch| key.scale.contains(pitch)) { keys.push(key); }
                    }
                }
                let list = if keys.is_empty() { String::new() } else { format!(" {}", joined(&keys, ", ")) };
                vec![format!("FINDKEY {}{list}", keys.len())]
            }
            "SPELL" => {
                let value = number(a[0])?;
                let key = Key::parse(&a[1..])?;
                let pitch = key.scale.iter().copied().find(|pitch| pitch.class() == value % 12)
                    .unwrap_or_else(|| Note::spelling(value, key.fifths < 0).pitch);
                let note = Note::from_pitch(pitch, value);
                if !note.valid() { return Err("ERROR OUT OF RANGE".into()); }
                vec![format!("SPELL {value} {key} {note} {}", key.label(pitch))]
            }
            "KEYSIG" | "RELATIVE" | "DIATONIC" | "PROGRESSION" | "ANALYZE" | "DEGREE" | "KEYDIST" => {
                let key = Key::parse(a)?;
                match command {
                    "KEYSIG" => {
                        let p = key.fifths;
                        let suffix = if p == 0 { "none".to_string() } else {
                            let names = if p > 0 { ["F#", "C#", "G#", "D#", "A#", "E#", "B#"] }
                                else { ["Bb", "Eb", "Ab", "Db", "Gb", "Cb", "Fb"] };
                            format!("{}={} {}", if p > 0 { "sharps" } else { "flats" }, p.abs(), names[..p.unsigned_abs() as usize].join(" "))
                        };
                        vec![format!("KEYSIG {key} {suffix}")]
                    }
                    "RELATIVE" => vec![format!("RELATIVE {key} major={} minor={}", Pitch::fifths(key.fifths), Pitch::fifths(key.fifths + 3))],
                    "DEGREE" => {
                        let pitch = Pitch::parse(a[2])?;
                        vec![format!("DEGREE {key} {pitch} {}", key.label(pitch))]
                    }
                    "KEYDIST" => {
                        let other = Key::parse(&a[2..])?;
                        let r = (other.fifths - key.fifths).rem_euclid(12);
                        let fifths = if r > 6 { r - 12 } else { r };
                        let same_tonic = key.tonic.class() == other.tonic.class();
                        let relation = if key.set() == other.set() { if same_tonic { "same" } else { "relative" } }
                            else if same_tonic { "parallel" } else if fifths.abs() == 1 { "close" } else { "distant" };
                        let distance = if fifths > 0 { format!("+{fifths}") } else { fifths.to_string() };
                        vec![format!("KEYDIST {key} {other} fifths={distance} common={} relation={relation}", (key.set() & other.set()).count_ones())]
                    }
                    "DIATONIC" => {
                        let mut rows = vec![format!("DIATONIC {key}")];
                        for size in 3..=4 {
                            let mut items = Vec::new();
                            for i in 0..7 {
                                let root = key.scale[i];
                                let third = (key.scale[(i + 2) % 7].class() - root.class()).rem_euclid(12);
                                let fifth = (key.scale[(i + 4) % 7].class() - root.class()).rem_euclid(12);
                                let quality = if size == 3 { if third == 4 { 0 } else if fifth == 7 { 1 } else { 2 } }
                                    else {
                                        let seventh = (key.scale[(i + 6) % 7].class() - root.class()).rem_euclid(12);
                                        if third == 4 { if seventh == 11 { 9 } else { 8 } } else if fifth == 7 { 10 } else { 12 }
                                    };
                                items.push(format!("{}={}", roman(i, quality), symbol(root, quality, None)));
                            }
                            rows.push(format!("{} {}", if size == 3 { "TRIADS" } else { "SEVENTHS" }, items.join(" ")));
                        }
                        rows
                    }
                    "ANALYZE" => {
                        let symbols = a[2..].iter().map(|text| Symbol::parse(text)).collect::<Result<Vec<_>>>()?;
                        let items: Vec<_> = symbols.iter().map(|s| format!("{}{}", key.prefix(s.root), roman(key.degree(s.root), s.quality))).collect();
                        vec![format!("ANALYZE {key} {}", items.join(" "))]
                    }
                    "PROGRESSION" => {
                        let numerals = a[2..].iter().map(|text| Numeral::parse(text)).collect::<Result<Vec<_>>>()?;
                        let mut rows = vec![format!("PROGRESSION {key} {}", numerals.len())];
                        for (i, numeral) in numerals.iter().enumerate() {
                            let mut root = key.scale[numeral.degree];
                            root.alteration += numeral.alteration;
                            let notes = build(root, CHORDS[numeral.quality].tones)?;
                            rows.push(format!("{} {} {}", a[i + 2], symbol(root, numeral.quality, None), joined(&notes, " ")));
                        }
                        let mut cadence = "none";
                        if numerals.len() >= 2 {
                            let x = numerals[numerals.len() - 2];
                            let y = numerals[numerals.len() - 1];
                            cadence = match (x.alteration, x.degree, y.alteration, y.degree) {
                                (0, 4, 0, 0) => "authentic", (0, 3, 0, 0) => "plagal", (0, 4, 0, 5) => "deceptive",
                                (_, _, 0, 4) => "half", _ => "none",
                            };
                        }
                        rows.push(format!("CADENCE {cadence}"));
                        rows
                    }
                    _ => unreachable!(),
                }
            }
            _ => unreachable!(),
        })
    }
}

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap()?.parse().unwrap();
    let mut calculator = Calculator { tuning: 44000 };
    let mut output = io::BufWriter::new(io::stdout().lock());
    for _ in 0..count {
        let line = lines.next().unwrap()?;
        match calculator.execute(&line) {
            Ok(rows) => for row in rows { writeln!(output, "{row}")?; },
            Err(error) => writeln!(output, "{error}")?,
        }
    }
    Ok(())
}
