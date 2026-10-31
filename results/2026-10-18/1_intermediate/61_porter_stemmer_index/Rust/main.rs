use std::cmp::{Ordering, Reverse};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fmt::{self, Display};
use std::io::{self, BufWriter, Read, Write};
use std::ops::RangeInclusive;

const VOWELS: &str = "aeiou";
const STEP_NAMES: [&str; 8] = ["1a", "1b", "1c", "2", "3", "4", "5a", "5b"];
const STEP_1A: &[(&str, &str)] = &[("sses", "ss"), ("ies", "i"), ("ss", "ss"), ("s", "")];
const STEP_1B: &[(&str, &str)] = &[("eed", "ee"), ("ed", ""), ("ing", "")];
const STEP_2: &[(&str, &str)] = &[
    ("ational", "ate"),
    ("tional", "tion"),
    ("enci", "ence"),
    ("anci", "ance"),
    ("izer", "ize"),
    ("abli", "able"),
    ("alli", "al"),
    ("entli", "ent"),
    ("eli", "e"),
    ("ousli", "ous"),
    ("ization", "ize"),
    ("ation", "ate"),
    ("ator", "ate"),
    ("alism", "al"),
    ("iveness", "ive"),
    ("fulness", "ful"),
    ("ousness", "ous"),
    ("aliti", "al"),
    ("iviti", "ive"),
    ("biliti", "ble"),
];
const STEP_3: &[(&str, &str)] = &[
    ("icate", "ic"),
    ("ative", ""),
    ("alize", "al"),
    ("iciti", "ic"),
    ("ical", "ic"),
    ("ful", ""),
    ("ness", ""),
];
const STEP_4_SUFFIXES: &[&str] = &[
    "al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment", "ent", "ion", "ou",
    "ism", "ate", "iti", "ous", "ive", "ize",
];
const MAX_WORD_LENGTH: usize = 30;
const KWIC_WIDTH: usize = 30;
const MAX_COUNT: usize = 100;
const MAX_DOCUMENT_NUMBER: usize = 999;
const MAX_LINE_NUMBER: usize = 999;

type CommandResult = Result<String, String>;

fn letter_pattern(word: &str) -> String {
    let mut kinds = String::with_capacity(word.len());
    for (index, letter) in word.chars().enumerate() {
        let vowel = VOWELS.contains(letter) || (letter == 'y' && index > 0 && kinds.ends_with('C'));
        kinds.push(if vowel { 'V' } else { 'C' });
    }
    kinds
}

fn measure(word: &str) -> usize {
    letter_pattern(word).matches("VC").count()
}

fn has_vowel(word: &str) -> bool {
    letter_pattern(word).contains('V')
}

fn ends_double(word: &str) -> bool {
    let bytes = word.as_bytes();
    letter_pattern(word).ends_with("CC") && bytes[bytes.len() - 1] == bytes[bytes.len() - 2]
}

fn ends_cvc(word: &str) -> bool {
    letter_pattern(word).ends_with("CVC") && !word.ends_with(['w', 'x', 'y'])
}

fn final_e_condition(remainder: &str) -> bool {
    let value = measure(remainder);
    value > 1 || (value == 1 && !ends_cvc(remainder))
}

fn apply_rules(
    word: &str,
    rules: impl IntoIterator<Item = (&'static str, &'static str)>,
    condition: impl Fn(&str, &str) -> bool,
) -> (String, Option<&'static str>) {
    let longest = rules
        .into_iter()
        .filter(|(suffix, _)| word.ends_with(suffix))
        .max_by_key(|(suffix, _)| suffix.len());
    let Some((suffix, replacement)) = longest else {
        return (word.to_string(), None);
    };
    let remainder = &word[..word.len() - suffix.len()];
    if !condition(suffix, remainder) {
        return (word.to_string(), None);
    }
    (format!("{remainder}{replacement}"), Some(suffix))
}

fn tidy_step_1b(word: String) -> String {
    if ["at", "bl", "iz"]
        .iter()
        .any(|suffix| word.ends_with(suffix))
    {
        return word + "e";
    }
    if ends_double(&word) && !word.ends_with(['l', 's', 'z']) {
        return word[..word.len() - 1].to_string();
    }
    if measure(&word) == 1 && ends_cvc(&word) {
        return word + "e";
    }
    word
}

