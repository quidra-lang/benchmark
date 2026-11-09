mod analysis;
mod playfair;
mod scoring;
mod substitution;
mod transposition;

use std::collections::{BTreeMap, HashSet};
use std::fmt::{self, Display};
use std::fs::{self, File};
use std::io::{self, BufWriter, Write};

use scoring::{is_letter, letter_string, letter_value, Weights};
use substitution::AFFINE_MULTIPLIERS;

const COMMANDS: [&str; 6] = ["ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY"];

#[derive(Clone, Copy, PartialEq, Eq)]
enum Cipher {
    Caesar,
    Affine,
    Vigenere,
    Autokey,
    Playfair,
    Railfence,
    Columnar,
}

impl Cipher {
    fn parse(word: &str) -> Result<Self, String> {
        match word {
            "caesar" => Ok(Self::Caesar),
            "affine" => Ok(Self::Affine),
            "vigenere" => Ok(Self::Vigenere),
            "autokey" => Ok(Self::Autokey),
            "playfair" => Ok(Self::Playfair),
            "railfence" => Ok(Self::Railfence),
            "columnar" => Ok(Self::Columnar),
            _ => Err(format!("unknown cipher {word}")),
        }
    }

    fn substitution(self) -> bool {
        matches!(self, Self::Caesar | Self::Affine | Self::Vigenere | Self::Autokey)
    }
}

impl Display for Cipher {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Caesar => "caesar",
            Self::Affine => "affine",
            Self::Vigenere => "vigenere",
            Self::Autokey => "autokey",
            Self::Playfair => "playfair",
            Self::Railfence => "railfence",
            Self::Columnar => "columnar",
        })
    }
}

#[derive(Clone)]
enum Key {
    Number(usize),
    Affine(usize, usize),
    Word(String),
}

impl Display for Key {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Number(value) => write!(formatter, "{value}"),
            Self::Affine(a, b) => write!(formatter, "{a},{b}"),
            Self::Word(word) => formatter.write_str(word),
        }
    }
}

fn valid_name(word: &str) -> bool {
    (1..=16).contains(&word.len())
        && word.bytes().all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_')
}

fn decimal(word: &str, max_digits: usize) -> Option<usize> {
    if (1..=max_digits).contains(&word.len()) && word.bytes().all(|byte| byte.is_ascii_digit()) {
        word.parse().ok()
    } else {
        None
    }
}

fn parse_key(cipher: Cipher, word: &str) -> Result<Key, String> {
    match cipher {
        Cipher::Caesar | Cipher::Railfence => {
            let (minimum, maximum) = if cipher == Cipher::Caesar { (0, 25) } else { (2, 20) };
            if let Some(value) = decimal(word, 2) {
                if (minimum..=maximum).contains(&value) {
                    return Ok(Key::Number(value));
                }
            }
        }
        Cipher::Affine => {
            if let Some((left, right)) = word.split_once(',') {
                if let (Some(a), Some(b)) = (decimal(left, 2), decimal(right, 2)) {
                    if AFFINE_MULTIPLIERS.contains(&a) && b <= 25 {
                        return Ok(Key::Affine(a, b));
                    }
                }
            }
        }
        Cipher::Columnar => {
            if (2..=9).contains(&word.len())
                && word.bytes().all(|byte| is_letter(byte) || byte.is_ascii_digit())
            {
                return Ok(Key::Word(word.to_ascii_uppercase()));
            }
        }
        _ => {
            let maximum = if cipher == Cipher::Playfair { 25 } else { 20 };
            if (1..=maximum).contains(&word.len()) && word.bytes().all(is_letter) {
                let key = word.to_ascii_uppercase();
                return Ok(Key::Word(if cipher == Cipher::Playfair { key.replace('J', "I") } else { key }));
            }
        }
    }
    Err(format!("bad key {word}"))
}

struct Options {
    top: usize,
    max_len: usize,
    max_rails: usize,
    ioc: i64,
    kasiski: usize,
    refine: usize,
    keys: Option<String>,
}

impl Options {
    fn defaults(cipher: Option<Cipher>) -> Self {
        Self {
            top: 5,
            max_len: match cipher {
                Some(Cipher::Autokey) => 8,
                Some(Cipher::Columnar) => 6,
                _ => 10,
            },
            max_rails: 10,
            ioc: 6000,
            kasiski: 60,
            refine: 5,
            keys: None,
        }
    }
}

