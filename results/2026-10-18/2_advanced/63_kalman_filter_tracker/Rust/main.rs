mod matrix;
mod kalman;
mod association;
mod imm;
mod evaluation;

use std::collections::BTreeMap;
use std::fs;
use matrix::Matrix;
use evaluation::{distance, real};

struct Scan { time: f64, measurements: Vec<[f64; 2]> }
struct Target { number: usize, positions: BTreeMap<usize, [f64; 2]> }
struct Params {
    ca: bool, kalman: kalman::Config, gate: f64, confirm: usize, window: usize, delete: usize,
    abg: [f64; 3], imm: imm::Config, matching: f64, cutoff: f64, bound: f64, edges: Vec<f64>,
    x: [f64; 2], y: [f64; 2], width: usize, height: usize,
}

fn read() -> (Vec<Scan>, Vec<Target>, Params) {
    let mut scans = Vec::<Scan>::new();
    for line in fs::read_to_string("input/measurements.csv").unwrap().lines().skip(1) {
        let w: Vec<_> = line.split(',').collect();
        let k = w[0].parse::<usize>().unwrap()-1;
        if scans.len() <= k { scans.push(Scan { time: w[1].parse().unwrap(), measurements: Vec::new() }); }
        scans[k].measurements.push([w[2].parse().unwrap(), w[3].parse().unwrap()]);
    }
    let mut targets = Vec::<Target>::new();
    for line in fs::read_to_string("input/truth.csv").unwrap().lines().skip(1) {
        let w: Vec<_> = line.split(',').collect();
        let number = w[0].parse().unwrap();
        if targets.last().map_or(true, |t| t.number != number) { targets.push(Target { number, positions: BTreeMap::new() }); }
        targets.last_mut().unwrap().positions.insert(w[1].parse::<usize>().unwrap()-1, [w[2].parse().unwrap(), w[3].parse().unwrap()]);
    }
    let mut p = Params { ca: false, kalman: kalman::Config { sigma: 0.0, velocity: 0.0, acceleration: 0.0, q_cv: 0.0, q_ca: 0.0 },
        gate: 0.0, confirm: 0, window: 0, delete: 0, abg: [0.0; 3],
        imm: imm::Config { noise: [0.0; 2], transition: [[0.0; 2]; 2], initial: [0.0; 2] },
        matching: 0.0, cutoff: 0.0, bound: 0.0, edges: Vec::new(), x: [0.0; 2], y: [0.0; 2], width: 0, height: 0 };
    for line in fs::read_to_string("input/params.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        let v = || w[1].parse::<f64>().unwrap();
        match w[0] {
            "MODEL" => p.ca = w[1] == "CA", "Q_CV" => p.kalman.q_cv = v(), "Q_CA" => p.kalman.q_ca = v(),
            "SIGMA" => p.kalman.sigma = v(), "INIT_VELOCITY_VARIANCE" => p.kalman.velocity = v(),
            "INIT_ACCELERATION_VARIANCE" => p.kalman.acceleration = v(), "GATE" => p.gate = v(),
            "CONFIRM" => { p.confirm = w[1].parse().unwrap(); p.window = w[2].parse().unwrap(); }
            "DELETE" => p.delete = w[1].parse().unwrap(),
            "ABG" => { for i in 0..3 { p.abg[i] = w[i+1].parse().unwrap(); } }
            "IMM_Q" => p.imm.noise = [v(), w[2].parse().unwrap()],
            "IMM_TRANSITION" => { for i in 0..2 { for j in 0..2 { p.imm.transition[i][j] = w[1+2*i+j].parse().unwrap(); } } }
            "IMM_INITIAL" => p.imm.initial = [v(), w[2].parse().unwrap()],
            "MATCH_DISTANCE" => p.matching = v(), "OSPA_CUTOFF" => p.cutoff = v(), "CONSISTENCY_BOUND" => p.bound = v(),
            "NIS_EDGES" => p.edges = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            "PLOT_X" => p.x = [v(), w[2].parse().unwrap()], "PLOT_Y" => p.y = [v(), w[2].parse().unwrap()],
            _ => { p.width = w[1].parse().unwrap(); p.height = w[2].parse().unwrap(); }
        }
    }
    (scans, targets, p)
}