fn apply_step(name: &str, word: &str) -> String {
    match name {
        "1a" => apply_rules(word, STEP_1A.iter().copied(), |_, _| true).0,
        "1b" => {
            let (result, suffix) =
                apply_rules(word, STEP_1B.iter().copied(), |suffix, remainder| {
                    if suffix == "eed" {
                        measure(remainder) > 0
                    } else {
                        has_vowel(remainder)
                    }
                });
            if matches!(suffix, Some("ed" | "ing")) {
                tidy_step_1b(result)
            } else {
                result
            }
        }
        "1c" => apply_rules(word, [("y", "i")], |_, remainder| has_vowel(remainder)).0,
        "2" => {
            apply_rules(word, STEP_2.iter().copied(), |_, remainder| {
                measure(remainder) > 0
            })
            .0
        }
        "3" => {
            apply_rules(word, STEP_3.iter().copied(), |_, remainder| {
                measure(remainder) > 0
            })
            .0
        }
        "4" => {
            let rules = STEP_4_SUFFIXES.iter().map(|&suffix| (suffix, ""));
            apply_rules(word, rules, |suffix, remainder| {
                measure(remainder) > 1 && (suffix != "ion" || remainder.ends_with(['s', 't']))
            })
            .0
        }
        "5a" => {
            apply_rules(word, [("e", "")], |_, remainder| {
                final_e_condition(remainder)
            })
            .0
        }
        _ => {
            if measure(word) > 1 && ends_double(word) && word.ends_with('l') {
                word[..word.len() - 1].to_string()
            } else {
                word.to_string()
            }
        }
    }
}

fn stemming_steps(word: &str) -> (String, Vec<(&'static str, String)>) {
    let mut current = word.to_string();
    let mut changes = Vec::new();
    if word.len() > 2 {
        for name in STEP_NAMES {
            let result = apply_step(name, &current);
            if result != current {
                changes.push((name, result.clone()));
            }
            current = result;
        }
    }
    (current, changes)
}

fn porter_stem(word: &str) -> String {
    stemming_steps(word).0
}

fn yes_no(flag: bool) -> &'static str {
    if flag { "YES" } else { "NO" }
}

fn is_word(text: &str) -> bool {
    (1..=MAX_WORD_LENGTH).contains(&text.len())
        && text.bytes().all(|byte| byte.is_ascii_alphabetic())
}

fn word_argument(text: &str) -> Result<String, String> {
    if is_word(text) {
        Ok(text.to_ascii_lowercase())
    } else {
        Err(format!("BAD WORD {text}"))
    }
}

fn number_argument(text: &str, minimum: usize, maximum: usize) -> Result<usize, String> {
    let digits = (1..=7).contains(&text.len()) && text.bytes().all(|byte| byte.is_ascii_digit());
    match text.parse() {
        Ok(value) if digits && (minimum..=maximum).contains(&value) => Ok(value),
        _ => Err(format!("BAD NUMBER {text}")),
    }
}

fn argument_range(name: &str) -> Option<RangeInclusive<usize>> {
    let range = match name {
        "STEM" => 1..=10,
        "PHRASE" => 2..=10,
        "RANK" => 2..=11,
        "INDEX" => 0..=1,
        "TOP" => 1..=2,
        "STATS" => 0..=0,
        "NEAR" => 3..=3,
        "TF" | "SIMILAR" | "LINE" | "APPEND" => 2..=2,
        "STEPS" | "MEASURE" | "SEARCH" | "KWIC" | "DF" | "VARIANTS" | "INFO" | "STOP"
        | "UNSTOP" | "DELETE" => 1..=1,
        _ => return None,
    };
    Some(range)
}

fn split_arguments<'a>(name: &str, rest: &'a str) -> Vec<&'a str> {
    match name {
        "SEARCH" => vec![rest],
        "APPEND" => rest.splitn(2, ' ').collect(),
        _ => rest.split(' ').collect(),
    }
}

fn with_items<T: Display>(head: String, items: impl IntoIterator<Item = T>) -> String {
    let mut line = head;
    for item in items {
        line += &format!(" {item}");
    }
    line
}

fn ranked_by_count<'a>(counts: &HashMap<&'a str, usize>) -> Vec<(&'a str, usize)> {
    let mut ranked: Vec<(&str, usize)> =
        counts.iter().map(|(&stem, &count)| (stem, count)).collect();
    ranked.sort_by_key(|&(stem, count)| (Reverse(count), stem));
    ranked
}

