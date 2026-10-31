use std::collections::{HashMap, VecDeque};
use std::io::{self, Read, Write};

type Matching = Vec<Option<usize>>;
type Response = Result<Vec<String>, String>;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind { TwoSided, Roommate, Housing }

#[derive(Clone, Copy)]
enum Side { Proposer, Receiver }

#[derive(Clone, Copy)]
enum Source { Gs, Gsr, Boston, Egalitarian, MinRegret }

impl Source {
    fn name(self) -> &'static str {
        match self {
            Self::Gs => "GS", Self::Gsr => "GSR", Self::Boston => "BOSTON",
            Self::Egalitarian => "EGALITARIAN", Self::MinRegret => "MINREGRET",
        }
    }
}

#[derive(Clone)]
struct Agent {
    name: String,
    preference: Vec<usize>,
    capacity: usize,
}

impl Agent {
    fn new(name: &str) -> Self {
        Self { name: name.into(), preference: Vec::new(), capacity: 1 }
    }
}

#[derive(Clone)]
struct Market {
    name: String,
    kind: Kind,
    agents: Vec<Agent>,
    houses: Vec<String>,
    proposers: usize,
    current: Option<(Source, Matching)>,
}

struct Run {
    matching: Matching,
    proposals: usize,
    history: Vec<String>,
}

#[derive(Clone, PartialEq, Eq)]
struct Rotation { pairs: Vec<(usize, usize)> }

struct Candidate {
    matching: Matching,
    origin: Option<usize>,
    via: Option<usize>,
    cost: usize,
    regret: usize,
}

struct Lattice { matchings: Vec<Candidate>, rotations: Vec<Rotation> }

fn list_text(values: impl IntoIterator<Item = String>) -> String {
    let text = values.into_iter().collect::<Vec<_>>().join(" ");
    if text.is_empty() { "-".into() } else { text }
}

impl Market {
    fn require(&self, kind: Kind) -> Result<(), String> {
        if self.kind == kind { Ok(()) } else { Err(format!("WRONG TYPE {}", self.name)) }
    }

    fn agent(&self, name: &str, side: Option<Side>) -> Result<usize, String> {
        let index = self.agents.iter().position(|a| a.name == name)
            .ok_or_else(|| format!("UNKNOWN AGENT {name}"))?;
        match side {
            Some(Side::Proposer) if index >= self.proposers => Err(format!("NOT PROPOSER {name}")),
            Some(Side::Receiver) if index < self.proposers => Err(format!("NOT RECEIVER {name}")),
            _ => Ok(index),
        }
    }

    fn rank(&self, agent: usize, partner: Option<usize>) -> usize {
        let preference = &self.agents[agent].preference;
        preference.iter().position(|&p| Some(p) == partner).map_or(preference.len() + 1, |i| i + 1)
    }

    fn accepts(&self, agent: usize, partner: usize) -> bool {
        self.agents[agent].preference.contains(&partner)
    }

    fn partner_name(&self, partner: Option<usize>) -> &str {
        partner.map_or("*", |a| self.agents[a].name.as_str())
    }

    fn pairs(&self, matching: &Matching) -> String {
        (0..self.proposers).map(|p| format!("{}-{}", self.agents[p].name, self.partner_name(matching[p])))
            .collect::<Vec<_>>().join(" ")
    }

    fn allocation(&self, allocation: &Matching) -> String {
        self.agents.iter().enumerate().map(|(a, agent)| {
            let house = allocation[a].map_or("*", |h| self.houses[h].as_str());
            format!("{}-{house}", agent.name)
        }).collect::<Vec<_>>().join(" ")
    }

    fn effective(&self, agent: usize) -> Vec<usize> {
        let preference = &self.agents[agent].preference;
        if let Some(i) = preference.iter().position(|&house| house == agent) {
            preference[..=i].to_vec()
        } else {
            let mut result = preference.clone();
            result.push(agent);
            result
        }
    }

