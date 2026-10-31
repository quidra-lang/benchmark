mod detector;
mod filters;
mod hrv;
mod report;
mod signal_io;

use detector::Peak;
use filters::Signals;
use report::{decimal2, decimal4, fraction, missing, ratio, rdiv};
use signal_io::Input;
use std::collections::{BTreeMap, VecDeque};
use std::fs;

const LABELS: [u8; 3] = [b'N', b'V', b'A'];

struct Detection {
    peaks: Vec<Peak>,
    registered: Vec<usize>,
    initial: [i64; 4],
    levels: [i64; 4],
    rr: VecDeque<i64>,
    average1: i64,
    average2: i64,
}

impl Detection {
    fn thresholds(&self) -> (i64, i64) {
        (self.levels[1] + (self.levels[0] - self.levels[1]).div_euclid(4), self.levels[3] + (self.levels[2] - self.levels[3]).div_euclid(4))
    }

    fn update(&mut self, index: usize, kind: &str) {
        let peak = &self.peaks[index];
        let (i, f, weight, divisor) = match kind { "noise" => (1, 3, 7, 8), "searchback" => (0, 2, 3, 4), _ => (0, 2, 7, 8) };
        self.levels[i] = (peak.integrated + weight * self.levels[i]).div_euclid(divisor);
        self.levels[f] = (peak.filtered + weight * self.levels[f]).div_euclid(divisor);
    }

    fn register(&mut self, index: usize) {
        if let Some(&previous) = self.registered.last() {
            let interval = (self.peaks[index].time - self.peaks[previous].time) as i64;
            self.rr.push_back(interval);
            if self.rr.len() > 8 { self.rr.pop_front(); }
            self.average1 = self.rr.iter().sum::<i64>() / self.rr.len() as i64;
            if 92 * self.average1 <= 100 * interval && 100 * interval <= 116 * self.average1 { self.average2 = self.average1; }
        }
        self.registered.push(index);
    }

    fn searchback(&mut self, time: usize, percent: i64) {
        loop {
            let previous = self.registered.last().map_or(0, |&i| self.peaks[i].time);
            if time as i64 - previous as i64 <= self.average2 * percent / 100 { return; }
            let (threshold_i, threshold_f) = self.thresholds();
            let candidate = self.peaks.iter().enumerate().filter(|(_, peak)| peak.class == "noise" && peak.time > previous && peak.time < time && peak.integrated > threshold_i.div_euclid(2) && peak.filtered > threshold_f.div_euclid(2)).min_by_key(|(_, peak)| (-peak.integrated, peak.time)).map(|(i, _)| i);
            let Some(index) = candidate else { return; };
            self.update(index, "searchback");
            self.peaks[index].class = "searchback";
            self.register(index);
        }
    }
}

fn detect(signals: &Signals, params: &BTreeMap<String, i64>) -> Detection {
    let initial = detector::initial(signals);
    let mut result = Detection { peaks: detector::peaks(signals), registered: Vec::new(), initial, levels: initial, rr: VecDeque::new(), average1: 200, average2: 200 };
    for i in 0..result.peaks.len() {
        let time = result.peaks[i].time;
        result.searchback(time, params["searchback_percent"]);
        let (threshold_i, threshold_f) = result.thresholds();
        result.peaks[i].threshold_i = threshold_i;
        result.peaks[i].threshold_f = threshold_f;
        let previous = result.registered.last().copied();
        if previous.is_some_and(|j| time - result.peaks[j].time < (params["refractory_ms"] / 5) as usize) {
            result.peaks[i].class = "refractory";
        } else if result.peaks[i].integrated > threshold_i && result.peaks[i].filtered > threshold_f {
            if previous.is_some_and(|j| time - result.peaks[j].time < (params["twave_ms"] / 5) as usize && 2 * result.peaks[i].slope < result.peaks[j].slope) {
                result.peaks[i].class = "twave";
                result.update(i, "noise");
            } else {
                result.peaks[i].class = "qrs";
                result.update(i, "signal");
                result.register(i);
            }
        } else {
            result.peaks[i].class = "noise";
            result.update(i, "noise");
        }
    }
    result.searchback(signals.integrated.len(), params["searchback_percent"]);
    result
}

