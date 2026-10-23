use std::cmp::Ordering;
use std::collections::{BTreeMap,BTreeSet,VecDeque};
use std::io::{self,Read};
type Answer = Result<Vec<String>,String>;

fn fail(s: impl Into<String>) -> String {
    format!("error: {}",s.into())
}

fn number(s: &str) -> Option<i64> {
    if (1..=4).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_digit()) && (s.len() == 1 || !s.starts_with('0')) {
        s.parse().ok()
    } else {
        None
    }
}

#[derive(Clone,Eq,PartialEq)]
struct Version {
    core: [i64;3],
    pre: Vec<String>,
}

impl Version {
    fn text(&self) -> String {
        format!("{}.{}.{}{}",self.core[0],self.core[1],self.core[2],if self.pre.is_empty() {
            String::new()
        } else {
            format!("-{}",self.pre.join("."))
        })
    }
}

impl Ord for Version {
    fn cmp(&self,other: &Self) -> Ordering {
        let c = self.core.cmp(&other.core);
        if c != Ordering::Equal {
            return c;
        }
        if self.pre.is_empty() || other.pre.is_empty() {
            return self.pre.is_empty().cmp(&other.pre.is_empty());
        }
        for (a,b) in self.pre.iter().zip(&other.pre) {
            if a == b {
                continue;
            }
            let na = a.bytes().all(|x| x.is_ascii_digit());
            let nb = b.bytes().all(|x| x.is_ascii_digit());
            return if na && nb {
                a.parse::<i64>().unwrap().cmp(&b.parse().unwrap())
            } else if na != nb {
                nb.cmp(&na)
            } else {
                a.cmp(b)
            };
        }
        self.pre.len().cmp(&other.pre.len())
    }
}