fn document_count(occurrences: &[(&Document, &Token)]) -> usize {
    let numbers: HashSet<usize> = occurrences
        .iter()
        .map(|(document, _)| document.number)
        .collect();
    numbers.len()
}

fn closest_distance(positions: &[usize], others: &[usize], same_stem: bool) -> Option<usize> {
    if same_stem {
        return positions.windows(2).map(|pair| pair[1] - pair[0]).min();
    }
    let mut merged: Vec<(usize, bool)> = positions
        .iter()
        .map(|&position| (position, false))
        .chain(others.iter().map(|&other| (other, true)))
        .collect();
    merged.sort_unstable();
    merged
        .windows(2)
        .filter(|pair| pair[0].1 != pair[1].1)
        .map(|pair| pair[1].0 - pair[0].0)
        .min()
}

fn gcd(a: usize, b: usize) -> usize {
    if b == 0 { a } else { gcd(b, a % b) }
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct Fraction {
    numerator: usize,
    denominator: usize,
}

impl Fraction {
    fn new(numerator: usize, denominator: usize) -> Self {
        if denominator == 0 {
            return Fraction {
                numerator: 0,
                denominator: 1,
            };
        }
        let divisor = gcd(numerator, denominator);
        Fraction {
            numerator: numerator / divisor,
            denominator: denominator / divisor,
        }
    }
}

impl Ord for Fraction {
    fn cmp(&self, other: &Self) -> Ordering {
        (self.numerator * other.denominator).cmp(&(other.numerator * self.denominator))
    }
}

impl PartialOrd for Fraction {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Display for Fraction {
    fn fmt(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
        write!(formatter, "{}/{}", self.numerator, self.denominator)
    }
}

#[derive(Clone, PartialEq)]
enum Lexeme {
    And,
    Or,
    Not,
    Open,
    Close,
    Term(String),
    Prefix(String),
}

fn lexemes(expression: &str) -> Vec<&str> {
    let mut found = Vec::new();
    let mut start = None;
    for (index, character) in expression.char_indices() {
        if matches!(character, ' ' | '(' | ')') {
            if let Some(begin) = start.take() {
                found.push(&expression[begin..index]);
            }
            if character != ' ' {
                found.push(&expression[index..index + 1]);
            }
        } else if start.is_none() {
            start = Some(index);
        }
    }
    if let Some(begin) = start {
        found.push(&expression[begin..]);
    }
    found
}

fn classify(lexeme: &str) -> Result<Lexeme, String> {
    match lexeme {
        "AND" => Ok(Lexeme::And),
        "OR" => Ok(Lexeme::Or),
        "NOT" => Ok(Lexeme::Not),
        "(" => Ok(Lexeme::Open),
        ")" => Ok(Lexeme::Close),
        _ if is_word(lexeme) => Ok(Lexeme::Term(lexeme.to_ascii_lowercase())),
        _ => match lexeme.strip_suffix('*') {
            Some(spelling) if is_word(spelling) => {
                Ok(Lexeme::Prefix(spelling.to_ascii_lowercase()))
            }
            _ => Err(format!("BAD TERM {lexeme}")),
        },
    }
}

struct Token {
    text: String,
    form: String,
    stem: String,
    line: usize,
    position: usize,
    start: usize,
}

impl Token {
    fn end(&self) -> usize {
        self.start + self.text.len()
    }
}

struct Document {
    number: usize,
    lines: Vec<String>,
    tokens: Vec<Token>,
}

impl Document {
    fn new(number: usize) -> Self {
        Document {
            number,
            lines: Vec::new(),
            tokens: Vec::new(),
        }
    }

    fn add_line(&mut self, text: &str) -> &[Token] {
        self.lines.push(text.to_string());
        let first = self.tokens.len();
        let bytes = text.as_bytes();
        let mut start = 0;
        while start < bytes.len() {
            if !bytes[start].is_ascii_alphabetic() {
                start += 1;
                continue;
            }
            let end = bytes[start..]
                .iter()
                .position(|byte| !byte.is_ascii_alphabetic())
                .map_or(bytes.len(), |length| start + length);
            let word = &text[start..end];
            let form = word.to_ascii_lowercase();
            self.tokens.push(Token {
                text: word.to_string(),
                stem: porter_stem(&form),
                form,
                line: self.lines.len(),
                position: self.tokens.len() + 1,
                start,
            });
            start = end;
        }
        &self.tokens[first..]
    }

    fn line_tokens(&self, line_number: usize) -> impl Iterator<Item = &Token> {
        self.tokens
            .iter()
            .filter(move |token| token.line == line_number)
    }

    fn reference(&self, token: &Token) -> String {
        format!("{}:{}:{}", self.number, token.line, token.position)
    }
}

type Evaluation = (String, BTreeSet<usize>);

struct QueryParser<'a> {
    items: &'a [Lexeme],
    position: usize,
    stem_sets: &'a BTreeMap<usize, HashSet<&'a str>>,
}

impl<'a> QueryParser<'a> {
    fn peek(&self) -> Option<&'a Lexeme> {
        self.items.get(self.position)
    }

    fn take(&mut self) -> Result<&'a Lexeme, String> {
        let item = self.peek().ok_or("SYNTAX")?;
        self.position += 1;
        Ok(item)
    }

    fn parse(mut self) -> Result<Evaluation, String> {
        let result = self.expression()?;
        if self.position < self.items.len() {
            return Err("SYNTAX".to_string());
        }
        Ok(result)
    }

    fn expression(&mut self) -> Result<Evaluation, String> {
        let (mut canonical, mut documents) = self.conjunction()?;
        while self.peek() == Some(&Lexeme::Or) {
            self.position += 1;
            let (right, right_documents) = self.conjunction()?;
            canonical = format!("({canonical} OR {right})");
            documents.extend(right_documents);
        }
        Ok((canonical, documents))
    }

    fn conjunction(&mut self) -> Result<Evaluation, String> {
        let (mut canonical, mut documents) = self.negation()?;
        while matches!(
            self.peek(),
            Some(Lexeme::And | Lexeme::Not | Lexeme::Open | Lexeme::Term(_) | Lexeme::Prefix(_))
        ) {
            if self.peek() == Some(&Lexeme::And) {
                self.position += 1;
            }
            let (right, right_documents) = self.negation()?;
            canonical = format!("({canonical} AND {right})");
            documents.retain(|number| right_documents.contains(number));
        }
        Ok((canonical, documents))
    }

    fn negation(&mut self) -> Result<Evaluation, String> {
        if self.peek() == Some(&Lexeme::Not) {
            self.position += 1;
            let (canonical, documents) = self.negation()?;
            let complement = self
                .stem_sets
                .keys()
                .filter(|number| !documents.contains(number))
                .copied()
                .collect();
            return Ok((format!("(NOT {canonical})"), complement));
        }
        self.element()
    }

    fn element(&mut self) -> Result<Evaluation, String> {
        match self.take()? {
            Lexeme::Open => {
                let result = self.expression()?;
                if self.take()? != &Lexeme::Close {
                    return Err("SYNTAX".to_string());
                }
                Ok(result)
            }
            Lexeme::Term(spelling) => {
                let stem = porter_stem(spelling);
                let documents = self.documents_where(|stems| stems.contains(stem.as_str()));
                Ok((stem, documents))
            }
            Lexeme::Prefix(spelling) => {
                let documents = self.documents_where(|stems| {
                    stems.iter().any(|stem| stem.starts_with(spelling.as_str()))
                });
                Ok((format!("{spelling}*"), documents))
            }
            _ => Err("SYNTAX".to_string()),
        }
    }

    fn documents_where(&self, predicate: impl Fn(&HashSet<&str>) -> bool) -> BTreeSet<usize> {
        self.stem_sets
            .iter()
            .filter(|(_, stems)| predicate(stems))
            .map(|(&number, _)| number)
            .collect()
    }
}

