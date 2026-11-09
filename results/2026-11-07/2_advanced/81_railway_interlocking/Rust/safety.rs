use crate::layout::Layout;
use crate::interlocking::Interlocking;
pub const NAMES: [&str;4] = ["OCCUPANCY","POINT_MOTION","CONFLICT","SIGNAL_PASSING"];
pub struct Checker {
    pub checks: [usize;4],
    pub violations: [usize;4],
    pub records: Vec<String>
}
impl Checker {
    pub fn new() -> Self {
        Self {
            checks: [0;4],
            violations: [0;4],
            records: Vec::new()
        }
    }
    fn record(&mut self, time: usize, property: usize, details: String) {
        self.violations[property] += 1;
        self.records.push(format!("VIOLATION {} {} {}",time,NAMES[property],details));
    }
    pub fn passing(&mut self, time: usize, train: &str, signal: &str, red: bool) {
        self.checks[3] += 1;
        if red {
            self.record(time,3,format!("{} {}",train,signal));
        }
    }
    pub fn check(&mut self, time: usize, layout: &Layout, locks: &Interlocking, occupancy: &[Vec<usize>], trains: &[String]) {
        for (s,section) in layout.sections.iter().enumerate() {
            self.checks[0] += 1;
            if occupancy[s].len() >= 2 {
                self.record(time,0,format!("{} {}",section.name,occupancy[s].iter().map(|&t| trains[t].as_str()).collect::<Vec<_>>().join(",")));
            }
        }
        for (p,point) in layout.points.iter().enumerate() {
            if point.motion.is_none() {
                continue;
            }
            self.checks[1] += 1;
            if !occupancy[point.common].is_empty() {
                self.record(time,1,format!("{} occupied",point.name));
            } else if locks.point_locks[p].iter().any(|&(r,_)| locks.routes[r].state == 2 || locks.routes[r].state == 3) {
                self.record(time,1,format!("{} locked",point.name));
            }
        }
        for a in 0..locks.routes.len() {
            if locks.routes[a].state != 1 && locks.routes[a].state != 3 {
                continue;
            }
            for b in a+1..locks.routes.len() {
                if locks.routes[b].state != 1 && locks.routes[b].state != 3 {
                    continue;
                }
                self.checks[2] += 1;
                if locks.routes[a].conflicts.contains(&b) || locks.routes[b].conflicts.contains(&a) {
                    self.record(time,2,format!("{} {}",locks.routes[a].name,locks.routes[b].name));
                }
            }
        }
    }
    pub fn lines(&self) -> Vec<String> {
        let mut lines: Vec<_> = (0..4).map(|i| format!("{} {} checks {} violations {}",NAMES[i],if self.violations[i] == 0 {
            "OK"
        } else {
            "FAIL"
        },self.checks[i],self.violations[i])).collect();
        lines.extend(self.records.clone());
        lines.push(format!("RESULT {}",if self.violations.iter().all(|&v| v == 0) {
            "SAFE"
        } else {
            "UNSAFE"
        }));
        lines
    }
}
