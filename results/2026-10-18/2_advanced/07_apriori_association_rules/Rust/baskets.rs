use std::collections::{BTreeMap, BTreeSet};
use std::fs;

pub type Itemset = Vec<String>;
pub type Basket = BTreeSet<String>;
pub type Frequent = BTreeMap<Itemset, i64>;

pub struct Product { pub category: String, pub price: i64 }
pub struct Transaction { pub tid: String, pub customer: String, pub day: i64, pub counts: BTreeMap<String, i64> }

impl Transaction {
    pub fn new(tid: String, customer: String, day: i64) -> Self { Self { tid, customer, day, counts: BTreeMap::new() } }
    pub fn add(&mut self, product: &str) -> bool {
        let duplicate = self.counts.contains_key(product);
        *self.counts.entry(product.into()).or_default() += 1;
        duplicate
    }
    pub fn products(&self) -> Itemset { self.counts.keys().cloned().collect() }
    pub fn units(&self) -> i64 { self.counts.values().sum() }
}

pub fn read_records(name: &str) -> Vec<Vec<String>> {
    fs::read_to_string(format!("input/{name}")).unwrap().lines().skip(1).map(|line| line.split(',').map(str::to_owned).collect()).collect()
}

pub fn contains(basket: &Basket, items: &[String]) -> bool { items.iter().all(|item| basket.contains(item)) }
pub fn extended_basket(products: &[String], taxonomy: &BTreeMap<String, String>) -> Basket {
    products.iter().cloned().chain(products.iter().map(|item| taxonomy[item].clone())).collect()
}
