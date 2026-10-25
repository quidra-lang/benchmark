mod signals;
mod effects;
mod filters;
mod dynamics;
mod analysis;

use std::{collections::BTreeMap, fs, rc::Rc};
use signals::{floor_div, format_signal, peak, rdiv, read_signals, Signal};
use analysis::{clipped, crest, pitch_lag, rms, zero_crossings};

#[derive(Clone)]
enum Bound { Number(i64), Expression(&'static str) }
use Bound::{Expression as E, Number as N};
#[derive(Clone)]
struct ArgumentSpec { name: &'static str, low: Option<Bound>, high: Option<Bound> }
struct CommandSpec { fixed: Vec<ArgumentSpec>, repeated: Vec<ArgumentSpec>, minimum: usize, maximum: usize }
impl CommandSpec {
    fn accepts(&self, count: usize) -> bool {
        if count < self.fixed.len() { return false; } let extra = count - self.fixed.len(); let size = self.repeated.len();
        if size == 0 { extra == 0 } else { extra >= self.minimum * size && extra <= self.maximum * size && extra % size == 0 }
    }
    fn argument(&self, index: usize) -> &ArgumentSpec { if index < self.fixed.len() { &self.fixed[index] } else { &self.repeated[(index - self.fixed.len()) % self.repeated.len()] } }
}
fn name_arg(name: &'static str) -> ArgumentSpec { ArgumentSpec { name, low: None, high: None } }
fn ranged(name: &'static str, low: Bound, high: Bound) -> ArgumentSpec { ArgumentSpec { name, low: Some(low), high: Some(high) } }
fn arg(name: &'static str, low: i64, high: i64) -> ArgumentSpec { ranged(name, N(low), N(high)) }
fn cmd(fixed: Vec<ArgumentSpec>) -> CommandSpec { CommandSpec { fixed, repeated: Vec::new(), minimum: 0, maximum: 0 } }
fn rep(fixed: Vec<ArgumentSpec>, repeated: Vec<ArgumentSpec>, minimum: usize, maximum: usize) -> CommandSpec { CommandSpec { fixed, repeated, minimum, maximum } }
fn command_table() -> BTreeMap<&'static str, CommandSpec> {
    let dst = || name_arg("dst"); let src = || name_arg("src"); let rate = || arg("rate", 1000, 48000); let count = || arg("count", 1, 20000);
    let num = || arg("num", -65536, 65536); let den = || arg("den", 1, 65536); let attack = || arg("attack", 1, 32768); let release = || arg("release", 1, 32768);
    let min_hz = || ranged("min_hz", N(1), E("rate div 2 - 1")); let max_hz = || ranged("max_hz", E("min_hz + 1"), E("rate div 2")); let start = || ranged("start", N(0), E("L - 1"));
    let test = || vec![dst(), rate(), count(), ranged("pos", N(0), E("count - 1")), arg("amp", -32768, 32767)];
    BTreeMap::from([
        ("SET", rep(vec![name_arg("var"), arg("value", -10000000, 10000000)], vec![name_arg("op"), arg("operand", -10000000, 10000000)], 0, 1)),
        ("IMPULSE", cmd(test())), ("STEP", cmd(test())), ("NOISE", cmd(vec![dst(), rate(), count(), arg("seed", 1, 2147483646)])),
        ("GAIN", cmd(vec![dst(), src(), num(), den()])), ("MIX", rep(vec![dst(), den()], vec![src(), arg("weight", -65536, 65536)], 1, 8)),
        ("DELAY", cmd(vec![dst(), src(), arg("samples", 0, 20000)])), ("ECHO", cmd(vec![dst(), src(), arg("delay", 1, 20000), num(), den(), arg("tail", 0, 20000)])),
        ("RESAMPLE", cmd(vec![dst(), src(), arg("new_rate", 1000, 48000)])), ("FADE", cmd(vec![dst(), src(), ranged("in", N(0), E("L")), ranged("out", N(0), E("L"))])),
        ("TRIM", cmd(vec![dst(), src(), start(), ranged("count", N(1), E("L - start"))])), ("CONCAT", rep(vec![dst()], vec![src()], 2, 8)),
        ("FIR", rep(vec![dst(), src(), arg("divisor", 1, 1000000)], vec![arg("tap", -32768, 32767)], 1, 64)),
        ("BIQUAD", rep(vec![dst(), src()], ["b0", "b1", "b2", "a1", "a2"].iter().map(|&name| arg(name, -65536, 65536)).collect(), 1, 4)),
        ("MOVAVG", cmd(vec![dst(), src(), arg("width", 1, 1000)])), ("DCBLOCK", cmd(vec![dst(), src(), arg("num", 0, 65535), ranged("den", E("num + 1"), N(65536))])),
        ("NORMALIZE", cmd(vec![dst(), src(), arg("target", 1, 32767)])), ("GATE", cmd(vec![dst(), src(), arg("threshold", 1, 32768), arg("hold", 0, 20000)])),
        ("ENVELOPE", cmd(vec![dst(), src(), attack(), release()])), ("COMPRESS", cmd(vec![dst(), src(), arg("threshold", 1, 32767), arg("ratio_num", 1, 100), ranged("ratio_den", N(1), E("ratio_num")), attack(), release()])),
        ("ANALYZE", cmd(vec![src(), min_hz(), max_hz()])), ("COMPARE", cmd(vec![src(), src()])),
        ("EXPECT", cmd(vec![src(), name_arg("metric"), name_arg("op"), arg("value", -1000000000, 1000000000)])),
        ("SEGMENTS", cmd(vec![src(), arg("threshold", 1, 32768), arg("gap", 1, 20000), arg("min_length", 1, 20000)])),
        ("ONSETS", cmd(vec![src(), attack(), release(), arg("threshold", 1, 32767), arg("min_gap", 1, 20000)])),
        ("PITCHTRACK", cmd(vec![src(), ranged("frame", N(16), E("L")), ranged("hop", N(1), E("frame")), min_hz(), max_hz(), arg("threshold", 0, 32767)])),
        ("EXCERPT", cmd(vec![src(), start(), arg("count", 1, 1000)])),
        ("PLOT", cmd(vec![src(), start(), ranged("count", N(1), E("L - start")), ranged("columns", N(8), E("min(120, count)")), arg("half", 2, 20), attack(), release()])),
        ("METER", cmd(vec![src(), arg("block", 1, 20000)])), ("HISTOGRAM", cmd(vec![src(), arg("bins", 2, 64)])), ("TRACE", cmd(vec![src()])), ("SAVE", cmd(vec![src()])),
    ])
}
enum Value { Text(String), Integer(i64), Signal(Rc<Signal>) }
struct Arguments { values: Vec<Value>, sources: Vec<Rc<Signal>> }
impl Arguments {
    fn n(&self, index: usize) -> i64 { match &self.values[index] { Value::Integer(value) => *value, _ => unreachable!() } }
    fn u(&self, index: usize) -> usize { self.n(index) as usize }
    fn text(&self, index: usize) -> &str { match &self.values[index] { Value::Text(value) => value, _ => unreachable!() } }
    fn signal(&self, index: usize) -> &Rc<Signal> { match &self.values[index] { Value::Signal(value) => value, _ => unreachable!() } }
}
fn resolve_bound(bound: &Bound, known: &BTreeMap<&str, i64>, source: Option<&Signal>) -> i64 {
    match bound {
        N(value) => *value, E(expression) => match *expression {
            "count - 1" => known["count"] - 1, "min(120, count)" => known["count"].min(120), "min_hz + 1" => known["min_hz"] + 1, "num + 1" => known["num"] + 1,
            "L" => source.unwrap().samples.len() as i64, "L - 1" => source.unwrap().samples.len() as i64 - 1, "L - start" => source.unwrap().samples.len() as i64 - known["start"],
            "rate div 2" => source.unwrap().rate / 2, "rate div 2 - 1" => source.unwrap().rate / 2 - 1, _ => known[*expression],
        }
    }
}
fn valid_name(token: &str) -> bool {
    let bytes = token.as_bytes(); (1..=16).contains(&bytes.len()) && bytes[0].is_ascii_lowercase() && bytes[1..].iter().all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'_')
}
fn valid_integer(token: &str) -> bool {
    let digits = token.strip_prefix('-').unwrap_or(token);
    token != "-0" && (1..=10).contains(&digits.len()) && (digits.len() == 1 || !digits.starts_with('0')) && digits.bytes().all(|byte| byte.is_ascii_digit())
}
fn same_rate(sources: &[Rc<Signal>]) -> Result<(), String> { if sources.iter().any(|source| source.rate != sources[0].rate) { Err("rate mismatch".to_owned()) } else { Ok(()) } }
fn milliseconds(index: usize, rate: i64) -> i64 { index as i64 * 1000 / rate }
fn two_decimals(value: i64) -> String { format!("{}.{:02}", value / 100, value % 100) }
fn frequency_text(rate: i64, lag: usize) -> String { two_decimals(rdiv(100 * rate, lag as i64)) }
fn lag_range(rate: i64, min_hz: i64, max_hz: i64) -> (usize, usize) { (((rate + max_hz - 1) / max_hz) as usize, (rate / min_hz) as usize) }
fn metric_value(samples: &[i64], metric: &str) -> i64 {
    match metric { "samples" => samples.len() as i64, "peak" => peak(samples), "rms" => rms(samples), "sum" => samples.iter().sum(), "zero_crossings" => zero_crossings(samples) as i64, _ => clipped(samples) as i64 }
}
fn waveform_plot(source: &Signal, start: usize, count: usize, columns: usize, half: usize, attack: i64, release: i64) -> Vec<String> {
    let window = &source.samples[start..start + count]; let envelope = dynamics::envelope(&source.samples, attack, release); let levels = &envelope[start..start + count];
    let rows = 2 * half + 1; let scale = peak(window).max(1); let mut grid = vec![vec![' '; columns]; rows];
    let row_of = |value| rdiv((scale - value) * (rows - 1) as i64, 2 * scale) as usize;
    for c in 0..columns {
        let first = c * count / columns; let last = (c + 1) * count / columns; let part = &window[first..last];
        let top = row_of(*part.iter().max().unwrap()); let bottom = row_of(*part.iter().min().unwrap()); let level = scale.min(*levels[first..last].iter().max().unwrap());
        let upper = row_of(level); let lower = row_of(-level);
        for r in 0..rows { grid[r][c] = if r == upper || r == lower { '*' } else if top <= r && r <= bottom { '#' } else if r == half { '-' } else { ' ' }; }
    }
    let mut lines = vec![format!("PLOT {} rate={} start={start} count={count} columns={columns} rows={rows} scale={scale} attack={attack} release={release}", source.name, source.rate)];
    for (r, cells) in grid.iter().enumerate() {
        let label = if r == 0 { scale.to_string() } else if r == half { "0".to_owned() } else if r == rows - 1 { (-scale).to_string() } else { String::new() };
        lines.push(format!("{label:>6} |{}|", cells.iter().collect::<String>()));
    }
    let axis: String = (0..columns).map(|c| if c % 10 == 0 { '+' } else { '-' }).collect(); lines.push(format!("       +{axis}+"));
    let mut time = "    ms".to_owned();
    for c in (0..columns).step_by(10) { time.push_str(&" ".repeat((8 + c).saturating_sub(time.len()))); time.push_str(&milliseconds(start + c * count / columns, source.rate).to_string()); } lines.push(time); lines
}
fn meter_plot(source: &Signal, block: usize) -> Vec<String> {
    let length = source.samples.len(); let blocks = length.div_ceil(block); let mut lines = vec![format!("METER {} rate={} samples={length} block={block} blocks={blocks}", source.name, source.rate)];
    for (b, part) in source.samples.chunks(block).enumerate() {
        let p = peak(part); let q = rms(part); let np = rdiv(p * 40, 32768); let nq = rdiv(q * 40, 32768);
        let bar: String = (0..40).map(|j| if j < nq { '#' } else if j < np { '-' } else { ' ' }).collect();
        lines.push(format!("{:>6} |{bar}| peak={p} rms={q} clipped={}", milliseconds(b * block, source.rate), clipped(part)));
    } lines
}
fn histogram_plot(source: &Signal, bins: usize) -> Vec<String> {
    let mut counts = vec![0i64; bins]; for &x in &source.samples { counts[((x + 32768) * bins as i64 / 65536) as usize] += 1; }
    let edges: Vec<_> = (0..=bins).map(|b| ((b * 65536 + bins - 1) / bins) as i64 - 32768).collect(); let largest = *counts.iter().max().unwrap();
    let mut lines = vec![format!("HISTOGRAM {} rate={} samples={} bins={bins} max={largest}", source.name, source.rate, source.samples.len())];
    for b in 0..bins { lines.push(format!("{:>6} {:>6} {:>5} |{}", edges[b], edges[b + 1] - 1, counts[b], "#".repeat(rdiv(counts[b] * 50, largest) as usize))); } lines
}
fn pitch_row(rate: i64, start: usize, level: i64, lag: Option<usize>, low: usize, high: usize) -> String {
    let prefix = format!("{:>6} |", milliseconds(start, rate));
    match lag {
        None => format!("{prefix}{}| unvoiced rms={level}", " ".repeat(41)),
        Some(lag) => { let position = if high > low { rdiv((high - lag) as i64 * 40, (high - low) as i64) as usize } else { 0 };
            format!("{prefix}{}o{}| lag={lag} hz={} rms={level}", " ".repeat(position), " ".repeat(40 - position), frequency_text(rate, lag)) }
    }
}
fn trace_lines(signal: &Signal, depth: usize, lines: &mut Vec<String>) { lines.push(format!("{}{} <- {}", " ".repeat(2 * depth), signal.name, signal.origin)); for ingredient in &signal.ingredients { trace_lines(ingredient, depth + 1, lines); } }

struct Pipeline {
    signals: BTreeMap<String, Rc<Signal>>,
    variables: BTreeMap<String, i64>,
    commands: BTreeMap<&'static str, CommandSpec>,
    log: Vec<String>,
    analysis: Vec<String>,
    excerpts: Vec<String>,
    waveforms: Vec<String>,
    saved: Vec<String>,
    steps: usize,
    errors: usize,
    passed: usize,
    failed: usize,
}
impl Pipeline {
    fn new() -> Self {
        let mut signals = BTreeMap::new(); let mut log = Vec::new();
        for signal in read_signals() { log.push(format!("load {} rate={} samples={} peak={}", signal.name, signal.rate, signal.samples.len(), peak(&signal.samples))); signals.insert(signal.name.clone(), signal); }
        Self { signals, variables: BTreeMap::new(), commands: command_table(), log, analysis: vec!["signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz".to_owned()], excerpts: Vec::new(), waveforms: Vec::new(), saved: Vec::new(), steps: 0, errors: 0, passed: 0, failed: 0 }
    }
    fn integer_value(&self, token: &str) -> Result<i64, String> {
        if let Some(name) = token.strip_prefix('$') { return self.variables.get(name).copied().ok_or_else(|| format!("undefined variable {token}")); }
        if !valid_integer(token) { return Err(format!("bad integer {token}")); } Ok(token.parse().unwrap())
    }
    fn parse(&self, name: &str, command: &CommandSpec, tokens: &[&str]) -> Result<Arguments, String> {
        let mut values = Vec::new(); let mut sources = Vec::<Rc<Signal>>::new(); let mut known = BTreeMap::new();
        for (j, &token) in tokens.iter().enumerate() {
            let argument = command.argument(j); let kind = argument.name;
            let value = match kind {
                "dst" | "var" => { if !valid_name(token) { return Err(format!("bad name {token}")); } Value::Text(token.to_owned()) }
                "src" => { let source = self.signals.get(token).ok_or_else(|| format!("unknown signal {token}"))?.clone(); sources.push(source.clone()); Value::Signal(source) }
                "metric" => { if !["samples", "peak", "rms", "sum", "zero_crossings", "clipped"].contains(&token) { return Err(format!("unknown metric {token}")); } Value::Text(token.to_owned()) }
                "op" => {
                    let operators: &[&str] = if name == "SET" { &["+", "-", "*", "/"] } else { &["eq", "ne", "lt", "le", "gt", "ge"] };
                    if !operators.contains(&token) { return Err(format!("unknown operator {token}")); } Value::Text(token.to_owned())
                }
                _ => {
                    let number = self.integer_value(token)?; let source = sources.first().map(Rc::as_ref);
                    let low = resolve_bound(argument.low.as_ref().unwrap(), &known, source); let high = resolve_bound(argument.high.as_ref().unwrap(), &known, source);
                    if number < low || number > high { return Err(format!("{kind} out of range")); } known.insert(kind, number); Value::Integer(number)
                }
            }; values.push(value);
        } Ok(Arguments { values, sources })
    }
    fn generate(&mut self, number: usize, command: &str, v: &Arguments) -> Result<String, String> {
        let sources = &v.sources; let x = sources.first().map_or(&[][..], |source| source.samples.as_slice());
        let mut rate = sources.first().map_or_else(|| v.n(1), |source| source.rate); let mut extras = Vec::new();
        let samples = match command {
            "IMPULSE" => signals::impulse(v.u(2), v.u(3), v.n(4)), "STEP" => signals::step(v.u(2), v.u(3), v.n(4)), "NOISE" => signals::noise(v.u(2), v.n(3)),
            "GAIN" => { let (y, count) = effects::gain(x, v.n(2), v.n(3)); extras.push(format!("clipped={count}")); y }
            "MIX" => {
                same_rate(sources)?; let tracks: Vec<_> = sources.iter().map(|source| source.samples.as_slice()).collect(); let weights: Vec<_> = (3..v.values.len()).step_by(2).map(|j| v.n(j)).collect();
                let (y, count) = effects::mix(&tracks, &weights, v.n(1)); extras.push(format!("clipped={count}")); y
            }
            "DELAY" => { if x.len() + v.u(2) > 20000 { return Err("result too long".to_owned()); } effects::delay(x, v.u(2)) }
            "ECHO" => {
                if v.n(3).abs() >= v.n(4) { return Err("unstable feedback".to_owned()); } if x.len() + v.u(5) > 20000 { return Err("result too long".to_owned()); }
                let (y, count) = effects::echo(x, v.u(2), v.n(3), v.n(4), v.u(5)); extras.push(format!("clipped={count}")); y
            }
            "RESAMPLE" => {
                if effects::resampled_length(x.len(), rate, v.n(2)) > 20000 { return Err("result too long".to_owned()); }
                let y = effects::resample(x, rate, v.n(2)); rate = v.n(2); y
            }
            "FADE" => effects::fade(x, v.u(2), v.u(3)), "TRIM" => x[v.u(2)..v.u(2) + v.u(3)].to_vec(),
            "CONCAT" => {
                same_rate(sources)?; let length: usize = sources.iter().map(|source| source.samples.len()).sum(); if length > 20000 { return Err("result too long".to_owned()); }
                sources.iter().flat_map(|source| source.samples.iter().copied()).collect()
            }
            "FIR" => { let taps: Vec<_> = (3..v.values.len()).map(|j| v.n(j)).collect(); let (y, count) = filters::fir(x, v.n(2), &taps); extras.push(format!("clipped={count}")); y }
            "BIQUAD" => {
                let sections: Vec<_> = (2..v.values.len()).step_by(5).map(|j| [v.n(j), v.n(j + 1), v.n(j + 2), v.n(j + 3), v.n(j + 4)]).collect();
                let (y, count) = filters::biquad(x, &sections); extras.push(format!("sections={}", sections.len())); extras.push(format!("clipped={count}")); y
            }
            "MOVAVG" => filters::moving_average(x, v.u(2)),
            "DCBLOCK" => { let (y, count) = filters::dc_block(x, v.n(2), v.n(3)); extras.push(format!("clipped={count}")); y }
            "NORMALIZE" => { let (y, source_peak) = dynamics::normalize(x, v.n(2)); extras.push(format!("source_peak={source_peak}")); y }
            "GATE" => { let (y, muted) = dynamics::gate(x, v.n(2), v.u(3)); extras.push(format!("muted={muted}")); y }
            "ENVELOPE" => dynamics::envelope(x, v.n(2), v.n(3)),
            "COMPRESS" => { let (y, minimum, reduced) = dynamics::compress(x, v.n(2), v.n(3), v.n(4), v.n(5), v.n(6)); extras.push(format!("min_gain={minimum}")); extras.push(format!("reduced={reduced}")); y }
            _ => unreachable!(),
        };
        let dst = v.text(0); let details = format!("{dst} rate={rate} samples={} peak={} sum={}{}", samples.len(), peak(&samples), samples.iter().sum::<i64>(), if extras.is_empty() { String::new() } else { format!(" {}", extras.join(" ")) });
        self.signals.insert(dst.to_owned(), Rc::new(Signal { name: dst.to_owned(), rate, samples, origin: format!("line {number} {command}"), ingredients: sources.clone() })); Ok(details)
    }
    fn execute(&mut self, number: usize, name: &str, tokens: &[&str]) -> Result<Vec<String>, String> {
        let command = self.commands.get(name).ok_or_else(|| format!("unknown command {name}"))?;
        if !command.accepts(tokens.len()) { return Err("wrong number of arguments".to_owned()); } let v = self.parse(name, command, tokens)?;
        if ["IMPULSE", "STEP", "NOISE", "GAIN", "MIX", "DELAY", "ECHO", "RESAMPLE", "FADE", "TRIM", "CONCAT", "FIR", "BIQUAD", "MOVAVG", "DCBLOCK", "NORMALIZE", "GATE", "ENVELOPE", "COMPRESS"].contains(&name) { return Ok(vec![self.generate(number, name, &v)?]); }
        if name == "SET" {
            let mut result = v.n(1);
            if v.values.len() == 4 {
                if v.text(2) == "/" && v.n(3) == 0 { return Err("division by zero".to_owned()); }
                result = match v.text(2) { "+" => result + v.n(3), "-" => result - v.n(3), "*" => result * v.n(3), _ => floor_div(result, v.n(3)) };
                if result.abs() > 10000000 { return Err("value out of range".to_owned()); }
            }
            self.variables.insert(v.text(0).to_owned(), result); return Ok(vec![format!("{}={result}", v.text(0))]);
        }
        let source = v.signal(0); let x = &source.samples; let length = x.len(); let rate = source.rate;
        let lines = match name {
            "ANALYZE" => {
                let (low, high) = lag_range(rate, v.n(1), v.n(2)); if low > high { return Err("empty lag range".to_owned()); } if high >= length { return Err("signal too short".to_owned()); }
                let lag = pitch_lag(x, low, high); let lag_text = lag.map_or_else(|| "none".to_owned(), |lag| lag.to_string()); let hz = lag.map_or_else(|| "none".to_owned(), |lag| frequency_text(rate, lag));
                self.analysis.push(format!("{},{},{},{},{},{},{lag_text},{hz}", source.name, peak(x), rms(x), zero_crossings(x), clipped(x), crest(x))); vec![format!("{} lags={low}-{high}", source.name)]
            }
            "COMPARE" => {
                same_rate(&v.sources)?; let b = &v.signal(1).samples; let mut differing = 0; let mut maximum: i64 = 0; let mut first = None; let mut energy = 0;
                for i in 0..length.max(b.len()) { let difference = x.get(i).unwrap_or(&0) - b.get(i).unwrap_or(&0); if difference != 0 { differing += 1; first.get_or_insert(i); } maximum = maximum.max(difference.abs()); energy += difference * difference; }
                vec![format!("{} {} differing={differing} max_diff={maximum} first={} error_energy={energy}", source.name, v.signal(1).name, first.map_or_else(|| "none".to_owned(), |index| index.to_string()))]
            }
            "EXPECT" => {
                let measured = metric_value(x, v.text(1)); let value = v.n(3);
                let pass = match v.text(2) { "eq" => measured == value, "ne" => measured != value, "lt" => measured < value, "le" => measured <= value, "gt" => measured > value, _ => measured >= value };
                if pass { self.passed += 1; } else { self.failed += 1; } vec![format!("{} {}={measured} {} {value} {}", source.name, v.text(1), v.text(2), if pass { "pass" } else { "fail" })]
            }
            "SEGMENTS" => {
                let mut found = Vec::<(usize, usize)>::new();
                for (i, &sample) in x.iter().enumerate() {
                    if sample.abs() < v.n(1) { continue; }
                    if let Some(last) = found.last_mut() { if i - last.1 <= v.u(2) { last.1 = i; continue; } } found.push((i, i));
                }
                found.retain(|&(start, end)| end - start + 1 >= v.u(3)); let mut lines = vec![format!("{} segments={}", source.name, found.len())];
                for (j, (start, end)) in found.into_iter().enumerate() {
                    let part = &x[start..=end]; lines.push(format!("  segment {} start={start} end={end} start_ms={} end_ms={} peak={} rms={} crossings={}", j + 1, milliseconds(start, rate), milliseconds(end, rate), peak(part), rms(part), zero_crossings(part)));
                } lines
            }
            "ONSETS" => {
                let levels = dynamics::envelope(x, v.n(1), v.n(2)); let mut onsets = Vec::new();
                for (n, &level) in levels.iter().enumerate() {
                    if level >= v.n(3) && (n == 0 || levels[n - 1] < v.n(3)) && onsets.last().is_none_or(|&last| n - last >= v.u(4)) { onsets.push(n); }
                }
                let intervals: Vec<_> = onsets.windows(2).map(|pair| pair[1] - pair[0]).collect();
                let tempo = if intervals.is_empty() { "none".to_owned() } else { let mut ordered = intervals.clone(); ordered.sort_unstable(); two_decimals(rdiv(6000 * rate, ordered[(onsets.len() - 2) / 2] as i64)) };
                let mut lines = vec![format!("{} onsets={} tempo={tempo}", source.name, onsets.len())];
                for (j, &n) in onsets.iter().enumerate() { lines.push(format!("  onset {} sample={n} ms={} interval={}", j + 1, milliseconds(n, rate), if j == 0 { "none".to_owned() } else { intervals[j - 1].to_string() })); } lines
            }
            "PITCHTRACK" => {
                let (low, high) = lag_range(rate, v.n(3), v.n(4)); if low > high { return Err("empty lag range".to_owned()); } if high >= v.u(1) { return Err("frame too short".to_owned()); }
                let count = (length - v.u(1)) / v.u(2) + 1; let mut rows = Vec::new(); let mut voiced = 0;
                for t in 0..count {
                    let part = &x[t * v.u(2)..t * v.u(2) + v.u(1)]; let level = rms(part); let lag = if level < v.n(5) { None } else { pitch_lag(part, low, high) };
                    if lag.is_some() { voiced += 1; } rows.push(pitch_row(rate, t * v.u(2), level, lag, low, high));
                }
                self.waveforms.push(format!("PITCHTRACK {} rate={rate} frame={} hop={} lags={low}-{high} threshold={} frames={count} voiced={voiced}", source.name, v.n(1), v.n(2), v.n(5))); self.waveforms.extend(rows); vec![format!("{} frames={count} voiced={voiced}", source.name)]
            }
            "EXCERPT" => {
                let start = v.u(1); let count = v.u(2).min(length - start); self.excerpts.push(format!("EXCERPT {} rate={rate} samples={length} start={start} count={count}", source.name));
                for (j, part) in x[start..start + count].chunks(8).enumerate() {
                    let values = part.iter().map(|sample| format!(" {sample:>6}")).collect::<String>(); self.excerpts.push(format!("{:>5}:{values}", start + 8 * j));
                } vec![format!("{} start={start} count={count}", source.name)]
            }
            "PLOT" => { self.waveforms.extend(waveform_plot(source, v.u(1), v.u(2), v.u(3), v.u(4), v.n(5), v.n(6))); vec![format!("{} start={} count={} columns={} rows={}", source.name, v.n(1), v.n(2), v.n(3), 2 * v.n(4) + 1)] }
            "METER" => { self.waveforms.extend(meter_plot(source, v.u(1))); vec![format!("{} block={}", source.name, v.n(1))] }
            "HISTOGRAM" => { self.waveforms.extend(histogram_plot(source, v.u(1))); vec![format!("{} bins={}", source.name, v.n(1))] }
            "TRACE" => { let mut lines = vec![source.name.clone()]; trace_lines(source, 1, &mut lines); lines }
            "SAVE" => { self.saved.extend(format_signal(source)); vec![format!("{} samples={length}", source.name)] }
            _ => unreachable!(),
        }; Ok(lines)
    }
    fn run(mut self) {
        let script = fs::read_to_string("input/pipeline.txt").unwrap();
        for (j, line) in script.lines().enumerate() {
            if line.is_empty() || line.starts_with('#') { continue; } let mut parts = line.split(' '); let name = parts.next().unwrap(); let tokens: Vec<_> = parts.collect(); let number = j + 1;
            match self.execute(number, name, &tokens) {
                Ok(lines) => { self.log.push(format!("line {number}: {name} {}", lines[0])); self.log.extend(lines.into_iter().skip(1)); self.steps += 1; }
                Err(error) => { self.log.push(format!("line {number}: error: {error}")); self.errors += 1; }
            }
        }
        for (name, signal) in &self.signals { self.log.push(format!("signal {name} rate={} samples={} peak={} rms={}", signal.rate, signal.samples.len(), peak(&signal.samples), rms(&signal.samples))); }
        self.log.push(format!("summary steps={} errors={} signals={} passed={} failed={}", self.steps, self.errors, self.signals.len(), self.passed, self.failed));
        fs::create_dir_all("output").unwrap();
        for (name, lines) in [("log.txt", self.log), ("analysis.csv", self.analysis), ("excerpts.txt", self.excerpts), ("waveforms.txt", self.waveforms), ("signals_out.txt", self.saved)] {
            let text = if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }; fs::write(format!("output/{name}"), text).unwrap();
        }
    }
}

fn main() { Pipeline::new().run(); }
