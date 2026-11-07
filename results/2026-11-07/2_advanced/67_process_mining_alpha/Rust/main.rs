mod eventlog;
mod dfg;
mod alpha_miner;
mod heuristic_miner;
mod conformance;
mod report;

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use eventlog::{Case, Event, Params};
use dfg::{Counts, Log};
use alpha_miner::Pair;
use conformance::{Net, Totals, PlaceTotals};
use report::{Fraction, fraction, percentage, list};

fn yes(value: bool) -> &'static str { if value { "yes" } else { "no" } }
fn names(log: &Log) -> Vec<String> { log.iter().flat_map(|(trace, _)| trace.iter().cloned()).collect::<BTreeSet<_>>().into_iter().collect() }
fn relations(names: &[String], counts: &Counts) -> Vec<Vec<String>> {
    names.iter().map(|a| names.iter().map(|b| dfg::relation(counts, a, b).to_owned()).collect()).collect()
}

struct Mined { net: Net, names: Vec<String>, pairs: Vec<Pair>, candidates: usize, causal: usize, starts: Vec<String>, ends: Vec<String> }

fn discover(log: &Log, names: &[String], relations: &[Vec<String>], transitions: &[String]) -> Mined {
    let n = names.len();
    let starts: Vec<_> = log.iter().map(|(trace, _)| trace[0].clone()).collect::<BTreeSet<_>>().into_iter().collect();
    let ends: Vec<_> = log.iter().map(|(trace, _)| trace.last().unwrap().clone()).collect::<BTreeSet<_>>().into_iter().collect();
    let mut candidates = BTreeSet::new();
    let mut queue = VecDeque::new();
    for a in 0..n { for b in 0..n {
        let pair = (1<<a, 1<<b);
        if alpha_miner::candidate(pair, relations) && candidates.insert(pair) { queue.push_back(pair); }
    } }
    while let Some((a, b)) = queue.pop_front() {
        for i in 0..n {
            for pair in [(a|(1<<i), b), (a, b|(1<<i))] {
                if !candidates.contains(&pair) && alpha_miner::candidate(pair, relations) { candidates.insert(pair); queue.push_back(pair); }
            }
        }
    }
    let mut pairs: Vec<_> = candidates.iter().copied().filter(|&(a, b)| (0..n).all(|i|
        (a&(1<<i) != 0 || !alpha_miner::candidate((a|(1<<i), b), relations))
        && (b&(1<<i) != 0 || !alpha_miner::candidate((a, b|(1<<i)), relations)))).collect();
    pairs.sort_by(|a, b| alpha_miner::compare(a, b, n));
    let mut places = vec!["start".to_owned()];
    places.extend((1..=pairs.len()).map(|i| format!("p{}", i))); places.push("end".to_owned());
    let final_place = places.len()-1;
    let mut net = Net { places, transitions: transitions.to_vec(), inputs: vec![Vec::new(); transitions.len()], outputs: vec![Vec::new(); transitions.len()], initial: 0, final_place };
    for name in &starts { net.inputs[transitions.binary_search(name).unwrap()].push(0); }
    for name in &ends { net.outputs[transitions.binary_search(name).unwrap()].push(final_place); }
    for (p, &(a, b)) in pairs.iter().enumerate() {
        for i in alpha_miner::indices(a, n) { net.outputs[transitions.binary_search(&names[i]).unwrap()].push(p+1); }
        for i in alpha_miner::indices(b, n) { net.inputs[transitions.binary_search(&names[i]).unwrap()].push(p+1); }
    }
    for places in net.inputs.iter_mut().chain(net.outputs.iter_mut()) { places.sort_unstable(); }
    let causal = relations.iter().flatten().filter(|r| r.as_str() == "->").count();
    Mined { net, names: names.to_vec(), pairs, candidates: candidates.len(), causal, starts, ends }
}

