mod baskets;
mod apriori;
mod fpgrowth;
mod rules;
mod report;

use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use baskets::{Basket, Frequent, Itemset, Product, Transaction, contains, extended_basket, read_records};
use apriori::{count_supports, generate_candidates};
use fpgrowth::{GrowthResult, fp_growth};
use rules::{Fraction, Rule, compare_rules, meets_thresholds};
use report::{arrow, fraction, money, percent};

struct Params { integers: BTreeMap<String, i64>, fractions: BTreeMap<String, Fraction> }
impl Params {
    fn read() -> Self {
        let mut p = Self { integers: BTreeMap::new(), fractions: BTreeMap::new() };
        for line in fs::read_to_string("input/params.txt").unwrap().lines() {
            let (key,value) = line.split_once(' ').unwrap();
            if value.contains('/') { p.fractions.insert(key.into(),Fraction::parse(value)); } else { p.integers.insert(key.into(),value.parse().unwrap()); }
        }
        p
    }
    fn value(&self, key: &str) -> i64 { self.integers[key] }
    fn n(&self, key: &str) -> usize { self.value(key) as usize }
    fn f(&self, key: &str) -> Fraction { self.fractions[key] }
    fn passes(&self, confidence: Fraction, lift: Fraction) -> bool { meets_thresholds(confidence,lift,self.f("min_confidence"),self.f("min_lift")) }
}

struct Data {
    errors: Vec<String>, products: BTreeMap<String, Product>, baskets: Vec<Transaction>, sets: Vec<Basket>, extended: Vec<Basket>,
    taxonomy: BTreeMap<String, String>, categories: BTreeSet<String>, customers: BTreeMap<String, Vec<usize>>,
    item_rows: usize, transaction_lines: usize, adopted: usize, rejected: usize, duplicates: usize, transactions: usize, first_day: i64, last_day: i64,
}

impl Data {
    fn read() -> Self {
        let rows = read_records("items.csv");
        let mut d = Self { errors: Vec::new(), products: BTreeMap::new(), baskets: Vec::new(), sets: Vec::new(), extended: Vec::new(), taxonomy: BTreeMap::new(), categories: BTreeSet::new(), customers: BTreeMap::new(), item_rows: rows.len(), transaction_lines: 0, adopted: 0, rejected: 0, duplicates: 0, transactions: 0, first_day: 0, last_day: 0 };
        for (index,f) in rows.into_iter().enumerate() {
            let price = f[2].parse().unwrap();
            let reason = if d.products.contains_key(&f[0]) { Some(format!("duplicate item {}",f[0])) } else if price == 0 { Some(format!("bad price {}",f[2])) } else { None };
            if let Some(reason) = reason { d.errors.push(format!("items.csv line {}: {reason}",index + 2)); }
            else { d.products.insert(f[0].clone(),Product { category: f[1].clone(), price }); d.taxonomy.insert(f[0].clone(),f[1].clone()); d.categories.insert(f[1].clone()); }
        }
        let rows = read_records("transactions.csv"); d.transaction_lines = rows.len();
        let mut transactions: Vec<Transaction> = Vec::new(); let mut seen = BTreeSet::new();
        for (index,f) in rows.into_iter().enumerate() {
            let day = f[2].parse().unwrap();
            let reason = if transactions.last().is_some_and(|t| t.tid != f[0]) && seen.contains(&f[0]) { Some(format!("tid {} not contiguous",f[0])) }
            else {
                if seen.insert(f[0].clone()) { transactions.push(Transaction::new(f[0].clone(),f[1].clone(),day)); }
                let current = transactions.last().unwrap();
                if current.customer != f[1] { Some(format!("tid {} customer {} differs from {}",f[0],f[1],current.customer)) }
                else if current.day != day { Some(format!("tid {} day {day} differs from {}",f[0],current.day)) }
                else if !d.products.contains_key(&f[3]) { Some(format!("unknown item {}",f[3])) } else { None }
            };
            if let Some(reason) = reason { d.errors.push(format!("transactions.csv line {}: {reason}",index + 2)); d.rejected += 1; }
            else { d.adopted += 1; d.duplicates += transactions.last_mut().unwrap().add(&f[3]) as usize; }
        }
        d.transactions = transactions.len(); d.baskets = transactions.into_iter().filter(|t| !t.counts.is_empty()).collect();
        for (index,basket) in d.baskets.iter().enumerate() {
            let products = basket.products(); d.sets.push(products.iter().cloned().collect()); d.extended.push(extended_basket(&products,&d.taxonomy)); d.customers.entry(basket.customer.clone()).or_default().push(index);
        }
        d.first_day = d.baskets.iter().map(|b| b.day).min().unwrap(); d.last_day = d.baskets.iter().map(|b| b.day).max().unwrap(); d
    }
}

struct Level { size: usize, candidates: usize, excluded: usize, pruned: usize, counted: usize, frequent: Frequent }
struct Mining { levels: Vec<Level>, frequent: Frequent }
struct RuleSet { generated: usize, rules: Vec<Rule>, productive: usize }
struct Classifications { closed: Frequent, maximal: Frequent, generators: Frequent }

