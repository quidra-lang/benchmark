use std::collections::{
    BTreeMap, BTreeSet
};
use crate::{
    hashing::digest, wallets::{
        Wallet, sign
    }
};
pub type Reference = (String, usize);
pub type Utxo = BTreeMap<Reference, Coin>;
#[derive(Clone)]
pub struct Coin {
    pub address: String,
    pub amount: i64,
    pub height: usize,
    pub coinbase: bool
}
impl Coin {
    pub fn mature(&self, height: usize, maturity: usize) -> bool {
        !self.coinbase || self.height == 0 || height >= self.height+maturity
    }
}
#[derive(Clone)]
pub struct Transaction {
    pub text: String,
    pub txid: String,
    pub inputs: Vec<Reference>,
    pub outputs: Vec<(String, i64)>,
    pub signatures: Vec<String>,
    pub coinbase_height: Option<usize>
}
impl Transaction {
    pub fn parse(text: &str) -> Self {
        let parts: Vec<&str >= text.split(';').collect();
        let outputs = parts[1][4..].split(',').map(|s| {
            let(a, b) = s.split_once(':').unwrap(); (a.to_owned(), b.parse().unwrap())
        }).collect();
        let coinbase_height = if parts[0].starts_with("cb=") {
            Some(parts[0][3..].parse().unwrap())
        }else {
            None
        };
        let inputs = if coinbase_height.is_some() {
            vec![]
        }else {
            parts[0][3..].split(',').map(|s| {
                let(a, b) = s.split_once(':').unwrap(); (a.to_owned(), b.parse().unwrap())
            }).collect()
        };
        let signatures = if coinbase_height.is_some() {
            vec![]
        }else {
            parts[2][4..].split(',').map(str::to_owned).collect()
        };
        Self {
            text: text.to_owned(),
            txid: digest(text),
            inputs,
            outputs,
            signatures,
            coinbase_height
        }
    }
    pub fn size(&self) -> i64 {
        self.text.len() as i64
    }
    pub fn body(&self) -> &str {
        self.text.split_once(";sig=").unwrap().0
    }
    pub fn total(&self) -> i64 {
        self.outputs.iter().map(|o|o.1).sum()
    }
    pub fn coinbase(&self) -> bool {
        self.coinbase_height.is_some()
    }
}
pub fn create_transaction(inputs: &[Reference], outputs: &[(String, i64)], secret: &str) -> Transaction {
    let ins = inputs.iter().map(|(id, i)|format!("{id}:{i}")).collect::<Vec<_>>().join(",");
    let outs = outputs.iter().map(|(a, v)|format!("{a}:{v}")).collect::<Vec<_>>().join(",");
    let body = format!("in={ins};out={outs}");
    let signatures = (0..inputs.len()).map(|i|sign(secret, i, &body)).collect::<Vec<_>>().join(",");
    Transaction::parse(&format!("{body};sig={signatures}"))
}
pub fn create_coinbase(height: usize, outputs: &[(String, i64)]) -> Transaction {
    Transaction::parse(&format!("cb={height};out={}", outputs.iter().map(|(a, v)|format!("{a}:{v}")).collect::<Vec<_>>().join(",")))
}
pub fn check(tx: &Transaction, utxo: &Utxo, spent: &BTreeSet<Reference>, height: usize, owners: &BTreeMap<String, Wallet>, maturity: usize) -> Result<i64, String> {
    if tx.outputs.iter().any(|(a, v)|!owners.contains_key(a) || *v == 0) {
        return Err("bad-output".into());
    }
    let mut seen = BTreeSet::new();
    let mut total = 0;
    for (i, r) in tx.inputs.iter().enumerate() {
        if spent.contains(r) || !seen.insert(r.clone()) {
            return Err("double-spend".into());
        }
        let coin = utxo.get(r).ok_or("missing-input")?;
        if !coin.mature(height, maturity) {
            return Err("immature".into());
        }
        if tx.signatures[i] != sign(&owners[&coin.address].secret, i, tx.body()) {
            return Err("bad-sig".into());
        }
        total += coin.amount;
    }
    if total<tx.total() {
        Err("overspend".into())
    }else {
        Ok(total-tx.total())
    }
}
pub fn apply(utxo: &mut Utxo, tx: &Transaction, height: usize) {
    for r in &tx.inputs {
        utxo.remove(r);
    }
    for (i, (address, amount)) in tx.outputs.iter().enumerate() {
        utxo.insert((tx.txid.clone(), i), Coin {
            address: address.clone(),
            amount: *amount,
            height,
            coinbase: tx.coinbase()
        });
    }
}