fn option_limits(command: &str, cipher: Option<Cipher>, name: &str) -> Option<(usize, usize)> {
    match (command, cipher, name) {
        ("BREAK", _, "TOP") => Some((1, 20)),
        ("ANALYZE", _, "MAXLEN") | ("BREAK", Some(Cipher::Vigenere), "MAXLEN") => Some((2, 20)),
        ("BREAK", Some(Cipher::Autokey), "MAXLEN") => Some((1, 20)),
        ("BREAK", Some(Cipher::Columnar), "MAXLEN") => Some((2, 6)),
        ("BREAK", Some(Cipher::Railfence), "MAXRAILS") => Some((2, 20)),
        ("BREAK", Some(Cipher::Vigenere), "IOC") => Some((1, 100000)),
        ("BREAK", Some(Cipher::Vigenere), "KASISKI") => Some((1, 100)),
        ("BREAK", Some(Cipher::Vigenere), "REFINE") => Some((0, 10)),
        _ => None,
    }
}

fn parse_options(command: &str, cipher: Option<Cipher>, words: &[&str]) -> Result<Options, String> {
    let mut options = Options::defaults(cipher);
    let mut seen = HashSet::new();
    for &word in words {
        let invalid = || format!("bad option {word}");
        let (name, value) = word.split_once('=').ok_or_else(invalid)?;
        if !seen.insert(name) {
            return Err(invalid());
        }
        if name == "KEYS" && (command == "IDENTIFY" || (command == "BREAK" && cipher == Some(Cipher::Playfair))) {
            if !valid_name(value) {
                return Err(invalid());
            }
            options.keys = Some(value.to_owned());
            continue;
        }
        let (minimum, maximum) = option_limits(command, cipher, name).ok_or_else(invalid)?;
        let number = decimal(value, 6).filter(|number| (minimum..=maximum).contains(number)).ok_or_else(invalid)?;
        match name {
            "TOP" => options.top = number,
            "MAXLEN" => options.max_len = number,
            "MAXRAILS" => options.max_rails = number,
            "IOC" => options.ioc = number as i64,
            "KASISKI" => options.kasiski = number,
            "REFINE" => options.refine = number,
            _ => unreachable!(),
        }
    }
    if command == "BREAK" && cipher == Some(Cipher::Playfair) && options.keys.is_none() {
        return Err("missing option KEYS".to_owned());
    }
    Ok(options)
}

fn apply(cipher: Cipher, key: &Key, text: &str, decrypt: bool) -> String {
    match (cipher, key) {
        (Cipher::Caesar, Key::Number(value)) => substitution::caesar(text, *value, decrypt),
        (Cipher::Affine, Key::Affine(a, b)) => substitution::affine(text, *a, *b, decrypt),
        (Cipher::Vigenere, Key::Word(word)) => substitution::vigenere(text, word, decrypt),
        (Cipher::Autokey, Key::Word(word)) => substitution::autokey(text, word, decrypt),
        (Cipher::Playfair, Key::Word(word)) => playfair::apply(text, word, decrypt),
        (Cipher::Railfence, Key::Number(value)) => transposition::rail_fence(text, *value, decrypt),
        (Cipher::Columnar, Key::Word(word)) => transposition::columnar(text, word, decrypt),
        _ => unreachable!(),
    }
}

fn group_form(text: &str) -> Vec<String> {
    text.as_bytes().chunks(50).map(|line| {
        line.chunks(5).map(|group| std::str::from_utf8(group).unwrap()).collect::<Vec<_>>().join(" ")
    }).collect()
}

fn solution_lines(cipher: Cipher, key: &Key, text: &str, letters: &str) -> Vec<String> {
    if cipher.substitution() {
        apply(cipher, key, text, true).split('\n').map(str::to_owned).collect()
    } else {
        group_form(&apply(cipher, key, letters, true))
    }
}

fn as_suffix(name: Option<&str>) -> String {
    name.map(|name| format!(" as={name}")).unwrap_or_default()
}

fn number_list<T: Display>(numbers: &[T]) -> String {
    numbers.iter().map(ToString::to_string).collect::<Vec<_>>().join(",")
}

