use std::cmp::Reverse;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt::{Display, Write as _};
use std::io::{self, Read, Write};

const ADJACENT_KEYS: [&str; 26] = [
    "qswz", "ghnv", "dfvx", "cefrsx", "drsw", "cdgrtv", "bfhtvy", "bgjnuy", "jkou", "hikmnu",
    "ijlmo", "kop", "jkn", "bhjm", "iklp", "lo", "aw", "deft", "adewxz", "fgry", "hijy", "bcfg",
    "aeqs", "cdsz", "ghtu", "asx",
];
// h and w map to 0: that is their value as a first letter, and they are skipped elsewhere
const SOUNDEX_DIGITS: &[u8; 26] = b"01230120022455012623010202";
const SENTENCE_MARKS: [char; 3] = ['.', '!', '?'];
const FINDING_KINDS: [&str; 4] = ["unknown", "case", "capital", "repeats"];
const KEYBOARD_MODES: [&str; 2] = ["ON", "OFF"];
const MAX_WORD_LENGTH: usize = 30;
const MAX_FREQUENCY: u32 = 1_000_000;
const MAX_LISTED: u32 = 20;
const REPORT_SIZE: usize = 10;

type CommandResult = Result<(), String>;

fn word_argument(text: &str) -> Result<String, String> {
    if (1..=MAX_WORD_LENGTH).contains(&text.len()) && text.bytes().all(|c| c.is_ascii_alphabetic())
    {
        Ok(text.to_ascii_lowercase())
    } else {
        Err(format!("BAD WORD {text}"))
    }
}

fn number_argument(text: &str, minimum: u32, maximum: u32) -> Result<u32, String> {
    let valid = (1..=7).contains(&text.len()) && text.bytes().all(|c| c.is_ascii_digit());
    match text.parse::<u32>() {
        Ok(value) if valid && (minimum..=maximum).contains(&value) => Ok(value),
        _ => Err(format!("BAD NUMBER {text}")),
    }
}

fn decimal_text(numerator: usize, denominator: usize, digits: u32) -> String {
    let scale = 10usize.pow(digits);
    let value = (2 * numerator * scale + denominator) / (2 * denominator);
    format!(
        "{}.{:0width$}",
        value / scale,
        value % scale,
        width = digits as usize
    )
}

fn listing<T: Display>(head: String, items: impl IntoIterator<Item = T>) -> String {
    let mut line = head;
    for item in items {
        write!(line, " {item}").unwrap();
    }
    line
}

fn is_all_upper(text: &str) -> bool {
    text.bytes().all(|c| c.is_ascii_uppercase())
}

fn capitalize_first(word: &str) -> String {
    let mut result = word.to_string();
    result[..1].make_ascii_uppercase();
    result
}

fn apply_case(token_text: &str, word: &str) -> String {
    if token_text.len() >= 2 && is_all_upper(token_text) {
        word.to_ascii_uppercase()
    } else if token_text.starts_with(|c: char| c.is_ascii_uppercase()) {
        capitalize_first(word)
    } else {
        word.to_string()
    }
}

struct Token {
    number: usize,
    text: String,
    word: String,
    end: usize,
    gap: String,
    sentence_start: bool,
    repeat: bool,
}

impl Token {
    fn mixed_case(&self) -> bool {
        self.text[1..].bytes().any(|c| c.is_ascii_uppercase()) && !is_all_upper(&self.text)
    }
}

fn tokenize(text: &str) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut tokens: Vec<Token> = Vec::new();
    let mut position = 0;
    let mut index = 0;
    while index < bytes.len() {
        if !bytes[index].is_ascii_alphabetic() {
            index += 1;
            continue;
        }
        let start = index;
        while index < bytes.len() && bytes[index].is_ascii_alphabetic() {
            index += 1;
        }
        let gap = &text[position..start];
        let word = text[start..index].to_ascii_lowercase();
        let previous = tokens.last();
        let sentence_start = previous.is_none() || gap.contains(SENTENCE_MARKS);
        let repeat = previous.is_some_and(|previous| previous.word == word)
            && gap.bytes().all(|c| c == b' ');
        tokens.push(Token {
            number: tokens.len() + 1,
            text: text[start..index].to_string(),
            word,
            end: index,
            gap: gap.to_string(),
            sentence_start,
            repeat,
        });
        position = index;
    }
    tokens
}