impl PartialOrd for Version {
    fn partial_cmp(&self,other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

fn version(s: &str) -> Option<Version> {
    let p: Vec<&str> = s.split('-').collect();
    if !(1..=2).contains(&p.len()) {
        return None;
    }
    let parts: Vec<_> = p[0].split('.').collect();
    if parts.len() != 3 {
        return None;
    }
    let core = [number(parts[0])?,number(parts[1])?,number(parts[2])?];
    let pre: Vec<String> = if p.len() == 2 {
        p[1].split('.').map(str::to_string).collect()
    } else {
        Vec::new()
    };
    for id in &pre {
        if id.is_empty() || !id.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit()) || (id.bytes().all(|b| b.is_ascii_digit()) && number(id).is_none()) {
            return None;
        }
    }
    Some(Version {
        core,pre
    })
}

fn checked_version(s: &str) -> Result<Version,String> {
    version(s).ok_or_else(|| fail(format!("invalid version '{}'",s)))
}

#[derive(Clone)]
struct Comparison {
    op: String,
    version: Version,
}

impl Comparison {
    fn accepts(&self,v: &Version) -> bool {
        match self.op.as_str() {
            "=" => v == &self.version,">" => v > &self.version,">=" => v >= &self.version,"<" => v < &self.version,_ => v <= &self.version
        }
    }
}

#[derive(Clone)]
struct Alternative {
    comparisons: Vec<Comparison>,
    prerelease_cores: Vec<[i64;3]>,
}

#[derive(Clone)]
struct Constraint {
    alternatives: Vec<Alternative>
}

impl Constraint {
    fn accepts(&self,v: &Version) -> bool {
        self.alternatives.iter().any(|a| (v.pre.is_empty() || a.prerelease_cores.contains(&v.core)) && a.comparisons.iter().all(|c| c.accepts(v)))
    }
    fn normal(&self) -> String {
        self.alternatives.iter().map(|a| {
            let s = a.comparisons.iter().map(|c| format!("{}{}",c.op,c.version.text())).collect::<Vec<_>>().join(" ");
            if s.is_empty() {
                "*".into()
            } else {
                s
            }
        }).collect::<Vec<_>>().join(" || ")
    }
}

fn constraint(text: &str) -> Result<Constraint,String> {
    let invalid = || fail(format!("invalid constraint '{}'",text));
    let mut alternatives = Vec::new();
    for alternative in text.split(" || ") {
        let mut comparisons = Vec::new();
        let mut prerelease_cores = Vec::new();
        for term in alternative.split(' ') {
            let op = [">=","<=",">","<","=","^","~"].iter().copied().find(|op| term.starts_with(*op)).unwrap_or("");
            let pattern = &term[op.len()..];
            let k;
            let lower;
            if pattern.contains('-') {
                lower = version(pattern).filter(|v| !v.pre.is_empty()).ok_or_else(invalid)?;
                k = 3;
                prerelease_cores.push(lower.core);
            } else {
                let parts: Vec<_> = pattern.split('.').collect();
                if !(1..=3).contains(&parts.len()) {
                    return Err(invalid());
                }
                let mut core = [0;3];
                let mut count = 0;
                let mut wildcard = false;
                for part in parts {
                    if part == "x" || part == "*" {
                        wildcard = true;
                    } else {
                        let n = number(part).ok_or_else(invalid)?;
                        if wildcard {
                            return Err(invalid());
                        }
                        core[count] = n;
                        count += 1;
                    }
                }
                k = count;
                lower = Version {
                    core,pre:Vec::new()
                };
            }
            let upper = |i: usize| {
                let mut core = lower.core;
                core[i-1] += 1;
                for v in &mut core[i..] {
                    *v = 0;
                }
                Version {
                    core,pre:Vec::new()
                }
            };
            let mut add = |op: &str,v: Version| comparisons.push(Comparison {
                op:op.into(),version:v
            });
            if k == 0 {
                if op == ">" || op == "<" {
                    add("<",Version {
                        core:[0;3],pre:vec!["0".into()]
                    });
                }
            } else {
                match op {
                    ""|"=" => if k == 3 {
                        add("=",lower.clone());
                    } else {
                        add(">=",lower.clone());
                        add("<",upper(k));
                    },">" => add(if k==3 {
                        ">"
                    } else {
                        ">="
                    },if k==3 {
                        lower.clone()
                    } else {
                        upper(k)
                    }),"<=" => add(if k==3 {
                        "<="
                    } else {
                        "<"
                    },if k==3 {
                        lower.clone()
                    } else {
                        upper(k)
                    }),">="|"<" => add(op,lower.clone()),"~" => {
                        add(">=",lower.clone());
                        add("<",upper(if k>=2 {
                            2
                        } else {
                            1
                        }));
                    },"^" => {
                        add(">=",lower.clone());
                        add("<",upper(if lower.core[0]!=0 || k==1 {
                            1
                        } else if lower.core[1]!=0 || k==2 {
                            2
                        } else {
                            3
                        }));
                    },_ => unreachable!()
                }
            }
        }
        alternatives.push(Alternative {
            comparisons,prerelease_cores
        });
    }
    Ok(Constraint {
        alternatives
    })
}

#[derive(Clone)]
struct Rule {
    name: String,
    text: String,
    constraint: Constraint,
}

#[derive(Clone)]
struct Release {
    version: Version,
    deps: Vec<Rule>,
    conflicts: Vec<Rule>,
    yanked: bool,
}

#[derive(Clone)]
struct Requirement {
    rule: Rule,
    origin: Option<(String,Version)>,
}

#[derive(Clone)]
struct Snapshot {
    requests: Vec<Rule>,
    installed: BTreeMap<String,Release>,
}

#[derive(Default)]
struct Manager {
    registry: BTreeMap<String,Vec<Release>>,
    requests: Vec<Rule>,
    installed: BTreeMap<String,Release>,
    held: BTreeSet<String>,
    advisories: BTreeMap<String,Rule>,
    history: Vec<Snapshot>,
}

struct Search<'a> {
    manager: &'a Manager,
    preferred: BTreeSet<String>,
    audit: bool,
    selected: BTreeMap<String,Release>,
    origins: BTreeMap<String,Requirement>,
    failure: Option<(usize,Vec<String>)>,
}

