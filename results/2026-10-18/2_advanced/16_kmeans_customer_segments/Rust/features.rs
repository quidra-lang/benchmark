use std::collections::BTreeMap;
use crate::transactions::{Order, orders_by_customer};

pub const FEATURE_NAMES: [&str; 6] = ["recency", "frequency", "monetary", "basket", "categories", "tenure"];
pub const SQRT_FEATURES: [bool; 6] = [false, true, true, true, false, false];
pub type Point = Vec<f64>;

#[derive(Clone)]
pub struct Customer {
    pub id: String,
    pub orders: Vec<Order>,
    pub recency: i64,
    pub frequency: usize,
    pub spend: i64,
    pub basket: f64,
    pub category_spend: BTreeMap<String, i64>,
    pub categories: usize,
    pub tenure: i64,
}

impl Customer {
    pub fn new(id: String, orders: Vec<Order>, day: i64) -> Self {
        let recency = day - orders.iter().map(|order| order.day).max().unwrap();
        let tenure = day - orders.iter().map(|order| order.day).min().unwrap();
        let frequency = orders.len();
        let spend: i64 = orders.iter().map(|order| order.net).sum();
        let basket = (spend as f64 / 100.0) / frequency as f64;
        let mut category_spend = BTreeMap::new();
        for order in &orders {
            for row in &order.rows { *category_spend.entry(row.category.clone()).or_insert(0) += row.amount; }
        }
        let categories = category_spend.values().filter(|&&spend| spend > 0).count();
        Self { id, orders, recency, frequency, spend, basket, category_spend, categories, tenure }
    }
    pub fn values(&self) -> Point {
        vec![self.recency as f64, self.frequency as f64, self.spend as f64 / 100.0,
            self.basket, self.categories as f64, self.tenure as f64]
    }
    pub fn transformed(&self) -> Point {
        self.values().into_iter().enumerate().map(|(index, value)| if SQRT_FEATURES[index] { value.sqrt() } else { value }).collect()
    }
}

pub fn eligible_customers(orders: &[Order], day: i64) -> Vec<Customer> {
    let valid: Vec<_> = orders.iter().filter(|order| order.net > 0).cloned().collect();
    orders_by_customer(&valid).into_iter().map(|(id, orders)| Customer::new(id, orders, day)).collect()
}
pub fn ordered_sum(values: &[f64]) -> f64 {
    let mut total = 0.0;
    for &value in values { total += value; }
    total
}
pub fn mean(values: &[f64]) -> f64 { ordered_sum(values) / values.len() as f64 }
pub fn sample_sd(values: &[f64]) -> f64 {
    let average = mean(values);
    let mut total = 0.0;
    for &value in values { let difference = value - average; total += difference * difference; }
    (total / (values.len() - 1) as f64).sqrt()
}
pub fn standardization(rows: &[Point]) -> (Point, Point) {
    let columns: Vec<Vec<f64>> = (0..FEATURE_NAMES.len()).map(|feature| rows.iter().map(|row| row[feature]).collect()).collect();
    (columns.iter().map(|column| mean(column)).collect(), columns.iter().map(|column| sample_sd(column)).collect())
}
pub fn standardize(values: &[f64], means: &[f64], sds: &[f64]) -> Point {
    values.iter().enumerate().map(|(index, value)| if sds[index] == 0.0 { 0.0 } else { (value - means[index]) / sds[index] }).collect()
}
pub fn correlation(points: &[Point], first: usize, second: usize) -> f64 {
    let mut total = 0.0;
    for point in points { total += point[first] * point[second]; }
    total / (points.len() - 1) as f64
}