fn apriori(baskets: &[Basket], universe: Itemset, minimum: i64, maximum: usize, taxonomy: Option<&BTreeMap<String, String>>) -> Mining {
    let mut universe = universe; universe.sort();
    let mut candidates: Vec<Itemset> = universe.into_iter().map(|item| vec![item]).collect();
    let mut previous = Vec::new(); let mut result = Mining { levels: Vec::new(), frequent: BTreeMap::new() };
    for size in 1..=maximum {
        let (joined,excluded,pruned) = if size == 1 { (candidates.len(),0,0) } else {
            if previous.is_empty() { break; }
            let level = generate_candidates(&previous,size,taxonomy); candidates = level.itemsets; (level.joined,level.excluded,level.pruned)
        };
        let counts = count_supports(baskets,&candidates);
        let mut frequent = BTreeMap::new(); previous.clear();
        for items in &candidates {
            let count = counts[items];
            if count >= minimum { frequent.insert(items.clone(),count); result.frequent.insert(items.clone(),count); previous.push(items.clone()); }
        }
        result.levels.push(Level { size, candidates: joined, excluded, pruned, counted: candidates.len(), frequent });
    }
    result
}

fn subsets(items: &[String]) -> Vec<Itemset> {
    (0..(1_usize << items.len())).map(|mask| items.iter().enumerate().filter(|&(i,_)| (mask & (1 << i)) != 0).map(|(_,item)| item.clone()).collect()).collect()
}
fn count_in(frequent: &Frequent, items: &Itemset, total: i64) -> i64 { if items.is_empty() { total } else { frequent[items] } }

fn make_rules(result: &Mining, total: i64, p: &Params, products: Option<&BTreeMap<String, Product>>) -> RuleSet {
    let frequent = &result.frequent;
    let mut generated = 0; let mut rules = Vec::new();
    for (items,&count) in frequent {
        if items.len() < 2 || products.is_some_and(|products| items.iter().all(|item| products.contains_key(item))) { continue; }
        for first in subsets(items) {
            if first.is_empty() || first.len() == items.len() { continue; }
            generated += 1;
            let second: Itemset = items.iter().filter(|item| !first.contains(item)).cloned().collect();
            let mut rule = Rule::new(items.clone(),first.clone(),second.clone(),count,total,count_in(frequent,&first,total),count_in(frequent,&second,total));
            if !p.passes(rule.confidence,rule.lift) { continue; }
            let mut best = Fraction::new(0,1);
            for subset in subsets(&first) {
                if subset.len() == first.len() { continue; }
                let mut union = subset.clone(); union.extend(second.iter().cloned()); union.sort();
                best = best.max(Fraction::new(count_in(frequent,&union,total),count_in(frequent,&subset,total)));
            }
            rule.improvement = rule.confidence.subtract(best); rules.push(rule);
        }
    }
    rules.sort_by(compare_rules); for (index,rule) in rules.iter_mut().enumerate() { rule.rank = index + 1; }
    let productive = rules.iter().filter(|rule| rule.improvement.numerator > 0).count(); RuleSet { generated, rules, productive }
}

fn classify(frequent: &Frequent, total: i64) -> Classifications {
    let mut closed: BTreeMap<Itemset,bool> = frequent.keys().cloned().map(|items| (items,true)).collect(); let mut maximal = closed.clone(); let mut generators = BTreeMap::new();
    for (items,&count) in frequent {
        let mut generator = true;
        for subset in subsets(items) {
            if subset.len() == items.len() { continue; }
            if count_in(frequent,&subset,total) == count { generator = false; }
            if subset.is_empty() { continue; }
            maximal.insert(subset.clone(),false); if frequent[&subset] == count { closed.insert(subset,false); }
        }
        if generator { generators.insert(items.clone(),count); }
    }
    let select = |flags: &BTreeMap<Itemset,bool>| frequent.iter().filter(|(items,_)| flags[*items]).map(|(items,&count)| (items.clone(),count)).collect();
    Classifications { closed: select(&closed), maximal: select(&maximal), generators }
}

fn median(values: &[i64]) -> Fraction {
    let mut ordered = values.to_vec(); ordered.sort(); let middle = ordered.len() / 2;
    if ordered.len() % 2 == 1 { Fraction::new(ordered[middle],1) } else { Fraction::new(ordered[middle - 1] + ordered[middle],2) }
}

struct Sequence { first: String, second: String, count: i64, base: i64, confidence: Fraction, lift: Fraction, gap: Fraction }
struct Repeat { item: String, customers: i64, count: usize, minimum: i64, maximum: i64, mean: Fraction, median: Fraction }
struct Patterns { buyers: BTreeMap<String,i64>, pairs: usize, multi_day: usize, sequences: Vec<Sequence>, repeats: Vec<Repeat> }