struct Beat {
    sample: usize,
    rr: Option<i64>,
    width: i64,
    label: u8,
    method: &'static str,
    reference: Option<usize>,
}

fn beats(input: &Input, signals: &Signals, detection: &Detection) -> (Vec<Beat>, Vec<Option<usize>>) {
    let mut beats: Vec<Beat> = Vec::new();
    for &i in &detection.registered {
        let peak = &detection.peaks[i];
        let sample = peak.r.saturating_sub(21);
        let rr = beats.last().map(|previous| 5 * (sample - previous.sample) as i64);
        let width = detector::width(signals, peak);
        let k = beats.len();
        let premature = if k >= 9 {
            let preceding: i64 = beats[k - 8..k].iter().map(|b| b.rr.unwrap()).sum();
            800 * rr.unwrap() < input.params["premature_percent"] * preceding
        } else { false };
        let label = if premature { if width > input.params["qrs_width_ms"] { b'V' } else { b'A' } } else { b'N' };
        beats.push(Beat { sample, rr, width, label, method: if peak.class == "qrs" { "threshold" } else { "searchback" }, reference: None });
    }
    let mut matched = vec![None; input.annotations.len()];
    for (index, beat) in beats.iter_mut().enumerate() {
        let reference = input.annotations.iter().enumerate().filter(|(i, annotation)| matched[*i].is_none() && annotation.sample.abs_diff(beat.sample) <= (input.params["match_ms"] / 5) as usize).min_by_key(|(_, annotation)| (annotation.sample.abs_diff(beat.sample), annotation.sample)).map(|(i, _)| i);
        if let Some(reference) = reference { matched[reference] = Some(index); beat.reference = Some(reference); }
    }
    (beats, matched)
}

fn beat_lines(input: &Input, beats: &[Beat]) -> Vec<String> {
    let mut lines = vec!["beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label".into()];
    for (index, beat) in beats.iter().enumerate() {
        let reference = beat.reference.map(|i| &input.annotations[i]);
        lines.push(format!("{},{},{},{},{},{},{},{},{},{}", index + 1, beat.sample, 5 * beat.sample, missing(beat.rr), beat.rr.map_or_else(|| "-".into(), |rr| decimal2(rdiv(6000000, rr))), beat.width, beat.label as char, beat.method, reference.map_or_else(|| "-".into(), |r| r.sample.to_string()), reference.map_or_else(|| "-".into(), |r| (r.label as char).to_string())));
    }
    lines
}

fn matching_lines(input: &Input, beats: &[Beat], matched: &[Option<usize>]) -> Vec<String> {
    let mut records = Vec::new();
    for (i, annotation) in input.annotations.iter().enumerate() {
        let line = if let Some(index) = matched[i] {
            let beat = &beats[index];
            format!("{},{},{},{},{},{},TP,{}", annotation.sample, annotation.label as char, index + 1, beat.sample, beat.label as char, 5 * (beat.sample as i64 - annotation.sample as i64), if annotation.label == beat.label { "yes" } else { "no" })
        } else { format!("{},{},-,-,-,-,FN,-", annotation.sample, annotation.label as char) };
        records.push((annotation.sample, 0, line));
    }
    for (i, beat) in beats.iter().enumerate().filter(|(_, b)| b.reference.is_none()) {
        records.push((beat.sample, 1, format!("-,-,{},{},{},-,FP,-", i + 1, beat.sample, beat.label as char)));
    }
    records.sort_by_key(|record| (record.0, record.1));
    let mut lines = vec!["ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree".into()];
    lines.extend(records.into_iter().map(|record| record.2));
    lines
}

fn segments(length: usize, params: &BTreeMap<String, i64>) -> Vec<(usize, usize)> {
    let width = (params["segment_ms"] / 5) as usize;
    (0..length).step_by(width).map(|start| (start, (start + width).min(length))).collect()
}