    fn able(&self, agent: usize, next: &[usize], counts: &[usize]) -> bool {
        counts[agent] < self.agents[agent].capacity && next[agent] < self.agents[agent].preference.len()
    }

    fn deferred(&self, reverse: bool, verbose: bool) -> Run {
        let n = self.agents.len();
        let mut next = vec![0; n];
        let mut counts = vec![0; n];
        let mut holding = vec![Vec::new(); n];
        let proposing = if reverse { self.proposers..n } else { 0..self.proposers };
        let mut queue: VecDeque<_> = proposing.filter(|&a| self.able(a, &next, &counts)).collect();
        let mut proposals = 0;
        let mut history = Vec::new();
        while let Some(x) = queue.pop_front() {
            let y = self.agents[x].preference[next[x]];
            next[x] += 1;
            proposals += 1;
            let mut action = "REJECT".to_string();
            if self.accepts(y, x) {
                if holding[y].len() < self.agents[y].capacity {
                    holding[y].push(x);
                    counts[x] += 1;
                    action = "HOLD".into();
                } else {
                    let worst = (0..holding[y].len()).max_by_key(|&i| self.rank(y, Some(holding[y][i]))).unwrap();
                    let rejected = holding[y][worst];
                    if self.rank(y, Some(x)) < self.rank(y, Some(rejected)) {
                        holding[y][worst] = x;
                        counts[rejected] -= 1;
                        counts[x] += 1;
                        action = format!("HOLD REJECT {}", self.agents[rejected].name);
                        if self.able(rejected, &next, &counts) && !queue.contains(&rejected) { queue.push_back(rejected); }
                    }
                }
            }
            if verbose { history.push(format!("PROPOSE {} {} {action}", self.agents[x].name, self.agents[y].name)); }
            if self.able(x, &next, &counts) { queue.push_back(x); }
        }
        let mut matching = vec![None; self.proposers];
        let receiving = if reverse { 0..self.proposers } else { self.proposers..n };
        for y in receiving {
            for &x in &holding[y] {
                if reverse { matching[y] = Some(x); } else { matching[x] = Some(y); }
            }
        }
        Run { matching, proposals, history }
    }

    fn boston(&self) -> Run {
        let mut matching = vec![None; self.proposers];
        let mut remaining: Vec<_> = self.agents.iter().map(|a| a.capacity).collect();
        let rounds = self.agents[..self.proposers].iter().map(|a| a.preference.len()).max().unwrap();
        let mut applications = 0;
        for round in 0..rounds {
            let mut applicants = vec![None; self.proposers];
            for p in 0..self.proposers {
                if matching[p].is_none() && round < self.agents[p].preference.len() {
                    applicants[p] = Some(self.agents[p].preference[round]);
                    applications += 1;
                }
            }
            for r in self.proposers..self.agents.len() {
                for &p in &self.agents[r].preference {
                    if remaining[r] > 0 && applicants[p] == Some(r) {
                        matching[p] = Some(r);
                        remaining[r] -= 1;
                    }
                }
            }
        }
        Run { matching, proposals: applications, history: Vec::new() }
    }

    fn rotations(&self, matching: &Matching) -> Vec<Rotation> {
        let mut owners = vec![None; self.agents.len()];
        for (p, &partner) in matching.iter().enumerate() {
            if let Some(r) = partner { owners[r] = Some(p); }
        }
        let mut successors = vec![None; self.proposers];
        for p in 0..self.proposers {
            if matching[p].is_none() { continue; }
            for &r in self.agents[p].preference.iter().skip(self.rank(p, matching[p])) {
                if self.accepts(r, p) && (owners[r].is_none() || self.rank(r, Some(p)) < self.rank(r, owners[r])) {
                    successors[p] = owners[r];
                    break;
                }
            }
        }
        let mut rotations = Vec::new();
        let mut covered = vec![false; self.proposers];
        for start in 0..self.proposers {
            if covered[start] { continue; }
            let mut seen = vec![false; self.proposers];
            let mut path = Vec::new();
            let mut current = Some(start);
            while let Some(p) = current {
                if seen[p] { break; }
                seen[p] = true;
                path.push(p);
                current = successors[p];
            }
            if current == Some(start) {
                for &p in &path { covered[p] = true; }
                rotations.push(Rotation { pairs: path.into_iter().map(|p| (p, matching[p].unwrap())).collect() });
            }
        }
        rotations
    }

