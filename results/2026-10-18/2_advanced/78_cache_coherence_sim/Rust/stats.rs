use std::collections::BTreeSet;
#[derive(Clone,Default)] pub struct Core {
    pub accesses: usize,
    pub reads: usize,
    pub writes: usize,
    pub hits: usize,
    pub misses: usize,
    pub fences: usize,
    pub classes: [usize;6],
    pub service: [usize;6],
    pub bus: [usize;5],
    pub snoop: [usize;4],
    pub latency: usize,
    pub fence_stall: usize,
    pub finish: usize
}
pub const SERVICE: [&str;6] = ["l1","upgrade","through","cache","l2","memory"];
pub fn fraction(mut p: usize, mut q: usize) -> String {
    let (a,b) = (p,q);
    while q != 0 {
        let r = p%q;
        p = q;
        q = r;
    }
    format!("{}/{}",a/p,b/p)
}
pub fn decimal(p: usize, q: usize) -> String {
    let rounded = (2*p*100+q)/(2*q);
    format!("{}.{:02}",rounded/100,rounded%100)
}
pub fn amat(latency: usize, accesses: usize) -> String {
    if accesses == 0 {
        "-".to_owned()
    } else {
        format!("{} {}",fraction(latency,accesses),decimal(latency,accesses))
    }
}
pub fn cores(cores: &BTreeSet<usize>) -> String {
    if cores.is_empty() {
        "-".to_owned()
    } else {
        cores.iter().map(usize::to_string).collect()
    }
}
pub fn ranges(labels: &[&str], counts: &[usize]) -> String {
    labels.iter().zip(counts).map(|(name,count)| format!("{}:{}",name,count)).collect::<Vec<_>>().join(" ")
}
pub fn total(cores: &[Core]) -> Core {
    let mut total = Core::default();
    for c in cores {
        total.accesses += c.accesses;
        total.reads += c.reads;
        total.writes += c.writes;
        total.hits += c.hits;
        total.misses += c.misses;
        total.fences += c.fences;
        for i in 0..6 {
            total.classes[i] += c.classes[i];
            total.service[i] += c.service[i];
        }
        for i in 0..5 {
            total.bus[i] += c.bus[i];
        }
        for i in 0..4 {
            total.snoop[i] += c.snoop[i];
        }
        total.latency += c.latency;
        total.fence_stall += c.fence_stall;
        total.finish = total.finish.max(c.finish);
    }
    total
}
pub fn lines(name: &str, c: &Core) -> Vec<String> {
    vec![format!("{} accesses {} reads {} writes {} hits {} misses {} fences {}",name,c.accesses,c.reads,c.writes,c.hits,c.misses,c.fences),format!("{} misses compulsory {} capacity {} conflict {} coherence {} true_sharing {} false_sharing {}",name,c.classes[0],c.classes[1],c.classes[2],c.classes[3],c.classes[4],c.classes[5]),format!("{} service l1 {} upgrade {} through {} cache {} l2 {} memory {}",name,c.service[0],c.service[1],c.service[2],c.service[3],c.service[4],c.service[5]),format!("{} bus BusRd {} BusRdX {} BusUpgr {} BusWr {} WB {}",name,c.bus[0],c.bus[1],c.bus[2],c.bus[3],c.bus[4]),format!("{} snoop invalidations_sent {} invalidations_received {} supplied {} back_invalidations {}",name,c.snoop[0],c.snoop[1],c.snoop[2],c.snoop[3]),format!("{} time latency {} amat {} fence_stall {} finish {}",name,c.latency,amat(c.latency,c.accesses),c.fence_stall,c.finish)]
}