struct SearchEngine {
    stopwords: HashSet<String>,
    documents: BTreeMap<usize, Document>,
}

impl SearchEngine {
    fn is_indexed(&self, token: &Token) -> bool {
        !self.stopwords.contains(&token.form)
    }

    fn indexed_tokens<'a>(&'a self, document: &'a Document) -> impl Iterator<Item = &'a Token> {
        document
            .tokens
            .iter()
            .filter(move |token| self.is_indexed(token))
    }

    fn term_frequencies<'a>(&'a self, document: &'a Document) -> HashMap<&'a str, usize> {
        let mut counts: HashMap<&str, usize> = HashMap::new();
        for token in self.indexed_tokens(document) {
            *counts.entry(token.stem.as_str()).or_default() += 1;
        }
        counts
    }

    fn stem_set<'a>(&'a self, document: &'a Document) -> HashSet<&'a str> {
        self.indexed_tokens(document)
            .map(|token| token.stem.as_str())
            .collect()
    }

    fn total_frequencies(&self) -> HashMap<&str, usize> {
        let mut totals: HashMap<&str, usize> = HashMap::new();
        for document in self.documents.values() {
            for (stem, count) in self.term_frequencies(document) {
                *totals.entry(stem).or_default() += count;
            }
        }
        totals
    }

