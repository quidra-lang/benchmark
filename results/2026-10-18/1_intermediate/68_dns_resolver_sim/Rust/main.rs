use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};
use std::convert::TryInto;
use std::io::{self, Read};
const TYPES: [&str; 8] = ["A","NS","CNAME","SOA","PTR","MX","TXT","AAAA"];
const KINDS: [&str; 7] = ["ANSWER","CNAME","REFERRAL","NODATA","NXDOMAIN","LAME","TIMEOUT"];
fn integer(s: &str) -> Option<i64> {
    if s.is_empty() || s.len()>9 || (s.len()>1 && s.starts_with('0')) || !s.bytes().all(|c|c.is_ascii_digit()) {
        None
    } else {
        s.parse().ok()
    }
}
fn ip(s: &str) -> Option<u32> {
    let fields:Vec<_>=s.split('.').collect();
    if fields.len()!=4 {
        return None;
    }
    let mut a=0;
    for p in fields {
        if p.len()>3 {
            return None;
        }
        let n=integer(p)?;
        if n>255 {
            return None;
        }
        a=a*256+n as u32;
    }
    Some(a)
}
fn address(a: u32) -> String {
    format!("{}.{}.{}.{}",a>>24,(a>>16)&255,(a>>8)&255,a&255)
}
fn ipv6(s: &str) -> Option<[u16; 8]> {
    fn groups(s: &str) -> Option<Vec<u16>> {
        if s.is_empty() {
            return Some(Vec::new());
        }
        s.split(':').map(|p| if (1..=4).contains(&p.len()) && p.bytes().all(|c|c.is_ascii_hexdigit()) {
            u16::from_str_radix(p,16).ok()
        } else {
            None
        }).collect()
    }
    let values=if let Some((a,b))=s.split_once("::") {
        let left=groups(a)?;
        let right=groups(b)?;
        if left.len()+right.len()>7 {
            return None;
        }
        let mut values=left;
        values.resize(8-right.len(),0);
        values.extend(right);
        values
    } else {
        let values=groups(s)?;
        if values.len()!=8 {
            return None;
        }
        values
    };
    values.try_into().ok()
}
fn address6(a: &[u16; 8]) -> String {
    let mut best=(0,0);
    let mut at=0;
    while at<8 {
        if a[at]!=0 {
            at+=1;
            continue;
        }
        let start=at;
        while at<8 && a[at]==0 {
            at+=1;
        }
        if at-start>=2 && at-start>best.1 {
            best=(start,at-start);
        }
    }
    let text=|part:&[u16]|part.iter().map(|n|format!("{n:x}")).collect::<Vec<_>>().join(":");
    if best.1==0 {
        text(a)
    } else {
        format!("{}::{}",text(&a[..best.0]),text(&a[best.0+best.1..]))
    }
}
fn name(word: &str, wild: bool, origin: Option<&str>) -> Result<String,String> {
    if word=="@" {
        if let Some(origin)=origin {
            return Ok(origin.into());
        }
    }
    if word=="." {
        return Ok(".".into());
    }
    let labels:Vec<_>=word.strip_suffix('.').unwrap_or(word).split('.').collect();
    for (i,label) in labels.iter().enumerate() {
        if wild && i==0 && *label=="*" {
            continue;
        }
        if label.is_empty() || label.len()>63 || label.starts_with('-') || label.ends_with('-') || !label.bytes().all(|c|c.is_ascii_alphanumeric() || c==b'-') {
            return Err(format!("bad name {word}"));
        }
    }
    let mut result=labels.join(".").to_ascii_lowercase()+".";
    if !word.ends_with('.') {
        if let Some(origin)=origin.filter(|&s|s!=".") {
            result+=origin;
        }
    }
    Ok(result)
}
fn labels(s: &str) -> Vec<&str> {
    if s=="." {
        Vec::new()
    } else {
        s[..s.len()-1].split('.').collect()
    }
}
fn name_order(a: &str,b: &str) -> Ordering {
    labels(a).into_iter().rev().cmp(labels(b).into_iter().rev())
}
fn below(a: &str,b: &str) -> bool {
    b=="." || a==b || a.ends_with(&(".".to_string()+b))
}
fn ancestors(s: &str) -> Vec<String> {
    let parts=labels(s);
    let mut out:Vec<_>=(0..parts.len()).map(|i|parts[i..].join(".")+".").collect();
    out.push(".".into());
    out
}
fn checked_ip(s: &str) -> Result<u32,String> {
    ip(s).ok_or_else(||format!("bad address {s}"))
}
fn checked_type(s: &str) -> Result<(),String> {
    if TYPES.contains(&s) {
        Ok(())
    } else {
        Err(format!("bad type {s}"))
    }
}
fn ttl(s: &str) -> Result<i64,String> {
    let parsed=integer(s).or_else(|| {
        let b=s.as_bytes();
        let mut at=0;
        let mut previous=None;
        let mut total=0;
        while at<b.len() {
            let start=at;
            while at<b.len() && b[at].is_ascii_digit() {
                at+=1;
            }
            if at==b.len() || at-start>3 {
                return None;
            }
            let n=integer(&s[start..at])?;
            let unit=b"wdhms".iter().position(|&c|c==b[at].to_ascii_lowercase())?;
            if previous.is_some_and(|p|unit<=p) {
                return None;
            }
            previous=Some(unit);
            total+=n*[604800,86400,3600,60,1][unit];
            at+=1;
        }
        previous.map(|_|total)
    });
    parsed.filter(|&n|(1..=604800).contains(&n)).ok_or_else(||format!("bad ttl {s}"))
}
#[derive(Clone,PartialEq,Eq)]
enum Data {
    A(u32), Aaaa([u16; 8]), Name(String), Mx(i64,String), Txt(String), Soa(String,String,[i64; 5])
}
impl Data {
    fn text(&self) -> String {
        match self {
            Self::A(a)=>address(*a),Self::Aaaa(a)=>address6(a),Self::Name(n)=>n.clone(),Self::Mx(p,n)=>format!("{p} {n}"),Self::Txt(s)=>s.clone(),Self::Soa(a,b,n)=>format!("{a} {b} {}",n.iter().map(i64::to_string).collect::<Vec<_>>().join(" "))
        }
    }
    fn compare(&self,b: &Self) -> Ordering {
        match (self,b) {
            (Self::A(a),Self::A(b))=>a.cmp(b),(Self::Aaaa(a),Self::Aaaa(b))=>a.cmp(b),(Self::Name(a),Self::Name(b))=>name_order(a,b),(Self::Mx(a,x),Self::Mx(b,y))=>a.cmp(b).then_with(||name_order(x,y)),(Self::Txt(a),Self::Txt(b))=>a.cmp(b),_=>Ordering::Equal
        }
    }
}
#[derive(Clone)]
struct Record {
    owner:String,ttl:i64,kind:String,data:Data
}
impl Record {
    fn text(&self) -> String {
        format!("{} {} {} {}",self.owner,self.ttl,self.kind,self.data.text())
    }
}
fn record_order(a: &Record,b: &Record) -> Ordering {
    name_order(&a.owner,&b.owner).then(TYPES.iter().position(|&t|t==a.kind).cmp(&TYPES.iter().position(|&t|t==b.kind))).then_with(||a.data.compare(&b.data))
}
struct Zone {
    origin:String,server:u32,line:usize,records:Vec<Record>
}
#[derive(Clone)]
struct Response {
    kind:usize,answer:Vec<Record>,authority:Vec<Record>,additional:Vec<Record>,cut:String
}
impl Response {
    fn empty(kind:usize) -> Self {
        Self {
            kind,answer:Vec::new(),authority:Vec::new(),additional:Vec::new(),cut:String::new()
        }
    }
    fn text(&self) -> String {
        match self.kind {
            1=>format!("CNAME {}",self.answer[0].data.text()),2=>format!("REFERRAL {}",self.cut),_=>KINDS[self.kind].into()
        }
    }
}
#[derive(Clone)]
struct Cache {
    kind:usize,records:Vec<Record>,expiry:i64
}
struct Resolver {
    roots:Vec<u32>,zones:Vec<Zone>,current:Option<usize>,down:BTreeSet<u32>,cache:BTreeMap<(String,String),Cache>,settings:[i64; 3],clock:i64,queries:BTreeMap<u32,[usize; 7]>,hits:usize,resolutions:[usize; 4],out:Vec<String>,
}
impl Resolver {
    fn new() -> Self {
        Self {
            roots:Vec::new(),zones:Vec::new(),current:None,down:BTreeSet::new(),cache:BTreeMap::new(),settings:[1,86400,3600],clock:0,queries:BTreeMap::new(),hits:0,resolutions:[0; 4],out:Vec::new()
        }
    }
    fn zone_line(&mut self,w: &[&str],line:usize) -> Result<(),String> {
        if w[0]=="ROOT" {
            let mut added=Vec::new();
            for word in &w[1..] {
                let a=checked_ip(word)?;
                if self.roots.contains(&a) || added.contains(&a) {
                    return Err(format!("duplicate root {word}"));
                }
                added.push(a);
            }
            self.roots.extend(added);
            return Ok(());
        }
        if w[0]=="ZONE" {
            self.current=None;
            let origin=name(w[1],false,None)?;
            let server=checked_ip(w[2])?;
            if self.zones.iter().any(|z|z.origin==origin && z.server==server) {
                return Err(format!("duplicate zone {origin} at {}",w[2]));
            }
            self.current=Some(self.zones.len());
            self.zones.push(Zone {
                origin,server,line,records:Vec::new()
            });
            return Ok(());
        }
        let i=self.current.ok_or("no current zone")?;
        let z=&self.zones[i];
        let origin=z.origin.as_str();
        let owner=name(w[0],true,Some(origin))?;
        if !below(&owner,origin) {
            return Err(format!("out of zone {owner}"));
        }
        let seconds=ttl(w[1])?;
        let kind=w[2];
        checked_type(kind)?;
        let fields=&w[3..];
        let expected=match kind {
            "MX"=>2,"SOA"=>7,"TXT"=>fields.len(),_=>1
        };
        if fields.len()!=expected {
            return Err("wrong field count".into());
        }
        let data=match kind {
            "A"=>Data::A(checked_ip(fields[0])?),"AAAA"=>Data::Aaaa(ipv6(fields[0]).ok_or_else(||format!("bad address {}",fields[0]))?),
            "NS"|"CNAME"|"PTR"=>Data::Name(name(fields[0],false,Some(origin))?),
            "MX"=>{
                let p=integer(fields[0]).filter(|&n|n<=65535).ok_or_else(||format!("bad preference {}",fields[0]))?;
                Data::Mx(p,name(fields[1],false,Some(origin))?)
            },
            "TXT"=>{
                let s=fields.join(" ");
                if s.len()<2 || !s.starts_with('"') || !s.ends_with('"') || s[1..s.len()-1].contains('"') {
                    return Err(format!("bad text {s}"));
                }
                Data::Txt(s)
            },
            _=>{
                let a=name(fields[0],false,Some(origin))?;
                let b=name(fields[1],false,Some(origin))?;
                let mut nums=[0; 5];
                for j in 0..4 {
                    nums[j]=integer(fields[j+2]).ok_or_else(||format!("bad number {}",fields[j+2]))?;
                }
                nums[4]=integer(fields[6]).filter(|&n|(1..=86400).contains(&n)).ok_or_else(||format!("bad minimum {}",fields[6]))?;
                Data::Soa(a,b,nums)
            },
        };
        if kind=="NS" && owner.starts_with("*.") {
            return Err("ns at wildcard".into());
        }
        if kind=="SOA" && owner!=origin {
            return Err("soa not at origin".into());
        }
        if kind=="SOA" && z.records.iter().any(|r|r.kind=="SOA") {
            return Err("duplicate soa".into());
        }
        if z.records.iter().any(|r|r.owner==owner && r.kind==kind && r.data==data) {
            return Err("duplicate record".into());
        }
        if z.records.iter().any(|r|r.owner==owner && (kind=="CNAME" || r.kind=="CNAME")) {
            return Err(format!("cname conflict {owner}"));
        }
        self.zones[i].records.push(Record {
            owner,ttl:seconds,kind:kind.into(),data
        });
        Ok(())
    }
    fn finish_zones(&mut self) {
        let zones=std::mem::take(&mut self.zones);
        for z in zones {
            if z.records.iter().any(|r|r.kind=="SOA") {
                self.out.push(format!("zone {} at {} records={}",z.origin,address(z.server),z.records.len()));
                self.zones.push(z);
            } else {
                self.out.push(format!("error line {}: zone {} at {} has no soa",z.line,z.origin,address(z.server)));
            }
        }
        self.out.push(format!("loaded roots={} zones={} records={}",self.roots.len(),self.zones.len(),self.zones.iter().map(|z|z.records.len()).sum::<usize>()));
    }
    fn records(z: &Zone,n: &str,t: &str) -> Vec<Record> {
        let mut r:Vec<_>=z.records.iter().filter(|r|r.owner==n && r.kind==t).cloned().collect();
        r.sort_by(|a,b|a.data.compare(&b.data));
        r
    }
    fn authoritative(&self,server:u32,n: &str,t: &str,cut: &str) -> Response {
        if self.down.contains(&server) || !self.zones.iter().any(|z|z.server==server) {
            return Response::empty(6);
        }
        let Some(z)=self.zones.iter().filter(|z|z.server==server && below(n,&z.origin)).max_by_key(|z|labels(&z.origin).len()) else {
            return Response::empty(5);
        };
        if labels(&z.origin).len()<labels(cut).len() {
            return Response::empty(5);
        }
        let mut ancestors=ancestors(n);
        ancestors.reverse();
        for d in ancestors.iter().filter(|d|d.as_str()!=z.origin && below(d,&z.origin)) {
            let ns=Self::records(z,d,"NS");
            if ns.is_empty() {
                continue;
            }
            let mut response=Response::empty(2);
            response.cut=d.clone();
            for r in &ns {
                if let Data::Name(host)=&r.data {
                    response.additional.extend(Self::records(z,host,"A"));
                }
            }
            response.authority=ns;
            return response;
        }
        let exists=|x:&str|z.records.iter().any(|r|below(&r.owner,x));
        let mut owner=n.to_string();
        if !z.records.iter().any(|r|r.owner==n) {
            if exists(n) {
                let mut r=Response::empty(3);
                r.authority=Self::records(z,&z.origin,"SOA");
                return r;
            }
            let ancestor=ancestors.iter().rev().find(|a|a.as_str()!=n && exists(a)).unwrap();
            owner=if ancestor=="." {
                "*.".into()
            } else {
                "*.".to_string()+ancestor
            };
            if !z.records.iter().any(|r|r.owner==owner) {
                let mut r=Response::empty(4);
                r.authority=Self::records(z,&z.origin,"SOA");
                return r;
            }
        }
        let mut answer=Self::records(z,&owner,t);
        let mut kind=0;
        if answer.is_empty() && t!="CNAME" {
            answer=Self::records(z,&owner,"CNAME");
            kind=1;
        }
        if answer.is_empty() {
            let mut r=Response::empty(3);
            r.authority=Self::records(z,&z.origin,"SOA");
            return r;
        }
        for r in &mut answer {
            r.owner=n.into();
        }
        let mut response=Response::empty(kind);
        response.answer=answer;
        response
    }
    fn ask(&mut self,a:u32,n:&str,t:&str,cut:&str) -> Response {
        let r=self.authoritative(a,n,t,cut);
        self.queries.entry(a).or_insert([0; 7])[r.kind]+=1;
        r
    }
    fn trace(&mut self,depth:usize,text:String) {
        self.out.push(" ".repeat(2*(depth+1))+&text);
    }
    fn positive(&mut self,records:Vec<Record>) -> i64 {
        let seconds=records.iter().map(|r|r.ttl).min().unwrap().max(self.settings[0]).min(self.settings[1]);
        let key=(records[0].owner.clone(),records[0].kind.clone());
        self.cache.insert(key,Cache {
            kind:0,records,expiry:self.clock+seconds
        });
        seconds
    }
    fn cached_records(&self,key:&(String,String)) -> Option<Vec<Record>> {
        let entry=self.cache.get(key).filter(|e|e.kind==0)?;
        Some(entry.records.iter().cloned().map(|mut r| {
            r.ttl=entry.expiry-self.clock;
            r
        }).collect())
    }
    fn query_servers(&mut self,n:&str,t:&str,cut:&str,servers:Option<Vec<String>>,depth:usize,stack:&mut Vec<(String,String)>) -> Option<Response> {
        if let Some(mut servers)=servers {
            servers.sort_by(|a,b|name_order(a,b));
            for host in servers {
                let records=if let Some(records)=self.cached_records(&(host.clone(),"A".into())) {
                    records
                }
                else if stack.contains(&(host.clone(),"A".into())) {
                    self.trace(depth,format!("GLUELESS {host} -> LOOP"));
                    Vec::new()
                }
                else {
                    self.trace(depth,format!("GLUELESS {host}"));
                    let (status,answer)=self.resolve(&host,"A",depth+1,stack);
                    if status=="NOERROR" {
                        answer
                    } else {
                        Vec::new()
                    }
                };
                let addresses:BTreeSet<_>=records.iter().filter_map(|r|if let Data::A(a)=r.data {
                    Some(a)
                } else {
                    None
                }).collect();
                for a in addresses {
                    let r=self.ask(a,n,t,cut);
                    self.trace(depth,format!("ASK {} {n} {t} -> {}",address(a),r.text()));
                    if r.kind<5 {
                        return Some(r);
                    }
                }
            }
        } else {
            for a in self.roots.clone() {
                let r=self.ask(a,n,t,cut);
                self.trace(depth,format!("ASK {} {n} {t} -> {}",address(a),r.text()));
                if r.kind<5 {
                    return Some(r);
                }
            }
        }
        None
    }
    fn lookup(&mut self,n:&str,t:&str,depth:usize,stack:&mut Vec<(String,String)>) -> Result<Response,String> {
        if let Some(entry)=self.cache.get(&(n.into(),t.into())).cloned() {
            let mut r=Response::empty(if entry.kind==0 {
                0
            } else {
                entry.kind
            });
            if entry.kind==0 {
                r.answer=self.cached_records(&(n.into(),t.into())).unwrap();
            }
            self.hits+=1;
            self.trace(depth,format!("CACHE HIT {n} {t} -> {}",KINDS[r.kind]));
            return Ok(r);
        }
        if self.cache.iter().any(|((m,_),e)|e.kind==4 && below(n,m)) {
            self.hits+=1;
            self.trace(depth,format!("CACHE HIT {n} {t} -> NXDOMAIN"));
            return Ok(Response::empty(4));
        }
        if t!="CNAME" {
            if let Some(records)=self.cached_records(&(n.into(),"CNAME".into())) {
                let mut r=Response::empty(1);
                r.answer=records;
                self.hits+=1;
                self.trace(depth,format!("CACHE HIT {n} {t} -> {}",r.text()));
                return Ok(r);
            }
        }
        let referral=self.cache.iter().filter(|((m,t),e)|t=="NS" && e.kind==0 && below(n,m)).max_by_key(|((m,_),_)|labels(m).len()).map(|((m,_),e)|(m.clone(),e.records.clone()));
        let (mut cut,mut servers)=if let Some((cut,records))=referral {
            self.hits+=1;
            self.trace(depth,format!("CACHE HIT {n} {t} -> REFERRAL {cut}"));
            (cut,Some(records.iter().map(|r|r.data.text()).collect()))
        } else {
            (".".into(),None)
        };
        loop {
            let mut r=self.query_servers(n,t,&cut,servers,depth,stack).ok_or_else(||format!("SERVFAIL no server for {cut}"))?;
            match r.kind {
                2=>{
                    self.positive(r.authority.clone());
                    let mut groups:BTreeMap<String,Vec<Record>>=BTreeMap::new();
                    for record in r.additional {
                        groups.entry(record.owner.clone()).or_default().push(record);
                    }
                    for records in groups.into_values() {
                        self.positive(records);
                    }
                    cut=r.cut;
                    servers=Some(r.authority.iter().map(|r|r.data.text()).collect());
                }
                0|1=>{
                    let seconds=self.positive(r.answer.clone());
                    for record in &mut r.answer {
                        record.ttl=seconds;
                    }
                    return Ok(r);
                }
                3|4=>{
                    let soa=&r.authority[0];
                    let minimum=if let Data::Soa(_,_,n)=&soa.data {
                        n[4]
                    } else {
                        unreachable!()
                    };
                    let seconds=soa.ttl.min(minimum).min(self.settings[2]);
                    self.cache.insert((n.into(),t.into()),Cache {
                        kind:r.kind,records:Vec::new(),expiry:self.clock+seconds
                    });
                    return Ok(r);
                }
                _=>unreachable!(),
            }
        }
    }
    fn resolve(&mut self,n:&str,t:&str,depth:usize,stack:&mut Vec<(String,String)>) -> (String,Vec<Record>) {
        stack.push((n.into(),t.into()));
        let mut chain=Vec::new();
        let mut seen=BTreeSet::from([n.to_string()]);
        let mut current=n.to_string();
        let result=loop {
            match self.lookup(&current,t,depth,stack) {
                Err(reason)=>break (reason,Vec::new()),
                Ok(r)=>match r.kind {
                    1=>{
                        let target=r.answer[0].data.text();
                        chain.extend(r.answer);
                        if seen.contains(&target) {
                            break ("SERVFAIL cname loop".into(),Vec::new());
                        }
                        if chain.len()==9 {
                            break ("SERVFAIL cname chain too long".into(),Vec::new());
                        }
                        seen.insert(target.clone());
                        current=target;
                    }
                    0=>{
                        chain.extend(r.answer);
                        break ("NOERROR".into(),chain);
                    }
                    _=>break (KINDS[r.kind].into(),chain),
                },
            }
        };
        stack.pop();
        let index=match result.0.as_str() {
            "NOERROR"=>0,"NODATA"=>1,"NXDOMAIN"=>2,_=>3
        };
        self.resolutions[index]+=1;
        result
    }
    fn output_resolution(&mut self,n:&str,t:&str) -> (String,Vec<Record>) {
        let result=self.resolve(n,t,0,&mut Vec::new());
        for r in &result.1 {
            self.out.push("answer ".to_string()+&r.text());
        }
        self.out.push("status ".to_string()+&result.0);
        result
    }
    fn host_addresses(&mut self,n:&str) -> Vec<String> {
        let mut out=Vec::new();
        for t in ["A","AAAA"] {
            let (status,answer)=self.resolve(n,t,0,&mut Vec::new());
            if status=="NOERROR" {
                out.extend(answer.iter().filter(|r|r.kind==t).map(|r|r.data.text()));
            }
        }
        out
    }
    fn command(&mut self,w:&[&str]) -> Result<(),String> {
        match w[0] {
            "RESOLVE"=>{
                let n=name(w[1],true,None)?;
                checked_type(w[2])?;
                self.out.push(format!("resolve {n} {}",w[2]));
                self.output_resolution(&n,w[2]);
            }
            "REVERSE"=>{
                let (a,n)=if w[1].contains(':') {
                    let a=ipv6(w[1]).ok_or_else(||format!("bad address {}",w[1]))?;
                    let digits=a.iter().map(|n|format!("{n:04x}")).collect::<String>();
                    (address6(&a),digits.chars().rev().map(|c|c.to_string()).collect::<Vec<_>>().join(".")+".ip6.arpa.")
                }
                else {
                    let a=checked_ip(w[1])?;
                    let s=address(a);
                    (s.clone(),s.split('.').rev().collect::<Vec<_>>().join(".")+".in-addr.arpa.")
                };
                self.out.push(format!("reverse {a} {n}"));
                self.output_resolution(&n,"PTR");
            }
            "MX"=>{
                let n=name(w[1],true,None)?;
                self.out.push(format!("mx {n}"));
                let (status,answer)=self.output_resolution(&n,"MX");
                if status=="NOERROR" {
                    for r in answer {
                        if let Data::Mx(p,host)=r.data {
                            if host=="." {
                                self.out.push(format!("exchange {p} . -> null"));
                            } else {
                                let addresses=self.host_addresses(&host);
                                self.out.push(format!("exchange {p} {host} -> {}",if addresses.is_empty() {
                                    "no address".into()
                                } else {
                                    addresses.join(" ")
                                }));
                            }
                        }
                    }
                }
                else if status=="NODATA" {
                    let host=answer.iter().rev().find(|r|r.kind=="CNAME").map_or(n.clone(),|r|r.data.text());
                    let addresses=self.host_addresses(&host);
                    self.out.push(format!("implicit {host} -> {}",if addresses.is_empty() {
                        "no address".into()
                    } else {
                        addresses.join(" ")
                    }));
                }
            }
            "QUERY"=>{
                let a=checked_ip(w[1])?;
                let n=name(w[2],true,None)?;
                checked_type(w[3])?;
                let r=self.ask(a,&n,w[3],".");
                self.out.push(format!("query {} {n} {} -> {}",address(a),w[3],r.text()));
                let sections=match r.kind {
                    0|1=>vec![("answer",r.answer)],2=>vec![("authority",r.authority),("additional",r.additional)],3|4=>vec![("authority",r.authority)],_=>Vec::new()
                };
                for (section,records) in sections {
                    for record in records {
                        self.out.push(format!("{section} {}",record.text()));
                    }
                }
            }
            "DUMP"=>{
                let a=checked_ip(w[1])?;
                let n=name(w[2],false,None)?;
                if self.down.contains(&a) || !self.zones.iter().any(|z|z.server==a) {
                    self.out.push(format!("dump {} {n} -> TIMEOUT",address(a)));
                } else if let Some(z)=self.zones.iter().find(|z|z.server==a && z.origin==n) {
                    let mut records=z.records.clone();
                    records.sort_by(record_order);
                    self.out.push(format!("dump {} {n} records={}",address(a),records.len()));
                    for r in records {
                        self.out.push("  ".to_string()+&r.text());
                    }
                } else {
                    self.out.push(format!("dump {} {n} -> REFUSED",address(a)));
                }
            }
            "UP"|"DOWN"=>{
                let a=checked_ip(w[1])?;
                if w[0]=="DOWN" {
                    if self.down.contains(&a) {
                        return Err(format!("server {} already down",w[1]));
                    }
                    self.down.insert(a);
                } else if !self.down.remove(&a) {
                    return Err(format!("server {} not down",w[1]));
                }
                self.out.push(format!("{} {}",w[0].to_ascii_lowercase(),address(a)));
            }
            "SET"=>{
                let i=["MINTTL","MAXTTL","NEGTTL"].iter().position(|&s|s==w[1]).ok_or_else(||format!("bad setting {}",w[1]))?;
                let n=integer(w[2]).filter(|&n|(1..=604800).contains(&n)).ok_or_else(||format!("bad value {}",w[2]))?;
                let mut settings=self.settings;
                settings[i]=n;
                if settings[0]>settings[1] {
                    return Err("minttl above maxttl".into());
                }
                self.settings=settings;
                self.out.push(format!("set {}={n}",w[1]));
            }
            "TIME"=>{
                let n=integer(w[1]).filter(|&n|(1..=1000000).contains(&n)).ok_or_else(||format!("bad time {}",w[1]))?;
                self.clock+=n;
                let old=self.cache.len();
                let clock=self.clock;
                self.cache.retain(|_,e|e.expiry>clock);
                self.out.push(format!("time now={} expired={}",self.clock,old-self.cache.len()));
            }
            "CACHE"|"FLUSH"=>{
                let selected=if w.len()==2 {
                    Some(name(w[1],false,None)?)
                } else {
                    None
                };
                let mut keys:Vec<_>=self.cache.keys().filter(|(n,_)|selected.as_ref().is_none_or(|parent|below(n,parent))).cloned().collect();
                keys.sort_by(|(a,t),(b,u)|name_order(a,b).then(TYPES.iter().position(|x|x==t).cmp(&TYPES.iter().position(|x|x==u))));
                if w[0]=="FLUSH" {
                    self.out.push(format!("flush removed={}",keys.len()));
                    for key in keys {
                        self.cache.remove(&key);
                    }
                }
                else {
                    self.out.push(format!("cache entries={}",keys.len()));
                    for key in keys {
                        let e=&self.cache[&key];
                        if e.kind==0 {
                            for r in self.cached_records(&key).unwrap() {
                                self.out.push("  ".to_string()+&r.text());
                            }
                        } else {
                            self.out.push(format!("  {} {} {} {}",key.0,e.expiry-self.clock,key.1,KINDS[e.kind]));
                        }
                    }
                }
            }
            _=>{
                let total:usize=self.queries.values().map(|counts|counts.iter().sum::<usize>()).sum();
                self.out.push(format!("stats queries={total} hits={}",self.hits));
                for (a,c) in &self.queries {
                    self.out.push(format!("  {} sent={} answer={} cname={} referral={} nodata={} nxdomain={} lame={} timeout={}",address(*a),c.iter().sum::<usize>(),c[0],c[1],c[2],c[3],c[4],c[5],c[6]));
                }
                let c=self.resolutions;
                self.out.push(format!("resolutions noerror={} nodata={} nxdomain={} servfail={}",c[0],c[1],c[2],c[3]));
            }
        }
        Ok(())
    }
}
fn main() {
    let mut input=String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut resolver=Resolver::new();
    let mut zones=true;
    for (i,line) in input.lines().enumerate() {
        if line=="END" {
            break;
        }
        if line=="END ZONES" {
            resolver.finish_zones();
            zones=false;
            continue;
        }
        let words:Vec<_>=line.split(' ').collect();
        let result=if zones {
            resolver.zone_line(&words,i+1)
        } else {
            resolver.command(&words)
        };
        if let Err(reason)=result {
            resolver.out.push(format!("error line {}: {reason}",i+1));
        }
    }
    for line in resolver.out {
        println!("{line}");
    }
}
