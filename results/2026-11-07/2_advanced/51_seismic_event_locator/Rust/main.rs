mod waveform_io;
mod picker;
mod associator;
mod locator;
mod magnitude;

use waveform_io::{Params, Station};
use picker::Pick;
use locator::{Observation, Solution, Run, Ellipse};
use std::{collections::{BTreeSet, VecDeque}, fs, io};

fn fixed(value: f64, digits: u32) -> String {
    let units = magnitude::rounded(value, digits);
    let scale = 10i64.pow(digits);
    format!("{}{}.{:0width$}", if units < 0 { "-" } else { "" }, units.abs() / scale, units.abs() % scale, width = digits as usize)
}

fn optional(value: Option<f64>, digits: u32) -> String {
    value.map_or("-".into(), |x| fixed(x, digits))
}

fn time(sample: i64) -> String {
    format!("{}.{:02}", sample / 100, sample % 100)
}

fn class_text(t: i64) -> String {
    format!("{}{}.{}", if t < 0 { "-" } else { "" }, t.abs() / 10, t.abs() % 10)
}

fn coordinates(label: &str, solution: Solution) -> String {
    format!("{} x={} y={} z={} t0={} rms={}", label, fixed(solution.x, 1), fixed(solution.y, 1), fixed(solution.z, 1), fixed(solution.time, 3), fixed(solution.rms, 4))
}

fn observations(indices: &[usize], picks: &[Pick], corrections: &[f64]) -> Vec<Observation> {
    indices.iter().map(|&i| Observation { station: picks[i].station, time: picks[i].sample as f64 / 100.0 - corrections[picks[i].station] }).collect()
}

fn record_run(pass: usize, run: &Run, indices: &[usize], picks: &[Pick], stations: &[Station], velocity: f64, lines: &mut Vec<String>) {
    lines.push(format!("PASS {} stations={}", pass, indices.iter().map(|&i| stations[picks[i].station].code.as_str()).collect::<Vec<_>>().join(",")));
    lines.push(coordinates("GRID", run.grid));
    lines.push(format!("PROFILE {}", run.profile.iter().map(|&x| fixed(x, 4)).collect::<Vec<_>>().join(" ")));
    for (j, &solution) in run.iterations.iter().enumerate() { lines.push(coordinates(&format!("ITER {}", j + 1), solution)); }
    let solution = run.solution();
    for &i in indices {
        let p = &picks[i];
        let d = locator::distance(solution, &stations[p.station]);
        let residual = p.sample as f64 / 100.0 - solution.time - d / velocity;
        lines.push(format!("RES {} dist={} tt={} obs={} res={}", stations[p.station].code, fixed(d, 1), fixed(d / velocity, 4), time(p.sample), fixed(residual, 4)));
    }
}

#[derive(Clone)]
struct State {
    kind: &'static str,
    event: usize,
    residual: Option<f64>,
}

struct Event {
    used: Vec<usize>,
    first: Solution,
    first_residuals: Vec<f64>,
    solution: Solution,
    residuals: Vec<f64>,
    ellipse: Option<Ellipse>,
    gap: f64,
    minimum_distance: f64,
    quality: &'static str,
    local: Vec<Option<f64>>,
    duration: Vec<f64>,
    ml: Option<f64>,
    md: f64,
    corrected: Option<f64>,
    cluster: usize,
}

fn frame(grid: &[Vec<char>]) -> Vec<String> {
    let border = format!("+{}+", "-".repeat(grid[0].len()));
    let mut result = vec![border.clone()];
    result.extend(grid.iter().map(|r| format!("|{}|", r.iter().collect::<String>())));
    result.push(border);
    result
}

fn symbol(event: &Event) -> char {
    event.ml.map_or('?', |m| {
        let h = magnitude::rounded(m, 2);
        if h < 100 { '.' } else if h < 200 { 'o' } else if h < 300 { 'O' } else { '@' }
    })
}