fn performance(input: &Input, detection: &Detection, beats: &[Beat], matched: &[Option<usize>]) -> Vec<String> {
    let tp = matched.iter().filter(|m| m.is_some()).count();
    let fp = beats.len() - tp;
    let fn_count = matched.len() - tp;
    let class_count = |class| detection.peaks.iter().filter(|peak| peak.class == class).count();
    let initial = detection.initial;
    let final_levels = detection.levels;
    let (threshold_i, threshold_f) = detection.thresholds();
    let label_count = |label| beats.iter().filter(|beat| beat.label == label).count();
    let ref_count = |label| input.annotations.iter().filter(|r| r.label == label).count();
    let mut lines = vec!["DETECTOR".into(), format!("samples {}", input.ecg.len()), format!("duration_ms {}", 5 * input.ecg.len()),
        format!("peaks {} qrs={} searchback={} twave={} refractory={} noise={}", detection.peaks.len(), class_count("qrs"), class_count("searchback"), class_count("twave"), class_count("refractory"), class_count("noise")),
        format!("initial_levels spki={} npki={} spkf={} npkf={}", initial[0], initial[1], initial[2], initial[3]),
        format!("final_levels spki={} npki={} spkf={} npkf={}", final_levels[0], final_levels[1], final_levels[2], final_levels[3]),
        format!("final_thresholds thr_i={threshold_i} thr_f={threshold_f}"), format!("final_rr_averages rravg1_ms={} rravg2_ms={}", 5 * detection.average1, 5 * detection.average2),
        "MATCHING".into(), format!("tolerance_ms {}", input.params["match_ms"]),
        format!("references {} N={} V={} A={}", input.annotations.len(), ref_count(b'N'), ref_count(b'V'), ref_count(b'A')),
        format!("detections {} N={} V={} A={}", beats.len(), label_count(b'N'), label_count(b'V'), label_count(b'A')),
        format!("true_positives {tp}"), format!("false_positives {fp}"), format!("false_negatives {fn_count}"),
        format!("sensitivity {}", ratio(tp as i64, (tp + fn_count) as i64)), format!("positive_predictivity {}", ratio(tp as i64, (tp + fp) as i64)), format!("detection_error_rate {}", ratio((fp + fn_count) as i64, input.annotations.len() as i64))];
    let method_counts = |method| (beats.iter().filter(|b| b.method == method && b.reference.is_some()).count(), beats.iter().filter(|b| b.method == method).count());
    let (threshold_matched, threshold_total) = method_counts("threshold");
    let (search_matched, search_total) = method_counts("searchback");
    lines.push(format!("by_method threshold={threshold_matched}/{threshold_total} searchback={search_matched}/{search_total}"));
    let offsets: Vec<_> = beats.iter().filter_map(|beat| beat.reference.map(|r| 5 * (beat.sample as i64 - input.annotations[r].sample as i64))).collect();
    if offsets.is_empty() { lines.push("offset_ms none".into()); }
    else { lines.push(format!("offset_ms mean={} mean_abs={} max_abs={}", decimal2(rdiv(100 * offsets.iter().sum::<i64>(), tp as i64)), decimal2(rdiv(100 * offsets.iter().map(|v| v.abs()).sum::<i64>(), tp as i64)), offsets.iter().map(|v| v.abs()).max().unwrap())); }
    let mut confusion = [[0_i64; 3]; 3];
    let mut misses = [0_i64; 3];
    let mut extras = [0_i64; 3];
    for (index, annotation) in input.annotations.iter().enumerate() {
        let row = LABELS.iter().position(|&l| l == annotation.label).unwrap();
        if let Some(beat) = matched[index] { confusion[row][LABELS.iter().position(|&l| l == beats[beat].label).unwrap()] += 1; }
        else { misses[row] += 1; }
    }
    for beat in beats.iter().filter(|beat| beat.reference.is_none()) { extras[LABELS.iter().position(|&l| l == beat.label).unwrap()] += 1; }
    lines.extend(["CONFUSION".into(), format!("ref  {:>6}{:>6}{:>6}  miss", "N", "V", "A")]);
    for i in 0..3 { lines.push(format!("{}    {:6}{:6}{:6}{:6}", LABELS[i] as char, confusion[i][0], confusion[i][1], confusion[i][2], misses[i])); }
    lines.push(format!("extra{:6}{:6}{:6}", extras[0], extras[1], extras[2]));
    lines.extend([format!("veb_sensitivity {}", ratio(confusion[1][1], ref_count(b'V') as i64)), format!("veb_positive_predictivity {}", ratio(confusion[1][1], label_count(b'V') as i64)), format!("sveb_sensitivity {}", ratio(confusion[2][2], ref_count(b'A') as i64)), format!("sveb_positive_predictivity {}", ratio(confusion[2][2], label_count(b'A') as i64))]);
    let segments = segments(input.ecg.len(), &input.params);
    lines.push(format!("SEGMENTS segment_ms={} segments={}", input.params["segment_ms"], segments.len()));
    for (start, end) in segments {
        let references: Vec<_> = input.annotations.iter().enumerate().filter(|(_, r)| start <= r.sample && r.sample < end).collect();
        let matched_count = references.iter().filter(|(i, _)| matched[*i].is_some()).count();
        let false_positive = beats.iter().filter(|b| b.reference.is_none() && start <= b.sample && b.sample < end).count();
        let noise = detection.peaks.iter().filter(|p| p.class == "noise" && start <= p.time && p.time < end).count();
        lines.push(format!("{:6}-{:6} refs={} tp={} fp={} fn={} noise_peaks={}", 5 * start, 5 * end, references.len(), matched_count, false_positive, references.len() - matched_count, noise));
    }
    lines.push(format!("ERRORS count={}", fp + fn_count));
    let mut errors: Vec<_> = beats.iter().enumerate().filter(|(_, beat)| beat.reference.is_none()).map(|(i, b)| (b.sample, 0, format!("false_positive beat={} sample={} time_ms={} label={}", i + 1, b.sample, 5 * b.sample, b.label as char))).collect();
    errors.extend(input.annotations.iter().enumerate().filter(|(i, _)| matched[*i].is_none()).map(|(_, r)| (r.sample, 1, format!("false_negative sample={} time_ms={} label={}", r.sample, 5 * r.sample, r.label as char))));
    errors.sort_by_key(|record| (record.0, record.1));
    lines.extend(errors.into_iter().map(|record| record.2));
    lines
}