#[derive(Clone, Copy, PartialEq)]
enum Status { Tentative, Confirmed, Deleted }
impl Status { fn text(self) -> &'static str { match self { Self::Tentative => "tentative", Self::Confirmed => "confirmed", Self::Deleted => "deleted" } } }
struct Track {
    state: kalman::State, status: Status, birth: usize, hits: usize, misses: usize,
    confirmation: Option<usize>, deletion: Option<usize>, last_hit: usize,
    measurements: Vec<Option<usize>>, nis: Vec<(usize, f64)>,
}

fn listing(keyword: &str, values: Vec<String>) -> String {
    format!("{} {}", keyword, if values.is_empty() { "none".to_owned() } else { values.join(" ") })
}

fn track(scans: &[Scan], p: &Params) -> (Vec<Track>, Vec<String>, Vec<String>, [usize; 3]) {
    let mut tracks = Vec::<Track>::new();
    let mut rows = vec!["track,scan,x,y,vx,vy,status".to_owned()];
    let mut log = Vec::new();
    let mut totals = [0; 3];
    for (k, scan) in scans.iter().enumerate() {
        let live: Vec<_> = tracks.iter().enumerate().filter(|(_, t)| t.status != Status::Deleted).map(|(i, _)| i).collect();
        for &i in &live {
            if k > 0 { tracks[i].state = tracks[i].state.predict(scan.time-scans[k-1].time, if p.ca { p.kalman.q_ca } else { p.kalman.q_cv }).0; }
        }
        let costs: Vec<Vec<_>> = live.iter().map(|&i| scan.measurements.iter().map(|&z| {
            let d = tracks[i].state.innovation(z, p.kalman.sigma).distance;
            if d <= p.gate { Some(d) } else { None }
        }).collect()).collect();
        let conflicts_measurements = (0..scan.measurements.len()).filter(|&j| costs.iter().filter(|r| r[j].is_some()).count() >= 2).count();
        let conflicts_tracks = costs.iter().filter(|r| r.iter().flatten().count() >= 2).count();
        totals[0] += conflicts_measurements; totals[1] += conflicts_tracks;
        let assigned = association::optimal(&costs, scan.measurements.len());
        let mut candidates: Vec<_> = costs.iter().enumerate().flat_map(|(i, row)| row.iter().enumerate().filter_map(move |(j, &c)| c.map(|c| (c, i, j)))).collect();
        candidates.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)).then(a.2.cmp(&b.2)));
        let mut used_tracks = vec![false; live.len()];
        let mut used_measurements = vec![false; scan.measurements.len()];
        let mut greedy = Vec::new();
        for (_, i, j) in candidates {
            if !used_tracks[i] && !used_measurements[j] { used_tracks[i] = true; used_measurements[j] = true; greedy.push((i, j)); }
        }
        greedy.sort_unstable();
        totals[2] += usize::from(greedy != assigned);
        used_measurements.fill(false);
        let (mut missed, mut confirmed, mut deleted) = (Vec::new(), Vec::new(), Vec::new());
        for (row, &i) in live.iter().enumerate() {
            let measurement = assigned.iter().find(|&&(r, _)| r == row).map(|&(_, j)| j);
            let t = &mut tracks[i];
            if let Some(j) = measurement {
                used_measurements[j] = true;
                let nis = t.state.update(scan.measurements[j], p.kalman.sigma).0;
                t.nis.push((k, nis)); t.hits += 1; t.misses = 0; t.last_hit = k;
            } else { t.misses += 1; missed.push((i+1).to_string()); }
            t.measurements.push(measurement);
            if t.status == Status::Confirmed {
                if t.misses >= p.delete { t.status = Status::Deleted; t.deletion = Some(k); deleted.push((i+1).to_string()); }
            } else if t.hits >= p.confirm {
                t.status = Status::Confirmed; t.confirmation = Some(k); confirmed.push((i+1).to_string());
            } else if k-t.birth+1 >= p.window {
                t.status = Status::Deleted; t.deletion = Some(k); deleted.push((i+1).to_string());
            }
        }
        let mut created = Vec::new();
        let mut processed = live.clone();
        for (j, &z) in scan.measurements.iter().enumerate() {
            if used_measurements[j] { continue; }
            let i = tracks.len();
            tracks.push(Track { state: kalman::State::new(z, p.ca, &p.kalman), status: Status::Tentative, birth: k, hits: 1, misses: 0,
                confirmation: None, deletion: None, last_hit: k, measurements: vec![Some(j)], nis: Vec::new() });
            created.push(format!("{}:{}", i+1, j+1)); processed.push(i);
        }
        for i in processed {
            rows.push(format!("{},{},{},{}", i+1, k+1, tracks[i].state.x[..4].iter().map(|&v| real(v)).collect::<Vec<_>>().join(","), tracks[i].status.text()));
        }
        log.push(format!("scan {} tracks {} measurements {}", k+1, live.len(), scan.measurements.len()));
        let gate: Vec<_> = costs.iter().enumerate().flat_map(|(i, row)| row.iter().enumerate().filter_map(move |(j, &value)| value.map(|v| (i, j, v)))).map(|(i, j, v)| format!("{}:{}={}", live[i]+1, j+1, real(v))).collect();
        log.push(listing("gate", gate));
        log.push(listing("assign", assigned.iter().map(|&(i, j)| format!("{}:{}", live[i]+1, j+1)).collect()));
        log.push(listing("greedy", greedy.iter().map(|&(i, j)| format!("{}:{}", live[i]+1, j+1)).collect()));
        log.push(listing("missed", missed)); log.push(listing("new", created)); log.push(listing("confirmed", confirmed)); log.push(listing("deleted", deleted));
        log.push(format!("status tentative {} confirmed {}", tracks.iter().filter(|t| t.status == Status::Tentative).count(), tracks.iter().filter(|t| t.status == Status::Confirmed).count()));
        log.push(format!("conflicts measurements {} tracks {}", conflicts_measurements, conflicts_tracks));
    }
    (tracks, rows, log, totals)
}

