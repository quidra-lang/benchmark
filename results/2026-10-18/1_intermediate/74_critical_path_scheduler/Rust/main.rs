use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};
type Answer = Result<Vec<String>, String>;

fn fail(s: impl Into<String>) -> String {
    format!("error: {}",s.into())
}

fn signed(n: i64) -> String {
    format!("{:+}",n)
}

fn decimal(n: i64,d: i64) -> String {
    let h = n*100/d;
    format!("{}.{:02}",h/100,h%100)
}

fn leap(y: i64) -> bool {
    y%4 == 0 && (y%100 != 0 || y%400 == 0)
}

fn month_days(y: i64,m: i64) -> i64 {
    if m == 2 && leap(y) {
        29
    } else {
        [31,28,31,30,31,30,31,31,30,31,30,31][m as usize-1]
    }
}

fn date(text: &str) -> Result<i64,String> {
    let p: Vec<i64> = text.split('-').map(|s| s.parse().unwrap()).collect();
    let (y,m,d) = (p[0],p[1],p[2]);
    if !(1..=12).contains(&m) || d < 1 || d > month_days(y,m) {
        return Err(fail(format!("invalid date {}",text)));
    }
    let day: i64 = (2000..y).map(|year| if leap(year) {
        366
    } else {
        365
    }).sum::<i64>()+(1..m).map(|month| month_days(y,month)).sum::<i64>();
    Ok(day+d-1)
}