fn gap_cost(keyboard: bool) -> usize {
    if keyboard { 2 } else { 1 }
}

fn substitution_cost(first: u8, second: u8, keyboard: bool) -> usize {
    if first == second {
        0
    } else if !keyboard {
        1
    } else if ADJACENT_KEYS[(first - b'a') as usize]
        .as_bytes()
        .contains(&second)
    {
        1
    } else {
        2
    }
}

fn is_swap(first: &[u8], second: &[u8], i: usize, j: usize) -> bool {
    i >= 2 && j >= 2 && first[i - 1] == second[j - 2] && first[i - 2] == second[j - 1]
}

fn distance_table(first: &[u8], second: &[u8], keyboard: bool) -> Vec<Vec<usize>> {
    let gap = gap_cost(keyboard);
    let mut table = vec![vec![0; second.len() + 1]; first.len() + 1];
    for (i, row) in table.iter_mut().enumerate() {
        row[0] = i * gap;
    }
    for (j, cell) in table[0].iter_mut().enumerate() {
        *cell = j * gap;
    }
    for i in 1..=first.len() {
        for j in 1..=second.len() {
            let substitution = substitution_cost(first[i - 1], second[j - 1], keyboard);
            let mut best = (table[i - 1][j] + gap)
                .min(table[i][j - 1] + gap)
                .min(table[i - 1][j - 1] + substitution);
            if is_swap(first, second, i, j) {
                best = best.min(table[i - 2][j - 2] + 1);
            }
            table[i][j] = best;
        }
    }
    table
}

fn edit_distance(first: &str, second: &str, keyboard: bool) -> usize {
    distance_table(first.as_bytes(), second.as_bytes(), keyboard)[first.len()][second.len()]
}

fn prefix_distance(word: &str, other: &str, keyboard: bool) -> usize {
    let table = distance_table(word.as_bytes(), other.as_bytes(), keyboard);
    *table[word.len()].iter().min().unwrap()
}

fn edit_operations(first: &str, second: &str, keyboard: bool) -> (usize, Vec<String>) {
    let first = first.as_bytes();
    let second = second.as_bytes();
    let table = distance_table(first, second, keyboard);
    let gap = gap_cost(keyboard);
    let mut operations = Vec::new();
    let (mut i, mut j) = (first.len(), second.len());
    while i > 0 || j > 0 {
        if i >= 1
            && j >= 1
            && table[i][j]
                == table[i - 1][j - 1] + substitution_cost(first[i - 1], second[j - 1], keyboard)
        {
            if first[i - 1] != second[j - 1] {
                operations.push(format!(
                    "sub:{}>{}",
                    first[i - 1] as char,
                    second[j - 1] as char
                ));
            }
            i -= 1;
            j -= 1;
        } else if is_swap(first, second, i, j) && table[i][j] == table[i - 2][j - 2] + 1 {
            operations.push(format!(
                "swap:{}{}",
                first[i - 2] as char,
                first[i - 1] as char
            ));
            i -= 2;
            j -= 2;
        } else if i >= 1 && table[i][j] == table[i - 1][j] + gap {
            operations.push(format!("del:{}", first[i - 1] as char));
            i -= 1;
        } else {
            operations.push(format!("ins:{}", second[j - 1] as char));
            j -= 1;
        }
    }
    operations.reverse();
    (table[first.len()][second.len()], operations)
}