fn value_line(name: &str, value: Option<i64>) -> String { format!("{} {}", name, value.map_or_else(|| "none".into(), decimal2)) }

fn hrv_report(input: &Input, beats: &[Beat]) -> Vec<String> {
    let rr: Vec<_> = beats.iter().filter_map(|b| b.rr).collect();
    let mut lines = vec!["RR".into(), format!("beats {}", beats.len()), format!("intervals {}", rr.len()), value_line("mean_rr_ms", hrv::mean(&rr))];
    if rr.is_empty() { lines.extend(["min_rr_ms none".into(), "max_rr_ms none".into()]); }
    else {
        let minimum = *rr.iter().min().unwrap();
        let maximum = *rr.iter().max().unwrap();
        lines.push(format!("min_rr_ms {minimum} beat={}", rr.iter().position(|&v| v == minimum).unwrap() + 2));
        lines.push(format!("max_rr_ms {maximum} beat={}", rr.iter().position(|&v| v == maximum).unwrap() + 2));
    }
    lines.push(value_line("mean_hr_bpm", hrv::heart_rate(&rr)));
    let mut nn_flags = vec![false; beats.len()];
    for k in 2..beats.len() {
        nn_flags[k] = beats[k - 1].label == b'N' && beats[k].label == b'N' && 5 * (beats[k].rr.unwrap() - beats[k - 1].rr.unwrap()).abs() <= beats[k - 1].rr.unwrap();
    }
    let nn: Vec<_> = beats.iter().enumerate().filter(|(i, _)| nn_flags[*i]).map(|(_, b)| b.rr.unwrap()).collect();
    let pairs: Vec<_> = (1..beats.len()).filter(|&k| nn_flags[k - 1] && nn_flags[k]).map(|k| (beats[k - 1].rr.unwrap(), beats[k].rr.unwrap())).collect();
    let differences: Vec<_> = pairs.iter().map(|&(a, b)| b - a).collect();
    let sums: Vec<_> = pairs.iter().map(|&(a, b)| a + b).collect();
    let k = pairs.len() as i64;
    let nn50 = differences.iter().filter(|d| d.abs() > 50).count() as i64;
    lines.extend(["NN".into(), format!("intervals {}", nn.len()), value_line("mean_nn_ms", hrv::mean(&nn)), value_line("sdnn_ms", hrv::deviation(&nn, 1)), format!("differences {k}"), value_line("rmssd_ms", if k > 0 { Some(hrv::root(differences.iter().map(|d| d * d).sum(), k)) } else { None }), value_line("sdsd_ms", hrv::deviation(&differences, 1)), format!("nn50 {nn50}")]);
    lines.push(if k > 0 { format!("pnn50 {}%", decimal2(rdiv(10000 * nn50, k))) } else { "pnn50 none".into() });
    lines.extend([value_line("sd1_ms", hrv::deviation(&differences, 2)), value_line("sd2_ms", hrv::deviation(&sums, 2))]);
    let bins = hrv::histogram(&nn);
    let maximum = bins.values().copied().max().unwrap_or(0);
    lines.push(format!("HISTOGRAM bin_ms=7.8125 bins={} max={maximum}", bins.len()));
    for (bin, count) in bins { lines.push(format!("{:>10} {:>10} {:3} |{}", decimal4(78125 * bin), decimal4(78125 * (bin + 1)), count, "#".repeat(count))); }
    lines.push(if nn.is_empty() { "triangular_index none".into() } else { format!("triangular_index {} {}", fraction(nn.len() as i64, maximum as i64), decimal2(rdiv(100 * nn.len() as i64, maximum as i64))) });
    let premature: Vec<_> = beats.iter().enumerate().filter(|(_, b)| b.label != b'N').collect();
    lines.push(format!("PREMATURE count={} V={} A={}", premature.len(), beats.iter().filter(|b| b.label == b'V').count(), beats.iter().filter(|b| b.label == b'A').count()));
    for (index, beat) in premature {
        let preceding: i64 = beats[index - 8..index].iter().map(|b| b.rr.unwrap()).sum();
        let next = beats.get(index + 1).and_then(|b| b.rr);
        let compensation = next.map_or("-", |next| {
            let total = beat.rr.unwrap() + next;
            if 10 * (4 * total - preceding).abs() <= preceding { "full" } else if 4 * total < preceding { "partial" } else { "long" }
        });
        lines.push(format!("beat={} sample={} label={} rr_ms={} next_rr_ms={} mean_ms={} prematurity={}% compensation={} width_ms={} ref={}", index + 1, beat.sample, beat.label as char, beat.rr.unwrap(), missing(next), decimal2(rdiv(100 * preceding, 8)), decimal2(rdiv(80000 * beat.rr.unwrap(), preceding)), compensation, beat.width, beat.reference.map_or('-', |i| input.annotations[i].label as char)));
    }
    let mut runs = Vec::new();
    for label in [b'V', b'A'] {
        runs.extend(hrv::ranges(beats, |b| b.label == label).into_iter().map(|(start, end)| (start, end, label)));
    }
    runs.sort_by_key(|run| run.0);
    lines.push(format!("RUNS count={}", runs.len()));
    for (start, end, label) in runs {
        let length = end - start + 1;
        let kind = if length == 1 { "isolated" } else if length == 2 { "couplet" } else { "run" };
        lines.push(format!("{} {} beats={}-{} length={} start_ms={}", label as char, kind, start + 1, end + 1, length, 5 * beats[start].sample));
    }
    let events = events(input, beats, &rr);
    lines.push(format!("EVENTS count={}", events.len()));
    lines.extend(events);
    let segments = segments(input.ecg.len(), &input.params);
    lines.push(format!("TREND segment_ms={} segments={}", input.params["segment_ms"], segments.len()));
    for (start, end) in segments {
        let included: Vec<_> = beats.iter().filter(|b| start <= b.sample && b.sample < end).collect();
        let intervals: Vec<_> = included.iter().filter_map(|b| b.rr).collect();
        let prefix = format!("{:6}-{:6} beats={}", 5 * start, 5 * end, included.len());
        if let Some(mean) = hrv::heart_rate(&intervals) {
            lines.push(format!("{} mean_hr={} min_hr={} max_hr={} |{}", prefix, decimal2(mean), decimal2(rdiv(6000000, *intervals.iter().max().unwrap())), decimal2(rdiv(6000000, *intervals.iter().min().unwrap())), "#".repeat(rdiv(mean, 500) as usize)));
        } else { lines.push(format!("{prefix} mean_hr=none min_hr=none max_hr=none |")); }
    }
    lines
}