fn mined_lines(mined: &Mined) -> Vec<String> {
    let mut lines = vec![format!("PLACE start - {}", list(&mined.starts))];
    for (p, &(a, b)) in mined.pairs.iter().enumerate() {
        let a: Vec<_> = alpha_miner::indices(a, mined.names.len()).iter().map(|&i| mined.names[i].clone()).collect();
        let b: Vec<_> = alpha_miner::indices(b, mined.names.len()).iter().map(|&i| mined.names[i].clone()).collect();
        lines.push(format!("PLACE p{} {} {}", p+1, list(&a), list(&b)));
    }
    lines.push(format!("PLACE end {} -", list(&mined.ends)));
    for (i, transition) in mined.net.transitions.iter().enumerate() {
        let inputs: Vec<_> = mined.net.inputs[i].iter().map(|&p| mined.net.places[p].clone()).collect();
        let outputs: Vec<_> = mined.net.outputs[i].iter().map(|&p| mined.net.places[p].clone()).collect();
        lines.push(format!("TRANSITION {} in {} out {}", transition, list(&inputs), list(&outputs)));
    }
    lines.push(format!("NET places {} transitions {} arcs {}", mined.net.places.len(), mined.net.transitions.len(), mined.net.arcs()));
    lines
}

fn heuristic(activities: &[String], counts: &Counts, triangles: &Counts, p: &Params) -> Vec<String> {
    let mut lines = Vec::new();
    let mut loop1 = BTreeSet::new();
    for a in activities {
        let count = dfg::get(counts, a, a);
        if count == 0 { continue; }
        let measure = heuristic_miner::loop_measure(count);
        let accepted = count >= p.observations && measure >= p.loop1;
        if accepted { loop1.insert(a.clone()); }
        lines.push(format!("L1 {} count {} measure {} {}", a, count, measure.text(), if accepted { "ACCEPT" } else { "REJECT" }));
    }
    let mut loop2 = BTreeSet::new();
    for (i, a) in activities.iter().enumerate() { for b in &activities[i+1..] {
        if loop1.contains(a) || loop1.contains(b) { continue; }
        let count = dfg::get(triangles, a, b)+dfg::get(triangles, b, a);
        if count == 0 { continue; }
        let measure = heuristic_miner::loop_measure(count);
        let accepted = count >= p.observations && measure >= p.loop2;
        if accepted { loop2.insert((a.clone(), b.clone())); }
        lines.push(format!("L2 {} {} count {} measure {} {}", a, b, count, measure.text(), if accepted { "ACCEPT" } else { "REJECT" }));
    } }
    let mut edges: BTreeSet<_> = loop1.iter().map(|a| (a.clone(), a.clone())).collect();
    for a in activities { for b in activities {
        let count = dfg::get(counts, a, b);
        if a == b || count == 0 { continue; }
        let measure = heuristic_miner::dependency(counts, a, b);
        let outgoing = activities.iter().filter(|&c| c != a && dfg::get(counts, a, c) > 0).map(|c| heuristic_miner::dependency(counts, a, c)).max().unwrap();
        let incoming = activities.iter().filter(|&c| c != b && dfg::get(counts, c, b) > 0).map(|c| heuristic_miner::dependency(counts, c, b)).max().unwrap();
        let pair = if a < b { (a.clone(), b.clone()) } else { (b.clone(), a.clone()) };
        let verdict = if loop2.contains(&pair) { "LOOP2" } else if count < p.observations { "REJECT_COUNT" }
            else if measure < p.dependency { "REJECT_MEASURE" }
            else if outgoing.subtract(measure) > p.relative && incoming.subtract(measure) > p.relative { "REJECT_BEST" } else { "ACCEPT" };
        if verdict == "LOOP2" || verdict == "ACCEPT" { edges.insert((a.clone(), b.clone())); }
        lines.push(format!("DEP {} {} count {} reverse {} measure {} {}", a, b, count, dfg::get(counts, b, a), measure.text(), verdict));
    } }
    for a in activities {
        let inputs: Vec<_> = activities.iter().filter(|&b| edges.contains(&(b.clone(), a.clone()))).cloned().collect();
        let outputs: Vec<_> = activities.iter().filter(|&b| edges.contains(&(a.clone(), b.clone()))).cloned().collect();
        lines.push(format!("NODE {} in {} out {}", a, list(&inputs), list(&outputs)));
    }
    for a in activities {
        for split in [true, false] {
            let adjacent: Vec<_> = activities.iter().filter(|&b| b != a && if split { edges.contains(&(a.clone(), b.clone())) } else { edges.contains(&(b.clone(), a.clone())) }).collect();
            for (i, b) in adjacent.iter().enumerate() { for c in &adjacent[i+1..] {
                let measure = if split { heuristic_miner::split(counts, a, b, c) } else { heuristic_miner::join(counts, a, b, c) };
                lines.push(format!("{} {} {} {} measure {} {}", if split { "SPLIT" } else { "JOIN" }, a, b, c, measure.text(), if measure >= p.and { "AND" } else { "XOR" }));
            } }
        }
    }
    lines.push(format!("GRAPH activities {} edges {} loops1 {} loops2 {}", activities.len(), edges.len(), loop1.len(), loop2.len()));
    lines
}

