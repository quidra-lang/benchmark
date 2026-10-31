mod trace_io;
mod hazards;
mod pipeline;
mod predictors;
mod report;

use trace_io::{Instruction, Config, CLASSES};
use pipeline::{Run, CAUSES};
use report::{decimal, percentage, fraction, hex, Row, Span};
use std::{collections::{BTreeMap, BTreeSet}, io};

const MISPREDICTIONS: [&str; 3] = ["direction", "btb_miss", "wrong_target"];
const STAGES: [&str; 5] = ["IF", "ID", "EX", "MEM", "WB"];

fn check(line: &str, number: usize, first: &BTreeMap<i64, usize>, accepted: &[Instruction]) -> Result<Instruction, &'static str> {
    let words: Vec<&str> = line.split(' ').collect();
    if words.len() != 8 || words.iter().any(|s| s.is_empty()) { return Err("fields"); }
    let pc = trace_io::hex(words[0]).filter(|p| p % 4 == 0).ok_or("pc")?;
    let class = CLASSES.iter().position(|&c| c == words[1]).ok_or("class")?;
    let rd = trace_io::register(words[2]).ok_or("register")?;
    let rs1 = trace_io::register(words[3]).ok_or("register")?;
    let rs2 = trace_io::register(words[4]).ok_or("register")?;
    let operands = match class {
        0 => rd.is_some() && rs1.is_some(),
        1 => rd.is_some() && rs1.is_some() && rs2.is_some(),
        2 => rd.is_some() && rs1.is_some() && rs2.is_none(),
        3 => rd.is_none() && rs1.is_some() && rs2.is_some(),
        4 => rd.is_none() && rs1.is_some(),
        5 => rs2.is_none(),
        _ => rd.is_none() && rs1.is_none() && rs2.is_none(),
    };
    if !operands { return Err("operands"); }
    let outcome = match class { 4 => words[5] == "T" || words[5] == "N", 5 => words[5] == "T", _ => words[5] == "-" };
    if !outcome { return Err("taken"); }
    let target = if class == 4 || class == 5 {
        Some(trace_io::hex(words[6]).filter(|&t| t % 4 == 0 && t != pc + 4).ok_or("target")?)
    } else { if words[6] != "-" { return Err("target"); } None };
    let address = if class == 2 || class == 3 {
        Some(trace_io::hex(words[7]).filter(|a| a % 4 == 0).ok_or("address")?)
    } else { if words[7] != "-" { return Err("address"); } None };
    if let Some(&index) = first.get(&pc) {
        let before = &accepted[index];
        if before.class != class || before.rd != rd || before.rs1 != rs1 || before.rs2 != rs2
            || ((class == 4 || (class == 5 && rs1.is_none())) && before.target != target) { return Err("conflict"); }
    }
    Ok(Instruction { pc, class, rd, rs1, rs2, taken: words[5] == "T", target, address, line: number })
}

struct Prediction {
    next: i64,
    kind: Option<usize>,
}

struct Predictions {
    values: Vec<Prediction>,
    btb_hits: usize,
    ras_predictions: usize,
    ras_correct: usize,
}

fn predict(instructions: &[Instruction], config: &Config, index: usize) -> Predictions {
    let definition = &config.predictors[index];
    let mut btb = predictors::Btb::new(config.btb);
    let mut ras = predictors::Ras::new(config.ras);
    let mut direction = predictors::Direction::new(definition);
    let mut result = Predictions { values: Vec::new(), btb_hits: 0, ras_predictions: 0, ras_correct: 0 };
    for instruction in instructions {
        if !instruction.control() { result.values.push(Prediction { next: instruction.pc + 4, kind: None }); continue; }
        let mut candidate = btb.lookup(instruction.pc);
        if candidate.is_some() { result.btb_hits += 1; }
        if instruction.returns() {
            if let Some(value) = ras.pop() { candidate = Some(value); result.ras_predictions += 1; if value == instruction.target.unwrap() { result.ras_correct += 1; } }
        }
        if instruction.call() { ras.push(instruction.pc + 4); }
        let taken = if instruction.class == 4 { direction.predict(instruction.pc, instruction.target.unwrap()) } else { true };
        let next = if definition.scheme == "PERFECT" { instruction.next() }
            else if instruction.class == 5 || taken { candidate.unwrap_or(instruction.pc + 4) } else { instruction.pc + 4 };
        let kind = if next == instruction.next() { None } else if instruction.class == 4 && taken != instruction.taken { Some(0) }
            else if candidate.is_none() { Some(1) } else { Some(2) };
        result.values.push(Prediction { next, kind });
        if instruction.class == 4 { direction.update(instruction.pc, instruction.taken); }
        if instruction.taken { btb.insert(instruction.pc, instruction.target.unwrap()); }
    }
    result
}

