use std::collections::{BTreeMap, HashSet};
use std::io;
use crate::items::{read_rows, Item};

#[derive(Clone)]
pub struct BomRow { pub parent: String, pub child: String, pub quantity: i64, pub scrap: i64 }
pub fn need(row: &BomRow, quantity: i64) -> i64 { (quantity * row.quantity * (100 + row.scrap) + 99) / 100 }
pub struct Bom { pub children: BTreeMap<String, Vec<BomRow>>, pub parents: BTreeMap<String, Vec<BomRow>> }
impl Bom {
    pub fn manufactured(&self, id: &str) -> bool { !self.children[id].is_empty() }
    fn path(&self, id: &str, target: &str, visited: &mut HashSet<String>) -> Option<Vec<String>> {
        if id == target { return Some(vec![id.to_owned()]); }
        visited.insert(id.to_owned());
        for row in &self.children[id] {
            if visited.contains(&row.child) { continue; }
            if let Some(rest) = self.path(&row.child, target, visited) { let mut path = vec![id.to_owned()]; path.extend(rest); return Some(path); }
        }
        None
    }
    pub fn code(&self, id: &str, codes: &mut BTreeMap<String, usize>) -> usize {
        if let Some(&code) = codes.get(id) { return code; }
        let mut code = 0; for row in &self.parents[id] { code = code.max(self.code(&row.parent, codes) + 1); }
        codes.insert(id.to_owned(), code); code
    }
    pub fn cumulative(&self, id: &str, items: &BTreeMap<String, Item>, times: &mut BTreeMap<String, usize>) -> usize {
        if let Some(&time) = times.get(id) { return time; }
        let mut longest = 0; for row in &self.children[id] { longest = longest.max(self.cumulative(&row.child, items, times)); }
        let time = items[id].lead + longest; times.insert(id.to_owned(), time); time
    }
}
pub fn read_bom(items: &BTreeMap<String, Item>, errors: &mut Vec<String>) -> io::Result<Bom> {
    let empty = items.keys().map(|id| (id.clone(), Vec::new())).collect::<BTreeMap<_, _>>(); let mut bom = Bom { children: empty.clone(), parents: empty };
    for (line, fields) in read_rows("bom.csv")? {
        let row = BomRow { parent: fields[0].clone(), child: fields[1].clone(), quantity: fields[2].parse().unwrap(), scrap: fields[3].parse().unwrap() };
        let parent = &row.parent; let child = &row.child;
        let reason = if !items.contains_key(parent) { Some(format!("unknown item {parent}")) } else if !items.contains_key(child) { Some(format!("unknown item {child}")) }
            else if row.quantity < 1 { Some(format!("bad quantity {}", row.quantity)) } else if row.scrap > 50 { Some(format!("bad scrap {}", row.scrap)) }
            else if parent == child { Some(format!("cycle {parent} -> {parent}")) } else if bom.children[parent].iter().any(|other| other.child == *child) { Some(format!("duplicate {parent} -> {child}")) }
            else { bom.path(child, parent, &mut HashSet::new()).map(|path| format!("cycle {parent} -> {}", path.join(" -> "))) };
        if let Some(reason) = reason { errors.push(format!("bom.csv line {line}: {reason}")); continue; }
        let children = bom.children.get_mut(parent).unwrap(); children.push(row.clone()); children.sort_by(|a, b| a.child.cmp(&b.child));
        let parents = bom.parents.get_mut(child).unwrap(); parents.push(row); parents.sort_by(|a, b| a.parent.cmp(&b.parent));
    }
    Ok(bom)
}