struct FilterRun { states: Vec<kalman::State>, predictions: Vec<Option<kalman::State>>, transitions: Vec<Option<Matrix>>, likelihood: f64 }

fn filter(scans: &[Scan], track: &Track, p: &Params, ca: bool) -> FilterRun {
    let mut state = kalman::State::new(scans[track.birth].measurements[track.measurements[0].unwrap()], ca, &p.kalman);
    let mut result = FilterRun { states: vec![state.clone()], predictions: vec![None], transitions: vec![None], likelihood: 0.0 };
    for k in track.birth+1..=track.last_hit {
        let (predicted, transition) = state.predict(scans[k].time-scans[k-1].time, if ca { p.kalman.q_ca } else { p.kalman.q_cv });
        state = predicted.clone();
        if let Some(j) = track.measurements[k-track.birth] { result.likelihood += state.update(scans[k].measurements[j], p.kalman.sigma).1; }
        result.states.push(state.clone()); result.predictions.push(Some(predicted)); result.transitions.push(Some(transition));
    }
    result
}

struct Estimates { track: usize, values: Vec<Vec<Vec<f64>>>, covariance: Vec<Matrix>, high: Vec<f64>, likelihood: [f64; 2] }

fn compare_filters(index: usize, track: &Track, scans: &[Scan], p: &Params) -> Estimates {
    let cv = filter(scans, track, p, false);
    let ca = filter(scans, track, p, true);
    let primary = if p.ca { &ca } else { &cv };
    let rts = kalman::smooth(&primary.states, &primary.predictions, &primary.transitions);
    let initial = scans[track.birth].measurements[track.measurements[0].unwrap()];
    let mut abg = vec![initial[0], initial[1], 0.0, 0.0, 0.0, 0.0];
    let mut abg_values = vec![abg[..4].to_vec()];
    let mut imm = imm::State::new(initial, &p.imm, &p.kalman);
    let mut imm_values = vec![imm.estimate()];
    let mut high = vec![imm.probabilities[1]];
    for k in track.birth+1..=track.last_hit {
        let t = scans[k].time-scans[k-1].time;
        let z = track.measurements[k-track.birth].map(|j| scans[k].measurements[j]);
        for axis in 0..2 {
            let (position, velocity, acceleration) = (abg[axis], abg[axis+2], abg[axis+4]);
            abg[axis] = position+t*velocity+t*t*acceleration/2.0;
            abg[axis+2] = velocity+t*acceleration;
            if let Some(z) = z {
                let residual = z[axis]-abg[axis];
                abg[axis] += p.abg[0]*residual;
                abg[axis+2] += p.abg[1]*residual/t;
                abg[axis+4] += 2.0*p.abg[2]*residual/(t*t);
            }
        }
        abg_values.push(abg[..4].to_vec());
        imm.step(t, z, &p.imm, &p.kalman);
        imm_values.push(imm.estimate()); high.push(imm.probabilities[1]);
    }
    let covariance = primary.states.iter().map(|s| s.covariance.clone()).collect();
    let values = vec![cv.states.iter().map(|s| s.x[..4].to_vec()).collect(), ca.states.iter().map(|s| s.x[..4].to_vec()).collect(),
        abg_values, imm_values, rts.iter().map(|x| x[..4].to_vec()).collect()];
    Estimates { track: index, values, covariance, high, likelihood: [cv.likelihood, ca.likelihood] }
}

