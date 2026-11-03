use crate::{
    hashing::{
        digest, merkle_root
    }, transactions::Transaction
};
#[derive(Clone)]
pub struct Block {
    pub height: usize,
    pub previous: String,
    pub merkle: String,
    pub timestamp: i64,
    pub difficulty: usize,
    pub nonce: i64,
    pub transactions: Vec<Transaction>,
    pub hash: String
}
impl Block {
    pub fn new(height: usize, previous: String, merkle: String, timestamp: i64, difficulty: usize, nonce: i64, transactions: Vec<Transaction>) -> Self {
        let hash = digest(&format!("{height}|{previous}|{merkle}|{timestamp}|{difficulty}|{nonce}"));
        Self {
            height,
            previous,
            merkle,
            timestamp,
            difficulty,
            nonce,
            transactions,
            hash
        }
    }
    pub fn parse(fields: &[&str], texts: &[&str]) -> Self {
        Self::new(fields[3].parse().unwrap(), fields[4].into(), fields[5].into(), fields[6].parse().unwrap(), fields[7].parse().unwrap(), fields[8].parse().unwrap(), texts.iter().map(|s|Transaction::parse(s)).collect())
    }
    pub fn size(&self) -> i64 {
        self.transactions.iter().skip(1).map(Transaction::size).sum()
    }
    pub fn txids(&self) -> Vec<String> {
        self.transactions.iter().map(|t|t.txid.clone()).collect()
    }
    pub fn context_error(&self, max_size: i64) -> Option<String> {
        let reason = if !self.hash.starts_with(&"0".repeat(self.difficulty)) {
            "bad-pow"
        }
        else if merkle_root(self.txids()) != self.merkle {
            "bad-merkle"
        }
        else if self.transactions[0].coinbase_height != Some(self.height) || self.transactions.iter().skip(1).any(Transaction::coinbase) {
            "bad-structure"
        }
        else if self.size()>max_size {
            "too-large"
        }else {
            return None
        };
        Some(reason.into())
    }
}
pub fn mine_block(height: usize, previous: String, transactions: Vec<Transaction>, timestamp: i64, difficulty: usize) -> Block {
    let merkle = merkle_root(transactions.iter().map(|t|t.txid.clone()).collect());
    let mut nonce = 0;
    loop {
        let block = Block::new(height, previous.clone(), merkle.clone(), timestamp, difficulty, nonce, transactions.clone());
        if block.hash.starts_with(&"0".repeat(difficulty)) {
            return block;
        }
        nonce += 1;
    }
}