struct Reachability { markings: usize, edges: usize, unsafe_count: usize, deadlocks: usize, stuck: usize, final_seen: bool, dead: Vec<String>, follows: Counts }

fn explore(net: &Net) -> Reachability {
    let initial = net.marking(false);
    let mut states = vec![initial.clone()];
    let mut indices = BTreeMap::from([(initial, 0)]);
    let mut edges: Vec<Vec<usize>> = vec![Vec::new()];
    let mut enabled = vec![false; net.transitions.len()];
    let mut unsafe_count = 0;
    let mut deadlocks = 0;
    let mut follows = Counts::new();
    let mut current = 0;
    while current < states.len() {
        let marking = states[current].clone();
        let mut any = false;
        for t in 0..net.transitions.len() {
            if !net.enabled(&marking, t) { continue; }
            any = true; enabled[t] = true;
            let next = net.fire(&marking, t);
            if next.iter().any(|&tokens| tokens > 1) { unsafe_count += 1; continue; }
            for u in 0..net.transitions.len() {
                if net.enabled(&next, u) { follows.insert((net.transitions[t].clone(), net.transitions[u].clone()), 1); }
            }
            let index = if let Some(&index) = indices.get(&next) { index } else {
                let index = states.len(); indices.insert(next.clone(), index); states.push(next); edges.push(Vec::new()); index
            };
            edges[current].push(index);
        }
        if !any && marking != net.marking(true) { deadlocks += 1; }
        current += 1;
    }
    let final_index = indices.get(&net.marking(true)).copied();
    let mut reaches = BTreeSet::new();
    let mut queue = VecDeque::new();
    if let Some(i) = final_index { reaches.insert(i); queue.push_back(i); }
    while let Some(target) = queue.pop_front() {
        for (i, successors) in edges.iter().enumerate() {
            if successors.contains(&target) && reaches.insert(i) { queue.push_back(i); }
        }
    }
    Reachability { markings: states.len(), edges: edges.iter().map(Vec::len).sum(), unsafe_count, deadlocks,
        stuck: states.len()-reaches.len(), final_seen: final_index.is_some(), dead: net.transitions.iter().enumerate().filter(|(i, _)| !enabled[*i]).map(|(_, n)| n.clone()).collect(), follows }
}

struct Replay { cases: Vec<Totals>, totals: Totals, places: Vec<PlaceTotals>, perfect: usize }

fn replay(net: &Net, cases: &[Case]) -> Replay {
    let mut result = Replay { cases: Vec::new(), totals: Totals::default(), places: (0..net.places.len()).map(|_| PlaceTotals { routes: vec![0; net.transitions.len()], ..PlaceTotals::default() }).collect(), perfect: 0 };
    for case in cases {
        let mut tokens = vec![VecDeque::new(); net.places.len()]; tokens[net.initial].push_back(case.events[0].time);
        let mut totals = Totals { produced: 1, ..Totals::default() };
        let mut missing = vec![0; net.places.len()];
        for event in &case.events {
            let Ok(t) = net.transitions.binary_search(&event.row.activity) else { totals.skipped += 1; continue; };
            for &q in &net.inputs[t] {
                totals.consumed += 1;
                if let Some(time) = tokens[q].pop_front() {
                    result.places[q].waits.push(event.time-time); result.places[q].routes[t] += 1;
                } else { totals.missing += 1; missing[q] += 1; }
            }
            for &q in &net.outputs[t] { tokens[q].push_back(event.time); totals.produced += 1; }
        }
        totals.consumed += 1;
        if tokens[net.final_place].pop_front().is_none() { totals.missing += 1; missing[net.final_place] += 1; }
        for q in 0..net.places.len() {
            let remaining = tokens[q].len() as i64;
            totals.remaining += remaining;
            result.places[q].missing += missing[q]; result.places[q].remaining += remaining;
            result.places[q].deviating += usize::from(missing[q] > 0 || remaining > 0);
        }
        result.perfect += usize::from(totals.missing == 0 && totals.remaining == 0);
        result.totals.add(&totals); result.cases.push(totals);
    }
    result
}

