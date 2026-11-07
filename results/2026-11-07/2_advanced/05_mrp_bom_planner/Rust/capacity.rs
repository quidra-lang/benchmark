use std::collections::BTreeMap;
use std::io;
use crate::items::{read_rows, Item};
use crate::bom::Bom;
pub struct WorkCenter { pub id: String, pub minutes: i64, pub efficiency: i64, pub available: i64, pub description: String }
pub struct Operation { pub number: usize, pub center: String, pub setup: i64, pub run: i64 }
impl Operation { pub fn minutes(&self, quantity: i64) -> i64 { self.setup + quantity * self.run } }
pub fn read_centers(errors: &mut Vec<String>) -> io::Result<BTreeMap<String, WorkCenter>> {
    let mut centers = BTreeMap::new();
    for (line, fields) in read_rows("workcenters.csv")? {
        let id = &fields[0]; let minutes = fields[1].parse::<i64>().unwrap(); let efficiency = fields[2].parse::<i64>().unwrap();
        let reason = if centers.contains_key(id) { Some(format!("duplicate center {id}")) } else if !(50..=150).contains(&efficiency) { Some(format!("bad efficiency {efficiency}")) } else { None };
        if let Some(reason) = reason { errors.push(format!("workcenters.csv line {line}: {reason}")); }
        else { centers.insert(id.clone(), WorkCenter { id: id.clone(), minutes, efficiency, available: minutes * efficiency / 100, description: fields[3].clone() }); }
    }
    Ok(centers)
}
pub fn read_routings(items: &BTreeMap<String, Item>, centers: &BTreeMap<String, WorkCenter>, bom: &Bom, errors: &mut Vec<String>) -> io::Result<BTreeMap<String, Vec<Operation>>> {
    let mut routings: BTreeMap<String, Vec<Operation>> = BTreeMap::new();
    for (line, fields) in read_rows("routings.csv")? {
        let id = &fields[0]; let number = fields[1].parse::<usize>().unwrap(); let center = &fields[2]; let run = fields[4].parse::<i64>().unwrap();
        let reason = if !items.contains_key(id) { Some(format!("unknown item {id}")) } else if !centers.contains_key(center) { Some(format!("unknown center {center}")) }
            else if !bom.manufactured(id) { Some(format!("purchased item {id}")) } else if run < 1 { Some(format!("bad run time {run}")) }
            else if routings.get(id).is_some_and(|operations| operations.iter().any(|operation| operation.number == number)) { Some(format!("duplicate {id} operation {number}")) } else { None };
        if let Some(reason) = reason { errors.push(format!("routings.csv line {line}: {reason}")); }
        else { routings.entry(id.clone()).or_default().push(Operation { number, center: center.clone(), setup: fields[3].parse().unwrap(), run }); }
    }
    for operations in routings.values_mut() { operations.sort_by_key(|operation| operation.number); }
    Ok(routings)
}
pub fn operation_week(receipt: usize, lead: usize, index: usize, count: usize) -> usize { (receipt as i32 - lead as i32 + (index * lead / count) as i32).max(1) as usize }
pub fn level_loads(loads: &[i64], available: i64) -> Vec<i64> {
    let mut leveled = vec![0; loads.len()]; let mut carry = 0;
    for week in (2..loads.len()).rev() { let total = loads[week] + carry; leveled[week] = total.min(available); carry = total - leveled[week]; }
    leveled[1] = loads[1] + carry; leveled
}