fn purchase_patterns(data: &Data, p: &Params) -> Patterns {
    let mut days = Vec::<BTreeMap<String, Vec<i64>>>::new(); let mut buyers: BTreeMap<String,i64> = data.products.keys().cloned().map(|item| (item,0)).collect(); let mut multi_day = 0;
    for indices in data.customers.values() {
        let mut customer_days = BTreeSet::new(); let mut purchased: BTreeMap<String,BTreeSet<i64>> = BTreeMap::new();
        for &index in indices {
            let basket = &data.baskets[index]; customer_days.insert(basket.day);
            for item in basket.counts.keys() { purchased.entry(item.clone()).or_default().insert(basket.day); }
        }
        if customer_days.len() >= 2 { multi_day += 1; }
        let mut lists = BTreeMap::new();
        for (item,set) in purchased { *buyers.get_mut(&item).unwrap() += 1; lists.insert(item,set.into_iter().collect()); }
        days.push(lists);
    }
    let mut pairs: BTreeMap<(String,String),Vec<i64>> = BTreeMap::new(); let mut intervals: BTreeMap<String,Vec<i64>> = BTreeMap::new(); let mut repeat_customers: BTreeMap<String,i64> = BTreeMap::new();
    for purchases in &days {
        for (first,first_days) in purchases {
            if first_days.len() >= 2 { *repeat_customers.entry(first.clone()).or_default() += 1; intervals.entry(first.clone()).or_default().extend(first_days.windows(2).map(|days| days[1] - days[0])); }
            for (second,second_days) in purchases {
                if first_days[0] >= *second_days.last().unwrap() { continue; }
                let mut gap = second_days.last().unwrap() - first_days[0]; let mut j = 0;
                for &day in first_days { while j < second_days.len() && second_days[j] <= day { j += 1; } if j < second_days.len() { gap = gap.min(second_days[j] - day); } }
                pairs.entry((first.clone(),second.clone())).or_default().push(gap);
            }
        }
    }
    let mut sequences = Vec::new();
    for ((first,second),gaps) in &pairs {
        let count = gaps.len() as i64; if count < p.value("sequence_min_support") { continue; }
        sequences.push(Sequence { first: first.clone(), second: second.clone(), count, base: buyers[first], confidence: Fraction::new(count,buyers[first]), lift: Fraction::new(count * data.customers.len() as i64,buyers[first] * buyers[second]), gap: median(gaps) });
    }
    sequences.sort_by(|a,b| b.count.cmp(&a.count).then_with(|| b.confidence.cmp(&a.confidence)).then_with(|| a.first.cmp(&b.first)).then_with(|| a.second.cmp(&b.second)));
    let mut repeats: Vec<Repeat> = intervals.iter().map(|(item,list)| Repeat { item: item.clone(), customers: repeat_customers[item], count: list.len(), minimum: *list.iter().min().unwrap(), maximum: *list.iter().max().unwrap(), mean: Fraction::new(list.iter().sum(),list.len() as i64), median: median(list) }).collect();
    repeats.sort_by(|a,b| a.mean.cmp(&b.mean).then_with(|| a.item.cmp(&b.item)));
    Patterns { buyers, pairs: pairs.len(), multi_day, sequences, repeats }
}

struct SupportCounter { baskets: Vec<Basket>, cache: RefCell<Frequent> }
impl SupportCounter {
    fn new(baskets: Vec<Basket>) -> Self { Self { baskets, cache: RefCell::new(BTreeMap::new()) } }
    fn count(&self, items: &[String]) -> i64 {
        if items.is_empty() { return self.baskets.len() as i64; }
        let mut key = items.to_vec(); key.sort();
        if let Some(&count) = self.cache.borrow().get(&key) { return count; }
        let count = self.baskets.iter().filter(|basket| contains(basket,&key)).count() as i64; self.cache.borrow_mut().insert(key,count); count
    }
    fn single(&self, item: &str) -> i64 { self.count(&[item.into()]) }
}

fn recommend(at_hand: &Basket, candidates: &[String], top: usize) -> Itemset {
    let mut selected = Vec::new();
    for item in candidates { if !at_hand.contains(item) && !selected.contains(item) { selected.push(item.clone()); if selected.len() == top { break; } } }
    selected
}
fn rule_recommendation(at_hand: &Basket, rules: &[Rule], top: usize) -> Itemset {
    let candidates: Itemset = rules.iter().filter(|rule| rule.consequent.len() == 1 && contains(at_hand,&rule.antecedent)).map(|rule| rule.consequent[0].clone()).collect(); recommend(at_hand,&candidates,top)
}

const VERDICTS: [&str; 3] = ["HOLD","FAIL","UNSEEN"];
struct TrainingCase { rule: usize, antecedent: i64, joint: i64, confidence: Option<Fraction>, lift: Option<Fraction>, verdict: usize }
struct Validation {
    train_count: usize, test_count: usize, training_count: usize, train_rules: Vec<Rule>, emerging: Vec<Rule>,
    verdicts: Vec<TrainingCase>, totals: [usize; 3], evaluations: BTreeMap<usize,[i64; 5]>, total: [i64; 5], held: BTreeMap<String,i64>, hits: BTreeMap<String,i64>,
}