fn precision(net: &Net, prefixes: &BTreeMap<Vec<String>, (i64, BTreeSet<String>)>, name: &str) -> Vec<String> {
    let (mut fitting, mut allowed, mut escaping) = (0, 0, 0);
    let mut escapes = vec![0i64; net.transitions.len()];
    for (prefix, (weight, followers)) in prefixes {
        let mut marking = net.marking(false);
        let mut fits = true;
        for activity in prefix {
            if let Ok(t) = net.transitions.binary_search(activity) {
                if net.enabled(&marking, t) { marking = net.fire(&marking, t); } else { fits = false; break; }
            } else { fits = false; break; }
        }
        if !fits { continue; }
        fitting += 1;
        for t in 0..net.transitions.len() {
            if net.enabled(&marking, t) {
                allowed += weight;
                if !followers.contains(&net.transitions[t]) { escaping += weight; escapes[t] += weight; }
            }
        }
    }
    let precision = if allowed == 0 { Fraction::new(1, 1) } else { Fraction::new(allowed-escaping, allowed) };
    let mut lines = vec![format!("PRECISION {} prefixes {} allowed {} escaping {} precision {}", name, fitting, allowed, escaping, precision.text())];
    let mut order: Vec<_> = (0..escapes.len()).filter(|&t| escapes[t] > 0).collect();
    order.sort_by_key(|&t| (std::cmp::Reverse(escapes[t]), t));
    for t in order { lines.push(format!("ESCAPE {} {} weight {}", name, net.transitions[t], escapes[t])); }
    lines
}

fn resources(cases: &[Case], resources: &[String], activities: &[String]) -> Vec<String> {
    let mut lines = Vec::new();
    for (i, resource) in resources.iter().enumerate() {
        let mut counts = BTreeMap::<String, usize>::new();
        let mut case_count = 0;
        for case in cases {
            let events: Vec<_> = case.events.iter().filter(|e| &e.row.resource == resource).collect();
            case_count += usize::from(!events.is_empty());
            for event in events { *counts.entry(event.row.activity.clone()).or_default() += 1; }
        }
        let work: Vec<_> = activities.iter().filter_map(|a| counts.get(a).map(|n| format!("{}={}", a, n))).collect();
        lines.push(format!("RESOURCE {} {} events {} cases {} work {}", i+1, resource, counts.values().sum::<usize>(), case_count, work.join(",")));
    }
    let mut handovers = BTreeMap::<(String, String), (usize, BTreeSet<String>)>::new();
    let mut subcontract = BTreeMap::<(String, String), usize>::new();
    let mut together = BTreeMap::<(String, String), usize>::new();
    for case in cases {
        for pair in case.events.windows(2) {
            let entry = handovers.entry((pair[0].row.resource.clone(), pair[1].row.resource.clone())).or_default();
            entry.0 += 1; entry.1.insert(case.id.clone());
        }
        for triple in case.events.windows(3) {
            if triple[0].row.resource == triple[2].row.resource && triple[0].row.resource != triple[1].row.resource {
                *subcontract.entry((triple[0].row.resource.clone(), triple[1].row.resource.clone())).or_default() += 1;
            }
        }
        let names: Vec<_> = case.events.iter().map(|e| e.row.resource.clone()).collect::<BTreeSet<_>>().into_iter().collect();
        for (i, a) in names.iter().enumerate() { for b in &names[i+1..] { *together.entry((a.clone(), b.clone())).or_default() += 1; } }
    }
    let mut other: Vec<_> = handovers.iter().filter(|((a, b), _)| a != b).collect();
    other.sort_by(|a, b| b.1.0.cmp(&a.1.0).then(a.0.cmp(b.0)));
    for ((a, b), (count, cases)) in other { lines.push(format!("HANDOVER {} {} count {} cases {}", a, b, count, cases.len())); }
    let table: Vec<Vec<_>> = resources.iter().map(|a| resources.iter().map(|b| handovers.get(&(a.clone(), b.clone())).map_or(0, |v| v.0).to_string()).collect()).collect();
    lines.extend(dfg::table(&table, 5));
    for (name, counts) in [("SUBCONTRACT", &subcontract), ("TOGETHER", &together)] {
        let mut pairs: Vec<_> = counts.iter().collect(); pairs.sort_by(|a, b| b.1.cmp(a.1).then(a.0.cmp(b.0)));
        for ((a, b), count) in pairs { lines.push(format!("{} {} {} {} {}", name, a, b, if name == "SUBCONTRACT" { "count" } else { "cases" }, count)); }
    }
    let total: usize = handovers.values().map(|v| v.0).sum();
    let same: usize = handovers.iter().filter(|((a, b), _)| a == b).map(|(_, v)| v.0).sum();
    lines.push(format!("TOTAL handovers {} self {} other {}", total, same, total-same));
    lines
}

