use std::collections::VecDeque;

#[derive(Clone)]
pub struct MemoryQueue { pub capacity: usize, pub texts: VecDeque<String>, pub log: Vec<String> }

impl MemoryQueue {
    pub fn new(capacity: usize) -> Self { Self { capacity, texts: VecDeque::new(), log: Vec::new() } }
    pub fn store(&mut self, prefix: &str, keyword: &str, text: String) -> bool {
        if self.texts.contains(&text) { self.log.push(format!("{prefix} SKIP {keyword} {text}")); return false; }
        if self.texts.len() == self.capacity { self.log.push(format!("{prefix} DROP {}", self.texts.pop_front().unwrap())); }
        self.log.push(format!("{prefix} STORE {keyword} {text}"));
        self.texts.push_back(text);
        true
    }
    pub fn recall(&mut self, prefix: &str) -> String {
        let text = self.texts.pop_front().unwrap();
        self.log.push(format!("{prefix} RECALL {text}"));
        text
    }
    pub fn clear(&mut self, prefix: &str) -> usize {
        let count = self.texts.len();
        if count > 0 { self.log.push(format!("{prefix} CLEAR {count}")); self.texts.clear(); }
        count
    }
}