    fn occurrence_map(&self) -> BTreeMap<&str, Vec<(&Document, &Token)>> {
        let mut occurrences: BTreeMap<&str, Vec<(&Document, &Token)>> = BTreeMap::new();
        for document in self.documents.values() {
            for token in self.indexed_tokens(document) {
                occurrences
                    .entry(token.stem.as_str())
                    .or_default()
                    .push((document, token));
            }
        }
        occurrences
    }

    fn occurrences(&self, stem: &str) -> Vec<(&Document, &Token)> {
        self.occurrence_map().remove(stem).unwrap_or_default()
    }

    fn stem_positions(&self, document: &Document, stem: &str) -> Vec<usize> {
        self.indexed_tokens(document)
            .filter(|token| token.stem == stem)
            .map(|token| token.position)
            .collect()
    }

    fn form_count(&self, form: &str) -> usize {
        self.documents
            .values()
            .flat_map(|document| &document.tokens)
            .filter(|token| token.form == form)
            .count()
    }

    fn token_matches(&self, token: &Token, target: &str) -> bool {
        target == "?" || (self.is_indexed(token) && token.stem == target)
    }

    fn describe_token(&self, token: &Token) -> String {
        if self.is_indexed(token) {
            format!("{}/{}", token.form, token.stem)
        } else {
            format!("{}/-", token.form)
        }
    }

    fn term_argument(&self, text: &str) -> Result<String, String> {
        let word = word_argument(text)?;
        if self.stopwords.contains(&word) {
            return Err(format!("STOPWORD {word}"));
        }
        Ok(porter_stem(&word))
    }

    fn document_argument(&self, text: &str) -> Result<&Document, String> {
        let number = number_argument(text, 1, MAX_DOCUMENT_NUMBER)?;
        self.documents
            .get(&number)
            .ok_or_else(|| format!("NO DOC {number}"))
    }

    fn stem_words(&self, arguments: &[&str]) -> CommandResult {
        let words = arguments
            .iter()
            .copied()
            .map(word_argument)
            .collect::<Result<Vec<_>, _>>()?;
        let items = words
            .iter()
            .map(|word| format!("{word}:{}", porter_stem(word)));
        Ok(with_items("STEM".to_string(), items))
    }

    fn show_steps(&self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        let (_, changes) = stemming_steps(&word);
        if changes.is_empty() {
            return Ok(format!("STEPS {word} NONE"));
        }
        let items = changes
            .iter()
            .map(|(name, result)| format!("{name}:{result}"));
        Ok(with_items(format!("STEPS {word}"), items))
    }

    fn show_measure(&self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        Ok(format!(
            "MEASURE {word} {} m={} vowel={} double={} cvc={}",
            letter_pattern(&word),
            measure(&word),
            yes_no(has_vowel(&word)),
            yes_no(ends_double(&word)),
            yes_no(ends_cvc(&word)),
        ))
    }

    fn show_index(&self, arguments: &[&str]) -> CommandResult {
        let prefix = match arguments.first() {
            Some(argument) => word_argument(argument)?,
            None => String::new(),
        };
        let occurrences = self.occurrence_map();
        let stems: Vec<_> = occurrences
            .iter()
            .filter(|(stem, _)| stem.starts_with(prefix.as_str()))
            .collect();
        let mut lines = vec![format!("INDEX stems={}", stems.len())];
        for (stem, found) in stems {
            let references = found
                .iter()
                .map(|(document, token)| document.reference(token));
            lines.push(with_items(
                format!("{stem} df={}", document_count(found)),
                references,
            ));
        }
        Ok(lines.join("\n"))
    }