    fn candidate(&self, matching: Matching, origin: Option<usize>, via: Option<usize>) -> Candidate {
        let mut cost = 0;
        let mut regret = 0;
        for (p, &partner) in matching.iter().enumerate() {
            if let Some(r) = partner {
                let a = self.rank(p, Some(r));
                let b = self.rank(r, Some(p));
                cost += a + b;
                regret = regret.max(a).max(b);
            }
        }
        Candidate { matching, origin, via, cost, regret }
    }

    fn enumerate(&self) -> Result<Lattice, String> {
        if self.agents[self.proposers..].iter().any(|a| a.capacity != 1) { return Err("NOT ONE TO ONE".into()); }
        let mut matchings = vec![self.candidate(self.deferred(false, false).matching, None, None)];
        let mut rotations = Vec::new();
        let mut index = 0;
        while index < matchings.len() {
            let matching = matchings[index].matching.clone();
            for rotation in self.rotations(&matching) {
                let number = if let Some(i) = rotations.iter().position(|old| old == &rotation) { i } else {
                    rotations.push(rotation.clone());
                    rotations.len() - 1
                };
                let mut next = matching.clone();
                for (i, &(p, _)) in rotation.pairs.iter().enumerate() {
                    next[p] = Some(rotation.pairs[(i + 1) % rotation.pairs.len()].1);
                }
                if matchings.iter().any(|old| old.matching == next) { continue; }
                if matchings.len() == 50 { return Err("TOO MANY MATCHINGS".into()); }
                matchings.push(self.candidate(next, Some(index + 1), Some(number + 1)));
            }
            index += 1;
        }
        Ok(Lattice { matchings, rotations })
    }

    fn check(&self, words: &[&str]) -> Response {
        if self.kind == Kind::Housing { return Err(format!("WRONG TYPE {}", self.name)); }
        let mut partners = vec![None; self.agents.len()];
        let mut counts = vec![0; self.agents.len()];
        for word in &words[2..] {
            let (left, right) = word.split_once('-').unwrap();
            let two = self.kind == Kind::TwoSided;
            let x = self.agent(left, if two { Some(Side::Proposer) } else { None })?;
            let y = self.agent(right, if two { Some(Side::Receiver) } else { None })?;
            if partners[x].is_some() { return Err(format!("DUPLICATE AGENT {left}")); }
            if two {
                counts[y] += 1;
                if counts[y] > self.agents[y].capacity { return Err(format!("OVER CAPACITY {right}")); }
            } else {
                if x == y || partners[y].is_some() { return Err(format!("DUPLICATE AGENT {right}")); }
                partners[y] = Some(x);
            }
            partners[x] = Some(y);
        }
        let mut unacceptable = Vec::new();
        let mut blocking = Vec::new();
        if self.kind == Kind::TwoSided {
            for p in 0..self.proposers {
                if let Some(r) = partners[p] {
                    if !self.accepts(p, r) || !self.accepts(r, p) { unacceptable.push((p, r)); }
                }
                for r in self.proposers..self.agents.len() {
                    if partners[p] == Some(r) || !self.accepts(p, r) || !self.accepts(r, p)
                        || self.rank(p, Some(r)) >= self.rank(p, partners[p]) { continue; }
                    let worst = (0..self.proposers).filter(|&a| partners[a] == Some(r)).map(|a| self.rank(r, Some(a))).max();
                    if counts[r] < self.agents[r].capacity || self.rank(r, Some(p)) < worst.unwrap() { blocking.push((p, r)); }
                }
            }
        } else {
            for a in 0..self.agents.len() {
                for b in a + 1..self.agents.len() {
                    let mutual = self.accepts(a, b) && self.accepts(b, a);
                    if partners[a] == Some(b) {
                        if !mutual { unacceptable.push((a, b)); }
                    } else if mutual && self.rank(a, Some(b)) < self.rank(a, partners[a])
                        && self.rank(b, Some(a)) < self.rank(b, partners[b]) { blocking.push((a, b)); }
                }
            }
        }
        if unacceptable.is_empty() && blocking.is_empty() { return Ok(vec![format!("CHECK {} STABLE", self.name)]); }
        let mut output = vec![format!("CHECK {} UNSTABLE unacceptable={} blocking={}", self.name, unacceptable.len(), blocking.len())];
        for (label, pairs) in [("UNACCEPTABLE", unacceptable), ("BLOCKING", blocking)] {
            for (a, b) in pairs { output.push(format!("{label} {} {}", self.agents[a].name, self.agents[b].name)); }
        }
        Ok(output)
    }