impl Validation {
    fn new(data: &Data, p: &Params) -> Self {
        let mut train = Vec::new(); let mut test = Vec::new();
        for (index,basket) in data.baskets.iter().enumerate() { if basket.day <= p.value("split_day") { train.push(data.sets[index].clone()); } else { test.push(data.sets[index].clone()); } }
        let universe: Itemset = data.products.keys().cloned().collect();
        let training = apriori(&train,universe.clone(),p.value("train_min_support"),p.n("max_size"),None);
        let testing = apriori(&test,universe.clone(),p.value("test_min_support"),p.n("max_size"),None);
        let train_rules = make_rules(&training,train.len() as i64,p,None).rules;
        let test_rules = make_rules(&testing,test.len() as i64,p,None).rules;
        let mut result = Self { train_count: train.len(), test_count: test.len(), training_count: training.frequent.len(), train_rules, emerging: Vec::new(), verdicts: Vec::new(), totals: [0;3], evaluations: BTreeMap::new(), total: [0;5], held: universe.iter().cloned().map(|item| (item,0)).collect(), hits: universe.iter().cloned().map(|item| (item,0)).collect() };
        let train_counter = SupportCounter::new(train); let test_counter = SupportCounter::new(test);
        let mut known = BTreeSet::new();
        for (index,rule) in result.train_rules.iter().enumerate() {
            let a = test_counter.count(&rule.antecedent); let b = test_counter.count(&rule.consequent); let c = test_counter.count(&rule.itemset);
            let (confidence,lift,verdict) = if a == 0 || b == 0 { (None,None,2) } else {
                let confidence = Fraction::new(c,a); let lift = Fraction::new(result.test_count as i64 * c,a * b);
                (Some(confidence),Some(lift),if p.passes(confidence,lift) { 0 } else { 1 })
            };
            result.totals[verdict] += 1; result.verdicts.push(TrainingCase { rule: index, antecedent: a, joint: c, confidence, lift, verdict }); known.insert((rule.antecedent.clone(),rule.consequent.clone()));
        }
        result.emerging = test_rules.into_iter().filter(|rule| !known.contains(&(rule.antecedent.clone(),rule.consequent.clone()))).collect();
        let mut popular = universe; popular.sort_by(|a,b| train_counter.single(b).cmp(&train_counter.single(a)).then_with(|| a.cmp(b)));
        for basket in &test_counter.baskets {
            let size = basket.len(); if size < 2 { continue; }
            for item in basket {
                let mut at_hand = basket.clone(); at_hand.remove(item);
                let recommendation = rule_recommendation(&at_hand,&result.train_rules,p.n("recommend_top")); let baseline = recommend(&at_hand,&popular,p.n("recommend_top"));
                let counts = [1,(!recommendation.is_empty()) as i64,(recommendation.first() == Some(item)) as i64,recommendation.contains(item) as i64,baseline.contains(item) as i64];
                *result.held.get_mut(item).unwrap() += 1; *result.hits.get_mut(item).unwrap() += counts[3]; let evaluation = result.evaluations.entry(size).or_default();
                for i in 0..5 { evaluation[i] += counts[i]; result.total[i] += counts[i]; }
            }
        }
        result
    }
}

struct Partner { item: String, count: i64, lift: Fraction }
struct ProductStats { units: i64, revenue: i64, support: i64, itemsets: usize, partner: Option<Partner>, best: Option<usize> }
struct Group { members: Itemset, edges: usize, core: String, revenue: i64 }
struct Substitute { first: String, second: String, count: i64, expected: Fraction, lift: Fraction }
struct ProductAnalysis { stats: BTreeMap<String,ProductStats>, groups: Vec<Group>, substitutes: Vec<Substitute> }