    fn search(&self, arguments: &[&str]) -> CommandResult {
        let items = lexemes(arguments[0])
            .into_iter()
            .map(classify)
            .collect::<Result<Vec<_>, _>>()?;
        let stem_sets: BTreeMap<usize, HashSet<&str>> = self
            .documents
            .values()
            .map(|document| (document.number, self.stem_set(document)))
            .collect();
        let parser = QueryParser {
            items: &items,
            position: 0,
            stem_sets: &stem_sets,
        };
        let (canonical, matches) = parser.parse()?;
        for item in &items {
            if let Lexeme::Term(spelling) = item
                && self.stopwords.contains(spelling)
            {
                return Err(format!("STOPWORD {spelling}"));
            }
        }
        Ok(with_items(
            format!("SEARCH {canonical} count={}", matches.len()),
            matches,
        ))
    }

    fn phrase(&self, arguments: &[&str]) -> CommandResult {
        let words = arguments
            .iter()
            .copied()
            .map(word_argument)
            .collect::<Result<Vec<_>, _>>()?;
        if words.iter().all(|word| self.stopwords.contains(word)) {
            return Err("STOPWORDS ONLY".to_string());
        }
        let targets: Vec<String> = words
            .iter()
            .map(|word| {
                if self.stopwords.contains(word) {
                    "?".to_string()
                } else {
                    porter_stem(word)
                }
            })
            .collect();
        let mut matches = Vec::new();
        for document in self.documents.values() {
            for window in document.tokens.windows(targets.len()) {
                if window
                    .iter()
                    .zip(&targets)
                    .all(|(token, target)| self.token_matches(token, target))
                {
                    matches.push(document.reference(&window[0]));
                }
            }
        }
        let header = format!("PHRASE \"{}\" matches={}", targets.join(" "), matches.len());
        Ok(with_items(header, matches))
    }

    fn near(&self, arguments: &[&str]) -> CommandResult {
        let first = self.term_argument(arguments[0])?;
        let second = self.term_argument(arguments[1])?;
        let limit = number_argument(arguments[2], 1, MAX_COUNT)?;
        let mut found = Vec::new();
        for document in self.documents.values() {
            let distance = closest_distance(
                &self.stem_positions(document, &first),
                &self.stem_positions(document, &second),
                first == second,
            );
            if let Some(distance) = distance
                && distance <= limit
            {
                found.push(format!("{}:{distance}", document.number));
            }
        }
        let header = format!("NEAR {first} {second} {limit} count={}", found.len());
        Ok(with_items(header, found))
    }

    fn top(&self, arguments: &[&str]) -> CommandResult {
        let limit = number_argument(arguments[0], 1, MAX_COUNT)?;
        let (header, counts) = match arguments.get(1) {
            Some(argument) => {
                let document = self.document_argument(argument)?;
                (
                    format!("TOP {limit} doc={}", document.number),
                    self.term_frequencies(document),
                )
            }
            None => (format!("TOP {limit}"), self.total_frequencies()),
        };
        let ranked = ranked_by_count(&counts);
        let items = ranked
            .iter()
            .take(limit)
            .map(|(stem, count)| format!("{stem}:{count}"));
        Ok(with_items(header, items))
    }

    fn kwic(&self, arguments: &[&str]) -> CommandResult {
        let stem = self.term_argument(arguments[0])?;
        let found = self.occurrences(&stem);
        let mut lines = vec![format!("KWIC {stem} count={}", found.len())];
        for (document, token) in found {
            let text = &document.lines[token.line - 1];
            let before = &text[token.start.saturating_sub(KWIC_WIDTH)..token.start];
            let after = &text[token.end()..(token.end() + KWIC_WIDTH).min(text.len())];
            lines.push(format!(
                "|{before:>width$}[{}]{after:<width$}| {}",
                token.text,
                document.reference(token),
                width = KWIC_WIDTH,
            ));
        }
        Ok(lines.join("\n"))
    }

    fn term_frequency(&self, arguments: &[&str]) -> CommandResult {
        let document = self.document_argument(arguments[0])?;
        let stem = self.term_argument(arguments[1])?;
        let count = self
            .term_frequencies(document)
            .get(stem.as_str())
            .copied()
            .unwrap_or(0);
        Ok(format!("TF {} {stem} {count}", document.number))
    }

    fn document_frequency(&self, arguments: &[&str]) -> CommandResult {
        let stem = self.term_argument(arguments[0])?;
        let found = self.occurrences(&stem);
        Ok(format!("DF {stem} {}", document_count(&found)))
    }

