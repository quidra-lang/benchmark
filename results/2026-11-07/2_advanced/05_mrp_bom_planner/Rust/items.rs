use std::collections::BTreeMap;
use std::{fs, io};

pub fn read_rows(name: &str) -> io::Result<Vec<(usize, Vec<String>)>> {
    Ok(fs::read_to_string(format!("input/{name}"))?.split_terminator('\n').skip(1).enumerate().map(|(index, line)| (index + 2, line.split(',').map(str::to_owned).collect())).collect())
}
#[derive(Clone, Copy)]
pub enum Lot { Lfl, Foq(i64), Poq(usize), Min(i64, i64) }
impl Lot {
    pub fn label(&self) -> String { match self { Self::Lfl => "LFL".to_owned(), Self::Foq(value) => format!("FOQ {value}"), Self::Poq(value) => format!("POQ {value}"), Self::Min(minimum, multiple) => format!("MIN {minimum}/{multiple}") } }
}
#[derive(Clone)]
pub struct Item { pub id: String, pub lead: usize, pub lot: Lot, pub safety: i64, pub on_hand: i64, pub material: i64, pub labor: i64, pub description: String }
fn parse_lot(rule: &str, text: &str) -> Option<Lot> {
    let values: Vec<i64> = text.split('/').map(|part| part.parse().unwrap()).collect();
    match (rule, values.as_slice()) {
        ("LFL", [0]) => Some(Lot::Lfl), ("FOQ", [value]) if *value >= 1 => Some(Lot::Foq(*value)),
        ("POQ", [value]) if *value >= 1 => Some(Lot::Poq(*value as usize)),
        ("MIN", [minimum, multiple]) if *minimum >= 1 && *multiple >= 1 => Some(Lot::Min(*minimum, *multiple)), _ => None,
    }
}
pub fn read_items(errors: &mut Vec<String>) -> io::Result<BTreeMap<String, Item>> {
    let mut items = BTreeMap::new();
    for (line, fields) in read_rows("items.csv")? {
        let id = &fields[0]; let rule = &fields[2]; let parameter = &fields[3];
        let reason = if items.contains_key(id) { Some(format!("duplicate item {id}")) }
            else if !["LFL", "FOQ", "POQ", "MIN"].contains(&rule.as_str()) { Some(format!("unknown lot rule {rule}")) }
            else if parse_lot(rule, parameter).is_none() { Some(format!("bad lot parameter {parameter} for {rule}")) } else { None };
        if let Some(reason) = reason { errors.push(format!("items.csv line {line}: {reason}")); continue; }
        items.insert(id.clone(), Item { id: id.clone(), lead: fields[1].parse().unwrap(), lot: parse_lot(rule, parameter).unwrap(), safety: fields[4].parse().unwrap(), on_hand: fields[5].parse().unwrap(), material: fields[6].parse().unwrap(), labor: fields[7].parse().unwrap(), description: fields[8].clone() });
    }
    Ok(items)
}