fn count_list(entries: &[(String, usize)]) -> String {
    entries.iter().take(10).map(|(pair, count)| format!("{pair}:{count}")).collect::<Vec<_>>().join(" ")
}

fn playfair_keys(text: &str) -> Vec<String> {
    let mut seen = HashSet::new();
    text.split(|character: char| !character.is_ascii_alphabetic())
        .filter(|word| !word.is_empty())
        .map(|word| word.to_ascii_uppercase().replace('J', "I"))
        .filter(|word| seen.insert(word.clone()))
        .collect()
}

struct Period {
    length: usize,
    indices: Vec<i64>,
    average: i64,
    kasiski: usize,
}

struct Profile {
    periods: Vec<Period>,
    repeats: Vec<analysis::Repeat>,
    gap_count: usize,
}

impl Profile {
    fn new(text: &str, max_len: usize) -> Self {
        let repeats = analysis::repeated_trigrams(text);
        let gaps: Vec<usize> = repeats.iter().flat_map(|repeat| repeat.gaps.iter().copied()).collect();
        let periods = (1..=max_len).map(|length| {
            let indices = analysis::column_indices(text, length);
            let average = indices.iter().sum::<i64>() / length as i64;
            let kasiski = gaps.iter().filter(|&&gap| gap % length == 0).count();
            Period { length, indices, average, kasiski }
        }).collect();
        Self { periods, repeats, gap_count: gaps.len() }
    }

    fn key_length(&self, options: &Options) -> (usize, &'static str) {
        if self.gap_count > 0 {
            if let Some(period) = self.periods.iter().skip(1).rev()
                .find(|period| 100 * period.kasiski >= options.kasiski * self.gap_count)
            {
                if period.average >= options.ioc {
                    return (period.length, "kasiski");
                }
            }
        }
        if let Some(period) = self.periods.iter().find(|period| period.average >= options.ioc) {
            return (period.length, "ioc");
        }
        let mut best = &self.periods[0];
        for period in &self.periods[1..] {
            if period.average > best.average {
                best = period;
            }
        }
        (best.length, "maxioc")
    }

    fn lines(&self) -> Vec<String> {
        let mut lines: Vec<String> = self.periods.iter().map(|period| {
            format!("L={} ioc={} kasiski={} cols={}", period.length, period.average, period.kasiski, number_list(&period.indices))
        }).collect();
        lines.push(format!("kasiski repeats={} spacings={}", self.repeats.len(), self.gap_count));
        for repeat in &self.repeats {
            lines.push(format!("{} at={} gaps={} gcd={}", repeat.trigram, number_list(&repeat.positions), number_list(&repeat.gaps), repeat.gcd));
        }
        lines
    }
}

struct Candidate {
    key: Key,
    plaintext: String,
    score: i64,
}

struct BreakResult {
    key: Key,
    score: i64,
    candidates: Vec<Candidate>,
    profile: Option<Profile>,
    length: usize,
    method: &'static str,
    passes: usize,
    changes: usize,
}

fn permutation_keys(width: usize, prefix: &mut String, keys: &mut Vec<Key>) {
    if prefix.len() == width {
        keys.push(Key::Word(prefix.clone()));
        return;
    }
    for byte in b'1'..b'1' + width as u8 {
        if !prefix.as_bytes().contains(&byte) {
            prefix.push(byte as char);
            permutation_keys(width, prefix, keys);
            prefix.pop();
        }
    }
}

struct CipherDesk {
    weights: Weights,
    messages: BTreeMap<String, Vec<String>>,
    jobs: usize,
    ok: [usize; 6],
    errors: [usize; 6],
    results: Vec<String>,
    candidates: Vec<String>,
    analyses: Vec<String>,
}

impl CipherDesk {
    fn new(weights: Weights, messages: BTreeMap<String, Vec<String>>) -> Self {
        Self { weights, messages, jobs: 0, ok: [0; 6], errors: [0; 6], results: Vec::new(), candidates: Vec::new(), analyses: Vec::new() }
    }

    fn message_text(&self, name: &str) -> Result<String, String> {
        self.messages.get(name).map(|lines| lines.join("\n")).ok_or_else(|| format!("unknown message {name}"))
    }

    fn require_unused(&self, name: Option<&str>) -> Result<(), String> {
        if let Some(name) = name {
            if self.messages.contains_key(name) {
                return Err(format!("duplicate message {name}"));
            }
        }
        Ok(())
    }