    fn variants(&self, arguments: &[&str]) -> CommandResult {
        let stem = self.term_argument(arguments[0])?;
        let mut forms: BTreeMap<&str, usize> = BTreeMap::new();
        for (_, token) in self.occurrences(&stem) {
            *forms.entry(token.form.as_str()).or_default() += 1;
        }
        let items = forms.iter().map(|(form, count)| format!("{form}:{count}"));
        Ok(with_items(
            format!("VARIANTS {stem} count={}", forms.len()),
            items,
        ))
    }

    fn similar(&self, arguments: &[&str]) -> CommandResult {
        let document = self.document_argument(arguments[0])?;
        let limit = number_argument(arguments[1], 1, MAX_COUNT)?;
        let stems = self.stem_set(document);
        let mut scores = Vec::new();
        for other in self.documents.values() {
            if other.number == document.number {
                continue;
            }
            let other_stems = self.stem_set(other);
            let shared = stems.intersection(&other_stems).count();
            let union = stems.union(&other_stems).count();
            scores.push((Fraction::new(shared, union), other.number));
        }
        scores.sort_by_key(|&(score, number)| (Reverse(score), number));
        let items = scores
            .iter()
            .take(limit)
            .map(|(score, number)| format!("{number}:{score}"));
        Ok(with_items(format!("SIMILAR {}", document.number), items))
    }

    fn rank(&self, arguments: &[&str]) -> CommandResult {
        let limit = number_argument(arguments[0], 1, MAX_COUNT)?;
        let query = arguments[1..]
            .iter()
            .map(|argument| self.term_argument(argument))
            .collect::<Result<HashSet<_>, _>>()?;
        let mut ranked = Vec::new();
        for document in self.documents.values() {
            let counts = self.term_frequencies(document);
            let frequencies: Vec<usize> = query
                .iter()
                .map(|stem| counts.get(stem.as_str()).copied().unwrap_or(0))
                .collect();
            let matched = frequencies.iter().filter(|&&count| count > 0).count();
            let total: usize = frequencies.iter().sum();
            if matched > 0 {
                ranked.push((matched, total, document.number));
            }
        }
        ranked.sort_by_key(|&(matched, total, number)| (Reverse(matched), Reverse(total), number));
        let items = ranked
            .iter()
            .take(limit)
            .map(|(matched, total, number)| format!("{number}:{matched}:{total}"));
        Ok(with_items(format!("RANK count={}", ranked.len()), items))
    }

    fn info(&self, arguments: &[&str]) -> CommandResult {
        let document = self.document_argument(arguments[0])?;
        let counts = self.term_frequencies(document);
        let top = match ranked_by_count(&counts).first() {
            Some((stem, count)) => format!("{stem}:{count}"),
            None => "-".to_string(),
        };
        Ok(format!(
            "INFO {} lines={} tokens={} indexed={} stems={} top={top}",
            document.number,
            document.lines.len(),
            document.tokens.len(),
            counts.values().sum::<usize>(),
            counts.len(),
        ))
    }

    fn show_line(&self, arguments: &[&str]) -> CommandResult {
        let document = self.document_argument(arguments[0])?;
        let line_number = number_argument(arguments[1], 1, MAX_LINE_NUMBER)?;
        if line_number > document.lines.len() {
            return Err(format!("NO LINE {}:{line_number}", document.number));
        }
        let tokens: Vec<&Token> = document.line_tokens(line_number).collect();
        let header = format!(
            "LINE {}:{line_number} tokens={}",
            document.number,
            tokens.len()
        );
        Ok(with_items(
            header,
            tokens.iter().map(|token| self.describe_token(token)),
        ))
    }

    fn stats(&self) -> CommandResult {
        let documents = self.documents.values();
        let lines: usize = documents.clone().map(|document| document.lines.len()).sum();
        let tokens: usize = documents
            .clone()
            .map(|document| document.tokens.len())
            .sum();
        let indexed: usize = documents
            .map(|document| self.indexed_tokens(document).count())
            .sum();
        Ok(format!(
            "STATS docs={} lines={lines} tokens={tokens} indexed={indexed} stems={} stopwords={}",
            self.documents.len(),
            self.total_frequencies().len(),
            self.stopwords.len(),
        ))
    }