fn position(x: &[f64]) -> [f64; 2] { [x[0], x[1]] }
fn track_character(index: usize) -> char { (if index < 26 { b'A'+index as u8 } else { b'a'+(index-26) as u8 }) as char }
fn path(points: &[[f64; 2]]) -> f64 { points.windows(2).map(|pair| distance(pair[0], pair[1])).sum() }
fn optional_scan(scan: Option<usize>) -> String { scan.map_or_else(|| "-".to_owned(), |s| (s+1).to_string()) }
fn segments(labels: &[Option<usize>]) -> Vec<(usize, usize, usize)> {
    let mut result = Vec::new();
    let mut i = 0;
    while i < labels.len() {
        if let Some(label) = labels[i] {
            let first = i; i += 1;
            while i < labels.len() && labels[i] == Some(label) { i += 1; }
            result.push((first, i-1, label));
        } else { i += 1; }
    }
    result
}
fn rmse_line(sum: &[f64; 5], count: usize) -> String {
    let values: Vec<_> = sum.iter().map(|&s| if count == 0 { "-".to_owned() } else { real((s/count as f64).sqrt()) }).collect();
    let best = if count == 0 { "-" } else {
        let best = (0..5).min_by(|&i, &j| values[i].parse::<f64>().unwrap().total_cmp(&values[j].parse::<f64>().unwrap()).then(i.cmp(&j))).unwrap();
        ["cv", "ca", "abg", "imm", "rts"][best]
    };
    format!("cv {} ca {} abg {} imm {} rts {} best {}", values[0], values[1], values[2], values[3], values[4], best)
}
fn framed(cells: &[u8], width: usize) -> Vec<String> {
    let frame = format!("+{}+", "-".repeat(width));
    let mut lines = vec![frame.clone()];
    for row in cells.chunks(width) { lines.push(format!("|{}|", String::from_utf8(row.to_vec()).unwrap())); }
    lines.push(frame); lines
}