    fn key_list(&self, options: &Options) -> Result<Option<Vec<String>>, String> {
        options.keys.as_ref().map(|name| self.message_text(name).map(|text| playfair_keys(&text))).transpose()
    }

    fn store(&mut self, name: Option<&str>, lines: &[String]) {
        if let Some(name) = name {
            self.messages.insert(name.to_owned(), lines.to_vec());
        }
    }

    fn score(&self, cipher: Cipher, text: &str) -> i64 {
        if matches!(cipher, Cipher::Caesar | Cipher::Affine) { self.weights.monogram(text) } else { self.weights.bigram(text) }
    }

    fn column_key(&self, cipher: Cipher, text: &str, length: usize) -> String {
        analysis::columns(text, length).iter().map(|column| {
            let mut best_shift = 0;
            let mut best_score = -1;
            for shift in 0..26 {
                let mut previous = shift;
                let mut score = 0;
                for byte in column.bytes() {
                    let plain = (letter_value(byte) as i32 - previous).rem_euclid(26);
                    score += self.weights.monograms[plain as usize];
                    if cipher == Cipher::Autokey {
                        previous = plain;
                    }
                }
                if score > best_score {
                    best_score = score;
                    best_shift = shift;
                }
            }
            (b'A' + best_shift as u8) as char
        }).collect()
    }

    fn break_cipher(&self, cipher: Cipher, text: &str, options: &Options, key_list: Option<&[String]>) -> BreakResult {
        let mut keys = Vec::new();
        match cipher {
            Cipher::Caesar => keys.extend((0..26).map(Key::Number)),
            Cipher::Affine => {
                for &a in &AFFINE_MULTIPLIERS {
                    keys.extend((0..26).map(|b| Key::Affine(a, b)));
                }
            }
            Cipher::Railfence => keys.extend((2..=options.max_rails).map(Key::Number)),
            Cipher::Columnar => {
                for width in 2..=options.max_len {
                    permutation_keys(width, &mut String::new(), &mut keys);
                }
            }
            Cipher::Playfair => keys.extend(key_list.unwrap().iter().cloned().map(Key::Word)),
            Cipher::Vigenere | Cipher::Autokey => {
                keys.extend((1..=options.max_len).map(|length| Key::Word(self.column_key(cipher, text, length))));
            }
        }
        let mut candidates: Vec<Candidate> = keys.into_iter().map(|key| {
            let plaintext = apply(cipher, &key, text, true);
            let score = self.score(cipher, &plaintext);
            Candidate { key, plaintext, score }
        }).collect();
        candidates.sort_by(|a, b| b.score.cmp(&a.score));
        let mut result = BreakResult {
            key: candidates[0].key.clone(), score: candidates[0].score, candidates,
            profile: None, length: 0, method: "", passes: 0, changes: 0,
        };
        if cipher == Cipher::Vigenere {
            self.refine_vigenere(text, options, &mut result);
        }
        result
    }

    fn refine_vigenere(&self, text: &str, options: &Options, result: &mut BreakResult) {
        let profile = Profile::new(text, options.max_len);
        let (length, method) = profile.key_length(options);
        let candidate = result.candidates.iter().find(|candidate| {
            matches!(&candidate.key, Key::Word(word) if word.len() == length)
        }).unwrap();
        let mut key = candidate.key.to_string().into_bytes();
        let mut reference = candidate.score;
        for _ in 0..options.refine {
            result.passes += 1;
            let mut changed = false;
            for index in 0..length {
                let mut best_letter = key[index];
                let mut best_score = reference;
                for letter in b'A'..=b'Z' {
                    key[index] = letter;
                    let plaintext = substitution::vigenere(text, std::str::from_utf8(&key).unwrap(), true);
                    let score = self.weights.bigram(&plaintext);
                    if score > best_score {
                        best_letter = letter;
                        best_score = score;
                    }
                }
                key[index] = best_letter;
                if best_score > reference {
                    reference = best_score;
                    result.changes += 1;
                    changed = true;
                }
            }
            if !changed {
                break;
            }
        }
        result.key = Key::Word(String::from_utf8(key).unwrap());
        result.score = reference;
        result.profile = Some(profile);
        result.length = length;
        result.method = method;
    }

