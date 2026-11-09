use std::io::{self, Read};

fn ip(word: &str) -> Result<u32, String> {
    let fields: Vec<_> = word.split('.').collect();
    if fields.len() != 4 { return Err(format!("bad address {word}")); }
    let mut address = 0;
    for field in fields {
        if field.is_empty() || field.len() > 3 || (field.len() > 1 && field.starts_with('0')) || !field.bytes().all(|c| c.is_ascii_digit()) {
            return Err(format!("bad address {word}"));
        }
        let n: u32 = field.parse().unwrap();
        if n > 255 { return Err(format!("bad address {word}")); }
        address = address * 256 + n;
    }
    Ok(address)
}
fn address(a: u32) -> String { format!("{}.{}.{}.{}", a>>24, (a>>16)&255, (a>>8)&255, a&255) }
fn mask(length: u32) -> u32 { if length == 0 { 0 } else { u32::MAX << (32-length) } }
#[derive(Clone, Copy, PartialEq, Eq)]
struct Prefix { network: u32, length: u32 }
impl Prefix {
    fn contains(self, a: u32) -> bool { a & mask(self.length) == self.network & mask(self.length) }
    fn notation(self) -> String { format!("{}/{}", address(self.network), self.length) }
    fn acl_notation(self) -> String { if self.length == 0 { "any".into() } else { self.notation() } }
}
fn prefix(word: &str, host_bits: bool) -> Result<Prefix, String> {
    let fields: Vec<_> = word.split('/').collect();
    let bad = || format!("bad prefix {word}");
    if fields.len() != 2 { return Err(bad()); }
    let network = ip(fields[0]).map_err(|_| bad())?;
    let s = fields[1];
    if s.is_empty() || s.len() > 2 || (s.len() == 2 && s.starts_with('0')) || !s.bytes().all(|c| c.is_ascii_digit()) { return Err(bad()); }
    let length: u32 = s.parse().unwrap();
    if length > 32 { return Err(bad()); }
    if host_bits && network & !mask(length) != 0 { return Err(format!("host bits set in {word}")); }
    Ok(Prefix { network, length })
}
#[derive(Clone)]
struct Ports { low: i64, high: i64, any: bool }
impl Ports {
    fn notation(&self) -> String { if self.any { "any".into() } else if self.low == self.high { self.low.to_string() } else { format!("{}-{}", self.low, self.high) } }
    fn contains(&self, port: i64) -> bool { self.low <= port && port <= self.high }
}
fn ports(word: &str) -> Result<Ports, String> {
    if word == "ANY" { return Ok(Ports { low: 0, high: 65535, any: true }); }
    let values: Vec<i64> = word.split('-').map(|s| s.parse().unwrap()).collect();
    let low = values[0];
    let high = *values.last().unwrap();
    if high > 65535 || low > 65535 || low > high { return Err(format!("bad port range {word}")); }
    Ok(Ports { low, high, any: false })
}
struct Interface {
    name: String, address: u32, length: u32, up: bool, outside: bool,
    pool: Option<i64>, rpf: String, rx: i64, tx: i64, drop: i64,
}
struct Route { kind: char, dest: Prefix, iface: usize, hop: Option<u32>, metric: i64, hits: i64 }
struct Rule {
    iface: usize, dir: usize, seq: i64, action: String, proto: String,
    src: Prefix, sports: Ports, dst: Prefix, dports: Ports, established: bool, hits: i64,
}
struct Forward { iface: usize, proto: String, port: i64, inside: u32, inport: i64 }
struct Pat { iface: usize, proto: String, inside: u32, inport: i64, port: i64, used: i64 }
#[derive(Clone, PartialEq, Eq)]
struct Tuple { proto: String, src: u32, sport: i64, dst: u32, dport: i64 }
impl Tuple { fn notation(&self) -> String { format!("{}:{} > {}:{}", address(self.src), self.sport, address(self.dst), self.dport) } }
struct Connection {
    number: i64, orig: Tuple, reply: Tuple, input: usize, output: usize,
    state: String, packets: [i64;2], used: i64, fin: [bool;2],
}
const REASONS: [&str;9] = ["down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted"];
struct Router {
    ifaces: Vec<Interface>, routes: Vec<Route>, rules: Vec<Rule>, defaults: Vec<[i64;2]>,
    statics: Vec<(u32,u32)>, forwards: Vec<Forward>, pats: Vec<Pat>, conns: Vec<Connection>,
    timeouts: [i64;3], clock: i64, packet_number: i64, connection_number: i64,
    forwarded: i64, local: i64, drops: [i64;9], errors: i64,
}
fn protocol(p: &str) -> usize { match p { "TCP" => 0, "UDP" => 1, _ => 2 } }
impl Router {
    fn new() -> Self {
        Self { ifaces: Vec::new(), routes: Vec::new(), rules: Vec::new(), defaults: Vec::new(), statics: Vec::new(), forwards: Vec::new(), pats: Vec::new(), conns: Vec::new(), timeouts: [300,60,30], clock: 0, packet_number: 0, connection_number: 0, forwarded: 0, local: 0, drops: [0;9], errors: 0 }
    }
    fn iface(&self, name: &str) -> Result<usize,String> { self.ifaces.iter().position(|i| i.name == name).ok_or_else(|| format!("no interface {name}")) }
    fn local_address(&self, a: u32) -> Option<usize> { self.ifaces.iter().position(|i| i.address == a) }
    fn select(&self, a: u32) -> Option<usize> {
        let mut selected = None;
        for (i,r) in self.routes.iter().enumerate() {
            if !self.ifaces[r.iface].up || !r.dest.contains(a) { continue; }
            if selected.is_none_or(|j: usize| r.dest.length > self.routes[j].dest.length || (r.dest.length == self.routes[j].dest.length && r.metric < self.routes[j].metric)) { selected = Some(i); }
        }
        selected
    }
    fn route_text(&self, r: &Route) -> String {
        format!("{} {}{} dev {} metric {}", r.kind, r.dest.notation(), r.hop.map_or(String::new(), |h| format!(" via {}",address(h))), self.ifaces[r.iface].name, r.metric)
    }
    fn acl(&mut self, iface: usize, dir: usize, tuple: &Tuple, existing: bool) -> Option<String> {
        let mut indices: Vec<_> = self.rules.iter().enumerate().filter(|(_,r)| r.iface==iface && r.dir==dir).map(|(i,_)| i).collect();
        if indices.is_empty() { return None; }
        indices.sort_by_key(|&i| self.rules[i].seq);
        let name = &self.ifaces[iface].name;
        let d = if dir == 0 { "in" } else { "out" };
        for i in indices {
            let r = &mut self.rules[i];
            if (r.proto != "ANY" && r.proto != tuple.proto) || !r.src.contains(tuple.src) || !r.dst.contains(tuple.dst) || (r.established && !existing) { continue; }
            if (r.proto == "TCP" || r.proto == "UDP") && (!r.sports.contains(tuple.sport) || !r.dports.contains(tuple.dport)) { continue; }
            r.hits += 1;
            return match r.action.as_str() {
                "PERMIT" => None,
                "DENY" => Some(format!("DROP acl {name} {d} {}", r.seq)),
                _ => Some(format!("REJECT acl {name} {d} {} {}", r.seq, if tuple.proto == "TCP" { "tcp-reset" } else { "icmp-prohibited" })),
            };
        }
        self.defaults[iface][dir] += 1;
        Some(format!("DROP acl {name} {d} default"))
    }
    fn packet(&mut self, input: usize, flags: &str, original: Tuple, ttl: i64) -> (String, i32) {
        if !self.ifaces[input].up { return ("DROP down".into(),0); }
        let martian = |a: u32| a>>24 == 0 || a>>24 == 127 || a >= 0xe0000000;
        if martian(original.src) || martian(original.dst) || self.local_address(original.src).is_some() { return ("DROP martian".into(),1); }
        if self.ifaces[input].rpf != "off" {
            let route = self.select(original.src);
            if route.is_none() || (self.ifaces[input].rpf == "strict" && self.routes[route.unwrap()].iface != input) { return ("DROP rpf".into(),2); }
        }
        let pure_syn = original.proto == "TCP" && flags == "S";
        let mut found = self.conns.iter().enumerate().find_map(|(i,c)| if c.orig == original { Some((i,0)) } else if c.reply == original { Some((i,1)) } else { None });
        if let Some((i,_)) = found {
            if self.conns[i].state == "CLOSED" && pure_syn { self.conns.remove(i); found = None; }
        }
        if original.proto == "TCP" && found.is_none() && !pure_syn { return ("DROP invalid".into(),3); }
        if let Some(verdict) = self.acl(input,0,&original,found.is_some()) { return (verdict,4); }
        let (mut dst, mut dport) = (original.dst,original.dport);
        let mut used = None;
        if self.ifaces[input].outside {
            if let Some(&(inside,_)) = self.statics.iter().find(|(_,outside)| *outside == dst) { dst = inside; }
            else if dst == self.ifaces[input].address {
                if let Some(f) = self.forwards.iter().find(|f| f.iface==input && f.proto==original.proto && f.port==dport) { dst=f.inside; dport=f.inport; }
                else if let Some((i,p)) = self.pats.iter().enumerate().find(|(_,p)| p.iface==input && p.proto==original.proto && p.port==dport) { dst=p.inside; dport=p.inport; used=Some(i); }
            }
        }
        if let Some(i) = self.local_address(dst) { return (format!("LOCAL {}",self.ifaces[i].name),-2); }
        if ttl == 1 { return ("DROP ttl".into(),5); }
        let Some(route) = self.select(dst) else { return ("DROP noroute".into(),6); };
        let output = self.routes[route].iface;
        let outgoing = Tuple { dst, dport, ..original.clone() };
        if let Some(verdict) = self.acl(output,1,&outgoing,found.is_some()) { return (verdict,7); }
        let (mut src, mut sport) = (original.src,original.sport);
        if !self.ifaces[input].outside && self.ifaces[output].outside {
            if let Some(&(_,outside)) = self.statics.iter().find(|(inside,_)| *inside == src) { src=outside; }
            else if let Some(f) = self.forwards.iter().find(|f| f.iface==output && f.proto==original.proto && f.inside==src && f.inport==sport) { src=self.ifaces[output].address; sport=f.port; }
            else if let Some(count) = self.ifaces[output].pool {
                let mapping = self.pats.iter().position(|p| p.iface==output && p.proto==original.proto && p.inside==src && p.inport==sport);
                let index = if let Some(i) = mapping { i } else {
                    let port = (20000..20000+count).find(|&p| !self.pats.iter().any(|m| m.iface==output && m.port==p) && !self.forwards.iter().any(|f| f.iface==output && f.port==p));
                    let Some(port) = port else { return ("DROP exhausted".into(),8); };
                    self.pats.push(Pat { iface: output, proto: original.proto.clone(), inside: src, inport: sport, port, used: self.clock });
                    self.pats.len()-1
                };
                used=Some(index); src=self.ifaces[output].address; sport=self.pats[index].port;
            }
        }
        if let Some(i) = used { self.pats[i].used=self.clock; }
        let (connection,side,direction) = if let Some((i,side)) = found { (i,side,if side==0 { "orig" } else { "reply" }) } else {
            self.connection_number += 1;
            self.conns.push(Connection { number: self.connection_number, orig: original.clone(), reply: Tuple { proto: original.proto.clone(), src: dst, sport: dport, dst: src, dport: sport }, input, output, state: if original.proto=="TCP" { "SYN_SENT".into() } else { "UNREPLIED".into() }, packets: [0;2], used: self.clock, fin: [false;2] });
            (self.conns.len()-1,0,"new")
        };
        let c = &mut self.conns[connection];
        c.packets[side] += 1; c.used=self.clock;
        if original.proto != "TCP" { if side==1 { c.state="REPLIED".into(); } }
        else if flags.contains('R') { c.state="CLOSED".into(); }
        else {
            if c.state=="SYN_SENT" && side==1 && flags.contains('S') && flags.contains('A') { c.state="ESTABLISHED".into(); }
            if flags.contains('F') && (c.state=="ESTABLISHED" || c.state=="FIN_WAIT") { c.fin[side]=true; c.state=if c.fin[0] && c.fin[1] { "CLOSED".into() } else { "FIN_WAIT".into() }; }
        }
        let number = c.number;
        self.ifaces[output].tx += 1; self.routes[route].hits += 1;
        let hop = self.routes[route].hop.map_or("direct".into(),|a| format!("via {}",address(a)));
        let mut verdict = format!("FORWARD {} {hop} ttl={}",self.ifaces[output].name,ttl-1);
        if (dst,dport)!=(original.dst,original.dport) { verdict+=&format!(" dnat={}:{}",address(dst),dport); }
        if (src,sport)!=(original.src,original.sport) { verdict+=&format!(" snat={}:{}",address(src),sport); }
        verdict+=&format!(" conn={number} {direction}");
        (verdict,-1)
    }
    fn command(&mut self, words: &[&str]) -> Result<Vec<String>,String> {
        let w = words;
        let n = |i: usize| w[i].parse::<i64>().unwrap();
        let dir = |s: &str| if s=="IN" { 0 } else { 1 };
        let single = match w[0] {
            "IFACE" => {
                if self.ifaces.iter().any(|i| i.name==w[1]) { return Err(format!("duplicate interface {}",w[1])); }
                let p = prefix(w[2],false)?;
                if !(8..=30).contains(&p.length) { return Err(format!("bad prefix {}",w[2])); }
                let host = p.network & !mask(p.length);
                if host==0 || host==!mask(p.length) { return Err(format!("bad host address {}",w[2])); }
                if let Some(i) = self.ifaces.iter().find(|i| (i.address & mask(i.length.min(p.length))) == (p.network & mask(i.length.min(p.length)))) { return Err(format!("subnet overlaps {}",i.name)); }
                let index=self.ifaces.len();
                self.ifaces.push(Interface { name:w[1].into(),address:p.network,length:p.length,up:true,outside:false,pool:None,rpf:"off".into(),rx:0,tx:0,drop:0 });
                self.defaults.push([0;2]);
                let dest=Prefix { network:p.network & mask(p.length),length:p.length };
                self.routes.push(Route { kind:'C',dest,iface:index,hop:None,metric:0,hits:0 });
                format!("ok iface {} {} network {}",w[1],w[2],dest.notation())
            }
            "UP" | "DOWN" => {
                let i=self.iface(w[1])?; let up=w[0]=="UP";
                if self.ifaces[i].up==up { return Err(format!("interface {} already {}",w[1],w[0].to_ascii_lowercase())); }
                self.ifaces[i].up=up; format!("ok {} {}",w[0].to_ascii_lowercase(),w[1])
            }
            "ROUTE" => {
                let dest=prefix(w[1],true)?;
                let hop=if w[2]=="VIA" { Some(ip(w[3])?) } else { self.iface(w[3])?; None };
                if !(1..=255).contains(&n(4)) { return Err(format!("bad metric {}",w[4])); }
                let iface=if let Some(hop)=hop {
                    if self.local_address(hop).is_some() { return Err(format!("nexthop {} is local",w[3])); }
                    self.ifaces.iter().position(|i| Prefix { network:i.address,length:i.length }.contains(hop)).ok_or_else(|| format!("nexthop {} unreachable",w[3]))?
                } else { self.iface(w[3])? };
                if self.routes.iter().any(|r| r.kind=='S' && r.dest==dest && r.iface==iface && r.hop==hop) { return Err(format!("duplicate route {}",w[1])); }
                let route=Route { kind:'S',dest,iface,hop,metric:n(4),hits:0 };
                let text=self.route_text(&route); self.routes.push(route); format!("ok route {text}")
            }
            "NOROUTE" => {
                let dest=prefix(w[1],true)?; let old=self.routes.len();
                if !self.routes.iter().any(|r| r.kind=='S' && r.dest==dest) { return Err(format!("no static route {}",w[1])); }
                self.routes.retain(|r| r.kind!='S' || r.dest!=dest); format!("ok noroute {} removed={}",w[1],old-self.routes.len())
            }
            "LOOKUP" => { let a=ip(w[1])?; format!("lookup {} {}",w[1],self.select(a).map_or("none".into(),|i| self.route_text(&self.routes[i]))) }
            "ACL" => {
                let iface=self.iface(w[1])?; let d=dir(w[2]);
                if !(1..=9999).contains(&n(3)) { return Err(format!("bad sequence {}",w[3])); }
                let src=if w[6]=="ANY" { Prefix { network:0,length:0 } } else { prefix(w[6],true)? };
                let sports=ports(w[7])?;
                let dst=if w[8]=="ANY" { Prefix { network:0,length:0 } } else { prefix(w[8],true)? };
                let dports=ports(w[9])?;
                if (w[5]=="ICMP" || w[5]=="ANY") && (!sports.any || !dports.any) { return Err(format!("ports not allowed for {}",w[5])); }
                if self.rules.iter().any(|r| r.iface==iface && r.dir==d && r.seq==n(3)) { return Err(format!("duplicate sequence {}",w[3])); }
                self.rules.push(Rule { iface,dir:d,seq:n(3),action:w[4].into(),proto:w[5].into(),src,sports,dst,dports,established:w.len()==11,hits:0 });
                format!("ok acl {} {} {}",w[1],w[2].to_ascii_lowercase(),w[3])
            }
            "NOACL" => {
                let iface=self.iface(w[1])?; let d=dir(w[2]);
                let i=self.rules.iter().position(|r| r.iface==iface && r.dir==d && r.seq==n(3)).ok_or_else(|| format!("no rule {} on {} {}",w[3],w[1],w[2].to_ascii_lowercase()))?;
                let hits=self.rules.remove(i).hits; format!("ok noacl {} {} {} hits={hits}",w[1],w[2].to_ascii_lowercase(),w[3])
            }
            "NAT" => match w[1] {
                "STATIC" => {
                    let inside=ip(w[2])?; let outside=ip(w[3])?;
                    for (a,word) in [(inside,w[2]),(outside,w[3])] { if self.local_address(a).is_some() { return Err(format!("address {word} is local")); } }
                    if self.statics.iter().any(|(a,_)| *a==inside) { return Err(format!("duplicate static {}",w[2])); }
                    if self.statics.iter().any(|(_,a)| *a==outside) { return Err(format!("duplicate static {}",w[3])); }
                    self.statics.push((inside,outside)); format!("ok nat static {} {}",w[2],w[3])
                }
                "OUTSIDE" => {
                    let i=self.iface(w[2])?; if self.ifaces[i].outside { return Err(format!("interface {} already outside",w[2])); }
                    self.ifaces[i].outside=true; format!("ok nat outside {}",w[2])
                }
                "PAT" => {
                    let i=self.iface(w[2])?;
                    if !(1..=1000).contains(&n(3)) { return Err(format!("bad pool size {}",w[3])); }
                    if self.ifaces[i].pool.is_some() { return Err(format!("pat already on {}",w[2])); }
                    self.ifaces[i].pool=Some(n(3)); self.ifaces[i].outside=true;
                    format!("ok nat pat {} {} 20000-{}",w[2],address(self.ifaces[i].address),20000+n(3)-1)
                }
                _ => {
                    let i=self.iface(w[2])?;
                    if !(1..=65535).contains(&n(4)) { return Err(format!("bad port {}",w[4])); }
                    let inside=ip(w[5])?;
                    if !(1..=65535).contains(&n(6)) { return Err(format!("bad port {}",w[6])); }
                    if !self.ifaces[i].outside { return Err(format!("interface {} not outside",w[2])); }
                    if self.local_address(inside).is_some() { return Err(format!("address {} is local",w[5])); }
                    if self.forwards.iter().any(|f| f.iface==i && f.proto==w[3] && f.port==n(4)) { return Err(format!("duplicate forward {} {} {}",w[2],w[3],w[4])); }
                    self.forwards.push(Forward { iface:i,proto:w[3].into(),port:n(4),inside,inport:n(6) });
                    format!("ok nat forward {} {} {} {}:{}",w[2],w[3],w[4],w[5],w[6])
                }
            },
            "RPF" => { let i=self.iface(w[1])?; self.ifaces[i].rpf=w[2].to_ascii_lowercase(); format!("ok rpf {} {}",w[1],self.ifaces[i].rpf) }
            "TIMEOUT" => {
                if !(1..=86400).contains(&n(2)) { return Err(format!("bad timeout {}",w[2])); }
                self.timeouts[protocol(w[1])]=n(2); format!("ok timeout {} {}",w[1],w[2])
            }
            "TICK" => {
                if !(1..=86400).contains(&n(1)) { return Err(format!("bad tick {}",w[1])); }
                self.clock+=n(1); let old=self.conns.len(); let old_nat=self.pats.len();
                let clock = self.clock;
                let timeouts = self.timeouts;
                self.conns.retain(|c| { let timeout=if c.orig.proto=="TCP" { match c.state.as_str() { "SYN_SENT"|"FIN_WAIT"=>60,"CLOSED"=>10,_=>timeouts[0] } } else { timeouts[protocol(&c.orig.proto)] }; clock-c.used<timeout });
                self.pats.retain(|p| clock-p.used<timeouts[protocol(&p.proto)]);
                format!("ok tick time={} expired conns={} nat={}",self.clock,old-self.conns.len(),old_nat-self.pats.len())
            }
            "PACKET" => {
                let i=self.iface(w[1])?;
                if w[2]!="TCP" && w[3]!="-" { return Err(format!("flags not allowed for {}",w[2])); }
                if w[2]=="TCP" && w[3]!="-" && (w[3].chars().any(|c| !"SAFR".contains(c)) || w[3].chars().any(|c| w[3].matches(c).count()>1)) { return Err(format!("bad flags {}",w[3])); }
                let src=ip(w[4])?;
                if !(0..=65535).contains(&n(5)) { return Err(format!("bad port {}",w[5])); }
                let dst=ip(w[6])?;
                if !(0..=65535).contains(&n(7)) { return Err(format!("bad port {}",w[7])); }
                if !(1..=255).contains(&n(8)) { return Err(format!("bad ttl {}",w[8])); }
                self.packet_number+=1; self.ifaces[i].rx+=1;
                let (verdict,reason)=self.packet(i,w[3],Tuple { proto:w[2].into(),src,sport:n(5),dst,dport:n(7) },n(8));
                if reason==-1 { self.forwarded+=1; } else if reason==-2 { self.local+=1; } else { self.drops[reason as usize]+=1; self.ifaces[i].drop+=1; }
                format!("#{} {} {} {}:{} > {}:{} {verdict}",self.packet_number,w[2],w[3],w[4],w[5],w[6],w[7])
            }
            "SHOW" => return Ok(self.show(w[1])),
            "CLEAR" => if w[1]=="CONNS" {
                let text=format!("ok clear conns={} nat={}",self.conns.len(),self.pats.len()); self.conns.clear(); self.pats.clear(); text
            } else {
                self.forwarded=0; self.local=0; self.drops=[0;9]; self.errors=0;
                for i in &mut self.ifaces { i.rx=0; i.tx=0; i.drop=0; }
                for r in &mut self.routes { r.hits=0; } for r in &mut self.rules { r.hits=0; } self.defaults.fill([0;2]);
                "ok clear counters".into()
            },
            _ => unreachable!(),
        };
        Ok(vec![single])
    }
    fn show(&self, what: &str) -> Vec<String> {
        let mut lines=Vec::new();
        let mut names: Vec<_>=(0..self.ifaces.len()).collect(); names.sort_by_key(|&i| &self.ifaces[i].name);
        match what {
            "IFACES" => {
                lines.push(format!("show ifaces count={}",self.ifaces.len()));
                for i in names { let f=&self.ifaces[i]; let mut text=format!("{} {}/{} {} {} rpf={}",f.name,address(f.address),f.length,if f.up { "up" } else { "down" },if f.outside { "outside" } else { "inside" },f.rpf); if let Some(pool)=f.pool { text+=&format!(" pat={}/{pool}",self.pats.iter().filter(|p| p.iface==i).count()); } lines.push(text); }
            }
            "ROUTES" => {
                lines.push(format!("show routes count={}",self.routes.len()));
                let mut routes: Vec<_>=self.routes.iter().enumerate().collect(); routes.sort_by_key(|(i,r)| (r.dest.network,r.dest.length,r.metric,*i));
                for (_,r) in routes { lines.push(format!("{} hits={}{}",self.route_text(r),r.hits,if self.ifaces[r.iface].up { "" } else { " inactive" })); }
            }
            "ACL" => {
                lines.push(format!("show acl count={}",self.rules.len()));
                for i in names { for d in 0..2 {
                    let mut rules: Vec<_>=self.rules.iter().filter(|r| r.iface==i && r.dir==d).collect(); rules.sort_by_key(|r| r.seq); if rules.is_empty() { continue; }
                    let name=&self.ifaces[i].name; let dir=if d==0 { "in" } else { "out" };
                    for r in rules { lines.push(format!("acl {name} {dir} {} {} {} {} {} {} {}{} hits={}",r.seq,r.action,r.proto,r.src.acl_notation(),r.sports.notation(),r.dst.acl_notation(),r.dports.notation(),if r.established { " established" } else { "" },r.hits)); }
                    lines.push(format!("acl {name} {dir} default DENY hits={}",self.defaults[i][d]));
                } }
            }
            "NAT" => {
                lines.push(format!("show nat static={} forward={} pat={}",self.statics.len(),self.forwards.len(),self.pats.len()));
                let mut statics=self.statics.clone(); statics.sort_by_key(|p| p.0); for (a,b) in statics { lines.push(format!("static {} {}",address(a),address(b))); }
                let mut forwards: Vec<_>=self.forwards.iter().collect();
                forwards.sort_by(|a,b| self.ifaces[a.iface].name.cmp(&self.ifaces[b.iface].name).then(a.port.cmp(&b.port)).then(a.proto.cmp(&b.proto)));
                for f in forwards { lines.push(format!("forward {} {} {} {}:{}",self.ifaces[f.iface].name,f.proto,f.port,address(f.inside),f.inport)); }
                let mut pats: Vec<_>=self.pats.iter().collect();
                pats.sort_by(|a,b| self.ifaces[a.iface].name.cmp(&self.ifaces[b.iface].name).then(a.port.cmp(&b.port)));
                for p in pats { lines.push(format!("pat {} {} {} {}:{} idle={}",self.ifaces[p.iface].name,p.port,p.proto,address(p.inside),p.inport,self.clock-p.used)); }
            }
            "CONNS" => {
                lines.push(format!("show conns count={}",self.conns.len()));
                for c in &self.conns { lines.push(format!("conn {} {} {} reply {} in={} out={} state={} pkts={}/{} idle={}",c.number,c.orig.proto,c.orig.notation(),c.reply.notation(),self.ifaces[c.input].name,self.ifaces[c.output].name,c.state,c.packets[0],c.packets[1],self.clock-c.used)); }
            }
            _ => {
                let dropped:i64=self.drops.iter().sum();
                lines.push(format!("show counters packets={} forwarded={} local={} dropped={dropped} errors={}",self.forwarded+self.local+dropped,self.forwarded,self.local,self.errors));
                lines.push(format!("drops {}",REASONS.iter().zip(self.drops).map(|(r,n)| format!("{r}={n}")).collect::<Vec<_>>().join(" ")));
                for i in names { let f=&self.ifaces[i]; lines.push(format!("iface {} rx={} tx={} drop={}",f.name,f.rx,f.tx,f.drop)); }
            }
        }
        lines
    }
}
fn main() {
    let mut input=String::new(); io::stdin().read_to_string(&mut input).unwrap();
    let mut lines=input.lines(); let count:usize=lines.next().unwrap().parse().unwrap();
    let mut router=Router::new();
    for line in lines.take(count) {
        match router.command(&line.split(' ').collect::<Vec<_>>()) {
            Ok(output) => for line in output { println!("{line}"); },
            Err(reason) => { router.errors+=1; println!("error: {reason}"); }
        }
    }
}
