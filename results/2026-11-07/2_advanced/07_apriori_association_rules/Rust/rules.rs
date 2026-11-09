use std::cmp::Ordering;
use crate::baskets::Itemset;

#[derive(Clone, Copy, Eq, PartialEq)]
pub struct Fraction { pub numerator: i64, pub denominator: i64 }

impl Fraction {
    pub fn new(mut numerator: i64, mut denominator: i64) -> Self {
        if denominator < 0 { numerator = -numerator; denominator = -denominator; }
        let (mut a,mut b) = (numerator.abs(),denominator);
        while b != 0 { (a,b) = (b,a % b); }
        Self { numerator: numerator / a, denominator: denominator / a }
    }
    pub fn parse(text: &str) -> Self { let (first,second) = text.split_once('/').unwrap(); Self::new(first.parse().unwrap(),second.parse().unwrap()) }
    pub fn subtract(self, other: Self) -> Self { Self::new(self.numerator * other.denominator - other.numerator * self.denominator,self.denominator * other.denominator) }
    pub fn times(self, numerator: i64, denominator: i64) -> Self { Self::new(self.numerator * numerator,self.denominator * denominator) }
}

impl Ord for Fraction { fn cmp(&self, other: &Self) -> Ordering { (self.numerator * other.denominator).cmp(&(other.numerator * self.denominator)) } }
impl PartialOrd for Fraction { fn partial_cmp(&self, other: &Self) -> Option<Ordering> { Some(self.cmp(other)) } }

#[derive(Clone)]
pub struct Rule {
    pub itemset: Itemset, pub antecedent: Itemset, pub consequent: Itemset, pub count: i64, pub rank: usize,
    pub support: Fraction, pub confidence: Fraction, pub lift: Fraction, pub leverage: Fraction, pub conviction: Option<Fraction>, pub improvement: Fraction,
}

impl Rule {
    pub fn new(itemset: Itemset, antecedent: Itemset, consequent: Itemset, count: i64, total: i64, first: i64, second: i64) -> Self {
        Self { itemset, antecedent, consequent, count, rank: 0, support: Fraction::new(count,total), confidence: Fraction::new(count,first), lift: Fraction::new(total * count,first * second), leverage: Fraction::new(total * count - first * second,total * total), conviction: if first == count { None } else { Some(Fraction::new((total - second) * first,total * (first - count))) }, improvement: Fraction::new(0,1) }
    }
}

pub fn meets_thresholds(confidence: Fraction, lift: Fraction, min_confidence: Fraction, min_lift: Fraction) -> bool { confidence >= min_confidence && lift >= min_lift }
pub fn compare_rules(a: &Rule, b: &Rule) -> Ordering { b.confidence.cmp(&a.confidence).then_with(|| b.lift.cmp(&a.lift)).then_with(|| b.count.cmp(&a.count)).then_with(|| a.antecedent.cmp(&b.antecedent)).then_with(|| a.consequent.cmp(&b.consequent)) }