fn main() {
    let (rows, params) = eventlog::read();
    let row_count = rows.len();
    let mut events = Vec::new();
    let mut duplicates = BTreeSet::new();
    let mut summary = Vec::new();
    for row in rows {
        let Some(time) = eventlog::timestamp(&row.timestamp) else {
            summary.push(format!("ERROR line {}: bad timestamp {}", row.line, row.timestamp)); continue;
        };
        let key = (row.case.clone(), row.activity.clone(), row.timestamp.clone());
        if !duplicates.insert(key) { summary.push(format!("ERROR line {}: duplicate event {} {} {}", row.line, row.case, row.activity, row.timestamp)); continue; }
        events.push(Event { row, time });
    }
    let cases = eventlog::cases(&events);
    let activities: Vec<_> = events.iter().map(|e| e.row.activity.clone()).collect::<BTreeSet<_>>().into_iter().collect();
    let resource_names: Vec<_> = events.iter().map(|e| e.row.resource.clone()).collect::<BTreeSet<_>>().into_iter().collect();
    let log: Log = cases.iter().map(|c| (c.trace(), 1)).collect();
    let counts = dfg::counts(&log);
    let triangles = alpha_miner::triangles(&log);
    let reference = Net::read();
    let first = events.iter().min_by_key(|e| e.time).unwrap();
    let last = events.iter().max_by_key(|e| e.time).unwrap();
    summary.push(format!("LOG rows {} adopted {} rejected {} cases {} activities {} resources {} first {} last {}", row_count, events.len(), row_count-events.len(),
        cases.len(), activities.len(), resource_names.len(), first.row.timestamp, last.row.timestamp));
    for activity in &activities {
        let mut event_count = 0;
        let (mut case_count, mut start, mut end, mut rework) = (0, 0, 0, 0);
        let mut waiting = Vec::new();
        let mut resources = BTreeSet::new();
        for case in &cases {
            let mut count = 0;
            for (i, event) in case.events.iter().enumerate() {
                if &event.row.activity == activity {
                    count += 1; event_count += 1; resources.insert(event.row.resource.clone());
                    if i > 0 { waiting.push(event.time-case.events[i-1].time); }
                }
            }
            case_count += usize::from(count > 0); rework += usize::from(count >= 2);
            start += usize::from(case.events[0].row.activity == *activity); end += usize::from(case.events.last().unwrap().row.activity == *activity);
        }
        summary.push(format!("ACTIVITY {} events {} cases {} start {} end {} rework {} wait {} resources {} model {}", activity, event_count, case_count, start, end, rework,
            if waiting.is_empty() { "-".to_owned() } else { fraction(waiting.iter().sum(), waiting.len() as i64) }, resources.len(), yes(reference.transitions.contains(activity))));
    }
    let lengths: Vec<_> = cases.iter().map(|c| c.events.len() as i64).collect();
    let durations: Vec<_> = cases.iter().map(Case::duration).collect();
    for (name, values) in [("LENGTH", &lengths), ("DURATION", &durations)] {
        summary.push(format!("{} min {} max {} mean {} median {}", name, values.iter().min().unwrap(), values.iter().max().unwrap(), fraction(values.iter().sum(), values.len() as i64), eventlog::median(values).text()));
    }
    for day in 0..=durations.iter().max().unwrap()/1440 {
        let count = durations.iter().filter(|&&d| d/1440 == day).count(); summary.push(format!("DAYS {} cases {} share {}", day, count, percentage(count, cases.len())));
    }
    let late = durations.iter().filter(|&&d| d > params.sla).count();
    summary.push(format!("SLA limit {} late {} share {}", params.sla, late, percentage(late, cases.len())));
    let weekday = |time: i64| ((time/1440+3)%7) as usize;
    for (day, name) in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].iter().enumerate() {
        summary.push(format!("WEEKDAY {} events {} starts {} ends {}", name, events.iter().filter(|e| weekday(e.time) == day).count(),
            cases.iter().filter(|c| weekday(c.events[0].time) == day).count(), cases.iter().filter(|c| weekday(c.events.last().unwrap().time) == day).count()));
    }
    let mut variants = BTreeMap::<Vec<String>, Vec<usize>>::new();
    for (i, case) in cases.iter().enumerate() { variants.entry(case.trace()).or_default().push(i); }
    let mut variants: Vec<_> = variants.into_iter().collect();
    variants.sort_by(|a, b| b.1.len().cmp(&a.1.len()).then(a.0.cmp(&b.0)));
    let kept: Vec<_> = variants.iter().map(|(trace, _)| trace.windows(2).all(|pair| dfg::get(&counts, &pair[0], &pair[1]) >= params.filter)).collect();
    let filtered: Log = variants.iter().enumerate().filter(|(i, _)| kept[*i]).map(|(_, (trace, cases))| (trace.clone(), cases.len() as i64)).collect();
    let filtered_counts = dfg::counts(&filtered);
    let tw = names(&filtered);
    let loops: Vec<_> = tw.iter().filter(|a| dfg::get(&filtered_counts, a, a) > 0).cloned().collect();
    let basic = relations(&tw, &filtered_counts);
    let alpha = discover(&filtered, &tw, &basic, &tw);
    let reduced: Log = filtered.iter().map(|(trace, weight)| (trace.iter().filter(|a| !loops.contains(a)).cloned().collect(), *weight)).collect();
    let tv = names(&reduced);
    let reduced_counts = dfg::counts(&reduced);
    let reduced_triangles = alpha_miner::triangles(&reduced);
    let plus_relations: Vec<Vec<_>> = tv.iter().map(|a| tv.iter().map(|b| alpha_miner::plus_relation(&reduced_counts, &reduced_triangles, a, b).to_owned()).collect()).collect();
    let mut plus = discover(&reduced, &tv, &plus_relations, &tw);
    let mut loop_lines = Vec::new();
    for activity in &loops {
        let pre: Vec<_> = tv.iter().filter(|a| dfg::get(&filtered_counts, a, activity) > 0).cloned().collect();
        let post: Vec<_> = tv.iter().filter(|b| dfg::get(&filtered_counts, activity, b) > 0).cloned().collect();
        let mask = |names: &[String]| names.iter().fold(0u16, |mask, a| mask|(1<<tv.binary_search(a).unwrap()));
        let pair = (mask(&pre), mask(&post));
        let place = plus.pairs.iter().position(|&p| p == pair);
        if let Some(p) = place {
            let t = plus.net.transitions.binary_search(activity).unwrap(); plus.net.inputs[t].push(p+1); plus.net.outputs[t].push(p+1);
        }
        loop_lines.push(format!("LOOP {} before {} after {} place {}", activity, list(&pre), list(&post), place.map_or_else(|| "-".to_owned(), |p| format!("p{}", p+1))));
    }
    let kept_cases: usize = filtered.iter().map(|(_, w)| *w as usize).sum();
    let kept_events: usize = filtered.iter().map(|(trace, w)| trace.len()*(*w as usize)).sum();
    let mut alpha_lines = vec![format!("LOG variants {} cases {} activities {}", filtered.len(), kept_cases, list(&tw)), format!("LOOPS {}", list(&loops)), "MINER alpha".to_owned()];
    alpha_lines.extend(dfg::footprint(&tw, &basic));
    alpha_lines.push(format!("PAIRS causal {} candidates {} maximal {}", alpha.causal, alpha.candidates, alpha.pairs.len())); alpha_lines.extend(mined_lines(&alpha));
    alpha_lines.push("MINER alpha_plus".to_owned());
    for ((a, b), count) in &reduced_triangles { alpha_lines.push(format!("TRIANGLE {} {} count {}", a, b, count)); }
    alpha_lines.extend(dfg::footprint(&tv, &plus_relations));
    alpha_lines.push(format!("PAIRS causal {} candidates {} maximal {}", plus.causal, plus.candidates, plus.pairs.len()));
    alpha_lines.extend(loop_lines); alpha_lines.extend(mined_lines(&plus));
    let mut dfg_lines = Vec::new();
    for start in [true, false] {
        let mut ends = BTreeMap::<String, Vec<i64>>::new();
        for case in &cases { let event = if start { &case.events[0] } else { case.events.last().unwrap() }; ends.entry(event.row.activity.clone()).or_default().push(case.duration()); }
        let mut ends: Vec<_> = ends.into_iter().collect(); ends.sort_by(|a, b| b.1.len().cmp(&a.1.len()).then(a.0.cmp(&b.0)));
        for (activity, durations) in ends {
            dfg_lines.push(if start { format!("START {} count {}", activity, durations.len()) } else { format!("END {} count {} duration {}", activity, durations.len(), fraction(durations.iter().sum(), durations.len() as i64)) });
        }
    }
    let mut edge_order: Vec<_> = counts.iter().collect(); edge_order.sort_by(|a, b| b.1.cmp(a.1).then(a.0.cmp(b.0)));
    for ((a, b), count) in edge_order {
        let mut waits = Vec::new(); let mut case_count = 0;
        for case in &cases {
            let pairs: Vec<_> = case.events.windows(2).filter(|pair| pair[0].row.activity == *a && pair[1].row.activity == *b).collect();
            case_count += usize::from(!pairs.is_empty());
            waits.extend(pairs.iter().map(|pair| pair[1].time-pair[0].time));
        }
        dfg_lines.push(format!("EDGE {} {} count {} cases {} mean {} min {} max {}", a, b, count, case_count, fraction(waits.iter().sum(), waits.len() as i64), waits.iter().min().unwrap(), waits.iter().max().unwrap()));
    }
    dfg_lines.extend(dfg::footprint(&activities, &relations(&activities, &counts)));
    let nets = [&reference, &alpha.net, &plus.net];
    let net_names = ["reference", "alpha", "alpha_plus"];
    let reachable: Vec<_> = nets.iter().map(|net| explore(net)).collect();
    let replays: Vec<_> = nets.iter().map(|net| replay(net, &cases)).collect();
    let mut conformance = vec![format!("MODEL places {} transitions {} arcs {}", reference.places.len(), reference.transitions.len(), reference.arcs())];
    for i in 0..3 {
        let r = &reachable[i]; conformance.push(format!("REACHABILITY {} markings {} edges {} unsafe {} deadlocks {} stuck {} final {} dead {} sound {}", net_names[i],
            r.markings, r.edges, r.unsafe_count, r.deadlocks, r.stuck, yes(r.final_seen), list(&r.dead), yes(r.unsafe_count == 0 && r.stuck == 0 && r.dead.is_empty())));
    }
    for i in 0..3 {
        let union: Vec<_> = activities.iter().chain(&nets[i].transitions).cloned().collect::<BTreeSet<_>>().into_iter().collect();
        let mut differing = 0; let mut diffs = Vec::new();
        for a in &union { for b in &union {
            let log = dfg::relation(&counts, a, b); let model = dfg::relation(&reachable[i].follows, a, b);
            if log != model { differing += 1; if a <= b { diffs.push(format!("DIFF {} {} log {} model {}", a, b, log, model)); } }
        } }
        let cells = union.len()*union.len();
        conformance.push(format!("FOOTPRINT {} activities {} cells {} differing {} fitness {}", net_names[i], union.len(), cells, differing, fraction((cells-differing) as i64, cells as i64)));
        if i == 0 { conformance.extend(diffs); }
    }
    let mut prefixes = BTreeMap::<Vec<String>, (i64, BTreeSet<String>)>::new();
    for case in &cases {
        let trace = case.trace();
        for length in 0..=trace.len() {
            let entry = prefixes.entry(trace[..length].to_vec()).or_default(); entry.0 += 1;
            if length < trace.len() { entry.1.insert(trace[length].clone()); }
        }
    }
    for i in 0..3 { conformance.extend(precision(nets[i], &prefixes, net_names[i])); }
    for i in 0..3 {
        let replay = &replays[i]; let net = nets[i]; let total = &replay.totals;
        conformance.push(format!("REPLAY {} cases {} fitting {} skipped {} missing {} remaining {} consumed {} produced {} fitness {}", net_names[i], cases.len(), replay.perfect,
            total.skipped, total.missing, total.remaining, total.consumed, total.produced, total.fitness().text()));
        for (q, place) in net.places.iter().enumerate() {
            let p = &replay.places[q]; conformance.push(format!("PLACE {} {} missing {} remaining {} deviating {} tokens {} mean {} max {}", net_names[i], place, p.missing,
                p.remaining, p.deviating, p.waits.len(), if p.waits.is_empty() { "-".to_owned() } else { fraction(p.waits.iter().sum(), p.waits.len() as i64) }, p.waits.iter().max().map_or_else(|| "-".to_owned(), i64::to_string)));
        }
        for (q, place) in net.places.iter().enumerate() {
            let transitions: Vec<_> = (0..net.transitions.len()).filter(|&t| net.inputs[t].contains(&q)).collect();
            if transitions.len() >= 2 { conformance.push(format!("ROUTE {} {} {}", net_names[i], place, transitions.iter().map(|&t| format!("{}={}", net.transitions[t], replay.places[q].routes[t])).collect::<Vec<_>>().join(","))); }
        }
    }
    let mut variant_numbers = vec![0; cases.len()];
    let mut variant_lines = Vec::new();
    for (i, (trace, indices)) in variants.iter().enumerate() {
        for &case in indices { variant_numbers[case] = i+1; }
        let duration: i64 = indices.iter().map(|&j| cases[j].duration()).sum();
        let late = indices.iter().filter(|&&j| cases[j].duration() > params.sla).count();
        variant_lines.push(format!("VARIANT {} count {} share {} length {} first {} duration {} late {} fitness {} {} {}", i+1, indices.len(), percentage(indices.len(), cases.len()),
            trace.len(), cases[indices[0]].id, fraction(duration, indices.len() as i64), late, replays[0].cases[indices[0]].fitness().text(), if kept[i] { "KEEP" } else { "DROP" }, trace.join(",")));
    }
    variant_lines.push(format!("FILTER min_follows {} variants {} of {} cases {} of {} events {} of {}", params.filter, filtered.len(), variants.len(), kept_cases, cases.len(), kept_events, events.len()));
    let mut csv = vec!["case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness".to_owned()];
    for (i, case) in cases.iter().enumerate() {
        let total = &replays[0].cases[i]; csv.push(format!("{},{},{},{},{},{},{},{},{}", case.id, variant_numbers[i], case.events.len(), total.skipped,
            total.missing, total.remaining, total.consumed, total.produced, total.fitness().text()));
    }
    let heuristic_lines = heuristic(&activities, &counts, &triangles, &params);
    let resource_lines = resources(&cases, &resource_names, &activities);
    for (file, lines) in [("log_summary.txt", summary), ("variants.txt", variant_lines), ("dfg.txt", dfg_lines), ("alpha_net.txt", alpha_lines),
        ("heuristic_net.txt", heuristic_lines), ("conformance.csv", csv), ("conformance.txt", conformance), ("resources.txt", resource_lines)] { report::write(file, &lines); }
}