impl ProductAnalysis {
    fn new(data: &Data, p: &Params, main: &Mining, rules: &[Rule], counter: &SupportCounter) -> Self {
        let mut stats: BTreeMap<String,ProductStats> = data.products.keys().map(|item| (item.clone(),ProductStats { units: 0, revenue: 0, support: counter.single(item), itemsets: 0, partner: None, best: None })).collect();
        for basket in &data.baskets {
            for (item,&quantity) in &basket.counts { let stat = stats.get_mut(item).unwrap(); stat.units += quantity; stat.revenue += quantity * data.products[item].price; }
        }
        let mut graph: BTreeMap<String,Itemset> = data.products.keys().cloned().map(|item| (item,Vec::new())).collect();
        for (items,&count) in &main.frequent {
            for item in items { stats.get_mut(item).unwrap().itemsets += 1; }
            if items.len() != 2 { continue; }
            let (first,second) = (&items[0],&items[1]);
            let lift = Fraction::new(data.baskets.len() as i64 * count,stats[first].support * stats[second].support);
            for (item,other) in [(first,second),(second,first)] {
                let stat = stats.get_mut(item).unwrap();
                if stat.partner.as_ref().is_none_or(|old| lift > old.lift || lift == old.lift && (count > old.count || count == old.count && other < &old.item)) { stat.partner = Some(Partner { item: other.clone(), count, lift }); }
            }
            if lift >= p.f("group_min_lift") { graph.get_mut(first).unwrap().push(second.clone()); graph.get_mut(second).unwrap().push(first.clone()); }
        }
        for (index,rule) in rules.iter().enumerate() { for item in &rule.itemset { let stat = stats.get_mut(item).unwrap(); if stat.best.is_none() { stat.best = Some(index); } } }
        let mut groups = Vec::new(); let mut visited = BTreeSet::new();
        for start in data.products.keys() {
            if visited.contains(start) || graph[start].is_empty() { continue; }
            let mut stack = vec![start.clone()]; let mut members = Vec::new(); visited.insert(start.clone());
            while let Some(item) = stack.pop() {
                members.push(item.clone());
                for other in &graph[&item] { if visited.insert(other.clone()) { stack.push(other.clone()); } }
            }
            members.sort(); let mut cores = members.clone(); cores.sort_by(|a,b| graph[b].len().cmp(&graph[a].len()).then_with(|| stats[b].support.cmp(&stats[a].support)).then_with(|| a.cmp(b)));
            let edges = members.iter().map(|item| graph[item].len()).sum::<usize>() / 2; let revenue = members.iter().map(|item| stats[item].revenue).sum();
            groups.push(Group { members, edges, core: cores[0].clone(), revenue });
        }
        groups.sort_by(|a,b| b.members.len().cmp(&a.members.len()).then_with(|| a.members[0].cmp(&b.members[0])));
        let singletons: Itemset = main.frequent.keys().filter(|items| items.len() == 1).map(|items| items[0].clone()).collect(); let mut substitutes = Vec::new();
        for (i,first) in singletons.iter().enumerate() {
            for second in &singletons[i + 1..] {
                let product = stats[first].support * stats[second].support; if product < p.value("negative_min_expected") * data.baskets.len() as i64 { continue; }
                let count = counter.count(&[first.clone(),second.clone()]); let lift = Fraction::new(data.baskets.len() as i64 * count,product);
                if lift <= p.f("negative_max_lift") { substitutes.push(Substitute { first: first.clone(), second: second.clone(), count, expected: Fraction::new(product,data.baskets.len() as i64), lift }); }
            }
        }
        substitutes.sort_by(|a,b| a.lift.cmp(&b.lift).then_with(|| b.expected.cmp(&a.expected)).then_with(|| a.first.cmp(&b.first)).then_with(|| a.second.cmp(&b.second)));
        Self { stats, groups, substitutes }
    }
}

struct Trend { name: String, units: i64, slope: Fraction, relative: Option<Fraction>, verdict: &'static str }
struct Trends { weeks: usize, series: BTreeMap<String,Vec<i64>>, baskets: Vec<i64>, units: Vec<i64>, customers: Vec<usize>, trends: Vec<Trend> }

impl Trends {
    fn new(data: &Data, p: &Params) -> Self {
        let weeks = ((data.last_day - 1) / 7 + 1) as usize;
        let mut series: BTreeMap<String,Vec<i64>> = data.categories.iter().chain(data.products.keys()).cloned().map(|name| (name,vec![0;weeks])).collect();
        let mut baskets = vec![0;weeks]; let mut units = vec![0;weeks]; let mut customer_sets = vec![BTreeSet::new();weeks];
        for basket in &data.baskets {
            let week = ((basket.day - 1) / 7) as usize; baskets[week] += 1; units[week] += basket.units(); customer_sets[week].insert(basket.customer.clone());
            for (item,&quantity) in &basket.counts { series.get_mut(item).unwrap()[week] += quantity; series.get_mut(&data.taxonomy[item]).unwrap()[week] += quantity; }
        }
        let customers = customer_sets.iter().map(BTreeSet::len).collect();
        let sum_w: i64 = (1..=weeks as i64).sum(); let sum_squares: i64 = (1..=weeks as i64).map(|i| i * i).sum(); let denominator = weeks as i64 * sum_squares - sum_w * sum_w;
        let threshold = p.f("trend_threshold"); let negative = Fraction::new(-threshold.numerator,threshold.denominator);
        let mut trends: Vec<Trend> = series.iter().map(|(name,values)| {
            let total = values.iter().sum::<i64>(); let weighted = values.iter().enumerate().map(|(i,&value)| (i as i64 + 1) * value).sum::<i64>();
            let slope = Fraction::new(weeks as i64 * weighted - sum_w * total,denominator); let relative = if total > 0 { Some(slope.times(weeks as i64,total)) } else { None };
            let verdict = match relative { None => "NONE", Some(value) if value >= threshold => "RISING", Some(value) if value <= negative => "FALLING", _ => "FLAT" };
            Trend { name: name.clone(), units: total, slope, relative, verdict }
        }).collect();
        trends.sort_by(|a,b| match (a.relative,b.relative) { (Some(a_value),Some(b_value)) => b_value.cmp(&a_value).then_with(|| a.name.cmp(&b.name)), (Some(_),None) => std::cmp::Ordering::Less, (None,Some(_)) => std::cmp::Ordering::Greater, (None,None) => a.name.cmp(&b.name) });
        Self { weeks, series, baskets, units, customers, trends }
    }
}

fn ordered_itemsets(frequent: &Frequent) -> Vec<(&Itemset,i64)> {
    let mut list: Vec<(&Itemset,i64)> = frequent.iter().map(|(items,&count)| (items,count)).collect();
    list.sort_by(|a,b| a.0.len().cmp(&b.0.len()).then_with(|| a.0.cmp(b.0))); list
}

struct Analysis {
    params: Params, data: Data, mining: Mining, classification: Classifications, growth: GrowthResult, matches: bool,
    main_rules: RuleSet, category: Mining, category_rules: RuleSet, patterns: Patterns, validation: Validation,
    counter: SupportCounter, extended_counter: SupportCounter, products: ProductAnalysis, trends: Trends,
}

impl Analysis {
    fn new() -> Self {
        let params = Params::read(); let data = Data::read(); let universe: Itemset = data.products.keys().cloned().collect(); let total = data.baskets.len() as i64;
        let mining = apriori(&data.sets,universe.clone(),params.value("min_support"),params.n("max_size"),None);
        let classification = classify(&mining.frequent,total);
        let growth = fp_growth(data.baskets.iter().map(|basket| (basket.products(),1)).collect(),params.value("min_support"),params.n("max_size")); let matches = mining.frequent == growth.itemsets;
        let main_rules = make_rules(&mining,total,&params,None);
        let category_universe = universe.into_iter().chain(data.categories.iter().cloned()).collect();
        let category = apriori(&data.extended,category_universe,params.value("category_min_support"),params.n("max_size"),Some(&data.taxonomy));
        let category_rules = make_rules(&category,total,&params,Some(&data.products));
        let patterns = purchase_patterns(&data,&params); let validation = Validation::new(&data,&params);
        let counter = SupportCounter::new(data.sets.clone()); let extended_counter = SupportCounter::new(data.extended.clone());
        let products = ProductAnalysis::new(&data,&params,&mining,&main_rules.rules,&counter); let trends = Trends::new(&data,&params);
        Self { params, data, mining, classification, growth, matches, main_rules, category, category_rules, patterns, validation, counter, extended_counter, products, trends }
    }