fn date_text(day: i64) -> String {
    let mut left = day;
    let mut y = 2000;
    while left >= if leap(y) {
        366
    } else {
        365
    }
    {
        left -= if leap(y) {
            366
        } else {
            365
        };
        y += 1;
    }
    let mut m = 1;
    while left >= month_days(y,m) {
        left -= month_days(y,m);
        m += 1;
    }
    format!("{:04}-{:02}-{:02} {}",y,m,left+1,["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][(day as usize+5)%7])
}

#[derive(Clone)]
struct Task {
    base: i64,
    resource: String,
    units: i64,
    not_before: i64,
    crash: Option<(i64,i64)>,
    used: i64,
    pert: Option<[i64;3]>,
}

impl Task {
    fn duration(&self) -> i64 {
        self.base-self.used
    }
}

struct Dep {
    a: String,
    b: String,
    kind: String,
    lag: i64,
}

#[derive(Clone)]
struct Times {
    duration: i64,
    es: i64,
    ef: i64,
    ls: i64,
    lf: i64,
    tf: i64,
    ff: i64,
}

struct Schedule {
    times: BTreeMap<String,Times>,
    total: i64,
}

struct Baseline {
    total: i64,
    times: BTreeMap<String,(i64,i64)>,
}

#[derive(Default)]
struct Project {
    tasks: BTreeMap<String,Task>,
    deps: Vec<Dep>,
    holidays: BTreeSet<i64>,
    capacities: BTreeMap<String,i64>,
    start: Option<i64>,
    deadline: Option<i64>,
    baseline: Option<Baseline>,
}

impl Project {
    fn task(&self,n: &str) -> Result<&Task,String> {
        self.tasks.get(n).ok_or_else(|| fail(format!("unknown task {}",n)))
    }
    fn preds(&self,n: &str) -> Vec<&Dep> {
        let mut p: Vec<_> = self.deps.iter().filter(|e| e.b == n).collect();
        p.sort_by(|x,y| x.a.cmp(&y.a));
        p
    }
    fn succs(&self,n: &str) -> Vec<&Dep> {
        let mut p: Vec<_> = self.deps.iter().filter(|e| e.a == n).collect();
        p.sort_by(|x,y| x.b.cmp(&y.b));
        p
    }
    fn order(&self) -> (Vec<String>,Option<String>) {
        let mut remaining: BTreeSet<String> = self.tasks.keys().cloned().collect();
        let mut order = Vec::new();
        while let Some(n) = remaining.iter().find(|n| self.preds(n).iter().all(|e| !remaining.contains(&e.a))).cloned() {
            remaining.remove(&n);
            order.push(n);
        }
        if remaining.is_empty() {
            return (order,None);
        }
        let mut walked = vec![remaining.first().unwrap().clone()];
        loop {
            let n = self.preds(walked.last().unwrap()).into_iter().find(|e| remaining.contains(&e.a)).unwrap().a.clone();
            if let Some(q) = walked.iter().position(|t| *t == n) {
                let mut cycle = vec![n];
                cycle.extend(walked[q+1..].iter().rev().cloned());
                let k = (0..cycle.len()).min_by_key(|&i| &cycle[i]).unwrap();
                cycle.rotate_left(k);
                cycle.push(cycle[0].clone());
                return (order,Some(cycle.join(" -> ")));
            }
            walked.push(n);
        }
    }
    fn schedule(&self,changed: Option<(&str,i64)>) -> Schedule {
        let order = self.order().0;
        let mut times: BTreeMap<String,Times> = BTreeMap::new();
        for n in &order {
            let t = &self.tasks[n];
            let d = changed.filter(|(name,_)| *name == n.as_str()).map_or(t.duration(),|(_,d)| d);
            let mut es = t.not_before;
            for e in self.preds(n) {
                let p = &times[&e.a];
                es = es.max(match e.kind.as_str() {
                    "FS" => p.ef+e.lag, "SS" => p.es+e.lag, _ => p.ef+e.lag-d
                });
            }
            times.insert(n.clone(),Times {
                duration:d,es,ef:es+d,ls:0,lf:0,tf:0,ff:0
            });
        }
        let total = times.values().map(|t| t.ef).max().unwrap();
        for n in order.iter().rev() {
            let d = times[n].duration;
            let mut lf = total;
            for e in self.succs(n) {
                let p = &times[&e.b];
                lf = lf.min(match e.kind.as_str() {
                    "FS" => p.ls-e.lag,"SS" => p.ls-e.lag+d,_ => p.lf-e.lag
                });
            }
            let t = times.get_mut(n).unwrap();
            t.lf = lf;
            t.ls = lf-d;
            t.tf = t.ls-t.es;
        }
        let mut s = Schedule {
            times,total
        };
        for n in &order {
            let ff = self.succs(n).iter().map(|e| self.margin(e,&s)).fold(total-s.times[n].ef,i64::min);
            s.times.get_mut(n).unwrap().ff = ff;
        }
        s
    }
    fn margin(&self,e: &Dep,s: &Schedule) -> i64 {
        let a = &s.times[&e.a];
        let b = &s.times[&e.b];
        match e.kind.as_str() {
            "FS" => b.es-a.ef-e.lag,"SS" => b.es-a.es-e.lag,_ => b.ef-a.ef-e.lag
        }
    }
    fn critical(&self,s: &Schedule) -> Vec<String> {
        self.tasks.keys().filter(|n| s.times[*n].tf == 0).cloned().collect()
    }
    fn paths(&self,s: &Schedule) -> Vec<Vec<String>> {
        let links: Vec<&Dep> = self.deps.iter().filter(|e| s.times[&e.a].tf == 0 && s.times[&e.b].tf == 0 && self.margin(e,s) == 0).collect();
        let mut result = Vec::new();
        fn visit(p: Vec<String>,links: &[&Dep],result: &mut Vec<Vec<String>>) {
            let mut next: Vec<String> = links.iter().filter(|e| e.a == *p.last().unwrap()).map(|e| e.b.clone()).collect();
            next.sort();
            if next.is_empty() {
                result.push(p);
            } else {
                for n in next {
                    let mut q = p.clone();
                    q.push(n);
                    visit(q,links,result);
                }
            }
        }
        for n in self.critical(s) {
            if !links.iter().any(|e| e.b == n) {
                visit(vec![n],&links,&mut result);
            }
        }
        result
    }
    fn working(&self,d: i64) -> bool {
        (d+5)%7 < 5 && !self.holidays.contains(&d)
    }
    fn usage(&self,r: &str,times: &BTreeMap<String,(i64,i64)>,total: i64) -> Vec<i64> {
        (0..total).map(|day| self.tasks.iter().filter(|(n,t)| t.resource == r && day >= times[*n].0 && day < times[*n].1).map(|(_,t)| t.units).sum()).collect()
    }
    fn command(&mut self,w: &[&str]) -> Answer {
        let c = w[0];
        let a = &w[1..];
        let num = |i: usize| -> i64 {
            a[i].parse().unwrap()
        };
        let mut out = Vec::new();
        match c {
            "TASK" => {
                if self.tasks.contains_key(a[0]) {
                    return Err(fail(format!("task {} already exists",a[0])));
                }
                self.tasks.insert(a[0].into(),Task {
                    base:num(1),resource:a[2].into(),units:num(3),not_before:0,crash:None,used:0,pert:None
                });
                return Ok(vec![format!("task {} added",a[0])]);
            }
            "DEP"|"UNDEP" => {
                self.task(a[0])?;
                self.task(a[1])?;
                let i = self.deps.iter().position(|e| e.a == a[0] && e.b == a[1]);
                if c == "DEP" {
                    if a[0] == a[1] {
                        return Err(fail(format!("self dependency {}",a[0])));
                    }
                    if i.is_some() {
                        return Err(fail(format!("dependency {} -> {} already exists",a[0],a[1])));
                    }
                    self.deps.push(Dep {
                        a:a[0].into(),b:a[1].into(),kind:a[2].into(),lag:num(3)
                    });
                    return Ok(vec![format!("dependency {} -> {} {}{} added",a[0],a[1],a[2],signed(num(3)))]);
                }
                let i = i.ok_or_else(|| fail(format!("no dependency {} -> {}",a[0],a[1])))?;
                self.deps.remove(i);
                return Ok(vec![format!("dependency {} -> {} removed",a[0],a[1])]);
            }
            "REMOVE" => {
                self.task(a[0])?;
                let k = self.deps.iter().filter(|e| e.a == a[0] || e.b == a[0]).count();
                self.deps.retain(|e| e.a != a[0] && e.b != a[0]);
                self.tasks.remove(a[0]);
                return Ok(vec![format!("task {} removed with {} dependencies",a[0],k)]);
            }
            "NOTBEFORE" => {
                self.task(a[0])?;
                self.tasks.get_mut(a[0]).unwrap().not_before = num(1);
                return Ok(vec![format!("notbefore {} {}",a[0],a[1])]);
            }
            "CRASHCOST" => {
                let t = self.task(a[0])?;
                if num(1) >= t.base {
                    return Err(fail(format!("crash limit too large for {}",a[0])));
                }
                if num(1) < t.used {
                    return Err(fail(format!("crash limit below used days for {}",a[0])));
                }
                self.tasks.get_mut(a[0]).unwrap().crash = Some((num(1),num(2)));
                return Ok(vec![format!("crash {} max {} cost {}",a[0],a[1],a[2])]);
            }
            "UNCRASH" => {
                let used = self.task(a[0])?.used;
                self.tasks.get_mut(a[0]).unwrap().used = 0;
                return Ok(vec![format!("uncrash {} restored {} days",a[0],used)]);
            }
            "PERT" => {
                self.task(a[0])?;
                let (o,m,p) = (num(1),num(2),num(3));
                if o > m || m > p {
                    return Err(fail("invalid estimate"));
                }
                self.tasks.get_mut(a[0]).unwrap().pert = Some([o,m,p]);
                return Ok(vec![format!("pert {} expected {} variance {}",a[0],decimal(o+4*m+p,6),decimal((p-o)*(p-o),36))]);
            }
            "CAPACITY" => {
                self.capacities.insert(a[0].into(),num(1));
                return Ok(vec![format!("capacity {} {}",a[0],a[1])]);
            }
            "START"|"HOLIDAY"|"DEADLINE" => {
                let d = date(a[0])?;
                if c == "HOLIDAY" && self.holidays.contains(&d) {
                    return Err(fail(format!("duplicate holiday {}",a[0])));
                }
                match c {
                    "START" => self.start = Some(d),"DEADLINE" => self.deadline = Some(d),_ => {
                        self.holidays.insert(d);
                    }
                }
                return Ok(vec![format!("{} {}",c.to_lowercase(),date_text(d))]);
            }
            "LIST" => {
                out.push(format!("tasks {}, dependencies {}, holidays {}",self.tasks.len(),self.deps.len(),self.holidays.len()));
                for (n,t) in &self.tasks {
                    let p = self.preds(n).iter().map(|e| e.a.as_str()).collect::<Vec<_>>().join(" ");
                    out.push(format!("{} duration {} resource {} units {} preds {}",n,t.duration(),t.resource,t.units,if p.is_empty() {
                        "none"
                    } else {
                        &p
                    }));
                }
                return Ok(out);
            }
            "SHOW" => {
                let n = a[0];
                let t = self.task(n)?;
                out.push(format!("task {} duration {} resource {} units {}{}",n,t.duration(),t.resource,t.units,if t.not_before != 0 {
                    format!(" notbefore {}",t.not_before)
                } else {
                    String::new()
                }));
                for incoming in [true,false] {
                    let list = if incoming {
                        self.preds(n)
                    } else {
                        self.succs(n)
                    };
                    let p = list.iter().map(|e| format!("{} {}{}",if incoming {
                        &e.a
                    } else {
                        &e.b
                    },e.kind,signed(e.lag))).collect::<Vec<_>>().join(", ");
                    out.push(format!("{}: {}",if incoming {
                        "preds"
                    } else {
                        "succs"
                    },if p.is_empty() {
                        "none"
                    } else {
                        &p
                    }));
                }
                out.push(t.crash.map_or("crash: none".into(),|(m,c)| format!("crash: max {} used {} cost {}",m,t.used,c)));
                out.push(t.pert.map_or("pert: none".into(),|p| format!("pert: {} {} {}",p[0],p[1],p[2])));
                if self.order().1.is_some() {
                    out.push("schedule: unavailable".into());
                } else {
                    let s = self.schedule(None);
                    let x = &s.times[n];
                    out.push(format!("schedule: ES {} EF {} LS {} LF {} TF {} FF {}{}",x.es,x.ef,x.ls,x.lf,x.tf,x.ff,if x.tf==0 {
                        " critical"
                    } else {
                        ""
                    }));
                }
                return Ok(out);
            }
            "IMPACT" => {
                self.task(a[0])?;
                let mut reached = BTreeSet::from([a[0].to_string()]);
                loop {
                    let before = reached.len();
                    for e in &self.deps {
                        if reached.contains(&e.a) {
                            reached.insert(e.b.clone());
                        }
                    }
                    if reached.len() == before {
                        break;
                    }
                }
                reached.remove(a[0]);
                let p = reached.into_iter().collect::<Vec<_>>().join(" ");
                return Ok(vec![format!("impact {}: {}",a[0],if p.is_empty() {
                    "none"
                } else {
                    &p
                })]);
            }
            _ => {
            }
        }
        if self.tasks.is_empty() {
            return Err(fail("no tasks"));
        }
        if let Some(cycle) = self.order().1 {
            return Err(fail(format!("cycle {}",cycle)));
        }
        match c {
            "CALENDAR" if self.start.is_none() => return Err(fail("no start date")),"LEVEL" => {
                for (n,t) in &self.tasks {
                    let cap = self.capacities.get(&t.resource).copied().unwrap_or(num(0));
                    if t.units > cap {
                        return Err(fail(format!("capacity {} too small for {}",cap,n)));
                    }
                }
            },"LOAD" if !self.tasks.values().any(|t| t.resource == a[0]) => return Err(fail(format!("unknown resource {}",a[0]))),"WHATIF" => {
                self.task(a[0])?;
            },"VARIANCE" if self.baseline.is_none() => return Err(fail("no baseline")),_ => {
            }
        }
        let s = self.schedule(None);
        let mut by_start: Vec<String> = self.tasks.keys().cloned().collect();
        by_start.sort_by_key(|n| (s.times[n].es,n.clone()));
        let resources: BTreeSet<String> = self.tasks.values().map(|t| t.resource.clone()).collect();
        let initial: BTreeMap<String,(i64,i64)> = s.times.iter().map(|(n,t)| (n.clone(),(t.es,t.ef))).collect();
        match c {
            "CPM" => {
                let width = 4.max(self.tasks.keys().map(|n| n.len()).max().unwrap());
                let mut header = format!("{:<width$}","TASK");
                for title in ["DUR","ES","EF","LS","LF","TF","FF"] {
                    header += &format!("{:>5}",title);
                }
                out.push(header);
                for (n,x) in &s.times {
                    let mut row = format!("{:<width$}",n);
                    for v in [x.duration,x.es,x.ef,x.ls,x.lf,x.tf,x.ff] {
                        row += &format!("{:>5}",v);
                    }
                    if x.tf == 0 {
                        row += " *";
                    }
                    out.push(row);
                }
                out.push(format!("project duration {}",s.total));
            }
            "CRITICAL" => {
                let paths = self.paths(&s);
                out.push(format!("critical paths: {}",paths.len()));
                out.extend(paths.iter().map(|p| p.join(" -> ")));
            }
            "SLACK" => {
                let floats: BTreeSet<i64> = s.times.values().map(|t| t.tf).collect();
                for f in floats {
                    out.push(format!("float {}: {}",f,s.times.iter().filter(|(_,t)| t.tf == f).map(|(n,_)| n.as_str()).collect::<Vec<_>>().join(" ")));
                }
            }
            "DRAG" => for n in self.critical(&s) {
                out.push(format!("{} drag {}",n,s.total-self.schedule(Some((&n,0))).total));
            },
            "STATS" => {
                let count = self.critical(&s).len() as i64;
                let sum: i64 = s.times.values().map(|t| t.tf).sum();
                out.push(format!("tasks {}, critical {}, dependencies {} (FS {}, SS {}, FF {})",self.tasks.len(),count,self.deps.len(),self.deps.iter().filter(|e| e.kind == "FS").count(),self.deps.iter().filter(|e| e.kind == "SS").count(),self.deps.iter().filter(|e| e.kind == "FF").count()));
                out.push(format!("work {}",resources.iter().map(|r| format!("{} {}",r,self.tasks.values().filter(|t| t.resource == *r).map(|t| t.duration()*t.units).sum::<i64>())).collect::<Vec<_>>().join(", ")));
                out.push(format!("float total {}, average {}",sum,decimal(sum,self.tasks.len() as i64)));
                out.push(format!("duration {}, critical share {}%",s.total,decimal(100*count,self.tasks.len() as i64)));
            }
            "CALENDAR" => {
                let mut dates = Vec::new();
                let mut day = self.start.unwrap();
                while dates.len() < s.total as usize {
                    if self.working(day) {
                        dates.push(day);
                    }
                    day += 1;
                }
                for n in &by_start {
                    let x = &s.times[n];
                    out.push(format!("{} {} - {}",n,date_text(dates[x.es as usize]),date_text(dates[(x.ef-1) as usize])));
                }
                let first = dates[0];
                let last = *dates.last().unwrap();
                out.push(format!("project {} - {}, {} working days, {} calendar days",date_text(first),date_text(last),s.total,last-first+1));
                if let Some(d) = self.deadline {
                    let count = (d.min(last)+1..=d.max(last)).filter(|&v| self.working(v)).count();
                    out.push(if last <= d {
                        format!("deadline {} met, {} working days to spare",date_text(d),count)
                    } else {
                        format!("deadline {} missed by {} working days",date_text(d),count)
                    });
                }
                let h = self.holidays.iter().filter(|&&d| d >= first && d <= last && (d+5)%7 < 5).map(|&d| date_text(d)).collect::<Vec<_>>().join(", ");
                out.push(format!("holidays in span: {}",if h.is_empty() {
                    "none"
                } else {
                    &h
                }));
            }
            "GANTT" => {
                if s.total > 60 {
                    return Err(fail(format!("chart too wide ({} days)",s.total)));
                }
                let width = self.tasks.keys().map(|n| n.len()).max().unwrap();
                out.push(format!("{} |{}|"," ".repeat(width),(0..s.total).map(|d| (d%10).to_string()).collect::<String>()));
                for n in &by_start {
                    let x = &s.times[n];
                    let bar: String = (0..s.total).map(|k| if k >= x.es && k < x.ef {
                        if x.tf == 0 {
                            '='
                        } else {
                            '-'
                        }
                    } else if k >= x.ef && k < x.lf {
                        '.'
                    } else {
                        ' '
                    }).collect();
                    out.push(format!("{:<width$} |{}|",n,bar));
                }
            }
            "LEVEL" => {
                let mut decided: BTreeMap<String,(i64,i64)> = BTreeMap::new();
                let mut decision = Vec::new();
                let mut daily: BTreeMap<(String,i64),i64> = BTreeMap::new();
                while decided.len() < self.tasks.len() {
                    let n = self.tasks.keys().filter(|n| !decided.contains_key(*n) && self.preds(n).iter().all(|e| decided.contains_key(&e.a))).min_by_key(|n| (s.times[*n].ls,(*n).clone())).unwrap().clone();
                    let t = &self.tasks[&n];
                    let mut begin = t.not_before;
                    for e in self.preds(&n) {
                        let p = decided[&e.a];
                        begin = begin.max(match e.kind.as_str() {
                            "FS" => p.1+e.lag,"SS" => p.0+e.lag,_ => p.1+e.lag-t.duration()
                        });
                    }
                    let capacity = self.capacities.get(&t.resource).copied().unwrap_or(num(0));
                    while (begin..begin+t.duration()).any(|day| daily.get(&(t.resource.clone(),day)).copied().unwrap_or(0)+t.units > capacity) {
                        begin += 1;
                    }
                    let finish = begin+t.duration();
                    decided.insert(n.clone(),(begin,finish));
                    decision.push(n);
                    for day in begin..finish {
                        *daily.entry((t.resource.clone(),day)).or_default() += t.units;
                    }
                }
                let total = decided.values().map(|p| p.1).max().unwrap();
                out.push(format!("level capacity {}: duration {} -> {}",a[0],s.total,total));
                for n in decision {
                    let p = decided[&n];
                    out.push(format!("{} start {} finish {} shift {}",n,p.0,p.1,p.0-s.times[&n].es));
                }
                for r in &resources {
                    out.push(format!("resource {} capacity {} peak {} -> {}",r,self.capacities.get(r).copied().unwrap_or(num(0)),self.usage(r,&initial,s.total).iter().max().unwrap(),self.usage(r,&decided,total).iter().max().unwrap()));
                }
            }
            "LOAD" => {
                let load = self.usage(a[0],&initial,s.total);
                let peak = *load.iter().max().unwrap();
                out.push(format!("load {}: {}",a[0],load.iter().map(|n| n.to_string()).collect::<Vec<_>>().join(" ")));
                out.push(format!("peak {} on day {}",peak,load.iter().position(|&x| x == peak).unwrap()));
                if let Some(cap) = self.capacities.get(a[0]) {
                    out.push(format!("capacity {} exceeded on {} days",cap,load.iter().filter(|&x| x > cap).count()));
                }
            }
            "PERTSUM" => for path in self.paths(&s) {
                let mut expected = 0;
                let mut variance = 0;
                for n in &path {
                    let t = &self.tasks[n];
                    let p = t.pert.unwrap_or([t.duration();3]);
                    expected += p[0]+4*p[1]+p[2];
                    variance += (p[2]-p[0])*(p[2]-p[0]);
                }
                out.push(format!("{}: expected {} variance {}",path.join(" -> "),decimal(expected,6),decimal(variance,36)));
            },
            "CRASH" => {
                let budget = num(0);
                let mut remaining = budget;
                let mut count = 0;
                let reason;
                loop {
                    let now = self.schedule(None);
                    let candidates: Vec<String> = self.critical(&now).into_iter().filter(|n| {
                        let t = &self.tasks[n];
                        t.crash.is_some_and(|(limit,_)| t.used < limit) && self.schedule(Some((n,t.duration()-1))).total < now.total
                    }).collect();
                    let n = match candidates.into_iter().min_by_key(|n| (self.tasks[n].crash.unwrap().1,n.clone())) {
                        Some(n) => n,None => {
                            reason = "no candidate";
                            break;
                        }
                    };
                    let cost = self.tasks[&n].crash.unwrap().1;
                    if cost > remaining {
                        reason = "insufficient budget";
                        break;
                    }
                    let before = self.tasks[&n].duration();
                    self.tasks.get_mut(&n).unwrap().used += 1;
                    remaining -= cost;
                    count += 1;
                    out.push(format!("step {}: {} {} -> {}, cost {}, project {}",count,n,before,self.tasks[&n].duration(),cost,self.schedule(None).total));
                }
                out.push(format!("crash done: {} days, cost {}, project {} -> {}, budget left {}, {}",count,budget-remaining,s.total,self.schedule(None).total,remaining,reason));
            }
            "WHATIF" => {
                let after = self.schedule(Some((a[0],num(1))));
                out.push(format!("whatif {} {} -> {}: project {} -> {}",a[0],self.tasks[a[0]].duration(),a[1],s.total,after.total));
                for n in self.tasks.keys() {
                    let x = &s.times[n];
                    let y = &after.times[n];
                    let fields: String = [("ES",x.es,y.es),("EF",x.ef,y.ef),("TF",x.tf,y.tf)].iter().filter(|(_,p,q)| p != q).map(|(title,p,q)| format!(" {} {}->{}",title,p,q)).collect();
                    if !fields.is_empty() {
                        out.push(format!("{}{}",n,fields));
                    }
                }
                let before = self.critical(&s);
                let after = self.critical(&after);
                if before != after {
                    out.push(format!("critical {} -> {}",before.join(" "),after.join(" ")));
                }
            }
            "BASELINE" => {
                self.baseline = Some(Baseline {
                    total:s.total,times:initial
                });
                out.push(format!("baseline saved: {} tasks, duration {}",self.tasks.len(),s.total));
            }
            "VARIANCE" => {
                let old = self.baseline.as_ref().unwrap();
                out.push(format!("variance: duration {} -> {} ({})",old.total,s.total,signed(s.total-old.total)));
                let names: BTreeSet<&String> = old.times.keys().chain(self.tasks.keys()).collect();
                for n in names {
                    match (old.times.get(n),initial.get(n)) {
                        (None,Some(_)) => out.push(format!("{} new",n)),(Some(_),None) => out.push(format!("{} removed",n)),(Some(x),Some(y)) if x != y => out.push(format!("{} start {} finish {}",n,signed(y.0-x.0),signed(y.1-x.1))),_ => {
                        }
                    }
                }
                if out.len() == 1 {
                    out.push("no task changes".into());
                }
            }
            _ => {
            }
        }
        Ok(out)
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut project = Project::default();
    for line in lines.take(count) {
        let words: Vec<&str> = line.split(' ').collect();
        match project.command(&words) {
            Ok(out) => for line in out {
                println!("{}",line);
            },Err(problem) => println!("{}",problem)
        }
    }
}