    fn run(&mut self, line: &str) {
        self.jobs += 1;
        let words: Vec<&str> = line.split(' ').collect();
        let command = words[0];
        let Some(index) = COMMANDS.iter().position(|&name| name == command) else {
            self.results.push(format!("JOB {} ERROR unknown command", self.jobs));
            return;
        };
        match self.execute(command, words) {
            Ok(()) => self.ok[index] += 1,
            Err(reason) => {
                self.errors[index] += 1;
                self.results.push(format!("JOB {} ERROR {reason}", self.jobs));
            }
        }
    }

    fn execute(&mut self, command: &str, mut words: Vec<&str>) -> Result<(), String> {
        let mut new_name = None;
        if matches!(command, "ENCRYPT" | "DECRYPT" | "BREAK") && words.len() >= 5 && words[words.len() - 2] == "AS" {
            let name = words[words.len() - 1];
            if !valid_name(name) {
                return Err("bad syntax".to_owned());
            }
            new_name = Some(name);
            words.truncate(words.len() - 2);
        }
        let valid = match command {
            "ENCRYPT" | "DECRYPT" => words.len() == 4,
            "BREAK" => words.len() >= 3,
            "ANALYZE" | "IDENTIFY" => (2..=3).contains(&words.len()),
            _ => words.len() == 3,
        };
        if !valid {
            return Err("bad syntax".to_owned());
        }
        match command {
            "ENCRYPT" | "DECRYPT" => self.transform(command, &words, new_name),
            "BREAK" => self.break_message(&words, new_name),
            "ANALYZE" => self.analyze(&words),
            "COMPARE" => self.compare(&words),
            _ => self.identify(&words),
        }
    }

    fn transform(&mut self, command: &str, words: &[&str], new_name: Option<&str>) -> Result<(), String> {
        let cipher = Cipher::parse(words[1])?;
        let key = parse_key(cipher, words[2])?;
        let source = words[3];
        let text = self.message_text(source)?;
        self.require_unused(new_name)?;
        let letters = letter_string(&text);
        if letters.is_empty() {
            return Err("no letters".to_owned());
        }
        let decrypt = command == "DECRYPT";
        if decrypt && cipher == Cipher::Playfair && !playfair::valid_ciphertext(&letters) {
            return Err("bad playfair text".to_owned());
        }
        let lines: Vec<String> = if cipher.substitution() {
            apply(cipher, &key, &text, decrypt).split('\n').map(str::to_owned).collect()
        } else {
            group_form(&apply(cipher, &key, &letters, decrypt))
        };
        let count: usize = lines.iter().map(|line| letter_string(line).len()).sum();
        self.results.push(format!("JOB {} {command} {cipher} key={key} source={source} letters={count} lines={}{}", self.jobs, lines.len(), as_suffix(new_name)));
        self.store(new_name, &lines);
        self.results.extend(lines);
        Ok(())
    }

    fn break_message(&mut self, words: &[&str], new_name: Option<&str>) -> Result<(), String> {
        let cipher = Cipher::parse(words[1])?;
        let source = words[2];
        let options = parse_options("BREAK", Some(cipher), &words[3..])?;
        let text = self.message_text(source)?;
        let key_list = self.key_list(&options)?;
        self.require_unused(new_name)?;
        let letters = letter_string(&text);
        if letters.len() < 40 {
            return Err("text too short".to_owned());
        }
        if cipher == Cipher::Playfair {
            if !playfair::valid_ciphertext(&letters) {
                return Err("bad playfair text".to_owned());
            }
            if key_list.as_ref().unwrap().is_empty() {
                return Err("empty key list".to_owned());
            }
        }
        let result = self.break_cipher(cipher, &letters, &options, key_list.as_deref());
        let lines = solution_lines(cipher, &result.key, &text, &letters);
        self.results.push(format!("JOB {} BREAK {cipher} source={source} key={} score={} lines={}{}", self.jobs, result.key, result.score, lines.len(), as_suffix(new_name)));
        self.store(new_name, &lines);
        self.results.extend(lines);
        let margin = if result.candidates.len() > 1 { result.candidates[0].score - result.candidates[1].score } else { 0 };
        self.candidates.push(format!("JOB {} BREAK {cipher} source={source} tried={} margin={margin}", self.jobs, result.candidates.len()));
        for (index, candidate) in result.candidates.iter().take(options.top).enumerate() {
            self.candidates.push(format!("{} {} {} {}", index + 1, candidate.key, candidate.score, &candidate.plaintext[..40]));
        }
        if cipher == Cipher::Vigenere {
            self.analyses.push(format!("JOB {} BREAK vigenere source={source}", self.jobs));
            self.analyses.push(format!("letters={}", letters.len()));
            self.analyses.extend(result.profile.as_ref().unwrap().lines());
            self.analyses.push(format!("decision length={} method={}", result.length, result.method));
            self.analyses.push(format!("refine passes={} changes={} key={}", result.passes, result.changes, result.key));
        } else if cipher == Cipher::Playfair {
            let normalized = letters.replace('J', "I");
            let counts = analysis::pair_counts(&normalized, 2);
            let square = playfair::build_square(&result.key.to_string());
            let rows = square.as_bytes().chunks(5).map(|row| std::str::from_utf8(row).unwrap()).collect::<Vec<_>>().join(" ");
            self.analyses.extend([
                format!("JOB {} BREAK playfair source={source}", self.jobs),
                format!("letters={}", letters.len()),
                format!("digraphs pairs={} distinct={}", normalized.len() / 2, counts.len()),
                format!("top {}", count_list(&counts)),
                format!("square {rows}"),
            ]);
        }
        Ok(())
    }

