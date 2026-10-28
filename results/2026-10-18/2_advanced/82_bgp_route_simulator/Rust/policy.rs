use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use crate::topology::{Asn,Prefix,Link};
pub type Communities=BTreeSet<(u32,u32)>;
pub fn community(s:&str)->(u32,u32){
    if s=="NO_EXPORT"{
        (65535,65281)
    }else{
        let(a,b)=s.split_once(':').unwrap();
        (a.parse().unwrap(),b.parse().unwrap())
    }
}
pub fn community_text(c:&Communities)->String{
    if c.is_empty(){
        "-".into()
    }else{
        c.iter().map(|&(a,b)|if(a,b)==(65535,65281){
            "NO_EXPORT".into()
        }else{
            format!("{}:{}",a,b)
        }).collect::<Vec<_>>().join(",")
    }
}
#[derive(Clone)] pub enum Condition {
    Prefix(String),
    Contains(Asn),
    Origin(Asn),
    Length(usize,usize),
    Community((u32,u32))
}
#[derive(Clone)] pub enum Action {
    Deny,
    Allow,
    Local(usize),
    Med(usize),
    Prepend(usize),
    Add((u32,u32)),
    Remove((u32,u32))
}
#[derive(Clone)] pub struct Rule {
    pub name:String,
    pub on:bool,
    pub owner:Asn,
    pub import:bool,
    pub target:String,
    pub conditions:Vec<Condition>,
    pub actions:Vec<Action>,
    pub hits:usize
}
pub struct Entry {
    permit:bool,
    prefix:Prefix,
    low:u8,
    high:u8
}
pub struct Policy {
    pub lists:BTreeMap<String,Vec<Entry>>,
    pub rules:Vec<Rule>
}
impl Policy {
    pub fn read()->Self{
        let mut p=Self{
            lists:BTreeMap::new(),
            rules:Vec::new()
        };
        for line in fs::read_to_string("input/policies.txt").unwrap().lines(){
            let a:Vec<_>=line.split(' ').collect();
            if a[0]=="PLIST"{
                let prefix=Prefix::parse(a[3]);
                let(mut low,mut high)=(prefix.length,prefix.length);
                let mut i=4;
                while i<a.len(){
                    if a[i]=="GE"{
                        low=a[i+1].parse().unwrap();
                        high=32;
                    }else{
                        high=a[i+1].parse().unwrap();
                    }
                    i+=2;
                }
                p.lists.entry(a[1].into()).or_default().push(Entry{
                    permit:a[2]=="PERMIT",
                    prefix,
                    low,
                    high
                });
            }else{
                let mut r=Rule{
                    name:a[1].into(),
                    on:a[2]=="ON",
                    owner:a[3].parse().unwrap(),
                    import:a[4]=="IMPORT",
                    target:a[5].into(),
                    conditions:Vec::new(),
                    actions:Vec::new(),
                    hits:0
                };
                let mut i=6;
                while a[i]!="THEN"{
                    r.conditions.push(match a[i]{
                        "PREFIX"=>Condition::Prefix(a[i+1].into()),"CONTAINS"=>Condition::Contains(a[i+1].parse().unwrap()),"ORIGINAS"=>Condition::Origin(a[i+1].parse().unwrap()),"LENGTH"=>{
                            let(x,y)=a[i+1].split_once('-').unwrap();
                            Condition::Length(x.parse().unwrap(),y.parse().unwrap())
                        },_=>Condition::Community(community(a[i+1]))
                    });
                    i+=2;
                }
                i+=1;
                while i<a.len(){
                    let action=match a[i]{
                        "DENY"=>Action::Deny,"ALLOW"=>Action::Allow,"LOCALPREF"=>Action::Local(a[i+1].parse().unwrap()),"MED"=>Action::Med(a[i+1].parse().unwrap()),"PREPEND"=>Action::Prepend(a[i+1].parse().unwrap()),"ADD"=>Action::Add(community(a[i+1])),_=>Action::Remove(community(a[i+1]))
                    };
                    i+=if matches!(action,Action::Deny|Action::Allow){
                        1
                    }else{
                        2
                    };
                    r.actions.push(action);
                }
                p.rules.push(r);
            }
        }
        p
    }
    pub fn permitted(&self,name:&str,p:Prefix)->bool{
        self.lists[name].iter().find(|e|e.low<=p.length&&p.length<=e.high&&e.prefix.contains(p.address)).map_or(false,|e|e.permit)
    }
    pub fn applied(&self,import:bool,x:Asn,link:&Link,p:Prefix,path:&[Asn],comm:&Communities)->Option<usize>{
        self.rules.iter().position(|r|r.on&&r.owner==x&&r.import==import&&(r.target=="*"||r.target==link.name||r.target==link.other(x).to_string())&&r.conditions.iter().all(|c|match c{
            Condition::Prefix(n)=>self.permitted(n,p),Condition::Contains(a)=>path.contains(a),Condition::Origin(a)=>path.last().copied().unwrap_or(x)==*a,Condition::Length(lo,hi)=>*lo<=path.len()&&path.len()<=*hi,Condition::Community(c)=>comm.contains(c)
        }))
    }
    pub fn edit(&self,id:usize,c:&Communities)->Communities{
        let mut c=c.clone();
        for a in &self.rules[id].actions{
            match a{
                Action::Add(v)=>{
                    c.insert(*v);
                },Action::Remove(v)=>{
                    c.remove(v);
                },_=>()
            }
        }
        c
    }
}