fn soundex(word: &str) -> String {
    let letters = word.as_bytes();
    let mut code = String::from(letters[0].to_ascii_uppercase() as char);
    let mut previous = SOUNDEX_DIGITS[(letters[0] - b'a') as usize];
    for &letter in &letters[1..] {
        if letter == b'h' || letter == b'w' {
            continue;
        }
        let digit = SOUNDEX_DIGITS[(letter - b'a') as usize];
        if digit != b'0' && digit != previous {
            code.push(digit as char);
        }
        previous = digit;
    }
    code.push_str("000");
    code.truncate(4);
    code
}

fn segment<'a>(word: &'a str, dictionary: &HashMap<String, u32>) -> (u64, Option<Vec<&'a str>>) {
    let length = word.len();
    let mut ways = vec![0u64; length + 1];
    let mut best: Vec<Option<Vec<&str>>> = vec![None; length + 1];
    ways[length] = 1;
    best[length] = Some(Vec::new());
    for start in (0..length).rev() {
        for end in start + 1..=length {
            let piece = &word[start..end];
            let Some(rest) = &best[end] else { continue };
            if !dictionary.contains_key(piece) {
                continue;
            }
            ways[start] += ways[end];
            let candidate: Vec<&str> = std::iter::once(piece).chain(rest.iter().copied()).collect();
            let better = match &best[start] {
                None => true,
                Some(current) => (candidate.len(), &candidate) < (current.len(), current),
            };
            if better {
                best[start] = Some(candidate);
            }
        }
    }
    (ways[0], best.swap_remove(0))
}

struct UndoRecord {
    name: &'static str,
    dictionary: HashMap<String, u32>,
    ignored: HashSet<String>,
    rules: BTreeMap<String, String>,
}

#[derive(Default)]
struct Counters {
    checked: usize,
    unknown: usize,
    case: usize,
    capital: usize,
    repeats: usize,
    corrected: usize,
}

#[derive(Clone, Copy)]
enum Handler {
    Text(fn(&mut SpellChecker, &str)),
    Words(usize, fn(&mut SpellChecker, &[&str]) -> CommandResult),
}

const COMMANDS: [(&str, Handler); 27] = [
    ("CHECK", Handler::Text(SpellChecker::check)),
    ("CORRECT", Handler::Text(SpellChecker::correct)),
    ("FIX", Handler::Text(SpellChecker::fix)),
    ("PROFILE", Handler::Text(SpellChecker::profile)),
    ("LEARN", Handler::Text(SpellChecker::learn)),
    ("SUGGEST", Handler::Words(1, SpellChecker::suggest)),
    ("DIST", Handler::Words(2, SpellChecker::dist)),
    ("SOUNDEX", Handler::Words(1, SpellChecker::soundex_code)),
    ("SOUNDS", Handler::Words(1, SpellChecker::sounds)),
    ("SPLIT", Handler::Words(1, SpellChecker::split)),
    ("PREFIX", Handler::Words(2, SpellChecker::prefix)),
    ("COMPLETE", Handler::Words(2, SpellChecker::complete)),
    ("LIST", Handler::Words(2, SpellChecker::list_words)),
    ("WORD", Handler::Words(1, SpellChecker::word_info)),
    ("ADD", Handler::Words(2, SpellChecker::add)),
    ("REMOVE", Handler::Words(1, SpellChecker::remove)),
    ("IGNORE", Handler::Words(1, SpellChecker::ignore)),
    ("UNIGNORE", Handler::Words(1, SpellChecker::unignore)),
    ("RULE", Handler::Words(2, SpellChecker::rule)),
    ("UNRULE", Handler::Words(1, SpellChecker::unrule)),
    ("RULES", Handler::Words(0, SpellChecker::show_rules)),
    ("KEYBOARD", Handler::Words(1, SpellChecker::keyboard_mode)),
    ("SET", Handler::Words(2, SpellChecker::set_option)),
    ("UNDO", Handler::Words(0, SpellChecker::undo)),
    ("REPORT", Handler::Words(0, SpellChecker::report)),
    ("HISTORY", Handler::Words(0, SpellChecker::history)),
    ("STATS", Handler::Words(0, SpellChecker::stats)),
];

