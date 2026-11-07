use std::{
    fs, io, collections::BTreeSet
};
pub struct Operation {
    pub job: usize,
    pub index: usize,
    pub machine: usize,
    pub duration: i64,
    pub head: i64,
    pub tail: i64,
    pub previous: Option<usize>,
    pub next: Option<usize>
}
pub struct Job {
    pub number: usize,
    pub operations: Vec<usize>,
    pub work: i64
}
pub struct Machine {
    pub operations: Vec<usize>,
    pub load: i64,
    pub head: i64,
    pub tail: i64,
    pub bound: i64
}
pub struct Instance {
    pub jobs: Vec<Job>,
    pub operations: Vec<Operation>,
    pub machines: Vec<Machine>,
    pub errors: Vec<String>
}
impl Instance {
    pub fn read() -> io::Result<Self> {
        let text = fs::read_to_string("input/instance.txt")?;
        let mut lines = text.lines();
        let dims: Vec<usize >= lines.next().unwrap().split(' ').map(|s|s.parse().unwrap()).collect();
        let(mut jobs, mut operations, mut errors) = (vec![], vec![], vec![]);
        for(number, line)in lines.take(dims[0]).enumerate() {
            let mut steps = vec![];
            let mut seen = BTreeSet::new();
            let mut valid = true;
            for(index, token)in line.split(' ').enumerate() {
                let(m, d) = token.split_once(':').unwrap();
                let m: usize = m.parse().unwrap();
                let d: i64 = d.parse().unwrap();
                let reason = if m<1 || m>dims[1] {
                    Some(format!("unknown machine {m}"))
                }else if !(1..=99).contains(&d) {
                    Some(format!("bad duration {d}"))
                }else if !seen.insert(m) {
                    Some(format!("repeated machine {m}"))
                }else {
                    None
                };
                if let Some(reason) = reason {
                    errors.push(format!("job {} operation {}: {reason}", number+1, index+1));
                    valid = false;
                    break
                }
                steps.push((m-1, d));
            }
            if !valid {
                continue
            }
            let work = steps.iter().map(|(_, d)|d).sum();
            let first = operations.len();
            let count = steps.len();
            let mut head = 0;
            for(index, (machine, duration))in steps.into_iter().enumerate() {
                operations.push(Operation {
                    job: jobs.len(),
                    index: index+1,
                    machine,
                    duration,
                    head,
                    tail: work-head-duration,
                    previous: if index == 0 {
                        None
                    }else {
                        Some(first+index-1)
                    },
                    next: if index+1 == count {
                        None
                    }else {
                        Some(first+index+1)
                    }
                });
                head += duration;
            }
            jobs.push(Job {
                number: number+1,
                operations: (first..operations.len()).collect(),
                work
            });
        }
        let machines = (0..dims[1]).map(|m| {
            let ids: Vec<usize >= operations.iter().enumerate().filter(|(_, o)|o.machine == m).map(|(i, _)|i).collect(); let load = ids.iter().map(|&i|operations[i].duration).sum(); let head = ids.iter().map(|&i|operations[i].head).min().unwrap(); let tail = ids.iter().map(|&i|operations[i].tail).min().unwrap(); Machine {
                operations: ids,
                load,
                head,
                tail,
                bound: head+load+tail
            }
        }).collect();
        Ok(Self {
            jobs,
            operations,
            machines,
            errors
        })
    }
    pub fn durations(&self) -> Vec<i64> {
        self.operations.iter().map(|o|o.duration).collect()
    }
    pub fn code(&self, i: usize) -> String {
        let o = &self.operations[i];
        format!("J{}-{}", self.jobs[o.job].number, o.index)
    }
}