fn prediction_accuracy(instructions: &[Instruction], predictions: &Predictions, class: Option<usize>) -> String {
    let indices: Vec<usize> = (0..instructions.len()).filter(|&i| instructions[i].control() && class.map_or(true, |c| c == instructions[i].class)).collect();
    let correct = indices.iter().filter(|&&i| predictions.values[i].kind.is_none()).count();
    percentage(correct, indices.len())
}

fn span(start: usize, end: usize, first: char, rest: char, stage: Option<usize>) -> Span {
    Span { start, end, first, rest, stage }
}

fn diagram(instructions: &[Instruction], predictions: &Predictions, variant: &trace_io::Variant, run: &Run) -> Vec<Row> {
    let mut annotations = vec![String::new(); instructions.len()];
    for stall in &run.stalls { if let Some(i) = stall.waiting { annotations[i] += &format!(" {} {}", CAUSES[stall.cause], stall.cycles); } }
    let mut rows = Vec::new();
    for (i, instruction) in instructions.iter().enumerate() {
        let t = run.timing[i];
        if let Some(kind) = predictions.values[i].kind { annotations[i] += &format!(" mispredict {}", MISPREDICTIONS[kind]); }
        rows.push(Row { instruction: Some(i), pc: instruction.pc, class: CLASSES[instruction.class].into(), annotation: annotations[i].clone(), spans: vec![
            span(t.f, t.d - 1, 'F', '*', Some(0)), span(t.d, t.x - 1, 'D', '*', Some(1)), span(t.x, t.m - 1, 'X', 'X', Some(2)),
            span(t.m, t.m, 'M', 'M', Some(3)), span(t.w, t.w, 'W', 'W', Some(4))] });
        if predictions.values[i].kind.is_some() {
            let mut spans = vec![span(t.d, t.x - 1, 'F', '*', Some(0))];
            let id = hazards::id_resolved(instruction, variant);
            let cancel = t.x + usize::from(!id);
            if !id { spans.push(span(t.x, t.x, 'D', 'D', Some(1))); }
            spans.push(span(cancel, cancel, 'x', 'x', None));
            rows.push(Row { instruction: None, pc: predictions.values[i].next, class: "FLUSH".into(), annotation: String::new(), spans });
            if !id {
                rows.push(Row { instruction: None, pc: predictions.values[i].next + 4, class: "FLUSH".into(), annotation: String::new(),
                    spans: vec![span(t.x, t.x, 'F', 'F', Some(0)), span(t.x + 1, t.x + 1, 'x', 'x', None)] });
            }
        }
    }
    rows
}

fn register(value: Option<usize>) -> String {
    value.map_or("-".into(), |r| format!("r{}", r))
}