    fn summary_lines(&self) -> Vec<String> {
        let d = &self.data; let total = d.baskets.len(); let sizes: Vec<usize> = d.baskets.iter().map(|basket| basket.counts.len()).collect(); let largest = *sizes.iter().max().unwrap();
        let mut lines: Vec<String> = d.errors.iter().map(|error| format!("ERROR {error}")).collect();
        lines.push(format!("ITEMS rows {} adopted {} categories {}",d.item_rows,d.products.len(),d.categories.len()));
        lines.push(format!("TRANSACTIONS lines {} adopted {} rejected {} duplicates {} transactions {} empty {}",d.transaction_lines,d.adopted,d.rejected,d.duplicates,d.transactions,d.transactions - total));
        lines.push(format!("BASKETS count {total} customers {} first_day {} last_day {} average_size {} largest {largest}",d.customers.len(),d.first_day,d.last_day,fraction(Fraction::new(sizes.iter().sum::<usize>() as i64,total as i64))));
        for size in 1..=largest { let count = sizes.iter().filter(|&&value| value == size).count(); lines.push(format!("SIZE {size} baskets {count} share {}",percent(count as i64,total as i64))); }
        let c = &self.classification;
        lines.push(format!("FREQUENT itemsets {} closed {} maximal {} generators {} levels {}",self.mining.frequent.len(),c.closed.len(),c.maximal.len(),c.generators.len(),self.mining.levels.len()));
        let g = &self.growth;
        lines.push(format!("FPGROWTH header {} nodes {} conditional_trees {} conditional_nodes {} itemsets {} {}",g.header,g.nodes,g.conditional_trees,g.conditional_nodes,g.itemsets.len(),if self.matches { "MATCH" } else { "MISMATCH" }));
        if !self.matches {
            for (label,first,second) in [("ONLY_APRIORI",&self.mining.frequent,&g.itemsets),("ONLY_FPGROWTH",&g.itemsets,&self.mining.frequent)] {
                for (items,count) in ordered_itemsets(first) { if second.get(items) != Some(&count) { lines.push(format!("{label} {} {count}",items.join("+"))); } }
            }
        }
        lines.push(format!("RULES generated {} passed {} productive {}",self.main_rules.generated,self.main_rules.rules.len(),self.main_rules.productive));
        for level in &self.category.levels { lines.push(format!("CATEGORY_LEVEL {} candidates {} taxonomy {} pruned {} counted {} frequent {}",level.size,level.candidates,level.excluded,level.pruned,level.counted,level.frequent.len())); }
        lines.push(format!("CATEGORY_RULES itemsets {} generated {} passed {} productive {}",self.category.frequent.len(),self.category_rules.generated,self.category_rules.rules.len(),self.category_rules.productive));
        lines.push(format!("SEQUENCES customers {} multi_day {} pairs {} frequent {}",d.customers.len(),self.patterns.multi_day,self.patterns.pairs,self.patterns.sequences.len())); lines
    }

    fn itemset_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for level in &self.mining.levels {
            lines.push(format!("LEVEL {} candidates {} pruned {} counted {} frequent {}",level.size,level.candidates,level.pruned,level.counted,level.frequent.len()));
            for (items,count) in &level.frequent { lines.push(format!("{} {count}",items.join("+"))); }
        }
        lines
    }