fn events(input: &Input, beats: &[Beat], rr: &[i64]) -> Vec<String> {
    let mut output = Vec::new();
    for (i, &interval) in rr.iter().enumerate().filter(|(_, value)| **value > input.params["pause_ms"]) {
        output.push(format!("pause beats={}-{} rr_ms={} start_ms={}", i + 1, i + 2, interval, 5 * beats[i].sample));
    }
    for (kind, key) in [("bradycardia", "brady_ms"), ("tachycardia", "tachy_ms")] {
        for (start, end) in hrv::ranges(rr, |&value| if kind == "bradycardia" { value > input.params[key] } else { value < input.params[key] }) {
            if end - start + 1 < 3 { continue; }
            output.push(format!("{kind} beats={}-{} intervals={} mean_hr={} start_ms={}", start + 1, end + 2, end - start + 1, decimal2(hrv::heart_rate(&rr[start..=end]).unwrap()), 5 * beats[start].sample));
        }
    }
    let ventricular: Vec<_> = beats.iter().enumerate().filter(|(_, b)| b.label == b'V').map(|(i, _)| i).collect();
    for (kind, distance) in [("bigeminy", 2), ("trigeminy", 3)] {
        let mut start = 0;
        while start < ventricular.len() {
            let mut end = start;
            while end + 1 < ventricular.len() {
                let (a, b) = (ventricular[end], ventricular[end + 1]);
                if b != a + distance || !beats[a + 1..b].iter().all(|beat| beat.label == b'N') { break; }
                end += 1;
            }
            if end - start + 1 >= 3 { output.push(format!("{kind} beats={}-{} cycles={} start_ms={}", ventricular[start] + 1, ventricular[end] + 1, end - start + 1, 5 * beats[ventricular[start]].sample)); }
            start = end + 1;
        }
    }
    output
}

