use std::collections::BTreeMap;
use std::fs;

pub struct Dictionary {
    words: BTreeMap<String, Vec<usize>>,
    left: usize,
    right: usize,
}

impl Dictionary {
    pub fn read(additions: &[String], left: usize, right: usize) -> Self {
        let mut dictionary = Self { words: BTreeMap::new(), left, right };
        for line in fs::read_to_string("input/hyphenation.txt").unwrap().lines().chain(additions.iter().map(String::as_str)) { dictionary.register(line); }
        dictionary
    }

    fn register(&mut self, text: &str) {
        let mut word = String::new();
        let mut positions = Vec::new();
        for c in text.chars() { if c == '-' { positions.push(word.len()); } else { word.push(c); } }
        self.words.insert(word, positions);
    }

    pub fn splits(&self, word: &str) -> Vec<(usize, bool)> {
        let bytes = word.as_bytes();
        let start = bytes.iter().position(u8::is_ascii_alphabetic).unwrap_or(bytes.len());
        let end = bytes.iter().rposition(u8::is_ascii_alphabetic).map_or(start, |i| i + 1);
        let mut splits = BTreeMap::new();
        if start < end && bytes[start..end].iter().all(u8::is_ascii_alphabetic) {
            if let Some(positions) = self.words.get(&word[start..end].to_ascii_lowercase()) {
                for &position in positions {
                    if position >= self.left && end - start - position >= self.right { splits.insert(start + position, true); }
                }
            }
        }
        for i in 1..bytes.len().saturating_sub(1) {
            if bytes[i] == b'-' && bytes[i - 1].is_ascii_alphabetic() && bytes[i + 1].is_ascii_alphabetic() { splits.insert(i + 1, false); }
        }
        splits.into_iter().collect()
    }
}
