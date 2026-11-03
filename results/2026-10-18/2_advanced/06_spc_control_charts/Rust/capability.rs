use crate::dataset::{Settings, CONSTANTS};
use crate::variable_charts::{real_sum, Subgroup};

pub const METRICS: [&str; 13] = ["mean","sigma_within","sigma_sbar","sigma_overall","cp","cpu","cpl","cpk","pp","ppu","ppl","ppk","cpm"];
pub struct HistogramBin { pub lower: i64, pub upper: i64, pub frequency: usize, pub length: usize, pub marks: Vec<&'static str> }
pub struct Capability {
    pub count: usize,
    pub metrics: [f64; 13],
    pub intervals: [[f64; 2]; 2],
    pub below: usize,
    pub above: usize,
    pub ppm: f64,
    pub verdict: &'static str,
    pub bins: Vec<HistogramBin>,
}

fn indices(mean: f64, sigma: f64, s: &Settings) -> [f64; 4] {
    let potential = (s.usl - s.lsl) as f64 / (6.0 * sigma);
    let upper = (s.usl as f64 - mean) / (3.0 * sigma);
    let lower = (mean - s.lsl as f64) / (3.0 * sigma);
    [potential, upper, lower, upper.min(lower)]
}

fn confidence_interval(index: f64, count: usize, z: f64) -> [f64; 2] {
    let delta = z * (1.0 / (9 * count) as f64 + index * index / (2 * (count - 1)) as f64).sqrt();
    [index - delta, index + delta]
}

impl Capability {
    pub fn new(groups: &[&Subgroup], settings: &Settings) -> Self {
        let values: Vec<i64> = groups.iter().flat_map(|g| g.values.iter().copied()).collect();
        let count = values.len();
        let mean = values.iter().sum::<i64>() as f64 / count as f64;
        let rbar = groups.iter().map(|g| g.range).sum::<i64>() as f64 / groups.len() as f64;
        let sbar = real_sum(groups.iter().map(|g| g.sd)) / groups.len() as f64;
        let constants = CONSTANTS[settings.size - 2];
        let within = rbar / constants[6];
        let sigma_sbar = sbar / constants[7];
        let squares = real_sum(values.iter().map(|&value| { let difference = value as f64 - mean; difference * difference }));
        let overall = (squares / (count - 1) as f64).sqrt();
        let [cp,cpu,cpl,cpk] = indices(mean, within, settings);
        let [pp,ppu,ppl,ppk] = indices(mean, overall, settings);
        let offset = mean - settings.target as f64;
        let cpm = (settings.usl - settings.lsl) as f64 / (6.0 * (overall * overall + offset * offset).sqrt());
        let below = values.iter().filter(|&&v| v < settings.lsl).count();
        let above = values.iter().filter(|&&v| v > settings.usl).count();
        Self {
            count, metrics: [mean,within,sigma_sbar,overall,cp,cpu,cpl,cpk,pp,ppu,ppl,ppk,cpm],
            intervals: [confidence_interval(cpk,count,settings.ci_z),confidence_interval(ppk,count,settings.ci_z)],
            below, above, ppm: (1_000_000 * (below + above)) as f64 / count as f64,
            verdict: if cpk >= 1.33 { "capable" } else if cpk >= 1.0 { "marginal" } else { "incapable" },
            bins: histogram(&values, settings),
        }
    }
}

fn histogram(values: &[i64], settings: &Settings) -> Vec<HistogramBin> {
    let width = settings.bin;
    let low = (*values.iter().min().unwrap()).min(settings.lsl) / width * width;
    let high = (*values.iter().max().unwrap()).max(settings.usl) / width * width + width;
    let mut frequencies = vec![0_usize; ((high - low) / width) as usize];
    for &value in values { frequencies[((value - low) / width) as usize] += 1; }
    let top = *frequencies.iter().max().unwrap();
    frequencies.into_iter().enumerate().map(|(index, frequency)| {
        let lower = low + index as i64 * width;
        let upper = lower + width - 1;
        let marks = [("lsl",settings.lsl),("target",settings.target),("usl",settings.usl)].into_iter().filter(|&(_, value)| lower <= value && value <= upper).map(|(name, _)| name).collect();
        HistogramBin { lower, upper, frequency, length: (50 * frequency + top - 1) / top, marks }
    }).collect()
}