fn main() -> io::Result<()> {
    let (raw, config) = trace_io::read()?;
    let mut instructions = Vec::new();
    let mut first = BTreeMap::new();
    let mut rejected = Vec::new();
    for (line, text) in raw.iter().enumerate() {
        match check(text, line + 1, &first, &instructions) {
            Ok(instruction) => { first.entry(instruction.pc).or_insert(instructions.len()); instructions.push(instruction); }
            Err(reason) => rejected.push(format!("reject line {} {}", line + 1, reason)),
        }
    }
    let n = instructions.len();
    let mut gaps = Vec::new();
    for i in 1..n { if instructions[i].pc != instructions[i - 1].next() { gaps.push(format!("gap line {} expected {} found {}", instructions[i].line, hex(instructions[i - 1].next()), hex(instructions[i].pc))); } }
    let sources = hazards::dependencies(&instructions);
    let predictions: Vec<Predictions> = (0..config.predictors.len()).map(|i| predict(&instructions, &config, i)).collect();
    let flags: Vec<Vec<bool>> = predictions.iter().map(|p| p.values.iter().map(|p| p.kind.is_some()).collect()).collect();
    let runs: Vec<Vec<Run>> = config.variants.iter().map(|v| flags.iter().map(|f| pipeline::simulate(&instructions, &sources, v, f)).collect()).collect();
    let primary_variant = config.variants.iter().position(|v| v.name == config.primary.0).unwrap();
    let primary_predictor = config.predictors.iter().position(|p| p.name == config.primary.1).unwrap();
    let variant = &config.variants[primary_variant];
    let prediction = &predictions[primary_predictor];
    let run = &runs[primary_variant][primary_predictor];
    let cycle_count = run.cycles;
    let rows = diagram(&instructions, prediction, variant, run);
    let (start, end) = config.window;
    let mut pipeline_lines = vec![format!("pipeline variant={} predictor={} cycles {}-{}", variant.name, config.predictors[primary_predictor].name, start, end), report::digits(start, end)];
    let mut written = 0;
    let mut stall_cells = 0;
    let mut flushed = 0;
    for row in &rows {
        if let Some(line) = row.format(start, end) {
            written += 1;
            for c in start..=end { match row.cell(c).0 { '*' => stall_cells += 1, 'x' => flushed += 1, _ => {} } }
            pipeline_lines.push(line);
        }
    }
    pipeline_lines.extend([format!("rows {} completed {} stall_cells {} flushed {}", written, run.timing.iter().filter(|t| t.w >= start && t.w <= end).count(), stall_cells, flushed),
        String::new(), "stages".into(), "cycle IF ID EX MEM WB".into()]);
    for cycle in start..=end {
        let mut contents = vec![".".to_owned(); 5];
        for row in &rows {
            if let Some(stage) = row.cell(cycle).1 { contents[stage] = row.instruction.map_or("w".into(), |i| (i + 1).to_string()); }
        }
        pipeline_lines.push(format!("{} {}", cycle, contents.join(" ")));
    }
    let mut occupancy = [[0usize; 2]; 5];
    for row in &rows {
        for span in &row.spans { if let Some(stage) = span.stage { occupancy[stage][usize::from(row.instruction.is_none())] += span.end - span.start + 1; } }
    }
    let mut per_pc: BTreeMap<i64, [usize; 4]> = BTreeMap::new();
    let mut dependencies: BTreeMap<(i64, i64, usize), (usize, usize)> = BTreeMap::new();
    let mut class_stalls = [0usize; 7];
    for stall in &run.stalls {
        let responsible = &instructions[stall.responsible];
        per_pc.entry(responsible.pc).or_insert([0; 4])[stall.cause] += stall.cycles;
        class_stalls[responsible.class] += stall.cycles;
        if stall.cause >= 2 {
            let producer = instructions[stall.producer.unwrap()].pc;
            let waiting = instructions[stall.waiting.unwrap()].pc;
            let entry = dependencies.entry((producer, waiting, stall.cause)).or_insert((0, 0));
            entry.0 += stall.cycles;
            entry.1 += 1;
        }
    }
    let mut mix = [0usize; 7];
    for instruction in &instructions { mix[instruction.class] += 1; }
    let mut parts: Vec<Vec<String>> = Vec::new();
    let mut lines = vec![format!("input lines {} accepted {} rejected {} gaps {}", raw.len(), n, rejected.len(), gaps.len())];
    lines.extend(rejected);
    lines.extend(gaps);
    parts.push(lines);
    let all_sources = sources.iter().map(Vec::len).sum::<usize>();
    let mut distances = [0usize; 5];
    let mut with_producer = 0;
    for (i, sources) in sources.iter().enumerate() { for source in sources { if let Some(p) = source.producer { with_producer += 1; distances[(i - p - 1).min(4)] += 1; } } }
    let addresses: BTreeSet<i64> = instructions.iter().filter_map(|i| i.address).collect();
    parts.push(vec!["trace".into(), format!("instructions {}", n), format!("static_instructions {}", first.len()),
        format!("mix {}", (0..7).map(|i| format!("{} {}", CLASSES[i], mix[i])).collect::<Vec<_>>().join(" ")),
        format!("branches {} taken {} backward {}", mix[4], instructions.iter().filter(|i| i.class == 4 && i.taken).count(), instructions.iter().filter(|i| i.class == 4 && i.target.unwrap() < i.pc).count()),
        format!("jumps {} indirect {} link {}", mix[5], instructions.iter().filter(|i| i.class == 5 && i.rs1.is_some()).count(), instructions.iter().filter(|i| i.class == 5 && i.rd.is_some()).count()),
        format!("static_control branches {} jumps {}", first.values().filter(|&&i| instructions[i].class == 4).count(), first.values().filter(|&&i| instructions[i].class == 5).count()),
        format!("memory loads {} stores {} distinct_addresses {}", mix[2], mix[3], addresses.len()), format!("operands {} with_producer {} distance 1 {} 2 {} 3 {} 4 {} 5+ {}", all_sources, with_producer, distances[0], distances[1], distances[2], distances[3], distances[4])]);
    let mut lines = vec!["prediction".into()];
    for (i, predictor) in config.predictors.iter().enumerate() {
        let p = &predictions[i];
        let mut kinds = [0usize; 3];
        for prediction in &p.values { if let Some(kind) = prediction.kind { kinds[kind] += 1; } }
        lines.push(format!("{} {} bits {} control {} mispredicted {} accuracy {} branches {} jumps {} direction {} btb_miss {} wrong_target {}", predictor.name, predictor.scheme, predictors::storage(predictor), mix[4] + mix[5], kinds.iter().sum::<usize>(),
            prediction_accuracy(&instructions, p, None), prediction_accuracy(&instructions, p, Some(4)), prediction_accuracy(&instructions, p, Some(5)), kinds[0], kinds[1], kinds[2]));
    }
    lines.extend([format!("btb entries {} lookups {} hits {} misses {}", config.btb, mix[4] + mix[5], predictions[0].btb_hits, mix[4] + mix[5] - predictions[0].btb_hits),
        format!("ras depth {} calls {} returns {} predicted {} correct {}", config.ras, instructions.iter().filter(|i| i.call()).count(), instructions.iter().filter(|i| i.returns()).count(), predictions[0].ras_predictions, predictions[0].ras_correct)]);
    parts.push(lines);
    let stalls: usize = run.totals.iter().sum();
    let refetch = rows.iter().filter(|r| r.instruction.is_none()).count();
    let mut lengths = [0usize; 5];
    for i in 1..n { let gap = run.timing[i].x - run.timing[i - 1].x - 1; if gap > 0 { lengths[(gap - 1).min(4)] += 1; } }
    let mut finish = vec![0usize; n];
    for i in 0..n {
        let start = sources[i].iter().filter_map(|s| s.producer.map(|p| finish[p])).max().unwrap_or(0);
        finish[i] = start + match instructions[i].class { 2 => 2, 1 => variant.multiply, _ => 1 };
    }
    let dataflow = *finish.iter().max().unwrap();
    parts.push(vec![format!("timing variant={} predictor={}", variant.name, config.predictors[primary_predictor].name),
        format!("forwarding {} branch_stage {} mul_latency {}", if variant.forwarding { "on" } else { "off" }, if variant.id { "ID" } else { "EX" }, variant.multiply),
        format!("cycles {}", cycle_count), format!("cpi {} {}", fraction(cycle_count, n), decimal(cycle_count, n)), format!("ipc {}", decimal(n, cycle_count)),
        format!("stall_cycles total {} control {} structural {} load_use {} raw {}", stalls, run.totals[0], run.totals[1], run.totals[2], run.totals[3]),
        format!("stall_events control {} structural {} load_use {} raw {}", run.events[0], run.events[1], run.events[2], run.events[3]), format!("flushed {}", refetch),
        format!("cycle_check {} + 4 + {} = {}", n, stalls, n + 4 + stalls),
        format!("cpi_stack base 1.0000 fill {} control {} structural {} load_use {} raw {}", decimal(4, n), decimal(run.totals[0], n), decimal(run.totals[1], n), decimal(run.totals[2], n), decimal(run.totals[3], n)),
        format!("stall_lengths 1 {} 2 {} 3 {} 4 {} 5+ {}", lengths[0], lengths[1], lengths[2], lengths[3], lengths[4]), format!("dataflow height {} ilp {}", dataflow, decimal(n, dataflow))]);
    let mut lines = vec!["whatif".into()];
    let mut variants = vec![variant.clone(); 4];
    variants[1].multiply = 1;
    variants[2].forwarding = !variant.forwarding;
    variants[3].id = !variant.id;
    let names = ["perfect_prediction", "single_cycle_mul", if variant.forwarding { "forwarding_off" } else { "forwarding_on" }, if variant.id { "branch_stage_EX" } else { "branch_stage_ID" }];
    for i in 0..4 {
        let flags = if i == 0 { vec![false; n] } else { flags[primary_predictor].clone() };
        let cycles = pipeline::simulate(&instructions, &sources, &variants[i], &flags).cycles;
        lines.push(format!("{} cycles {} saved {} speedup {}", names[i], cycles, cycle_count as i64 - cycles as i64, decimal(cycle_count, cycles)));
    }
    parts.push(lines);
    let mut lines = vec!["classes".into()];
    for i in 0..7 { lines.push(format!("{} count {} stall_cycles {} per_instruction {}", CLASSES[i], mix[i], class_stalls[i], decimal(class_stalls[i], mix[i]))); }
    parts.push(lines);
    let mut forwarding = [0usize; 3];
    for i in 0..n {
        for source in &sources[i] {
            let path = source.producer.map_or(0, |p| hazards::forwarding(&instructions[i], &run.timing[p], &run.timing[i], variant));
            forwarding[path] += 1;
        }
    }
    parts.push(vec![format!("forwarding regfile {} ex_mem {} mem_wb {}", forwarding[0], forwarding[1], forwarding[2])]);
    let mut lines = vec![format!("occupancy cycles {}", cycle_count)];
    for stage in 0..5 {
        let [correct, wrong] = occupancy[stage];
        lines.push(format!("{} correct {} wrong {} idle {} busy {}", STAGES[stage], correct, wrong, cycle_count - correct - wrong, percentage(correct + wrong, cycle_count)));
    }
    parts.push(lines);
    let mut hotspots: Vec<i64> = per_pc.keys().copied().collect();
    hotspots.sort_by_key(|pc| (std::cmp::Reverse(per_pc[pc].iter().sum::<usize>()), *pc));
    let mut lines = vec!["hotspots".into()];
    for (rank, &pc) in hotspots.iter().take(config.top).enumerate() {
        let counts = per_pc[&pc];
        lines.push(format!("{} {} {} stall_cycles {} control {} structural {} load_use {} raw {}", rank + 1, hex(pc), CLASSES[instructions[first[&pc]].class], counts.iter().sum::<usize>(), counts[0], counts[1], counts[2], counts[3]));
    }
    parts.push(lines);
    let mut groups: Vec<(i64, i64, usize)> = dependencies.keys().copied().collect();
    groups.sort_by_key(|key| (std::cmp::Reverse(dependencies[key].0), key.0, key.1, key.2));
    let mut lines = vec![format!("dependencies total {}", groups.len())];
    for (rank, &(producer, waiting, cause)) in groups.iter().take(config.top).enumerate() {
        let (cycles, events) = dependencies[&(producer, waiting, cause)];
        lines.push(format!("{} {} {} -> {} {} {} stall_cycles {} events {}", rank + 1, hex(producer), CLASSES[instructions[first[&producer]].class], hex(waiting),
            CLASSES[instructions[first[&waiting]].class], CAUSES[cause], cycles, events));
    }
    parts.push(lines);
    let mut lines = vec![format!("intervals size {}", config.interval)];
    for start in (0..n).step_by(config.interval) {
        let end = (start + config.interval).min(n) - 1;
        let cycles = run.timing[end].w - if start == 0 { 0 } else { run.timing[start - 1].w };
        lines.push(format!("{}-{} cycles {} cpi {}", start + 1, end + 1, cycles, decimal(cycles, end - start + 1)));
    }
    parts.push(lines);
    let mut lines = vec![format!("cycles_table {}", config.predictors.iter().map(|p| p.name.as_str()).collect::<Vec<_>>().join(" "))];
    for (i, variant) in config.variants.iter().enumerate() { lines.push(format!("{} {}", variant.name, runs[i].iter().map(|r| r.cycles.to_string()).collect::<Vec<_>>().join(" "))); }
    parts.push(lines);
    let mut stats = Vec::new();
    for (i, part) in parts.into_iter().enumerate() { if i > 0 { stats.push(String::new()); } stats.extend(part); }
    let mut branch_lines = vec!["predictor,pc,class,executions,taken,mispredictions,accuracy".into()];
    for (p, definition) in config.predictors.iter().enumerate() {
        for (&pc, &i) in &first {
            if !instructions[i].control() { continue; }
            let executions: Vec<usize> = (0..n).filter(|&i| instructions[i].pc == pc).collect();
            let taken = executions.iter().filter(|&&i| instructions[i].taken).count();
            let missed = executions.iter().filter(|&&i| predictions[p].values[i].kind.is_some()).count();
            branch_lines.push(format!("{},{},{},{},{},{},{}", definition.name, hex(pc), CLASSES[instructions[i].class], executions.len(), taken, missed, percentage(executions.len() - missed, executions.len())));
        }
    }
    let mut combinations: Vec<(usize, usize)> = (0..config.variants.len()).flat_map(|v| (0..config.predictors.len()).map(move |p| (v, p))).collect();
    combinations.sort_by_key(|&(v, p)| (runs[v][p].cycles, config.variants[v].name.clone(), config.predictors[p].name.clone()));
    let mut comparison = vec!["rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw".into()];
    for (rank, &(v, p)) in combinations.iter().enumerate() {
        let run = &runs[v][p];
        comparison.push(format!("{},{},{},{},{},{},{},{},{},{},{},{}", rank + 1, config.variants[v].name, config.predictors[p].name, run.cycles, decimal(run.cycles, n), decimal(cycle_count, run.cycles),
            prediction_accuracy(&instructions, &predictions[p], None), predictions[p].values.iter().filter(|p| p.kind.is_some()).count(), run.totals[0], run.totals[1], run.totals[2], run.totals[3]));
    }
    let mut profile = vec!["branches".into()];
    let mut loops = vec!["loops".into()];
    for (&pc, &i) in &first {
        let instruction = &instructions[i];
        if instruction.class != 4 { continue; }
        let executions: Vec<usize> = (0..n).filter(|&i| instructions[i].pc == pc).collect();
        let outcomes: Vec<bool> = executions.iter().map(|&i| instructions[i].taken).collect();
        let transitions = outcomes.windows(2).filter(|pair| pair[0] != pair[1]).count();
        let mut longest = [0usize; 2];
        let mut length = 0;
        let mut previous = None;
        for &taken in &outcomes {
            if previous == Some(taken) { length += 1; } else { length = 1; }
            longest[usize::from(taken)] = longest[usize::from(taken)].max(length);
            previous = Some(taken);
        }
        let best = (0..config.predictors.len()).filter(|&p| config.predictors[p].scheme != "PERFECT").min_by_key(|&p| {
            (executions.iter().filter(|&&i| predictions[p].values[i].kind.is_some()).count(), p)
        }).unwrap();
        let missed = executions.iter().filter(|&&i| predictions[best].values[i].kind.is_some()).count();
        let backward = instruction.target.unwrap() < pc;
        profile.push(format!("{} {} executions {} taken {} transitions {} longest_taken {} longest_not_taken {} best {} {}", hex(pc), if backward { "backward" } else { "forward" }, executions.len(), outcomes.iter().filter(|&&t| t).count(), transitions, longest[1], longest[0], config.predictors[best].name, missed));
        if backward {
            let mut trips = Vec::new();
            let mut length = 0;
            for &taken in &outcomes { length += 1; if !taken { trips.push(length); length = 0; } }
            if length > 0 { trips.push(length); }
            loops.push(format!("{}-{} body {} entries {} iterations {} avg_trip {} max_trip {}", hex(instruction.target.unwrap()), hex(pc), (pc - instruction.target.unwrap()) / 4 + 1,
                trips.len(), executions.len(), decimal(executions.len(), trips.len()), trips.iter().max().unwrap()));
        }
    }
    profile.push(String::new());
    profile.extend(loops);
    let mut segment_groups: BTreeMap<i64, (usize, usize, usize)> = BTreeMap::new();
    let mut segment_start = 0;
    for i in 0..n {
        if instructions[i].control() || i + 1 == n {
            let cycles = run.timing[i].w - if segment_start == 0 { 0 } else { run.timing[segment_start - 1].w };
            let entry = segment_groups.entry(instructions[segment_start].pc).or_insert((0, 0, 0));
            entry.0 += 1;
            entry.1 += i - segment_start + 1;
            entry.2 += cycles;
            segment_start = i + 1;
        }
    }
    let mut segment_order: Vec<i64> = segment_groups.keys().copied().collect();
    segment_order.sort_by_key(|pc| (std::cmp::Reverse(segment_groups[pc].2), *pc));
    profile.extend([String::new(), format!("segments total {}", segment_order.len())]);
    for (rank, &pc) in segment_order.iter().take(config.top).enumerate() {
        let (instances, instructions, cycles) = segment_groups[&pc];
        profile.push(format!("{} {} instances {} instructions {} cycles {} cpi {}", rank + 1, hex(pc), instances, instructions, cycles, decimal(cycles, instructions)));
    }
    profile.extend([String::new(), "indirect".into()]);
    for (&pc, &i) in &first {
        if instructions[i].class != 5 || instructions[i].rs1.is_none() { continue; }
        let mut targets: BTreeMap<i64, usize> = BTreeMap::new();
        for instruction in &instructions { if instruction.pc == pc { *targets.entry(instruction.target.unwrap()).or_insert(0) += 1; } }
        let mut ordered: Vec<i64> = targets.keys().copied().collect();
        ordered.sort_by_key(|target| (std::cmp::Reverse(targets[target]), *target));
        profile.push(format!("{} executions {} distinct {} targets {}", hex(pc), targets.values().sum::<usize>(), targets.len(), ordered.iter().map(|target| format!("{}:{}", hex(*target), targets[target])).collect::<Vec<_>>().join(" ")));
    }
    profile.extend([String::new(), "instructions".into()]);
    for (&pc, &i) in &first {
        let instruction = &instructions[i];
        let count = instructions.iter().filter(|i| i.pc == pc).count();
        let stalls = per_pc.get(&pc).map_or(0, |counts| counts.iter().sum::<usize>());
        profile.push(format!("{} {} {} {} {} executions {} stall_cycles {}", hex(pc), CLASSES[instruction.class], register(instruction.rd), register(instruction.rs1), register(instruction.rs2), count, stalls));
    }
    for (name, lines) in [("pipeline.txt", pipeline_lines), ("stats.txt", stats), ("branches.csv", branch_lines), ("comparison.csv", comparison), ("profile.txt", profile)] { report::write(name, &lines)?; }
    Ok(())
}
