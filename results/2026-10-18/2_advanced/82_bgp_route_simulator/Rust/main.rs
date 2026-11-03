mod topology;
mod policy;
mod decision;
mod simulator;
mod report;
use std::collections::{BTreeMap,BTreeSet};
use topology::{Asn,Prefix,Topology};
use policy::{Policy,Action};
use decision::{Attribute,Route};
use simulator::{Queue,Params,Event,Message};
#[derive(Clone,Debug,Default)] struct Session {
    incoming:BTreeMap<Prefix,Attribute>,
    outgoing:BTreeMap<Prefix,Attribute>,
    pending:BTreeSet<Prefix>,
    timer:Option<i64>,
    sent:usize,
    received:usize
}
#[derive(Default)] struct Counters {
    convergence:i64,
    updates:usize,
    withdrawals:usize,
    drops:usize,
    changes:usize,
    exploration:BTreeMap<(Asn,Prefix),usize>
}
#[derive(Clone)] struct Forward {
    result:&'static str,
    visits:Vec<Asn>,
    hops:Vec<(Asn,Prefix,Option<usize>)>
}
struct TraceRecord {
    trace:usize,
    start:i64,
    end:Option<i64>,
    result:&'static str,
    visits:Vec<Asn>
}
struct RingRecord {
    prefix:Prefix,
    start:i64,
    end:Option<i64>,
    cycle:Vec<Asn>
}
struct Divergence {
    event:usize,
    first:i64,
    repeat:i64,
    lines:Vec<(i64,Asn,Prefix,Option<Route>)>
}
struct Bgp {
    topology:Topology,
    policy:Policy,
    params:Params,
    sessions:BTreeMap<(Asn,usize),Session>,
    origins:BTreeMap<Asn,BTreeMap<Prefix,Route>>,
    ribs:BTreeMap<Asn,BTreeMap<Prefix,Route>>,
    as_changes:BTreeMap<Asn,usize>,
    queue:Queue,
    time:i64,
    logs:Vec<String>,
    convergence:Vec<String>,
    counter:Counters,
    changed:BTreeSet<Prefix>,
    best_lines:Vec<(i64,Asn,Prefix,Option<Route>)>,
    trace_records:Vec<TraceRecord>,
    trace_active:Vec<Option<usize>>,
    ring_records:Vec<RingRecord>,
    ring_active:BTreeMap<(Prefix,Vec<Asn>),usize>,
    divergences:Vec<Divergence>
}
impl Bgp {
    fn new()->Self{
        let topology=Topology::read();
        let policy=Policy::read();
        let params=simulator::params();
        let mut sessions=BTreeMap::new();
        let(mut origins,mut ribs,mut as_changes)=(BTreeMap::new(),BTreeMap::new(),BTreeMap::new());
        for &x in topology.routers.keys(){
            origins.insert(x,BTreeMap::new());
            ribs.insert(x,BTreeMap::new());
            as_changes.insert(x,0);
            for l in topology.sessions(x){
                sessions.insert((x,l),Session::default());
            }
        }
        let trace_active=vec![None;params.traces.len()];
        Self{
            topology,
            policy,
            params,
            sessions,
            origins,
            ribs,
            as_changes,
            queue:Queue::new(),
            time:0,
            logs:Vec::new(),
            convergence:vec!["event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration".into()],
            counter:Counters::default(),
            changed:BTreeSet::new(),
            best_lines:Vec::new(),
            trace_records:Vec::new(),
            trace_active,
            ring_records:Vec::new(),
            ring_active:BTreeMap::new(),
            divergences:Vec::new()
        }
    }
    fn log(&mut self,text:String){
        self.logs.push(format!("{} {}",self.time,text));
    }
    fn import(&self,x:Asn,l:usize,p:Prefix,a:&Attribute)->(Option<Route>,Option<usize>){
        let rule=self.policy.applied(true,x,&self.topology.links[l],p,&a.path,&a.communities);
        let mut route=Route{
            attribute:a.clone(),
            local_pref:self.params.defaults[self.topology.links[l].role(x)],
            link:Some(l)
        };
        if let Some(id)=rule{
            for action in &self.policy.rules[id].actions{
                match action{
                    Action::Deny=>return(None,rule),Action::Local(n)=>route.local_pref=*n,Action::Med(n)=>route.attribute.med=*n,_=>()
                }
            }
            route.attribute.communities=self.policy.edit(id,&a.communities);
        }
        (Some(route),rule)
    }
    fn candidates(&self,x:Asn,p:Prefix)->Vec<Route>{
        self.topology.sessions(x).into_iter().filter_map(|l|self.sessions[&(x,l)].incoming.get(&p).and_then(|a|self.import(x,l,p,a).0)).collect()
    }
    fn decide(&mut self,x:Asn,p:Prefix){
        let new=if let Some(r)=self.origins[&x].get(&p){
            Some(r.clone())
        }else{
            let c=self.candidates(x,p);
            if c.is_empty(){
                None
            }else{
                Some(decision::best(&c,&self.topology).0)
            }
        };
        if self.ribs[&x].get(&p)==new.as_ref(){
            return;
        }
        if let Some(r)=&new{
            self.ribs.get_mut(&x).unwrap().insert(p,r.clone());
        }else{
            self.ribs.get_mut(&x).unwrap().remove(&p);
        }
        self.log(format!("BEST {} {} {}",x,p.text(),report::route(new.as_ref(),&self.topology)));
        self.counter.changes+=1;
        *self.counter.exploration.entry((x,p)).or_default()+=1;
        *self.as_changes.get_mut(&x).unwrap()+=1;
        self.changed.insert(p);
        self.best_lines.push((self.time,x,p,new));
        for l in self.topology.sessions(x){
            if self.topology.links[l].up{
                self.sessions.get_mut(&(x,l)).unwrap().pending.insert(p);
                if self.sessions[&(x,l)].timer.is_none(){
                    self.pending(x,l);
                }
            }
        }
    }
    fn advertised(&self,x:Asn,l:usize,p:Prefix)->(Option<Attribute>,Option<usize>){
        let r=match self.ribs[&x].get(&p){
            Some(r)=>r,None=>return(None,None)
        };
        let link=&self.topology.links[l];
        if r.link.is_some()&&r.neighbor()==link.other(x)||r.attribute.communities.contains(&(65535,65281)){
            return(None,None);
        }
        let rule=self.policy.applied(false,x,link,p,&r.attribute.path,&r.attribute.communities);
        let(mut allow,mut prepend,mut med)=(false,0,0);
        if let Some(id)=rule{
            for a in &self.policy.rules[id].actions{
                match a{
                    Action::Deny=>return(None,rule),Action::Allow=>allow=true,Action::Prepend(n)=>prepend=*n,Action::Med(n)=>med=*n,_=>()
                }
            }
        }
        if !allow&&r.link.map_or(false,|k|self.topology.links[k].role(x)!=0)&&link.role(x)!=0{
            return(None,rule);
        }
        let mut path=vec![x;1+prepend];
        path.extend(&r.attribute.path);
        let communities=rule.map_or_else(||r.attribute.communities.clone(),|id|self.policy.edit(id,&r.attribute.communities));
        (Some(Attribute{
            path,
            origin:r.attribute.origin.clone(),
            med,
            communities
        }),rule)
    }
    fn pending(&mut self,x:Asn,l:usize){
        let prefixes:Vec<_>=self.sessions[&(x,l)].pending.iter().copied().collect();
        let mut sent=false;
        for p in prefixes{
            let(content,rule)=self.advertised(x,l,p);
            if self.sessions[&(x,l)].outgoing.get(&p)==content.as_ref(){
                continue;
            }
            if let Some(a)=&content{
                self.sessions.get_mut(&(x,l)).unwrap().outgoing.insert(p,a.clone());
            }else{
                self.sessions.get_mut(&(x,l)).unwrap().outgoing.remove(&p);
            }
            let link=&self.topology.links[l];
            let message=self.queue.send(self.time,link.delay,x,link.other(x),l,p,content);
            let notation=message.content.as_ref().map_or_else(||"WITHDRAW".into(),|a|format!("ANNOUNCE {}",report::attribute(a)));
            self.log(format!("SEND #{} {}->{} {} {} {}",message.serial,x,message.receiver,self.topology.links[l].name,p.text(),notation));
            self.sessions.get_mut(&(x,l)).unwrap().sent+=1;
            self.counter.updates+=1;
            if message.content.is_none(){
                self.counter.withdrawals+=1;
            }
            if let Some(id)=rule{
                self.policy.rules[id].hits+=1;
            }
            sent=true;
        }
        let s=self.sessions.get_mut(&(x,l)).unwrap();
        s.pending.clear();
        s.timer=if sent&&self.topology.links[l].mrai>0{
            Some(self.time+self.topology.links[l].mrai)
        }else{
            None
        };
    }
    fn receive(&mut self,m:Message){
        let(x,l,p)=(m.receiver,m.link,m.prefix);
        self.sessions.get_mut(&(x,l)).unwrap().received+=1;
        let result=if let Some(a)=&m.content{
            if a.path.contains(&x){
                self.sessions.get_mut(&(x,l)).unwrap().incoming.remove(&p);
                "ANNOUNCE loop".into()
            }else{
                self.sessions.get_mut(&(x,l)).unwrap().incoming.insert(p,a.clone());
                let(accepted,rule)=self.import(x,l,p,a);
                if let Some(id)=rule{
                    self.policy.rules[id].hits+=1;
                    format!("ANNOUNCE {} {}",if accepted.is_some(){
                        "accept"
                    }else{
                        "deny"
                    },self.policy.rules[id].name)
                }else{
                    "ANNOUNCE accept".into()
                }
            }
        }else{
            self.sessions.get_mut(&(x,l)).unwrap().incoming.remove(&p);
            "WITHDRAW".into()
        };
        self.log(format!("RECV #{} {}->{} {} {} {}",m.serial,m.sender,x,self.topology.links[l].name,p.text(),result));
        self.decide(x,p);
    }
    fn execute(&mut self,number:usize,event:&Event){
        self.log(format!("EVENT {} {}",number,event.text));
        let a=&event.fields;
        match a[0].as_str(){
            "INITIAL"=>{
                for(x,p,o,c)in self.topology.initial.clone(){
                    self.origins.get_mut(&x).unwrap().insert(p,Route::local(o,c));
                    self.decide(x,p);
                }
            },"ANNOUNCE"=>{
                let x=a[1].parse().unwrap();
                let p=Prefix::parse(&a[2]);
                let c=a[4..].iter().map(|v|policy::community(v)).collect();
                self.origins.get_mut(&x).unwrap().insert(p,Route::local(a[3].clone(),c));
                self.decide(x,p);
            },"WITHDRAW"=>{
                let x=a[1].parse().unwrap();
                let p=Prefix::parse(&a[2]);
                self.origins.get_mut(&x).unwrap().remove(&p);
                self.decide(x,p);
            },"LINK"=>{
                let l=self.topology.links.iter().position(|l|l.name==a[2]).unwrap();
                let mut endpoints=vec![self.topology.links[l].a,self.topology.links[l].b];
                endpoints.sort();
                self.topology.links[l].up=a[1]=="UP";
                if a[1]=="DOWN"{
                    self.topology.links[l].downs+=1;
                    for m in self.queue.remove(l){
                        self.counter.drops+=1;
                        self.log(format!("DROP #{} {}->{} {} {}",m.serial,m.sender,m.receiver,self.topology.links[l].name,m.prefix.text()));
                    }
                    let mut remembered=Vec::new();
                    for &x in &endpoints{
                        let s=self.sessions.get_mut(&(x,l)).unwrap();
                        remembered.push((x,s.incoming.keys().copied().collect::<Vec<_>>()));
                        s.incoming.clear();
                        s.outgoing.clear();
                        s.pending.clear();
                        s.timer=None;
                    }
                    for(x,prefixes)in remembered{
                        for p in prefixes{
                            self.decide(x,p);
                        }
                    }
                }else{
                    for x in endpoints{
                        self.sessions.get_mut(&(x,l)).unwrap().pending=self.ribs[&x].keys().copied().collect();
                        self.pending(x,l);
                    }
                }
            },"POLICY"=>{
                let id=self.policy.rules.iter().position(|r|r.name==a[2]).unwrap();
                self.policy.rules[id].on=a[1]=="ON";
                let x=self.policy.rules[id].owner;
                if self.policy.rules[id].import{
                    let prefixes:BTreeSet<_>=self.topology.sessions(x).into_iter().flat_map(|l|self.sessions[&(x,l)].incoming.keys().copied()).collect();
                    for p in prefixes{
                        self.decide(x,p);
                    }
                }else{
                    for l in self.topology.sessions(x){
                        if self.topology.links[l].up{
                            let prefixes:BTreeSet<_>=self.ribs[&x].keys().chain(self.sessions[&(x,l)].outgoing.keys()).copied().collect();
                            self.sessions.get_mut(&(x,l)).unwrap().pending.extend(prefixes);
                            if self.sessions[&(x,l)].timer.is_none(){
                                self.pending(x,l);
                            }
                        }
                    }
                }
            },_=>unreachable!()
        }
    }
    fn forward(&self,source:Asn,address:u32)->Forward{
        let mut f=Forward{
            result:"UNREACHABLE",
            visits:vec![source],
            hops:Vec::new()
        };
        let mut x=source;
        loop{
            let selected=self.ribs[&x].iter().filter(|(p,_)|p.contains(address)).max_by_key(|(p,_)|p.length);
            let(&p,r)=match selected{
                Some(v)=>v,None=>{
                    f.result=if f.hops.is_empty(){
                        "UNREACHABLE"
                    }else{
                        "BLACKHOLE"
                    };
                    return f;
                }
            };
            f.hops.push((x,p,r.link));
            if let Some(l)=r.link{
                let y=self.topology.links[l].other(x);
                let repeat=f.visits.contains(&y);
                f.visits.push(y);
                if repeat{
                    f.result="LOOP";
                    return f;
                }
                x=y;
            }else{
                f.result="DELIVERED";
                return f;
            }
        }
    }
    fn rings(&self,p:Prefix)->BTreeSet<Vec<Asn>>{
        let graph:BTreeMap<_,_>=self.ribs.iter().filter_map(|(&x,r)|r.get(&p).and_then(|r|r.link.map(|l|(x,self.topology.links[l].other(x))))).collect();
        let mut rings=BTreeSet::new();
        for &start in graph.keys(){
            let mut path=Vec::new();
            let mut x=start;
            while let Some(&next)=graph.get(&x){
                if let Some(i)=path.iter().position(|&v|v==x){
                    let mut cycle=path[i..].to_vec();
                    let k=cycle.iter().enumerate().min_by_key(|(_,v)|**v).unwrap().0;
                    cycle.rotate_left(k);
                    rings.insert(cycle);
                    break;
                }
                path.push(x);
                x=next;
            }
        }
        rings
    }
    fn forwarding_check(&mut self){
        for p in self.changed.clone(){
            let rings=self.rings(p);
            let ended:Vec<_>=self.ring_active.keys().filter(|(q,c)|*q==p&&!rings.contains(c)).cloned().collect();
            for key in ended{
                let id=self.ring_active.remove(&key).unwrap();
                self.ring_records[id].end=Some(self.time);
            }
            for cycle in rings{
                let key=(p,cycle.clone());
                if !self.ring_active.contains_key(&key){
                    let id=self.ring_records.len();
                    self.ring_records.push(RingRecord{
                        prefix:p,
                        start:self.time,
                        end:None,
                        cycle
                    });
                    self.ring_active.insert(key,id);
                }
            }
        }
        for i in 0..self.params.traces.len(){
            let(s,_,a)=&self.params.traces[i];
            let f=self.forward(*s,*a);
            let bad=f.result=="LOOP"||f.result=="BLACKHOLE";
            if let Some(id)=self.trace_active[i]{
                let r=&self.trace_records[id];
                if !bad||r.result!=f.result||r.visits!=f.visits{
                    self.trace_records[id].end=Some(self.time);
                    self.trace_active[i]=None;
                }
            }
            if bad&&self.trace_active[i].is_none(){
                self.trace_active[i]=Some(self.trace_records.len());
                self.trace_records.push(TraceRecord{
                    trace:i,
                    start:self.time,
                    end:None,
                    result:f.result,
                    visits:f.visits
                });
            }
        }
    }
    fn state(&self)->String{
        let sessions:Vec<_>=self.sessions.values().map(|s|(&s.incoming,&s.outgoing,&s.pending,s.timer.map(|v|v-self.time))).collect();
        format!("{:?}|{:?}",sessions,self.queue.state(self.time))
    }
    fn quiet(&self)->bool{
        self.queue.messages.is_empty()&&self.sessions.values().all(|s|s.pending.is_empty())
    }
    fn run(&mut self,events:&[Event]){
        for(k,e)in events.iter().enumerate(){
            self.time=e.time;
            self.counter=Counters::default();
            self.best_lines.clear();
            self.changed.clear();
            let start=self.ribs.clone();
            let(mut deliveries,mut seen,mut divergent)=(0usize,BTreeMap::new(),None);
            self.execute(k,e);
            loop{
                let messages=self.queue.deliveries(self.time);
                let delivered=!messages.is_empty();
                if delivered{
                    self.counter.convergence=self.time-e.time;
                }
                for m in messages{
                    self.receive(m);
                }
                let expiring:Vec<_>=self.sessions.iter().filter(|(_,s)|s.timer==Some(self.time)).map(|(k,_)|*k).collect();
                for(x,l)in expiring{
                    self.sessions.get_mut(&(x,l)).unwrap().timer=None;
                    if !self.sessions[&(x,l)].pending.is_empty(){
                        self.pending(x,l);
                    }
                }
                if !self.changed.is_empty(){
                    self.forwarding_check();
                }
                if delivered{
                    deliveries+=1;
                    if divergent.is_none()&&deliveries<=self.params.stepcap{
                        let state=self.state();
                        if let Some(&first)=seen.get(&state){
                            divergent=Some((first,self.time));
                            let lines=self.best_lines.iter().filter(|v|first<v.0&&v.0<=self.time).cloned().collect();
                            self.divergences.push(Divergence{
                                event:k,
                                first,
                                repeat:self.time,
                                lines
                            });
                        }else{
                            seen.insert(state,self.time);
                        }
                    }
                }
                let last=k+1==events.len();
                if if last{
                    self.quiet()||divergent.is_some()||deliveries>=self.params.stepcap
                }else{
                    self.time==events[k+1].time-1
                }
                {
                    break;
                }
                self.time+=1;
                self.changed.clear();
            }
            let status=if divergent.is_some(){
                "DIVERGENT"
            }else if self.quiet(){
                "CONVERGED"
            }else if k+1==events.len(){
                "CAPPED"
            }else{
                "UNSETTLED"
            };
            let mut changed=0;
            for &x in self.topology.routers.keys(){
                let prefixes:BTreeSet<_>=start[&x].keys().chain(self.ribs[&x].keys()).copied().collect();
                changed+=prefixes.iter().filter(|p|start[&x].get(*p)!=self.ribs[&x].get(*p)).count();
            }
            let c=&self.counter;
            self.convergence.push(format!("{},{},{},{},{},{},{},{},{},{},{}",k,e.time,e.kind,status,c.convergence,c.updates,c.withdrawals,c.drops,c.changes,changed,c.exploration.values().max().copied().unwrap_or(0)));
        }
    }
    fn ribs_report(&self)->Vec<String>{
        let mut lines=Vec::new();
        for(&x,rib)in &self.ribs{
            let sessions=self.topology.sessions(x);
            let sent:usize=sessions.iter().map(|&l|self.sessions[&(x,l)].sent).sum();
            let received:usize=sessions.iter().map(|&l|self.sessions[&(x,l)].received).sum();
            lines.push(format!("AS {} routes {} local {} sent {} received {} changes {}",x,rib.len(),rib.values().filter(|r|r.link.is_none()).count(),sent,received,self.as_changes[&x]));
            for l in sessions{
                let s=&self.sessions[&(x,l)];
                let link=&self.topology.links[l];
                let accepted=s.incoming.iter().filter(|(&p,a)|self.import(x,l,p,a).0.is_some()).count();
                lines.push(format!("SESSION {} {} {} {} in {} accepted {} out {} sent {} received {} flaps {}",link.name,link.other(x),link.role_text(x),if link.up{
                    "UP"
                }else{
                    "DOWN"
                },s.incoming.len(),accepted,s.outgoing.len(),s.sent,s.received,link.downs));
            }
            for(&p,r)in rib{
                let mut c=self.candidates(x,p);
                let reason=if r.link.is_some(){
                    format!(" reason {}",decision::best(&c,&self.topology).1)
                }else{
                    String::new()
                };
                lines.push(format!("{} {} candidates {}{}",p.text(),report::route(Some(r),&self.topology),c.len(),reason));
                c.retain(|a|a!=r);
                while !c.is_empty(){
                    let(best,_)=decision::best(&c,&self.topology);
                    lines.push(format!("ALT {}",report::route(Some(&best),&self.topology)));
                    c.retain(|r|r!=&best);
                }
            }
        }
        lines
    }
    fn paths_report(&self)->Vec<String>{
        let mut lines=Vec::new();
        for(s,address,a)in &self.params.traces{
            let f=self.forward(*s,*a);
            let hops=f.hops.iter().filter(|h|h.2.is_some()).count();
            lines.push(format!("TRACE {} {} {} hops {}",s,address,f.result,hops));
            for &(x,p,l)in &f.hops{
                lines.push(if let Some(l)=l{
                    format!("HOP {} {} next {} link {}",x,p.text(),self.topology.links[l].other(x),self.topology.links[l].name)
                }else{
                    format!("HOP {} {} LOCAL",x,p.text())
                });
            }
            if f.result=="LOOP"{
                lines.push(format!("HOP {} REVISIT",f.visits.last().unwrap()));
            }else if f.result!="DELIVERED"{
                lines.push(format!("HOP {} NOROUTE",f.visits.last().unwrap()));
            }
            if let Some(&(_,p,_))=f.hops.first(){
                let r=&self.ribs[s][&p];
                let mut merged=r.attribute.path.clone();
                merged.dedup();
                let matched=f.result=="DELIVERED"&&merged==f.visits[1..];
                lines.push(format!("CONTROL {} {}",if r.link.is_none(){
                    "LOCAL".into()
                }else{
                    report::path(&r.attribute.path)
                },if matched{
                    "MATCH"
                }else{
                    "MISMATCH"
                }));
            }else{
                lines.push("CONTROL NONE".into());
            }
            if hops>0{
                let pattern:String=f.hops.iter().filter_map(|&(x,_,l)|l.map(|l|self.topology.links[l].symbol(x))).collect();
                lines.push(format!("PATTERN {} {}",pattern,if valley(&pattern)==pattern.len(){
                    "VALLEYFREE"
                }else{
                    "VALLEY"
                }));
            }
        }
        let prefixes:BTreeSet<_>=self.origins.values().flat_map(|r|r.keys().copied()).collect();
        lines.push(format!("PREFIXES {}",prefixes.iter().map(Prefix::text).collect::<Vec<_>>().join(",")));
        for &s in self.topology.routers.keys(){
            let symbols:String=prefixes.iter().map(|p|{
                let f=self.forward(s,p.address);
                match f.result{
                    "DELIVERED"=>if f.hops.iter().all(|h|h.2.is_none()){
                        '*'
                    }else if self.origins[f.visits.last().unwrap()].contains_key(p){
                        '+'
                    }else{
                        'X'
                    },"LOOP"=>'L',"BLACKHOLE"=>'B',_=>'U'
                }
            }).collect();
            lines.push(format!("REACH {} {}",s,symbols));
        }
        lines
    }
    fn audit_report(&self)->Vec<String>{
        let mut lines=Vec::new();
        let mut traces:Vec<_>=self.trace_records.iter().collect();
        traces.sort_by_key(|r|(r.start,r.trace));
        let mut loops=0;
        let mut blackholes=0;
        for r in traces{
            let(s,a,_)=&self.params.traces[r.trace];
            let end=r.end.map_or_else(||"END".into(),|v|v.to_string());
            if r.result=="LOOP"{
                loops+=1;
                lines.push(format!("LOOP {} {} from {} to {} path {}",s,a,r.start,end,report::path(&r.visits)));
            }else{
                blackholes+=1;
                lines.push(format!("BLACKHOLE {} {} from {} to {} at {} path {}",s,a,r.start,end,r.visits.last().unwrap(),report::path(&r.visits)));
            }
        }
        let mut rings:Vec<_>=self.ring_records.iter().collect();
        rings.sort_by_key(|r|(r.start,r.prefix,r.cycle[0]));
        for r in rings{
            lines.push(format!("RING {} from {} to {} path {}",r.prefix.text(),r.start,r.end.map_or_else(||"END".into(),|v|v.to_string()),report::path(&r.cycle)));
        }
        let(mut routes,mut valleys)=(0,0);
        for(&x,rib)in &self.ribs{
            for(p,r)in rib{
                if r.link.is_none(){
                    continue;
                }
                routes+=1;
                let mut h=vec![x];
                h.extend(&r.attribute.path);
                h.dedup();
                let pattern:String=h.windows(2).map(|w|self.topology.connecting(w[0],w[1]).symbol(w[0])).collect();
                let g=valley(&pattern);
                if g<pattern.len(){
                    valleys+=1;
                    lines.push(format!("VALLEY {} {} path {} pattern {} leaker {}",x,p.text(),report::path(&r.attribute.path),pattern,h[g]));
                }
            }
        }
        for r in &self.policy.rules{
            lines.push(format!("RULE {} {} {} hits {}",r.name,if r.import{
                "IMPORT"
            }else{
                "EXPORT"
            },if r.on{
                "ON"
            }else{
                "OFF"
            },r.hits));
        }
        for d in &self.divergences{
            lines.push(format!("DIVERGENT event {} first {} repeat {} period {}",d.event,d.first,d.repeat,d.repeat-d.first));
            let mut oscillate=BTreeMap::new();
            for(t,x,p,r)in &d.lines{
                lines.push(format!("CYCLE {} {} {} {}",t,x,p.text(),report::route(r.as_ref(),&self.topology)));
                *oscillate.entry((*x,*p)).or_insert(0usize)+=1;
            }
            for((x,p),n)in oscillate{
                lines.push(format!("OSCILLATE {} {} changes {}",x,p.text(),n));
            }
        }
        lines.push(format!("SUMMARY loops {} blackholes {} rings {} routes {} valleys {} divergent {} end {}",loops,blackholes,self.ring_records.len(),routes,valleys,self.divergences.len(),self.time));
        lines
    }
}
fn valley(pattern:&str)->usize{
    let a=pattern.as_bytes();
    let mut i=0;
    while i<a.len()&&a[i]==b'U'{
        i+=1;
    }
    if i<a.len()&&a[i]==b'P'{
        i+=1;
    }
    while i<a.len()&&a[i]==b'D'{
        i+=1;
    }
    i
}
fn main(){
    let events=simulator::events();
    let mut bgp=Bgp::new();
    bgp.run(&events);
    report::write("updates.txt",&bgp.logs);
    report::write("convergence.csv",&bgp.convergence);
    report::write("ribs.txt",&bgp.ribs_report());
    report::write("paths.txt",&bgp.paths_report());
    report::write("audit.txt",&bgp.audit_report());
}
