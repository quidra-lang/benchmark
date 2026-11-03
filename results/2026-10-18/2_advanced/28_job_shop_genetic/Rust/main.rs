mod instance;
mod minstd;
mod dispatch_rules;
mod genetic;
mod gantt;
use std::{
    fs, io, collections::{
        BTreeMap, BTreeSet
    }
};
use instance::Instance;
use minstd::Minstd;
use dispatch_rules::{
    dispatch, RULES
};
use genetic::{
    decode, gene_operations, tournament, crossover, swap_mutation, insert_mutation
};
fn percentage(a: i64, b: i64) -> String {
    let t = (2000*a+b)/(2*b);
    format!("{}.{}%", t/10, t%10)
}
fn letter(number: usize) -> char {
    char::from(b'A'+number as u8-1)
}
fn integers(xs: impl IntoIterator<Item = usize>) -> String {
    xs.into_iter().map(|x|x.to_string()).collect::<Vec<_>>().join(" ")
}
struct Params {
    v: BTreeMap<String, Vec<String>>
}
impl Params {
    fn get(&self, k: &str) -> usize {
        self.v[k][0].parse().unwrap()
    }
    fn chance(&self, k: &str) -> (usize, usize) {
        let(a, b) = self.v[k][0].split_once('/').unwrap();
        (a.parse().unwrap(), b.parse().unwrap())
    }
    fn read() -> io::Result<Self> {
        Ok(Self {
            v: fs::read_to_string("input/ga_params.txt")?.lines().map(|l| {
                let mut f = l.split(' '); (f.next().unwrap().into(), f.map(str::to_owned).collect())
            }).collect()
        })
    }
}
#[derive(Clone)]
struct Schedule {
    starts: Vec<i64>,
    ends: Vec<i64>,
    order: Vec<Vec<usize>>,
    previous: Vec<Option<usize>>,
    next: Vec<Option<usize>>,
    makespan: i64
}
impl Schedule {
    fn new(ins: &Instance, starts: Vec<i64>) -> Self {
        let n = starts.len();
        let ends = starts.iter().zip(&ins.operations).map(|(s, o)|s+o.duration).collect::<Vec<_>>();
        let makespan = *ends.iter().max().unwrap();
        let mut order = vec![vec![]; ins.machines.len()];
        let mut ids = (0..n).collect::<Vec<_>>();
        ids.sort_by_key(|&i|(starts[i], i));
        for id in ids {
            order[ins.operations[id].machine].push(id);
        }
        let(mut previous, mut next) = (vec![None; n], vec![None; n]);
        for seq in &order {
            for pair in seq.windows(2) {
                next[pair[0]] = Some(pair[1]);
                previous[pair[1]] = Some(pair[0]);
            }
        }
        Self {
            starts,
            ends,
            order,
            previous,
            next,
            makespan
        }
    }
    fn by_start(&self) -> Vec<usize> {
        let mut ids = (0..self.starts.len()).collect::<Vec<_>>();
        ids.sort_by_key(|&i|(self.starts[i], i));
        ids
    }
    fn chromosome(&self, ins: &Instance) -> Vec<usize> {
        self.by_start().iter().map(|&i|ins.operations[i].job).collect()
    }
    fn path(&self, ins: &Instance) -> Vec<usize> {
        let mut o = self.ends.iter().position(|&c|c == self.makespan).unwrap();
        let mut path = vec![o];
        while self.starts[o] != 0 {
            o = match self.previous[o] {
                Some(p)if self.ends[p] == self.starts[o] => p, _ => ins.operations[o].previous.unwrap()
            };
            path.push(o);
        }
        path.reverse();
        path
    }
    fn blocks(&self, ins: &Instance) -> Vec<Vec<usize>> {
        let mut blocks: Vec<Vec<usize> >= vec![];
        for id in self.path(ins) {
            if blocks.last().is_some_and(|b|ins.operations[b[0]].machine == ins.operations[id].machine) {
                blocks.last_mut().unwrap().push(id)
            }else {
                blocks.push(vec![id])
            }
        }
        blocks
    }
    fn moves(&self, ins: &Instance) -> Vec<(usize, usize)> {
        self.blocks(ins).iter().flat_map(|b|b.windows(2).map(|p|(p[0], p[1]))).collect()
    }
    fn path_count(&self, ins: &Instance) -> i64 {
        let mut ways = vec![0; self.starts.len()];
        for id in self.by_start() {
            if self.starts[id] == 0 {
                ways[id] = 1
            }else {
                for p in [ins.operations[id].previous, self.previous[id]].into_iter().flatten() {
                    if self.ends[p] == self.starts[id] {
                        let source = ways[p];
                        ways[id] += source;
                    }
                }
            }
        }
        self.ends.iter().enumerate().filter(|(_, c)|**c == self.makespan).map(|(i, _)|ways[i]).sum()
    }
    fn path_counts(&self, ins: &Instance) -> Vec<usize> {
        let mut counts = vec![0; ins.machines.len()];
        for i in self.path(ins) {
            counts[ins.operations[i].machine] += 1
        }
        counts
    }
    fn bottleneck(&self, ins: &Instance) -> usize {
        let c = self.path_counts(ins);
        (0..c.len()).max_by_key(|&m|(c[m], std::cmp::Reverse(m))).unwrap()
    }
    fn left_shift(&self, ins: &Instance, id: usize) -> Option<(i64, usize)> {
        let o = &ins.operations[id];
        let seq = &self.order[o.machine];
        let pos = seq.iter().position(|&i|i == id).unwrap();
        let ready = o.previous.map_or(0, |p|self.ends[p]);
        for at in 0..pos {
            let lo = if at == 0 {
                0
            }else {
                self.ends[seq[at-1]]
            };
            let s = lo.max(ready);
            if s+o.duration <= self.starts[seq[at]] {
                return Some((s, at))
            }
        }
        None
    }
    fn slacks(&self, ins: &Instance) -> (Vec<i64>, Vec<i64>) {
        let n = self.starts.len();
        let(mut latest, mut slack, mut free) = (vec![0; n], vec![0; n], vec![0; n]);
        for id in self.by_start().into_iter().rev() {
            let following = [ins.operations[id].next, self.next[id]].into_iter().flatten().collect::<Vec<_>>();
            latest[id] = following.iter().map(|&j|latest[j]).min().unwrap_or(self.makespan)-ins.operations[id].duration;
            slack[id] = latest[id]-self.starts[id];
            free[id] = following.iter().map(|&j|self.starts[j]).min().unwrap_or(self.makespan)-self.ends[id];
        }
        (slack, free)
    }
    fn flow(&self, ins: &Instance) -> i64 {
        ins.jobs.iter().map(|j|self.ends[*j.operations.last().unwrap()]).sum()
    }
    fn idle(&self, ins: &Instance) -> i64 {
        ins.machines.len() as i64*self.makespan-ins.machines.iter().map(|m|m.load).sum::<i64>()
    }
    fn letters(&self, ins: &Instance, m: usize) -> String {
        self.order[m].iter().map(|&i|letter(ins.jobs[ins.operations[i].job].number)).collect()
    }
}
fn order_starts(ins: &Instance, order: &[Vec<usize>], durations: &[i64]) -> Vec<i64> {
    let n = ins.operations.len();
    let mut starts = vec![-1; n];
    let mut ends = vec![0; n];
    let mut positions = vec![0; order.len()];
    let mut placed = 0;
    while placed<n {
        for(m, seq)in order.iter().enumerate() {
            while positions[m]<seq.len() {
                let pos = positions[m];
                let id = seq[pos];
                let p = ins.operations[id].previous;
                if p.is_some_and(|p|starts[p]<0) {
                    break
                }
                let ready = p.map_or(0, |p|ends[p]);
                let free = if pos == 0 {
                    0
                }else {
                    ends[seq[pos-1]]
                };
                starts[id] = ready.max(free);
                ends[id] = starts[id]+durations[id];
                positions[m] += 1;
                placed += 1;
            }
        }
    }
    starts
}
fn schedule_order(ins: &Instance, order: &[Vec<usize>]) -> Schedule {
    Schedule::new(ins, order_starts(ins, order, &ins.durations()))
}
fn order_value(ins: &Instance, order: &[Vec<usize>], durations: &[i64]) -> i64 {
    order_starts(ins, order, durations).iter().zip(durations).map(|(s, d)|s+d).max().unwrap()
}
fn apply_move(ins: &Instance, order: &[Vec<usize>], pair: (usize, usize)) -> Vec<Vec<usize>> {
    let mut out = order.to_vec();
    let seq = &mut out[ins.operations[pair.0].machine];
    let pos = seq.iter().position(|&i|i == pair.0).unwrap();
    seq.swap(pos, pos+1);
    out
}
fn distances(a: &Schedule, b: &Schedule) -> Vec<usize> {
    a.order.iter().zip(&b.order).map(|(x, y)| {
        let rank = y.iter().enumerate().map(|(i, &o)|(o, i)).collect::<BTreeMap<_, _>>(); let mut n = 0; for i in 0..x.len() {
            for j in i+1..x.len() {
                if rank[&x[i]]>rank[&x[j]] {
                    n += 1
                }
            }
        }
        n
    }).collect()
}
fn jackson(ins: &Instance, m: usize) -> i64 {
    let ids = &ins.machines[m].operations;
    let mut remaining = ids.iter().map(|&i|ins.operations[i].duration).collect::<Vec<_>>();
    let(mut t, mut bound) = (0, 0);
    while remaining.iter().any(|&r|r>0) {
        if !ids.iter().enumerate().any(|(k, &i)|remaining[k]>0 && ins.operations[i].head <= t) {
            t = ids.iter().enumerate().filter(|(k, _)|remaining[*k]>0).map(|(_, &i)|ins.operations[i].head).min().unwrap();
        }
        let k = ids.iter().enumerate().filter(|(k, i)|remaining[*k]>0 && ins.operations[**i].head <= t).max_by_key(|(_, &i)|(ins.operations[i].tail, std::cmp::Reverse(ins.operations[i].job))).unwrap().0;
        let later = ids.iter().map(|&i|ins.operations[i].head).filter(|&h|h>t).min();
        let step = remaining[k].min(later.map_or(remaining[k], |h|h-t));
        t += step;
        remaining[k] -= step;
        if remaining[k] == 0 {
            bound = bound.max(t+ins.operations[ids[k]].tail)
        }
    }
    bound
}
struct TabuRecord {
    iteration: usize,
    moves: usize,
    tabu: usize,
    pair: (usize, usize),
    aspiration: bool,
    value: i64,
    best: i64
}
struct Search {
    order: Vec<Vec<usize>>,
    start: i64,
    best: i64,
    found: usize,
    records: Vec<TabuRecord>,
    reason: String
}
fn tabu(ins: &Instance, initial: &[Vec<usize>], p: &Params) -> Search {
    let mut current = initial.to_vec();
    let start = order_value(ins, &current, &ins.durations());
    let mut out = Search {
        order: current.clone(),
        start,
        best: start,
        found: 0,
        records: vec![],
        reason: "limit".into()
    };
    let mut expiry = BTreeMap::new();
    for it in 1..=p.get("tabu_iterations") {
        let moves = schedule_order(ins, &current).moves(ins);
        if moves.is_empty() {
            out.reason = "no_moves".into();
            break
        }
        let values = moves.iter().map(|&m|order_value(ins, &apply_move(ins, &current, m), &ins.durations())).collect::<Vec<_>>();
        let is_tabu = moves.iter().map(|m|expiry.get(m).is_some_and(|&e|e >= it)).collect::<Vec<_>>();
        let chosen = (0..moves.len()).filter(|&i|!is_tabu[i] || values[i]<out.best).min_by_key(|&i|(values[i], i));
        let Some(i) = chosen else {
            out.reason = "all_tabu".into();
            break
        };
        let(u, v) = moves[i];
        current = apply_move(ins, &current, (u, v));
        expiry.insert((v, u), it+p.get("tabu_tenure"));
        if values[i]<out.best {
            out.order = current.clone();
            out.best = values[i];
            out.found = it;
        }
        out.records.push(TabuRecord {
            iteration: it,
            moves: moves.len(),
            tabu: is_tabu.iter().filter(| && b|b).count(),
            pair: (u, v),
            aspiration: is_tabu[i],
            value: values[i],
            best: out.best
        });
    }
    out
}
struct Baseline {
    schedule: Schedule,
    decisions: usize,
    ties: usize,
    search: Search
}
struct Ga {
    population: Vec<Vec<usize>>,
    values: Vec<i64>,
    records: Vec<(usize, i64, usize)>,
    progress: Vec<String>,
    crossovers: usize,
    swaps: usize,
    inserts: usize
}
fn ranking(values: &[i64]) -> Vec<usize> {
    let mut ids = (0..values.len()).collect::<Vec<_>>();
    ids.sort_by_key(|&i|(values[i], i));
    ids
}
fn gcd(mut a: i64, mut b: i64) -> i64 {
    while b != 0 {
        let r = a%b;
        a = b;
        b = r
    }
    a
}
fn run_ga(ins: &Instance, p: &Params, seeds: Vec<Vec<usize>>) -> Ga {
    let mut rng = Minstd {
        state: p.get("seed") as i64
    };
    let mut ga = Ga {
        population: seeds,
        values: vec![],
        records: vec![],
        progress: vec!["generation,best,mean,worst,distinct".into()],
        crossovers: 0,
        swaps: 0,
        inserts: 0
    };
    while ga.population.len()<p.get("population") {
        let mut c = ins.jobs.iter().enumerate().flat_map(|(j, job)|vec![j; job.operations.len()]).collect::<Vec<_>>();
        rng.shuffle(&mut c);
        ga.population.push(c);
    }
    let checkpoints = p.v["checkpoints"].iter().map(|s|s.parse().unwrap()).collect::<BTreeSet<usize>>();
    let mut previous = i64::MAX;
    for g in 0..=p.get("generations") {
        ga.values = ga.population.iter().map(|c|Schedule::new(ins, decode(ins, c)).makespan).collect();
        let rank = ranking(&ga.values);
        let best = ga.values[rank[0]];
        if best<previous {
            ga.records.push((g, best, rank[0]+1));
        }
        previous = best;
        if checkpoints.contains(&g) {
            let total = ga.values.iter().sum::<i64>();
            let divisor = gcd(total, ga.values.len() as i64);
            let distinct = ga.population.iter().collect::<BTreeSet<_>>().len();
            ga.progress.push(format!("{g},{best},{}/{},{},{distinct}", total/divisor, ga.values.len() as i64/divisor, ga.values.iter().max().unwrap()));
        }
        if g == p.get("generations") {
            break
        }
        let mut children = rank.iter().take(p.get("elitism")).map(|&i|ga.population[i].clone()).collect::<Vec<_>>();
        while children.len()<ga.population.len() {
            let a = tournament(&mut rng, &ga.values, p.get("tournament"));
            let b = tournament(&mut rng, &ga.values, p.get("tournament"));
            let(mut first, mut second) = if rng.chance(p.chance("crossover")) {
                ga.crossovers += 1;
                crossover(&mut rng, &ga.population[a], &ga.population[b], ins.jobs.len())
            }else {
                (ga.population[a].clone(), ga.population[b].clone())
            };
            for c in [&mut first, &mut second] {
                if rng.chance(p.chance("swap_mutation")) {
                    ga.swaps += 1;
                    swap_mutation(&mut rng, c);
                }
                if rng.chance(p.chance("insert_mutation")) {
                    ga.inserts += 1;
                    insert_mutation(&mut rng, c);
                }
            }
            children.push(first);
            children.push(second);
        }
        ga.population = children;
    }
    ga
}
fn write_lines(name: &str, lines: Vec<String>) -> io::Result<()> {
    fs::write(format!("output/{name}"), lines.join("\n")+"\n")
}
fn main() -> io::Result<()> {
    let ins = Instance::read()?;
    let p = Params::read()?;
    let baselines = RULES.iter().map(|rule| {
        let(starts, decisions, ties) = dispatch(&ins, rule, &[]); let schedule = Schedule::new(&ins, starts); let search = tabu(&ins, &schedule.order, &p); Baseline {
            schedule,
            decisions,
            ties,
            search
        }
    }).collect::<Vec<_>>();
    let jacksons = (0..ins.machines.len()).map(|m|jackson(&ins, m)).collect::<Vec<_>>();
    let jb = (0..ins.jobs.len()).max_by_key(|&j|(ins.jobs[j].work, std::cmp::Reverse(j))).unwrap();
    let mb = (0..ins.machines.len()).max_by_key(|&m|(ins.machines[m].bound, std::cmp::Reverse(m))).unwrap();
    let jx = (0..jacksons.len()).max_by_key(|&m|(jacksons[m], std::cmp::Reverse(m))).unwrap();
    let lb = ins.jobs[jb].work.max(ins.machines[mb].bound).max(jacksons[jx]);
    let ga = run_ga(&ins, &p, baselines.iter().map(|b|b.schedule.chromosome(&ins)).collect());
    let rank = ranking(&ga.values);
    let genes = &ga.population[rank[0]];
    let ga_schedule = Schedule::new(&ins, decode(&ins, genes));
    let mut positions = vec![0; ins.operations.len()];
    for(pos, id)in gene_operations(&ins, genes).iter().enumerate() {
        positions[*id] = pos+1;
    }
    let(active, active_decisions, _) = dispatch(&ins, "GENES", &positions);
    let active_value = Schedule::new(&ins, active).makespan;
    let mut activated = ga_schedule.order.clone();
    let mut shifts = vec![];
    loop {
        let s = schedule_order(&ins, &activated);
        let candidate = s.by_start().iter().find_map(|&id|s.left_shift(&ins, id).map(|(start, at)|(id, start, at)));
        let Some((id, start, at)) = candidate else {
            break
        };
        let seq = &mut activated[ins.operations[id].machine];
        let pos = seq.iter().position(|&i|i == id).unwrap();
        seq.remove(pos);
        seq.insert(at, id);
        shifts.push((id, s.starts[id], start));
    }
    let search = tabu(&ins, &activated, &p);
    let final_schedule = schedule_order(&ins, &search.order);
    let s = &final_schedule;
    let path = s.path(&ins);
    let blocks = s.blocks(&ins);
    let counts = s.path_counts(&ins);
    let bottleneck = s.bottleneck(&ins);
    let(slack, free) = s.slacks(&ins);
    let mut base = vec![format!("INSTANCE jobs {} machines {} operations {} work {} errors {}", ins.jobs.len(), ins.machines.len(), ins.operations.len(), ins.jobs.iter().map(|j|j.work).sum::<i64>(), ins.errors.len())];
    base.extend(ins.errors.iter().map(|e|format!("ERROR {e}")));
    for j in &ins.jobs {
        base.push(format!("JOB J{} operations {} work {} route {}", j.number, j.operations.len(), j.work, j.operations.iter().map(|&i|format!("M{}", ins.operations[i].machine+1)).collect::<Vec<_>>().join(" ")));
    }
    for(m, machine)in ins.machines.iter().enumerate() {
        base.push(format!("MACHINE M{} operations {} load {} head {} tail {} bound {} jackson {}", m+1, machine.operations.len(), machine.load, machine.head, machine.tail, machine.bound, jacksons[m]));
    }
    base.extend([format!("BOUND job {} J{}", ins.jobs[jb].work, ins.jobs[jb].number), format!("BOUND machine {} M{}", ins.machines[mb].bound, mb+1), format!("BOUND jackson {} M{}", jacksons[jx], jx+1), format!("BOUND lower {lb}")]);
    for(i, b)in baselines.iter().enumerate() {
        let rule = RULES[i];
        let c = b.schedule.makespan;
        base.push(format!("RULE {rule} makespan {c} gap {} flow {} idle {} decisions {} ties {}", percentage(c-lb, lb), b.schedule.flow(&ins), b.schedule.idle(&ins), b.decisions, b.ties));
        base.push(format!("PATH {rule} operations {} blocks {} critical_paths {} bottleneck M{}", b.schedule.path(&ins).len(), b.schedule.blocks(&ins).len(), b.schedule.path_count(&ins), b.schedule.bottleneck(&ins)+1));
        base.push(format!("TABU {rule} makespan {c} -> {} found {} iterations {} stop {}", b.search.best, b.search.found, b.search.records.len(), b.search.reason));
    }
    let best = (0..4).min_by_key(|&i|(baselines[i].schedule.makespan, i)).unwrap();
    base.push(format!("BEST {} makespan {}", RULES[best], baselines[best].schedule.makespan));
    for(m, machine)in ins.machines.iter().enumerate() {
        base.push(format!("UTILIZATION M{} {}", m+1, (0..4).map(|i|format!("{} {}", RULES[i], percentage(machine.load, baselines[i].schedule.makespan))).collect::<Vec<_>>().join(" ")));
    }
    let mut out = vec![format!("GA best {} generation {} crossovers {} swaps {} inserts {}", ga_schedule.makespan, ga.records.last().unwrap().0, ga.crossovers, ga.swaps, ga.inserts)];
    for&(g, c, i)in &ga.records {
        out.push(format!("RECORD generation {g} makespan {c} individual {i}"));
    }
    let mut seen = BTreeSet::new();
    let mut top = 0;
    for&i in &rank {
        if !seen.insert(ga.population[i].clone()) {
            continue
        }
        top += 1;
        let distance: usize = distances(&Schedule::new(&ins, decode(&ins, &ga.population[i])), &ga_schedule).iter().sum();
        out.push(format!("TOP {top} individual {} makespan {} distance {distance}", i+1, ga.values[i]));
        if top == 5 {
            break
        }
    }
    out.push(format!("GA_CHROMOSOME {}", integers(genes.iter().map(|&j|ins.jobs[j].number))));
    out.push(format!("ACTIVE_DECODE makespan {active_value} decisions {active_decisions}"));
    for(i, &(id, old, new))in shifts.iter().enumerate() {
        out.push(format!("SHIFT {} {} M{} start {old} -> {new}", i+1, ins.code(id), ins.operations[id].machine+1));
    }
    out.push(format!("ACTIVATED makespan {} -> {} shifts {}", ga_schedule.makespan, search.start, shifts.len()));
    out.push(format!("SCHEDULE makespan {} lower_bound {lb} gap {} improvement {} shiftable {}", s.makespan, percentage(s.makespan-lb, lb), ga_schedule.makespan-s.makespan, (0..ins.operations.len()).filter(|&i|s.left_shift(&ins, i).is_some()).count()));
    out.push(format!("CHROMOSOME {}", integers(s.chromosome(&ins).iter().map(|&j|ins.jobs[j].number))));
    out.push(format!("LEGEND {}", ins.jobs.iter().map(|j|format!("{}=J{}", letter(j.number), j.number)).collect::<Vec<_>>().join(" ")));
    let(q, n) = gantt::scale(s.makespan, p.get("gantt_width") as i64);
    let on_path = path.iter().copied().collect::<BTreeSet<_>>();
    let mut intervals = vec![vec![]; ins.machines.len()];
    for(i, o)in ins.operations.iter().enumerate() {
        let mut mark = letter(ins.jobs[o.job].number);
        if on_path.contains(&i) {
            mark = mark.to_ascii_lowercase()
        }
        intervals[o.machine].push((s.starts[i], s.ends[i], mark));
    }
    out.extend([format!("GANTT scale {q} columns {n}"), gantt::time_row(q, n), gantt::rule_row(n)]);
    for(m, row)in intervals.iter().enumerate() {
        out.push(gantt::chart_row(&format!("M{}", m+1), row, q, n));
    }
    out.push(gantt::busy_row(&intervals, q, n));
    for j in &ins.jobs {
        let row = j.operations.iter().map(|&i|(s.starts[i], s.ends[i], char::from(b'0'+((ins.operations[i].machine+1)%10)as u8))).collect::<Vec<_>>();
        out.push(gantt::chart_row(&format!("J{}", j.number), &row, q, n));
    }
    for m in 0..ins.machines.len() {
        out.push(format!("ORDER M{} FINAL {} {}", m+1, s.letters(&ins, m), (0..4).map(|i|format!("{} {}", RULES[i], baselines[i].schedule.letters(&ins, m))).collect::<Vec<_>>().join(" ")));
    }
    for(m, machine)in ins.machines.iter().enumerate() {
        let seq = &s.order[m];
        let gaps = seq.windows(2).map(|a|s.starts[a[1]]-s.ends[a[0]]).filter(|&x|x>0).collect::<Vec<_>>();
        let sequence = seq.iter().map(|&i|format!("J{}:{}-{}", ins.jobs[ins.operations[i].job].number, s.starts[i], s.ends[i])).collect::<Vec<_>>().join(" ");
        out.push(format!("MACHINE M{} load {} idle {} utilization {} gaps {} longest_gap {} sequence {sequence}", m+1, machine.load, s.makespan-machine.load, percentage(machine.load, s.makespan), gaps.len(), gaps.iter().max().unwrap_or(&0)));
        let mut idle = vec![(0, s.starts[seq[0]])];
        idle.extend(seq.windows(2).map(|a|(s.ends[a[0]], s.starts[a[1]])));
        idle.push((s.ends[*seq.last().unwrap()], s.makespan));
        let text = idle.iter().filter(|(a, b)|b>a).map(|(a, b)|format!("{a}-{b}")).collect::<Vec<_>>().join(" ");
        out.push(format!("IDLE M{} {}", m+1, if text.is_empty() {
            "none"
        }else {
            &text
        }));
    }
    let mut waiting = 0;
    for j in &ins.jobs {
        let completion = s.ends[*j.operations.last().unwrap()];
        waiting += completion-j.work;
        out.push(format!("JOB J{} operations {} work {} start {} completion {completion} waiting {}", j.number, j.operations.len(), j.work, s.starts[j.operations[0]], completion-j.work));
    }
    out.push(format!("TOTAL flow {} waiting {waiting} idle {}", s.flow(&ins), s.idle(&ins)));
    let others = baselines.iter().map(|b|&b.schedule).chain([&ga_schedule]).collect::<Vec<_>>();
    let labels = ["SPT", "LPT", "MWKR", "FIFO", "GA"];
    let distance = others.iter().map(|b|distances(s, b)).collect::<Vec<_>>();
    let mut pairs_total = 0;
    for(m, machine)in ins.machines.iter().enumerate() {
        let count = machine.operations.len();
        let pairs = count*(count-1)/2;
        pairs_total += pairs;
        out.push(format!("DISTANCE M{} pairs {pairs} {}", m+1, (0..5).map(|i|format!("{} {}", labels[i], distance[i][m])).collect::<Vec<_>>().join(" ")));
    }
    out.push(format!("DISTANCE total pairs {pairs_total} {}", (0..5).map(|i|format!("{} {}", labels[i], distance[i].iter().sum::<usize>())).collect::<Vec<_>>().join(" ")));
    let mut critical = vec![format!("SEARCH start {} iterations {} tenure {}", search.start, p.get("tabu_iterations"), p.get("tabu_tenure"))];
    for r in &search.records {
        critical.push(format!("ITER {} moves {} tabu {} swap M{} {} {} {} makespan {} best {}", r.iteration, r.moves, r.tabu, ins.operations[r.pair.0].machine+1, ins.code(r.pair.0), ins.code(r.pair.1), if r.aspiration {
            "aspiration"
        }else {
            "free"
        }, r.value, r.best));
    }
    critical.push(format!("STOP iterations {} reason {} best {} found {}", search.records.len(), search.reason, search.best, search.found));
    critical.push(format!("PATH operations {} blocks {} makespan {} critical_paths {}", path.len(), blocks.len(), s.makespan, s.path_count(&ins)));
    for(k, &id)in path.iter().enumerate() {
        let link = if k == 0 {
            "start"
        }else if s.previous[id] == Some(path[k-1]) {
            "machine"
        }else {
            "job"
        };
        critical.push(format!("NODE {} {} M{} {}-{} {link}", k+1, ins.code(id), ins.operations[id].machine+1, s.starts[id], s.ends[id]));
    }
    for(k, b)in blocks.iter().enumerate() {
        critical.push(format!("BLOCK {} M{} {}-{} {}", k+1, ins.operations[b[0]].machine+1, s.starts[b[0]], s.ends[*b.last().unwrap()], b.iter().map(|&i|ins.code(i)).collect::<Vec<_>>().join(" ")));
    }
    for(k, pair)in s.moves(&ins).iter().enumerate() {
        critical.push(format!("NEIGHBOUR {} M{} {} {} makespan {}", k+1, ins.operations[pair.0].machine+1, ins.code(pair.0), ins.code(pair.1), order_value(&ins, &apply_move(&ins, &s.order, *pair), &ins.durations())));
    }
    critical.push(format!("CRITICAL operations {} total {}", slack.iter().filter(| && x|x == 0).count(), ins.operations.len()));
    for(label, values)in [("SLACK", &slack), ("FREE", &free)] {
        for j in &ins.jobs {
            critical.push(format!("{label} J{} {}", j.number, j.operations.iter().map(|&i|values[i].to_string()).collect::<Vec<_>>().join(" ")));
        }
    }
    for(m, machine)in ins.machines.iter().enumerate() {
        let durations = ins.operations.iter().map(|o|o.duration+if o.machine == m {
            (o.duration+9)/10
        }else {
            0
        }).collect::<Vec<_>>();
        let sensitivity = order_value(&ins, &s.order, &durations);
        critical.push(format!("MACHINE M{} critical {} path {} sensitivity {sensitivity} delta {}", m+1, machine.operations.iter().filter(| && i|slack[i] == 0).count(), counts[m], sensitivity-s.makespan));
    }
    critical.push(format!("BOTTLENECK M{} path {}", bottleneck+1, counts[bottleneck]));
    fs::create_dir_all("output")?;
    write_lines("baselines.txt", base)?;
    write_lines("ga_progress.csv", ga.progress)?;
    write_lines("best_schedule.txt", out)?;
    write_lines("critical_path.txt", critical)
}
