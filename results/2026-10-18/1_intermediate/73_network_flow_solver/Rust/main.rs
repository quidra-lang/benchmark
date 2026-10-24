use std::collections::{BTreeSet, VecDeque};
use std::io::{self, Read};

#[derive(Clone)]
struct Edge {
    from: usize,
    to: usize,
    capacity: i64,
    cost: i64,
    lower: i64,
    flow: i64,
}

#[derive(Clone,Copy,PartialEq,Eq)]
struct Arc {
    edge: usize,
    forward: bool,
}

#[derive(Clone,Copy,PartialEq,Eq)]
enum Owner {
    None,
    Flow(usize,usize),
    Circulation,
}

#[derive(Clone)]
struct Network {
    names: Vec<String>,
    demands: Vec<i64>,
    edges: Vec<Edge>,
    owner: Owner,
}

struct Pushed {
    arcs: Vec<Arc>,
    amount: i64,
    phase: usize,
    delta: i64,
    cost: i64,
}

struct Component {
    start: usize,
    edges: Vec<usize>,
    amount: i64,
    cycle: bool,
}

fn error(reason: impl AsRef<str>) -> String {
    format!("ERROR {}",reason.as_ref())
}

impl Network {
    fn new() -> Self {
        Self {
            names:Vec::new(),demands:Vec::new(),edges:Vec::new(),owner:Owner::None
        }
    }
    fn node(&self, name: &str) -> Result<usize,String> {
        self.names.iter().position(|n|n == name).ok_or_else(||error(format!("UNKNOWN NODE {name}")))
    }
    fn endpoints(&self, a: &str, b: &str) -> Result<(usize,usize),String> {
        let s = self.node(a)?;
        let t = self.node(b)?;
        if s == t {
            Err(error("SAME NODE"))
        } else {
            Ok((s,t))
        }
    }
    fn edge_number(&self, text: &str) -> Result<usize,String> {
        let i: usize = text.parse().unwrap();
        if i == 0 || i > self.edges.len() {
            Err(error(format!("UNKNOWN EDGE {text}")))
        } else {
            Ok(i-1)
        }
    }
    // Forward arcs precede all backward arcs, including in every vertex list.
    fn global_arcs(&self) -> Vec<Arc> {
        [true,false].iter().copied().flat_map(|forward|(0..self.edges.len()).map(move |edge|Arc {
            edge,forward
        })).collect()
    }
    fn arcs(&self, node: usize) -> Vec<Arc> {
        self.global_arcs().into_iter().filter(|&a|self.start(a) == node).collect()
    }
    fn start(&self, a: Arc) -> usize {
        if a.forward {
            self.edges[a.edge].from
        } else {
            self.edges[a.edge].to
        }
    }
    fn end(&self, a: Arc) -> usize {
        if a.forward {
            self.edges[a.edge].to
        } else {
            self.edges[a.edge].from
        }
    }
    fn residual(&self, a: Arc) -> i64 {
        let e = &self.edges[a.edge];
        if a.forward {
            e.capacity-e.flow
        } else {
            e.flow
        }
    }
    fn arc_cost(&self, a: Arc) -> i64 {
        if a.forward {
            self.edges[a.edge].cost
        } else {
            -self.edges[a.edge].cost
        }
    }
    fn push(&mut self, path: &[Arc], amount: i64) {
        for &a in path {
            self.edges[a.edge].flow += if a.forward {
                amount
            } else {
                -amount
            };
        }
    }
    fn bottleneck(&self, path: &[Arc]) -> i64 {
        path.iter().map(|&a|self.residual(a)).min().unwrap()
    }
    fn balances(&self) -> Vec<i64> {
        let mut b = vec![0;self.names.len()];
        for e in &self.edges {
            b[e.from] += e.flow;
            b[e.to] -= e.flow;
        }
        b
    }
    fn cost(&self) -> i64 {
        self.edges.iter().map(|e|e.flow*e.cost).sum()
    }
    fn zero(&mut self) {
        for e in &mut self.edges {
            e.flow = 0;
        }
    }
    fn begin(&mut self, s: usize, t: usize) -> i64 {
        if self.owner != Owner::Flow(s,t) {
            self.zero();
        }
        self.owner = Owner::Flow(s,t);
        self.balances()[s]
    }
    fn bfs(&self, s: usize, delta: i64) -> (Vec<Option<usize>>,Vec<Option<Arc>>) {
        let mut level = vec![None;self.names.len()];
        let mut parent = vec![None;self.names.len()];
        let mut queue = VecDeque::from([s]);
        level[s] = Some(0);
        while let Some(u) = queue.pop_front() {
            for a in self.arcs(u) {
                let v = self.end(a);
                if self.residual(a) >= delta && level[v].is_none() {
                    level[v] = Some(level[u].unwrap()+1);
                    parent[v] = Some(a);
                    queue.push_back(v);
                }
            }
        }
        (level,parent)
    }
    fn path(&self, s: usize, t: usize, parent: &[Option<Arc>]) -> Vec<Arc> {
        let mut path = Vec::new();
        let mut at = t;
        while at != s {
            let a = parent[at].unwrap();
            path.push(a);
            at = self.start(a);
        }
        path.reverse();
        path
    }
    fn augment(&mut self, s: usize, t: usize, delta: i64) -> Option<Pushed> {
        let (level,parent) = self.bfs(s,delta);
        level[t]?;
        let arcs = self.path(s,t,&parent);
        let amount = self.bottleneck(&arcs);
        self.push(&arcs,amount);
        Some(Pushed {
            arcs,amount,phase:0,delta,cost:0
        })
    }
    fn maxflow(&mut self, s: usize, t: usize) -> Vec<Pushed> {
        let mut paths = Vec::new();
        while let Some(p) = self.augment(s,t,1) {
            paths.push(p);
        }
        paths
    }
    fn dinic(&mut self, s: usize, t: usize) -> (usize,Vec<Pushed>) {
        let mut phases = 0;
        let mut pushed = Vec::new();
        loop {
            let (level,_) = self.bfs(s,1);
            if level[t].is_none() {
                return (phases,pushed);
            }
            phases += 1;
            let lists: Vec<_> = (0..self.names.len()).map(|v|self.arcs(v)).collect();
            let mut pointers = vec![0;self.names.len()];
            let mut path = Vec::new();
            let mut u = s;
            loop {
                if u == t {
                    let amount = self.bottleneck(&path);
                    self.push(&path,amount);
                    pushed.push(Pushed {
                        arcs:path,amount,phase:phases,delta:1,cost:0
                    });
                    path = Vec::new();
                    u = s;
                } else if pointers[u] == lists[u].len() {
                    if u == s {
                        break;
                    }
                    let a = path.pop().unwrap();
                    u = self.start(a);
                    pointers[u] += 1;
                } else {
                    let a = lists[u][pointers[u]];
                    let v = self.end(a);
                    if self.residual(a) > 0 && level[v].is_some() && level[v].unwrap() == level[u].unwrap()+1 {
                        path.push(a);
                        u = v;
                    } else {
                        pointers[u] += 1;
                    }
                }
            }
        }
    }
    fn scaling(&mut self, s: usize, t: usize) -> Vec<Pushed> {
        let capacity = self.edges.iter().map(|e|e.capacity).max().unwrap_or(0);
        let mut delta = 1;
        while delta*2 <= capacity {
            delta *= 2;
        }
        let mut paths = Vec::new();
        while delta >= 1 {
            while let Some(p) = self.augment(s,t,delta) {
                paths.push(p);
            }
            delta /= 2;
        }
        paths
    }
    fn negative_cycle(&self, residual_lower: bool) -> bool {
        let mut distance = vec![0i64;self.names.len()];
        for pass in 0..self.names.len() {
            let mut changed = false;
            for e in &self.edges {
                if e.capacity-(if residual_lower {
                    e.lower
                } else {
                    0
                }) > 0 && distance[e.to] > distance[e.from]+e.cost {
                    distance[e.to] = distance[e.from]+e.cost;
                    changed = true;
                }
            }
            if !changed {
                return false;
            }
            if pass+1 == self.names.len() {
                return true;
            }
        }
        false
    }
    // Keep the usable arc sequence fixed and apply each relaxation immediately.
    fn shortest(&self, s: usize) -> (Vec<Option<i64>>,Vec<Option<Arc>>) {
        let arcs: Vec<_> = self.global_arcs().into_iter().filter(|&a|self.residual(a) > 0).collect();
        let mut distance = vec![None;self.names.len()];
        let mut parent = vec![None;self.names.len()];
        distance[s] = Some(0);
        loop {
            let mut changed = false;
            for &a in &arcs {
                let u = self.start(a);
                let v = self.end(a);
                if let Some(d) = distance[u] {
                    let next = d+self.arc_cost(a);
                    if distance[v].is_none_or(|old|next < old) {
                        distance[v] = Some(next);
                        parent[v] = Some(a);
                        changed = true;
                    }
                }
            }
            if !changed {
                return (distance,parent);
            }
        }
    }
    fn mincost(&mut self, s: usize, t: usize, target: Option<i64>) -> (i64,i64,Vec<Pushed>) {
        let mut amount = 0;
        let mut cost = 0;
        let mut paths = Vec::new();
        while target.is_none_or(|k|amount < k) {
            let (distance,parent) = self.shortest(s);
            let Some(unit) = distance[t] else {
                break;
            };
            let arcs = self.path(s,t,&parent);
            let mut delta = self.bottleneck(&arcs);
            if let Some(k) = target {
                delta = delta.min(k-amount);
            }
            self.push(&arcs,delta);
            amount += delta;
            cost += delta*unit;
            paths.push(Pushed {
                arcs,amount:delta,phase:0,delta:1,cost:unit
            });
        }
        (amount,cost,paths)
    }
    fn notation(&self, start: usize, path: &[Arc]) -> String {
        let mut text = self.names[start].clone();
        for &a in path {
            text += &format!(" {}{} {}",if a.forward {
                "+"
            } else {
                "-"
            },a.edge+1,self.names[self.end(a)]);
        }
        text
    }
    fn flows(&self) -> Vec<String> {
        self.edges.iter().enumerate().map(|(i,e)|format!("FLOW {} {} {} {}/{}",i+1,self.names[e.from],self.names[e.to],e.flow,e.capacity)).collect()
    }
    fn decompose(&self) -> Vec<Component> {
        let mut g: Vec<_> = self.edges.iter().map(|e|e.flow).collect();
        let mut balance = self.balances();
        let mut result = Vec::new();
        while let Some(first) = g.iter().position(|&f|f > 0) {
            let start = balance.iter().position(|&b|b > 0).unwrap_or(self.edges[first].from);
            let mut vertices = vec![start];
            let mut path = Vec::new();
            loop {
                let u = *vertices.last().unwrap();
                let i = self.edges.iter().enumerate().position(|(i,e)|e.from == u && g[i] > 0).unwrap();
                let v = self.edges[i].to;
                path.push(i);
                if let Some(q) = vertices.iter().position(|&x|x == v) {
                    let cycle = path[q..].to_vec();
                    let delta = cycle.iter().map(|&i|g[i]).min().unwrap();
                    for &i in &cycle {
                        g[i] -= delta;
                    }
                    result.push(Component {
                        start:v,edges:cycle,amount:delta,cycle:true
                    });
                    break;
                }
                vertices.push(v);
                if balance[v] < 0 {
                    let delta = path.iter().map(|&i|g[i]).min().unwrap().min(balance[start]).min(-balance[v]);
                    for &i in &path {
                        g[i] -= delta;
                    }
                    balance[start] -= delta;
                    balance[v] += delta;
                    result.push(Component {
                        start,edges:path,amount:delta,cycle:false
                    });
                    break;
                }
            }
        }
        result
    }
    fn command(&mut self, w: &[&str]) -> Result<Vec<String>,String> {
        let c = w[0];
        let a = &w[1..];
        let num = |i:usize|a[i].parse::<i64>().unwrap();
        let mut out = Vec::new();
        match c {
            "NODE" => {
                let mut seen: BTreeSet<_> = self.names.iter().map(String::as_str).collect();
                for &name in a {
                    if !seen.insert(name) {
                        return Err(error(format!("DUPLICATE NODE {name}")));
                    }
                }
                if self.names.len()+a.len() > 20 {
                    return Err(error("TOO MANY NODES"));
                }
                self.names.extend(a.iter().map(|n|n.to_string()));
                self.demands.resize(self.names.len(),0);
                out.push(format!("NODE added={} total={}",a.len(),self.names.len()));
            }
            "EDGE" => {
                let u = self.node(a[0])?;
                let v = self.node(a[1])?;
                if u == v {
                    return Err(error("SELF LOOP"));
                }
                if self.edges.len() == 60 {
                    return Err(error("TOO MANY EDGES"));
                }
                let cost = if a.len() == 4 {
                    num(3)
                } else {
                    0
                };
                self.edges.push(Edge {
                    from:u,to:v,capacity:num(2),cost,lower:0,flow:0
                });
                out.push(format!("EDGE {} {} {} cap={} cost={cost}",self.edges.len(),a[0],a[1],num(2)));
            }
            "LOWER" | "CAP" | "COST" => {
                let i = self.edge_number(a[0])?;
                let e = &mut self.edges[i];
                let n = num(1);
                match c {
                    "LOWER" => {
                        if n > e.capacity {
                            return Err(error("BAD BOUND"));
                        }
                        e.lower = n;
                        out.push(format!("LOWER {} low={n} cap={}",a[0],e.capacity));
                    }, "CAP" => {
                        if n < e.lower {
                            return Err(error("BAD BOUND"));
                        }
                        if n < e.flow {
                            return Err(error("BELOW FLOW"));
                        }
                        e.capacity = n;
                        out.push(format!("CAP {} low={} cap={n}",a[0],e.lower));
                    }, _ => {
                        e.cost = n;
                        out.push(format!("COST {} cost={n}",a[0]));
                    }
                }
            }
            "DEMAND" => {
                let i = self.node(a[0])?;
                self.demands[i] = num(1);
                out.push(format!("DEMAND {} {} total={}",a[0],num(1),self.demands.iter().sum::<i64>()));
            }
            "RESET" => {
                out.push(format!("RESET edges={}",self.edges.iter().filter(|e|e.flow != 0).count()));
                self.zero();
                self.owner = Owner::None;
            }
            "CLEAR" => {
                out.push(format!("CLEAR nodes={} edges={}",self.names.len(),self.edges.len()));
                *self = Self::new();
            }
            "SHOW" => {
                let balance = self.balances();
                out.push(format!("NETWORK nodes={} edges={}",self.names.len(),self.edges.len()));
                out.push(match self.owner {
                    Owner::None => "STATE none".into(), Owner::Circulation => format!("STATE circulation cost={}",self.cost()), Owner::Flow(s,t) => format!("STATE flow {} {} value={} cost={}",self.names[s],self.names[t],balance[s],self.cost())
                });
                for (i,name) in self.names.iter().enumerate() {
                    let sent: i64 = self.edges.iter().filter(|e|e.from == i).map(|e|e.flow).sum();
                    let received: i64 = self.edges.iter().filter(|e|e.to == i).map(|e|e.flow).sum();
                    out.push(format!("NODE {name} demand={} out={sent} in={received}",self.demands[i]));
                }
                for (i,e) in self.edges.iter().enumerate() {
                    out.push(format!("EDGE {} {} {} cap={} cost={} low={} flow={}",i+1,self.names[e.from],self.names[e.to],e.capacity,e.cost,e.lower,e.flow));
                }
            }
            "AUGMENT" | "MAXFLOW" | "DINIC" | "SCALING" | "MINCUT" => {
                let (s,t) = self.endpoints(a[0],a[1])?;
                let start = self.begin(s,t);
                if c == "AUGMENT" {
                    if let Some(p) = self.augment(s,t,1) {
                        out.push(format!("AUGMENT {} {} value={} amount={} {}",a[0],a[1],self.balances()[s],p.amount,self.notation(s,&p.arcs)));
                    } else {
                        out.push(format!("AUGMENT {} {} value={} none",a[0],a[1],self.balances()[s]));
                    }
                } else if c == "MINCUT" {
                    self.maxflow(s,t);
                    let (level,_) = self.bfs(s,1);
                    let cut: Vec<_> = self.edges.iter().enumerate().filter(|(_,e)|level[e.from].is_some() && level[e.to].is_none()).collect();
                    out.push(format!("MINCUT {} {} value={} edges={}",a[0],a[1],self.balances()[s],cut.len()));
                    out.push(format!("SOURCE {}",self.names.iter().enumerate().filter(|(i,_)|level[*i].is_some()).map(|(_,n)|n.as_str()).collect::<Vec<_>>().join(" ")));
                    out.push(format!("SINK {}",self.names.iter().enumerate().filter(|(i,_)|level[*i].is_none()).map(|(_,n)|n.as_str()).collect::<Vec<_>>().join(" ")));
                    for (i,e) in cut {
                        out.push(format!("CUT {} {} {} {}",i+1,self.names[e.from],self.names[e.to],e.capacity));
                    }
                } else {
                    let (phases,paths) = if c == "DINIC" {
                        self.dinic(s,t)
                    } else if c == "SCALING" {
                        (0,self.scaling(s,t))
                    } else {
                        (0,self.maxflow(s,t))
                    };
                    out.push(format!("{c} {} {} value={} start={start}{} paths={}",a[0],a[1],self.balances()[s],if c == "DINIC" {
                        format!(" phases={phases}")
                    } else {
                        String::new()
                    },paths.len()));
                    for (i,p) in paths.iter().enumerate() {
                        let extra = if c == "DINIC" {
                            format!(" phase={}",p.phase)
                        } else if c == "SCALING" {
                            format!(" delta={}",p.delta)
                        } else {
                            String::new()
                        };
                        out.push(format!("AUG {}{extra} amount={} {}",i+1,p.amount,self.notation(s,&p.arcs)));
                    }
                    out.extend(self.flows());
                }
            }
            "SENSITIVITY" => {
                let (s,t) = self.endpoints(a[0],a[1])?;
                let mut base = self.clone();
                base.zero();
                base.maxflow(s,t);
                let value = base.balances()[s];
                let mut up = 0;
                let mut down = 0;
                let mut lines = Vec::new();
                for i in 0..self.edges.len() {
                    let mut work = self.clone();
                    work.zero();
                    work.edges[i].capacity += 1;
                    work.maxflow(s,t);
                    let effective_up = work.balances()[s] > value;
                    let mut effective_down = false;
                    if self.edges[i].capacity > 0 {
                        work = self.clone();
                        work.zero();
                        work.edges[i].capacity -= 1;
                        work.maxflow(s,t);
                        effective_down = work.balances()[s] < value;
                    }
                    up += usize::from(effective_up);
                    down += usize::from(effective_down);
                    if effective_up || effective_down {
                        let e = &self.edges[i];
                        lines.push(format!("CRITICAL {} {} {} up={} down={}",i+1,self.names[e.from],self.names[e.to],if effective_up {
                            "yes"
                        } else {
                            "no"
                        },if effective_down {
                            "yes"
                        } else {
                            "no"
                        }));
                    }
                }
                out.push(format!("SENSITIVITY {} {} value={value} up={up} down={down}",a[0],a[1]));
                out.extend(lines);
            }
            "MINCOST" => {
                let (s,t) = self.endpoints(a[0],a[1])?;
                if self.negative_cycle(false) {
                    return Err(error("NEGATIVE CYCLE"));
                }
                let target = if a[2] == "MAX" {
                    None
                } else {
                    Some(num(2))
                };
                let mut work = self.clone();
                work.zero();
                let (amount,cost,paths) = work.mincost(s,t,target);
                if target.is_some_and(|k|amount < k) {
                    out.push(format!("MINCOST {} {} k={} infeasible max={amount}",a[0],a[1],a[2]));
                } else {
                    for (e,new) in self.edges.iter_mut().zip(work.edges.iter()) {
                        e.flow = new.flow;
                    }
                    self.owner = Owner::Flow(s,t);
                    out.push(format!("MINCOST {} {} k={} flow={amount} cost={cost}",a[0],a[1],a[2]));
                    for (i,p) in paths.iter().enumerate() {
                        out.push(format!("AUG {} amount={} cost={} {}",i+1,p.amount,p.cost,self.notation(s,&p.arcs)));
                    }
                    out.extend(self.flows());
                }
            }
            "DISJOINT" => {
                let (s,t) = self.endpoints(a[0],a[1])?;
                let original = self.edges.len();
                let mut work = self.clone();
                work.zero();
                let mut exits: Vec<_> = (0..self.names.len()).collect();
                if a[2] == "VERTEX" {
                    for (v,exit) in exits.iter_mut().enumerate() {
                        if v != s && v != t {
                            *exit = work.names.len();
                            work.names.push(self.names[v].clone());
                            work.demands.push(0);
                        }
                    }
                }
                for e in &mut work.edges {
                    e.from = exits[e.from];
                    e.capacity = i64::from(e.capacity > 0);
                    e.cost = 0;
                }
                if a[2] == "VERTEX" {
                    for (v,&exit) in exits.iter().enumerate() {
                        if v != s && v != t {
                            work.edges.push(Edge {
                                from:v,to:exit,capacity:1,cost:0,lower:0,flow:0
                            });
                        }
                    }
                }
                work.maxflow(s,t);
                let paths: Vec<_> = work.decompose().into_iter().filter(|p|!p.cycle).collect();
                out.push(format!("DISJOINT {} {} {} count={}",a[0],a[1],a[2],paths.len()));
                for (i,p) in paths.iter().enumerate() {
                    let arcs: Vec<_> = p.edges.iter().filter(|&&e|e < original).map(|&edge|Arc {
                        edge,forward:true
                    }).collect();
                    out.push(format!("PATH {} {}",i+1,self.notation(s,&arcs)));
                }
            }
            "DECOMPOSE" => {
                let parts = self.decompose();
                out.push(format!("DECOMPOSE paths={} cycles={}",parts.iter().filter(|p|!p.cycle).count(),parts.iter().filter(|p|p.cycle).count()));
                let mut counts = [0,0];
                for p in parts {
                    let kind = usize::from(p.cycle);
                    counts[kind] += 1;
                    let arcs: Vec<_> = p.edges.iter().map(|&edge|Arc {
                        edge,forward:true
                    }).collect();
                    out.push(format!("{} {} amount={} {}",if p.cycle {
                        "CYCLE"
                    } else {
                        "PATH"
                    },counts[kind],p.amount,self.notation(p.start,&arcs)));
                }
            }
            "VERIFY" => {
                let mut violations = Vec::new();
                for (i,e) in self.edges.iter().enumerate() {
                    if e.flow < e.lower {
                        violations.push(format!("LOW {} flow={} low={}",i+1,e.flow,e.lower));
                    }
                }
                let balance = self.balances();
                for (i,&b) in balance.iter().enumerate() {
                    let need = match self.owner {
                        Owner::Flow(s,t) if i == s || i == t => None, Owner::Flow(_,_) => Some(0), _ => Some(self.demands[i])
                    };
                    if let Some(need) = need {
                        if -b != need {
                            violations.push(format!("BALANCE {} net={} need={need}",self.names[i],-b));
                        }
                    }
                }
                if violations.is_empty() {
                    out.push("VERIFY ok".into());
                } else {
                    out.push(format!("VERIFY violations={}",violations.len()));
                    out.extend(violations);
                }
            }
            "CIRCULATION" => {
                if a[0] == "MINCOST" && self.negative_cycle(true) {
                    return Err(error("NEGATIVE CYCLE"));
                }
                let sum: i64 = self.demands.iter().sum();
                if sum != 0 {
                    return Ok(vec![format!("CIRCULATION infeasible unbalanced={sum}")]);
                }
                let n = self.names.len();
                let mut work = self.clone();
                work.names.extend(["super source".into(),"super sink".into()]);
                work.demands.extend([0,0]);
                let mut required = self.demands.clone();
                for e in &mut work.edges {
                    required[e.to] -= e.lower;
                    required[e.from] += e.lower;
                    e.capacity -= e.lower;
                    e.flow = 0;
                }
                for (v,&r) in required.iter().enumerate() {
                    if r < 0 {
                        work.edges.push(Edge {
                            from:n,to:v,capacity:-r,cost:0,lower:0,flow:0
                        });
                    }
                }
                let sink_start = work.edges.len();
                for (v,&r) in required.iter().enumerate() {
                    if r > 0 {
                        work.edges.push(Edge {
                            from:v,to:n+1,capacity:r,cost:0,lower:0,flow:0
                        });
                    }
                }
                if a[0] == "ANY" {
                    work.maxflow(n,n+1);
                } else {
                    work.mincost(n,n+1,None);
                }
                let total: i64 = required.iter().filter(|&&r|r > 0).sum();
                let achieved: i64 = work.edges[sink_start..].iter().map(|e|e.flow).sum();
                if achieved < total {
                    let (level,_) = work.bfs(n,1);
                    out.push(format!("CIRCULATION infeasible required={total} achieved={achieved}"));
                    out.push(format!("CUT {}",self.names.iter().enumerate().filter(|(v,_)|level[*v].is_some()).map(|(_,s)|s.as_str()).collect::<Vec<_>>().join(" ")));
                } else {
                    for (e,new) in self.edges.iter_mut().zip(work.edges.iter()) {
                        e.flow = e.lower+new.flow;
                    }
                    self.owner = Owner::Circulation;
                    out.push(format!("CIRCULATION feasible required={total} cost={}",self.cost()));
                    out.extend(self.flows());
                }
            }
            "MATCH" => out = matching(a)?,
            "ASSIGN" => out = assignment(a)?,
            _ => unreachable!(),
        }
        Ok(out)
    }
}