fn scale(value: i64, top: i64, bottom: i64, rows: usize) -> usize {
    if top == bottom { 0 } else { rdiv((top - value) * (rows - 1) as i64, top - bottom) as usize }
}

fn waveform(high: &[i64], low: &[i64], rows: usize) -> Vec<String> {
    let top = *high.iter().max().unwrap();
    let bottom = *low.iter().min().unwrap();
    let zero = (bottom <= 0 && top >= 0).then(|| scale(0, top, bottom, rows));
    (0..rows).map(|row| {
        let label = if row == 0 { top.to_string() } else if row == rows - 1 { bottom.to_string() } else if zero == Some(row) { "0".into() } else { String::new() };
        let marks: String = high.iter().zip(low).map(|(&hi, &lo)| {
            if scale(hi, top, bottom, rows) <= row && row <= scale(lo, top, bottom, rows) { '#' }
            else if zero == Some(row) { '-' } else { ' ' }
        }).collect();
        format!("{label:>6} |{marks}|")
    }).collect()
}

fn axis(columns: usize, mark: impl Fn(usize) -> bool) -> String {
    format!("       +{}+", (0..columns).map(|c| if mark(c) { '+' } else { '-' }).collect::<String>())
}

fn label_row(heading: &str, pairs: &[(usize, String)]) -> String {
    let mut row = format!("{heading:>6}  ").into_bytes();
    for (column, text) in pairs {
        let offset = 8 + column;
        if row.len() < offset + text.len() { row.resize(offset + text.len(), b' '); }
        row[offset..offset + text.len()].copy_from_slice(text.as_bytes());
    }
    String::from_utf8(row).unwrap().trim_end().into()
}