    fn table(&self, lists: &[Vec<usize>], output: &mut Vec<String>) {
        for (a, list) in lists.iter().enumerate() {
            output.push(format!("TABLE {} {}", self.agents[a].name, list_text(list.iter().map(|&b| self.agents[b].name.clone()))));
        }
    }

    fn roommates(&self, verbose: bool) -> Response {
        self.require(Kind::Roommate)?;
        let n = self.agents.len();
        for agent in &self.agents {
            if agent.preference.len() < n - 1 { return Err(format!("INCOMPLETE {}", agent.name)); }
        }
        let mut lists: Vec<_> = self.agents.iter().map(|a| a.preference.clone()).collect();
        let mut held = vec![None; n];
        let mut queue: VecDeque<_> = (0..n).collect();
        let mut proposals = 0;
        let mut failure = None;
        while let Some(x) = queue.pop_front() {
            let y = lists[x][0];
            if let Some(z) = held[y] { queue.push_back(z); }
            held[y] = Some(x);
            proposals += 1;
            let cut = lists[y].iter().position(|&a| a == x).unwrap();
            let removed = lists[y][cut + 1..].to_vec();
            for w in removed { remove_pair(&mut lists, y, w); }
            failure = lists.iter().position(Vec::is_empty);
            if failure.is_some() { break; }
        }
        let mut history = Vec::new();
        let mut rotations = 0;
        if failure.is_none() && verbose { self.table(&lists, &mut history); }
        while failure.is_none() {
            let Some(mut p) = lists.iter().position(|list| list.len() >= 2) else { break; };
            let mut path = Vec::new();
            let mut positions = vec![None; n];
            while positions[p].is_none() {
                positions[p] = Some(path.len());
                path.push(p);
                let q = lists[p][1];
                p = *lists[q].last().unwrap();
            }
            let cycle = &path[positions[p].unwrap()..];
            let front: Vec<_> = cycle.iter().map(|&x| lists[x][0]).collect();
            rotations += 1;
            let notation = cycle.iter().zip(&front).map(|(&x, &y)| format!("{}-{}", self.agents[x].name, self.agents[y].name))
                .collect::<Vec<_>>().join(" ");
            history.push(format!("ROTATION {rotations} {notation}"));
            let mut removals = Vec::new();
            for (i, &x) in cycle.iter().enumerate() {
                let u = front[(i + 1) % front.len()];
                let cut = lists[u].iter().position(|&a| a == x).unwrap();
                for &w in &lists[u][cut + 1..] { removals.push((u, w)); }
            }
            for (a, b) in removals { remove_pair(&mut lists, a, b); }
            if verbose { self.table(&lists, &mut history); }
            failure = lists.iter().position(Vec::is_empty);
        }
        let mut output = vec![format!("ROOMMATES {} proposals={proposals}", self.name)];
        output.extend(history);
        if let Some(a) = failure { output.push(format!("NO STABLE MATCHING {}", self.agents[a].name)); }
        else {
            let pairs = (0..n).filter(|&a| a < lists[a][0]).map(|a| format!("{}-{}", self.agents[a].name, self.agents[lists[a][0]].name))
                .collect::<Vec<_>>().join(" ");
            output.push(format!("MATCHING {pairs}"));
        }
        Ok(output)
    }