struct SpellChecker {
    dictionary: HashMap<String, u32>,
    ignored: HashSet<String>,
    rules: BTreeMap<String, String>,
    keyboard: bool,
    base_limit: usize,
    suggestion_count: usize,
    undo_history: Vec<UndoRecord>,
    unknown_log: HashMap<String, u32>,
    correction_log: HashMap<(String, String), u32>,
    counters: Counters,
    output: Vec<String>,
}

impl SpellChecker {
    fn new(dictionary: HashMap<String, u32>) -> Self {
        SpellChecker {
            dictionary,
            ignored: HashSet::new(),
            rules: BTreeMap::new(),
            keyboard: false,
            base_limit: 2,
            suggestion_count: 5,
            undo_history: Vec::new(),
            unknown_log: HashMap::new(),
            correction_log: HashMap::new(),
            counters: Counters::default(),
            output: Vec::new(),
        }
    }

    fn emit(&mut self, line: String) {
        self.output.push(line);
    }

    fn limit(&self) -> usize {
        if self.keyboard {
            2 * self.base_limit
        } else {
            self.base_limit
        }
    }

    fn is_known(&self, word: &str) -> bool {
        self.dictionary.contains_key(word) || self.ignored.contains(word)
    }

    fn frequency_order(&self) -> Vec<&str> {
        let mut entries: Vec<(&String, &u32)> = self.dictionary.iter().collect();
        entries.sort_by_key(|&(word, &frequency)| (Reverse(frequency), word));
        entries.into_iter().map(|(word, _)| word.as_str()).collect()
    }

    fn require_entry(&self, word: &str) -> Result<u32, String> {
        self.dictionary
            .get(word)
            .copied()
            .ok_or_else(|| format!("NOT FOUND {word}"))
    }

    fn candidates(&self, word: &str) -> Vec<(String, usize)> {
        let limit = self.limit();
        let gap = gap_cost(self.keyboard);
        let mut found: Vec<(usize, Reverse<u32>, &String)> = self
            .dictionary
            .iter()
            .filter(|(other, _)| *other != word && other.len().abs_diff(word.len()) * gap <= limit)
            .map(|(other, &frequency)| {
                (
                    edit_distance(word, other, self.keyboard),
                    Reverse(frequency),
                    other,
                )
            })
            .filter(|(distance, _, _)| *distance <= limit)
            .collect();
        found.sort();
        found
            .into_iter()
            .map(|(distance, _, other)| (other.clone(), distance))
            .collect()
    }

    fn correction(&self, word: &str) -> Option<String> {
        if self.is_known(word) {
            return None;
        }
        if let Some(target) = self.rules.get(word) {
            return Some(target.clone());
        }
        self.candidates(word)
            .into_iter()
            .next()
            .map(|(other, _)| other)
    }

    fn record_undo(&mut self, name: &'static str) {
        self.undo_history.push(UndoRecord {
            name,
            dictionary: self.dictionary.clone(),
            ignored: self.ignored.clone(),
            rules: self.rules.clone(),
        });
    }

    fn log_correction(&mut self, word: &str, replacement: &str) {
        let key = (word.to_string(), replacement.to_string());
        *self.correction_log.entry(key).or_default() += 1;
        self.counters.corrected += 1;
    }

    fn unknown_finding(&self, token: &Token) -> String {
        let prefix = format!("UNKNOWN {} {}", token.number, token.text);
        if let Some(target) = self.rules.get(&token.word) {
            return format!("{prefix} RULE {target}");
        }
        let found = self.candidates(&token.word);
        if found.is_empty() {
            return format!("{prefix} NONE");
        }
        let words = found
            .iter()
            .take(self.suggestion_count)
            .map(|(other, _)| other);
        listing(format!("{prefix} SUGGEST"), words)
    }