fn charts(input: &Input, beats: &[Beat]) -> Vec<String> {
    let rr: Vec<_> = beats.iter().filter_map(|b| b.rr).collect();
    let rows = input.params["chart_rows"] as usize;
    let mut lines = Vec::new();
    if rr.is_empty() { lines.extend(["TACHOGRAM intervals=0".into(), "POINCARE points=0".into()]); }
    else {
        let low = *rr.iter().min().unwrap();
        let high = *rr.iter().max().unwrap();
        lines.push(format!("TACHOGRAM intervals={} min_ms={} max_ms={} rows={rows}", rr.len(), low, high));
        for row in 0..rows {
            let label = if row == 0 { high.to_string() } else if row == rows - 1 { low.to_string() } else { String::new() };
            let marks: String = rr.iter().map(|&value| if scale(value, high, low, rows) == row { '*' } else { ' ' }).collect();
            lines.push(format!("{label:>6} |{marks}|"));
        }
        lines.push(axis(rr.len(), |i| (i + 2) % 10 == 0));
        lines.push(label_row("beat", &(0..rr.len()).filter(|i| (i + 2) % 10 == 0).map(|i| (i, (i + 2).to_string())).collect::<Vec<_>>()));
        lines.push(format!(" label |{}|", beats.iter().skip(1).map(|b| b.label as char).collect::<String>()));
        let size = input.params["poincare_size"] as usize;
        let mut counts = vec![vec![0; size]; size];
        for pair in rr.windows(2) {
            let column = if high > low { rdiv((pair[0] - low) * (size - 1) as i64, high - low) as usize } else { 0 };
            counts[scale(pair[1], high, low, size)][column] += 1;
        }
        lines.push(format!("POINCARE points={} size={} min_ms={} max_ms={}", rr.len() - 1, size, low, high));
        for (row, counts) in counts.iter().enumerate() {
            let label = if row == 0 { high.to_string() } else if row == size - 1 { low.to_string() } else { String::new() };
            let marks: String = counts.iter().map(|&count| if count == 0 { '.' } else if count < 10 { (b'0' + count as u8) as char } else { '#' }).collect();
            lines.push(format!("{label:>6} |{marks}|"));
        }
        lines.push(axis(size, |_| false));
        let mut row = vec![b' '; size + 8];
        let low = low.to_string();
        let high = high.to_string();
        row[8..8 + low.len()].copy_from_slice(low.as_bytes());
        row[size + 8 - high.len()..size + 8].copy_from_slice(high.as_bytes());
        lines.push(String::from_utf8(row).unwrap());
    }
    for label in LABELS {
        let used: Vec<_> = beats.iter().filter(|b| b.label == label && b.sample >= 60 && b.sample <= input.ecg.len() - 100).collect();
        if used.is_empty() { lines.push(format!("TEMPLATE {} beats=0", label as char)); continue; }
        let baselines: Vec<i64> = used.iter().map(|b| input.ecg[b.sample - 60..b.sample - 50].iter().sum()).collect();
        let values: Vec<_> = (-60..100).map(|j| rdiv(used.iter().zip(&baselines).map(|(b, &baseline)| 10 * input.ecg[(b.sample as i64 + j) as usize] - baseline).sum(), 10 * used.len() as i64)).collect();
        let maximum = *values.iter().max().unwrap();
        let minimum = *values.iter().min().unwrap();
        lines.push(format!("TEMPLATE {} beats={} max_uv={} max_ms={} min_uv={} min_ms={} rows={rows}", label as char, used.len(), maximum, 5 * (values.iter().position(|&v| v == maximum).unwrap() as i64 - 60), minimum, 5 * (values.iter().position(|&v| v == minimum).unwrap() as i64 - 60)));
        let highs: Vec<_> = values.chunks(2).map(|pair| pair[0].max(pair[1])).collect();
        let lows: Vec<_> = values.chunks(2).map(|pair| pair[0].min(pair[1])).collect();
        lines.extend(waveform(&highs, &lows, rows));
        lines.push(axis(80, |i| i % 10 == 0));
        lines.push(label_row("ms", &(0..80).step_by(10).map(|i| (i, (10 * i as i64 - 300).to_string())).collect::<Vec<_>>()));
    }
    lines
}

