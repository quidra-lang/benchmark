use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};

pub struct Params {
    pub reference_day: i64,
    pub snapshot_day: i64,
    pub outcome_days: i64,
    pub k_min: usize,
    pub k_max: usize,
    pub methods: Vec<String>,
    pub restarts: usize,
    pub max_iterations: usize,
    pub seed: i64,
    pub subsamples: usize,
    pub subsample_percent: usize,
    pub outlier_sd: f64,
    pub overdue_factor: i64,
    pub order_bins: Vec<i64>,
    pub top_categories: usize,
    pub top_customers: usize,
    pub period_days: i64,
    pub periods: usize,
}

#[derive(Clone)]
pub struct Row {
    pub customer: String,
    pub day: i64,
    pub order_id: String,
    pub category: String,
    pub amount: i64,
}

pub struct TransactionData {
    pub row_count: usize,
    pub duplicates: usize,
    pub free: usize,
    pub valid_rows: Vec<Row>,
    pub customers: BTreeSet<String>,
}

#[derive(Clone)]
pub struct Order {
    pub customer: String,
    pub day: i64,
    pub net: i64,
    pub rows: Vec<Row>,
}

pub fn read_lines(path: &str) -> io::Result<Vec<String>> {
    Ok(fs::read_to_string(path)?.lines().map(str::to_owned).collect())
}

pub fn read_params(path: &str) -> io::Result<Params> {
    let entries: Vec<Vec<String>> = read_lines(path)?.iter()
        .map(|line| line.split(' ').skip(1).map(str::to_owned).collect()).collect();
    let value = |line: usize| entries[line][0].parse::<usize>().unwrap();
    Ok(Params {
        reference_day: value(0) as i64, snapshot_day: value(1) as i64, outcome_days: value(2) as i64,
        k_min: value(3), k_max: entries[3][1].parse().unwrap(), methods: entries[4].clone(),
        restarts: value(5), max_iterations: value(6), seed: value(7) as i64,
        subsamples: value(8), subsample_percent: value(9), outlier_sd: entries[10][0].parse().unwrap(),
        overdue_factor: value(11) as i64, order_bins: entries[12].iter().map(|text| text.parse().unwrap()).collect(),
        top_categories: value(13), top_customers: value(14), period_days: value(15) as i64, periods: value(16),
    })
}

pub fn read_transactions(path: &str) -> io::Result<TransactionData> {
    let mut data = TransactionData { row_count: 0, duplicates: 0, free: 0,
        valid_rows: Vec::new(), customers: BTreeSet::new() };
    let mut seen = BTreeSet::new();
    for line in read_lines(path)?.into_iter().skip(1) {
        let fields: Vec<_> = line.split(',').collect();
        let row = Row { customer: fields[0].to_owned(), day: fields[1].parse().unwrap(),
            order_id: fields[2].to_owned(), category: fields[3].to_owned(), amount: fields[4].parse().unwrap() };
        data.row_count += 1;
        data.customers.insert(row.customer.clone());
        if !seen.insert(line) { data.duplicates += 1; }
        else if row.amount == 0 { data.free += 1; }
        else { data.valid_rows.push(row); }
    }
    Ok(data)
}

pub fn group_orders(rows: &[Row], first: i64, last: i64) -> Vec<Order> {
    let mut orders: Vec<Order> = Vec::new();
    let mut indices = BTreeMap::new();
    for row in rows.iter().filter(|row| first <= row.day && row.day <= last) {
        let index = *indices.entry(row.order_id.clone()).or_insert_with(|| {
            orders.push(Order { customer: row.customer.clone(), day: row.day, net: 0, rows: Vec::new() });
            orders.len() - 1
        });
        orders[index].day = orders[index].day.min(row.day);
        orders[index].net += row.amount;
        orders[index].rows.push(row.clone());
    }
    orders
}

pub fn orders_by_customer(orders: &[Order]) -> BTreeMap<String, Vec<Order>> {
    let mut grouped: BTreeMap<String, Vec<Order>> = BTreeMap::new();
    for order in orders { grouped.entry(order.customer.clone()).or_default().push(order.clone()); }
    grouped
}
