use std::collections::HashSet;

pub struct Tokens {
    pub raw_count: usize,
    pub stopword_count: usize,
    pub short_count: usize,
    pub words: Vec<String>,
    pub bigrams: Vec<String>,
    combined: Vec<String>,
}
impl Tokens {
    pub fn new(text: &str, stopwords: &HashSet<String>) -> Self {
        let mut raw = Vec::new();
        let mut word = String::new();
        for byte in text.bytes().chain(std::iter::once(b' ')) {
            if byte.is_ascii_alphanumeric() { word.push(byte.to_ascii_lowercase() as char); }
            else if !word.is_empty() { raw.push(std::mem::take(&mut word)); }
        }
        let raw_count = raw.len();
        let (mut stopword_count, mut short_count) = (0, 0);
        let mut words = Vec::new();
        for word in raw {
            if stopwords.contains(&word) { stopword_count += 1; }
            else if word.len() == 1 { short_count += 1; }
            else { words.push(word); }
        }
        let bigrams: Vec<String> = words.windows(2).map(|pair| format!("{}_{}", pair[0], pair[1])).collect();
        let mut combined = words.clone();
        combined.extend(bigrams.iter().cloned());
        Self { raw_count, stopword_count, short_count, words, bigrams, combined }
    }
    pub fn terms(&self, use_bigrams: bool) -> &[String] { if use_bigrams { &self.combined } else { &self.words } }
}