fn main() {
    let (scans, targets, p) = read();
    let (tracks, track_rows, log, totals) = track(&scans, &p);
    let estimates: Vec<_> = tracks.iter().enumerate().filter(|(_, t)| t.confirmation.is_some())
        .map(|(i, t)| compare_filters(i, t, &scans, &p)).collect();
    let primary = usize::from(p.ca);
    let filters = ["cv", "ca", "abg", "imm", "rts"];
    let mut smoothed = vec!["track,scan,x,y,vx,vy".to_owned()];
    for estimate in &estimates {
        let track = &tracks[estimate.track];
        for (i, state) in estimate.values[4].iter().enumerate() {
            smoothed.push(format!("{},{},{}", estimate.track+1, track.birth+i+1, state.iter().map(|&v| real(v)).collect::<Vec<_>>().join(",")));
        }
    }
    let mut labels = vec![vec![vec![None; scans.len()]; targets.len()]; 5];
    let mut primary_targets = vec![vec![None; scans.len()]; estimates.len()];
    let mut ospa = vec![[0.0; 5]; scans.len()];
    let mut scan_counts = Vec::new();
    for k in 0..scans.len() {
        let active: Vec<_> = estimates.iter().enumerate().filter(|(_, e)| tracks[e.track].birth <= k && k <= tracks[e.track].last_hit).map(|(i, _)| i).collect();
        let existing: Vec<_> = targets.iter().enumerate().filter(|(_, t)| t.positions.contains_key(&k)).map(|(i, _)| i).collect();
        scan_counts.push((existing.len(), active.len()));
        let truth: Vec<_> = existing.iter().map(|&b| targets[b].positions[&k]).collect();
        for f in 0..5 {
            let positions: Vec<_> = active.iter().map(|&a| position(&estimates[a].values[f][k-tracks[estimates[a].track].birth])).collect();
            let costs: Vec<Vec<_>> = positions.iter().map(|&x| truth.iter().map(|&y| {
                let d = distance(x, y); if d <= p.matching { Some(d) } else { None }
            }).collect()).collect();
            for (i, j) in association::optimal(&costs, truth.len()) {
                labels[f][existing[j]][k] = Some(active[i]);
                if f == primary { primary_targets[active[i]][k] = Some(existing[j]); }
            }
            ospa[k][f] = evaluation::ospa(&positions, &truth, p.cutoff);
        }
    }
    let costs: Vec<Vec<_>> = estimates.iter().map(|estimate| {
        let track = &tracks[estimate.track];
        targets.iter().map(|target| {
            let mut total = 0.0;
            let mut count = 0;
            let mut usable = false;
            for k in 0..scans.len() {
                let in_track = track.birth <= k && k <= track.last_hit;
                let truth = target.positions.get(&k);
                if !in_track && truth.is_none() { continue; }
                count += 1;
                if in_track && truth.is_some() {
                    let d = distance(position(&estimate.values[primary][k-track.birth]), *truth.unwrap());
                    usable |= d < p.cutoff; total += p.cutoff.min(d);
                } else { total += p.cutoff; }
            }
            if usable { Some(total/count as f64) } else { None }
        }).collect()
    }).collect();
    let matching = association::optimal(&costs, targets.len());
    let mut matched_tracks = vec![None; targets.len()];
    let mut matched_targets = vec![None; estimates.len()];
    for (a, b) in matching { matched_tracks[b] = Some(a); matched_targets[a] = Some(b); }
    let false_tracks = primary_targets.iter().filter(|v| v.iter().all(Option::is_none)).count();
    let mut lines = vec!["summary".to_owned(), format!("scans {}", scans.len()), format!("measurements {}", scans.iter().map(|s| s.measurements.len()).sum::<usize>()),
        format!("targets {}", targets.len()), format!("tracks_created {}", tracks.len()), format!("tracks_confirmed {}", estimates.len()),
        format!("false_tracks {}", false_tracks), format!("missed_targets {}", matched_tracks.iter().filter(|m| m.is_none()).count()),
        format!("measurements_used {}", estimates.iter().map(|e| tracks[e.track].measurements[..=tracks[e.track].last_hit-tracks[e.track].birth].iter().flatten().count()).sum::<usize>()),
        format!("conflict_measurements {}", totals[0]), format!("conflict_tracks {}", totals[1]), format!("greedy_differences {}", totals[2]), String::new(), "targets".to_owned()];
    for target in &targets {
        let first = *target.positions.keys().next().unwrap();
        let last = *target.positions.keys().last().unwrap();
        let points: Vec<_> = target.positions.values().copied().collect();
        let length = path(&points);
        lines.push(format!("target {} first {} last {} scans {} path {} mean_speed {}", target.number, first+1, last+1, points.len(), real(length), real(length/(scans[last].time-scans[first].time))));
    }
    lines.extend([String::new(), "tracks".to_owned()]);
    let all_nis: Vec<_> = estimates.iter().flat_map(|e| tracks[e.track].nis.iter().filter(|(k, _)| *k <= tracks[e.track].last_hit).map(|(_, v)| *v)).collect();
    for estimate in &estimates {
        let track = &tracks[estimate.track];
        let measurements = &track.measurements[..=track.last_hit-track.birth];
        let hits = measurements.iter().flatten().count();
        let mut gap = 0;
        let mut longest = 0;
        for m in measurements { if m.is_none() { gap += 1; longest = longest.max(gap); } else { gap = 0; } }
        let nis: Vec<_> = track.nis.iter().filter(|(k, _)| *k <= track.last_hit).map(|(_, v)| *v).collect();
        let positions: Vec<_> = estimate.values[4].iter().map(|x| position(x)).collect();
        lines.push(format!("track {} birth {} confirmed {} end {} deleted {} hits {} misses {} longest_gap {} path {} nis {} nis_inside {}/{}",
            estimate.track+1, track.birth+1, track.confirmation.unwrap()+1, track.last_hit+1, optional_scan(track.deletion), hits, measurements.len()-hits, longest,
            real(path(&positions)), if nis.is_empty() { "-".to_owned() } else { real(nis.iter().sum::<f64>()/nis.len() as f64) }, nis.iter().filter(|&&v| v <= p.bound).count(), nis.len()));
    }
    lines.extend([String::new(), "matching".to_owned()]);
    for (a, estimate) in estimates.iter().enumerate() {
        let track = &tracks[estimate.track];
        let matched_scans = primary_targets[a].iter().flatten().count();
        let segments: Vec<_> = segments(&primary_targets[a]).iter().map(|&(first, last, b)| format!("{}-{}:{}", first+1, last+1, targets[b].number)).collect();
        let segment_text = if segments.is_empty() { "none".to_owned() } else { segments.join(" ") };
        let matched = if let Some(b) = matched_targets[a] {
            let common = targets[b].positions.keys().filter(|&&k| track.birth <= k && k <= track.last_hit).count();
            format!("{} common {} mean_distance {}", targets[b].number, common, real(costs[a][b].unwrap()))
        } else { "-".to_owned() };
        lines.push(format!("track {} target {} matched_scans {} segments {}", estimate.track+1, matched, matched_scans, segment_text));
    }
    lines.extend([String::new(), "rmse".to_owned()]);
    let (mut position_total, mut velocity_total) = ([0.0; 5], [0.0; 5]);
    let (mut position_count, mut velocity_count) = (0, 0);
    let mut consistency = vec!["consistency".to_owned()];
    for (b, target) in targets.iter().enumerate() {
        let Some(a) = matched_tracks[b] else {
            lines.push(format!("target {} track -", target.number)); consistency.push(format!("target {} track -", target.number)); continue;
        };
        let estimate = &estimates[a];
        let track = &tracks[estimate.track];
        let (mut pos, mut vel) = ([0.0; 5], [0.0; 5]);
        let (mut common, mut velocities, mut nees_sum, mut nees_inside) = (0, 0, 0.0, 0);
        for (&k, &truth) in &target.positions {
            if k < track.birth || k > track.last_hit { continue; }
            common += 1;
            let offset = k-track.birth;
            let velocity = if k > 0 && k+1 < scans.len() && target.positions.contains_key(&(k-1)) && target.positions.contains_key(&(k+1)) {
                let (before, after) = (target.positions[&(k-1)], target.positions[&(k+1)]);
                Some([(after[0]-before[0])/(scans[k+1].time-scans[k-1].time), (after[1]-before[1])/(scans[k+1].time-scans[k-1].time)])
            } else { None };
            if velocity.is_some() { velocities += 1; }
            for f in 0..5 {
                let state = &estimate.values[f][offset];
                let (ex, ey) = (state[0]-truth[0], state[1]-truth[1]);
                pos[f] += ex*ex+ey*ey;
                position_total[f] += ex*ex+ey*ey;
                if let Some(v) = velocity {
                    let (fx, fy) = (state[2]-v[0], state[3]-v[1]);
                    vel[f] += fx*fx+fy*fy; velocity_total[f] += fx*fx+fy*fy;
                }
            }
            let state = &estimate.values[primary][offset];
            let covariance = &estimate.covariance[offset];
            let inverse = matrix::inverse(&vec![covariance[0][..2].to_vec(), covariance[1][..2].to_vec()]);
            let nees = matrix::quadratic([state[0]-truth[0], state[1]-truth[1]], &inverse);
            nees_sum += nees; nees_inside += usize::from(nees <= p.bound);
        }
        position_count += common; velocity_count += velocities;
        lines.push(format!("target {} track {} common {} {}", target.number, estimate.track+1, common, rmse_line(&pos, common)));
        lines.push(format!("target {} velocity {} {}", target.number, velocities, rmse_line(&vel, velocities)));
        consistency.push(format!("target {} track {} nees {} inside {}/{}", target.number, estimate.track+1, real(nees_sum/common as f64), nees_inside, common));
    }
    lines.push(format!("overall position {}", rmse_line(&position_total, position_count)));
    lines.push(format!("overall velocity {}", rmse_line(&velocity_total, velocity_count)));
    let mut observed = vec![0; p.edges.len()+1];
    for &nis in &all_nis { let bin = p.edges.iter().filter(|&&e| nis >= e).count(); observed[bin] += 1; }
    let expected: Vec<_> = (0..observed.len()).map(|i| {
        let lower = if i == 0 { 0.0 } else { p.edges[i-1] };
        let upper_exp = if i == p.edges.len() { 0.0 } else { (-p.edges[i]/2.0).exp() };
        real(all_nis.len() as f64*((-lower/2.0).exp()-upper_exp))
    }).collect();
    consistency.push(format!("nis_histogram total {} observed {} expected {}", all_nis.len(), observed.iter().map(usize::to_string).collect::<Vec<_>>().join(" "), expected.join(" ")));
    lines.push(String::new()); lines.extend(consistency);
    lines.extend([String::new(), "models".to_owned()]);
    for estimate in &estimates {
        let updates = tracks[estimate.track].nis.iter().filter(|(k, _)| *k <= tracks[estimate.track].last_hit).count();
        lines.push(format!("track {} updates {} cv {} ca {} better {}", estimate.track+1, updates, real(estimate.likelihood[0]), real(estimate.likelihood[1]),
            if estimate.likelihood[0] >= estimate.likelihood[1] { "cv" } else { "ca" }));
    }
    lines.extend([String::new(), format!("ospa cutoff {} order 2", real(p.cutoff)), "scan targets tracks cv ca abg imm rts".to_owned()]);
    for k in 0..scans.len() { lines.push(format!("{} {} {} {}", k+1, scan_counts[k].0, scan_counts[k].1, ospa[k].iter().map(|&v| real(v)).collect::<Vec<_>>().join(" "))); }
    lines.push(format!("mean {}", (0..5).map(|f| real(ospa.iter().map(|row| row[f]).sum::<f64>()/scans.len() as f64)).collect::<Vec<_>>().join(" ")));
    lines.extend([String::new(), "continuity".to_owned()]);
    for f in 0..5 {
        let summaries: Vec<_> = targets.iter().enumerate().map(|(b, target)| {
            let sequence: Vec<_> = target.positions.keys().map(|&k| labels[f][b][k]).collect();
            evaluation::continuity(&sequence)
        }).collect();
        lines.push(format!("{} covered {} breaks {} swaps {}", filters[f], summaries.iter().map(|c| c.covered).sum::<usize>(), summaries.iter().map(|c| c.breaks).sum::<usize>(), summaries.iter().map(|c| c.swaps).sum::<usize>()));
        for (b, summary) in summaries.iter().enumerate() {
            lines.push(format!("  target {} scans {} covered {} breaks {} swaps {} delay {}", targets[b].number, targets[b].positions.len(), summary.covered, summary.breaks, summary.swaps,
                summary.delay.map_or_else(|| "-".to_owned(), |d| d.to_string())));
        }
    }
    lines.extend([String::new(), "imm".to_owned()]);
    for estimate in &estimates {
        let track = &tracks[estimate.track];
        let peak = (0..estimate.high.len()).min_by(|&i, &j| estimate.high[j].total_cmp(&estimate.high[i]).then(i.cmp(&j))).unwrap();
        let high: Vec<_> = estimate.high.iter().map(|&v| if v > 0.5 { Some(0) } else { None }).collect();
        let segments: Vec<_> = segments(&high).iter().map(|&(a, b, _)| format!("{}-{}", track.birth+a+1, track.birth+b+1)).collect();
        lines.push(format!("track {} mean_high {} max_high {} at {} high_scans {} segments {}", estimate.track+1, real(estimate.high.iter().sum::<f64>()/estimate.high.len() as f64),
            real(estimate.high[peak]), track.birth+peak+1, high.iter().flatten().count(), if segments.is_empty() { "none".to_owned() } else { segments.join(" ") }));
    }
    let point_cell = |point: [f64; 2]| {
        let dx = (p.x[1]-p.x[0])/p.width as f64;
        let dy = (p.y[1]-p.y[0])/p.height as f64;
        let c = ((point[0]-p.x[0])/dx).floor() as i64;
        let r = ((p.y[1]-point[1])/dy).floor() as i64;
        if c >= 0 && c < p.width as i64 && r >= 0 && r < p.height as i64 { Some(r as usize*p.width+c as usize) } else { None }
    };
    let mut cells = vec![b' '; p.width*p.height];
    for target in &targets { for &position in target.positions.values() { if let Some(cell) = point_cell(position) { cells[cell] = b'.'; } } }
    for (a, estimate) in estimates.iter().enumerate() {
        for state in &estimate.values[4] { if let Some(cell) = point_cell(position(state)) { cells[cell] = track_character(a) as u8; } }
    }
    let mut plot = vec![format!("tracks x {} {} y {} {} size {} {}", real(p.x[0]), real(p.x[1]), real(p.y[0]), real(p.y[1]), p.width, p.height)];
    plot.extend(framed(&cells, p.width));
    for (a, estimate) in estimates.iter().enumerate() { plot.push(format!("{} track {} target {}", track_character(a), estimate.track+1,
        matched_targets[a].map_or_else(|| "-".to_owned(), |b| targets[b].number.to_string()))); }
    plot.extend([String::new(), "measurements".to_owned()]);
    let mut counts = vec![0; cells.len()];
    for scan in &scans { for &position in &scan.measurements { if let Some(cell) = point_cell(position) { counts[cell] += 1; } } }
    let measurements: Vec<_> = counts.iter().map(|&count| if count == 0 { b' ' } else if count <= 9 { b'0'+count as u8 } else { b'#' }).collect();
    plot.extend(framed(&measurements, p.width));
    plot.extend([String::new(), "timeline".to_owned()]);
    for (b, target) in targets.iter().enumerate() {
        let timeline: String = (0..scans.len()).map(|k| if !target.positions.contains_key(&k) { ' ' }
            else { labels[primary][b][k].map_or('.', track_character) }).collect();
        plot.push(format!("{} |{}|", target.number, timeline));
    }
    plot.extend([String::new(), format!("ospa {}", filters[primary])]);
    let cutoff = p.cutoff;
    let ospa_cells: Vec<_> = (1..=10).flat_map(|row| ospa.iter().map(move |values|
        if (10.0*values[primary]/cutoff).floor() as usize >= 11-row { b'#' } else { b' ' })).collect();
    plot.extend(framed(&ospa_cells, scans.len()));
    fs::create_dir_all("output").unwrap();
    for (file, lines) in [("tracks.csv", track_rows), ("smoothed.csv", smoothed), ("association_log.txt", log), ("evaluation.txt", lines), ("track_plot.txt", plot)] {
        fs::write(format!("output/{}", file), lines.join("\n")+"\n").unwrap();
    }
}