    fn ttc(&self) -> Vec<String> {
        let n = self.agents.len();
        let effective: Vec<_> = (0..n).map(|a| self.effective(a)).collect();
        let mut remaining = vec![true; n];
        let mut allocation = vec![None; n];
        let mut history = Vec::new();
        while let Some(start) = remaining.iter().position(|&value| value) {
            let mut points = vec![0; n];
            for a in 0..n {
                if remaining[a] { points[a] = *effective[a].iter().find(|&&house| remaining[house]).unwrap(); }
            }
            let mut seen = vec![false; n];
            let mut p = start;
            while !seen[p] { seen[p] = true; p = points[p]; }
            let first = p;
            let mut cycle = Vec::new();
            loop {
                allocation[p] = Some(points[p]);
                remaining[p] = false;
                cycle.push(format!("{}:{}", self.agents[p].name, self.houses[points[p]]));
                p = points[p];
                if p == first { break; }
            }
            history.push(format!("CYCLE {} {}", history.len() + 1, cycle.join(" ")));
        }
        let mut output = vec![format!("TTC {} cycles={}", self.name, history.len())];
        output.extend(history);
        output.push(format!("ALLOCATION {}", self.allocation(&allocation)));
        output
    }

    fn serial(&self, words: &[&str]) -> Response {
        let n = self.agents.len();
        let mut order = Vec::new();
        for name in &words[2..] {
            let a = self.agent(name, None)?;
            if order.contains(&a) { return Err(format!("DUPLICATE AGENT {name}")); }
            order.push(a);
        }
        if order.len() != n { return Err("BAD ORDER".into()); }
        let mut taken = vec![false; n];
        let mut allocation = vec![None; n];
        for a in order {
            if let Some(&house) = self.agents[a].preference.iter().find(|&&house| !taken[house]) {
                allocation[a] = Some(house);
                taken[house] = true;
            }
        }
        let assigned = allocation.iter().filter(|house| house.is_some()).count();
        let worse = list_text((0..n).filter(|&a| allocation[a].is_none_or(|house| !self.effective(a).contains(&house)))
            .map(|a| self.agents[a].name.clone()));
        Ok(vec![format!("SERIAL {} assigned={assigned}", self.name), format!("ALLOCATION {}", self.allocation(&allocation)), format!("WORSE {worse}")])
    }

    fn hr(&self) -> Vec<String> {
        let resident = self.deferred(false, false).matching;
        let hospital = self.deferred(true, false).matching;
        let unmatched = list_text((0..self.proposers).filter(|&p| resident[p].is_none()).map(|p| self.agents[p].name.clone()));
        let mut output = vec![format!("HR {} residents={} hospitals={}", self.name, self.proposers, self.agents.len() - self.proposers),
            format!("RESIDENT-OPTIMAL {}", self.pairs(&resident)), format!("HOSPITAL-OPTIMAL {}", self.pairs(&hospital)), format!("UNMATCHED {unmatched}")];
        let mut rural = (0..self.proposers).all(|p| resident[p].is_some() == hospital[p].is_some());
        for r in self.proposers..self.agents.len() {
            let a: Vec<_> = (0..self.proposers).filter(|&p| resident[p] == Some(r)).collect();
            let h: Vec<_> = (0..self.proposers).filter(|&p| hospital[p] == Some(r)).collect();
            let same = a == h;
            let capacity = self.agents[r].capacity;
            output.push(format!("HOSPITAL {} cap={capacity} resident={} hospital={} same={}", self.agents[r].name, a.len(), h.len(), if same { "YES" } else { "NO" }));
            rural &= a.len() == h.len() && (a.len() == capacity || same);
        }
        output.push(format!("RURAL {}", if rural { "HOLDS" } else { "FAILS" }));
        output
    }