    fn check(&mut self, text: &str) {
        let tokens = tokenize(text);
        let mut findings = Vec::new();
        let mut counts = [0; 4];
        for token in &tokens {
            if !self.is_known(&token.word) {
                findings.push(self.unknown_finding(token));
                counts[0] += 1;
                *self.unknown_log.entry(token.word.clone()).or_default() += 1;
            }
            if token.mixed_case() {
                findings.push(format!("CASE {} {}", token.number, token.text));
                counts[1] += 1;
            }
            if token.sentence_start && token.text.starts_with(|c: char| c.is_ascii_lowercase()) {
                findings.push(format!("CAPITAL {} {}", token.number, token.text));
                counts[2] += 1;
            }
            if token.repeat {
                findings.push(format!("REPEAT {} {}", token.number, token.text));
                counts[3] += 1;
            }
        }
        self.counters.checked += tokens.len();
        self.counters.unknown += counts[0];
        self.counters.case += counts[1];
        self.counters.capital += counts[2];
        self.counters.repeats += counts[3];
        let header = FINDING_KINDS
            .iter()
            .zip(counts)
            .map(|(kind, count)| format!("{kind}={count}"));
        self.emit(listing(format!("CHECK words={}", tokens.len()), header));
        self.output.extend(findings);
    }

    fn correct(&mut self, text: &str) {
        let mut result = String::new();
        let mut position = 0;
        let mut changed = 0;
        for token in tokenize(text) {
            result.push_str(&token.gap);
            match self.correction(&token.word) {
                Some(replacement) => {
                    result.push_str(&apply_case(&token.text, &replacement));
                    self.log_correction(&token.word, &replacement);
                    changed += 1;
                }
                None => result.push_str(&token.text),
            }
            position = token.end;
        }
        result.push_str(&text[position..]);
        self.emit(format!("CORRECT changed={changed}: {result}"));
    }

    fn fix(&mut self, text: &str) {
        let mut result = String::new();
        let mut position = 0;
        let mut removed = 0;
        let mut replaced = 0;
        let mut recased = 0;
        for token in tokenize(text) {
            position = token.end;
            if token.repeat {
                removed += 1;
                continue;
            }
            let replacement = self.correction(&token.word);
            let mut fixed = apply_case(&token.text, replacement.as_deref().unwrap_or(&token.word));
            if token.sentence_start && fixed.starts_with(|c: char| c.is_ascii_lowercase()) {
                fixed = capitalize_first(&fixed);
            }
            if let Some(replacement) = replacement {
                self.log_correction(&token.word, &replacement);
                replaced += 1;
            } else if fixed != token.text {
                recased += 1;
            }
            result.push_str(&token.gap);
            result.push_str(&fixed);
        }
        result.push_str(&text[position..]);
        self.emit(format!(
            "FIX removed={removed} replaced={replaced} recased={recased}: {result}"
        ));
    }

    fn profile(&mut self, text: &str) {
        let tokens = tokenize(text);
        let distinct = tokens
            .iter()
            .map(|token| &token.word)
            .collect::<HashSet<_>>()
            .len();
        let unknown = tokens
            .iter()
            .filter(|token| !self.is_known(&token.word))
            .count();
        let sentences = tokens.iter().filter(|token| token.sentence_start).count();
        let (rate, average, longest) =
            match tokens.iter().min_by_key(|token| Reverse(token.text.len())) {
                None => ("0.0".to_string(), "0.00".to_string(), "-"),
                Some(longest) => {
                    let characters: usize = tokens.iter().map(|token| token.text.len()).sum();
                    (
                        decimal_text(100 * unknown, tokens.len(), 1),
                        decimal_text(characters, tokens.len(), 2),
                        longest.word.as_str(),
                    )
                }
            };
        self.emit(format!(
            "PROFILE words={} distinct={distinct} unknown={unknown} rate={rate} avglen={average} \
             longest={longest} sentences={sentences}",
            tokens.len()
        ));
    }

