use std::collections::BTreeMap;
use std::fs;
use crate::decision::Attribute;
use crate::topology::{Asn,Prefix,address};
#[derive(Clone,Debug)] pub struct Message {
    pub serial:usize,
    pub sender:Asn,
    pub receiver:Asn,
    pub link:usize,
    pub prefix:Prefix,
    pub content:Option<Attribute>,
    pub arrival:i64
}
pub struct Queue {
    pub messages:BTreeMap<(i64,Asn,Asn,usize),Message>,
    pub serial:usize
}
impl Queue {
    pub fn new()->Self{
        Self{
            messages:BTreeMap::new(),
            serial:0
        }
    }
    pub fn send(&mut self,time:i64,delay:i64,sender:Asn,receiver:Asn,link:usize,prefix:Prefix,content:Option<Attribute>)->Message{
        self.serial+=1;
        let m=Message{
            serial:self.serial,
            sender,
            receiver,
            link,
            prefix,
            content,
            arrival:time+delay
        };
        self.messages.insert((m.arrival,receiver,sender,m.serial),m.clone());
        m
    }
    pub fn deliveries(&mut self,t:i64)->Vec<Message>{
        let keys:Vec<_>=self.messages.keys().take_while(|k|k.0==t).copied().collect();
        keys.into_iter().map(|k|self.messages.remove(&k).unwrap()).collect()
    }
    pub fn remove(&mut self,link:usize)->Vec<Message>{
        let keys:Vec<_>=self.messages.iter().filter(|(_,m)|m.link==link).map(|(k,_)|*k).collect();
        keys.into_iter().map(|k|self.messages.remove(&k).unwrap()).collect()
    }
    pub fn state(&self,t:i64)->Vec<(i64,Asn,Asn,usize,Prefix,Option<Attribute>)>{
        self.messages.values().map(|m|(m.arrival-t,m.receiver,m.sender,m.link,m.prefix,m.content.clone())).collect()
    }
}
#[derive(Clone)] pub struct Event{
    pub time:i64,
    pub text:String,
    pub fields:Vec<String>,
    pub kind:String
}
pub fn events()->Vec<Event>{
    let mut all=vec![Event{
        time:0,text:"INITIAL".into(),fields:vec!["INITIAL".into()],kind:"INITIAL".into()
    }];
    for line in fs::read_to_string("input/events.txt").unwrap().lines(){
        let(t,text)=line.split_once(' ').unwrap();
        let fields:Vec<String>=text.split(' ').map(str::to_string).collect();
        let kind=if fields[0]=="LINK"||fields[0]=="POLICY"{
            fields[..2].join("_")
        }else{
            fields[0].clone()
        };
        all.push(Event{
            time:t.parse().unwrap(),
            text:text.into(),
            fields,
            kind
        });
    }
    all
}
pub struct Params{
    pub defaults:[usize;3],
    pub stepcap:usize,
    pub traces:Vec<(Asn,String,u32)>
}
pub fn params()->Params{
    let text=fs::read_to_string("input/params.txt").unwrap();
    let a:Vec<_>=text.lines().collect();
    let d:Vec<usize>=a[0].split(' ').skip(1).map(|v|v.parse().unwrap()).collect();
    Params{
        defaults:[d[0],d[1],d[2]],
        stepcap:a[1].split(' ').nth(1).unwrap().parse().unwrap(),
        traces:a[2..].iter().map(|s|{
            let v:Vec<_>=s.split(' ').collect();
            (v[1].parse().unwrap(),v[2].into(),address(v[2]))
        }).collect()
    }
}