impl Search<'_> {
    fn chain(&self,r: &Requirement) -> Vec<String> {
        if let Some((n,v)) = &r.origin {
            let mut chain = self.chain(&self.origins[n]);
            chain.push(format!("{}@{} requires {} {}",n,v.text(),r.rule.name,r.rule.text));
            chain
        } else {
            vec![format!("requested {} {}",r.rule.name,r.rule.text)]
        }
    }
    // Materialize a failure before backtracking changes its selection and origins.
    fn record(&mut self,r: &Requirement,reason: String,other: Option<&str>) {
        if self.failure.as_ref().is_none_or(|(depth,_)| self.selected.len() > *depth) {
            let mut out = vec!["UNSATISFIABLE".into()];
            out.extend(self.chain(r).iter().map(|s| format!("  {}",s)));
            out.push(format!("  {}",reason));
            if let Some(n) = other {
                out.extend(self.chain(&self.origins[n]).iter().map(|s| format!("    {}",s)));
            }
            self.failure=Some((self.selected.len(),out));
        }
    }
    fn usable(&self,n: &str,r: &Release) -> bool {
        (!r.yanked || self.manager.installed.get(n).is_some_and(|old| old.version == r.version)) && (!self.audit || self.manager.applicable(n,&r.version).is_empty())
    }
    fn search(&mut self,queue: Vec<Requirement>) -> bool {
        if queue.is_empty() {
            return true;
        }
        let r = &queue[0];
        let n = &r.rule.name;
        let rest = &queue[1..];
        if let Some(old) = self.selected.get(n) {
            if r.rule.constraint.accepts(&old.version) {
                return self.search(rest.to_vec());
            }
            self.record(r,format!("{}@{} was selected by:",n,old.version.text()),Some(n));
            return false;
        }
        let mut candidates;
        if self.manager.held.contains(n) {
            let installed = &self.manager.installed[n];
            let fixed = self.manager.registry[n].iter().find(|v| v.version == installed.version).unwrap().clone();
            if !r.rule.constraint.accepts(&fixed.version) || !self.usable(n,&fixed) {
                self.record(r,format!("{}@{} is held",n,fixed.version.text()),None);
                return false;
            }
            candidates=vec![fixed];
        } else {
            candidates=self.manager.releases(n).into_iter().filter(|v| r.rule.constraint.accepts(&v.version) && self.usable(n,v)).cloned().collect::<Vec<_>>();
            if self.preferred.contains(n) {
                if let Some(i) = candidates.iter().position(|v| self.manager.installed.get(n).is_some_and(|old| old.version == v.version)) {
                    let first=candidates.remove(i);
                    candidates.insert(0,first);
                }
            }
            if candidates.is_empty() {
                self.record(r,format!("no version of {} matches {}",n,r.rule.text),None);
                return false;
            }
        }
        for candidate in candidates {
            let conflict=self.selected.iter().find(|(q,w)| candidate.conflicts.iter().any(|d| d.name.as_str() == q.as_str() && d.constraint.accepts(&w.version)) || w.conflicts.iter().any(|d| d.name == *n && d.constraint.accepts(&candidate.version))).map(|(q,w)| (q.clone(),w.version.clone()));
            if let Some((q,w))=conflict {
                self.record(r,format!("{}@{} conflicts with {}@{}, which was selected by:",n,candidate.version.text(),q,w.text()),Some(&q));
                continue;
            }
            self.selected.insert(n.clone(),candidate.clone());
            self.origins.insert(n.clone(),r.clone());
            let mut next=candidate.deps.iter().map(|d| Requirement {
                rule:d.clone(),origin:Some((n.clone(),candidate.version.clone()))
            }).collect::<Vec<_>>();
            next.extend_from_slice(rest);
            if self.search(next) {
                return true;
            }
            self.selected.remove(n);
            self.origins.remove(n);
        }
        false
    }
}