    fn analyze(&mut self, words: &[&str]) -> Result<(), String> {
        let source = words[1];
        let options = parse_options("ANALYZE", None, &words[2..])?;
        let letters = letter_string(&self.message_text(source)?);
        let count = letters.len();
        if count < 40 {
            return Err("text too short".to_owned());
        }
        let counts = analysis::letter_counts(&letters);
        let doubles: Vec<usize> = letters.as_bytes().windows(2).enumerate().filter_map(|(index, pair)| (pair[0] == pair[1]).then_some(index)).collect();
        let pair_doubles = doubles.iter().filter(|&&index| index % 2 == 0).count();
        self.results.push(format!("JOB {} ANALYZE source={source} letters={count}", self.jobs));
        self.analyses.extend([
            format!("JOB {} ANALYZE source={source}", self.jobs),
            format!("letters={count}"),
            format!("ioc={} mono={} bigram={}", analysis::index_of_coincidence(&letters), self.weights.monogram(&letters), self.weights.bigram(&letters)),
            format!("doubles={} pair_doubles={pair_doubles} distinct={}", doubles.len(), counts.iter().filter(|&&value| value > 0).count()),
        ]);
        for (index, &occurrences) in counts.iter().enumerate() {
            self.analyses.push(format!("{} {occurrences} {}", (b'A' + index as u8) as char, analysis::percentage(occurrences, count)));
        }
        self.analyses.push(format!("bigrams {}", count_list(&analysis::pair_counts(&letters, 1))));
        self.analyses.extend(Profile::new(&letters, options.max_len).lines());
        Ok(())
    }

    fn compare(&mut self, words: &[&str]) -> Result<(), String> {
        let (first_name, second_name) = (words[1], words[2]);
        let first = letter_string(&self.message_text(first_name)?);
        let second = letter_string(&self.message_text(second_name)?);
        let prefix = format!("JOB {} COMPARE {first_name} {second_name}", self.jobs);
        if first == second {
            self.results.push(format!("{prefix} equal letters={}", first.len()));
        } else {
            let mismatches: Vec<usize> = first.bytes().zip(second.bytes()).enumerate().filter_map(|(index, (a, b))| (a != b).then_some(index + 1)).collect();
            let first_mismatch = mismatches.first().copied().unwrap_or(first.len().min(second.len()) + 1);
            self.results.push(format!("{prefix} differ letters={},{} first={first_mismatch} mismatches={}", first.len(), second.len(), mismatches.len()));
        }
        Ok(())
    }