fn place(grid: &mut [Vec<char>], position: Option<(usize, usize)>, mark: char) {
    if let Some((c, r)) = position {
        let priority = |c| match c { '^' => 6, '@' => 5, 'O' => 4, 'o' => 3, '.' => 2, '?' => 1, _ => 0 };
        if priority(mark) > priority(grid[r][c]) { grid[r][c] = mark; }
    }
}

fn map_position(x: i64, y: i64, params: &Params) -> Option<(usize, usize)> {
    let [xmin, xmax, ymin, ymax] = params.area;
    let (w, h) = params.map_size;
    if x < 10 * xmin || x >= 10 * xmax || y < 10 * ymin || y >= 10 * ymax {
        None
    } else {
        let column = ((x - 10 * xmin) * w as i64 / (10 * (xmax - xmin))) as usize;
        let row = h - 1 - ((y - 10 * ymin) * h as i64 / (10 * (ymax - ymin))) as usize;
        Some((column, row))
    }
}

fn section_position(coordinate: i64, z: i64, minimum: i64, maximum: i64, params: &Params) -> Option<(usize, usize)> {
    if coordinate < 10 * minimum || coordinate >= 10 * maximum || z >= 10 * params.section.0 {
        None
    } else {
        let column = ((coordinate - 10 * minimum) * params.map_size.0 as i64 / (10 * (maximum - minimum))) as usize;
        let row = (z * params.section.1 as i64 / (10 * params.section.0)) as usize;
        Some((column, row))
    }
}

fn position_text(position: Option<(usize, usize)>) -> String {
    position.map_or("outside".into(), |(c, r)| format!("{},{}", c, r))
}

fn charts(events: &[Event], stations: &[Station], params: &Params) -> Vec<String> {
    let (w, h) = params.map_size;
    let mut map = vec![vec![' '; w]; h];
    let mut ew = vec![vec![' '; w]; params.section.1];
    let mut ns = ew.clone();
    let [xmin, xmax, ymin, ymax] = params.area;
    let mut positions = Vec::new();
    for event in events {
        let x = magnitude::rounded(event.solution.x, 1);
        let y = magnitude::rounded(event.solution.y, 1);
        let z = magnitude::rounded(event.solution.z, 1);
        let point = map_position(x, y, params);
        let east = section_position(x, z, xmin, xmax, params);
        let north = section_position(y, z, ymin, ymax, params);
        let mark = symbol(event);
        place(&mut map, point, mark);
        place(&mut ew, east, mark);
        place(&mut ns, north, mark);
        positions.push((point, east, north));
    }
    let mut station_positions = Vec::new();
    for station in stations {
        let position = map_position(10 * station.x, 10 * station.y, params);
        place(&mut map, position, '^');
        station_positions.push(position);
    }
    let mut lines = vec![format!("MAP x={}..{} y={}..{}", xmin, xmax, ymin, ymax)];
    lines.extend(frame(&map));
    lines.push(format!("SECTION EW x={}..{} z=0..{}", xmin, xmax, params.section.0));
    lines.extend(frame(&ew));
    lines.push(format!("SECTION NS y={}..{} z=0..{}", ymin, ymax, params.section.0));
    lines.extend(frame(&ns));
    lines.push("LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML".into());
    for (j, station) in stations.iter().enumerate() { lines.push(format!("STATION {} map={}", station.code, position_text(station_positions[j]))); }
    for (j, event) in events.iter().enumerate() {
        let (map, east, north) = positions[j];
        lines.push(format!("EVENT {} {} map={} ew={} ns={}", j + 1, symbol(event), position_text(map), position_text(east), position_text(north)));
    }
    lines
}