    fn manipulate(&self, a: usize) -> Vec<String> {
        let truth = &self.agents[a].preference;
        let baseline_b = self.boston().matching[a];
        let baseline_g = self.deferred(false, false).matching[a];
        let mut output = vec![format!("MANIPULATE {} {} boston={} gs={} swaps={}", self.name, self.agents[a].name,
            self.partner_name(baseline_b), self.partner_name(baseline_g), truth.len().saturating_sub(1))];
        for i in 0..truth.len().saturating_sub(1) {
            let mut trial = self.clone();
            trial.agents[a].preference.swap(i, i + 1);
            let b = trial.boston().matching[a];
            let g = trial.deferred(false, false).matching[a];
            for (label, result, baseline) in [("BOSTON", b, baseline_b), ("GS", g, baseline_g)] {
                if self.rank(a, result) < self.rank(a, baseline) {
                    output.push(format!("IMPROVE {label} {} {} {} result={}", i + 1,
                        self.agents[truth[i]].name, self.agents[truth[i + 1]].name, self.partner_name(result)));
                }
            }
        }
        if output.len() == 1 { output.push("NO IMPROVEMENT".into()); }
        output
    }

    fn stats(&self) -> Response {
        let (source, matching) = self.current.as_ref().ok_or("NO MATCHING")?;
        let mut sums = [0; 2];
        let mut first = [0; 2];
        let mut pairs = 0;
        let mut occupied = vec![false; self.agents.len()];
        for (p, &partner) in matching.iter().enumerate() {
            if let Some(r) = partner {
                pairs += 1;
                occupied[r] = true;
                let ranks = [self.rank(p, Some(r)), self.rank(r, Some(p))];
                for i in 0..2 { sums[i] += ranks[i]; first[i] += usize::from(ranks[i] == 1); }
            }
        }
        let unmatched = [self.proposers - pairs, occupied[self.proposers..].iter().filter(|&&value| !value).count()];
        let mut output = vec![format!("STATS {} source={} pairs={pairs}", self.name, source.name())];
        for (i, label) in ["PROPOSERS", "RECEIVERS"].iter().enumerate() {
            let (average, truncated) = if pairs == 0 { ("-".into(), "-".into()) } else {
                let divisor = gcd(sums[i], pairs);
                let cents = 100 * sums[i] / pairs;
                (format!("{}/{}", sums[i] / divisor, pairs / divisor), format!("{}.{:02}", cents / 100, cents % 100))
            };
            output.push(format!("{label} sum={} average={average} truncated={truncated} first={} unmatched={}", sums[i], first[i], unmatched[i]));
        }
        Ok(output)
    }

    fn show(&self) -> Vec<String> {
        let mut output = vec![match self.kind {
            Kind::TwoSided => format!("SHOW {} MARKET proposers={} receivers={}", self.name, self.proposers, self.agents.len() - self.proposers),
            Kind::Roommate => format!("SHOW {} ROOMS agents={}", self.name, self.agents.len()),
            Kind::Housing => format!("SHOW {} HOUSES agents={}", self.name, self.agents.len()),
        }];
        for (a, agent) in self.agents.iter().enumerate() {
            let preference = list_text(agent.preference.iter().map(|&b| if self.kind == Kind::Housing { self.houses[b].clone() } else { self.agents[b].name.clone() }));
            let prefix = match self.kind {
                Kind::TwoSided if a < self.proposers => format!("PROPOSER {}", agent.name),
                Kind::TwoSided => format!("RECEIVER {} cap={}", agent.name, agent.capacity),
                Kind::Roommate => format!("AGENT {}", agent.name),
                Kind::Housing => format!("AGENT {} house={}", agent.name, self.houses[a]),
            };
            output.push(format!("{prefix} {preference}"));
        }
        if self.kind == Kind::TwoSided { output.push(format!("CURRENT {}", self.current.as_ref().map_or("-", |(source, _)| source.name()))); }
        output
    }
}