    fn stop(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        if !self.stopwords.insert(word.clone()) {
            return Err(format!("ALREADY STOPWORD {word}"));
        }
        Ok(format!("STOP {word} unindexed={}", self.form_count(&word)))
    }

    fn unstop(&mut self, arguments: &[&str]) -> CommandResult {
        let word = word_argument(arguments[0])?;
        if !self.stopwords.remove(&word) {
            return Err(format!("NOT STOPWORD {word}"));
        }
        Ok(format!("UNSTOP {word} indexed={}", self.form_count(&word)))
    }

    fn append(&mut self, arguments: &[&str]) -> CommandResult {
        let number = number_argument(arguments[0], 1, MAX_DOCUMENT_NUMBER)?;
        let created = !self.documents.contains_key(&number);
        let document = self
            .documents
            .entry(number)
            .or_insert_with(|| Document::new(number));
        let tokens = document.add_line(arguments[1]);
        let added = tokens.len();
        let indexed = tokens
            .iter()
            .filter(|token| !self.stopwords.contains(&token.form))
            .count();
        Ok(format!(
            "APPEND {number} line={} tokens={added} indexed={indexed} new={}",
            document.lines.len(),
            yes_no(created),
        ))
    }

    fn delete(&mut self, arguments: &[&str]) -> CommandResult {
        let number = number_argument(arguments[0], 1, MAX_DOCUMENT_NUMBER)?;
        let document = self
            .documents
            .remove(&number)
            .ok_or_else(|| format!("NO DOC {number}"))?;
        Ok(format!(
            "DELETE {number} lines={} tokens={}",
            document.lines.len(),
            document.tokens.len(),
        ))
    }

    fn run(&mut self, name: &str, rest: Option<&str>) -> CommandResult {
        let range = argument_range(name).ok_or_else(|| format!("UNKNOWN COMMAND {name}"))?;
        let arguments = rest.map_or_else(Vec::new, |rest| split_arguments(name, rest));
        if !range.contains(&arguments.len()) {
            return Err(format!("BAD ARGUMENTS {name}"));
        }
        match name {
            "STEM" => self.stem_words(&arguments),
            "STEPS" => self.show_steps(&arguments),
            "MEASURE" => self.show_measure(&arguments),
            "INDEX" => self.show_index(&arguments),
            "SEARCH" => self.search(&arguments),
            "PHRASE" => self.phrase(&arguments),
            "NEAR" => self.near(&arguments),
            "TOP" => self.top(&arguments),
            "KWIC" => self.kwic(&arguments),
            "TF" => self.term_frequency(&arguments),
            "DF" => self.document_frequency(&arguments),
            "VARIANTS" => self.variants(&arguments),
            "SIMILAR" => self.similar(&arguments),
            "RANK" => self.rank(&arguments),
            "INFO" => self.info(&arguments),
            "LINE" => self.show_line(&arguments),
            "STATS" => self.stats(),
            "STOP" => self.stop(&arguments),
            "UNSTOP" => self.unstop(&arguments),
            "APPEND" => self.append(&arguments),
            "DELETE" => self.delete(&arguments),
            _ => unreachable!("command names are checked by argument_range"),
        }
    }

    fn execute(&mut self, line: &str) -> String {
        let (name, rest) = match line.split_once(' ') {
            Some((name, rest)) => (name, Some(rest)),
            None => (line, None),
        };
        self.run(name, rest)
            .unwrap_or_else(|message| format!("ERROR {message}"))
    }
}

fn main() {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .expect("failed to read standard input");
    let mut lines = input.lines().peekable();
    let stopwords = lines
        .next()
        .unwrap_or_default()
        .split_whitespace()
        .skip(1)
        .map(String::from)
        .collect();
    let mut engine = SearchEngine {
        stopwords,
        documents: BTreeMap::new(),
    };
    while let Some(header) = lines.next_if(|line| line.starts_with("DOC ")) {
        let number = header[4..].parse().expect("invalid document number");
        let mut document = Document::new(number);
        for line in lines.by_ref() {
            if line == "ENDDOC" {
                break;
            }
            document.add_line(line);
        }
        engine.documents.insert(number, document);
    }
    let mut output = BufWriter::new(io::stdout().lock());
    for line in lines.take_while(|&line| line != "END") {
        writeln!(output, "{}", engine.execute(line)).expect("failed to write output");
    }
}