fn rhythm(input: &Input, beats: &[Beat]) -> Vec<String> {
    let start = (input.params["strip_start_ms"] / 5) as usize;
    let length = (input.params["strip_ms"] / 5) as usize;
    let columns = length / 10;
    let rows = input.params["strip_rows"] as usize;
    let high: Vec<_> = input.ecg[start..start + length].chunks(10).map(|chunk| *chunk.iter().max().unwrap()).collect();
    let low: Vec<_> = input.ecg[start..start + length].chunks(10).map(|chunk| *chunk.iter().min().unwrap()).collect();
    let mut lines = vec![format!("RHYTHM start_ms={} end_ms={} columns={} rows={} max_uv={} min_uv={}", input.params["strip_start_ms"], input.params["strip_start_ms"] + input.params["strip_ms"], columns, rows, high.iter().max().unwrap(), low.iter().min().unwrap())];
    lines.extend(waveform(&high, &low, rows));
    lines.push(axis(columns, |i| i % 20 == 0));
    lines.push(label_row("s", &(0..columns).step_by(20).map(|i| (i, ((input.params["strip_start_ms"] + 50 * i as i64) / 1000).to_string())).collect::<Vec<_>>()));
    let mut detected = vec![b' '; columns];
    let mut referenced = vec![b' '; columns];
    for beat in beats.iter().filter(|b| start <= b.sample && b.sample < start + length) { detected[(beat.sample - start) / 10] = beat.label; }
    for annotation in input.annotations.iter().filter(|r| start <= r.sample && r.sample < start + length) { referenced[(annotation.sample - start) / 10] = annotation.label; }
    lines.push(format!(" beats |{}|", String::from_utf8(detected).unwrap()));
    lines.push(format!("  refs |{}|", String::from_utf8(referenced).unwrap()));
    lines
}

fn main() {
    let input = signal_io::read();
    let signals = filters::apply(&input.ecg);
    let detection = detect(&signals, &input.params);
    let (beats, matched) = beats(&input, &signals, &detection);
    let mut peak_lines = vec!["peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class".into()];
    for (i, peak) in detection.peaks.iter().enumerate() { peak_lines.push(format!("{},{},{},{},{},{},{},{},{}", i + 1, peak.time, peak.r, peak.integrated, peak.filtered, peak.slope, peak.threshold_i, peak.threshold_f, peak.class)); }
    let mut excerpt = vec!["sample,ecg,lowpass,bandpass,derivative,squared,integrated".into()];
    for n in 0..(input.params["excerpt_ms"] / 5) as usize { excerpt.push(format!("{},{},{},{},{},{},{}", n, input.ecg[n], signals.lowpass[n], signals.bandpass[n], signals.derivative[n], signals.squared[n], signals.integrated[n])); }
    fs::create_dir_all("output").unwrap();
    signal_io::write("beats.csv", &beat_lines(&input, &beats));
    signal_io::write("peaks.csv", &peak_lines);
    signal_io::write("matching.csv", &matching_lines(&input, &beats, &matched));
    signal_io::write("signals_excerpt.csv", &excerpt);
    signal_io::write("performance.txt", &performance(&input, &detection, &beats, &matched));
    signal_io::write("hrv.txt", &hrv_report(&input, &beats));
    signal_io::write("charts.txt", &charts(&input, &beats));
    signal_io::write("rhythm_strip.txt", &rhythm(&input, &beats));
}