fn remove_pair(lists: &mut [Vec<usize>], a: usize, b: usize) {
    lists[a].retain(|&x| x != b);
    lists[b].retain(|&x| x != a);
}

fn gcd(mut a: usize, mut b: usize) -> usize {
    while b != 0 { (a, b) = (b, a % b); }
    a
}

fn new_market(words: &[&str]) -> Result<(Market, String), String> {
    let op = words[0];
    let name = words[1];
    let kind = match op { "ROOMS" => Kind::Roommate, "HOUSES" => Kind::Housing, _ => Kind::TwoSided };
    let mut market = Market { name: name.into(), kind, agents: Vec::new(), houses: Vec::new(), proposers: 0, current: None };
    let output;
    if op == "RANDOM" {
        let n: usize = words[2].parse().unwrap();
        let seed: i64 = words[3].parse().unwrap();
        let mut state = seed;
        market.proposers = n;
        for a in 0..2 * n {
            let mut agent = Agent::new(&format!("{}{}", if a < n { 'P' } else { 'R' }, a % n + 1));
            agent.preference = if a < n { (n..2 * n).collect() } else { (0..n).collect() };
            for i in (2..=n).rev() {
                state = 48271 * state % 2147483647;
                agent.preference.swap(i - 1, (state % i as i64) as usize);
            }
            market.agents.push(agent);
        }
        output = format!("RANDOM {name} n={n} seed={seed}");
    } else {
        for word in &words[2..] {
            if *word == "|" { market.proposers = market.agents.len(); continue; }
            let (agent, house) = if kind == Kind::Housing {
                let (a, h) = word.split_once(':').unwrap();
                (a, Some(h))
            } else { (*word, None) };
            if market.agents.iter().any(|a| a.name == agent) { return Err(format!("DUPLICATE AGENT {agent}")); }
            if let Some(h) = house {
                if market.houses.iter().any(|old| old == h) { return Err(format!("DUPLICATE HOUSE {h}")); }
                market.houses.push(h.into());
            }
            market.agents.push(Agent::new(agent));
        }
        output = if kind == Kind::TwoSided {
            format!("MARKET {name} proposers={} receivers={}", market.proposers, market.agents.len() - market.proposers)
        } else { format!("{op} {name} agents={}", market.agents.len()) };
    }
    Ok((market, output))
}

