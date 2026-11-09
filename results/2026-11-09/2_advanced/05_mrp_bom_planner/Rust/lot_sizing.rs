use crate::items::{Item, Lot};
fn multiple(quantity: i64, factor: i64) -> i64 { (quantity + factor - 1) / factor * factor }
pub fn lot_size(item: &Item, week: usize, mut projected: i64, receipts: &[i64], gross: &[i64], horizon: usize) -> i64 {
    let net = item.safety - projected;
    match item.lot {
        Lot::Lfl => net, Lot::Foq(factor) => multiple(net, factor), Lot::Min(minimum, factor) => multiple(net.max(minimum), factor),
        Lot::Poq(periods) => { let mut quantity = net; for later in week + 1..=horizon.min(week + periods - 1) { projected += receipts[later] - gross[later]; quantity = quantity.max(item.safety - projected); } quantity }
    }
}