    fn learn(&mut self, text: &str) {
        self.record_undo("LEARN");
        let mut updated = 0;
        let mut added = 0;
        let mut skipped = 0;
        for token in tokenize(text) {
            if token.word.len() > MAX_WORD_LENGTH {
                skipped += 1;
            } else if let Some(frequency) = self.dictionary.get_mut(&token.word) {
                *frequency += 1;
                updated += 1;
            } else {
                self.ignored.remove(&token.word);
                self.dictionary.insert(token.word, 1);
                added += 1;
            }
        }
        self.emit(format!(
            "LEARN updated={updated} added={added} skipped={skipped}"
        ));
    }

    fn suggest(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let line = if self.is_known(&word) {
            format!("SUGGEST {word} KNOWN")
        } else if let Some(target) = self.rules.get(&word) {
            format!("SUGGEST {word} RULE {target}")
        } else {
            let found = self.candidates(&word);
            let shown = found
                .iter()
                .take(self.suggestion_count)
                .map(|(other, distance)| format!("{other}:{distance}"));
            listing(format!("SUGGEST {word} found={}", found.len()), shown)
        };
        self.emit(line);
        Ok(())
    }

    fn dist(&mut self, arguments: &[&str]) -> CommandResult {
        let first = word_argument(arguments[0])?;
        let second = word_argument(arguments[1])?;
        let (distance, operations) = edit_operations(&first, &second, self.keyboard);
        self.emit(listing(
            format!("DIST {first} {second} {distance}"),
            operations,
        ));
        Ok(())
    }

    fn soundex_code(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        self.emit(format!("SOUNDEX {word} {}", soundex(&word)));
        Ok(())
    }

    fn sounds(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let code = soundex(&word);
        let matches: Vec<&str> = self
            .frequency_order()
            .into_iter()
            .filter(|other| *other != word && soundex(other) == code)
            .collect();
        let head = format!("SOUNDS {word} {code} count={}", matches.len());
        let line = listing(head, matches.iter().take(REPORT_SIZE));
        self.emit(line);
        Ok(())
    }

    fn split(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let line = match segment(&word, &self.dictionary) {
            (ways, Some(best)) => listing(format!("SPLIT {word} ways={ways} ->"), best),
            (_, None) => format!("SPLIT {word} ways=0 -> NONE"),
        };
        self.emit(line);
        Ok(())
    }

    fn prefix(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let count = number_argument(arguments[1], 1, MAX_LISTED)? as usize;
        let matches: Vec<&str> = self
            .frequency_order()
            .into_iter()
            .filter(|other| other.starts_with(&word))
            .collect();
        let shown = matches
            .iter()
            .take(count)
            .map(|other| format!("{other}:{}", self.dictionary[*other]));
        let line = listing(format!("PREFIX {word} count={}", matches.len()), shown);
        self.emit(line);
        Ok(())
    }

    fn complete(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let count = number_argument(arguments[1], 1, MAX_LISTED)? as usize;
        let threshold = self.limit() / 2;
        let mut matches: Vec<(usize, Reverse<u32>, &String)> = self
            .dictionary
            .iter()
            .map(|(other, &frequency)| {
                (
                    prefix_distance(&word, other, self.keyboard),
                    Reverse(frequency),
                    other,
                )
            })
            .filter(|(distance, _, _)| *distance <= threshold)
            .collect();
        matches.sort();
        let shown = matches
            .iter()
            .take(count)
            .map(|(distance, _, other)| format!("{other}:{distance}"));
        let line = listing(format!("COMPLETE {word} count={}", matches.len()), shown);
        self.emit(line);
        Ok(())
    }

    fn list_words(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let count = number_argument(arguments[1], 1, MAX_LISTED)? as usize;
        let mut matches: Vec<&String> = self
            .dictionary
            .keys()
            .filter(|other| **other >= word)
            .collect();
        matches.sort();
        let shown = matches
            .iter()
            .take(count)
            .map(|other| format!("{other}:{}", self.dictionary[*other]));
        let line = listing(format!("LIST {word} count={}", matches.len()), shown);
        self.emit(line);
        Ok(())
    }