fn matching(a: &[&str]) -> Result<Vec<String>,String> {
    let left: Vec<_> = a[0].split(',').collect();
    let right: Vec<_> = a[1].split(',').collect();
    let mut seen = BTreeSet::new();
    for &n in left.iter().chain(right.iter()) {
        if !seen.insert(n) {
            return Err(error(format!("DUPLICATE VERTEX {n}")));
        }
    }
    let mut pairs = Vec::new();
    if a[2] != "-" {
        for p in a[2].split(',') {
            let (x,y) = p.split_once('-').unwrap();
            let u = left.iter().position(|&n|n == x).ok_or_else(||error(format!("UNKNOWN VERTEX {x}")))?;
            let v = right.iter().position(|&n|n == y).ok_or_else(||error(format!("UNKNOWN VERTEX {y}")))?;
            if pairs.contains(&(u,v)) {
                return Err(error(format!("DUPLICATE PAIR {p}")));
            }
            pairs.push((u,v));
        }
    }
    fn attempt(u: usize, pairs: &[(usize,usize)], examined: &mut [bool], lp: &mut [Option<usize>], rp: &mut [Option<usize>]) -> bool {
        for &(a,b) in pairs {
            if a != u || examined[b] {
                continue;
            }
            examined[b] = true;
            if rp[b].is_none() || attempt(rp[b].unwrap(),pairs,examined,lp,rp) {
                lp[u] = Some(b);
                rp[b] = Some(u);
                return true;
            }
        }
        false
    }
    let mut lp = vec![None;left.len()];
    let mut rp = vec![None;right.len()];
    for u in 0..left.len() {
        attempt(u,&pairs,&mut vec![false;right.len()],&mut lp,&mut rp);
    }
    let mut zl: Vec<_> = lp.iter().map(Option::is_none).collect();
    let mut zr = vec![false;right.len()];
    loop {
        let mut changed = false;
        for &(u,v) in &pairs {
            if zl[u] && lp[u] != Some(v) && !zr[v] {
                zr[v] = true;
                changed = true;
            }
        }
        for v in 0..right.len() {
            if zr[v] {
                if let Some(u) = rp[v] {
                    if !zl[u] {
                        zl[u] = true;
                        changed = true;
                    }
                }
            }
        }
        if !changed {
            break;
        }
    }
    let size = lp.iter().filter(|p|p.is_some()).count();
    let mut out = vec![format!("MATCH size={size} left={} right={}",left.len(),right.len())];
    for (u,p) in lp.iter().enumerate() {
        if let Some(v) = p {
            out.push(format!("PAIR {} {}",left[u],right[*v]));
        }
    }
    let list = |values:Vec<&str>|if values.is_empty() {
        "-".into()
    } else {
        values.join(",")
    };
    out.push(format!("FREE {} {}",list(left.iter().enumerate().filter(|(i,_)|lp[*i].is_none()).map(|(_,n)|*n).collect()),list(right.iter().enumerate().filter(|(i,_)|rp[*i].is_none()).map(|(_,n)|*n).collect())));
    let cover: Vec<_> = left.iter().enumerate().filter(|(i,_)|!zl[*i]).map(|(_,n)|*n).chain(right.iter().enumerate().filter(|(i,_)|zr[*i]).map(|(_,n)|*n)).collect();
    out.push(format!("COVER size={}{}",cover.len(),if cover.is_empty() {
        String::new()
    } else {
        " ".to_string()+&cover.join(" ")
    }));
    if lp.iter().any(Option::is_none) {
        out.push(format!("HALL {} {}",list(left.iter().enumerate().filter(|(i,_)|zl[*i]).map(|(_,n)|*n).collect()),list(right.iter().enumerate().filter(|(i,_)|zr[*i]).map(|(_,n)|*n).collect())));
    }
    Ok(out)
}