    fn classification_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for (label,frequent) in [("CLOSED",&self.classification.closed),("MAXIMAL",&self.classification.maximal),("GENERATOR",&self.classification.generators)] {
            for (items,count) in ordered_itemsets(frequent) { lines.push(format!("{label} {} {count}",items.join("+"))); }
        }
        lines
    }

    fn sequence_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for (index,s) in self.patterns.sequences.iter().enumerate() { lines.push(format!("SEQ {} {} -> {} customers {} base {} confidence {} lift {} gap {}",index + 1,s.first,s.second,s.count,s.base,fraction(s.confidence),fraction(s.lift),fraction(s.gap))); }
        for r in &self.patterns.repeats { lines.push(format!("REPEAT {} customers {} intervals {} min {} max {} mean {} median {}",r.item,r.customers,r.count,r.minimum,r.maximum,fraction(r.mean),fraction(r.median))); } lines
    }

    fn evaluation_line(label: &str, counts: [i64;5]) -> String {
        let [cases,covered,hit1,hit,baseline] = counts;
        format!("RECOMMEND {label} cases {cases} covered {covered} hit1 {hit1} hit {hit} rate {} baseline {baseline} rate {}",fraction(Fraction::new(hit,cases)),fraction(Fraction::new(baseline,cases)))
    }

    fn validation_lines(&self) -> Vec<String> {
        let v = &self.validation; let mut lines = Vec::new();
        for entry in &v.verdicts {
            let rule = &v.train_rules[entry.rule];
            lines.push(format!("RULE {} {} train {} confidence {} lift {} test {} of {} confidence {} lift {} {}",rule.rank,arrow(rule),rule.count,fraction(rule.confidence),fraction(rule.lift),entry.joint,entry.antecedent,entry.confidence.map_or_else(|| "-".into(),fraction),entry.lift.map_or_else(|| "-".into(),fraction),VERDICTS[entry.verdict]));
        }
        for rule in &v.emerging { lines.push(format!("EMERGING {} {} test {} confidence {} lift {}",rule.rank,arrow(rule),rule.count,fraction(rule.confidence),fraction(rule.lift))); }
        lines.push(format!("VALIDATION train {} test {} itemsets {} rules {} hold {} fail {} unseen {} emerging {}",v.train_count,v.test_count,v.training_count,v.train_rules.len(),v.totals[0],v.totals[1],v.totals[2],v.emerging.len()));
        for (size,&counts) in &v.evaluations { lines.push(Self::evaluation_line(&format!("size {size}"),counts)); }
        lines.push(Self::evaluation_line("total",v.total)); lines
    }

    fn matrix_lines(label: &str, items: &[String], counter: &SupportCounter) -> Vec<String> {
        let mut lines = Vec::new();
        for (index,item) in items.iter().enumerate() { lines.push(format!("{label} {} {item} baskets {}",index + 1,counter.single(item))); }
        let mut header = "    ".to_string(); for i in 1..=items.len() { header.push_str(&format!("{i:7}")); } lines.push(header);
        for (i,first) in items.iter().enumerate() {
            let mut line = format!("{:4}",i + 1);
            for (j,second) in items.iter().enumerate() {
                let value = if i == j { "-".into() } else { (100 * counter.baskets.len() as i64 * counter.count(&[first.clone(),second.clone()]) / (counter.single(first) * counter.single(second))).to_string() };
                line.push_str(&format!("{value:>7}"));
            }
            lines.push(line);
        }
        lines
    }

    fn product_lines(&self) -> Vec<String> {
        let d = &self.data; let stats = &self.products.stats; let total = d.baskets.len() as i64;
        let revenue: i64 = stats.values().map(|p| p.revenue).sum(); let units: i64 = stats.values().map(|p| p.units).sum(); let mut lines = Vec::new();
        let mut order: Itemset = d.products.keys().cloned().collect(); order.sort_by(|a,b| stats[b].revenue.cmp(&stats[a].revenue).then_with(|| a.cmp(b)));
        for (index,item) in order.iter().enumerate() {
            let product = &d.products[item]; let p = &stats[item];
            let partner = p.partner.as_ref().map_or_else(|| "none".into(),|partner| format!("{} {}",partner.item,fraction(partner.lift)));
            let best = p.best.map_or_else(|| "none".into(),|index| { let rule = &self.main_rules.rules[index]; format!("{} {}",rule.rank,arrow(rule)) });
            lines.push(format!("ITEM {} {item} {} price {} units {} revenue {} share {} baskets {} support {} customers {} itemsets {} heldout {} hits {} partner {partner} best {best}",index + 1,product.category,money(product.price),p.units,money(p.revenue),percent(p.revenue,revenue),p.support,fraction(Fraction::new(p.support,total)),self.patterns.buyers[item],p.itemsets,self.validation.held[item],self.validation.hits[item]));
        }
        let mut categories: BTreeMap<String,[i64;3]> = BTreeMap::new();
        for (item,product) in &d.products { let row = categories.entry(product.category.clone()).or_default(); row[0] += 1; row[1] += stats[item].units; row[2] += stats[item].revenue; }
        let mut order: Itemset = categories.keys().cloned().collect(); order.sort_by(|a,b| categories[b][2].cmp(&categories[a][2]).then_with(|| a.cmp(b)));
        for name in order {
            let [items,units,value] = categories[&name]; let count = self.extended_counter.single(&name);
            lines.push(format!("CATEGORY {name} items {items} units {units} revenue {} share {} baskets {count} support {}",money(value),percent(value,revenue),fraction(Fraction::new(count,total))));
        }
        lines.push(format!("TOTAL items {} units {units} revenue {} baskets {total} customers {}",d.products.len(),money(revenue),d.customers.len()));
        for (index,group) in self.products.groups.iter().enumerate() { lines.push(format!("GROUP {} items {} edges {} core {} revenue {} share {} members {}",index + 1,group.members.len(),group.edges,group.core,money(group.revenue),percent(group.revenue,revenue),group.members.join("+"))); }
        for s in &self.products.substitutes { lines.push(format!("SUBSTITUTE {} {} count {} expected {} lift {}",s.first,s.second,s.count,fraction(s.expected),fraction(s.lift))); }
        let mut order: Itemset = d.products.keys().cloned().collect(); order.sort_by(|a,b| self.counter.single(b).cmp(&self.counter.single(a)).then_with(|| a.cmp(b))); order.truncate(self.params.n("matrix_size"));
        lines.extend(Self::matrix_lines("MATRIX",&order,&self.counter));
        let mut order: Itemset = d.categories.iter().cloned().collect(); order.sort_by(|a,b| self.extended_counter.single(b).cmp(&self.extended_counter.single(a)).then_with(|| a.cmp(b)));
        lines.extend(Self::matrix_lines("CATEGORY_MATRIX",&order,&self.extended_counter)); lines
    }

    fn trend_lines(&self) -> Vec<String> {
        let t = &self.trends; let mut lines = Vec::new();
        let mut rows: Vec<(&str,Vec<i64>)> = vec![("WEEK",(1..=t.weeks as i64).collect()),("BASKETS",t.baskets.clone()),("UNITS",t.units.clone()),("CUSTOMERS",t.customers.iter().map(|&n| n as i64).collect())];
        rows.extend(t.series.iter().map(|(name,values)| (name.as_str(),values.clone())));
        for (label,values) in rows { let mut line = format!("{label:<17}"); for value in values { line.push_str(&format!("{value:6}")); } lines.push(line); }
        for trend in &t.trends { lines.push(format!("TREND {} units {} slope {} relative {} {}",trend.name,trend.units,fraction(trend.slope),trend.relative.map_or_else(|| "-".into(),fraction),trend.verdict)); } lines
    }

    fn customer_lines(&self) -> Vec<String> {
        let d = &self.data; let mut lines = Vec::new(); let mut segments = [[0_i64;2];4]; let labels = ["NEW","LOYAL","AT_RISK","REGULAR"];
        let total_revenue: i64 = self.products.stats.values().map(|p| p.revenue).sum();
        for (customer,indices) in &d.customers {
            let mut days = BTreeSet::new(); let mut history = Basket::new(); let mut categories: BTreeMap<String,i64> = BTreeMap::new(); let (mut units,mut revenue) = (0,0);
            for &index in indices {
                let basket = &d.baskets[index]; days.insert(basket.day);
                for (item,&quantity) in &basket.counts { history.insert(item.clone()); units += quantity; let product = &d.products[item]; revenue += quantity * product.price; *categories.entry(product.category.clone()).or_default() += quantity; }
            }
            let first = *days.first().unwrap(); let last = *days.last().unwrap(); let count = indices.len();
            let mut favorite: Itemset = categories.keys().cloned().collect(); favorite.sort_by(|a,b| categories[b].cmp(&categories[a]).then_with(|| a.cmp(b)));
            let segment = if first > d.last_day - 28 { 0 } else if count >= 4 && d.last_day - last <= 14 { 1 } else if d.last_day - last > 28 { 2 } else { 3 };
            let offer = rule_recommendation(&history,&self.main_rules.rules,self.params.n("recommend_top")); segments[segment][0] += 1; segments[segment][1] += revenue;
            lines.push(format!("CUSTOMER {customer} baskets {count} days {} first {first} last {last} items {} units {units} revenue {} average {} favorite {} segment {} offer {}",days.len(),history.len(),money(revenue),money(revenue / count as i64),favorite[0],labels[segment],if offer.is_empty() { "none".into() } else { offer.join("+") }));
        }
        for (label,[count,revenue]) in labels.into_iter().zip(segments) { lines.push(format!("SEGMENT {label} customers {count} revenue {} share {}",money(revenue),percent(revenue,total_revenue))); } lines
    }
}

fn main() {
    let a = Analysis::new();
    for (name,lines) in [("summary.txt",a.summary_lines()),("itemsets.txt",a.itemset_lines()),("closed_maximal.txt",a.classification_lines()),("rules.csv",report::rules_csv(&a.main_rules.rules)),("category_rules.csv",report::rules_csv(&a.category_rules.rules)),("sequences.txt",a.sequence_lines()),("validation.txt",a.validation_lines()),("items_report.txt",a.product_lines()),("trends.txt",a.trend_lines()),("customers.txt",a.customer_lines())] { report::write_report(name,lines); }
}
