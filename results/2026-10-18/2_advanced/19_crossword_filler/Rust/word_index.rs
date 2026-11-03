use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet};

pub fn is_valid_word(text: &str) -> bool { (3..=15).contains(&text.len()) && text.bytes().all(|letter| letter.is_ascii_uppercase()) }
pub fn is_valid_integer(text: &str, low: i64, high: i64) -> bool {
    !text.is_empty() && !text.starts_with('0') && text.len() <= high.to_string().len()
        && text.bytes().all(|digit| digit.is_ascii_digit()) && text.parse::<i64>().is_ok_and(|value| low <= value && value <= high)
}
pub fn word_line_error(line: &str) -> Option<&'static str> {
    if line.bytes().filter(|&byte| byte == b' ').count() != 1 { return Some("bad format"); }
    let (word, score) = line.split_once(' ').unwrap();
    if !is_valid_word(word) { Some("bad word") }
    else if !is_valid_integer(score, 1, 100) { Some("bad score") } else { None }
}
pub fn clue_line_error(line: &str) -> Option<&'static str> {
    if line.bytes().filter(|&byte| byte == b'|').count() != 1 { return Some("bad format"); }
    let (word, clue) = line.split_once('|').unwrap();
    if !is_valid_word(word) { Some("bad word") }
    else if !(1..=60).contains(&clue.len()) || clue.starts_with(' ') || clue.ends_with(' ') { Some("bad clue") } else { None }
}
pub fn matches(word: &[u8], pattern: &[u8]) -> bool { word.iter().zip(pattern).all(|(&letter, &mark)| mark == b'.' || mark == letter) }

pub struct Word { pub text: String, pub letters: Vec<u8>, pub score: i64 }
pub struct WordIndex {
    pub words: Vec<Word>,
    pub lookup: BTreeMap<String, usize>,
    pub by_length: BTreeMap<usize, Vec<usize>>,
    by_letter: BTreeMap<(usize, usize, u8), Vec<usize>>,
}
impl WordIndex {
    pub fn new(scores: BTreeMap<String, i64>) -> Self {
        let mut entries: Vec<_> = scores.into_iter().collect();
        entries.sort_by_key(|(word, score)| (Reverse(*score), word.clone()));
        let mut result = Self { words: Vec::new(), lookup: BTreeMap::new(), by_length: BTreeMap::new(), by_letter: BTreeMap::new() };
        for (id, (text, score)) in entries.into_iter().enumerate() {
            let letters = text.as_bytes().to_vec();
            result.lookup.insert(text.clone(), id);
            result.by_length.entry(letters.len()).or_default().push(id);
            for (position, &letter) in letters.iter().enumerate() { result.by_letter.entry((letters.len(), position, letter)).or_default().push(id); }
            result.words.push(Word { text, letters, score });
        }
        result
    }
    pub fn candidates(&self, pattern: &[u8], minimum: i64, used: &BTreeSet<usize>) -> Vec<usize> {
        let empty = Vec::new();
        let mut pool = self.by_length.get(&pattern.len()).unwrap_or(&empty);
        for (position, &mark) in pattern.iter().enumerate() {
            if mark == b'.' { continue; }
            let bucket = self.by_letter.get(&(pattern.len(), position, mark)).unwrap_or(&empty);
            if bucket.len() < pool.len() { pool = bucket; }
        }
        pool.iter().copied().take_while(|&id| self.words[id].score >= minimum)
            .filter(|id| !used.contains(id) && matches(&self.words[*id].letters, pattern)).collect()
    }
}
