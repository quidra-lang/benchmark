use std::collections::BTreeMap;
use std::fs;

pub struct Station { pub code: String, pub name: String, pub observations: BTreeMap<i64, Option<i64>> }
pub struct Constituent { pub name: String, pub speed: f64 }
pub struct Params {
    pub epoch: i64, pub stations: Vec<Station>, pub reference: String,
    pub flat: usize, pub window: i64, pub count: usize, pub factor: f64, pub lower: f64,
    pub rayleigh: f64, pub snr: f64, pub top: usize, pub surge: f64, pub surge_hours: usize,
    pub start: i64, pub duration: i64, pub grid: i64, pub min_range: f64, pub lag: i64,
    pub plot: String, pub plot_hours: usize, pub plot_top: i64, pub plot_bottom: i64, pub plot_step: i64,
}

fn leap(year: i64) -> bool { year%4 == 0 && (year%100 != 0 || year%400 == 0) }
fn before_year(year: i64) -> i64 { let y = year-1; 365*y+y/4-y/100+y/400 }
fn month_days(year: i64) -> [i64; 12] { [31, if leap(year) { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] }

pub fn parse_datetime(value: &str) -> i64 {
    let year: i64 = value[..4].parse().unwrap();
    let month: usize = value[5..7].parse().unwrap();
    let day: i64 = value[8..10].parse().unwrap();
    let hour: i64 = value[11..13].parse().unwrap();
    let minute: i64 = value[14..16].parse().unwrap();
    (before_year(year)+month_days(year)[..month-1].iter().sum::<i64>()+day-1)*1440+hour*60+minute
}

pub fn datetime(epoch: i64, minute: i64) -> String {
    let value = epoch+minute;
    let days = value.div_euclid(1440);
    let clock = value.rem_euclid(1440);
    let (mut lo, mut hi) = (1, 10000);
    while lo+1 < hi { let mid = (lo+hi)/2; if before_year(mid) <= days { lo = mid; } else { hi = mid; } }
    let year = lo;
    let mut day = days-before_year(year);
    let mut month = 1;
    for length in month_days(year) { if day < length { break; } day -= length; month += 1; }
    format!("{:04}-{:02}-{:02} {:02}:{:02}", year, month, day+1, clock/60, clock%60)
}

pub fn date(epoch: i64, minute: i64) -> String { datetime(epoch, minute)[..10].to_owned() }

pub fn read() -> (Params, Vec<Constituent>) {
    let mut p = Params { epoch: 0, stations: Vec::new(), reference: String::new(), flat: 0, window: 0, count: 0,
        factor: 0.0, lower: 0.0, rayleigh: 0.0, snr: 0.0, top: 0, surge: 0.0, surge_hours: 0,
        start: 0, duration: 0, grid: 0, min_range: 0.0, lag: 0, plot: String::new(), plot_hours: 0,
        plot_top: 0, plot_bottom: 0, plot_step: 0 };
    for line in fs::read_to_string("input/params.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "epoch" => p.epoch = parse_datetime(&format!("{} {}", w[1], w[2])),
            "station" => p.stations.push(Station { code: w[1].to_owned(), name: w[2..].join(" "), observations: BTreeMap::new() }),
            "reference" => p.reference = w[1].to_owned(), "flat_run" => p.flat = w[1].parse().unwrap(),
            "spike" => { p.window = w[1].parse().unwrap(); p.count = w[2].parse().unwrap(); p.factor = w[3].parse().unwrap(); p.lower = w[4].parse().unwrap(); }
            "rayleigh" => p.rayleigh = w[1].parse().unwrap(), "snr_min" => p.snr = w[1].parse().unwrap(), "top_residuals" => p.top = w[1].parse().unwrap(),
            "surge" => { p.surge = w[1].parse().unwrap(); p.surge_hours = w[2].parse().unwrap(); }
            "predict" => { p.start = (parse_datetime(&format!("{} {}", w[1], w[2]))-p.epoch)/60; p.duration = w[3].parse().unwrap(); }
            "grid_minutes" => p.grid = w[1].parse().unwrap(), "min_range" => p.min_range = w[1].parse().unwrap(), "correlation_lag" => p.lag = w[1].parse().unwrap(),
            _ => { p.plot = w[1].to_owned(); p.plot_hours = w[2].parse().unwrap(); p.plot_top = w[3].parse().unwrap(); p.plot_bottom = w[4].parse().unwrap(); p.plot_step = w[5].parse().unwrap(); }
        }
    }
    let constituents = fs::read_to_string("input/constituents.txt").unwrap().lines().skip(1).map(|line| {
        let w: Vec<_> = line.split_whitespace().collect(); Constituent { name: w[0].to_owned(), speed: w[1].parse().unwrap() }
    }).collect();
    for line in fs::read_to_string("input/observations.csv").unwrap().lines().skip(1) {
        let w: Vec<_> = line.split(',').collect();
        let time = (parse_datetime(w[1])-p.epoch)/60;
        let value = if w[2] == "NA" { None } else { Some(w[2].replace('.', "").parse().unwrap()) };
        p.stations.iter_mut().find(|s| s.code == w[0]).unwrap().observations.insert(time, value);
    }
    (p, constituents)
}