    fn identify(&mut self, words: &[&str]) -> Result<(), String> {
        let source = words[1];
        let options = parse_options("IDENTIFY", None, &words[2..])?;
        let text = self.message_text(source)?;
        let key_list = self.key_list(&options)?;
        let letters = letter_string(&text);
        let count = letters.len();
        if count < 40 {
            return Err("text too short".to_owned());
        }
        let ioc = analysis::index_of_coincidence(&letters);
        let average = self.weights.monogram(&letters) / count as i64;
        let distinct = analysis::letter_counts(&letters).iter().filter(|&&value| value > 0).count();
        let shaped = count % 2 == 0 && !letters.contains('J') && playfair::valid_ciphertext(&letters);
        let family = if shaped { "playfair" } else if ioc >= 5500 && average >= 44 { "transposition" } else if ioc >= 5500 { "monoalphabetic" } else { "polyalphabetic" };
        if family == "playfair" && key_list.as_ref().is_some_and(Vec::is_empty) {
            return Err("empty key list".to_owned());
        }
        let ciphers = match family {
            "playfair" if key_list.is_some() => vec![Cipher::Playfair],
            "playfair" => Vec::new(),
            "transposition" => vec![Cipher::Railfence, Cipher::Columnar],
            "monoalphabetic" => vec![Cipher::Affine],
            _ => vec![Cipher::Vigenere, Cipher::Autokey],
        };
        let tried: Vec<(Cipher, BreakResult)> = ciphers.into_iter().map(|cipher| {
            let result = self.break_cipher(cipher, &letters, &Options::defaults(Some(cipher)), key_list.as_deref());
            (cipher, result)
        }).collect();
        self.analyses.extend([
            format!("JOB {} IDENTIFY source={source}", self.jobs),
            format!("letters={count} ioc={ioc} mono_avg={average} distinct={distinct} shape={}", if shaped { "yes" } else { "no" }),
            format!("family={family}"),
        ]);
        for (cipher, result) in &tried {
            self.analyses.push(format!("try {cipher} key={} score={}", result.key, result.score));
        }
        let header = format!("JOB {} IDENTIFY source={source} family={family}", self.jobs);
        if tried.is_empty() {
            self.results.push(header);
            return Ok(());
        }
        let mut chosen = 0;
        for index in 1..tried.len() {
            if tried[index].1.score > tried[chosen].1.score {
                chosen = index;
            }
        }
        let mut cipher = tried[chosen].0;
        let result = &tried[chosen].1;
        let mut key = result.key.clone();
        if cipher == Cipher::Affine {
            if let Key::Affine(1, b) = &key {
                cipher = Cipher::Caesar;
                key = Key::Number(*b);
            }
        }
        let lines = solution_lines(cipher, &key, &text, &letters);
        self.results.push(format!("{header} cipher={cipher} key={key} score={} lines={}", result.score, lines.len()));
        self.results.extend(lines);
        self.analyses.push(format!("choice {cipher}"));
        Ok(())
    }

    fn finish(&mut self) {
        for (index, command) in COMMANDS.iter().enumerate() {
            self.results.push(format!("TOTAL {command} ok={} errors={}", self.ok[index], self.errors[index]));
        }
        let ok: usize = self.ok.iter().sum();
        self.results.push(format!("SUMMARY jobs={} ok={ok} errors={} messages={}", self.jobs, self.jobs - ok, self.messages.len()));
    }
}

fn parse_messages(text: &str) -> BTreeMap<String, Vec<String>> {
    let mut messages = BTreeMap::new();
    let mut lines = text.split_terminator('\n');
    while let Some(line) = lines.next() {
        if let Some(name) = line.strip_prefix("MESSAGE ") {
            let mut body = Vec::new();
            for line in lines.by_ref() {
                if line == "END" {
                    break;
                }
                body.push(line.to_owned());
            }
            messages.insert(name.to_owned(), body);
        }
    }
    messages
}

fn write_lines(path: &str, lines: &[String]) -> io::Result<()> {
    let mut writer = BufWriter::new(File::create(path)?);
    for line in lines {
        writeln!(writer, "{line}")?;
    }
    writer.flush()
}

fn main() -> io::Result<()> {
    let weights = Weights::parse(&fs::read_to_string("input/weights.txt")?)?;
    let messages = parse_messages(&fs::read_to_string("input/messages.txt")?);
    let mut desk = CipherDesk::new(weights, messages);
    for line in fs::read_to_string("input/jobs.txt")?.lines().filter(|line| !line.is_empty() && !line.starts_with('#')) {
        desk.run(line);
    }
    desk.finish();
    fs::create_dir_all("output")?;
    write_lines("output/results.txt", &desk.results)?;
    write_lines("output/candidates.txt", &desk.candidates)?;
    write_lines("output/analysis.txt", &desk.analyses)
}
