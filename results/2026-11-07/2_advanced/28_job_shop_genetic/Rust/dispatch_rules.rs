use crate::instance::Instance;
pub const RULES: [&str; 4] = ["SPT", "LPT", "MWKR", "FIFO"];
pub fn dispatch(ins: &Instance, rule: &str, genes: &[usize]) -> (Vec<i64>, usize, usize) {
    let mut starts = vec![0; ins.operations.len()];
    let mut next = vec![0; ins.jobs.len()];
    let mut ready = vec![0i64; ins.jobs.len()];
    let mut free = vec![0i64; ins.machines.len()];
    let(mut decisions, mut ties) = (0, 0);
    for _ in 0..starts.len() {
        let candidates: Vec<(usize, i64) >= ins.jobs.iter().enumerate().filter(|(j, job)|next[*j]<job.operations.len()).map(|(j, job)| {
            let id = job.operations[next[j]]; (id, ready[j].max(free[ins.operations[id].machine]))
        }).collect();
        let cutoff = candidates.iter().map(|&(id, s)|s+ins.operations[id].duration).min().unwrap();
        let machine = candidates.iter().filter(| && (id, s)|s+ins.operations[id].duration == cutoff).map(|&(id, _)|ins.operations[id].machine).min().unwrap();
        let conflict: Vec<(usize, i64) >= candidates.into_iter().filter(|&(id, s)|ins.operations[id].machine == machine && s<cutoff).collect();
        let priority = |id: usize| {
            let o = &ins.operations[id];
            match rule {
                "SPT" => o.duration, "LPT" => -o.duration, "MWKR" => -o.duration-o.tail, "FIFO" => ready[o.job], _ => genes[id] as i64
            }
        };
        let low = conflict.iter().map(|&(id, _)|priority(id)).min().unwrap();
        if conflict.len()>1 {
            decisions += 1
        }
        if conflict.iter().filter(| && (id, _)|priority(id) == low).count()>1 {
            ties += 1
        }
        let(id, start) = *conflict.iter().find(| && (id, _)|priority(id) == low).unwrap();
        let o = &ins.operations[id];
        starts[id] = start;
        ready[o.job] = start+o.duration;
        free[machine] = start+o.duration;
        next[o.job] += 1;
    }
    (starts, decisions, ties)
}