    fn word_info(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let frequency = self.require_entry(&word)?;
        let rank = self
            .frequency_order()
            .iter()
            .position(|other| *other == word)
            .unwrap()
            + 1;
        let line = format!(
            "WORD {word} freq={frequency} rank={rank} soundex={} neighbors={}",
            soundex(&word),
            self.candidates(&word).len()
        );
        self.emit(line);
        Ok(())
    }

    fn add(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let frequency = number_argument(arguments[1], 1, MAX_FREQUENCY)?;
        if self.dictionary.contains_key(&word) {
            return Err(format!("DUPLICATE {word}"));
        }
        self.record_undo("ADD");
        self.ignored.remove(&word);
        self.emit(format!("ADD {word} {frequency}"));
        self.dictionary.insert(word, frequency);
        Ok(())
    }

    fn remove(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let frequency = self.require_entry(&word)?;
        self.record_undo("REMOVE");
        self.dictionary.remove(&word);
        self.emit(format!("REMOVE {word} {frequency}"));
        Ok(())
    }

    fn ignore(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        if self.dictionary.contains_key(&word) {
            return Err(format!("IN DICTIONARY {word}"));
        }
        if self.ignored.contains(&word) {
            return Err(format!("ALREADY IGNORED {word}"));
        }
        self.record_undo("IGNORE");
        self.emit(format!("IGNORE {word}"));
        self.ignored.insert(word);
        Ok(())
    }

    fn unignore(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        if !self.ignored.contains(&word) {
            return Err(format!("NOT IGNORED {word}"));
        }
        self.record_undo("UNIGNORE");
        self.ignored.remove(&word);
        self.emit(format!("UNIGNORE {word}"));
        Ok(())
    }

    fn rule(&mut self, arguments: &[&str]) -> CommandResult {
        let source = word_argument(arguments[0])?;
        let target = word_argument(arguments[1])?;
        if self.dictionary.contains_key(&source) {
            return Err(format!("IN DICTIONARY {source}"));
        }
        if !self.dictionary.contains_key(&target) {
            return Err(format!("NOT FOUND {target}"));
        }
        self.record_undo("RULE");
        let line = match self.rules.insert(source.clone(), target.clone()) {
            Some(previous) => format!("RULE {source} {target} REPLACED {previous}"),
            None => format!("RULE {source} {target}"),
        };
        self.emit(line);
        Ok(())
    }

    fn unrule(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let Some(target) = self.rules.get(&word).cloned() else {
            return Err(format!("NO RULE {word}"));
        };
        self.record_undo("UNRULE");
        self.rules.remove(&word);
        self.emit(format!("UNRULE {word} {target}"));
        Ok(())
    }

    fn show_rules(&mut self, _arguments: &[&str]) -> CommandResult {
        let shown = self
            .rules
            .iter()
            .map(|(source, target)| format!("{source}>{target}"));
        let line = listing(format!("RULES count={}", self.rules.len()), shown);
        self.emit(line);
        Ok(())
    }

    fn keyboard_mode(&mut self, arguments: &[&str]) -> CommandResult {
        let mode = arguments[0];
        if !KEYBOARD_MODES.contains(&mode) {
            return Err(format!("BAD MODE {mode}"));
        }
        self.keyboard = mode == "ON";
        self.emit(format!("KEYBOARD {mode}"));
        Ok(())
    }

    fn set_option(&mut self, arguments: &[&str]) -> CommandResult {
        let option = arguments[0];
        let maximum = match option {
            "LIMIT" => 3,
            "SUGGESTIONS" => 10,
            _ => return Err(format!("BAD OPTION {option}")),
        };
        let value = number_argument(arguments[1], 1, maximum)?;
        if option == "LIMIT" {
            self.base_limit = value as usize;
        } else {
            self.suggestion_count = value as usize;
        }
        self.emit(format!("SET {option} {value}"));
        Ok(())
    }

    fn undo(&mut self, _arguments: &[&str]) -> CommandResult {
        let record = self.undo_history.pop().ok_or("NOTHING TO UNDO")?;
        self.dictionary = record.dictionary;
        self.ignored = record.ignored;
        self.rules = record.rules;
        self.emit(format!("UNDO {}", record.name));
        Ok(())
    }