fn assignment(a: &[&str]) -> Result<Vec<String>,String> {
    let n: usize = a[1].parse().unwrap();
    if !(1..=8).contains(&n) {
        return Err(error("BAD SIZE"));
    }
    if a.len()-2 != n*n {
        return Err(error("BAD LENGTH"));
    }
    let values: Vec<Option<i64>> = a[2..].iter().map(|s|if *s == "x" {
        None
    } else {
        Some(s.parse().unwrap())
    }).collect();
    fn visit(n: usize, values: &[Option<i64>], maximize: bool, chosen: &mut Vec<usize>, used: u32, sum: i64, best: &mut Option<(i64,usize,Vec<usize>)>) {
        let row = chosen.len();
        if row == n {
            if best.as_ref().is_none_or(|b|if maximize {
                sum > b.0
            } else {
                sum < b.0
            }) {
                *best = Some((sum,1,chosen.clone()));
            } else if best.as_ref().unwrap().0 == sum {
                best.as_mut().unwrap().1 += 1;
            }
            return;
        }
        for col in 0..n {
            if used & (1 << col) == 0 {
                if let Some(v) = values[row*n+col] {
                    chosen.push(col);
                    visit(n,values,maximize,chosen,used | (1 << col),sum+v,best);
                    chosen.pop();
                }
            }
        }
    }
    let mut best = None;
    visit(n,&values,a[0] == "MAX",&mut Vec::new(),0,0,&mut best);
    if let Some((sum,count,chosen)) = best {
        let mut out = vec![format!("ASSIGN {} n={n} total={sum} optimal={count}",a[0])];
        for (row,&col) in chosen.iter().enumerate() {
            out.push(format!("MATE {} {} {}",row+1,col+1,values[row*n+col].unwrap()));
        }
        Ok(out)
    } else {
        Ok(vec![format!("ASSIGN {} n={n} infeasible",a[0])])
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let n: usize = lines.next().unwrap().parse().unwrap();
    let mut network = Network::new();
    for line in lines.take(n) {
        match network.command(&line.split(' ').collect::<Vec<_>>()) {
            Ok(out) => for line in out {
                println!("{line}");
            }, Err(error) => println!("{error}")
        }
    }
}
