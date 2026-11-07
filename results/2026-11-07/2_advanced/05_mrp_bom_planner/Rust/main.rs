mod items;
mod bom;
mod lot_sizing;
mod capacity;
mod costing;
mod report;

use std::collections::{BTreeMap, HashSet};
use std::{fs, io};
use items::{read_items, read_rows, Item};
use bom::{read_bom, need, Bom};
use capacity::{read_centers, read_routings, operation_week, level_loads, WorkCenter, Operation};
use costing::{standard_costs, abc_classes, Cost};
use lot_sizing::lot_size;
use report::{money, percent, table_row, write_report};

const MESSAGE_KINDS: [&str; 9] = ["BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER", "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD"];
fn total(values: &[i64]) -> i64 { values.iter().sum() }
#[derive(Clone)]
struct ScheduleRow { item: String, week: usize, quantity: i64, line: usize }
struct Inquiry { id: String, item: String, quantity: i64, week: usize, line: usize }
#[derive(Clone)]
struct Demand { item: String, kind: &'static str, week: usize, quantity: i64, order_id: String, line: usize, parent: String, parent_number: usize }
impl Demand {
    fn new(item: String, kind: &'static str, week: usize, quantity: i64) -> Self { Self { item, kind, week, quantity, order_id: String::new(), line: 0, parent: String::new(), parent_number: 0 } }
    fn sort_key(&self) -> (usize, u8, usize, &str, usize) { (self.week, match self.kind { "MPS" => 0, "ORDER" => 1, _ => 2 }, self.line, &self.parent, self.parent_number) }
    fn root_key(&self) -> (String, u8, usize, String) { (self.item.clone(), match self.kind { "MPS" => 0, "ORDER" => 1, _ => 2 }, self.week, self.order_id.clone()) }
    fn text(&self) -> String {
        match self.kind { "SAFETY" => format!("SAFETY {}", self.item), "MPS" => format!("MPS {} week {}", self.item, self.week), "ORDER" => format!("ORDER {} {} week {}", self.order_id, self.item, self.week), _ => format!("{} order {} week {}", self.parent, self.parent_number, self.week) }
    }
}
#[derive(Clone)]
struct PlannedOrder { item: String, number: usize, receipt: usize, quantity: i64, original_release: i32, release: usize }
impl PlannedOrder {
    fn new(item: String, number: usize, receipt: usize, quantity: i64, lead: usize) -> Self { let original_release = receipt as i32 - lead as i32; Self { item, number, receipt, quantity, original_release, release: original_release.max(1) as usize } }
}
#[derive(Clone)]
struct Allocation { demand: Demand, share: i64 }
#[derive(Clone)]
struct Supply { kind: &'static str, week: usize, quantity: i64, line: usize, order: Option<PlannedOrder>, remaining: i64, allocations: Vec<Allocation>, roots: Vec<Demand> }
impl Supply {
    fn new(kind: &'static str, week: usize, quantity: i64, line: usize, order: Option<PlannedOrder>) -> Self { Self { kind, week, quantity, line, order, remaining: quantity, allocations: Vec::new(), roots: Vec::new() } }
    fn header(&self) -> String {
        match self.kind {
            "STOCK" => format!("STOCK quantity {}", self.quantity), "RECEIPT" => format!("RECEIPT line {} week {} quantity {}", self.line, self.week, self.quantity),
            _ => { let order = self.order.as_ref().unwrap(); format!("ORDER {} receipt {} release {} quantity {}", order.number, order.receipt, order.release, order.quantity) }
        }
    }
    fn serves(&self, order_id: &str) -> bool { self.roots.iter().any(|root| root.kind == "ORDER" && root.order_id == order_id) }
}
#[derive(Clone)]
struct ItemPlan {
    item: Item, receipts: Vec<i64>, demands: Vec<Demand>, gross: Vec<i64>, on_hand: Vec<i64>, net: Vec<i64>, planned_receipts: Vec<i64>, planned_releases: Vec<i64>,
    orders: Vec<PlannedOrder>, supplies: Vec<Supply>, order_supplies: Vec<usize>,
}
impl ItemPlan {
    fn new(item: Item, horizon: usize, receipts: Vec<i64>) -> Self {
        let mut on_hand = vec![0; horizon + 1]; on_hand[0] = item.on_hand;
        Self { item, receipts, demands: Vec::new(), gross: vec![0; horizon + 1], on_hand, net: vec![0; horizon + 1], planned_receipts: vec![0; horizon + 1], planned_releases: vec![0; horizon + 1], orders: Vec::new(), supplies: Vec::new(), order_supplies: Vec::new() }
    }
    fn past_due(&self) -> i64 { self.orders.iter().filter(|order| order.original_release < 1).map(|order| order.quantity).sum() }
}
#[derive(Clone)]
struct Plan { items: BTreeMap<String, ItemPlan>, loads: BTreeMap<String, Vec<i64>>, overloads: BTreeMap<String, Vec<i64>> }
struct Promise { inquiry: usize, week: usize, material_week: usize, reason: String }
impl Promise { fn status(&self, inquiry: &Inquiry) -> &'static str { if self.week == 0 { "rejected" } else if self.week == inquiry.week { "on_time" } else { "late" } } }
struct PlanningData {
    errors: Vec<String>, horizon: usize, peg: Vec<String>, tree_quantity: i64, items: BTreeMap<String, Item>, bom: Bom, centers: BTreeMap<String, WorkCenter>, routings: BTreeMap<String, Vec<Operation>>,
    inquiries: Vec<Inquiry>, mps: Vec<Demand>, codes: BTreeMap<String, usize>, cumulative: BTreeMap<String, usize>, order: Vec<String>, center_order: Vec<String>, receipts: BTreeMap<String, Vec<ScheduleRow>>, scheduled: BTreeMap<String, Vec<i64>>,
}
fn schedule_error(item: &str, week: usize, quantity: i64, items: &BTreeMap<String, Item>, horizon: usize) -> Option<String> {
    if !items.contains_key(item) { Some(format!("unknown item {item}")) } else if !(1..=horizon).contains(&week) { Some(format!("week {week} outside horizon")) } else if quantity < 1 { Some(format!("bad quantity {quantity}")) } else { None }
}
fn read_schedule(name: &str, items: &BTreeMap<String, Item>, horizon: usize, errors: &mut Vec<String>, unique: bool) -> io::Result<Vec<ScheduleRow>> {
    let mut result = Vec::new(); let mut seen = HashSet::new();
    for (line, fields) in read_rows(name)? {
        let item = &fields[0]; let week = fields[1].parse().unwrap(); let quantity = fields[2].parse().unwrap();
        let mut reason = schedule_error(item, week, quantity, items, horizon);
        if reason.is_none() && unique && seen.contains(&(item.clone(), week)) { reason = Some(format!("duplicate {item} week {week}")); }
        if let Some(reason) = reason { errors.push(format!("{name} line {line}: {reason}")); }
        else { seen.insert((item.clone(), week)); result.push(ScheduleRow { item: item.clone(), week, quantity, line }); }
    }
    Ok(result)
}
impl PlanningData {
    fn read() -> io::Result<Self> {
        let (mut horizon, mut peg, mut tree_quantity) = (0, Vec::new(), 0);
        for line in fs::read_to_string("input/params.txt")?.split_terminator('\n') {
            let words: Vec<_> = line.split(' ').collect(); match words[0] { "horizon" => horizon = words[1].parse().unwrap(), "peg" => peg = words[1..].iter().map(|word| (*word).to_owned()).collect(), _ => tree_quantity = words[1].parse().unwrap() }
        }
        let mut errors = Vec::new(); let items = read_items(&mut errors)?; let bom = read_bom(&items, &mut errors)?; let centers = read_centers(&mut errors)?; let routings = read_routings(&items, &centers, &bom, &mut errors)?;
        let mps_rows = read_schedule("mps.csv", &items, horizon, &mut errors, true)?; let mut receipt_rows = read_schedule("receipts.csv", &items, horizon, &mut errors, false)?;
        let mut inquiries = Vec::new(); let mut seen = HashSet::new();
        for (line, fields) in read_rows("orders.csv")? {
            let id = &fields[0]; let item = &fields[1]; let quantity = fields[2].parse().unwrap(); let week = fields[3].parse().unwrap();
            let reason = if seen.contains(id) { Some(format!("duplicate order {id}")) } else { schedule_error(item, week, quantity, &items, horizon) };
            if let Some(reason) = reason { errors.push(format!("orders.csv line {line}: {reason}")); }
            else { seen.insert(id.clone()); inquiries.push(Inquiry { id: id.clone(), item: item.clone(), quantity, week, line }); }
        }
        let mps = mps_rows.into_iter().map(|row| Demand::new(row.item, "MPS", row.week, row.quantity)).collect();
        let (mut codes, mut cumulative) = (BTreeMap::new(), BTreeMap::new()); for id in items.keys() { bom.code(id, &mut codes); bom.cumulative(id, &items, &mut cumulative); }
        let mut order: Vec<_> = items.keys().cloned().collect(); order.sort_by(|a, b| codes[a].cmp(&codes[b]).then_with(|| a.cmp(b)));
        let center_order = centers.keys().cloned().collect(); let mut receipts: BTreeMap<String, Vec<ScheduleRow>> = items.keys().map(|id| (id.clone(), Vec::new())).collect(); let mut scheduled: BTreeMap<String, Vec<i64>> = items.keys().map(|id| (id.clone(), vec![0; horizon + 1])).collect();
        receipt_rows.sort_by_key(|row| (row.week, row.line)); for row in receipt_rows { scheduled.get_mut(&row.item).unwrap()[row.week] += row.quantity; receipts.get_mut(&row.item).unwrap().push(row); }
        Ok(Self { errors, horizon, peg, tree_quantity, items, bom, centers, routings, inquiries, mps, codes, cumulative, order, center_order, receipts, scheduled })
    }
    fn weeks(&self) -> Vec<i64> { (1..=self.horizon).map(|week| week as i64).collect() }
}
fn run_mrp(data: &PlanningData, orders: &[Demand]) -> Plan {
    let mut plans: BTreeMap<_, _> = data.order.iter().map(|id| (id.clone(), ItemPlan::new(data.items[id].clone(), data.horizon, data.scheduled[id].clone()))).collect();
    for demand in data.mps.iter().chain(orders) { plans.get_mut(&demand.item).unwrap().demands.push(demand.clone()); }
    for id in &data.order {
        {
            let plan = plans.get_mut(id).unwrap(); for demand in &plan.demands { plan.gross[demand.week] += demand.quantity; }
            let mut projected = plan.item.on_hand;
            for week in 1..=data.horizon {
                projected += plan.receipts[week] - plan.gross[week];
                if projected < plan.item.safety {
                    let quantity = lot_size(&plan.item, week, projected, &plan.receipts, &plan.gross, data.horizon);
                    let order = PlannedOrder::new(id.clone(), plan.orders.len() + 1, week, quantity, plan.item.lead);
                    plan.net[week] = plan.item.safety - projected; plan.planned_receipts[week] = quantity; plan.planned_releases[order.release] += quantity; projected += quantity; plan.orders.push(order);
                }
                plan.on_hand[week] = projected;
            }
        }
        for order in plans[id].orders.clone() { for row in &data.bom.children[id] { let mut demand = Demand::new(row.child.clone(), "DEPENDENT", order.release, need(row, order.quantity)); demand.parent = id.clone(); demand.parent_number = order.number; plans.get_mut(&row.child).unwrap().demands.push(demand); } }
    }
    let mut loads: BTreeMap<_, _> = data.centers.keys().map(|id| (id.clone(), vec![0; data.horizon + 1])).collect();
    for (id, operations) in &data.routings { for order in &plans[id].orders { for (index, operation) in operations.iter().enumerate() { let week = operation_week(order.receipt, data.items[id].lead, index, operations.len()); loads.get_mut(&operation.center).unwrap()[week] += operation.minutes(order.quantity); } } }
    let overloads = loads.iter().map(|(id, weeks)| (id.clone(), weeks.iter().map(|&load| (load - data.centers[id].available).max(0)).collect())).collect();
    Plan { items: plans, loads, overloads }
}
fn promise_inquiries(data: &PlanningData, base: &Plan) -> (Vec<Promise>, Plan) {
    let mut current = base.clone(); let mut promised = Vec::new(); let mut promises = Vec::new();
    for (number, inquiry) in data.inquiries.iter().enumerate() {
        let mut promise = Promise { inquiry: number, week: 0, material_week: 0, reason: String::new() };
        for week in inquiry.week..=data.horizon {
            let mut demand = Demand::new(inquiry.item.clone(), "ORDER", week, inquiry.quantity); demand.order_id = inquiry.id.clone(); demand.line = inquiry.line;
            let mut demands = promised.clone(); demands.push(demand.clone()); let trial = run_mrp(data, &demands);
            let mut reason = data.order.iter().find(|id| trial.items[*id].past_due() > current.items[*id].past_due()).cloned();
            if reason.is_none() {
                if promise.material_week == 0 { promise.material_week = week; }
                'centers: for id in &data.center_order { for w in 1..=data.horizon { if trial.overloads[id][w] > current.overloads[id][w] { reason = Some(format!("{id} week {w}")); break 'centers; } } }
            }
            if let Some(reason) = reason { if week == inquiry.week { promise.reason = reason; } }
            else { promise.week = week; promised.push(demand); current = trial; break; }
        }
        promises.push(promise);
    }
    (promises, current)
}
fn parent_supply<'a>(plan: &'a Plan, demand: &Demand) -> &'a Supply { let parent = &plan.items[&demand.parent]; &parent.supplies[parent.order_supplies[demand.parent_number - 1]] }
fn peg_plan(data: &PlanningData, plan: &mut Plan) {
    for id in &data.order {
        let p = &plan.items[id]; let item = &p.item; let mut demands = p.demands.clone(); demands.sort_by(|a, b| a.sort_key().cmp(&b.sort_key()));
        if item.safety > 0 { demands.insert(0, Demand::new(id.clone(), "SAFETY", 0, item.safety)); }
        let mut supplies = Vec::new(); if item.on_hand > 0 { supplies.push(Supply::new("STOCK", 0, item.on_hand, 0, None)); }
        for receipt in &data.receipts[id] { supplies.push(Supply::new("RECEIPT", receipt.week, receipt.quantity, receipt.line, None)); }
        for order in &p.orders { supplies.push(Supply::new("ORDER", order.receipt, order.quantity, 0, Some(order.clone()))); }
        supplies.sort_by_key(|supply| (supply.week, match supply.kind { "STOCK" => 0, "RECEIPT" => 1, _ => 2 }, supply.line)); let mut index = 0;
        for demand in demands {
            let mut remaining = demand.quantity;
            while remaining > 0 { while supplies[index].remaining == 0 { index += 1; } let supply = &mut supplies[index]; let share = remaining.min(supply.remaining); supply.allocations.push(Allocation { demand: demand.clone(), share }); supply.remaining -= share; remaining -= share; }
        }
        let order_supplies: Vec<_> = supplies.iter().enumerate().filter(|(_, supply)| supply.kind == "ORDER").map(|(index, _)| index).collect();
        for &index in &order_supplies {
            let mut roots = BTreeMap::new();
            for allocation in &supplies[index].allocations {
                let demand = &allocation.demand;
                if demand.kind == "DEPENDENT" { for root in &parent_supply(plan, demand).roots { roots.insert(root.root_key(), root.clone()); } }
                else { roots.insert(demand.root_key(), demand.clone()); }
            }
            supplies[index].roots = roots.into_values().collect();
        }
        let p = plan.items.get_mut(id).unwrap(); p.supplies = supplies; p.order_supplies = order_supplies;
    }
}
fn depth_label(depth: usize) -> String { format!("{}{depth}", ".".repeat(depth)) }
fn grid_lines(data: &PlanningData, plan: &Plan) -> Vec<String> {
    let mut lines = Vec::new();
    for id in &data.order {
        let p = &plan.items[id]; let item = &p.item;
        lines.push(format!("ITEM {id} LLC {} LT {} LOT {} SS {} OH {} {}", data.codes[id], item.lead, item.lot.label(), item.safety, item.on_hand, item.description)); lines.push(table_row("WEEK", &data.weeks(), 6));
        for (label, values) in [("GROSS", &p.gross), ("RECEIPTS", &p.receipts), ("ON_HAND", &p.on_hand), ("NET", &p.net), ("PLAN_RCPT", &p.planned_receipts), ("PLAN_REL", &p.planned_releases)] { lines.push(table_row(label, &values[1..], 6)); }
        lines.push(format!("TOTAL gross {} receipts {} planned {} orders {} ending {}", total(&p.gross), total(&p.receipts), total(&p.planned_receipts), p.orders.len(), p.on_hand[data.horizon]));
    }
    lines
}
fn where_used(bom: &Bom, id: &str, depth: usize, extension: i64, lines: &mut Vec<String>) {
    for row in &bom.parents[id] { let next = extension * row.quantity; lines.push(format!("{} {} qty {} ext {next}", depth_label(depth), row.parent, row.quantity)); where_used(bom, &row.parent, depth + 1, next, lines); }
}
fn allocation_lines(plan: &Plan, supply: &Supply, depth: usize, lines: &mut Vec<String>) {
    for allocation in &supply.allocations { let demand = &allocation.demand; lines.push(format!("{}ALLOC {} {}", " ".repeat(2 * depth), allocation.share, demand.text())); if supply.kind == "ORDER" && demand.kind == "DEPENDENT" { allocation_lines(plan, parent_supply(plan, demand), depth + 1, lines); } }
}
fn pegging_lines(data: &PlanningData, plan: &Plan) -> Vec<String> {
    let mut lines = Vec::new();
    for id in &data.peg {
        let p = &plan.items[id]; lines.push(format!("PEG {id} orders {}", p.orders.len())); where_used(&data.bom, id, 1, 1, &mut lines);
        for kind in ["STOCK", "RECEIPT", "ORDER"] { for supply in p.supplies.iter().filter(|supply| supply.kind == kind) { lines.push(supply.header()); allocation_lines(plan, supply, 1, &mut lines); if supply.remaining > 0 { lines.push(format!("  EXCESS {}", supply.remaining)); } for root in &supply.roots { lines.push(format!("  ROOT {}", root.text())); } } }
    }
    lines
}
fn explosion_lines(data: &PlanningData, id: &str, gross: i64, extension: i64, depth: usize, lines: &mut Vec<String>, totals: &mut BTreeMap<String, i64>) {
    for row in &data.bom.children[id] { let child = &data.items[&row.child]; let next = extension * row.quantity; let quantity = need(row, gross); *totals.entry(row.child.clone()).or_default() += quantity; lines.push(format!("{} {} qty {} scrap {} ext {next} gross {quantity} lt {} cum {} {}", depth_label(depth), row.child, row.quantity, row.scrap, child.lead, data.cumulative[&row.child], child.description)); explosion_lines(data, &row.child, quantity, next, depth + 1, lines, totals); }
}
fn bom_tree_lines(data: &PlanningData) -> Vec<String> {
    let mut lines = Vec::new();
    for (id, item) in &data.items {
        if !data.bom.manufactured(id) || !data.bom.parents[id].is_empty() { continue; }
        lines.push(format!("TREE {id} quantity {}", data.tree_quantity)); lines.push(format!("0 {id} ext 1 gross {} lt {} cum {} {}", data.tree_quantity, item.lead, data.cumulative[id], item.description));
        let mut totals = BTreeMap::new(); explosion_lines(data, id, data.tree_quantity, 1, 1, &mut lines, &mut totals); for (child, quantity) in totals { lines.push(format!("SUM {child} {quantity}")); }
        let mut path = vec![id.clone()]; let mut current = id.as_str();
        while data.bom.manufactured(current) { let mut best = &data.bom.children[current][0]; for row in &data.bom.children[current] { if data.cumulative[&row.child] > data.cumulative[&best.child] { best = row; } } current = &best.child; path.push(current.to_owned()); }
        lines.push(format!("CRITICAL {} cum {}", path.join(" -> "), data.cumulative[id]));
    }
    lines
}
fn cost_lines(data: &PlanningData, plan: &Plan, costs: &BTreeMap<String, Cost>) -> Vec<String> {
    let usage: BTreeMap<_, _> = data.items.keys().map(|id| (id.clone(), total(&plan.items[id].gross))).collect(); let values = data.items.keys().map(|id| (id.clone(), usage[id] * costs[id].total)).collect(); let classes = abc_classes(&values);
    let mut lines = vec!["item,material,labor,total,usage,value,class".to_owned()]; for id in data.items.keys() { let cost = &costs[id]; lines.push(format!("{id},{},{},{},{},{},{}", money(cost.material), money(cost.labor), money(cost.total), usage[id], money(values[id]), classes[id])); } lines
}
fn exception_lines(data: &PlanningData, plan: &Plan) -> Vec<String> {
    let mut messages = Vec::new();
    for id in &data.order {
        let p = &plan.items[id]; let item = &p.item;
        if item.on_hand < item.safety { messages.push(format!("BELOW_SAFETY {id} on hand {} safety {}", item.on_hand, item.safety)); }
        for order in &p.orders { if order.original_release < 1 { messages.push(format!("PAST_DUE {id} order {} receipt {} release {} late {} quantity {}", order.number, order.receipt, order.original_release, 1 - order.original_release, order.quantity)); } else if order.original_release == 1 { messages.push(format!("RELEASE {id} order {} receipt {} quantity {}", order.number, order.receipt, order.quantity)); } }
        let mut balances = vec![0; data.horizon + 1]; let mut balance = item.on_hand; for week in 1..=data.horizon { balance -= p.gross[week]; balances[week] = balance; }
        let mut covered = 0;
        for receipt in &data.receipts[id] { let needed = (1..=data.horizon).find(|&week| balances[week] + covered < item.safety); let text = format!("{id} receipt line {} week {} quantity {}", receipt.line, receipt.week, receipt.quantity); match needed { None => messages.push(format!("CANCEL {text}")), Some(week) if week < receipt.week => messages.push(format!("EXPEDITE {text} to {week}")), Some(week) if week > receipt.week => messages.push(format!("DEFER {text} to {week}")), _ => {} } covered += receipt.quantity; }
        if data.bom.manufactured(id) && !data.routings.contains_key(id) { messages.push(format!("NO_ROUTING {id}")); }
        if total(&p.gross) == 0 && item.on_hand > 0 { messages.push(format!("NO_DEMAND {id} on hand {}", item.on_hand)); }
    }
    for id in &data.center_order { for week in 1..=data.horizon { if plan.overloads[id][week] > 0 { messages.push(format!("OVERLOAD {id} week {week} load {} available {}", plan.loads[id][week], data.centers[id].available)); } } }
    let mut summary = format!("SUMMARY errors {}", data.errors.len()); for kind in MESSAGE_KINDS { let count = messages.iter().filter(|message| message.split(' ').next() == Some(kind)).count(); summary.push_str(&format!(" {} {count}", kind.to_ascii_lowercase())); }
    let mut lines: Vec<_> = data.errors.iter().map(|error| format!("ERROR {error}")).collect(); lines.extend(messages); lines.push(summary); lines
}
fn capacity_lines(data: &PlanningData, plan: &Plan) -> Vec<String> {
    let mut lines = Vec::new(); let mut totals = BTreeMap::new();
    for id in &data.center_order {
        let center = &data.centers[id]; let loads = &plan.loads[id][1..]; let overloads = &plan.overloads[id][1..]; let leveled = level_loads(&plan.loads[id], center.available); let sum = total(loads); totals.insert(id.clone(), sum);
        let capacity = center.available * data.horizon as i64; let peak = if sum > 0 { loads.iter().position(|value| value == loads.iter().max().unwrap()).unwrap() + 1 } else { 0 }; let overloaded = overloads.iter().filter(|&&value| value > 0).count(); let backlog = (leveled[1] - center.available).max(0);
        lines.push(format!("CENTER {} minutes {} efficiency {} available {} {}", center.id, center.minutes, center.efficiency, center.available, center.description));
        for (label, values) in [("WEEK", data.weeks()), ("LOAD", loads.to_vec()), ("UTIL", loads.iter().map(|&load| percent(load, center.available)).collect()), ("OVER", overloads.to_vec()), ("LEVELED", leveled[1..].to_vec())] { lines.push(table_row(label, &values, 7)); }
        lines.push(format!("TOTAL load {sum} available {capacity} utilization {} overloaded {overloaded} peak {peak} backlog {backlog}", percent(sum, capacity)));
    }
    let mut ranked = data.center_order.clone(); ranked.sort_by(|a, b| (totals[b] * data.centers[a].available).cmp(&(totals[a] * data.centers[b].available)).then_with(|| a.cmp(b)));
    for (index, id) in ranked.iter().enumerate() { lines.push(format!("RANK {} {id} load {} utilization {}", index + 1, totals[id], percent(totals[id], data.centers[id].available * data.horizon as i64))); } lines
}
fn promise_lines(data: &PlanningData, promises: &[Promise], base: &Plan, final_plan: &Plan) -> Vec<String> {
    let mut lines = Vec::new(); let (mut on_time, mut late, mut rejected) = (0, 0, 0);
    for promise in promises {
        let inquiry = &data.inquiries[promise.inquiry]; let head = format!("ORDER {} {} quantity {} requested {}", inquiry.id, inquiry.item, inquiry.quantity, inquiry.week); let material = if promise.material_week > 0 { promise.material_week.to_string() } else { "none".to_owned() };
        match promise.status(inquiry) {
            "rejected" => { rejected += 1; lines.push(format!("{head} rejected material {material} reason {}", promise.reason)); continue; }
            "on_time" => { on_time += 1; lines.push(format!("{head} promised {}", promise.week)); }
            _ => { late += 1; lines.push(format!("{head} promised {} late {} material {material} reason {}", promise.week, promise.week - inquiry.week, promise.reason)); }
        }
        for id in &data.order { let p = &final_plan.items[id]; for &index in &p.order_supplies { let supply = &p.supplies[index]; if supply.serves(&inquiry.id) { let order = supply.order.as_ref().unwrap(); lines.push(format!("  SUPPLY {id} order {} receipt {} release {} quantity {}", order.number, order.receipt, order.release, order.quantity)); } } }
    }
    for id in &data.order { let before = &base.items[id]; let after = &final_plan.items[id]; if let Some(week) = (1..=data.horizon).find(|&week| before.planned_receipts[week] != after.planned_receipts[week]) { lines.push(format!("CHANGE {id} from {week} planned {} -> {} orders {} -> {}", total(&before.planned_receipts), total(&after.planned_receipts), before.orders.len(), after.orders.len())); } }
    lines.push(format!("SUMMARY orders {} on_time {on_time} late {late} rejected {rejected}", promises.len())); lines
}
fn release_lines(data: &PlanningData, plan: &Plan) -> Vec<String> {
    let mut orders: Vec<_> = data.order.iter().flat_map(|id| plan.items[id].orders.iter().filter(|order| order.release == 1)).collect(); orders.sort_by(|a, b| (a.original_release, &a.item, a.number).cmp(&(b.original_release, &b.item, b.number)));
    let mut available: BTreeMap<_, _> = data.items.iter().map(|(id, item)| (id.clone(), item.on_hand + data.scheduled[id][1])).collect(); let mut lines = Vec::new(); let (mut made, mut ready_count, mut bought, mut purchase) = (0, 0, 0, 0);
    for order in orders {
        let id = &order.item; let item = &data.items[id]; let lateness = if order.original_release < 1 { format!(" late {}", 1 - order.original_release) } else { String::new() }; let head = format!("{id} order {} receipt {} quantity {}", order.number, order.receipt, order.quantity);
        if !data.bom.manufactured(id) { let value = order.quantity * item.material; bought += 1; purchase += value; lines.push(format!("BUY {head}{lateness} value {}", money(value))); continue; }
        let picks: Vec<_> = data.bom.children[id].iter().map(|row| (row.child.clone(), need(row, order.quantity), available[&row.child])).collect(); let ready = picks.iter().all(|&(_, quantity, have)| quantity <= have);
        made += 1; if ready { ready_count += 1; } lines.push(format!("MAKE {head}{lateness} {}", if ready { "READY" } else { "SHORT" }));
        for (child, quantity, have) in picks { lines.push(format!("  PICK {child} need {quantity} available {have} short {}", (quantity - have).max(0))); if ready { *available.get_mut(&child).unwrap() -= quantity; } }
        if let Some(operations) = data.routings.get(id) { for (index, operation) in operations.iter().enumerate() { lines.push(format!("  OPERATION {} {} week {} minutes {}", operation.number, operation.center, operation_week(order.receipt, item.lead, index, operations.len()), operation.minutes(order.quantity))); } }
    }
    lines.push(format!("SUMMARY make {made} ready {ready_count} short {} buy {bought} value {}", made - ready_count, money(purchase))); lines
}
fn value_lines(data: &PlanningData, plan: &Plan, costs: &BTreeMap<String, Cost>) -> Vec<String> {
    let mut lines = vec!["week,inventory,purchases,labor".to_owned()];
    for week in 1..=data.horizon { let (mut inventory, mut purchases, mut labor) = (0, 0, 0); for id in &data.order { let p = &plan.items[id]; let released = p.planned_releases[week]; inventory += p.on_hand[week] * costs[id].total; if data.bom.manufactured(id) { labor += released * p.item.labor; } else { purchases += released * p.item.material; } } lines.push(format!("{week},{},{},{}", money(inventory), money(purchases), money(labor))); } lines
}
fn main() -> io::Result<()> {
    let data = PlanningData::read()?; let base = run_mrp(&data, &[]); let (promises, mut final_plan) = promise_inquiries(&data, &base); peg_plan(&data, &mut final_plan); let costs = standard_costs(&data.items, &data.bom, &data.order);
    for (name, lines) in [("mrp_grid.txt", grid_lines(&data, &final_plan)), ("pegging.txt", pegging_lines(&data, &final_plan)), ("bom_tree.txt", bom_tree_lines(&data)), ("cost_rollup.csv", cost_lines(&data, &final_plan, &costs)), ("exceptions.txt", exception_lines(&data, &final_plan)), ("capacity.txt", capacity_lines(&data, &final_plan)), ("promises.txt", promise_lines(&data, &promises, &base, &final_plan)), ("releases.txt", release_lines(&data, &final_plan)), ("value_plan.csv", value_lines(&data, &final_plan, &costs))] { write_report(name, &lines)?; }
    Ok(())
}