fn execute(markets: &mut HashMap<String, Market>, words: &[&str]) -> Response {
    let op = words[0];
    let name = words[1];
    if matches!(op, "MARKET" | "ROOMS" | "HOUSES" | "RANDOM") {
        if markets.contains_key(name) { return Err(format!("DUPLICATE MARKET {name}")); }
        let (market, output) = new_market(words)?;
        markets.insert(name.into(), market);
        return Ok(vec![output]);
    }
    let market = markets.get_mut(name).ok_or_else(|| format!("UNKNOWN MARKET {name}"))?;
    match op {
        "SHOW" => Ok(market.show()),
        "PREF" => {
            let a = market.agent(words[2], None)?;
            let mut preference = Vec::new();
            for word in &words[3..] {
                let choice = if market.kind == Kind::Housing { market.houses.iter().position(|h| h.as_str() == *word) }
                    else { market.agents.iter().position(|agent| agent.name == *word) };
                let b = choice.ok_or_else(|| format!("BAD CHOICE {word}"))?;
                if (market.kind == Kind::TwoSided && (a < market.proposers) == (b < market.proposers))
                    || (market.kind == Kind::Roommate && a == b) { return Err(format!("BAD CHOICE {word}")); }
                if preference.contains(&b) { return Err(format!("DUPLICATE CHOICE {word}")); }
                preference.push(b);
            }
            let length = preference.len();
            market.agents[a].preference = preference;
            if market.kind == Kind::TwoSided { market.current = None; }
            Ok(vec![format!("PREF {name} {} length={length}", words[2])])
        }
        "CHECK" => market.check(words),
        "ROOMMATES" => market.roommates(words.len() == 3),
        "TTC" | "SERIAL" => {
            market.require(Kind::Housing)?;
            if op == "TTC" { Ok(market.ttc()) } else { market.serial(words) }
        }
        _ => {
            market.require(Kind::TwoSided)?;
            match op {
                "CAPACITY" => {
                    let r = market.agent(words[2], Some(Side::Receiver))?;
                    let capacity = words[3].parse().unwrap();
                    market.agents[r].capacity = capacity;
                    market.current = None;
                    Ok(vec![format!("CAPACITY {name} {} {capacity}", words[2])])
                }
                "GS" | "GSR" | "BOSTON" => {
                    let source = match op { "GS" => Source::Gs, "GSR" => Source::Gsr, _ => Source::Boston };
                    let result = if op == "BOSTON" { market.boston() } else { market.deferred(op == "GSR", words.len() == 3) };
                    let mut output = vec![format!("{op} {name} {}={}", if op == "BOSTON" { "applications" } else { "proposals" }, result.proposals)];
                    output.extend(result.history);
                    output.push(format!("MATCHING {}", market.pairs(&result.matching)));
                    market.current = Some((source, result.matching));
                    Ok(output)
                }
                "HR" => Ok(market.hr()),
                "MANIPULATE" => {
                    let a = market.agent(words[2], Some(Side::Proposer))?;
                    Ok(market.manipulate(a))
                }
                "STATS" => market.stats(),
                "LATTICE" | "EGALITARIAN" | "MINREGRET" => {
                    let lattice = market.enumerate()?;
                    if op == "LATTICE" {
                        let mut output = vec![format!("LATTICE {name} matchings={} rotations={}", lattice.matchings.len(), lattice.rotations.len())];
                        for (i, candidate) in lattice.matchings.iter().enumerate() {
                            let origin = candidate.origin.map_or_else(|| "-".into(), |n| n.to_string());
                            let via = candidate.via.map_or_else(|| "-".into(), |n| n.to_string());
                            output.push(format!("MATCHING {} from={origin} via={via} cost={} regret={} {}", i + 1,
                                candidate.cost, candidate.regret, market.pairs(&candidate.matching)));
                        }
                        for (i, rotation) in lattice.rotations.iter().enumerate() {
                            let notation = rotation.pairs.iter().map(|&(p, r)| format!("{}-{}", market.agents[p].name, market.agents[r].name))
                                .collect::<Vec<_>>().join(" ");
                            output.push(format!("ROTATION {} {notation}", i + 1));
                        }
                        Ok(output)
                    } else {
                        let egalitarian = op == "EGALITARIAN";
                        let (index, candidate) = lattice.matchings.iter().enumerate()
                            .min_by_key(|(_, c)| if egalitarian { c.cost } else { c.regret }).unwrap();
                        let value = if egalitarian { candidate.cost } else { candidate.regret };
                        let output = vec![format!("{op} {name} matching={} {}={value}", index + 1, if egalitarian { "cost" } else { "regret" }),
                            format!("MATCHING {}", market.pairs(&candidate.matching))];
                        market.current = Some((if egalitarian { Source::Egalitarian } else { Source::MinRegret }, candidate.matching.clone()));
                        Ok(output)
                    }
                }
                _ => unreachable!(),
            }
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut markets = HashMap::new();
    let mut output = String::new();
    for line in lines.take(count) {
        let words: Vec<_> = line.split(' ').collect();
        match execute(&mut markets, &words) {
            Ok(response) => for text in response { output.push_str(&text); output.push('\n'); },
            Err(error) => { output.push_str("ERROR "); output.push_str(&error); output.push('\n'); }
        }
    }
    io::stdout().lock().write_all(output.as_bytes()).unwrap();
}
