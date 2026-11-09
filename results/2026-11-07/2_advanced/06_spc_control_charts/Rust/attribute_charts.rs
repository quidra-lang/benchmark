use crate::dataset::Lot;

pub const CHARTS: [&str; 4] = ["p","np","c","u"];

pub struct CenterLine { pub value: f64, pub fraction: f64 }
pub struct LotPoint { pub value: f64, pub lcl: f64, pub ucl: f64, pub z: f64, pub status: &'static str }

pub fn center_line(chart: usize, lots: &[&Lot]) -> CenterLine {
    let defectives: i64 = lots.iter().map(|l| l.defectives).sum();
    let defects: i64 = lots.iter().map(|l| l.defects).sum();
    let inspected: i64 = lots.iter().map(|l| l.inspected).sum();
    let fraction = defectives as f64 / inspected as f64;
    let value = match chart { 0 => fraction, 1 => defectives as f64 / lots.len() as f64, 2 => defects as f64 / lots.len() as f64, _ => defects as f64 / inspected as f64 };
    CenterLine { value, fraction }
}

pub fn lot_point(chart: usize, lot: &Lot, center: &CenterLine) -> LotPoint {
    let cl = center.value;
    let (value, sigma) = match chart {
        0 => (lot.defectives as f64 / lot.inspected as f64, (cl * (1.0 - cl) / lot.inspected as f64).sqrt()),
        1 => (lot.defectives as f64, (cl * (1.0 - center.fraction)).sqrt()),
        2 => (lot.defects as f64, cl.sqrt()),
        _ => (lot.defects as f64 / lot.inspected as f64, (cl / lot.inspected as f64).sqrt()),
    };
    let lcl = (cl - 3.0 * sigma).max(0.0);
    let ucl = cl + 3.0 * sigma;
    LotPoint { value, lcl, ucl, z: (value - cl) / sigma, status: if value > ucl { "high" } else if value < lcl { "low" } else { "ok" } }
}