fn main() -> io::Result<()> {
    let data = waveform_io::read()?;
    let stations = &data.stations;
    let params = &data.params;
    let station_count = stations.len();
    let mut picks = Vec::new();
    let mut waveform_stats = Vec::new();
    for (j, wave) in data.waves.iter().enumerate() {
        let (found, stats) = picker::detect(j, wave, params);
        picks.extend(found);
        waveform_stats.push(stats);
    }
    picks.sort_by_key(|p| (p.sample, p.station));
    let candidates = associator::associate(&picks, params.window, params.minimum);
    let mut states = vec![State { kind: "unassociated", event: 0, residual: None }; picks.len()];
    let mut events = Vec::new();
    let mut locations = Vec::new();
    let mut rejected = 0;
    let zero = vec![0.0; station_count];
    for (candidate, original) in candidates.iter().enumerate() {
        locations.push(format!("CANDIDATE {} picks={} first={}", candidate + 1, original.len(), time(picks[original[0]].sample)));
        let mut ordered = original.clone();
        ordered.sort_by_key(|&i| picks[i].station);
        let obs = observations(&ordered, &picks, &zero);
        let pass1 = locator::run(&obs, stations, params);
        record_run(1, &pass1, &ordered, &picks, stations, params.velocity, &mut locations);
        let residuals = locator::residuals(pass1.solution(), &obs, stations, params.velocity);
        let dropped: Vec<usize> = (0..ordered.len()).filter(|&j| residuals[j].abs() > params.residual).collect();
        let retained: Vec<usize> = (0..ordered.len()).filter(|j| !dropped.contains(j)).map(|j| ordered[j]).collect();
        for &j in &dropped { locations.push(format!("DROP {} res={}", stations[picks[ordered[j]].station].code, fixed(residuals[j], 4))); }
        if !dropped.is_empty() && retained.len() < params.minimum {
            locations.push(format!("RESULT REJECTED stations={}", retained.len()));
            rejected += 1;
            for &i in &ordered { states[i].kind = "rejected"; }
            continue;
        }
        let solution = if dropped.is_empty() { pass1.solution() } else {
            let obs = observations(&retained, &picks, &zero);
            let pass2 = locator::run(&obs, stations, params);
            record_run(2, &pass2, &retained, &picks, stations, params.velocity, &mut locations);
            pass2.solution()
        };
        let obs = observations(&retained, &picks, &zero);
        let first_residuals = locator::residuals(solution, &obs, stations, params.velocity);
        let number = events.len() + 1;
        for &i in &retained { states[i] = State { kind: "used", event: number, residual: None }; }
        for &j in &dropped { states[ordered[j]] = State { kind: "dropped", event: number, residual: None }; }
        events.push(Event { used: retained, first: solution, first_residuals, solution, residuals: Vec::new(), ellipse: None,
            gap: 0.0, minimum_distance: 0.0, quality: "C", local: Vec::new(), duration: Vec::new(), ml: None, md: 0.0, corrected: None, cluster: 0 });
        locations.push(format!("RESULT EVENT {}", number));
    }
    let mut correction = vec![0.0; station_count];
    let mut counts = vec![0usize; station_count];
    for event in &events {
        for (j, &i) in event.used.iter().enumerate() { correction[picks[i].station] += event.first_residuals[j]; counts[picks[i].station] += 1; }
    }
    locations.push("CORRECTIONS".into());
    for j in 0..station_count {
        if counts[j] > 0 { correction[j] /= counts[j] as f64; }
        locations.push(format!("{} n={} correction={}", stations[j].code, counts[j], fixed(correction[j], 4)));
    }
    for (number, event) in events.iter_mut().enumerate() {
        let obs = observations(&event.used, &picks, &correction);
        let mut initial = event.first;
        initial.rms = locator::rms(initial, &obs, stations, params.velocity);
        locations.extend([format!("EVENT {}", number + 1), coordinates("START", initial)]);
        let iterations = locator::geiger(initial, &obs, stations, params.velocity);
        for (j, &solution) in iterations.iter().enumerate() { locations.push(coordinates(&format!("ITER {}", j + 1), solution)); }
        event.solution = *iterations.last().unwrap();
        event.residuals = locator::residuals(event.solution, &obs, stations, params.velocity);
        let s = event.solution;
        for (j, &i) in event.used.iter().enumerate() {
            let pick = &picks[i];
            let station = &stations[pick.station];
            let d = locator::distance(s, station);
            states[i].residual = Some(event.residuals[j]);
            locations.push(format!("RES {} dist={} tt={} obs={} corr={} res={}", station.code, fixed(d, 1), fixed(d / params.velocity, 4), time(pick.sample), fixed(correction[pick.station], 4), fixed(event.residuals[j], 4)));
        }
        let ellipse = locator::ellipse(s, &obs, stations, params.velocity);
        locations.push(format!("ELLIPSE smaj={} smin={} az={} erz={} ert={}", fixed(ellipse.major, 1), fixed(ellipse.minor, 1), fixed(ellipse.azimuth, 1), fixed(ellipse.depth, 1), fixed(ellipse.time, 4)));
        let dx = s.x - event.first.x;
        let dy = s.y - event.first.y;
        locations.push(format!("SHIFT dh={} dz={}", fixed((dx * dx + dy * dy).sqrt(), 1), fixed(s.z - event.first.z, 1)));
        let mut azimuths: Vec<f64> = event.used.iter().map(|&i| {
            let station = &stations[picks[i].station];
            let mut angle = (station.x as f64 - s.x).atan2(station.y as f64 - s.y) * 180.0 / 3.141592653589793;
            if angle < 0.0 { angle += 360.0; }
            angle
        }).collect();
        azimuths.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let mut gap = azimuths[0] + 360.0 - azimuths[azimuths.len() - 1];
        for pair in azimuths.windows(2) { gap = gap.max(pair[1] - pair[0]); }
        event.gap = gap;
        event.minimum_distance = event.used.iter().map(|&i| {
            let station = &stations[picks[i].station];
            let dx = station.x as f64 - s.x;
            let dy = station.y as f64 - s.y;
            (dx * dx + dy * dy).sqrt()
        }).fold(f64::INFINITY, f64::min);
        let meets = |limits: [f64; 3]| gap <= limits[0] && s.rms <= limits[1] && ellipse.major <= limits[2];
        event.quality = if meets(params.quality[0]) { "A" } else if meets(params.quality[1]) { "B" } else { "C" };
        locations.push(format!("GAP {} DMIN {} QUALITY {}", fixed(gap, 1), fixed(event.minimum_distance, 1), event.quality));
        let mut maximum = -1.0;
        let mut worst = 0;
        for j in 0..obs.len() {
            let retained: Vec<Observation> = obs.iter().enumerate().filter(|(k, _)| *k != j).map(|(_, &o)| o).collect();
            let solution = *locator::geiger(s, &retained, stations, params.velocity).last().unwrap();
            let (dx, dy, dz) = (solution.x - s.x, solution.y - s.y, solution.z - s.z);
            let shift = (dx * dx + dy * dy).sqrt();
            if shift > maximum { maximum = shift; worst = obs[j].station; }
            locations.push(format!("JACK {} dx={} dy={} dz={} shift={}", stations[obs[j].station].code, fixed(dx, 1), fixed(dy, 1), fixed(dz, 1), fixed(shift, 1)));
        }
        locations.push(format!("JACKKNIFE max={} station={}", fixed(maximum, 1), stations[worst].code));
        event.ellipse = Some(ellipse);
        for &i in &event.used {
            let pick = &picks[i];
            let r = locator::distance(s, &stations[pick.station]) / 1000.0;
            event.local.push(if pick.clipped { None } else { Some(magnitude::local(pick.amplitude, r, params.local)) });
            event.duration.push(magnitude::duration(pick.duration, r, params.duration_mag));
        }
        let ml: Vec<f64> = event.local.iter().filter_map(|&m| m).collect();
        event.ml = if ml.is_empty() { None } else { Some(magnitude::median(&ml)) };
        event.md = magnitude::median(&event.duration);
    }
    let mut magnitude_correction = vec![0.0; station_count];
    let mut magnitude_counts = vec![0usize; station_count];
    let mut magnitude_lines = Vec::new();
    for (number, event) in events.iter().enumerate() {
        magnitude_lines.push(format!("EVENT {} ML={} n={} MD={}", number + 1, optional(event.ml, 2), event.local.iter().filter(|m| m.is_some()).count(), fixed(event.md, 2)));
        for (j, &i) in event.used.iter().enumerate() {
            let pick = &picks[i];
            let station = &stations[pick.station];
            let r = locator::distance(event.solution, station) / 1000.0;
            let prefix = format!("{} r={} amp={}", station.code, fixed(r, 3), pick.amplitude);
            if let Some(ml) = event.local[j] {
                let residual = ml - event.ml.unwrap();
                magnitude_correction[pick.station] += residual;
                magnitude_counts[pick.station] += 1;
                magnitude_lines.push(format!("{} ml={} res={} dur={} md={}", prefix, fixed(ml, 2), fixed(residual, 2), pick.duration, fixed(event.duration[j], 2)));
            } else { magnitude_lines.push(format!("{} clipped dur={} md={}", prefix, pick.duration, fixed(event.duration[j], 2))); }
        }
    }
    for j in 0..station_count { if magnitude_counts[j] > 0 { magnitude_correction[j] /= magnitude_counts[j] as f64; } }
    magnitude_lines.push("CORRECTED".into());
    for (number, event) in events.iter_mut().enumerate() {
        let values: Vec<f64> = event.local.iter().enumerate().filter_map(|(j, &m)| m.map(|m| m - magnitude_correction[picks[event.used[j]].station])).collect();
        event.corrected = if values.is_empty() { None } else { Some(magnitude::median(&values)) };
        magnitude_lines.push(format!("EVENT {} MLC={}", number + 1, optional(event.corrected, 2)));
    }
    let mut fit = Vec::new();
    for event in &events {
        for &i in &event.used { fit.push((locator::distance(event.solution, &stations[picks[i].station]) / 1000.0, picks[i].sample as f64 / 100.0 - event.solution.time)); }
    }
    let count = fit.len() as f64;
    let sd = fit.iter().map(|p| p.0).sum::<f64>();
    let st = fit.iter().map(|p| p.1).sum::<f64>();
    let sdd = fit.iter().map(|p| p.0 * p.0).sum::<f64>();
    let sdt = fit.iter().map(|p| p.0 * p.1).sum::<f64>();
    let slope = (count * sdt - sd * st) / (count * sdd - sd * sd);
    let intercept = (st - slope * sd) / count;
    let fit_rms = (fit.iter().map(|&(d, t)| (t - intercept - slope * d) * (t - intercept - slope * d)).sum::<f64>() / count).sqrt();
    locations.push(format!("FIT n={} velocity={} intercept={} rms={}", fit.len(), fixed(1000.0 / slope, 1), fixed(intercept, 4), fixed(fit_rms, 4)));
    let mut clusters = Vec::new();
    for i in 0..events.len() {
        if events[i].cluster != 0 { continue; }
        let number = clusters.len() + 1;
        let mut queue = VecDeque::from([i]);
        let mut members = Vec::new();
        events[i].cluster = number;
        while let Some(j) = queue.pop_front() {
            members.push(j);
            for k in 0..events.len() {
                if events[k].cluster != 0 { continue; }
                let a = events[j].solution;
                let b = events[k].solution;
                let dx = a.x - b.x;
                let dy = a.y - b.y;
                let dz = a.z - b.z;
                if (a.time - b.time).abs() <= params.cluster.1 && (dx * dx + dy * dy + dz * dz).sqrt() <= params.cluster.0 { events[k].cluster = number; queue.push_back(k); }
            }
        }
        members.sort();
        clusters.push(members);
    }
    for (number, members) in clusters.iter().enumerate() {
        if members.len() < 2 { continue; }
        let count = members.len() as f64;
        let x = members.iter().map(|&j| events[j].solution.x).sum::<f64>() / count;
        let y = members.iter().map(|&j| events[j].solution.y).sum::<f64>() / count;
        let z = members.iter().map(|&j| events[j].solution.z).sum::<f64>() / count;
        let minimum = members.iter().map(|&j| events[j].solution.time).fold(f64::INFINITY, f64::min);
        let maximum = members.iter().map(|&j| events[j].solution.time).fold(f64::NEG_INFINITY, f64::max);
        locations.push(format!("CLUSTER {} events={} x={} y={} z={} span={}", number + 1, members.iter().map(|j| (j + 1).to_string()).collect::<Vec<_>>().join(","), fixed(x, 1), fixed(y, 1), fixed(z, 1), fixed(maximum - minimum, 3)));
    }
    let mut station_sets: Vec<BTreeSet<usize>> = events.iter().map(|e| e.used.iter().map(|&i| picks[i].station).collect()).collect();
    locations.push("ADDED".into());
    for (i, pick) in picks.iter().enumerate() {
        if states[i].kind != "unassociated" { continue; }
        let mut best: Option<(usize, f64)> = None;
        for (j, event) in events.iter().enumerate() {
            if station_sets[j].contains(&pick.station) { continue; }
            let rho = pick.sample as f64 / 100.0 - event.solution.time - locator::distance(event.solution, &stations[pick.station]) / params.velocity - correction[pick.station];
            if rho.abs() <= params.residual && best.map_or(true, |(_, old)| rho.abs() < old.abs()) { best = Some((j, rho)); }
        }
        if let Some((j, rho)) = best {
            states[i] = State { kind: "added", event: j + 1, residual: Some(rho) };
            station_sets[j].insert(pick.station);
            locations.push(format!("{} sample={} event={} res={}", stations[pick.station].code, pick.sample, j + 1, fixed(rho, 4)));
        }
    }
    locations.push(format!("SUMMARY picks={} candidates={} events={} rejected={} unassociated={}", picks.len(), candidates.len(), events.len(), rejected, states.iter().filter(|s| s.kind == "unassociated").count()));
    let depths: Vec<f64> = events.iter().map(|e| e.solution.z).collect();
    locations.push(format!("DEPTH min={} median={} max={}", fixed(depths.iter().copied().fold(f64::INFINITY, f64::min), 1), fixed(magnitude::median(&depths), 1), fixed(depths.iter().copied().fold(f64::NEG_INFINITY, f64::max), 1)));
    locations.push(format!("QUALITY A={} B={} C={} mean_rms={}", events.iter().filter(|e| e.quality == "A").count(), events.iter().filter(|e| e.quality == "B").count(),
        events.iter().filter(|e| e.quality == "C").count(), fixed(events.iter().map(|e| e.solution.rms).sum::<f64>() / events.len() as f64, 4)));
    let ml: Vec<f64> = events.iter().filter_map(|e| e.ml).collect();
    let frequency = magnitude::frequency(&ml);
    magnitude_lines.push("FMD".into());
    for t in *frequency.histogram.keys().next().unwrap()..=*frequency.histogram.keys().last().unwrap() {
        let count = frequency.histogram.get(&t).copied().unwrap_or(0);
        let cumulative: usize = frequency.histogram.range(t..).map(|(_, n)| n).sum();
        magnitude_lines.push(format!("M={} N={} CUM={}", class_text(t), count, cumulative));
    }
    magnitude_lines.extend([format!("MC {}", class_text(frequency.completeness)), format!("BVALUE {} SIGMA {} N {}", fixed(frequency.b, 3), fixed(frequency.sigma, 3), frequency.count), format!("AVALUE {}", fixed(frequency.a, 3))]);
    let pairs: Vec<(f64, f64)> = events.iter().filter_map(|e| e.ml.map(|ml| (e.md, ml))).collect();
    let count = pairs.len() as f64;
    let xbar = pairs.iter().map(|p| p.0).sum::<f64>() / count;
    let ybar = pairs.iter().map(|p| p.1).sum::<f64>() / count;
    let sxx = pairs.iter().map(|p| (p.0 - xbar) * (p.0 - xbar)).sum::<f64>();
    let sxy = pairs.iter().map(|p| (p.0 - xbar) * (p.1 - ybar)).sum::<f64>();
    let syy = pairs.iter().map(|p| (p.1 - ybar) * (p.1 - ybar)).sum::<f64>();
    let slope = sxy / sxx;
    magnitude_lines.push(format!("MLMD n={} slope={} intercept={} r={} mean_diff={}", pairs.len(), fixed(slope, 3), fixed(ybar - slope * xbar, 3), fixed(sxy / (sxx * syy).sqrt(), 3), fixed(ybar - xbar, 3)));
    let (td, wt, mlo, mhi, ht) = params.timeline;
    let mut timeline = vec![vec![' '; wt]; ht];
    for event in &events {
        if let Some(ml) = event.ml {
            let h = magnitude::rounded(ml, 2);
            let t = magnitude::rounded(event.solution.time, 3);
            if t < 0 || t >= 1000 * td || h < 100 * mlo { continue; }
            let column = (t * wt as i64 / (1000 * td)) as usize;
            let height = (((h - 100 * mlo) * ht as i64 / (100 * (mhi - mlo))) as usize).min(ht - 1);
            for level in 0..=height {
                let row = ht - 1 - level;
                if level == height { timeline[row][column] = 'o'; }
                else if timeline[row][column] == ' ' { timeline[row][column] = '|'; }
            }
        }
    }
    magnitude_lines.push(format!("TIMELINE t=0..{} ML={}..{}", td, mlo, mhi));
    magnitude_lines.extend(frame(&timeline));
    let mut station_lines = Vec::new();
    for (j, station) in stations.iter().enumerate() {
        let stats = &waveform_stats[j];
        station_lines.push(format!("STATION {} x={} y={} elevation={}", station.code, station.x, station.y, station.elevation));
        station_lines.push(format!("SAMPLES start={} count={} mean={} noise={} peak={} clipped={}", data.waves[j].start, data.waves[j].samples.len(), stats.mean, fixed(stats.noise, 1), stats.peak, stats.clipped));
        station_lines.push(format!("TRIGGERS total={} short={} picks={}", stats.triggers, stats.short, stats.picks));
        let count = |kind| picks.iter().zip(&states).filter(|(p, s)| p.station == j && s.kind == kind).count();
        station_lines.push(format!("PICKS used={} dropped={} added={} rejected={} unassociated={}", count("used"), count("dropped"), count("added"), count("rejected"), count("unassociated")));
        let mut before = Vec::new();
        let mut after = Vec::new();
        for event in &events {
            for (k, &i) in event.used.iter().enumerate() {
                if picks[i].station == j { before.push(event.first_residuals[k]); after.push(event.residuals[k]); }
            }
        }
        let rms = |values: &[f64]| if values.is_empty() { None } else { Some((values.iter().map(|r| r * r).sum::<f64>() / values.len() as f64).sqrt()) };
        station_lines.push(format!("RESIDUALS n={} rms={} correction={} after={}", before.len(), optional(rms(&before), 4), fixed(correction[j], 4), optional(rms(&after), 4)));
        station_lines.push(format!("MAGNITUDES n={} correction={}", magnitude_counts[j], fixed(magnitude_correction[j], 2)));
    }
    let mut pick_lines = vec!["station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual".into()];
    for (i, p) in picks.iter().enumerate() {
        pick_lines.push(format!("{},{},{},{},{},{},{},{},{},{}", stations[p.station].code, p.sample, time(p.sample), p.duration, fixed(p.ratio, 2), p.amplitude,
            if p.clipped { "yes" } else { "no" }, states[i].event, states[i].kind, optional(states[i].residual, 4)));
    }
    let mut catalog = vec!["event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster".into()];
    for (j, event) in events.iter().enumerate() {
        let s = event.solution;
        let e = event.ellipse.as_ref().unwrap();
        catalog.push(format!("{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}", j + 1, fixed(s.time, 3), fixed(s.x, 1), fixed(s.y, 1), fixed(s.z, 1), fixed(s.rms, 4), event.used.len(),
            fixed(event.gap, 1), fixed(event.minimum_distance, 1), fixed(e.major, 1), fixed(e.minor, 1), fixed(e.azimuth, 1), fixed(e.depth, 1), optional(event.ml, 2), fixed(event.md, 2), event.quality, event.cluster));
    }
    let map = charts(&events, stations, params);
    fs::create_dir_all("output")?;
    for (name, lines) in [("picks.csv", pick_lines), ("locations.txt", locations), ("catalog.csv", catalog),
        ("magnitudes.txt", magnitude_lines), ("stations.txt", station_lines), ("map.txt", map)] {
        fs::write(format!("output/{}", name), lines.join("\n") + "\n")?;
    }
    Ok(())
}
