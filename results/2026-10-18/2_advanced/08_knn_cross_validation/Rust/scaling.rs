use crate::dataset::Rows;

pub struct Scaling {
    pub centers: Vec<f64>,
    pub scales: Vec<f64>,
}
impl Scaling {
    pub fn fit(rows: &Rows, method: &str) -> Self {
        let mut centers = Vec::new(); let mut scales = Vec::new();
        for j in 0..rows[0].values.len() {
            let (center, scale) = if method == "standard" {
                let mut sum = 0.0; for row in rows { sum += row.values[j]; }
                let center = sum / rows.len() as f64;
                let mut squares = 0.0; for row in rows { let difference = row.values[j] - center; squares += difference * difference; }
                (center, if rows.len() == 1 { 0.0 } else { (squares / (rows.len() - 1) as f64).sqrt() })
            } else {
                let mut low = rows[0].values[j]; let mut high = low;
                for row in rows { low = low.min(row.values[j]); high = high.max(row.values[j]); }
                (low, high - low)
            };
            centers.push(center); scales.push(scale);
        }
        Self { centers, scales }
    }
    pub fn transform(&self, values: &[f64], features: &[usize]) -> Vec<f64> {
        features.iter().map(|&j| if self.scales[j] > 0.0 { (values[j] - self.centers[j]) / self.scales[j] } else { 0.0 }).collect()
    }
}