    fn report(&mut self, _arguments: &[&str]) -> CommandResult {
        let mut entries: Vec<(&String, &u32)> = self.unknown_log.iter().collect();
        entries.sort_by_key(|&(word, &count)| (Reverse(count), word));
        let shown = entries
            .iter()
            .take(REPORT_SIZE)
            .map(|(word, count)| format!("{word}:{count}"));
        let line = listing(format!("REPORT distinct={}", entries.len()), shown);
        self.emit(line);
        Ok(())
    }

    fn history(&mut self, _arguments: &[&str]) -> CommandResult {
        let mut entries: Vec<(&(String, String), &u32)> = self.correction_log.iter().collect();
        entries.sort_by_key(|&(pair, &count)| (Reverse(count), pair));
        let shown = entries
            .iter()
            .take(REPORT_SIZE)
            .map(|((word, replacement), count)| format!("{word}>{replacement}:{count}"));
        let line = listing(format!("HISTORY distinct={}", entries.len()), shown);
        self.emit(line);
        Ok(())
    }

    fn stats(&mut self, _arguments: &[&str]) -> CommandResult {
        let top = self.frequency_order()[0];
        let characters: usize = self.dictionary.keys().map(String::len).sum();
        let total: u32 = self.dictionary.values().sum();
        let line = format!(
            "STATS words={} total={total} avglen={} top={top}:{} ignored={} rules={} \
             keyboard={} limit={} suggestions={} undo={}",
            self.dictionary.len(),
            decimal_text(characters, self.dictionary.len(), 2),
            self.dictionary[top],
            self.ignored.len(),
            self.rules.len(),
            if self.keyboard { "ON" } else { "OFF" },
            self.limit(),
            self.suggestion_count,
            self.undo_history.len()
        );
        self.emit(line);
        let counters = &self.counters;
        let session = format!(
            "SESSION checked={} unknown={} case={} capital={} repeats={} corrected={}",
            counters.checked,
            counters.unknown,
            counters.case,
            counters.capital,
            counters.repeats,
            counters.corrected
        );
        self.emit(session);
        Ok(())
    }

    fn dispatch(&mut self, name: &str, rest: Option<&str>) -> CommandResult {
        let Some(&(_, handler)) = COMMANDS.iter().find(|(command, _)| *command == name) else {
            return Err(format!("UNKNOWN COMMAND {name}"));
        };
        let bad_arguments = || format!("BAD ARGUMENTS {name}");
        match handler {
            Handler::Text(run) => {
                run(self, rest.ok_or_else(bad_arguments)?);
                Ok(())
            }
            Handler::Words(arity, run) => {
                let arguments: Vec<&str> =
                    rest.map_or_else(Vec::new, |rest| rest.split(' ').collect());
                if arguments.len() != arity {
                    return Err(bad_arguments());
                }
                run(self, &arguments)
            }
        }
    }

    fn execute(&mut self, line: &str) {
        let (name, rest) = match line.split_once(' ') {
            Some((name, rest)) => (name, Some(rest)),
            None => (line, None),
        };
        if let Err(message) = self.dispatch(name, rest) {
            self.emit(format!("ERROR {message}"));
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let word_count: usize = lines.next().unwrap().trim().parse().unwrap();
    let mut dictionary = HashMap::new();
    for _ in 0..word_count {
        let (word, frequency) = lines.next().unwrap().split_once(' ').unwrap();
        dictionary.insert(word.to_string(), frequency.trim().parse().unwrap());
    }
    let mut checker = SpellChecker::new(dictionary);
    let command_count: usize = lines.next().unwrap().trim().parse().unwrap();
    for _ in 0..command_count {
        checker.execute(lines.next().unwrap_or(""));
    }
    let mut output = checker.output.join("\n");
    output.push('\n');
    io::stdout().write_all(output.as_bytes()).unwrap();
}
