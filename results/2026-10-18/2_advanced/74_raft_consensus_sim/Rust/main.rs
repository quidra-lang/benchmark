mod minstd;
mod network;
mod raft_node;
mod cluster;
mod checker;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use raft_node::{Entry,Node,Transfer,ROLES};
use cluster::{Control,Request,Settings};
use network::{Message,Payload,TYPES};
fn node_name(node: usize) -> String {
    format!("n{}",node+1)
}
fn node_option(node: Option<usize>) -> String {
    node.map_or_else(|| "-".to_owned(),node_name)
}
fn node_set(nodes: &BTreeSet<usize>) -> String {
    if nodes.is_empty() {
        "-".to_owned()
    } else {
        nodes.iter().map(|&i| node_name(i)).collect::<Vec<_>>().join(",")
    }
}
struct Election {
    time: usize,
    node: usize,
    term: usize,
    trigger: &'static str,
    votes: usize,
    won: Option<usize>
}
struct Leader {
    node: usize,
    time: usize,
    votes: BTreeSet<usize>,
    end: Option<(usize,&'static str,usize)>,
    appended: usize
}
struct Simulation {
    settings: Settings,
    controls: Vec<(usize,Control)>,
    requests: Vec<Request>,
    nodes: Vec<Node>,
    network: network::Network,
    random: minstd::Generator,
    checker: checker::Checker,
    time: usize,
    trace: Vec<String>,
    elections: Vec<Election>,
    leaders: BTreeMap<usize,Leader>,
    timeline: Vec<String>,
    gaps: Vec<(usize,usize)>,
    gap_start: Option<usize>,
    leader_ticks: usize,
    multi_ticks: usize
}
impl Simulation {
    fn new() -> Self {
        let input = cluster::read();
        let n = input.settings.nodes;
        let seed = input.settings.seed;
        Self {
            settings: input.settings,
            controls: input.controls,
            requests: input.requests,
            nodes: (0..n).map(|_| Node::new(n)).collect(),
            network: network::Network::read(n),
            random: minstd::Generator::new(seed),
            checker: checker::Checker::new(),
            time: 0,
            trace: Vec::new(),
            elections: Vec::new(),
            leaders: BTreeMap::new(),
            timeline: Vec::new(),
            gaps: Vec::new(),
            gap_start: None,
            leader_ticks: 0,
            multi_ticks: 0
        }
    }
    fn trace(&mut self, line: String) {
        self.trace.push(format!("{} {}",self.time,line));
    }
    fn timer(&mut self, i: usize) {
        let delay = self.random.range(self.settings.minimum,self.settings.maximum);
        self.nodes[i].deadline = Some(self.time+delay);
    }
    fn send(&mut self, source: usize, destination: usize, payload: Payload) {
        self.network.send(self.time,Message {
            source,
            destination,
            term: self.nodes[source].term,
            payload
        });
    }
    fn append(&mut self, source: usize, destination: usize) {
        let node = &self.nodes[source];
        let previous = node.next[destination]-1;
        let last = (previous+self.settings.batch).min(node.length());
        let payload = Payload::Append {
            previous,
            previous_term: node.term_at(previous),
            entries: node.log[previous..last].to_vec(),
            commit: node.commit
        };
        self.send(source,destination,payload);
    }
    fn timeout_now(&mut self, source: usize, target: usize) {
        self.trace(format!("TIMEOUTNOW n{} n{} term {} index {}",source+1,target+1,self.nodes[source].term,self.nodes[source].length()));
        self.nodes[source].transfer.as_mut().unwrap().sent = true;
        self.send(source,target,Payload::TimeoutNow);
    }
    fn end_leadership(&mut self, i: usize, reason: &'static str) {
        let term = self.nodes[i].term;
        let commit = self.nodes[i].commit;
        if let Some(leader) = self.leaders.get_mut(&term) {
            leader.end = Some((self.time,reason,commit));
        }
        self.nodes[i].transfer = None;
    }
    fn election(&mut self, i: usize, trigger: &'static str) {
        let node = &mut self.nodes[i];
        node.term += 1;
        node.role = 1;
        node.voted = Some(i);
        node.votes.clear();
        node.votes.insert(i);
        node.known = None;
        node.stats[0] += 1;
        self.timer(i);
        let node = &self.nodes[i];
        let (term,index,last,deadline) = (node.term,node.length(),node.last_term(),node.deadline.unwrap());
        self.nodes[i].election = Some(self.elections.len());
        self.elections.push(Election {
            time: self.time,
            node: i,
            term,
            trigger,
            votes: 1,
            won: None
        });
        self.trace(format!("ELECTION n{} term {} last {}/{} deadline {}",i+1,term,index,last,deadline));
        for j in 0..self.nodes.len() {
            if i != j {
                self.send(i,j,Payload::Vote(index,last));
            }
        }
    }
    fn leader(&mut self, i: usize) {
        let n = self.nodes.len();
        let node = &mut self.nodes[i];
        node.role = 2;
        node.known = Some(i);
        let next = node.length()+1;
        for j in 0..n {
            if j != i {
                node.next[j] = next;
                node.matched[j] = 0;
            }
        }
        node.log.push(Entry {
            term: node.term,
            command: "NOOP".to_owned(),
            request: 0
        });
        node.stats[1] += 1;
        let election = node.election.unwrap();
        self.elections[election].won = Some(self.time);
        self.checker.leader(i,self.nodes[i].term,&self.nodes[i].log);
        let term = self.nodes[i].term;
        let votes = self.nodes[i].votes.clone();
        self.leaders.insert(term,Leader {
            node: i,
            time: self.time,
            votes: votes.clone(),
            end: None,
            appended: 1
        });
        self.trace(format!("LEADER n{} term {} votes {} noop {}",i+1,term,node_set(&votes),self.nodes[i].length()));
        for j in 0..n {
            if i != j {
                self.append(i,j);
            }
        }
        self.nodes[i].heartbeat = Some(self.time+self.settings.heartbeat);
        self.nodes[i].quorum = Some(self.time+self.settings.quorum);
        self.nodes[i].heard.clear();
    }
    fn advance(&mut self, i: usize, commit: usize) {
        let old = self.nodes[i].commit;
        if commit <= old {
            return;
        }
        for index in old+1..=commit {
            self.checker.commit(index,self.nodes[i].term_at(index),self.time);
        }
        self.nodes[i].commit = commit;
        let first = self.nodes[i].applied+1;
        for index in first..=commit {
            let entry = self.nodes[i].log[index-1].clone();
            let result = raft_node::apply(&mut self.nodes[i].store,&entry.command);
            self.nodes[i].stats[8] += 1;
            self.checker.apply(index,&entry,result);
        }
        self.nodes[i].applied = commit;
        self.trace(format!("APPLY n{} {}-{}",i+1,first,commit));
    }
    fn commit_check(&mut self, i: usize) {
        for index in (self.nodes[i].commit+1..=self.nodes[i].length()).rev() {
            if self.nodes[i].term_at(index) != self.nodes[i].term {
                break;
            }
            let count = 1+(0..self.nodes.len()).filter(|&j| j != i && self.nodes[i].matched[j] >= index).count();
            if 2*count > self.nodes.len() {
                self.trace(format!("COMMIT n{} {}-{} term {}",i+1,self.nodes[i].commit+1,index,self.nodes[i].term));
                self.advance(i,index);
                break;
            }
        }
    }
    fn receive(&mut self, message: Message) {
        let (i,source) = (message.destination,message.source);
        let kind = message.kind();
        if message.term > self.nodes[i].term {
            let role = self.nodes[i].role;
            self.trace(format!("TERM n{} {}->{} {} n{} {}",i+1,self.nodes[i].term,message.term,TYPES[kind],source+1,ROLES[role]));
            if role == 2 {
                self.end_leadership(i,"STEPDOWN");
            }
            self.nodes[i].term = message.term;
            self.nodes[i].voted = None;
            self.nodes[i].known = None;
            self.nodes[i].role = 0;
            if role == 2 {
                self.timer(i);
            }
        }
        match message.payload {
            Payload::Vote(index,term) => {
                let reason = if message.term < self.nodes[i].term {
                    Some("term")
                } else if self.nodes[i].voted.map_or(false,|v| v != source) {
                    Some("voted")
                } else if !self.nodes[i].up_to_date(index,term) {
                    Some("log")
                } else {
                    None
                };
                if let Some(reason) = reason {
                    self.trace(format!("DENY n{} n{} term {} {}",i+1,source+1,self.nodes[i].term,reason));
                } else {
                    self.nodes[i].voted = Some(source);
                    self.nodes[i].stats[2] += 1;
                    self.timer(i);
                    self.trace(format!("VOTE n{} n{} term {} deadline {}",i+1,source+1,self.nodes[i].term,self.nodes[i].deadline.unwrap()));
                }
                self.send(i,source,Payload::VoteResponse(reason.is_none()));
            }
            Payload::VoteResponse(granted) => {
                if self.nodes[i].role == 1 && message.term == self.nodes[i].term && granted {
                    self.nodes[i].votes.insert(source);
                    self.elections[self.nodes[i].election.unwrap()].votes = self.nodes[i].votes.len();
                    if 2*self.nodes[i].votes.len() > self.nodes.len() {
                        self.leader(i);
                    }
                }
            }
            Payload::Append {
                previous,previous_term,entries,commit
            }
            => {
                if message.term < self.nodes[i].term {
                    self.send(i,source,Payload::AppendResponse(false,0));
                    return;
                }
                if self.nodes[i].role == 1 {
                    self.nodes[i].role = 0;
                    self.trace(format!("YIELD n{} term {} n{}",i+1,self.nodes[i].term,source+1));
                }
                self.nodes[i].known = Some(source);
                self.timer(i);
                if previous > self.nodes[i].length() || self.nodes[i].term_at(previous) != previous_term {
                    self.nodes[i].stats[5] += 1;
                    let hint = if previous > self.nodes[i].length() {
                        self.nodes[i].length()
                    } else {
                        previous-1
                    };
                    self.send(i,source,Payload::AppendResponse(false,hint));
                    return;
                }
                self.nodes[i].stats[4] += 1;
                let confirmed = previous+entries.len();
                for (offset,entry) in entries.into_iter().enumerate() {
                    let index = previous+offset+1;
                    if index <= self.nodes[i].length() && self.nodes[i].term_at(index) != entry.term {
                        let removed = self.nodes[i].log[index-1..].to_vec();
                        self.checker.truncate(index,&removed);
                        self.nodes[i].stats[7] += removed.len();
                        self.nodes[i].log.truncate(index-1);
                        self.trace(format!("TRUNCATE n{} from {} removed {}",i+1,index,removed.len()));
                    }
                    if index > self.nodes[i].length() {
                        self.nodes[i].log.push(entry);
                        self.nodes[i].stats[6] += 1;
                    }
                }
                self.advance(i,commit.min(confirmed));
                self.send(i,source,Payload::AppendResponse(true,confirmed));
            }
            Payload::AppendResponse(success,m) => {
                if self.nodes[i].role != 2 || message.term != self.nodes[i].term {
                    return;
                }
                self.nodes[i].heard.insert(source);
                if success {
                    self.nodes[i].matched[source] = self.nodes[i].matched[source].max(m);
                    self.nodes[i].next[source] = self.nodes[i].next[source].max(m+1);
                    self.commit_check(i);
                    let transfer = self.nodes[i].transfer.as_ref().map_or(false,|t| t.target == source && !t.sent && self.nodes[i].matched[source] == self.nodes[i].length());
                    if transfer {
                        self.timeout_now(i,source);
                    } else if self.nodes[i].next[source] <= self.nodes[i].length() {
                        self.append(i,source);
                    }
                } else {
                    self.nodes[i].next[source] = (self.nodes[i].matched[source]+1).max((self.nodes[i].next[source]-1).min(m+1));
                    self.trace(format!("BACKTRACK n{} n{} next {}",i+1,source+1,self.nodes[i].next[source]));
                    self.append(i,source);
                }
            }
            Payload::TimeoutNow => {
                if message.term != self.nodes[i].term || self.nodes[i].role != 0 {
                    self.trace(format!("IGNORE n{} TN n{} term {}",i+1,source+1,message.term));
                } else {
                    self.election(i,"transfer");
                }
            }
        }
    }
    fn control(&mut self, control: Control) {
        match control {
            Control::Crash(i) => {
                self.trace(format!("CRASH n{} {} term {}",i+1,ROLES[self.nodes[i].role],self.nodes[i].term));
                if self.nodes[i].role == 2 {
                    self.end_leadership(i,"CRASH");
                }
                self.nodes[i].up = false;
                self.nodes[i].reset();
            }
            Control::Restart(i) => {
                self.nodes[i].up = true;
                self.timer(i);
                self.trace(format!("RESTART n{} term {} length {} deadline {}",i+1,self.nodes[i].term,self.nodes[i].length(),self.nodes[i].deadline.unwrap()));
            }
            Control::Partition(groups) => {
                self.network.partition(&groups);
                let description = groups.iter().map(|g| node_set(&g.iter().copied().collect())).collect::<Vec<_>>().join(" ");
                self.trace(format!("PARTITION {}",description));
            }
            Control::Heal => {
                self.network.heal();
                self.trace("HEAL".to_owned());
            }
            Control::Transfer(i,target) => {
                if !self.nodes[i].up || self.nodes[i].role != 2 || self.nodes[i].transfer.is_some() || i == target {
                    self.trace(format!("TRANSFER n{} n{} ignored",i+1,target+1));
                } else {
                    self.trace(format!("TRANSFER n{} n{} start match {}/{}",i+1,target+1,self.nodes[i].matched[target],self.nodes[i].length()));
                    self.nodes[i].transfer = Some(Transfer {
                        target,
                        sent: false,
                        deadline: self.time+self.settings.minimum
                    });
                    if self.nodes[i].matched[target] == self.nodes[i].length() {
                        self.timeout_now(i,target);
                    } else {
                        self.append(i,target);
                    }
                }
            }
        }
    }
    fn attempt(&mut self, q: usize) {
        self.requests[q].attempts += 1;
        let mut i = self.requests[q].destination;
        let mut redirects = 0;
        let reason;
        loop {
            if !self.nodes[i].up {
                reason = "down";
                break;
            }
            if self.nodes[i].role == 2 {
                if self.nodes[i].transfer.is_some() {
                    reason = "transfer";
                    break;
                }
                let term = self.nodes[i].term;
                let entry = Entry {
                    term,
                    command: self.requests[q].command.clone(),
                    request: q+1
                };
                self.nodes[i].log.push(entry);
                let index = self.nodes[i].length();
                self.leaders.get_mut(&term).unwrap().appended += 1;
                self.requests[q].accepted = Some((index,term));
                self.trace(format!("ACCEPT r{} n{} index {} term {}",q+1,i+1,index,term));
                return;
            }
            if self.nodes[i].known.is_none() || redirects == self.nodes.len()-1 {
                reason = "noleader";
                break;
            }
            let next = self.nodes[i].known.unwrap();
            self.trace(format!("REDIRECT r{} n{} n{}",q+1,i+1,next+1));
            redirects += 1;
            self.requests[q].redirects += 1;
            i = next;
        }
        if self.requests[q].attempts < self.settings.attempts {
            self.requests[q].destination = (i+1)%self.nodes.len();
            self.requests[q].scheduled = self.time+self.settings.retry;
            self.trace(format!("REJECT r{} n{} {} retry n{} at {}",q+1,i+1,reason,self.requests[q].destination+1,self.requests[q].scheduled));
        } else {
            self.requests[q].abandoned = true;
            self.trace(format!("REJECT r{} n{} {} giveup",q+1,i+1,reason));
        }
    }
    fn timers(&mut self) {
        for i in 0..self.nodes.len() {
            if !self.nodes[i].up {
                continue;
            }
            if self.nodes[i].role == 2 {
                if self.nodes[i].quorum == Some(self.time) {
                    if 2*(1+self.nodes[i].heard.len()) <= self.nodes.len() {
                        self.trace(format!("STEPDOWN n{} term {} heard {}",i+1,self.nodes[i].term,node_set(&self.nodes[i].heard)));
                        self.end_leadership(i,"QUORUM");
                        self.nodes[i].role = 0;
                        self.nodes[i].known = None;
                        self.timer(i);
                        continue;
                    }
                    self.nodes[i].heard.clear();
                    self.nodes[i].quorum = Some(self.time+self.settings.quorum);
                }
                if self.nodes[i].transfer.as_ref().map_or(false,|t| t.deadline == self.time) {
                    let target = self.nodes[i].transfer.as_ref().unwrap().target;
                    self.trace(format!("TRANSFER n{} n{} abort",i+1,target+1));
                    self.nodes[i].transfer = None;
                }
                if self.nodes[i].heartbeat == Some(self.time) {
                    for j in 0..self.nodes.len() {
                        if j != i {
                            self.append(i,j);
                        }
                    }
                    self.nodes[i].heartbeat = Some(self.time+self.settings.heartbeat);
                }
            } else if self.nodes[i].deadline == Some(self.time) {
                self.election(i,"timeout");
            }
        }
    }
    fn end_tick(&mut self) {
        self.checker.matching(&self.nodes);
        let mut leaders = 0;
        for node in &mut self.nodes {
            if node.up && node.role == 2 {
                node.stats[3] += 1;
                leaders += 1;
            }
        }
        if leaders == 0 {
            if self.gap_start.is_none() {
                self.gap_start = Some(self.time);
            }
        } else {
            self.leader_ticks += 1;
            if leaders > 1 {
                self.multi_ticks += 1;
            }
            if let Some(start) = self.gap_start.take() {
                self.gaps.push((start,self.time-1));
            }
        }
        if self.time%self.settings.sample == 0 {
            self.timeline.push(format!("TIMELINE {} {}",self.time,self.nodes.iter().map(|n| format!("{}{}",if !n.up {
                'D'
            } else {
                ROLES[n.role].as_bytes()[0] as char
            },n.term)).collect::<Vec<_>>().join(" ")));
        }
    }
    fn run(&mut self) {
        for i in 0..self.nodes.len() {
            self.timer(i);
            self.trace(format!("START n{} deadline {}",i+1,self.nodes[i].deadline.unwrap()));
        }
        for time in 0..=self.settings.end {
            self.time = time;
            let controls: Vec<_> = self.controls.iter().filter(|(t,_)| *t == time).map(|(_,c)| c.clone()).collect();
            for control in controls {
                self.control(control);
            }
            for q in 0..self.requests.len() {
                if self.requests[q].accepted.is_none() && !self.requests[q].abandoned && self.requests[q].scheduled == time {
                    self.attempt(q);
                }
            }
            for message in self.network.arriving(time) {
                if self.network.deliver(&message,self.nodes[message.destination].up) {
                    self.receive(message);
                }
            }
            self.timers();
            self.end_tick();
        }
        if let Some(start) = self.gap_start.take() {
            self.gaps.push((start,self.settings.end));
        }
    }
    fn terms(&self) -> usize {
        self.nodes.iter().map(|n| n.term).max().unwrap()
    }
    fn leader_report(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for e in &self.elections {
            lines.push(format!("ELECTION {} n{} term {} trigger {} votes {} {}",e.time,e.node+1,e.term,e.trigger,e.votes,e.won.map_or_else(|| "LOST".to_owned(),|time| format!("WON {}",time))));
        }
        for term in 1..=self.terms() {
            let elections: Vec<_> = self.elections.iter().filter(|e| e.term == term).collect();
            let candidates = node_set(&elections.iter().map(|e| e.node).collect());
            if let Some(leader) = self.leaders.get(&term) {
                let (end,reason,commit) = leader.end.map_or_else(|| ("-".to_owned(),"ACTIVE",self.nodes[leader.node].commit),|(t,r,c)| (t.to_string(),r,c));
                let start = elections[0].time;
                lines.push(format!("TERM {} LEADER n{} elected {} votes {} ended {} {} appended {} commit {} candidates {} started {} wait {}",term,leader.node+1,leader.time,node_set(&leader.votes),end,reason,leader.appended,commit,candidates,start,leader.time-start));
            } else {
                lines.push(format!("TERM {} NONE candidates {}",term,candidates));
            }
        }
        for (i,node) in self.nodes.iter().enumerate() {
            lines.push(format!("NODE n{} elections {} leader_terms {} leader_ticks {} votes_granted {}",i+1,node.stats[0],node.stats[1],node.stats[3],node.stats[2]));
        }
        lines.extend(self.timeline.clone());
        for &(first,last) in &self.gaps {
            lines.push(format!("GAP {}-{} length {}",first,last,last-first+1));
        }
        lines.push(format!("SUMMARY terms {} leaders {} elections {} leader_ticks {} multi_ticks {} ticks {} gaps {} longest {}",self.terms(),self.leaders.len(),self.elections.len(),self.leader_ticks,self.multi_ticks,self.settings.end+1,self.gaps.len(),self.gaps.iter().map(|&(a,b)| b-a+1).max().unwrap_or(0)));
        lines
    }
    fn log_report(&self) -> Vec<String> {
        let mut lines = Vec::new();
        let committed = self.checker.committed.len();
        for (i,node) in self.nodes.iter().enumerate() {
            lines.push(format!("NODE n{} {} term {} voted {} commit {} applied {} length {}",i+1,if node.up {
                ROLES[node.role]
            } else {
                "DOWN"
            },node.term,node_option(node.voted),node.commit,node.applied,node.length()));
            for (index,entry) in node.log.iter().enumerate() {
                lines.push(format!("{} {} {}{}",index+1,entry.term,entry.command,if entry.request == 0 {
                    String::new()
                } else {
                    format!(" r{}",entry.request)
                }));
            }
        }
        let limit = self.nodes.iter().map(Node::length).min().unwrap();
        let prefix = (0..limit).take_while(|&i| self.nodes.iter().all(|n| n.log[i] == self.nodes[0].log[i])).count();
        lines.push(format!("AGREE prefix {} committed {}",prefix,committed));
        for (i,node) in self.nodes.iter().enumerate() {
            let common = (1..=node.length().min(committed)).take_while(|&index| node.term_at(index) == self.checker.committed[&index].0).count();
            lines.push(format!("DIFF n{} common {} behind {} extra {} ae_ok {} ae_fail {} appended {} truncated {} applies {}",i+1,common,committed-common,node.length()-common,node.stats[4],node.stats[5],node.stats[6],node.stats[7],node.stats[8]));
        }
        lines
    }
    fn state_report(&self) -> Vec<String> {
        let mut reference = vec![BTreeMap::new()];
        for (entry,_) in self.checker.applied.values() {
            let mut state = reference.last().unwrap().clone();
            raft_node::apply(&mut state,&entry.command);
            reference.push(state);
        }
        let mut lines = Vec::new();
        for (i,node) in self.nodes.iter().enumerate() {
            lines.push(format!("NODE n{} {} applied {} keys {} replay {}",i+1,if node.up {
                "UP"
            } else {
                "DOWN"
            },node.applied,node.store.len(),if node.store == reference[node.applied] {
                "match"
            } else {
                "mismatch"
            }));
            for (key,value) in &node.store {
                lines.push(format!("{} {}",key,value));
            }
        }
        let mut counts = [0usize;5];
        let mut keys = BTreeMap::<String,(usize,usize)>::new();
        let mut latencies = Vec::new();
        for (q,request) in self.requests.iter().enumerate() {
            let key = request.command.split_whitespace().nth(1).unwrap().to_owned();
            let entry = keys.entry(key).or_insert((0,0));
            entry.0 += 1;
            let status;
            let field = if let Some((index,term)) = request.accepted {
                if self.checker.committed.get(&index).map_or(false,|&(t,_)| t == term) {
                    status = 0;
                    entry.1 += 1;
                    let latency = self.checker.committed[&index].1-request.at;
                    latencies.push(latency);
                    format!("COMMITTED index {} term {} latency {} result {}",index,term,latency,self.checker.applied[&index].1)
                } else if self.nodes.iter().any(|n| n.length() >= index && n.term_at(index) == term) {
                    status = 1;
                    format!("UNCOMMITTED index {} term {}",index,term)
                } else {
                    status = 2;
                    format!("LOST index {} term {}",index,term)
                }
            } else if request.abandoned {
                status = 3;
                "FAILED".to_owned()
            } else {
                status = 4;
                format!("WAITING next {}",request.scheduled)
            };
            counts[status] += 1;
            lines.push(format!("REQUEST r{} at {} n{} {} attempts {} redirects {} {}",q+1,request.at,request.original+1,request.command,request.attempts,request.redirects,field));
        }
        for (key,(requests,committed)) in keys {
            let value = reference.last().unwrap().get(&key).map_or_else(|| "missing".to_owned(),i64::to_string);
            lines.push(format!("KEY {} requests {} committed {} final {}",key,requests,committed,value));
        }
        lines.push(format!("REQUESTS total {} committed {} uncommitted {} lost {} failed {} waiting {}",self.requests.len(),counts[0],counts[1],counts[2],counts[3],counts[4]));
        lines.push(format!("LATENCY count {} total {} min {} max {}",latencies.len(),latencies.iter().sum::<usize>(),latencies.iter().min().unwrap_or(&0),latencies.iter().max().unwrap_or(&0)));
        lines
    }
    fn safety_report(&self) -> Vec<String> {
        let mut lines = self.checker.lines(self.terms(),self.settings.end+1,self.nodes.len());
        let inflight = self.network.inflight();
        let mut total = [0usize;6];
        for statistics in &self.network.by_type {
            for i in 0..6 {
                total[i] += statistics[i];
            }
        }
        lines.push(format!("MESSAGES sent {} delivered {} inflight {} partition {} rule {} loss {} down {}",total[0],total[1],inflight.iter().sum::<usize>(),total[2],total[3],total[4],total[5]));
        for i in 0..5 {
            let s = self.network.by_type[i];
            lines.push(format!("TYPE {} sent {} delivered {} inflight {} partition {} rule {} loss {} down {}",TYPES[i],s[0],s[1],inflight[i],s[2],s[3],s[4],s[5]));
        }
        for a in 0..self.nodes.len() {
            for b in 0..self.nodes.len() {
                if a == b {
                    continue;
                }
                let s = self.network.by_link[a][b];
                lines.push(format!("LINK n{}->n{} delay {} loss {} sent {} delivered {} dropped {}",a+1,b+1,self.network.delays[a][b],self.network.losses[a][b],s[0],s[1],s[2..].iter().sum::<usize>()));
            }
        }
        lines.push(format!("DRAWS {}",self.random.draws));
        lines.push(format!("RESULT {}",if self.checker.violations.iter().all(|&n| n == 0) {
            "SAFE"
        } else {
            "UNSAFE"
        }));
        lines
    }
    fn write(&self) {
        fs::create_dir_all("output").unwrap();
        let outputs = [("trace.txt",self.trace.clone()),("leaders.txt",self.leader_report()),("logs.txt",self.log_report()),("state.txt",self.state_report()),("safety.txt",self.safety_report())];
        for (name,lines) in outputs {
            fs::write(format!("output/{}",name),lines.join("\n")+"\n").unwrap();
        }
    }
}
fn main() {
    let mut simulation = Simulation::new();
    simulation.run();
    simulation.write();
}