impl Manager {
    fn releases(&self,n: &str) -> Vec<&Release> {
        let mut list=self.registry.get(n).map(|v| v.iter().collect::<Vec<_>>()).unwrap_or_default();
        list.sort_by(|a,b| b.version.cmp(&a.version));
        list
    }
    fn registered(&self,n: &str,v: &str) -> Result<&Release,String> {
        self.registry.get(n).and_then(|list| list.iter().find(|r| r.version.text() == v)).ok_or_else(|| fail(format!("{}@{} is not registered",n,v)))
    }
    fn check_installed(&self,n: &str) -> Result<&Release,String> {
        self.installed.get(n).ok_or_else(|| fail(format!("{} is not installed",n)))
    }
    fn applicable(&self,n: &str,v: &Version) -> Vec<String> {
        self.advisories.iter().filter(|(_,r)| r.name == n && r.constraint.accepts(v)).map(|(id,_)| id.clone()).collect()
    }
    fn display(&self,n: &str,r: &Release) -> String {
        let mut flags=Vec::new();
        if r.yanked {
            flags.push("yanked");
        }
        if self.installed.get(n).is_some_and(|v| v.version == r.version) {
            flags.push("installed");
        }
        format!("{}@{}{}",n,r.version.text(),if flags.is_empty() {
            String::new()
        } else {
            format!(" ({})",flags.join(", "))
        })
    }
    fn resolve(&self,requests: &[Rule],preferred: BTreeSet<String>,audit: bool) -> Result<BTreeMap<String,Release>,Vec<String>> {
        let mut search=Search {
            manager:self,preferred,audit,selected:BTreeMap::new(),origins:BTreeMap::new(),failure:None
        };
        if search.search(requests.iter().map(|r| Requirement {
            rule:r.clone(),origin:None
        }).collect()) {
            Ok(search.selected)
        } else {
            Err(search.failure.unwrap().1)
        }
    }
    fn plan(&self,next: &BTreeMap<String,Release>) -> Vec<String> {
        let mut out=Vec::new();
        let mut counts=[0;4];
        let mut remaining: BTreeSet<String>=next.keys().cloned().collect();
        while !remaining.is_empty() {
            let n=remaining.iter().find(|n| next[*n].deps.iter().all(|d| !remaining.contains(&d.name))).unwrap().clone();
            remaining.remove(&n);
            let v=&next[&n].version;
            if let Some(old)=self.installed.get(&n) {
                if v!=&old.version {
                    let up=v>&old.version;
                    out.push(format!("{} {} {} -> {}",if up {
                        "upgrade"
                    } else {
                        "downgrade"
                    },n,old.version.text(),v.text()));
                    counts[if up {
                        1
                    } else {
                        2
                    }]+=1;
                }
            } else {
                out.push(format!("install {}@{}",n,v.text()));
                counts[0]+=1;
            }
        }
        remaining=self.installed.keys().filter(|n| !next.contains_key(*n)).cloned().collect();
        while !remaining.is_empty() {
            let n=remaining.iter().find(|n| !remaining.iter().any(|q| self.installed[q].deps.iter().any(|d| d.name.as_str() == n.as_str()))).unwrap().clone();
            remaining.remove(&n);
            out.push(format!("remove {}@{}",n,self.installed[&n].version.text()));
            counts[3]+=1;
        }
        if out.is_empty() {
            out.push("no changes".into());
        } else {
            out.push(format!("{} installed, {} upgraded, {} downgraded, {} removed",counts[0],counts[1],counts[2],counts[3]));
        }
        out
    }
    fn update(&mut self,requests: Vec<Rule>,next: BTreeMap<String,Release>) {
        self.history.push(Snapshot {
            requests:self.requests.clone(),installed:self.installed.clone()
        });
        self.requests=requests;
        self.installed=next;
        let installed = &self.installed;
        self.held.retain(|n| installed.contains_key(n));
    }
    fn parent(&self,n: &str) -> String {
        self.installed.iter().find(|(_,r)| r.deps.iter().any(|d| d.name == n)).unwrap().0.clone()
    }
    fn command(&mut self,line: &str) -> Answer {
        let clauses: Vec<&str>=line.split("; ").collect();
        let w: Vec<&str>=clauses[0].split(' ').collect();
        let c=w[0];
        let a=&w[1..];
        let rest=|i: usize| a[i..].join(" ");
        let mut out=Vec::new();
        match c {
            "PKG" => {
                let v=checked_version(a[1])?;
                if self.registry.get(a[0]).is_some_and(|list| list.iter().any(|r| r.version == v)) {
                    return Err(fail(format!("{}@{} is already registered",a[0],a[1])));
                }
                let mut deps=Vec::new();
                let mut conflicts=Vec::new();
                for clause in &clauses[1..] {
                    let words: Vec<_>=clause.split(' ').collect();
                    let text=words[2..].join(" ");
                    let con=constraint(&text)?;
                    let rule=Rule {
                        name:words[1].into(),text,constraint:con
                    };
                    if words[0]=="DEP" {
                        deps.push(rule);
                    } else {
                        conflicts.push(rule);
                    }
                }
                self.registry.entry(a[0].into()).or_default().push(Release {
                    version:v,deps,conflicts,yanked:false
                });
                Ok(vec![format!("registered {}@{}",a[0],a[1])])
            }
            "YANK"|"INFO" => {
                let r=self.registered(a[0],a[1])?;
                if c=="YANK" {
                    if r.yanked {
                        return Err(fail(format!("{}@{} is already yanked",a[0],a[1])));
                    }
                    self.registry.get_mut(a[0]).unwrap().iter_mut().find(|r| r.version.text()==a[1]).unwrap().yanked=true;
                    return Ok(vec![format!("yanked {}@{}",a[0],a[1])]);
                }
                out.push(self.display(a[0],r));
                out.extend(r.deps.iter().map(|d| format!("  requires {} {}",d.name,d.text)));
                out.extend(r.conflicts.iter().map(|d| format!("  conflicts with {} {}",d.name,d.text)));
                out.extend(self.applicable(a[0],&r.version).iter().map(|id| format!("  advisory {}",id)));
                Ok(out)
            }
            "VERSIONS" => {
                let con=if a.len()>1 {
                    Some(constraint(&rest(1))?)
                } else {
                    None
                };
                if !self.registry.contains_key(a[0]) {
                    return Err(fail(format!("unknown package {}",a[0])));
                }
                out.extend(self.releases(a[0]).iter().filter(|r| con.as_ref().is_none_or(|c| c.accepts(&r.version))).map(|r| self.display(a[0],r)));
                if out.is_empty() {
                    out.push("no matching versions".into());
                }
                Ok(out)
            }
            "DEPENDENTS" => {
                let v=if a.len()>1 {
                    Some(checked_version(a[1])?)
                } else {
                    None
                };
                for n in self.registry.keys() {
                    for r in self.releases(n) {
                        for d in &r.deps {
                            if d.name==a[0] && v.as_ref().is_none_or(|v| d.constraint.accepts(v)) {
                                out.push(format!("{}@{} requires {} {}",n,r.version.text(),d.name,d.text));
                            }
                        }
                    }
                }
                if out.is_empty() {
                    out.push("no dependents".into());
                }
                Ok(out)
            }
            "COMPARE" => {
                let x=checked_version(a[0])?;
                let y=checked_version(a[1])?;
                Ok(vec![format!("{} {} {}",a[0],if x<y {
                    "<"
                } else if x>y {
                    ">"
                } else {
                    "="
                },a[1])])
            }
            "MATCH" => {
                let v=checked_version(a[0])?;
                let con=constraint(&rest(1))?;
                Ok(vec![if con.accepts(&v) {
                    "yes"
                } else {
                    "no"
                }.into()])
            }
            "RANGE" => Ok(vec![constraint(&rest(0))?.normal()]),
            "INSTALL"|"SIMULATE" => {
                let text=if a.len()>1 {
                    rest(1)
                } else {
                    "*".into()
                };
                let con=constraint(&text)?;
                if !self.registry.contains_key(a[0]) {
                    return Err(fail(format!("unknown package {}",a[0])));
                }
                let rule=Rule {
                    name:a[0].into(),text,constraint:con
                };
                let mut requests=self.requests.clone();
                if let Some(i)=requests.iter().position(|r| r.name==a[0]) {
                    requests[i]=rule;
                } else {
                    requests.push(rule);
                }
                match self.resolve(&requests,self.installed.keys().cloned().collect(),false) {
                    Ok(next)=> {
                        let plan=self.plan(&next);
                        if c=="INSTALL" {
                            self.update(requests,next);
                        }
                        Ok(plan)
                    },Err(report)=>Ok(report)
                }
            }
            "REMOVE" => {
                let n=a[0];
                if !self.requests.iter().any(|r| r.name==n) {
                    return Err(fail(if self.installed.contains_key(n) {
                        format!("{} is required by {}",n,self.parent(n))
                    } else {
                        format!("{} is not installed",n)
                    }));
                }
                let requests: Vec<Rule>=self.requests.iter().filter(|r| r.name!=n).cloned().collect();
                let mut keep: BTreeSet<String>=requests.iter().map(|r| r.name.clone()).collect();
                loop {
                    let next: Vec<String>=keep.iter().flat_map(|n| self.installed[n].deps.iter().map(|d| d.name.clone())).collect();
                    let old=keep.len();
                    keep.extend(next);
                    if keep.len()==old {
                        break;
                    }
                }
                if keep.contains(n) {
                    out.push(format!("{}@{} is still required by {}",n,self.installed[n].version.text(),self.parent(n)));
                    self.update(requests,self.installed.clone());
                } else {
                    let next=self.installed.iter().filter(|(n,_)| keep.contains(*n)).map(|(n,r)|(n.clone(),r.clone())).collect();
                    out=self.plan(&next);
                    self.update(requests,next);
                }
                Ok(out)
            }
            "UPGRADE" => {
                if !a.is_empty() {
                    self.check_installed(a[0])?;
                }
                let preferred=if a.is_empty() {
                    BTreeSet::new()
                } else {
                    self.installed.keys().filter(|n| n.as_str()!=a[0]).cloned().collect()
                };
                match self.resolve(&self.requests,preferred,false) {
                    Ok(next)=> {
                        out=self.plan(&next);
                        self.update(self.requests.clone(),next);
                        Ok(out)
                    },Err(report)=>Ok(report)
                }
            }
            "ROLLBACK" => {
                let snapshot=self.history.pop().ok_or_else(||fail("nothing to roll back"))?;
                out=self.plan(&snapshot.installed);
                self.requests=snapshot.requests;
                self.installed=snapshot.installed;
                let installed = &self.installed;
                self.held.retain(|n| installed.contains_key(n));
                Ok(out)
            }
            "HOLD" => {
                let v=self.check_installed(a[0])?.version.text();
                if !self.held.insert(a[0].into()) {
                    return Err(fail(format!("{} is already held",a[0])));
                }
                Ok(vec![format!("held {}@{}",a[0],v)])
            }
            "UNHOLD" => {
                if !self.held.remove(a[0]) {
                    return Err(fail(format!("{} is not held",a[0])));
                }
                Ok(vec![format!("released {}",a[0])])
            }
            "WHY" => {
                let n=a[0];
                let r=self.check_installed(n)?;
                let roots: BTreeSet<String>=self.requests.iter().map(|r|r.name.clone()).collect();
                if roots.contains(n) {
                    return Ok(vec![format!("{}@{} is explicitly installed",n,r.version.text())]);
                }
                let mut seen=roots.clone();
                let mut queue: VecDeque<String>=roots.iter().cloned().collect();
                let mut parents=BTreeMap::new();
                while let Some(u)=queue.pop_front() {
                    let mut next: Vec<String>=self.installed[&u].deps.iter().map(|d| d.name.clone()).collect();
                    next.sort();
                    for v in next {
                        if seen.insert(v.clone()) {
                            parents.insert(v.clone(),u.clone());
                            queue.push_back(v);
                        }
                    }
                }
                let mut path=vec![n.to_string()];
                while !roots.contains(path.last().unwrap()) {
                    path.push(parents[path.last().unwrap()].clone());
                }
                path.reverse();
                Ok(vec![path.iter().map(|n|format!("{}@{}",n,self.installed[n].version.text())).collect::<Vec<_>>().join(" -> ")])
            }
            "TREE" => {
                if !a.is_empty() {
                    self.check_installed(a[0])?;
                }
                let mut roots: Vec<String>=if a.is_empty() {
                    self.requests.iter().map(|r|r.name.clone()).collect()
                } else {
                    vec![a[0].into()]
                };
                roots.sort();
                if roots.is_empty() {
                    return Ok(vec!["(empty)".into()]);
                }
                let mut seen=BTreeSet::new();
                fn visit(m: &Manager,n: &str,text: Option<&str>,prefix: &str,indent: &str,seen: &mut BTreeSet<String>,out: &mut Vec<String>) {
                    let r=&m.installed[n];
                    let body=format!("{}{}@{}{}",prefix,n,r.version.text(),text.map_or(String::new(),|c|format!(" [{}]",c)));
                    if !seen.insert(n.into()) {
                        out.push(body+" (*)");
                        return;
                    }
                    out.push(body);
                    for (i,d) in r.deps.iter().enumerate() {
                        let last=i+1==r.deps.len();
                        visit(m,&d.name,Some(&d.text),&format!("{}{}",indent,if last {
                            "`-- "
                        } else {
                            "|-- "
                        }),&format!("{}{}",indent,if last {
                            "    "
                        } else {
                            "|   "
                        }),seen,out);
                    }
                }
                for n in roots {
                    visit(self,&n,self.requests.iter().find(|r|r.name==n).map(|r|r.text.as_str()),"","",&mut seen,&mut out);
                }
                Ok(out)
            }
            "OUTDATED" => {
                for (n,r) in &self.installed {
                    let constraints: Vec<&Constraint>=self.requests.iter().filter(|r|r.name==*n).map(|r|&r.constraint).chain(self.installed.values().flat_map(|r|&r.deps).filter(|d|d.name==*n).map(|d|&d.constraint)).collect();
                    let versions=self.releases(n);
                    let wanted=versions.iter().find(|v|(!v.yanked || v.version==r.version) && constraints.iter().all(|c|c.accepts(&v.version))).unwrap();
                    let latest=versions.iter().find(|v|!v.yanked && v.version.pre.is_empty());
                    if wanted.version!=r.version || latest.is_some_and(|v|v.version>r.version) {
                        out.push(format!("{} {} {} {}",n,r.version.text(),wanted.version.text(),latest.map_or("-".into(),|v|v.version.text())));
                    }
                }
                if out.is_empty() {
                    out.push("all packages are up to date".into());
                }
                Ok(out)
            }
            "LOCK" => {
                out.extend(self.installed.iter().map(|(n,r)|format!("{}@{}",n,r.version.text())));
                if out.is_empty() {
                    out.push("(empty)".into());
                }
                Ok(out)
            }
            "STATUS" => {
                out.extend(self.requests.iter().map(|r|format!("{} {} -> {}",r.name,r.text,self.installed[&r.name].version.text())));
                if out.is_empty() {
                    out.push("no requests".into());
                }
                out.push(format!("{} installed, {} held, {} snapshots",self.installed.len(),self.held.len(),self.history.len()));
                Ok(out)
            }
            "ADVISORY" => {
                if self.advisories.contains_key(a[0]) {
                    return Err(fail(format!("advisory {} already exists",a[0])));
                }
                let text=rest(2);
                let con=constraint(&text)?;
                self.advisories.insert(a[0].into(),Rule {
                    name:a[1].into(),text,constraint:con
                });
                Ok(vec![format!("advisory {} recorded",a[0])])
            }
            "AUDIT" => {
                if !a.is_empty() {
                    return match self.resolve(&self.requests,self.installed.keys().cloned().collect(),true) {
                        Ok(next)=> {
                            out=self.plan(&next);
                            self.update(self.requests.clone(),next);
                            Ok(out)
                        },Err(report)=>Ok(report)
                    };
                }
                for (n,r) in &self.installed {
                    let ids=self.applicable(n,&r.version);
                    if ids.is_empty() {
                        continue;
                    }
                    let fix=self.releases(n).into_iter().rev().find(|v|v.version>r.version && v.version.pre.is_empty() && !v.yanked && self.applicable(n,&v.version).is_empty());
                    out.push(format!("{}@{}: {} {}",n,r.version.text(),ids.join(", "),fix.map_or("(no fix)".into(),|v|format!("(fix: {})",v.version.text()))));
                }
                if out.is_empty() {
                    out.push("no known vulnerabilities".into());
                }
                Ok(out)
            }
            _ => Ok(out)
        }
    }
}

fn main() {
    let mut input=String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines=input.lines();
    let count:usize=lines.next().unwrap().parse().unwrap();
    let mut manager=Manager::default();
    for line in lines.take(count) {
        match manager.command(line) {
            Ok(out)=>for line in out {
                println!("{}",line);
            },Err(problem)=>println!("{}",problem)
        }
    }
}
