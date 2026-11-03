use std::collections::BTreeMap;
use crate::items::Item;
use crate::bom::Bom;
pub struct Cost { pub material: i64, pub labor: i64, pub total: i64 }
pub fn standard_costs(items: &BTreeMap<String, Item>, bom: &Bom, order: &[String]) -> BTreeMap<String, Cost> {
    let mut costs: BTreeMap<String, Cost> = BTreeMap::new();
    for id in order.iter().rev() {
        let item = &items[id]; let (mut material, mut labor) = (item.material, item.labor);
        for row in &bom.children[id] { let child = &costs[&row.child]; let factor = row.quantity * (100 + row.scrap); material += (factor * child.material + 50) / 100; labor += (factor * child.labor + 50) / 100; }
        costs.insert(id.clone(), Cost { material, labor, total: material + labor });
    }
    costs
}
pub fn abc_classes(values: &BTreeMap<String, i64>) -> BTreeMap<String, char> {
    let mut ranked: Vec<_> = values.iter().collect(); ranked.sort_by(|a, b| b.1.cmp(a.1).then_with(|| a.0.cmp(b.0)));
    let total: i64 = values.values().sum(); let mut before = 0; let mut classes = BTreeMap::new();
    for (id, &value) in ranked { classes.insert(id.clone(), if value == 0 { 'C' } else if 100 * before < 80 * total { 'A' } else if 100 * before < 95 * total { 'B' } else { 'C' }); before += value; }
    classes
}
